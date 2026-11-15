# T-20 Envoyer trop de messages pour épuiser le quota

[Retour au sommaire](../README.md)

- **Type** : Attaque testée
- **Statut** : Bloquée
- **Catégorie** : L'IA
- **Codes MITRE** : `T1499`, `T1499.003`, `AML.T0029`, `AML.T0034`, `CWE-770`
- **Premier essai** : test automatique et essai en direct
- **Rejoué le 15/11/2026** : OK, en direct et par les tests automatiques
- **Voir aussi** : [F-05](F-05-limite-messages-simultanes.md)

## Ce qu'on teste

Une rafale de messages, et dix messages en même temps.

## Comment le reproduire

Avant de commencer, lancer Persona et préparer les outils de [methode.md](../methode.md) : `chat`, `nouvelle_session` et `psql_persona`.

1. Envoyer 10 messages en même temps dans la même session :
   ```bash
   S=$(nouvelle_session)
   for i in $(seq 1 10); do chat "$S" "bonjour" & done; wait
   ```
2. Compter ce que la base a enregistré :
   ```bash
   echo "SELECT count(*) FROM chat_ai_requests WHERE session_id='$S';" | psql_persona
   ```

**Tests automatiques** (chaque ligne doit commencer par OK) :

```bash
docker-compose exec -T n8n node - < scripts/test_scenarios.js | grep -F -e "6 messages en une minute : le suivant est refusé" -e "100 messages dans la journée sur une session : le suivant est refusé" -e "200 messages dans la journée pour un compte : le suivant est refusé" -e "les non connectés ont une limite à eux : 150 messages par jour en tout" -e "600 messages dans la journée en tout : le suivant est refusé, même connecté"
```

## Résultat attendu

6 messages passent, 4 reçoivent un message qui dit d'écrire moins vite. La base compte 6 lignes.

## Résultat du test (15/11/2026)

Rejoué en direct sur Persona : **OK**.

```
10 messages en même temps : 6 acceptés, 4 refusés (attendu 6 et 4) | lignes comptées en base : 6
```

Ces tests passent (les 105 tests du script passent) :

- 6 messages en une minute : le suivant est refusé
- 100 messages dans la journée sur une session : le suivant est refusé
- 200 messages dans la journée pour un compte : le suivant est refusé
- les non connectés ont une limite à eux : 150 messages par jour en tout
- 600 messages dans la journée en tout : le suivant est refusé, même connecté

## Pourquoi ça bloque

La fonction `reserver_appel_ia` compte et enregistre en une seule fois. Les limites : 6 par minute et 100 par jour par session, 200 par jour par compte, 150 par jour pour tous les non connectés, 600 par jour en tout. Voir aussi F-05 pour la faille trouvée en testant.

## Codes MITRE

- [`T1499`](https://attack.mitre.org/techniques/T1499/) Endpoint Denial of Service
- [`T1499.003`](https://attack.mitre.org/techniques/T1499/003/) Endpoint Denial of Service: Application Exhaustion Flood
- [`AML.T0029`](https://atlas.mitre.org/techniques/AML.T0029) Denial of AI Service
- [`AML.T0034`](https://atlas.mitre.org/techniques/AML.T0034) Cost Harvesting
- [`CWE-770`](https://cwe.mitre.org/data/definitions/770.html) Allocation of Resources Without Limits or Throttling

Les codes sont expliqués dans [mitre.md](../mitre.md).
