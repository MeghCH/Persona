#!/usr/bin/env bash
# Exporte les workflows de n8n vers ./workflows, chacun dans son fichier, puis les nettoie
# avec scripts/sanitize.py. À lancer avant de commit des workflows modifiés dans n8n.
#
#   bash scripts/export.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if docker compose version >/dev/null 2>&1; then DC=(docker compose); else DC=(docker-compose); fi
command -v python3 >/dev/null || { echo "Erreur : python3 n'est pas installé." >&2; exit 1; }

# n8n nomme les fichiers exportés d'après l'id du workflow : on exporte à part, puis on
# réécrit chaque workflow dans le fichier de ./workflows qui a le même id.
out=$("${DC[@]}" exec -T n8n sh -c \
  'rm -rf /tmp/persona-export && n8n export:workflow --all --separate --output=/tmp/persona-export/' 2>&1) \
  || { echo "$out" >&2; exit 1; }

"${DC[@]}" exec -T n8n node - <<'JS'
const fs = require('fs');
const dir = '/home/node/exports';
const tmp = '/tmp/persona-export';
// les seuls champs gardés dans le repo (le reste change à chaque export : dates, versions...)
const KEEP = ['id', 'name', 'description', 'active', 'isArchived', 'nodes', 'connections', 'settings', 'meta', 'tags'];

const fileById = {};
for (const f of fs.readdirSync(dir).filter((f) => f.endsWith('.json'))) {
  try { fileById[JSON.parse(fs.readFileSync(`${dir}/${f}`, 'utf8')).id] = f; } catch (e) {}
}
// « [A] Chat - Entrée » -> a_chat_entree.json
const fileName = (name) => name.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
  .replace(/^\[(\w+)\]\s*/, '$1_').replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '') + '.json';

for (const f of fs.readdirSync(tmp).filter((f) => f.endsWith('.json')).sort()) {
  const wf = JSON.parse(fs.readFileSync(`${tmp}/${f}`, 'utf8'));
  if (wf.isArchived) continue;
  const kept = {};
  for (const k of KEEP) if (k in wf) kept[k] = wf[k];
  const target = fileById[wf.id] || fileName(wf.name);
  fs.writeFileSync(`${dir}/${target}`, JSON.stringify(kept, null, 2) + '\n');
  console.log(`${fileById[wf.id] ? 'mis à jour' : 'nouveau   '} : workflows/${target}`);
}
JS

sortie=$(python3 scripts/sanitize.py workflows/)
grep -v '^OK ' <<<"$sortie" || true
if grep -q '!!' <<<"$sortie"; then
  echo "Attention : secret probable dans un workflow (voir ci-dessus), à retirer avant de commit." >&2
fi
echo
echo "Exporté et nettoyé. Vérifier avec « git diff workflows/ », puis commit."
