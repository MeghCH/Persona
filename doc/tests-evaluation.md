# Tests de l'évaluation avant l'envoi

On teste les cas où quelque chose se passe mal avant l'envoi de la newsletter : un mauvais
résumé, une IA relectrice en panne, un email piégé. Le but : rien de mauvais n'arrive chez
l'abonné.

## Lancer les tests

Persona doit tourner :

```bash
docker compose exec -T n8n node - < scripts/test_scenarios.js
```

Le script lance le vrai code des nœuds des workflows. Gemini est remplacé par des réponses
écrites à la main. Rien n'est écrit en base.

Résultat : **24 tests sur 24 passent** (collecte et envoi).

## Les scénarios

Chaque test imagine une situation où quelque chose tourne mal, puis vérifie que le système
réagit bien. Un test « OK » veut dire que la protection a marché. Les cas normaux sont là pour
vérifier que l'évaluation ne bloque pas tout.

### Collecte : évaluation des résumés

| Ce qui tourne mal | Ce qu'on attend |
|---|---|
| rien (cas normal) : Gemini a bien fait son travail | le résumé est gardé |
| Gemini n'a rien écrit (réponse coupée ou vide) | le résumé est rejeté |
| Gemini a écrit un pavé au lieu de 2 phrases | le résumé est rejeté |
| Gemini a oublié de traduire un article de la BBC | le résumé est rejeté |
| un article piégé fait écrire du HTML à Gemini (`<img onerror=…>`) | le résumé est rejeté |
| un article piégé fait ajouter un lien à Gemini (phishing) | le résumé est rejeté |
| un article piégé fait recopier une consigne à Gemini (« ignore tes instructions… ») | le résumé est rejeté |
| rien (cas normal) : un vrai article sur l'IA parle de « prompt système » | le résumé est gardé |
| l'IA relectrice voit un chiffre qui n'est pas dans l'article | le résumé est rejeté |
| l'IA relectrice ne répond pas (quota épuisé) et le résumé est bon | le résumé est gardé |
| l'IA relectrice ne répond pas et le résumé contient du HTML | le résumé est rejeté par le contrôle automatique |

Un résumé rejeté n'est pas enregistré, donc l'article n'est jamais envoyé.

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
| une des 3 mises en page casse le contrôle de l'email | les 3 passent `Vérifier l'email` |
| l'utilisateur a exclu une source, mais la requête ne lit pas `excluded_sources` | `Utilisateurs à servir` lit `format`, `excluded_sources` et `timezone` |
| les sources exclues sont retirées après le `LIMIT` (moins d'articles que demandé) | le filtre est dans le `WHERE`, avant le `LIMIT` |

## Ce qui n'est pas testé

- **La vraie IA relectrice** : le script remplace Gemini par des réponses écrites à la main
  (voir plus bas pour la tester à la main).
- **Les pannes techniques** : Gemini en panne pendant le résumé, le serveur mail (SMTP) qui ne
  répond pas, la base arrêtée, un flux RSS inaccessible.

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
