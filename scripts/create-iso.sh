#!/usr/bin/sh

OS_DIR=${1-"/mnt/heroana-os/"}
SCRIPTS_DIR=${2-"scripts"}
CONFIGS_DIR=${3-"configs"}

USER=${4-"familia"}
USER_FULL_NAME=${5-"Edmilson Rodrigues"}
USER_TEAM=${6-"DevOps Team"}
USER_EMAIL=${7-"edmilson.rodriguesn38@gmail.com"}
USER_HOME="/home/${USER}"
USER_GROUPS="docker incus-admin lxd microk8s libvirt kvm wireshark"


INSTALLATION_CMD_AWK="${SCRIPTS_DIR}/installation-commands.awk"
DEPS_FILE="${CONFIGS_DIR}/deps"

prepare_fs() {
    apt update
    apt install -y debootstrap

    debootstrap --arch=amd64 stable "$OS_DIR" http://deb.debian.org/debian/

    mount --bind /dev /mnt/heroana-os/dev
    mount --bind /proc /mnt/heroana-os/proc
    mount --bind /sys /mnt/heroana-os/sys
    mount --bind /dev/pts /mnt/heroana-os/dev/pts
    mount --bind /run /mnt/heroana-os/run
}

create_main_user() {
    apt install zsh

    for group in $USER_GROUPS
    do
        groupadd "$group"
    done

    _groups=$(echo "$USER_GROUPS" | sed 's/ /,/g')
    _comment="$USER_FULL_NAME,$USER_TEAM,$USER_EMAIL"

    useradd -c "$_comment" -m -s "/usr/bin/zsh" -G "$_groups"
}

configure_root() {
    
}

install_deps() {
    while IFS= read -r line; do
        test -e "$line" && printf "chroot ${OS_DIR} %s" "$line"
    done | awk -f "$INSTALLATION_CMD_AWK" "$DEPS_FILE"
}

umount_fs() {
    umount /mnt/heroana-os/dev
    umount /mnt/heroana-os/proc
    umount /mnt/heroana-os/sys
    umount /mnt/heroana-os/dev/pts
    umount /mnt/heroana-os/run    
}

main() {
    prepare_fs
    create_main_user
    install_deps
    configure_root
    configure_main_user
    configure_system
    umount_fs
}

