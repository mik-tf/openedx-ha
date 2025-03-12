#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
CONFIG_FILE="$PARENT_DIR/config/cluster-config.json"

# Get CouchDB credentials
COUCHDB_USER=$(jq -r '.couchdb.user' "$CONFIG_FILE")
COUCHDB_PASSWORD=$(jq -r '.couchdb.password' "$CONFIG_FILE")

DATE=$(date +%Y%m%d)
BACKUP_DIR="/opt/k3s/storage/backup/daily/$DATE"

echo "Starting daily backup at $(date)"

# Create backup directory on the backup node
BACKUP_NODE=$(jq -r '.nodes[] | select(.role=="backup") | .name + "," + .ipv6 + "," + .user + "," + .ssh_key_path' "$CONFIG_FILE")
IFS=',' read -r BACKUP_NAME BACKUP_IPV6 BACKUP_USER BACKUP_KEY <<< "$BACKUP_NODE"

ssh -i "$BACKUP_KEY" -o StrictHostKeyChecking=no "$BACKUP_USER@$BACKUP_IPV6" "
    mkdir -p $BACKUP_DIR
    if [ ! -d \"$BACKUP_DIR\" ]; then
        echo \"ERROR: Failed to create backup directory: $BACKUP_DIR\"
        exit 1
    fi
    if [ ! -w \"$BACKUP_DIR\" ]; then
        echo \"ERROR: Backup directory is not writable: $BACKUP_DIR\"
        exit 1
    fi
    # Check for available disk space (require at least 5GB free)
    FREE_SPACE=\$(df -k \"$BACKUP_DIR\" | awk 'NR==2 {print \$4}')
    if [ \"\$FREE_SPACE\" -lt 5242880 ]; then
        echo \"ERROR: Insufficient disk space. Only \$((FREE_SPACE/1024))MB available on backup volume.\"
        exit 1
    fi
"

# Get CouchDB pod
COUCHDB_POD=$(kubectl -n openedx get pods -l app=couchdb -o jsonpath='{.items[0].metadata.name}')

# Back up each database
echo "Backing up CouchDB databases..."
DBS=$(kubectl -n openedx exec $COUCHDB_POD -- curl -s -X GET "http://${COUCHDB_USER}:${COUCHDB_PASSWORD}@127.0.0.1:5984/_all_dbs")
echo $DBS | jq -r '.[]' | while read -r db; do
    echo "Backing up database: $db"
    # Dump database to temp file
    kubectl -n openedx exec $COUCHDB_POD -- curl -s "http://${COUCHDB_USER}:${COUCHDB_PASSWORD}@127.0.0.1:5984/$db/_all_docs?include_docs=true" > /tmp/$db.json
    # Copy to backup node
    scp -i "$BACKUP_KEY" -o StrictHostKeyChecking=no /tmp/$db.json "$BACKUP_USER@$BACKUP_IPV6:$BACKUP_DIR/"
    rm /tmp/$db.json
done

# Backup configuration
echo "Backing up configuration files..."
kubectl -n openedx get configmap -o yaml > /tmp/configmaps.yaml
kubectl -n openedx get secret -o yaml > /tmp/secrets.yaml
scp -i "$BACKUP_KEY" -o StrictHostKeyChecking=no /tmp/configmaps.yaml /tmp/secrets.yaml "$BACKUP_USER@$BACKUP_IPV6:$BACKUP_DIR/"
rm /tmp/configmaps.yaml /tmp/secrets.yaml

# Create backup manifest
ssh -i "$BACKUP_KEY" -o StrictHostKeyChecking=no "$BACKUP_USER@$BACKUP_IPV6" "
cat > $BACKUP_DIR/backup_manifest.json << EOF
{
  \"backup_date\": \"$(date -Iseconds)\",
  \"backup_type\": \"daily\",
  \"checksum\": \"$(find $BACKUP_DIR -type f -not -name backup_manifest.json -exec md5sum {} \; | sort | md5sum | cut -d' ' -f1)\"
}
EOF

# Cleanup old backups (keep 7 days)
find /opt/k3s/storage/backup/daily -maxdepth 1 -type d -name \"20*\" -mtime +7 -exec rm -rf {} \;
"

echo "Daily backup completed at $(date)"
echo "Backup stored in: $BACKUP_DIR"
