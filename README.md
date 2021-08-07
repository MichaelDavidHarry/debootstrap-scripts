# debootstrap-scripts
## Scripts to install a Debian system                                                       

### Features
* Full disk encryption
* LVM
* BTRFS root filesystem
* snapper snapshots
* Can create a loopmounted file to install the system to
* Has scripts to run loopmounted file as a VM for testing

### How To Use
* Edit config.sh to set configuration settings for the install
* Run build.sh with superuser privileges
* If installing the system to a file:
  * Run kvm-efi.sh, kvm-efi-nographic.sh, kvm-bios.sh, or kvm-bios-nographic.sh to run the created system as a VM
  * If an error occurs, run clean.sh with superuser privileges to clean things up to give it another try

### Dependencies (Debian packages)
* lvm2
* btrfs-progs
* debootstrap
  * For running VMs:
    * qemu-kvm
