#!/usr/bin/bash

MAIN_TITLE="Heroana OS Installer"

SCRIPTS_DIR="$(dirname -- "${BASH_SOURCE[0]}")"
PARENT_DIR="$(dirname -- "$SCRIPTS_DIR")"
CONFIGS_DIR="${PARENT_DIR}/config"
IMG_DIR="${PARENT_DIR}/img"
DOTFILES_DIR="${PARENT_DIR}/dotfiles"


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

    disk_to_install="$choice_selected"
}

get_user_info() {
    local name_input
    local user_input
    local host_input
    local password_input
    local password_match
    local confirm_password
    local team_input
    local email_input
    local locale_input
    local keyboard_input
    local timezone_input
    
    name_input=$(whiptail --title "${MAIN_TITLE}" --inputbox "
    Full Name
" 0 0 1>&2 2>&3 3>&1)
    user_input=$(whiptail --title "${MAIN_TITLE}" --inputbox "
    Username
" 0 0 "$(tr "[:lower:]" "[:upper:]" "$name_input" | sed 's///g')" 1>&2 2>&3 3>&1)
    host_input=$(whiptail --title "${MAIN_TITLE}" --inputbox "

" 0 0 "$user_input" 1>&2 2>&3 3>&1)

    password_input=$(whiptail --title "${MAIN_TITLE}" --inputbox "
    Password
" 0 0 1>&2 2>&3 3>&1)
    while [ whiptail --title "${MAIN_TITLE}" --inputbox "
    Password
" 0 0 1>&2 2>&3 3>&1 -ne "$password_input" ]
    do
        
}

install_system() {
    echo "Disk: $disk_to_install"
    
}

quit() {
    whiptail --title "${MAIN_TITLE}" --msgbox "Well, glad to have been with you! Bye, bye!!" 0 0
    exit 1
}

main() {
    whiptail --title "${MAIN_TITLE}" --yesno "

Hello, nice to meet you!

This is the Live Installer of the Heroana OS.
If you want to install the program, please, proceed with the installation.
If you do not want to live install, and, instead, want to test it first, or something like this, please, install the other iso in the site heroana.edmilsonrodrigues.net.br.

Do you want to proceed with the installation?
" 0 0 || quit

    get_fs_info

    install_system
}

main



