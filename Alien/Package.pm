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
a class derived from this one, such as Alien::Package::Rpm Feed the object
a rpm file, thus populating all of its fields. Then rebless the object into
the destination class, such as Alien::Package::Deb. Finally, ask the object
to build a package, and the package has been converted.

=head1 FIELDS

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

The package's dependancies.

=item group

The section the package is in.

=item summary

A one line description of the package.

=item description

A longer description of the package. May contain multiple paragraphs.

=item copyright

A short statement of copyright.

=item distribution

What distribution family the package originated from.

=item conffiles

A reference to a list of all the conffiles in the package.

=item files

A reference to a list of all the files in the package.

=item postinst

The postinst script of the package.

=item postrm

The postrm script of the package.

=item preinst

The preinst script of the package.

=item prerm

The prerm script of the package.

=item unpacked_tree

Points to a directory where the package has been unpacked.

=item filename

The filename of the package the object represents.

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
	my $this=bless ({@_}, $class);
	$this->init;
	return $this;
}

=item init

This is called by new(). It's a handy place to set fields, etc, without
having to write your own new() method.

=cut

sub init {}

=item read_file

This method looks at the actual package file the package represents, and
populates all the fields it can from that package file. The filename field
should already be set before this method is called.

(This is just a stub; child classes should override it to actually do
something.)

=cut

sub read_file {
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
	mkdir $workdir, 0755 ||
		die "unable to mkdir $workdir: $!";
	$this->unpacked_tree($workdir);
}

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
	system ('rm', '-rf', $this->unpacked_tree) &&
		die "unable to delete temporary directory `".$this->unpacked_tree."`: $!";
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
