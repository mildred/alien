#!/usr/bin/perl
#
# Package for converting from a tgz file.

package From::tgz;

use strict;

# Query a tgz file for fields, and return a hash of the fields found.
# Pass the filename of the tgz file to query.
sub GetFields { my ($self,$file)=@_;
	my %fields;

	# Get basename of the filename.
	my ($basename)=('/'.$file)=~m#^/?.*/(.*?)$#;

	# Strip out any tar extentions.
	$basename=~s/\.(tgz|tar\.gz)$//;

	if ($basename=~m/(.*)-(.*)/ ne undef) {
		$fields{NAME}=$1;
		$fields{VERSION}=$2;
	}
	else {
		$fields{NAME}=$basename;
		$fields{VERSION}=1;
	}

	$fields{ARCH}='i386';
	if ($main::tgzdescription eq undef) {
		$fields{SUMMARY}='Converted Slackware tgz package';
	}
	else {
		$fields{SUMMARY}=$main::tgzdescription;
	}
	$fields{DESCRIPTION}=$fields{SUMMARY};
	$fields{COPYRIGHT}="unknown";
	$fields{RELEASE}=1;
	$fields{DISTRIBUTION}="Slackware";

	# Now figure out the conffiles. Assume anything in etc/ is a conffile.
	# It's a little nasty to do it here, but it's much cleaner than waiting 
	# until the tar file is unpacked and then doing it.
	$fields{CONFFILES}='';
	open (FILELIST,"tar zvtf $file | grep etc/ |") 
		|| Alien::Error("Getting filelist: $!");
	while (<FILELIST>) {
		# Make sure it's a normal file. This is looking at the
		# permissions, and making sure the first character is '-'.
		# Ie: -rw-r--r--
		if (m:^-:) {
			# Strip it down to the filename.
			m/^(.*) (.*)$/;
			$fields{CONFFILES}.="/$2\n";
		}
	}
	close FILELIST;

	# Now get the whole filelist. We have to add leading /'s to the filenames.
  # We have to ignore all files under /install/
	$fields{FILELIST}='';
	open (FILELIST, "tar ztf $file |");
	while (<FILELIST>) {
		if ($_=~m:^install/: eq undef) {
			$fields{FILELIST}.="/$_";
		}
	}
	close FILELIST;

	# Now get the scripts.
	if ($main::scripts) {
		my %scripttrans=(
			'doinst.sh' => 'POSTINST',
			'delete.sh' => 'POSTRM',
			'predelete.sh' => 'PRERM',
			'predoinst.sh' => 'PREINST',
		);
		my $script;
		foreach $script (keys(%scripttrans)) {
			$fields{$scripttrans{$script}}=
				`tar Oxzf $file install/$script 2>/dev/null`;
		}
	}

	return %fields;
}

# Handles unpacking of tgz's.
sub Unpack { my ($self,$file)=@_;
	Alien::SafeSystem ("(cd ..;cat $file) | tar zxpf -","Error unpacking $file\n");

	# Delete this install directory that has slackware info in it.
	Alien::SafeSystem ("rm -rf install");
}

1
