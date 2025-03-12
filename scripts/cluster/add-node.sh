#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="$PARENT_DIR/config/cluster-config.json"

if [ "$#" -lt 4 ]; then
    echo "Usage: $0 <name> <ipv6> <user> <ssh_key_path> [role]"
    echo "Role can be: master, worker, master+worker, or backup (default: worker)"
    exit 1
fi

NODE_NAME=$1
NODE_IPV6=$2
NODE_USER=$3
NODE_KEY=$4
NODE_ROLE=${5:-worker}  # Default to worker if not specified

if [[ ! "$NODE_ROLE" =~ ^(master|worker|master\+worker|backup)$ ]]; then
    echo "Invalid role: $NODE_ROLE"
    echo "Role must be one of: master, worker, master+worker, backup"
    exit 1
fi

echo "Adding new node $NODE_NAME with IPv6 [$NODE_IPV6] to the cluster as $NODE_ROLE..."

# Get master node info
MASTER_NODE=$(jq -r '.nodes[] | select(.is_first_master==true) | .name + "," + .ipv6 + "," + .user + "," + .ssh_key_path' "$CONFIG_FILE")
IFS=',' read -r MASTER_NAME MASTER_IPV6 MASTER_USER MASTER_KEY <<< "$MASTER_NODE"

# Get k3s token from master
TOKEN=$(ssh -i "$MASTER_KEY" -o StrictHostKeyChecking=no "$MASTER_USER@$MASTER_IPV6" "sudo cat /var/lib/rancher/k3s/server/node-token")

# Setup the new node based on role
case "$NODE_ROLE" in
    master)
        echo "Setting up node as a master..."
        "$SCRIPT_DIR/setup-k3s-additional-master.sh" "$NODE_IPV6" "$NODE_USER" "$NODE_KEY" "$MASTER_IPV6" "$TOKEN"
        ;;
    worker)
        echo "Setting up node as a worker..."
        "$SCRIPT_DIR/setup-k3s-worker.sh" "$NODE_IPV6" "$NODE_USER" "$NODE_KEY" "$MASTER_IPV6" "$TOKEN"
        ;;
    master+worker)
        echo "Setting up node as a master+worker..."
        "$SCRIPT_DIR/setup-k3s-additional-master.sh" "$NODE_IPV6" "$NODE_USER" "$NODE_KEY" "$MASTER_IPV6" "$TOKEN"
        ;;
    backup)
        echo "Setting up node as a backup worker..."
        "$SCRIPT_DIR/setup-k3s-worker.sh" "$NODE_IPV6" "$NODE_USER" "$NODE_KEY" "$MASTER_IPV6" "$TOKEN"

        # Create backup directory on the node
        ssh -i "$NODE_KEY" -o StrictHostKeyChecking=no "$NODE_USER@$NODE_IPV6" "
            sudo mkdir -p /opt/k3s/storage/backup
            sudo chmod 777 /opt/k3s/storage/backup
        "
        ;;
esac

# Set is_first_master flag based on role
IS_FIRST_MASTER="false"
if [ "$NODE_ROLE" == "master" ] || [ "$NODE_ROLE" == "master+worker" ]; then
    # Since this is an additional master, it's never the first master
    IS_FIRST_MASTER="false"
fi

# Set is_backup flag based on role
IS_BACKUP="false"
if [ "$NODE_ROLE" == "backup" ]; then
    IS_BACKUP="true"
fi

# Add node to config.json
jq --arg name "$NODE_NAME" \
   --arg ipv6 "$NODE_IPV6" \
   --arg user "$NODE_USER" \
   --arg key "$NODE_KEY" \
   --arg role "$NODE_ROLE" \
   --arg is_first_master "$IS_FIRST_MASTER" \
   --arg is_backup "$IS_BACKUP" \
   '.nodes += [{
     "name": $name,
     "ipv6": $ipv6,
     "user": $user,
     "ssh_key_path": $key,
     "role": $role,
     "is_first_master": ($is_first_master == "true"),
     "is_backup": ($is_backup == "true")
   }]' "$CONFIG_FILE" > "$CONFIG_FILE.tmp"
mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

echo "Node added successfully! Updating DNS records..."

# Update DNS records
DOMAIN=$(jq -r '.domain' "$CONFIG_FILE")
"$PARENT_DIR/scripts/generate-configs.sh" "$CONFIG_FILE"

echo "Node $NODE_NAME added to the cluster successfully!"
echo "Please update your DNS records according to the updated config/dns-records.txt file"
