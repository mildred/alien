#!/usr/bin/perl
#
# Package for converting from a .deb file.

package From::deb;

use strict;

# Global variable initialization.

# This is set to 1 if dpkg-deb is in the path.
my $dpkg_deb=undef;
my $dir;
foreach $dir (split(/:/,$ENV{PATH})) {
  if (-x "$dir/dpkg-deb") {
    $dpkg_deb=1;
    last;
  }
}

# Query a deb file for fields, and return a hash of the fields found.
# Pass the filename of the deb file to query.
sub GetFields { my ($self,$file)=@_;
	my %fields;
	
	# Extract the control file from the deb file.
	my @control;
	if ($dpkg_deb) {
		@control = `dpkg-deb --info $file control`;
	}
	else {
		@control = `ar p $file control.tar.gz | tar Oxzf - control`;
	}

	# Parse control file and extract fields.
	my $i=0;
	while ($i<=$#control) {
		$_ = $control[$i];
		chomp;
		$fields{NAME} = $1 if (/^Package:\s*(.+)/i);
		$fields{VERSION} = $1 if (/^Version:\s*(.+)/i);
		$fields{ARCH} = $1 if (/^Architecture:\s*(.+)/i);
		$fields{MAINTAINER} = $1 if (/^Maintainer:\s*(.+)/i);
		$fields{DEPENDS} = $1 if (/^Depends:\s*(.+)/i);
		$fields{REQUIRES} = $1 if (/^Requires:\s*(.+)/i);
		$fields{GROUP} = $1 if (/^Section:\s*(.+)/i);
		if (/^Description:\s*(.+)/i) {
			$fields{SUMMARY} = "$1";
			$i++;
				while (($i<=$#control) && ($control[$i])) {
				$control[$i] =~ s/^ //g; #remove leading space
				$control[$i] = "\n" if ($control[$i] eq ".\n");
				$fields{DESCRIPTION}.=$control[$i];
				$i++;
			}
			$i--;
		}
		$i++;
	}

	$fields{COPYRIGHT}="see /usr/share/doc/$fields{NAME}/copyright";
	$fields{GROUP}="unknown" if (!$fields{GROUP});
	$fields{DISTRIBUTION}="Debian";
	if ($fields{VERSION} =~ /(.+)-(.+)/) {
		$fields{VERSION} = $1;
		$fields{RELEASE} = $2;
	} else {
		$fields{RELEASE} = '1';
	}
	# Just get rid of epochs for now.
	if ($fields{VERSION} =~ /\d+:(.*)/) { 
		$fields{VERSION} = $1;
	}

	# Read in the list of conffiles, if any.
	if ($dpkg_deb) {
		$fields{CONFFILES}=`dpkg-deb --info $file conffiles 2>/dev/null`;
	}
	else {
		$fields{CONFFILES}=
			`ar p $file control.tar.gz | tar Oxzf - conffiles 2>/dev/null`;
	}

	# Read in the list of all files.
	# Note that tar doesn't supply a leading `/', so we have to add that.
	$fields{FILELIST}=undef;
	if ($dpkg_deb) {
		my $fn;
		foreach $fn (`dpkg-deb --fsys-tarfile $file | tar tf -`) {
			$fields{FILELIST}.="/$fn";
		}
	}
	else {
		my $fn;
		foreach $fn (`ar p $file data.tar.gz | tar tzf -`) {
			$fields{FILELIST}.="/$fn";
		}
	}

	if ($main::scripts) {
		# Read in the scripts, if any.
		my $field;
		for $field ('postinst', 'postrm', 'preinst', 'prerm') {
			if ($dpkg_deb) {
				$fields{uc($field)}=`dpkg-deb --info $file $field 2>/dev/null`;
			}
			else {
				$fields{uc($field)}=
					`ar p $file control.tar.gz | tar Oxzf - $field 2>/dev/null`;
			}
		}
	}

	$fields{RELEASE}++ unless $main::keep_version;

	return %fields;
}

# Handles unpacking of debs.
sub Unpack { my ($self,$file,%fields)=@_;
	if ($dpkg_deb) {
		Alien::SafeSystem ("(cd ..;dpkg-deb -x $file $fields{NAME}-$fields{VERSION})",
			"Error unpacking $file\n");
	}
	else {
		Alien::SafeSystem ("(cd ..;ar p $file data.tar.gz) | tar zxpf -",
			"Error unpacking $file\n");
	}
}

1
