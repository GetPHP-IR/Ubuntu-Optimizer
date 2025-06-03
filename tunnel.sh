#!/bin/bash

# Script to update Ubuntu, install optimizer, udp2raw, gost, wireguard-tools, and configure services

# Exit immediately if a command exits with a non-zero status.
set -e

echo "Starting server update process..."
# Update and upgrade system packages
sudo apt update && sudo apt upgrade -y
echo "Server update completed successfully."

# Create the target directory /opt/tunnel if it doesn't exist
echo "Creating directory /opt/tunnel if it doesn't exist..."
sudo mkdir -p /opt/tunnel
echo "Directory /opt/tunnel is ready."

echo "Changing directory to /opt/tunnel..."
# Change directory to /opt/tunnel
cd /opt/tunnel
echo "Current directory: $(pwd)"

echo "Downloading and executing Ubuntu optimizer script..."
# Download and execute the optimizer script
# Note: The optimizer script might have its own assumptions about paths.
curl -fsSL https://raw.githubusercontent.com/GetPHP-IR/Ubuntu-Optimizer/refs/heads/main/old.sh | sudo bash
echo "Optimizer script executed successfully."

echo "Downloading and extracting udp2raw..."
# Download udp2raw (will be downloaded to the current directory: /opt/tunnel)
wget https://github.com/wangyu-/udp2raw/releases/download/20230206.0/udp2raw_binaries.tar.gz -O udp2raw_binaries.tar.gz

# Extract the downloaded file (into /opt/tunnel)
tar -xzf udp2raw_binaries.tar.gz
echo "udp2raw extracted successfully."

echo "Moving udp2raw_amd64 to /usr/local/bin/udp2raw..."
# Move the udp2raw_amd64 binary from the current directory (/opt/tunnel) to /usr/local/bin
# First, check if the file exists in the current directory
if [ -f "udp2raw_amd64" ]; then
    sudo mv udp2raw_amd64 /usr/local/bin/udp2raw
    sudo chmod +x /usr/local/bin/udp2raw # Ensure the file is executable
    echo "udp2raw moved to /usr/local/bin/udp2raw successfully."
else
    echo "Error: udp2raw_amd64 not found in $(pwd) after extraction. Please check."
    # exit 1
fi

# Clean up the downloaded archive from the current directory (/opt/tunnel)
rm -f udp2raw_binaries.tar.gz
echo "Downloaded udp2raw_binaries.tar.gz archive removed from $(pwd)."

echo "Installing gost..."
# Inlined content of https://raw.githubusercontent.com/go-gost/gost/master/install.sh
# The --install argument is passed to this inlined script.
# This block is executed with sudo bash -s -- --install
# The -s option reads commands from the standard input (the heredoc).
# The first '--' signals the end of bash options, and '--install' is passed as an argument to the script.
sudo bash -s -- --install << 'GOST_INSTALL_EOF'
# This script is meant for quick & easy install via:
#   'curl -sSL https://github.com/go-gost/gost/raw/master/install.sh | sh -s --install'
# or
#   'bash <(curl -fsSL https://github.com/go-gost/gost/raw/master/install.sh) --install'
#
#
# The script needs 'curl' and 'unzip' to run.
# It can be run as root or normal user.
#
# Arguments:
#   --install: install or update gost to the latest release version
#   --remove: remove gost
#   --version <VERSION>: install a specific version of gost, e.g., --version v2.11.5
#   --proxy <URL>: use proxy to download, e.g., --proxy http://127.0.0.1:1080
#   --mirror <URL>: use mirror to download, e.g., --mirror https://github.com.cnpmjs.org
#   --dest <DIR>: set gost install destination, default: /usr/local/bin
#   --asset <ASSET>: set gost asset name, default: gost-linux-amd64 (for linux/amd64)
#
# Environment variables:
#   GOST_INSTALL_VERSION: a specific version of gost, e.g., v2.11.5
#   GOST_INSTALL_MIRROR: use mirror to download, e.g., https://github.com.cnpmjs.org
#   GOST_INSTALL_DEST: set gost install destination, default: /usr/local/bin
#   GOST_INSTALL_ASSET: set gost asset name, default: gost-linux-amd64 (for linux/amd64)
#
# Home: https://github.com/go-gost/gost
#
# Thanks to https://github.com/v2fly/fhs-install-v2ray for the script.

set -e

# detect machine arch
get_arch() {
  local ARCH
  case "$(uname -m)" in
    x86_64 | amd64)
      ARCH=amd64
      ;;
    armv5tel | armv6l | armv7 | armv7l)
      ARCH=armv5
      ;;
    armv8 | arm64 | aarch64)
      ARCH=armv8
      ;;
    i386 | i686)
      ARCH=386
      ;;
    *)
      echo "Unsupported arch: $(uname -m)"
      exit 1
      ;;
  esac
  echo "$ARCH"
}

# detect machine os
get_os() {
  local OS
  case "$(uname -s)" in
    Linux)
      OS=linux
      ;;
    Darwin)
      OS=darwin
      ;;
    *)
      echo "Unsupported os: $(uname -s)"
      exit 1
      ;;
  esac
  echo "$OS"
}

# parse command line arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --install)
      ACTION=install
      shift
      ;;
    --remove)
      ACTION=remove
      shift
      ;;
    --version)
      if [ -z "$2" ]; then
        echo "Please specify a version for --version"
        exit 1
      fi
      VERSION_ARG="$2"
      shift 2
      ;;
    --proxy)
      if [ -z "$2" ]; then
        echo "Please specify a URL for --proxy"
        exit 1
      fi
      PROXY_URL="$2"
      shift 2
      ;;
    --mirror)
      if [ -z "$2" ]; then
        echo "Please specify a URL for --mirror"
        exit 1
      fi
      MIRROR_URL="$2"
      shift 2
      ;;
    --dest)
      if [ -z "$2" ]; then
        echo "Please specify a directory for --dest"
        exit 1
      fi
      DEST_DIR="$2"
      shift 2
      ;;
    --asset)
      if [ -z "$2" ]; then
        echo "Please specify an asset name for --asset"
        exit 1
      fi
      ASSET_NAME_ARG="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# check action
if [ -z "$ACTION" ]; then
  echo "Please specify an action: --install or --remove"
  exit 1
fi

# set gost install destination
DEST_DIR="${DEST_DIR:-${GOST_INSTALL_DEST:-/usr/local/bin}}"
GOST_BIN="$DEST_DIR/gost"

# remove gost
if [ "$ACTION" = "remove" ]; then
  if [ ! -f "$GOST_BIN" ]; then
    echo "gost is not installed."
    exit 0
  fi

  if [ "$(id -u)" -ne 0 ]; then
    echo "Root privileges are required to remove gost."
    exit 1
  fi

  rm -f "$GOST_BIN"
  echo "gost removed successfully."
  exit 0
fi

# install or update gost
if [ "$ACTION" = "install" ]; then
  # check root privileges
  # Since this entire heredoc is run via 'sudo bash -s', id -u will be 0.
  # The original script's check `if [ "$(id -u)" -ne 0 ] && [ ! -w "$DEST_DIR" ]`
  # would evaluate to false if DEST_DIR is /usr/local/bin, which is fine.
  if [ "$(id -u)" -ne 0 ] && [ ! -w "$DEST_DIR" ]; then
    echo "Root privileges are required to install gost to $DEST_DIR"
    exit 1
  fi

  # check dependencies
  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is not installed. Please install curl first."
    exit 1
  fi
  if ! command -v unzip >/dev/null 2>&1; then
    echo "unzip is not installed. Please install unzip first."
    exit 1
  fi

  # set gost version
  VERSION="${VERSION_ARG:-${GOST_INSTALL_VERSION}}"
  if [ -z "$VERSION" ]; then
    VERSION="$(curl -fsSLk ${PROXY_URL:+"-x $PROXY_URL"} "https://api.github.com/repos/go-gost/gost/releases/latest" | grep 'tag_name' | cut -d\" -f4)"
    if [ -z "$VERSION" ]; then
      echo "Failed to get latest version of gost."
      exit 1
    fi
  fi
  echo "Installing gost version: $VERSION"

  # set gost asset name
  OS_NAME=$(get_os)
  ARCH_NAME=$(get_arch)
  ASSET_NAME="${ASSET_NAME_ARG:-${GOST_INSTALL_ASSET:-"gost-${OS_NAME}-${ARCH_NAME}"}}"

  # set download url
  DOWNLOAD_URL="${MIRROR_URL:-${GOST_INSTALL_MIRROR:-"https://github.com"}}/go-gost/gost/releases/download/$VERSION/${ASSET_NAME}.gz"
  if [ "$OS_NAME" = "darwin" ]; then
    DOWNLOAD_URL="${MIRROR_URL:-${GOST_INSTALL_MIRROR:-"https://github.com"}}/go-gost/gost/releases/download/$VERSION/${ASSET_NAME}.zip"
  fi
  echo "Downloading from: $DOWNLOAD_URL"

  # download and install
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT # Clean up TMP_DIR on exit of this subshell

  curl -L -H "Cache-Control: no-cache" -fsSLk ${PROXY_URL:+"-x $PROXY_URL"} "$DOWNLOAD_URL" -o "$TMP_DIR/gost.archive"
  if [ "$?" -ne 0 ]; then
    echo "Failed to download gost."
    exit 1
  fi

  if [ "$OS_NAME" = "darwin" ]; then
    unzip -q "$TMP_DIR/gost.archive" -d "$TMP_DIR"
  else
    gzip -df "$TMP_DIR/gost.archive" 
    # After gzip -df, if $TMP_DIR/gost.archive was foo.gz, it becomes foo.
    # The original script renames this uncompressed file (still at path $TMP_DIR/gost.archive if gzip modifies in-place) to $TMP_DIR/gost
    mv "$TMP_DIR/gost.archive" "$TMP_DIR/gost"
  fi

  if [ ! -f "$TMP_DIR/$ASSET_NAME" ] && [ ! -f "$TMP_DIR/gost" ]; then
    echo "Failed to extract gost."
    exit 1
  fi

  INSTALL_CMD="install"
  # Since this script block is run with 'sudo bash', $(id -u) will be 0.
  # So, INSTALL_CMD will remain 'install', which is correct.
  if [ "$(id -u)" -ne 0 ]; then
    INSTALL_CMD="sudo install" 
  fi

  if [ -f "$TMP_DIR/$ASSET_NAME" ]; then # This case is mainly for Darwin (zip)
    $INSTALL_CMD -m 755 "$TMP_DIR/$ASSET_NAME" "$GOST_BIN"
  else # This case is for Linux (gz), where the file is $TMP_DIR/gost
    $INSTALL_CMD -m 755 "$TMP_DIR/gost" "$GOST_BIN"
  fi

  echo "gost installed successfully to $GOST_BIN"
  exit 0 # Exit the subshell successfully
fi

echo "Invalid action: $ACTION" # Should not be reached if --install is passed
exit 1
GOST_INSTALL_EOF

# Check the exit status of the inlined gost installation script
if [ $? -ne 0 ]; then
  echo "Gost installation script failed."
  exit 1 # Exit the main script if gost installation failed
fi
# The success message is already printed by the inlined script.

echo "Creating directory for gost configuration..."
# Create directory for gost configuration files
sudo mkdir -p /usr/local/etc/gost
echo "Directory /usr/local/etc/gost created successfully."

echo "Installing wireguard-tools..."
# Install wireguard-tools
sudo apt install wireguard-tools -y
echo "wireguard-tools installed successfully."

echo "Downloading gost.service systemd file..."
# Download gost.service and place it in /usr/lib/systemd/system/
sudo curl -fsSL -o /usr/lib/systemd/system/gost.service https://raw.githubusercontent.com/GetPHP-IR/Ubuntu-Optimizer/refs/heads/main/gost.service
echo "gost.service file downloaded to /usr/lib/systemd/system/gost.service successfully."

echo "Downloading initial conf.yml for gost..."
# Download conf.yml and place it in /usr/local/etc/gost/
sudo curl -fsSL -o /usr/local/etc/gost/conf.yml https://raw.githubusercontent.com/GetPHP-IR/Ubuntu-Optimizer/refs/heads/main/conf.yml
echo "conf.yml file downloaded to /usr/local/etc/gost/conf.yml successfully."

echo "Configuring the initial service in conf.yml..."
# Get user input for the initial service (service-0) in conf.yml
read -p "Please enter the port for the initial gost service (service-0) (e.g., 8080): " user_port
read -p "Please enter the type for the initial gost service (service-0) (e.g., http or socks5): " user_type
read -p "Please enter the local IP address for the initial gost service (service-0) to bind to (e.g., 0.0.0.0 or 127.0.0.1): " user_localip

# Replace placeholders in conf.yml for the initial service
sudo sed -i "s/\\[port\\]/$user_port/g" /usr/local/etc/gost/conf.yml
sudo sed -i "s/\\[type\\]/$user_type/g" /usr/local/etc/gost/conf.yml
sudo sed -i "s/\\[localip\\]/$user_localip/g" /usr/local/etc/gost/conf.yml
echo "Initial service in conf.yml configured successfully."

# --- Loop to add more services ---
service_index=0 # Counter for naming new services (service-1, service-2, ...)

while true; do
    read -p "Do you want to add another service to gost? (y/n): " add_another_service
    add_another_service_lower=$(echo "$add_another_service" | tr '[:upper:]' '[:lower:]')

    if [[ "$add_another_service_lower" == "y" || "$add_another_service_lower" == "yes" ]]; then
        service_index=$((service_index + 1))
        new_service_name="service-${service_index}"
        new_target_name="target-${service_index}"

        echo "--- Configuring new service: $new_service_name ---"
        read -p "Please enter the port for the new service '$new_service_name': " new_port
        read -p "Please enter the type for the new service '$new_service_name' (e.g., http or socks5): " new_type
        read -p "Please enter the local IP address for the new service '$new_service_name' (e.g., 0.0.0.0 or 127.0.0.1): " new_localip

        # Create YAML block for the new service
        # Note: Indentation is crucial in YAML.
        new_service_block=$(printf -- "\n\
  - name: %s\n\
    addr: :%s\n\
    handler:\n\
      type: %s\n\
    listener:\n\
      type: %s\n\
    forwarder:\n\
      nodes:\n\
        - name: %s\n\
          addr: %s:%s" \
        "$new_service_name" \
        "$new_port" \
        "$new_type" \
        "$new_type" \
        "$new_target_name" \
        "$new_localip" \
        "$new_port")

        # Append the new service block to conf.yml
        echo -e "$new_service_block" | sudo tee -a /usr/local/etc/gost/conf.yml > /dev/null
        echo "Service '$new_service_name' added to conf.yml successfully."
    else
        echo "Configuration of additional services finished."
        break
    fi
done
# --- End loop for adding more services ---

echo "Downloading udp2raw.service systemd file..."
# Download udp2raw.service and place it in /usr/lib/systemd/system/
sudo curl -fsSL -o /usr/lib/systemd/system/udp2raw.service https://raw.githubusercontent.com/GetPHP-IR/Ubuntu-Optimizer/refs/heads/main/udp2raw.service
echo "udp2raw.service file downloaded to /usr/lib/systemd/system/udp2raw.service successfully."

echo "Configuring udp2raw.service..."
# Get user input for udp2raw.service
read -p "Please enter the destination server IP address for udp2raw (IPv4 or IPv6): " user_ip_udp2raw
read -p "Please enter the destination server port for udp2raw (e.g., 20000): " user_port_udp2raw
read -p "Please enter the passcode for udp2raw: " user_passcode_udp2raw

# Check IP type and format accordingly for replacement
ip_to_replace_udp2raw="$user_ip_udp2raw"
if [[ "$user_ip_udp2raw" == *":"* ]]; then
  # If IP contains ':', it's considered IPv6 and enclosed in brackets
  ip_to_replace_udp2raw="[$user_ip_udp2raw]"
fi

# Replace placeholders in udp2raw.service
# Using | as a delimiter in sed to avoid conflicts with slashes in user input
sudo sed -i "s|\\[ip\\]|$ip_to_replace_udp2raw|g" /usr/lib/systemd/system/udp2raw.service
sudo sed -i "s|\\[port\\]|$user_port_udp2raw|g" /usr/lib/systemd/system/udp2raw.service
sudo sed -i "s|\\[passcode\\]|$user_passcode_udp2raw|g" /usr/lib/systemd/system/udp2raw.service
echo "udp2raw.service configured successfully."

echo "Reloading systemd daemon..."
sudo systemctl daemon-reload
echo "systemd daemon reloaded successfully."

echo "All steps completed successfully!"
echo "You can start the services using: sudo systemctl start gost && sudo systemctl start udp2raw"
echo "To enable them on boot: sudo systemctl enable gost && sudo systemctl enable udp2raw"

# Optionally, return to the previous directory (if it was different from where the script started)
# cd - > /dev/null # This might not be necessary if the script starts in /opt/tunnel or similar fixed location.

exit 0
