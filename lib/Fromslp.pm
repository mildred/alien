#!/usr/bin/perl
#
# Package for converting from a .slp (Stampede) file.

package From::slp;

use strict;

# Becuase .slp files are a binary format we parse by hand, I need to code in
# the details of the structure here.

	# Complete sizeof(slpformat) from slp.h in the stampede package manager source.
	$From::slp::footer_size=3784;

	# This is the pack format string for the footer.
	$From::slp::footer_packstring="A756IIIIA128A128A80A1536A512A512A30A30IA20A20III";

	# What package format are we up to now? (Lowest one this is still compatable
	# with.)
	$From::slp::footer_version=5;

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
	)=unpack($From::slp::footer_packstring,$footer);

	# A simple sanity check.
	if (! $fields{SLPKGVERSION} || $fields{SLPKGVERSION} < $From::slp::footer_version) {
		Alien::Error("This is not a V$From::slp::footer_version or greater Stampede package");
	}

	return %fields;
}

# Pass it a filename of a .slp file, it will pull out a footer and return it
# in a scalar.
sub GetFooter { my ($filename)=@_;
	open (SLP,"<$filename") || Alien::Error("unable to read $filename: $!");
	seek SLP,(-1 * $From::slp::footer_size),2; # position at beginning of footer (2 = seek from EOF)
	read SLP,$_,$From::slp::footer_size;
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

	if ($fields{COPYRIGHT} == 0) {
		$fields{COPYRIGHT}="GPL";
	}
	elsif ($fields{COPYRIGHT} == 1) {
		$fields{COPYRIGHT}="BSD";
	}
	elsif ($fields{COPYRIGHT} == 2) {
		$fields{COPYRIGHT}="LGPL";
	}
	elsif ($fields{COPYRIGHT} == 3) {
		$fields{COPYRIGHT}="unknown";
	}
	else {
		Alien::Warning("I don't know what copyright type \"$fields{COPYRIGHT}\" is.");
		$fields{COPYRIGHT}="unknown";
	}

	if ($fields{ARCH} == 0) {
		$fields{ARCH}='all';		
	}
	elsif ($fields{ARCH} == 1) {
		$fields{ARCH}='i386';
	}
	elsif ($fields{ARCH} == 2) {
		$fields{ARCH}='sparc';
	}
	elsif ($fields{ARCH} == 3) {
		$fields{ARCH}='alpha';
	}
	elsif ($fields{ARCH} == 4) {
		$fields{ARCH}='powerpc';
	}
	elsif ($fields{ARCH} == 5) {
		$fields{ARCH}='m68k';
	}
	else {
		Alien::Error("An unknown architecture of \"$fields{ARCH}\" was specified.");
	}

	$fields{RELEASE}++ unless $main::keep_version;
	$fields{DISTRIBUTION}="Stampede";

	# Read in the list of all files.
	# Note that they will have a leading "." we don't want.
	$fields{FILELIST}=undef;
	my $fn;
	foreach $fn (`tar -Itf $file`) {
		$fn=~s/^\.//;
		$fields{FILELIST}.="$fn\n";
	}

	# TODO: read in postinst script.

	return %fields;
}

# Unpack a slp file.
sub Unpack { my ($self,$file,%fields)=@_;
	# Note it's a .tar.bz2, this the -I
	Alien::SafeSystem ("(cd ..;cat $file) | tar Ixpf -","Error unpacking $file\n");
}

1
