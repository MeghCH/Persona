# T-12 Valeurs absurdes

[Retour au sommaire](../README.md)

- **Type** : Attaque testée
- **Statut** : Bloquée
- **Catégorie** : Données et droits
- **Codes MITRE** : `CWE-20`
- **Premier essai** : attaque jouée sur l'instance de test (29/10)
- **Rejoué le 15/11/2026** : OK, en direct

## Ce qu'on teste

Fuseau `Mars/Olympus`, heure 25, jours 9 et 99, ton `admin`.

## Comment le reproduire

Avant de commencer, lancer Persona et préparer les outils de [methode.md](../methode.md) : `chat`, `nouvelle_session` et `psql_persona`.

1. Essayer chacune de ces valeurs dans la base, dans une transaction qu'on annule :
   ```sql
   BEGIN; UPDATE preferences SET send_hour = 25 WHERE user_id = (SELECT id FROM users LIMIT 1); ROLLBACK;
   BEGIN; UPDATE preferences SET send_days = '{9,99}' WHERE user_id = (SELECT id FROM users LIMIT 1); ROLLBACK;
   BEGIN; UPDATE preferences SET tone = 'admin' WHERE user_id = (SELECT id FROM users LIMIT 1); ROLLBACK;
   BEGIN; UPDATE preferences SET timezone = 'Mars/Olympus' WHERE user_id = (SELECT id FROM users LIMIT 1); ROLLBACK;
   ```

## Résultat attendu

Les 4 commandes échouent avec `violates check constraint`.

## Résultat du test (15/11/2026)

Rejoué en direct sur Persona : **OK**.

```
refusés par la base : heure 25, jours 9 et 99, ton admin, fuseau Mars/Olympus (sur 4)
```

## Pourquoi ça bloque

La table `preferences` a des contraintes `CHECK` sur l'heure, les jours, le ton, le format, le nombre d'articles et le fuseau. Les outils de l'agent vérifient aussi les valeurs avant d'écrire.

## Codes MITRE

- [`CWE-20`](https://cwe.mitre.org/data/definitions/20.html) Improper Input Validation

Les codes sont expliqués dans [mitre.md](../mitre.md).
