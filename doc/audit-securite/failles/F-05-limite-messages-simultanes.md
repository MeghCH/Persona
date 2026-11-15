# F-05 Des messages envoyés en même temps dépassent la limite

[Retour au sommaire](../README.md)

- **Type** : Faille trouvée
- **Gravité** : Moyenne
- **Statut** : Corrigée
- **Où** : `[A] Chat - Entrée`, limite des messages envoyés à l'IA
- **Codes MITRE** : `T1499`, `AML.T0029`, `AML.T0034`, `CWE-770`
- **Premier essai** : 09/11, essai en direct
- **Rejoué le 15/11/2026** : OK, en direct et par les tests automatiques
- **Voir aussi** : [T-20](T-20-epuisement-du-quota.md)

## Ce qui se passait

Le comptage et l'enregistrement se faisaient en deux étapes. Avec dix messages simultanés, 9 passaient pour une limite de 6.

**Impact** : La limite ne protégeait pas le quota de Gemini contre une rafale.

## Comment le reproduire

Avant de commencer, lancer Persona et préparer les outils de [methode.md](../methode.md) : `chat`, `nouvelle_session` et `psql_persona`.

1. Choisir une session et envoyer 10 messages en même temps :
   ```bash
   S=$(nouvelle_session)
   for i in $(seq 1 10); do chat "$S" "bonjour" & done; wait
   ```
2. Compter les messages enregistrés :
   ```bash
   echo "SELECT count(*) FROM chat_ai_requests WHERE session_id='$S';" | psql_persona
   ```

**Tests automatiques** (chaque ligne doit commencer par OK) :

```bash
docker-compose exec -T n8n node - < scripts/test_scenarios.js | grep -F -e "le comptage et l'enregistrement se font en une seule requête (reserver_appel_ia)" -e "aucun autre nœud n'enregistre de message dans chat_ai_requests" -e "un message refusé rend sa place (sa réservation est supprimée)"
```

## Résultat attendu

6 messages passent et 4 reçoivent « très vite » (la limite est de 6 par minute). La base compte 6 lignes. Avant la correction, 9 messages sur 10 passaient.

## Résultat du test (15/11/2026)

Rejoué en direct sur Persona : **OK**.

```
10 messages en même temps : 6 acceptés, 4 refusés (attendu 6 et 4) | lignes comptées en base : 6
```

Ces tests passent (les 105 tests du script passent) :

- le comptage et l'enregistrement se font en une seule requête (reserver_appel_ia)
- aucun autre nœud n'enregistre de message dans chat_ai_requests
- un message refusé rend sa place (sa réservation est supprimée)

## La correction

Le comptage et l'enregistrement se font en une seule fois, dans la fonction SQL `reserver_appel_ia`, avec un verrou.

**Vérification** : Même essai après correction : 6 passent et 4 sont refusés. Trois tests automatiques vérifient que le comptage reste en une seule requête.

## Pourquoi ça tient maintenant

Le comptage et l'enregistrement se font en une seule fois dans la fonction SQL `reserver_appel_ia`, qui pose un verrou : les messages simultanés passent un par un, et chacun voit les précédents.

## Codes MITRE

- [`T1499`](https://attack.mitre.org/techniques/T1499/) Endpoint Denial of Service
- [`AML.T0029`](https://atlas.mitre.org/techniques/AML.T0029) Denial of AI Service
- [`AML.T0034`](https://atlas.mitre.org/techniques/AML.T0034) Cost Harvesting
- [`CWE-770`](https://cwe.mitre.org/data/definitions/770.html) Allocation of Resources Without Limits or Throttling

Les codes sont expliqués dans [mitre.md](../mitre.md).
