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
				"rm -f /tmp/alien.$field\n".
				qq{perl -pe '\$_=unpack("u",\$_)' << '__EOF__' > /tmp/alien.$field\n}.
				pack("u",$fields{$field}).
				"__EOF__\n".
				"sh /tmp/alien.$field \"\$@\"\n".
				"rm -f /tmp/alien.$field\n";
		}
	}

	return %fields;
}

# Generate the spec file.
sub Convert { my ($self,$workdir,%fields)=@_;
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
			my $efn=quotemeta($fn);
			if (grep(m:^$efn$:,@conffiles)) { # it's a conffile
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
	if (!$rpmarch || !$rpmdir) {
		Alien::Error("rpm --showrc failed.");
	}

	# Debian's "all" architecture is a special case, and the output rpm will
	# be a noarch rpm.
	if ($fields{ARCH} eq 'all') { $rpmarch='noarch' }
	return "$rpmdir/$rpmarch/$fields{NAME}-$fields{VERSION}-$fields{RELEASE}.$rpmarch.rpm";
}

# Build a rpm file.
sub Build { my ($self,%fields)=@_;
		# Debian's "all" architecture is a special case where we make noarch rpms.
		my $buildarch;
		if ($fields{ARCH} eq 'all') { $buildarch="--buildarch noarch" }
		Alien::SafeSystem("rpm $buildarch -bb $ENV{RPMBUILDOPT} $fields{NAME}-$fields{VERSION}-$fields{RELEASE}.spec",
			"Error putting together the RPM package.\n");
}

# Install the passed rpm file.
sub Install { my ($self,$package)=shift;
	Alien::SafeSystem("rpm -ivh $ENV{RPMINSTALLOPT} $package");
}

1
