# Voir la base, le journal et les retours

Les données de Persona sont dans la base `persona` (PostgreSQL). On peut les lire dans le
navigateur avec Adminer, ou en ligne de commande. Pour installer Persona, voir le
[README](../README.md).

## Adminer

Adminer est une interface web pour la base. Il est dans `docker-compose.yml`, mais ne démarre pas
avec le reste (profil `outils`) : `setup.sh` ne le lance pas.

```bash
docker compose --profile outils up -d adminer   # démarrer
docker compose stop adminer                     # arrêter
```

Ouvrir http://localhost:8081 et se connecter :

| Champ           | Valeur                                                         |
| --------------- | -------------------------------------------------------------- |
| Système         | **PostgreSQL** (Adminer propose MySQL par défaut : le changer) |
| Serveur         | `postgres` (déjà rempli)                                       |
| Utilisateur     | `persona_app`                                                  |
| Mot de passe    | la valeur de `PERSONA_DB_PASSWORD` dans `.env`                 |
| Base de données | `persona` (la base `n8n`, à côté, est celle de n8n lui-même)   |

Les tables sont listées à gauche. _Afficher les données_ montre le contenu d'une table, avec des
filtres et du tri. _Requête SQL_ (en haut à gauche) lance une requête, par exemple pour suivre un
[envoi programmé](../README.md#6-tester-un-envoi-programmé) :

```sql
SELECT u.email, p.interests, p.send_hour, p.send_minute, p.send_days, p.is_active, p.last_sent_at
FROM users u JOIN preferences p ON p.user_id = u.id;
```

`persona_app` peut lire et modifier les données, mais pas le schéma. Une ligne modifiée ou
supprimée dans Adminer l'est vraiment, comme depuis les workflows. Adminer n'est ouvert que sur la
machine (`127.0.0.1:8081`).

## En ligne de commande

Sans Adminer, la même base est accessible avec `psql` :

```bash
docker compose exec postgres sh -c 'psql -U "$POSTGRES_USER" -d persona'
```

## Le journal

Le journal (table `audit_log`) note chaque action sensible : l'événement, le compte concerné,
la date et quelques détails. Il ne garde ni l'email (seulement l'identifiant du compte), ni le
texte des messages, ni les mots de passe. Il est conservé 1 an.

```bash
bash scripts/journal.sh      # les 20 derniers événements
bash scripts/journal.sh 50   # les 50 derniers
```

Chaque ligne donne la date (en UTC), l'événement, l'email du compte s'il existe encore et les
détails. Pour ne voir qu'un seul événement, remplacer `newsletter_blocked` par celui qu'on cherche :

```bash
docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d persona' <<'SQL'
SELECT a.created_at, u.email, a.details
FROM audit_log a LEFT JOIN users u ON u.id = a.user_id
WHERE a.event = 'newsletter_blocked'
ORDER BY a.created_at DESC LIMIT 20;
SQL
```

Combien de fois chaque événement est arrivé :

```bash
docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d persona' <<'SQL'
SELECT event, count(*), max(created_at) AS dernier FROM audit_log GROUP BY event ORDER BY 2 DESC;
SQL
```

Les événements :

| Partie                | Événement                 | Quand                                                                                     |
| --------------------- | ------------------------- | ----------------------------------------------------------------------------------------- |
| Inscription et compte | `register_otp_sent`       | un code d'inscription est envoyé (ou renvoyé)                                             |
|                       | `register_otp_failed`     | un mauvais code est tapé (avec le numéro de l'essai)                                      |
|                       | `register_ok`             | le compte est créé                                                                        |
|                       | `register_duplicate`      | quelqu'un s'inscrit avec un email déjà pris                                               |
|                       | `email_changed`           | l'agent a changé l'email du compte                                                        |
|                       | `account_deleted`         | le compte est supprimé, dans le chat ou 6 mois après la désinscription                    |
| Connexion             | `login_ok`                | connexion réussie                                                                         |
|                       | `login_failed`            | mauvais mot de passe sur un compte qui existe                                             |
|                       | `account_locked`          | 5e erreur : le compte est bloqué 15 minutes                                               |
|                       | `login_blocked`           | tentative de connexion pendant le blocage                                                 |
|                       | `login_failed_unknown`    | email inconnu (rien n'est gardé sur cet email)                                            |
|                       | `logout`                  | déconnexion                                                                               |
| Réglages (agent)      | `prefs_interests_updated` | centres d'intérêt modifiés                                                                |
|                       | `prefs_schedule_updated`  | jours, heure, minute ou fuseau d'envoi modifiés                                           |
|                       | `prefs_style_updated`     | ton, format ou nombre d'articles modifiés                                                 |
|                       | `prefs_active_updated`    | newsletter mise en pause ou reprise dans le chat                                          |
|                       | `prefs_source_excluded`   | une source est exclue                                                                     |
|                       | `prefs_source_included`   | une source exclue est remise                                                              |
|                       | `feedback_added`          | un retour est enregistré (le texte est dans `feedback`, voir [Les retours](#les-retours)) |
| Sécurité              | `injection_suspected`     | message bloqué par le filtre anti-injection, avant l'IA                                   |
|                       | `rate_limited`            | trop de messages vers l'IA (avec la raison du refus)                                      |
| Newsletter            | `summary_review`          | un résumé est rejeté à la collecte (avec l'article et la raison)                          |
|                       | `newsletter_blocked`      | un email est bloqué juste avant l'envoi (avec la liste des problèmes)                     |
|                       | `unsubscribed`            | désinscription par le lien de l'email                                                     |
| Maintenance           | `night_cleanup`           | nettoyage de 3 h (avec le nombre d'articles, d'envois et de sessions supprimés)           |

Les lignes `retention_cleanup` qu'on peut encore voir viennent d'une version d'avant le 03/11 :
c'était l'ancien nom de `night_cleanup`.

## Les retours

Les retours (table `feedback`) sont ce que les abonnés disent de leurs newsletters dans le
chat (« trop long », « je n'aime pas le sport »…). L'agent les enregistre avec `donner_feedback` :
1 000 caractères et 20 retours par jour au plus. Ils sont conservés 1 an.

```bash
docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d persona' <<'SQL'
SELECT f.created_at, u.email, f.message
FROM feedback f JOIN users u ON u.id = f.user_id
ORDER BY f.created_at DESC LIMIT 20;
SQL
```

Un retour ne change pas la newsletter tout seul : l'agent propose le réglage qui va avec
(exclure une source, passer au format `titres`, moins d'articles…), et l'utilisateur décide.
Chaque abonné voit ses propres retours avec `mes données` dans le chat.

Les deux tables se lisent aussi dans [Adminer](#adminer) : `audit_log` et
`feedback`, puis _Afficher les données_.
