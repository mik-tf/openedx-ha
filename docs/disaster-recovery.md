# Disaster Recovery Guide

This guide outlines procedures for recovering your Open edX platform in case of catastrophic infrastructure failure.

## Complete Infrastructure Loss Recovery

Use this procedure when all nodes are lost, but you have local PC backups available.

### Prerequisites
- Latest local backup (fetched using `fetch-openedx-backup.sh`)
- Access to 4 new mini PCs
- SSH key pair
- Original domain name access

### Step 1: Setup New Nodes

1. Set up Mycelium IPv6 networking on your new hardware
2. Ensure SSH access is configured on all nodes
3. Create a new `cluster-config.json` with the new node information:
   ```json
   {
     "domain": "school.example.com",
     "nodes": [
       {
         "name": "node1-new",
         "ipv6": "2001:db8:1::10",
         "user": "admin",
         "role": "master",
         "ssh_key_path": "~/.ssh/id_rsa"
       },
       ...
     ],
     ...
   }
   ```

### Step 2: Deploy Kubernetes Infrastructure

```bash
./deploy.sh
```

This will set up a fresh Kubernetes cluster on your new hardware.

### Step 3: Prepare Backup for Restore

```bash
# Identify your latest local backup
LATEST_BACKUP=$(find ~/openedx-backups -maxdepth 1 -type d -name "20*" | sort -r | head -1)

# Copy to backup node
scp -r $LATEST_BACKUP admin@[NEW_BACKUP_NODE_IPV6]:/tmp/openedx-restore
```

### Step 4: Run Restore Job

1. Create a restore job:
   ```bash
   cat << EOF | kubectl -n openedx apply -f -
   apiVersion: batch/v1
   kind: Job
   metadata:
     name: restore-from-backup
     namespace: openedx
   spec:
     template:
       spec:
         containers:
         - name: restore
           image: curlimages/curl:7.87.0
           command:
           - /bin/sh
           - -c
           - |
             BACKUP_DIR="/tmp/openedx-restore"

             echo "Starting restore from $BACKUP_DIR"

             # Verify backup
             if [ ! -f "$BACKUP_DIR/backup_manifest.json" ]; then
               echo "ERROR: No backup manifest found."
               exit 1
             fi

             # Restore each database
             find "$BACKUP_DIR" -name "*.json" -not -name "backup_manifest.json" | while read -r db_file; do
               db_name=$(basename "$db_file" .json)
               echo "Restoring database: $db_name"

               # Create database if it doesn't exist
               curl -X PUT "http://\${COUCHDB_USER}:\${COUCHDB_PASSWORD}@couchdb-service:5984/$db_name"

               # Extract documents and insert them
               cat "$db_file" | jq -c '.rows[] | .doc' | while read -r doc; do
                 # Skip design documents for now
                 if [[ \$(echo "\$doc" | jq -r '._id') != _design* ]]; then
                   echo "\$doc" | curl -X POST "http://\${COUCHDB_USER}:\${COUCHDB_PASSWORD}@couchdb-service:5984/$db_name" -H "Content-Type: application/json" -d @-
                 fi
               done

               # Now handle design documents
               cat "$db_file" | jq -c '.rows[] | .doc' | while read -r doc; do
                 if [[ \$(echo "\$doc" | jq -r '._id') == _design* ]]; then
                   doc_id=\$(echo "\$doc" | jq -r '._id')
                   echo "Restoring design document: \$doc_id"
                   echo "\$doc" | curl -X PUT "http://\${COUCHDB_USER}:\${COUCHDB_PASSWORD}@couchdb-service:5984/$db_name/\$doc_id" -H "Content-Type: application/json" -d @-
                 fi
               done
             done

             echo "Restore completed"
           env:
           - name: COUCHDB_USER
             valueFrom:
               secretKeyRef:
                 name: couchdb-secrets
                 key: adminUsername
           - name: COUCHDB_PASSWORD
             valueFrom:
               secretKeyRef:
                 name: couchdb-secrets
                 key: adminPassword
           volumeMounts:
           - name: restore-volume
             mountPath: /tmp/openedx-restore
         volumes:
         - name: restore-volume
           hostPath:
             path: /tmp/openedx-restore
             type: Directory
         restartPolicy: Never
     backoffLimit: 2
   EOF
   ```

2. Wait for the job to complete:
   ```bash
   kubectl -n openedx wait --for=condition=complete job/restore-from-backup
   ```

### Step 5: Update DNS Records

Update your DNS AAAA records to point to the new node IPv6 addresses.

### Step 6: Verify Restoration

- Access LMS at https://school.example.com
- Access Studio at https://studio.school.example.com
- Login with admin credentials
- Check that courses, users, and content are restored

### Recovery Verification Checklist
- [ ] All nodes accessible via SSH
- [ ] Kubernetes cluster is healthy
- [ ] CouchDB cluster formed successfully
- [ ] LMS and Studio accessible via web browser
- [ ] Admin login works
- [ ] Course content is visible
- [ ] User data is restored
- [ ] File uploads are accessible

## Single Node Failure Recovery

If just one node has failed:

1. Remove the failed node from the cluster:
   ```bash
   ./scripts/cluster/remove-node.sh node2
   ```

2. Add a new node to replace it:
   ```bash
   ./scripts/cluster/add-node.sh node2-new 2001:db8:2::10 admin ~/.ssh/id_rsa
   ```

3. Update DNS records if necessary:
   ```bash
   # Update the AAAA record for school.example.com to point to the new IPv6 address
   ```

## CouchDB Cluster Failure Recovery

If the CouchDB cluster is corrupted:

1. Scale down the OpenedX services:
   ```bash
   kubectl -n openedx scale deployment lms-deployment --replicas=0
   kubectl -n openedx scale deployment cms-deployment --replicas=0
   ```

2. Delete and recreate the CouchDB StatefulSet:
   ```bash
   kubectl -n openedx delete statefulset couchdb
   kubectl -n openedx apply -f kubernetes/couchdb/couchdb-statefulset.yaml
   ```

3. Wait for the StatefulSet to be ready:
   ```bash
   kubectl -n openedx wait --for=condition=ready pod -l app=couchdb --timeout=300s
   ```

4. Set up the CouchDB cluster:
   ```bash
   ./scripts/setup-couchdb-cluster.sh
   ```

5. Restore from backup using the restore job

6. Scale up the OpenedX services:
   ```bash
   kubectl -n openedx scale deployment lms-deployment --replicas=3
   kubectl -n openedx scale deployment cms-deployment --replicas=3
   ```

## Emergency Contacts

If you need emergency assistance with recovery, contact the website admin.
