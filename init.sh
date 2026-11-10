#!/usr/bin/env bash
# Generate a .env file for the shared EMOBase infrastructure.
#
# Usage:
#   ./init.sh
#   ./init.sh --portal-server https://portal.example.org
#   ./init.sh --portal-dir ../emobase-portal-deploy --yes
#   ./init.sh --print > .env
#
# The script only writes .env. Starting the stack is documented in README.md.

set -eo pipefail

PASSWORD_LENGTH=24
FORCE=false
YES=false
PRINT=false
LOCAL=false
PORTAL_SERVER=
PORTAL_DIR=
INFRA_NETWORK=
KEYCLOAK_REALM=
KEYCLOAK_CLIENT_ID=
KEYCLOAK_PUBLIC_URL=
KEYCLOAK_INTERNAL_URL=
KEYCLOAK_HOST_PORT=

DEFAULT_PORTAL_SERVER="http://localhost:9080"
DEFAULT_INFRA_NETWORK="emobase-infra"
DEFAULT_PORTAL_DIR="../emobase-portal-deploy"
DEFAULT_KEYCLOAK_REALM="ibb"
DEFAULT_KEYCLOAK_CLIENT_ID="ibb-client"
DEFAULT_KEYCLOAK_HOST_PORT=8081
DEFAULT_KEYCLOAK_PUBLIC_URL="http://localhost:${DEFAULT_KEYCLOAK_HOST_PORT}/keycloak"
DEFAULT_KEYCLOAK_INTERNAL_URL="http://keycloak:8080/keycloak"

fatal() {
  >&2 echo "❌ $1"
  exit 1
}

generate_secret_key() {
  length="${1:-32}"
  local key # Needed to avoid pipefail
  key=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length" || true)
  echo "$key"
}

generate_password() {
  length="${1:-$PASSWORD_LENGTH}"

  upper=$(LC_ALL=C tr -dc 'A-Z' </dev/urandom | head -c1 || true)
  lower=$(LC_ALL=C tr -dc 'a-z' </dev/urandom | head -c1 || true)
  digit=$(LC_ALL=C tr -dc '0-9' </dev/urandom | head -c1 || true)
  # "+" is deliberately excluded: emobase-genomics builds a MySQL DSN from
  # these values, and golang-migrate url.QueryUnescape()s "+" into a space.
  symbol=$(LC_ALL=C tr -dc '_-=' </dev/urandom | head -c1 || true)

  rest_length=$((length - 4))
  rest=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$rest_length" || true)

  # Shuffle safely using awk (portable)
  printf "%s\n" "$upper$lower$digit$symbol$rest" | \
    awk 'BEGIN{srand()} {for(i=1;i<=length;i++) a[i]=substr($0,i,1)}
         END{for(i=1;i<=length;i++){j=int(rand()*length)+1; tmp=a[i]; a[i]=a[j]; a[j]=tmp}
             for(i=1;i<=length;i++) printf a[i]; printf "\n"}'
}

usage() {
  echo "Usage: $0 [-f|--force] [-p|--print] [-y|--yes] [--local] [--portal-server URL] [--portal-dir DIR] [--infra-network NAME] [--keycloak-public-url URL] [--keycloak-internal-url URL] [--keycloak-host-port PORT] [--keycloak-realm NAME] [--keycloak-client-id ID]"
  echo "  --portal-server     Public portal origin, if this server runs one"
  echo "                      (default: ${DEFAULT_PORTAL_SERVER})"
  echo "  --portal-dir        Portal checkout whose .env holds PUBLIC_SERVER"
  echo "                      (default: ${DEFAULT_PORTAL_DIR} when present)"
  echo "  --infra-network     Docker network shared with the deploy stacks (default: ${DEFAULT_INFRA_NETWORK})"
  echo "  --keycloak-public-url"
  echo "                      Browser-facing Keycloak base URL (default: ${DEFAULT_KEYCLOAK_PUBLIC_URL})"
  echo "  --keycloak-internal-url"
  echo "                      Container-facing Keycloak base URL on the shared network"
  echo "                      (default: ${DEFAULT_KEYCLOAK_INTERNAL_URL})"
  echo "  --keycloak-host-port"
  echo "                      Host port for Keycloak (default: ${DEFAULT_KEYCLOAK_HOST_PORT})"
  echo "  --keycloak-realm    Shared realm used by the portal and by species that"
  echo "                      reuse it (default: ${DEFAULT_KEYCLOAK_REALM})"
  echo "  --keycloak-client-id"
  echo "                      Client ID in the shared realm (default: ${DEFAULT_KEYCLOAK_CLIENT_ID})"
  echo "  --local             Use http://localhost:9080 as the portal URL"
  echo "  -f, --force         Overwrite an existing .env file"
  echo "  -y, --yes           Use defaults without prompting (secrets are still generated)"
  echo "  -p, --print         Print the generated .env to stdout instead of writing it"
  echo "  -h, --help          Show this help"
}

# Read a value from a dotenv file without sourcing it.
read_env_value() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 1
  local value
  value=$(grep -E "^${key}=" "$file" | tail -n1 | cut -d= -f2- | tr -d '\r') || return 1
  [[ -n "$value" ]] || return 1
  echo "$value"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --portal-server)
      PORTAL_SERVER="$2"
      shift 2
      ;;
    --portal-dir)
      PORTAL_DIR="$2"
      shift 2
      ;;
    --infra-network)
      INFRA_NETWORK="$2"
      shift 2
      ;;
    --keycloak-public-url)
      KEYCLOAK_PUBLIC_URL="$2"
      shift 2
      ;;
    --keycloak-internal-url)
      KEYCLOAK_INTERNAL_URL="$2"
      shift 2
      ;;
    --keycloak-host-port)
      KEYCLOAK_HOST_PORT="$2"
      shift 2
      ;;
    --keycloak-realm)
      KEYCLOAK_REALM="$2"
      shift 2
      ;;
    --keycloak-client-id)
      KEYCLOAK_CLIENT_ID="$2"
      shift 2
      ;;
    -f|--force)
      FORCE=true
      shift
      ;;
    -y|--yes)
      YES=true
      shift
      ;;
    --local)
      LOCAL=true
      shift
      ;;
    -p|--print)
      PRINT=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

if [[ "$PRINT" != true ]]; then
  if [[ -f .env ]] && [[ "$FORCE" != true ]]; then
    echo "⚠️  .env file already exists. Use -f to overwrite."
    exit 1
  fi
fi

# Ask for inputs
if [[ "$LOCAL" == true ]] && [[ -z "$PORTAL_SERVER" ]]; then
  PORTAL_SERVER="http://localhost:9080"
  >&2 echo "🏠 Local mode: using ${PORTAL_SERVER}"
fi

if [[ -z "$PORTAL_SERVER" ]]; then
  if [[ -z "$PORTAL_DIR" ]] && [[ -f "${DEFAULT_PORTAL_DIR}/.env" ]]; then
    PORTAL_DIR="$DEFAULT_PORTAL_DIR"
  fi

  if [[ -n "$PORTAL_DIR" ]]; then
    PORTAL_SERVER=$(read_env_value "${PORTAL_DIR}/.env" PUBLIC_SERVER || true)
    [[ -n "$PORTAL_SERVER" ]] \
      || fatal "Could not read PUBLIC_SERVER from ${PORTAL_DIR}/.env; pass --portal-server URL"
    >&2 echo "🔗 Using portal URL from ${PORTAL_DIR}/.env"
  elif [[ "$YES" == true ]]; then
    PORTAL_SERVER=${DEFAULT_PORTAL_SERVER}
  else
    read -rp "🌐 Public URL of the portal, if this server runs one [${DEFAULT_PORTAL_SERVER}]: " PORTAL_SERVER
    PORTAL_SERVER="${PORTAL_SERVER:-${DEFAULT_PORTAL_SERVER}}"
  fi
fi
PORTAL_SERVER="${PORTAL_SERVER%/}"
[[ -z "$PORTAL_SERVER" ]] && fatal "PORTAL_SERVER cannot be empty"

if [[ -n "$PORTAL_DIR" ]]; then
  portal_value=$(read_env_value "${PORTAL_DIR}/.env" PUBLIC_SERVER || true)
  if [[ -n "$portal_value" ]] && [[ "${portal_value%/}" != "$PORTAL_SERVER" ]]; then
    >&2 echo "⚠️  PORTAL_SERVER (${PORTAL_SERVER}) does not match ${PORTAL_DIR}/.env PUBLIC_SERVER (${portal_value})."
  fi
fi

if [[ -z "$INFRA_NETWORK" ]]; then
  if [[ "$YES" == true ]]; then
    INFRA_NETWORK=${DEFAULT_INFRA_NETWORK}
  else
    read -rp "🔌 Shared Docker network [${DEFAULT_INFRA_NETWORK}]: " INFRA_NETWORK
    INFRA_NETWORK="${INFRA_NETWORK:-${DEFAULT_INFRA_NETWORK}}"
  fi
fi
[[ "$INFRA_NETWORK" =~ ^[a-zA-Z0-9_.-]+$ ]] || fatal "EMOBASE_INFRA_NETWORK contains invalid characters"

if [[ -z "$KEYCLOAK_HOST_PORT" ]]; then
  KEYCLOAK_HOST_PORT=$DEFAULT_KEYCLOAK_HOST_PORT
fi
[[ "$KEYCLOAK_HOST_PORT" =~ ^[0-9]+$ ]] && (( 10#$KEYCLOAK_HOST_PORT >= 1 && 10#$KEYCLOAK_HOST_PORT <= 65535 )) \
  || fatal "KEYCLOAK_HOST_PORT must be a number between 1 and 65535"

if [[ -z "$KEYCLOAK_PUBLIC_URL" ]]; then
  default_public="http://localhost:${KEYCLOAK_HOST_PORT}/keycloak"
  if [[ "$LOCAL" == true ]] || [[ "$YES" == true ]]; then
    KEYCLOAK_PUBLIC_URL="$default_public"
    if [[ "$LOCAL" != true ]]; then
      >&2 echo "⚠️  KEYCLOAK_PUBLIC_URL defaults to ${KEYCLOAK_PUBLIC_URL}."
      >&2 echo "   Set --keycloak-public-url for a real server."
    fi
  else
    read -rp "🌐 Browser-facing Keycloak URL [${default_public}]: " KEYCLOAK_PUBLIC_URL
    KEYCLOAK_PUBLIC_URL="${KEYCLOAK_PUBLIC_URL:-$default_public}"
  fi
fi
KEYCLOAK_PUBLIC_URL="${KEYCLOAK_PUBLIC_URL%/}"
[[ "$KEYCLOAK_PUBLIC_URL" =~ ^https?://[^/]+ ]] \
  || fatal "KEYCLOAK_PUBLIC_URL must start with http:// or https://"
[[ "$KEYCLOAK_PUBLIC_URL" == */keycloak ]] \
  || fatal "KEYCLOAK_PUBLIC_URL must end with /keycloak"

KEYCLOAK_INTERNAL_URL="${KEYCLOAK_INTERNAL_URL:-$DEFAULT_KEYCLOAK_INTERNAL_URL}"
KEYCLOAK_INTERNAL_URL="${KEYCLOAK_INTERNAL_URL%/}"
[[ "$KEYCLOAK_INTERNAL_URL" =~ ^https?://[^/]+ ]] \
  || fatal "KEYCLOAK_INTERNAL_URL must start with http:// or https://"
[[ "$KEYCLOAK_INTERNAL_URL" == */keycloak ]] \
  || fatal "KEYCLOAK_INTERNAL_URL must end with /keycloak"

KEYCLOAK_REALM="${KEYCLOAK_REALM:-$DEFAULT_KEYCLOAK_REALM}"
KEYCLOAK_CLIENT_ID="${KEYCLOAK_CLIENT_ID:-$DEFAULT_KEYCLOAK_CLIENT_ID}"
[[ "$KEYCLOAK_REALM" =~ ^[a-zA-Z0-9_.-]+$ ]] || fatal "KEYCLOAK_REALM contains invalid characters"
[[ "$KEYCLOAK_CLIENT_ID" =~ ^[a-zA-Z0-9_.-]+$ ]] || fatal "KEYCLOAK_CLIENT_ID contains invalid characters"

ENV_CONTENT="# ── Deployment ──────────────────────────────────────────────────────────────
# Browser-facing Keycloak base URL, without a trailing slash. Put a TLS
# reverse proxy in front in production and point it at 127.0.0.1:${KEYCLOAK_HOST_PORT}.
KEYCLOAK_PUBLIC_URL=${KEYCLOAK_PUBLIC_URL}
KEYCLOAK_INTERNAL_URL=${KEYCLOAK_INTERNAL_URL}
KEYCLOAK_HOST_PORT=${KEYCLOAK_HOST_PORT}

# Public origin of the portal, if this server runs one. Used for the initial
# realm redirect URI; add other origins with scripts/allow-origin.sh.
PORTAL_PUBLIC_SERVER=${PORTAL_SERVER}

# Name of the Docker network shared with the local portal and species stacks.
# Keep the same value in the three .env files on this server.
EMOBASE_INFRA_NETWORK=${INFRA_NETWORK}

# ── Keycloak shared realm ───────────────────────────────────────────────────
# The portal always uses this realm. A species deployment can reuse it (shared
# administration) or create a dedicated realm during its init.sh.
KEYCLOAK_REALM=${KEYCLOAK_REALM}
KEYCLOAK_CLIENT_ID=${KEYCLOAK_CLIENT_ID}

# ── Secrets ─────────────────────────────────────────────────────────────────
# Generated by init.sh. Keep this file private.
#
# MYSQL_ROOT_PASSWORD and KEYCLOAK_CLIENT_SECRET must be copied into every
# deploy stack's .env. The deploy stacks' init.sh reads them from this file.
MYSQL_ROOT_PASSWORD=$(generate_password)
KEYCLOAK_CLIENT_SECRET=$(generate_secret_key 32)

# Keycloak admin console credentials.
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=$(generate_password)

# Initial realm user imported by Keycloak. The password is temporary and must
# be changed on first login.
COCO_USERNAME=coco
COCO_PASSWORD=$(generate_password)

# ── Keycloak runtime ────────────────────────────────────────────────────────
KEYCLOAK_JAVA_OPTS=\"-Xms256m -Xmx768m\""

if [[ "$PRINT" == true ]]; then
  echo "$ENV_CONTENT"
  exit 0
fi

printf '%s\n' "$ENV_CONTENT" > .env
chmod 600 .env

>&2 echo "✅ .env file generated successfully"
>&2 echo "   Portal URL:     ${PORTAL_SERVER}"
>&2 echo "   Keycloak URL:   ${KEYCLOAK_PUBLIC_URL}"
>&2 echo "   Keycloak port:  ${KEYCLOAK_HOST_PORT}"
>&2 echo "   Infra network:  ${INFRA_NETWORK}"
>&2 echo "   Shared realm:   ${KEYCLOAK_REALM} (${KEYCLOAK_CLIENT_ID})"
>&2 echo
>&2 echo "Next:"
>&2 echo "  1. Review .env (secrets, network, Keycloak heap)."
>&2 echo "  2. docker compose up -d --wait"
>&2 echo "  3. Deploy the portal with emobase-portal-deploy/init.sh."
>&2 echo "  4. For each species, create its Directus database and register its URL:"
>&2 echo "       ./scripts/create-database.sh directus_<species>"
>&2 echo "       ./scripts/allow-origin.sh https://<species>.example.org"
