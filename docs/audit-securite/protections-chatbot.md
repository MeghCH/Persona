# Comment le chatbot se protège

[Retour au sommaire](README.md)

## Le trajet d'un message

1. On le nettoie (caractères invisibles, 1000 caractères au maximum) et on refuse les identifiants
   de session trop courts, qu'on pourrait deviner.
2. Si c'est une inscription ou une connexion, on la traite en SQL, sans l'IA.
3. Sinon, on vérifie la session. Pas connecté : le chatbot répond par une phrase et s'arrête là.
4. Les commandes `deconnexion`, `mes données` et `supprimer mon compte` sont aussi traitées sans IA.
5. Les messages qui vont à l'IA passent d'abord par la limite du nombre de messages.
6. Puis par un filtre anti-injection, et enfin à l'agent.

## Les idées principales

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
- **Le prompt de l'agent suit l'étape de l'utilisateur**, mais garde toujours les mêmes règles de
  sécurité (voir [protections-IA.md](protections-IA.md)).
