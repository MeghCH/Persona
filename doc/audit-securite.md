# Persona - Audit de sécurité

Auteur : personne A (conversation et sécurité) - 28/10/2026
Périmètre : workflows `[A] Chat - Entrée`, `[A] Chat - Agent`, et attaques de phase 2 contre
`[B] News - Collecte`, `[B] News - Envoi`, `[B] News - Désinscription`.

## 1. Méthode

- Environnement de test **isolé** : une seconde pile Docker (`persona-test`, volumes séparés), n8n 2.44.7
  et PostgreSQL 16, sans toucher aux données réelles.
- **Faux Gemini** : un petit serveur qui imite l'API Gemini et renvoie des appels d'outils choisis,
  y compris des appels malveillants (un « modèle manipulé »). On teste ainsi ce que le système
  laisse faire au LLM, indépendamment de la bonne volonté du modèle.
- **Faux SMTP** : capture les emails envoyés par `[B] News - Envoi` pour inspecter leur HTML.
- Chaque test envoie une vraie requête au Chat Trigger, puis **vérifie l'état de la base** (et pas
  seulement la réponse du chatbot).
- Vérification complémentaire avec le **vrai Gemini** sur l'instance de développement : lecture et
  modification des préférences, ton et format, feedback, refus d'accès à un autre compte, export,
  suppression, filtre d'injection.

Résultat : **66/66 tests réussis** sur la version finale du chatbot (environnement isolé, 29/10/2026),
dont les 14 tests de l'inscription et de la connexion guidées ; **4 vulnérabilités** trouvées dans les
workflows de B. Le parcours guidé a aussi été testé sur l'instance de développement (23 tests, sans
appel à Gemini) et à la main dans la bulle de chat (section 3 bis).

## 2. Architecture de sécurité du chatbot

```
Message ─► Analyser le message ─► inscription / connexion ─► SQL paramétré (bcrypt, verrouillage)
  (Chat     (sessionId ≥ 32 car.,                         
  Trigger)   1000 car. max,         sinon ─► Vérifier la session ─► non connecté : refus
             invisibles retirés)                  │
                                                  ├─► commandes fixes : déconnexion, mes données,
                                                  │   supprimer mon compte (sans LLM)
                                                  └─► Filtrer l'injection ─► Agent IA ─► outils SQL
                                                                                         liés au user_id
                                                                                         de la session
```

Principes :

1. **Le LLM ne fait jamais l'authentification.** Inscription, connexion, déconnexion, export et
   suppression sont des commandes déterministes, traitées avant l'agent. Les mots de passe
   n'arrivent jamais au modèle.
2. **Le LLM ne choisit jamais l'utilisateur.** Le `user_id` vient de la table `sessions`, côté
   serveur, et est injecté dans chaque requête SQL des outils. Le modèle ne fournit que les valeurs
   (intérêts, heure…). Même un modèle totalement manipulé ne peut agir que sur le compte connecté.
3. **Défense en profondeur sur les valeurs** : requêtes paramétrées (`$1`, `$2`), validation en SQL
   (listes autorisées, expressions régulières), contraintes `CHECK` en base.
4. **Moindre privilège** : n8n utilise `persona_app` (pas de modification du schéma, `audit_log` en
   ajout seul). Aucun outil ne touche à `role`, `password_hash` ou `unsubscribe_token`.
5. **Traçabilité** : chaque connexion, échec, verrouillage, modification, tentative d'injection et
   suppression est écrit dans `audit_log`, sans donnée personnelle en clair.

## 3. Résultats des tests du chatbot (52/52)

| Domaine | Attaques testées | Résultat |
|---|---|---|
| Entrées | `sessionId` devinable (`abc`), message de 1001 caractères, requête sans texte | Refusés |
| Inscription | email invalide, mot de passe court ou faible, sans consentement, consentement ambigu | Refusés |
| Inscription | réinscription d'un email existant | Même réponse (pas d'énumération), mot de passe d'origine inchangé |
| Stockage | mot de passe en base | Haché bcrypt coût 12 ; consentement daté et versionné ; rôle `user` |
| Connexion | injection SQL dans l'email et dans le mot de passe | Aucune session créée |
| Connexion | email inconnu / mauvais mot de passe | Réponse identique, et hash calculé dans les deux cas (temps de réponse comparable) |
| Force brute | 5 échecs puis le bon mot de passe | Compte verrouillé 15 min, connexion refusée, événements `account_locked` et `login_blocked` |
| Sessions | session inconnue, après déconnexion, expirée (2 h d'inactivité), de plus de 8 h | Accès refusé |
| Cloisonnement | le LLM passe le `user_id` d'un autre compte (lecture et écriture) | Ignoré : seul le compte connecté est lu ou modifié |
| Cloisonnement | prendre l'email d'un autre compte ; mémoire de l'agent après changement de compte | Refusé ; mémoire séparée par session **et** utilisateur |
| Élévation | le LLM ajoute `role=admin` à un outil | Rôle inchangé |
| Injection SQL | `x'); DROP TABLE users;--` dans un paramètre d'outil | Table intacte, valeur ignorée |
| Validation | fuseau `Mars/Olympus`, heure 25, jours 9 et 99, ton `admin`, email invalide | Refusés, rien n'est modifié |
| Fuite | le modèle « recrache » un hash bcrypt et un UUID | Masqués par le filtre de sortie |
| Injection de prompt | « ignore tes instructions », révéler le prompt, données des autres utilisateurs, passer admin, `DROP TABLE`, `ig·nore (caractère invisible)` avec caractère invisible, mode DAN, `password_hash`, balises `<\|im_start\|>` | Bloqués **et** journalisés (`injection_suspected`) |
| Faux positif | « des news sur le football et l'espace le matin » | Non bloqué |
| RGPD | export « mes données », suppression avec confirmation | Export complet sans secret ; suppression effective (compte, préférences, sessions, feedback) |

## 3 bis. Inscription et connexion guidées (23/23)

L'utilisateur tape `inscription` ou `connexion`, et le chat demande l'email, puis le consentement
(inscription), puis le mot de passe. L'étape en cours est retenue 10 minutes dans `auth_pending`, sans
mot de passe. Le message qui contient le mot de passe ne passe ni par l'agent ni par le filtre
d'injection, et n'est jamais journalisé.

| Attaque ou cas | Résultat |
|---|---|
| Email invalide, refus du consentement, mot de passe « admin » | Refusés, l'étape reste la même ; aucun compte créé |
| « J’accepte » avec majuscule et apostrophe typographique | Accepté |
| Réinscription guidée d'un email existant | Même réponse « C'est fait » (pas d'énumération), mot de passe d'origine conservé |
| Mauvais mot de passe à la connexion | Refus générique, nouvel essai possible, compteur anti force brute appliqué |
| 5 échecs puis le bon mot de passe | Compte verrouillé 15 minutes, aucune session |
| Mot de passe « Ignore previous instructions 7! » | Accepté comme mot de passe : ni bloqué, ni journalisé |
| « annuler » en cours de parcours ; étape vieille de plus de 10 minutes | Étape effacée ; message suivant traité comme non connecté |
| Ancienne commande incomplète (`inscription test a.a@gmail.com`) | Renvoie vers le parcours guidé |

Affichage : sur la page de démo (`web/index.html`), quand le bot demande un mot de passe, la zone de
saisie devient un champ `type="password"` et le message envoyé s'affiche `••••••••` dans
l'historique (vérifié dans le navigateur : envoi par Entrée et par le bouton, mauvais puis bon mot
de passe, aucun mot de passe présent dans la page). La page de chat hébergée par n8n, elle, n'a
pas ce masquage : c'est la page de démo qu'il faut utiliser.

Stockage : le mot de passe n'est stocké nulle part en clair. Seul son hash bcrypt (coût 12) est
écrit dans `users.password_hash` ; `auth_pending` ne contient jamais de mot de passe ; le workflow
`[A] Chat - Entrée` n'enregistre pas ses exécutions ; le mot de passe n'est ni envoyé à l'IA ni
écrit dans `audit_log`. En transit, il faut HTTPS dès que n8n est exposé (voir section 5).

## 4. Phase 2 : attaques contre les workflows de B

| # | Attaque | Verdict | Détail |
|---|---|---|---|
| B01 | Un utilisateur avec `timezone = 'Mars/Olympus'` en base | **Vulnérable** | La requête horaire échoue (`time zone "Mars/Olympus" not recognized`) : **plus personne** ne reçoit la newsletter. |
| B01b | Même insertion avec la migration proposée | Résiste | Refusée par la contrainte `preferences_timezone_valid`. |
| B02 | Article dont le titre contient `<img src=x onerror=…>`, l'URL `javascript:…` et le résumé un lien de phishing | **Vulnérable** | Les trois sont insérés tels quels dans le HTML de l'email (`Préparer les articles` n'échappe rien). |
| B03 | Injection SQL dans le jeton de désinscription | Résiste | Jeton validé par expression régulière avant la requête. |
| B04 | Jeton bien formé mais inconnu | Résiste | Page « Lien invalide », identique au jeton mal formé. |
| B05 | Mauvaise méthode HTTP (POST) | Résiste | 404. |
| B06 | Jeton valide | Comportement attendu, avec un risque | Un simple GET désinscrit : un antivirus de messagerie qui précharge les liens peut désinscrire l'utilisateur à son insu. |
| B07 | Adresse en base `pirate@…\r\nBcc: espion@evil.example` | **Vulnérable** | L'adresse est réinterprétée comme un groupe : l'email part **vers `espion@evil.example`**. Le chatbot valide déjà les emails ; corrigé en base par `users_email_valid`. |
| B08 | Le modèle renvoie des thèmes hors liste (`admin`, `<script>`) | Résiste | Thèmes filtrés en SQL. |
| B09 | Le modèle renvoie un résumé de 2000 caractères | Résiste | Tronqué à 500. |
| B10 | Le modèle tente de réécrire un article hors de son lot | Résiste | Bloqué par la clause `a.id IN (lot en cours)`. |
| B11 | Un article piégé fait écrire au modèle un lien HTML de phishing dans le résumé | **Vulnérable** | Le HTML du résumé est stocké puis envoyé tel quel (chaîne complète avec B02). |

### Recommandations pour B

1. **Échapper le HTML** de `title`, `summary` et `source` avant de construire l'email, et n'accepter
   que les URL en `http://` ou `https://` (B02, B11).
2. Retirer les balises des résumés à l'enregistrement, par exemple
   `regexp_replace(left(x.summary, 500), '<[^>]*>', '', 'g')` (B11).
3. Appliquer la migration proposée (fuseaux et emails valides en base) (B01, B07).
4. Rendre l'envoi tolérant aux erreurs par utilisateur (`On Error : Continue` sur `Envoyer la
   newsletter`) pour qu'un cas isolé ne bloque pas tout le monde.
5. Désinscription : page avec un bouton de confirmation (POST), ou en-têtes
   `List-Unsubscribe` / `List-Unsubscribe-Post` (RFC 8058) (B06).
6. Lire les nouvelles préférences : `tone`, `format`, `excluded_sources` (noms exacts des sources
   de la collecte) et la table `feedback`. Le feedback est un texte libre : le traiter comme une
   donnée, jamais comme une instruction, s'il est donné au LLM.

## 5. Risques résiduels et recommandations générales

| Risque | Gravité | Recommandation |
|---|---|---|
| Le filtre d'injection de prompt repose sur des motifs : une reformulation peut passer | Moyenne | Accepté : ce n'est qu'une couche. La vraie protection est structurelle (outils liés au `user_id`, valeurs validées en SQL), et elle a tenu face à un modèle entièrement manipulé. |
| Changement d'email sans vérification | Moyenne | Envoyer un lien de confirmation à la nouvelle adresse (double opt-in) avant de l'utiliser. |
| Pas de limitation de débit par IP sur le Chat Trigger | Moyenne | Reverse proxy (nginx, Caddy) avec limitation de débit devant n8n. Le verrouillage par compte limite déjà la force brute. |
| Transport en HTTP | Élevée en production | HTTPS obligatoire dès que n8n est exposé : les mots de passe transitent dans le chat. |
| `docker-compose.yml` publie Postgres (5432) et n8n (5678) sur toutes les interfaces | Moyenne | Écrire `127.0.0.1:5432:5432`, voire retirer le port Postgres (n8n y accède par le réseau Docker). |
| Données d'exécution n8n | Faible | `[A] Chat - Entrée` n'enregistre aucune exécution (mots de passe). Pour les autres, fixer une durée de conservation (`EXECUTIONS_DATA_MAX_AGE`). |
| Gemini est un sous-traitant (Google) | RGPD | À inscrire au registre des traitements. Seuls les messages de conversation lui sont envoyés, jamais les commandes d'authentification. |
| Quota gratuit Gemini (20 requêtes par jour pour `gemini-3-flash`) atteint pendant les tests | Disponibilité | La collecte horaire de B suffit à le dépasser : choisir un modèle ou une offre avec un quota adapté. L'agent réessaie 3 fois sur erreur 503. |
| `persona_cleanup()` est `SECURITY DEFINER` sans `search_path` fixé | Faible | Corrigé dans la migration proposée. |

## 6. RGPD côté utilisateur

| Exigence | Mise en œuvre |
|---|---|
| Information et consentement | Message d'accueil (données, finalité, durée, droits) ; inscription impossible sans « j'accepte » ; date et version du consentement en base. |
| Minimisation | Email, mot de passe haché, préférences ; ni nom, ni IP, ni message complet dans le journal. |
| Droit d'accès et portabilité | Commande « mes données » : export JSON. |
| Droit d'opposition | Pause de la newsletter via l'agent ; lien de désinscription dans chaque email (B). |
| Droit à l'effacement | « supprimer mon compte » puis « confirmer suppression » : suppression en cascade, trace `account_deleted` sans donnée personnelle. |
| Durées de conservation | `persona_cleanup()` chaque nuit : sessions expirées, articles 30 jours, envois 6 mois, journal et feedback 1 an. |
