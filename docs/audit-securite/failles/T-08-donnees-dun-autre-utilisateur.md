# T-08 Lire ou modifier les données d'un autre utilisateur par l'IA

[Retour au sommaire](../README.md)

- **Type** : Attaque testée
- **Statut** : Bloquée
- **Catégorie** : Données et droits
- **Codes MITRE** : `CWE-639`
- **Premier essai** : attaque jouée sur l'instance de test (29/10)
- **Rejoué le 15/11/2026** : OK, en direct

## Ce qu'on teste

Demander à l'IA de changer l'identifiant d'utilisateur.

## Comment le reproduire

Avant de commencer, lancer Persona et préparer les outils de [methode.md](../methode.md) : `chat`, `nouvelle_session` et `psql_persona`.

1. Vérifier qu'aucun des 8 outils de l'agent ne reçoit l'identifiant de l'utilisateur de la part de l'IA :
   ```bash
   grep -c "fromAI('user" workflows/a_chat_agent.json
   ```
2. Vérifier que chaque outil prend l'identifiant dans la session :
   ```bash
   grep -c "first().json.user_id" workflows/a_chat_agent.json
   ```

## Résultat attendu

La première commande affiche 0. La deuxième affiche un nombre supérieur ou égal à 8 : un par outil, soit « 8 outils sur 8 ».

## Résultat du test (15/11/2026)

Rejoué en direct sur Persona : **OK**.

```
8 outils sur 8 prennent l'identifiant dans la session, jamais dans la réponse de l'IA
```

## Pourquoi ça bloque

L'IA ne donne que des valeurs (sujets, heure…). L'identifiant vient de la session que le workflow d'entrée a vérifiée. Même une IA manipulée ne peut donc agir que sur le compte connecté.

## Codes MITRE

- [`CWE-639`](https://cwe.mitre.org/data/definitions/639.html) Authorization Bypass Through User-Controlled Key

Les codes sont expliqués dans [mitre.md](../mitre.md).
