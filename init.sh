#!/usr/bin/env bash
# Generate a .env file for the shared EMOBase infrastructure.
#
# Usage:
#   ./init.sh
#   ./init.sh --keycloak-public-url https://auth.example.org/keycloak --yes
#   ./init.sh --print > .env
#
# The script only writes .env. Starting the stack is documented in README.md.

set -eo pipefail

PASSWORD_LENGTH=24
FORCE=false
YES=false
PRINT=false
LOCAL=false
INFRA_NETWORK=
KEYCLOAK_PUBLIC_URL=
KEYCLOAK_INTERNAL_URL=
KEYCLOAK_HOST_PORT=

DEFAULT_INFRA_NETWORK="emobase-infra"
DEFAULT_KEYCLOAK_HOST_PORT=8081
DEFAULT_KEYCLOAK_INTERNAL_URL="http://keycloak:8080/keycloak"

fatal() {
  >&2 echo "❌ $1"
  exit 1
}

# ask VAR "label" "default"
# Keeps an explicit flag or discovered value; otherwise asks with a default.
# --yes uses the default without prompting. A non-terminal without --yes aborts
# instead of silently generating a configuration nobody confirmed.
ask() {
  local var="$1" label="$2" default="$3" value
  [[ -n "${!var:-}" ]] && return 0
  if [[ "$YES" == true ]]; then
    printf -v "$var" '%s' "$default"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    fatal "Cannot ask for ${label}: stdin is not a terminal. Pass --yes or the matching option."
  fi
  if [[ -n "$default" ]]; then
    read -rp "${label} [${default}]: " value
  else
    read -rp "${label}: " value
  fi
  printf -v "$var" '%s' "${value:-$default}"
}

# detect_host_ip prints the address used for the default route. It is the
# server's reachable interface address, not necessarily its internet-facing
# address when the host is behind NAT.
detect_host_ip() {
  local ip
  ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{
    for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }
  }')
  if [[ -z "$ip" ]]; then
    ip=$(hostname -I 2>/dev/null | awk '{
      for (i = 1; i <= NF; i++) if ($i !~ /^127\./) { print $i; exit }
    }')
  fi
  if [[ -z "$ip" ]] && command -v ipconfig >/dev/null 2>&1; then
    ip=$(ipconfig getifaddr en0 2>/dev/null || true)
  fi
  printf '%s\n' "$ip"
}

is_private_ip() {
  [[ "$1" =~ ^10\. ]] || [[ "$1" =~ ^192\.168\. ]] || \
    [[ "$1" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]]
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
  echo "Usage: $0 [-f|--force] [-p|--print] [-y|--yes] [--local] [--infra-network NAME] [--keycloak-public-url URL] [--keycloak-internal-url URL] [--keycloak-host-port PORT]"
  echo "Without options, asks each value in order and shows its default."
  echo "  --infra-network     Docker network shared with the deploy stacks (default: ${DEFAULT_INFRA_NETWORK})"
  echo "  --keycloak-public-url"
  echo "                      Browser-facing Keycloak base URL"
  echo "                      (default: http://localhost:<keycloak-host-port>/keycloak)"
  echo "  --keycloak-internal-url"
  echo "                      Container-facing Keycloak base URL on the shared network"
  echo "                      (default: ${DEFAULT_KEYCLOAK_INTERNAL_URL})"
  echo "  --keycloak-host-port"
  echo "                      Host port for Keycloak (default: ${DEFAULT_KEYCLOAK_HOST_PORT})"
  echo "  --local             Use localhost URLs for a same-machine trial"
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
ask INFRA_NETWORK "🔌 Shared Docker network" "$DEFAULT_INFRA_NETWORK"
[[ "$INFRA_NETWORK" =~ ^[a-zA-Z0-9_.-]+$ ]] || fatal "EMOBASE_INFRA_NETWORK contains invalid characters"

ask KEYCLOAK_HOST_PORT "🔌 Host port for Keycloak" "$DEFAULT_KEYCLOAK_HOST_PORT"
[[ "$KEYCLOAK_HOST_PORT" =~ ^[0-9]+$ ]] && (( 10#$KEYCLOAK_HOST_PORT >= 1 && 10#$KEYCLOAK_HOST_PORT <= 65535 )) \
  || fatal "KEYCLOAK_HOST_PORT must be a number between 1 and 65535"

default_public="http://localhost:${KEYCLOAK_HOST_PORT}/keycloak"
if [[ "$LOCAL" != true ]]; then
  host_ip=$(detect_host_ip)
  if [[ -n "$host_ip" ]]; then
    default_public="http://${host_ip}:${KEYCLOAK_HOST_PORT}/keycloak"
    if [[ -z "$KEYCLOAK_PUBLIC_URL" ]] && is_private_ip "$host_ip"; then
      >&2 echo "⚠️  Detected host address ${host_ip}; use the public IP or domain if this server is behind NAT."
    fi
  fi
fi
if [[ "$LOCAL" == true ]]; then
  KEYCLOAK_PUBLIC_URL="${KEYCLOAK_PUBLIC_URL:-$default_public}"
fi
ask KEYCLOAK_PUBLIC_URL "🌐 Browser-facing Keycloak URL" "$default_public"
if [[ "$KEYCLOAK_PUBLIC_URL" == *localhost* ]] && [[ "$LOCAL" != true ]]; then
  >&2 echo "⚠️  KEYCLOAK_PUBLIC_URL points at localhost."
  >&2 echo "   Set --keycloak-public-url for a real server."
fi
KEYCLOAK_PUBLIC_URL="${KEYCLOAK_PUBLIC_URL%/}"
[[ "$KEYCLOAK_PUBLIC_URL" =~ ^https?://[^/]+ ]] \
  || fatal "KEYCLOAK_PUBLIC_URL must start with http:// or https://"
[[ "$KEYCLOAK_PUBLIC_URL" == */keycloak ]] \
  || fatal "KEYCLOAK_PUBLIC_URL must end with /keycloak"

ask KEYCLOAK_INTERNAL_URL "🔗 Container-facing Keycloak URL" "$DEFAULT_KEYCLOAK_INTERNAL_URL"
KEYCLOAK_INTERNAL_URL="${KEYCLOAK_INTERNAL_URL%/}"
[[ "$KEYCLOAK_INTERNAL_URL" =~ ^https?://[^/]+ ]] \
  || fatal "KEYCLOAK_INTERNAL_URL must start with http:// or https://"
[[ "$KEYCLOAK_INTERNAL_URL" == */keycloak ]] \
  || fatal "KEYCLOAK_INTERNAL_URL must end with /keycloak"

ENV_CONTENT="# ── Deployment ──────────────────────────────────────────────────────────────
# Browser-facing Keycloak base URL, without a trailing slash. Put a TLS
# reverse proxy in front in production and point it at 127.0.0.1:${KEYCLOAK_HOST_PORT}.
KEYCLOAK_PUBLIC_URL=${KEYCLOAK_PUBLIC_URL}
KEYCLOAK_INTERNAL_URL=${KEYCLOAK_INTERNAL_URL}
KEYCLOAK_HOST_PORT=${KEYCLOAK_HOST_PORT}

# Name of the Docker network shared with the local portal and species stacks.
# Keep the same value in the three .env files on this server.
EMOBASE_INFRA_NETWORK=${INFRA_NETWORK}

# ── Secrets ─────────────────────────────────────────────────────────────────
# Generated by init.sh. Keep this file private.
#
# MYSQL_ROOT_PASSWORD is copied into the deploy stacks' .env. Keycloak realms
# and their client/seed secrets are owned by the portal and species stacks.
MYSQL_ROOT_PASSWORD=$(generate_password)

# Keycloak admin console credentials.
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=$(generate_password)

# ── Keycloak runtime ────────────────────────────────────────────────────────
KEYCLOAK_JAVA_OPTS=\"-Xms256m -Xmx768m\""

if [[ "$PRINT" == true ]]; then
  echo "$ENV_CONTENT"
  exit 0
fi

printf '%s\n' "$ENV_CONTENT" > .env
chmod 600 .env

>&2 echo "✅ .env file generated successfully"
>&2 echo "   Keycloak URL:   ${KEYCLOAK_PUBLIC_URL}"
>&2 echo "   Keycloak port:  ${KEYCLOAK_HOST_PORT}"
>&2 echo "   Infra network:  ${INFRA_NETWORK}"
>&2 echo
>&2 echo "Next:"
>&2 echo "  1. Review .env (secrets, network, Keycloak heap)."
>&2 echo "  2. docker compose up -d --wait"
>&2 echo "  3. Deploy the portal with emobase-portal-deploy/init.sh."
>&2 echo "     The portal creates and owns its Keycloak realm."
>&2 echo "  4. For each species, run emobase-deploy/init.sh."
>&2 echo "     A species can join an existing realm or create its own."
