#!/usr/bin/env bash
# Drop a database from the shared MySQL instance.
#
# Usage:
#   ./scripts/drop-database.sh directus_tcas
#   ./scripts/drop-database.sh --yes directus_tcas
#
# This permanently deletes the database. The --yes flag skips the confirmation.

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

MYSQL_ROOT_PASSWORD=$(read_env_value .env MYSQL_ROOT_PASSWORD || true)
[[ -n "$MYSQL_ROOT_PASSWORD" ]] || {
  echo "❌ .env has no MYSQL_ROOT_PASSWORD; re-run ./init.sh." >&2
  exit 1
}

assume_yes=false
if [[ "${1:-}" == "--yes" ]]; then
  assume_yes=true
  shift
fi

db="${1:-}"
if [[ -z "$db" ]]; then
  echo "Usage: $0 [--yes] DATABASE" >&2
  exit 1
fi
[[ "$db" =~ ^[A-Za-z0-9_]+$ ]] || {
  echo "❌ Database names may only contain letters, digits and underscores." >&2
  exit 1
}

if [[ "$assume_yes" != true ]]; then
  read -rp "Drop database '$db'? This cannot be undone. [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || {
    echo "Cancelled."
    exit 1
  }
fi

docker compose exec -T mysql \
  mysql -uroot -p"$MYSQL_ROOT_PASSWORD" \
  -e "DROP DATABASE IF EXISTS \`$db\`;"

echo "✅ Database '$db' dropped."
