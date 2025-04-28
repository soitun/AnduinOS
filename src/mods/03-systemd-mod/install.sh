set -e                  # exit on error
set -o pipefail         # exit on pipeline error
set -u                  # treat unset variable as error

# we need to install systemd first, to configure machine id
print_ok "Installing systemd"

# Don't wait for network, because curl is not available
#waitNetwork
apt update
apt install $INTERACTIVE \
    libterm-readline-gnu-perl \
    systemd-sysv \
    curl \
    krb5-locales \
    publicsuffix \
    libnss-systemd \
    networkd-dispatcher \
    systemd-cryptsetup \
    linux-sysctl-defaults \
    shared-mime-info \
    dmsetup \
    xdg-user-dirs \
    ca-certificates \
    --no-install-recommends
judge "Install systemd"
