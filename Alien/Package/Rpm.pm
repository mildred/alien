#!/usr/bin/perl -w

=head1 NAME

Alien::Package::Rpm - an object that represents a rpm package

=cut

package Alien::Package::Rpm;
use strict;
use Alien::Package; # perlbug
use base qw(Alien::Package);

=head1 DESCRIPTION

This is an object class that represents a rpm package. It is derived from
Alien::Package.

=head1 FIELDS

=over 4

=item prefixes

Relocatable rpm packages have a prefixes field.

=head1 METHODS

=over 4

=item install

Install a rpm. If RPMINSTALLOPT is set in the environement, the options in
it are passed to rpm on its command line.

=cut

sub install {
	my $this=shift;
	my $rpm=shift;

	system("rpm -ivh $ENV{RPMINSTALLOPT} $rpm") &&
		die "Unable to install: $!";
}

=item scan

Implement the scan method to read a rpm file.

=cut

sub scan {
	my $this=shift;
	$this->SUPER::read_file(@_);
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
		$_=`LANG=C rpm -qp $file --queryformat \%{$field}`;
		$field=$fieldtrans{$field};
		$this->$field($_) if $_ ne '(none)';
	}

	# Get the conffiles list.
	$this->conffiles([map { chomp; $_ } `rpm -qcp $file`]);

	$this->binary_info(scalar `rpm -qpi $file`);

	# Get the filelist.
	$this->filelist([map { chomp; $_ } `rpm -qpl $file`]);

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

	system ("rpm2cpio ".$this->filename." | (cd $workdir; cpio --extract --make-directories --no-absolute-filenames --preserve-modification-time) 2>/dev/null") &&
		die "Unpacking of `".$this->filename."' failed: $!";
	
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
		my $filelist=join ' ',glob("$workdir/*");

		# Now, make the destination directory.
		my $collect=$workdir;
		foreach (split m:/:, $this->prefixes) {
			if ($_ ne undef) { # this keeps us from using anything but relative paths.
				$collect.="$_/";
				mkdir $collect,0755 || die "unable to mkdir $collect: $!";
			}
		}
		# Now move all files in the package to the directory we made.
		system "mv $filelist $workdir/".$this->prefixes &&
			die "error moving unpacked files into the default prefix directory: $!";
	}

	# When cpio extracts the file, any child directories that are
	# present, but whose parent directories are not, end up mode 700.
	# This next block correctsthat to 755, which is more reasonable.
	#
	# Of course, this whole thing assumes we get the filelist in sorted
	# order.
	my $lastdir='';
	foreach my $file (@{$this->filelist}) {
		$file=~s/^\///;
		if (($lastdir && $file=~m:^\Q$lastdir\E/[^/]*$: eq undef) || !$lastdir) {
			# We've found one of the nasty directories. Fix it
			# up.
			#
			# Note that I strip the trailing filename off $file
			# here, for two reasons. First, it makes the loop
			# easier, we don't need to fix the perms on the
			# last file, after all! Second, it makes the -d
			# test below fire, which saves us from trying to
			# fix a parent directory twice.
			($file)=$file=~m:(.*)/.*?:;
			my $dircollect='';
			foreach my $dir (split(/\//,$file)) {
				$dircollect.="$dir/";
				chmod 0755,$dircollect; # TADA!
			}
		}
		$lastdir=$file if -d "./$file";
	}

	return 1;
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

When retreiving a value, we have to do some truely sick mangling. Since
debian/slackware scripts can be anything -- perl programs or binary files
-- and rpm is limited to only shell scripts, we need to encode the files
and add a scrap of shell script to make it unextract and run on the fly.

=cut

# This helper function deals with all the scripts.
sub _script_helper {
	my $this=shift;
	my $script=shift;

	# set
	$this->{$script} = shift if @_;

	# get
	return unless defined wantarray; # optimization
	$_=$this->{$script};
	return $_ if ! defined $_ || m/^\s*$/;
	my $f = pack("u",$_);
	$f =~ s/%/%%/g; # Rpm expands %S, so escape such things.
	return "set -e\n".
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
	$this->_script_helper($this, 'postinst', @_);
}
sub postrm {
	my $this=shift;
	$this->_script_helper($this, 'postrm', @_);
}
sub preinst {
	my $this=shift;
	$this->_script_helper($this, 'preinst', @_);
}
sub prerm {
	my $this=shift;
	$this->_script_helper($this, 'prerm', @_);
}

=item arch

Set/get arch field. When the arch field is set, some sanitizing is done
first to convert it to the debian format used internally.

=cut

sub arch {
	my $this=shift;
	return $this->{arch} unless @_;
	my $arch=shift;

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
	
	# Treat 486, 586, etc, as 386.
	if ($arch =~ m/i\d86/i || $arch =~ m/pentium/i) {
		$arch='i386';
	}
	
	return $this->{arch}=$arch;
}

=back

=head1 AUTHOR

Joey Hess <joey@kitenet.net>

=cut

1
