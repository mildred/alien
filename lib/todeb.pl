#!/usr/bin/perl
#
# Package for converting to .deb file.

# Create debian/* files, either from a patch, or automatically.
sub Convert { my ($workdir,%fields)=@_;
	if ($generate && !$single) {
		SafeSystem("cp -fa $workdir $workdir.orig", "Error creating $workdir.orig");
	}

	# Make sure package name is all lower case.
	$fields{NAME}=lc($fields{NAME});

	# Fix up the description field to Debian standards (indented at
	# least one space, no empty lines.)
	my $description=undef;
	foreach $line (split(/\n/,$fields{DESCRIPTION})) {
		$line=~s/\t/        /g; # change tabs to spaces.
		$line=~s/\s+$//g; # remove trailing whitespace.
		if (!$line) {  # empty lines
			$line=" .";
		}
		else { # normal lines
			$line=" $line";
		}
		$description.=$line."\n";
	}
	chomp $description;
	$fields{DESCRIPTION}=$description."\n";

	# Do the actual conversion here.
	mkdir "$fields{NAME}-$fields{VERSION}/debian",0755 
		|| Error("Unable to make debian directory");
	$patchfile=GetPatch($fields{NAME}) if !$patchfile;
	if ($patchfile) {
		Patch($patchfile,$workdir);
	}
	else {
		AutoDebianize($workdir,%fields);
	}
	chmod 0755,"$workdir/debian/rules";

	# Make the .orig directory if we were instructed to do so.
	if ($single) {
		print "Directory $workdir prepared.\n";
	}
	elsif ($generate) {
		print "Directories $workdir and $workdir.orig prepared.\n";
	}
}

# Fill out templates to create debian/* files.
# Pass it the work directory, and the type of package we are debianizing.
sub AutoDebianize { my ($workdir,%fields)=@_;
	Status("Automatic package debianization");

	# Generate some more fields we need.
	$fields{DATE}=GetDate();
	$fields{EMAIL}=GetEmail();
	$fields{USERNAME}=GetUserName();

	# Fill out all the templates.
	foreach $fn (glob("$libdir/to-$desttype/$filetype/*")) {
		my $destfn=$fn;
		$destfn=~s#^$libdir/to-$desttype/$filetype/##;
		FillOutTemplate($fn,"$workdir/debian/$destfn",%fields);
	}
}

# Passed the available info about the package in a hash, return the name of 
# the debian package that will be made.
sub GetPackageName { my %fields=@_;
	return "$fields{NAME}_$fields{VERSION}-$fields{RELEASE}_$fields{ARCH}.deb";
}

# Build the debian package.
sub Build {
	SafeSystem("debian/rules binary","Package build failed.\n");
}

# Install the debian package that is passed.
sub Install { my $package=shift;
	SafeSystem("dpkg -i $package");
}

1
