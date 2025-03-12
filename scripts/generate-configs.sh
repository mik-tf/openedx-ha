#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="$1"

if [ -z "$CONFIG_FILE" ] || [ ! -f "$CONFIG_FILE" ]; then
    echo "Usage: $0 <path/to/config.json>"
    exit 1
fi

echo "Generating Kubernetes configuration files..."

# Extract values from config.json
DOMAIN=$(jq -r '.domain' "$CONFIG_FILE")
COUCHDB_USER=$(jq -r '.couchdb.user' "$CONFIG_FILE")
COUCHDB_PASSWORD=$(jq -r '.couchdb.password' "$CONFIG_FILE")
PLATFORM_NAME=$(jq -r '.platform_name' "$CONFIG_FILE")
PLATFORM_EMAIL=$(jq -r '.platform_email' "$CONFIG_FILE")

# Create secrets.yaml for CouchDB
echo "Creating CouchDB secrets..."
cat > "$PARENT_DIR/kubernetes/couchdb/couchdb-secret.yaml" << EOF
apiVersion: v1
kind: Secret
metadata:
  name: couchdb-secrets
  namespace: openedx
type: Opaque
data:
  adminUsername: $(echo -n "$COUCHDB_USER" | base64)
  adminPassword: $(echo -n "$COUCHDB_PASSWORD" | base64)
  cookieAuthSecret: $(openssl rand -base64 32 | tr -d '\n' | base64)
  sharedSecret: $(openssl rand -base64 32 | tr -d '\n' | base64)
EOF

# Update Caddy ConfigMap with domain
echo "Updating Caddy configuration..."
cat > "$PARENT_DIR/kubernetes/caddy/caddy-configmap.yaml" << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: caddy-config
  namespace: openedx
data:
  Caddyfile: |
    {
      email $PLATFORM_EMAIL
      acme_http
    }

    $DOMAIN {
      tls {
        # This will automatically obtain certificates
      }

      handle /health {
        respond "OK" 200
      }

      handle {
        reverse_proxy lms-service:8000
      }
    }

    studio.$DOMAIN {
      tls {
        # This will automatically obtain certificates
      }

      reverse_proxy cms-service:8000
    }

    monitoring.$DOMAIN {
      tls {
        # This will automatically obtain certificates
      }

      basicauth {
        admin JDJhJDEwJE1uOEV1OFVUcTVZNUNML1VzWjhPTS4vUEZoWUtzdVVvVnpnS1M2MVhuYnBIVk9xQ2JCUm1h
      }

      reverse_proxy grafana-service:3000
    }
EOF

# Update LMS/CMS ConfigMaps
echo "Updating Open edX configuration..."
cat > "$PARENT_DIR/kubernetes/openedx/lms-configmap.yaml" << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: lms-config
  namespace: openedx
data:
  config.yml: |
    PLATFORM_NAME: "$PLATFORM_NAME"
    SITE_NAME: "$DOMAIN"
    LMS_BASE: "$DOMAIN"
    CMS_BASE: "studio.$DOMAIN"
    LMS_ROOT_URL: "https://$DOMAIN"
    CMS_ROOT_URL: "https://studio.$DOMAIN"

    FEATURES:
      ENABLE_DISCUSSION_SERVICE: true
      ENABLE_COURSEWARE_SEARCH: true
      ENABLE_COURSE_DISCOVERY: true
      ENABLE_DASHBOARD_SEARCH: true
      ENABLE_COMBINED_LOGIN_REGISTRATION: true
      PREVIEW_LMS_BASE: "$DOMAIN"
      ENABLE_COUCHDB: true

    EMAIL_BACKEND: 'django.core.mail.backends.smtp.EmailBackend'
    EMAIL_HOST: 'smtp.example.com'
    EMAIL_PORT: 587
    EMAIL_USE_TLS: true
    EMAIL_HOST_USER: 'your-email@example.com'
    EMAIL_HOST_PASSWORD: 'your-email-password'
    DEFAULT_FROM_EMAIL: "$PLATFORM_EMAIL"

    REGISTRATION_EXTRA_FIELDS:
      city: hidden
      country: hidden
      gender: hidden
      goals: hidden
      honor_code: hidden
      level_of_education: hidden
      mailing_address: hidden
      year_of_birth: hidden

    COUCHDB_HOST: 'couchdb-service'
    COUCHDB_PORT: 5984
    COUCHDB_USER: "$COUCHDB_USER"
    COUCHDB_PASSWORD: "$COUCHDB_PASSWORD"
    COUCHDB_DB_NAME: "openedx_k8s"

    DEFAULT_FILE_STORAGE: 'storage.couchdb_storage.CouchDBStorage'
    COURSE_IMPORT_EXPORT_STORAGE: 'storage.couchdb_storage.CouchDBStorage'
    VIDEO_TRANSCRIPTS_STORAGE: 'storage.couchdb_storage.CouchDBStorage'
    GRADES_DOWNLOAD_STORAGE: 'storage.couchdb_storage.CouchDBStorage'
EOF

cat > "$PARENT_DIR/kubernetes/openedx/cms-configmap.yaml" << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cms-config
  namespace: openedx
data:
  config.yml: |
    PLATFORM_NAME: "$PLATFORM_NAME"
    SITE_NAME: "studio.$DOMAIN"
    LMS_BASE: "$DOMAIN"
    CMS_BASE: "studio.$DOMAIN"
    LMS_ROOT_URL: "https://$DOMAIN"
    CMS_ROOT_URL: "https://studio.$DOMAIN"

    FEATURES:
      ENABLE_DISCUSSION_SERVICE: true
      ENABLE_COURSEWARE_SEARCH: true
      ENABLE_COURSE_DISCOVERY: true
      ENABLE_DASHBOARD_SEARCH: true
      ENABLE_COMBINED_LOGIN_REGISTRATION: true
      PREVIEW_LMS_BASE: "$DOMAIN"
      ENABLE_COUCHDB: true

    EMAIL_BACKEND: 'django.core.mail.backends.smtp.EmailBackend'
    EMAIL_HOST: 'smtp.example.com'
    EMAIL_PORT: 587
    EMAIL_USE_TLS: true
    EMAIL_HOST_USER: 'your-email@example.com'
    EMAIL_HOST_PASSWORD: 'your-email-password'
    DEFAULT_FROM_EMAIL: "$PLATFORM_EMAIL"

    COUCHDB_HOST: 'couchdb-service'
    COUCHDB_PORT: 5984
    COUCHDB_USER: "$COUCHDB_USER"
    COUCHDB_PASSWORD: "$COUCHDB_PASSWORD"
    COUCHDB_DB_NAME: "openedx_k8s"

    DEFAULT_FILE_STORAGE: 'storage.couchdb_storage.CouchDBStorage'
    COURSE_IMPORT_EXPORT_STORAGE: 'storage.couchdb_storage.CouchDBStorage'
    VIDEO_TRANSCRIPTS_STORAGE: 'storage.couchdb_storage.CouchDBStorage'
    GRADES_DOWNLOAD_STORAGE: 'storage.couchdb_storage.CouchDBStorage'
EOF

echo "Configuration files generated successfully!"
