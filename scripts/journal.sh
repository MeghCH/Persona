# Usage : ./scripts/journal.sh
docker compose exec postgres psql -U persona_admin -d persona -P pager=off -c "
SELECT a.created_at, a.event, u.email, a.details
FROM audit_log a LEFT JOIN users u ON u.id = a.user_id
ORDER BY a.created_at DESC LIMIT ${1:-20};"