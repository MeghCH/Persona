# T-04 Réutiliser une session

[Retour au sommaire](../README.md)

- **Type** : Attaque testée
- **Statut** : Bloquée
- **Catégorie** : Authentification et comptes
- **Codes MITRE** : `T1550.004`
- **Premier essai** : attaque jouée sur l'instance de test (29/10)
- **Rejoué le 15/11/2026** : OK, en direct

## Ce qu'on teste

Après la déconnexion, après 2 h d'inactivité, après 8 h.

## Comment le reproduire

Avant de commencer, lancer Persona et préparer les outils de [methode.md](../methode.md) : `chat`, `nouvelle_session` et `psql_persona`.

1. Créer un compte de test, se connecter avec une session `S`, puis vérifier que `chat "$S" "mes données"` affiche l'email.
2. Se déconnecter, puis redemander :
   ```bash
   chat "$S" "deconnexion"
   chat "$S" "mes données"
   ```
3. Se reconnecter, vieillir la session de 2 heures sans activité, puis redemander :
   ```bash
   echo "UPDATE sessions SET expires_at = now() - interval '1 minute' WHERE chat_session_id='$S';" | psql_persona
   chat "$S" "mes données"
   ```
4. Se reconnecter, vieillir la session de plus de 8 heures, puis redemander :
   ```bash
   echo "UPDATE sessions SET created_at = now() - interval '9 hours', expires_at = now() + interval '1 hour' WHERE chat_session_id='$S';" | psql_persona
   chat "$S" "mes données"
   ```

## Résultat attendu

Après la déconnexion, après 2 h d'inactivité et après 8 h, « mes données » n'affiche plus l'email : le chatbot répond que l'on n'est pas connecté.

## Résultat du test (15/11/2026)

Rejoué en direct sur Persona : **OK**.

```
session valide : True | après déconnexion : False | expirée (2 h) : False | plus de 8 h : False
```

## Pourquoi ça bloque

`Vérifier la session` ne reconnaît une session que si elle n'est pas expirée et a moins de 8 h. Chaque message repousse l'expiration de 2 h, jamais au-delà de 8 h.

## Codes MITRE

- [`T1550.004`](https://attack.mitre.org/techniques/T1550/004/) Use Alternate Authentication Material: Web Session Cookie

Les codes sont expliqués dans [mitre.md](../mitre.md).
