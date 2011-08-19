(
redo-ifchange config
source ./config

redo all

./alien.pl -r "alien-$VER"

) >&2
