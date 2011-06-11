#!/usr/bin/perl -w

=head1 NAME

Alien::Package::Lsb - an object that represents a lsb package

=cut

package Alien::Package::Lsb;
use strict;
use base qw(Alien::Package::Rpm);

=head1 DESCRIPTION

This is an object class that represents a lsb package. It is derived from
Alien::Package::Rpm.

=head1 METHODS

=over 4

=item checkfile

Lsb files are rpm's with a lsb- prefix, that depend on a package called 'lsb'
and nothing else.

=cut

sub checkfile {
	my $this=shift;
	my $file=shift;
	return unless $file =~ m/^lsb-.*\.rpm$/;
	my @deps=$this->runpipe(1, "LANG=C rpm -qp -R '$file'");
	return 1 if grep { s/\s+//g; $_ eq 'lsb' } @deps;
	return;
}

=item scan

Uses the parent scan method to read the file. lsb is added to the depends.

=cut

sub scan {
	my $this=shift;
	$this->SUPER::scan(@_);

	$this->distribution("Linux Standard Base");
	$this->origformat("lsb");
	$this->depends("lsb");
	# Converting from lsb, so the scripts should be portable and safe.
	# Haha.
	$this->usescripts(1);

	return 1;
}

=item prep

The parent's prep method is used to generate the spec file. First though,
the package's name is munged to make it lsb compliant (sorta) and lsb is added
to its dependencies.

=cut

sub prep {
	my $this=shift;
	
	$this->_orig_name($this->name);
	if ($this->name !~ /^lsb-/) {
		$this->name("lsb-".$this->name);
	}
	$this->_orig_depends($this->depends);
	$this->depends("lsb");
	# Always include scripts when generating lsb package.
	$this->_orig_usescripts($this->usescripts);
	$this->usescripts(1);
	
	$this->SUPER::prep(@_);	
}

=item revert

Undo the changes made by prep.

=cut

sub revert {
	my $this=shift;
	$this->name($this->_orig_name);
	$this->depends($this->_orig_depends);
	$this->usescripts($this->_orig_usescripts);
	$this->SUPER::revert(@_);
}


=item build

Uses the parent's build method. If a lsb-rpm is available, uses it to build
the package.

=cut

sub build {
	my $this=shift;
	my $buildcmd=shift || 'rpmbuild';
	foreach (split(/:/,$ENV{PATH})) {
		if (-x "$_/lsb-rpm") {
			$buildcmd='lsb-rpm';
			last;
		}
	}
	$this->SUPER::build($buildcmd);
}

=item incrementrelease

LSB package versions are not changed.

=cut

sub incrementrelease {}

=back

=head1 AUTHOR

Joey Hess <joey@kitenet.net>

=cut

1
