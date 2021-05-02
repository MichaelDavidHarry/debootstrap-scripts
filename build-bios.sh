#!/bin/bash

# Stop on errors
set -e

FILE_BLOCK_DEVICE_ROOT_PARTITION_SIZE=3G
HOSTNAME=debian-vm
BLOCK_DEVICE_ROOT_PARTITION=/dev/loop0p1
BLOCK_DEVICE=/dev/loop0
USER_NAME=user
USER_PASSWORD=password
ROOT_PASSWORD=password
LOCALE="en_US.UTF-8 UTF-8"
LANG="en_US.UTF-8"

echo "Prepping file block device"
truncate -s $FILE_BLOCK_DEVICE_ROOT_PARTITION_SIZE debian.dd
sudo losetup --partscan --show --find debian.dd
echo 'type=83' | sudo sfdisk "$BLOCK_DEVICE"
sudo mkfs.btrfs "$BLOCK_DEVICE_ROOT_PARTITION"
mkdir mnt
sudo mount "$BLOCK_DEVICE_ROOT_PARTITION" mnt

echo "Bootstrapping the OS"
set +e
mkdir debootstrap-cache
set -e
sudo debootstrap --arch amd64 --cache-dir `pwd`/debootstrap-cache --include grub2,linux-image-amd64,btrfs-progs buster mnt/ https://deb.debian.org/debian/ 

echo "Copying template files"
sudo cp -r template-files/* mnt

echo "Setting up hostname"
echo "$HOSTNAME" > mnt/etc/hostname
echo "127.0.1.1	$HOSTNAME" >> mnt/etc/hosts

echo "Setting up fstab"
ROOT_BLOCK_DEVICE_ROOT_PARTITION=`blkid -o value -s UUID "$BLOCK_DEVICE_ROOT_PARTITION"`
echo "UUID=$ROOT_BLOCK_DEVICE_ROOT_PARTITION	/	btrfs	defaults	0	0"  >> mnt/etc/fstab

echo "Chroot phase"
sudo mount -t proc /proc mnt/proc/
sudo mount -t sysfs /sys mnt/sys/
sudo mount -o bind /dev mnt/dev/
sudo chroot mnt /bin/bash -c "tasksel install standard && \
echo \"$LOCALE\" >> /etc/locale.gen && \
echo LANG=\"$LANG\" >> /etc/default/locale && \
locale-gen && \
grub-install --root-directory=/ \"$BLOCK_DEVICE\" && \
update-grub && \
echo \"root:$ROOT_PASSWORD\" | chpasswd && \
useradd -m -s /bin/bash $USER_NAME && \
echo \"$USER_NAME:$USER_PASSWORD\" | chpasswd"

echo "Unmounting chroot mounts"
# Unmount devices from chroot
sudo umount mnt/proc/
sudo umount mnt/sys/
sudo umount mnt/dev/

echo "Cleaning up loop mount and mount point"
# Umount the block device
sudo umount mnt
sudo losetup -d "$BLOCK_DEVICE"
#sudo rm debian.dd
rm -rf mnt
