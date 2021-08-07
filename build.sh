#!/bin/bash

# Set up constants
FILE_BLOCK_DEVICE_SIZE=3G
HOSTNAME=debian-vm
BLOCK_DEVICE_CRYPT_PARTITION=/dev/loop0p2
BLOCK_DEVICE=/dev/loop0
USER_NAME=user
USER_PASSWORD=password
ROOT_PASSWORD=password
LOCALE="en_US.UTF-8 UTF-8"
LANG="en_US.UTF-8"
CRYPT_DM_NAME="cryptlvm1"
LVM_VG_NAME="vg1"
ENCRYPTION_PASSWORD="crypt"
SWAP_SIZE=128M
ENABLE_SERIAL_CONSOLE=true

# EFI-specific options
USE_EFI=true
BLOCK_EFI_PARTITION=/dev/loop0p1

# Stop on errors
set -e

echo "Prepping file block device"
truncate -s $FILE_BLOCK_DEVICE_SIZE debian.dd
sudo losetup --partscan --show --find debian.dd
if [ "$USE_EFI" = true ];
then
	echo "Create EFI partition and root partition"
	echo $',100M,ef\n,,83' | sudo sfdisk "$BLOCK_DEVICE"
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

echo "Create and mount BTRFS subvolumes"
sudo btrfs subvolume create mnt/@
sudo btrfs subvolume create mnt/@-snapshots
sudo btrfs subvolume create mnt/@home
sudo btrfs subvolume create mnt/@home-snapshots
sudo btrfs subvolume create mnt/@log
sudo btrfs subvolume create mnt/@log-snapshots
sudo umount mnt
sudo mount "/dev/$LVM_VG_NAME/root" -o subvol=@ mnt
mkdir -p mnt/home mnt/var/log mnt/.btrfs
sudo mount "/dev/$LVM_VG_NAME/root" mnt/.btrfs
chmod 700 mnt/.btrfs
sudo mount "/dev/$LVM_VG_NAME/root" -o subvol=@home mnt/home
sudo mount "/dev/$LVM_VG_NAME/root" -o subvol=@log mnt/var/log

echo "Bootstrapping the OS"
# debootstrap-cache directory may already exist, it's alright if it does
set +e
mkdir debootstrap-cache
set -e
PACKAGES="grub2,linux-image-amd64,btrfs-progs,sudo,lvm2,cryptsetup-bin,cryptsetup-initramfs,cryptsetup-run,snapper,console-setup"
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
echo "/dev/mapper/$LVM_VG_NAME-root	/	btrfs	defaults,subvol=@	0	0"  >> mnt/etc/fstab
echo "/dev/mapper/$LVM_VG_NAME-swap   none   swap   defaults   0   0" >> mnt/etc/fstab
echo "/dev/mapper/$LVM_VG_NAME-root     /.btrfs       btrfs   defaults       0       0"  >> mnt/etc/fstab
echo "/dev/mapper/$LVM_VG_NAME-root     /.snapshots       btrfs   defaults,subvol=@-snapshots       0       0"  >> mnt/etc/fstab
echo "/dev/mapper/$LVM_VG_NAME-root     /home       btrfs   defaults,subvol=@home       0       0"  >> mnt/etc/fstab
echo "/dev/mapper/$LVM_VG_NAME-root     /home/.snapshots       btrfs   defaults,subvol=@home-snapshots       0       0"  >> mnt/etc/fstab
echo "/dev/mapper/$LVM_VG_NAME-root     /var/log       btrfs   defaults,subvol=@log       0       0"  >> mnt/etc/fstab
echo "/dev/mapper/$LVM_VG_NAME-root     /var/log/.snapshots       btrfs   defaults,subvol=@log-snapshots       0       0"  >> mnt/etc/fstab

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
	sudo mount "$BLOCK_EFI_PARTITION" mnt/boot/efi
fi

GRUB_EFI_OPTIONS=""
if [ "$USE_EFI" = true ];
then
	GRUB_EFI_OPTIONS="--target=x86_64-efi --efi-directory=/boot/efi --removable"
fi
if [ "$ENABLE_SERIAL_CONSOLE" = true ];
then
	sudo chroot mnt /bin/bash -c "systemctl enable serial-getty@ttyS0.service"
fi
sudo chroot mnt /bin/bash -c "set -e && tasksel install standard && \
echo \"$LOCALE\" >> /etc/locale.gen && \
echo LANG=\"$LANG\" >> /etc/default/locale && \
locale-gen && \
echo 'GRUB_ENABLE_CRYPTODISK=y' >> /etc/default/grub && \
grub-install $GRUB_EFI_OPTIONS --root-directory=/ \"$BLOCK_DEVICE\" && \
update-grub && \
echo \"root:$ROOT_PASSWORD\" | chpasswd && \
useradd -m -s /bin/bash $USER_NAME && \
echo \"$USER_NAME:$USER_PASSWORD\" | chpasswd && \
usermod -aG sudo $USER_NAME && \
snapper --no-dbus -c root create-config --fstype btrfs / && \
snapper --no-dbus -c home create-config --fstype btrfs /home && \
snapper --no-dbus -c log create-config --fstype btrfs /var/log && \
rm -rf /.snapshots && \
mkdir .snapshots && \
mount .snapshots && \
rm -rf /home/.snapshots && \
mkdir /home/.snapshots && \
mount /home/.snapshots && \
chmod 750 /home/.snapshots && \
rm -rf /var/log/.snapshots && \
mkdir /var/log/.snapshots && \
mount /var/log/.snapshots && \
chmod 750 /var/log/.snapshots"

# Make a keyfile and add it to the LUKS container so the encryption password will not have to be entered twice when the system boots. Update cryptsetup-initramfs so the keyfile will be copied into the initramfs when that is generated.
mkdir -m0700 mnt/etc/keys
( umask 0077 && dd if=/dev/urandom bs=1 count=64 of=mnt/etc/keys/root.key conv=fsync )
echo -n "$ENCRYPTION_PASSWORD" | sudo cryptsetup luksAddKey $BLOCK_DEVICE_CRYPT_PARTITION mnt/etc/keys/root.key 
echo "KEYFILE_PATTERN=\"/etc/keys/*.key\"" >> mnt/etc/cryptsetup-initramfs/conf-hook
echo UMASK=0077 >> mnt/etc/initramfs-tools/initramfs.conf

echo "Updating initramfs"
sudo chroot mnt /bin/bash -c "set -e && update-initramfs -u -k all && \
snapper --no-dbus -c root create --description initial && \
snapper --no-dbus -c home create --description initial && \
snapper --no-dbus -c log create --description initial"

echo "Unmounting chroot mounts"
# Unmount devices from chroot
sudo umount mnt/proc/
sudo umount mnt/sys/
sudo umount mnt/dev/
sudo umount mnt/run/
sudo umount mnt/home/.snapshots
sudo umount mnt/home
sudo umount mnt/var/log/.snapshots
sudo umount mnt/var/log
sudo umount mnt/.snapshots
sudo umount mnt/.btrfs
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
