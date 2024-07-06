# About

This repository automates the creation and release of PXE boot artifacts for Ubuntu using scripts and workflows.

# How to Use

## Building PXE Artifacts

To obtain the artifacts, you have two options:

### Build Locally

Clone this repository and run the `./build.sh [ubuntu_version]` script. This script creates an `output` directory and places the kernel, initrd, and root file system there. Docker must be installed for this process.

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
