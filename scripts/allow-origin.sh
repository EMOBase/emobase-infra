#!/usr/bin/env bash
# Allow one or more public origins to sign in through the shared Keycloak.
#
# Usage:
#   ./scripts/allow-origin.sh https://tcas.example.org
#   ./scripts/allow-origin.sh https://tcas.example.org https://dmel.example.org
#
# The portal origin is imported with the realm automatically. Every species
# site must be registered here once, before users sign in on that site. The
# script is idempotent: running it again with the same origin changes nothing.
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

set -a
# shellcheck disable=SC1091
. ./.env
set +a

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
  --server http://localhost:8080/ibb/keycloak \
  --realm master \
  --user "$KEYCLOAK_ADMIN" \
  --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null

client_id=$(kcadm get clients -r ibb -q clientId=ibb-client --fields id --format csv --noquotes \
  | tail -n1 | tr -d '\r')
if [[ -z "$client_id" ]]; then
  echo "❌ Client 'ibb-client' was not found in realm 'ibb'." >&2
  exit 1
fi

current=$(kcadm get "clients/$client_id" -r ibb --fields redirectUris,webOrigins --format json)

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

kcadm update "clients/$client_id" -r ibb \
  -s "redirectUris=$redirects" \
  -s "webOrigins=$origins"

echo "✅ Keycloak now accepts sign-in redirects from:"
for origin in "$@"; do
  echo "   - ${origin%/}"
done
