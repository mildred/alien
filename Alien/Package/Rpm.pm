#!/usr/bin/perl -w

=head1 NAME

Alien::Package::Rpm - an object that represents a rpm package

=cut

package Alien::Package::Rpm;
use strict;
use Alien::Package; # perlbug
use base qw(Alien::Package);

=head1 DESCRIPTION

This is an object class that represents a rpm package. It is derived from
Alien::Package.

=head1 FIELDS

=over 4

=item prefixes

Relocatable rpm packages have a prefixes field.

=item changelogtext

The text of the changelog

=head1 METHODS

=over 4

=item read_file

Implement the read_file method to read a rpm file.

=cut

sub read_file {
	my $this=shift;
	$this->SUPER::read_file(@_);
	my $file=$this->filename;

	my %fieldtrans=(
		PREIN => 'preinst',
		POSTIN => 'postinst',
		PREUN => 'prerm',
		POSTUN => 'postrm',
	);

	# These fields need no translation except case.
	foreach (qw{name version release arch changelogtext summary
		    description copyright prefixes}) {
		$fieldtrans{uc $_}=$_;
	}

	# Use --queryformat to pull out all the fields we need.
	foreach my $field (keys(%fieldtrans)) {
		$_=`LANG=C rpm -qp $file --queryformat \%{$field}`;
		$field=$fieldtrans{$field};
		$this->$field($_) if $_ ne '(none)';
	}

	# Fix up the scripts - they are always shell scripts, so make them so.
	foreach my $field (qw{preinst postinst prerm postrm}) {
		$this->$field("$!/bin/sh\n".$this->field);
	}

	# Get the conffiles list.
	$this->conffiles([map { chomp; $_ } `rpm -qcp $file`]);

	$this->copyright_extra(scalar `rpm -qpi $file`);

	# Get the filelist.
	$this->filelist([map { chomp; $_ } `rpm -qpl $file`]);

	# Sanity check and sanitize fields.
	unless (defined $this->summary) {
		# Older rpms will have no summary, but will have a
		# description. We'll take the 1st line out of the
		# description, and use it for the summary.
		$this->summary($this->description."\n")=~m/(.*?)\n/m;

		# Fallback.
		if (! $this->summary) {
			$this->summary('Converted RPM package');
		}
	}
	unless (defined $this->copyright) {
		$this->copyright('unknown');
	}
	unless (defined $this->description) {
		$this->description($this->summary);
	}
	if (! defined $this->release || ! defined $this->version || 
	    ! defined $this->name) {
		die "Error querying rpm file";
	}

	$this->distribution("Red Hat");

	return 1;
}

=item arch

Set/get arch field. When the arch field is set, some sanitizing is done
first.

=cut

sub arch {
	my $this=shift;
	return $this->{arch} unless @_;
	my $arch=shift;

	if ($arch eq 1) {
		$arch='i386';
	}
	elsif ($arch eq 2) {
		$arch='alpha';
	}
	elsif ($arch eq 3) {
		$arch='sparc';
	}
	elsif ($arch eq 6) {
		$arch='m68k';
	}
	elsif ($arch eq 'noarch') {
		$arch='all';
	}
	elsif ($arch eq 'ppc') {
		$arch='powerpc';
	}
	
	# Treat 486, 586, etc, as 386.
	if ($arch =~ m/i\d86/) {
		$arch='i386';
	}
	
	return $this->{arch}=$arch;
}

=back

=head1 AUTHOR

Joey Hess <joey@kitenet.net>

=cut

1
