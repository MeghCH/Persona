# T-06 Créer un compte avec l'email de quelqu'un d'autre

[Retour au sommaire](../README.md)

- **Type** : Attaque testée
- **Statut** : Bloquée
- **Catégorie** : Authentification et comptes
- **Codes MITRE** : `T1136`
- **Premier essai** : test automatique et essai en direct
- **Rejoué le 15/11/2026** : OK, en direct et par les tests automatiques

## Ce qu'on teste

Inscription en une ligne, ou code tapé sans inscription en cours.

## Comment le reproduire

Avant de commencer, lancer Persona et préparer les outils de [methode.md](../methode.md) : `chat`, `nouvelle_session` et `psql_persona`.

1. Essayer de créer un compte en une seule ligne, avec l'email d'une autre personne :
   ```bash
   chat "$(nouvelle_session)" "inscription victime@example.com Mot-De-Passe-42! j'accepte"
   ```
2. Vérifier qu'aucun compte n'existe :
   ```bash
   echo "SELECT count(*) FROM users WHERE email='victime@example.com';" | psql_persona
   ```

**Tests automatiques** (chaque ligne doit commencer par OK) :

```bash
docker-compose exec -T n8n node - < scripts/test_scenarios.js | grep -F -e "l'inscription en une ligne est refusée" -e "un seul nœud crée des comptes : « Vérifier le code »"
```

## Résultat attendu

Le chatbot répond de taper simplement « inscription ». La base compte 0 compte.

## Résultat du test (15/11/2026)

Rejoué en direct sur Persona : **OK**.

```
réponse : « Pour créer un compte, tapez simplement « inscription » : je vous guide… » | comptes créés : 0
```

Ces tests passent (les 105 tests du script passent) :

- l'inscription en une ligne est refusée
- un seul nœud crée des comptes : « Vérifier le code »

## Pourquoi ça bloque

L'inscription en une ligne n'existe plus. Le seul nœud qui crée des comptes est `Vérifier le code` : il faut avoir reçu le code sur l'adresse.

## Codes MITRE

- [`T1136`](https://attack.mitre.org/techniques/T1136/) Create Account

Les codes sont expliqués dans [mitre.md](../mitre.md).
