#!/usr/bin/perl
# Becuase .slp files are a binary format we parse by hand, I need to code in
# the details of the structure here.

package slp;

use strict;

# Complete sizeof(slpformat) from slp.h in the stampede package manager source.
$slp::footer_size=3784;

# This is the pack format string for the footer.
# (A=space terminated character, I=unsigned integer.)
$slp::footer_packstring="A756IIIIA128A128A80A1536A512A512A30A30IA20A20III";

# What package format are we up to now? (Lowest one this is still compatable
# with.)
$slp::footer_version=5;

# This is a translation table between architectures and the number
# that represents them in a slp package.
$slp::archtrans={
	0 => 'all',
	1 => 'i386',
	2 => 'sparc',
	3 => 'alpha',
	4 => 'powerpc',
	5 => 'm68k',
};

# This is a translation table between copyrights and the number that
# represents them in a slp package
$slp::copyrighttrans={
	0 => 'GPL',
	1 => 'BSD',
	2 => 'LGPL',
	3 => 'unknown',
	254 => 'unknown',
};

1
