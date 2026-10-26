#!/usr/bin/env python3
"""
Nettoie les workflows n8n exportés avant commit / rendu (cf. page 5 du sujet).
- remplace les noms de credentials par un nom générique
- supprime les données épinglées (pinData), qui peuvent contenir des données réelles
- signale les headers sensibles (Authorization, api key...) et les vide

Usage : python3 scripts/sanitize.py workflows/
"""
import json
import re
import sys
from pathlib import Path

SENSITIVE_HEADER = re.compile(r"authorization|api[-_]?key|token|secret|cookie|password", re.I)


def clean_headers(node, warnings):
    params = node.get("parameters", {})
    for key in ("headerParameters", "queryParameters"):
        for p in params.get(key, {}).get("parameters", []):
            if SENSITIVE_HEADER.search(str(p.get("name", ""))) and p.get("value"):
                warnings.append(f"  ! {node['name']} : '{p['name']}' vidé")
                p["value"] = ""


def sanitize(path: Path) -> list[str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    workflows = data if isinstance(data, list) else [data]
    warnings = []

    for wf in workflows:
        if wf.pop("pinData", None):
            warnings.append("  - pinData supprimé")
        for node in wf.get("nodes", []):
            for cred_type, cred in node.get("credentials", {}).items():
                cred["name"] = f"{cred_type} (à configurer)"
            clean_headers(node, warnings)

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
