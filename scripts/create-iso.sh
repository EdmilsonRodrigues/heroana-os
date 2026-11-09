#!/usr/bin/sh
set -e

OS_DIR=${1-"/mnt/heroana-os"}
ISO_ROOT="/mnt/iso-root"

apt install -y xorriso grub-pc-bin grub-efi-amd64-bin mtools dosfstools isolinux squashfs-tools

# Bind mount host pseudo-filesystems for chroot operations
mount --bind /dev "${OS_DIR}/dev"
mount --bind /dev/pts "${OS_DIR}/dev/pts"
mount --bind /proc "${OS_DIR}/proc"
mount --bind /sys "${OS_DIR}/sys"

# Ensure cleanup on unexpected exit
trap 'umount "${OS_DIR}/sys" "${OS_DIR}/proc" "${OS_DIR}/dev/pts" "${OS_DIR}/dev" 2>/dev/null || true' EXIT

chroot "${OS_DIR}" apt install -y linux-image-amd64 linux-headers-amd64 grub-efi-amd64 live-boot

# Clean up bind mounts immediately
umount "${OS_DIR}/sys"
umount "${OS_DIR}/proc"
umount "${OS_DIR}/dev/pts"
umount "${OS_DIR}/dev"

# 1. Dynamically discover the kernel and initrd versions from the target root
KERNEL_IMG=$(chroot "${OS_DIR}" ls boot/ | grep '^vmlinuz-' | head -n1)
INITRD_IMG=$(chroot "${OS_DIR}" ls boot/ | grep '^initrd.img-' | head -n1)

if [ -z "$KERNEL_IMG" ] || [ -z "$INITRD_IMG" ]; then
    echo "Error: Could not find kernel or initrd in ${OS_DIR}/boot/" >&2
    exit 1
fi

# 2. Prepare ISO staging directory and compress OS root into SquashFS
rm -rf "$ISO_ROOT"
mkdir -p "$ISO_ROOT/live" "$ISO_ROOT/boot/grub"

echo "Compressing OS root into SquashFS (this may take a moment)..."
mksquashfs "${OS_DIR}" "$ISO_ROOT/live/filesystem.squashfs" -comp xz -e boot

# Copy kernel and initrd to the ISO staging boot directory so GRUB can load them
cp "${OS_DIR}/boot/${KERNEL_IMG}" "$ISO_ROOT/boot/"
cp "${OS_DIR}/boot/${INITRD_IMG}" "$ISO_ROOT/boot/"

# 3. Write grub.cfg in staging area
cat << EOF > "$ISO_ROOT/boot/grub/grub.cfg"
set timeout=5
set default=0

menuentry "Heroana OS (Live)" {
    search --no-floppy --label HEROANA_OS --set=root
    linux /boot/${KERNEL_IMG} boot=live components quiet splash
    initrd /boot/${INITRD_IMG}
}
EOF

# 4. Create early config file for standalone bootloaders
cat << 'EOF' > /tmp/early.cfg
search --no-floppy --label HEROANA_OS --set=root
set prefix=($root)/boot/grub
configfile ($root)/boot/grub/grub.cfg
EOF

# 5. Generate UEFI standalone bootloader with embedded early config
mkdir -p "$ISO_ROOT/boot/grub/efi"
grub-mkimage -O x86_64-efi \
    -p "/boot/grub" \
    -c /tmp/early.cfg \
    -o "$ISO_ROOT/boot/grub/efi/BOOTX64.EFI" \
    iso9660 search search_label search_fs_uuid configfile normal linux \
    part_gpt part_msdos fat ext2

# Populate EFI boot image
dd if=/dev/zero of="$ISO_ROOT/boot/grub/efi.img" bs=1M count=4 status=none
mkfs.vfat -F 12 "$ISO_ROOT/boot/grub/efi.img" >/dev/null

mmd -i "$ISO_ROOT/boot/grub/efi.img" ::/EFI ::/EFI/BOOT
mcopy -i "$ISO_ROOT/boot/grub/efi.img" "$ISO_ROOT/boot/grub/efi/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "$ISO_ROOT/boot/grub/efi.img" "$ISO_ROOT/boot/grub/grub.cfg" ::/EFI/BOOT/grub.cfg

# 6. Generate BIOS El Torito boot image with padding and early config
mkdir -p "$ISO_ROOT/boot/grub/i386-pc"
grub-mkimage -O i386-pc \
    -p "/boot/grub" \
    -c /tmp/early.cfg \
    -o "$ISO_ROOT/boot/grub/i386-pc/core.img" \
    biosdisk iso9660 normal configfile linux \
    search search_label part_msdos part_gpt

IMG="$ISO_ROOT/boot/grub/i386-pc/eltorito.img"
cat /usr/lib/grub/i386-pc/cdboot.img "$ISO_ROOT/boot/grub/i386-pc/core.img" > "$IMG"
rm -f "$ISO_ROOT/boot/grub/i386-pc/core.img"

# Pad image to a multiple of 2048 bytes for reliable CD sector mapping
SIZE=$(stat -c %s "$IMG")
PAD=$(( (2048 - SIZE % 2048) % 2048 ))
[ "$PAD" -gt 0 ] && dd if=/dev/zero bs=1 count=$PAD >> "$IMG"
SECTORS=$(( $(stat -c %s "$IMG") / 512 ))

# 7. Build hybrid BIOS + UEFI ISO from the staging directory using xorriso
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
    "$ISO_ROOT"

echo "ISO successfully built at /mnt/heroana-os.iso"
