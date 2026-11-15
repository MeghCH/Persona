# F-01 Un fuseau horaire invalide bloque l'envoi pour tout le monde

[Retour au sommaire](../README.md)

- **Type** : Faille trouvée
- **Gravité** : Moyenne
- **Statut** : Corrigée
- **Où** : `[B] News - Envoi` et la table `preferences`
- **Codes MITRE** : `T1499`
- **Premier essai** : 29/10, phase 2
- **Rejoué le 15/11/2026** : OK, en direct

## Ce qui se passait

Un seul utilisateur avec `timezone = 'Mars/Olympus'` en base faisait planter la requête de l'envoi.

**Impact** : Plus personne ne recevait la newsletter.

## Comment le reproduire

Avant de commencer, lancer Persona et préparer les outils de [methode.md](../methode.md) : `chat`, `nouvelle_session` et `psql_persona`.

1. Ouvrir la base :
   ```bash
   psql_persona
   ```
2. Essayer de mettre un fuseau qui n'existe pas à un utilisateur (dans une transaction qu'on annule) :
   ```sql
   BEGIN;
   UPDATE preferences SET timezone = 'Mars/Olympus'
     WHERE user_id = (SELECT id FROM users LIMIT 1);
   ROLLBACK;
   ```

## Résultat attendu

La base répond `violates check constraint "preferences_timezone_valid"`. Avant la correction, la valeur était acceptée, et la requête de l'envoi de B plantait à la première heure lue.

## Résultat du test (15/11/2026)

Rejoué en direct sur Persona : **OK**.

```
fuseau Mars/Olympus : ERROR:  new row for relation "preferences" violates check constraint "preferences_timezone_valid"
```

## La correction

La base refuse la valeur : contrainte `preferences_timezone_valid` dans `db/schema/02-schema.sql`.

**Vérification** : La contrainte est dans le schéma. Elle n'est pas dans le script de tests.

## Pourquoi ça tient maintenant

La contrainte `preferences_timezone_valid` utilise la fonction `is_valid_timezone` : la base refuse tout fuseau qu'elle ne connaît pas, quel que soit celui qui écrit (chatbot, B, ou quelqu'un qui a accès à la base).

## Codes MITRE

- [`T1499`](https://attack.mitre.org/techniques/T1499/) Endpoint Denial of Service

Les codes sont expliqués dans [mitre.md](../mitre.md).
