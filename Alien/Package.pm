#!/usr/bin/perl -w

=head1 NAME

Alien::Package - an object that represents a package

=cut

package Alien::Package;
use strict;
use vars qw($AUTOLOAD);

=head1 DESCRIPTION

This is a perl object class that represents a package in an internal format
usable by alien. The package may be a deb, a rpm, a tgz, or a slp package,
etc. Objects in this class hold various fields of metadata from the actual
packages they represent, as well as some fields pointing to the actual
contents of the package. They can also examine an actual package on disk,
and populate those fields. And they can build the actual package using the
data stored in the fields.

A typical use of this object class will be to instantiate an object from
a class derived from this one, such as Alien::Package::Rpm. Feed the object
a rpm file, thus populating all of its fields. Then rebless the object into
the destination class, such as Alien::Package::Deb. Finally, ask the object
to build a package, and the package has been converted.

=head1 FIELDS

These fields are of course really just methods that all act similarly;
allowing a value to be passed in to set them, or simply returning the value
of the field if nothing is passed in. Child classes may override these
fields to process input data, or to format output data. The general rule is
that input data is modified to get things into a package-independant form,
which is how the data is stored in the fields. When the value of a field is
read, it too may be modified before it is returned, to change things into a
form more suitable for the particular type of package.

=over 4

=item name

The package's name.

=item version

The package's upstream version.

=item release

The package's distribution specific release number.

=item arch

The package's architecture, in the format used by Debian.

=item maintainer

The package's maintainer.

=item depends

The package's dependancies. Only dependencies that should exist on all
target distributions can be put in here though (ie: lsb).

=item group

The section the package is in.

=item summary

A one line description of the package.

=item description

A longer description of the package. May contain multiple paragraphs.

=item copyright

A short statement of copyright.

=item origformat

What format the package was originally in.

=item distribution

What distribution family the package originated from.

=item binary_info

Whatever the package's package tool says when told to display info about
the package.

=item conffiles

A reference to a list of all the conffiles in the package.

=item files

A reference to a list of all the files in the package.

=item changelogtext

The text of the changelog

=item postinst

The postinst script of the package.

=item postrm

The postrm script of the package.

=item preinst

The preinst script of the package.

=item prerm

The prerm script of the package.

=item usescripts

Only use the above scripts fields when generating the package if this is set
to a true value.

=item unpacked_tree

Points to a directory where the package has been unpacked.

=item owninfo

If set this will be a reference to a hash, with filename as key, that holds
ownership/group information for files that cannot be represented on the
filesystem. Typically that is because the owners or groups just don't exist
yet. It will be set at unpack time.

=back

=head1 METHODS

=over 4

=item new

Returns a new object of this class. Optionally, you can pass in named
parameters that specify the values of any fields in the class.

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $this=bless ({}, $class);
	$this->init;
	$this->$_(shift) while $_=shift; # run named parameters as methods
	return $this;
}

=item init

This is called by new(). It's a handy place to set fields, etc, without
having to write your own new() method.

=cut

sub init {}

=item checkfile

This is a class method. Pass it a filename, and it will return true if it
looks like the file is a package of the type handled by the class.

=cut

sub checkfile {
	my $this=shift;
	my $file=shift;

	return ''; # children override this.
}

=item install

Simply installs a package file. The filename is passed.
This has to be overridden in child classes.

=cut

sub install {
	my $this=shift;
}

=item test

Test a package file. The filename is passed, should return an array of lines
of test results. Child classses may implement this.

=cut

sub test {
	my $this=shift;
	return;
}

=item filename

Set/get the filename of the package the object represents.

When it is set, it performs a scan of the file, populating most other
fields with data from it.

(This is just a stub; child classes should override it to actually do
something.)

=cut

sub filename {
	my $this=shift;

	# set
	if (@_) {
		$this->{filename} = shift;
		$this->scan;
	}

	return $this->{filename};
}

=item scan

This method scans the file associated with an object, and populates as many
other fields as it can with data from it.

=cut

sub scan {
	my $this=shift;
	my $file=$this->filename;

	if (! -e $file) {
		die "`$file' does not exist; cannot read.";
	}
}

=item unpack

This method unpacks the package into a temporary directory. It sets
unpacked_tree to point to that directory.

(This is just a stub method that makes a directory below the current
working directory, and sets unpacked_tree to point to it. It should be
overridden by child classes to actually unpack the package as well.)

=cut

sub unpack {
	my $this=shift;
	
	my $workdir = $this->name."-".$this->version;
	mkdir($workdir, 0755) ||
		die "unable to mkdir $workdir: $!";
	# If the parent directory is suid/sgid, mkdir will make the root
	# directory of the package inherit those bits. That is a bad thing,
	# so explicitly force perms to 755.
	chmod 0755, $workdir;
	$this->unpacked_tree($workdir);
}

=item prep

This method causes the object to prepare a build tree to be used in
building the object. It expects that the unpack method has already been
called. It takes the tree generated by that method, and mangles it somehow,
to produce a suitable build tree.

(This is just a stub method that all child classes should override.)

=cut

sub prep {}

=item cleantree

This method should clean the unpacked_tree of any effects the prep and
build methods might have on it.

=cut

sub cleantree {}

=item revert

This method should ensure that the object is in the same state it was in
before the prep method was called.

=cut

sub revert {}

=item build

This method takes a prepped build tree, and simply builds a package from
it. It should put the package in the current directory, and should return
the filename of the generated package.

(This is just a stub method that all child classes should override.)

=cut

sub build {}

=item DESTROY

When an object is destroyed, it cleans some stuff up. In particular, if the
package was unpacked, it is time now to wipe out the temporary directory.

=cut

sub DESTROY {
	my $this=shift;

	return if (! defined $this->unpacked_tree || $this->unpacked_tree eq '');
	# This should never happen, but it pays to check.
	if ($this->unpacked_tree eq '/') {
		die "alien internal error: unpacked_tree is set to `/'. Please file a bug report!";
	}
	(system('rm', '-rf', $this->unpacked_tree) == 0)
		or die "unable to delete temporary directory `".$this->unpacked_tree."`: $!";
	$this->unpacked_tree('');	
}

=item AUTOLOAD

Handles all fields, by creating accessor methods for them the first time
they are accessed.

=cut

sub AUTOLOAD {
	my $field;
	($field = $AUTOLOAD) =~ s/.*://;

	no strict 'refs';
	*$AUTOLOAD = sub {
		my $this=shift;

		return $this->{$field} unless @_;
		return $this->{$field}=shift;
	};
	goto &$AUTOLOAD;
}

=back

=head1 AUTHOR

Joey Hess <joey@kitenet.net>

=cut

1
