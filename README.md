# Open edX High Availability Kubernetes Deployment

This project provides a complete solution for deploying Open edX in a high-availability configuration using Kubernetes (k3s) on a 4-node cluster with Mycelium IPv6 networking.

## Architecture

The deployment consists of:
- 3 production nodes running Kubernetes with Open edX components
- 1 backup node for centralized backup storage
- DNS round-robin for load balancing
- CouchDB cluster for data replication
- Local PC backup solution for off-site redundancy

## Features

- **High Availability**: No single point of failure, redundant data storage
- **Geographic Distribution**: Nodes can be physically distributed
- **Automatic Updates**: Using standard Kubernetes mechanisms
- **Infrastructure as Code**: Complete deployment scripts
- **Comprehensive Backup**: Server-side and local backup options
- **Self-Healing**: Built-in Kubernetes health checks and recovery
- **IPv6 Ready**: Works with Mycelium overlay network

## Prerequisites

- 4 mini Ubuntu 24.04 PCs with IPv6 connectivity via Mycelium
  - For more information consult this [Mycelium cluster repo](https://github.com/mik-tf/mcluster) and this [ISO Boot Maker repo](https://github.com/mik-tf/isobootmaker)
- SSH access to all nodes
- A domain name with access to DNS settings
- Basic understanding of Kubernetes concepts

## Quick Start

1. **Clone this repository**:
   ```bash
   git clone https://github.com/mik-tf/openedx-ha.git
   cd openedx-ha
   ```

2. **Configure your cluster**:
   ```bash
   cp config/cluster-config.json.example config/cluster-config.json
   # Edit cluster-config.json with your node details
   ```

3. **Deploy the cluster**:
   ```bash
   ./deploy.sh
   ```

4. **Configure DNS**:
   Add AAAA records for your domain pointing to your three production nodes' IPv6 addresses as shown in `config/dns-records.txt`.

See the [detailed deployment guide](docs/deployment.md) for complete instructions.

## Documentation

- [Architecture Details](docs/architecture.md)
- [Deployment Guide](docs/deployment.md)
- [Operations Manual](docs/operations.md)
- [Backup and Restore](docs/backup.md)
- [Disaster Recovery](docs/disaster-recovery.md)
- [Troubleshooting](docs/troubleshooting.md)

## License

This project is licensed under the [MIT License](LICENSE).
