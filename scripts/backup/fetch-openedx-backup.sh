#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="$PARENT_DIR/config/cluster-config.json"

# Local backup path
LOCAL_BACKUP_PATH="$HOME/openedx-backups"
DATE=$(date +%Y%m%d)

# Get backup node info
BACKUP_NODE=$(jq -r '.nodes[] | select(.role=="backup") | .name + "," + .ipv6 + "," + .user + "," + .ssh_key_path' "$CONFIG_FILE")
IFS=',' read -r BACKUP_NAME BACKUP_IPV6 BACKUP_USER BACKUP_KEY <<< "$BACKUP_NODE"

# Create local directory structure
mkdir -p "$LOCAL_BACKUP_PATH/$DATE"
mkdir -p "$LOCAL_BACKUP_PATH/logs"

# Log file
LOG_FILE="$LOCAL_BACKUP_PATH/logs/backup-$DATE.log"

echo "Starting OpenEdX backup pull at $(date)" | tee -a "$LOG_FILE"

# Test connection
if ! ssh -i "$BACKUP_KEY" -o ConnectTimeout=10 "$BACKUP_USER@$BACKUP_IPV6" "echo Connection successful"; then
    echo "ERROR: Cannot connect to backup node" | tee -a "$LOG_FILE"
    exit 1
fi

# Get list of available backups
AVAILABLE_BACKUPS=$(ssh -i "$BACKUP_KEY" "$BACKUP_USER@$BACKUP_IPV6" "find /opt/k3s/storage/backup/daily -maxdepth 1 -type d -name '20*' | sort")
if [ -z "$AVAILABLE_BACKUPS" ]; then
    echo "ERROR: No backups found on server" | tee -a "$LOG_FILE"
    exit 1
fi

echo "Available backups:" | tee -a "$LOG_FILE"
echo "$AVAILABLE_BACKUPS" | tee -a "$LOG_FILE"

# Determine latest backup
LATEST_BACKUP=$(echo "$AVAILABLE_BACKUPS" | tail -1)
echo "Fetching latest backup: $LATEST_BACKUP" | tee -a "$LOG_FILE"

# Pull the backup using rsync
echo "Starting download..." | tee -a "$LOG_FILE"
rsync -avz --progress -e "ssh -i $BACKUP_KEY" \
    "$BACKUP_USER@$BACKUP_IPV6:$LATEST_BACKUP/" \
    "$LOCAL_BACKUP_PATH/$DATE/" \
    2>&1 | tee -a "$LOG_FILE"

# Verify backup integrity
"$SCRIPT_DIR/verify-backup.sh" "$LOCAL_BACKUP_PATH/$DATE" | tee -a "$LOG_FILE"

# Cleanup old local backups (keep last 10)
find "$LOCAL_BACKUP_PATH" -maxdepth 1 -type d -name "20*" | sort | head -n -10 | xargs -r rm -rf
echo "Cleaned up old backups, keeping most recent 10" | tee -a "$LOG_FILE"

echo "Backup completed at $(date)" | tee -a "$LOG_FILE"
echo "Backup stored in: $LOCAL_BACKUP_PATH/$DATE" | tee -a "$LOG_FILE"
