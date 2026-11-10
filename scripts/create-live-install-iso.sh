#!/usr/bin/sh
set -e

BUILD_DIR=${1-"/mnt/liveinstaller"}
SHARED_DIR=${2-"/mnt/shared"}
OUTPUT_ISO=${3-"/mnt/heroana-os-liveinstaller.iso"}
ISO_ROOT="/mnt/iso-root"

echo "=== Step 1: Preparing base filesystem using debootstrap ==/root/installer"
apt update
apt install -y debootstrap xorriso grub-pc-bin grub-efi-amd64-bin mtools dosfstools isolinux squashfs-tools

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

debootstrap --arch=amd64 stable "$BUILD_DIR" http://deb.debian.org/debian/

# Bind mount pseudo-filesystems for chroot operations
mount --bind /dev           "$BUILD_DIR/dev"
mount --bind /dev/null      "$BUILD_DIR/dev/null"
mount --bind /dev/urandom   "$BUILD_DIR/dev/urandom"
mount --bind /dev/random    "$BUILD_DIR/dev/random"
mount --bind /proc          "$BUILD_DIR/proc"
mount --bind /sys           "$BUILD_DIR/sys"
mount -t devpts devpts      "$BUILD_DIR/dev/pts"
mount --bind /run           "$BUILD_DIR/run"

# Ensure cleanup on unexpected exit
trap 'umount "$BUILD_DIR/run" "$BUILD_DIR/dev/pts" "$BUILD_DIR/dev/sys" "$BUILD_DIR/proc" "$BUILD_DIR/dev/random" "$BUILD_DIR/dev/urandom" "$BUILD_DIR/dev/null" "$BUILD_DIR/dev" 2>/dev/null || true' EXIT

echo "=== Step 2: Installing core packages and disk utilities inside the environment ==="
chroot "$BUILD_DIR" apt update
chroot "$BUILD_DIR" apt install -y \
    linux-image-amd64 \
    linux-headers-amd64 \
    grub-efi-amd64 \
    live-boot \
    systemd-sysv \
    whiptail \
    gdisk \
    parted \
    util-linux \
    dosfstools \
    xfsprogs \
    btrfs-progs \
    locales-all \
    sudo \
    zsh \
    git \
    curl

# CRUCIAL: Update initramfs so live-boot modules are baked into the initrd
echo "Updating initramfs for live-boot..."
chroot "$BUILD_DIR" update-initramfs -u -k all

echo "=== Step 3: Copying shared installer files to /root/installer ==="
mkdir -p "$BUILD_DIR/root/installer"
if [ -d "$SHARED_DIR" ]; then
    cp -r "$SHARED_DIR"/* "$BUILD_DIR/root/installer/"
else
    echo "Warning: Shared directory $SHARED_DIR not found. Ensure your scripts and dotfiles are placed correctly."
fi

echo "=== Step 4: Configuring root autologin and live installer auto-launch ==="
mkdir -p "$BUILD_DIR/etc/systemd/system/getty@tty1.service.d"
cat << 'EOF' > "$BUILD_DIR/etc/systemd/system/getty@tty1.service.d/autologin.conf"
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I $TERM
EOF

# Safe launcher: sets TERM and drops to shell if installer exits
cat << 'EOF' > "$BUILD_DIR/root/.bash_profile"
if [ "$(tty)" = "/dev/tty1" ]; then
    export TERM=linux
    export NCURSES_NO_UTF8_ACS=1

    if [ -f /root/installer/scripts/live-installer.bash ]; then
        /usr/bin/bash /root/installer/scripts/live-installer.bash
    else
        echo "Error: live-installer.sh not found in /root/installer/scripts/"
    fi

    echo ""
    echo "Installer session ended. Dropping to shell..."
    exec /bin/bash
fi
EOF

# Clean up bind mounts before squashfs packaging
umount "$BUILD_DIR/run"
umount "$BUILD_DIR/dev/pts"
umount "$BUILD_DIR/proc"
umount "$BUILD_DIR/sys"
umount "$BUILD_DIR/dev/random"
umount "$BUILD_DIR/dev/urandom"
umount "$BUILD_DIR/dev/null"
umount "$BUILD_DIR/dev"

echo "=== Step 5: Dynamically discovering kernel and initrd versions ==="
KERNEL_IMG=$(chroot "$BUILD_DIR" ls boot/ | grep '^vmlinuz-' | head -n1)
INITRD_IMG=$(chroot "$BUILD_DIR" ls boot/ | grep '^initrd.img-' | head -n1)

if [ -z "$KERNEL_IMG" ] || [ -z "$INITRD_IMG" ]; then
    echo "Error: Could not find kernel or initrd in $BUILD_DIR/boot/" >&2
    exit 1
fi

echo "=== Step 6: Staging ISO contents and creating SquashFS ==="
rm -rf "$ISO_ROOT"
mkdir -p "$ISO_ROOT/live" "$ISO_ROOT/boot/grub"

mksquashfs "$BUILD_DIR" "$ISO_ROOT/live/filesystem.squashfs" -comp xz -e boot

cp "$BUILD_DIR/boot/$KERNEL_IMG" "$ISO_ROOT/boot/"
cp "$BUILD_DIR/boot/$INITRD_IMG" "$ISO_ROOT/boot/"

cat << EOF > "$ISO_ROOT/boot/grub/grub.cfg"
set timeout=5
set default=0

menuentry "Heroana OS (Live Installer)" {
    search --no-floppy --label HEROANA_OS --set=root
    linux /boot/$KERNEL_IMG boot=live components
    initrd /boot/$INITRD_IMG
}
EOF

cat << 'EOF' > /tmp/early.cfg
search --no-floppy --label HEROANA_OS --set=root
set prefix=($root)/boot/grub
configfile ($root)/boot/grub/grub.cfg
EOF

echo "=== Step 7: Generating UEFI and BIOS Boot Loaders ==="
mkdir -p "$ISO_ROOT/boot/grub/efi"
grub-mkimage -O x86_64-efi \
    -p "/boot/grub" \
    -c /tmp/early.cfg \
    -o "$ISO_ROOT/boot/grub/efi/BOOTX64.EFI" \
    iso9660 search search_label search_fs_uuid configfile normal linux \
    part_gpt part_msdos fat ext2

dd if=/dev/zero of="$ISO_ROOT/boot/grub/efi.img" bs=1M count=4 status=none
mkfs.vfat -F 12 "$ISO_ROOT/boot/grub/efi.img" >/dev/null

mmd -i "$ISO_ROOT/boot/grub/efi.img" ::/EFI ::/EFI/BOOT
mcopy -i "$ISO_ROOT/boot/grub/efi.img" "$ISO_ROOT/boot/grub/efi/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "$ISO_ROOT/boot/grub/efi.img" "$ISO_ROOT/boot/grub/grub.cfg" ::/EFI/BOOT/grub.cfg

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

SIZE=$(stat -c %s "$IMG")
PAD=$(( (2048 - SIZE % 2048) % 2048 ))
[ "$PAD" -gt 0 ] && dd if=/dev/zero bs=1 count=$PAD >> "$IMG"
SECTORS=$(( $(stat -c %s "$IMG") / 512 ))

echo "=== Step 8: Compiling final hybrid ISO using xorriso ==="
xorriso -as mkisofs \
    -o "$OUTPUT_ISO" \
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

echo "ISO successfully built and stored at: $OUTPUT_ISO"
