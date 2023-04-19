# kapow-builds
Most mined kawpaw coins builds for linux (deb/ubuntu and based distros)

# Available scripts

#meowcoin

#neoxa

#clore

#paprikacoin

# Linux wallet releases didn't worked

I decided to work around the original scripts on doc/build_with_db 4_linux.sh once the binary release doesn't work for me. 
I noticed the only files on that releases was like 3 binaries but the statics and dinamics libs needed (and many other files)
for run the program are not present on it.

# Start build
You must to be sure to have alien installed

sudo apt install alien

get the <source_tarball>.tar.gz

tar xf <sorce_tarball>.tar.gz

copy the build script on <source_tarball>

cd <source_tarball>

chmod 755 build_script.sh

./build_scrit.sh

When it done a debian package should be created on tmp-destdir/<packagename>.deb

You could ignore the alien warning "package not found"
