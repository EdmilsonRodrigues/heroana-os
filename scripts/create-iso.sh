#!/usr/bin/sh
set -e

OS_DIR=${1-"/mnt/heroana-os"}

apt install -y xorriso grub-pc-bin grub-efi-amd64-bin mtools dosfstools isolinux

# Bind mount host pseudo-filesystems for chroot operations
mount --bind /dev "${OS_DIR}/dev"
mount --bind /dev/pts "${OS_DIR}/dev/pts"
mount --bind /proc "${OS_DIR}/proc"
mount --bind /sys "${OS_DIR}/sys"

chroot "${OS_DIR}" apt install -y linux-image-amd64 linux-headers-amd64 grub-efi-amd64 live-boot

umount "${OS_DIR}/sys"
umount "${OS_DIR}/proc"
umount "${OS_DIR}/dev/pts" || true
umount "${OS_DIR}/dev" || true

# 1. Dynamically discover the kernel and initrd versions from the target root
KERNEL_IMG=$(chroot "${OS_DIR}" ls boot/ | grep '^vmlinuz-' | head -n1)
INITRD_IMG=$(chroot "${OS_DIR}" ls boot/ | grep '^initrd.img-' | head -n1)

if [ -z "$KERNEL_IMG" ] || [ -z "$INITRD_IMG" ]; then
    echo "Error: Could not find kernel or initrd in ${OS_DIR}/boot/" >&2
    exit 1
fi

cat << EOF > "${OS_DIR}/boot/grub/grub.cfg"
set timeout=5
set default=0

menuentry "Heroana OS (Live / Install)" {
    search --no-floppy --label HEROANA_OS --set=root
    linux /boot/${KERNEL_IMG} root=/dev/sr0 rw quiet splash
    initrd /boot/${INITRD_IMG}
}
EOF

# 2. Create early config file to guarantee prefix and config discovery
cat << 'EOF' > /tmp/early.cfg
search --no-floppy --label HEROANA_OS --set=root
set prefix=($root)/boot/grub
configfile ($root)/boot/grub/grub.cfg
EOF

# 3. Generate UEFI standalone bootloader with embedded early config
mkdir -p "${OS_DIR}/boot/grub/efi"
grub-mkimage -O x86_64-efi \
    -p "/boot/grub" \
    -c /tmp/early.cfg \
    -o "${OS_DIR}/boot/grub/efi/BOOTX64.EFI" \
    iso9660 search search_label search_fs_uuid configfile normal linux \
    part_gpt part_msdos fat ext2

# Populate EFI image
mkdir -p "${OS_DIR}/boot/grub"
dd if=/dev/zero of="${OS_DIR}/boot/grub/efi.img" bs=1M count=4 status=none
mkfs.vfat -F 12 "${OS_DIR}/boot/grub/efi.img" >/dev/null

mmd -i "${OS_DIR}/boot/grub/efi.img" ::/EFI ::/EFI/BOOT
mcopy -i "${OS_DIR}/boot/grub/efi.img" "${OS_DIR}/boot/grub/efi/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "${OS_DIR}/boot/grub/efi.img" "${OS_DIR}/boot/grub/grub.cfg" ::/EFI/BOOT/grub.cfg

# Verify EFI binary was copied successfully
mdir -i "${OS_DIR}/boot/grub/efi.img" ::/EFI/BOOT

# 4. Generate BIOS El Torito boot image with padding and early config
mkdir -p "${OS_DIR}/boot/grub/i386-pc"
grub-mkimage -O i386-pc \
    -p "/boot/grub" \
    -c /tmp/early.cfg \
    -o "${OS_DIR}/boot/grub/i386-pc/core.img" \
    biosdisk iso9660 normal configfile linux \
    search search_label part_msdos part_gpt

IMG="${OS_DIR}/boot/grub/i386-pc/eltorito.img"
cat /usr/lib/grub/i386-pc/cdboot.img "${OS_DIR}/boot/grub/i386-pc/core.img" > "$IMG"
rm -f "${OS_DIR}/boot/grub/i386-pc/core.img"

# Pad image to a multiple of 2048 bytes for reliable CD sector mapping
SIZE=$(stat -c %s "$IMG")
PAD=$(( (2048 - SIZE % 2048) % 2048 ))
[ "$PAD" -gt 0 ] && dd if=/dev/zero bs=1 count=$PAD >> "$IMG"
SECTORS=$(( $(stat -c %s "$IMG") / 512 ))

# 5. Build hybrid BIOS + UEFI ISO using xorriso
xorriso -as mkisofs \
    -o /mnt/heroana-os.iso \
    -iso-level 3 \
    -r -J \
    -V "HEROANA_OS" \
    -b boot/grub/i386-pc/eltorito.img \
    -c boot/grub/boot.cat \
    -no-emul-boot \
    -boot-load-size ${SECTORS} \
    -boot-info-table \
    -eltorito-alt-boot \
    -e boot/grub/efi.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    "${OS_DIR}"
