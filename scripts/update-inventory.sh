#!/usr/bin/env bash
#
# Pulls the current floating IP from Terraform's output and writes it into
# ansible/inventory.ini. The IP changes every time the instance is
# recreated, so inventory.ini can't just be hand-edited once and forgotten.
set -euo pipefail

# Resolve paths relative to this script's own location, not the caller's
# current directory, so it works no matter where it's run from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
INVENTORY_FILE="$PROJECT_ROOT/ansible/inventory.ini"

# Run terraform output from inside terraform/ (state lives there), but don't
# permanently change the caller's shell directory.
SERVER_IP="$(cd "$TERRAFORM_DIR" && terraform output -raw server_public_ip 2>/dev/null)" || {
  echo "Error: could not read 'server_public_ip' from terraform output." >&2
  echo "Tip: source ~/.cumulus-secrets/project-openrc.sh first" >&2
  exit 1
}

cat > "$INVENTORY_FILE" <<EOF
[webserver]
$SERVER_IP
EOF

echo "Inventory updated: $SERVER_IP"
