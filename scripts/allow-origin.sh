#!/usr/bin/env bash
# Allow one or more public origins to sign in through an existing Keycloak realm.
#
# Usage:
#   ./scripts/allow-origin.sh --realm emobase-portal --client-id emobase-portal-client \
#     https://tcas.example.org
#   ./scripts/allow-origin.sh --realm emobase-tcas --client-id emobase-tcas-client \
#     https://tcas.example.org https://dmel.example.org
#
# The realm/client and their credentials belong to the portal or species that
# created them. This helper only adds origins to an existing client.
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

read_env_value() {
  local file="$1" key="$2" value
  value=$(grep -E "^${key}=" "$file" | tail -n1 | cut -d= -f2- | tr -d '\r')
  value=${value#\"}; value=${value%\"}
  value=${value#\'}; value=${value%\'}
  printf '%s\n' "$value"
}

usage() {
  echo "Usage: $0 --realm REALM --client-id ID ORIGIN [ORIGIN...]" >&2
}

REALM=
CLIENT_ID=
ORIGINS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --realm)
      REALM="$2"
      shift 2
      ;;
    --client-id)
      CLIENT_ID="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      usage
      exit 1
      ;;
    *)
      ORIGINS+=("$1")
      shift
      ;;
  esac
done

[[ -n "$REALM" ]] || { usage; exit 1; }
[[ -n "$CLIENT_ID" ]] || { usage; exit 1; }
[[ ${#ORIGINS[@]} -gt 0 ]] || { usage; exit 1; }
[[ "$REALM" =~ ^[a-zA-Z0-9_.-]+$ ]] || {
  echo "❌ Invalid realm name '$REALM'." >&2
  exit 1
}
[[ "$CLIENT_ID" =~ ^[a-zA-Z0-9_.-]+$ ]] || {
  echo "❌ Invalid client ID '$CLIENT_ID'." >&2
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

client_id=$(kcadm get clients -r "$REALM" -q clientId="$CLIENT_ID" --fields id --format csv --noquotes \
  | tail -n1 | tr -d '\r')
if [[ -z "$client_id" ]]; then
  echo "❌ Client '${CLIENT_ID}' was not found in realm '${REALM}'." >&2
  exit 1
fi

current=$(kcadm get "clients/$client_id" -r "$REALM" --fields redirectUris,webOrigins --format json)

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
' "${ORIGINS[@]}")

kcadm update "clients/$client_id" -r "$REALM" \
  -s "redirectUris=$redirects" \
  -s "webOrigins=$origins"

echo "✅ Realm '${REALM}' now accepts sign-in redirects from:"
for origin in "${ORIGINS[@]}"; do
  echo "   - ${origin%/}"
done
