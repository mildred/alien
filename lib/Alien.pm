#!/usr/bin/perl
#
# Misc. functions used by alien.

package Alien;

use strict;


# Pass this the name and version and revision of a package, it will return the 
# filename of a patch file for the package or undef if there is none.
sub GetPatch { my ($name,$version,$revision)=@_;
	my @patches=();
	my $dir;
	foreach $dir (@main::patchdirs) {
		push @patches,glob("$dir/$name\_$version-$revision*.diff.gz");
	}
	if ($#patches < 0) {
		# try not matching the revision, see if that helps.
		foreach $dir (@main::patchdirs) {
			push @patches,glob("$dir/$name\_$version*.diff.gz");
		}
		if ($#patches < 0) {
			# fallback to anything that matches the name.
			foreach $dir (@main::patchdirs) {
				push @patches,glob("$dir/$name\_*.diff.gz");
			}
		}
	}

	# If we ended up with multiple matches, return the first.
	return $patches[0];
}

1
