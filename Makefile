# This makefile is really small. Most of the
# intelligence is in debian/debstd

all:

clean:
	-rm build

install:	
	install -d $(DESTDIR)/usr/bin
	install alien $(DESTDIR)/usr/bin
	install -d $(DESTDIR)/usr/lib/alien $(DESTDIR)/var/lib/alien
	cp -a lib/* $(DESTDIR)/usr/lib/alien
