#!/usr/bin/perl -w

=head1 NAME

Alien::Package::Deb - an object that represents a deb package

=cut

package Alien::Package::Deb;
use strict;
use base qw(Alien::Package);

=head1 DESCRIPTION

This is an object class that represents a deb package. It is derived from
Alien::Package.

=head1 FIELDS

=over 4

=item have_dpkg_deb

Set to a true value if dpkg-deb is available. 

=item dirtrans

After the build stage, set to a hash reference of the directories we moved
files from and to, so these moves can be reverted in the cleantree stage.

=back

=head1 METHODS

=over 4

=item init

Sets have_dpkg_deb if dpkg-deb is in the path. I prefer to use dpkg-deb,
if it is available since it is a lot more future-proof.

=cut

sub init {
	my $this=shift;
	$this->SUPER::init(@_);

	$this->have_dpkg_deb('');
	foreach (split(/:/,$ENV{PATH})) {
		if (-x "$_/dpkg-deb") {
			$this->have_dpkg_deb(1);
			last;
		}
	}
}

=item checkfile

Detect deb files by their extention.

=cut

sub checkfile {
	my $this=shift;
	my $file=shift;

	return $file =~ m/.*\.deb$/;
}

=item install

Install a deb with dpkg. Pass in the filename of the deb to install.

=cut

sub install {
	my $this=shift;
	my $deb=shift;

	system("dpkg", "--no-force-overwrite", "-i", $deb) == 0
		or die "Unable to install";
}

=item getcontrolfile

Helper method. Pass it the name of a control file, and it will pull it out
of the deb and return it.

=cut

sub getcontrolfile {
	my $this=shift;
	my $controlfile=shift;
	my $file=$this->filename;
	
	if ($this->have_dpkg_deb) {
		return `dpkg-deb --info $file $controlfile 2>/dev/null`;
	}
	else {
		# Have to handle old debs without a leading ./ and
		# new ones with it.
		return `ar p $file control.tar.gz | gzip -dc | tar Oxf - $controlfile ./$controlfile 2>/dev/null`
	}
}

=item scan

Implement the scan method to read a deb file.

=cut

sub scan {
	my $this=shift;
	$this->SUPER::scan(@_);
	my $file=$this->filename;

	my @control=$this->getcontrolfile('control');

	# Parse control file and extract fields. Use a translation table
	# to map between the debian names and the internal field names,
	# which more closely resemble those used by rpm (for historical
	# reasons; TODO: change to deb style names).
	my $description='';
	my $field;
	my %fieldtrans=(
		Package => 'name',
		Version => 'version',
		Architecture => 'arch',
		Maintainer => 'maintainer',
		Depends => 'depends',
		Section => 'group',
		Description => 'summary',
	);
	for (my $i=0; $i <= $#control; $i++) {
		$_ = $control[$i];
		chomp;
		if (/^(\w.*?):\s+(.*)/) {
			$field=$1;
			if (exists $fieldtrans{$field}) {
				$field=$fieldtrans{$field};
				$this->$field($2);
			}
		}
		elsif (/^ / && $field eq 'summary') {
			# Handle extended description.
			s/^ //g;
			$_="" if $_ eq ".";
			$description.="$_\n";
		}
	}
	$this->description($description);

	$this->copyright("see /usr/share/doc/".$this->name."/copyright");
	$this->group("unknown") if ! $this->group;
	$this->distribution("Debian");
	$this->origformat("deb");
	$this->binary_info(scalar $this->getcontrolfile('control'));

	# Read in the list of conffiles, if any.
	my @conffiles;
	@conffiles=map { chomp; $_ } $this->getcontrolfile('conffiles');
	$this->conffiles(\@conffiles);

	# Read in the list of all files.
	# Note that tar doesn't supply a leading `/', so we have to add that.
	my @filelist;
	if ($this->have_dpkg_deb) {
		@filelist=map { chomp; s:\./::; "/$_" }
			  `dpkg-deb --fsys-tarfile $file | tar tf -`;
	}
	else {
		@filelist=map { chomp; s:\./::; "/$_" }
			  `ar p $file data.tar.gz | gzip -dc | tar tf -`;
	}
	$this->filelist(\@filelist);

	# Read in the scripts, if any.
	foreach my $field (qw{postinst postrm preinst prerm}) {
		$this->$field(scalar $this->getcontrolfile($field));
	}

	return 1;
}

=item unpack

Implment the unpack method to unpack a deb file.

=cut

sub unpack {
	my $this=shift;
	$this->SUPER::unpack(@_);
	my $file=$this->filename;

	if ($this->have_dpkg_deb) {
		system("dpkg-deb", "-x", $file, $this->unpacked_tree) == 0
			or die "Unpacking of `$file' failed: $!";
	}
	else {
		system("ar p $file data.tar.gz | gzip -dc | (cd ".$this->unpacked_tree."; tar xpf -)") == 0
			or die "Unpacking of `$file' failed: $!";
	}

	return 1;
}

=item getpatch

This method tries to find a patch file to use in the prep stage. If it
finds one, it returns it.  Pass in a list of directories to search for
patches in.

=cut

sub getpatch {
	my $this=shift;

	my @patches;
	foreach my $dir (@_) {
		push @patches, glob("$dir/".$this->name."_".$this->version."-".$this->release."*.diff.gz");
	}
	unless (@patches) {
		# Try not matching the revision, see if that helps.
		foreach my $dir (@_) {
			push @patches,glob("$dir/".$this->name."_".$this->version."*.diff.gz");
		}
		unless (@patches) {
			# Fallback to anything that matches the name.
			foreach my $dir (@_) {
				push @patches,glob("$dir/".$this->name."_*.diff.gz");
			}
		}
	}

	# If we ended up with multiple matches, return the first.
	return $patches[0];
}

=item prep

Adds a populated debian directory the unpacked package tree, making it
ready for building. This can either be done automatically, or via a patch
file. 

=cut

sub prep {
	my $this=shift;
	my $dir=$this->unpacked_tree || die "The package must be unpacked first!";

	mkdir "$dir/debian", 0755 ||
		die "mkdir $dir/debian failed: $!";
	
	# Use a patch file to debianize?
	if (defined $this->patchfile) {
		# The -f passed to zcat makes it pass uncompressed files
		# through without error.
		system("zcat -f ".$this->patchfile." | (cd $dir; patch -p1)") == 0
			or die "patch error: $!";
		# Look for .rej files.
		die "patch failed with .rej files; giving up"
			if `find $dir -name "*.rej"`;
		system('find', '.', '-name', '*.orig', '-exec', 'rm', '{}', ';');
		chmod 0755, "$dir/debian/rules";
		return;
	}

	# Automatic debianization.
	# Changelog file.
	open (OUT, ">$dir/debian/changelog") || die "$dir/debian/changelog: $!";
	print OUT $this->name." (".$this->version."-".$this->release.") experimental; urgency=low\n";
	print OUT "\n";
	print OUT "  * Converted from .".$this->origformat." format to .deb\n";
	print OUT "\n";
	print OUT " -- ".$this->username." <".$this->email.">  ".$this->date."\n";
	print OUT "\n";
	print OUT $this->changelogtext."\n";
	close OUT;

	# Control file.
	open (OUT, ">$dir/debian/control") || die "$dir/debian/control: $!";
	print OUT "Source: ".$this->name."\n";
	print OUT "Section: alien\n";
	print OUT "Priority: extra\n";
	print OUT "Maintainer: ".$this->username." <".$this->email.">\n";
	print OUT "\n";
	print OUT "Package: ".$this->name."\n";
	print OUT "Architecture: ".$this->arch."\n";
	print OUT "Depends: \${shlibs:Depends}\n";
	print OUT "Description: ".$this->summary."\n";
	print OUT $this->description."\n";
	print OUT " .\n";
	print OUT " (Converted from a .".$this->origformat." package by alien.)\n";
	close OUT;

	# Copyright file.
	open (OUT, ">$dir/debian/copyright") || die "$dir/debian/copyright: $!";
	print OUT "This package was debianized by the alien program by converting\n";
	print OUT "a binary .".$this->origformat." package on ".$this->date."\n";
	print OUT "\n";
	print OUT "Copyright: ".$this->copyright."\n";
	print OUT "\n";
	print OUT "Information from the binary package:\n";
	print OUT $this->binary_info."\n";
	close OUT;

	# Conffiles, if any.
	my @conffiles=@{$this->conffiles};
	if (@conffiles) {
		open (OUT, ">$dir/debian/conffiles") || die "$dir/debian/conffiles: $!";
		print OUT join("\n", @conffiles)."\n";
		close OUT;
	}

	# A minimal rules file.
	open (OUT, ">$dir/debian/rules") || die "$dir/debian/rules: $!";
	print OUT << 'EOF';
#!/usr/bin/make -f
# debian/rules for alien

# Uncomment this to turn on verbose mode.
#export DH_VERBOSE=1

# Use v3 compatability mode, so ldconfig gets added to maint scripts.
export DH_COMPAT=3

PACKAGE=$(shell dh_listpackages)

build:
	dh_testdir

clean:
	dh_testdir
	dh_testroot
	dh_clean

binary-indep: build

binary-arch: build
	dh_testdir
	dh_testroot
	dh_clean -k
	dh_installdirs
	cp -a `ls -1 |grep -v debian` debian/$(PACKAGE)
#
# If you need to move files around in debian/$(PACKAGE) or do some
# binary patching, do it here
#
	dh_installdocs
	dh_installchangelogs
# This has been known to break on some wacky binaries.
#	dh_strip
	dh_compress
# This is too paramoid to be generally useful to alien.
#	dh_fixperms
	dh_makeshlibs
	dh_installdeb
	-dh_shlibdeps
	dh_gencontrol
	dh_md5sums
	dh_builddeb

binary: binary-indep binary-arch
.PHONY: build clean binary-indep binary-arch binary
EOF
	close OUT;
	chmod 0755,"$dir/debian/rules";

	# Save any scripts.
	foreach my $script (qw{postinst postrm preinst prerm}) {
		my $data=$this->$script();
		next unless defined $data;
		next if $data =~ m/^\s*$/;
		open (OUT,">$dir/debian/$script") ||
			die "$dir/debian/$script: $!";
		print OUT $data;
		close OUT;
	}

	my %dirtrans=( # Note: no trailing slahshes on these directory names!
		# Move files to FHS-compliant locations, if possible.
		'/usr/man'	=> '/usr/share/man',
		'/usr/info'	=> '/usr/share/info',
		'/usr/doc'	=> '/usr/share/doc',
	);
	foreach my $olddir (keys %dirtrans) {
		if (-d "$dir/$olddir" && ! -e "$dir/$dirtrans{$olddir}") {
			# Ignore failure..
			my ($dirbase)=$dirtrans{$olddir}=~/(.*)\//;
			system("install", "-d", "$dir/$dirbase");
			system("mv", "$dir/$olddir", "$dir/$dirtrans{$olddir}");
			if (-d "$dir/$olddir") {
				system("rmdir", "-p", "$dir/$olddir");
			}
		}
		else {
			delete $dirtrans{$olddir};
		}
	}
	$this->dirtrans(\%dirtrans); # store for cleantree
}

=item build

Build a deb.

=cut

sub build {
	my $this=shift;

	chdir $this->unpacked_tree;
	my $log=`debian/rules binary`;
	if ($?) {
		die "Package build failed. Here's the log:\n", $log;
	}
	chdir "..";

	return $this->name."_".$this->version."-".$this->release."_".$this->arch.".deb";
}

=item cleantree

Delete the entire debian/ directory.

=cut

sub cleantree {
        my $this=shift;
	my $dir=$this->unpacked_tree || die "The package must be unpacked first!";

	my %dirtrans=%{$this->dirtrans};
	foreach my $olddir (keys %dirtrans) {
		if (! -e "$dir/$olddir" && -d "$dir/$dirtrans{$olddir}") {
			# Ignore failure.. (should I?)
			my ($dirbase)=$dir=~/(.*)\//;
			system("install", "-d", "$dir/$dirbase");
			system("mv", "$dir/$dirtrans{$olddir}", "$dir/$olddir");
			if (-d "$dir/$dirtrans{$olddir}") {
				system("rmdir", "-p", "$dir/$dirtrans{$olddir}");
			}
		}
	}
	
	system("rm", "-rf", "$dir/debian");
}

=item package

Set/get package name. 

Always returns the packge name in lowercase with all invalid characters
returned. The name is however, stored unchanged.

=cut

sub name {
	my $this=shift;
	
	# set
	$this->{name} = shift if @_;
	return unless defined wantarray; # optimization
	
	# get
	$_=lc($this->{name});
	tr/_/-/;
	s/[^a-z0-9-\.\+]//g;
	return $_;
}

=item version

Set/get package version.

When the version is set, it will be stripped of any epoch. If there is a
release, the release will be stripped away and used to set the release
field as a side effect. Otherwise, the release will be set to 1.

More sanitization of the version is done when the field is retrieved, to
make sure it is a valid debian version field.

=cut

sub version {
	my $this=shift;

	# set
	if (@_) {
		my $version=shift;
		if ($version =~ /(.+)-(.+)/) {
                	$version=$1;
	                $this->release($2);
	        }
	        else {
	                $this->release(1);
		}
        	# Kill epochs.
		$version=~s/^\d+://;
		
		$this->{version}=$version;
        }
	
	# get
	return unless defined wantarray; # optimization
	$_=$this->{version};
	# Make sure the version contains digets.
	unless (/[0-9]/) {
		# Drat. Well, add some. dpkg-deb won't work
		# # on a version w/o numbers!
		return $_."0";
	}
	return $_;
}

=item release

Set/get package release.

Always returns a sanitized release version. The release is however, stored
unchanged.

=cut

sub release {
	my $this=shift;

	# set
	$this->{release} = shift if @_;

	# get
	return unless defined wantarray; # optimization
	$_=$this->{release};
	# Make sure the release contains digets.
	return $_."-1" unless /[0-9]/;
	return $_;
}

=item description

Set/get description

Although the description is stored internally unchanged, this will always
return a sanitized form of it that is compliant with Debian standards.

=cut

sub description {
	my $this=shift;

	# set
	$this->{description} = shift if @_;

	# get
	return unless defined wantarray; # optimization
	my $ret='';
	foreach (split /\n/,$this->{description}) {
		s/\t/        /g; # change tabs to spaces
		s/\s+$//g; # remove trailing whitespace
		$_="." if $_ eq ''; # empty lines become dots
		$ret.=" $_\n";
	}
	chomp $ret;
	return $ret;
}

=item date

Returns the date, in rfc822 format.

=cut

sub date {
	my $this=shift;

	my $date=`822-date`;
	chomp $date;
	if (!$date) {
		die "822-date did not return a valid result. You probably need to install the dpkg-dev debian package";
	}

	return $date;
}

=item email

Returns an email address for the current user.

=cut

sub email {
	my $this=shift;

	return $ENV{EMAIL} if exists $ENV{EMAIL};

	my $login = getlogin || (getpwuid($<))[0] || $ENV{USER};
	my $mailname='';
	if (open (MAILNAME,"</etc/mailname")) {
		$mailname=<MAILNAME>;
		if (defined $mailname) {
			chomp $mailname;
		}
		close MAILNAME;
	}
	if (!$mailname) {
		$mailname=`hostname -f`;
		chomp $mailname;
	}
	return "$login\@$mailname";
}

=item username

Returns the user name of the real uid.

=cut

sub username {
	my $this=shift;

	my $username;
	my $login = getlogin || (getpwuid($<))[0] || $ENV{USER};
	(undef, undef, undef, undef, undef, undef, $username) = getpwnam($login);

	# Remove GECOS fields from username.
	$username=~s/,.*//g;

	# The ultimate fallback.
	if ($username eq '') {
		$username=$login;
	}

	return $username;
}

=head1 AUTHOR

Joey Hess <joey@kitenet.net>

=cut

1
