# Set this to wherever you want alien to install. Eg, /usr/local or /usr
PREFIX=/usr

VER=$(shell perl -e '$$_=<>;print m/\((.*?)\)/'<debian/changelog)
VERFILES=alien.spec alien.lsm

all:

clean:
	-rm build
	-rm *.bak *.out

install:	
	install -d $(DESTDIR)/$(PREFIX)/bin
	perl -pe '$$_="\t\$$prefix=\"$(PREFIX)\";" if /PREFIX_AUTOREPLACE/;\
		$$_="\tmy \$$version_string=\"$(VER)\";" if /VERSION_AUTOREPLACE/' alien \
		> $(DESTDIR)/$(PREFIX)/bin/alien
	chmod 755 $(DESTDIR)/$(PREFIX)/bin/alien
	install -d $(DESTDIR)/$(PREFIX)/lib/alien/patches \
		$(DESTDIR)/var/lib/alien
	cp -fr lib/* $(DESTDIR)/$(PREFIX)/lib/alien
	cp -f patches/* $(DESTDIR)/$(PREFIX)/lib/alien/patches/
	-rm -f $(DESTDIR)/$(PREFIX)/lib/alien/patches/*.gz
	gzip -qf9 $(DESTDIR)/$(PREFIX)/lib/alien/patches/*
	install -d $(DESTDIR)/$(PREFIX)/man/man1
	cp -f alien.1 $(DESTDIR)/$(PREFIX)/man/man1

# This updates the version number in various files.
version:
	@echo Updating version info....
	perl -i -pe "s/\@version\@/$(VER)/g" <alien.spec.in >alien.spec
	perl -i -pe "s/\@version\@/$(VER)/g" <alien.lsm.in >alien.lsm

debian:
	dpkg-buildpackage -tc -rfakeroot

rpm:
	sudo rpm -ba -v alien.spec --target noarch

.PHONY: debian
