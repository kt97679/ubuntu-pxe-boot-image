#!/bin/bash
set -xeu -o pipefail

UBUNTU_VERSION=${1:-latest}
IMAGE_ROOT="/new_root"
BUILD_DIR="/build"
ISO_DIR="/iso"
ISO_LABEL="UBUNTU_LIVE"

SCRIPT_DIR=$(dirname $(realpath $0))
OUTPUT_DIR="$SCRIPT_DIR/output"

[ -r /.dockerenv ] || {
    mkdir -p $OUTPUT_DIR
    exec &> >(tee $OUTPUT_DIR/$(basename $0).log)
    exec docker run -u root --entrypoint=$BUILD_DIR/$(basename $0) --rm -v $SCRIPT_DIR:$BUILD_DIR ubuntu:$UBUNTU_VERSION
}

# Hybrid BIOS/UEFI ISO that is also bootable from a USB stick (dd).
# UEFI uses Canonical's signed shim + GRUB, so it boots with Secure Boot enabled.
build_iso() {
    local iso=$1 kernel=$2 initrd=$3 squashfs=$4
    local signed=/iso-signed efi_img=/iso-efi.img
    mkdir -p $ISO_DIR/live $ISO_DIR/.disk $ISO_DIR/boot/grub/i386-pc $ISO_DIR/EFI/BOOT $signed
    cp $squashfs $ISO_DIR/live/filesystem.squashfs
    cp $kernel $ISO_DIR/live/vmlinuz
    cp $initrd $ISO_DIR/live/initrd
    # the signed GRUB (gcdx64) locates the ISO filesystem by searching for this file
    echo "Ubuntu ${VERSION_ID} live ($(date -u +%Y%m%d))" > $ISO_DIR/.disk/info
    # the signed GRUB can't load modules from disk, so stick to built-in commands here
    cat > $ISO_DIR/boot/grub/grub.cfg <<GRUB
serial --unit=0 --speed=115200
terminal_input console serial
terminal_output console serial
set timeout=3
menuentry "Ubuntu ${VERSION_ID} live" {
    linux /live/vmlinuz boot=live autologin nomodeset console=tty0 console=ttyS0,115200n8
    initrd /live/initrd
}
GRUB

    # BIOS: El Torito image + GRUB modules on the ISO, same as grub-mkrescue does
    grub-mkimage -O i386-pc-eltorito -p /boot/grub -o $ISO_DIR/boot/grub/i386-pc/eltorito.img biosdisk iso9660
    cp /usr/lib/grub/i386-pc/*.{mod,lst} $ISO_DIR/boot/grub/i386-pc/

    # UEFI: shim -> signed GRUB (+ MokManager), in an ESP image appended as a GPT partition
    (cd $signed && apt-get download shim-signed grub-efi-amd64-signed && for deb in *.deb; do dpkg-deb -x $deb .; done)
    cp $(ls $signed/usr/lib/shim/shimx64.efi.signed{.latest,} 2>/dev/null | head -1) $ISO_DIR/EFI/BOOT/BOOTX64.EFI
    cp $signed/usr/lib/shim/mmx64.efi $ISO_DIR/EFI/BOOT/mmx64.efi
    cp $signed/usr/lib/grub/x86_64-efi-signed/gcdx64.efi.signed $ISO_DIR/EFI/BOOT/grubx64.efi
    mkfs.vfat -n ESP -C $efi_img 8192
    mmd -i $efi_img ::/EFI ::/EFI/BOOT
    mcopy -i $efi_img $ISO_DIR/EFI/BOOT/* ::/EFI/BOOT/

    xorriso -as mkisofs -r -J -joliet-long -l -iso-level 3 -V $ISO_LABEL \
        -partition_offset 16 --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img --mbr-force-bootable \
        -append_partition 2 0xEF $efi_img -appended_part_as_gpt \
        -c /boot.catalog \
        -b /boot/grub/i386-pc/eltorito.img -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
        -eltorito-alt-boot -e '--interval:appended_partition_2:all::' -no-emul-boot \
        -o $iso $ISO_DIR
}

mkdir -p "$IMAGE_ROOT" && cd "$IMAGE_ROOT"

. /etc/os-release
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install --no-install-recommends -y squashfs-tools debootstrap \
    grub-common grub-pc-bin mtools dosfstools xorriso
debootstrap --arch amd64 --variant=minbase --components=main,restricted,universe --include=systemd-sysv,curl ${UBUNTU_CODENAME} .
printf "deb http://archive.ubuntu.com/ubuntu/ %s main restricted universe multiverse\n" \
    $UBUNTU_CODENAME{,-backports,-updates,-security} > ./etc/apt/sources.list
# debootstrap only uses the release pocket: pull updates and install the kernel from -updates/-security
rm -f ./etc/machine-id
chroot . apt-get update
chroot . apt-get -y dist-upgrade
chroot . apt-get install --no-install-recommends -y live-boot openssh-server linux-image-virtual zstd linux-firmware-misc linux-firmware-realtek linux-firmware-qlogic
mkdir -p /etc/systemd/{network,system}
cat > ./etc/systemd/network/80-dhcp.network <<NETWORK
[Match]
Name=!lo* !docker*
[Network]
DHCP=yes
NETWORK
cat > ./etc/systemd/system/http_hook.service <<HTTP_HOOK
[Unit]
Description=Fetch via http and run script provided via http_hook kernel parameter
Wants=network-online.target
After=network-online.target
[Service]
Type=oneshot
ExecStart=/bin/bash -c ". <(grep -oP 'http_hook=\K\S+' /proc/cmdline|xargs -r -L1 -P1 curl -sf)"
[Install]
WantedBy=multi-user.target
HTTP_HOOK

# console getty wrapper: log in as root automatically if the kernel was booted with "autologin"
mkdir -p ./usr/local/sbin ./etc/systemd/system/{getty,serial-getty}@.service.d
cat > ./usr/local/sbin/console-getty <<CONSOLE_GETTY
#!/bin/sh
grep -qw autologin /proc/cmdline &&
    exec /sbin/agetty --autologin root --noclear --keep-baud - "\${1:-linux}"
exec /sbin/agetty -o '-p -- \\u' --noclear --keep-baud - "\${1:-linux}"
CONSOLE_GETTY
chmod 755 ./usr/local/sbin/console-getty
tee ./etc/systemd/system/{getty,serial-getty}@.service.d/autologin.conf <<AUTOLOGIN >/dev/null
[Service]
ExecStart=
ExecStart=-/usr/local/sbin/console-getty \$TERM
AUTOLOGIN

chroot . /bin/bash -c "systemctl enable systemd-networkd.service && systemctl enable http_hook"

sed -i -e '/^PermitRootLogin/d' -e '$aPermitRootLogin without-password' ./etc/ssh/sshd_config
> ./etc/machine-id
#echo "root:root"|chpasswd --root $PWD

rm -rf ./var/cache/apt ./etc/{hostname,hosts} ./var/log/*.log ./root/.cache
mksquashfs . ./boot/root.squashfs -b 1048576 -comp xz -Xdict-size 100% -regex -e "proc/.*" -e "sys/.*" -e "run/.*" -e "var/lib/apt/lists/.*" -e "boot/.*"
cd ./boot && chmod -R +r .
build_iso $PWD/ubuntu-${VERSION_ID}-live.iso $(ls vmlinuz-*generic) $(ls initrd.img-*generic) root.squashfs
# stat -c with a format starting with "-" is rejected by the uutils coreutils used since Ubuntu 25.10
setpriv --reuid=$(stat -c %u $0) --regid=$(stat -c %g $0) --clear-groups cp root.squashfs {vmlinuz,initrd}*generic *.iso $OUTPUT_DIR
