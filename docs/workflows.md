# Les workflows

Comment Persona marche à l'intérieur : ce que fait chaque workflow, et d'où viennent les news.
Pour installer et utiliser Persona, voir le [README](../README.md).

| Workflow                    | Fichier                        | Quand                          | Credentials      |
| --------------------------- | ------------------------------ | ------------------------------ | ---------------- |
| `[A] Chat - Entrée`         | `a_chat_entree.json`           | à chaque message du chat       | Postgres, SMTP   |
| `[A] Chat - Agent`          | `a_chat_agent.json`            | appelé par `Chat - Entrée`     | Postgres, Gemini |
| `[A] Chat - Intention`      | `a_chat_intention.json`        | appelé par `Chat - Entrée`     | Gemini           |
| `[B] News - Collecte`       | `b_news_collecte.json`         | toutes les heures à h52        | Postgres, Gemini |
| `[B] News - Envoi`          | `b_news_envoi.json`            | toutes les 5 minutes           | Postgres, SMTP   |
| `[B] News - Désinscription` | `b_news_desinscription.json`   | lien `/unsubscribe` des emails | Postgres         |
| `[Commun] Maintenance RGPD` | `commun_maintenance_RGPD.json` | tous les jours à 3 h           | Postgres         |

L'ordre de publication est à l'[étape 4 du README](../README.md#4-publier-les-workflows).

Les 4 nœuds Gemini utilisent le même modèle, `gemini-3.5-flash-lite`, écrit dans chaque nœud. Pour
en changer, il faut changer les 4 : un test le vérifie. Le choix, et les mesures des deux modèles
essayés, sont dans [optimisation-IA.md](optimisation-IA.md#les-deux-modèles-essayés).

## `[A] Chat - Entrée`

Le chat se fait depuis la page http://localhost:8090 (fichier `web/index.html`, servi par
le conteneur `web`). Il y a aussi la page de chat de n8n, sans mise en forme :
http://localhost:5678/webhook/9d5a3c0e-6c1e-4b6e-9a53-2f0c7a8f4a11/chat

Les commandes du chat et ce que l'agent sait régler sont dans le
[README](../README.md#5-utiliser-le-chatbot). L'inscription en une ligne (`inscription EMAIL
MOT_DE_PASSE`) n'existe plus : elle créait le compte sans vérifier l'email. Le code envoyé par
email est détaillé dans [code-inscription.md](code-inscription.md).

On peut aussi écrire une phrase normale, comme « je voudrais créer un compte » ou « comment je
récupère mes données ? » : `[A] Chat - Intention` comprend ce qu'on veut et le chatbot fait la même
chose que pour la commande. Pour supprimer son compte, il faut dans tous les cas taper exactement
`confirmer suppression`.

Les messages qui passent par l'IA sont limités : 6 par minute et par session, puis des limites
par jour (par session, par compte, pour les non connectés ensemble, et en tout). Les commandes
exactes ne sont pas limitées. Détails dans
[protection-deni-of-service.md](protection-deni-of-service.md).

Tout ce qui touche à la connexion est fait en SQL, sans l'IA. Le mot de passe est haché
avec bcrypt, il fait au moins 12 caractères, et 5 erreurs bloquent le compte 15 minutes.
Une session dure 2 h sans activité (8 h maximum). Sur la page, le mot de passe est masqué
quand on le tape et affiché `••••••••` dans la conversation.

Ce workflow et `[A] Chat - Intention` n'enregistrent pas leurs exécutions, parce que les
messages contiennent des mots de passe. n8n garde quand même chaque exécution, invisible, jusqu'à
son nettoyage suivant : `docker-compose.yml` le règle sur toutes les minutes
(`EXECUTIONS_DATA_PRUNE_HARD_DELETE_INTERVAL`). Pour déboguer, on peut réactiver la sauvegarde
dans les _Settings_ du workflow, le temps du test.

## `[A] Chat - Intention`

Appelé par `[A] Chat - Entrée` pour les phrases courtes (200 caractères ou moins), connecté ou non,
quand elles ne sont pas une commande exacte. Gemini classe la phrase dans une liste fermée (`inscription`, `connexion`,
`deconnexion`, `mes_donnees`, `supprimer_compte`, `confidentialite`, `aide`, `annuler`, `aucune`).
Il y a deux prompts, choisis par le nœud `Choisir le prompt` : pour un visiteur, Gemini écrit aussi
une réponse courte et naturelle (sans lien), que le chatbot affiche à la place de sa phrase habituelle ;
pour un abonné, il donne seulement le mot, puisque l'agent répond au reste (sauf pour `aide`, où il
rédige aussi la réponse). Gemini n'a aucun outil et ne voit
jamais un mot de passe. Les étapes sensibles (inscription, mot de passe, suppression, politique de
confidentialité) gardent leurs phrases fixes. Si Gemini ne répond pas, le chatbot garde sa phrase habituelle.

## `[A] Chat - Agent`

Agent Gemini avec 9 outils : `lire_preferences`, `modifier_interets`, `modifier_horaire`,
`modifier_email`, `activer_newsletter`, `modifier_style`, `exclure_source`, `reinclure_source`,
`donner_feedback`.

L'identifiant de l'utilisateur vient de la session, jamais de l'IA : même si on manipule
le modèle, il ne peut toucher qu'au compte connecté. Les centres d'intérêt doivent faire
partie des thèmes de la collecte (`sport`, `technologie`…).

Le prompt de l'agent change selon l'étape de l'utilisateur, lue en base par `Lire l'étape` : newsletter
en pause, choisir ses sujets (1 sur 3), régler la première newsletter (2 sur 3), donner son avis
(3 sur 3), ou tout est réglé. Chaque étape a son objectif et annonce la suivante. Le prompt contient
aussi les préférences actuelles, la date et l'heure, le premier créneau d'envoi possible et le
prochain envoi prévu (calculés par le code, avec la règle des 20 h de `[B] News - Envoi`), et suit
le ton choisi par l'utilisateur. L'heure d'envoi se règle par créneaux de 5 minutes : `modifier_horaire`
refuse une minute qui n'est pas 0, 5, 10… 55, et le prompt demande d'arrondir au créneau suivant. Les étapes et les versions
successives des prompts sont dans [prompts-IA.md](prompts-IA.md).

Les protections et les tests sont détaillés dans [audit-securite/audit-secu.md](audit-securite/audit-secu.md).

## `[B] News - Collecte`

1. Toutes les heures à h52, lit les 4 flux RSS (voir [Sources de news](#sources-de-news)) et
   ne garde que les articles publiés depuis moins de 48 h. L'ancre `#...` est retirée des URL.
   h52 n'est jamais un créneau d'envoi, et la collecte (une vingtaine de secondes) est finie
   avant les envois de h00, les plus courants. Avant, elle partait à h00 en même temps que
   l'envoi, qui ne voyait donc jamais les articles de l'heure.
2. Insère dans `articles` avec `ON CONFLICT (url) DO NOTHING` : un article déjà
   connu n'est pas réinséré. Puis `Articles à résumer` prend les articles des
   dernières 24 h qui n'ont encore **ni résumé ni thème** : les nouveaux, et ceux
   dont le lot a échoué à une collecte précédente (Gemini indisponible, quota
   épuisé). Les plus récents d'abord, 50 au maximum ; le reste attend la collecte
   suivante. Un article rejeté par l'évaluation a des thèmes : il n'est pas repris.
3. Par lots de 10, Gemini (température 0.2, sortie JSON structurée) donne à chaque
   article 1 à 3 thèmes et un résumé factuel en français (2 phrases max, traduit
   si l'article est en anglais).
4. **Contrôle automatique** (`Contrôler les résumés`, sans IA) : rejette un résumé
   absent, vide, de plus de 500 caractères ou de plus de 3 phrases, pas en français,
   ou qui contient du HTML, un lien ou des traces d'injection de prompt.
5. **Relecture par l'IA** (`Évaluer les résumés`, Gemini température 0) : une
   deuxième requête compare chaque résumé restant au titre et au texte de l'article.
   Le résumé doit être fidèle (rien d'inventé), en français, neutre, et ne parler que
   de l'article. Si Gemini ne répond pas (quota), seul le contrôle automatique s'applique.
6. Enregistre `tags` et `summary` dans `articles`. Un résumé rejeté n'est pas
   enregistré : l'article garde ses thèmes mais n'a pas de résumé, donc il n'est
   jamais envoyé. Les rejets sont notés dans `audit_log` (événement `summary_review`,
   avec l'id de l'article et la raison).

La relecture coûte une requête Gemini de plus par lot de 10 articles.

Thèmes autorisés : `politique`, `international`, `économie`, `société`, `sport`,
`culture`, `technologie`, `science`, `espace`, `santé`, `environnement`,
`jeux-vidéo`, `faits-divers`, `autre`.

Protection contre l'injection de prompt : le prompt précise que le texte des
articles est une donnée, jamais une instruction, et la requête SQL ne fait pas
confiance à la réponse de l'IA : les thèmes hors liste sont ignorés (`autre` si
aucun ne reste), le résumé est tronqué à 500 caractères et seuls les articles
du lot en cours peuvent être modifiés.

## `[B] News - Envoi`

1. Toutes les 5 minutes, sélectionne les utilisateurs dont l'abonnement est actif
   (`is_active`) et dont le jour (`send_days`), l'heure (`send_hour`) et la minute
   (`send_minute` : 0, 5, 10… 55) d'envoi correspondent au créneau actuel **dans leur
   fuseau** (`timezone`). Un utilisateur déjà servi il y a moins de 20 h est ignoré
   (pas de double envoi, même s'il vient de changer d'heure).
2. Choisit ses `max_articles` articles les plus récents (5 par défaut) dont les
   thèmes croisent ses `interests`, qui ont un résumé et ont été collectés dans
   les dernières 24 h. Les sources exclues dans le chat (`excluded_sources`) sont
   retirées avant de compter : l'utilisateur reçoit quand même `max_articles` articles.
   Aucun article = aucun email.
3. Construit un email HTML avec un lien de désinscription personnel. La mise en
   page suit le `format` choisi dans le chat :

   | `format`              | Pour chaque article                                                               |
   | --------------------- | --------------------------------------------------------------------------------- |
   | `titres`              | titre cliquable et source                                                         |
   | `resume` (par défaut) | titre cliquable, source et résumé                                                 |
   | `detaille`            | titre cliquable, source, heure de publication (dans son fuseau), thèmes et résumé |

   Le titre, la source et le résumé sont échappés, et les articles dont le lien
   n'est pas en `http(s)://` sont écartés. Le ton (`tone`) ne sert qu'à l'agent du
   chat : l'email ne change pas de ton (il faudrait un appel à Gemini par abonné,
   voir [optimisation-IA.md](optimisation-IA.md)).

4. **Vérifie l'email avant l'envoi** (`Vérifier l'email`) : destinataire valide,
   au moins un article, lien de désinscription présent, aucune balise dangereuse
   (`<script>`, `onerror=`…) et uniquement des liens `http(s)`. Si un point échoue,
   l'email n'est pas envoyé et un événement `newsletter_blocked` est ajouté dans
   `audit_log` avec la liste des problèmes.
5. Envoie l'email (sans la mention « This email was sent automatically with n8n »
   que n8n ajoute par défaut), l'enregistre dans `sent_newsletters` (avec les articles
   réellement envoyés) et met à jour `last_sent_at`.

À adapter si on sort du local : l'adresse d'expéditeur dans le nœud `Envoyer la newsletter`,
et l'URL du lien de désinscription (`http://localhost:5678/...` dans `Construire l'email`)
si n8n est exposé ailleurs.

## `[B] News - Désinscription`

Lien présent dans chaque newsletter :
`http://localhost:5678/webhook/unsubscribe?token=<unsubscribe_token>`

1. Vérifie que le jeton est un UUID bien formé avant toute requête en base.
2. Cherche l'utilisateur par `users.unsubscribe_token`.
3. Passe `preferences.is_active` à `false` (les données restent, la suppression
   du compte est gérée à part) et ajoute un événement `unsubscribed` dans `audit_log`.
4. Répond par une page HTML de confirmation.

Jeton mal formé ou inconnu : même page « Lien invalide » dans les deux cas,
pour ne pas révéler si un jeton existe.

```bash
curl "http://localhost:5678/webhook/unsubscribe?token=00000000-0000-0000-0000-000000000000"
# -> page « Lien invalide »
```

## `[Commun] Maintenance RGPD`

Chaque nuit à 3 h, ajoute un événement `night_cleanup` dans `audit_log` (avec le nombre
d'articles, d'envois et de sessions à supprimer), puis appelle `SELECT persona_cleanup();`.
Ce qui est supprimé :

- les comptes désabonnés : 6 mois après la désinscription (la date est notée toute seule en base)
- `sessions` : une fois expirées
- `auth_pending` (inscription ou connexion en cours) : après 1 heure
- `chat_ai_requests` (comptage des messages vers l'IA) : après 2 jours
- `articles` : après 30 jours
- `sent_newsletters` : après 6 mois
- `audit_log` et `feedback` : après 1 an

`persona_app` n'a pas le droit de supprimer dans `audit_log` : la fonction est
`SECURITY DEFINER` et s'exécute avec les droits de son propriétaire.

## Sources de news

Persona lit 4 flux RSS, listés dans le nœud `Liste des sources` de `[B] News - Collecte` :

| Source      | Flux                                   | Langue                   | Part des articles | Thèmes les plus fréquents                       |
| ----------- | -------------------------------------- | ------------------------ | ----------------- | ----------------------------------------------- |
| Le Monde    | https://www.lemonde.fr/rss/une.xml     | français                 | 23 %              | politique, international, société, économie     |
| France Info | https://www.francetvinfo.fr/titres.rss | français                 | 34 %              | société, politique, international, faits-divers |
| Numerama    | https://www.numerama.com/feed/         | français                 | 15 %              | technologie, économie, jeux-vidéo, culture      |
| BBC News    | https://feeds.bbci.co.uk/news/rss.xml  | anglais (résumé traduit) | 28 %              | international, société, politique, sport        |

Parts et thèmes mesurés le 14/11/2026 sur les 3 019 articles en base (les 30 derniers jours au
plus).

Choix : des thèmes variés pour que le filtrage par intérêts ait du sens, et une source anglophone
pour l'international. La newsletter ne contient qu'un résumé et un lien vers l'article original
(respect du droit d'auteur).

Dans le chat, un abonné peut exclure une source (« je ne veux plus de Le Monde ») et la remettre
plus tard (« remets Le Monde »). L'agent utilise `exclure_source` et `reinclure_source`, qui
acceptent aussi `lemonde`, `franceinfo`, `francetvinfo` et `bbc`.

**Ajouter une source**, à faire partout en même temps :

1. le flux dans `Liste des sources` (`[B] News - Collecte`) ;
2. le nom et ses variantes dans la liste `VALUES` de `exclure_source` **et** de `reinclure_source`
   (`[A] Chat - Agent`) : les deux listes doivent être les mêmes, sinon on pourrait exclure une
   source sans pouvoir la remettre ;
3. le nom dans la description de ces deux outils et dans les « Valeurs autorisées » du prompt
   (`Choisir le prompt`, même workflow).

Pour vérifier un flux :

```bash
curl -sL -A "Mozilla/5.0" https://feeds.bbci.co.uk/news/rss.xml | head -c 300
```

La réponse doit commencer par `<?xml`. Si un site refuse la requête, garder `-A "Mozilla/5.0"` :
certains sites bloquent les requêtes qui n'ont pas l'air de venir d'un navigateur.
