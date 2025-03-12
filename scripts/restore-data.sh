#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PARENT_DIR/config/cluster-config.json"

if [ $# -ne 1 ]; then
  echo "Usage: $0 <backup_directory>"
  exit 1
fi

BACKUP_DIR="$1"

if [ ! -d "$BACKUP_DIR" ]; then
  echo "Backup directory not found: $BACKUP_DIR"
  exit 1
fi

echo "Starting data restore from $BACKUP_DIR"

# Restore CouchDB
"$SCRIPT_DIR/restore-couchdb.sh" "$BACKUP_DIR"

# Restart pods to apply changes
echo "Restarting pods to apply changes..."
kubectl -n openedx rollout restart deployment lms-deployment
kubectl -n openedx rollout restart deployment cms-deployment

# Wait for pods to restart
echo "Waiting for pods to restart..."
kubectl -n openedx rollout status deployment lms-deployment
kubectl -n openedx rollout status deployment cms-deployment

echo "Data restore completed successfully"
