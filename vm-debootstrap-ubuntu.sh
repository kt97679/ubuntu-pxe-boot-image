#!/bin/bash

set -eu

SSH_PUB="$(cat ~/.ssh/*.pub)"
USERNAME=$USER
INSTALL_CODENAME=noble
INSTALL_HOSTNAME=ubuntu-dev

send_script_to_remote() {
    declare -p SSH_PUB
    declare -p USERNAME
    declare -p INSTALL_CODENAME
    declare -p INSTALL_HOSTNAME
    declare -f main
    echo "main"
    exit 0
}

main() {
    set -eux

    [ "${1:-}" == 'local' ] && send_script_to_remote

    exec &> >(tee /tmp/install.log)

    export http_proxy=http://10.0.2.2:3128/
    export https_proxy=$http_proxy
    apt-get update && apt-get install -y debootstrap gdisk
    sgdisk --zap-all /dev/sda
    sgdisk -n 0:0:+1MiB -t 0:ef02 -c 0:grub /dev/sda
    sgdisk -n 0:0:0 -t 0:8300 -c 0:root /dev/sda
    mkfs.ext4 /dev/sda2
    #tune2fs -O "^orphan_file,^metadata_csum_seed" /dev/sda2
    mount /dev/sda2 /mnt
    debootstrap --arch amd64 --variant=minbase $INSTALL_CODENAME /mnt/
    . /etc/os-release 
    grep "^deb h" /etc/apt/sources.list|sed -e "s/$UBUNTU_CODENAME/$INSTALL_CODENAME/" >/mnt/etc/apt/sources.list
    mount --make-private --rbind /dev  /mnt/dev
    mount --make-private --rbind /proc /mnt/proc
    mount --make-private --rbind /sys  /mnt/sys
    echo "$INSTALL_HOSTNAME" >/mnt/etc/hostname
    sed -e "s/\(127.0.1.1\).*/\1 $INSTALL_HOSTNAME/" /etc/hosts >/mnt/etc/hosts
    cat >/mnt/etc/fstab <<FSTAB
/dev/sda2 / ext4 errors=remount-ro 0 1
tmpfs /tmp tmpfs nosuid,nodev 0 0
FSTAB
    cat <<APT_CONF >/etc/apt/apt.conf.d/99_norecommends
APT::Install-Recommends "false";
APT::AutoRemove::RecommendsImportant "false";
APT::AutoRemove::SuggestsImportant "false";
APT_CONF
    chroot /mnt /bin/bash <<CHROOT
        set -eux
        apt-get update
        apt-get install -y --no-install-recommends grub2 linux-image-generic openssh-server systemd-sysv initramfs-tools sudo
        sed -i -e 's/^\(GRUB_CMDLINE_LINUX_DEFAULT\).*/\1="console=ttyS0,115200n8"/' /etc/default/grub
        cat > /etc/systemd/network/80-dhcp.network <<NETWORK
[Match]
Name=en*
[Network]
DHCP=yes
NETWORK
        systemctl enable systemd-networkd.service
        useradd -m -s /bin/bash $USERNAME
        usermod -p '*' $USERNAME
        echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/$USERNAME
        chmod 0440 /etc/sudoers.d/$USERNAME
        mkdir /home/$USERNAME/.ssh
        echo "$SSH_PUB" >/home/$USERNAME/.ssh/authorized_keys
        chown -R $USERNAME:$USERNAME /home/$USERNAME
        usermod -a -G adm,cdrom,dip,plugdev,sudo $USERNAME
        update-initramfs -c -k all
        grub-install /dev/sda
        update-grub
CHROOT
}

main local
