#!/usr/bin/perl -w

=head1 NAME

Alien::Package::Deb - an object that represents a deb package

=cut

package Alien::Package::Deb;
use strict;
use Alien::Package; # perlbug
use base qw(Alien::Package);

=head1 DESCRIPTION

This is an object class that represents a deb package. It is derived from
Alien::Package.

=head1 FIELDS

=over 4

=item have_dpkg_deb

Set to a true value if dpkg-deb is available. 

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

=item install

Install a deb with dpkg.

=cut

sub install {
	my $this=shift;

	system("dpkg --no-force-overwrite -i ".$this->filename) &&
		die "Unable to install: $!";
}

=item read_file

Implement the read_file method to read a deb file.

=cut

sub read_file {
	my $this=shift;
	$this->SUPER::read_file(@_);
	my $file=$this->filename;

	# Extract the control file from the deb file.
	my @control;
	if ($this->have_dpkg_deb) {
		@control = `dpkg-deb --info $file control`;
	}
	else {
		# It can have one of two names, depending on the tar
		# version the .deb was built from.
		@control = `ar p $file control.tar.gz | tar Oxzf - control [./]control`;
	}

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
	$this->binary_info(scalar `dpkg --info $file`);

	# Read in the list of conffiles, if any.
	my @conffiles;
	if ($this->have_dpkg_deb) {
		@conffiles=map { chomp; $_ }
			   `dpkg-deb --info $file conffiles 2>/dev/null`;
	}
	else {
		@conffiles=map { chomp; $_ }
			   `ar p $file control.tar.gz | tar Oxzf - conffiles 2>/dev/null`;
	}
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
			  `ar p $file data.tar.gz | tar tzf -`;
	}
	$this->filelist(\@filelist);

	# Read in the scripts, if any.
	foreach my $field (qw{postinst postrm preinst prerm}) {
		if ($this->have_dpkg_deb) {
			$this->$field(scalar `dpkg-deb --info $file $field 2>/dev/null`);
		}
		else {
			$this->$field(scalar `ar p $file control.tar.gz | tar Oxzf - $field 2>/dev/null`);
		}
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
		system("dpkg-deb -x $file ".$this->unpacked_tree) &&
			die "Unpacking of `$file' failed: $!";
	}
	else {
		system ("ar p $file data.tar.gz | (cd ".$this->unpacked_tree."; tar zxpf -)") &&
			die "Unpacking of `$file' failed: $!";
	}

	return 1;
}

=item prep

Adds a populated debian directory the unpacked package tree, making it
ready for building. This can either be done automatically, or via a patch
file. 

=cut

sub prep {
	my $this=shift;
	my $dir=$this->unpacked_tree;

	mkdir "$dir/debian", 0755 ||
		die "mkdir $dir/debian failed: $!";
	
	# Use a patch file to debianize?
	if (defined $this->patchfile) {
		# The -f passed to zcat makes it pass uncompressed files
		# through without error.
		system("zcat -f ".$this->patchfile." | (cd $dir; patch -p1)") ||
			die "patch error: $!";
		# Look for .rej files.
		die "patch failed with .rej files; giving up"
			if `find $dir -name "*.rej"`;
		system('find . -name \'*.orig\' -exec rm {} \\;');
		chmod 0755,"$dir/debian/rules";
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
	print OUT ".\n"
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
	print OUT <<EOF;
#!/usr/bin/make -f
# debian/rules for alien

# Uncomment this to turn on verbose mode.
#export DH_VERBOSE=1

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
	cp -a `ls |grep -v debian` debian/tmp
#
# If you need to move files around in debian/tmp or do some
# binary patching ... Insert it here
#
	dh_installdocs
	dh_installchangelogs
#	dh_strip
	dh_compress
#	dh_fixperms
	dh_suidregister
	dh_installdeb
	-dh_shlibdeps
	dh_gencontrol
	dh_makeshlibs
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
	open (MAILNAME,"</etc/mailname");
	my $mailname=<MAILNAME>;
	chomp $mailname;
	close MAILNAME;
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
	if (!$username) {
		$username=$login;
	}
}

=head1 AUTHOR

Joey Hess <joey@kitenet.net>

=cut

1
