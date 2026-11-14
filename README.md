# Persona

Chatbot (A) et newsletter personnalisée (B), faits avec n8n et PostgreSQL.

On s'inscrit dans le chat, on choisit ses centres d'intérêt, et on reçoit un résumé de
l'actualité par email, aux jours et à l'heure qu'on veut.

## Lancer le projet

### Ce qu'il faut

- **Docker** : Docker Desktop sous Windows et macOS, Docker Engine avec le plugin Compose sous Linux
- **Git**
- **Sous Windows** : WSL 2 avec Ubuntu, et Docker Desktop avec l'intégration WSL activée. Toutes
  les commandes se tapent dans le terminal Ubuntu, et le projet se clone dans Ubuntu (`~`), pas dans `C:`.
- **Des ports libres** : 5432 (base), 5678 (n8n), 8025 (emails), 8090 (chatbot). Ils ne sont
  ouverts que sur la machine (`127.0.0.1`), pas sur le réseau
- **Aucun nœud communautaire** : Persona n'utilise que les nœuds fournis avec n8n (image
  `n8nio/n8n:2.44.7`), il n'y a rien à installer dans n8n. Les données sont dans PostgreSQL, que
  `setup.sh` prépare tout seul (étape 1)
- **Une clé API Gemini**, gratuite sur https://aistudio.google.com/apikey. Sans clé, l'inscription
  et la connexion marchent, mais pas l'agent ni la collecte des news. Le quota gratuit est compté
  par modèle : Persona utilise `gemini-3.5-flash-lite` (voir [docs/optimisation-IA.md](docs/optimisation-IA.md)).
- **Python 3**, seulement pour exporter des workflows (voir [Travailler à deux](#travailler-à-deux))

### 1. Démarrer

```bash
git clone <url-du-repo> persona
cd persona
bash scripts/setup.sh
```

La première fois, le script crée le fichier `.env` et s'arrête. Ouvrir `.env` et remplacer :

- `POSTGRES_PASSWORD` et `PERSONA_DB_PASSWORD` : deux mots de passe au choix
- `N8N_ENCRYPTION_KEY` : le résultat de `openssl rand -hex 32`

Puis relancer `bash scripts/setup.sh`. Il démarre les conteneurs (la première fois, Docker
télécharge les images : quelques minutes), prépare la base et importe les workflows dans n8n.

Le `.env` ne doit jamais être commit (il est dans `.gitignore`). Ne plus changer
`N8N_ENCRYPTION_KEY` ensuite : n8n ne pourrait plus lire ses credentials.

### 2. Créer les credentials dans n8n

Ouvrir http://localhost:5678. La première fois, n8n demande de créer un compte : c'est un compte
local, qui ne sert qu'à cette installation.

Puis _Create_ → _Credential_, trois fois. **Les noms doivent être exactement ceux-ci** : c'est grâce
à eux que n8n branche les workflows dessus.

| Nom                | Type                    | Réglages                                                                                                                                       |
| ------------------ | ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `Postgres Persona` | Postgres                | Host `postgres`, Database `persona`, User `persona_app`, Password : la valeur de `PERSONA_DB_PASSWORD` dans `.env`, Port `5432`, SSL `Disable` |
| `SMTP Persona`     | SMTP                    | Host `mailpit`, Port `1025`, SSL/TLS désactivé, User et Password vides                                                                         |
| `LLM Persona`      | Google Gemini(PaLM) Api | API Key : la clé Gemini (laisser le Host par défaut)                                                                                           |

n8n utilise `persona_app` et pas le compte admin : même si un attaquant détourne une requête,
il ne peut pas supprimer de tables.

Avec ces réglages, aucun email ne part vraiment : ils arrivent tous dans Mailpit, une fausse boîte
mail, sur http://localhost:8025. Pour envoyer de vrais emails avec Gmail, régler `SMTP Persona` sur :
Host `smtp.gmail.com`, Port `465`, SSL/TLS activé, User l'adresse Gmail, Password un
[mot de passe d'application](https://myaccount.google.com/apppasswords). Changer aussi l'adresse
d'expéditeur dans les nœuds `Envoyer le code` et `Envoyer la newsletter`.

### 3. Brancher les workflows sur les credentials

```bash
bash scripts/workflows.sh import # Git -> n8n : tous les workflows
```

```bash
bash scripts/workflows.sh import b_news_envoi  # Git -> n8n : un seul
```

Cette commande réimporte les workflows du dossier `workflows/`. Au passage, n8n branche chaque
nœud sur le credential du même nom.

### 4. Publier les workflows

Dans n8n, ouvrir chaque workflow et cliquer sur _Publish_, dans cet ordre :

1. `[A] Chat - Agent` et `[A] Chat - Intention` d'abord : n8n refuse de publier `[A] Chat - Entrée`
   tant que les workflows qu'il appelle ne sont pas publiés
2. `[A] Chat - Entrée`
3. `[B] News - Collecte`, `[B] News - Désinscription` et `[Commun] Maintenance RGPD`
4. `[B] News - Envoi` seulement si on veut envoyer les newsletters (elles arrivent dans Mailpit)

Puis, la première fois, ouvrir `[B] News - Collecte` et cliquer sur _Execute workflow_ (moins
d'une minute). Sinon la base n'a aucun article jusqu'à la première collecte automatique, à h52, et
aucune newsletter ne peut partir.

C'est prêt :

- **chatbot** : http://localhost:8090, cliquer sur la bulle et taper `inscription`
- **emails** : http://localhost:8025, où arrive le code d'inscription

### 5. Tester un envoi programmé

Les newsletters partent par créneaux de 5 minutes : `[B] News - Envoi` passe à h00, h05, h10…
On peut donc régler un envoi quelques minutes plus tard et le voir arriver.

1. Vérifier que l'étape 4 est faite : `[B] News - Envoi` publié, et une collecte lancée à la main.
2. Dans le chat (http://localhost:8090) : `inscription`, puis suivre les étapes jusqu'au code
   reçu dans Mailpit.
3. Donner des sujets larges, pour être sûr d'avoir des articles : « politique, international et
   société ».
4. Demander un envoi dans quelques minutes : « envoie-moi la newsletter tous les jours dans 10
   minutes », ou une heure précise : « tous les jours à 14 h 35 ». L'agent arrondit au créneau
   suivant (14 h 32 devient 14 h 35) et répond avec la date et l'heure du prochain envoi.
5. À l'heure dite, la newsletter arrive dans Mailpit (http://localhost:8025) dans la minute. Dans
   n8n, l'onglet _Executions_ de `[B] News - Envoi` montre un passage toutes les 5 minutes.

Pour refaire le test avec le même compte : une seule newsletter part toutes les 20 h (pour ne pas
en envoyer deux le jour où on change d'heure), et l'agent le dit. Créer un autre compte, ou
effacer la date du dernier envoi :

```bash
docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d persona -c "UPDATE preferences SET last_sent_at = NULL"'
```

Si rien n'arrive : aucun article de moins de 24 h ne correspond aux sujets choisis (lancer une
collecte, ou choisir d'autres sujets), ou l'email a été bloqué par la vérification avant envoi
(`bash scripts/journal.sh` montre un événement `newsletter_blocked`).

### Au quotidien

| Pour...                                      | Faire                                                                                   |
| -------------------------------------------- | --------------------------------------------------------------------------------------- |
| arrêter                                      | `docker compose down`                                                                   |
| relancer                                     | `bash scripts/setup.sh`                                                                 |
| récupérer le travail de l'autre              | `git pull`, `bash scripts/setup.sh`, puis les étapes 3 et 4                             |
| mettre dans Git un workflow modifié dans n8n | `bash scripts/workflows.sh export <nom>` (voir [Travailler à deux](#travailler-à-deux)) |
| voir les derniers événements du journal      | `bash scripts/journal.sh` (ou `bash scripts/journal.sh 50`)                             |
| lancer les tests                             | `docker compose exec -T n8n node - < scripts/test_scenarios.js`                         |
| tout effacer et repartir de zéro             | `docker compose down -v`, puis les étapes 1 à 4                                         |

`bash scripts/setup.sh` met aussi la base à jour : le schéma est dans un seul fichier,
`db/schema/02-schema.sql`, et une base existante reçoit les nouvelles tables et colonnes sans
perdre ses données.

`docker compose down -v` efface tout : la base, mais aussi le compte n8n, les credentials et les
workflows de n8n.

### Si ça ne marche pas

| Ce qu'on voit                                                             | Quoi faire                                                                                                                                |
| ------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `port is already allocated` au démarrage                                  | un autre programme utilise un des ports (souvent un PostgreSQL installé sur l'ordinateur, sur 5432) : l'arrêter, puis relancer            |
| la page ne répond pas (Windows)                                           | garder Docker Desktop et un terminal Ubuntu ouverts                                                                                       |
| des nœuds en rouge dans n8n                                               | un credential n'a pas exactement le bon nom, ou a été créé après l'import : corriger le nom, puis refaire les étapes 3 et 4               |
| « Je n'ai pas pu envoyer l'email »                                        | vérifier les réglages de `SMTP Persona`, et que Mailpit tourne (`docker compose ps`)                                                      |
| « Désolé, je n'ai pas pu traiter votre demande »                          | clé Gemini absente ou invalide, ou quota Gemini du jour épuisé                                                                            |
| une collecte en erreur « too many requests », des articles sans résumé    | quota Gemini du jour épuisé : les articles sont repris à la collecte suivante (voir [`[B] News - Collecte`](#b-news---collecte), étape 2) |
| les réglages du chat (format, sources exclues) ne changent rien à l'email | `[B] News - Envoi` n'a pas été réimporté depuis : `bash scripts/workflows.sh import b_news_envoi`, puis le republier                      |
| « Error in workflow »                                                     | la base est arrêtée : relancer `bash scripts/setup.sh`                                                                                    |
| le chat répond comme une ancienne version                                 | une copie du workflow est publiée à la place de l'original : dans n8n, archiver la copie et publier l'original                            |
| autre chose                                                               | `docker compose logs n8n` montre les erreurs de n8n                                                                                       |

## Travailler à deux

Un workflow existe à deux endroits : **dans n8n**, où on le modifie, et **dans le dossier
`workflows/`**, qui est dans Git. Les deux ne se synchronisent pas tout seuls : on passe de l'un à
l'autre avec `scripts/workflows.sh`.

| Je veux...                                              | Commande                                         |
| ------------------------------------------------------- | ------------------------------------------------ |
| mettre dans Git un workflow que j'ai modifié dans n8n   | `bash scripts/workflows.sh export a_chat_entree` |
| mettre dans n8n les workflows récupérés avec `git pull` | `bash scripts/workflows.sh import`               |
| mettre dans n8n un seul workflow                        | `bash scripts/workflows.sh import b_news_envoi`  |

Le nom d'un workflow est celui de son fichier, sans `.json`. On peut en donner plusieurs à la
suite. `bash scripts/workflows.sh`, sans rien, affiche la liste.

| Workflow dans n8n           | Nom                       |
| --------------------------- | ------------------------- |
| `[A] Chat - Entrée`         | `a_chat_entree`           |
| `[A] Chat - Agent`          | `a_chat_agent`            |
| `[A] Chat - Intention`      | `a_chat_intention`        |
| `[B] News - Collecte`       | `b_news_collecte`         |
| `[B] News - Envoi`          | `b_news_envoi`            |
| `[B] News - Désinscription` | `b_news_desinscription`   |
| `[Commun] Maintenance RGPD` | `commun_maintenance_RGPD` |

### J'ai modifié un workflow dans n8n

```bash
bash scripts/workflows.sh export a_chat_entree  # n8n -> Git : exporte, nettoie, montre le diff
git diff workflows/a_chat_entree.json
```

Le script remplace le fichier par la version de n8n, puis le nettoie (voir plus bas).

**Lire le diff avant de commit** : il ne doit contenir que ses propres changements. S'il efface le
travail de l'autre, c'est que ce workflow n'avait pas été importé après le dernier `git pull`. Dans
ce cas, `git restore workflows/a_chat_entree.json` annule l'export. Importer alors le workflow,
puis refaire ses changements dans n8n.

Le script demande toujours un nom, pour n'exporter que les workflows qu'on a vraiment modifiés.

### L'autre a modifié un workflow

```bash
git pull
bash scripts/workflows.sh import
```

L'import remplace les workflows de n8n par ceux du dépôt :

- si on a modifié un de ces workflows dans n8n sans l'exporter, ces changements sont perdus :
  l'exporter avant
- les workflows importés sont dépubliés : les republier ensuite (étape 4)

Ne jamais importer avec _Import from File_ dans n8n : n8n en ferait une copie avec un nouvel id,
qui prendrait la place de l'original.

### Nettoyage et CI

`export` lance `scripts/sanitize.py` tout seul. Il retire ce qui ne doit pas aller dans Git
(données épinglées, en-têtes sensibles), et remet aux credentials leur nom d'équipe pour que
l'import marche chez l'autre. S'il affiche `!!`, c'est un secret probable : le retirer à la main
avant de commit.

À chaque PR, la CI de GitHub (`.github/workflows/ci.yml`) relance `sanitize.py` et les tests. La PR
passe en rouge si un workflow n'a pas été nettoyé, contient un secret, ou si un test échoue.

### Ajouter un nouveau workflow

Le script ne connaît que les workflows qui ont déjà un fichier dans `workflows/`. La première fois,
exporter à la main, avec l'id qu'on trouve dans l'URL du workflow dans n8n (`/workflow/<id>`) :

```bash
docker compose exec -T n8n n8n export:workflow --id=<id> --output=/home/node/exports/<nom>.json
python3 scripts/sanitize.py workflows/<nom>.json
```

Ensuite, `bash scripts/workflows.sh export <nom>` suffit.

## Conventions d'équipe

**Workflows** : le préfixe indique qui s'en occupe (`[A]`, `[B]`, `[Commun]`). Un workflow par
fichier dans `workflows/`.

**Credentials** : seulement les trois credentials de l'étape 2, avec ces noms exacts, jamais de nom
ou d'email perso.

**Nœuds** : chaque nœud a un nom avec un verbe (`Vérifier la session`, `Préparer le code`…),
jamais `Postgres1` ou `Code3`.

**Base de données** : pas de modification du schéma sans accord des deux. Les mots de passe se
hachent en SQL, jamais dans un nœud Code :

```sql
-- à la création du compte
crypt($2, gen_salt('bf', 12))
-- à la connexion
SELECT id FROM users WHERE email = $1 AND password_hash = crypt($2, password_hash);
```

Toujours passer par les **paramètres de requête** (`$1`, `$2`, option _Query Parameters_
du nœud Postgres), jamais de concaténation : c'est ce qui protège de l'injection SQL.

## Les workflows

| Workflow                    | Fichier                        | Quand                          | Credentials      |
| --------------------------- | ------------------------------ | ------------------------------ | ---------------- |
| `[A] Chat - Entrée`         | `a_chat_entree.json`           | à chaque message du chat       | Postgres, SMTP   |
| `[A] Chat - Agent`          | `a_chat_agent.json`            | appelé par `Chat - Entrée`     | Postgres, Gemini |
| `[A] Chat - Intention`      | `a_chat_intention.json`        | appelé par `Chat - Entrée`     | Gemini           |
| `[B] News - Collecte`       | `b_news_collecte.json`         | toutes les heures à h52        | Postgres, Gemini |
| `[B] News - Envoi`          | `b_news_envoi.json`            | toutes les 5 minutes           | Postgres, SMTP   |
| `[B] News - Désinscription` | `b_news_desinscription.json`   | lien `/unsubscribe` des emails | Postgres         |
| `[Commun] Maintenance RGPD` | `commun_maintenance_RGPD.json` | tous les jours à 3 h           | Postgres         |

L'ordre de publication est à l'étape 4 de [Lancer le projet](#lancer-le-projet).

Les 4 nœuds Gemini utilisent le même modèle, `gemini-3.5-flash-lite`, écrit dans chaque nœud. Pour
en changer, il faut changer les 4 : un test le vérifie. Le choix, et les mesures des deux modèles
essayés, sont dans [docs/optimisation-IA.md](docs/optimisation-IA.md#les-deux-modèles-essayés).

### `[A] Chat - Entrée`

Le chat se fait depuis la page http://localhost:8090 (fichier `web/index.html`, servi par
le conteneur `web`). Il y a aussi la page de chat de n8n, sans mise en forme :
http://localhost:5678/webhook/9d5a3c0e-6c1e-4b6e-9a53-2f0c7a8f4a11/chat

Ce qu'on peut écrire au chatbot :

- `inscription` : il demande l'email, si on accepte la politique de confidentialité, puis le mot de passe,
  puis envoie un code à 6 chiffres par email : le compte n'est créé qu'une fois ce code tapé dans le chat
  (`renvoyer le code` en envoie un autre, voir [docs/code-inscription.md](docs/code-inscription.md))
- `en savoir plus` : affiche la politique de confidentialité (celle de `docs/normes-RGPD.md`)
- `connexion` : il demande l'email puis le mot de passe
- `annuler` : arrête l'inscription ou la connexion en cours
- `deconnexion`
- `mes données` : affiche tout ce qu'on garde sur l'utilisateur
- `supprimer mon compte`, puis `confirmer suppression`
- `aide`
- n'importe quel autre message, une fois connecté : il part à l'agent

On peut aussi se connecter en une ligne : `connexion EMAIL MOT_DE_PASSE`. L'inscription en une ligne
n'existe plus : elle créait le compte sans vérifier l'email.

On peut aussi écrire une phrase normale, comme « je voudrais créer un compte » ou « comment je
récupère mes données ? » : `[A] Chat - Intention` comprend ce qu'on veut et le chatbot fait la même
chose que pour la commande. Pour supprimer son compte, il faut dans tous les cas taper exactement
`confirmer suppression`.

Les messages qui passent par l'IA sont limités : 6 par minute et par session, puis des limites
par jour (par session, par compte, pour les non connectés ensemble, et en tout). Les commandes
exactes ne sont pas limitées. Détails dans
[docs/protection-deni-of-service.md](docs/protection-deni-of-service.md).

Tout ce qui touche à la connexion est fait en SQL, sans l'IA. Le mot de passe est haché
avec bcrypt, il fait au moins 12 caractères, et 5 erreurs bloquent le compte 15 minutes.
Une session dure 2 h sans activité (8 h maximum). Sur la page, le mot de passe est masqué
quand on le tape et affiché `••••••••` dans la conversation.

Ce workflow et `[A] Chat - Intention` n'enregistrent pas leurs exécutions, parce que les
messages contiennent des mots de passe. n8n garde quand même chaque exécution, invisible, jusqu'à
son nettoyage suivant : `docker-compose.yml` le règle sur toutes les minutes
(`EXECUTIONS_DATA_PRUNE_HARD_DELETE_INTERVAL`). Pour déboguer, on peut réactiver la sauvegarde
dans les _Settings_ du workflow, le temps du test.

### `[A] Chat - Intention`

Appelé par `[A] Chat - Entrée` pour les phrases courtes (200 caractères ou moins), connecté ou non,
quand elles ne sont pas une commande exacte. Gemini classe la phrase dans une liste fermée (`inscription`, `connexion`,
`deconnexion`, `mes_donnees`, `supprimer_compte`, `confidentialite`, `aide`, `annuler`, `aucune`).
Il y a deux prompts, choisis par le nœud `Choisir le prompt` : pour un visiteur, Gemini écrit aussi
une réponse courte et naturelle (sans lien), que le chatbot affiche à la place de sa phrase habituelle ;
pour un abonné, il donne seulement le mot, puisque l'agent répond au reste (sauf pour `aide`, où il
rédige aussi la réponse). Gemini n'a aucun outil et ne voit
jamais un mot de passe. Les étapes sensibles (inscription, mot de passe, suppression, politique de
confidentialité) gardent leurs phrases fixes. Si Gemini ne répond pas, le chatbot garde sa phrase habituelle.

### `[A] Chat - Agent`

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
successives des prompts sont dans [docs/prompts-IA.md](docs/prompts-IA.md).

Les protections et les tests sont détaillés dans [docs/audit-securite/audit-secu.md](docs/audit-securite/audit-secu.md).

### `[B] News - Collecte`

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

### `[B] News - Envoi`

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
   voir [docs/optimisation-IA.md](docs/optimisation-IA.md)).

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

### `[B] News - Désinscription`

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

### `[Commun] Maintenance RGPD`

Chaque nuit à 3 h, appelle `SELECT persona_cleanup();` puis ajoute un événement
`retention_cleanup` dans `audit_log`. Ce qui est supprimé :

- les comptes désabonnés : 6 mois après la désinscription (la date est notée toute seule en base)
- `sessions` : une fois expirées
- `auth_pending` (inscription ou connexion en cours) : après 1 heure
- `chat_ai_requests` (comptage des messages vers l'IA) : après 2 jours
- `articles` : après 30 jours
- `sent_newsletters` : après 6 mois
- `audit_log` et `feedback` : après 1 an

`persona_app` n'a pas le droit de supprimer dans `audit_log` : la fonction est
`SECURITY DEFINER` et s'exécute avec les droits de son propriétaire.

## Tests

Avec Persona lancé :

```bash
docker compose exec -T n8n node - < scripts/test_scenarios.js
```

Ou sans Docker, comme la CI (Node.js 22) :

```bash
WORKFLOWS=workflows node scripts/test_scenarios.js
```

Le script lance le vrai code des nœuds des workflows, avec des réponses de Gemini écrites à la
main. Rien n'est écrit en base.

35 tests, qui doivent tous passer (`35 réussis, 0 ratés`). Le script les range comme les
workflows : un groupe par partie (A, B, Commun), puis une section par workflow, qui affiche les
nœuds qu'elle lance.

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

Le détail de chaque test, et ce qui n'est pas testé, est dans
[docs/tests-scenarios.md](docs/tests-scenarios.md).

Les tests ne remplacent pas un essai avec le vrai Gemini : ils ne vérifient ni la qualité des
résumés, ni ce que l'agent décide de faire. Les conversations à rejouer à la main sont dans
[docs/prompts-IA.md](docs/prompts-IA.md#tester-une-nouvelle-version).

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

## Documentation

- [docs/tests-scenarios.md](docs/tests-scenarios.md) : tous les tests, rangés par workflow, et ce qui n'est pas testé
- [docs/code-inscription.md](docs/code-inscription.md) : le code par email à l'inscription
- [docs/protection-deni-of-service.md](docs/protection-deni-of-service.md) : les limites de messages vers l'IA
- [docs/prompts-IA.md](docs/prompts-IA.md) : les prompts de l'agent et de l'intention, et leurs versions
- [docs/optimisation-IA.md](docs/optimisation-IA.md) : ce que coûte chaque workflow en temps et en tokens, et le quota Gemini
- [docs/audit-securite/audit-secu.md](docs/audit-securite/audit-secu.md) : l'audit de sécurité du chatbot et des workflows de B (13/11, avec une mise à jour du 14/11)
- [docs/audit-securite.md](docs/audit-securite.md) : la première version de l'audit (29/10)
- [docs/normes-RGPD.md](docs/normes-RGPD.md) : la politique de confidentialité et le registre des traitements
