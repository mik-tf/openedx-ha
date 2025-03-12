# Troubleshooting Guide

This guide helps diagnose and fix common issues with the Open edX Kubernetes deployment.

## Common Issues

### Kubernetes Cluster Problems

#### Symptoms:
- Nodes show as NotReady
- Pods stuck in Pending state
- Unexpected pod evictions

#### Solutions:

1. **Check Node Status**:
   ```bash
   kubectl get nodes
   kubectl describe node <node-name>
   ```

2. **Check System Resources**:
   ```bash
   kubectl top nodes
   kubectl top pods -n openedx
   ```

3. **Check Logs**:
   ```bash
   # For k3s issues on the master node
   ssh admin@[IPV6_ADDRESS] "sudo journalctl -u k3s"

   # For k3s issues on worker nodes
   ssh admin@[IPV6_ADDRESS] "sudo journalctl -u k3s-agent"
   ```

4. **Restart k3s Service**:
   ```bash
   ssh admin@[IPV6_ADDRESS] "sudo systemctl restart k3s"
   # or on agent nodes
   ssh admin@[IPV6_ADDRESS] "sudo systemctl restart k3s-agent"
   ```

### CouchDB Cluster Problems

#### Symptoms:
- Database sync failures
- Error messages about nodes disconnected
- Inconsistent data across instances

#### Solutions:

1. **Check Cluster Status**:
   ```bash
   kubectl -n openedx exec deploy/couchdb-0 -- curl -s \
     http://admin:password@localhost:5984/_membership | jq
   ```

2. **Verify Pod Status**:
   ```bash
   kubectl -n openedx get pods -l app=couchdb
   kubectl -n openedx describe pods -l app=couchdb
   ```

3. **Check CouchDB Logs**:
   ```bash
   kubectl -n openedx logs sts/couchdb
   ```

4. **Rebuild Cluster**:
   If the cluster is in a bad state:
   ```bash
   ./scripts/setup-couchdb-cluster.sh
   ```

### Pod Startup Failures

#### Symptoms:
- Pods stuck in CrashLoopBackOff or Error states
- Services unavailable

#### Solutions:

1. **Check Pod Status**:
   ```bash
   kubectl -n openedx get pods
   kubectl -n openedx describe pod <pod-name>
   ```

2. **View Container Logs**:
   ```bash
   kubectl -n openedx logs <pod-name>
   ```

3. **Check Resources**:
   ```bash
   kubectl -n openedx describe pod <pod-name> | grep -A 10 "Resources"
   ```

4. **Verify ConfigMaps and Secrets**:
   ```bash
   kubectl -n openedx get configmaps
   kubectl -n openedx get secrets
   ```

5. **Restart Deployments**:
   ```bash
   kubectl -n openedx rollout restart deploy/<deployment-name>
   ```

### DNS Issues

#### Symptoms:
- Intermittent service availability
- Some users can access, others cannot

#### Solutions:

1. **Verify IPv6 Connectivity**:
   ```bash
   ping6 <node-ipv6-address>
   ```

2. **Check DNS Records**:
   ```bash
   dig AAAA school.example.com
   # Should return all production VM IPv6 addresses
   ```

3. **Check TTL Settings**:
   Ensure your DNS TTL is set to a low value (300 seconds recommended)

4. **Test Mycelium Network**:
   ```bash
   # From one node to another
   ssh admin@[IPV6_ADDRESS] "ping6 [OTHER_IPV6_ADDRESS]"
   ```

### SSL/TLS Issues

#### Symptoms:
- Browser security warnings
- Certificate errors
- Mixed content warnings

#### Solutions:

1. **Check Caddy Status**:
   ```bash
   kubectl -n openedx logs deploy/caddy-deployment
   ```

2. **Verify Caddy Config**:
   ```bash
   kubectl -n openedx get configmap caddy-config -o yaml
   ```

3. **Test SSL Configuration**:
   ```bash
   # Install OpenSSL if needed
   openssl s_client -connect school.example.com:443 -servername school.example.com
   ```

4. **Force Certificate Renewal**:
   ```bash
   kubectl -n openedx rollout restart deploy/caddy-deployment
   ```

### Backup/Restore Issues

#### Symptoms:
- Backup job failing
- Incomplete backups
- Restore process errors

#### Solutions:

1. **Check Backup Job Logs**:
   ```bash
   kubectl -n openedx get jobs
   kubectl -n openedx logs job/<job-name>
   ```

2. **Verify Backup Volume**:
   ```bash
   kubectl -n openedx get pv
   kubectl -n openedx get pvc
   ```

3. **Check Backup Storage**:
   ```bash
   # SSH to the backup node
   ssh admin@[BACKUP_NODE_IPV6]
   # Check disk space
   df -h /opt/k3s/storage/backup
   # Check directory permissions
   ls -la /opt/k3s/storage/backup
   ```

4. **Test Backup Manually**:
   ```bash
   kubectl -n openedx create job --from=cronjob/daily-backup manual-backup-$(date +%s)
   ```

## Advanced Troubleshooting

### Network Policy Issues

If pods can't communicate with each other:

```bash
# Temporarily allow all traffic in the namespace for testing
kubectl -n openedx apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all
spec:
  podSelector: {}
  ingress:
  - {}
  egress:
  - {}
EOF
```

### Storage Issues

If PersistentVolumes are not working:

```bash
# Check PersistentVolume status
kubectl get pv

# Check PersistentVolumeClaim status
kubectl -n openedx get pvc

# Check path on node
ssh admin@[NODE_IPV6] "ls -la /opt/k3s/storage"
```

### Node Resource Exhaustion

If nodes are running out of resources:

```bash
# Check node resource usage
kubectl top nodes

# Check disk space
ssh admin@[NODE_IPV6] "df -h"

# Check memory usage
ssh admin@[NODE_IPV6] "free -h"

# Check for processes using excessive resources
ssh admin@[NODE_IPV6] "top -b -n 1"
```

### IPv6 Connectivity Issues

For IPv6-specific problems:

```bash
# Check IPv6 is enabled
ssh admin@[NODE_IPV6] "sysctl net.ipv6.conf.all.disable_ipv6"
# Should return 0

# Check IPv6 forwarding
ssh admin@[NODE_IPV6] "sysctl net.ipv6.conf.all.forwarding"
# Should return 1

# Check firewall isn't blocking IPv6
ssh admin@[NODE_IPV6] "ip6tables -L"
```

## Getting Help

If you're unable to resolve the issue using this guide:

1. Check the [Open edX documentation](https://docs.openedx.org/)
2. Search the [Open edX discussion forums](https://discuss.openedx.org/)
3. File an issue on the GitHub repository
```

### `docs/operations.md` (Updated sections)
```markdown
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

## IPv6 Operations

### Testing IPv6 Connectivity

```bash
# Check if nodes can reach each other
ssh admin@[NODE1_IPV6] "ping6 -c 4 [NODE2_IPV6]"

# Check if IPv6 services are responding
curl -6 -k https://[NODE1_IPV6]
```

### Updating DNS Records

When you need to update the IPv6 addresses for your domain:

1. Generate new DNS records:
   ```bash
   ./scripts/generate-configs.sh config/cluster-config.json
   ```

2. Apply the changes at your DNS provider using the output in `config/dns-records.txt`

## Scaling the Deployment

To adjust the number of replicas:

```bash
# Scale up LMS pods
kubectl -n openedx scale deployment lms-deployment --replicas=5

# Scale down CMS pods
kubectl -n openedx scale deployment cms-deployment --replicas=2
```

## SSL Certificate Management

This deployment uses Caddy for automatic SSL certificate management:

### How It Works

- Caddy automatically obtains and renews certificates for your domain
- Certificates are stored in the Caddy pod's persistent volume
- The same domain certificates work across all nodes due to DNS round-robin

### Forcing Certificate Renewal

If you need to force certificate renewal:

```bash
kubectl -n openedx rollout restart deployment caddy-deployment
```

### Checking Certificate Status

```bash
kubectl -n openedx exec deploy/caddy-deployment -- caddy list-certs
```

### Manual TLS Configuration

If you need to use custom certificates:

1. Edit the Caddy ConfigMap:
   ```bash
   kubectl -n openedx edit configmap caddy-config
   ```

2. Modify the Caddyfile to use your custom certificates:
   ```
   school.example.com {
     tls /path/to/cert.pem /path/to/key.pem
     # ...
   }
   ```

3. Restart Caddy:
   ```bash
   kubectl -n openedx rollout restart deployment caddy-deployment
   ```

## Managing Open edX Users

### Creating Admin Users

```bash
kubectl -n openedx exec deploy/lms-deployment -- bash -c "python /openedx/edx-platform/manage.py lms --settings=tutor.production createsuperuser"
```

### Resetting User Passwords

```bash
kubectl -n openedx exec deploy/lms-deployment -- bash -c "python /openedx/edx-platform/manage.py lms --settings=tutor.production changepassword USERNAME"
```
