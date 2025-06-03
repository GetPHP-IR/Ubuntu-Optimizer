#!/bin/bash

# Script to update Ubuntu, install optimizer, udp2raw, gost, wireguard-tools, and configure services

# Exit immediately if a command exits with a non-zero status.
set -e

echo "Starting server update process..."
# Update and upgrade system packages
sudo apt update && sudo apt upgrade -y
echo "Server update completed successfully."

echo "Changing directory to /opt..."
# Change directory to /opt
cd /opt
echo "Current directory: $(pwd)"

echo "Downloading and executing Ubuntu optimizer script..."
# Download and execute the optimizer script
curl -fsSL https://raw.githubusercontent.com/GetPHP-IR/Ubuntu-Optimizer/refs/heads/main/old.sh | sudo bash
echo "Optimizer script executed successfully."

echo "Downloading and extracting udp2raw..."
# Download udp2raw
wget https://github.com/wangyu-/udp2raw/releases/download/20230206.0/udp2raw_binaries.tar.gz -O udp2raw_binaries.tar.gz

# Extract the downloaded file
tar -xzf udp2raw_binaries.tar.gz
echo "udp2raw extracted successfully."

echo "Moving udp2raw_amd64 to /usr/local/bin/udp2raw..."
# Move the udp2raw_amd64 binary to /usr/local/bin and rename it to udp2raw
# First, check if the file exists
if [ -f "udp2raw_amd64" ]; then
    sudo mv udp2raw_amd64 /usr/local/bin/udp2raw
    sudo chmod +x /usr/local/bin/udp2raw # Ensure the file is executable
    echo "udp2raw moved to /usr/local/bin/udp2raw successfully."
else
    echo "Error: udp2raw_amd64 not found after extraction. Please check."
    # exit 1
fi

# Clean up the downloaded archive
rm -f udp2raw_binaries.tar.gz
echo "Downloaded udp2raw_binaries.tar.gz archive removed."

echo "Installing gost..."
# Download and execute the gost installation script
sudo bash <(curl -fsSL https://github.com/go-gost/gost/raw/master/install.sh) --install
echo "gost installed successfully."

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

# Optionally, return to the previous directory
cd - > /dev/null

exit 0
