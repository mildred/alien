#!/usr/bin/perl
#
# Package for converting from a .rpm file.

package From::rpm;

use strict;

# Query a rpm file for fields, and return a hash of the fields found.
# Pass the filename of the rpm file to query.
sub GetFields { my ($self,$file)=@_;
	my %fields;

	# This maps rpm fields (the keys) to the name we want
	# for each field (the values).
	my %fieldtrans;

	# Get the scripts fields too?
	if ($main::scripts) {
		%fieldtrans=(
			'PREIN' => 'PREINST',
			'POSTIN' => 'POSTINST',
			'PREUN' => 'PRERM',
			'POSTUN' => 'POSTRM',
		);
	}

	# These fields need no translation.
	my $field;
	foreach $field ('NAME','VERSION','RELEASE','ARCH','CHANGELOGTEXT','SUMMARY',
	         'DESCRIPTION', 'COPYRIGHT', 'DEFAULTPREFIX') {
		$fieldtrans{$field}=$field;
	}

	# Use --queryformat to pull out all the fields we need.
	foreach $field (keys(%fieldtrans)) {
		$_=`rpm -qp $file --queryformat \%{$field}`;
		$fields{$fieldtrans{$field}}=$_ if $_ ne '(none)';
	}

	if ($main::scripts) {
		# Fix up the scripts - they are always shell scripts, so make them so.
		foreach $field ('PREINST','POSTINST','PRERM','POSTRM') {
			$fields{$field}="#!/bin/sh\n$fields{$field}" if $fields{$field};
		}
	}

	# Get the conffiles list.
	# TOCHECK: if this is a relocatable package and DEFAULTPREFIX is set,
	# do we need to prepend DEFAULTPREFIX to each of these filenames?
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
	elsif ($fields{ARCH} eq "noarch") { # noarch = all
		$fields{ARCH}='all';
	}

	if ($fields{RELEASE} eq undef || $fields{VERSION} eq undef|| !$fields{NAME}) {
		Alien::Error("Error querying rpm file.");
	}

	$fields{RELEASE}++ unless $main::keep_version;
	$fields{DISTRIBUTION}="Red Hat";

	return %fields;
}

# Unpack a rpm file.
sub Unpack { my ($self,$file,%fields)=@_;
	Alien::SafeSystem("(cd ..;rpm2cpio $file) | cpio --extract --make-directories --no-absolute-filenames --preserve-modification-time",
  	"Error unpacking $file\n");
	if ($fields{DEFAULTPREFIX} ne undef) {
		print "Moving unpacked files into $fields{DEFAULTPREFIX}\n";

		# We have extracted the package, but it's in the wrong place. Move it
		# to be under the DEFAULTPREFIX directory.
		# First, get a list of files to move.
		my $filelist=join ' ',glob('*');

		# Now, make the destination directory.
		my $collect=undef;
		foreach (split(m:/:,$fields{DEFAULTPREFIX})) {
			if ($_ ne undef) { # this keeps us from using anything but relative paths.
				$collect.="$_/";
				mkdir $collect,0755 || Alien::Error("Unable to make directory: $collect: $!");
			}
		}
		# Now move all files in the package to the directory we made.
		Alien::SafeSystem("mv $filelist ./$fields{DEFAULTPREFIX}",
			"Error moving unpacked files into the default prefix directory\n");
	}
}

1
