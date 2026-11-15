# F-02 Le HTML des articles passe tel quel dans l'email

[Retour au sommaire](../README.md)

- **Type** : Faille trouvée
- **Gravité** : Haute
- **Statut** : Corrigée
- **Où** : `[B] News - Envoi`, nœud `Construire l'email`
- **Codes MITRE** : `CWE-79`, `T1566.002`
- **Premier essai** : 29/10, phase 2
- **Rejoué le 15/11/2026** : OK, par les tests automatiques

## Ce qui se passait

Un titre avec `<img src=x onerror=…>`, un lien `javascript:` ou un lien de phishing arrivait dans la newsletter.

**Impact** : Du contenu piégé envoyé à tous les abonnés, dans un email qui vient de nous.

## Comment le reproduire

Avant de commencer, lancer Persona et préparer les outils de [methode.md](../methode.md) : `chat`, `nouvelle_session` et `psql_persona`.

1. Lancer les tests de l'envoi. Ils fabriquent un article avec un titre piégé (`<script>`) et un autre avec un lien `javascript:`, puis lancent le vrai nœud `Construire l'email`.
2. Pour le voir à la main : dans n8n, ouvrir `[B] News - Envoi`, épingler (`Pin data`) un article dont le titre est `<img src=x onerror=alert(1)>` à la sortie de `Articles pour l'utilisateur`, puis exécuter `Construire l'email` et lire le HTML produit.

**Tests automatiques** (chaque ligne doit commencer par OK) :

```bash
docker-compose exec -T n8n node - < scripts/test_scenarios.js | grep -F -e "du HTML dans un titre est échappé" -e "un article avec un lien javascript: est retiré, donc email bloqué"
```

## Résultat attendu

Le titre ressort sous la forme `&lt;img …&gt;` (échappé), et l'article au lien `javascript:` est retiré : s'il ne reste aucun article, l'email ne part pas.

## Résultat du test (15/11/2026)

Ces tests passent (les 105 tests du script passent) :

- du HTML dans un titre est échappé
- un article avec un lien javascript: est retiré, donc email bloqué

## La correction

Le titre, la source et le résumé sont échappés, et seuls les liens `http` et `https` sont gardés.

**Vérification** : Tests automatiques : un titre avec `<script>` est échappé, un lien `javascript:` est retiré.

## Pourquoi ça tient maintenant

`Construire l'email` échappe le titre, la source et le résumé, et ne garde que les liens qui commencent par `http://` ou `https://`. `Vérifier l'email` bloque ensuite tout email qui contient encore une balise dangereuse.

## Codes MITRE

- [`CWE-79`](https://cwe.mitre.org/data/definitions/79.html) Improper Neutralization of Input During Web Page Generation
- [`T1566.002`](https://attack.mitre.org/techniques/T1566/002/) Phishing: Spearphishing Link

Les codes sont expliqués dans [mitre.md](../mitre.md).
