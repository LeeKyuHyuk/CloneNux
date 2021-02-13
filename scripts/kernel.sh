#!/bin/bash
#
# CloneNux kernel build script
# Optional parameteres below:
set -o nounset
set -o errexit

export LC_ALL=POSIX
export CONFIG_HOST=`echo ${MACHTYPE} | sed -e 's/-[^-]*/-cross/'`

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

rm -rf $BUILD_DIR $KERNEL_DIR
mkdir -pv $BUILD_DIR $KERNEL_DIR

step "[1/1] Linux Kernel 5.10.15"
extract $SOURCES_DIR/linux-5.10.15.tar.xz $BUILD_DIR
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH mrproper -C $BUILD_DIR/linux-5.10.15
make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH $CONFIG_LINUX_KERNEL_DEFCONFIG -C $BUILD_DIR/linux-5.10.15
# Changes the name of the system to 'clonenux'.
sed -i "s/.*CONFIG_DEFAULT_HOSTNAME.*/CONFIG_DEFAULT_HOSTNAME=\"$CONFIG_HOSTNAME\"/" $BUILD_DIR/linux-5.10.15/.config
# Step 1 - disable all active kernel compression options (should be only one).
sed -i "s/.*\\(CONFIG_KERNEL_.*\\)=y/\\#\\ \\1 is not set/" $BUILD_DIR/linux-5.10.15/.config
# Step 2 - enable the 'xz' compression option.
sed -i "s/.*CONFIG_KERNEL_XZ.*/CONFIG_KERNEL_XZ=y/" $BUILD_DIR/linux-5.10.15/.config
# Enable the VESA framebuffer for graphics support.
sed -i "s/.*CONFIG_FB_VESA.*/CONFIG_FB_VESA=y/" $BUILD_DIR/linux-5.10.15/.config
# Disable debug symbols in kernel => smaller kernel binary.
sed -i "s/^CONFIG_DEBUG_KERNEL.*/\\# CONFIG_DEBUG_KERNEL is not set/" $BUILD_DIR/linux-5.10.15/.config
# Enable the EFI stub
sed -i "s/.*CONFIG_EFI_STUB.*/CONFIG_EFI_STUB=y/" $BUILD_DIR/linux-5.10.15/.config
# Request that the firmware clear the contents of RAM after reboot (4.14+).
echo "CONFIG_RESET_ATTACK_MITIGATION=y" >> $BUILD_DIR/linux-5.10.15/.config
# Disable Apple Properties (Useful for Macs but useless in general)
echo "CONFIG_APPLE_PROPERTIES=n" >> $BUILD_DIR/linux-5.10.15/.config
# Check if we are building 64-bit kernel.
if [ "`grep "CONFIG_X86_64=y" $BUILD_DIR/linux-5.10.15/.config`" = "CONFIG_X86_64=y" ] ; then
    # Enable the mixed EFI mode when building 64-bit kernel.
    echo "CONFIG_EFI_MIXED=y" >> $BUILD_DIR/linux-5.10.15/.config
fi
# Support NVMe Driver
echo "CONFIG_NVME_CORE=y" >> $BUILD_DIR/linux-5.10.15/.config
echo "CONFIG_BLK_DEV_NVME=y" >> $BUILD_DIR/linux-5.10.15/.config
echo "CONFIG_NVME_MULTIPATH=y" >> $BUILD_DIR/linux-5.10.15/.config
echo "CONFIG_NVME_HWMON=n" >> $BUILD_DIR/linux-5.10.15/.config
echo "CONFIG_NVME_FC=n" >> $BUILD_DIR/linux-5.10.15/.config
echo "CONFIG_NVME_TCP=n" >> $BUILD_DIR/linux-5.10.15/.config

make -j$PARALLEL_JOBS ARCH=$CONFIG_LINUX_ARCH HOSTCC="gcc -O2 -I$TOOLS_DIR/include -L$TOOLS_DIR/lib -Wl,-rpath,$TOOLS_DIR/lib" CROSS_COMPILE="$TOOLS_DIR/bin/$CONFIG_TARGET-" bzImage -C $BUILD_DIR/linux-5.10.15
cp -v $BUILD_DIR/linux-5.10.15/arch/x86/boot/bzImage $KERNEL_DIR/bzImage
rm -rf $BUILD_DIR/linux-5.10.15

success "\nTotal kernel build time: $(timer $total_build_time)\n"
