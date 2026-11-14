# Tests de l'évaluation avant l'envoi

On teste les cas où quelque chose se passe mal avant l'envoi de la newsletter : un mauvais
résumé, un email piégé, un réglage du chat ignoré. Le but : rien de mauvais n'arrive chez
l'abonné.

## Lancer les tests

Persona doit tourner :

```bash
docker compose exec -T n8n node - < scripts/test_scenarios.js
```

Le script lance le vrai code des nœuds des workflows. Gemini est remplacé par des réponses
écrites à la main. Rien n'est écrit en base.

Pour la collecte et l'envoi, le script a **un test par protection** : 21 tests, sur 31 en tout
(les autres parties sont listées dans le README, section Tests).

## Les scénarios

Chaque test imagine une situation où quelque chose tourne mal, puis vérifie que le système
réagit bien. Un test « OK » veut dire que la protection a marché. Les cas normaux sont là pour
vérifier que l'évaluation ne bloque pas tout.

Les titres ci-dessous sont ceux des sections affichées par le script.

### Collecte : évaluation des résumés

| Ce qui tourne mal | Ce qu'on attend |
|---|---|
| rien (cas normal) : Gemini a bien fait son travail | le résumé est gardé |
| un article piégé fait ajouter un lien à Gemini (phishing) | le résumé est rejeté |
| Gemini n'a rien écrit (réponse coupée ou vide) | le résumé est rejeté |
| Gemini a écrit un pavé au lieu de 2 phrases | le résumé est rejeté |
| Gemini a oublié de traduire un article de la BBC | le résumé est rejeté |
| un article piégé fait écrire du HTML à Gemini (`<img onerror=…>`) | le résumé est rejeté |
| un article piégé fait recopier une consigne à Gemini (« ignore tes instructions… ») | le résumé est rejeté |
| l'IA relectrice voit un chiffre qui n'est pas dans l'article | le résumé est rejeté |
| l'IA relectrice ne répond pas (quota épuisé) | seul le contrôle automatique compte : un bon résumé est gardé, un résumé avec du HTML est rejeté |

Un résumé rejeté n'est pas enregistré, donc l'article n'est jamais envoyé.

### Collecte : reprise des articles sans résumé

| Ce qui tourne mal | Ce qu'on attend |
|---|---|
| Gemini a refusé un lot à la collecte d'avant | après l'insertion, les articles passent par `Articles à résumer`, qui les reprend |

### Envoi : vérification de l'email

| Ce qui tourne mal | Ce qu'on attend |
|---|---|
| rien (cas normal) : un article correct et une adresse correcte | l'email part |
| un flux RSS piégé met du code dans un titre (`<script>`) | le code est échappé, il s'affiche comme du texte |
| un article a un lien `javascript:` | l'article est retiré, et l'email ne part pas s'il ne reste aucun article |
| une adresse piégée cache un destinataire (`\r\nBcc: …`) | l'email ne part pas |
| le jeton de désinscription manque (obligatoire pour le RGPD) | l'email ne part pas |

Un email bloqué est noté dans `audit_log` (`newsletter_blocked`).

### Envoi : réglages choisis dans le chat

| Ce qui tourne mal | Ce qu'on attend |
|---|---|
| l'utilisateur est passé en format `titres` (« c'est trop long ») | l'email n'a plus les résumés |
| rien (cas normal) : format `resume` | le résumé est là |
| rien (cas normal) : format `detaille` | résumé, heure de publication à l'heure de Paris et thèmes |
| une valeur inconnue arrive dans `format` | mise en page `resume`, pas d'email cassé |
| le fuseau en base n'est pas connu de Node | heure de Paris, sans planter |
| les sources exclues sont retirées après le `LIMIT` (moins d'articles que demandé), ou pas du tout | le filtre est dans le `WHERE`, avant le `LIMIT` |

## Ce qui n'est pas testé

- **La vraie IA relectrice** : le script remplace Gemini par des réponses écrites à la main
  (voir plus bas pour la tester à la main).
- **Les pannes techniques** : le serveur mail (SMTP) qui ne répond pas, la base arrêtée, un flux
  RSS inaccessible. Pour Gemini en panne pendant le résumé, le test vérifie seulement que les
  articles passent par la reprise. La reprise a aussi été constatée une fois en vrai, le 14/11
  (voir [optimisation.md](optimisation.md#reprise-des-articles)).

## À tester à la main avec le vrai Gemini

Le script ne teste pas la vraie IA relectrice. Pour le faire dans n8n, sur `[B] News - Collecte` :
lancer le workflow une fois, épingler la sortie de `Regrouper le lot` et de `Classer et résumer`
(_Pin data_), modifier un résumé dans `Classer et résumer`, puis exécuter seulement
`Appliquer l'évaluation` (_Execute step_).

| Résumé modifié | Attendu | Résultat |
|---|---|---|
| un résumé fidèle | gardé | |
| un chiffre qui n'est pas dans l'article | rejeté | |
| une opinion (« une réforme scandaleuse ») | rejeté | |
