Summary: Install Debian and Slackware Packages with rpm.
Name: alien
Packager: Joey Hess <joey@kitenet.net>
Version: 6.59
Release: 1
Source: ftp://kitenet.net/pub/code/debian/alien_6.59.tar.gz
Copyright: GPL
Group: Utilities/File
Buildroot: /tmp/alien-6.59.build
Requires: perl

%description
Alien allows you to convert Debian, Slackware, and Stampede Packages into Red
Hat packages, which can be installed with rpm.

It can also convert into Slackware, Debian and Stampede packages.

This is a tool only suitable for binary packages.

%prep
%setup -n alien
rm -r /tmp/alien-6.59.build || true

%install
make DESTDIR=$RPM_BUILD_ROOT install
chown -R root.root $RPM_BUILD_ROOT
find $RPM_BUILD_ROOT -not -type d -printf "/%%P\n" > manifest

%files -f manifest
%doc CHANGES COPYING README alien.lsm
