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

DEFAULT_PORTAL_SERVER="http://localhost:9080"
DEFAULT_INFRA_NETWORK="emobase-infra"
DEFAULT_PORTAL_DIR="../emobase-portal-deploy"

fatal() {
  >&2 echo "❌ $1"
  exit 1
}

generate_secret_key() {
  length="${1:-32}"
  local key # Needed to avoid pipefail
  key=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length")
  echo "$key"
}

generate_password() {
  length="${1:-$PASSWORD_LENGTH}"

  upper=$(LC_ALL=C tr -dc 'A-Z' </dev/urandom | head -c1)
  lower=$(LC_ALL=C tr -dc 'a-z' </dev/urandom | head -c1)
  digit=$(LC_ALL=C tr -dc '0-9' </dev/urandom | head -c1)
  # "+" is deliberately excluded: emobase-genomics builds a MySQL DSN from
  # these values, and golang-migrate url.QueryUnescape()s "+" into a space.
  symbol=$(LC_ALL=C tr -dc '_-=' </dev/urandom | head -c1)

  rest_length=$((length - 4))
  rest=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$rest_length")

  # Shuffle safely using awk (portable)
  printf "%s\n" "$upper$lower$digit$symbol$rest" | \
    awk 'BEGIN{srand()} {for(i=1;i<=length;i++) a[i]=substr($0,i,1)}
         END{for(i=1;i<=length;i++){j=int(rand()*length)+1; tmp=a[i]; a[i]=a[j]; a[j]=tmp}
             for(i=1;i<=length;i++) printf a[i]; printf "\n"}'
}

usage() {
  echo "Usage: $0 [-f|--force] [-p|--print] [-y|--yes] [--local] [--portal-server URL] [--portal-dir DIR] [--infra-network NAME]"
  echo "  --portal-server     Public portal URL, also used as the Keycloak issuer (default: ${DEFAULT_PORTAL_SERVER})"
  echo "  --portal-dir        Portal checkout whose .env holds PUBLIC_SERVER"
  echo "                      (default: ${DEFAULT_PORTAL_DIR} when present)"
  echo "  --infra-network     Docker network shared with the deploy stacks (default: ${DEFAULT_INFRA_NETWORK})"
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
    read -rp "🌐 Public URL of the portal (Keycloak is proxied there) [${DEFAULT_PORTAL_SERVER}]: " PORTAL_SERVER
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

ENV_CONTENT="# ── Deployment ──────────────────────────────────────────────────────────────
# Public origin of the portal deployment. Keycloak is proxied by the portal
# nginx under <PORTAL_PUBLIC_SERVER>/ibb/keycloak/, so this must be exactly the
# portal's PUBLIC_SERVER (same scheme, host and port, no trailing slash).
PORTAL_PUBLIC_SERVER=${PORTAL_SERVER}

# Name of the Docker network shared with emobase-portal-deploy and
# emobase-deploy. Keep the same value in all three .env files.
EMOBASE_INFRA_NETWORK=${INFRA_NETWORK}

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
>&2 echo "   Infra network:  ${INFRA_NETWORK}"
>&2 echo
>&2 echo "Next:"
>&2 echo "  1. Review .env (secrets, network, Keycloak heap)."
>&2 echo "  2. docker compose up -d --wait"
>&2 echo "  3. Deploy the portal with emobase-portal-deploy/init.sh."
>&2 echo "  4. For each species, create its Directus database and register its URL:"
>&2 echo "       ./scripts/create-database.sh directus_<species>"
>&2 echo "       ./scripts/allow-origin.sh https://<species>.example.org"
