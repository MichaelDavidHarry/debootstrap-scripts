#!/bin/bash

truncate -s 5G debian.dd
sudo losetup --partscan --show --find debian.dd
echo $',100M,ef\n,,83' | sudo sfdisk /dev/loop0
sudo mkfs.fat -F32 /dev/loop0p1
sudo mkfs.btrfs /dev/loop0p2
mkdir mnt
sudo mount /dev/loop0p2 mnt
sudo debootstrap --arch arm64 buster mnt/ https://deb.debian.org/debian/
