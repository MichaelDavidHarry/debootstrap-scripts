#!/bin/bash

# Set up constants
FILE_BLOCK_DEVICE_SIZE=3G
HOSTNAME=debian-vm
BLOCK_DEVICE_CRYPT_PARTITION=/dev/loop0p1
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

# EFI-specific options
USE_EFI=true
BLOCK_EFI_PARTITION=/dev/loop0p1

# Stop on errors
set -e

# When EFI is in use, the first partition is used as the EFI partition, and the second partition is the encrypted root
if [ "$USE_EFI" = true ];
then
	BLOCK_DEVICE_CRYPT_PARTITION=/dev/loop0p2
fi

echo "Prepping file block device"
truncate -s $FILE_BLOCK_DEVICE_SIZE debian.dd
sudo losetup --partscan --show --find debian.dd
if [ "$USE_EFI" = true ];
then
	echo "Create EFI partition and root partition"
	echo $',100M,ef\n,,83' | sudo sfdisk /dev/loop0
	sudo mkfs.fat -F32 $BLOCK_EFI_PARTITION
	EFI_BLOCK_DEVICE_UUID=`blkid -o value -s UUID "$BLOCK_EFI_PARTITION"`
else
	echo "Create root partiton"
	echo 'type=83' | sudo sfdisk "$BLOCK_DEVICE"
fi

echo "Create and open encrypted device"
echo -n "$ENCRYPTION_PASSWORD" | cryptsetup --type luks1 -y -v luksFormat "$BLOCK_DEVICE_CRYPT_PARTITION" -d -
CRYPT_BLOCK_DEVICE_UUID=`blkid -o value -s UUID "$BLOCK_DEVICE_CRYPT_PARTITION"`
echo -n "$ENCRYPTION_PASSWORD" | cryptsetup open "$BLOCK_DEVICE_CRYPT_PARTITION" "$CRYPT_DM_NAME" -d -

echo "Create LVM physical volume, volume group, and logical volumes"
pvcreate "/dev/mapper/$CRYPT_DM_NAME"
vgcreate "$LVM_VG_NAME" "/dev/mapper/$CRYPT_DM_NAME"
lvcreate -L "$SWAP_SIZE" "$LVM_VG_NAME" -n swap
lvcreate -l 100%FREE "$LVM_VG_NAME" -n root

echo "Create filesystem and mount it"
sudo mkfs.btrfs "/dev/$LVM_VG_NAME/root"
sudo mkswap "/dev/$LVM_VG_NAME/swap"
mkdir mnt
sudo mount "/dev/$LVM_VG_NAME/root" mnt

echo "Bootstrapping the OS"
# debootstrap-cache directory may already exist, it's alright if it does
set +e
mkdir debootstrap-cache
set -e
PACKAGES="grub2,linux-image-amd64,btrfs-progs,sudo,lvm2,cryptsetup-bin,cryptsetup-initramfs,cryptsetup-run"
if [ "$USE_EFI" = true ];
then
	PACKAGES="$PACKAGES,grub-efi-amd64-bin"
fi
sudo debootstrap --arch amd64 --cache-dir `pwd`/debootstrap-cache --include "$PACKAGES" buster mnt/ https://deb.debian.org/debian/ 

echo "Copying template files"
sudo cp -r template-files/* mnt

echo "Setting up hostname"
echo "$HOSTNAME" > mnt/etc/hostname
echo "127.0.1.1	$HOSTNAME" >> mnt/etc/hosts

echo "Setting up fstab"
echo "/dev/mapper/$LVM_VG_NAME-root	/	btrfs	defaults	0	0"  >> mnt/etc/fstab
echo "/dev/mapper/$LVM_VG_NAME-swap   none   swap   defaults   0   0" >> mnt/etc/fstab

if [ "$USE_EFI" = true ];
then
	echo "UUID=$EFI_BLOCK_DEVICE_UUID	/boot/efi	vfat	defaults	0	0" >> mnt/etc/fstab
fi

echo "Setting up crypttab"
echo "$CRYPT_DM_NAME UUID=$CRYPT_BLOCK_DEVICE_UUID /etc/keys/root.key luks,key-slot=1" >> mnt/etc/crypttab

echo "Chroot phase"
sudo mount -t proc /proc mnt/proc/
sudo mount -t sysfs /sys mnt/sys/
sudo mount -o bind /dev mnt/dev/
sudo mount -o bind /run mnt/run/

if [ "$USE_EFI" = true ];
then
	mkdir -p mnt/boot/efi
	sudo mount /dev/loop0p1 mnt/boot/efi
fi

GRUB_EFI_OPTIONS=""
if [ "$USE_EFI" = true ];
then
	GRUB_EFI_OPTIONS="--target=x86_64-efi --efi-directory=/boot/efi --removable"
fi

sudo chroot mnt /bin/bash -c "tasksel install standard && \
echo \"$LOCALE\" >> /etc/locale.gen && \
echo LANG=\"$LANG\" >> /etc/default/locale && \
locale-gen && \
echo 'GRUB_ENABLE_CRYPTODISK=y' >> /etc/default/grub && \
grub-install $GRUB_EFI_OPTIONS --root-directory=/ \"$BLOCK_DEVICE\" && \
update-grub && \
echo \"root:$ROOT_PASSWORD\" | chpasswd && \
useradd -m -s /bin/bash $USER_NAME && \
echo \"$USER_NAME:$USER_PASSWORD\" | chpasswd && \
usermod -aG sudo $USER_NAME"

# Make a keyfile and add it to the LUKS container so the encryption password will not have to be entered twice when the system boots. Update cryptsetup-initramfs so the keyfile will be copied into the initramfs when that is generated.
mkdir -m0700 mnt/etc/keys
( umask 0077 && dd if=/dev/urandom bs=1 count=64 of=mnt/etc/keys/root.key conv=fsync )
echo -n "$ENCRYPTION_PASSWORD" | sudo cryptsetup luksAddKey $BLOCK_DEVICE_CRYPT_PARTITION mnt/etc/keys/root.key 
echo "KEYFILE_PATTERN=\"/etc/keys/*.key\"" >> mnt/etc/cryptsetup-initramfs/conf-hook
echo UMASK=0077 >> mnt/etc/initramfs-tools/initramfs.conf

sudo chroot mnt /bin/bash -c "update-initramfs -u -k all"

echo "Unmounting chroot mounts"
# Unmount devices from chroot
sudo umount mnt/proc/
sudo umount mnt/sys/
sudo umount mnt/dev/
sudo umount mnt/run/
if [ "$USE_EFI" = true ];
then
	sudo umount mnt/boot/efi
fi

echo "Cleaning up loop mount and mount point"
sudo umount mnt
sudo vgchange -an "/dev/$LVM_VG_NAME"
sudo cryptsetup luksClose "$CRYPT_DM_NAME"
sudo losetup -d "$BLOCK_DEVICE"
#sudo rm debian.dd
rm -rf mnt
sudo chmod 777 debian.dd
