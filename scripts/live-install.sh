#!/usr/bin/sh

OS_DIR=${1-"/mnt/heroana-os"}
SCRIPTS_DIR=${2-"scripts"}
CONFIGS_DIR=${3-"config"}
IMG_DIR=${4-"img"}
DOTFILES_DIR=${5-"dotfiles"}

USER=${6-"familia"}
USER_FULL_NAME=${7-"Edmilson Rodrigues"}
USER_TEAM=${8-"DevOps Team"}
USER_EMAIL=${9-"edmilson.rodriguesn38@gmail.com"}
USER_PASSWORD="${10-123456}"
USER_HOST="${11-heroana}"
USER_LOCALE="${12-en_US.UTF-8}"
USER_KB_LAYOUT="${13-en_US}"
USER_TIMEZONE="${14-UTC}"
USER_GROUPS="docker incus-admin lxd microk8s libvirt kvm wireshark sudo"
USER_HOME="/home/${USER}"

export ISO_USER="$USER"

INSTALLATION_CMD_AWK="${SCRIPTS_DIR}/installation-commands.awk"
DEPS_FILE="${CONFIGS_DIR}/deps"

prepare_fs() {
    apt update
    apt install -y debootstrap

    debootstrap --arch=amd64 stable "${OS_DIR}/" http://deb.debian.org/debian/

    mount --bind /dev         "${OS_DIR}/dev"
    mount --bind /dev/null    "${OS_DIR}/dev/null"
    mount --bind /dev/urandom "${OS_DIR}/dev/urandom"
    mount --bind /dev/random  "${OS_DIR}/dev/random"
    mount --bind /proc        "${OS_DIR}/proc"
    mount --bind /sys         "${OS_DIR}/sys"
    mount -t devpts devpts    "${OS_DIR}/dev/pts"
    mount --bind /run         "${OS_DIR}/run"
}

configure_skel() {
    chroot "${OS_DIR}/" apt install -y zsh

    install -Dm644 "${DOTFILES_DIR}/kitty/kitty.conf" "${OS_DIR}/etc/skel/.config/kitty/kitty.conf"
    install -Dm644 "${DOTFILES_DIR}/kitty/theme.conf" "${OS_DIR}/etc/skel/.config/kitty/theme.conf"

    install -Dm644 "${DOTFILES_DIR}/sway/config"                       "${OS_DIR}/etc/skel/.config/sway/config"
    install -Dm644 "${DOTFILES_DIR}/sway/config.d/00-theme.conf"       "${OS_DIR}/etc/skel/.config/sway/config.d/00-theme.conf"
    install -Dm644 "${DOTFILES_DIR}/sway/config.d/00-keybindings.conf" "${OS_DIR}/etc/skel/.config/sway/config.d/00-keybindings.conf"

    install -Dm644 "${DOTFILES_DIR}/wofi/config"     "${OS_DIR}/etc/skel/.config/wofi/config"
    install -Dm644 "${DOTFILES_DIR}/wofi/styles.css" "${OS_DIR}/etc/skel/.config/wofi/styles.css"

    install -Dm644 "${DOTFILES_DIR}/waybar/config"    "${OS_DIR}/etc/skel/.config/waybar/config"
    install -Dm644 "${DOTFILES_DIR}/waybar/style.css" "${OS_DIR}/etc/skel/.config/waybar/style.css"

    install -Dm644 "${DOTFILES_DIR}/eww/eww.scss"                "${OS_DIR}/etc/skel/.config/eww/eww.scss"
    install -Dm644 "${DOTFILES_DIR}/eww/eww.yuck"                "${OS_DIR}/etc/skel/.config/eww/eww.yuck"
    install -Dm644 "${DOTFILES_DIR}/eww/eww_vars.yuck"           "${OS_DIR}/etc/skel/.config/eww/eww_vars.yuck"
    install -Dm644 "${DOTFILES_DIR}/eww/eww_widgets.yuck"        "${OS_DIR}/etc/skel/.config/eww/eww_widgets.yuck"
    install -Dm644 "${DOTFILES_DIR}/eww/scripts/start.sh"        "${OS_DIR}/etc/skel/.config/eww/scripts/start.sh"
    install -Dm644 "${DOTFILES_DIR}/eww/scripts/uptime.sh"       "${OS_DIR}/etc/skel/.config/eww/scripts/uptime.sh"
    install -Dm644 "${DOTFILES_DIR}/eww/scripts/day_format.sh"   "${OS_DIR}/etc/skel/.config/eww/scripts/day_format.sh"
    install -Dm644 "${DOTFILES_DIR}/eww/scripts/month_format.sh" "${OS_DIR}/etc/skel/.config/eww/scripts/month_format.sh"
    install -Dm644 "${DOTFILES_DIR}/eww/scripts/year_format.sh"  "${OS_DIR}/etc/skel/.config/eww/scripts/year_format.sh"

    _skel_bashrc="${OS_DIR}/etc/skel/.bashrc"
    echo >> "$_skel_bashrc"
    # shellcheck disable=SC2016
    echo 'eval "$(/opt/linuxbrew/bin/brew shellenv bash)"' >> "$_skel_bashrc"

    _skel_zshrc="${OS_DIR}/etc/skel/.zshrc"
    echo >> "$_skel_zshrc"
    # shellcheck disable=SC2016
    echo 'eval "$(/opt/linuxbrew/bin/brew shellenv zsh)"' >> "$_skel_zshrc"
}

create_main_user() {
    chroot "${OS_DIR}/" apt update
    chroot "${OS_DIR}/" apt install -y locales
    chroot "${OS_DIR}/" sed -i "/${USER_LOCALE}/s/^# //g" /etc/locale.gen
    chroot "${OS_DIR}/" locale-gen
    chroot "${OS_DIR}/" update-locale LANG="${USER_LOCALE}"

    for group in $USER_GROUPS
    do
        chroot "${OS_DIR}/" groupadd -f "$group" 2>/dev/null || true
    done

    _groups=$(echo "$USER_GROUPS" | sed 's/ /,/g')
    _comment="$USER_FULL_NAME,$USER_TEAM,$USER_EMAIL"

    chroot "${OS_DIR}/" useradd -c "$_comment" -m -s "/usr/bin/zsh" -G "$_groups" "$USER"
    echo "${USER}:${USER_PASSWORD}" | chroot "${OS_DIR}/" chpasswd
}

configure_root() {
    install -Dm644 "${IMG_DIR}/wallpaper.jpg" "${OS_DIR}/usr/share/backgrounds/wallpaper.jpg"

    echo "export EDITOR=nano" >> "${OS_DIR}/etc/profile.d/editor.sh"
    echo "export VISUAL=nano" >> "${OS_DIR}/etc/profile.d/editor.sh"
    chmod +x "${OS_DIR}/etc/profile.d/editor.sh"

    echo "${USER_HOST}" > "${OS_DIR}/etc/hostname"
    cat << EOF > "${OS_DIR}/etc/hosts"
127.0.0.1   localhost
127.0.1.1   ${USER_HOST}

::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF

    chroot "${OS_DIR}" ln -sf "/usr/share/zoneinfo/${USER_TIMEZONE}" /etc/localtime
}

install_deps() {
    apt install -y gawk unzip

    chroot "${OS_DIR}/" bash -c "
  echo 'keyboard-configuration keyboard-configuration/layout select ${USER_KB_LAYOUT}' | debconf-set-selections
  echo 'keyboard-configuration keyboard-configuration/variant select ${USER_KB_LAYOUT}' | debconf-set-selections
"

    mkdir "${OS_DIR}/opt/linuxbrew"
    chroot "${OS_DIR}" chown -R "$ISO_USER:$ISO_USER" /opt/linuxbrew
    chroot "${OS_DIR}" apt install -y git curl unzip
    chroot "${OS_DIR}" git config --global --add safe.directory /opt/linuxbrew/Homebrew

    mkdir -p "${OS_DIR}/usr/local/share/fonts/maple-mono"
    curl -fsSL https://github.com/subframe7536/maple-font/releases/download/v7.9/MapleMono-TTF.zip -o "${OS_DIR}/tmp/maple-mono.zip"
    unzip "${OS_DIR}/tmp/maple-mono.zip" -d "${OS_DIR}/usr/local/share/fonts/maple-mono/"
    chroot "${OS_DIR}" chmod 644 /usr/local/share/fonts/maple-mono/*
    chroot "${OS_DIR}" chmod 755 /usr/local/share/fonts/maple-mono
    chroot "${OS_DIR}" chown -R root:root /usr/local/share/fonts/maple-mono
    chroot "${OS_DIR}" fc-cache -fv

    curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "${OS_DIR}/tmp/brew_install.sh"

    chroot --userspec="$ISO_USER:$ISO_USER" "${OS_DIR}" /bin/bash -c "export HOME=${USER_HOME} && NONINTERACTIVE=1 /bin/bash /tmp/brew_install.sh --path /opt/linuxbrew"

    rm -f "${OS_DIR}/tmp/brew_install.sh"

    gawk -f "$INSTALLATION_CMD_AWK" "$DEPS_FILE" | while IFS= read -r line; do
        [ -z "$line" ] && continue

        _userspec=""
        if echo "$line" | grep -q "brew "
        then
            _userspec="--userspec=$ISO_USER:$ISO_USER"
        fi

        if [ ! -z "$_userspec" ]
        then
            chroot "$_userspec" "${OS_DIR}" /bin/bash -c "export HOME=${USER_HOME} && $line"
        else
            chroot "${OS_DIR}" $line
        fi
    done

    mkdir -p "${OS_DIR}/etc/greetd"

    cat << 'EOF' > "${OS_DIR}/etc/greetd/config.toml"
[terminal]
vt = 1

[default_session]
command = "cage -s -- gtkgreet"
user = "_greetd"
EOF

    # Specify the sessions available to launch from gtkgreet
    echo "sway" > "${OS_DIR}/etc/greetd/environments"

    systemctl enable greetd
}

umount_fs() {
    umount "${OS_DIR}/dev/pts"
    umount "${OS_DIR}/dev/null"
    umount "${OS_DIR}/dev/urandom"
    umount "${OS_DIR}/dev/random"
    umount "${OS_DIR}/dev"
    umount "${OS_DIR}/proc"
    umount "${OS_DIR}/sys"
    umount "${OS_DIR}/run"
}

main() {
    prepare_fs
    configure_skel
    create_main_user
    install_deps
    configure_root
    # configure_main_user
    # configure_system
    umount_fs
}

main
