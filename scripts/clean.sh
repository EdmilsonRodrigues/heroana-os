#!/usr/bin/sh

OS_DIR=${1-"/mnt/heroana-os"}
umount_fs() {
    umount "${OS_DIR}/dev/pts"
    umount "${OS_DIR}/dev/null"
    umount "${OS_DIR}/dev/random"
    umount "${OS_DIR}/dev/urandom"
    umount "${OS_DIR}/dev"
    umount "${OS_DIR}/proc"
    umount "${OS_DIR}/sys"
    umount "${OS_DIR}/run"
}

umount_fs
rm -rf "${OS_DIR}"
