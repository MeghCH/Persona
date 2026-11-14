# Audit de sécurité - Persona

Partie A (chatbot et sécurité). Version du 13/11/2026, sur la branche `main`.

Cet audit regarde ce qu'on a construit pour le chatbot, ce qu'on a essayé de casser, ce qui a tenu,
ce qui ne tenait pas et ce qui reste à faire. Il couvre aussi les workflows de B, qu'on a attaqués
comme prévu en phase 2.

## En bref

- Le chatbot ne laisse pas l'IA gérer la connexion, les comptes ni les mots de passe : tout ça se
  fait en SQL, sans Gemini.
- Même si on arrive à manipuler l'IA, elle ne peut toucher qu'au compte de l'utilisateur connecté.
- Depuis le premier audit (29/10), on a ajouté deux protections : une limite du nombre de messages
  envoyés à l'IA, et un code reçu par email avant de créer un compte.
- Les 75 tests de `scripts/test_scenarios.js` passent (lancés le 13/11). Depuis le 14/11, le
  script en a 35 (voir la mise à jour ci-dessous).
- Les 4 failles trouvées chez B sont corrigées.
- Il reste des risques, dont 2 à traiter avant une mise en ligne : pas de HTTPS, et pas de limite
  d'envois de codes par adresse email. Postgres et n8n ne sont plus ouverts sur le réseau depuis
  le 14/11.

## Mise à jour du 14/11

Ce qui a changé depuis le 13/11 et touche cet audit. Le reste du document est celui du 13/11.

- **Le modèle.** Les 4 nœuds Gemini utilisent maintenant `gemini-3.5-flash-lite`, écrit dans chaque
  nœud. Avant, n8n prenait `gemini-3-flash-preview` par défaut. Le quota de 20 requêtes par jour
  cité plus bas était celui de l'ancien modèle : le nouveau a tenu au moins 31 requêtes le 14/11
  sans aucun refus. La limite de 600 messages par jour reste à régler sur son vrai quota (voir
  [optimisation-IA.md](../optimisation-IA.md)).
- **Une erreur de l'agent, trouvée à la main.** À « réinclure Le Monde », qu'il ne savait pas
  faire, l'agent a appelé `exclure_source` avec France Info, puis a répondu sans le dire. Ce n'est
  pas une faille (il ne pouvait toucher qu'au compte connecté), mais c'est le risque « Excessive
  Agency » de l'OWASP : l'IA modifie quelque chose qu'on ne lui a pas demandé. Corrigé de deux
  façons :
  - un outil `reinclure_source`, avec les mêmes protections que les autres : l'utilisateur vient
    de la session, la liste des sources est fermée, et chaque modification est notée dans
    `audit_log` (`prefs_source_included`) ;
  - une règle dans le prompt, à toutes les étapes : un outil ne sert qu'à ce que l'utilisateur a
    demandé ; sinon, l'agent le dit et ne modifie rien.

  Revérifié à la main. Aucun test automatique ne vérifie ces deux corrections : il faut rejouer les
  conversations de [prompts-IA.md](../prompts-IA.md#tester-une-nouvelle-version) quand on modifie
  l'agent.
- **Les préférences du chat dans l'email.** B applique maintenant le format et les sources exclues.
  Les sources exclues sont filtrées en SQL, avec une liste passée en paramètre : pas d'injection
  possible. Le ton et le feedback ne sont toujours pas utilisés par B.
- **Les articles perdus.** Quand Gemini refusait un lot, ses articles n'étaient jamais repris. Ils
  le sont maintenant, 50 au plus par collecte, et passent par les mêmes contrôles (contrôle
  automatique, puis IA relectrice).
- **Les tests.** Le script est passé à 124 tests, puis on l'a réduit à 29, rangés par workflow :
  un test par protection pour la collecte et l'envoi, et ailleurs le cas normal et le cas le plus
  important à bloquer. Les 29 passent (lancés le 14/11). Les tests de la collecte et de l'email
  cités plus bas (HTML, lien `javascript:`, adresse piégée, résumé piégé) sont toujours là.
  D'autres n'existent plus : le comptage en une seule requête (`reserver_appel_ia`), les liens
  retirés de la réponse de l'intention, le code tiré avec `gen_random_bytes`, les règles du prompt
  de l'agent à chaque étape, l'outil `reinclure_source`. Ces protections, elles, sont toujours
  dans les workflows. Côté chat, les tests qui restent sont : le mot de passe qui ne part jamais à
  l'IA, la limite de 6 messages par minute, une phrase d'inscription comprise, aucune intention
  qui supprime un compte (toutes essayées, connecté ou non), le bon code qui crée le compte et ses
  5 essais, et l'étape 1 de l'agent. La liste complète est dans
  [tests-scenarios.md](../tests-scenarios.md).
- **Le registre RGPD.** Gemini y est noté comme sous-traitant qui reçoit les messages du chat, et
  la table `chat_ai_requests` y a été ajoutée (voir [normes-RGPD.md](../normes-RGPD.md)).
- **Les ports de Postgres et de n8n.** Ils étaient ouverts sur toutes les interfaces réseau
  (`5432:5432`, `5678:5678`) : sur le réseau de l'école, n'importe qui pouvait essayer de se
  connecter à la base. Ils ne sont plus ouverts que sur la machine (`127.0.0.1:5432:5432`,
  `127.0.0.1:5678:5678`), comme Mailpit et la page du chatbot. Le chat et le lien de
  désinscription marchent toujours : ils passent par `localhost`.
- **L'heure d'envoi par créneaux de 5 minutes.** Nouvelle colonne `send_minute`. La base refuse une
  minute qui n'est pas 0, 5… 55 (contrainte `preferences_send_minute_check`), et `modifier_horaire`
  la vérifie avant d'écrire, comme l'heure. L'IA ne peut toujours toucher qu'au compte connecté.
  6 tests ajoutés : le script en a 35, qui passent.

## Ce qu'on a audité

- les workflows `[A] Chat - Entrée`, `[A] Chat - Agent` et `[A] Chat - Intention`
- la base de données (`db/schema/02-schema.sql`) et les droits de l'utilisateur `persona_app`
- la page du chatbot (`web/index.html`) et la configuration Docker
- les workflows de B : collecte, envoi, désinscription, maintenance RGPD

## Comment on a testé

Il y a eu trois sortes de tests.

**1. Attaques sur une deuxième installation (29/10).** On a monté une copie de Persona, à part, pour
ne pas toucher aux vraies données. On y a remplacé Gemini par un faux serveur qui répond ce qu'on
veut, y compris des réponses malveillantes : c'est comme si quelqu'un avait réussi à manipuler
l'IA. On voit donc ce que le système laisse passer même dans le pire cas. Un faux serveur mail
récupérait aussi les newsletters envoyées par B. Chaque test envoyait un vrai message au chatbot
puis regardait ce qui avait changé dans la base.

**2. Les tests automatiques (relancés le 13/11).** Le fichier `scripts/test_scenarios.js` lance le
vrai code des nœuds des workflows. 75 tests, tous passent. Ils couvrent la collecte, l'envoi, le
choix des messages qui partent vers l'IA, les limites, la lecture des réponses de l'IA, le chemin
vers l'agent et le code d'inscription. La CI de GitHub les relance à chaque pull request.
Depuis le 14/11, il en reste 29 : la lecture des réponses de l'IA et le chemin vers l'agent ne
sont plus testés, et il ne reste qu'une limite (6 messages par minute).

**3. Les essais en direct (novembre).** Pour les deux nouveautés, on a joué des vrais scénarios
dans le vrai n8n, avec la vraie base :

- dix messages envoyés en même temps pour tester la limite (voir plus bas)
- l'inscription complète avec le code, y compris les mauvais cas
- les requêtes SQL du code, jouées à la main avec le compte `persona_app`

## Comment le chatbot se protège

Un message passe par ces étapes :

1. On le nettoie (caractères invisibles, 1000 caractères au maximum) et on refuse les identifiants
   de session trop courts, qu'on pourrait deviner.
2. Si c'est une inscription ou une connexion, on la traite en SQL, sans l'IA.
3. Sinon, on vérifie la session. Pas connecté : le chatbot répond par une phrase et s'arrête là.
4. Les commandes `deconnexion`, `mes données` et `supprimer mon compte` sont aussi traitées sans IA.
5. Les messages qui vont à l'IA passent d'abord par la limite du nombre de messages.
6. Puis par un filtre anti-injection, et enfin à l'agent.

Les idées principales :

- **L'IA ne s'occupe jamais de la connexion.** Le mot de passe et le code reçu par email ne lui
  sont jamais envoyés.
- **L'IA ne choisit jamais l'utilisateur.** Les outils de l'agent reçoivent l'identifiant de
  l'utilisateur depuis la session. L'IA donne seulement les valeurs (intérêts, heure…).
- **Tout est vérifié en base** : requêtes avec paramètres (`$1`, `$2`), listes de valeurs
  autorisées, contraintes `CHECK`.
- **n8n a le minimum de droits** : il utilise `persona_app`, qui ne peut pas modifier le schéma ni
  effacer ou modifier `audit_log`. Aucun outil ne touche à `role` ni à `password_hash`.
- **Les mots de passe sont hachés** avec bcrypt (coût 12), font au moins 12 caractères avec au
  moins 3 types de caractères, et ne peuvent pas contenir l'identifiant de l'email.
- **Les sessions expirent** : 2 heures sans activité, 8 heures au maximum.
- **5 mauvais mots de passe bloquent le compte 15 minutes.**
- **Tout est noté dans `audit_log`** (connexions, échecs, blocages, injections, suppressions),
  sans mot de passe ni message en clair.
- **Le workflow n'enregistre pas ses exécutions**, parce que les messages contiennent des mots de
  passe.

## Ce qu'on a ajouté depuis le 29/10

### Limite des messages envoyés à l'IA

Le risque : quelqu'un envoie beaucoup de messages pour épuiser le quota de Gemini, et plus
personne n'a de réponse (le risque « Model Denial of Service » de l'OWASP). Avant, on limitait
seulement la taille d'un message.

Maintenant, chaque message qui coûte un appel à Gemini est compté :

- 6 messages par minute et par session
- 100 messages par jour et par session
- 200 messages par jour et par compte
- 150 messages par jour pour tous les non connectés ensemble
- 600 messages par jour en tout

Les non connectés ont une petite part du total : même s'ils changent d'identifiant de session à
chaque message, ils ne peuvent pas épuiser le quota des utilisateurs connectés.

**Une faille trouvée en testant.** Notre première version comptait les messages, puis les
enregistrait, en deux étapes. Avec dix messages envoyés en même temps, tous lisaient le même
comptage : 9 sur 10 passaient, pour une limite de 6. On l'a corrigé : le comptage et
l'enregistrement se font maintenant en une seule fois, dans la fonction SQL `reserver_appel_ia`,
qui pose un verrou. Même test après correction : 6 passent, 4 sont refusés. Un test automatique
vérifiait qu'aucun autre nœud n'enregistre de message (retiré le 14/11 : la protection est toujours
dans le workflow, mais plus aucun test ne la vérifie).

Autres réglages : l'agent réessaie 2 fois (au lieu de 3), chaque exécution est coupée au bout de
60 secondes, et les refus sont notés dans `audit_log` (au plus une ligne par raison et par minute,
pour qu'on ne puisse pas remplir le journal). Les commandes exactes (`inscription`, `connexion`,
`aide`…) marchent même quand la limite est atteinte, car elles n'ont pas besoin de l'IA.

Détails : [protection-deni-of-service.md](../protection-deni-of-service.md).

### Comprendre les phrases libres

Le chatbot comprend maintenant « je voudrais créer un compte ». Gemini range la phrase dans une
liste fermée (`inscription`, `connexion`, `aide`, `aucune`…) et écrit une réponse courte. Il n'a
aucun outil et ne fait aucune action : c'est le workflow qui décide.

- Si l'IA répond autre chose qu'un mot de la liste, la réponse est ignorée.
- Une phrase ne peut jamais supprimer un compte : il faut taper exactement
  `confirmer suppression`. Un test essaie toutes les intentions possibles pour le vérifier.
- Un non connecté ne peut pas obtenir un export ni une suppression.
- Les liens sont retirés de la réponse de l'IA, et elle est limitée à 400 caractères. Un test
  simulait une IA qui écrit un lien de phishing (retiré le 14/11 : la protection est toujours dans
  le workflow).
- Pendant l'inscription et la connexion, rien ne part vers l'IA.
- Si Gemini ne répond pas (quota), le chatbot garde ses phrases fixes.

### Code reçu par email à l'inscription

Le risque : sans vérification, on pouvait créer un compte avec l'email de quelqu'un d'autre, ou
créer des comptes en masse avec de fausses adresses.

Maintenant, le compte n'est créé qu'avec le bon code à 6 chiffres reçu par email :

- le code est tiré avec `gen_random_bytes` (hasard sûr), pas avec `random()`
- il n'est jamais gardé en clair : seulement son hash, qui disparaît avec l'étape
- il est valable 10 minutes, avec 5 essais au maximum
- on ne peut pas demander plus de 3 codes par inscription
- le code ne part jamais à l'IA, et n'apparaît dans aucune réponse du chat
- l'inscription en une ligne a été supprimée, parce qu'elle sautait le code
- pour un email déjà inscrit, le chat répond exactement pareil, et la vraie personne reçoit un
  email qui la prévient, sans code : on ne peut pas savoir qui a un compte

Détails : [code-inscription.md](../code-inscription.md).

## Ce qu'on a essayé sur le chatbot

Tout a été refusé ou bloqué :

- un identifiant de session comme `abc`, un message de 1001 caractères, un message vide
- s'inscrire avec un email invalide, un mot de passe trop court ou trop simple, sans accepter les
  conditions
- se réinscrire avec un email déjà pris : même réponse que pour un nouvel email, et le mot de passe
  d'origine ne change pas
- de l'injection SQL dans l'email et dans le mot de passe
- se connecter avec un email inconnu ou un mauvais mot de passe : même réponse dans les deux cas
- 5 mauvais mots de passe puis le bon : compte bloqué 15 minutes
- réutiliser une session après déconnexion, après 2 h d'inactivité ou après 8 h
- faire lire ou modifier par l'IA les données d'un autre utilisateur
- prendre l'email d'un autre compte
- retrouver la mémoire de l'IA d'un autre compte dans la même fenêtre de chat
- faire ajouter `role=admin` par l'IA : le rôle reste `user`
- `x'); DROP TABLE users;--` dans un outil : la table est intacte
- des valeurs absurdes : fuseau `Mars/Olympus`, heure 25, jours 9 et 99, ton `admin`
- une IA qui recrache un hash de mot de passe ou un identifiant interne : masqués avant l'affichage
- les injections de prompt classiques (« ignore tes instructions », révéler le prompt, « passe mon
  compte en admin », mode DAN, `<|im_start|>`, mot caché avec un caractère invisible…) : bloquées
  et notées dans `audit_log`
- pour le code d'inscription : un mauvais code, un ancien code après un renvoi, 5 erreurs puis le
  bon code, une 4e demande de code, un code tapé sans inscription en cours, un email déjà inscrit

Et ce qui devait marcher marche : une demande normale (« des news sur le foot et l'espace le
matin ») n'est pas bloquée, l'export « mes données » ne contient aucun secret, et la suppression
du compte efface bien tout (compte, préférences, sessions, feedback).

Le mot de passe n'est écrit nulle part en clair : seulement son hash bcrypt. Il n'est pas envoyé à
l'IA, ni écrit dans le journal. Sur la page de démo, il est masqué pendant la saisie et affiché
`••••••••` ensuite. La page de chat de n8n ne le masque pas, il faut donc utiliser la page de démo.

## Phase 2 : nos attaques sur les workflows de B

On avait trouvé 4 failles. Elles sont corrigées. Le script de tests vérifie les cas de l'email et
de la collecte (HTML, lien `javascript:`, adresse piégée, résumé piégé). Les deux contraintes de la
base (fuseau et email) sont dans le schéma, mais pas dans le script de tests.

- **Un fuseau horaire invalide bloquait tout le monde.** Un seul utilisateur avec
  `timezone = 'Mars/Olympus'` faisait planter la requête de l'envoi : plus personne ne recevait
  la newsletter. Maintenant la base refuse cette valeur (`preferences_timezone_valid`).
- **Le HTML des articles passait tel quel dans l'email.** Un titre avec `<img src=x onerror=…>`, un
  lien `javascript:` ou un lien de phishing arrivaient dans la newsletter. Maintenant le titre, la
  source et le résumé sont échappés, et seuls les liens `http` et `https` sont gardés.
- **L'IA de la collecte pouvait écrire du HTML dans les résumés.** Un article piégé pouvait lui
  faire ajouter un lien de phishing. Maintenant un contrôle automatique rejette un résumé avec du
  HTML, un lien ou une consigne, puis une deuxième IA relit chaque résumé avant qu'il soit gardé.
- **Une adresse email piégée détournait la newsletter.** Avec `pirate@…\r\nBcc: espion@…` en base,
  l'email partait chez l'espion. Maintenant la base vérifie le format (`users_email_valid`) et
  l'envoi est bloqué si l'adresse est suspecte.

Avant chaque envoi, `Vérifier l'email` contrôle le destinataire, la présence d'un lien de
désinscription, l'absence de balises dangereuses et les liens. Si un point échoue, l'email ne part
pas et l'événement `newsletter_blocked` est noté dans `audit_log`.

Ce qui a tenu dès le début : l'injection SQL, les jetons inconnus sur le lien de désinscription,
les thèmes hors liste renvoyés par l'IA, les résumés trop longs (coupés à 500 caractères) et une
IA qui essaie de modifier un article hors de son lot.

## Ce qui reste à améliorer

Classé du plus important au moins important.

**À traiter avant une mise en ligne**

- ~~**Postgres et n8n sont ouverts sur toutes les interfaces réseau.**~~ Fait le 14/11 :
  `127.0.0.1:5432:5432` et `127.0.0.1:5678:5678` dans `docker-compose.yml`. Pour une mise en ligne,
  on pourrait aussi ne plus ouvrir Postgres du tout.
- **Tout passe en HTTP.** Les mots de passe passent par le chat : il faudra du HTTPS dès que le
  projet sera en ligne.
- **Pas de limite d'envois de codes par adresse email.** On limite à 3 codes par inscription, mais
  quelqu'un peut recommencer avec une nouvelle session et envoyer beaucoup d'emails à la même
  personne. La limite du nombre de messages ne s'applique pas ici, parce que ces messages ne
  passent pas par l'IA. Solution : compter les codes envoyés par adresse et par heure.

**Importants**

- **On peut changer d'email sans confirmer la nouvelle adresse** (outil `modifier_email` de
  l'agent). Il faudrait envoyer un code à la nouvelle adresse, comme à l'inscription.
- **Pas de limite par adresse IP**, ni sur le nombre d'inscriptions. Le workflow ne reçoit pas
  l'adresse de l'appelant : le plus simple est de la mettre dans nginx (`limit_req`) devant la page.
  Quelqu'un avec beaucoup de vraies adresses peut toujours créer beaucoup de comptes.
- **Le quota gratuit de Gemini (20 requêtes par jour) est trop petit** : la collecte de B le
  dépasse à elle seule, et les appels de B ne passent pas par notre limite. Quand il est épuisé, le
  chatbot n'a plus que ses phrases fixes.

**Petits risques**

- **La désinscription se fait avec un simple clic** sur le lien de l'email. Certains antivirus
  ouvrent les liens tout seuls et peuvent désinscrire quelqu'un sans qu'il le sache. Un bouton de
  confirmation règlerait ça.
- **Un problème d'envoi d'email arrête l'envoi des autres.** Le nœud d'envoi n'est pas en
  `On Error : Continue`. Une adresse mal vue par le serveur mail peut bloquer la suite de la liste.
- **Le filtre anti-injection marche avec des mots-clés** : une reformulation peut passer. Ce n'est
  pas grave, car même sans filtre l'IA ne peut toucher qu'au compte connecté.
- **Le chat est public** : n'importe qui peut écrire au chatbot sans compte. C'est voulu, pour
  l'inscription. Seules les origines `localhost` sont autorisées (`allowedOrigins`), à changer
  pour la mise en ligne.

## RGPD côté utilisateur

- **Consentement** : avant le mot de passe, le chatbot demande si on accepte la politique de
  confidentialité, et `en savoir plus` l'affiche en entier. On ne peut pas s'inscrire sans écrire
  « j'accepte ». La date et la version sont enregistrées.
- **Peu de données** : email, mot de passe haché, préférences. Pas de nom, pas d'IP.
- **Accès** : `mes données` affiche tout ce qu'on garde.
- **Désinscription** : on peut mettre la newsletter en pause dans le chat, et chaque email a un
  lien de désinscription.
- **Effacement** : `supprimer mon compte` efface tout.
- **Durée de conservation** : `persona_cleanup()` tourne chaque nuit (sessions expirées, étapes
  d'inscription après 1 heure, appels à l'IA après 2 jours, articles après 30 jours, envois après
  6 mois, journal et feedback après 1 an). Un compte désabonné depuis 6 mois est supprimé en entier.
- **À noter dans le registre RGPD** : Gemini (Google) reçoit les messages de conversation.

## Journal : relier une tentative au compte visé

Un échec de connexion sur un compte qui existe (`login_failed`, `account_locked`) et une
inscription avec un email déjà pris (`register_duplicate`) sont reliés au compte visé (`user_id`).
On peut donc voir si un compte précis est attaqué. Pour un email qui n'existe pas
(`login_failed_unknown`), on n'enregistre rien qui permette de le retrouver : il n'y a pas de
compte à relier, et on évite de garder l'adresse d'un inconnu. C'est le compromis choisi entre
détecter les attaques et garder le moins de données possible.

Les événements du code d'inscription sont aussi notés : `register_otp_sent`,
`register_otp_failed` (avec le numéro de l'essai) et `register_ok`.

## Conclusion

Le chatbot est bien protégé contre les attaques qu'on a essayées : l'IA n'a pas la main sur les
comptes, les mots de passe et les codes ne lui arrivent jamais, et les données de chaque
utilisateur sont séparées. Les deux ajouts récents (limite des messages et code par email) ont
chacun une faille trouvée en test, corrigée, puis vérifiée.

Avant de mettre Persona en ligne, il faut au minimum passer en HTTPS et limiter les envois de codes
par adresse. Les ports de Postgres et de n8n ne sont plus ouverts sur le réseau depuis le 14/11.
