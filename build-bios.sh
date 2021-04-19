#!/bin/bash

# Stop on errors
set -e

FILE_BLOCK_DEVICE_SIZE=3G
HOSTNAME=debian-vm

echo "Prepping file block device"
truncate -s $FILE_BLOCK_DEVICE_SIZE debian.dd
sudo losetup --partscan --show --find debian.dd
echo 'type=83' | sudo sfdisk /dev/loop0
sudo mkfs.btrfs /dev/loop0p1
mkdir mnt
sudo mount /dev/loop0p1 mnt

echo "Bootstrapping the OS"
set +e
mkdir debootstrap-cache
set -e
sudo debootstrap --arch amd64 --cache-dir `pwd`/debootstrap-cache --include htop,grub2,linux-image-amd64 buster mnt/ https://deb.debian.org/debian/ 

echo "Copying template files"
sudo cp -r template-files/* mnt

echo "Setting up hostname"
echo "$HOSTNAME" > mnt/etc/hostname
echo "127.0.1.1	$HOSTNAME" >> mnt/etc/hosts

echo "Setting up fstab"
ROOT_BLOCK_DEVICE=`blkid -o value -s UUID /dev/loop0p1`
echo "UUID=$ROOT_BLOCK_DEVICE	/	btrfs	defaults	0	0"  >> mnt/etc/fstab

echo "Chroot phase"
sudo mount -t proc /proc mnt/proc/
sudo mount -t sysfs /sys mnt/sys/
sudo mount -o bind /dev mnt/dev/
sudo chroot mnt /bin/bash -c 'tasksel install standard && \
apt install btrfs-progs -y && \
grub-install --root-directory=/ /dev/loop0 && \
update-grub && \
echo "root:password" | chpasswd'

echo "Unmounting chroot mounts"
# Unmount devices from chroot
sudo umount mnt/proc/
sudo umount mnt/sys/
sudo umount mnt/dev/

echo "Cleaning up loop mount and mount point"
# Umount the block device
sudo umount mnt
sudo losetup -d /dev/loop0
#sudo rm debian.dd
rm -rf mnt
