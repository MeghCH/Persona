# Persona

Chatbot (A) et newsletter personnalisée (B), faits avec n8n et PostgreSQL.

## Lancer le projet

Il faut Docker et Git.

```bash
bash scripts/setup.sh
```

La première fois, le script crée le fichier `.env` : remplir les mots de passe et relancer la commande.
Il démarre les conteneurs, prépare la base et importe les workflows.

Toujours la première fois, sur http://localhost:5678 :

1. créer son compte n8n
2. créer les credentials `Postgres Persona` (voir plus bas), `LLM Persona` (clé Gemini) et `SMTP Persona`
3. ouvrir chaque workflow, choisir ces credentials dans les nœuds en rouge, puis l'activer

Le chatbot est sur http://localhost:8090 : on clique sur la bulle et on tape `inscription`.

Pour arrêter : `docker compose down`.

Si ça ne marche pas :

- la page ne répond pas : sous WSL, garder un terminal Ubuntu ouvert
- « Error in workflow » : la base est arrêtée, relancer `bash scripts/setup.sh`
- « Désolé, je n'ai pas pu traiter votre demande » : le quota Gemini du jour est épuisé

## Installation à la main

```bash
git clone <votre-repo> persona && cd persona
cp .env.example .env # puis remplir les valeurs
openssl rand -hex 32 # à coller dans N8N_ENCRYPTION_KEY
docker compose up -d
```

Le schéma de la base est créé **au premier démarrage uniquement**. Si on modifie
`db/schema/02-schema.sql`, il faut repartir d'une base vide :

```bash
docker compose down -v # efface toutes les données locales
docker compose up -d
```

## Credential Postgres

Dans n8n : _Credentials -> Add -> Postgres_, nommé **`Postgres Persona`** :

- Host : `postgres`
- Database : `persona`
- User : `persona_app`
- Password : la valeur de `PERSONA_DB_PASSWORD`
- Port : `5432`

On utilise `persona_app` et pas le compte admin : même si un attaquant détourne une
requête, il ne peut pas supprimer de tables.

## Conventions d'équipe

**Workflows** (le préfixe indique qui s'en occupe) :

- `[A] Chat - Entrée` : Chat Trigger + authentification
- `[A] Chat - Agent` : agent IA et ses outils
- `[B] News - Collecte` : récupération des sources
- `[B] News - Envoi` : sélection + newsletter planifiée
- `[B] News - Désinscription` : lien de désinscription en un clic (webhook)
- `[Commun] Maintenance RGPD` : nettoyage RGPD de nuit (`SELECT persona_cleanup();`)

**Credentials** : noms génériques, jamais de nom ou d'email perso
(`Postgres Persona`, `SMTP Persona`, `LLM Persona`).

**Nœuds** : chaque nœud a un nom avec un verbe (`Vérifier session`, `Hasher mot de passe`…),
jamais `Postgres1` ou `Code3`.

**Base de données** : pas de modification du schéma sans accord des deux.
Les mots de passe se hashent en SQL :

```sql
-- inscription
INSERT INTO users (email, password_hash, consent_given_at, consent_version)
VALUES ($1, crypt($2, gen_salt('bf')), now(), 'v1');
-- connexion
SELECT id FROM users WHERE email = $1 AND password_hash = crypt($2, password_hash);
```

Toujours passer par les **paramètres de requête** (`$1`, `$2`, option _Query Parameters_
du nœud Postgres), jamais de concaténation : c'est ce qui protège de l'injection SQL.

## Partager son travail (Git)

```bash
# exporter tous les workflows depuis n8n vers ./workflows
docker compose exec n8n n8n export:workflow --all --separate --output=/home/node/exports
# nettoyer avant commit (obligatoire)
python3 scripts/sanitize.py workflows/
git add workflows && git commit -m "..." && git push
```

Pour récupérer le travail de l'autre :

```bash
git pull
docker compose exec n8n n8n import:workflow --separate --input=/home/node/exports
```

Puis ré-associer les credentials dans les nœuds. Après un import, ils s'appellent
`<type> (à configurer)` (renommés par `scripts/sanitize.py`).

## Checklist de fin de Phase 0

- [ ] n8n tourne chez A et chez B
- [ ] la base `persona` contient les 6 tables (`users`, `sessions`, `preferences`,
      `articles`, `sent_newsletters`, `audit_log`)
- [ ] credential `Postgres Persona` créé et testé chez les deux
- [ ] un modèle d'IA connecté (Ollama local ou API avec crédits étudiants)
- [ ] un compte email d'envoi de test (SMTP Gmail avec mot de passe d'application, Brevo, Mailtrap…)
- [ ] repo Git créé, premier export/import réussi dans les deux sens

## Les workflows

- `[A] Chat - Entrée` (`workflows/a_chat_entree.json`) : Chat Trigger, Postgres
- `[A] Chat - Agent` (`workflows/a_chat_agent.json`) : appelé par `Chat - Entrée`, Postgres + Gemini
- `[B] News - Collecte` (`workflows/b_news_collecte.json`) : toutes les heures, Postgres + Gemini
- `[B] News - Envoi` (`workflows/b_news_envoi.json`) : toutes les heures à h00, Postgres + SMTP
- `[B] News - Désinscription` (`workflows/b_news_desinscription.json`) : webhook `/unsubscribe`, Postgres
- `[Commun] Maintenance RGPD` (`workflows/commun_maintenance_rgpd.json`) : tous les jours à 3 h, Postgres

### `[A] Chat - Entrée`

Le chat se fait depuis la page http://localhost:8090 (fichier `web/index.html`, servi par
le conteneur `web`). Il y a aussi la page de chat de n8n, sans mise en forme :
http://localhost:5678/webhook/9d5a3c0e-6c1e-4b6e-9a53-2f0c7a8f4a11/chat

Ce qu'on peut écrire au chatbot :

- `inscription` : il demande l'email, si on accepte la politique de confidentialité, puis le mot de passe
- `en savoir plus` : affiche la politique de confidentialité (celle de `doc/normes-RGPD.md`)
- `connexion` : il demande l'email puis le mot de passe
- `annuler` : arrête l'inscription ou la connexion en cours
- `deconnexion`
- `mes données` : affiche tout ce qu'on garde sur l'utilisateur
- `supprimer mon compte`, puis `confirmer suppression`
- `aide`
- n'importe quel autre message, une fois connecté : il part à l'agent

On peut aussi s'inscrire ou se connecter en une ligne :
`inscription EMAIL MOT_DE_PASSE j'accepte` et `connexion EMAIL MOT_DE_PASSE`.

Tout ce qui touche à la connexion est fait en SQL, sans l'IA. Le mot de passe est haché
avec bcrypt, il fait au moins 12 caractères, et 5 erreurs bloquent le compte 15 minutes.
Une session dure 2 h sans activité (8 h maximum). Sur la page, le mot de passe est masqué
quand on le tape et affiché `••••••••` dans la conversation.

Ce workflow n'enregistre pas ses exécutions, parce que les messages contiennent des mots
de passe. Pour déboguer, on peut réactiver la sauvegarde dans les _Settings_ du workflow.

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

À adapter : l'adresse d'expéditeur dans le nœud `Envoyer la newsletter`, et l'URL
du lien de désinscription (`http://localhost:5678/...` dans `Construire l'email`)
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

## Sources de news

- Le Monde (https://www.lemonde.fr/rss/une.xml) : actualité générale, international
- France Info (https://www.francetvinfo.fr/titres.rss) : actualité générale, société, sport
- Numerama (https://www.numerama.com/feed/) : tech, sciences, espace
- BBC News (https://feeds.bbci.co.uk/news/rss.xml) : international, en anglais

Choix : thèmes variés pour que le filtrage par intérêts ait du sens, une source anglophone
pour l'international. La newsletter ne contient qu'un résumé et un lien vers l'article original
(respect du droit d'auteur). France Info nécessite un en-tête `User-Agent` dans les requêtes.

### Pour vérifier le flux :

```bash
curl -sL -A "Mozilla/5.0" https://feeds.bbci.co.uk/news/rss.xml | head -c 300
```

-> Chaque bloc doit commencer par `<?xml`.
