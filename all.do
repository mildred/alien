(
redo-ifchange config
source ./config

perl Makefile.PL
sed -i 's:/usr/local:/usr:g' Makefile
make

outdir="alien-$VER"

rm -rf $outdir
mkdir -p $outdir/usr/bin
make PREFIX="`pwd`/$outdir/usr" VARPREFIX="`pwd`/$outdir" DESTDIR="`pwd`/$outdir" install

) >&2
