#!/bin/bash
set -e

IPV6=$1
USER=$2
SSH_KEY=$3

if [ -z "$IPV6" ] || [ -z "$USER" ] || [ -z "$SSH_KEY" ]; then
    echo "Usage: $0 <ipv6> <user> <ssh_key_path>"
    exit 1
fi

echo "Setting up k3s master node on [$IPV6]..."

# Install k3s on the master node
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$USER@$IPV6" "
    # Update package list
    sudo apt-get update

    # Install necessary packages
    sudo apt-get install -y curl openssh-server nfs-common

    # Setup IPv6 for k3s
    sudo sysctl -w net.ipv6.conf.all.forwarding=1
    echo 'net.ipv6.conf.all.forwarding=1' | sudo tee -a /etc/sysctl.conf

    # Install k3s as a pure master node
    export INSTALL_K3S_EXEC='server --cluster-init --tls-san $IPV6 --node-ip $IPV6 --bind-address $IPV6 --flannel-ipv6-masq --disable-agent'
    curl -sfL https://get.k3s.io | sh -

    # Wait for k3s to be ready
    sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml wait --for=condition=Ready node --all --timeout=120s || true

    # Label the master node
    sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml label node \$(hostname) node-role.kubernetes.io/master= --overwrite || true

    # Make master node unschedulable for workloads (pure control plane)
    sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml taint nodes \$(hostname) node-role.kubernetes.io/master=true:NoSchedule --overwrite || true

    # Create directory for PVs
    sudo mkdir -p /opt/k3s/storage
    sudo chmod 777 /opt/k3s/storage
"

echo "Master node setup completed successfully!"
