#!/usr/bin/perl
#
# Package for converting from a .deb file.

# Query a deb file for fields, and return a hash of the fields found.
# Pass the filename of the deb file to query.
sub GetFields { my $file=shift;
	my %fields;
	
	# Extract the control file from the deb file.
	my @control = `ar p $file control.tar.gz | tar Oxzf - control`;

	# Parse control file and extract fields.
	my $i=0;
	while ($i<=$#control) {
		$_ = $control[$i];
		chomp;
		$fields{NAME} = $1 if (/^Package: (.+)/i);
		$fields{VERSION} = $1 if (/^Version: (.+)/i);
		$fields{ARCH} = $1 if (/^Architecture: (.+)/i);
		$fields{MAINTAINER} = $1 if (/^Maintainer: (.+)/i);
		$fields{DEPENDS} = $1 if (/^Depends: (.+)/i);
		$fields{REQUIRES} = $1 if (/^Requires: (.+)/i);
		$fields{GROUP} = $1 if (/^Section: (.+)/i);
		if (/^Description: (.+)/i) {
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

	$fields{COPYRIGHT}="see /usr/doc/$fields{NAME}/copyright";
	$fields{GROUP}="unknown" if (!$fields{GROUP});
	$fields{DISTRIBUTION}="Debian";
	if ($fields{VERSION} =~ /(.+)-(.+)/) {
		$fields{VERSION} = $1;
		$fields{RELEASE} = $2 + 1;
	} else {
		$fields{RELEASE} = '1';
	}

	# Read in the list of conffiles, if any.
	$fields{CONFFILES}=`ar p $file control.tar.gz | tar Oxzf - conffiles 2>/dev/null`;

	# Read in the list of all files.
	# Note that tar doesn't supply a leading `/', so we have to add that.
	$fields{FILELIST}=undef;
	foreach $fn (`ar p $file data.tar.gz | tar tzf -`) {
		$fields{FILELIST}.="/$fn";
	}

	return %fields;
}

# Handles unpacking of debs.
sub Unpack { my ($file)=@_;
	SafeSystem ("(cd ..;ar p $file data.tar.gz) | tar zxpf -","Error unpacking $file\n");
}

1
