#!/bin/bash
# =============================================================================
# Keycloak Bulk User Creation Script
# =============================================================================
# Automates adding multiple users to the Keycloak 'iqgeo' realm using the 
# Keycloak Admin CLI (kcadm.sh) running inside the Keycloak pod on OpenShift.
#
# Usage:
#   ./keycloak-add-users.sh [--from-csv users.csv]
#
# Without arguments, it creates a default set of demo users.
# With --from-csv, it reads users from a CSV file with format:
#   username,email,firstName,lastName,password,role
#
# Prerequisites:
#   - oc CLI logged in to the OpenShift cluster
#   - Keycloak pod running in the target namespace
# =============================================================================

set -euo pipefail

NAMESPACE="${NAMESPACE:-suzuki3182-dev}"
REALM="${REALM:-iqgeo}"
KC_ADMIN="${KC_ADMIN:-admin}"
KC_ADMIN_PASS="${KC_ADMIN_PASS:-admin}"
KC_POD=$(oc get pods -n "$NAMESPACE" -l app=keycloak -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || \
         oc get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep keycloak | awk '{print $1}' | head -1)

if [[ -z "$KC_POD" ]]; then
    echo "ERROR: Could not find Keycloak pod in namespace $NAMESPACE"
    exit 1
fi

echo "=== Keycloak Bulk User Creator ==="
echo "Namespace: $NAMESPACE"
echo "Realm:     $REALM"
echo "Pod:       $KC_POD"
echo ""

# Function to run kcadm commands in the pod
# Use --config /tmp/kcadm.config since /.keycloak is not writable (non-root)
KCADM_CONFIG="/tmp/kcadm.config"
kcadm() {
    oc exec "$KC_POD" -n "$NAMESPACE" -- /opt/keycloak/bin/kcadm.sh "$@" --config "$KCADM_CONFIG" 2>&1
}

# Authenticate to Keycloak admin
echo "Authenticating to Keycloak as '$KC_ADMIN'..."
kcadm config credentials \
    --server http://localhost:8080 \
    --realm master \
    --user "$KC_ADMIN" \
    --password "$KC_ADMIN_PASS"
echo "✓ Authenticated successfully"
echo ""

# Function to create a single user
create_user() {
    local username="$1"
    local email="$2"
    local first_name="$3"
    local last_name="$4"
    local password="$5"
    local role="${6:-}"

    echo -n "Creating user '$username'... "
    
    # Check if user already exists (by username or email)
    local existing
    existing=$(kcadm get users -r "$REALM" -q "username=$username" --fields id 2>/dev/null || echo "")
    if echo "$existing" | grep -q '"id"'; then
        echo "SKIPPED (already exists)"
        return 0
    fi
    local existing_email
    existing_email=$(kcadm get users -r "$REALM" -q "email=$email" --fields id 2>/dev/null || echo "")
    if echo "$existing_email" | grep -q '"id"'; then
        echo "SKIPPED (email already exists)"
        return 0
    fi

    # Create the user
    local create_result
    create_result=$(kcadm create users -r "$REALM" \
        -s "username=$username" \
        -s "email=$email" \
        -s "firstName=$first_name" \
        -s "lastName=$last_name" \
        -s "enabled=true" \
        -s "emailVerified=true" 2>&1) || {
        echo "FAILED: $create_result"
        return 0
    }

    # Set password (not temporary)
    kcadm set-password -r "$REALM" \
        --username "$username" \
        --new-password "$password"

    # Assign role if specified
    if [[ -n "$role" ]]; then
        # Try to assign realm role
        kcadm add-roles -r "$REALM" \
            --uname "$username" \
            --rolename "$role" 2>/dev/null || \
        echo "  (warning: role '$role' not found, skipping role assignment)"
    fi

    echo "✓ Created"
}

# Check if CSV file provided
if [[ "${1:-}" == "--from-csv" ]] && [[ -n "${2:-}" ]]; then
    CSV_FILE="$2"
    if [[ ! -f "$CSV_FILE" ]]; then
        echo "ERROR: CSV file '$CSV_FILE' not found"
        exit 1
    fi
    
    echo "Reading users from: $CSV_FILE"
    echo "---"
    
    # Skip header line, read CSV
    tail -n +2 "$CSV_FILE" | while IFS=',' read -r username email first_name last_name password role; do
        # Trim whitespace
        username=$(echo "$username" | xargs)
        email=$(echo "$email" | xargs)
        first_name=$(echo "$first_name" | xargs)
        last_name=$(echo "$last_name" | xargs)
        password=$(echo "$password" | xargs)
        role=$(echo "$role" | xargs)
        
        if [[ -n "$username" ]]; then
            create_user "$username" "$email" "$first_name" "$last_name" "$password" "$role"
        fi
    done

else
    # Default demo users
    echo "Creating default demo users..."
    echo "---"
    
    create_user "iqgeo_admin"  "iqgeo_admin@iqgeo.local" "IQGeo"   "Admin"    "IQGeo2026!"  ""
    create_user "operator1"    "operator1@iqgeo.local"    "Operator" "One"     "IQGeo2026!"  ""
    create_user "operator2"    "operator2@iqgeo.local"    "Operator" "Two"     "IQGeo2026!"  ""
    create_user "viewer1"      "viewer1@iqgeo.local"      "Viewer"   "One"     "IQGeo2026!"  ""
    create_user "engineer1"    "engineer1@iqgeo.local"    "Field"    "Engineer" "IQGeo2026!" ""
fi

echo ""
echo "=== Done ==="
echo ""
echo "Users in realm '$REALM':"
kcadm get users -r "$REALM" --fields "username,email,enabled" 2>/dev/null || echo "(could not list users)"
