# Disaster Recovery Guide

This guide outlines procedures for recovering your Open edX platform in case of catastrophic infrastructure failure. The system is designed with zero single points of failure (SPOF), but proper disaster recovery procedures are still essential.

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
         "role": "master+worker",
         "is_first_master": true,
         "ssh_key_path": "~/.ssh/id_rsa"
       },
       {
         "name": "node2-new",
         "ipv6": "2001:db8:2::10",
         "user": "admin",
         "role": "master+worker",
         "is_first_master": false,
         "ssh_key_path": "~/.ssh/id_rsa"
       },
       {
         "name": "node3-new",
         "ipv6": "2001:db8:3::10",
         "user": "admin",
         "role": "master+worker",
         "is_first_master": false,
         "ssh_key_path": "~/.ssh/id_rsa"
       },
       {
         "name": "node4-new",
         "ipv6": "2001:db8:4::10",
         "user": "admin",
         "role": "backup",
         "is_backup": true,
         "ssh_key_path": "~/.ssh/id_rsa"
       }
     ],
     "couchdb": {
       "user": "admin",
       "password": "StrongPasswordHere"
     },
     "platform_name": "Open edX HA",
     "platform_email": "admin@example.com"
   }
   ```

### Step 2: Deploy Kubernetes Infrastructure

```bash
./deploy.sh
```

This will set up a fresh Kubernetes cluster on your new hardware with:
- Three combined master+worker nodes for distributed control plane and workloads
- One backup node for dedicated backup operations

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

Update your DNS AAAA records to point to the new node IPv6 addresses:

```
school.example.com. IN AAAA 2001:db8:1::10
school.example.com. IN AAAA 2001:db8:2::10
school.example.com. IN AAAA 2001:db8:3::10

studio.school.example.com. IN AAAA 2001:db8:1::10
studio.school.example.com. IN AAAA 2001:db8:2::10
studio.school.example.com. IN AAAA 2001:db8:3::10

monitoring.school.example.com. IN AAAA 2001:db8:1::10
```

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
   # For a production node (master+worker)
   ./scripts/cluster/add-node.sh node2-new 2001:db8:2::10 admin ~/.ssh/id_rsa master+worker

   # For a backup node
   ./scripts/cluster/add-node.sh node4-new 2001:db8:4::10 admin ~/.ssh/id_rsa backup
   ```

3. Update DNS records if necessary:
   ```bash
   # Update the AAAA record for school.example.com to point to the new IPv6 address
   ```

### Zero-Downtime Node Replacement

The master+worker architecture means that even when replacing a node:

1. Kubernetes control plane remains available through the other master nodes
2. Workloads continue running on the remaining production nodes
3. The system maintains functionality throughout the replacement process

## Partial Cluster Failure

In case of multiple node failures (but not complete infrastructure loss):

1. Assess which nodes are still operational:
   ```bash
   kubectl get nodes
   ```

2. If at least one master+worker node is operational, you can rebuild the cluster from there:
   - Keep the functioning nodes
   - Remove the failed nodes using the script
   - Add replacement nodes

3. If the backup node failed but production nodes are operational:
   - Add a new backup node
   - Configure backup storage
   - Run a manual backup to verify

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

## Control Plane Failure

In the unlikely event that all three master+worker nodes fail simultaneously, but your data is intact:

1. Identify a worker node that is still operational (backup node)
2. Promote the worker node to a master+worker temporarily:
   ```bash
   ssh admin@[BACKUP_NODE_IPV6] "sudo k3s server \
     --cluster-init \
     --token <saved-token> \
     --tls-san [BACKUP_NODE_IPV6]"
   ```

3. Add new master+worker nodes using the add-node.sh script
4. Once the new master+worker nodes are operational, restore the backup node to its original role

## Catastrophic Network Failure

If your IPv6 Mycelium network fails:

1. Check if nodes can still communicate directly via their LAN
2. If LAN communication is possible, reconfigure the Kubernetes API server to use LAN IPs:
   ```bash
   ssh admin@[NODE_LAN_IP] "sudo sed -i 's/bind-address=.*/bind-address=0.0.0.0/' /etc/rancher/k3s/config.yaml && sudo systemctl restart k3s"
   ```

3. Update your kubeconfig to use LAN IPs
4. Once network issues are resolved, revert to the original IPv6 configuration

## Emergency Contacts

If you need emergency assistance with recovery, contact the website admin.

## Recovery Drills

It's recommended to practice these recovery procedures regularly in a test environment:

1. Set up a duplicate testing environment
2. Simulate different failure scenarios
3. Practice the recovery steps
4. Document any issues encountered and improvements needed

Regular drills ensure your team is prepared for real emergencies and confirm that your backup and recovery processes work as expected.
