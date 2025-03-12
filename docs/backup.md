# Backup and Restore Guide

This document details the backup strategy and restore procedures for the Kubernetes-based Open edX deployment.

## Backup Strategy Overview

Our backup strategy has three tiers:

1. **Kubernetes Scheduled Backups**: Daily, weekly, and monthly CronJobs
2. **Backup Rotation**: Automatic cleanup with configurable retention periods
3. **Local PC Backup**: Off-site backup for disaster recovery

## Server-Side Backup Configuration

The backup process is automated using Kubernetes CronJobs:

- **Daily backups**: Every day at 1:00 AM via `daily-backup` CronJob
- **Weekly backups**: Every Sunday at 2:00 AM via `weekly-backup` CronJob
- **Monthly backups**: First day of each month at 3:00 AM via `monthly-backup` CronJob

### Backup Contents

Each backup includes:
- CouchDB database dumps (JSON format)
- Kubernetes ConfigMaps and Secrets
- Metadata with backup date, type, and integrity checksum

### Backup Storage

Backups are stored on Node4 (backup node) in a PersistentVolume at `/opt/k3s/storage/backup` with the following structure:
- `/daily/YYYYMMDD/`: Daily backups with date-based directories
- `/weekly/YYYY-weekNN/`: Weekly backups
- `/monthly/YYYY-MM/`: Monthly backups

### Retention Policy

- Daily backups: Kept for 7 days
- Weekly backups: Kept for 4 weeks
- Monthly backups: Kept for 12 months

## Local PC Backup

The local backup script pulls the latest backup from the backup node to your local machine.

### Setup

1. Configure your cluster-config.json with the correct backup node information
2. Run the fetch script:
   ```bash
   ./scripts/backup/fetch-openedx-backup.sh
   ```

### Usage

The script will:
- Connect to the backup node
- Download the latest backup
- Verify its integrity
- Store it locally with a date-based directory structure
- Remove old backups (keeping the latest 10)

## Manual Backup

You can trigger a manual backup at any time:

```bash
kubectl -n openedx create job --from=cronjob/daily-backup manual-backup-$(date +%s)
```

## Verifying Backups

To verify a backup's integrity:

```bash
./scripts/backup/verify-backup.sh /path/to/backup
```

The script will check:
- Presence of all required files
- Checksum integrity
- Valid JSON structure in database dumps

## Restore Procedures

### Full System Restore

In case of catastrophic failure:

1. Deploy new infrastructure using the deployment script
2. Edit the restore job:
   ```bash
   kubectl -n openedx edit job restore-job
   # Change BACKUP_DIR to point to your backup
   ```
3. Run the restore job:
   ```bash
   kubectl -n openedx create -f kubernetes/backup/restore-job.yaml
   ```
4. Restart services to apply changes:
   ```bash
   kubectl -n openedx rollout restart deploy/lms-deployment
   kubectl -n openedx rollout restart deploy/cms-deployment
   ```

### Single Node Restore

If only one node has failed:

1. Remove the failed node:
   ```bash
   ./scripts/cluster/remove-node.sh node2
   ```
2. Add a replacement node:
   ```bash
   ./scripts/cluster/add-node.sh node2-new 2001:db8:2::2 admin ~/.ssh/id_rsa
   ```

Kubernetes and CouchDB will automatically rebalance data to the new node.

### Data-Only Restore

To restore just the database without rebuilding the cluster:

```bash
kubectl -n openedx create -f kubernetes/backup/restore-job.yaml
```

## Catastrophic Recovery Preparation

While our multi-tier backup strategy provides robust data protection, it's essential to be prepared for worst-case scenarios where all infrastructure is lost. The local PC backup is your last line of defense.

### Why Your Local Backup Is Critical

Your local PC backup contains everything needed to completely rebuild the Open edX platform, including:
- All course content and structure
- User data, enrollments, and progress
- System configurations and customizations
- Database schema and relationships

### Safeguarding Your Local Backup

To ensure your local backup remains viable for disaster recovery:

1. **Storage Security**:
   - Store backups on an encrypted drive
   - Consider a secondary offline copy (external drive)
   - Protect backup media from physical damage and theft

2. **Verification**:
   - Regularly run the backup verification script
   - Address any integrity issues immediately

3. **Documentation**:
   - Keep notes on any custom configurations
   - Store a copy of your infrastructure credentials securely
   - Document your domain registrar access details

### Disaster Recovery Testing

We recommend conducting a disaster recovery test at least once per quarter:

1. Create a temporary test environment
2. Restore from your local backup
3. Verify functionality
4. Document any issues and their solutions

The time to establish your disaster recovery protocol is before you need it. Regular testing ensures that even in the worst-case scenario, your educational platform can be fully restored with minimal downtime.
