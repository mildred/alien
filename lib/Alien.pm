#!/usr/bin/perl
#
# Misc. functions used by alien.

package Alien;

use strict;

# Print out a status line.
sub Status { my $message=shift;
	print "-- $message\n";
}

# Print out an error message and exit the program.
sub Error { my $message=shift;
	print STDERR "alien: $message\n";
	exit 1;
}

# Run a system command, and print an error message if it fails.
# The errormessage parameter is optional.
sub SafeSystem { my ($command,$errormessage)=@_;
	my $ret=system $command;
	if (int($ret/256) > 0) {
		$errormessage="Error running: $command" if !$errormessage;
		Error($errormessage);
	}
}

# Make the passed directory. Exits with error if the directory already
# exists.
sub SafeMkdir { my ($dir)=@_;
	if (-e $dir) {
        	Error("Directory $dir already exists.\nRemove it and re-run alien.");
	}
	mkdir $dir,0755 || Error("Unable to make directory, \"$dir\": $!");
}

# Pass the filename of a package.
# Returns "rpm" or "tgz" or "deb", depending on what it thinks the file type
# is, based on the filename.
# Perhaps this should call file(1), instead?
#
# Note that the file type this returns corresponds to directories in 
# $libdir.
sub FileType { my $file=shift;
	if ($file=~m/.*\.rpm/ ne undef) {
		return 'rpm';
	}	
	elsif ($file=~m/.*\.(tgz|tar\.gz)/ ne undef) {
		return 'tgz';
	}
	elsif ($file=~m/.*\.deb/ ne undef) {
		return 'deb';
	}
	else {
		Error("Format of filename bad: $file");
	}
}

# Pass this the name and version and revision of a package, it will return the 
# filename of a patch file for the package or undef if there is none.
sub GetPatch { my ($name,$version,$revision)=@_;
	my @patches=glob("$main::patchdir/$name\_$version-$revision*.diff.gz");
	if ($#patches < 0) {
		# try not matching the revision, see if that helps.
		@patches=glob("$main::patchdir/$name\_$version*.diff.gz");
		if ($#patches < 0) {
			# fallback to anything that matches the name.
			@patches=glob("$main::patchdir/$name\_*.diff.gz");
		}
	}

	# If we ended up with multiple matches, return the first.
	return $patches[0];
}

# Apply the given patch file to the given subdirectory.
sub Patch { my ($patchfile,$subdir)=@_;
	Status("Patching in $patchfile");
	chdir $subdir;
	# cd .. here in case the patchfile's name was a relative path.
	# The -f passed to zcat makes it pass uncompressed files through
	# without error.
	SafeSystem("(cd ..;zcat -f $patchfile) | patch -p1","Patch error.\n");
	# look for .rej files
	if (`find . -name "*.rej"`) {
		Error("Patch failed: giving up.");
	}
	SafeSystem('find . -name \'*.orig\' -exec rm {} \\;',"Error removing .orig files");
	chdir "..";
}

# Returns the 822-date.
sub GetDate {
	my $date=`822-date`;
	chomp $date;
	if (!$date) {
		Error("822-date did not return a valid result.\n");
	}

	return $date;
}

# Returns a email address for the current user.
sub GetEmail {
	if (!$ENV{EMAIL}) {
		my $login = getlogin || (getpwuid($<))[0] || $ENV{USER};
		open (MAILNAME,"</etc/mailname");
		my $mailname=<MAILNAME>;
		chomp $mailname;
		close MAILNAME;
		if (!$mailname) {
			$mailname=`hostname -f`;
			chomp $mailname;
		}
		return "$login\@$mailname";
	}
	else {
		return $ENV{EMAIL};
	}
}

# Returns the user name of the user who is running this.
sub GetUserName {
	my $username;
	my $username_in_passwd=undef;	

	my $login = getlogin || (getpwuid($<))[0] || $ENV{USER};

	open (PASSWD,"</etc/passwd");
	while (<PASSWD>) {
		my (@fields)=split(/:/,$_);
		if ($fields[0] eq $login) {
			$username=$fields[4];
			$username_in_passwd=1; # don't try NIS, no matter what.
			close PASSWD;
		}
	}
	close PASSWD;

	if (!$username_in_passwd && !$username && -x "/usr/bin/ypmatch") {
		# Give NIS a try.
		open (YPMATCH,"ypmatch $login passwd.byname |");
		my (@fields)=split(/:/,<YPMATCH>);
		$username=$fields[4];
		close YPMATCH;
	}

	# Remove GECOS(?) fields from username.
	$username=~s/,.*//g;

	# The ultimate fallback.
	if (!$username) {
		$username=$login;
	}

	return $username;
}

# Fill out a template, and save it to the passed location.
# The hash that is passed to this function lists the tags that can be onthe
# template, and the values to fill in for those tags.
sub FillOutTemplate { my ($fn,$destfn,%fields)=@_;
	open (IN,"<$fn") || Error("$fn: $!");
	open (OUT,">$destfn") || Error("$destfn: $!");
	while (<IN>) {
		s/#(.*?)#/$fields{$1}/g;
		print OUT $_;
	}
	close OUT;
	close IN;
}

1
