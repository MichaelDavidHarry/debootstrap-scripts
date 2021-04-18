#!/bin/bash

sudo mount -t proc /proc mnt/proc/
sudo mount -t sysfs /sys mnt/sys/
sudo mount -o bind /dev mnt/dev/
#sudo chroot mnt /bin/bash
