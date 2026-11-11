#!/usr/bin/env bash
# Lance Persona : conteneurs, base de données, credentials n8n et workflows.
# On peut le relancer autant qu'on veut : il saute ce qui est déjà fait.
#
#   bash scripts/setup.sh           lance (ou relance) le projet
#   bash scripts/setup.sh --import  réimporte aussi les workflows de ./workflows (après un git pull)
set -euo pipefail
cd "$(dirname "$0")/.."

IMPORT=0
case "${1:-}" in
  '') ;;
  --import) IMPORT=1 ;;
  *) echo "Usage : bash scripts/setup.sh [--import]" >&2; exit 1 ;;
esac

# Mêmes ids que dans scripts/sanitize.py : tous les nœuds des workflows pointent vers eux.
CRED_POSTGRES=NVYHYZPCSYpCPKph
CRED_SMTP=jS2Eif9DDVW1DYQd
CRED_GEMINI=I6nWZedjVfgjuRJ9

fail() { echo "Erreur : $*" >&2; exit 1; }

# lance une commande sans rien afficher, sauf si elle échoue
quiet() {
  local out
  if ! out=$("$@" 2>&1); then echo "$out" >&2; return 1; fi
}

# ---------------------------------------------------------------------
# Vérifications
# ---------------------------------------------------------------------
command -v docker >/dev/null || fail "Docker n'est pas installé (voir « Ce qu'il faut » dans le README)."
docker info >/dev/null 2>&1 || fail "Docker ne répond pas : lance Docker Desktop (ou le service docker), puis relance ce script."
if docker compose version >/dev/null 2>&1; then DC=(docker compose)
elif command -v docker-compose >/dev/null; then DC=(docker-compose)
else fail "Docker Compose est introuvable (voir « Ce qu'il faut » dans le README)."; fi
command -v curl >/dev/null || fail "curl n'est pas installé (sous Ubuntu : sudo apt install curl)."

# ---------------------------------------------------------------------
# Fichier .env : créé la première fois, avec des mots de passe générés
# ---------------------------------------------------------------------
random_hex() { head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n'; }

if [ ! -f .env ]; then
  sed -e "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(random_hex 24)/" \
      -e "s/^PERSONA_DB_PASSWORD=.*/PERSONA_DB_PASSWORD=$(random_hex 24)/" \
      -e "s/^N8N_ENCRYPTION_KEY=.*/N8N_ENCRYPTION_KEY=$(random_hex 32)/" \
      .env.example > .env
  echo "Fichier .env créé, avec des mots de passe générés."
fi

env_value() {
  local v
  v=$(grep -E "^$1=" .env | tail -n 1 | cut -d= -f2-) || true
  v=${v%$'\r'}                       # .env enregistré sous Windows
  v=${v#\"}; v=${v%\"}; v=${v#\'}; v=${v%\'}
  printf '%s' "$v"
}
for var in POSTGRES_USER POSTGRES_PASSWORD PERSONA_DB_PASSWORD N8N_ENCRYPTION_KEY; do
  [ -n "$(env_value "$var")" ] || fail "$var est vide dans .env."
done
PERSONA_DB_PASSWORD=$(env_value PERSONA_DB_PASSWORD)
GEMINI_API_KEY=$(env_value GEMINI_API_KEY)

# ---------------------------------------------------------------------
# Conteneurs
# ---------------------------------------------------------------------
echo "Démarrage des conteneurs (la première fois, Docker télécharge les images : quelques minutes)..."
"${DC[@]}" up -d

wait_for() {  # wait_for <description> <commande...>
  local what=$1; shift
  for _ in $(seq 1 90); do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 2
  done
  fail "$what ne répond pas après 3 minutes. Pour voir pourquoi : ${DC[*]} logs"
}
echo "Attente de la base et de n8n..."
# -h 127.0.0.1 : pendant sa toute première initialisation, Postgres n'écoute pas encore le réseau
wait_for "La base" "${DC[@]}" exec -T postgres sh -c 'pg_isready -q -h 127.0.0.1 -U "$POSTGRES_USER" -d persona'
# /healthz répond dès le démarrage ; /healthz/readiness attend que n8n ait fini de préparer sa base
N8N_READY=http://localhost:5678/healthz/readiness
wait_for "n8n" curl -sf "$N8N_READY"

# ---------------------------------------------------------------------
# Base de données : le schéma est rejoué à chaque fois (il ne recrée pas ce qui existe)
# ---------------------------------------------------------------------
echo "Mise à jour de la base..."
"${DC[@]}" exec -T -e PGOPTIONS='-c client_min_messages=warning' postgres \
  sh -c 'psql -q -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d persona' < db/schema/02-schema.sql

# ---------------------------------------------------------------------
# Credentials n8n
# - Postgres Persona et SMTP Persona : créés s'ils manquent, jamais modifiés ensuite
#   (on peut donc passer SMTP Persona sur un vrai serveur mail dans n8n).
# - LLM Persona : créé s'il manque, et mis à jour si GEMINI_API_KEY est rempli dans .env.
# ---------------------------------------------------------------------
existing=$("${DC[@]}" exec -T postgres sh -c 'psql -qAt -U "$POSTGRES_USER" -d n8n -c "SELECT id FROM credentials_entity"')
has_cred() { grep -qx "$1" <<<"$existing"; }
json_string() { local s=${1//\\/\\\\}; s=${s//\"/\\\"}; printf '"%s"' "$s"; }

creds=()
if ! has_cred "$CRED_POSTGRES"; then
  creds+=("{\"id\":\"$CRED_POSTGRES\",\"name\":\"Postgres Persona\",\"type\":\"postgres\",\"data\":{\"host\":\"postgres\",\"port\":5432,\"database\":\"persona\",\"user\":\"persona_app\",\"password\":$(json_string "$PERSONA_DB_PASSWORD"),\"ssl\":\"disable\"}}")
fi
if ! has_cred "$CRED_SMTP"; then
  creds+=("{\"id\":\"$CRED_SMTP\",\"name\":\"SMTP Persona\",\"type\":\"smtp\",\"data\":{\"host\":\"mailpit\",\"port\":1025,\"secure\":false,\"disableStartTls\":true,\"user\":\"\",\"password\":\"\"}}")
fi
if ! has_cred "$CRED_GEMINI" || [ -n "$GEMINI_API_KEY" ]; then
  creds+=("{\"id\":\"$CRED_GEMINI\",\"name\":\"LLM Persona\",\"type\":\"googlePalmApi\",\"data\":{\"host\":\"https://generativelanguage.googleapis.com\",\"apiKey\":$(json_string "${GEMINI_API_KEY:-a-remplir}")}}")
fi
if [ ${#creds[@]} -gt 0 ]; then
  echo "Credentials n8n..."
  # les secrets passent par l'entrée standard (pas par la ligne de commande), et le fichier
  # temporaire est effacé tout de suite
  (IFS=,; printf '[%s]' "${creds[*]}") | "${DC[@]}" exec -T n8n sh -c '
    umask 077; f=/tmp/persona-credentials.json
    cat > "$f" && out=$(n8n import:credentials --input="$f" 2>&1); rc=$?
    rm -f "$f"; [ "$rc" -eq 0 ] || echo "$out" >&2; exit "$rc"' \
    || fail "création des credentials impossible."
fi

# ---------------------------------------------------------------------
# Workflows : importés la première fois, ou avec --import
# ---------------------------------------------------------------------
workflows_in_n8n=$("${DC[@]}" exec -T n8n n8n list:workflow 2>/dev/null || true)
if [ "$IMPORT" = 1 ] || ! grep -q PersonaChatEntr1 <<<"$workflows_in_n8n"; then
  # deux fichiers avec le même id s'écraseraient à l'import : on refuse
  to_publish=$("${DC[@]}" exec -T n8n node -e '
    const fs = require("fs"), dir = "/home/node/exports", seen = {};
    let ok = true;
    for (const f of fs.readdirSync(dir).filter((f) => f.endsWith(".json")).sort()) {
      const wf = JSON.parse(fs.readFileSync(dir + "/" + f, "utf8"));
      if (seen[wf.id]) { console.error("même id " + wf.id + " dans " + seen[wf.id] + " et " + f); ok = false; }
      seen[wf.id] = f;
      if (wf.active) console.log(wf.id);
    }
    process.exit(ok ? 0 : 1);') \
    || fail "deux fichiers de workflows/ ont le même id (voir ci-dessus) : n'en garder qu'un."

  echo "Import des workflows (ceux de n8n sont remplacés par ceux de ./workflows)..."
  quiet "${DC[@]}" exec -T n8n n8n import:workflow --separate --input=/home/node/exports \
    || fail "import des workflows impossible."
  # l'import dépublie les workflows : on republie ceux marqués actifs dans leur fichier
  for id in $to_publish; do
    quiet "${DC[@]}" exec -T n8n n8n publish:workflow --id="$id" || fail "publication du workflow $id impossible."
  done
  echo "Redémarrage de n8n..."
  quiet "${DC[@]}" restart n8n
  wait_for "n8n" curl -sf "$N8N_READY"
fi

echo
echo "Persona est lancé."
echo "  chatbot : http://localhost:8090  (cliquer sur la bulle et taper « inscription »)"
echo "  emails  : http://localhost:8025  (Mailpit : les codes d'inscription et les newsletters arrivent ici)"
echo "  n8n     : http://localhost:5678  (pour voir et modifier les workflows)"
if [ -z "$GEMINI_API_KEY" ]; then
  echo
  echo "Pas de clé Gemini : l'inscription et la connexion marchent, mais pas l'agent ni la collecte des news."
  echo "Pour l'ajouter : la coller après GEMINI_API_KEY= dans .env, puis relancer bash scripts/setup.sh"
fi
