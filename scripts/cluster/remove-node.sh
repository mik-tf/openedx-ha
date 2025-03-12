#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="$PARENT_DIR/config/cluster-config.json"

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <node_name>"
    exit 1
fi

NODE_NAME=$1

# Check if node exists in config
NODE_INFO=$(jq -r --arg name "$NODE_NAME" '.nodes[] | select(.name==$name) | .name + "," + .ipv6 + "," + .user + "," + .ssh_key_path + "," + .role' "$CONFIG_FILE")
if [ -z "$NODE_INFO" ]; then
    echo "Error: Node $NODE_NAME not found in configuration"
    exit 1
fi

IFS=',' read -r _ NODE_IPV6 NODE_USER NODE_KEY NODE_ROLE <<< "$NODE_INFO"

echo "Removing node $NODE_NAME ([$NODE_IPV6]) from the cluster..."

# Get master node info
MASTER_NODE=$(jq -r '.nodes[] | select(.role=="master") | .name + "," + .ipv6 + "," + .user + "," + .ssh_key_path' "$CONFIG_FILE")
IFS=',' read -r MASTER_NAME MASTER_IPV6 MASTER_USER MASTER_KEY <<< "$MASTER_NODE"

# Get node name in kubernetes
NODE_K8S_NAME=$(ssh -i "$MASTER_KEY" -o StrictHostKeyChecking=no "$MASTER_USER@$MASTER_IPV6" "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get nodes -o wide | grep $NODE_IPV6 | awk '{print \$1}'")

if [ ! -z "$NODE_K8S_NAME" ]; then
    # Drain and delete node from kubernetes
    ssh -i "$MASTER_KEY" -o StrictHostKeyChecking=no "$MASTER_USER@$MASTER_IPV6" "
        sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml drain $NODE_K8S_NAME --ignore-daemonsets --delete-emptydir-data --force
        sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml delete node $NODE_K8S_NAME
    "
fi

# Uninstall k3s from the node
ssh -i "$NODE_KEY" -o StrictHostKeyChecking=no "$NODE_USER@$NODE_IPV6" "
    sudo /usr/local/bin/k3s-uninstall.sh || true
"

# Remove node from config.json
jq --arg name "$NODE_NAME" '.nodes = [.nodes[] | select(.name != $name)]' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

echo "Node removed successfully! Updating DNS records..."

# Update DNS records
DOMAIN=$(jq -r '.domain' "$CONFIG_FILE")
"$PARENT_DIR/scripts/generate-configs.sh" "$CONFIG_FILE"

echo "Node $NODE_NAME removed from the cluster successfully!"
echo "Please update your DNS records according to the updated config/dns-records.txt file"

# If this was a master node, we need to inform about reconfiguring the cluster
if [ "$NODE_ROLE" == "master" ]; then
    echo ""
    echo "WARNING: You have removed a master node. You will need to reconfigure the cluster."
    echo "It is recommended to set up a new master node using add-node.sh with role=master"
    echo "and then redeploy the application."
fi
