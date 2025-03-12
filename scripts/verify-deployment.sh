#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$PARENT_DIR/config/cluster-config.json"

DOMAIN=$(jq -r '.domain' "$CONFIG_FILE")

echo "Verifying deployment..."

# Wait for all pods to be ready
echo "Waiting for all pods to be ready..."
kubectl -n openedx wait --for=condition=ready pod --all --timeout=300s || {
    echo "ERROR: Not all pods are ready. Current pod status:"
    kubectl -n openedx get pods
    exit 1
}

# Check CouchDB cluster status
echo "Checking CouchDB cluster status..."
"$SCRIPT_DIR/health-check.sh" > /dev/null || {
    echo "ERROR: Health check failed. Please check the logs."
    exit 1
}

# Get service endpoints
LMS_SERVICE=$(kubectl -n openedx get service lms-service -o jsonpath='{.spec.clusterIP}')
CMS_SERVICE=$(kubectl -n openedx get service cms-service -o jsonpath='{.spec.clusterIP}')

echo "LMS Service: $LMS_SERVICE"
echo "CMS Service: $CMS_SERVICE"

# Check if services are accessible within the cluster
echo "Checking if services are accessible within the cluster..."
kubectl -n openedx run curl --image=curlimages/curl --restart=Never --rm --command -- curl -s http://$LMS_SERVICE:8000/heartbeat || {
    echo "ERROR: LMS service is not accessible within the cluster."
    exit 1
}

kubectl -n openedx run curl --image=curlimages/curl --restart=Never --rm --command -- curl -s http://$CMS_SERVICE:8000/heartbeat || {
    echo "ERROR: CMS service is not accessible within the cluster."
    exit 1
}

echo "Services are accessible within the cluster."

echo "Deployment verification completed successfully!"
echo ""
echo "Now you need to set up DNS AAAA records for your domain:"
echo "- $DOMAIN"
echo "- studio.$DOMAIN"
echo "- monitoring.$DOMAIN"
echo ""
echo "The DNS records have been generated in config/dns-records.txt"
echo ""
echo "Once DNS is configured, you can access the platform at:"
echo "- LMS: https://$DOMAIN"
echo "- Studio: https://studio.$DOMAIN"
echo "- Monitoring: https://monitoring.$DOMAIN"
