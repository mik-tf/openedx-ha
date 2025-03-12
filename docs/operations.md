# Operations Manual

This document covers day-to-day operations and maintenance tasks for the Open edX HA Kubernetes deployment.

## Routine Operations

### Checking System Health

```bash
# Get node status
kubectl get nodes

# Get pod status
kubectl -n openedx get pods

# Check CouchDB cluster status
kubectl -n openedx exec deploy/couchdb-0 -- curl -s http://admin:password@localhost:5984/_membership

# Run the health check script
./scripts/health-check.sh
```

### Viewing Logs

```bash
# View logs for LMS
kubectl -n openedx logs deploy/lms-deployment

# View logs for CMS
kubectl -n openedx logs deploy/cms-deployment

# View logs for CouchDB
kubectl -n openedx logs sts/couchdb

# View logs for Caddy
kubectl -n openedx logs deploy/caddy-deployment
```

### Restarting Services

```bash
# Restart LMS
kubectl -n openedx rollout restart deploy/lms-deployment

# Restart CMS
kubectl -n openedx rollout restart deploy/cms-deployment

# Restart CouchDB (careful with this!)
kubectl -n openedx rollout restart sts/couchdb

# Restart Caddy
kubectl -n openedx rollout restart deploy/caddy-deployment
```

## Adding a New Node

```bash
# Add a new worker node
./scripts/cluster/add-node.sh node5 2001:db8:5::1 admin ~/.ssh/id_rsa
```

## Removing a Node

```bash
# Remove a worker node
./scripts/cluster/remove-node.sh node2
```

## Updating Configuration

1. Edit the Kubernetes ConfigMap:
   ```bash
   kubectl -n openedx edit configmap lms-config
   ```

2. Restart the pod to apply changes:
   ```bash
   kubectl -n openedx rollout restart deploy/lms-deployment
   ```

## Backup and Restore

### Manual Backup

```bash
# Trigger a manual backup
kubectl -n openedx create job --from=cronjob/daily-backup manual-backup
```

### Restore from Backup

1. Edit the restore job to specify the backup directory:
   ```bash
   kubectl -n openedx edit job/restore-job
   # Change BACKUP_DIR value to point to the backup you want to restore
   ```

2. Run the restore job:
   ```bash
   kubectl -n openedx create -f kubernetes/backup/restore-job.yaml
   ```

## Accessing the Kubernetes Dashboard (Optional)

If you've installed the Kubernetes Dashboard:

```bash
# Start the proxy
kubectl proxy

# Access the dashboard at:
# http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
```

## Checking Backups

```bash
# List backups on the backup node
kubectl -n openedx exec deploy/couchdb-0 -- ls -la /backup/daily
kubectl -n openedx exec deploy/couchdb-0 -- ls -la /backup/weekly
kubectl -n openedx exec deploy/couchdb-0 -- ls -la /backup/monthly
```

## Handling Node Failures

If a node becomes unreachable:

1. Check the node status:
   ```bash
   kubectl get nodes
   ```

2. If the node is marked as NotReady, you might want to drain it:
   ```bash
   kubectl drain node2 --ignore-daemonsets
   ```

3. Once the node is back online or replaced:
   ```bash
   kubectl uncordon node2
   ```

## Monitoring Resources

```bash
# Check resource usage
kubectl -n openedx top nodes
kubectl -n openedx top pods
```

## Security Updates

For updating the underlying OS on each node:

```bash
# SSH into the node
ssh admin@2001:db8:1::1

# Update packages
sudo apt update
sudo apt upgrade -y

# Reboot if necessary
sudo reboot
```

## Common Tasks

### Reset Admin Password

```bash
kubectl -n openedx exec deploy/lms-deployment -- bash -c "python /openedx/edx-platform/manage.py lms --settings=tutor.production changepassword admin"
```

### Clear Cache

```bash
kubectl -n openedx exec deploy/lms-deployment -- bash -c "python /openedx/edx-platform/manage.py lms --settings=tutor.production cache_clear"
```

### Update Kubernetes Resources

If you need to update the Kubernetes resources:

1. Edit the resource file
2. Apply the changes:
   ```bash
   kubectl apply -f kubernetes/openedx/lms-deployment.yaml
   ```
