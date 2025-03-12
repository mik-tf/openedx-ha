#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config/cluster-config.json"

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found at $CONFIG_FILE"
    exit 1
fi

echo "===== Undeploying OpenedX High Availability Kubernetes Deployment ====="
echo "WARNING: This will remove the entire OpenedX deployment from your cluster!"
read -p "Are you sure you want to continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Undeployment cancelled."
    exit 0
fi

# Remove Kubernetes resources
echo "Step 1: Removing Kubernetes resources..."
kubectl delete -f "$SCRIPT_DIR/kubernetes/backup/" --ignore-not-found
kubectl delete -f "$SCRIPT_DIR/kubernetes/monitoring/" --ignore-not-found
kubectl delete -f "$SCRIPT_DIR/kubernetes/caddy/" --ignore-not-found
kubectl delete -f "$SCRIPT_DIR/kubernetes/openedx/" --ignore-not-found
kubectl delete -f "$SCRIPT_DIR/kubernetes/couchdb/" --ignore-not-found
kubectl delete -f "$SCRIPT_DIR/kubernetes/storage/" --ignore-not-found
kubectl delete -f "$SCRIPT_DIR/kubernetes/namespace.yaml" --ignore-not-found

# Uninstall k3s from all nodes
echo "Step 2: Uninstalling k3s from all nodes..."
for NODE in $(jq -r '.nodes[] | .name + "," + .ipv6 + "," + .user + "," + .ssh_key_path' "$CONFIG_FILE"); do
    IFS=',' read -r NODE_NAME NODE_IPV6 NODE_USER NODE_KEY <<< "$NODE"
    echo "Uninstalling k3s from $NODE_NAME ($NODE_IPV6)..."
    ssh -i "$NODE_KEY" -o StrictHostKeyChecking=no "$NODE_USER@$NODE_IPV6" "sudo /usr/local/bin/k3s-uninstall.sh || true"
done

echo "===== Undeployment Complete ====="
echo "The k3s cluster and all OpenedX resources have been removed."
echo "To redeploy, run ./deploy.sh"
