#!/bin/bash
#
# CloneNux toolchain build script
# Optional parameteres below:
set +h
set -o nounset
set -o errexit
umask 022

export LC_ALL=POSIX
export CONFIG_HOST=`echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/'`

export CFLAGS="-O2 -I$TOOLS_DIR/include"
export CPPFLAGS="-O2 -I$TOOLS_DIR/include"
export CXXFLAGS="-O2 -I$TOOLS_DIR/include"
export LDFLAGS="-L$TOOLS_DIR/lib -Wl,-rpath,$TOOLS_DIR/lib"

export PKG_CONFIG="$TOOLS_DIR/bin/pkg-config"
export PKG_CONFIG_SYSROOT_DIR="/"
export PKG_CONFIG_LIBDIR="$TOOLS_DIR/lib/pkgconfig:$TOOLS_DIR/share/pkgconfig"
export PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=1
export PKG_CONFIG_ALLOW_SYSTEM_LIBS=1

CONFIG_PKG_VERSION="CloneNux x86_64 2021.02"
CONFIG_BUG_URL="https://github.com/LeeKyuHyuk/CloneNux/issues"

# End of optional parameters
function step() {
    echo -e "\e[7m\e[1m>>> $1\e[0m"
}

function success() {
    echo -e "\e[1m\e[32m$1\e[0m"
}

function error() {
    echo -e "\e[1m\e[31m$1\e[0m"
}

function extract() {
    case $1 in
        *.tgz) tar -zxf $1 -C $2 ;;
        *.tar.gz) tar -zxf $1 -C $2 ;;
        *.tar.bz2) tar -jxf $1 -C $2 ;;
        *.tar.xz) tar -Jxf $1 -C $2 ;;
    esac
}

function check_environment_variable {
    if ! [[ -d $SOURCES_DIR ]] ; then
        error "Please download tarball files!"
        error "Run 'make download'."
        exit 1
    fi
}

function check_tarballs {
    LIST_OF_TARBALLS="
    "

    for tarball in $LIST_OF_TARBALLS ; do
        if ! [[ -f $SOURCES_DIR/$tarball ]] ; then
            error "Can't find '$tarball'!"
            exit 1
        fi
    done
}

function do_strip {
    set +o errexit
    if [[ $CONFIG_STRIP_AND_DELETE_DOCS = 1 ]] ; then
        strip --strip-debug $TOOLS_DIR/lib/*
        strip --strip-unneeded $TOOLS_DIR/{,s}bin/*
        rm -rf $TOOLS_DIR/{,share}/{info,man,doc}
    fi
}

function timer {
    if [[ $# -eq 0 ]]; then
        echo $(date '+%s')
    else
        local stime=$1
        etime=$(date '+%s')
        if [[ -z "$stime" ]]; then stime=$etime; fi
        dt=$((etime - stime))
        ds=$((dt % 60))
        dm=$(((dt / 60) % 60))
        dh=$((dt / 3600))
        printf '%02d:%02d:%02d' $dh $dm $ds
    fi
}

check_environment_variable
check_tarballs
total_build_time=$(timer)

step "[1/23] Create toolchain directory."
rm -rf $BUILD_DIR $TOOLS_DIR
mkdir -pv $BUILD_DIR $TOOLS_DIR
ln -svf . $TOOLS_DIR/usr

step "[2/23] Create the sysroot directory"
mkdir -pv $SYSROOT_DIR
ln -svf . $SYSROOT_DIR/usr
mkdir -pv $SYSROOT_DIR/lib
if [[ "$CONFIG_LINUX_ARCH" = "i386" ]] ; then
    ln -snvf lib $SYSROOT_DIR/lib32
fi
if [[ "$CONFIG_LINUX_ARCH" = "x86_64" ]] ; then
    ln -snvf lib $SYSROOT_DIR/lib64
fi

step "[3/23] Pkgconf 1.7.3"
extract $SOURCES_DIR/pkgconf-1.7.3.tar.xz $BUILD_DIR
( cd $BUILD_DIR/pkgconf-1.7.3 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --disable-dependency-tracking )
make -j$PARALLEL_JOBS -C $BUILD_DIR/pkgconf-1.7.3
make -j$PARALLEL_JOBS install -C $BUILD_DIR/pkgconf-1.7.3
cat > $TOOLS_DIR/bin/pkg-config << "EOF"
#!/bin/sh
PKGCONFDIR=$(dirname $0)
DEFAULT_PKG_CONFIG_LIBDIR=${PKGCONFDIR}/../@STAGING_SUBDIR@/usr/lib/pkgconfig:${PKGCONFDIR}/../@STAGING_SUBDIR@/usr/share/pkgconfig
DEFAULT_PKG_CONFIG_SYSROOT_DIR=${PKGCONFDIR}/../@STAGING_SUBDIR@
DEFAULT_PKG_CONFIG_SYSTEM_INCLUDE_PATH=${PKGCONFDIR}/../@STAGING_SUBDIR@/usr/include
DEFAULT_PKG_CONFIG_SYSTEM_LIBRARY_PATH=${PKGCONFDIR}/../@STAGING_SUBDIR@/usr/lib

PKG_CONFIG_LIBDIR=${PKG_CONFIG_LIBDIR:-${DEFAULT_PKG_CONFIG_LIBDIR}} \
	PKG_CONFIG_SYSROOT_DIR=${PKG_CONFIG_SYSROOT_DIR:-${DEFAULT_PKG_CONFIG_SYSROOT_DIR}} \
	PKG_CONFIG_SYSTEM_INCLUDE_PATH=${PKG_CONFIG_SYSTEM_INCLUDE_PATH:-${DEFAULT_PKG_CONFIG_SYSTEM_INCLUDE_PATH}} \
	PKG_CONFIG_SYSTEM_LIBRARY_PATH=${PKG_CONFIG_SYSTEM_LIBRARY_PATH:-${DEFAULT_PKG_CONFIG_SYSTEM_LIBRARY_PATH}} \
	exec ${PKGCONFDIR}/pkgconf @STATIC@ "$@"
EOF
chmod 755 $TOOLS_DIR/bin/pkg-config
sed -i -e "s,@STAGING_SUBDIR@,$SYSROOT_DIR,g" $TOOLS_DIR/bin/pkg-config
sed -i -e "s,@STATIC@,," $TOOLS_DIR/bin/pkg-config
rm -rf $BUILD_DIR/pkgconf-1.7.3

step "[4/23] M4 1.4.18"
extract $SOURCES_DIR/m4-1.4.18.tar.xz $BUILD_DIR
patch -Np1 -i $SUPPORT_DIR/m4/fflush-adjust-to-glibc-2.28-libio.h-removal.patch -d $BUILD_DIR/m4-1.4.18
( cd $BUILD_DIR/m4-1.4.18 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/m4-1.4.18
make -j$PARALLEL_JOBS install -C $BUILD_DIR/m4-1.4.18
rm -rf $BUILD_DIR/m4-1.4.18

step "[5/23] Libtool 2.4.6"
extract $SOURCES_DIR/libtool-2.4.6.tar.xz $BUILD_DIR
( cd $BUILD_DIR/libtool-2.4.6 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/libtool-2.4.6
make -j$PARALLEL_JOBS install -C $BUILD_DIR/libtool-2.4.6
rm -rf $BUILD_DIR/libtool-2.4.6

step "[6/23] Autoconf 2.71"
extract $SOURCES_DIR/autoconf-2.71.tar.xz $BUILD_DIR
( cd $BUILD_DIR/autoconf-2.71 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/autoconf-2.71
make -j$PARALLEL_JOBS install -C $BUILD_DIR/autoconf-2.71
rm -rf $BUILD_DIR/autoconf-2.71

step "[7/23] Automake 1.16.3"
extract $SOURCES_DIR/automake-1.16.3.tar.xz $BUILD_DIR
( cd $BUILD_DIR/automake-1.16.3 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/automake-1.16.3
make -j$PARALLEL_JOBS install -C $BUILD_DIR/automake-1.16.3
mkdir -p $SYSROOT_DIR/usr/share/aclocal
rm -rf $BUILD_DIR/automake-1.16.3

step "[8/23] Bison 3.7.5"
extract $SOURCES_DIR/bison-3.7.5.tar.xz $BUILD_DIR
( cd $BUILD_DIR/bison-3.7.5 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/bison-3.7.5
make -j$PARALLEL_JOBS install -C $BUILD_DIR/bison-3.7.5
rm -rf $BUILD_DIR/bison-3.7.5

step "[9/23] Gawk 5.1.0"
extract $SOURCES_DIR/gawk-5.1.0.tar.xz $BUILD_DIR
( cd $BUILD_DIR/gawk-5.1.0 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --without-readline \
    --without-mpfr )
make -j$PARALLEL_JOBS -C $BUILD_DIR/gawk-5.1.0
make -j$PARALLEL_JOBS install -C $BUILD_DIR/gawk-5.1.0
rm -rf $BUILD_DIR/gawk-5.1.0

step "[10/23] Flex 2.6.4"
extract $SOURCES_DIR/flex-2.6.3.tar.gz $BUILD_DIR
( cd $BUILD_DIR/flex-2.6.3 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --disable-doc )
make -j$PARALLEL_JOBS -C $BUILD_DIR/flex-2.6.3
make -j$PARALLEL_JOBS install -C $BUILD_DIR/flex-2.6.3
rm -rf $BUILD_DIR/flex-2.6.3

step "[11/23] Zlib 1.2.11"
extract $SOURCES_DIR/zlib-1.2.11.tar.xz $BUILD_DIR
( cd $BUILD_DIR/zlib-1.2.11 && ./configure --prefix=$TOOLS_DIR )
make -j1 -C $BUILD_DIR/zlib-1.2.11
make -j1 install -C $BUILD_DIR/zlib-1.2.11
rm -rf $BUILD_DIR/zlib-1.2.11

step "[12/23] Elfutils 0.183"
extract $SOURCES_DIR/elfutils-0.183.tar.bz2 $BUILD_DIR
( cd $BUILD_DIR/elfutils-0.183 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared \
    --disable-libdebuginfod \
    --disable-debuginfod )
make -j$PARALLEL_JOBS -C $BUILD_DIR/elfutils-0.183
make -j$PARALLEL_JOBS install -C $BUILD_DIR/elfutils-0.183
rm -rf $BUILD_DIR/elfutils-0.183

step "[13/23] Openssl 1.1.1i"
extract $SOURCES_DIR/openssl-1.1.1i.tar.gz $BUILD_DIR
( cd $BUILD_DIR/openssl-1.1.1i && \
    ./config \
    --prefix=$TOOLS_DIR \
    --openssldir=$TOOLS_DIR/etc/ssl \
    --libdir=lib \
    no-tests \
    no-fuzz-libfuzzer \
    no-fuzz-afl \
    shared \
    zlib-dynamic )
make -j$PARALLEL_JOBS -C $BUILD_DIR/openssl-1.1.1i
make -j$PARALLEL_JOBS install -C $BUILD_DIR/openssl-1.1.1i
rm -rf $BUILD_DIR/openssl-1.1.1i

step "[14/23] Dosfstools 4.2"
extract $SOURCES_DIR/dosfstools-4.2.tar.gz $BUILD_DIR
( cd $BUILD_DIR/dosfstools-4.2 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-compat-symlinks \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/dosfstools-4.2
make -j$PARALLEL_JOBS install -C $BUILD_DIR/dosfstools-4.2
rm -rf $BUILD_DIR/dosfstools-4.2

step "[15/23] Mtools 4.0.26"
extract $SOURCES_DIR/mtools-4.0.26.tar.bz2 $BUILD_DIR
( cd $BUILD_DIR/mtools-4.0.26 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/mtools-4.0.26
make -j$PARALLEL_JOBS install -C $BUILD_DIR/mtools-4.0.26
rm -rf $BUILD_DIR/mtools-4.0.26

step "[16/23] libconfuse 3.3"
extract $SOURCES_DIR/confuse-3.3.tar.xz $BUILD_DIR
( cd $BUILD_DIR/confuse-3.3 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/confuse-3.3
make -j$PARALLEL_JOBS install -C $BUILD_DIR/confuse-3.3
rm -rf $BUILD_DIR/confuse-3.3

step "[17/23] Genimage 14"
extract $SOURCES_DIR/genimage-14.tar.xz $BUILD_DIR
( cd $BUILD_DIR/genimage-14 && \
    ./configure \
    --prefix=$TOOLS_DIR \
    --disable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/genimage-14
make -j$PARALLEL_JOBS install -C $BUILD_DIR/genimage-14
rm -rf $BUILD_DIR/genimage-14

step "[18/23] Binutils 2.36.1"
extract $SOURCES_DIR/binutils-2.36.1.tar.xz $BUILD_DIR
mkdir -pv $BUILD_DIR/binutils-2.36.1/binutils-build
( cd $BUILD_DIR/binutils-2.36.1/binutils-build && \
    $BUILD_DIR/binutils-2.36.1/configure \
    --prefix=$TOOLS_DIR \
    --target=$CONFIG_TARGET \
    --disable-multilib \
    --disable-nls \
    --with-sysroot=$SYSROOT_DIR )
make -j$PARALLEL_JOBS configure-host -C $BUILD_DIR/binutils-2.36.1/binutils-build
make -j$PARALLEL_JOBS -C $BUILD_DIR/binutils-2.36.1/binutils-build
make -j$PARALLEL_JOBS install -C $BUILD_DIR/binutils-2.36.1/binutils-build
rm -rf $BUILD_DIR/binutils-2.36.1

step "[19/23] Gcc 10.2.0 - Static"
tar -Jxf $SOURCES_DIR/gcc-10.2.0.tar.xz -C $BUILD_DIR
extract $SOURCES_DIR/gmp-6.2.1.tar.xz $BUILD_DIR/gcc-10.2.0
mv -v $BUILD_DIR/gcc-10.2.0/gmp-6.2.1 $BUILD_DIR/gcc-10.2.0/gmp
extract $SOURCES_DIR/mpfr-4.1.0.tar.xz $BUILD_DIR/gcc-10.2.0
mv -v $BUILD_DIR/gcc-10.2.0/mpfr-4.1.0 $BUILD_DIR/gcc-10.2.0/mpfr
extract $SOURCES_DIR/mpc-1.2.1.tar.gz $BUILD_DIR/gcc-10.2.0
mv -v $BUILD_DIR/gcc-10.2.0/mpc-1.2.1 $BUILD_DIR/gcc-10.2.0/mpc
mkdir -pv $BUILD_DIR/gcc-10.2.0/gcc-static-build
( cd $BUILD_DIR/gcc-10.2.0/gcc-static-build && \
    MAKEINFO=missing \
    CFLAGS_FOR_TARGET="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -Os" \
    CXXFLAGS_FOR_TARGET="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -Os" \
    $BUILD_DIR/gcc-10.2.0/configure \
    --prefix=$TOOLS_DIR \
    --build=$CONFIG_HOST \
    --host=$CONFIG_HOST \
    --target=$CONFIG_TARGET \
    --disable-decimal-float \
    --disable-libatomic \
    --disable-libgomp \
    --disable-libmudflap \
    --disable-libquadmath \
    --disable-libssp \
    --disable-multilib \
    --disable-nls  \
    --disable-shared \
    --disable-threads \
    --enable-languages=c \
    --with-arch="$CONFIG_GCC_ARCH" \
    --with-bugurl="$CONFIG_BUG_URL" \
    --with-newlib \
    --with-pkgversion="$CONFIG_PKG_VERSION" \
    --with-sysroot=$SYSROOT_DIR \
    --without-headers )
make -j$PARALLEL_JOBS all-gcc all-target-libgcc -C $BUILD_DIR/gcc-10.2.0/gcc-static-build
make -j$PARALLEL_JOBS install-gcc install-target-libgcc -C $BUILD_DIR/gcc-10.2.0/gcc-static-build
rm -rf $BUILD_DIR/gcc-10.2.0

step "[20/23] Linux 5.10.15 API Headers"
extract $SOURCES_DIR/linux-5.10.15.tar.xz $BUILD_DIR
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH mrproper -C $BUILD_DIR/linux-5.10.15
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH headers_check -C $BUILD_DIR/linux-5.10.15
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH INSTALL_HDR_PATH=$SYSROOT_DIR headers_install -C $BUILD_DIR/linux-5.10.15
rm -rf $BUILD_DIR/linux-5.10.15

step "[21/23] glibc 2.33"
extract $SOURCES_DIR/glibc-2.33.tar.xz $BUILD_DIR
mkdir $BUILD_DIR/glibc-2.33/glibc-build
( cd $BUILD_DIR/glibc-2.33/glibc-build && \
    CC="$TOOLS_DIR/bin/$CONFIG_TARGET-gcc" \
    CXX="$TOOLS_DIR/bin/$CONFIG_TARGET-g++" \
    AR="$TOOLS_DIR/bin/$CONFIG_TARGET-ar" \
    AS="$TOOLS_DIR/bin/$CONFIG_TARGET-as" \
    LD="$TOOLS_DIR/bin/$CONFIG_TARGET-ld" \
    RANLIB="$TOOLS_DIR/bin/$CONFIG_TARGET-ranlib" \
    READELF="$TOOLS_DIR/bin/$CONFIG_TARGET-readelf" \
    STRIP="$TOOLS_DIR/bin/$CONFIG_TARGET-strip" \
    CFLAGS="-O2 " CPPFLAGS="" CXXFLAGS="-O2 " LDFLAGS="" \
    ac_cv_path_BASH_SHELL=/bin/sh \
    libc_cv_forced_unwind=yes \
    libc_cv_ssp=no \
    $BUILD_DIR/glibc-2.33/configure \
    --target=$CONFIG_TARGET \
    --host=$CONFIG_TARGET \
    --build=$CONFIG_HOST \
    --prefix=/usr \
    --enable-shared \
    --without-cvs \
    --disable-profile \
    --without-gd \
    --enable-obsolete-rpc \
    --enable-kernel=5.10.15 \
    --with-headers=$SYSROOT_DIR/usr/include )
make -j$PARALLEL_JOBS -C $BUILD_DIR/glibc-2.33/glibc-build
make -j$PARALLEL_JOBS install_root=$SYSROOT_DIR install -C $BUILD_DIR/glibc-2.33/glibc-build
rm -rf $BUILD_DIR/glibc-2.33

step "[22/23] Gcc 10.2.0 - Final"
tar -Jxf $SOURCES_DIR/gcc-10.2.0.tar.xz -C $BUILD_DIR
extract $SOURCES_DIR/gmp-6.2.1.tar.xz $BUILD_DIR/gcc-10.2.0
mv -v $BUILD_DIR/gcc-10.2.0/gmp-6.2.1 $BUILD_DIR/gcc-10.2.0/gmp
extract $SOURCES_DIR/mpfr-4.1.0.tar.xz $BUILD_DIR/gcc-10.2.0
mv -v $BUILD_DIR/gcc-10.2.0/mpfr-4.1.0 $BUILD_DIR/gcc-10.2.0/mpfr
extract $SOURCES_DIR/mpc-1.2.1.tar.gz $BUILD_DIR/gcc-10.2.0
mv -v $BUILD_DIR/gcc-10.2.0/mpc-1.2.1 $BUILD_DIR/gcc-10.2.0/mpc
mkdir -pv $BUILD_DIR/gcc-10.2.0/gcc-final-build
( cd $BUILD_DIR/gcc-10.2.0/gcc-final-build && \
    MAKEINFO=missing \
    CFLAGS_FOR_TARGET="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -Os" \
    CXXFLAGS_FOR_TARGET="-D_LARGEFILE_SOURCE -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64 -Os" \
    $BUILD_DIR/gcc-10.2.0/configure \
    --prefix=$TOOLS_DIR \
    --build=$CONFIG_HOST \
    --host=$CONFIG_HOST \
    --target=$CONFIG_TARGET \
    --disable-libmudflap \
    --disable-multilib \
    --disable-nls \
    --enable-c99 \
    --enable-languages=c \
    --enable-long-long \
    --with-arch="$CONFIG_GCC_ARCH" \
    --with-bugurl="$CONFIG_BUG_URL" \
    --with-pkgversion="$CONFIG_PKG_VERSION" \
    --with-sysroot=$SYSROOT_DIR )
make -j$PARALLEL_JOBS -C $BUILD_DIR/gcc-10.2.0/gcc-final-build
make -j$PARALLEL_JOBS install -C $BUILD_DIR/gcc-10.2.0/gcc-final-build
if [ ! -e $TOOLS_DIR/bin/$CONFIG_TARGET-cc ]; then
  ln -vf $TOOLS_DIR/bin/$CONFIG_TARGET-gcc $TOOLS_DIR/bin/$CONFIG_TARGET-cc
fi
rm -rf $BUILD_DIR/gcc-10.2.0

step "[23/23] Eudev 3.2.9"
extract $SOURCES_DIR/eudev-3.2.9.tar.gz $BUILD_DIR
mkdir $BUILD_DIR/eudev-3.2.9/eudev-build
( cd $BUILD_DIR/eudev-3.2.9/eudev-build && \
    CC="$TOOLS_DIR/bin/$CONFIG_TARGET-gcc" \
    CXX="$TOOLS_DIR/bin/$CONFIG_TARGET-g++" \
    AR="$TOOLS_DIR/bin/$CONFIG_TARGET-ar" \
    AS="$TOOLS_DIR/bin/$CONFIG_TARGET-as" \
    LD="$TOOLS_DIR/bin/$CONFIG_TARGET-ld" \
    RANLIB="$TOOLS_DIR/bin/$CONFIG_TARGET-ranlib" \
    READELF="$TOOLS_DIR/bin/$CONFIG_TARGET-readelf" \
    STRIP="$TOOLS_DIR/bin/$CONFIG_TARGET-strip" \
    CFLAGS="-O2 " CPPFLAGS="" CXXFLAGS="-O2 " LDFLAGS="" \
    $BUILD_DIR/eudev-3.2.9/configure \
    --target=$CONFIG_TARGET \
    --host=$CONFIG_TARGET \
    --build=$CONFIG_HOST \
    --prefix=/usr \
    --enable-static \
    --enable-shared )
make -j$PARALLEL_JOBS -C $BUILD_DIR/eudev-3.2.9/eudev-build
make -j$PARALLEL_JOBS DESTDIR=$SYSROOT_DIR install -C $BUILD_DIR/eudev-3.2.9/eudev-build
rm -rf $BUILD_DIR/eudev-3.2.9

do_strip

success "\nTotal toolchain build time: $(timer $total_build_time)\n"
