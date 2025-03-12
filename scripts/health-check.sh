#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PARENT_DIR/config/cluster-config.json"

# Get CouchDB credentials
COUCHDB_USER=$(jq -r '.couchdb.user' "$CONFIG_FILE")
COUCHDB_PASSWORD=$(jq -r '.couchdb.password' "$CONFIG_FILE")
DOMAIN=$(jq -r '.domain' "$CONFIG_FILE")

echo "Running health check at $(date)"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "kubectl not found. Please make sure kubectl is installed."
    exit 1
fi

# Check if namespace exists
if ! kubectl get namespace openedx &> /dev/null; then
    echo "openedx namespace not found. Is the cluster properly initialized?"
    exit 1
fi

# Check node status
echo "Checking node status..."
NODE_STATUS=$(kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}')
if [[ "$NODE_STATUS" != *"True"* ]]; then
    echo "ERROR: Some nodes are not in Ready state."
    kubectl get nodes
    exit 1
fi

# Check pod status
echo "Checking pod status..."
UNHEALTHY_PODS=$(kubectl -n openedx get pods -o jsonpath='{range .items[?(@.status.phase!="Running")]}{.metadata.name}{"\n"}{end}')
if [ ! -z "$UNHEALTHY_PODS" ]; then
    echo "ERROR: Some pods are not in Running state:"
    echo "$UNHEALTHY_PODS"
    exit 1
fi

# Check CouchDB cluster
echo "Checking CouchDB cluster status..."
COUCHDB_POD=$(kubectl -n openedx get pods -l app=couchdb -o jsonpath='{.items[0].metadata.name}')
MEMBERSHIP=$(kubectl -n openedx exec $COUCHDB_POD -- curl -s http://${COUCHDB_USER}:${COUCHDB_PASSWORD}@127.0.0.1:5984/_membership)
NODE_COUNT=$(echo $MEMBERSHIP | jq '.cluster_nodes | length')
EXPECTED_NODES=$(kubectl -n openedx get pods -l app=couchdb -o jsonpath='{.items}' | jq length)

if [ "$NODE_COUNT" -lt "$EXPECTED_NODES" ]; then
    echo "WARNING: CouchDB cluster has $NODE_COUNT nodes, expected $EXPECTED_NODES"
    echo "CouchDB cluster membership: $MEMBERSHIP"
    exit 1
fi

# Check LMS and CMS services
echo "Checking LMS and CMS services..."
LMS_READY=$(kubectl -n openedx get pods -l app=lms -o jsonpath='{.items[*].status.containerStatuses[0].ready}')
CMS_READY=$(kubectl -n openedx get pods -l app=cms -o jsonpath='{.items[*].status.containerStatuses[0].ready}')

if [[ "$LMS_READY" != *"true"* ]]; then
    echo "ERROR: LMS pod is not ready."
    kubectl -n openedx describe pods -l app=lms
    exit 1
fi

if [[ "$CMS_READY" != *"true"* ]]; then
    echo "ERROR: CMS pod is not ready."
    kubectl -n openedx describe pods -l app=cms
    exit 1
fi

# Check persistent volumes
echo "Checking persistent volumes..."
PV_STATUS=$(kubectl get pv -o jsonpath='{.items[*].status.phase}')
if [[ "$PV_STATUS" == *"Failed"* ]] || [[ "$PV_STATUS" == *"Released"* ]]; then
    echo "ERROR: Some persistent volumes are in Failed or Released state."
    kubectl get pv
    exit 1
fi

echo "All checks passed. System is healthy."
