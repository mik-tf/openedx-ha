#!/bin/bash
# Modified deploy.sh for 3 master+worker nodes and 1 backup node

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config/cluster-config.json"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found at $CONFIG_FILE"
    echo "Please create one based on the example at config/cluster-config.json.example"
    exit 1
fi

echo "===== OpenedX High Availability Kubernetes Deployment ====="
echo "Starting deployment using configuration from $CONFIG_FILE"

# Install dependencies on local machine
echo "Step 1: Installing dependencies..."
"$SCRIPT_DIR/scripts/install-dependencies.sh"

# Generate Kubernetes configuration files from template
echo "Step 2: Generating Kubernetes configurations..."
"$SCRIPT_DIR/scripts/generate-configs.sh" "$CONFIG_FILE"

# Setup first master+worker node
echo "Step 3: Setting up k3s cluster..."
FIRST_MASTER=$(jq -r '.nodes[] | select(.is_first_master==true) | .name + "," + .ipv6 + "," + .user + "," + .ssh_key_path' "$CONFIG_FILE")
IFS=',' read -r MASTER_NAME MASTER_IPV6 MASTER_USER MASTER_KEY <<< "$FIRST_MASTER"

echo "Setting up first master+worker node on $MASTER_NAME ($MASTER_IPV6)..."
"$SCRIPT_DIR/scripts/cluster/setup-k3s-master-worker.sh" "$MASTER_IPV6" "$MASTER_USER" "$MASTER_KEY"

# Get k3s token from master
TOKEN=$(ssh -i "$MASTER_KEY" -o StrictHostKeyChecking=no "$MASTER_USER@$MASTER_IPV6" "sudo cat /var/lib/rancher/k3s/server/node-token")

# Setup other master+worker nodes
for NODE in $(jq -r '.nodes[] | select(.role=="master+worker" and .is_first_master==false) | .name + "," + .ipv6 + "," + .user + "," + .ssh_key_path' "$CONFIG_FILE"); do
    IFS=',' read -r NODE_NAME NODE_IPV6 NODE_USER NODE_KEY <<< "$NODE"
    echo "Setting up additional master+worker node on $NODE_NAME ($NODE_IPV6)..."
    "$SCRIPT_DIR/scripts/cluster/setup-k3s-additional-master.sh" "$NODE_IPV6" "$NODE_USER" "$NODE_KEY" "$MASTER_IPV6" "$TOKEN"
done

# Setup backup worker node
BACKUP_NODE=$(jq -r '.nodes[] | select(.role=="backup") | .name + "," + .ipv6 + "," + .user + "," + .ssh_key_path' "$CONFIG_FILE")
IFS=',' read -r BACKUP_NAME BACKUP_IPV6 BACKUP_USER BACKUP_KEY <<< "$BACKUP_NODE"
echo "Setting up backup worker node on $BACKUP_NAME ($BACKUP_IPV6)..."
"$SCRIPT_DIR/scripts/cluster/setup-k3s-worker.sh" "$BACKUP_IPV6" "$BACKUP_USER" "$BACKUP_KEY" "$MASTER_IPV6" "$TOKEN"

# Create specialized directory on backup node
ssh -i "$BACKUP_KEY" -o StrictHostKeyChecking=no "$BACKUP_USER@$BACKUP_IPV6" "sudo mkdir -p /opt/k3s/storage/backup && sudo chmod 777 /opt/k3s/storage/backup"

# Copy kubeconfig to local machine
echo "Step 4: Configuring kubectl on local machine..."
mkdir -p ~/.kube
ssh -i "$MASTER_KEY" "$MASTER_USER@$MASTER_IPV6" "sudo cat /etc/rancher/k3s/k3s.yaml" > ~/.kube/config
# Update the server address in the kubeconfig
sed -i "s/127.0.0.1/$MASTER_IPV6/g" ~/.kube/config

# Apply Kubernetes manifests
echo "Step 5: Applying Kubernetes manifests..."
kubectl apply -f "$SCRIPT_DIR/kubernetes/namespace.yaml"
kubectl apply -f "$SCRIPT_DIR/kubernetes/storage/"
kubectl apply -f "$SCRIPT_DIR/kubernetes/couchdb/"
sleep 30  # Give CouchDB time to start
kubectl apply -f "$SCRIPT_DIR/kubernetes/openedx/"
kubectl apply -f "$SCRIPT_DIR/kubernetes/caddy/"
kubectl apply -f "$SCRIPT_DIR/kubernetes/monitoring/"
kubectl apply -f "$SCRIPT_DIR/kubernetes/backup/"

# Setup CouchDB cluster
echo "Step 6: Setting up CouchDB cluster..."
"$SCRIPT_DIR/scripts/setup-couchdb-cluster.sh"

# Verify deployment
echo "Step 7: Verifying deployment..."
"$SCRIPT_DIR/scripts/verify-deployment.sh"

# Generate DNS configuration
DOMAIN=$(jq -r '.domain' "$CONFIG_FILE")
echo "Step 8: Generating DNS configuration for domain $DOMAIN..."
cat "$SCRIPT_DIR/config/dns-records-template.txt" | \
    sed "s/school.example.com/$DOMAIN/g" | \
    sed "s/2001:db8:1::1/$(jq -r '.nodes[0].ipv6' "$CONFIG_FILE")/g" | \
    sed "s/2001:db8:2::1/$(jq -r '.nodes[1].ipv6' "$CONFIG_FILE")/g" | \
    sed "s/2001:db8:3::1/$(jq -r '.nodes[2].ipv6' "$CONFIG_FILE")/g" > "$SCRIPT_DIR/config/dns-records.txt"

echo "===== Deployment Complete ====="
echo "Please set up the DNS AAAA records as shown in config/dns-records.txt"
echo "You can access the Open edX platform at https://$DOMAIN once DNS is configured"
echo "For more information, please refer to the documentation in the docs/ directory"
