#!/bin/bash

# Stop on errors
set -e

# Prep block device as a drive
truncate -s 5G debian.dd
sudo losetup --partscan --show --find debian.dd
echo 'type=83' | sudo sfdisk /dev/loop0
sudo mkfs.btrfs /dev/loop0p1
mkdir mnt
sudo mount /dev/loop0p1 mnt

# Bootstrap the OS
set +e
mkdir debootstrap-cache
set -e
sudo debootstrap --arch amd64 --cache-dir `pwd`/debootstrap-cache --include htop,grub2,linux-image-amd64 buster mnt/ https://deb.debian.org/debian/ 

# Copy template files
sudo cp -r template-files/* mnt

# Chroot phase
sudo mount -t proc /proc mnt/proc/
sudo mount -t sysfs /sys mnt/sys/
sudo mount -o bind /dev mnt/dev/
sudo chroot mnt /bin/bash -c 'tasksel install standard && \
apt install btrfs-progs -y && \
grub-install --root-directory=/ /dev/loop0 && \
update-grub && \
echo "root:password" | chpasswd'

# Unmount devices from chroot
sudo umount mnt/proc/
sudo umount mnt/sys/
sudo umount mnt/dev/

# Umount the block device
sudo umount mnt
sudo losetup -d /dev/loop0
#sudo rm debian.dd
rm -rf mnt

