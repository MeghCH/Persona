# T-05 Savoir qui est inscrit

[Retour au sommaire](../README.md)

- **Type** : Attaque testée
- **Statut** : Bloquée
- **Catégorie** : Authentification et comptes
- **Codes MITRE** : `T1087`, `CWE-204`
- **Premier essai** : test automatique et essai en direct
- **Rejoué le 15/11/2026** : OK, en direct et par les tests automatiques

## Ce qu'on teste

Email déjà pris, email inconnu, mauvais mot de passe.

## Comment le reproduire

Avant de commencer, lancer Persona et préparer les outils de [methode.md](../methode.md) : `chat`, `nouvelle_session` et `psql_persona`.

1. Créer un compte de test.
2. Se connecter avec un email qui n'existe pas, puis avec un email qui existe et un mauvais mot de passe :
   ```bash
   chat "$(nouvelle_session)" "connexion inconnu@example.com Whatever-12345!"
   chat "$(nouvelle_session)" "connexion audit.test@example.com Whatever-12345!"
   ```
3. Pour l'inscription : lancer les tests ci-dessous. Ils vérifient qu'un email déjà inscrit reçoit un email sans code, et que le chat répond comme pour un nouvel email.

**Tests automatiques** (chaque ligne doit commencer par OK) :

```bash
docker-compose exec -T n8n node - < scripts/test_scenarios.js | grep -F -e "un email déjà inscrit reçoit un message sans code" -e "le code est tiré à vide quand l'email est déjà inscrit (aucun code ne peut marcher)"
```

## Résultat attendu

Les deux réponses de connexion sont identiques : on ne peut pas savoir si l'email existe.

## Résultat du test (15/11/2026)

Rejoué en direct sur Persona : **OK**.

```
email inconnu : « Identifiants invalides, ou compte temporairement verrou… » | mauvais mot de passe : « Identifiants invalides, ou compte temporairement verrou… »
```

Ces tests passent (les 105 tests du script passent) :

- un email déjà inscrit reçoit un message sans code
- le code est tiré à vide quand l'email est déjà inscrit (aucun code ne peut marcher)

## Pourquoi ça bloque

`Vérifier les identifiants` hache le mot de passe même pour un email inconnu (même temps de réponse) et renvoie le même message dans tous les cas d'échec. À l'inscription, le chat répond « code envoyé » dans tous les cas.

## Codes MITRE

- [`T1087`](https://attack.mitre.org/techniques/T1087/) Account Discovery
- [`CWE-204`](https://cwe.mitre.org/data/definitions/204.html) Observable Response Discrepancy

Les codes sont expliqués dans [mitre.md](../mitre.md).
