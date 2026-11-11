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
- **Des ports libres** : 5432 (base), 5678 (n8n), 8025 (emails), 8090 (chatbot)
- **Facultatif** : une clé API Gemini, gratuite sur https://aistudio.google.com/apikey. Sans clé,
  l'inscription et la connexion marchent, mais pas l'agent ni la collecte des news.

### Démarrer

```bash
git clone <url-du-repo> persona
cd persona
bash scripts/setup.sh
```

C'est tout. La première fois, le script :

1. crée le fichier `.env`, avec des mots de passe générés
2. démarre les conteneurs (Docker télécharge les images : quelques minutes)
3. crée la base de données
4. crée les credentials de n8n (base, emails, Gemini)
5. importe les workflows et les publie

Ensuite :

- **chatbot** : http://localhost:8090, cliquer sur la bulle et taper `inscription`
- **emails** : http://localhost:8025 (Mailpit). Rien ne part vraiment : le code d'inscription et
  les newsletters arrivent ici.
- **n8n** : http://localhost:5678, pour voir et modifier les workflows. La première fois, n8n
  demande de créer un compte : c'est un compte local, qui ne sert qu'à cette installation.

Pour la clé Gemini : la coller après `GEMINI_API_KEY=` dans le fichier `.env`, puis relancer
`bash scripts/setup.sh`.

### Au quotidien

| Pour... | Commande |
|---|---|
| arrêter | `docker compose down` |
| relancer | `bash scripts/setup.sh` |
| récupérer le travail de l'autre | `git pull` puis `bash scripts/setup.sh --import` |
| exporter ses workflows modifiés dans n8n | `bash scripts/export.sh` (voir [Travailler à deux](#travailler-à-deux)) |
| voir les derniers événements du journal | `bash scripts/journal.sh` (ou `bash scripts/journal.sh 50`) |
| lancer les tests | `docker compose exec -T n8n node - < scripts/test_scenarios.js` |
| tout effacer et repartir de zéro | `docker compose down -v` puis `bash scripts/setup.sh` |

`--import` remplace les workflows de n8n par ceux du dossier `workflows/`. Si on a modifié un
workflow dans n8n sans l'exporter, le faire avant (`bash scripts/export.sh`).

`docker compose down -v` efface tout : la base, mais aussi le compte n8n, les credentials et les
workflows de n8n. Le script recrée tout.

### Si ça ne marche pas

| Ce qu'on voit | Quoi faire |
|---|---|
| `port is already allocated` au démarrage | un autre programme utilise un des ports (souvent un PostgreSQL installé sur l'ordinateur, sur 5432) : l'arrêter, puis relancer |
| `Docker ne répond pas` | lancer Docker Desktop, attendre qu'il soit prêt, puis relancer |
| la page ne répond pas (Windows) | garder Docker Desktop et un terminal Ubuntu ouverts |
| « Je n'ai pas pu envoyer l'email » | Mailpit est arrêté (`docker compose ps` pour vérifier), ou le credential `SMTP Persona` a été modifié dans n8n |
| « Désolé, je n'ai pas pu traiter votre demande » | pas de clé Gemini, clé invalide, ou quota Gemini du jour épuisé |
| « Error in workflow » | la base est arrêtée : relancer `bash scripts/setup.sh` |
| autre chose | `docker compose logs n8n` montre les erreurs de n8n |

### Ce que crée `setup.sh`

Le fichier `.env` garde les mots de passe. Il ne faut jamais le commit (il est dans `.gitignore`),
et ne plus changer `N8N_ENCRYPTION_KEY` après le premier lancement : n8n ne pourrait plus lire
ses credentials.

Les credentials de n8n, partagés par tous les workflows :

| Credential | Pour | Réglage en local |
|---|---|---|
| `Postgres Persona` | la base `persona` | host `postgres`, utilisateur `persona_app`, mot de passe `PERSONA_DB_PASSWORD` du `.env` |
| `SMTP Persona` | le code d'inscription et les newsletters | Mailpit (host `mailpit`, port 1025) |
| `LLM Persona` | Gemini | la clé `GEMINI_API_KEY` du `.env` |

n8n utilise `persona_app` et pas le compte admin : même si un attaquant détourne une requête,
il ne peut pas supprimer de tables.

`setup.sh` ne modifie jamais `Postgres Persona` et `SMTP Persona` une fois créés. `LLM Persona`
est mis à jour à chaque lancement si `GEMINI_API_KEY` est rempli.

Pour envoyer de vrais emails, modifier `SMTP Persona` dans n8n (_Credentials_). Avec Gmail :
host `smtp.gmail.com`, port 465, SSL/TLS activé, l'adresse Gmail comme utilisateur et un
[mot de passe d'application](https://myaccount.google.com/apppasswords) comme mot de passe.
Changer aussi l'adresse d'expéditeur dans les nœuds `Envoyer le code` et `Envoyer la newsletter`.

Le schéma de la base est dans un seul fichier, `db/schema/02-schema.sql`. Docker le lance à la
création de la base, et `setup.sh` le relance à chaque fois : une base existante reçoit les
nouvelles tables et colonnes sans perdre ses données.

## Travailler à deux

Les workflows se modifient dans n8n, puis s'exportent dans le dossier `workflows/` pour Git :

```bash
bash scripts/export.sh        # exporte chaque workflow dans son fichier, puis le nettoie
git diff workflows/           # vérifier ce qui a changé
git add workflows && git commit -m "..." && git push
```

`export.sh` lance `scripts/sanitize.py`, qui retire ce qui ne doit pas aller dans Git (données
épinglées, en-têtes sensibles) et signale les secrets probables. Il fait aussi pointer chaque
nœud vers les credentials communs : chez l'autre, il n'y a rien à reconfigurer après un import.

À chaque PR, la CI de GitHub (`.github/workflows/ci.yml`) relance `sanitize.py` et les tests. La PR
passe en rouge si un workflow n'a pas été nettoyé, contient un secret, ou si un test échoue.

Pour récupérer le travail de l'autre : `git pull` puis `bash scripts/setup.sh --import`. Le
script met aussi la base à jour, et republie les workflows.

## Conventions d'équipe

**Workflows** : le préfixe indique qui s'en occupe (`[A]`, `[B]`, `[Commun]`). Un workflow par
fichier dans `workflows/`, jamais deux fichiers avec le même id (`setup.sh` refuse d'importer).

**Credentials** : seulement les trois credentials communs (`Postgres Persona`, `SMTP Persona`,
`LLM Persona`). Ne pas en créer d'autres de ces types : `sanitize.py` les remplacerait par les
communs.

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

| Workflow | Fichier | Quand | Credentials |
|---|---|---|---|
| `[A] Chat - Entrée` | `a_chat_entree.json` | à chaque message du chat | Postgres, SMTP |
| `[A] Chat - Agent` | `a_chat_agent.json` | appelé par `Chat - Entrée` | Postgres, Gemini |
| `[A] Chat - Intention` | `a_chat_intention.json` | appelé par `Chat - Entrée` | Gemini |
| `[B] News - Collecte` | `b_news_collecte.json` | toutes les heures | Postgres, Gemini |
| `[B] News - Envoi` | `b_news_envoi.json` | toutes les heures à h00 | Postgres, SMTP |
| `[B] News - Désinscription` | `b_news_desinscription.json` | lien `/unsubscribe` des emails | Postgres |
| `[Commun] Maintenance RGPD` | `commun_maintenance_RGPD.json` | tous les jours à 3 h | Postgres |

`[B] News - Envoi` n'est pas publié par défaut. Pour recevoir les newsletters dans Mailpit : l'ouvrir
dans n8n et le publier.

### `[A] Chat - Entrée`

Le chat se fait depuis la page http://localhost:8090 (fichier `web/index.html`, servi par
le conteneur `web`). Il y a aussi la page de chat de n8n, sans mise en forme :
http://localhost:5678/webhook/9d5a3c0e-6c1e-4b6e-9a53-2f0c7a8f4a11/chat

Ce qu'on peut écrire au chatbot :

- `inscription` : il demande l'email, si on accepte la politique de confidentialité, puis le mot de passe,
  puis envoie un code à 6 chiffres par email : le compte n'est créé qu'une fois ce code tapé dans le chat
  (`renvoyer le code` en envoie un autre, voir [doc/code-inscription.md](doc/code-inscription.md))
- `en savoir plus` : affiche la politique de confidentialité (celle de `doc/normes-RGPD.md`)
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
[doc/protection-deni-de-service.md](doc/protection-deni-de-service.md).

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
`deconnexion`, `mes_donnees`, `supprimer_compte`, `confidentialite`, `aide`, `annuler`, `aucune`),
et écrit une réponse courte et naturelle (sans lien). Le chatbot l'affiche à la place de sa phrase
habituelle quand on n'est pas connecté ou qu'on demande de l'aide. Gemini n'a aucun outil et ne voit
jamais un mot de passe. Les étapes sensibles (inscription, mot de passe, suppression, politique de
confidentialité) gardent leurs phrases fixes. Si Gemini ne répond pas, le chatbot garde sa phrase habituelle.

### `[A] Chat - Agent`

Agent Gemini avec 8 outils : `lire_preferences`, `modifier_interets`, `modifier_horaire`,
`modifier_email`, `activer_newsletter`, `modifier_style`, `exclure_source`, `donner_feedback`.

L'identifiant de l'utilisateur vient de la session, jamais de l'IA : même si on manipule
le modèle, il ne peut toucher qu'au compte connecté. Les centres d'intérêt doivent faire
partie des thèmes de la collecte (`sport`, `technologie`…).

Les protections et les tests sont détaillés dans [doc/audit-securite.md](doc/audit-securite.md).

### `[B] News - Collecte`

1. Lit les 4 flux RSS (voir [Sources de news](#sources-de-news)) et ne garde que
   les articles publiés depuis moins de 48 h. L'ancre `#...` est retirée des URL.
2. Insère dans `articles` avec `ON CONFLICT (url) DO NOTHING` : un article déjà
   connu n'est pas réinséré, et seuls les **nouveaux** articles passent à la suite.
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

1. Chaque heure, sélectionne les utilisateurs dont l'abonnement est actif
   (`is_active`) et dont l'heure (`send_hour`) et le jour (`send_days`) d'envoi
   correspondent à l'heure actuelle **dans leur fuseau** (`timezone`). Un
   utilisateur déjà servi il y a moins de 20 h est ignoré (pas de double envoi).
2. Choisit ses `max_articles` articles les plus récents (5 par défaut) dont les
   thèmes croisent ses `interests`, qui ont un résumé et ont été collectés dans
   les dernières 24 h.
   Aucun article = aucun email.
3. Construit un email HTML (titre cliquable, source, résumé) avec un lien de
   désinscription personnel. Le titre, la source et le résumé sont échappés, et
   les articles dont le lien n'est pas en `http(s)://` sont écartés.
4. **Vérifie l'email avant l'envoi** (`Vérifier l'email`) : destinataire valide,
   au moins un article, lien de désinscription présent, aucune balise dangereuse
   (`<script>`, `onerror=`…) et uniquement des liens `http(s)`. Si un point échoue,
   l'email n'est pas envoyé et un événement `newsletter_blocked` est ajouté dans
   `audit_log` avec la liste des problèmes.
5. Envoie l'email, l'enregistre dans `sent_newsletters` (avec les articles
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
- `articles` : après 30 jours
- `sent_newsletters` : après 6 mois
- `audit_log` : après 1 an

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
main. Rien n'est écrit en base. Chaque test imagine un scénario où quelque chose tourne mal, et
vérifie que le système réagit bien :

| Partie | Exemples | Détails |
|---|---|---|
| Collecte | un résumé vide, trop long, en anglais, avec du HTML ou un lien : rejeté | [doc/tests-evaluation.md](doc/tests-evaluation.md) |
| Envoi | un `<script>` dans un titre est échappé, un `Bcc` caché bloque l'email | [doc/tests-evaluation.md](doc/tests-evaluation.md) |
| Chat | aucun mot de passe ne part vers l'IA, chaque limite de messages tient | [doc/protection-deni-de-service.md](doc/protection-deni-de-service.md) |
| Inscription | le code est aléatoire, haché, limité à 5 essais et 3 envois | [doc/code-inscription.md](doc/code-inscription.md) |

## Sources de news

- Le Monde (https://www.lemonde.fr/rss/une.xml) : actualité générale, international
- France Info (https://www.francetvinfo.fr/titres.rss) : actualité générale, société, sport
- Numerama (https://www.numerama.com/feed/) : tech, sciences, espace
- BBC News (https://feeds.bbci.co.uk/news/rss.xml) : international, en anglais

Choix : thèmes variés pour que le filtrage par intérêts ait du sens, une source anglophone
pour l'international. La newsletter ne contient qu'un résumé et un lien vers l'article original
(respect du droit d'auteur). France Info nécessite un en-tête `User-Agent` dans les requêtes.

Pour vérifier un flux :

```bash
curl -sL -A "Mozilla/5.0" https://feeds.bbci.co.uk/news/rss.xml | head -c 300
```

La réponse doit commencer par `<?xml`.

## Documentation

- [doc/code-inscription.md](doc/code-inscription.md) : le code par email à l'inscription
- [doc/protection-deni-de-service.md](doc/protection-deni-de-service.md) : les limites de messages vers l'IA
- [doc/audit-securite.md](doc/audit-securite.md) : l'audit de sécurité du chatbot et des workflows de B
- [doc/tests-evaluation.md](doc/tests-evaluation.md) : les tests de l'évaluation avant l'envoi
- [doc/normes-RGPD.md](doc/normes-RGPD.md) : la politique de confidentialité et le registre des traitements
