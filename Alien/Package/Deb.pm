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

Sets have_dpkg_deb if dpkg-deb is in the path. I prefer to use dpkg-deb,
if it is available since it is a lot more future-proof.

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

=item install

Install a deb with dpkg.

=cut

sub install {
	my $this=shift;

	system("dpkg --no-force-overwrite -i ".$this->filename) &&
		die "Unable to install: $!";
}

=item read_file

Implement the read_file method to read a deb file.

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

	# Parse control file and extract fields. Use a translation table
	# to map between the debian names and the internal field names,
	# which more closely resemble those used by rpm (for historical
	# reasons; TODO: change to deb style names).
	my $description='';
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
			# Handle extended description.
			s/^ //g;
			$_="" if $_ eq ".";
			$description.="$_\n";
		}
	}
	$this->description($description);

	$this->copyright("see /usr/share/doc/".$this->name."/copyright");
	$this->group("unknown") if ! $this->group;
	$this->distribution("Debian");

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

=item package

Set/get package name. 

Always returns the packge name in lowercase with all invalid characters
returned. The name is however, stored unchanged.

=cut

sub name {
	my $this=shift;
	
	# set
	$this->{name} = shift if @_;
	return unless defined wantarray; # optimization
	
	# get
	$_=lc($this->{name});
	tr/_/-/;
	s/[^a-z0-9-\.\+]//g;
	return $_;
}

=item version

Set/get package version.

When the version is set, it will be stripped of any epoch. If there is a
release, the release will be stripped away and used to set the release
field as a side effect. Otherwise, the release will be set to 1.

More sanitization of the version is done when the field is retrieved, to
make sure it is a valid debian version field.

=cut

sub version {
	my $this=shift;

	# set
	if (@_) {
		my $version=shift;
		if ($version =~ /(.+)-(.+)/) {
                	$version=$1;
	                $this->release($2);
	        }
	        else {
	                $this->release(1);
		}
        	# Kill epochs.
		$version=~s/^\d+://;
		
		$this->{version}=$version;
        }
	
	# get
	return unless defined wantarray; # optimization
	$_=$this->{version};
	# Make sure the version contains digets.
	unless (/[0-9]/) {
		# Drat. Well, add some. dpkg-deb won't work
		# # on a version w/o numbers!
		return $_."0";
	}
	return $_;
}

=item release

Set/get package release.

Always returns a sanitized release version. The release is however, stored
unchanged.

=cut

sub release {
	my $this=shift;

	# set
	$this->{release} = shift if @_;

	# get
	return unless defined wantarray; # optimization
	$_=$this->{release};
	# Make sure the release contains digets.
	return $_."-1" unless /[0-9]/;
	return $_;
}

=item description

Set/get description

Although the description is stored internally unchanged, this will always
return a sanitized form of it that is compliant with Debian standards.

=cut

sub description {
	my $this=shift;

	# set
	$this->{description} = shift if @_;

	# get
	return unless defined wantarray; # optimization
	my $ret='';
	foreach (split /\n/,$this->{description}) {
		s/\t/        /g; # change tabs to spaces
		s/\s+$//g; # remove trailing whitespace
		$_="." if $_ eq ''; # empty lines become dots
		$ret.=" $_\n";
	}
	chomp $ret;
	return $ret;
}

=head1 AUTHOR

Joey Hess <joey@kitenet.net>

=cut

1
