#!/usr/bin/env bash
# Delete a Keycloak realm owned by an EMOBase checkout.
#
# Usage:
#   ./scripts/delete-realm.sh --yes emobase-tcas
#
# This deletes the realm's users, clients, roles and sessions. It is intended
# for `emobase prune`, after the owning checkout is removed.

set -euo pipefail

cd "$(dirname "$0")/.."

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

assume_yes=false
if [[ "${1:-}" == "--yes" ]]; then
  assume_yes=true
  shift
fi

realm="${1:-}"
if [[ -z "$realm" ]]; then
  echo "Usage: $0 [--yes] REALM" >&2
  exit 1
fi
[[ "$realm" != "master" ]] || {
  echo "❌ Refusing to delete the master realm." >&2
  exit 1
}
[[ "$realm" =~ ^[a-zA-Z0-9_.-]+$ ]] || {
  echo "❌ Invalid realm name '$realm'." >&2
  exit 1
}

KEYCLOAK_ADMIN=$(read_env_value .env KEYCLOAK_ADMIN || true)
KEYCLOAK_ADMIN="${KEYCLOAK_ADMIN:-admin}"
KEYCLOAK_ADMIN_PASSWORD=$(read_env_value .env KEYCLOAK_ADMIN_PASSWORD || true)
[[ -n "$KEYCLOAK_ADMIN_PASSWORD" ]] || {
  echo "❌ .env has no KEYCLOAK_ADMIN_PASSWORD; re-run ./init.sh." >&2
  exit 1
}

kcadm() {
  docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@"
}

if ! docker compose ps --status running --services 2>/dev/null | grep -qx keycloak; then
  echo "❌ The Keycloak container is not running. Start it with:" >&2
  echo "   docker compose up -d --wait" >&2
  exit 1
fi

kcadm config credentials \
  --server http://localhost:8080/keycloak \
  --realm master \
  --user "$KEYCLOAK_ADMIN" \
  --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null

if ! kcadm get "realms/$realm" >/dev/null 2>&1; then
  echo "✅ Realm '$realm' is already absent."
  exit 0
fi

if [[ "$assume_yes" != true ]]; then
  if [[ ! -t 0 ]]; then
    echo "❌ Refusing to delete '$realm' without --yes (stdin is not a terminal)." >&2
    exit 1
  fi
  read -rp "Delete realm '$realm' and all its users? This cannot be undone. [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || {
    echo "Cancelled."
    exit 1
  }
fi

kcadm delete "realms/$realm" -r master >/dev/null
echo "✅ Realm '$realm' deleted."
