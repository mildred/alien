#!/usr/bin/perl
#
# Package for converting to .rpm file.

# Generate the spec file.
sub Convert { my ($workdir,%fields)=@_;
	Status("Automatic spec file generation");

	# Create some more fields we will need.
	my $pwd=`pwd`;
	chomp $pwd;
	$fields{BUILDROOT}="$pwd/$workdir"; # must be absolute filename.

	# Remove directories from the filelist. Place %config in front of files 
	# that are conffiles.
	my @conffiles=split(/\n/,$fields{CONFFILES});
	my $filelist;
	foreach $fn (split(/\n/,$fields{FILELIST})) {
		if ($fn=~m:/$: eq undef) { # not a directory
			if (grep(m:^$fn$:,@conffiles)) { # it's a conffile
				$filelist.="%config $fn\n";
			}
			else { # normal file
				$filelist.="$fn\n";
			}
		}
	}
	$fields{FILELIST}=$filelist;

	FillOutTemplate("$libdir/to-$desttype/$filetype/spec",
		"$workdir/$fields{NAME}-$fields{VERSION}-$fields{RELEASE}.spec",%fields);

	if ($generate) {
		print "Directory $workdir prepared.\n";
	}
}

# Passed the available info about the package in a hash, return the name of
# the rpm package that will be made.
sub GetPackageName { my %fields=@_;

	# Ask rpm how it's set up. We want to know what architecture it will output,
	# and where it will place rpms.
	my $rpmarch, $rpmdir;
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
		Error("rpm --showrc failed.");
	}

	return "$rpmdir/$rpmarch/$fields{NAME}-$fields{VERSION}-$fields{RELEASE}.$rpmarch.rpm";
}

# Build a rpm file.
sub Build { my (%fields)=@_;
		SafeSystem("rpm -bb $ENV{RPMBUILDOPT} $fields{NAME}-$fields{VERSION}-$fields{RELEASE}.spec",
			"Error putting together the RPM package.\n");
}

# Install the passed rpm file.
sub Install { my $package=shift;
	SafeSystem("rpm -ivh $ENV{RPMINSTALLOPT} $package");
}

1
