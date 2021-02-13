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

total_build_time=$(timer)

step "[1/3] Generate Ramdisk Image"
rm -rf $BUILD_DIR $IMAGES_DIR
mkdir -pv $BUILD_DIR $IMAGES_DIR
( cd $ROOTFS_DIR && find . -print0 | cpio --null -ov --format=newc | gzip -9 >  $BUILD_DIR/rootfs.cpio.gz )

step "[2/3] Createing UEFI boot image"
rm -f $BUILD_DIR/uefi.img $BUILD_DIR/uefi
mkdir -pv $BUILD_DIR/uefi/EFI/BOOT
cp -v $SUPPORT_DIR/systemd-boot/uefi_root/EFI/BOOT/BOOTx64.EFI $BUILD_DIR/uefi/EFI/BOOT/BOOTx64.EFI
mkdir -pv $BUILD_DIR/uefi/clonenux/x86_64
cp -v $KERNEL_DIR/bzImage $BUILD_DIR/uefi/clonenux/x86_64/bzImage
cp -v $BUILD_DIR/rootfs.cpio.gz $BUILD_DIR/uefi/clonenux/x86_64/rootfs.cpio.gz
cp -Rv $SUPPORT_DIR/systemd-boot/uefi_root/loader $BUILD_DIR/uefi/loader
$TOOLS_DIR/usr/bin/genimage \
  --rootpath "$ROOTFS_DIR" \
  --tmppath "$BUILD_DIR/genimage.tmp" \
  --inputpath "$BUILD_DIR/uefi" \
  --outputpath "$BUILD_DIR" \
  --config "$SUPPORT_DIR/genimage/genimage-uefi.cfg"
mkdir -pv $IMAGES_DIR/boot
cp -v $BUILD_DIR/uefi.vfat $IMAGES_DIR/boot/uefi.img
chmod ugo+r $IMAGES_DIR/boot/uefi.img

step "[3/3] Generate ISO Image"
extract $SOURCES_DIR/syslinux-6.03.tar.xz $BUILD_DIR
cp -v $BUILD_DIR/syslinux-6.03/bios/core/isolinux.bin $IMAGES_DIR/boot/isolinux.bin
( cd $IMAGES_DIR && xorriso -as mkisofs \
    -o $IMAGES_DIR/$CONFIG_ISO_FILENAME \
    -isohybrid-mbr $BUILD_DIR/syslinux-6.03/bios/mbr/isohdpfx.bin \
    -c boot/boot.cat \
    -b boot/isolinux.bin \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -eltorito-alt-boot \
    -e boot/uefi.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    $IMAGES_DIR )

success "\nTotal image build time: $(timer $total_build_time)\n"
