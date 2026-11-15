# T-09 Prendre l'email d'un autre compte

[Retour au sommaire](../README.md)

- **Type** : Attaque testée
- **Statut** : Bloquée
- **Catégorie** : Données et droits
- **Codes MITRE** : `T1098`
- **Premier essai** : attaque jouée sur l'instance de test (29/10)
- **Rejoué le 15/11/2026** : OK, en direct

## Ce qu'on teste

Changer son email pour celui d'un autre utilisateur.

## Comment le reproduire

Avant de commencer, lancer Persona et préparer les outils de [methode.md](../methode.md) : `chat`, `nouvelle_session` et `psql_persona`.

1. Lire la requête de l'outil `modifier_email` :
   ```bash
   python3 -c "import json;print(next(n for n in json.load(open('workflows/a_chat_agent.json',encoding='utf-8'))['nodes'] if n['name']=='modifier_email')['parameters']['query'])"
   ```

## Résultat attendu

La requête contient `AND NOT EXISTS (SELECT 1 FROM users WHERE email = … AND id <> …)` : un email déjà pris par un autre compte est refusé.

## Résultat du test (15/11/2026)

Rejoué en direct sur Persona : **OK**.

```
la requête de modifier_email refuse un email déjà utilisé (NOT EXISTS)
```

## Pourquoi ça bloque

Une double protection : la requête de l'outil, et la colonne `users.email` qui est `UNIQUE` dans la base.

## Codes MITRE

- [`T1098`](https://attack.mitre.org/techniques/T1098/) Account Manipulation

Les codes sont expliqués dans [mitre.md](../mitre.md).
