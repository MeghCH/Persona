# T-10 Retrouver la mémoire de l'IA d'un autre compte

[Retour au sommaire](../README.md)

- **Type** : Attaque testée
- **Statut** : Bloquée
- **Catégorie** : Données et droits
- **Codes MITRE** : `CWE-200`
- **Premier essai** : attaque jouée sur l'instance de test (29/10)
- **Rejoué le 15/11/2026** : OK, en direct

## Ce qu'on teste

Dans la même fenêtre de chat.

## Comment le reproduire

Avant de commencer, lancer Persona et préparer les outils de [methode.md](../methode.md) : `chat`, `nouvelle_session` et `psql_persona`.

1. Lire la clé de la mémoire de l'agent :
   ```bash
   grep -o "sessionKey.*" workflows/a_chat_agent.json
   ```

## Résultat attendu

La clé est faite de l'identifiant de session ET de l'identifiant d'utilisateur : `session_id + ':' + user_id`.

## Résultat du test (15/11/2026)

Rejoué en direct sur Persona : **OK**.

```
clé de la mémoire : ={{ session_id + ':' + user_id }}
```

## Pourquoi ça bloque

Deux comptes qui se connectent dans la même fenêtre de chat n'ont jamais la même mémoire.

## Codes MITRE

- [`CWE-200`](https://cwe.mitre.org/data/definitions/200.html) Exposure of Sensitive Information to an Unauthorized Actor

Les codes sont expliqués dans [mitre.md](../mitre.md).
