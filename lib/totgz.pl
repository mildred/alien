#!/usr/bin/perl
#
# Package for converting to .tgz file.

sub Convert { my ($workdir,%fields)=@_;
	# Nothing to do.
}

# Passed the available info about the package in a hash, return the name of
# the tgz package that will be made.
sub GetPackageName { my %fields=@_;
	return "$fields{NAME}.tgz";
}

# Build a tgz file.
sub Build { my (%fields)=@_;
	SafeSystem("tar czf ../".GetPackageName(%fields)." .");
}

# Install the passed tgz file.
sub Install { my $package=shift;
	# Not yet supported. (I really don't like unpacking tgz files into the 
	# root directory. :-)	
	print STDERR "Sorry, installing generated .tgz files in not yet supported.\n";
}

1
