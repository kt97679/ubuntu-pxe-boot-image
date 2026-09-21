# About

This repository automates the creation and release of PXE boot artifacts for Ubuntu using scripts and workflows.

# How to Use

## Building PXE Artifacts

To obtain the artifacts, you have two options:

### Build Locally

Clone this repository and run the `./build.sh [ubuntu_version]` script. This script creates an `output` directory and places the kernel, initrd, root file system and a bootable ISO (`ubuntu-<version>-live.iso`) there. Docker must be installed for this process.

Replace `[ubuntu_version]` with the optional Ubuntu version parameter. Omitting this parameter builds the latest version of Ubuntu.

### Download Pre-built Artifacts

Alternatively, download pre-built artifacts directly from the Releases page.

# Testing with QEMU VM

You can test the obtained artifacts using the `qemu.sh` script. Ensure the `output` directory exists and contains the required kernel, initrd, and root file system files.

## Booting the VM

To boot the VM, use `./qemu.sh start`.

## Accessing the VM

To log into the VM:
* Use `./qemu.sh ssh` for SSH access.
* Use `./qemu.sh console` for console access.

Note: By default, the root password is not set. If console access is needed, uncomment the line in `build.sh` that sets the root password and rebuild the artifacts.

## Stopping the VM

To stop the VM, use `./qemu.sh stop`.

# ISO image

The build also produces a hybrid ISO containing the same kernel, initrd and root file system. It boots:

- in BIOS and UEFI mode,
- with UEFI Secure Boot enabled (it uses Ubuntu's signed shim and GRUB),
- from a CD/DVD or from a USB stick (`sudo dd if=output/ubuntu-24.04-live.iso of=/dev/sdX bs=4M conv=fsync`).

The ISO kernel command line contains `autologin`, so the console (both the serial port and tty1) logs
straight into a root shell, with no password prompt. Anyone with physical or console access to a machine
booted from this ISO therefore gets root; drop `autologin` from `grub.cfg` in `build.sh` if that is not wanted.
The same flag works for PXE boots: add `autologin` to the kernel command line in your iPXE/GRUB config.

No ssh key or root password is set on the ISO, since there is no `http_hook`. For remote access you can:

- press `e` in the GRUB menu and append `http_hook=http://<server>/<script>.sh` to the `linux` line,
- on Ubuntu 24.04+ (systemd >= 252) pass the key as a systemd credential, e.g. for QEMU:
  `-smbios type=11,value=io.systemd.credential.binary:ssh.authorized_keys.root=$(base64 -w0 key.pub)`,
- uncomment the line in `build.sh` that sets the root password and rebuild.

## Testing the ISO with QEMU

`./qemu.sh start-iso` boots the ISO as a CD-ROM and injects the ssh key via the SMBIOS credential above,
after that `./qemu.sh ssh` and `./qemu.sh stop` work as usual. `./qemu.sh console-iso` boots it in the foreground.

`QEMU_MEM` (default 4096) and `WAIT_SECONDS` (default 180) can be used to adjust VM memory and the boot timeout.

# VM provisioning

Using PXE boot artifacts you can provision vm that will boot from disk:

```
# create disk
qemu-img create -f qcow2 /var/tmp/myimage.qcow2 16G
# pxe boot vm with new disk attached
QEMU_OPTS="-drive file=/var/tmp/myimage.qcow2" ./qemu.sh start
# provision new vm via ssh
./vm-debootstrap-ubuntu.sh |./qemu.sh ssh
# stop vm
./qemu.sh stop
# now you can boot new vm
qemu-system-x86_64 -drive file=/var/tmp/myimage.qcow2 -device virtio-net-pci,netdev=n1 \
    -netdev user,id=n1,hostfwd=tcp:127.0.0.1:2222-:22 -nographic -enable-kvm -cpu max -m 4096
# and connect to it via ssh
ssh -p 2222 127.0.0.1
```
