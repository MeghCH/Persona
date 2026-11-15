# T-13 Retrouver un mot de passe dans le journal ou les exécutions

[Retour au sommaire](../README.md)

- **Type** : Attaque testée
- **Statut** : Bloquée
- **Catégorie** : Données et droits
- **Codes MITRE** : `T1552`, `CWE-532`
- **Premier essai** : attaque jouée sur l'instance de test (29/10)
- **Rejoué le 15/11/2026** : OK, en direct

## Ce qu'on teste

Chercher le mot de passe en clair après une inscription ou une connexion.

## Comment le reproduire

Avant de commencer, lancer Persona et préparer les outils de [methode.md](../methode.md) : `chat`, `nouvelle_session` et `psql_persona`.

1. Se connecter avec un compte de test, puis chercher le mot de passe dans le journal :
   ```bash
   echo "SELECT count(*) FROM audit_log WHERE details::text LIKE '%Zx-Test-12345-Qw9!%';" | psql_persona
   ```
2. Regarder ce que la base garde :
   ```bash
   echo "SELECT left(password_hash, 4) FROM users WHERE email='audit.test@example.com';" | psql_persona
   ```
3. Vérifier que le workflow d'entrée n'enregistre pas ses exécutions :
   ```bash
   grep -n "saveData" workflows/a_chat_entree.json
   ```

## Résultat attendu

Le journal ne contient jamais le mot de passe (0). La base garde seulement un hash qui commence par `$2a$` (bcrypt). Le workflow a `saveDataSuccessExecution` et `saveDataErrorExecution` à `none`.

## Résultat du test (15/11/2026)

Rejoué en direct sur Persona : **OK**.

```
mot de passe retrouvé dans audit_log : 0 fois | base : $2a$ / identique au mot de passe : false
```

## Pourquoi ça bloque

Le mot de passe est haché en SQL avec bcrypt, jamais écrit dans `audit_log`, et n8n n'enregistre pas les exécutions du workflow d'entrée.

## Codes MITRE

- [`T1552`](https://attack.mitre.org/techniques/T1552/) Unsecured Credentials
- [`CWE-532`](https://cwe.mitre.org/data/definitions/532.html) Insertion of Sensitive Information into Log File

Les codes sont expliqués dans [mitre.md](../mitre.md).
