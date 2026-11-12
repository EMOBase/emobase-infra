#!/usr/bin/env bash
# Allow one or more public origins to sign in through the shared Keycloak realm.
#
# Usage:
#   ./scripts/allow-origin.sh https://tcas.example.org
#   ./scripts/allow-origin.sh https://tcas.example.org https://dmel.example.org
#
# Use this for species that reuse the portal's shared realm. A species with a
# dedicated realm is configured by create-realm.sh instead.
#
# The shared realm must exist first; ensure-shared-realm.sh creates it with the
# portal or first species origin. Every additional shared-realm origin must be
# registered here once, before users sign in on that site. The script is
# idempotent.
#
# Requires python3 on the Docker host and a running Keycloak container.

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  echo "❌ .env not found. Run ./init.sh first." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "❌ python3 is required to update the Keycloak client." >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 ORIGIN [ORIGIN...]" >&2
  exit 1
fi

read_env_value() {
  local file="$1" key="$2" value
  value=$(grep -E "^${key}=" "$file" | tail -n1 | cut -d= -f2- | tr -d '\r')
  value=${value#\"}; value=${value%\"}
  value=${value#\'}; value=${value%\'}
  printf '%s\n' "$value"
}

KEYCLOAK_ADMIN=$(read_env_value .env KEYCLOAK_ADMIN || true)
KEYCLOAK_ADMIN="${KEYCLOAK_ADMIN:-admin}"
KEYCLOAK_ADMIN_PASSWORD=$(read_env_value .env KEYCLOAK_ADMIN_PASSWORD || true)
[[ -n "$KEYCLOAK_ADMIN_PASSWORD" ]] || {
  echo "❌ .env has no KEYCLOAK_ADMIN_PASSWORD; re-run ./init.sh." >&2
  exit 1
}
KEYCLOAK_REALM=$(read_env_value .env KEYCLOAK_REALM || true)
KEYCLOAK_REALM="${KEYCLOAK_REALM:-ibb}"
KEYCLOAK_CLIENT_ID=$(read_env_value .env KEYCLOAK_CLIENT_ID || true)
KEYCLOAK_CLIENT_ID="${KEYCLOAK_CLIENT_ID:-ibb-client}"

kcadm() {
  docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh "$@"
}

# Fail early with a clear message when the stack is not running.
if ! docker compose ps --status running --services 2>/dev/null | grep -qx keycloak; then
  echo "❌ The shared Keycloak container is not running. Start it with:" >&2
  echo "   docker compose up -d --wait" >&2
  exit 1
fi

kcadm config credentials \
  --server http://localhost:8080/keycloak \
  --realm master \
  --user "$KEYCLOAK_ADMIN" \
  --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null

client_id=$(kcadm get clients -r "$KEYCLOAK_REALM" -q clientId="$KEYCLOAK_CLIENT_ID" --fields id --format csv --noquotes \
  | tail -n1 | tr -d '\r')
if [[ -z "$client_id" ]]; then
  echo "❌ Client '${KEYCLOAK_CLIENT_ID}' was not found in realm '${KEYCLOAK_REALM}'." >&2
  exit 1
fi

current=$(kcadm get "clients/$client_id" -r "$KEYCLOAK_REALM" --fields redirectUris,webOrigins --format json)

{
  read -r redirects
  read -r origins
} < <(printf '%s' "$current" | python3 -c '
import json, sys

data = json.load(sys.stdin)
redirects = data.get("redirectUris") or []
origins = data.get("webOrigins") or []

for origin in sys.argv[1:]:
    origin = origin.rstrip("/")
    redirect = origin + "/*"
    if redirect not in redirects:
        redirects.append(redirect)
    if origin not in origins:
        origins.append(origin)

print(json.dumps(redirects))
print(json.dumps(origins))
' "$@")

kcadm update "clients/$client_id" -r "$KEYCLOAK_REALM" \
  -s "redirectUris=$redirects" \
  -s "webOrigins=$origins"

echo "✅ Realm '${KEYCLOAK_REALM}' now accepts sign-in redirects from:"
for origin in "$@"; do
  echo "   - ${origin%/}"
done
