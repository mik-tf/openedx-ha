# Architecture Details

## Overview

This Open edX deployment implements a high-availability architecture with no single point of failure (SPOF) using Kubernetes (k3s), CouchDB clustering, and DNS-based load balancing on custom hardware.

```

                   DNS Round-Robin (AAAA Records)
                   your-domain.com
                         │
           ┌─────────────┼─────────────┐
           │             │             │
     ┌─────▼─────┐ ┌─────▼─────┐ ┌─────▼─────┐
     │    VM1    │ │    VM2    │ │    VM3    │
     ├───────────┤ ├───────────┤ ├───────────┤
     │    K3s    | │    K3s    | │    K3s    |
     ├───────────┤ ├───────────┤ ├───────────┤
     │ Open edX  │ │ Open edX  │ │ Open edX  │
     │ CouchDB   │◄┼─CouchDB───┼►│ CouchDB   │
     └───────────┘ └───────────┘ └───────────┘
                                        │
                                        ▼
                               ┌─────────────┐
                               │  Backup VM  │
                               ├─────────────┤
                               │ K3s Worker  |
                               └─────────────┘
                                        │
                                        ▼
                               ┌─────────────┐
                               │  Local PC   │
                               │  Backup     │
                               └─────────────┘

```

## Components

### Kubernetes Cluster

The k3s Kubernetes distribution provides lightweight but powerful orchestration across all nodes:

- **Master Node**: Runs the Kubernetes control plane (Node1)
- **Worker Nodes**: Run workloads (Node2, Node3, and Node4)
- **Networking**: Mycelium IPv6 overlay network between nodes

### Production Nodes (3x)

Each production node runs these Kubernetes workloads:

1. **Open edX LMS**: Learning Management System deployment
2. **Open edX CMS (Studio)**: Content Management System deployment
3. **CouchDB**: Document database configured as a StatefulSet in a cluster
4. **Caddy**: Web server for SSL/TLS termination and load balancing
5. **Monitoring**: Prometheus and node exporters

### Backup Node (1x)

Dedicated node for backup operations:
1. Runs backup CronJobs
2. Maintains backup storage with PersistentVolume
3. Stores backup history (daily, weekly, monthly)

### Load Balancing

DNS round-robin distributes requests across the three production nodes:
- AAAA records point to each node's IPv6 address
- Simple, no additional infrastructure needed
- No single point of failure
- Client browsers automatically try alternative IPs if one server fails

### Data Replication

CouchDB cluster replicates all data across the three production nodes:
- StatefulSet ensures stable network identities
- All files and database content are replicated
- Automatic failover if one node goes down
- Built-in conflict resolution

### Update Strategy

Kubernetes provides rolling updates:
- Zero-downtime updates
- Automatic rollback if failures occur
- Configurable update strategy

### Backup Strategy

Three-tier backup approach:
1. Production to Backup Node (daily Kubernetes CronJobs)
2. Backup Node rotation (daily, weekly, monthly)
3. Local PC backups (on-demand)

## High Availability Characteristics

- **No Single Point of Failure**: All components are redundant
- **Self-Healing**: Kubernetes automatically restarts failed pods
- **Geographic Distribution**: Nodes can be in different physical locations
- **Graceful Degradation**: Service continues if components fail
- **Data Redundancy**: All data replicated across nodes
- **Network Redundancy**: Mycelium provides overlay networking that works across different networks

## IPv6 Considerations

- All services configured to work with IPv6
- Mycelium provides the overlay network across physically distributed nodes
- DNS AAAA records used for service discovery
- End-to-end IPv6 architecture

## Security Architecture

- Kubernetes RBAC for access control
- Network policies limit pod-to-pod communication
- TLS certificates automatically provisioned by Caddy
- Secrets stored as Kubernetes Secrets resources
