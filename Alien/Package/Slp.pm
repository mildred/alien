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

=item fieldlist

This is a list of all the fields in the order they appear in the footer.

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
	},
	fieldlist => [qw{conffiles priority compresstype release copyright
			 conflicts setupscript summary description depends
			 provides author date compiler version name arch
			 group slpkgversion}];

=back

=head1 FIELDS

=over 4

=item compresstype

Holds the compression type used in the slp file.

=item slpkgversion

Holds the slp package format version of the slp file.

=item 

=head1 METHODS

=over 4

=item install

Install a slp. Pass in the filename of the slp to install.

=cut

sub install {
	my $this=shift;
	my $slp=shift;

}

=item getfooter

Pulls the footer out of the slp file and returns it.

=cut

sub getfooter {
	my $this=shift;
	my $file=$this->filename;

	open (SLP,"<$file") || die "$file: $!";
	# position at beginning of footer (2 = seek from EOF)
	seek SLP,(- footer_size),2;
	read SLP,$_,footer_size;
	close SLP;
	return $_;
}

=item scan

Implement the scan method to read a slp file.

=cut

sub scan {
	my $this=shift;
	$this->SUPER::scan(@_);
	my $file=$this->filename;

	# Decode the footer.
	my @values=unpack(footer_packstring,$this->getfooter);
	# Populate fields.
	foreach my $field (@{fieldlist}) {
		$_=shift @values;
		$this->$field($_);
	}

	# A simple sanity check.
	if (! defined $this->slpkgversion || $this->slpkgversion < footer_version) {
		die "unsupported stampede package version";
	}

	# Read in the file list.
	my @filelist;
	# FIXME: support gzip files too!
	foreach (`bzip2 -d < $file | tar -tf -`) {
		s:^\./:/:;
		$_="/$_" unless m:^/:;
		push @filelist, $fn;
	}

	# TODO: read in postinst script.

	$this->distribution('Stampede');
	$this->origformat('slp');
	
	return 1;
}

=item unpack

Unpack a slp file. They can be compressed in various ways, depending on
what is in the compresstype field.

=cut

sub unpack {
	my $this=shift;
	$this->SUPER::unpack(@_);
	my $file=$this->filename;
	my $compresstype=$this->compresstype;

	if ($compresstype == 0) {
		system("bzip2 -d $file | (cd ".$this->unpacked_tree."; tar xpf -") &&
			die "unpack failed: $!";
	}
	elsif ($compresstype == 1) {
		system("cat $file | (cd ".$this->unpacked_tree."; tar zxpf -") &&
			die "unpack failed: $!";
	}
	else {
		die "package uses an unknown compression type, $compresstype (please file a bug report)";
	}

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

=item conffiles

Set/get conffiles.

When the conffiles are set, the format used by slp (a colon-delimited list)
is turned into the real list that is used internally.

=cut

sub conffiles {
	my $this=shift;

	# set
	$this->{conffiles}=[split /:/, shift]; if @_;

	# get
	return unless defined wantarray; # optimization
	return $this->{conffiles};
}

=item copyright

Set/get copyright.

When the copyright is set, the number used by slp is changed into a textual
description. This is changed back into a number when the value is
retreived.

=cut

sub copyright {
	my $this=shift;

	# set
	$this->{copyright}=(${copyrighttrans}{shift} || 'unknown') if @_;
	
	# get
	return unless defined wantarray; # optimization
	return $this->{copyright};
}

=item arch

Set/get arch.

When the arch is set, the number used by slp is changed into a textual
description. This is changed back into a number when the value is
retreived.

=cut

sub arch {
	my $this=shift;

	# set
	if (@_) {
		$this->{arch}=(${archtrans}{shift};
		die "unknown architecture" if ! $this->{arch};
	}

	# get
	return unless defined wantarray; # optimization
	return $this->{arch};
}

=head1 AUTHOR

Joey Hess <joey@kitenet.net>

=cut

1
