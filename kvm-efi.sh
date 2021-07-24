#!/bin/bash
kvm -m 1G -drive file=debian.dd,format=raw -bios /usr/share/ovmf/OVMF.fd
