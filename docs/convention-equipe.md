# Travailler sur le projet

Pour l'équipe : comment passer les workflows entre n8n et Git, et les règles du dépôt. Pour
installer et utiliser Persona, voir le [README](../README.md).

En plus de ce que demande le README, il faut **Python 3** pour exporter des workflows
(`scripts/sanitize.py`).

| Pour...                                      | Faire                                                                     |
| -------------------------------------------- | ------------------------------------------------------------------------- |
| récupérer le travail de l'autre              | `git pull`, `bash scripts/setup.sh`, puis les étapes 3 et 4 du README     |
| mettre dans Git un workflow modifié dans n8n | `bash scripts/workflows.sh export <nom>` (voir plus bas)                  |
| ajouter une source de news                   | voir [workflows.md](workflows.md#sources-de-news), « Ajouter une source » |

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
- les workflows importés sont dépubliés : les republier ensuite ([étape 4 du README](../README.md#4-publier-les-workflows))

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

**Credentials** : seulement les trois credentials de l'[étape 2 du README](../README.md#2-créer-les-credentials-dans-n8n), avec ces noms exacts, jamais de nom
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
