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
	         'DESCRIPTION', 'COPYRIGHT', 'PREFIXES') {
		$fieldtrans{$field}=$field;
	}

	# Use --queryformat to pull out all the fields we need.
	foreach $field (keys(%fieldtrans)) {
		$_=`LANG=C rpm -qp $file --queryformat \%{$field}`;
		$fields{$fieldtrans{$field}}=$_ if $_ ne '(none)';
	}

	if ($main::scripts) {
		# Fix up the scripts - they are always shell scripts, so make them so.
		foreach $field ('PREINST','POSTINST','PRERM','POSTRM') {
			$fields{$field}="#!/bin/sh\n$fields{$field}" if $fields{$field};
		}
	}

	# Get the conffiles list.
	$fields{CONFFILES}=`rpm -qcp $file`;

	# Include the output of rpm -qi in the copyright file.
	$fields{COPYRIGHT_EXTRA}=`rpm -qpi $file`;

	# Get the filelist, it's used in the parent directory check in Unpack().
	$fields{FILELIST}=`rpm -qpl $file`;

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

	# Treat 486, 586, etc, as 386.
	if ($fields{ARCH}=~m/i\d86/) {
		$fields{ARCH}='i386';
	}

	
	# Treat ppc as powerpc.
	if ($fields{ARCH} eq 'ppc') {
		$fields{ARCH} = 'powerpc';
	}

	if ($fields{RELEASE} eq undef || $fields{VERSION} eq undef|| !$fields{NAME}) {
		Alien::Error("Error querying rpm file.");
	}

	$fields{RELEASE}++ unless $main::keep_version;
	$fields{DISTRIBUTION}="Red Hat";

	return %fields;
}

# Unpack a rpm file.
sub Unpack { my ($self,$file,$nopatch,%fields)=@_;
	Alien::SafeSystem("(cd ..;rpm2cpio $file) | cpio --extract --make-directories --no-absolute-filenames --preserve-modification-time",
  	"Error unpacking $file\n");

	# If the package is relocatable. We'd like to move it to be under the
	# PREFIXES directory. However, it's possible that that directory is in
	# the package - it seems some rpm's are marked as relocatable and
	# unpack already in the directory they can relocate to, while some are
	# marked relocatable and the directory they can relocate to is removed
	# from all filenames in the package. I suppose this is due to some
	# vchange between versions of rpm, but none of this is adequatly
	# documented, so we'll just muddle through.
	# 
	# Test to see if the package contains the PREFIXES directory already.
	print "----$fields{PREFIXES}\n";
	if ($fields{PREFIXES} ne undef && ! -e "./$fields{PREFIXES}") {
		print "Moving unpacked files into $fields{PREFIXES}\n";
		
		# Get the files to move.
		my $filelist=join ' ',glob('*');
		
		# Now, make the destination directory.
		my $collect=undef;
		foreach (split(m:/:,$fields{PREFIXES})) {
			if ($_ ne undef) { # this keeps us from using anything but relative paths.
				$collect.="$_/";
				mkdir $collect,0755 || Alien::Error("Unable to make directory: $collect: $!");
			}
		}
		# Now move all files in the package to the directory we made.
		Alien::SafeSystem("mv $filelist ./$fields{PREFIXES}",
			"Error moving unpacked files into the default prefix directory\n");
	}

	# When cpio extracts the file, any child directories that are present, but
	# whose parent directories are not, end up mode 700. This next block corrects
	# that to 755, which is more reasonable.
	#
	# Of course, this whole thing assumes we get the filelist in sorted order.
	my $lastdir=undef;
	foreach $file (split(/\n/,$fields{FILELIST})) {
		$file=~s/^\///;
		if (($lastdir && $file=~m:^\Q$lastdir\E/[^/]*$: eq undef) || !$lastdir) {
			# We've found one of the nasty directories. Fix it up.
			#
			# Note that I strip the trailing filename off $file here, for two 
			# reasons. First, it makes the loop easier, we don't need to fix the
			# perms on the last file, after all! Second, it makes the -d test below
			# fire, which saves us from trying to fix a parent directory twice.
			($file)=$file=~m:(.*)/.*?:;
			my $dircollect=undef;
			my $dir;
			foreach $dir (split(/\//,$file)) {
				$dircollect.="$dir/";
				chmod 0755,$dircollect; # TADA!
			}
		}
		if (-d "./$file") {
			$lastdir=$file;
		}
	}
}

1
