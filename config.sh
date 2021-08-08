#!/bin/bash

HOSTNAME=debian-vm
BLOCK_DEVICE_CRYPT_PARTITION=/dev/loop0p2
BLOCK_DEVICE=/dev/loop0
USER_NAME=user
USER_PASSWORD=password
ROOT_PASSWORD=password
LOCALE="en_US.UTF-8 UTF-8"
LANG="en_US.UTF-8"
TIMEZONE="America/Chicago"
CRYPT_DM_NAME="cryptlvm1"
LVM_VG_NAME="vg1"
ENCRYPTION_PASSWORD="crypt"
SWAP_SIZE=128M
# Enable this if you want to use KVM with nographic option
ENABLE_SERIAL_CONSOLE=true

# EFI-specific options
USE_EFI=true
BLOCK_EFI_PARTITION=/dev/loop0p1

# Loopmount file device options
FILE_BLOCK_DEVICE_SIZE=3G
USE_LOOPMOUNT_DEVICE=true