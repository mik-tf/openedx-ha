#!/bin/bash
set -e

if [ $# -ne 1 ]; then
  echo "Usage: $0 <backup_directory>"
  exit 1
fi

BACKUP_DIR="$1"

if [ ! -d "$BACKUP_DIR" ]; then
  echo "Backup directory not found: $BACKUP_DIR"
  exit 1
fi

echo "Verifying backup integrity in $BACKUP_DIR"

# Check manifest file
if [ ! -f "$BACKUP_DIR/backup_manifest.json" ]; then
  echo "ERROR: Manifest file not found"
  exit 1
fi

# Verify manifest structure
if ! jq -e . "$BACKUP_DIR/backup_manifest.json" > /dev/null; then
  echo "ERROR: Manifest file is not valid JSON"
  exit 1
fi

# Check backup date
BACKUP_DATE=$(jq -r '.backup_date' "$BACKUP_DIR/backup_manifest.json")
echo "Backup date: $BACKUP_DATE"

# Check backup type
BACKUP_TYPE=$(jq -r '.backup_type' "$BACKUP_DIR/backup_manifest.json")
echo "Backup type: $BACKUP_TYPE"

# Verify checksum if present
if jq -e '.checksum' "$BACKUP_DIR/backup_manifest.json" > /dev/null; then
  MANIFEST_CHECKSUM=$(jq -r '.checksum' "$BACKUP_DIR/backup_manifest.json")

  # Calculate actual checksum
  CALCULATED_CHECKSUM=$(find "$BACKUP_DIR" -type f -not -name "backup_manifest.json" -exec md5sum {} \; | sort | md5sum | cut -d' ' -f1)

  echo "Manifest checksum: $MANIFEST_CHECKSUM"
  echo "Calculated checksum: $CALCULATED_CHECKSUM"

  if [ "$MANIFEST_CHECKSUM" != "$CALCULATED_CHECKSUM" ]; then
    echo "ERROR: Checksum verification failed!"
    exit 1
  else
    echo "Checksum verification passed."
  fi
fi

# Check for essential files
DB_COUNT=$(find "$BACKUP_DIR" -name "*.json" -not -name "backup_manifest.json" | wc -l)
echo "Database files found: $DB_COUNT"

if [ "$DB_COUNT" -eq 0 ]; then
  echo "WARNING: No database files found in backup!"
  exit 1
fi

# Check if configmaps and secrets are present
if [ ! -f "$BACKUP_DIR/configmaps.yaml" ] || [ ! -f "$BACKUP_DIR/secrets.yaml" ]; then
  echo "WARNING: Configuration backup may be incomplete!"
fi

echo "Backup verification passed. The backup appears to be valid."
