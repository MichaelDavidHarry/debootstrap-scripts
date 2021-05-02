#!/bin/bash

sudo umount mnt
sudo vgchange -an /dev/vg
sudo cryptsetup luksClose cryptlvm
sudo losetup -d /dev/loop0
sudo rm debian.dd
rm -rf mnt
