#!/usr/bin/perl
#
# Package for converting from a .slp (Stampede) file.

# Pull in details on the binary footer.
use Slp;

package From::slp;

use strict;

# Pass it a chunk of footer, it will attempt a decode and spit back the result
# in a hash, %fields.
sub DecodeFooter { my $footer=shift;
	my %fields;

	($fields{CONFFILES},
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
	)=unpack($slp::footer_packstring,$footer);

	# A simple sanity check.
	if (! $fields{SLPKGVERSION} || $fields{SLPKGVERSION} < $slp::footer_version) {
		Alien::Error("This is not a V$slp::footer_version or greater Stampede package");
	}

	return %fields;
}

# Pass it a filename of a .slp file, it will pull out a footer and return it
# in a scalar.
sub GetFooter { my ($filename)=@_;
	open (SLP,"<$filename") || Alien::Error("unable to read $filename: $!");
	seek SLP,(-1 * $slp::footer_size),2; # position at beginning of footer (2 = seek from EOF)
	read SLP,$_,$slp::footer_size;
	close SLP;
	return $_;
}

# Query a slp file for fields, and return a hash of the fields found.
# Pass the filename of the slp file to query.
sub GetFields { my ($self,$file)=@_;
	my %fields=DecodeFooter(GetFooter($file));

	# Massage the fields into appropriate formats.
	if ($fields{CONFFILES}) {
		$fields{CONFFILES}=~s/:/\n/g;
		$fields{CONFFILES}.="\n";
	}

	if ($$slp::copyrighttrans{$fields{COPYRIGHT}}) {
		$fields{COPYRIGHT}=$$slp::copyrighttrans{$fields{COPYRIGHT}};
	}
	else {
		Alien::Warning("I don't know what copyright type \"$fields{COPYRIGHT}\" is.");
		$fields{COPYRIGHT}="unknown";
	}

	if ($$slp::archtrans{$fields{ARCH}}) {
		$fields{ARCH}=$$slp::archtrans{$fields{ARCH}};
	}
	else {
		Alien::Error("An unknown architecture, \"$fields{ARCH}\" was specified.");
	}

	$fields{RELEASE}++ unless $main::keep_version;
	$fields{DISTRIBUTION}="Stampede";

	# Read in the list of all files.
	$fields{FILELIST}=undef;
	my $fn;
	foreach $fn (`bzip2 -d < $file | tar -tf -`) {
		# They may have a leading "." we don't want.
		$fn=~s:^\./:/:;
		# Ensure there is always a leading '/'.
		if ($fn=~m:^/: eq undef) {
			$fn="/$fn";
		}
		$fields{FILELIST}.="$fn\n";
	}

	# TODO: read in postinst script.

	return %fields;
}

# Unpack a slp file.
# They can be compressed in various ways, depending on what is in
# $fields{COMPRESSTYPE}.
sub Unpack { my ($self,$file,$nopatch,%fields)=@_;
	if ($fields{COMPRESSTYPE} eq 0) {
		Alien::SafeSystem ("(cd ..;cat $file) | bzip2 -d | tar xpf -","Error unpacking $file\n");
	}
	elsif ($fields{COMPRESSTYPE} eq 1) {
		# .gz
		Alien::SafeSystem ("(cd ..;cat $file) | tar zxpf -","Error unpacking $file\n");
	}
	else {
		# Seems .zip might be a possibility, but I have no way of testing it.
		Alien::Error("This packages uses an unknown compression type, $fields{COMPRESSTYPE}.");
	}
}

1
