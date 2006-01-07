#!/usr/bin/perl -w
use ExtUtils::MakeMaker;
use strict;

# Just to make it ignore editor backup files.
sub MY::libscan {
	$_ = $_[1];

	return '' if $_ eq 'alien.pl';
	return '' if m/\/(RCS|CVS|SCCS)\// || m/[~%]$/ || m/\.(orig|rej)$/;
	return $_;
}

# Add a few more targets.
sub MY::postamble {
	return q{

VER=$(shell perl -e '$$_=<>;print m/\((.*?)\)/'<debian/changelog)

all:: extra_build
clean:: extra_build
install:: extra_install
pure_install:: extra_install

extra_build:
	perl -i -pe "s/\@version\@/$(VER)/g" <alien.lsm.in >alien.lsm
	perl -i -pe "s/\@version\@/$(VER)/g" <alien.spec.in >alien.spec

extra_install:
	install -d $(PREFIX)/share/alien/patches \
		   $(VARPREFIX)/var/lib/alien
	cp -f patches/*.diff $(PREFIX)/share/alien/patches/
	-rm -f $(PREFIX)/share/alien/patches/*.gz
	gzip -qf9 $(PREFIX)/share/alien/patches/*

alien:
	perl -pe '$$_="" if /use lib/; $$_="our \$$Version=\"$(VER)\";\n" if /VERSION_AUTOREPLACE/' alien.pl > alien
}
}

WriteMakefile(
	'NAME'		=> 'Alien',
	'EXE_FILES'	=> ['alien'],
	'clean'		=> {FILES => 'alien'},
);
