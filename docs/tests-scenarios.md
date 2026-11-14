# Les tests

Tous les tests de `scripts/test_scenarios.js`, dans le même ordre et avec les mêmes titres que ce
que le script affiche.

## Lancer les tests

Persona doit tourner :

```bash
docker compose exec -T n8n node - < scripts/test_scenarios.js
```

Ou sans Docker, comme la CI de GitHub (Node.js 22) :

```bash
WORKFLOWS=workflows node scripts/test_scenarios.js
```

Le script lance le vrai code des nœuds des workflows. Gemini est remplacé par des réponses
écrites à la main. Rien n'est écrit en base. Les 35 tests doivent passer : `35 réussis, 0 ratés`.

## Comment ils sont rangés

Le script suit les workflows, dans l'ordre de [workflows.md](workflows.md) :

| Groupe | Ce qu'il teste |
|---|---|
| **A · Chatbot** | `[A] Chat - Entrée` et `[A] Chat - Agent` |
| **B · Newsletter** | `[B] News - Collecte` et `[B] News - Envoi` |
| **Commun** | ce qui touche plusieurs workflows (le modèle Gemini) |

Chaque section porte le nom du workflow, puis la partie testée, et affiche les nœuds qu'elle
lance. Pour la collecte et l'envoi, il y a un test par protection. Ailleurs, il y a le cas normal
et le cas le plus important à bloquer.

Un test « OK » veut dire que la protection a marché. Les cas normaux sont là pour vérifier que
les protections ne bloquent pas tout.

En résumé :

| Groupe         | Section du script                           | Tests | Ce qui est testé                                                                                                 |
| -------------- | ------------------------------------------- | ----- | ---------------------------------------------------------------------------------------------------------------- |
| A · Chatbot    | [A] Chat - Entrée : messages envoyés à l'IA | 2     | rien ne part vers l'IA pendant l'inscription ou la connexion ; une rafale de messages est refusée                |
| A · Chatbot    | [A] Chat - Entrée : comprendre les phrases  | 2     | une phrase d'inscription est comprise ; aucune phrase ne supprime un compte                                      |
| A · Chatbot    | [A] Chat - Entrée : code d'inscription      | 2     | le bon code crée le compte ; 5 essais au maximum                                                                 |
| A · Chatbot    | [A] Chat - Agent : prompt par étape         | 3     | sans centre d'intérêt, l'agent est à l'étape 1 ; prochain envoi à la minute près, règle des 20 h                 |
| A · Chatbot    | [A] Chat - Agent : outil modifier_horaire   | 1     | une minute hors créneau (7, 60) ou piégée est refusée                                                            |
| B · Newsletter | [B] News - Collecte : contrôle des résumés  | 9     | un bon résumé est gardé, les mauvais sont rejetés, même si l'IA relectrice est en panne                          |
| B · Newsletter | [B] News - Collecte : reprise des articles  | 1     | les articles d'un lot raté sont repris                                                                           |
| B · Newsletter | [B] News - Envoi : sécurité de l'email      | 5     | le HTML est échappé ; un lien `javascript:`, un `Bcc` caché ou un lien de désinscription absent bloquent l'email |
| B · Newsletter | [B] News - Envoi : réglages de l'abonné     | 6     | les 3 formats, un format ou un fuseau inconnu, les sources exclues                                               |
| B · Newsletter | [B] News - Envoi : horaire                  | 3     | envoi toutes les 5 minutes au bon créneau ; collecte jamais en même temps ; pas de mention n8n                   |
| Commun         | Modèle Gemini                               | 1     | les 4 nœuds Gemini ont le même modèle, écrit en toutes lettres                                                   |

## A · Chatbot

### [A] Chat - Entrée : messages envoyés à l'IA

Nœuds : `Faut-il limiter ?`, `Contrôler le débit`. Détails dans
[protection-deni-of-service.md](protection-deni-of-service.md).

| Ce qui tourne mal | Ce qu'on attend |
|---|---|
| l'utilisateur tape son mot de passe pendant l'inscription ou la connexion guidée | rien ne part vers l'IA, à aucune étape (code d'inscription compris) |
| un script envoie des messages en rafale | au 7e message dans la minute, le message est refusé |

### [A] Chat - Entrée : comprendre les phrases

Nœud : `Appliquer l'intention`. Détails dans
[protection-deni-of-service.md](protection-deni-of-service.md).

| Ce qui tourne mal | Ce qu'on attend |
|---|---|
| rien (cas normal) : un non connecté écrit qu'il veut s'inscrire | l'inscription démarre |
| une phrase, piégée ou non, essaie de supprimer un compte | aucune intention ne mène à la suppression, connecté ou non : il faut taper exactement `confirmer suppression`. Le test essaie les 9 intentions de la liste et 4 valeurs piégées |

### [A] Chat - Entrée : code d'inscription

Nœuds : `Répondre code`, `Vérifier le code`. Détails dans
[code-inscription.md](code-inscription.md).

| Ce qui tourne mal | Ce qu'on attend |
|---|---|
| rien (cas normal) : le bon code est tapé | le compte est créé |
| un attaquant essaie tous les codes un par un | 5 essais au maximum par code |

### [A] Chat - Agent : prompt par étape

Nœud : `Choisir le prompt`. Détails dans [prompts-IA.md](prompts-IA.md).

| Ce qui tourne mal | Ce qu'on attend |
|---|---|
| rien (cas normal) : un nouvel inscrit n'a pas encore de centre d'intérêt | l'agent est à l'étape 1, choisir ses sujets |
| rien (cas normal) : à 14 h 23, l'utilisateur règle 14 h 30 | le prompt annonce le prochain envoi aujourd'hui à 14 h 30 |
| l'utilisateur a déjà reçu une newsletter il y a 3 h : `[B] News - Envoi` n'en enverra pas d'autre avant 20 h | le prompt annonce le lendemain, et dit jusqu'à quand il faut attendre |

L'heure est arrêtée pour ces tests : le script passe au nœud une fausse `Date`, fixée au samedi
14 novembre 2026 à 14 h 23 (heure de Paris).

### [A] Chat - Agent : outil modifier_horaire

Nœud : `modifier_horaire`. Le script lance la vraie expression régulière de la requête SQL.

| Ce qui tourne mal | Ce qu'on attend |
|---|---|
| l'IA envoie une minute qui n'est pas un créneau (7, 60, -5) ou une valeur piégée | refusée ; 0, 5… 55 sont acceptées |

## B · Newsletter

### [B] News - Collecte : contrôle des résumés

Nœuds : `Contrôler les résumés`, `Appliquer l'évaluation`.

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

### [B] News - Collecte : reprise des articles

Nœuds : `Enregistrer les articles`, `Articles à résumer`, `Articles trouvés`. Détails dans
[optimisation-IA.md](optimisation-IA.md#reprise-des-articles).

| Ce qui tourne mal | Ce qu'on attend |
|---|---|
| Gemini a refusé un lot à la collecte d'avant | après l'insertion, les articles passent par `Articles à résumer`, qui les reprend |

### [B] News - Envoi : sécurité de l'email

Nœuds : `Préparer les articles`, `Vérifier l'email`.

| Ce qui tourne mal | Ce qu'on attend |
|---|---|
| rien (cas normal) : un article correct et une adresse correcte | l'email part |
| un flux RSS piégé met du code dans un titre (`<script>`) | le code est échappé, il s'affiche comme du texte |
| un article a un lien `javascript:` | l'article est retiré, et l'email ne part pas s'il ne reste aucun article |
| une adresse piégée cache un destinataire (`\r\nBcc: …`) | l'email ne part pas |
| le jeton de désinscription manque (obligatoire pour le RGPD) | l'email ne part pas |

Un email bloqué est noté dans `audit_log` (`newsletter_blocked`).

### [B] News - Envoi : réglages de l'abonné

Nœuds : `Préparer les articles`, `Articles pour l'utilisateur`.

| Ce qui tourne mal | Ce qu'on attend |
|---|---|
| l'utilisateur est passé en format `titres` (« c'est trop long ») | l'email n'a plus les résumés |
| rien (cas normal) : format `resume` | le résumé est là |
| rien (cas normal) : format `detaille` | résumé, heure de publication à l'heure de Paris et thèmes |
| une valeur inconnue arrive dans `format` | mise en page `resume`, pas d'email cassé |
| le fuseau en base n'est pas connu de Node | heure de Paris, sans planter |
| les sources exclues sont retirées après le `LIMIT` (moins d'articles que demandé), ou pas du tout | le filtre est dans le `WHERE`, avant le `LIMIT` |

### [B] News - Envoi : horaire

Nœuds : `Schedule Trigger` (de l'envoi et de la collecte), `Utilisateurs à servir`,
`Envoyer la newsletter`.

| Ce qui tourne mal | Ce qu'on attend |
|---|---|
| l'utilisateur choisit 14 h 35, mais l'envoi ne passe qu'à l'heure pile ou ne regarde pas la minute | l'envoi passe toutes les 5 minutes (`*/5 * * * *`) et compare l'heure et le créneau de 5 minutes |
| la collecte et l'envoi partent à la même minute : l'envoi ne voit pas les articles de l'heure | la collecte part à une minute qui n'est jamais un créneau d'envoi (h52) |
| n8n ajoute « This email was sent automatically with n8n » à la fin de la newsletter | l'option `appendAttribution` est à `false` |

## Commun

### Modèle Gemini

Nœuds : les 4 nœuds Gemini, dans `[A] Chat - Agent`, `[A] Chat - Intention` et
`[B] News - Collecte`. Détails dans
[optimisation-IA.md](optimisation-IA.md#les-deux-modèles-essayés).

| Ce qui tourne mal | Ce qu'on attend |
|---|---|
| un nœud Gemini n'a pas de modèle écrit : n8n prendrait son modèle par défaut, qui change avec ses versions | les 4 nœuds ont un modèle écrit, le même partout (`gemini-3.5-flash-lite`) |

## Ce qui n'est pas testé automatiquement

Ces protections sont dans les workflows, mais aucun test ne les vérifie à chaque PR. Si on
modifie le nœud qui les porte, il faut les revérifier à la main :

- **A · Chatbot** : les limites par jour, par compte et pour les non connectés ; le comptage des
  messages en une seule requête (`reserver_appel_ia`) ; les liens retirés des réponses de
  l'intention ; le code tiré avec `gen_random_bytes`, haché, et ses 3 envois au maximum ; les
  règles de sécurité du prompt de l'agent à chaque étape ; l'outil `reinclure_source` ;
- **B · Newsletter** : la vraie IA relectrice (le script la remplace par des réponses écrites à
  la main) ;
- **les pannes techniques** : le serveur mail (SMTP) qui ne répond pas, la base arrêtée, un flux
  RSS inaccessible. Pour Gemini en panne pendant le résumé, le test vérifie seulement que les
  articles passent par la reprise. La reprise a aussi été constatée une fois en vrai, le 14/11
  (voir [optimisation-IA.md](optimisation-IA.md#reprise-des-articles)).

Les conversations à rejouer à la main pour l'agent sont dans
[prompts-IA.md](prompts-IA.md#tester-une-nouvelle-version).

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
