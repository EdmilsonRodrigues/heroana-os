#!/usr/bin/sh

OS_DIR=${1-"/mnt/heroana-os"}

mount_fs() {
    mount --bind /dev         "${OS_DIR}/dev"
    mount --bind /dev/null    "${OS_DIR}/dev/null"
    mount --bind /dev/urandom "${OS_DIR}/dev/urandom"
    mount --bind /dev/random  "${OS_DIR}/dev/random"
    mount --bind /proc        "${OS_DIR}/proc"
    mount --bind /sys         "${OS_DIR}/sys"
    mount -t devpts devpts    "${OS_DIR}/dev/pts"
    mount --bind /run         "${OS_DIR}/run"
}

mount_fs
