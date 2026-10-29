#!/usr/bin/env bash
# Lance Persona : démarre les conteneurs, applique la migration des workflows A
# et importe les workflows dans n8n. Ce qui est déjà fait est sauté.
# Usage : bash scripts/setup.sh
set -e
cd "$(dirname "$0")/.."

if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi

if [ ! -f .env ]; then
  cp .env.example .env
  echo "Fichier .env créé : remplis les mots de passe, puis relance ce script."
  exit 1
fi

$DC up -d

echo "Attente de la base et de n8n..."
until $DC exec -T postgres sh -c 'pg_isready -q -U "$POSTGRES_USER" -d persona'; do sleep 2; done
until curl -sf http://localhost:5678/healthz >/dev/null; do sleep 2; done

if [ "$($DC exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d persona -At -c "select to_regclass('"'"'public.auth_pending'"'"') is null"')" = "t" ]; then
  echo "Migration de la base..."
  $DC exec -T postgres sh -c 'psql -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d persona' < db/proposals/03-style-feedback-timezone.sql
fi

# Réimporter désactiverait les workflows : on n'importe que s'ils sont absents.
if ! $DC exec -T n8n n8n list:workflow 2>/dev/null | grep -q PersonaChatEntr1; then
  echo "Import des workflows..."
  $DC exec -T n8n n8n import:workflow --separate --input=/home/node/exports
fi

echo
echo "Persona est lancé."
echo "  n8n     : http://localhost:5678"
echo "  chatbot : http://localhost:8090"
