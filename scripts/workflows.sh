#!/usr/bin/env bash
# Fait passer les workflows entre n8n et le dossier workflows/ (qui est dans Git).
#
#   bash scripts/workflows.sh export <nom> [<nom>...]   n8n -> dépôt, puis nettoyage (sanitize.py)
#   bash scripts/workflows.sh import [<nom>...]         dépôt -> n8n (tous si aucun nom)
#
# <nom> est le nom du fichier sans .json : a_chat_entree, b_news_envoi...
set -e
cd "$(dirname "$0")/.."

if docker compose version >/dev/null 2>&1; then DC="docker compose"; else DC="docker-compose"; fi

usage() {
  echo "Usage :"
  echo "  bash scripts/workflows.sh export <nom> [<nom>...]   n8n -> dépôt"
  echo "  bash scripts/workflows.sh import [<nom>...]         dépôt -> n8n (tous si aucun nom)"
  echo
  echo "Noms possibles :"
  for f in workflows/*.json; do echo "  $(basename "$f" .json)"; done
  exit 1
}

action="$1"
[ "$action" = export ] || [ "$action" = import ] || usage
shift

# accepte a_chat_entree, a_chat_entree.json ou workflows/a_chat_entree.json
noms=()
for arg in "$@"; do
  nom=$(basename "${arg%.json}")
  if [ ! -f "workflows/$nom.json" ]; then
    echo "Workflow inconnu : $arg"
    echo
    usage
  fi
  noms+=("$nom")
done

if [ "$action" = export ]; then
  # pas de « tout exporter » : un export écrase le fichier avec la version de n8n, et effacerait
  # le travail de l'autre sur les workflows qu'on n'a pas réimportés depuis le dernier git pull
  [ ${#noms[@]} -gt 0 ] || usage

  fichiers=()
  for nom in "${noms[@]}"; do
    # l'id est lu dans le fichier du dépôt (gère aussi un fichier exporté sans nettoyage)
    id=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d=d[0] if isinstance(d,list) else d; print(d["id"])' "workflows/$nom.json")
    echo "Export de $nom ($id)..."
    $DC exec -T n8n n8n export:workflow --id="$id" --output="/home/node/exports/$nom.json"
    python3 scripts/sanitize.py "workflows/$nom.json"
    fichiers+=("workflows/$nom.json")
  done

  echo
  if git diff --quiet -- "${fichiers[@]}"; then
    echo "Aucun changement par rapport au dépôt."
  else
    git --no-pager diff --stat -- "${fichiers[@]}"
    echo
    echo "Avant de commit, lire le diff : git diff ${fichiers[*]}"
    echo "Il ne doit contenir que tes changements. Pour annuler l'export : git restore ${fichiers[*]}"
  fi
else
  if [ ${#noms[@]} -eq 0 ]; then
    echo "Import de tous les workflows..."
    $DC exec -T n8n n8n import:workflow --separate --input=/home/node/exports
  else
    for nom in "${noms[@]}"; do
      echo "Import de $nom..."
      $DC exec -T n8n n8n import:workflow --input="/home/node/exports/$nom.json"
    done
  fi
  echo
  echo "Import terminé. Les workflows importés sont dépubliés : les republier dans n8n (README, étape 4)."
fi
