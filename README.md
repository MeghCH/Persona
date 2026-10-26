# Persona - Phase 0 : mise en place

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
- `[Commun] Maintenance` : nettoyage RGPD nocturne (`SELECT persona_cleanup();`)

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
