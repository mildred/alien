Summary: Install Debian and Slackware Packages with dpkg.
Name: alien
Packager: Joey Hess <joey@kite.ml.org>
Version: 4.00
Release: 1
Source: ftp://kite.ml.org/pub/code/debian/alien_4.00.tar.gz
Copyright: GPL
Group: Utilities/File
Buildroot: /tmp/alien-4.00.build

%description
Alien allows you to convert Debian and Slackware Packages into Red Hat
packages, which can be installed with rpm.

It can also convert Red Hat and Slackware packages into Debian packages.

This is a tool only suitable for binary packages.

%prep
%setup

%install
make DESTDIR=$RPM_BUILD_ROOT install
find $RPM_BUILD_ROOT -type f -printf "/%P\n" > manifest

%files -f manifest
