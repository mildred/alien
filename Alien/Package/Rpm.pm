#!/usr/bin/perl -w

=head1 NAME

Alien::Package::Rpm - an object that represents a rpm package

=cut

package Alien::Package::Rpm;
use strict;
use base qw(Alien::Package);

=head1 DESCRIPTION

This is an object class that represents a rpm package. It is derived from
Alien::Package.

=head1 FIELDS

=over 4

=item prefixes

Relocatable rpm packages have a prefixes field.

=back

=head1 METHODS

=over 4

=item checkfile

Detect rpm files by their extention.

=cut

sub checkfile {
	my $this=shift;
	my $file=shift;

	return $file =~ m/.*\.rpm$/;
}

=item install

Install a rpm. If RPMINSTALLOPT is set in the environement, the options in
it are passed to rpm on its command line.

=cut

sub install {
	my $this=shift;
	my $rpm=shift;

	my $v=$Alien::Package::verbose;
	$Alien::Package::verbose=2;
	$this->do("rpm -ivh ".(exists $ENV{RPMINSTALLOPT} ? $ENV{RPMINSTALLOPT} : '').$rpm)
		or die "Unable to install";
	$Alien::Package::verbose=$v;
}

=item scan

Implement the scan method to read a rpm file.

=cut

sub scan {
	my $this=shift;
	$this->SUPER::scan(@_);
	my $file=$this->filename;

	my %fieldtrans=(
		PREIN => 'preinst',
		POSTIN => 'postinst',
		PREUN => 'prerm',
		POSTUN => 'postrm',
	);

	# These fields need no translation except case.
	foreach (qw{name version release arch changelogtext summary
		    description copyright prefixes}) {
		$fieldtrans{uc $_}=$_;
	}

	# Use --queryformat to pull out all the fields we need.
	foreach my $field (keys(%fieldtrans)) {
		$_=$this->runpipe(0, "LANG=C rpm -qp --queryformat \%{$field} $file");
		$field=$fieldtrans{$field};
		$_='' if $_ eq '(none)';
		$this->$field($_);
	}

	# Get the conffiles list.
	$this->conffiles([map { chomp; $_ } $this->runpipe(0, "LANG=C rpm -qcp $file")]);
	if (defined $this->conffiles->[0] &&
	    $this->conffiles->[0] eq '(contains no files)') {
		$this->conffiles([]);
	}

	$this->binary_info(scalar $this->runpipe(0, "rpm -qpi $file"));

	# Get the filelist.
	$this->filelist([map { chomp; $_ } $this->runpipe(0, "LANG=C rpm -qpl $file")]);
	if (defined $this->filelist->[0] &&
	    $this->filelist->[0] eq '(contains no files)') {
		$this->filelist([]);
	}

	# Sanity check and sanitize fields.
	unless (defined $this->summary) {
		# Older rpms will have no summary, but will have a
		# description. We'll take the 1st line out of the
		# description, and use it for the summary.
		$this->summary($this->description."\n")=~m/(.*?)\n/m;

		# Fallback.
		if (! $this->summary) {
			$this->summary('Converted RPM package');
		}
	}
	unless (defined $this->copyright) {
		$this->copyright('unknown');
	}
	unless (defined $this->description) {
		$this->description($this->summary);
	}
	if (! defined $this->release || ! defined $this->version || 
	    ! defined $this->name) {
		die "Error querying rpm file";
	}

	$this->distribution("Red Hat");
	$this->origformat("rpm");

	return 1;
}

=item unpack

Implement the unpack method to unpack a rpm file. This is a little nasty
because it has to handle relocatable rpms and has to do a bit of
permissions fixing as well.

=cut

sub unpack {
	my $this=shift;
	$this->SUPER::unpack(@_);
	my $workdir=$this->unpacked_tree;
	
	$this->do("rpm2cpio ".$this->filename." | (cd $workdir; cpio --extract --make-directories --no-absolute-filenames --preserve-modification-time) 2>&1")
		or die "Unpacking of '".$this->filename."' failed";
	
	# cpio does not necessarily store all parent directories in an
	# archive, and so some directories, if it has to make them and has
	# no permission info, will come out with some random permissions.
	# Find those directories and make them mode 755, which is more
	# reasonable.
	my %seenfiles;
	open (RPMLIST, "rpm2cpio ".$this->filename." | cpio -it --quiet |")
		or die "File list of '".$this->filename."' failed";
	while (<RPMLIST>) {
		chomp;
		$seenfiles{$_}=1;
	}
	close RPMLIST;
	foreach my $file (`cd $workdir; find ./`) {
		chomp $file;
		if (! $seenfiles{$file} && -d "$workdir/$file" && ! -l "$workdir/$file") {
			$this->do("chmod 755 $workdir/$file");
		}
	}

	# If the package is relocatable. We'd like to move it to be under
	# the $this->prefixes directory. However, it's possible that that
	# directory is in the package - it seems some rpm's are marked as
	# relocatable and unpack already in the directory they can relocate
	# to, while some are marked relocatable and the directory they can
	# relocate to is removed from all filenames in the package. I
	# suppose this is due to some change between versions of rpm, but
	# none of this is adequatly documented, so we'll just muddle
	# through.
	#
	# Test to see if the package contains the prefix directory already.
	if (defined $this->prefixes && ! -e "$workdir/".$this->prefixes) {
		# Get the files to move.
		my @filelist=glob("$workdir/*");

		# Now, make the destination directory.
		my $collect=$workdir;
		foreach (split m:/:, $this->prefixes) {
			if ($_ ne '') { # this keeps us from using anything but relative paths.
				$collect.="/$_";
				$this->do("mkdir", $collect) || die "unable to mkdir $collect: $!";
			}
		}
		# Now move all files in the package to the directory we made.
		if (@filelist) {
			$this->do("mv", @filelist, "$workdir/".$this->prefixes)
				or die "error moving unpacked files into the default prefix directory: $!";
		}

		# Deal with relocating conffiles.
		my @cf;
		foreach my $cf (@{$this->conffiles}) {
			$cf=$this->prefixes.$cf;
			push @cf, $cf;
		}
		$this->conffiles([@cf]);
	}
	
	# rpm files have two sets of permissions; the set in the cpio
	# archive, and the set in the control data; which override them.
	# The set in the control data are more correct, so let's use those.
	# Some permissions setting may have to be postponed until the
	# postinst.
	my %owninfo = ();
	my %modeinfo = ();
	open (GETPERMS, 'rpm --queryformat \'[%{FILEMODES} %{FILEUSERNAME} %{FILEGROUPNAME} %{FILENAMES}\n]\' -qp '.$this->filename.' |');
	while (<GETPERMS>) {
		chomp;
		my ($mode, $owner, $group, $file) = split(/ /, $_, 4);
		$mode = $mode & 07777; # remove filetype
		my $uid = getpwnam($owner);
		if (! defined $uid || $uid != 0) {
			$owninfo{$file}=$owner;
			$uid=0;
		}
		my $gid = getgrnam($group);
		if (! defined $gid || $gid != 0) {
			if (exists $owninfo{$file}) {
				$owninfo{$file}.=":$group";
			}
			else {
				$owninfo{$file}=":$group";
			}
			$gid=0;
		}
		if (defined($owninfo{$file}) && ($mode & 07000 > 0)) {
			$modeinfo{$file} = sprintf "%lo", $mode;
		}
		next unless -e "$workdir/$file"; # skip broken links
		if ($> == 0) {
			$this->do("chown", "$uid:$gid", "$workdir/$file") 
				|| die "failed chowning $file to $uid\:$gid\: $!";
		}
		next if -l "$workdir/$file"; # skip links
		$this->do("chmod", sprintf("%lo", $mode), "$workdir/$file") 
			|| die "failed changing mode of $file to $mode\: $!";
	}
	$this->owninfo(\%owninfo);
	$this->modeinfo(\%modeinfo);

	return 1;
}

=item prep

Prepare for package building by generating the spec file.

=cut

sub prep {
	my $this=shift;
	my $dir=$this->unpacked_tree || die "The package must be unpacked first!";

	# Place %config in front of files that are conffiles.
	my @conffiles = @{$this->conffiles};
	my $filelist;
	foreach my $fn (@{$this->filelist}) {
		# Unquote any escaped characters in filenames - needed for
		# non ascii characters. (eg. iso_8859-1 latin set)
		if ($fn =~ /\\/) {
			$fn=eval qq{"$fn"};
		}

		# Note all filenames are quoted in case they contain
		# spaces.
		if ($fn =~ m:/$:) {
			$filelist.=qq{%dir "$fn"\n};
		}
		elsif (grep(m:^\Q$fn\E$:,@conffiles)) { # it's a conffile
			$filelist.=qq{%config "$fn"\n};
		}
		else { # normal file
			$filelist.=qq{"$fn"\n};
		}
	}

	# Write out the spec file.
	my $spec="$dir/".$this->name."-".$this->version."-".$this->release.".spec";
	open (OUT, ">$spec") || die "$spec: $!";
	my $pwd=`pwd`;
	chomp $pwd;
	print OUT "Buildroot: $pwd/$dir\n"; # must be absolute dirname
	print OUT "Name: ".$this->name."\n";
	print OUT "Version: ".$this->version."\n";
	print OUT "Release: ".$this->release."\n";
	print OUT "Requires: ".$this->depends."\n"
		if defined $this->depends && length $this->depends;
	print OUT "Summary: ".$this->summary."\n";
	print OUT "License: ".$this->copyright."\n";
	print OUT "Distribution: ".$this->distribution."\n";
	print OUT "Group: Converted/".$this->group."\n";
	print OUT "\n";
	print OUT "\%define _rpmdir ../\n"; # write rpm to current directory
	print OUT "\%define _rpmfilename %%{NAME}-%%{VERSION}-%%{RELEASE}.%%{ARCH}.rpm\n";
	print OUT "\%define _unpackaged_files_terminate_build 0\n"; # work on SuSE
	print OUT "\n";
	if ($this->usescripts) {
		if ($this->preinst) {
			print OUT "\%pre\n";
			print OUT $this->preinst."\n";
			print OUT "\n";
		}
		if ($this->postinst) {
			print OUT "\%post\n";
			print OUT $this->postinst."\n";
			print OUT "\n";
		}
		if ($this->prerm) {
			print OUT "\%preun\n";
			print OUT $this->prerm."\n";
			print OUT "\n";
		}
		if ($this->postrm) {
			print OUT "\%postun\n";
			print OUT $this->postrm."\n";
			print OUT "\n";
		}
	}
	print OUT "\%description\n";
	print OUT $this->description."\n";
	print OUT "\n";
	print OUT "(Converted from a ".$this->origformat." package by alien version $Alien::Version.)\n";
	print OUT "\n";
	print OUT "%files\n";
	print OUT $filelist if defined $filelist;
	close OUT;
}

=item cleantree

Delete the spec file.

=cut

sub cleantree {
	my $this=shift;
	my $dir=$this->unpacked_tree || die "The package must be unpacked first!";
	
	unlink "$dir/".$this->name."-".$this->version."-".$this->release.".spec";
}

=item build

Build a rpm. If RPMBUILDOPT is set in the environement, the options in
it are passed to rpm on its command line.

An optional parameter, if passed, can be used to specify the program to use
to build the rpm. It defaults to rpmbuild.

=cut

sub build {
	my $this=shift;
	my $buildcmd=shift || 'rpmbuild';
	my $dir=$this->unpacked_tree || die "The package must be unpacked first!";
	
	# Ask rpm how it's set up. We want to know where it will place rpms.
	my $rpmdir;
	foreach ($this->runpipe(1, "rpm --showrc")) {
		chomp;
		if (/^rpmdir\s+:\s(.*)$/) {
			$rpmdir=$1;
		}
	}

	my $rpm=$this->name."-".$this->version."-".$this->release.".".$this->arch.".rpm";
	my $opts='';
	if ($rpmdir) {
		# Old versions of rpm toss it off in the middle of nowhere.
		$rpm="$rpmdir/".$this->arch."/$rpm";

		# This is the old command line argument to set the arch.
		$opts="--buildarch ".$this->arch;
	}
	else {
		# Presumably we're delaing with rpm 3.0 or above, which
		# doesn't output rpmdir in any format I'd care to try to
		# parse. Instead, rpm is now of a late enough version to
		# notice the %define's in the spec file, that will make the
		# file end up in the directory we started in.
		# Anyway, let's assume this is version 3 or above.
		
		# This is the new command line arcgument to set the arch
		# rpms. It appeared in rpm version 3.
		$opts="--target ".$this->arch;
	}

	$opts.=" $ENV{RPMBUILDOPT}" if exists $ENV{RPMBUILDOPT};
	my $command="cd $dir; $buildcmd -bb $opts ".$this->name."-".$this->version."-".$this->release.".spec";
	my $log=$this->runpipe(1, "$command 2>&1");
	if ($?) {
		die "Package build failed. Here's the log of the command ($command):\n", $log;
	}

	return $rpm;
}

=item version

Set/get version.

When retreiving the version, remove any dashes in it.

=cut

sub version {
	my $this=shift;

	# set
	$this->{version} = shift if @_;

	# get
	return unless defined wantarray; # optimization
	$_=$this->{version};
	tr/-/_/;
	return $_;
}

=item postinst

=item postrm

=item preinst

=item prerm

Set/get script fields.

When retrieving a value, we have to do some truely sick mangling. Since
debian/slackware scripts can be anything -- perl programs or binary files
-- and rpm is limited to only shell scripts, we need to encode the files
and add a scrap of shell script to make it unextract and run on the fly.

When setting a value, we do some mangling too. Rpm maitainer scripts
are typically shell scripts, but often lack the leading #!/bin/sh
This can confuse dpkg, so add the #!/bin/sh if it looks like there
is no shebang magic already in place.

Also, if the rpm is relocatable, the script could refer to
RPM_INSTALL_PREFIX, which is set by rpm at run time. Deal with this by
adding code to the script to set RPM_INSTALL_PREFIX.

=cut

# This helper function deals with all the scripts.
sub _script_helper {
	my $this=shift;
	my $script=shift;

	# set
	if (@_) {
		my $prefixcode="";
		if (defined $this->prefixes) {
			$prefixcode="RPM_INSTALL_PREFIX=".$this->prefixes."\n";
			$prefixcode.="export RPM_INSTALL_PREFIX\n";
		}

		my $value=shift;
		if (length $value and $value !~ m/^#!\s*\//) {
			$value="#!/bin/sh\n$prefixcode$value";
		}
		else {
			$value=~s/\n/\n$prefixcode/s;
		}
		$this->{$script} = $value;
	}
	$this->{$script} = shift if @_;

	# get
	return unless defined wantarray; # optimization
	$_=$this->{$script};
	return '' unless defined $_;
	return $_ if m/^\s*$/;
	return $_ if m/^#!\s*\/bin\/sh/; # looks like a shell script already
	my $f = pack("u",$_);
	$f =~ s/%/%%/g; # Rpm expands %S, so escape such things.
	return "#!/bin/sh\n".
	       "set -e\n".
	       "mkdir /tmp/alien.\$\$\n".
	       qq{perl -pe '\$_=unpack("u",\$_)' << '__EOF__' > /tmp/alien.\$\$/script\n}.
	       $f."__EOF__\n".
	       "chmod 755 /tmp/alien.\$\$/script\n".
	       "/tmp/alien.\$\$/script \"\$@\"\n".
	       "rm -f /tmp/alien.\$\$/script\n".
	       "rmdir /tmp/alien.\$\$";
}
sub postinst {
	my $this=shift;
	$this->_script_helper('postinst', @_);
}
sub postrm {
	my $this=shift;
	$this->_script_helper('postrm', @_);
}
sub preinst {
	my $this=shift;
	$this->_script_helper('preinst', @_);
}
sub prerm {
	my $this=shift;
	$this->_script_helper('prerm', @_);
}

=item arch

Set/get arch field. When the arch field is set, some sanitizing is done
first to convert it to the debian format used internally. When it's
retreived it's converted back to rpm form from the internal form.

=cut

sub arch {
	my $this=shift;

	my $arch;
	if (@_) {
		$arch=shift;

		if ($arch eq 1) {
			$arch='i386';
		}
		elsif ($arch eq 2) {
			$arch='alpha';
		}
		elsif ($arch eq 3) {
			$arch='sparc';
		}
		elsif ($arch eq 6) {
			$arch='m68k';
		}
		elsif ($arch eq 'noarch') {
			$arch='all';
		}
		elsif ($arch eq 'ppc') {
			$arch='powerpc';
		}
		elsif ($arch eq 'x86_64') {
			$arch='amd64';
		}
		elsif ($arch eq 'em64t') {
			$arch='amd64';
		}
		elsif ($arch =~ m/i\d86/i || $arch =~ m/pentium/i) {
			# Treat 486, 586, etc, as 386.
			$arch='i386';
		}
		elsif ($arch eq 'armv4l') {
			# Treat armv4l as arm.
			$arch='arm';
		}
		elsif ($arch eq 'parisc') {
			$arch='hppa';
		}
		
		$this->{arch}=$arch;
	}

	$arch=$this->{arch};
	if ($arch eq 'amd64') {
		$arch='x86_64';
	}
	elsif ($arch eq 'powerpc') {
		# XXX is this the canonical name for powerpc on rpm
		# systems?
		$arch='ppc';
	}
	elsif ($arch eq 'hppa') {
		$arch='parisc';
	}
	elsif ($arch eq 'all') {
		$arch='noarch';
	}

	return $arch
}

=back

=head1 AUTHOR

Joey Hess <joey@kitenet.net>

=cut

1
