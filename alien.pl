#!/usr/bin/perl -w

=head1 NAME

alien - Convert or install an alien binary package

=head1 SYNOPSIS

 alien [--to-deb] [--to-rpm] [--to-tgz] [--to-slp] [options] file [...]

=head1 DESCRIPTION

B<alien> is a program that converts between Redhat rpm, Debian deb,
Stampede slp, Slackware tgz, and Solaris pkg file formats. If you want to
use a package from another linux distribution than the one you have
installed on your system, you can use alien to convert it to your preferred
package format and install it. It also supports LSB packages.

=head1 WARNING

Despite the high version number, alien is still (and will probably always
be) rather experimental software. It's been under development for many
years now, but there are still many bugs and limitations.

Alien should not be used to replace important system packages, like
init, libc, or other things that are essential for the functioning of
your system. Many of these packages are set up differently by the
different distributions, and packages from the different distributions
cannot be used interchangeably. In general, if you can't remove a
package without breaking your system, don't try to replace it with an
alien version.

=head1 PACKAGE FORMAT NOTES

=over 4

=item rpm

For converting to and from rpm format the Red Hat Package Manager must be
installed.

=item lsb

To convert from lsb packages, the Red Hat Package Manager must be installed.
Unlike the other package formats, alien can handle the depenendencies of
lsb packages if the destination package format supports dependencies. Note
that this means that the package generated from a lsb package will depend on
a package named "lsb" -- your distribution should provide a package by that
name, if it is lsb compliant. The scripts in the lsb package will be converted
by default as well.

To generate lsb packages, the Red Hat Package Manager must be installed,
and alien will use by preference a program named lsb-rpm, if it exists.
No guarantees are made that the generated lsb packages will be fully LSB
compliant, and it's rather unlikely they will unless you build them in the
lsbdev environment.

=item deb

For converting to (but not from) deb format, the gcc, make, debmake,
dpkg-dev, and dpkg packages must be installed.

=item tgz

Note that when converting from the tgz format, B<alien> will simply generate an
output package that has the same files in it as are in the tgz file. This
only works well if the tgz file has precompiled binaries in it in a
standard linux directory tree. Do NOT run alien on tar files with source
code in them, unless you want this source code to be installed in your root
directory when you install the package!

=item pkg

To manipulate packages in the Solaris pkg format (which is really the SV 
datastream package format), you will need the Solaris pkginfo and pkgtrans
tools.

=back

=head1 OPTIONS

Alien will convert all the files you pass into it into all the output types
you specify. If no output type is specified, it defaults to converting to
deb format.

=over 4

=item file [...]

The list of package files to convert.

=item B<-d>, B<--to-deb>

Make debian packages. This is the default.

=item B<-r>, B<--to-rpm>

Make rpm packages.

=item B<-t>, B<--to-tgz>

Make tgz packages.

=item B<--to-slp>

Make slp packages.

=item B<-p>, B<--to-pkg>

Make Solaris pkg packages.

=item B<-i>, B<--install>

Automatically install each generated package, and remove the package file
after it has been installed.

=item B<-g>, B<--generate>

Generate a temporary directory suitable for building a package from, but do
not actually create the package. This is useful if you want to move files
around in the package before building it. The package can be built from
this temporary directory by running "debian/rules binary", if you were creating
a Debian package, or by running "rpm -bb <packagename>.spec" if you were
creating a Red Hat package.

=item B<-s>, B<--single>

Like B<-g>, but do not generate the packagename.orig directory. This is only
useful when you are very low on disk space and are generating a debian
package.

=item B<--patch=>I<patch>

Specify the patch to be used instead of automatically looking the patch up
in B</var/lib/alien>. This has no effect unless a debian package is being
built.

=item B<--nopatch>

Do not use any patch files.

=item B<--description=>I<desc>

Specifiy a description for the package. This only has an effect when
converting from the tgz package format, which lacks descriptions.

=item B<-c>, B<--scripts>

Try to convert the scripts that are meant to be run when the
package is installed and removed. Use this with caution, becuase these
scripts might be designed to work on a system unlike your own, and could
cause problems. It is recommended that you examine the scripts by hand
and check to see what they do before using this option.

This is enabled by default when converting from lsb packages.

=item B<-T>, B<--test>

Test the generated packages. Currently this is only supported for debian
packages, which, if lintian is installed, will be tested with lintian and
lintian's output displayed.

=item B<-k>, B<--keep-version>

By default, alien adds one to the minor version number of each package it
converts. If this option is given, alien will not do this.

=item B<--fixperms>

Sanitize all file owners and permissions when building a deb. This may be
useful if the original package is a mess. On the other hand, it may break
some things to mess with their permissions and owners to the degree this does,
so it defaults to off. This can only be used when converting to debian
packages.

=item B<-h>, B<--help>

Display a short usage summary.

=back

=head1 EXAMPLES

Here are some examples of the use of alien:

=over 4

=item alien --to-deb package.rpm

Convert the package.rpm into a package.deb

=item alien --to-rpm package.deb

Convert the package.deb into a package.rpm

=item alien -i package.rpm

Convert the package.rpm into a package.deb (converting to a .deb package is
default, so you need not specify --to-deb), and install the generated
package.

=item alien --to-deb --to-rpm --to-tgz --to-slp foo.deb bar.rpm baz.tgz

Creates 9 new packages. When it is done, foo bar and baz are available in
all 4 package formats.

=back

=head1 ENVIRONMENT

Alien recognizes the following environemnt variables:

=over 4

=item RPMBUILDOPT

Options to pass to rpm when it is building a package.

=item RPMINSTALLOPT

Options to pass to rpm when it is installing a package.

=item EMAIL

If set, alien assumes this is your email address. Email addresses are included
in generated debian packages.

=back

=head1 NOTES

When using alien to convert a tgz package, all files in /etc in are assumed
to be configuration files.

If alien is not run as root, the files in the generated package will have
incorrect owners and permissions.

=head1 AUTHOR

Alien was written by Christoph Lameter, B<<clameter@debian.org>>.

deb to rpm conversion code was taken from the Martian program by
Randolph Chung, B<<tausq@debian.org>>.

The Solaris pkg code was written by Mark A. Hershberger B<<mah@everybody.org>>.

Alien has been extensively rewritten (3 times) and is now maintained by
Joey Hess, B<<joeyh@debian.org>>.

=head1 COPYRIGHT

Alien may be copied amd modified under the terms of the GNU General Public
License.

=cut

use strict;
use lib '.'; # For debugging, removed by Makefile.
use Getopt::Long;
use Alien::Package::Deb;
use Alien::Package::Rpm;
use Alien::Package::Tgz;
use Alien::Package::Slp;
use Alien::Package::Pkg;
use Alien::Package::Lsb;

# Returns a list of directories to search for patches.
sub patchdirs {
	return '/var/lib/alien',"/usr/share/alien/patches";
}

# Display alien's version number.
sub version {
	my $version_string='unknown'; # VERSION_AUTOREPLACE done by Makefile, DNE
	print "Alien version $version_string\n";
	exit;
}

# Display usage help.
sub usage {
	print STDERR <<EOF;
Usage: alien [options] file [...]
  file [...]                Package file or files to convert.
  -d, --to-deb              Generate a Debian deb package (default).
     Enables the following options:
       --patch=<patch>      Specify patch file to use instead of automatically
                            looking for patch in /var/lib/alien.
       --nopatch	    Do not use patches.
       --single             Like --generate, but do not create .orig
                            directory.
       --fixperms           Munge/fix permissions and owners.
       --test               Test generated packages with lintian.
  -r, --to-rpm              Generate a RedHat rpm package.
      --to-slp              Generate a Stampede slp package.
  -l, --to-lsb              Generate a LSB package.
  -t, --to-tgz              Generate a Slackware tgz package.
     Enables the following option:
       --description=<desc> Specify package description.
  -p, --to-pkg              Generate a Solaris pkg package.
  -i, --install             Install generated package.
  -g, --generate            Unpack, but do not generate a new package.
  -c, --scripts             Include scripts in package.
  -k, --keep-version        Do not change version of generated package.
  -h, --help                Display this help message.
  -v, --version		    Display alien's version number.

EOF
	exit 1;
}

# Start by processing the parameters.
my (%destformats, $generate, $install, $single, $scripts, $patchfile,
    $nopatch, $tgzdescription, $keepversion, $fixperms, $test);

GetOptions(
	"to-deb|d", sub { $destformats{deb}=1 },
	"to-rpm|r", sub { $destformats{rpm}=1 },
	"to-lsb|l", sub { $destformats{lsb}=1 },
	"to-tgz|t", sub { $destformats{tgz}=1 },
	"to-slp",   sub { $destformats{slp}=1 },
	"to-pkg|p", sub { $destformats{pkg}=1 },
	"test|T", \$test,
	"generate|g", \$generate,
	"install|i", \$install,
	"single|s", sub { $single=1; $generate=1 },
	"scripts|c", \$scripts,
	"patch|p=s", \$patchfile,
	"nopatch", \$nopatch,
	"description=s", \$tgzdescription,
	"keep-version|k", \$keepversion,
	"fixperms", \$fixperms,
	"help|h", \&usage,
	"version|v", \&version,
) || usage();

# Default to deb conversion.
if (! %destformats) {
	$destformats{deb}=1;
}

# A few sanity checks.
if (($generate || $single) && $install) {
	die "You can not use --generate or --single with --install.\n";
}
if (($generate || $single) && keys %destformats > 1) {
	die "--generate and --single may only be used when converting to a single format.\n";
}
if ($patchfile && ! -f $patchfile) {
	die "Specified patch file, \"$patchfile\" cannot be found.\n";
}
if ($patchfile && $nopatch) {
	die "The options --nopatch and --patchfile cannot be used together.\n";
}
unless (@ARGV) {
	print STDERR "You must specify a file to convert.\n\n";
	usage();
}

# Check alien's working anvironment.
if (! -w '.') {
	die("Cannot write to current directory. Try moving to /tmp and re-running alien.\n");
}
if ($> ne 0) {
	if ($destformats{deb} && ! $generate && ! $single) {
		die "Must run as root to convert to deb format (or you may use fakeroot).\n";
	}
	print STDERR "Warning: alien is not running as root!\n";
	print STDERR "Ownerships of files in the generated packages will probably be messed up.\n";
}

foreach my $file (@ARGV) {
	if (! -f $file) {
		die "File \"$file\" not found.\n";
	}

	# Figure out what kind of file this is.
	my $package;

	# Check lsb before rpm, since lsb packages are really just
	# glorified rpms.
	if (Alien::Package::Lsb->checkfile($file)) {
		$package=Alien::Package::Lsb->new(filename => $file);
	}
	elsif (Alien::Package::Rpm->checkfile($file)) {
		$package=Alien::Package::Rpm->new(filename => $file);
	}
	elsif (Alien::Package::Deb->checkfile($file)) {
		$package=Alien::Package::Deb->new(filename => $file);
	}
	elsif (Alien::Package::Tgz->checkfile($file)) {
		$package=Alien::Package::Tgz->new(filename => $file);
		$package->description($tgzdescription) if defined $tgzdescription;
	}
	elsif (Alien::Package::Slp->checkfile($file)) {
		$package=Alien::Package::Slp->new(filename => $file);
	}
	elsif (Alien::Package::Pkg->checkfile($file)) {
		$package=Alien::Package::Pkg->new(filename => $file);
	}
	else {
		die "Unknown type of package, $file.\n";
	}

	$package->usescripts($scripts) unless $package->usescripts;

	# Increment release.
	unless (defined $keepversion) {
		$^W=0; # Shut of possible "is not numeric" warning.
		$package->release($package->release + 1);
		$^W=1; # Re-enable warnings.
	}

	foreach my $format (keys %destformats) {
		# Skip conversion if package is already the correct format.
		if ($package->origformat ne $format) {
			# Only unpack once.
			if ($package->unpacked_tree) {
				$package->cleantree;
			}
			else {
				$package->unpack;
			}
			
			# Mutate package into desired format.
			bless($package, "Alien::Package::".ucfirst($format));
		
			# Make .orig.tar.gz directory?
			if ($format eq 'deb' && ! $single && $generate) {
				# Make .orig.tar.gz directory.
				system("cp", "-fa", "--", $package->unpacked_tree, $package->unpacked_tree.".orig") == 0
					or die "cp -fa failed";
			}
	
			# See if a patch file should be used.
			if ($format eq 'deb' && ! $nopatch) {
				if (defined $patchfile) {
					$package->patchfile($patchfile)
				}
				else {
					$package->patchfile($package->getpatch(patchdirs()));
				}
			}

			$package->fixperms($fixperms);
			
			$package->prep;
			
			# If generating build tree only, stop here with message.
			if ($generate) {
				if ($format eq 'deb' && ! $single) {
					print "Directories ".$package->unpacked_tree." and ".$package->unpacked_tree.".orig prepared.\n"
				}
				else {
					print "Directory ".$package->unpacked_tree." prepared.\n";
				}
				# Make sure $package does not wipe out the
				# directory when it is destroyed.
				$package->unpacked_tree('');
				exit;
			}
			
			my $newfile=$package->build;
			if ($test) {
				my @results = $package->test($newfile);
				if (@results) {
					print "Test results:\n";
					print "\t$_\n" foreach @results;
				}
			}
			if ($install) {
				$package->install($newfile);
				unlink $newfile;
			}
			else {
				# Tell them where the package ended up.
				print "$newfile generated\n";
			}
		}
		elsif ($install) {
			# Don't convert the package, but do install it.
			$package->install($file);
			# Note I don't unlink it. I figure that might annoy
			# people, since it was an input file.
		}

		$package->revert;
	}
}
