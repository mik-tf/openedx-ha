#!/bin/bash
# scripts/cluster/setup-k3s-master-worker.sh
set -e

IPV6=$1
USER=$2
SSH_KEY=$3

echo "Setting up k3s master+worker node on [$IPV6]..."

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$USER@$IPV6" "
    # Update package list
    sudo apt-get update

    # Install necessary packages
    sudo apt-get install -y curl openssh-server nfs-common

    # Setup IPv6 for k3s
    sudo sysctl -w net.ipv6.conf.all.forwarding=1
    echo 'net.ipv6.conf.all.forwarding=1' | sudo tee -a /etc/sysctl.conf

    # Install k3s as master and worker combined
    export INSTALL_K3S_EXEC='server --cluster-init --tls-san $IPV6 --node-ip $IPV6 --bind-address $IPV6 --flannel-ipv6-masq'
    curl -sfL https://get.k3s.io | sh -

    # Wait for k3s to be ready
    sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml wait --for=condition=Ready node --all --timeout=120s || true

    # Label the node
    sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml label node \$(hostname) node-role.kubernetes.io/master= --overwrite || true
    sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml label node \$(hostname) node-role.kubernetes.io/worker= --overwrite || true

    # Create directories for PVs
    sudo mkdir -p /opt/k3s/storage/couchdb
    sudo mkdir -p /opt/k3s/storage/openedx
    sudo chmod 777 /opt/k3s/storage/couchdb
    sudo chmod 777 /opt/k3s/storage/openedx
"

echo "Master+worker node setup completed successfully!"
