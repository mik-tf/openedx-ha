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
NODE_INFO=$(jq -r --arg name "$NODE_NAME" '.nodes[] | select(.name==$name) | .name + "," + .ipv6 + "," + .user + "," + .ssh_key_path + "," + .role + "," + (.is_first_master|tostring)' "$CONFIG_FILE")
if [ -z "$NODE_INFO" ]; then
    echo "Error: Node $NODE_NAME not found in configuration"
    exit 1
fi

IFS=',' read -r _ NODE_IPV6 NODE_USER NODE_KEY NODE_ROLE IS_FIRST_MASTER <<< "$NODE_INFO"

echo "Removing node $NODE_NAME ([$NODE_IPV6]) with role $NODE_ROLE from the cluster..."

# Check if this is the first master - we cannot remove it without reconfiguring the cluster
if [ "$IS_FIRST_MASTER" == "true" ]; then
    echo "ERROR: Cannot remove the first master node ($NODE_NAME) without reconfiguring the entire cluster."
    echo "Please promote another master node to be the first master before removing this node."
    exit 1
fi

# Get master node info
MASTER_NODE=$(jq -r '.nodes[] | select(.is_first_master==true) | .name + "," + .ipv6 + "," + .user + "," + .ssh_key_path' "$CONFIG_FILE")
IFS=',' read -r MASTER_NAME MASTER_IPV6 MASTER_USER MASTER_KEY <<< "$MASTER_NODE"

# Get node name in kubernetes
NODE_K8S_NAME=$(ssh -i "$MASTER_KEY" -o StrictHostKeyChecking=no "$MASTER_USER@$MASTER_IPV6" "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get nodes -o wide | grep $NODE_IPV6 | awk '{print \$1}'")

if [ ! -z "$NODE_K8S_NAME" ]; then
    # Special handling for master nodes
    if [[ "$NODE_ROLE" == "master" || "$NODE_ROLE" == "master+worker" ]]; then
        echo "Removing a master node ($NODE_K8S_NAME)..."

        # Count remaining masters to ensure we don't remove too many
        MASTER_COUNT=$(jq -r '.nodes[] | select(.role=="master" or .role=="master+worker") | .name' "$CONFIG_FILE" | wc -l)
        if [ "$MASTER_COUNT" -le 2 ]; then
            echo "WARNING: Removing this master will leave you with less than 2 masters."
            echo "This will compromise the high-availability of your control plane."
            read -p "Do you want to continue? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Node removal cancelled."
                exit 0
            fi
        fi

        # Drain the node with a longer timeout for master components
        ssh -i "$MASTER_KEY" -o StrictHostKeyChecking=no "$MASTER_USER@$MASTER_IPV6" "
            sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml drain $NODE_K8S_NAME --ignore-daemonsets --delete-emptydir-data --force --timeout=120s
            sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml delete node $NODE_K8S_NAME
        "
    else
        # Standard drain and delete for worker nodes
        ssh -i "$MASTER_KEY" -o StrictHostKeyChecking=no "$MASTER_USER@$MASTER_IPV6" "
            sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml drain $NODE_K8S_NAME --ignore-daemonsets --delete-emptydir-data --force
            sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml delete node $NODE_K8S_NAME
        "
    fi
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

# Special message for backup node removal
if [[ "$NODE_ROLE" == "backup" ]]; then
    echo ""
    echo "WARNING: You have removed the backup node. Make sure to configure another node"
    echo "for backups or add a new backup node to maintain your backup strategy."
fi
