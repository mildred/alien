#!/usr/bin/perl -w

=head1 NAME

Alien::Package::Slp - an object that represents a slp package

=cut

package Alien::Package::Slp;
use strict;
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

use constant footer_size => 3784;
use constant footer_packstring => "A756IIIIA128A128A80A1536A512A512A30A30IA20A20III";
use constant footer_version => 5;
use constant archtrans => {
		0 => 'all',
		1 => 'i386',
		2 => 'sparc',
		3 => 'alpha',
		4 => 'powerpc',
		5 => 'm68k',
	};
use constant copyrighttrans => {
		0 => 'GPL',
		1 => 'BSD',
		2 => 'LGPL',
		3 => 'unknown',
		254 => 'unknown',
	};
use constant fieldlist => [qw{conffiles priority compresstype release copyright
			      conflicts setupscript summary description depends
			      provides maintainer date compiler version name
			      arch group slpkgversion}];

=back

=head1 FIELDS

=over 4

=item compresstype

Holds the compression type used in the slp file.

=item slpkgversion

Holds the slp package format version of the slp file.

=back

=head1 METHODS

=over 4

=item checkfile

Detect slp files by their extention.

=cut

sub checkfile {
        my $this=shift;
        my $file=shift;

        return $file =~ m/.*\.slp$/;
}

=item install

Install a slp. Pass in the filename of the slp to install.

=cut

sub install {
	my $this=shift;
	my $slp=shift;

	my $v=$Alien::Package::verbose;
	$Alien::Package::verbose=2;
	$this->do("slpi", $slp)
		or die "Unable to install";
	$Alien::Package::verbose=$v;
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
	my @values=unpack(footer_packstring(),$this->getfooter);
	# Populate fields.
	foreach my $field (@{fieldlist()}) {
		$_=shift @values;
		$this->$field($_);
	}

	# A simple sanity check.
	if (! defined $this->slpkgversion || $this->slpkgversion < footer_version()) {
		die "unsupported stampede package version";
	}

	# Read in the file list.
	my @filelist;
	# FIXME: support gzip files too!
	foreach ($this->runpipe(0, "bzip2 -d < '$file' | tar -tf -")) {
		chomp;
		s:^\./:/:;
		$_="/$_" unless m:^/:;
		push @filelist, $_;
	}
	$this->filelist(\@filelist);

	# TODO: read in postinst script.

	$this->distribution('Stampede');
	$this->origformat('slp');
	$this->changelogtext('');
	$this->binary_info($this->runpipe(0, "ls -l '$file'"));
	
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
		$this->do("bzip2 -d < $file | (cd ".$this->unpacked_tree."; tar xpf -)")
	}
	elsif ($compresstype == 1) {
		$this->do("gzip -dc $file | (cd ".$this->unpacked_tree."; tar xpf -)")
	}
	else {
		die "package uses an unknown compression type, $compresstype (please file a bug report)";
	}

	return 1;
}

=item build

Build a slp.

=cut

sub build {
	my $this=shift;
	my $slp=$this->name."-".$this->version.".slp";
	
	# Now generate the footer.
	# We cannot use the actual $slp::footer_packstring, becuase it uses
	# space terminated strings (A) instead of null terminated strings
	# (a). That is good for decoding, but not for encoding.
	my $fmt=footer_packstring();
	$fmt=~tr/A/a/;
	my $footer=pack($fmt,
		$this->conffiles,
		2, # Use priority optional for alien packages.
		0, # Always use bzip2 as the compression type.
		$this->release,
		254, # Don't try to guess copyright, just use unknown.
		'', # Conflicts.
		'', # Set up script. TODO
		$this->summary,
		$this->description,
		'', # $this->depends would go here, but slp uses some weird format
		'', # Provides.
		$this->maintainer,
		scalar localtime, # Use current date.
		252, # Unknown compiler.
		$this->version,
		$this->name,
		$this->arch,
		252, # Unknown group.
		footer_version(),
	);

	# Generate .tar.bz2 file.
	# Note that it's important I use "./*" instead of just "." or
	# something like that, becuase it results in a tar file where all
	# the files in it start with "./", which is consitent with how
	# normal stampede files look.
	$this->do("(cd ".$this->unpacked_tree."; tar cf - ./*) | bzip2 - > $slp")
		or die "package build failed: $!";

	# Now append the footer.
	open (OUT,">>$slp") || die "$slp: $!";
	print OUT $footer;
	close OUT;

	return $slp;
}

=item conffiles

Set/get conffiles.

When the conffiles are set, the format used by slp (a colon-delimited list)
is turned into the real list that is used internally. The list is changed
back into slp's internal format when it is retreived.

=cut

sub conffiles {
	my $this=shift;

	# set
	$this->{conffiles}=[split /:/, shift] if @_;

	# get
	return unless defined wantarray; # optimization
	return join(':',@{$this->{conffiles}});
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
	$this->{copyright}=(${copyrighttrans()}{shift} || 'unknown') if @_;
	
	# get
	return unless defined wantarray; # optimization
	my %transcopyright=reverse %{copyrighttrans()};
	return $transcopyright{$this->{copyright}}
		if (exists $transcopyright{$this->{copyright}});
	return 254; # unknown
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
		my $arch=shift;
		$this->{arch}=${archtrans()}{$arch};
		die "unknown architecture $arch" unless defined $this->{arch};
	}

	# get
	return unless defined wantarray; # optimization
	my %transarch=reverse %{archtrans()};
	return $transarch{$this->{arch}}
		if (exists $transarch{$this->{arch}});
	die "Stampede does not support architecture ".$this->{arch}." packages";
}

=item release

Set/get release version.

When the release version is retreived, it is converted to an unsigned
integer, as is required by the slp package format.

=cut

sub release {
	my $this=shift;

	# set
	$this->{release}=shift if @_;

	# get
	return unless defined wantarray; # optimization
	return int($this->{release});
}


=back

=head1 AUTHOR

Joey Hess <joey@kitenet.net>

=cut

1
