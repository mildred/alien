#!/usr/bin/perl -w

=head1 NAME

Alien::Package::Slp - an object that represents a slp package

=cut

package Alien::Package::Deb;
use strict;
use Alien::Package; # perlbug
use base qw(Alien::Package);

=head1 DESCRIPTION

This is an object class that represents a slp package. It is derived from
Alien::Package.

=head1 CLASS DATA

The following data is global to the class, and is used to describe the slp
package format, which this class processes directly.

=over 4

=item footer_size

Complete sizeof(slpformat) from slp.h in the stampede package manager
source.

=item footer_packstring

This is the pack format string for the footer. (A=space terminated
character, I=unsigned integer.)

=item footer_version

What package format are we up to now? (Lowest one this is still
compatable with.)

=item archtrans

This is a translation table between architectures and the number
that represents them in a slp package.

=cut

use constant footer_size => 3784,
	footer_packstring => "A756IIIIA128A128A80A1536A512A512A30A30IA20A20III",
	footer_version => 5,
	archtrans => {
		0 => 'all',
		1 => 'i386',
		2 => 'sparc',
		3 => 'alpha',
		4 => 'powerpc',
		5 => 'm68k',
	},
	copyrighttrans => {
		0 => 'GPL',
		1 => 'BSD',
		2 => 'LGPL',
		3 => 'unknown',
		254 => 'unknown',
	};

=back

=head1 FIELDS

=over 4

=head1 METHODS

=over 4

=item install

Install a slp. Pass in the filename of the slp to install.

=cut

sub install {
	my $this=shift;
	my $slp=shift;

}

=item scan

Implement the scan method to read a slp file.

=cut

sub scan {
	my $this=shift;
	$this->SUPER::scan(@_);
	my $file=$this->filename;


	return 1;
}

=item unpack

Implment the unpack method to unpack a slp file.

=cut

sub unpack {
	my $this=shift;
	$this->SUPER::unpack(@_);
	my $file=$this->filename;


	return 1;
}

=item prep

No prep stage is needed for slp files.

=cut

sub prep {
	my $this=shift;
	my $dir=$this->unpacked_tree || die "The package must be unpacked first!";
}

=item build

Build a slp.

=cut

sub build {
	my $this=shift;

	return # filename
}

=head1 AUTHOR

Joey Hess <joey@kitenet.net>

=cut

1
