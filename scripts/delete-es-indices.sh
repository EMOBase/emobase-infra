#!/usr/bin/env bash
# Delete every Elasticsearch index owned by one stack prefix.
#
# Usage:
#   ./scripts/delete-es-indices.sh tcas
#   ./scripts/delete-es-indices.sh --yes tcas
#
# Only indices named "<prefix>-*" are matched. Other stacks' indices and the
# portal's "genomics-*" indices are left untouched. The prefix is the value of
# EMOBASE_ES_INDEX_PREFIX in a species .env.

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  echo "❌ .env not found. Run ./init.sh first." >&2
  exit 1
fi

assume_yes=false
if [[ "${1:-}" == "--yes" ]]; then
  assume_yes=true
  shift
fi

prefix="${1:-}"
if [[ -z "$prefix" ]]; then
  echo "Usage: $0 [--yes] PREFIX" >&2
  exit 1
fi
[[ "$prefix" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || {
  echo "❌ Invalid index prefix '$prefix': use lowercase letters, digits, '_' or '-'." >&2
  exit 1
}
[[ "$prefix" != "genomics" ]] || {
  echo "❌ Refusing to delete the portal prefix 'genomics'." >&2
  exit 1
}

if ! docker compose ps --status running --services 2>/dev/null | grep -qx elasticsearch; then
  echo "❌ The Elasticsearch container is not running. Start it with:" >&2
  echo "   docker compose up -d --wait" >&2
  exit 1
fi

es() {
  docker compose exec -T elasticsearch curl -fsS "$@" </dev/null
}

indices=$(es "http://localhost:9200/_cat/indices/${prefix}-*?h=index&expand_wildcards=open,closed" || true)
count=$(printf '%s\n' "$indices" | grep -c . || true)

if [[ "$count" -eq 0 ]]; then
  echo "✅ No indices found for prefix '$prefix'."
  exit 0
fi

echo "Indices for prefix '$prefix':"
printf '%s\n' "$indices" | sed 's/^/  /'

if [[ "$assume_yes" != true ]]; then
  if [[ ! -t 0 ]]; then
    echo "❌ Refusing to delete ${count} indices without --yes (stdin is not a terminal)." >&2
    exit 1
  fi
  read -rp "Delete these indices? This cannot be undone. [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || {
    echo "Cancelled."
    exit 1
  }
fi

deleted=0
while IFS= read -r index; do
  [[ -z "$index" ]] && continue
  es -X DELETE "http://localhost:9200/${index}" >/dev/null
  deleted=$((deleted + 1))
done <<< "$indices"
echo "✅ Deleted ${deleted} indices for prefix '$prefix'."
