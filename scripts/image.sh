#!/bin/bash
#
# CloneNux kernel build script
# Optional parameteres below:
set -o nounset
set -o errexit

# End of optional parameters
function step() {
    echo -e "\e[7m\e[1m>>> $1\e[0m"
}

function success() {
    echo -e "\e[1m\e[32m$1\e[0m"
}

function check_root() {
  if [ ! "$(id -u)" = "0" ] ; then
    cat << EOF
  ISO image preparation process for UEFI systems requires root permissions
  but you don't have such permissions. Restart this script with root
  permissions in order to generate UEFI compatible ISO structure.
EOF
    exit 1
  fi
}

function extract() {
    case $1 in
        *.tgz) tar -zxf $1 -C $2 ;;
        *.tar.gz) tar -zxf $1 -C $2 ;;
        *.tar.bz2) tar -jxf $1 -C $2 ;;
        *.tar.xz) tar -Jxf $1 -C $2 ;;
    esac
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

check_root
total_build_time=$(timer)

step "[1/2] Generate Ramdisk Image"
rm -rf $BUILD_DIR $IMAGES_DIR
mkdir -pv $BUILD_DIR $IMAGES_DIR
( cd $ROOTFS_DIR && find . -print0 | cpio --null -ov --format=newc | gzip -9 >  $BUILD_DIR/rootfs.cpio.gz )

step "[2/2] Createing UEFI boot image"
echo "Creating UEFI boot image file '$BUILD_DIR/uefi.img'."
rm -f $BUILD_DIR/uefi.img

if [ "$CONFIG_LINUX_ARCH" = "i386" ] ; then \
    CLONENUX_CONF=x86 ; \
    LOADER=$SUPPORT_DIR/systemd-boot/uefi_root/EFI/BOOT/BOOTIA32.EFI ; \
fi;
if [ "$CONFIG_LINUX_ARCH" = "x86_64" ] ; then \
    CLONENUX_CONF=x86_64 ; \
    LOADER=$SUPPORT_DIR/systemd-boot/uefi_root/EFI/BOOT/BOOTx64.EFI ; \
fi;
# Find the kernel size in bytes.
kernel_size=`du -b $KERNEL_DIR/bzImage | awk '{print \$1}'`
# Find the initramfs size in bytes.
rootfs_size=`du -b $BUILD_DIR/rootfs.cpio.gz | awk '{print \$1}'`
loader_size=`du -b $LOADER | awk '{print \$1}'`
# The EFI boot image is 64KB bigger than the kernel size.
image_size=$((kernel_size + rootfs_size + loader_size + 65536))
truncate -s $image_size $BUILD_DIR/uefi.img

echo "Attaching hard disk image file to loop device."
LOOP_DEVICE_HDD=$(losetup -f)
losetup $LOOP_DEVICE_HDD $BUILD_DIR/uefi.img

echo "Formatting hard disk image with FAT filesystem."
mkfs.vfat $LOOP_DEVICE_HDD

echo "Preparing 'uefi' work area."
rm -rf $BUILD_DIR/uefi
mkdir -p $BUILD_DIR/uefi
mount $BUILD_DIR/uefi.img $BUILD_DIR/uefi

echo "Preparing kernel and rootfs."
mkdir -p $BUILD_DIR/uefi/clonenux/$CLONENUX_CONF
cp $KERNEL_DIR/bzImage $BUILD_DIR/uefi/clonenux/$CLONENUX_CONF/bzImage
cp $BUILD_DIR/rootfs.cpio.gz $BUILD_DIR/uefi/clonenux/$CLONENUX_CONF/rootfs.cpio.gz

echo "Preparing 'systemd-boot' UEFI boot loader."
mkdir -p $BUILD_DIR/uefi/EFI/BOOT
cp $LOADER $BUILD_DIR/uefi/EFI/BOOT

echo "Preparing 'systemd-boot' configuration."
mkdir -p $BUILD_DIR/uefi/loader/entries
cp $SUPPORT_DIR/systemd-boot/uefi_root/loader/loader.conf $BUILD_DIR/uefi/loader
cp $SUPPORT_DIR/systemd-boot/uefi_root/loader/entries/clonenux-${CLONENUX_CONF}.conf  $BUILD_DIR/uefi/loader/entries

echo "Unmounting UEFI boot image file."
sync
umount $BUILD_DIR/uefi
sync
sleep 1

# The directory is now empty (mount point for loop device).
rm -rf $BUILD_DIR/uefi

# Make sure the UEFI boot image is readable.
chmod ugo+r $BUILD_DIR/uefi.img

mkdir -p $IMAGES_DIR/boot
cp $BUILD_DIR/uefi.img $IMAGES_DIR/boot

step "[3/3] Generate ISO Image"
extract $SOURCES_DIR/syslinux-6.03.tar.xz $BUILD_DIR
( cd $IMAGES_DIR && xorriso -as mkisofs \
    -isohybrid-mbr $BUILD_DIR/syslinux-6.03/bios/mbr/isohdpfx.bin \
    -c boot/boot.cat \
    -e boot/uefi.img \
      -no-emul-boot \
      -isohybrid-gpt-basdat \
    -o $IMAGES_DIR/$CONFIG_ISO_FILENAME \
    $IMAGES_DIR )

success "\nTotal image build time: $(timer $total_build_time)\n"
