#!/usr/bin/perl
#
# Package for converting to stampede package format.

# Pull in details on the binary footer.
use Slp;

package To::slp;

use strict;

# Mangle the fields as necessary for a stampede package.
sub FixFields { my ($self,%fields)=@_;
	# Mangle conffiles to the format they want.
	$fields{CONFFILES}=~s/\n/:/g;
	$fields{CONFFILES}=~s/:$//;

	# Use priority optional for alien packages.
	$fields{PRIORITY}=2;

	# I always use bzip2 as the compression type.
	$fields{COMPRESSTYPE}=0;

	# Their version of release is a unsigned integer, so I need to 
	# convert anythnig more compilcated.
	$fields{RELEASE}=int($fields{RELEASE});

	# I don't try to guess copyright, just use unknown.
	$fields{COPYRIGHT}=254;

	# I don't try to fill these in with meaningful values.
	$fields{CONFLICTS}="";
	$fields{DEPENDS}="";
	$fields{PROVIDES}="";

	# TODO:
	$fields{SETUPSTRIPT}=undef;

	# Let's use the current date for this.
	$fields{DATE}=`date`;
	chomp $fields{DATE};

	# Pick a compiler version.
	if ($fields{ARCH} eq 'all') {
		$fields{COMPILER}=253; # No compiler
	}
	else {
		$fields{COMPILER}=252; # Unknown compiler
	}

	# Pick a binary format from the translation table.
	$fields{BINFORMAT}=undef;
	my $archnum;
	foreach $archnum (keys %$slp::archtrans) {
		if ($$slp::archtrans{$archnum} eq $fields{ARCH}) {
			$fields{BINFORMAT} = $archnum;
			last;
		}
	}
	if ($fields{BINFORMAT} eq undef) {
		Alien::Error("Stampede does not appear to support architecure $fields{ARCH} packages.");
	}

	# This is really the software category; use unknown.
	$fields{GROUP}=252;

	$fields{SLPKGVERSION}=$slp::footer_version;

	return %fields;
}

# Do any necessary conversions on the file tree.
sub Convert { my ($self,$workdir,%fields)=@_;
}

# Passed the available info about the package in a hash, return the name of
# the slp package that will be made.
sub GetPackageName { my ($self,%fields)=@_;
	return "$fields{NAME}-$fields{VERSION}.slp";
}

# Returns a slp footer in a scalar.
sub MakeFooter { my %fields=@_;
	# We cannot use the actual $slp::footer_packstring, becuase it uses
	# space terminated strings (A) instead of null terminated strings (a).
	# This is good for decoding, but not for encoding.
	$_=$slp::footer_packstring;
	tr/A/a/;

	return pack($_,(
		$fields{CONFFILES},
		$fields{PRIORITY},
		$fields{COMPRESSTYPE},
		$fields{RELEASE},
		$fields{COPYRIGHT},
		$fields{CONFLICTS},
		$fields{SETUPSCRIPT},
		$fields{SUMMARY},
		$fields{DESCRIPTION},
		$fields{DEPENDS},
		$fields{PROVIDES},
		$fields{AUTHOR},
		$fields{DATE},
		$fields{COMPILER},
		$fields{VERSION},
		$fields{NAME},
		$fields{ARCH},
		$fields{GROUP},
		$fields{SLPKGVERSION},
	)); 
}

# Build a slp file.
# This consists of first generating a .tar.bz2 file, and then appending the
# footer to it.
sub Build { my ($self,%fields)=@_;
	# Note the -I is for making a .bzip2 file.
	Alien::SafeSystem("tar cIf ../".$self->GetPackageName(%fields)." .");

	# Now append the footer to that.
	open (OUT,">>../".$self->GetPackageName(%fields)) ||
		Alien::Error("Unable to append footer.");
	print OUT MakeFooter(%fields);
	close OUT;
}

# Install the passed slp file.
sub Install { my ($self,$package)=shift;
	Alien::SafeSystem("slpi $package");
}

1
