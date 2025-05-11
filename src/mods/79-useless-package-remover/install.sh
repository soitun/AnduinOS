set -e                  # exit on error
set -o pipefail         # exit on pipeline error
set -u                  # treat unset variable as error

# remove unused and clean up apt cache
print_ok "Removing unused packages..."
apt autoremove -y --purge
judge "Remove unused packages"

print_ok "Purging unnecessary packages"
packages=(
    # gnome-mahjongg
    # gnome-mines
    # gnome-sudoku
    # aisleriot
    # hitori
    # gnome-initial-setup
    # gnome-photos
    # eog
    # tilix
    # gnome-contacts
    # gnome-terminal
    # zutty
    # update-manager-core
    # gnome-shell-extension-ubuntu-dock
    # libreoffice-*
    # yaru-theme-unity
    # yaru-theme-icon
    # yaru-theme-gtk
    # apport
    # imagemagick*
    # ubuntu-pro-client
    # ubuntu-advantage-desktop-daemon
    # ubuntu-advantage-tools
    # ubuntu-pro-client-l10n
    # software-properties-gtk
)

for pkg in "${packages[@]}"; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
        print_warn "Error: package '$pkg' is installed." >&2
        apt autoremove -y --purge "$pkg"
        judge "Purge package $pkg"
    fi
done

mkdir -p -m 700 ~/.gnupg
gpg --no-default-keyring --keyring gnupg-ring:/tmp/onlyoffice.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys CB2DE8E5
chmod 644 /tmp/onlyoffice.gpg
sudo chown root:root /tmp/onlyoffice.gpg
sudo mv /tmp/onlyoffice.gpg /usr/share/keyrings/onlyoffice.gpg

echo 'deb [signed-by=/usr/share/keyrings/onlyoffice.gpg] https://download.onlyoffice.com/repo/debian squeeze main' | sudo tee -a /etc/apt/sources.list.d/onlyoffice.list

sudo apt-get update
sudo apt-get -y install onlyoffice-desktopeditors
