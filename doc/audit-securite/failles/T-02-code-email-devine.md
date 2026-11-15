# T-02 Deviner le code reçu par email

[Retour au sommaire](../README.md)

- **Type** : Attaque testée
- **Statut** : Bloquée
- **Catégorie** : Authentification et comptes
- **Codes MITRE** : `T1110`, `CWE-307`, `CWE-338`
- **Premier essai** : test automatique et essai en direct
- **Rejoué le 15/11/2026** : OK, par les tests automatiques

## Ce qu'on teste

Un mauvais code, 5 erreurs puis le bon code, un ancien code après un renvoi.

## Comment le reproduire

Avant de commencer, lancer Persona et préparer les outils de [methode.md](../methode.md) : `chat`, `nouvelle_session` et `psql_persona`.

1. Avec `SMTP Persona` réglé sur Mailpit (README, étape 2), ouvrir http://localhost:8090 et taper `inscription`, un email, `j'accepte`, puis un mot de passe. Le code arrive sur http://localhost:8025.
2. Taper 5 mauvais codes : `000000`, `111111`, `222222`, `333333`, `444444`.
3. Taper le vrai code.
4. Regarder la base :
   ```bash
   echo "SELECT otp_attempts, otp_hash IS NOT NULL AS code_garde, length(otp_hash) AS taille FROM auth_pending;" | psql_persona
   ```

**Tests automatiques** (chaque ligne doit commencer par OK) :

```bash
docker-compose exec -T n8n node - < scripts/test_scenarios.js | grep -F -e "le code est tiré avec gen_random_bytes (pas random())" -e "le code et le mot de passe sont hachés avant d'être gardés" -e "5 essais au maximum par code" -e "5e mauvais code : il faut recommencer" -e "le code doit faire exactement 6 chiffres"
```

## Résultat attendu

Après le 5e mauvais code, le vrai code est refusé : « Trop d'essais. Tapez « inscription » pour recommencer. ». La base garde un hash (60 caractères), jamais le code à 6 chiffres.

## Résultat du test (15/11/2026)

Ces tests passent (les 105 tests du script passent) :

- le code est tiré avec gen_random_bytes (pas random())
- le code et le mot de passe sont hachés avant d'être gardés
- 5 essais au maximum par code
- 5e mauvais code : il faut recommencer
- le code doit faire exactement 6 chiffres

## Pourquoi ça bloque

`Vérifier le code` compare le code haché et refuse au-delà de 5 essais. Le code est tiré avec `gen_random_bytes`, ce qui évite un hasard prévisible. Le parcours complet a aussi été joué dans le vrai n8n le 10/11 (voir [code-inscription.md](../../code-inscription.md)).

## Codes MITRE

- [`T1110`](https://attack.mitre.org/techniques/T1110/) Brute Force
- [`CWE-307`](https://cwe.mitre.org/data/definitions/307.html) Improper Restriction of Excessive Authentication Attempts
- [`CWE-338`](https://cwe.mitre.org/data/definitions/338.html) Use of Cryptographically Weak Pseudo-Random Number Generator (PRNG)

Les codes sont expliqués dans [mitre.md](../mitre.md).
