# T-07 Injection SQL

[Retour au sommaire](../README.md)

- **Type** : Attaque testée
- **Statut** : Bloquée
- **Catégorie** : Données et droits
- **Codes MITRE** : `T1190`, `T1485`, `CWE-89`
- **Premier essai** : attaque jouée sur l'instance de test (29/10)
- **Rejoué le 15/11/2026** : OK, en direct

## Ce qu'on teste

Dans l'email, dans le mot de passe, et `x'); DROP TABLE users;--` dans un outil.

## Comment le reproduire

Avant de commencer, lancer Persona et préparer les outils de [methode.md](../methode.md) : `chat`, `nouvelle_session` et `psql_persona`.

1. Envoyer des charges SQL à la place de l'email, du mot de passe, et dans le parcours guidé :
   ```bash
   chat "$(nouvelle_session)" "connexion admin'--@x.fr motdepasse"
   chat "$(nouvelle_session)" "connexion audit.test@example.com 'OR'1'='1"
   S=$(nouvelle_session); chat "$S" "connexion"; chat "$S" "x');DROP TABLE users;--"
   ```
2. Vérifier que la table existe toujours, et que l'on n'est pas connecté :
   ```bash
   echo "SELECT to_regclass('public.users') IS NOT NULL, count(*) FROM users;" | psql_persona
   ```

## Résultat attendu

Aucune connexion n'est obtenue, la table `users` existe toujours et le nombre de comptes n'a pas bougé.

## Résultat du test (15/11/2026)

Rejoué en direct sur Persona : **OK**.

```
connexion obtenue par injection : False | table users présente : t | comptes 7 -> 8 (+1 = le compte de test)
```

## Pourquoi ça bloque

Toutes les requêtes passent les valeurs par paramètres (`$1`, `$2`) : le texte tapé n'est jamais collé dans le SQL. Les emails sont aussi vérifiés par une expression régulière avant la base.

## Codes MITRE

- [`T1190`](https://attack.mitre.org/techniques/T1190/) Exploit Public-Facing Application
- [`T1485`](https://attack.mitre.org/techniques/T1485/) Data Destruction
- [`CWE-89`](https://cwe.mitre.org/data/definitions/89.html) Improper Neutralization of Special Elements used in an SQL Command

Les codes sont expliqués dans [mitre.md](../mitre.md).
