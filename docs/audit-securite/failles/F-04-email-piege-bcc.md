# F-04 Une adresse email piégée détourne la newsletter

[Retour au sommaire](../README.md)

- **Type** : Faille trouvée
- **Gravité** : Moyenne
- **Statut** : Corrigée
- **Où** : `[B] News - Envoi` et la table `users`
- **Codes MITRE** : `CWE-93`
- **Premier essai** : 29/10, phase 2
- **Rejoué le 15/11/2026** : OK, en direct et par les tests automatiques

## Ce qui se passait

Avec `pirate@…` suivi d'un saut de ligne et de `Bcc: espion@…` en base, l'email partait aussi chez l'espion.

**Impact** : Les newsletters étaient copiées à quelqu'un d'autre. Il faut pouvoir écrire cette valeur en base : le chatbot vérifie déjà les emails.

## Comment le reproduire

Avant de commencer, lancer Persona et préparer les outils de [methode.md](../methode.md) : `chat`, `nouvelle_session` et `psql_persona`.

1. Ouvrir la base :
   ```bash
   psql_persona
   ```
2. Essayer d'écrire une adresse qui contient un saut de ligne et un `Bcc` (dans une transaction qu'on annule) :
   ```sql
   BEGIN;
   UPDATE users SET email = E'pirate@example.com\r\nBcc: espion@evil.example'
     WHERE id = (SELECT id FROM users LIMIT 1);
   ROLLBACK;
   ```

**Tests automatiques** (chaque ligne doit commencer par OK) :

```bash
docker-compose exec -T n8n node - < scripts/test_scenarios.js | grep -F -e "un destinataire avec un Bcc caché bloque l'email"
```

## Résultat attendu

La base répond `violates check constraint "users_email_valid"`. Et si une telle adresse arrivait quand même jusqu'à l'envoi, le test montre que l'email est bloqué.

## Résultat du test (15/11/2026)

Rejoué en direct sur Persona : **OK**.

```
la base refuse l'adresse avec saut de ligne et Bcc : ERROR:  new row for relation "users" violates check constraint "users_email_valid"
```

Ces tests passent (les 105 tests du script passent) :

- un destinataire avec un Bcc caché bloque l'email

## La correction

La base vérifie le format (`users_email_valid`) et l'envoi est bloqué si l'adresse est suspecte.

**Vérification** : Test automatique : une adresse avec `Bcc` ne part pas.

## Pourquoi ça tient maintenant

Deux protections : la contrainte `users_email_valid` dans la base, et la vérification du destinataire dans `Vérifier l'email`, juste avant l'envoi.

## Codes MITRE

- [`CWE-93`](https://cwe.mitre.org/data/definitions/93.html) Improper Neutralization of CRLF Sequences

Les codes sont expliqués dans [mitre.md](../mitre.md).
