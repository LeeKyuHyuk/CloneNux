#!/bin/bash
#
# CloneNux system build script
# Optional parameteres below:
set -o nounset
set -o errexit

export LC_ALL=POSIX
export CONFIG_HOST=`echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/'`

export CC="$TOOLS_DIR/bin/$CONFIG_TARGET-gcc"
export CXX="$TOOLS_DIR/bin/$CONFIG_TARGET-g++"
export AR="$TOOLS_DIR/bin/$CONFIG_TARGET-ar"
export AS="$TOOLS_DIR/bin/$CONFIG_TARGET-as"
export LD="$TOOLS_DIR/bin/$CONFIG_TARGET-ld"
export RANLIB="$TOOLS_DIR/bin/$CONFIG_TARGET-ranlib"
export READELF="$TOOLS_DIR/bin/$CONFIG_TARGET-readelf"
export STRIP="$TOOLS_DIR/bin/$CONFIG_TARGET-strip"

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

step "[1/3] Create root file system directory."
rm -rf $BUILD_DIR $ROOTFS_DIR
mkdir -pv $BUILD_DIR $ROOTFS_DIR
mkdir -pv $ROOTFS_DIR/{boot,bin,dev,etc,lib,media,mnt,opt,proc,root,run,sbin,sys,tmp,usr}
mkdir -pv $ROOTFS_DIR/dev/{pts,shm}
chmod -v 1777 $ROOTFS_DIR/tmp
ln -svf /tmp/log $ROOTFS_DIR/dev/log
mkdir -pv $ROOTFS_DIR/etc/{network,profile.d}
mkdir -pv $ROOTFS_DIR/etc/network/{if-down.d,if-post-down.d,if-pre-up.d,if-up.d}
ln -svf /proc/self/mounts $ROOTFS_DIR/etc/mtab
ln -svf /tmp/resolv.conf $ROOTFS_DIR/etc/resolv.conf
mkdir -pv $ROOTFS_DIR/usr/{bin,lib,sbin}
mkdir -pv $ROOTFS_DIR/var/lib
ln -svf /tmp $ROOTFS_DIR/var/cache
ln -svf /tmp $ROOTFS_DIR/var/lock
ln -svf /tmp $ROOTFS_DIR/var/log
ln -svf /tmp $ROOTFS_DIR/var/run
ln -svf /tmp $ROOTFS_DIR/var/spool
ln -svf /tmp $ROOTFS_DIR/var/tmp
ln -svf /tmp $ROOTFS_DIR/var/lib/misc
if [ "$CONFIG_LINUX_ARCH" = "i386" ] ; then \
    ln -snvf lib $ROOTFS_DIR/lib32 ; \
    ln -snvf lib $ROOTFS_DIR/usr/lib32 ; \
fi;
if [ "$CONFIG_LINUX_ARCH" = "x86_64" ] ; then \
    ln -snvf lib $ROOTFS_DIR/lib64 ; \
    ln -snvf lib $ROOTFS_DIR/usr/lib64 ; \
fi;

step "[2/3] CloneNux 1.0.0"
cat > $BUILD_DIR/clonenux.c << "EOF"
#include <stdio.h>
#include <stdlib.h>

int main(void) {
  printf("The source code of CloneNux is entered here.\n");
  return 0;
}
EOF
$TOOLS_DIR/bin/$CONFIG_TARGET-gcc -static $BUILD_DIR/clonenux.c -o $ROOTFS_DIR/bin/clonenux
rm -rf $BUILD_DIR/clonenux.c

step "[3/3] Busybox 1.32.1"
extract $SOURCES_DIR/busybox-1.32.1.tar.bz2 $BUILD_DIR
make -j$PARALLEL_JOBS distclean -C $BUILD_DIR/busybox-1.32.1
make -j$PARALLEL_JOBS ARCH="$CONFIG_LINUX_ARCH" defconfig -C $BUILD_DIR/busybox-1.32.1
sed -i "s/.*CONFIG_STATIC.*/CONFIG_STATIC=y/" $BUILD_DIR/busybox-1.32.1/.config
make -j$PARALLEL_JOBS ARCH="$CONFIG_LINUX_ARCH" CROSS_COMPILE="$TOOLS_DIR/bin/$CONFIG_TARGET-" -C $BUILD_DIR/busybox-1.32.1
make -j$PARALLEL_JOBS ARCH="$CONFIG_LINUX_ARCH" CROSS_COMPILE="$TOOLS_DIR/bin/$CONFIG_TARGET-" CONFIG_PREFIX="$ROOTFS_DIR" install -C $BUILD_DIR/busybox-1.32.1
cat > $ROOTFS_DIR/etc/inittab << "EOF"
::restart:/sbin/init
::shutdown:echo -e "\nSyncing all file buffers."
::shutdown:sync
::shutdown:echo "Unmounting all filesystems."
::shutdown:umount -a -r
::shutdown:echo -e "\n  \\e[1mThank you for using CloneNux.\\e[0m\n"
::shutdown:sleep 1
::ctrlaltdel:/sbin/reboot
::respawn:/bin/cttyhack /bin/clonenux
tty2::respawn:/bin/sh
tty3::respawn:/bin/sh
tty4::respawn:/bin/sh
EOF

cat > $ROOTFS_DIR/init << "EOF"
#!/bin/sh

# Disable kernel message
dmesg -n 1

#Mount things needed by this script
mount -t devtmpfs none /dev
mount -t proc none /proc
mount -t tmpfs none /tmp -o mode=1777
mount -t sysfs none /sys

mkdir -p /dev/pts

mount -t devpts none /dev/pts

cat << BOOT_LOGO
Boot took $(cut -d' ' -f1 /proc/uptime) seconds

  ____ _                    _   _
 / ___| | ___  _ __   ___  | \\ | |_   ___  __
| |   | |/ _ \\| '_ \\ / _ \\ |  \\| | | | \\ \\/ /
| |___| | (_) | | | |  __/ | |\\  | |_| |>  <
 \\____|_|\\___/|_| |_|\\___| |_| \\_|\\__,_/_/\\_\\

Welcome to CloneNux!

BOOT_LOGO

exec /sbin/init
EOF
chmod +x $ROOTFS_DIR/init
rm -fv $ROOTFS_DIR/linuxrc
cp -v $BUILD_DIR/busybox-1.32.1/examples/depmod.pl $TOOLS_DIR/bin
rm -rf $BUILD_DIR/busybox-1.32.1

success "\nTotal system build time: $(timer $total_build_time)\n"
