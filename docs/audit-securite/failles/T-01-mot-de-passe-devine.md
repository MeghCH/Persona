# T-01 Deviner le mot de passe

[Retour au sommaire](../README.md)

- **Type** : Attaque testée
- **Statut** : Bloquée
- **Catégorie** : Authentification et comptes
- **Codes MITRE** : `T1110.001`, `CWE-307`
- **Premier essai** : attaque jouée sur l'instance de test (29/10)
- **Rejoué le 15/11/2026** : OK, en direct

## Ce qu'on teste

5 mauvais mots de passe, puis le bon.

## Comment le reproduire

Avant de commencer, lancer Persona et préparer les outils de [methode.md](../methode.md) : `chat`, `nouvelle_session` et `psql_persona`.

1. Créer un compte de test (voir [methode.md](../methode.md)) et choisir une session : `S=$(nouvelle_session)`.
2. Envoyer 5 mauvais mots de passe :
   ```bash
   for i in 1 2 3 4 5; do chat "$S" "connexion audit.test@example.com Mauvais-$i-Mdp9!"; done
   ```
3. Envoyer le bon mot de passe :
   ```bash
   chat "$S" "connexion audit.test@example.com Zx-Test-12345-Qw9!"
   ```
4. Regarder la base :
   ```bash
   echo "SELECT failed_login_attempts, locked_until FROM users WHERE email='audit.test@example.com';" | psql_persona
   ```

## Résultat attendu

Même avec le bon mot de passe, la réponse est « Identifiants invalides, ou compte temporairement verrouillé ». La base montre 5 échecs et un `locked_until` dans 15 minutes.

## Résultat du test (15/11/2026)

Rejoué en direct sur Persona : **OK**.

```
bon mot de passe après 5 échecs : « Identifiants invalides, ou compte temporairement verrouillé … » | base : 5 echecs, verrouille=true
```

## Pourquoi ça bloque

Le nœud `Vérifier les identifiants` compte les échecs en SQL et verrouille le compte au 5e. Un compte verrouillé refuse même le bon mot de passe, et la réponse ne dit pas si c'est le mot de passe ou le verrou.

## Codes MITRE

- [`T1110.001`](https://attack.mitre.org/techniques/T1110/001/) Brute Force: Password Guessing
- [`CWE-307`](https://cwe.mitre.org/data/definitions/307.html) Improper Restriction of Excessive Authentication Attempts

Les codes sont expliqués dans [mitre.md](../mitre.md).
