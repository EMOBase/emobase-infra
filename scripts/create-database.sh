#!/usr/bin/env bash
# Create a database in the shared MySQL instance.
#
# Usage:
#   ./scripts/create-database.sh directus_tcas
#
# Per-species deployments need one Directus database each. The database name
# must match DIRECTUS_DB_DATABASE in that species checkout's .env.

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  echo "❌ .env not found. Run ./init.sh first." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1091
. ./.env
set +a

db="${1:-}"
if [[ -z "$db" ]]; then
  echo "Usage: $0 DATABASE" >&2
  exit 1
fi
[[ "$db" =~ ^[A-Za-z0-9_]+$ ]] || {
  echo "❌ Database names may only contain letters, digits and underscores." >&2
  exit 1
}

docker compose exec -T mysql \
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" \
  -e "CREATE DATABASE IF NOT EXISTS \`$db\`;"

echo "✅ Database '$db' is available."
