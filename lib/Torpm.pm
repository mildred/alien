#!/usr/bin/perl
#
# Package for converting to .rpm file.

package To::rpm;

use strict;

# Mangle the fields to make rpm happy with them.
sub FixFields { my ($self,%fields)=@_;
  # Make sure the version has no dashes in it.
	$fields{VERSION} =~ tr/-/_/;

	# Fix up the scripts. Since debian/slackware scripts can be anything, even
	# perl programs or binary files, and redhat is limited to only shell scripts,
	# we need to encode the files and add a scrap of shell script to make it 
	# unextract and run on the fly.
	my $field;
	foreach $field ('POSTINST', 'POSTRM', 'PREINST', 'PRERM') {
		if ($fields{$field}) {
			$fields{$field}=
				"set -e\n".
				"mkdir /tmp/alien.\$\$\n".
				qq{perl -pe '\$_=unpack("u",\$_)' << '__EOF__' > /tmp/alien.\$\$/script\n}.
				pack("u",$fields{$field}).
				"__EOF__\n".
				"chmod 755 /tmp/alien.\$\$/script\n".
				"/tmp/alien.\$\$/script \"\$@\"\n".
				"rm -f /tmp/alien.\$\$/script\n".
				"rmdir /tmp/alien.\$\$";
		}
	}

	return %fields;
}

# Generate the spec file.
sub Convert { my ($self,$workdir,$nopatch,%fields)=@_;
	Alien::Status("Automatic spec file generation");

	# Create some more fields we will need.
	my $pwd=`pwd`;
	chomp $pwd;
	$fields{BUILDROOT}="$pwd/$workdir"; # must be absolute filename.

	# Remove directories from the filelist. Place %config in front of files 
	# that are conffiles.
	my @conffiles=split(/\n/,$fields{CONFFILES});
	my $filelist;
	my $fn;
	foreach $fn (split(/\n/,$fields{FILELIST})) {
		if ($fn=~m:/$: eq undef) { # not a directory
			if (grep(m:^\Q$fn\E$:,@conffiles)) { # it's a conffile
				$filelist.="%config $fn\n";
			}
			else { # normal file
				$filelist.="$fn\n";
			}
		}
	}
	$fields{FILELIST}=$filelist;

	Alien::FillOutTemplate("$main::libdir/to-$main::desttype/$main::filetype/spec",
		"$workdir/$fields{NAME}-$fields{VERSION}-$fields{RELEASE}.spec",%fields);

	if ($main::generate) {
		print "Directory $workdir prepared.\n";
	}
}

# Passed the available info about the package in a hash, return the name of
# the rpm package that will be made.
sub GetPackageName { my ($self,%fields)=@_;

	# Ask rpm how it's set up. We want to know what architecture it will output,
	# and where it will place rpms.
	my ($rpmarch, $rpmdir);
	foreach (`rpm --showrc`) {
		chomp;
		if (/^build arch\s+:\s(.*)$/) {
			$rpmarch=$1;
		}
		elsif (/^rpmdir\s+:\s(.*)$/) {
			$rpmdir=$1;
		}
	}
	if (!$rpmarch) {
		Alien::Error("rpm --showrc failed.");
	}

	# Debian's "all" architecture is a special case, and the output rpm
	# will be a noarch rpm.
	if ($fields{ARCH} eq 'all') { $rpmarch='noarch' }

	if (! $rpmdir) {
		# Presumably we're delaing with rpm 3.0 or above, which
		# doesn't output rpmdir in any format I'd care to try to parse.
		# Instead, rpm is now of a late enough version to notice the
		# %define's in the spec file, that will make the file end up in
		# the directory we started in.
		return "$fields{NAME}-$fields{VERSION}-$fields{RELEASE}.$rpmarch.rpm";
	}
	else {
		# Old rpm.
		return "$rpmdir/$rpmarch/$fields{NAME}-$fields{VERSION}-$fields{RELEASE}.$rpmarch.rpm";
	}
}

# Build a rpm file.
sub Build { my ($self,%fields)=@_;
		# Debian's "all" architecture is a special case where we make noarch rpms.
		my $buildarch;
		if ($fields{ARCH} eq 'all') {
			# Nasty version check in here because rpm gratuitously
			# changed this option at version 3.0.
			my $lc_all=$ENV{LC_ALL};
			$ENV{LC_ALL}='C';
			my $version=`rpm --version`;
			$ENV{LC_ALL}=$lc_all; # important to reset it.
			my $minor;
			($version,$minor)=$version=~m/version (\d+).(\d+)/;
			if ($version >= 3 || ($version eq 2 && $minor >= 92)) {
				$buildarch="--target noarch";
			}
			else {
				$buildarch="--buildarch noarch"
			}
		}
		Alien::SafeSystem("rpm $buildarch -bb $ENV{RPMBUILDOPT} $fields{NAME}-$fields{VERSION}-$fields{RELEASE}.spec",
			"Error putting together the RPM package.\n");
}

# Install the passed rpm file.
sub Install { my ($self,$package)=@_;
	Alien::SafeSystem("rpm -ivh $ENV{RPMINSTALLOPT} $package");
}

1
