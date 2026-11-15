# T-14 Entrées invalides

[Retour au sommaire](../README.md)

- **Type** : Attaque testée
- **Statut** : Bloquée
- **Catégorie** : Données et droits
- **Codes MITRE** : `CWE-20`
- **Premier essai** : attaque jouée sur l'instance de test (29/10)
- **Rejoué le 15/11/2026** : OK, en direct

## Ce qu'on teste

Identifiant de session `abc`, message vide, message de 1001 caractères.

## Comment le reproduire

Avant de commencer, lancer Persona et préparer les outils de [methode.md](../methode.md) : `chat`, `nouvelle_session` et `psql_persona`.

1. Envoyer les trois entrées invalides :
   ```bash
   chat "abc" "bonjour"
   chat "$(nouvelle_session)" "   "
   chat "$(nouvelle_session)" "$(printf 'a%.0s' $(seq 1 1001))"
   ```

## Résultat attendu

Trois refus : « Session invalide », « Message vide » et « Message trop long (1000 caractères maximum) ».

## Résultat du test (15/11/2026)

Rejoué en direct sur Persona : **OK**.

```
session « abc » : « Session invalide : rechargez la page du … » | message vide : « Message vide. » | 1001 caractères : « Message trop long (1000 caractères maxim… »
```

## Pourquoi ça bloque

Le nœud `Analyser le message` vérifie la session (32 à 64 caractères), nettoie le texte et limite la taille avant de faire quoi que ce soit d'autre.

## Codes MITRE

- [`CWE-20`](https://cwe.mitre.org/data/definitions/20.html) Improper Input Validation

Les codes sont expliqués dans [mitre.md](../mitre.md).
