#!/usr/bin/perl -w

=head1 NAME

Alien::Package::Pkg - an object that represents a Solaris pkg package

=cut

package Alien::Package::Pkg;
use strict;
use base qw(Alien::Package);

=head1 DESCRIPTION

This is an object class that represents a pkg package, as used in Solaris. 
It is derived from Alien::Package.

=head1 CLASS DATA

=over 4

=item scripttrans

Translation table between canoical script names and the names used in
pkg's.

=cut

use constant scripttrans => {
	postinst => 'postinstall',
	preinst => 'preinstall',
};

=back

=head1 METHODS

=over 4

=item init

This class needs the Solaris pkginfo and kgtrans tools to work.

=cut

sub init {
	foreach (qw(/usr/bin/pkginfo /usr/bin/pkgtrans)) {
		-x || die "$_ is needed to use ".__PACKAGE__."\n";
	}
}

=item converted_name

Convert name from something debian-like to something that the
Solaris constraints will handle (i.e. 9 chars max).

=cut

sub converted_name {
	my $this = shift;
	my $prefix = "ALN";
	my $name = $this->name;

	for ($name) {		# A Short list to start us off.
				# Still, this is risky since we need
				# unique names.
		s/^lib/l/;
		s/-perl$/p/;
		s/^perl-/pl/;
	}
	
	$name = substr($name, 0, 9);

	return $prefix.$name;
}

=item checkfile

Detect pkg files by their contents.

=cut

sub checkfile {
	my $this=shift;
	my $file=shift;

	open(F, $file) || die "Couldn't open $file: $!\n";
	my $line = <F>;
	close F;

	return unless defined $line;
	
	if($line =~ "# PaCkAgE DaTaStReAm") {
		return 1;
	}
}

=item install

Install a pkg with pkgadd. Pass in the filename of the pkg to install.

=cut

sub install {
	my $this=shift;
	my $pkg=shift;

	if (-x "/usr/sbin/pkgadd") {
		$this->do("/usr/sbin/pkgadd", "-d .", "$pkg")
			or die "Unable to install";
	}
	else {
		die "Sorry, I cannot install the generated .pkg file because /usr/sbin/pkgadd is not present.\n";
	}
}

=item scan

Scan a pkg file for fields.

=cut

sub scan {
	my $this=shift;
	$this->SUPER::scan(@_);
	my $file=$this->filename;
	my $tdir="pkg-scan-tmp.$$";

	$this->do("mkdir", $tdir) || die "Error making $tdir: $!\n"; 

	my $pkgname;
	if (-x "/usr/bin/pkginfo" && -x "/usr/bin/pkgtrans") {
		my $pkginfo;

		open(INFO, "/usr/bin/pkginfo -d $file|")
			|| die "Couldn't open pkginfo: $!\n";
		$_ = <INFO>;
		($pkgname) = /\S+\s+(\S+)/;
		close INFO;

		# Extract the files
		$this->do("/usr/bin/pkgtrans -i $file $tdir $pkgname")
			|| die "Error running pkgtrans: $!\n";

		open(INFO, "$tdir/$pkgname/pkginfo")
			|| die "Couldn't open pkgparam: $!\n";
		my ($key, $value);
		while (<INFO>) {
			if (/^([^=]+)=(.*)$/) {
				$key = $1;
				$value = $2;
			}
			else {
				$value = $_;
			}
			push @{$pkginfo->{$key}}, $value
		}
		close INFO;
		$file =~ m,([^/]+)-[^-]+(?:.pkg)$,;
		$this->name($1);
		$this->arch($pkginfo->{ARCH}->[0]);
		$this->summary("Converted Solaris pkg package");
		$this->description(join("", @{[$pkginfo->{DESC} || "."]}));
		$this->version($pkginfo->{VERSION}->[0]);
		$this->distribution("Solaris");
		$this->group("unknown"); # *** FIXME
		$this->origformat('pkg');
		$this->changelogtext('');
		$this->binary_info('unknown'); # *** FIXME
	
		if (-f "$tdir/$pkgname/copyright") {
			open (COPYRIGHT, "$file/install/copyright")
				|| die "Couldn't open copyright: $!\n";
			$this->copyright(join("\n",<COPYRIGHT>));
			close(COPYRIGHT);
		}
		else {
			$this->copyright("unknown");
		}
	}

	# Now figure out the conffiles. Assume anything in etc/ is a
	# conffile.
	my @conffiles;
	my @filelist;
	my @scripts;
	open (FILELIST,"$tdir/$pkgname/pkgmap") ||
		die "getting filelist ($file/pkgmap): $!";
	while (<FILELIST>) {
		if (m,^1 f \S+ etc/([^\s=]+),) {
			push @conffiles, "/etc/$1";
		}
		if (m,^1 [fd] \S+ ([^\s=]+),) {
			push @filelist, $1;
		}
		if (m,^1 i (\S+),) {
			push @scripts, $1;
		}
	}

	$this->filelist(\@filelist);
	$this->conffiles(\@conffiles);

	# Now get the scripts.
	foreach my $script (keys %{scripttrans()}) {
		$this->$script(scripttrans()->{$script})
			if -e "$file/".scripttrans()->{$script};
	}

	$this->do("rm -rf $tdir");

	return 1;
}

=item unpack

Unpack pkg.

=cut

sub unpack {
	my $this=shift;
	$this->SUPER::unpack(@_);
	my $file=$this->filename;

	my $pkgname;
	open(INFO, "/usr/bin/pkginfo -d $file|")
		|| die "Couldn't open pkginfo: $!\n";
	$_ = <INFO>;
	($pkgname) = /\S+\s+(\S+)/;
	close INFO;

	if (-x "/usr/bin/pkgtrans") {
		my $workdir = $this->name."-".$this->version;;
		$this->do("mkdir", $workdir) || die "unable to mkdir $workdir: $!\n";
		$this->do("/usr/bin/pkgtrans $file $workdir $pkgname")
			|| die "unable to extract $file: $!\n";
		rename("$workdir/$pkgname", "$ {workdir}_1")
			|| die "unable rename $workdir/$pkgname: $!\n";
		rmdir $workdir;
		rename("$ {workdir}_1", $workdir)
			|| die "unable to rename $ {workdir}_1: $!\n";
		$this->unpacked_tree($workdir);
	}
}

=item prep

Adds a populated install directory to the build tree.

=cut

sub prep {
	my $this=shift;
	my $dir=$this->unpacked_tree || die "The package must be unpacked first!";

#  	opendir(DIR, $this->unpacked_tree);
#  	my @sub = map {$this->unpacked_tree . "$_"}
#  	  grep {/^\./} readdir DIR;
#  	closedir DIR;

	$this->do("cd $dir; find . -print | pkgproto > ./prototype")
		|| die "error during pkgproto: $!\n";

	open(PKGPROTO, ">>$dir/prototype")
		|| die "error appending to prototype: $!\n";

	open(PKGINFO, ">$dir/pkginfo")
		|| die "error creating pkginfo: $!\n";
	print PKGINFO qq{PKG="}.$this->converted_name.qq{"\n};
	print PKGINFO qq{NAME="}.$this->name.qq{"\n};
	print PKGINFO qq{ARCH="}.$this->arch.qq{"\n};
	print PKGINFO qq{VERSION="}.$this->version.qq{"\n};
	print PKGINFO qq{CATEGORY="application"\n};
	print PKGINFO qq{VENDOR="Alien-converted package"\n};
	print PKGINFO qq{EMAIL=\n};
	print PKGINFO qq{PSTAMP=alien\n};
	print PKGINFO qq{MAXINST=1000\n};
	print PKGINFO qq{BASEDIR="/"\n};
	print PKGINFO qq{CLASSES="none"\n};
	print PKGINFO qq{DESC="}.$this->description.qq{"\n};
	close PKGINFO;
	print PKGPROTO "i pkginfo=./pkginfo\n";

	$this->do("mkdir", "$dir/install") || die "unable to mkdir $dir/install: $!";
	open(COPYRIGHT, ">$dir/install/copyright")
		|| die "error creating copyright: $!\n";
	print COPYRIGHT $this->copyright;
	close COPYRIGHT;
	print PKGPROTO "i copyright=./install/copyright\n";

	foreach my $script (keys %{scripttrans()}) {
		my $data=$this->$script();
		my $out=$this->unpacked_tree."/install/".${scripttrans()}{$script};
		next if ! defined $data || $data =~ m/^\s*$/;

		open (OUT, ">$out") || die "$out: $!";
		print OUT $data;
		close OUT;
		$this->do("chmod", 755, $out);
		print PKGPROTO "i $script=$out\n";
	}
	close PKGPROTO;
}

=item build

Build a pkg.

=cut

sub build {
	my $this = shift;
	my $dir = $this->unpacked_tree;

	$this->do("cd $dir; pkgmk -r / -d .")
		|| die "Error during pkgmk: $!\n";

	my $pkgname = $this->converted_name;
	my $name = $this->name."-".$this->version.".pkg";
	$this->do("pkgtrans $dir $name $pkgname")
		|| die "Error during pkgtrans: $!\n";
	$this->do("mv", "$dir/$name", $name);
	return $name;
}

=head1 AUTHOR

Mark Hershberger <mah@everybody.org>

=cut

1
