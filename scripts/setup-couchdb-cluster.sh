#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PARENT_DIR/config/cluster-config.json"

# Get CouchDB credentials
COUCHDB_USER=$(jq -r '.couchdb.user' "$CONFIG_FILE")
COUCHDB_PASSWORD=$(jq -r '.couchdb.password' "$CONFIG_FILE")

echo "Setting up CouchDB cluster..."

# Wait for all CouchDB pods to be ready
kubectl -n openedx wait --for=condition=ready pod -l app=couchdb --timeout=300s

# Get all CouchDB pod names
PODS=$(kubectl -n openedx get pods -l app=couchdb -o jsonpath='{.items[*].metadata.name}')
PODS_ARRAY=($PODS)

if [ ${#PODS_ARRAY[@]} -lt 3 ]; then
    echo "Warning: Less than 3 CouchDB pods found. Cluster will not be highly available."
fi

# Setup CouchDB Cluster
PRIMARY_POD=${PODS_ARRAY[0]}
echo "Using $PRIMARY_POD as the primary CouchDB node"

# Enable cluster on primary node
kubectl -n openedx exec $PRIMARY_POD -- \
    curl -s -X POST -H "Content-Type: application/json" \
    http://${COUCHDB_USER}:${COUCHDB_PASSWORD}@127.0.0.1:5984/_cluster_setup \
    -d "{\"action\": \"enable_cluster\", \"bind_address\":\"0.0.0.0\", \
         \"username\": \"${COUCHDB_USER}\", \"password\":\"${COUCHDB_PASSWORD}\", \
         \"node_count\":\"$(echo ${#PODS_ARRAY[@]})\"}"

# Add other nodes to cluster
for ((i=1; i<${#PODS_ARRAY[@]}; i++)); do
    NODE=${PODS_ARRAY[$i]}
    NODE_IP=$(kubectl -n openedx get pod $NODE -o jsonpath='{.status.podIP}')

    echo "Adding CouchDB node $NODE ($NODE_IP) to cluster..."

    # Initialize the node
    kubectl -n openedx exec $NODE -- \
        curl -s -X POST -H "Content-Type: application/json" \
        http://${COUCHDB_USER}:${COUCHDB_PASSWORD}@127.0.0.1:5984/_cluster_setup \
        -d "{\"action\": \"enable_cluster\", \"bind_address\":\"0.0.0.0\", \
             \"username\": \"${COUCHDB_USER}\", \"password\":\"${COUCHDB_PASSWORD}\"}"

    # Add the node to the cluster
    kubectl -n openedx exec $PRIMARY_POD -- \
        curl -s -X POST -H "Content-Type: application/json" \
        http://${COUCHDB_USER}:${COUCHDB_PASSWORD}@127.0.0.1:5984/_cluster_setup \
        -d "{\"action\": \"add_node\", \"host\":\"${NODE_IP}\", \
             \"port\": \"5984\", \"username\": \"${COUCHDB_USER}\", \"password\":\"${COUCHDB_PASSWORD}\"}"
done

# Finish cluster setup
kubectl -n openedx exec $PRIMARY_POD -- \
    curl -s -X POST -H "Content-Type: application/json" \
    http://${COUCHDB_USER}:${COUCHDB_PASSWORD}@127.0.0.1:5984/_cluster_setup \
    -d '{"action": "finish_cluster"}'

# Check cluster status
echo "Checking CouchDB cluster status..."
kubectl -n openedx exec $PRIMARY_POD -- \
    curl -s http://${COUCHDB_USER}:${COUCHDB_PASSWORD}@127.0.0.1:5984/_membership

echo "CouchDB cluster setup completed successfully!"
