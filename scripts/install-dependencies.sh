#!/bin/bash
set -e

echo "Installing required dependencies..."

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
elif type lsb_release >/dev/null 2>&1; then
    OS=$(lsb_release -si)
elif [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    OS=$DISTRIB_ID
else
    OS=$(uname -s)
fi

# Convert to lowercase
OS=${OS,,}

# Install dependencies based on OS
case "$OS" in
    ubuntu|debian)
        sudo apt-get update
        sudo apt-get install -y jq curl ssh rsync
        ;;
    fedora|centos|rhel)
        sudo dnf install -y jq curl openssh rsync
        ;;
    arch|manjaro)
        sudo pacman -Sy jq curl openssh rsync --noconfirm
        ;;
    *)
        echo "Unsupported operating system: $OS"
        echo "Please manually install jq, curl, ssh, and rsync"
        ;;
esac

# Install kubectl if not already installed
if ! command -v kubectl &> /dev/null; then
    echo "Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
fi

echo "All dependencies installed successfully!"
