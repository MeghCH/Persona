# Persona

Chatbot (A) et newsletter personnalisée (B), construits avec n8n et PostgreSQL.
Les sections 1 à 5 décrivent la mise en place (Phase 0), la section 6 les
workflows réalisés.

## 1. Installation (chacun sur sa machine)

Prérequis : Docker Desktop (ou Docker + Docker Compose) et Git.

```bash
git clone <votre-repo> persona && cd persona
cp .env.example .env # puis remplir les valeurs
openssl rand -hex 32 # à coller dans N8N_ENCRYPTION_KEY
docker compose up -d
```

Ouvrir http://localhost:5678 et créer son compte propriétaire n8n.

Le schéma de la base est créé automatiquement **au premier démarrage uniquement**.
Si vous modifiez `db/schema/02-schema.sql`, il faut réinitialiser la base :

```bash
docker compose down -v # efface toutes les données locales
docker compose up -d
```

## 2. Credential Postgres dans n8n

Dans n8n : _Credentials -> Add -> Postgres_

| Champ    | Valeur                          |
| -------- | ------------------------------- |
| Host     | `postgres`                      |
| Database | `persona`                       |
| User     | `persona_app`                   |
| Password | valeur de `PERSONA_DB_PASSWORD` |
| Port     | `5432`                          |

Nom du credential : **`Postgres Persona`** (le même chez vous deux).
On utilise `persona_app` et pas le compte admin : même si un attaquant
détourne une requête, il ne peut pas supprimer de tables.

## 3. Conventions d'équipe

**Workflows** (préfixe = responsable)

- `[A] Chat - Entrée` : Chat Trigger + authentification
- `[A] Chat - Agent` : agent IA et ses outils
- `[B] News - Collecte` : récupération des sources
- `[B] News - Envoi` : sélection + newsletter planifiée
- `[B] News - Désinscription` : lien de désinscription en un clic (webhook)
- `[Commun] Maintenance RGPD` : nettoyage RGPD nocturne (`SELECT persona_cleanup();`)

**Credentials** : noms génériques, jamais de nom/email perso
(`Postgres Persona`, `SMTP Persona`, `LLM Persona`).

**Nœuds** : renommer chaque nœud avec un verbe (`Vérifier session`,
`Hasher mot de passe`…), jamais `Postgres1`, `Code3`.

**Base de données** : aucune modification du schéma sans accord des deux.
Les mots de passe se hashent en SQL :

```sql
-- inscription
INSERT INTO users (email, password_hash, consent_given_at, consent_version)
VALUES ($1, crypt($2, gen_salt('bf')), now(), 'v1');
-- connexion
SELECT id FROM users WHERE email = $1 AND password_hash = crypt($2, password_hash);
```

Toujours utiliser les **paramètres de requête** (`$1`, `$2` dans le nœud Postgres,
option _Query Parameters_), jamais de concaténation de texte : c'est votre
protection contre l'injection SQL.

## 4. Partager son travail (Git)

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

Puis ré-associer les credentials dans les nœuds concernés.

## 5. Checklist de fin de Phase 0

- [ ] n8n tourne chez A et chez B
- [ ] la base `persona` contient les 6 tables (`users`, `sessions`, `preferences`,
      `articles`, `sent_newsletters`, `audit_log`)
- [ ] credential `Postgres Persona` créé et testé chez les deux
- [ ] un modèle d'IA connecté (Ollama local ou API avec crédits étudiants)
- [ ] un compte email d'envoi de test (SMTP Gmail avec mot de passe d'application, Brevo, Mailtrap…)
- [ ] repo Git créé, premier export/import réussi dans les deux sens

## 6. Workflows réalisés

| Workflow                     | Fichier                                  | Déclencheur              | Credentials                                 |
| ---------------------------- | ---------------------------------------- | ------------------------ | ------------------------------------------- |
| `[B] News - Collecte`        | `workflows/b_news_collecte.json`         | toutes les heures        | `Postgres Persona`, `LLM Persona` (Gemini)  |
| `[B] News - Envoi`           | `workflows/b_news_envoi.json`            | toutes les heures à h00  | `Postgres Persona`, `SMTP Persona`          |
| `[B] News - Désinscription`  | `workflows/b_news_desinscription.json`   | webhook `/unsubscribe`   | `Postgres Persona`                          |
| `[Commun] Maintenance RGPD`  | `workflows/commun_maintenance_rgpd.json` | tous les jours à 3 h     | `Postgres Persona`                          |

Après un import, les credentials apparaissent sous le nom `<type> (à configurer)`
(renommés par `scripts/sanitize.py`) : les ré-associer dans chaque nœud, puis
activer les workflows.

### `[B] News - Collecte`

1. Lit les 4 flux RSS (voir [Sources de news](#sources-de-news)) et ne garde que
   les articles publiés depuis moins de 48 h. L'ancre `#...` est retirée des URL.
2. Insère dans `articles` avec `ON CONFLICT (url) DO NOTHING` : un article déjà
   connu n'est pas réinséré, et seuls les **nouveaux** articles passent à la suite.
3. Par lots de 10, Gemini (température 0.2, sortie JSON structurée) donne à chaque
   article 1 à 3 thèmes et un résumé factuel en français (2 phrases max, traduit
   si l'article est en anglais).
4. Enregistre `tags` et `summary` dans `articles`.

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
3. Envoie un email HTML (titre cliquable, source, résumé) avec un lien de
   désinscription personnel.
4. Enregistre l'envoi dans `sent_newsletters` et met à jour `last_sent_at`.

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
`retention_cleanup` dans `audit_log`. Durées de conservation appliquées :

| Donnée                    | Supprimée après  |
| ------------------------- | ---------------- |
| `sessions`                | expiration       |
| `articles`                | 30 jours         |
| `sent_newsletters`        | 6 mois           |
| `audit_log`               | 1 an             |

`persona_app` n'a pas le droit de supprimer dans `audit_log` : la fonction est
`SECURITY DEFINER` et s'exécute avec les droits de son propriétaire.

## Sources de news

| Source      | Flux RSS                               | Thèmes                             |
| ----------- | -------------------------------------- | ---------------------------------- |
| Le Monde    | https://www.lemonde.fr/rss/une.xml     | Actualité générale, international  |
| France Info | https://www.francetvinfo.fr/titres.rss | Actualité générale, société, sport |
| Numerama    | https://www.numerama.com/feed/         | Tech, sciences, espace             |
| BBC News    | https://feeds.bbci.co.uk/news/rss.xml  | International (anglais)            |

Choix : thèmes variés pour que le filtrage par intérêts ait du sens, une source anglophone
pour l'international. La newsletter ne contient qu'un résumé et un lien vers l'article original
(respect du droit d'auteur). France Info nécessite un en-tête `User-Agent` dans les requêtes.

### Pour verifier le flux :

```bash
curl -sL -A "Mozilla/5.0" https://feeds.bbci.co.uk/news/rss.xml | head -c 300
```

-> Chaque bloc doit commencer par `<?xml`.
