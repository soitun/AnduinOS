#!/bin/bash
#==========================
# Set up the environment
#==========================
set -e                  # exit on error
set -o pipefail         # exit on pipeline error
set -u                  # treat unset variable as error
export DEBIAN_FRONTEND=noninteractive
export LATEST_VERSION="1.4.2"
export CODE_NAME="questing"
export OS_ID="AnduinOS"
export CURRENT_VERSION=$(cat /etc/lsb-release | grep DISTRIB_RELEASE | cut -d "=" -f 2)

#==========================
# Color
#==========================
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

#==========================
# Print Colorful Text
#==========================
function print_ok() {
  echo -e "${OK} ${Blue} $1 ${Font}"
}

function print_error() {
  echo -e "${ERROR} ${Red} $1 ${Font}"
}

function print_warn() {
  echo -e "${WARNING} ${Yellow} $1 ${Font}"
}

#==========================
# Judge function
#==========================
function judge() {
  if [[ 0 -eq $? ]]; then
    print_ok "$1 succeeded"
    sleep 0.2
  else
    print_error "$1 failed"
    exit 1
  fi
}

function ensureCurrentOsAnduinOs() {
    # Ensure the current OS is AnduinOS
    if ! grep -q "DISTRIB_ID=AnduinOS" /etc/lsb-release; then
        print_error "This script can only be run on AnduinOS."
        exit 1
    fi
}

function upgrade_140_to_141() {
    print_ok "Upgrading from version 1.4.0 to 1.4.1..."
    sudo apt-get update
    sudo apt-get install sane-airscan sane-utils simple-scan -y --no-install-recommends

    print_ok "Installing do-anduinos-autorepair tool to /usr/local/bin/..."
    BRANCH=$(grep -oP "VERSION_ID=\"\\K\\d+\\.\\d+" /etc/os-release)
    sudo wget -O /usr/local/bin/do-anduinos-autorepair "https://gitlab.aiursoft.com/anduin/anduinos/-/raw/${BRANCH}/src/mods/40-do-anduinos-autorepair-mod/do-anduinos-autorepair.sh"
    sudo chmod +x /usr/local/bin/do-anduinos-autorepair
    judge "Install do-anduinos-autorepair tool"

    print_ok "Successfully upgraded to version 1.4.1"
}

function upgrade_141_to_142() {
    print_ok "Upgrading from version 1.4.1 to 1.4.2..."

    # gstreamer plugins and tools
    print_ok "Installing GStreamer plugins and tools..."
    sudo apt-get update
    sudo apt-get install -y \
      gstreamer1.0-plugins-base \
      gstreamer1.0-plugins-good \
      gstreamer1.0-plugins-bad \
      gstreamer1.0-plugins-ugly \
      gstreamer1.0-libav \
      libavcodec-extra \
      gstreamer1.0-pipewire \
      gstreamer1.0-alsa \
      gstreamer1.0-gl \
      gstreamer1.0-gtk3 \
      gstreamer1.0-x \
      gstreamer1.0-tools \
      gstreamer1.0-packagekit \
      gstreamer1.0-plugins-base-apps --no-install-recommends
    judge "Install GStreamer plugins and tools"

    #do-anduinos-autorepair
    print_ok "Updating do-anduinos-autorepair tool to /usr/local/bin/..."
    BRANCH=$(grep -oP "VERSION_ID=\"\\K\\d+\\.\\d+" /etc/os-release)
    sudo wget -O /usr/local/bin/do-anduinos-autorepair "https://gitlab.aiursoft.com/anduin/anduinos/-/raw/${BRANCH}/src/mods/40-do-anduinos-autorepair-mod/do-anduinos-autorepair.sh"
    sudo chmod +x /usr/local/bin/do-anduinos-autorepair
    judge "Update do-anduinos-autorepair tool"

    #do_anduinos_upgrade
    print_ok "Updating do_anduinos tool to /usr/local/bin/..."
    cat <<"EOF" | sudo tee /usr/local/bin/do_anduinos_upgrade > /dev/null
#!/bin/bash
set -o pipefail

echo "Upgrading AnduinOS..."

VERSION=$(grep -oP "VERSION_ID=\"\K\d+\.\d+" /etc/os-release)
URL="https://www.anduinos.com/upgrade/$VERSION"

echo "Current fork version is: $VERSION, running upgrade script..."

SCRIPT_CONTENT=$(wget -qO- "$URL")
WGET_EXIT_CODE=$?

if [ $WGET_EXIT_CODE -ne 0 ] || [ -z "$SCRIPT_CONTENT" ]; then
    echo "Error: Failed to download upgrade script from server."
    echo "The server might be down or the upgrade path for version $VERSION doesn't exist."
    exit 1
fi

echo "$SCRIPT_CONTENT" | bash
EOF
    sudo chmod +x /usr/local/bin/do_anduinos_upgrade
    judge "Update do_anduinos tool"
    print_ok "Successfully upgraded to version 1.4.2"
}

function applyLsbRelease() {

    # Update /etc/os-release
    sudo bash -c "cat > /etc/os-release <<EOF
PRETTY_NAME=\"AnduinOS $LATEST_VERSION\"
NAME=\"AnduinOS\"
VERSION_ID=\"$LATEST_VERSION\"
VERSION=\"$LATEST_VERSION ($CODE_NAME)\"
VERSION_CODENAME=$CODE_NAME
ID=ubuntu
ID_LIKE=debian
HOME_URL=\"https://www.anduinos.com/\"
SUPPORT_URL=\"https://github.com/Anduin2017/AnduinOS/discussions\"
BUG_REPORT_URL=\"https://github.com/Anduin2017/AnduinOS/issues\"
PRIVACY_POLICY_URL=\"https://www.ubuntu.com/legal/terms-and-policies/privacy-policy\"
UBUNTU_CODENAME=$CODE_NAME
EOF"

    # Update /etc/lsb-release
    sudo bash -c "cat > /etc/lsb-release <<EOF
DISTRIB_ID=AnduinOS
DISTRIB_RELEASE=$LATEST_VERSION
DISTRIB_CODENAME=$CODE_NAME
DISTRIB_DESCRIPTION=\"AnduinOS $LATEST_VERSION\"
EOF"

    # Update /etc/issue
    echo "AnduinOS ${LATEST_VERSION} \n \l
" | sudo tee /etc/issue

    # Update /usr/lib/os-release
    sudo cp /etc/os-release /usr/lib/os-release
}

function main() {
    print_ok "Current version is: ${CURRENT_VERSION}. Checking for updates..."

    # Ensure the current OS is AnduinOS
    ensureCurrentOsAnduinOs

    # Compare current version with latest version
    if [ "$CURRENT_VERSION" == "$LATEST_VERSION" ]; then
        print_ok "Your system is already up to date. No update available."
        exit 0
    fi

    print_ok "This script will upgrade your system to version ${LATEST_VERSION}..."
    print_ok "Please press CTRL+C to cancel... Countdown will start in 5 seconds..."
    sleep 5

    # Run necessary upgrades based on current version
    case "$CURRENT_VERSION" in
          "1.4.0")
              # Call upgrade functions for 1.4.0 to 1.4.1
              upgrade_140_to_141
              upgrade_141_to_142
              ;;
          "1.4.1")
              # Call upgrade function for 1.4.1 to 1.4.2
              upgrade_141_to_142
              ;;
          "1.4.2")
              print_ok "Your system is already up to date. No update available."
              exit 0
              ;;
           *)
              print_error "Unknown current version. Exiting."
              exit 1
              ;;
    esac

    # Grammar sample:
    # case "$CURRENT_VERSION" in
    #     "1.0.2")
    #         upgrade_102_to_103
    #         upgrade_103_to_104
    #         ;;
    #     "1.0.3")
    #         upgrade_103_to_104
    #         ;;
    #     "1.0.4")
    #         print_ok "Your system is already up to date. No update available."
    #         exit 0
    #         ;;
    #     *)
    #         print_error "Unknown current version. Exiting."
    #         exit 1
    #         ;;
    # esac

    # Apply updates to lsb-release, os-release, and issue files
    applyLsbRelease
    print_ok "System upgraded successfully to version ${LATEST_VERSION}"
}

main