# Optimisation du temps et des tokens

Mesures du 14/11/2026, sur les exécutions enregistrées par n8n du 31/10 au 13/11 : 68 collectes,
68 envois, 75 messages du chat et 19 appels de l'agent. Pendant ces mesures, le modèle était
`gemini-3-flash-preview` : aucun nœud n'en choisissait un, et n8n prenait son modèle par défaut.
Depuis le 14/11, les 4 nœuds Gemini utilisent `gemini-3.5-flash-lite` (voir
[Changement de modèle](#changement-de-modèle)).

## En bref

- La newsletter coûte des tokens une fois par article, pas une fois par abonné : l'envoi
  n'appelle jamais l'IA. Le coût ne bouge pas avec le nombre d'abonnés.
- Seul un tiers des articles lus dans les flux part vers l'IA : les autres sont déjà en base.
- Les lots de 10 articles divisent le nombre de requêtes par 10 et les tokens d'entrée par 3,6.
- Ce qui nous bloque, ce n'est pas le nombre de tokens mais le nombre de requêtes : la clé
  gratuite est limitée à **20 requêtes par jour** pour ce modèle, et la collecte seule en demande
  30 à 48.
- Conséquence : **22 % des articles collectés n'ont jamais été résumés**, et 25 collectes sur 68
  se sont arrêtées sur un refus de Gemini. Depuis le 14/11, ces articles sont repris à la
  collecte suivante.
- L'évaluation des résumés prend 92 % du temps de la collecte.

## Ce que coûte chaque partie

| Partie | Appels à Gemini | Tokens par appel (entrée / sortie) | Durée moyenne |
|---|---|---|---|
| Collecte : résumer un lot de 10 | 1 par lot | ~1 470 / ~980 | 19 s |
| Collecte : évaluer un lot | 1 par lot | ~1 930 / ~340 | 161 s |
| Envoi | 0 | - | 0,2 s |
| Chat : `[A] Chat - Entrée` | 0 pour les commandes | - | 0,8 s |
| Chat : agent | 1 à 3 par message | ~1 370 à 2 400 / 10 à 130 | 3,5 s |

`[A] Chat - Intention` n'est pas mesuré : n8n n'a enregistré aucune de ses exécutions.

L'agent fait un appel de plus à chaque outil utilisé, et chaque appel renvoie tout le prompt.
Un message qui modifie deux réglages coûte donc 3 appels (1 370, puis 2 000, puis 2 400 tokens
d'entrée).

## Ce qui est déjà optimisé

### 1. Un résumé par article, pas par abonné

`[B] News - Collecte` résume chaque article une seule fois. `[B] News - Envoi` ne fait que du SQL
et remplit un modèle d'email. Avec 1 000 abonnés, la collecte coûte autant qu'avec un seul.

C'est aussi ce qui rend le ton de chaque abonné coûteux : pour réécrire la newsletter dans son
ton, il faudrait un appel par abonné et par envoi.

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

`Par lots de 10` envoie 10 articles dans une seule requête. Sur les 182 lots mesurés, une requête
coûte environ **430 tokens fixes** (les consignes et le format de réponse) plus **104 tokens par
article**. Les consignes ne sont envoyées qu'une fois pour 10 articles :

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
  [protection-deni-de-service.md](protection-deni-de-service.md))

## Ce qui ne va pas encore

### Le quota de requêtes, pas les tokens

Les logs de n8n montrent la vraie limite de notre clé :

```
Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests,
limit: 20, model: gemini-3-flash, description: Generate content requests per day limit exceeded on Free Tier
```

20 requêtes par jour, pour la collecte et le chat ensemble. On collecte environ 180 articles par
jour (de 157 à 220 en semaine, moitié moins le week-end), et chaque lot coûte 2 requêtes (résumer, puis évaluer) :

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
  Gemini ». Le vrai quota est 30 fois plus bas : avec cette clé, elle ne protège rien.

### L'évaluation prend 92 % du temps

Dans la plus longue collecte réussie (79 articles, 8 lots, 27 minutes), résumer a pris 125 s et évaluer
1 506 s. Sur toutes les collectes, un appel d'évaluation dure 161 s en moyenne, contre 19 s pour un
résumé, alors qu'il écrit trois fois moins de tokens.

La cause n'est pas encore confirmée. Deux pistes :

- **les réessais après un refus** : l'évaluation part juste après le résumé, et les mêmes
  exécutions contiennent des refus « too many requests ». Le nœud réessaie alors tout seul, en
  attendant de plus en plus longtemps.
- **la réflexion du modèle** : `gemini-3-flash-preview` « réfléchit » avant de répondre. On l'a vu
  sur l'agent : 577 tokens de réflexion pour 23 de réponse (voir [prompts.md](prompts.md)). Vérifier
  chaque fait demande sans doute plus de réflexion que résumer. Ces tokens de réflexion
  n'apparaissent pas dans le compteur de n8n : si c'est la cause, nos chiffres de sortie sont
  sous-estimés.

Pour trancher : quand le quota est revenu, relancer seulement `Évaluer les résumés` avec des
données épinglées (comme dans [tests-evaluation.md](tests-evaluation.md)). Si l'appel dure encore
plus de 2 minutes sans aucun refus dans les logs, c'est la réflexion.

## Changement de modèle

Le 14/11, les 4 nœuds Gemini (`Google Gemini Chat Model` et `Modèle Gemini (évaluation)` dans la
collecte, `Modèle Gemini` dans l'agent et dans l'intention) passent à `gemini-3.5-flash-lite`, écrit
dans chaque nœud. On garde le même modèle partout.

Pourquoi :

- `gemini-3-flash-preview` est une préversion de décembre 2025, que Google conseille de remplacer.
  Une préversion peut changer ou disparaître, et elle tient moins bien la charge (4 « service
  unavailable » dans nos collectes).
- Le quota est compté par modèle (`limit: 20, model: gemini-3-flash` dans les logs). Google ne
  publie pas les quotas gratuits de chaque modèle, mais les relevés qu'on a trouvés donnent environ
  500 requêtes par jour aux modèles Flash-Lite, contre 20 pour les Flash 3.x. Avec un Flash, même
  avec la piste 2, il ne resterait presque rien pour le chat.
- Nos tâches sont simples : classer dans une liste fermée, résumer en 2 phrases, vérifier un
  résumé, régler des préférences avec des outils.
- Sans modèle écrit, n8n prend son modèle par défaut, qui change avec ses versions. Un test de
  `scripts/test_scenarios.js` vérifie maintenant que les 4 nœuds ont le même modèle, écrit en toutes
  lettres.

Ce qu'il reste à vérifier :

- **le quota réel** : s'il est dépassé, les logs de n8n donnent la limite
  (`docker compose logs n8n | grep "Quota exceeded"`).
- **l'agent du chat**, à la main : un Lite peut moins bien enchaîner les outils. À essayer : changer
  ses sujets, l'heure, exclure une source, deux changements dans le même message.
- **les mesures de cette page**, à refaire après quelques jours (tokens, durées, résumés rejetés par
  l'évaluation), pour comparer.

Premier essai à la main (14/11) : l'heure, les sujets, le style et l'exclusion d'une source
marchent, y compris deux changements dans le même message. Une erreur : pour « réinclure Le
Monde », que l'agent ne savait pas faire, il a exclu France Info à la place. On ne sait pas si un
autre modèle aurait fait mieux. C'est corrigé par un outil et une règle dans le prompt (voir
[prompts.md](prompts.md)), mais c'est le genre d'erreur à surveiller avec un modèle Lite.

Si l'agent se trompe trop, l'étape suivante est `gemini-3.8-flash` avec une clé payante : avec la clé
gratuite, son quota ne suffit pas.

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

Avant la correction, le 14/11 à 16 h 37 (heure de Paris), 42 articles des dernières 24 h n'avaient
jamais été résumés. Pour vérifier après quelques collectes :

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

Rien de cette partie n'est fait, sauf les pistes 1 et 3. Les gains sont calculés pour 180 articles
par jour.

| Piste | Gain | Ce que ça coûte |
|---|---|---|
| 1. ~~Reprendre les articles sans résumé~~ (fait le 14/11) | plus aucun article perdu | voir [Reprise des articles](#reprise-des-articles) |
| 2. Des lots plus gros, une collecte moins souvent | de 48 à 8-12 requêtes par jour | voir le tableau plus bas |
| 3. ~~Choisir le modèle dans les nœuds~~ (fait le 14/11) | une mise à jour de n8n ne change plus le modèle ni le quota en silence | voir [Changement de modèle](#changement-de-modèle) |
| 4. Ne pas appeler l'IA relectrice quand le contrôle automatique a tout rejeté | 1 requête de moins par lot entièrement rejeté | rare : 1 seul rejet automatique mesuré |
| 5. Régler la limite globale du chat sur le vrai quota | la limite protège vraiment le quota | moins de messages possibles par jour |
| 6. Passer à une clé payante | plus de quota par jour | le prix dépend alors des tokens : les chiffres plus haut permettent de l'estimer |

**2.** Pour 180 articles par jour :

| Collecte | Taille des lots | Requêtes par jour |
|---|---|---|
| toutes les heures (aujourd'hui, une fois en ligne) | 10 | 48 |
| toutes les 4 h | 10 | 36 |
| toutes les 4 h | 30 | 12 |
| toutes les 6 h | 50 | 8 |

Des lots plus gros coûtent aussi un peu moins de tokens (les 430 tokens fixes sont partagés par
plus d'articles). En contrepartie, un article peut être résumé jusqu'à 6 h après sa parution et rater
la newsletter du matin (il passe alors dans celle du lendemain), un refus
de Gemini fait perdre plus d'articles d'un coup (d'où la piste 1 avant celle-ci), et une réponse
plus longue a plus de chances d'arriver mal formée.

## Comment on a mesuré

- **Durées** : table `execution_entity` de la base `n8n` (`startedAt`, `stoppedAt`), et le temps de
  chaque nœud dans `execution_data`.
- **Tokens** : le `tokenUsage` que chaque nœud Gemini enregistre dans `execution_data`. Les tokens
  fixes et par article viennent d'une régression sur les 182 lots (tailles de 1 à 10 articles).
- **Articles par jour et articles sans résumé** : table `articles` de la base `persona`.
- **Quota** : `docker compose logs n8n | grep "Quota exceeded"`.

Limites : n8n n'a gardé que les exécutions de quand le PC était allumé, `[A] Chat - Intention`
n'a pas d'exécution enregistrée, et les tokens de réflexion du modèle ne sont peut-être pas comptés.
