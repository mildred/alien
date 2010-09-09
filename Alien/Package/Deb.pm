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

=item fixperms

If this is set to true, the generated debian/rules will run dh_fixperms.

=back

=head1 METHODS

=over 4

=item init

Sets have_dpkg_deb if dpkg-deb is in the path. I prefer to use dpkg-deb,
if it is available since it is a lot more future-proof.

=cut

sub _inpath {
	my $this=shift;
	my $program=shift;

	foreach (split(/:/,$ENV{PATH})) {
		if (-x "$_/$program") {
			return 1;
		}
	}
	return '';
}

sub init {
	my $this=shift;
	$this->SUPER::init(@_);

	$this->have_dpkg_deb($this->_inpath('dpkg-deb'));
}

=item checkfile

Detect deb files by their extention.

=cut

sub checkfile {
	my $this=shift;
	my $file=shift;

	return $file =~ m/.*\.u?deb$/;
}

=item install

Install a deb with dpkg. Pass in the filename of the deb to install.

=cut

sub install {
	my $this=shift;
	my $deb=shift;

	my $v=$Alien::Package::verbose;
	$Alien::Package::verbose=2;
	$this->do("dpkg", "--no-force-overwrite", "-i", $deb)
		or die "Unable to install";
	$Alien::Package::verbose=$v;
}

=item test

Test a deb with lintian. Pass in the filename of the deb to test.

=cut

sub test {
	my $this=shift;
	my $deb=shift;

	if ($this->_inpath("lintian")) {
		# Ignore some lintian warnings that don't matter for
		# aliened packages.
		return map { s/\n//; $_ }
		       grep {
		       		! /unknown-section alien/
		       } $this->runpipe(1, "lintian $deb");
	}
	else {
		return "lintian not available, so not testing";
	}
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
		return $this->runpipe(1, "dpkg-deb --info $file $controlfile 2>/dev/null");
	}
	else {
		# Solaris tar doesn't support O
		sub tar_out {
			my $file = shift;

			return "(mkdir /tmp/tar_out.$$ &&".
				" cd /tmp/tar_out.$$ &&".
				" tar xf - ./$file &&".
				" cat $file; cd /; rm -rf /tmp/tar_out.$$)";
		}
		my $getcontrol = "ar -p $file control.tar.gz | gzip -dc | ".tar_out($controlfile)." 2>/dev/null";
		return $this->runpipe(1, $getcontrol);
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
	die "Control file couldn't be read!"
		if @control == 0;
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
		Section => 'group',
		Description => 'summary',
	);
	for (my $i=0; $i <= $#control; $i++) {
		$_ = $control[$i];
		chomp;
		if (/^(\w.*?):\s+(.*)/) {
			# Really old debs might have oddly capitalized
			# field names.
			$field=ucfirst(lc($1));
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
	# Note that tar doesn't supply a leading '/', so we have to add that.
	my @filelist;
	if ($this->have_dpkg_deb) {
		@filelist=map { chomp; s:\./::; "/$_" }
			  $this->runpipe(0, "dpkg-deb --fsys-tarfile $file | tar tf -");
	}
	else {
		@filelist=map { chomp; s:\./::; "/$_" }
			  $this->runpipe(0, "ar -p $file data.tar.gz | gzip -dc | tar tf -");
	}
	$this->filelist(\@filelist);

	# Read in the scripts, if any.
	foreach my $field (qw{postinst postrm preinst prerm}) {
		$this->$field(scalar $this->getcontrolfile($field));
	}

	return 1;
}

=item unpack

Implement the unpack method to unpack a deb file.

=cut

sub unpack {
	my $this=shift;
	$this->SUPER::unpack(@_);
	my $file=$this->filename;

	if ($this->have_dpkg_deb) {
		$this->do("dpkg-deb", "-x", $file, $this->unpacked_tree)
			or die "Unpacking of '$file' failed: $!";
	}
	else {
		$this->do("ar -p $file data.tar.gz | gzip -dc | (cd ".$this->unpacked_tree."; tar xpf -)")
			or die "Unpacking of '$file' failed: $!";
	}

	return 1;
}

=item getpatch

This method tries to find a patch file to use in the prep stage. If it
finds one, it returns it. Pass in a list of directories to search for
patches in.

=cut

sub getpatch {
	my $this=shift;
	my $anypatch=shift;
	
	my @patches;
	foreach my $dir (@_) {
		push @patches, glob("$dir/".$this->name."_".$this->version."-".$this->release."*.diff.gz");
	}
	if (! @patches) {
		# Try not matching the release, see if that helps.
		foreach my $dir (@_) {
			push @patches,glob("$dir/".$this->name."_".$this->version."*.diff.gz");
		}
		if (@patches && $anypatch) {
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

	$this->do("mkdir $dir/debian") ||
		die "mkdir $dir/debian failed: $!";
	
	# Use a patch file to debianize?
	if (defined $this->patchfile) {
		# The -f passed to zcat makes it pass uncompressed files
		# through without error.
		$this->do("zcat -f ".$this->patchfile." | (cd $dir; patch -p1)")
			or die "patch error: $!";
		# Look for .rej files.
		die "patch failed with .rej files; giving up"
			if $this->runpipe(1, "find $dir -name \"*.rej\"");
		$this->do('find', '.', '-name', '*.orig', '-exec', 'rm', '{}', ';');
		$this->do("chmod", 755, "$dir/debian/rules");

		# It's possible that the patch file changes the debian
		# release or version. Parse changelog to detect that.
		open (my $changelog, "<$dir/debian/changelog") || return;
		my $line=<$changelog>;
		if ($line=~/^[^ ]+\s+\(([^)]+)\)\s/) {
			my $version=$1;
			$version=~s/\s+//; # ensure no whitespace
			if ($version=~/(.*)-(.*)/) {
				$version=$1;
				$this->release($2);
			}
			$this->version($1);
		}
		close $changelog;
		
		return;
	}

	# Automatic debianization.
	# Changelog file.
	open (OUT, ">$dir/debian/changelog") || die "$dir/debian/changelog: $!";
	print OUT $this->name." (".$this->version."-".$this->release.") experimental; urgency=low\n";
	print OUT "\n";
	print OUT "  * Converted from .".$this->origformat." format to .deb by alien version $Alien::Version\n";
	print OUT "  \n";
	if (defined $this->changelogtext) {
		my $ct=$this->changelogtext;
		$ct=~s/^/  /gm;
		print OUT $ct."\n";
	}
	print OUT "\n";
	print OUT " -- ".$this->username." <".$this->email.">  ".$this->date."\n";
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
	if (defined $this->depends) {
		print OUT "Depends: ".join(", ", "\${shlibs:Depends}", $this->depends)."\n";
	}
	else {
		print OUT "Depends: \${shlibs:Depends}\n";
	}
	print OUT "Description: ".$this->summary."\n";
	print OUT $this->description."\n";
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

	# Conffiles, if any. Note that debhelper takes care of files in /etc.
	my @conffiles=grep { $_ !~ /^\/etc/ } @{$this->conffiles};
	if (@conffiles) {
		open (OUT, ">$dir/debian/conffiles") || die "$dir/debian/conffiles: $!";
		print OUT join("\n", @conffiles)."\n";
		close OUT;
	}

	# Use debhelper v7
	open (OUT, ">$dir/debian/compat") || die "$dir/debian/compat: $!";
	print OUT "7\n";
	close OUT;

	# A minimal rules file.
	open (OUT, ">$dir/debian/rules") || die "$dir/debian/rules: $!";
	my $fixpermscomment = $this->fixperms ? "" : "#";
	print OUT << "EOF";
#!/usr/bin/make -f
# debian/rules for alien

PACKAGE=\$(shell dh_listpackages)

build:
	dh_testdir

clean:
	dh_testdir
	dh_testroot
	dh_clean -d

binary-indep: build

binary-arch: build
	dh_testdir
	dh_testroot
	dh_prep
	dh_installdirs

	dh_installdocs
	dh_installchangelogs

# Copy the packages's files.
	find . -maxdepth 1 -mindepth 1 -not -name debian -print0 | \\
		xargs -0 -r -i cp -a {} debian/\$(PACKAGE)

#
# If you need to move files around in debian/\$(PACKAGE) or do some
# binary patching, do it here
#


# This has been known to break on some wacky binaries.
#	dh_strip
	dh_compress
$fixpermscomment	dh_fixperms
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
	$this->do("chmod", 755, "$dir/debian/rules");

	# Save any scripts.
	if ($this->usescripts) {
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
	
	my %dirtrans=( # Note: no trailing slashes on these directory names!
		# Move files to FHS-compliant locations, if possible.
		'/usr/man'	=> '/usr/share/man',
		'/usr/info'	=> '/usr/share/info',
		'/usr/doc'	=> '/usr/share/doc',
	);
	foreach my $olddir (keys %dirtrans) {
		if (-d "$dir/$olddir" && ! -e "$dir/$dirtrans{$olddir}") {
			# Ignore failure..
			my ($dirbase)=$dirtrans{$olddir}=~/(.*)\//;
			$this->do("install", "-d", "$dir/$dirbase");
			$this->do("mv", "$dir/$olddir", "$dir/$dirtrans{$olddir}");
			if (-d "$dir/$olddir") {
				$this->do("rmdir", "-p", "$dir/$olddir");
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
	
	# Detect architecture mismatch and abort with a comprehensible
	# error message.
	my $arch=$this->arch;
	if ($arch ne 'all') {
		my $ret=system("dpkg-architecture", "-i".$arch);
		if ($ret != 0) {
			die $this->filename." is for architecture ".$this->arch." ; the package cannot be built on this system"."\n";
		}
	}

	chdir $this->unpacked_tree;
	my $log=$this->runpipe(1, "debian/rules binary 2>&1");
	chdir "..";
	my $err=$?;
	if ($err) {
		if (! defined $log) {
			die "Package build failed; could not run generated debian/rules file.\n";
		}
		die "Package build failed. Here's the log:\n", $log;
	}

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
			$this->do("install", "-d", "$dir/$dirbase");
			$this->do("mv", "$dir/$dirtrans{$olddir}", "$dir/$olddir");
			if (-d "$dir/$dirtrans{$olddir}") {
				$this->do("rmdir", "-p", "$dir/$dirtrans{$olddir}");
			}
		}
	}
	
	$this->do("rm", "-rf", "$dir/debian");
}

=item package

Set/get package name. 

Always returns the packge name in lowercase with all invalid characters
rmoved. The name is however, stored unchanged.

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
		# on a version w/o numbers!
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
	$ret=~s/^\n+//g; # kill leading blank lines
	$ret.=" .\n" if length $ret;
	$ret.=" (Converted from a ".$this->origformat." package by alien version $Alien::Version.)";
	return $ret;
}

=item date

Returns the date, in rfc822 format.

=cut

sub date {
	my $this=shift;

	my $date=$this->runpipe(1, "date -R");
	chomp $date;
	if (!$date) {
		die "date -R did not return a valid result.";
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
		$mailname=$this->runpipe(1, "hostname");
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

=item postinst

Returns the postinst. This may include generated shell code to set owners
and groups from the owninfo field, and update modes from the modeinfo field.

=cut

sub postinst {
	my $this=shift;

	if (@_) {
		$this->{postinst}=shift;
	}
	
	my $owninfo = $this->owninfo;
	my $modeinfo = $this->modeinfo;
	my $postinst = $this->{postinst};
	return $postinst unless ref $owninfo;

	# If there is no postinst, let's make one up..
	$postinst="#!/bin/sh\n" unless length $postinst;
	
	return $postinst unless %$owninfo;
	
	my ($firstline, $rest)=split(/\n/, $postinst, 2);
	if ($firstline !~ m/^#!\s*\/bin\/(ba)?sh/) {
		print STDERR "warning: unable to add ownership fixup code to postinst as the postinst is not a shell script!\n";
		return $postinst;
	}

	my $permscript="# alien added permissions fixup code\n";
	foreach my $file (sort keys %$owninfo) {
		my $quotedfile=$file;
		$quotedfile=~s/'/'"'"'/g; # no single quotes in single quotes..
		$permscript.="chown '".$owninfo->{$file}."' '$quotedfile'\n";
		$permscript.="chmod '".$modeinfo->{$file}."' '$quotedfile'\n"
			if (defined $modeinfo->{$file});
	}
	return "$firstline\n$permscript\n$rest";
}

=back

=head1 AUTHOR

Joey Hess <joey@kitenet.net>

=cut

1
