# Set this to wherever you want alien to install. Eg, /usr/local or /usr
PREFIX=/usr

VER=$(shell perl -e '$$_=<>;print m/\((.*?)\)/'<debian/changelog)

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
	install -d $(DESTDIR)/$(PREFIX)/share/alien/patches \
		$(DESTDIR)/var/lib/alien
	cp -fr lib/* $(DESTDIR)/$(PREFIX)/share/alien
	cp -f patches/* $(DESTDIR)/$(PREFIX)/share/alien/patches/
	-rm -f $(DESTDIR)/$(PREFIX)/share/alien/patches/*.gz
	gzip -qf9 $(DESTDIR)/$(PREFIX)/share/alien/patches/*
	install -d $(DESTDIR)/$(PREFIX)/share/man/man1
	cp -f alien.1 $(DESTDIR)/$(PREFIX)/share/man/man1

# This updates the version number in various files.
version:
	@echo Updating version info....
	perl -i -pe "s/\@version\@/$(VER)/g" <alien.spec.in >alien.spec
	perl -i -pe "s/\@version\@/$(VER)/g" <alien.lsm.in >alien.lsm

debian:
	dpkg-buildpackage -tc -rfakeroot

rpm: version
	install -d /home/joey/src/redhat/SOURCES
	install -d /home/joey/src/redhat/BUILD
	install -d /home/joey/src/redhat/SRPMS
	install -d /home/joey/src/redhat/RPMS/noarch
	ln -sf /home/ftp/pub/code/debian/alien_$(VER).tar.gz \
		/home/joey/src/redhat/SOURCES/alien_$(VER).tar.gz
	sudo rpm -ba -v alien.spec --target noarch
	rm -f /home/joey/src/redhat/SOURCES/alien_$(VER).tar.gz
	mv /home/joey/src/redhat/SRPMS/* /home/ftp/pub/code/SRPMS
	mv /home/joey/src/redhat/RPMS/noarch/* /home/ftp/pub/code/RPMS/noarch
	sudo rm -rf /home/joey/src/redhat/SOURCES \
		/home/joey/src/redhat/BUILD \
		/home/joey/src/redhat/SRPMS \
		/home/joey/src/redhat/RPMS/

.PHONY: debian
