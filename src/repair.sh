#!/bin/bash
set -e
set -o pipefail
set -u

PKG_TEMP_FILE=$(mktemp)
trap 'rm -f "$PKG_TEMP_FILE"' EXIT

Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
Blue="\033[36m"
Font="\033[0m"
GreenBG="\033[42;37m"
RedBG="\033[41;37m"
OK="${Green}[  OK  ]${Font}"
ERROR="${Red}[FAILED]${Font}"
WARNING="${Yellow}[ WARN ]${Font}"

function print_ok() {
  echo -e "${OK} ${Blue} $1 ${Font}"
}

function print_error() {
  echo -e "${ERROR} ${Red} $1 ${Font}"
}

function print_warn() {
  echo -e "${WARNING} ${Yellow} $1 ${Font}"
}

function judge() {
  if [[ 0 -eq $? ]]; then
    print_ok "$1 succeeded"
    sleep 0.2
  else
    print_error "$1 failed"
    exit 1
  fi
}

function clean_up() {
  print_ok "Cleaning up old files..."
  sudo umount /mnt/anduinos_squashfs >/dev/null 2>&1 || true
  sudo umount /mnt/anduinos_iso >/dev/null 2>&1 || true
  sudo rm -rf /mnt/anduinos_squashfs >/dev/null 2>&1 || true
  sudo rm -rf /mnt/anduinos_iso >/dev/null 2>&1 || true
  sudo rm /tmp/AnduinOS-1.4.0* >/dev/null 2>&1 || true
  judge "Cleanup"
}

clean_up

print_ok "Checking system compatibility..."
codename=$(lsb_release -cs)
if [[ "$codename" != "questing" ]] then
    print_error "This upgrade script can only be run *from* AnduinOS Questing."
    exit 1
fi
judge "System compatibility check"

echo -e "${Yellow}WARNING: This script is intended for repairing AnduinOS 1.4.0 systems.${Font}"
echo -e "${Yellow}Some configuration files may be overwritten during this process. Including:${Font}"
echo -e "${Yellow}- APT sources and preferences files${Font}"
echo -e "${Yellow}- GNOME session and Wayland session files${Font}"
echo -e "${Yellow}- GNOME extensions, icons, themes, and backgrounds${Font}"
echo -e "${Yellow}- System version information files${Font}"
echo -e "${Yellow}Please ensure you have backups of any important data before proceeding.${Font}"
read -p "Do you want to continue? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    print_error "Repair process aborted by user."
    exit 1
fi

print_ok "Ensure current user is not root..."
if [[ "$(id -u)" -eq 0 ]]; then
    print_error "This script must not be run as root. Please run as a normal user with sudo privileges."
    exit 1
fi

print_ok "Installing required packages (aria2, curl, lsb-release)..."
sudo apt install -y aria2 curl lsb-release
judge "Install required packages"

CURRENT_LANG=${LANG%%.*}
DOWNLOAD_URL="https://download.anduinos.com/1.4/1.4.0/AnduinOS-1.4.0-${CURRENT_LANG}.torrent"
HASH_URL="https://download.anduinos.com/1.4/1.4.0/AnduinOS-1.4.0-${CURRENT_LANG}.sha256"

print_ok "Current system language detected: ${CURRENT_LANG}"
print_ok "Attempting to download with URL: ${DOWNLOAD_URL}"

if ! curl --head --silent --fail "$DOWNLOAD_URL" >/dev/null; then
    print_warn "Language pack for ${CURRENT_LANG} not found, falling back to en_US"
    DOWNLOAD_URL="https://download.anduinos.com/1.4/1.4.0/AnduinOS-1.4.0-en_US.torrent"
    HASH_URL="https://download.anduinos.com/1.4/1.4.0/AnduinOS-1.4.0-en_US.sha256"
fi

if ! curl --head --silent --fail "$DOWNLOAD_URL" >/dev/null; then
    print_error "Download URL is not reachable. Please check your network connection."
    exit 1
fi

print_ok "Downloading AnduinOS 1.4.0 torrent, please wait..."
curl -o /tmp/AnduinOS-1.4.0.torrent "$DOWNLOAD_URL"
curl -o /tmp/AnduinOS-1.4.0.sha256 "$HASH_URL"
judge "Download AnduinOS 1.4.0 torrent"

print_ok "Starting download via aria2..."
aria2c --allow-overwrite=true --seed-ratio=0.0 --seed-time=0 -x 16 -s 16 -k 1M -d /tmp /tmp/AnduinOS-1.4.0.torrent
judge "Download AnduinOS 1.4.0 ISO"

ISO_FILE_PATH=$(ls /tmp/AnduinOS-1.4.0*.iso | head -n 1)
print_ok "Ensure downloaded ISO file exists..."
if [[ -f "$ISO_FILE_PATH" ]]; then
    print_ok "Downloaded ISO file found: $ISO_FILE_PATH"
else
    print_error "Downloaded ISO file not found."
    exit 1
fi

SHA256_FILE_PATH="/tmp/AnduinOS-1.4.0.sha256"

print_ok "Verifying download integrity..."
ACTUAL_SHA256=$(sha256sum "$ISO_FILE_PATH" | awk '{print $1}')
EXPECTED_SHA256=$(grep 'SHA256:' "$SHA256_FILE_PATH" | awk '{print $2}')
if [[ "$ACTUAL_SHA256" == "$EXPECTED_SHA256" ]]; then
    print_ok "SHA256 checksum verification passed."
else
    print_ok "Expected SHA256: $EXPECTED_SHA256"
    print_ok "Actual SHA256:   $ACTUAL_SHA256"
    print_error "SHA256 checksum verification failed. The downloaded file may be corrupted."
    exit 1
fi

print_ok "Mounting the ISO..."
sudo mkdir -p /mnt/anduinos_iso
sudo mount -o loop,ro "$ISO_FILE_PATH" /mnt/anduinos_iso
judge "Mount ISO"

print_ok "Verifying content in the ISO..."
(cd /mnt/anduinos_iso && sudo md5sum -c md5sum.txt)
judge "ISO content integrity verification"

print_ok "Mounting the filesystem.squashfs..."
sudo mkdir -p /mnt/anduinos_squashfs
sudo mount -o loop,ro /mnt/anduinos_iso/casper/filesystem.squashfs /mnt/anduinos_squashfs
judge "Mount filesystem.squashfs"

print_ok "Resetting APT configuration files..."
sudo rm /etc/apt/preferences.d/* >/dev/null 2>&1 || true
judge "Reset APT configuration files"

print_ok "Updating package mirrors..."
curl -s https://gitlab.aiursoft.com/anduin/init-server/-/raw/master/mirror.sh?ref_type=heads | bash
sudo apt update
judge "Update package mirrors"

print_ok "Updating Mozilla Team PPA..."
sudo rm -f /etc/apt/sources.list.d/mozillateam*
sudo rsync -Aax /mnt/anduinos_squashfs/etc/apt/sources.list.d/mozillateam* /etc/apt/sources.list.d/
sudo apt update
judge "Update Mozilla Team PPA"

print_ok "Generating package list for upgrade..."
MANIFEST_FILE="/mnt/anduinos_iso/casper/filesystem.manifest-desktop"

cut -d' ' -f1 "$MANIFEST_FILE" \
  | grep -v '^linux-' \
  | grep -v '^lib' \
  | grep -v '^plymouth-' \
  | grep -v '^software-properties-' > "$PKG_TEMP_FILE"

if [ ! -s "$PKG_TEMP_FILE" ]; then
    print_ok "No missing packages to install."
else
    if xargs sudo apt install --no-install-recommends -y < "$PKG_TEMP_FILE" > /tmp/anduinos-fast-install.log 2>&1; then
        print_ok "Fast mode installation successful."
        rm -f /tmp/anduinos-fast-install.log
    
    else
        print_warn "Fast mode failed. Retrying one by one (robust mode)..."
        print_ok "This may take 5-30 minutes. Only errors will be displayed."
        
        PKG_INSTALL_LOG="/tmp/anduinos-pkg-install.log"

        while read -r pkg; do
            if [ -n "$pkg" ]; then
                if sudo apt install --no-install-recommends -y "$pkg" > "$PKG_INSTALL_LOG" 2>&1; then
                    : # Bash的 "no-op" (空操作)
                else
                    print_warn "Failed to install package: '$pkg'. Details:"
                    cat "$PKG_INSTALL_LOG"
                    echo -e "${Red}-----------------------------------------------------${Font}"
                fi
            fi
        done < "$PKG_TEMP_FILE"
        
        rm -f "$PKG_INSTALL_LOG"
        print_ok "Robust missing package install mode finished."
    fi
fi
judge "Install missing packages"

print_ok "Removing obsolete packages..."
sudo apt autoremove -y \
  distro-info \
  software-properties-gtk \
  ubuntu-advantage-tools \
  ubuntu-pro-client \
  ubuntu-pro-client-l10n \
  ubuntu-release-upgrader-gtk \
  ubuntu-report \
  ubuntu-settings \
  update-notifier-common \
  update-manager \
  update-manager-core \
  update-notifier \
  ubuntu-release-upgrader-core \
  ubuntu-advantage-desktop-daemon \
  kgx
judge "Remove obsolete packages"

print_ok "Upgrading installed packages..."
sudo apt upgrade -y
sudo apt autoremove --purge -y
judge "System package cleanup"

print_ok "Upgrading GNOME Shell extensions..."
sudo rsync -Aax --update --delete /mnt/anduinos_squashfs/usr/share/gnome-shell/extensions/ /usr/share/gnome-shell/extensions/
judge "Upgrade GNOME Shell extensions"

print_ok "Upgrading icon and theme files..."
sudo rsync -Aax --update --delete /mnt/anduinos_squashfs/usr/share/icons/ /usr/share/icons/
sudo rsync -Aax --update --delete /mnt/anduinos_squashfs/usr/share/themes/ /usr/share/themes/
judge "Upgrade icon and theme files"

# Intel SOF Mod installation
print_ok "Installing Intel SOF Mod..."
#/usr/local/bin/sof-*
#/lib/firmware/intel/sof*
#/usr/share/alsa/ucm2/
sudo rsync -Aax --update /mnt/anduinos_squashfs/lib/firmware/intel/sof* /lib/firmware/intel/
sudo rsync -Aax --update /mnt/anduinos_squashfs/usr/local/bin/sof-* /usr/local/bin/
sudo rsync -Aax --update /mnt/anduinos_squashfs/usr/share/alsa/ucm2/ /usr/share/alsa/ucm2/
judge "Install Intel SOF Mod"

print_ok "Upgrading desktop backgrounds..."
sudo rsync -Aax --update /mnt/anduinos_squashfs/usr/share/backgrounds/ /usr/share/backgrounds/
sudo rsync -Aax --update /mnt/anduinos_squashfs/usr/share/gnome-background-properties/ /usr/share/gnome-background-properties/
judge "Upgrade desktop backgrounds"

print_ok "Upgrading APT configuration files..."
sudo rsync -Aax --update --delete /mnt/anduinos_squashfs/etc/apt/apt.conf.d/ /etc/apt/apt.conf.d/
judge "Upgrade APT configuration files"

print_ok "Upgrading APT preferences files..."
sudo rsync -Aax --update --delete /mnt/anduinos_squashfs/etc/apt/preferences.d/ /etc/apt/preferences.d/
judge "Upgrade APT preferences files"

print_ok "Upgrading session files..."
sudo rsync -Aax --update --delete /mnt/anduinos_squashfs/usr/share/gnome-session/sessions/ /usr/share/gnome-session/sessions/
sudo rsync -Aax --update --delete /mnt/anduinos_squashfs/usr/share/wayland-sessions/ /usr/share/wayland-sessions/
judge "Upgrade session files"

print_ok "Upgrading pixmaps..."
sudo rsync -Aax --update --delete /mnt/anduinos_squashfs/usr/share/pixmaps/ /usr/share/pixmaps/
judge "Upgrade pixmaps"

print_ok "Upgrading /etc/skel/ files..."
sudo rsync -Aax --update --delete /mnt/anduinos_squashfs/etc/skel/ /etc/skel/
judge "Upgrade /etc/skel/ files"

print_ok "Upgrading python-apt templates and distro info..."
sudo rsync -Aax --update --delete /mnt/anduinos_squashfs/usr/share/python-apt/templates/ /usr/share/python-apt/templates/
sudo rsync -Aax --update --delete /mnt/anduinos_squashfs/usr/share/distro-info/ /usr/share/distro-info/
judge "Upgrade python-apt templates and distro info"

print_ok "Upgrading deskmon service..."
sudo rsync -Aax /mnt/anduinos_squashfs/usr/local/bin/deskmon /usr/local/bin/deskmon
sudo rsync -Aax /mnt/anduinos_squashfs/etc/systemd/user/deskmon.service /etc/systemd/user/deskmon.service
sudo rsync -Aax /mnt/anduinos_squashfs/etc/systemd/user/default.target.wants/deskmon.service /etc/systemd/user/default.target.wants/deskmon.service
judge "Upgrade deskmon service"

print_ok "Upgrading gnome-session and wayland session files..."
sudo rsync -Aax --update --delete /mnt/anduinos_squashfs/usr/share/gnome-session/sessions/ /usr/share/gnome-session/sessions/
sudo rsync -Aax --update --delete /mnt/anduinos_squashfs/usr/share/wayland-sessions/ /usr/share/wayland-sessions/
judge "Upgrade gnome-session and wayland session files"

print_ok "Updating system version information..."
sudo rsync -Aax /mnt/anduinos_squashfs/usr/local/bin/do_anduinos_upgrade /usr/local/bin/do_anduinos_upgrade
sudo rsync -Aax /mnt/anduinos_squashfs/usr/bin/add-apt-repository /usr/bin/add-apt-repository
sudo rsync -Aax /mnt/anduinos_squashfs/etc/lsb-release /etc/lsb-release
sudo rsync -Aax /mnt/anduinos_squashfs/etc/issue /etc/issue
sudo rsync -Aax /mnt/anduinos_squashfs/etc/issue.net /etc/issue.net
sudo rsync -Aax /mnt/anduinos_squashfs/etc/os-release /etc/os-release
sudo rsync -Aax /mnt/anduinos_squashfs/usr/lib/os-release /usr/lib/os-release
sudo rsync -Aax /mnt/anduinos_squashfs/etc/legal /etc/legal
sudo rsync -Aax /mnt/anduinos_squashfs/etc/sysctl.d/20-apparmor-donotrestrict.conf /etc/sysctl.d/20-apparmor-donotrestrict.conf
sudo rsync -Aax /mnt/anduinos_squashfs/var/lib/flatpak/repo/config /var/lib/flatpak/repo/config
sudo rsync -Aax /mnt/anduinos_squashfs/usr/share/plymouth/themes/spinner/bgrt-fallback.png /usr/share/plymouth/themes/spinner/bgrt-fallback.png
sudo rsync -Aax /mnt/anduinos_squashfs/usr/share/plymouth/themes/spinner/watermark.png /usr/share/plymouth/themes/spinner/watermark.png
sudo rsync -Aax /mnt/anduinos_squashfs/usr/share/plymouth/ubuntu-logo.png /usr/share/plymouth/ubuntu-logo.png
judge "Update system version information"

print_ok "Applying dconf settings patch..."
PATCH_URL="https://gitlab.aiursoft.com/anduin/anduinos/-/raw/1.4/src/mods/35-dconf-patch/dconf.ini?ref_type=heads"
curl -sL "$PATCH_URL" | dconf load /org/gnome/
judge "Apply dconf settings patch"

print_ok "Updating initramfs..."
sudo update-initramfs -u -k all
judge "Update initramfs"

print_ok "Updating GRUB configuration..."
sudo update-grub
judge "Update GRUB configuration"

print_ok "Upgrade completed! Please reboot your system to apply all changes."

print_ok "Starting cleanup..."
clean_up