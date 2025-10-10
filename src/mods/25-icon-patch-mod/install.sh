set -e                  # exit on error
set -o pipefail         # exit on pipeline error
set -u                  # treat unset variable as error

print_ok "Patching default application icons"
# This is a hack. Because the icon theme doesn't cover `Papers` icon, we use `Evince` icon instead.
sed -i 's/Icon=org.gnome.Papers/Icon=org.gnome.Evince/' /usr/share/applications/org.gnome.Papers.desktop
judge "Patched default application icons"