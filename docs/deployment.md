# Deployment Guide

This guide walks through the complete process of deploying the Open edX High Availability solution using Kubernetes on your homemade cluster. This deployment is designed with zero single points of failure (SPOF) across all components.

## Prerequisites

- 4 mini PCs with IPv6 connectivity via Mycelium
- SSH access to all nodes
- A domain name with access to DNS settings
- Basic understanding of Kubernetes concepts

## Architecture Overview

Before deployment, it's important to understand the high-availability design:

- **3 Production Nodes**: Each running identical components (master+worker roles)
  - Kubernetes control plane (distributed)
  - CouchDB cluster nodes
  - Open edX LMS/CMS replicas
  - Caddy web servers
  - Monitoring components

- **1 Backup Node**: Dedicated for backup storage and operations
  - Regular backup jobs
  - Backup verification
  - Off-site backup synchronization

This architecture ensures that no single component failure can bring down the system. All services are replicated across multiple nodes, and the load is distributed via DNS round-robin.

## Step 1: Prepare Your Configuration

1. Clone this repository:
   ```bash
   git clone https://github.com/mik-tf/openedx-ha.git
   cd openedx-ha
   ```

2. Create your cluster configuration:
   ```bash
   cp config/cluster-config.json.example config/cluster-config.json
   # Edit the file with your actual values
   ```

   Example `cluster-config.json` content:
   ```json
   {
     "domain": "school.example.com",
     "nodes": [
       {
         "name": "node1",
         "ipv6": "2001:db8:1::1",
         "user": "admin",
         "role": "master+worker",
         "is_first_master": true,
         "ssh_key_path": "~/.ssh/id_rsa"
       },
       {
         "name": "node2",
         "ipv6": "2001:db8:2::1",
         "user": "admin",
         "role": "master+worker",
         "is_first_master": false,
         "ssh_key_path": "~/.ssh/id_rsa"
       },
       {
         "name": "node3",
         "ipv6": "2001:db8:3::1",
         "user": "admin",
         "role": "master+worker",
         "is_first_master": false,
         "ssh_key_path": "~/.ssh/id_rsa"
       },
       {
         "name": "node4",
         "ipv6": "2001:db8:4::1",
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

   **Note**: Using the `master+worker` role for the first three nodes ensures that both Kubernetes control plane and workloads are distributed, eliminating control plane as a potential SPOF.

## Step 2: Run the Deployment Script

```bash
./deploy.sh
```

This script will:
1. Install dependencies on your local machine
2. Generate Kubernetes configuration files from your settings
3. Set up k3s on your cluster nodes with appropriate roles
   - First node as initial master+worker
   - Other production nodes as additional master+worker nodes
   - Backup node as worker with dedicated storage
4. Deploy all the necessary Kubernetes resources with redundancy
   - CouchDB StatefulSet (3 replicas distributed across nodes)
   - Open edX LMS/CMS Deployments (3 replicas each)
   - Caddy for SSL/TLS termination (3 replicas)
   - Monitoring stack (Prometheus, Grafana, node exporters)
   - Backup system (CronJobs, PersistentVolumes)
5. Set up the CouchDB cluster for data replication
6. Verify the deployment is working correctly
7. Generate DNS record information

### High-Availability Component Verification

During deployment, the system verifies that components are properly distributed:

- Kubernetes scheduler ensures pods are distributed across nodes via PodAntiAffinity
- CouchDB cluster forms successfully with all nodes joining
- All services are accessible via their respective endpoints
- DNS configuration is generated for round-robin load balancing

## Step 3: DNS Configuration

Once the deployment is complete, you need to add AAAA DNS records for your domain. The script will generate a file `config/dns-records.txt` with the exact records you need to create.

Example:
```
school.example.com. IN AAAA 2001:db8:1::1
school.example.com. IN AAAA 2001:db8:2::1
school.example.com. IN AAAA 2001:db8:3::1

studio.school.example.com. IN AAAA 2001:db8:1::1
studio.school.example.com. IN AAAA 2001:db8:2::1
studio.school.example.com. IN AAAA 2001:db8:3::1

monitoring.school.example.com. IN AAAA 2001:db8:1::1
```

Add these records at your DNS provider. The multiple AAAA records for the same domain create a simple round-robin load balancing mechanism, distributing requests across all three production nodes.

### DNS TTL Considerations

For optimal failover, set your DNS TTL (Time To Live) to a relatively low value (300-600 seconds). This ensures that if one node becomes unavailable, clients will quickly try alternative IP addresses.

## Step 4: Create Admin User

1. Connect to your Kubernetes cluster:
   ```bash
   # This should already be configured by the deploy script
   kubectl get nodes
   ```

2. Create an admin user:
   ```bash
   kubectl -n openedx exec deploy/lms-deployment -- bash -c "python /openedx/edx-platform/manage.py lms --settings=tutor.production createsuperuser"
   ```

3. Follow the prompts to create an admin username, email, and password.

## Step 5: Verify Deployment

1. Wait for DNS propagation (may take some time depending on your DNS provider)

2. Visit these URLs in your browser:
   - LMS: https://school.example.com
   - Studio: https://studio.school.example.com
   - Monitoring: https://monitoring.school.example.com (login: admin/admin)

3. Test high-availability by accessing the site and then:
   - Temporarily shut down one node
   - Verify the site remains accessible (might require a browser refresh)
   - Restart the node
   - Repeat the test with different nodes

4. Check if the CouchDB cluster is functioning correctly:
   ```bash
   kubectl -n openedx exec deploy/couchdb-0 -- curl -s http://admin:password@localhost:5984/_membership
   ```
   You should see all three nodes in the cluster.

## Step 6: Configure Local Backup

On your local PC:

1. Set up the fetch-openedx-backup.sh script:
   ```bash
   chmod +x scripts/backup/fetch-openedx-backup.sh
   ./scripts/backup/fetch-openedx-backup.sh
   ```

2. Set up a scheduled task to run this script regularly

## Zero-SPOF Validation

To validate that your deployment has no single points of failure:

1. **Test Kubernetes Control Plane Redundancy**:
   - Temporarily shut down the first master node
   - Verify you can still run kubectl commands against the cluster
   - ```bash
     ssh admin@[NODE2_IPV6] "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/config
     sed -i "s/127.0.0.1/[NODE2_IPV6]/g" ~/.kube/config
     kubectl get nodes  # Should still work
     ```

2. **Test Application Redundancy**:
   - Temporarily shut down any single node
   - Verify the LMS and Studio remain accessible
   - Check monitoring to see how pods are automatically rescheduled

3. **Test Database Redundancy**:
   - Temporarily shut down one CouchDB pod
   - Verify data operations still work
   - ```bash
     kubectl -n openedx delete pod couchdb-0  # Will be automatically recreated
     # Site should still function with couchdb-1 and couchdb-2
     ```

4. **Test Backup System**:
   - Manually trigger a backup
   - Verify the backup completes successfully
   - ```bash
     kubectl -n openedx create job --from=cronjob/daily-backup manual-backup-test
     ```

## Troubleshooting

If you encounter issues during deployment, refer to the [troubleshooting guide](troubleshooting.md) for common issues and solutions.

## Next Steps

After successful deployment:

1. Review the [operations manual](operations.md) for day-to-day management
2. Test the backup and restore procedures as described in the [backup guide](backup.md)
3. Familiarize yourself with the [architecture overview](architecture.md) to understand the system
4. Run a simulated disaster recovery drill following the [disaster recovery guide](disaster-recovery.md)

Congratulations! You now have a high-availability Open edX deployment with zero single points of failure running on your own hardware cluster.
