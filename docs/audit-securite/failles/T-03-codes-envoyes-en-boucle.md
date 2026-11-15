# T-03 Demander des codes en boucle

[Retour au sommaire](../README.md)

- **Type** : Attaque testée
- **Statut** : Bloquée
- **Catégorie** : Authentification et comptes
- **Codes MITRE** : `T1499`
- **Premier essai** : test automatique et essai en direct
- **Rejoué le 15/11/2026** : OK, par les tests automatiques

## Ce qu'on teste

Une 4e demande de code pour la même inscription.

## Comment le reproduire

Avant de commencer, lancer Persona et préparer les outils de [methode.md](../methode.md) : `chat`, `nouvelle_session` et `psql_persona`.

1. Commencer une inscription dans la bulle (comme pour T-02), jusqu'à l'envoi du premier code.
2. Taper `renvoyer le code` trois fois de suite.
3. Regarder la base et la boîte Mailpit (http://localhost:8025) :
   ```bash
   echo "SELECT otp_sent_count FROM auth_pending;" | psql_persona
   ```

**Tests automatiques** (chaque ligne doit commencer par OK) :

```bash
docker-compose exec -T n8n node - < scripts/test_scenarios.js | grep -F -e "3 envois de code au maximum par inscription" -e "« renvoyer le code » pendant l'inscription renvoie un code" -e "« renvoyer le code » sans inscription en cours ne fait rien de spécial"
```

## Résultat attendu

Le premier code et deux renvois partent : 3 emails au total. Le 3e « renvoyer le code » est refusé : « Je ne peux plus envoyer de code pour cette inscription. ». `otp_sent_count` vaut 3.

## Résultat du test (15/11/2026)

Ces tests passent (les 105 tests du script passent) :

- 3 envois de code au maximum par inscription
- « renvoyer le code » pendant l'inscription renvoie un code
- « renvoyer le code » sans inscription en cours ne fait rien de spécial

## Pourquoi ça bloque

La requête de `Renvoyer le code` contient `otp_sent_count < 3`. Limite connue : avec une nouvelle session, on recommence à zéro (voir R-03 dans [risques-restants.md](../risques-restants.md)).

## Codes MITRE

- [`T1499`](https://attack.mitre.org/techniques/T1499/) Endpoint Denial of Service

Les codes sont expliqués dans [mitre.md](../mitre.md).
