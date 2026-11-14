# Optimisation du temps et des tokens

Mesures du 14/11/2026, sur les exécutions enregistrées par n8n du 31/10 au 13/11 : 68 collectes,
68 envois, 75 messages du chat et 19 appels de l'agent. Le modèle est `gemini-3-flash-preview` :
aucun nœud n'en choisit un, n8n prend donc son modèle par défaut.

## En bref

- La newsletter coûte des tokens une fois par article, pas une fois par abonné : l'envoi
  n'appelle jamais l'IA. Le coût ne bouge pas avec le nombre d'abonnés.
- Seul un tiers des articles lus dans les flux part vers l'IA : les autres sont déjà en base.
- Les lots de 10 articles divisent le nombre de requêtes par 10 et les tokens d'entrée par 3,6.
- Ce qui nous bloque, ce n'est pas le nombre de tokens mais le nombre de requêtes : la clé
  gratuite est limitée à **20 requêtes par jour** pour ce modèle, et la collecte seule en demande
  30 à 48.
- Conséquence : **22 % des articles collectés n'ont jamais été résumés**, et 25 collectes sur 68
  se sont arrêtées sur un refus de Gemini.
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
les URL inconnues (`ON CONFLICT DO NOTHING`), et `Nouveaux articles` ne laisse passer que ceux qui
viennent d'être insérés.

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
  s'arrête. Les articles restants sont déjà en base, et `Nouveaux articles` ne laisse passer que
  ceux qui viennent d'être insérés : ils ne sont jamais repris.
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
- **la réflexion du modèle** : `gemini-3-flash-preview` peut « réfléchir » avant de répondre, et vérifier
  chaque fait demande plus de réflexion que résumer. Ces tokens de réflexion n'apparaissent pas
  dans le compteur de n8n : si c'est la cause, nos chiffres de sortie sont sous-estimés.

Pour trancher : quand le quota est revenu, relancer seulement `Évaluer les résumés` avec des
données épinglées (comme dans [tests-evaluation.md](tests-evaluation.md)). Si l'appel dure encore
plus de 2 minutes sans aucun refus dans les logs, c'est la réflexion.

## Pistes

Rien de cette partie n'est fait. Les gains sont calculés pour 180 articles par jour.

| Piste | Gain | Ce que ça coûte |
|---|---|---|
| 1. Reprendre les articles sans résumé | plus aucun article perdu | aucune requête en plus : ce sont les mêmes articles |
| 2. Des lots plus gros, une collecte moins souvent | de 48 à 8-12 requêtes par jour | voir le tableau plus bas |
| 3. Choisir le modèle dans les nœuds | une mise à jour de n8n ne change plus le modèle ni le quota en silence | comparer les quotas des modèles sur la page des limites d'AI Studio |
| 4. Ne pas appeler l'IA relectrice quand le contrôle automatique a tout rejeté | 1 requête de moins par lot entièrement rejeté | rare : 1 seul rejet automatique mesuré |
| 5. Régler la limite globale du chat sur le vrai quota | la limite protège vraiment le quota | moins de messages possibles par jour |
| 6. Passer à une clé payante | plus de quota par jour | le prix dépend alors des tokens : les chiffres plus haut permettent de l'estimer |

**1.** Après `Enregistrer les articles`, on prendrait aussi les articles des dernières 24 h qui
n'ont ni résumé ni thème (`summary IS NULL AND tags = '{}'`). Un article rejeté par l'évaluation a des thèmes : il ne
serait pas renvoyé.

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
