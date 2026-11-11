#!/usr/bin/env bash
# Lance Persona (conteneurs, mise à jour de la base, import des workflows).
# On peut le relancer, il saute ce qui est déjà fait.
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

echo "Mise à jour de la base..."
$DC exec -T -e PGOPTIONS='-c client_min_messages=warning' postgres \
  sh -c 'psql -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d persona' < db/schema/02-schema.sql

# réimporter désactive les workflows, donc seulement s'ils n'y sont pas
if ! $DC exec -T n8n n8n list:workflow 2>/dev/null | grep -q PersonaChatEntr1; then
  echo "Import des workflows..."
  $DC exec -T n8n n8n import:workflow --separate --input=/home/node/exports
fi

echo
echo "Persona est lancé."
echo "  n8n     : http://localhost:5678"
echo "  chatbot : http://localhost:8090"
