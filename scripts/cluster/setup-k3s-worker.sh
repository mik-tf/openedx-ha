#!/bin/bash
set -e

IPV6=$1
USER=$2
SSH_KEY=$3
MASTER_IPV6=$4
TOKEN=$5

if [ -z "$IPV6" ] || [ -z "$USER" ] || [ -z "$SSH_KEY" ] || [ -z "$MASTER_IPV6" ] || [ -z "$TOKEN" ]; then
    echo "Usage: $0 <ipv6> <user> <ssh_key_path> <master_ipv6> <token>"
    exit 1
fi

echo "Setting up k3s worker node on [$IPV6]..."

# Install k3s on the worker node
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$USER@$IPV6" "
    # Update package list
    sudo apt-get update

    # Install necessary packages
    sudo apt-get install -y curl openssh-server nfs-common

    # Setup IPv6 for k3s
    sudo sysctl -w net.ipv6.conf.all.forwarding=1
    echo 'net.ipv6.conf.all.forwarding=1' | sudo tee -a /etc/sysctl.conf

    # Install k3s
    export K3S_URL=https://[$MASTER_IPV6]:6443
    export K3S_TOKEN=$TOKEN
    export INSTALL_K3S_EXEC='--node-ip $IPV6'
    curl -sfL https://get.k3s.io | sh -

    # Create directory for PVs
    sudo mkdir -p /opt/k3s/storage
    sudo chmod 777 /opt/k3s/storage
"

echo "Worker node setup completed successfully!"
