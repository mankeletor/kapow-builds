#!/bin/bash

# Definir variables de color
rojo='\e[0m\e[1;31m'
verde='\033[0;32m'
amarillo='\e[1;33m'
azul='\033[0;34m'
morado='\033[0;35m'
cyan='\033[0;36m'
fin_color='\033[0m'

NEOXA_ROOT=$(pwd)
NAME="neoxa"
VERSION=$(head -1 release-linux.sh | cut -d= -f2)
PKG=$NAME-$VERSION

echo -ne "${azul}In order to build deb binary package I'll need your sudo pass: "
read -s PASS
echo ""

# Pick some path to install BDB to, here we create a directory within the Clore directory
BDB_PREFIX="${NEOXA_ROOT}/db4"
mkdir -p $BDB_PREFIX

echo -e "${amarillo}=======Get Berkley DB 4.8 source tarball=======${fin_color}"

# Fetch the source and verify that it is not tampered with
wget -c 'http://download.oracle.com/berkeley-db/db-4.8.30.NC.tar.gz'
echo '12edc0df75bf9abd7f82f821795bcee50f42cb2e5f76a6a281b85732798364ef  db-4.8.30.NC.tar.gz' | sha256sum -c
# -> db-4.8.30.NC.tar.gz: OK

if [ ! -d "db-4.8.30.NC" ]; then
    tar xvf db-4.8.30.NC.tar.gz
fi

# copy patch to fix error in db4
echo -e "${amarillo}=======DB48 Aplies patch=======${fin_color}"
chmod a+w ./db-4.8.30.NC/dbinc/atomic.h
cp ./depends/patches/atomic.h db-4.8.30.NC/dbinc/
echo -e "${amarillo}=======DB48 Fix perms=======${fin_color}"

# Build the library and install to our prefix
cd db-4.8.30.NC/build_unix/
find ../ \
  \( -perm 777 -o -perm 775 -o -perm 711 -o -perm 555 -o -perm 511 \) \
  -exec chmod 755 {} \; -o \
  \( -perm 666 -o -perm 664 -o -perm 600 -o -perm 444 -o -perm 440 -o -perm 400 \) \
  -exec chmod 644 {} \;
#  Note: Do a static build so that it can be embedded into the executable, instead of having to find a .so at runtime
echo -e "${amarillo}=======DB48 configure=======${fin_color}"
../dist/configure --enable-cxx --disable-shared --with-pic --prefix=$BDB_PREFIX 
echo -e "${amarillo}=======DB48 make=======${fin_color}"
make -j$(nproc) 
echo -e "${amarillo}=======DB48 strip=======${fin_color}"
find -type f | xargs file | grep -e "executable" -e "shared object" | grep ELF \
  | cut -f 1 -d : | xargs strip --strip-unneeded 2> /dev/null || true
echo -e "${amarillo}=======DB48 make install (custom prefix)=======${fin_color}"
make install 

# Configure Clore Core to use our own-built instance of BDB
echo -e "${amarillo}=======Configure ${PKG} built instance=======${fin_color}"
cd $NEOXA_ROOT 
cd depends
chmod +x config.guess config.sub
make -j$(nproc) HOST=x86_64-pc-linux-gnu
cd ..

if [ ! -f "./configure" ]; then
    chmod 755 autogen.sh
    ./autogen.sh 
fi

echo -e "${amarillo}=======$PKG configure=======${fin_color}"
#CONFIG_SITE=$PWD/depends/x86_64-pc-linux-gnu/share/config.site ./configure  --prefix=$PWD/depends/x86_64-pc-linux-gnu --enable-cxx --disable-shared --disable-tests --disable-gui-tests --enable-static=yes --with-pic LDFLAGS="-L${BDB_PREFIX}/lib/" CPPFLAGS="-I${BDB_PREFIX}/include/" # (other args...) 
CONFIG_SITE=$PWD/depends/x86_64-pc-linux-gnu/share/config.site ./configure  \
--prefix=/usr --enable-cxx --disable-shared \
--disable-tests --disable-gui-tests --with-pic LDFLAGS="-L${BDB_PREFIX}/lib/" \
CPPFLAGS="-I${BDB_PREFIX}/include/" --with-gui=qt5 

echo -e "${amarillo}=======$PKG make=======${fin_color}"
find -name 'genbuild.sh' -exec chmod 755 {} \;
make -j$(nproc) 
echo -e "${amarillo}=======$PKG make install=======${fin_color}"
make install DESTDIR=$NEOXA_ROOT/tmp-destdir
echo -e "${amarillo}=======Building package=======${fin_color}"
cd $NEOXA_ROOT/tmp-destdir
mkdir -p ./usr/share/applications
mkdir -p ./usr/share/icons
cp ../share/pixmaps/neoxa128.png ./usr/share/icons/
echo '
#!/usr/bin/env xdg-open

[Desktop Entry]
Version=1.0
Type=Application
Terminal=false
Exec=/usr/bin/neoxa-qt
Name=neoxacoin
Comment= neoxa coin wallet
Icon=/usr/share/icons/neoxa128.png
' > ./usr/share/applications/neoxacoin.desktop
find -type d -name 'man' -exec find {} -type f \; | while read line; do gzip -9 $line; done
find -type f | xargs file | grep -e "executable" -e "shared object" | grep ELF \
  | cut -f 1 -d : | xargs strip --strip-unneeded 2> /dev/null
tar cf $PKG.tar ./
echo $PASS | sudo -S alien $PKG.tar $PKG.deb --description="Neoxa Core is the original Neoxa \
client and it builds the backbone of the network. It downloads and, by default, stores the entire \
history of Neoxa transactions; depending on the speed of your computer and network connection, \
the synchronization process is typically complete in under an hour. \
<package by mankeletor>"
rm -f $PKG.tar
