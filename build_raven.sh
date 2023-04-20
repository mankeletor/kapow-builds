#!/bin/bash

# Definir variables de color
rojo='\e[0m\e[1;31m'
verde='\033[0;32m'
amarillo='\e[1;33m'
azul='\033[0;34m'
morado='\033[0;35m'
cyan='\033[0;36m'
fin_color='\033[0m'

RAVENCOIN_ROOT=$(pwd)
NAME="raven"
VERSION="4.6.1"
PKG=$NAME-$VERSION

echo -ne "${azul}In order to build deb binary package I'll need your sudo pass: "
read -s PASS
echo ""

# Pick some path to install BDB to, here we create a directory within the Clore directory
BDB_PREFIX="${RAVENCOIN_ROOT}/db4"
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

echo -e "${amarillo}=======DB48 Fix perms=======${fin_color}"

find . \
  \( -perm 777 -o -perm 775 -o -perm 711 -o -perm 555 -o -perm 511 \) \
  -exec chmod 755 {} \; -o \
  \( -perm 666 -o -perm 664 -o -perm 600 -o -perm 444 -o -perm 440 -o -perm 400 \) \
  -exec chmod 644 {} \;

cat << EOF > db-4.8.30.NC/dbinc/atomic.h
/*
 * See the file LICENSE for redistribution information.
 *
 * Copyright (c) 2009 Oracle.  All rights reserved.
 *
 * $Id$
 */

#ifndef _DB_ATOMIC_H_
#define	_DB_ATOMIC_H_

#if defined(__cplusplus)
extern "C" {
#endif

/*
 *	Atomic operation support for Oracle Berkeley DB
 *
 * HAVE_ATOMIC_SUPPORT configures whether to use the assembly language
 * or system calls to perform:
 *
 *	 atomic_inc(env, valueptr)
 *	    Adds 1 to the db_atomic_t value, returning the new value.
 *
 *	 atomic_dec(env, valueptr)
 *	    Subtracts 1 from the db_atomic_t value, returning the new value.
 *
 *	 atomic_compare_exchange(env, valueptr, oldval, newval)
 *	    If the db_atomic_t's value is still oldval, set it to newval.
 *	    It returns 1 for success or 0 for failure.
 *
 * The ENV * paramter is used only when HAVE_ATOMIC_SUPPORT is undefined.
 *
 * If the platform does not natively support any one of these operations,
 * then atomic operations will be emulated with this sequence:
 *		MUTEX_LOCK()
 *		<op>
 *		MUTEX_UNLOCK();
 * Uses where mutexes are not available (e.g. the environment has not yet
 * attached to the mutex region) must be avoided.
 */
#if defined(DB_WIN32)
typedef DWORD	atomic_value_t;
#else
typedef int32_t	 atomic_value_t;
#endif

/*
 * Windows CE has strange issues using the Interlocked APIs with variables
 * stored in shared memory. It seems like the page needs to have been written
 * prior to the API working as expected. Work around this by allocating an
 * additional 32-bit value that can be harmlessly written for each value
 * used in Interlocked instructions.
 */
#if defined(DB_WINCE)
typedef struct {
	volatile atomic_value_t value;
	volatile atomic_value_t dummy;
} db_atomic_t;
#else
typedef struct {
	volatile atomic_value_t value;
} db_atomic_t;
#endif

/*
 * These macro hide the db_atomic_t structure layout and help detect
 * non-atomic_t actual argument to the atomic_xxx() calls. DB requires
 * aligned 32-bit reads to be atomic even outside of explicit 'atomic' calls.
 * These have no memory barriers; the caller must include them when necessary.
 */
#define	atomic_read(p)		((p)->value)
#define	atomic_init(p, val)	((p)->value = (val))

#ifdef HAVE_ATOMIC_SUPPORT

#if defined(DB_WIN32)
#if defined(DB_WINCE)
#define	WINCE_ATOMIC_MAGIC(p)						\
	/*								\
	 * Memory mapped regions on Windows CE cause problems with	\
	 * InterlockedXXX calls. Each page in a mapped region needs to	\
	 * have been written to prior to an InterlockedXXX call, or the	\
	 * InterlockedXXX call hangs. This does not seem to be		\
	 * documented anywhere. For now, read/write a non-critical	\
	 * piece of memory from the shared region prior to attempting	\
	 * shared region prior to attempting an InterlockedExchange	\
	 * InterlockedXXX operation.					\
	 */								\
	(p)->dummy = 0
#else
#define	WINCE_ATOMIC_MAGIC(p) 0
#endif

#if defined(DB_WINCE) || (defined(_MSC_VER) && _MSC_VER < 1300)
/*
 * The Interlocked instructions on Windows CE have different parameter
 * definitions. The parameters lost their 'volatile' qualifier,
 * cast it away, to avoid compiler warnings.
 * These definitions should match those in dbinc/mutex_int.h for tsl_t, except
 * that the WINCE version drops the volatile qualifier.
 */
typedef PLONG interlocked_val;
#define	atomic_inc(env, p)						\
	(WINCE_ATOMIC_MAGIC(p),						\
	InterlockedIncrement((interlocked_val)(&(p)->value)))

#else
typedef LONG volatile *interlocked_val;
#define	atomic_inc(env, p)	\
	InterlockedIncrement((interlocked_val)(&(p)->value))
#endif

#define	atomic_dec(env, p)						\
	(WINCE_ATOMIC_MAGIC(p),						\
	InterlockedDecrement((interlocked_val)(&(p)->value)))
#if defined(_MSC_VER) && _MSC_VER < 1300
#define	atomic_compare_exchange(env, p, oldval, newval)			\
	(WINCE_ATOMIC_MAGIC(p),						\
	(InterlockedCompareExchange((PVOID *)(&(p)->value),		\
	(PVOID)(newval), (PVOID)(oldval)) == (PVOID)(oldval)))
#else
#define	atomic_compare_exchange(env, p, oldval, newval)			\
	(WINCE_ATOMIC_MAGIC(p),						\
	(InterlockedCompareExchange((interlocked_val)(&(p)->value),	\
	(newval), (oldval)) == (oldval)))
#endif
#endif

#if defined(HAVE_ATOMIC_SOLARIS)
/* Solaris sparc & x86/64 */
#include <atomic.h>
#define	atomic_inc(env, p)	\
	atomic_inc_uint_nv((volatile unsigned int *) &(p)->value)
#define	atomic_dec(env, p)	\
	atomic_dec_uint_nv((volatile unsigned int *) &(p)->value)
#define	atomic_compare_exchange(env, p, oval, nval)		\
	(atomic_cas_32((volatile unsigned int *) &(p)->value,	\
	    (oval), (nval)) == (oval))
#endif

#if defined(HAVE_ATOMIC_X86_GCC_ASSEMBLY)
/* x86/x86_64 gcc  */
#define	atomic_inc(env, p)	__atomic_inc(p)
#define	atomic_dec(env, p)	__atomic_dec(p)
#define	atomic_compare_exchange(env, p, o, n)	\
	__atomic_compare_pexchange((p), (o), (n))
static inline int __atomic_inc(db_atomic_t *p)
{
	int	temp;

	temp = 1;
	__asm__ __volatile__("lock; xadd %0, (%1)"
		: "+r"(temp)
		: "r"(p));
	return (temp + 1);
}

static inline int __atomic_dec(db_atomic_t *p)
{
	int	temp;

	temp = -1;
	__asm__ __volatile__("lock; xadd %0, (%1)"
		: "+r"(temp)
		: "r"(p));
	return (temp - 1);
}

/*
 * x86/gcc Compare exchange for shared latches. i486+
 *	Returns 1 for success, 0 for failure
 *
 * GCC 4.1+ has an equivalent  __sync_bool_compare_and_swap() as well as
 * __sync_val_compare_and_swap() which returns the value read from *dest
 * http://gcc.gnu.org/onlinedocs/gcc-4.1.0/gcc/Atomic-Builtins.html
 * which configure could be changed to use.
 */
static inline int __atomic_compare_pexchange(
	db_atomic_t *p, atomic_value_t oldval, atomic_value_t newval)
{
	atomic_value_t was;

	if (p->value != oldval)	/* check without expensive cache line locking */
		return 0;
	__asm__ __volatile__("lock; cmpxchgl %1, (%2);"
	    :"=a"(was)
	    :"r"(newval), "r"(p), "a"(oldval)
	    :"memory", "cc");
	return (was == oldval);
}
#endif

#else
/*
 * No native hardware support for atomic increment, decrement, and
 * compare-exchange. Emulate them when mutexes are supported;
 * do them without concern for atomicity when no mutexes.
 */
#ifndef HAVE_MUTEX_SUPPORT
/*
 * These minimal versions are correct to use only for single-threaded,
 * single-process environments.
 */
#define	atomic_inc(env, p)	(++(p)->value)
#define	atomic_dec(env, p)	(--(p)->value)
#define	atomic_compare_exchange(env, p, oldval, newval)		\
	(DB_ASSERT(env, atomic_read(p) == (oldval)),		\
	atomic_init(p, (newval)), 1)
#else
#define atomic_inc(env, p)	__atomic_inc(env, p)
#define atomic_dec(env, p)	__atomic_dec(env, p)
#endif
#endif

#if defined(__cplusplus)
}
#endif

#endif /* !_DB_ATOMIC_H_ */
EOF

# Build the library and install to our prefix
cd db-4.8.30.NC/build_unix/
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
cd $RAVENCOIN_ROOT 
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
make install DESTDIR=$RAVENCOIN_ROOT/tmp-destdir
echo -e "${amarillo}=======Building package=======${fin_color}"
cd $RAVENCOIN_ROOT/tmp-destdir
mkdir -p ./usr/share/applications
mkdir -p ./usr/share/icons
cp ../share/pixmaps/raven128.png ./usr/share/icons/raven128.png
echo '
#!/usr/bin/env xdg-open

[Desktop Entry]
Encoding=UTF-8
Name=Raven Core
Comment=Connect to the Raven P2P Network
Comment[de]=Verbinde mit dem Raven peer-to-peer Netzwerk
Comment[fr]=Raven, monnaie virtuelle cryptographique pair à pair
Comment[tr]=Raven, eşten eşe kriptografik sanal para birimi
Exec=raven-qt %u
Terminal=false
Type=Application
Icon=raven128.png
MimeType=x-scheme-handler/raven;
Categories=Network;Finance;
' > ./usr/share/applications/meowcoincoin.desktop

find -type d -name 'man' -exec find {} -type f \; | while read line; do gzip -9 $line; done
find -type f | xargs file | grep -e "executable" -e "shared object" | grep ELF \
  | cut -f 1 -d : | xargs strip --strip-unneeded 2> /dev/null
tar cf $PKG.tar ./
echo $PASS | sudo -S alien $PKG.tar $PKG.deb --description="Ravencoin Core is the original \
Ravencoin client and it builds the backbone of the network. It downloads and, by default, \
stores the entire history of Ravencoin transactions; depending on the speed of your \
computer and network connection, the synchronization process is typically complete in under an hour. \
\
<package by mankeletor>"
rm -f $PKG.tar
