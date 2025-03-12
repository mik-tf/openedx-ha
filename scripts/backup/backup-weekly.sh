#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="$PARENT_DIR/config/cluster-config.json"

WEEK=$(date +%Y-week%U)

echo "Starting weekly backup at $(date)"

# Get backup node info
BACKUP_NODE=$(jq -r '.nodes[] | select(.role=="backup") | .name + "," + .ipv6 + "," + .user + "," + .ssh_key_path' "$CONFIG_FILE")
IFS=',' read -r BACKUP_NAME BACKUP_IPV6 BACKUP_USER BACKUP_KEY <<< "$BACKUP_NODE"

# Find latest daily backup
ssh -i "$BACKUP_KEY" -o StrictHostKeyChecking=no "$BACKUP_USER@$BACKUP_IPV6" "
    LATEST_DAILY=\$(find /opt/k3s/storage/backup/daily -maxdepth 1 -type d -name \"20*\" | sort -r | head -1)

    if [ -z \"\$LATEST_DAILY\" ]; then
        echo \"No daily backup found, cannot create weekly backup\"
        exit 1
    fi

    echo \"Creating weekly backup from \$LATEST_DAILY\"

    # Create weekly backup directory
    mkdir -p \"/opt/k3s/storage/backup/weekly/$WEEK\"

    # Copy latest daily backup
    cp -a \"\$LATEST_DAILY\"/* \"/opt/k3s/storage/backup/weekly/$WEEK/\"

    # Update manifest
    sed -i 's/\"backup_type\": \"daily\"/\"backup_type\": \"weekly\"/' \"/opt/k3s/storage/backup/weekly/$WEEK/backup_manifest.json\"

    # Cleanup old weekly backups (keep 4 weeks)
    find /opt/k3s/storage/backup/weekly -maxdepth 1 -type d -mtime +28 -exec rm -rf {} \;

    echo \"Weekly backup completed\"
"

echo "Weekly backup completed at $(date)"
