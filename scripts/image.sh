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

step "[1/1] Generate Ramdisk Image"
rm -rf $IMAGES_DIR
mkdir -pv $IMAGES_DIR
( cd $ROOTFS_DIR && find . -print0 | cpio --null -ov --format=newc | gzip -9 >  $IMAGES_DIR/rootfs.cpio.gz )

success "\nTotal image build time: $(timer $total_build_time)\n"
