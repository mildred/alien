#!/usr/bin/perl
#
# Package for converting to .tgz file.

package To::tgz;

use strict;

sub FixFields { my ($self,%fields)=@_;
	# Nothing to do.

	return %fields;
}

sub Convert { my ($self,$workdir,$nopatch,%fields)=@_;
	if ($main::scripts) {
		my $install_made=undef;
		my %scripttrans=(
			'doinst.sh' => 'POSTINST',
			'delete.sh' => 'POSTRM',
			'predelete.sh' => 'PRERM',
			'predoinst.sh' => 'PREINST',
		);
		my $script;
		foreach $script (keys(%scripttrans)) {
			if ($fields{$scripttrans{$script}}) {
				if (!$install_made) {
					Alien::Status("Setting up scripts.");
					mkdir "$fields{NAME}-$fields{VERSION}/install",0755
						|| Alien::Error("Unable to make install directory");
					$install_made=1;
				}
				open (OUT,">$workdir/install/$script") ||
					Alien::Error("$workdir/install/$script: $!");;
				print OUT $fields{$scripttrans{$script}};
				close OUT;
				chmod 0755,"$workdir/install/$script";
			}
		}
	}

	if ($main::generate) {
		print "Directory $workdir prepared.\n";
	}
}

# Passed the available info about the package in a hash, return the name of
# the tgz package that will be made.
sub GetPackageName { my ($self,%fields)=@_;
	return "$fields{NAME}-$fields{VERSION}-$fields{RELEASE}.tgz";
}

# Build a tgz file.
sub Build { my ($self,%fields)=@_;
	Alien::SafeSystem("tar czf ../".$self->GetPackageName(%fields)." .");
}

# Install the passed tgz file.
sub Install { my ($self,$package)=@_;
	if (-x "/sbin/installpkg") {
		Alien::SafeSystem("/sbin/installpkg $package");
	}
	else {
		Alien::Warning("Sorry, I cannot install the generated .tgz file,");
		Alien::Warning("\"$package\" because /sbin/installpkg is not");
		Alien::Warning("present. You can use tar to install it yourself.");
		exit 1; # otherwise alien will delete the package file on us.
	}
}

1
