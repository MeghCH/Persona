# Persona

Chatbot (A) et newsletter personnalisée (B), faits avec n8n et PostgreSQL.

On s'inscrit dans le chat, on choisit ses centres d'intérêt, et on reçoit un résumé de
l'actualité par email, aux jours et à l'heure qu'on veut.

Ce README explique comment installer Persona en partant de zéro et comment s'en servir. Le
fonctionnement interne et le travail en équipe sont dans [docs/](#pour-aller-plus-loin).

## Lancer le projet

### Ce qu'il faut

- **Docker** : Docker Desktop sous Windows et macOS, Docker Engine avec le plugin Compose sous Linux
- **Git**
- **Sous Windows** : WSL 2 avec Ubuntu, et Docker Desktop avec l'intégration WSL activée. Toutes
  les commandes se tapent dans le terminal Ubuntu, et le projet se clone dans Ubuntu (`~`), pas dans `C:`.
- **Des ports libres** : 5432 (base), 5678 (n8n), 8025 (emails), 8090 (chatbot), et 8081 si on
  lance Adminer pour [voir la base](docs/base-de-donnees.md#adminer). Ils ne sont ouverts que sur
  la machine (`127.0.0.1`), pas sur le réseau
- **Aucun nœud communautaire** : Persona n'utilise que les nœuds fournis avec n8n (image
  `n8nio/n8n:2.44.7`), il n'y a rien à installer dans n8n. Les données sont dans PostgreSQL, que
  `setup.sh` prépare tout seul (étape 1)
- **Une clé API Gemini**, gratuite sur https://aistudio.google.com/apikey. Sans clé, l'inscription
  et la connexion marchent, mais pas l'agent ni la collecte des news. Le quota gratuit est compté
  par modèle : Persona utilise `gemini-3.5-flash-lite` (voir [docs/optimisation-IA.md](docs/optimisation-IA.md)).
  Pour la créer :
  1. Ouvrir https://aistudio.google.com/apikey et se connecter avec un compte Google (un compte
     Gmail suffit). La première fois, accepter les conditions d'utilisation.
  2. Cliquer sur _Create API key_. Si Google demande un projet, en créer un nouveau (ou en choisir
     un existant).
  3. Copier la clé (elle commence par `AIza`). Elle se colle dans n8n à l'étape 2 (credential
     `LLM Persona`), pas dans `.env`. La garder pour soi : avec elle, n'importe qui peut utiliser
     le quota. On la retrouve à tout moment sur la même page.
  4. Ne pas activer la facturation sur ce projet : sans facturation, on reste sur le quota gratuit
     et rien n'est jamais payé.

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

Pour chacun :

1. Dans la recherche, taper le type (`Postgres`, `SMTP` ou `Gemini`), le choisir, puis _Continue_.
2. Remplir les réglages du tableau. Les champs qui n'y sont pas restent comme ils sont.
3. Renommer le credential : n8n lui donne un nom par défaut (par exemple `Postgres account`), en
   haut à gauche de la fenêtre. Cliquer dessus et taper le nom du tableau.
4. Cliquer sur _Save_. n8n teste la connexion : s'il affiche une erreur, revérifier les réglages.
   Pour `Postgres Persona`, c'est presque toujours le mot de passe, qui doit être exactement la
   valeur de `PERSONA_DB_PASSWORD` dans `.env`.

n8n utilise `persona_app` et pas le compte admin : même si un attaquant détourne une requête,
il ne peut pas supprimer de tables.

Avec ces réglages, aucun email ne part vraiment : ils arrivent tous dans Mailpit, une fausse boîte
mail, sur http://localhost:8025. Pour envoyer de vrais emails avec Gmail, il faut un compte Gmail
personnel (les comptes d'école ou d'entreprise bloquent souvent les mots de passe d'application) :

1. Activer la validation en deux étapes sur le compte Google (https://myaccount.google.com/security) :
   sans elle, Google ne propose pas de mot de passe d'application.
2. Créer un [mot de passe d'application](https://myaccount.google.com/apppasswords) : lui donner un
   nom (par exemple `Persona`), puis copier les 16 lettres affichées, sans les espaces.
3. Régler `SMTP Persona` sur : Host `smtp.gmail.com`, Port `465`, SSL/TLS activé, User l'adresse
   Gmail, Password le mot de passe d'application. Pas le mot de passe habituel du compte : Gmail le
   refuse.
4. Après « 3. Brancher les workflows », et pas avant (l'import remettrait l'ancienne adresse), changer l'adresse
   d'expéditeur : dans `[A] Chat - Entrée`, nœud `Envoyer le code`, et dans `[B] News - Envoi`,
   nœud `Envoyer la newsletter`, remplacer `personaepitech26@gmail.com` par l'adresse Gmail dans
   le champ _From Email_. Le faire avant de publier les workflows (étape 4), sinon cliquer de
   nouveau sur _Publish_ après. À refaire après chaque `bash scripts/workflows.sh import`.

Avec Gmail, les emails n'arrivent plus dans Mailpit, mais dans la vraie boîte de l'adresse donnée
au chatbot (regarder aussi les spams) : il faut donc s'inscrire avec une vraie adresse. Partout où
ce README parle de Mailpit, c'est cette boîte qu'il faut ouvrir.

### 3. Brancher les workflows sur les credentials

```bash
bash scripts/workflows.sh import
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
- **emails** : http://localhost:8025, où arrive le code d'inscription. Avec Mailpit, pas besoin
  d'une vraie adresse : il reçoit tous les emails, quelle que soit l'adresse. On peut donc
  s'inscrire avec une adresse inventée (par exemple `test@exemple.fr`), puis cliquer sur l'email
  dans la liste de Mailpit pour lire le code.

### 5. Utiliser le chatbot

Le chat se fait sur http://localhost:8090. La page de chat de n8n marche aussi, sans mise en
forme : http://localhost:5678/webhook/9d5a3c0e-6c1e-4b6e-9a53-2f0c7a8f4a11/chat

Ce qu'on peut écrire au chatbot :

- `inscription` : il demande l'email, si on accepte la politique de confidentialité, puis le mot de passe
  (12 caractères au moins), puis envoie un code à 6 chiffres par email : le compte n'est créé qu'une fois
  ce code tapé dans le chat (`renvoyer le code` en envoie un autre)
- `en savoir plus` : affiche la politique de confidentialité (celle de `docs/normes-RGPD.md`)
- `connexion` : il demande l'email puis le mot de passe. On peut aussi se connecter en une ligne :
  `connexion EMAIL MOT_DE_PASSE`
- `annuler` : arrête l'inscription ou la connexion en cours
- `deconnexion`
- `mes données` : affiche tout ce qu'on garde sur l'utilisateur
- `supprimer mon compte`, puis `confirmer suppression`
- `aide`
- n'importe quel autre message, une fois connecté : il part à l'agent

On peut aussi écrire une phrase normale, comme « je voudrais créer un compte » ou « comment je
récupère mes données ? » : le chatbot fait la même chose que pour la commande. Pour supprimer son
compte, il faut dans tous les cas taper exactement `confirmer suppression`.

Une fois connecté, on règle sa newsletter en écrivant normalement à l'agent, par exemple :

| Pour régler...        | On peut écrire                                         | Valeurs possibles                                                                                                                                |
| --------------------- | ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| les centres d'intérêt | « j'aime le foot et l'espace »                         | politique, international, économie, société, sport, culture, technologie, science, espace, santé, environnement, jeux-vidéo, faits-divers, autre |
| les jours et l'heure  | « le lundi et le jeudi à 7 h 30 », « dans 10 minutes » | n'importe quels jours, par créneaux de 5 minutes, dans son fuseau horaire                                                                        |
| la mise en page       | « c'est trop long », « juste les titres »              | titres, résumé (par défaut), détaillé ; de 1 à 20 articles                                                                                       |
| le ton de l'agent     | « tutoie-moi »                                         | neutre, décontracté, formel, humoristique                                                                                                        |
| les sources           | « je ne veux plus de Le Monde », « remets Le Monde »   | Le Monde, France Info, Numerama, BBC News                                                                                                        |
| l'adresse email       | « change mon email pour … »                            |                                                                                                                                                  |
| l'abonnement          | « mets ma newsletter en pause », « reprends-la »       |                                                                                                                                                  |
| un avis               | « la dernière newsletter était trop longue »           | il est enregistré, et l'agent propose le réglage qui va avec                                                                                     |

Chaque newsletter a aussi un lien de désinscription en un clic.

Les messages envoyés à l'IA sont limités (6 par minute, puis des limites par jour, voir
[docs/protection-deni-of-service.md](docs/protection-deni-of-service.md)). Les commandes exactes
ne le sont pas.

### 6. Tester un envoi programmé

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

## Au quotidien

| Pour...                                 | Faire                                                                                                                      |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| arrêter                                 | `docker compose down`                                                                                                      |
| relancer                                | `bash scripts/setup.sh`                                                                                                    |
| voir la base dans le navigateur         | `docker compose --profile outils up -d adminer`, puis http://localhost:8081 ([connexion](docs/base-de-donnees.md#adminer)) |
| voir les derniers événements du journal | `bash scripts/journal.sh` (ou `bash scripts/journal.sh 50`), voir [le journal](docs/base-de-donnees.md#le-journal)         |
| lire les retours des abonnés            | voir [les retours](docs/base-de-donnees.md#les-retours)                                                                    |
| lancer les tests                        | `docker compose exec -T n8n node - < scripts/test_scenarios.js` (voir [Tests](#tests))                                     |
| tout effacer et repartir de zéro        | `docker compose down -v`, puis les étapes 1 à 4                                                                            |

`bash scripts/setup.sh` met aussi la base à jour : le schéma est dans un seul fichier,
`db/schema/02-schema.sql`, et une base existante reçoit les nouvelles tables et colonnes sans
perdre ses données.

`docker compose down -v` efface tout : la base, mais aussi le compte n8n, les credentials et les
workflows de n8n.

Pour modifier les workflows à plusieurs (passer de n8n à Git et inversement), voir
[docs/contribuer.md](docs/contribuer.md).

## Si ça ne marche pas

| Ce qu'on voit                                                             | Quoi faire                                                                                                                                                 |
| ------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `port is already allocated` au démarrage                                  | un autre programme utilise un des ports (souvent un PostgreSQL installé sur l'ordinateur, sur 5432) : l'arrêter, puis relancer                             |
| la page ne répond pas (Windows)                                           | garder Docker Desktop et un terminal Ubuntu ouverts                                                                                                        |
| des nœuds en rouge dans n8n                                               | un credential n'a pas exactement le bon nom, ou a été créé après l'import : corriger le nom, puis refaire les étapes 3 et 4                                |
| « Je n'ai pas pu envoyer l'email »                                        | vérifier les réglages de `SMTP Persona`, et que Mailpit tourne (`docker compose ps`)                                                                       |
| « Désolé, je n'ai pas pu traiter votre demande »                          | clé Gemini absente ou invalide, ou quota Gemini du jour épuisé                                                                                             |
| une collecte en erreur « too many requests », des articles sans résumé    | quota Gemini du jour épuisé : les articles sont repris à la collecte suivante (voir [`[B] News - Collecte`](docs/workflows.md#b-news---collecte), étape 2) |
| les réglages du chat (format, sources exclues) ne changent rien à l'email | `[B] News - Envoi` n'a pas été réimporté depuis : `bash scripts/workflows.sh import b_news_envoi`, puis le republier                                       |
| « Error in workflow »                                                     | la base est arrêtée : relancer `bash scripts/setup.sh`                                                                                                     |
| le chat répond comme une ancienne version                                 | une copie du workflow est publiée à la place de l'original : dans n8n, archiver la copie et publier l'original                                             |
| autre chose                                                               | `docker compose logs n8n` montre les erreurs de n8n                                                                                                        |

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
main. Rien n'est écrit en base. Les 35 tests doivent tous passer (`35 réussis, 0 ratés`). Ce que
teste chacun, et ce qui n'est pas testé, est dans [docs/tests-scenarios.md](docs/tests-scenarios.md).

Les tests ne remplacent pas un essai avec le vrai Gemini : ils ne vérifient ni la qualité des
résumés, ni ce que l'agent décide de faire. Les conversations à rejouer à la main sont dans
[docs/prompts-IA.md](docs/prompts-IA.md#tester-une-nouvelle-version).

## Pour aller plus loin

- [docs/workflows.md](docs/workflows.md) : ce que fait chaque workflow, et les sources de news
- [docs/base-de-donnees.md](docs/base-de-donnees.md) : voir la base (Adminer), le journal et les retours des abonnés
- [docs/contribuer.md](docs/contribuer.md) : modifier les workflows à deux, et les conventions de l'équipe
- [docs/tests-scenarios.md](docs/tests-scenarios.md) : tous les tests, rangés par workflow, et ce qui n'est pas testé
- [docs/code-inscription.md](docs/code-inscription.md) : le code par email à l'inscription
- [docs/protection-deni-of-service.md](docs/protection-deni-of-service.md) : les limites de messages vers l'IA
- [docs/prompts-IA.md](docs/prompts-IA.md) : les prompts de l'agent et de l'intention, et leurs versions
- [docs/optimisation-IA.md](docs/optimisation-IA.md) : ce que coûte chaque workflow en temps et en tokens, et le quota Gemini
- [docs/audit-securite/](docs/audit-securite/README.md) : l'audit de sécurité du chatbot et des workflows de B (15/11)
  - [README.md](docs/audit-securite/README.md) : le sommaire, le résumé et la liste des failles et des attaques
  - [failles/](docs/audit-securite/failles/) : une fiche par faille (F-01 à F-05) et par attaque testée (T-01 à T-25)
  - [scope.md](docs/audit-securite/scope.md) : ce qui est dans le périmètre, ce qui n'y est pas, l'échelle de gravité
  - [methode.md](docs/audit-securite/methode.md) : comment on a testé, et les outils pour tout rejouer
  - [protections-chatbot.md](docs/audit-securite/protections-chatbot.md) : le trajet d'un message et les protections
  - [protections-IA.md](docs/audit-securite/protections-IA.md) : ce que l'IA a le droit de faire, et les prompts par étape
  - [mitre.md](docs/audit-securite/mitre.md) : ce que sont les codes MITRE, et l'index des codes utilisés
  - [risques-restants.md](docs/audit-securite/risques-restants.md) : les risques qui restent, et la conclusion
  - [rgpd-et-journal.md](docs/audit-securite/rgpd-et-journal.md) : les droits des utilisateurs et le journal de sécurité
  - [test-globaux.md](docs/audit-securite/test-globaux.md) : la première version de l'audit (29/10)
- [docs/normes-RGPD.md](docs/normes-RGPD.md) : la politique de confidentialité et le registre des traitements
