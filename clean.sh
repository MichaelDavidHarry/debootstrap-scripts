#!/bin/bash

# Import config variables
source "`dirname $0`/config.sh"

sudo umount ./mnt/proc
sudo umount ./mnt/sys
sudo umount ./mnt/dev
sudo umount ./mnt/run
sudo umount ./mnt/boot/efi
sudo umount ./mnt/home
sudo umount ./mnt/home/.snapshots
sudo umount ./mnt/var/log
sudo umount ./mnt/var/log/.snapshots
sudo umount ./mnt/.snapshots
sudo umount ./mnt/.btrfs

sudo umount mnt
sudo vgchange -an "/dev/$LVM_VG_NAME"
sudo cryptsetup luksClose "$CRYPT_DM_NAME"
if [ "$USE_LOOPMOUNT_DEVICE" = true ];
then
    sudo losetup -d "$BLOCK_DEVICE"
fi

sudo rm -rf mnt
sudo rm debian.dd
