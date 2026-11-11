#!/usr/bin/env bash
# Affiche les derniers événements du journal de sécurité (audit_log), 20 par défaut.
#
#   bash scripts/journal.sh       les 20 derniers
#   bash scripts/journal.sh 50    les 50 derniers
set -euo pipefail
cd "$(dirname "$0")/.."

n=${1:-20}
case "$n" in
  ''|*[!0-9]*) echo "Usage : bash scripts/journal.sh [nombre]" >&2; exit 1 ;;
esac
if docker compose version >/dev/null 2>&1; then DC=(docker compose); else DC=(docker-compose); fi

"${DC[@]}" exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d persona -P pager=off -c "
SELECT a.created_at, a.event, u.email, a.details
FROM audit_log a LEFT JOIN users u ON u.id = a.user_id
ORDER BY a.created_at DESC LIMIT '"$n"';"'
