#!/usr/bin/perl
#
# Package for converting from a .rpm file.

# Query a rpm file for fields, and return a hash of the fields found.
# Pass the filename of the rpm file to query.
sub GetFields { my $file=shift;
	my %fields;

	# Use --queryformat to pull out all the fields we need.
	foreach $field ('NAME','VERSION','RELEASE','ARCH','CHANGELOGTEXT',
	                'SUMMARY','DESCRIPTION','COPYRIGHT') {
		$_=`rpm -qp $file --queryformat \%{$field}`;
		$fields{$field}=$_ if $_ ne '(none)';
	}

	# Get the conffiles list.
	$fields{CONFFILES}=`rpm -qcp $file`;

	# Include the output of rpm -qi in the copyright file.
	$fields{COPYRIGHT_EXTRA}=`rpm -qpi $file`;

	# Sanity check fields.
	if (!$fields{SUMMARY}) {
		# Older rpms will have no summary, but will have a 
		# description. We'll take the 1st line out of the 
		# description, and use it for the summary.
		($fields{SUMMARY})=($fields{DESCRIPTION}."\n")=~m/(.*?)\n/m;

		# Fallback.
		if (!$fields{SUMMARY}) {
			$fields{SUMMARY}="Converted RPM package";
		}
	}
	if (!$fields{COPYRIGHT}) {
		$fields{COPYRIGHT}="unknown";
	}
	if (!$fields{DESCRIPTION}) {
		$fields{DESCRIPTION}=$fields{SUMMARY};
	}

	# Convert ARCH into string, if it isn't already a string.
	if ($fields{ARCH} eq 1) {
		$fields{ARCH}='i386';
	}
	elsif ($fields{ARCH} eq 2) {
		$fields{ARCH}='alpha';
	}
	elsif ($fields{ARCH} eq 3) {
		$fields{ARCH}='sparc';
	}
	elsif ($fields{ARCH} eq 6) {
		$fields{ARCH}='m68k';
	}

	if (!$fields{RELEASE} || !$fields{VERSION} || !$fields{NAME}) {
		Error("Error querying rpm file.");
	}

	$fields{RELEASE}=$fields{RELEASE}+1;
	$fields{DISTRIBUTION}="Red Hat";

	return %fields;
}

# Unpack a rpm file.
sub Unpack { my ($file)=@_;
	SafeSystem("(cd ..;rpm2cpio $file) | cpio --extract --make-directories --no-absolute-filenames",
	           "Error unpacking $file\n");
}

1
