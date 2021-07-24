#!/bin/bash

# Set up constants
FILE_BLOCK_DEVICE_SIZE=3G
HOSTNAME=debian-vm
BLOCK_DEVICE_CRYPT_PARTITION=/dev/loop0p1
BLOCK_EFI_PARTITION=/dev/loop0p1
BLOCK_DEVICE=/dev/loop0
USER_NAME=user
USER_PASSWORD=password
ROOT_PASSWORD=password
LOCALE="en_US.UTF-8 UTF-8"
LANG="en_US.UTF-8"
CRYPT_DM_NAME="cryptlvm"
LVM_VG_NAME="vg"
ENCRYPTION_PASSWORD="crypt"
SWAP_SIZE=128M
USE_EFI=true

sudo umount ./mnt/proc
sudo umount ./mnt/sys
sudo umount ./mnt/dev
sudo umount ./mnt/run
sudo umount ./mnt/boot/efi

sudo umount mnt
sudo vgchange -an "/dev/$LVM_VG_NAME"
sudo cryptsetup luksClose "$CRYPT_DM_NAME"
sudo losetup -d "$BLOCK_DEVICE"

sudo rm -rf mnt
sudo rm debian.dd
