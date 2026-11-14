# Optimisation du temps et des tokens

Mesures du 14/11/2026, à partir des exécutions enregistrées par n8n, de la base et des logs. On a
essayé deux modèles Gemini, et on garde les mesures des deux :

- **`gemini-3-flash-preview`** du 31/10 au 14/11 : aucun nœud ne choisissait de modèle, n8n prenait
  le sien par défaut. Mesuré sur 68 collectes, 68 envois, 75 messages du chat et 19 appels de l'agent.
- **`gemini-3.5-flash-lite`** depuis le 14/11 vers 16 h : écrit dans les 4 nœuds Gemini. Mesuré sur
  4 collectes (dont 2 sans nouvel article) et 9 messages à l'agent.

## En bref

- La newsletter coûte des tokens une fois par article, pas une fois par abonné : l'envoi
  n'appelle jamais l'IA. Le coût ne bouge pas avec le nombre d'abonnés.
- Seul un tiers des articles lus dans les flux part vers l'IA : les autres sont déjà en base.
- Les lots de 10 articles divisent le nombre de requêtes par 10 et les tokens d'entrée par 3,6.
- Avec le premier modèle, ce qui bloquait n'était pas le nombre de tokens mais le nombre de
  requêtes : **20 par jour** avec la clé gratuite, alors que la collecte seule en demandait 30 à 48.
  Résultat : 22 % des articles n'ont jamais été résumés.
- Depuis le 14/11, un article dont le lot a échoué est repris à la collecte suivante, et le
  nouveau modèle a un quota plus haut (au moins 31 requêtes le 14/11 sans aucun refus).
- Pour le même nombre de tokens, le nouveau modèle résume **6 à 7 fois plus vite** et évalue
  **100 fois plus vite**. Une collecte de 46 articles prend 22 s, contre 27 min pour 79 articles
  avant.
- À surveiller : l'évaluation rejette 18 % des résumés du nouveau modèle, contre 15 % pour
  l'ancien. C'est proche, mais mesuré sur 49 articles seulement.

## Les deux modèles essayés

| | `gemini-3-flash-preview` | `gemini-3.5-flash-lite` |
|---|---|---|
| Période mesurée | 31/10 au 13/11 | 14/11, à partir de 16 h |
| Résumer un lot de 10 (entrée / sortie) | 19 s, ~1 470 / ~980 tokens | 2,9 s, ~1 340 / ~920 tokens |
| Évaluer un lot (entrée / sortie) | 161 s, ~1 930 / ~340 tokens | 1,6 s, ~1 910 / ~350 tokens |
| Plus grosse collecte réussie | 79 articles en 27 min | 46 articles en 22 s |
| Un message à l'agent | 3,5 s en moyenne | 2,4 s en moyenne |
| Résumés rejetés par l'évaluation | 15,4 % (94 sur 611, depuis le 07/11) | 18,4 % (9 sur 49) |
| Refus de Gemini | 25 collectes sur 68 arrêtées | aucun |
| Quota par jour (clé gratuite) | 20 requêtes, vu dans les logs | inconnu, au moins 31 requêtes le 14/11 sans refus |

Pour l'agent, la comparaison n'est pas tout à fait juste : la plupart des mesures de l'ancien
modèle datent du premier prompt (v1), plus court. Avec le prompt v2 et l'historique de la
conversation, un appel prend 1 700 à 2 600 tokens d'entrée, quel que soit le modèle.

### Pourquoi on a changé

- `gemini-3-flash-preview` est une préversion de décembre 2025, que Google conseille de remplacer.
  Une préversion peut changer ou disparaître, et elle tenait mal la charge (« service unavailable »
  dans nos collectes, encore une fois le 14/11 juste avant le changement).
- Le quota est compté par modèle (`limit: 20, model: gemini-3-flash` dans les logs). Google ne
  publie pas les quotas gratuits de chaque modèle, mais les relevés qu'on a trouvés donnent environ
  500 requêtes par jour aux modèles Flash-Lite, contre 20 pour les Flash 3.x. Avec un Flash, il ne
  serait presque rien resté pour le chat.
- Nos tâches sont simples : classer dans une liste fermée, résumer en 2 phrases, vérifier un
  résumé, régler des préférences avec des outils.
- Sans modèle écrit, n8n prend son modèle par défaut, qui change avec ses versions. Un test de
  `scripts/test_scenarios.js` vérifie maintenant que les 4 nœuds ont le même modèle, écrit en toutes
  lettres. On garde le même modèle partout.

### Ce qu'on a appris

- **Le temps** : la lenteur de l'évaluation venait de l'ancien modèle (voir plus bas). Avec le
  nouveau, un appel d'évaluation dure 1 à 2 s.
- **Les tokens** : presque les mêmes avec les deux modèles. Changer de modèle n'a pas changé ce que
  coûte un article.
- **Le quota** : plus aucun refus depuis le changement.
- **La qualité des résumés** : le taux de rejet est proche (15 % et 18 %). Les rejets du nouveau
  modèle ont l'air justes (« Pochettino n'est pas le nouveau manager de Man Utd dans le texte »,
  « jugement de valeur ») : le modèle invente parfois un détail, et l'évaluation le rattrape. Un
  rejet, c'est un article en moins dans les newsletters : si le taux monte au-dessus de 20 % sur
  plusieurs jours, il faudra revoir le prompt de `Classer et résumer` ou le modèle. Pour l'ancien
  modèle, 12 lots sont passés sans l'IA relectrice (Gemini indisponible) : son vrai taux de rejet
  est sans doute un peu plus haut.
- **L'agent** : à la main, l'heure, les sujets, le style, l'exclusion d'une source et deux
  changements dans le même message marchent. Une erreur : pour « réinclure Le Monde », que l'agent
  ne savait pas faire, il a exclu France Info à la place, sans le dire. Corrigé par un outil
  `reinclure_source` et une règle dans le prompt (voir [prompts-IA.md](prompts-IA.md)), puis revérifié à
  la main. C'est le genre d'erreur à surveiller avec un modèle Lite.

Si l'agent se trompe trop, l'étape suivante est `gemini-3.8-flash` avec une clé payante : avec la clé
gratuite, son quota ne suffirait pas.

## Ce que coûte chaque partie

Les tokens sont ceux de l'ancien modèle, mesurés sur deux semaines. Ceux du nouveau sont presque les
mêmes (voir le tableau plus haut).

| Partie | Appels à Gemini | Tokens par appel (entrée / sortie) | Durée moyenne (ancien / nouveau modèle) |
|---|---|---|---|
| Collecte : résumer un lot de 10 | 1 par lot | ~1 470 / ~980 | 19 s / 2,9 s |
| Collecte : évaluer un lot | 1 par lot | ~1 930 / ~340 | 161 s / 1,6 s |
| Envoi | 0 | - | 0,2 s |
| Chat : `[A] Chat - Entrée` | 0 pour les commandes | - | 0,8 s |
| Chat : agent | 1 à 3 par message (5 une fois, pendant l'erreur décrite plus haut) | ~1 370 à 2 600 / 10 à 130 | 3,5 s / 2,4 s |

`[A] Chat - Intention` n'est pas mesuré : il n'enregistre pas ses exécutions, exprès, parce que les
messages tapés dans le chat peuvent contenir un mot de passe (voir le README).

L'agent fait un appel de plus à chaque outil utilisé, et chaque appel renvoie tout le prompt.
Un message qui modifie deux réglages coûte donc 3 appels (1 370, puis 2 000, puis 2 400 tokens
d'entrée avec le prompt v1).

## Ce qui est déjà optimisé

### 1. Un résumé par article, pas par abonné

`[B] News - Collecte` résume chaque article une seule fois. `[B] News - Envoi` ne fait que du SQL
et remplit un modèle d'email. Avec 1 000 abonnés, la collecte coûte autant qu'avec un seul.

C'est aussi ce qui rend le ton de chaque abonné coûteux : pour réécrire la newsletter dans son
ton, il faudrait un appel par abonné et par envoi. Aujourd'hui, le ton ne sert qu'au chat.

### 2. Seuls les nouveaux articles vont à l'IA

Les flux RSS renvoient à chaque passage des articles qu'on a déjà. Trois étapes les écartent avant
Gemini : `Articles récents` garde ceux des dernières 48 h, `Enregistrer les articles` n'insère que
les URL inconnues (`ON CONFLICT DO NOTHING`), et `Articles à résumer` ne prend que ceux qui n'ont
pas encore de résumé. Depuis le 14/11, ça comprend aussi ceux d'un lot qui a échoué (voir
[Reprise des articles](#reprise-des-articles)). Les mesures ci-dessous datent d'avant.

| Articles lus dans les flux | Récents (48 h) | Nouveaux, envoyés à l'IA |
|---|---|---|
| 6 510 | 6 296 | 2 057 (32 %) |

Sans ce filtre, chaque collecte enverrait trois fois plus d'articles à Gemini.

### 3. Les articles par lots de 10

`Par lots de 10` envoie 10 articles dans une seule requête. Sur les 182 lots mesurés avec l'ancien
modèle, une requête coûte environ **430 tokens fixes** (les consignes et le format de réponse) plus
**104 tokens par article**. Les consignes ne sont envoyées qu'une fois pour 10 articles :

| | Un article par requête | Lots de 10 |
|---|---|---|
| Tokens d'entrée par article | ~536 | ~147 (-73 %) |
| Tokens de sortie par article | ~98 | ~98 |
| Requêtes pour 180 articles (une journée) | 180 | 18 |

### 4. Pas d'IA quand le code suffit

- **Collecte** : `Contrôler les résumés` rejette sans IA les résumés vides, trop longs, en anglais
  ou suspects. L'IA relectrice ne reçoit que les autres, avec le texte de l'article coupé à 1 500
  caractères.
- **Chat** : l'inscription, la connexion, le code par email, l'export et la suppression du compte
  se font en SQL, sans Gemini. On ne demande à l'IA de comprendre une phrase que si elle fait
  200 caractères au plus, et jamais pendant l'inscription ou la connexion.
- **Envoi** : le choix des articles (intérêts, sources exclues, nombre) se fait dans une seule
  requête SQL par abonné.

### 5. Des plafonds partout

- 2 048 tokens de réponse au maximum pour l'agent, 1 024 pour l'intention
- 1 000 caractères par message
- l'agent ne garde que les 8 derniers messages de la conversation, et s'arrête au bout de 6 tours
  (appels d'outils) par message
- l'agent fait 2 essais au maximum si Gemini échoue
- les limites de messages par minute et par jour (voir
  [protection-deni-of-service.md](protection-deni-of-service.md))
- 50 articles au maximum par collecte (voir [Reprise des articles](#reprise-des-articles))

## Ce qu'on a trouvé avec le premier modèle

### Le quota de requêtes, pas les tokens

Les logs de n8n montraient la vraie limite de notre clé pour `gemini-3-flash-preview` :

```
Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests,
limit: 20, model: gemini-3-flash, description: Generate content requests per day limit exceeded on Free Tier
```

20 requêtes par jour, pour la collecte et le chat ensemble. On collecte environ 180 articles par
jour (de 157 à 220 en semaine, moitié moins le week-end), et chaque lot coûte 2 requêtes (résumer,
puis évaluer) :

> requêtes par jour = 2 × collectes par jour × (nouveaux articles par collecte ÷ 10, arrondi au-dessus)

- **En local**, n8n ne tourne que quand le PC est allumé : environ 5 collectes par jour, 30 articles
  chacune, donc 3 lots, soit **30 à 36 requêtes par jour**.
- **En ligne**, la collecte tournerait toutes les heures : 7 ou 8 nouveaux articles par heure, donc
  1 lot incomplet par heure, soit **48 requêtes par jour**.

Le chat vient en plus : 1 à 3 requêtes par message pour l'agent.

Ce que ça a donné :

- 25 collectes sur 68 se sont arrêtées sur un refus de Gemini, toutes sur `Classer et résumer` :
  19 « too many requests », 4 « service unavailable », 2 autres erreurs de l'API.
- **654 articles sur 2 930 (22 %) n'ont jamais été résumés.** Quand Gemini refuse, la collecte
  s'arrête. Les articles restants sont déjà en base, et le filtre de l'époque ne laissait passer
  que ceux qui venaient d'être insérés : ils n'étaient jamais repris. Corrigé le 14/11 (voir
  [Reprise des articles](#reprise-des-articles)).
- La limite globale du chat (600 messages par jour, tout le monde) a été réglée « sous le quota
  Gemini ». Le vrai quota était 30 fois plus bas : avec ce modèle, elle ne protégeait rien.

**Avec le nouveau modèle** : au moins 31 requêtes le 14/11 (19 pour l'agent, 12 pour la collecte,
sans compter l'intention) et aucun refus. On ne connaît pas encore sa limite exacte : si elle est
atteinte, les logs la donneront (`docker compose logs n8n | grep "Quota exceeded"`).

### L'évaluation prenait 92 % du temps

Dans la plus longue collecte réussie (79 articles, 8 lots, 27 minutes), résumer a pris 125 s et
évaluer 1 506 s. Sur toutes les collectes, un appel d'évaluation durait 161 s en moyenne, contre
19 s pour un résumé, alors qu'il écrivait trois fois moins de tokens.

On avait deux pistes :

- **les réessais après un refus** : l'évaluation part juste après le résumé, et les mêmes
  exécutions contenaient des refus « too many requests ». Le nœud réessaie alors tout seul, en
  attendant de plus en plus longtemps.
- **la réflexion du modèle** : `gemini-3-flash-preview` « réfléchit » avant de répondre. On l'avait
  vu sur l'agent : 577 tokens de réflexion pour 23 de réponse (voir [prompts-IA.md](prompts-IA.md)).
  Vérifier chaque fait demande sans doute plus de réflexion que résumer. Ces tokens de réflexion
  n'apparaissent pas dans le compteur de n8n.

**Avec le nouveau modèle**, un appel d'évaluation dure 1 à 2 s : le problème venait bien de l'ancien
modèle. On ne saura pas laquelle des deux pistes était la bonne, puisqu'on ne l'utilise plus.

## Reprise des articles

Depuis le 14/11, un article dont le lot a échoué est repris à la collecte suivante. Après
`Enregistrer les articles`, le nœud `Articles à résumer` cherche en base les articles à résumer,
au lieu de ne prendre que ceux qu'on vient d'insérer :

| Choix | Pourquoi |
|---|---|
| ni résumé ni thème (`summary IS NULL AND tags = '{}'`) | un article passé par l'évaluation a toujours des thèmes, même s'il a été rejeté : on ne repaie pas un résumé déjà refusé |
| collectés depuis 24 h | l'envoi ne prend que ces articles-là : résumer les plus vieux ne servirait à rien |
| les plus récents d'abord | si la liste est coupée, on garde les plus utiles ; et un article qui ferait planter Gemini à chaque fois ne bloque que les lots qui viennent après lui |
| 50 au maximum par collecte (5 lots, 10 requêtes) | après une journée sans Gemini, une seule collecte n'envoie pas 40 requêtes d'un coup : le reste attend la suivante |
| `alwaysOutputData` sur `Enregistrer les articles` | sans nouvel article, ce nœud ne sort rien et la suite ne tournait pas : les articles en attente seraient restés en attente |

Ça ne coûte aucune requête de plus : ce sont des articles qu'on aurait dû résumer de toute façon.

**Résultat.** Le 14/11 à 16 h 37 (heure de Paris), 42 articles des dernières 24 h n'avaient jamais
été résumés. La collecte suivante (16 h 41) en a pris 46 (les 42 en attente et 4 nouveaux), en
5 lots, sans erreur : il n'en restait plus aucun. Les deux collectes d'après, sans nouvel article,
ont quand même vérifié les articles en attente, n'en ont trouvé aucun et se sont arrêtées en 1 s.

Pour vérifier à nouveau :

```sql
SELECT count(*) FILTER (WHERE summary IS NULL AND tags = '{}') AS jamais_resumes,
       count(*) FILTER (WHERE summary IS NULL AND tags <> '{}') AS rejetes,
       count(*) FILTER (WHERE summary IS NOT NULL) AS resumes
FROM articles
WHERE fetched_at > now() - INTERVAL '24 hours';
```

`jamais_resumes` doit retomber à 0 après une collecte qui se passe bien.

Limites :

- si deux collectes tournent en même temps (une collecte qui dure plus d'une heure), elles peuvent
  prendre les mêmes articles. L'article est alors résumé deux fois : des tokens perdus, mais pas de
  donnée fausse ;
- un article qui ferait planter Gemini à chaque fois serait repris pendant 24 h, puis abandonné.

## Pistes

Les pistes 1 et 3 sont faites. Les gains sont calculés pour 180 articles par jour.

| Piste | Gain | Ce que ça coûte |
|---|---|---|
| 1. ~~Reprendre les articles sans résumé~~ (fait le 14/11) | plus aucun article perdu | voir [Reprise des articles](#reprise-des-articles) |
| 2. Des lots plus gros, une collecte moins souvent | de 48 à 8-12 requêtes par jour | voir le tableau plus bas ; moins urgent si le quota du nouveau modèle tient |
| 3. ~~Choisir le modèle dans les nœuds~~ (fait le 14/11) | une mise à jour de n8n ne change plus le modèle ni le quota en silence | voir [Les deux modèles essayés](#les-deux-modèles-essayés) |
| 4. Ne pas appeler l'IA relectrice quand le contrôle automatique a tout rejeté | 1 requête de moins par lot entièrement rejeté | rare : 1 seul rejet automatique mesuré |
| 5. Régler la limite globale du chat sur le vrai quota | la limite protège vraiment le quota | il faut d'abord connaître le quota du nouveau modèle |
| 6. Passer à une clé payante | plus de quota par jour | le prix dépend alors des tokens : les chiffres plus haut permettent de l'estimer |

**2.** Pour 180 articles par jour :

| Collecte | Taille des lots | Requêtes par jour |
|---|---|---|
| toutes les heures (aujourd'hui, une fois en ligne) | 10 | 48 |
| toutes les 4 h | 10 | 36 |
| toutes les 4 h | 30 | 12 |
| toutes les 6 h | 50 | 8 |

Des lots plus gros coûtent aussi un peu moins de tokens (les 430 tokens fixes sont partagés par
plus d'articles). En contrepartie, un article peut être résumé jusqu'à 6 h après sa parution et
rater la newsletter du matin (il passe alors dans celle du lendemain), un refus de Gemini retarde
plus d'articles d'un coup, et une réponse plus longue a plus de chances d'arriver mal formée.

## Comment on a mesuré

- **Durées** : table `execution_entity` de la base `n8n` (`startedAt`, `stoppedAt`), et le temps de
  chaque nœud dans `execution_data`.
- **Tokens et modèle utilisé** : ce que chaque nœud Gemini enregistre dans `execution_data`
  (`tokenUsage`, et le nom du modèle dans les options de l'appel). Les tokens fixes et par article
  viennent d'une régression sur les 182 lots de l'ancien modèle (tailles de 1 à 10 articles).
- **Articles par jour, articles sans résumé et taux de rejet** : table `articles` de la base
  `persona`. Un article qui a des thèmes mais pas de résumé a été rejeté par l'évaluation. Le taux
  de l'ancien modèle part du 07/11, jour où l'évaluation a été ajoutée.
- **Quota et refus** : `docker compose logs n8n | grep "Quota exceeded"`.

Limites : n8n n'a gardé que les exécutions de quand le PC était allumé, `[A] Chat - Intention`
n'enregistre pas ses exécutions, les tokens de réflexion de l'ancien modèle n'étaient peut-être pas
comptés, et le nouveau modèle n'est mesuré que sur quelques heures.
