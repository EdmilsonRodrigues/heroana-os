#!/usr/bin/bash
set -e

MAIN_TITLE="Heroana OS Installer"

SCRIPTS_DIR="$(dirname -- "${BASH_SOURCE[0]}")"
PARENT_DIR="$(dirname -- "$SCRIPTS_DIR")"
SIZE_EFI="512M"

quit() {
    whiptail --title "${MAIN_TITLE} - Exit" --msgbox "Well, glad to have been with you! Bye, bye!!" 0 0
    exit 1
}

get_fs_info() {
    whiptail --title "${MAIN_TITLE}" --defaultno --yesno "
    Okay, now, as of today, this live installer WILL format your drive and install Heroana OS. Side installs will be available soon.

    Are you sure you want to proceed?
" 0 0 || quit

    CHOICES=()
    while read -r name size; do
        CHOICES+=("$name" "Disk: $name Size: $size")
    done < <(lsblk -bndo NAME,SIZE,TYPE | awk '$3 == "disk" {print $1, $2}')

    local choice_selected
    choice_selected=$(whiptail --title "${MAIN_TITLE}" --menu "
    Choose now the disk you want to install the system.
" 0 0 0 "${CHOICES[@]}" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && quit

    disk_to_install="$choice_selected"

    local disk_bytes
    disk_bytes=$(lsblk -bndo SIZE "/dev/$disk_to_install" | head -n1)
    local disk_gb=$(( disk_bytes / 1024 / 1024 / 1024 ))

    SIZE_BOOT="1G"

    if [ "$disk_gb" -le 32 ]; then
        HAS_SWAP="yes"
        SIZE_SWAP="2G"
        SIZE_HOME="$(( disk_gb - 4 ))G"
    elif [ "$disk_gb" -le 128 ]; then
        HAS_SWAP="yes"
        SIZE_SWAP="4G"
        SIZE_HOME="$(( disk_gb - 10 ))G"
    else
        HAS_SWAP="yes"
        SIZE_SWAP="8G"
        SIZE_HOME="$(( disk_gb - 20 ))G"
    fi

    FS_ROOT=$(whiptail --title "${MAIN_TITLE} - Root Filesystem" --menu "Choose filesystem for Root" 0 0 3 \
        "ext4" "Ext4 filesystem" \
        "xfs" "XFS filesystem" \
        "btrfs" "Btrfs filesystem" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && quit

    FS_HOME=$(whiptail --title "${MAIN_TITLE} - Home Filesystem" --menu "Choose filesystem for Home" 0 0 3 \
        "ext4" "Ext4 filesystem" \
        "xfs" "XFS filesystem" \
        "btrfs" "Btrfs filesystem" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && quit

    while true; do
        local partition_summary="=== Partition Layout Proposal ===
Selected Disk: /dev/$disk_to_install (~${disk_gb} GB)

- EFI Partition:        $SIZE_EFI
- Boot Partition:       $SIZE_BOOT (ext4)
- Swap Partition:       $SIZE_SWAP (Enabled: $HAS_SWAP)
- Home Partition:       $SIZE_HOME (Filesystem: $FS_HOME)
- Root Partition (/):   Remaining space (Filesystem: $FS_ROOT)

Do you agree with these automatic partition sizes and filesystems?"

        if whiptail --title "${MAIN_TITLE} - Partition Layout" --yesno "$partition_summary" 0 0; then
            break
        else
            HAS_SWAP=$(whiptail --title "${MAIN_TITLE}" --menu "Enable Swap?" 0 0 2 "yes" "Use swap partition" "no" "No swap" 3>&1 1>&2 2>&3)
            [ $? -ne 0 ] && quit

            if [ "$HAS_SWAP" = "yes" ]; then
                SIZE_SWAP=$(whiptail --title "${MAIN_TITLE}" --inputbox "Enter Swap Size (e.g., 4G)" 0 0 "$SIZE_SWAP" 3>&1 1>&2 2>&3)
                [ $? -ne 0 ] && quit
            else
                SIZE_SWAP="0G"
            fi

            SIZE_BOOT=$(whiptail --title "${MAIN_TITLE}" --inputbox "Enter Boot Size (e.g., 1G)" 0 0 "$SIZE_BOOT" 3>&1 1>&2 2>&3)
            [ $? -ne 0 ] && quit

            SIZE_HOME=$(whiptail --title "${MAIN_TITLE}" --inputbox "Enter Home Size (e.g., 50G or all remaining)" 0 0 "$SIZE_HOME" 3>&1 1>&2 2>&3)
            [ $? -ne 0 ] && quit
        fi
    done
}

get_user_info() {
    USER_FULL_NAME=$(whiptail --title "${MAIN_TITLE} - Full Name" --inputbox "Full Name" 0 60 "Edmilson Rodrigues" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && quit

    local default_user
    default_user=$(echo "$USER_FULL_NAME" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

    USER=$(whiptail --title "${MAIN_TITLE} - Username" --inputbox "Username" 0 0 "$default_user" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && quit

    USER_HOST=$(whiptail --title "${MAIN_TITLE} - Host" --inputbox "Hostname" 0 0 "heroana" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && quit

    USER_TEAM=$(whiptail --title "${MAIN_TITLE} - Team" --inputbox "Team Name" 0 60 "DevOps Team" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && quit

    USER_EMAIL=$(whiptail --title "${MAIN_TITLE} - Email" --inputbox "Email Address" 0 60 "${USER}@${USER_HOST}" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && quit

    while true; do
        USER_PASSWORD=$(whiptail --title "${MAIN_TITLE} - Password" --passwordbox "Password" 0 60 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && quit

        local confirm_password
        confirm_password=$(whiptail --title "${MAIN_TITLE} - Confirm Password" --passwordbox "Confirm Password" 0 60 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && quit

        if [ "$USER_PASSWORD" = "$confirm_password" ]; then
            break
        else
            whiptail --title "${MAIN_TITLE}" --msgbox "Passwords do not match. Please try again." 0 0
        fi
    done

    local tz_choices=()
    while read -r tz; do
        tz_choices+=("$tz" "$tz")
    done < <(find /usr/share/zoneinfo -type f | sed 's|/usr/share/zoneinfo/||' | grep -v '^posix/' | grep -v '^right/' | sort)

    USER_TIMEZONE=$(whiptail --title "${MAIN_TITLE} - Timezone" --menu "Choose Timezone" 0 0 0 "${tz_choices[@]}" 3>&1 1>&2 2>&3)
    [ -z "$USER_TIMEZONE" ] && USER_TIMEZONE="UTC"

    local loc_choices=()
    while read -r loc; do
        loc_choices+=("$loc" "$loc")
    done < <(locale -a 2>/dev/null || echo "en_US.UTF-8")

    USER_LOCALE=$(whiptail --title "${MAIN_TITLE} - Locale" --menu "Choose Locale" 0 0 0 "${loc_choices[@]}" 3>&1 1>&2 2>&3)
    [ -z "$USER_LOCALE" ] && USER_LOCALE="en_US.UTF-8"

    local kb_choices=("en_US" "English (US)" "pt_BR" "Portuguese (Brazil)" "es" "Spanish" "fr" "French" "de" "German")
    USER_KB_LAYOUT=$(whiptail --title "${MAIN_TITLE} - Keyboard" --menu "Choose Keyboard Layout" 0 0 0 "${kb_choices[@]}" 3>&1 1>&2 2>&3)
    [ -z "$USER_KB_LAYOUT" ] && USER_KB_LAYOUT="en_US"
}

install_system() {
    local summary="=== Collected Configuration ===
Target Disk: $disk_to_install
Full Name:   $USER_FULL_NAME
Username:    $USER
Hostname:    $USER_HOST
Team:        $USER_TEAM
Email:       $USER_EMAIL
Timezone:    $USER_TIMEZONE
Locale:      $USER_LOCALE
Keyboard:    $USER_KB_LAYOUT

======= Partition Configurations =======
- EFI Partition:        $SIZE_EFI
- Boot Partition:       $SIZE_BOOT (ext4)
- Swap Partition:       $SIZE_SWAP (Enabled: $HAS_SWAP)
- Home Partition:       $SIZE_HOME ($FS_HOME)
- Root Partition (/):   Remaining space ($FS_ROOT)

Is this configuration correct? Do you want to proceed?"

    whiptail --title "${MAIN_TITLE} - Summary" --yesno "$summary" 0 0 || quit

    echo "Wiping and partitioning /dev/$disk_to_install..."

    sgdisk --zap-all "/dev/$disk_to_install"

    sgdisk -n "1:0:+${SIZE_EFI}" -t 1:ef00 -c 1:"EFI" "/dev/$disk_to_install"
    sgdisk -n "2:0:+${SIZE_BOOT}" -t 2:8300 -c 2:"BOOT" "/dev/$disk_to_install"

    local current_part=3
    if [ "$HAS_SWAP" = "yes" ] && [ "$SIZE_SWAP" != "0G" ]; then
        sgdisk -n "${current_part}:0:+${SIZE_SWAP}" -t "${current_part}:8200" -c "${current_part}:SWAP" "/dev/$disk_to_install"
        current_part=$((current_part + 1))
    fi

    sgdisk -n "${current_part}:0:+${SIZE_HOME}" -t "${current_part}:8300" -c "${current_part}:HOME" "/dev/$disk_to_install"
    local home_part_num=$current_part
    current_part=$((current_part + 1))

    sgdisk -n "${current_part}:0:0" -t "${current_part}:8300" -c "${current_part}:ROOT" "/dev/$disk_to_install"

    partprobe "/dev/$disk_to_install"
    sleep 2

    local p_prefix=""
    if [[ "$disk_to_install" =~ ^nvme ]] || [[ "$disk_to_install" =~ ^mmcblk ]]; then
        p_prefix="p"
    fi

    local dev_efi="/dev/${disk_to_install}${p_prefix}1"
    local dev_boot="/dev/${disk_to_install}${p_prefix}2"
    local dev_swap=""
    local dev_home=""
    local dev_root=""

    if [ "$HAS_SWAP" = "yes" ] && [ "$SIZE_SWAP" != "0G" ]; then
        if [ $home_part_num -eq 4 ]; then
            dev_swap="/dev/${disk_to_install}${p_prefix}3"
            dev_home="/dev/${disk_to_install}${p_prefix}4"
            dev_root="/dev/${disk_to_install}${p_prefix}5"
        else
            dev_home="/dev/${disk_to_install}${p_prefix}3"
            dev_root="/dev/${disk_to_install}${p_prefix}4"
        fi
    else
        if [ $home_part_num -eq 3 ]; then
            dev_home="/dev/${disk_to_install}${p_prefix}3"
            dev_root="/dev/${disk_to_install}${p_prefix}4"
        fi
    fi

    echo "Formatting partitions..."
    mkfs.vfat -F32 "$dev_efi"
    mkfs.ext4 -F "$dev_boot"

    if [ "$FS_ROOT" = "xfs" ]; then
        mkfs.xfs -f "$dev_root"
    elif [ "$FS_ROOT" = "btrfs" ]; then
        mkfs.btrfs -f "$dev_root"
    else
        mkfs.ext4 -F "$dev_root"
    fi

    if [ -n "$dev_swap" ]; then
        mkswap "$dev_swap"
        swapon "$dev_swap"
    fi

    if [ "$FS_HOME" = "xfs" ]; then
        mkfs.xfs -f "$dev_home"
    elif [ "$FS_HOME" = "btrfs" ]; then
        mkfs.btrfs -f "$dev_home"
    else
        mkfs.ext4 -F "$dev_home"
    fi

    local os_dir="/mnt/heroana-os"
    echo "Mounting filesystems to ${os_dir}..."
    mkdir -p "${os_dir}"
    mount "$dev_root" "${os_dir}"

    mkdir -p "${os_dir}/boot" "${os_dir}/home" "${os_dir}/boot/efi"
    mount "$dev_boot" "${os_dir}/boot"
    mount "$dev_home" "${os_dir}/home"
    mount "$dev_efi" "${os_dir}/boot/efi"

    # Pass configuration and partition identifiers to the background system installer
    sh "${SCRIPTS_DIR}/live-install.sh" \
        "${os_dir}" \
        "${PARENT_DIR}/scripts" \
        "${PARENT_DIR}/config" \
        "${PARENT_DIR}/img" \
        "${PARENT_DIR}/dotfiles" \
        "$USER" \
        "$USER_FULL_NAME" \
        "$USER_TEAM" \
        "$USER_EMAIL" \
        "$USER_PASSWORD" \
        "$USER_HOST" \
        "$USER_LOCALE" \
        "$USER_KB_LAYOUT" \
        "$USER_TIMEZONE" \
        "$dev_efi" \
        "$dev_boot" \
        "$dev_swap" \
        "$dev_home" \
        "$dev_root" \
        "$FS_ROOT" \
        "$FS_HOME" \
        "$disk_to_install"
}

main() {
    whiptail --title "${MAIN_TITLE} - Intro" --yesno "
Hello, nice to meet you!

This is the Live Installer of the Heroana OS.
If you want to install the program, please, proceed with the installation.
If you do not want to live install, and, instead, want to test it first, please install the other iso from the site.

Do you want to proceed with the installation?
" 0 0 || quit

    get_fs_info
    get_user_info
    install_system
}

main
