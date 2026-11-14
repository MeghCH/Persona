#!/usr/bin/env bash
# Affiche les derniers événements du journal (audit_log). Voir docs/base-de-donnees.md.
# Usage : bash scripts/journal.sh [nombre de lignes, 20 par défaut]
set -e
cd "$(dirname "$0")/.."

lignes="${1:-20}"
case "$lignes" in
  '' | *[!0-9]*) echo "Usage : bash scripts/journal.sh [nombre de lignes]"; exit 1 ;;
esac

# le compte admin est celui du .env (POSTGRES_USER), lu dans le conteneur
docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d persona -P pager=off' <<SQL
SELECT a.created_at, a.event, u.email, a.details
FROM audit_log a LEFT JOIN users u ON u.id = a.user_id
ORDER BY a.created_at DESC LIMIT $lignes;
SQL
