#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="$PARENT_DIR/config/cluster-config.json"

if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <name> <ipv6> <user> <ssh_key_path>"
    exit 1
fi

NODE_NAME=$1
NODE_IPV6=$2
NODE_USER=$3
NODE_KEY=$4

echo "Adding new node $NODE_NAME with IPv6 [$NODE_IPV6] to the cluster..."

# Get master node info
MASTER_NODE=$(jq -r '.nodes[] | select(.role=="master") | .name + "," + .ipv6 + "," + .user + "," + .ssh_key_path' "$CONFIG_FILE")
IFS=',' read -r MASTER_NAME MASTER_IPV6 MASTER_USER MASTER_KEY <<< "$MASTER_NODE"

# Get k3s token from master
TOKEN=$(ssh -i "$MASTER_KEY" -o StrictHostKeyChecking=no "$MASTER_USER@$MASTER_IPV6" "sudo cat /var/lib/rancher/k3s/server/node-token")

# Setup new worker node
"$SCRIPT_DIR/setup-k3s-worker.sh" "$NODE_IPV6" "$NODE_USER" "$NODE_KEY" "$MASTER_IPV6" "$TOKEN"

# Add node to config.json
jq --arg name "$NODE_NAME" --arg ipv6 "$NODE_IPV6" --arg user "$NODE_USER" --arg key "$NODE_KEY" '.nodes += [{"name": $name, "ipv6": $ipv6, "user": $user, "role": "worker", "ssh_key_path": $key}]' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

echo "Node added successfully! Updating DNS records..."

# Update DNS records
DOMAIN=$(jq -r '.domain' "$CONFIG_FILE")
"$PARENT_DIR/scripts/generate-configs.sh" "$CONFIG_FILE"

echo "Node $NODE_NAME added to the cluster successfully!"
echo "Please update your DNS records according to the updated config/dns-records.txt file"
