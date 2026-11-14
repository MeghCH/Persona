#!/usr/bin/env python3
"""
Nettoie les workflows n8n exportés avant commit / rendu.
- donne aux credentials leur nom d'équipe (Postgres Persona, SMTP Persona, LLM Persona) : à
  l'import, n8n rattache chaque nœud au credential qui porte ce nom.
- supprime les données épinglées (pinData), staticData et shared, qui peuvent contenir des données réelles,
  et meta.instanceId (un hash tiré de la clé de chiffrement de n8n).
- vide les headers sensibles (Authorization, api key...).
- signale les secrets probables ailleurs (webhooks Discord, clés API...) sans les modifier.

Usage : python3 scripts/sanitize.py workflows/
"""
import json
import re
import sys
from pathlib import Path

CREDENTIAL_NAMES = {"postgres": "Postgres Persona", "smtp": "SMTP Persona", "googlePalmApi": "LLM Persona"}

SENSITIVE_HEADER = re.compile(r"authorization|api[-_]?key|token|secret|cookie|password", re.I)
SECRET_PATTERNS = re.compile(r"discord(app)?\.com/api/webhooks/|AIza[0-9A-Za-z_-]{20,}|sk-[A-Za-z0-9_-]{20,}|Bearer\s+\S{10,}"
)


def clean_headers(node, warnings):
    params = node.get("parameters", {})
    for key in ("headerParameters", "queryParameters"):
        for p in params.get(key, {}).get("parameters", []):
            if SENSITIVE_HEADER.search(str(p.get("name", ""))) and p.get("value"):
                warnings.append(f"  ! {node['name']} : '{p['name']}' vidé")
                p["value"] = ""

def scan_secrets(obj, where, warnings):
    if isinstance(obj, dict):
        for k, v in obj.items():
            scan_secrets(v, f"{where}.{k}", warnings)
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            scan_secrets(v, f"{where}[{i}]", warnings)
    elif isinstance(obj, str) and SECRET_PATTERNS.search(obj):
        warnings.append(f"  !! secret probable dans {where} : à retirer à la main")


def sanitize(path: Path) -> list[str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    workflows = data if isinstance(data, list) else [data]
    warnings = []

    for wf in workflows:
        if wf.pop("pinData", None):
            warnings.append("  - pinData supprimé")
        for key in ("staticData", "shared"):
            if wf.pop(key, None):
                warnings.append(f"  - {key} supprimé")
        # instanceId : un hash tiré de N8N_ENCRYPTION_KEY. Pas un secret, mais inutile dans Git.
        if (wf.get("meta") or {}).pop("instanceId", None):
            warnings.append("  - meta.instanceId supprimé")
        for node in wf.get("nodes", []):
            for cred_type, cred in node.get("credentials", {}).items():
                cred["name"] = CREDENTIAL_NAMES.get(cred_type, f"{cred_type} (à configurer)")
            clean_headers(node, warnings)
            scan_secrets(node.get("parameters", {}), node["name"], warnings)

        if isinstance(data, list) and len(data) == 1:
            data = data[0]
            warnings.append("  - liste retirée : workflow seul, importable par l'interface")
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return warnings


def main():
    target = Path(sys.argv[1] if len(sys.argv) > 1 else "workflows")
    files = [target] if target.is_file() else sorted(target.glob("*.json"))
    if not files:
        print(f"Aucun fichier JSON dans {target}")
        return
    for f in files:
        warnings = sanitize(f)
        print(f"OK {f.name}")
        for w in warnings:
            print(w)


if __name__ == "__main__":
    main()
