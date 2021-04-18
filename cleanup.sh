#!/bin/bash

sudo umount mnt
sudo losetup -d /dev/loop0
sudo rm debian.dd
rm -rf mnt
