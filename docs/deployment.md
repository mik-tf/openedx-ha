# Deployment Guide

This guide walks through the complete process of deploying the Open edX High Availability solution using Kubernetes on your homemade cluster.

## Prerequisites

- 4 mini PCs with IPv6 connectivity via Mycelium
- SSH access to all nodes
- A domain name with access to DNS settings
- Basic understanding of Kubernetes concepts

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
         "role": "master",
         "ssh_key_path": "~/.ssh/id_rsa"
       },
       {
         "name": "node2",
         "ipv6": "2001:db8:2::1",
         "user": "admin",
         "role": "worker",
         "ssh_key_path": "~/.ssh/id_rsa"
       },
       {
         "name": "node3",
         "ipv6": "2001:db8:3::1",
         "user": "admin",
         "role": "worker",
         "ssh_key_path": "~/.ssh/id_rsa"
       },
       {
         "name": "node4",
         "ipv6": "2001:db8:4::1",
         "user": "admin",
         "role": "backup",
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

## Step 2: Run the Deployment Script

```bash
./deploy.sh
```

This script will:
1. Install dependencies on your local machine
2. Generate Kubernetes configuration files from your settings
3. Set up k3s on your cluster nodes
4. Deploy all the necessary Kubernetes resources
5. Set up the CouchDB cluster
6. Verify the deployment is working correctly
7. Generate DNS record information

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

Add these records at your DNS provider.

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

3. Check if the CouchDB cluster is functioning correctly:
   ```bash
   kubectl -n openedx exec deploy/couchdb-0 -- curl -s http://admin:password@localhost:5984/_membership
   ```

## Step 6: Configure Local Backup

On your local PC:

1. Set up the fetch-openedx-backup.sh script:
   ```bash
   chmod +x scripts/backup/fetch-openedx-backup.sh
   ./scripts/backup/fetch-openedx-backup.sh
   ```

2. Set up a scheduled task to run this script regularly

## Troubleshooting

If you encounter issues during deployment, refer to the [troubleshooting guide](troubleshooting.md) for common issues and solutions.

## Next Steps

After successful deployment:

1. Review the [operations manual](operations.md) for day-to-day management
2. Test the backup and restore procedures as described in the [backup guide](backup.md)
3. Familiarize yourself with the [architecture overview](architecture.md) to understand the system

Congratulations! You now have a high-availability Open edX deployment running on your own hardware cluster.
