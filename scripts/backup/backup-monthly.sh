#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="$PARENT_DIR/config/cluster-config.json"

MONTH=$(date +%Y-%m)

echo "Starting monthly backup at $(date)"

# Get backup node info
BACKUP_NODE=$(jq -r '.nodes[] | select(.role=="backup") | .name + "," + .ipv6 + "," + .user + "," + .ssh_key_path' "$CONFIG_FILE")
IFS=',' read -r BACKUP_NAME BACKUP_IPV6 BACKUP_USER BACKUP_KEY <<< "$BACKUP_NODE"

# Find latest weekly backup
ssh -i "$BACKUP_KEY" -o StrictHostKeyChecking=no "$BACKUP_USER@$BACKUP_IPV6" "
    LATEST_WEEKLY=\$(find /opt/k3s/storage/backup/weekly -maxdepth 1 -type d -name \"20*\" | sort -r | head -1)

    if [ -z \"\$LATEST_WEEKLY\" ]; then
        echo \"No weekly backup found, cannot create monthly backup\"
        exit 1
    fi

    echo \"Creating monthly backup from \$LATEST_WEEKLY\"

    # Create monthly backup directory
    mkdir -p \"/opt/k3s/storage/backup/monthly/$MONTH\"

    # Copy latest weekly backup
    cp -a \"\$LATEST_WEEKLY\"/* \"/opt/k3s/storage/backup/monthly/$MONTH/\"

    # Update manifest
    sed -i 's/\"backup_type\": \"weekly\"/\"backup_type\": \"monthly\"/' \"/opt/k3s/storage/backup/monthly/$MONTH/backup_manifest.json\"

    # Cleanup old monthly backups (keep 12 months)
    find /opt/k3s/storage/backup/monthly -maxdepth 1 -type d -mtime +365 -exec rm -rf {} \;

    echo \"Monthly backup completed\"
"

echo "Monthly backup completed at $(date)"
