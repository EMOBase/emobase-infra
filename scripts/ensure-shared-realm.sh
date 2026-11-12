#!/usr/bin/env bash
# Create or update the shared Keycloak realm and allow one browser origin.
#
# Usage:
#   ./scripts/ensure-shared-realm.sh https://portal.example.org
#   ./scripts/ensure-shared-realm.sh https://tcas.example.org
#
# Run this after Keycloak is healthy. The portal setup uses the portal URL;
# a species-only server can use its first shared-realm species URL. Additional
# shared-realm origins can be added later with scripts/allow-origin.sh.
#
# Requires python3 on the Docker host and a running Keycloak container.

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 ORIGIN" >&2
  exit 1
fi

if [[ ! -f .env ]]; then
  echo "❌ .env not found. Run ./init.sh first." >&2
  exit 1
fi

read_env_value() {
  local file="$1" key="$2" value
  value=$(grep -E "^${key}=" "$file" | tail -n1 | cut -d= -f2- | tr -d '\r')
  value=${value#\"}; value=${value%\"}
  value=${value#\'}; value=${value%\'}
  printf '%s\n' "$value"
}

KEYCLOAK_REALM=$(read_env_value .env KEYCLOAK_REALM || true)
KEYCLOAK_REALM="${KEYCLOAK_REALM:-ibb}"
KEYCLOAK_CLIENT_ID=$(read_env_value .env KEYCLOAK_CLIENT_ID || true)
KEYCLOAK_CLIENT_ID="${KEYCLOAK_CLIENT_ID:-ibb-client}"
KEYCLOAK_CLIENT_SECRET=$(read_env_value .env KEYCLOAK_CLIENT_SECRET || true)
COCO_USERNAME=$(read_env_value .env COCO_USERNAME || true)
COCO_USERNAME="${COCO_USERNAME:-coco}"
COCO_PASSWORD=$(read_env_value .env COCO_PASSWORD || true)

[[ -n "$KEYCLOAK_CLIENT_SECRET" ]] || {
  echo "❌ .env has no KEYCLOAK_CLIENT_SECRET; re-run ./init.sh." >&2
  exit 1
}
[[ -n "$COCO_PASSWORD" ]] || {
  echo "❌ .env has no COCO_PASSWORD; re-run ./init.sh." >&2
  exit 1
}

exec ./scripts/create-realm.sh \
  --realm "$KEYCLOAK_REALM" \
  --origin "$1" \
  --client-id "$KEYCLOAK_CLIENT_ID" \
  --client-secret "$KEYCLOAK_CLIENT_SECRET" \
  --coco-username "$COCO_USERNAME" \
  --coco-password "$COCO_PASSWORD" \
  --keep-password \
  --quiet
