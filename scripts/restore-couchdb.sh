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

# Get CouchDB credentials
COUCHDB_USER=$(jq -r '.couchdb.user' "$CONFIG_FILE")
COUCHDB_PASSWORD=$(jq -r '.couchdb.password' "$CONFIG_FILE")

# Get CouchDB pod
COUCHDB_POD=$(kubectl -n openedx get pods -l app=couchdb -o jsonpath='{.items[0].metadata.name}')

echo "Restoring CouchDB data from $BACKUP_DIR"

# Copy backup files to pod
echo "Copying backup files to pod..."
kubectl -n openedx exec $COUCHDB_POD -- mkdir -p /tmp/restore
kubectl cp "$BACKUP_DIR" openedx/$COUCHDB_POD:/tmp/restore

# Find all JSON files (database dumps)
JSON_FILES=$(find "$BACKUP_DIR" -name "*.json")
for db_file in $JSON_FILES; do
  db_name=$(basename "$db_file" .json)
  echo "Restoring database: $db_name"

  # Create database if it doesn't exist
  kubectl -n openedx exec $COUCHDB_POD -- \
    curl -X PUT "http://${COUCHDB_USER}:${COUCHDB_PASSWORD}@127.0.0.1:5984/$db_name"

  # Restore data
  kubectl -n openedx exec $COUCHDB_POD -- bash -c "
    cat /tmp/restore/$(basename "$BACKUP_DIR")/$(basename "$db_file") | \
    jq -c '.rows[] | .doc' | \
    while read -r doc; do
      # Skip design documents for now
      if [[ \$(echo \"\$doc\" | jq -r '._id') != _design* ]]; then
        echo \"\$doc\" | curl -X POST \"http://${COUCHDB_USER}:${COUCHDB_PASSWORD}@127.0.0.1:5984/$db_name\" -H \"Content-Type: application/json\" -d @-
      fi
    done

    # Now handle design documents
    cat /tmp/restore/$(basename "$BACKUP_DIR")/$(basename "$db_file") | \
    jq -c '.rows[] | .doc' | \
    while read -r doc; do
      if [[ \$(echo \"\$doc\" | jq -r '._id') == _design* ]]; then
        doc_id=\$(echo \"\$doc\" | jq -r '._id')
        echo \"Restoring design document: \$doc_id\"
        echo \"\$doc\" | curl -X PUT \"http://${COUCHDB_USER}:${COUCHDB_PASSWORD}@127.0.0.1:5984/$db_name/\$doc_id\" -H \"Content-Type: application/json\" -d @-
      fi
    done
  "
done

# Clean up
kubectl -n openedx exec $COUCHDB_POD -- rm -rf /tmp/restore

echo "CouchDB restore completed"
