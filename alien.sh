#!/bin/sh

# Script to handle alien packages under Debian
#
# Options:
# -p<Patch> 	Manually specify a patch
# -n		Build an alien package using heuristics
# -g		Prepare directories for development
# -s		Like -g, but prepare single directory for debian-only package
# -i		Do not install package after building it.
#
# Christoph Lameter, <clameter@debian.org> October 30, 1996

set -e
#set -v

LIB=/usr/lib/alien

while expr "$1" : '-.*' >/dev/null; do
	case $1 in
		--auto|--nopatch|-n)
			NOPATCH=1
			;;
		--generate|-g)
			GENERATE=1
			;;
		--noinstall|-i)
			NOINSTALL=1
			;;
		--single|-s)
			SINGLE=1
			NOPATCH=1
			NOBUILD=1
			NOINSTALL=1
			;;
		--patch=*)
			PATCHFILE=`expr "$1" : '--patch=\(.*\)'`
			if [ ! -f "$PATCHFILE" ]; then
				echo "$PATCHFILE not found"
				exit 1
			fi
			;;
		-p*)	PATCHFILE=`expr "$1" : '-p\(.*\)'`
			if [ ! -f "$PATCHFILE" ]; then
				echo "$PATCHFILE not found"
				exit 1
			fi
			;;
		*)	echo "Bad option $1"
			exit 1
			;;
	esac
	shift
done

if [ "$NOPATCH" -a "$PATCHFILE" ]; then
	echo "Cannot handle -n and -p options simultaneously"
	exit 1
fi

FILE=$1

if [ "$FILE" = "" ]; then
	echo "Usage: alien [-n] [-i] [-g] [-s] [-p<patchfile>] <filename>"
	exit 1
fi

if [ ! -f $FILE ]; then
	echo "File $FILE not found"
	exit 1
fi

DATE="`822-date`"

# Cut off the directory name
if echo $FILE|grep -q "/"; then
	X=`expr $FILE : '.*/\(.*\)'`
else
	X="$FILE"
fi

if expr $X : '.*\.rpm' >/dev/null; then
	RPM=1
	if [ ! -f /usr/bin/rpm ]; then
		echo "RPM Package Manager not installed"
		exit 1
	fi
	X=`expr $X : '\(.*\)\.rpm'`
else
	case $X in
		*.tgz)		X=`expr $X : '\(.*\).tgz'` ;;
		*.tar.gz)	X=`expr $X : '\(.*\).tar.gz'` ;;
		*) 		echo "Format of filename bad $FILE" ;;
	esac
fi

if [ "$RPM" ]; then
	# Use --queryformat to pull out all the values we need.
	eval `rpm -qp $FILE --queryformat '
		PACKAGE="%{NAME}"
		VERSION="%{VERSION}"
		DELTA="%{RELEASE}"
		ARCHNUM="%{ARCH}"
		CHANGELOG="%{CHANGELOGTEXT}"
		SUMMARY="%{SUMMARY}"
		DESCRIPTION="%{DESCRIPTION}"
		COPYRIGHT="%{COPYRIGHT}"
	'`

	if [ "$SUMMARY" = "" -o "$SUMMARY" = "(none)" ] ; then 
		SUMMARY="Converted RPM package"
	fi

	if [ "$COPYRIGHT" = "" -o "$COPYRIGHT" = "(none)" ] ; then
		COPYRIGHT="unknown"
	fi

	if [ "$CHANGELOG" = "(none)" ] ; then
		CHANGELOG=""
	fi

	# Fix up the description field to debian standards (indented at
        # least one space, no empty lines in it.)
	DESCRIPTION=" $SUMMARY"

	# Convert ARCH number into string, if it isn't already a string.
	case $ARCHNUM in
		1)	ARCHIT=i386
		;;
		2)	ARCHIT=alpha
		;;
		3)	ARCHIT=sparc
		;;
		6)	ARCHIT=m68k
		;;
		i386|alpha|sparc|m68k)
			# Seems that some rpms have the actual arch in them.
			ARCHIT=$ARCHNUM
		;;
	esac

	if [ "$DELTA" = "" -o "$VERSION" = "" -o "$PACKAGE" = "" ]; then
		echo "Error querying rpm file."
		exit 1
	fi
	
	if [ "$ARCHIT" = "" ]; then
		echo "Unable to determine architecture: arch number is $ARCHNUM."
		echo "Please report this as a bug to the maintainer of alien."
		exit 1
	fi

	CDIR=rpm
else
# Generic handling for slackware and tar.gz packages
	if echo $X | grep -q "-"; then
        	PACKAGE=`expr $X : '\(.*\)-.*'`
	        VERSION=`expr $X : '.*-\(.*\)'`
	else
	        PACKAGE=$X
	        VERSION=1
	fi

	if [ "$VERSION" = "" -o "$PACKAGE" = "" ]; then
	        echo "Filename must have the form Package-Version.tgz"
	        exit 1
	fi

	ARCHIT=i386
	DELTA=1
	CDIR=tgz
fi

if [ "$NOPATCH" = "" ]; then
	if [ "$PATCHFILE" = "" ]; then
		PATCHFILE=/var/lib/alien/$PACKAGE*.diff.gz
	fi
	if [ ! -f $PATCHFILE -a "$GENERATE" = "" ]; then
		echo "Patchfile $PATCHFILE not found."
		echo "You may need to rerun this command with -n added to the command line."
		exit 1
	fi
	if [ ! -f $PATCHFILE ]; then
		PATCHFILE=
	fi
fi

mkdir $PACKAGE-$VERSION
cd $PACKAGE-$VERSION
mkdir debian

echo "-- Unpacking $FILE"
if [ "$RPM" ]; then
	(cd ..;rpm2cpio $FILE) | cpio --extract --make-directories --no-absolute-filenames
# install script could be located here.
else
# Must be a tar file
	tar zxpf ../$FILE
	# Make install script to postinst
	if [ -e install/doinst.sh ]; then
       		mv install/doinst.sh debian/postinst
        	if ! rmdir install; then 
                	echo "Other files besides doinst.sh present in install directory"
	                echo "Install script cannot be used as postinst script!"
	                mv debian/postinst install/doinst.sh
        	fi
	fi
fi

if [ "$GENERATE" ]; then
	cd ..
	cp -a $PACKAGE-$VERSION $PACKAGE-$VERSION.orig
	echo "Directories $PACKAGE-$VERSION.orig + $PACKAGE-$VERSION prepared."
	cd $PACKAGE-$VERSION
elif [ "$SINGLE" ]; then
	echo "Directory $PACKAGE-$VERSION prepared."
fi

# Now lets patch it!
if [ "$PATCHFILE" ]; then
	echo "-- Patching in $PATCHFILE"
	# cd .. here in case the patchfile's name was a relative path.
	(cd .. && zcat $PATCHFILE) | patch -p1
	X=`find . -name "*.rej"`
	if [ "$X" ]; then
		echo "Patch failed: giving up"
		exit 1
	fi
	rm `find . -name "*.orig"`
else
	echo "-- Automatic package debianization"
	# Generate all the values we need
	if [ "$EMAIL" = "" ]; then
	        EMAIL="$USER@`cat /etc/mailname`"
	fi
	USERNAME=`awk -F: -vUSER=$USER '$1 == USER { print $5; }' /etc/passwd`

	if [ "$USERNAME" = "" -a -x /usr/bin/ypmatch ]; then
		# Give NIS a try
		USERNAME=`ypmatch $USER passwd.byname|awk -F: '{ print $5; }'`
	fi

	if echo $USERNAME | grep -q "\,"; then
        	X=`expr index "$USERNAME" ","`
	        X=`expr $X - 1`
		USERNAME=`expr substr "$USERNAME" 1 $X`
	fi

	cd debian
	X=`(cd $LIB/$CDIR;ls)`
	for i in $X; do
		sed <$LIB/$CDIR/$i >$i -e "s/#PACKAGE#/$PACKAGE/g" \
		-e "s/#VERSION#/$VERSION/g" \
		-e "s/#DELTA#/$DELTA/g" \
		-e "s/#ARCHIT#/$ARCHIT/g" \
                -e "s/#EMAIL#/$EMAIL/g" \
                -e "s/#USERNAME#/$USERNAME/g" \
		-e "s/#CHANGELOG#/$CHANGELOG/g" \
		-e "s/#SUMMARY#/$SUMMARY/g" \
		-e "s/#DESCRIPTION#/$DESCRIPTION/g" \
		-e "s/#COPYRIGHT#/$COPYRIGHT/g" \
		-e "s/#DATE#/$DATE/g"
	done

	if [ "$RPM" ]; then
		(cd ../..;rpm -qpi $FILE) >>copyright
	fi

	cd ..
	# Assume all files in etc are conffiles
	if [ -d etc ]; then
		find etc -type f -printf "/%p\n" >debian/conffiles
	fi
fi

chmod a+x debian/rules

if [ "$GENERATE" = "" -a "$NOBUILD" = "" ]; then
	echo "-- Building the package $PACKAGE-$VERSION-$DELTA.deb"
	debian/rules binary
	cd ..
	rm -rf $PACKAGE-$VERSION
fi

if [ "$NOINSTALL" = "" -a "$GENERATE" = "" ]; then
	echo "-- Installing generated .deb package"
	dpkg -i $PACKAGE*.deb
	rm $PACKAGE\_$VERSION-$DELTA*.deb
fi

echo "-- Successfully finished"
exit 0



