#!/usr/bin/perl -w
use ExtUtils::MakeMaker;
use strict;

# Just to make it ignore editor backup files.
sub MY::libscan {
	$_ = $_[1];

	return '' if m/\/(RCS|CVS|SCCS)\// || m/[~%]$/ || m/\.(orig|rej)$/;
	return $_;
}

# Add a more targets.
sub MY::postamble {
	return q{

VER=$(shell perl -e '$$_=<>;print m/\((.*?)\)/'<debian/changelog)

extra_build:
	perl -i -pe "s/\@version\@/$(VER)/g" <alien.lsm.in >alien.lsm

extra_install:
	install -d $(PREFIX)/usr/share/alien/patches \
		   $(PREFIX)/var/lib/alien
	cp -f patches/*.diff $(PREFIX)/usr/share/alien/patches/
	-rm -f $(PREFIX)/usr/share/alien/patches/*.gz
	gzip -qf9 $(PREFIX)/usr/share/alien/patches/*

alien:
	perl -pe ' \
		$$_="\tmy \$$version_string=\"$(VER)\";\n" \
			if /VERSION_AUTOREPLACE/' alien.pl > alien
}
}

WriteMakefile(
	'NAME'		=> 'Alien',
	'EXE_FILES'	=> ['alien'],
	# Pure evil. Hook into build and install targets
	'depend'	=> {'all:' => 'extra_build',
			    'install:' => 'extra_install',
			    'pure_install:' => 'extra_install'},
	'clean'		=> {FILES => 'alien.lsm alien'},
);
