#!/usr/bin/perl -w

=head1 NAME

Alien::Package::Deb - an object that represents a deb package

=cut

package Alien::Package::Deb;
use strict;
use Alien::Package; # perlbug
use base qw(Alien::Package);

=head1 DESCRIPTION

This is an object class that represents a deb package. It is derived from
Alien::Package.

=head1 FIELDS

=over 4

=item have_dpkg_deb

Set to a true value if dpkg-deb is available.

=back

=head1 METHODS

=over 4

=item init

Sets have_dpkg_deb if dpkg-deb is in the path.

=cut

sub init {
	my $this=shift;
	$this->SUPER::init(@_);

	$this->have_dpkg_deb('');
	foreach (split(/:/,$ENV{PATH})) {
		if (-x "$_/dpkg-deb") {
			$this->have_dpkg_deb(1);
			last;
		}
	}
}

=item read_file

Implement the read_file method to read a deb file.

This uses either dpkg-deb, if it is present, or ar and tar if it is not.
Using dpkg-deb is a lot more future-proof, but the system may not have it.

=cut

sub read_file {
	my $this=shift;
	$this->SUPER::read_file(@_);
	my $file=$this->filename;

	# Extract the control file from the deb file.
	my @control;
	if ($this->have_dpkg_deb) {
		@control = `dpkg-deb --info $file control`;
	}
	else {
		# It can have one of two names, depending on the tar
		# version the .deb was built from.
		@control = `ar p $file control.tar.gz | tar Oxzf - control [./]control`;
	}

	# Parse control file and extract fields.
	my $field;
	my %fieldtrans=(
		Package => 'name',
		Version => 'version',
		Architecture => 'arch',
		Maintainer => 'maintainer',
		Depends => 'depends',
		Section => 'group',
		Description => 'summary',
	);
	for (my $i=0; $i <= $#control; $i++) {
		$_ = $control[$i];
		chomp;
		if (/^(\w.*?):\s+(.*)/) {
			$field=$1;
			if (exists $fieldtrans{$field}) {
				$field=$fieldtrans{$field};
				$this->$field($2);
			}
		}
		elsif (/^ / && $field eq 'summary') {
			# Handle xtended description.
			s/^ //g;
			$_="" if $_ eq ".";
			$this->description($this->description . $_. "\n");
		}
	}

	$this->copyright("see /usr/share/doc/".$this->name."/copyright");
	$this->group("unknown") if ! $this->group;
	$this->distribution("Debian");
	if ($this->version =~ /(.+)-(.+)/) {
		$this->version($1);
		$this->release($2);
	}
	else {
		$this->release(1);
	}
	# Kill epochs.
	if ($this->version =~ /\d+:(.*)/) {
		$this->version($1);
	}

	# Read in the list of conffiles, if any.
	my @conffiles;
	if ($this->have_dpkg_deb) {
		@conffiles=map { chomp; $_ }
			   `dpkg-deb --info $file conffiles 2>/dev/null`;
	}
	else {
		@conffiles=map { chomp; $_ }
			   `ar p $file control.tar.gz | tar Oxzf - conffiles 2>/dev/null`;
	}
	$this->conffiles(\@conffiles);

	# Read in the list of all files.
	# Note that tar doesn't supply a leading `/', so we have to add that.
	my @filelist;
	if ($this->have_dpkg_deb) {
		@filelist=map { chomp; s:\./::; "/$_" }
			  `dpkg-deb --fsys-tarfile $file | tar tf -`;
	}
	else {
		@filelist=map { chomp; s:\./::; "/$_" }
			  `ar p $file data.tar.gz | tar tzf -`;
	}
	$this->filelist(\@filelist);

	# Read in the scripts, if any.
	foreach my $field (qw{postinst postrm preinst prerm}) {
		if ($this->have_dpkg_deb) {
			$this->$field(`dpkg-deb --info $file $field 2>/dev/null`);
		}
		else {
			$this->$field(`ar p $file control.tar.gz | tar Oxzf - $field 2>/dev/null`);
		}
	}

	return 1;
}

=item unpack

Implment the unpack method to unpack a deb file.

=cut

sub unpack {
	my $this=shift;
	$this->SUPER::unpack(@_);
	my $file=$this->filename;

	if ($this->have_dpkg_deb) {
		system("dpkg-deb -x $file ".$this->unpacked_tree) &&
			die "Unpacking of `$file' failed: $!";
	}
	else {
		system ("ar p $file data.tar.gz | (cd ".$this->unpacked_tree."; tar zxpf -)") &&
			die "Unpacking of `$file' failed: $!";
	}

	return 1;
}

=back

=head1 AUTHOR

Joey Hess <joey@kitenet.net>

=cut

1
