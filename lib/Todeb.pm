#!/usr/bin/perl
#
# Package for converting to .deb file.

package To::deb;

use strict;

# Mangle the fields to fit debian standards.
sub FixFields { my ($self,%fields)=@_;
	# Make sure package name is all lower case.
	$fields{NAME}=lc($fields{NAME});
	# Make sure the package name contains no invalid characters.
	$fields{NAME} =~ tr/_/-/;
	$fields{NAME} =~ s/[^a-z0-9-\.\+]//g;

	# Fix up the description field to Debian standards (indented at
	# least one space, no empty lines.)
	my $description=undef;
	my $line;
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

	return %fields;
}

# Create debian/* files, either from a patch, or automatically.
sub Convert { my ($self,$workdir,%fields)=@_;
	if ($main::generate && !$main::single) {
		Alien::SafeSystem("cp -fa $workdir $workdir.orig", "Error creating $workdir.orig");
	}

	# Do the actual conversion here.
	mkdir "$fields{NAME}-$fields{VERSION}/debian",0755 
		|| Alien::Error("Unable to make debian directory");
	my $patchfile=$main::patchfile;
	$patchfile=Alien::GetPatch($fields{NAME},$fields{VERSION},$fields{RELEASE}) if !$patchfile;
	if ($patchfile) {
		Alien::Patch($patchfile,$workdir);
	}
	else {
		$self->AutoDebianize($workdir,%fields);
	}
	chmod 0755,"$workdir/debian/rules";

	# Make the .orig directory if we were instructed to do so.
	if ($main::single) {
		print "Directory $workdir prepared.\n";
	}
	elsif ($main::generate) {
		print "Directories $workdir and $workdir.orig prepared.\n";
	}
}

# Fill out templates to create debian/* files.
# Pass it the work directory, and the type of package we are debianizing.
sub AutoDebianize { my ($self,$workdir,%fields)=@_;
	Alien::Status("Automatic package debianization");

	# Generate some more fields we need.
	$fields{DATE}=Alien::GetDate();
	$fields{EMAIL}=Alien::GetEmail();
	$fields{USERNAME}=Alien::GetUserName();

	# Fill out all the templates.
	my $fn;
	foreach $fn (glob("$main::libdir/to-$main::desttype/$main::filetype/*")) {
		my $destfn=$fn;
		$destfn=~s#^$main::libdir/to-$main::desttype/$main::filetype/##;
		Alien::FillOutTemplate($fn,"$main::workdir/debian/$destfn",%fields);
	}

	# Autogenerate the scripts without templates, so the scripts 
	# only exist if they need to.
	my $script;
	foreach $script ('postinst','postrm','preinst','prerm') {
		if ($fields{uc($script)}) {
			open (OUT,">$workdir/debian/$script") ||
				Alien::Error("$workdir/debian/$script: $!");;
			print OUT $fields{uc($script)};
			close OUT;
		}
	}
}

# Passed the available info about the package in a hash, return the name of 
# the debian package that will be made.
sub GetPackageName { my ($self,%fields)=@_;
	return "$fields{NAME}_$fields{VERSION}-$fields{RELEASE}_$fields{ARCH}.deb";
}

# Build the debian package.
sub Build { my ($self)=@_;
	Alien::SafeSystem("debian/rules binary","Package build failed.\n");
}

# Install the debian package that is passed.
sub Install { my ($self,$package)=@_;
	Alien::SafeSystem("dpkg --no-force-overwrite -i $package");
}

1
