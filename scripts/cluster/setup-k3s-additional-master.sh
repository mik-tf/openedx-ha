#!/bin/bash
# scripts/cluster/setup-k3s-additional-master.sh
set -e

IPV6=$1
USER=$2
SSH_KEY=$3
MASTER_IPV6=$4
TOKEN=$5

echo "Setting up additional k3s master+worker node on [$IPV6]..."

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$USER@$IPV6" "
    # Update package list
    sudo apt-get update

    # Install necessary packages
    sudo apt-get install -y curl openssh-server nfs-common

    # Setup IPv6 for k3s
    sudo sysctl -w net.ipv6.conf.all.forwarding=1
    echo 'net.ipv6.conf.all.forwarding=1' | sudo tee -a /etc/sysctl.conf

    # Install k3s as additional server node
    export K3S_TOKEN=$TOKEN
    export INSTALL_K3S_EXEC='server --server https://[$MASTER_IPV6]:6443 --tls-san $IPV6 --node-ip $IPV6 --bind-address $IPV6 --flannel-ipv6-masq'
    curl -sfL https://get.k3s.io | sh -

    # Wait for k3s to be ready
    sleep 10

    # Label the node
    sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml label node \$(hostname) node-role.kubernetes.io/master= --overwrite || true
    sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml label node \$(hostname) node-role.kubernetes.io/worker= --overwrite || true

    # Create directories for PVs
    sudo mkdir -p /opt/k3s/storage/couchdb
    sudo mkdir -p /opt/k3s/storage/openedx
    sudo chmod 777 /opt/k3s/storage/couchdb
    sudo chmod 777 /opt/k3s/storage/openedx
"

echo "Additional master+worker node setup completed successfully!"
