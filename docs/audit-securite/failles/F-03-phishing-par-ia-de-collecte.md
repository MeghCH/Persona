# F-03 L'IA de la collecte peut écrire un lien de phishing dans un résumé

[Retour au sommaire](../README.md)

- **Type** : Faille trouvée
- **Gravité** : Haute
- **Statut** : Corrigée
- **Où** : `[B] News - Collecte`
- **Codes MITRE** : `AML.T0051.001`, `T1566.002`
- **Premier essai** : 29/10, phase 2
- **Rejoué le 15/11/2026** : OK, par les tests automatiques

## Ce qui se passait

Un article piégé pouvait faire écrire à l'IA du HTML ou un lien de phishing dans le résumé, qui partait ensuite dans la newsletter.

**Impact** : La consigne vient d'un article du web, pas d'un utilisateur : tous les abonnés pouvaient la recevoir.

## Comment le reproduire

Avant de commencer, lancer Persona et préparer les outils de [methode.md](../methode.md) : `chat`, `nouvelle_session` et `psql_persona`.

1. Lancer les tests de la collecte : chacun fabrique un résumé comme l'écrirait une IA manipulée par un article piégé (HTML, lien de phishing, consigne cachée), puis lance le vrai nœud `Contrôler les résumés`.

**Tests automatiques** (chaque ligne doit commencer par OK) :

```bash
docker-compose exec -T n8n node - < scripts/test_scenarios.js | grep -F -e "un résumé avec du HTML est rejeté" -e "un résumé avec un lien est rejeté" -e "un résumé avec une injection de prompt est rejeté" -e "un résumé refusé par l'IA relectrice est rejeté" -e "IA relectrice en panne : un résumé avec du HTML est quand même rejeté"
```

## Résultat attendu

Chaque résumé piégé est rejeté, y compris quand la deuxième IA (celle qui relit) est en panne : le contrôle automatique suffit.

## Résultat du test (15/11/2026)

Ces tests passent (les 105 tests du script passent) :

- un résumé avec du HTML est rejeté
- un résumé avec un lien est rejeté
- un résumé avec une injection de prompt est rejeté
- un résumé refusé par l'IA relectrice est rejeté
- IA relectrice en panne : un résumé avec du HTML est quand même rejeté

## La correction

Un contrôle automatique rejette un résumé avec du HTML, un lien ou une consigne, puis une deuxième IA relit chaque résumé avant qu'il soit gardé.

**Vérification** : Tests automatiques : un résumé piégé est rejeté, et le contrôle marche encore quand la deuxième IA est en panne.

## Pourquoi ça tient maintenant

Un contrôle sans IA (`Contrôler les résumés`) rejette le HTML, les liens et les traces d'injection. Une deuxième IA, avec un prompt à part, compare ensuite chaque résumé à l'article. Un résumé rejeté n'est pas enregistré, donc il n'est jamais envoyé.

## Codes MITRE

- [`AML.T0051.001`](https://atlas.mitre.org/techniques/AML.T0051.001) LLM Prompt Injection: Indirect
- [`T1566.002`](https://attack.mitre.org/techniques/T1566/002/) Phishing: Spearphishing Link

Les codes sont expliqués dans [mitre.md](../mitre.md).
