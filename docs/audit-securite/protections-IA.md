# L'IA : phrases libres et prompts

[Retour au sommaire](README.md)

Ajouté depuis le premier audit (29/10).

## Ce que ça fait

Le chatbot comprend maintenant « je voudrais créer un compte ». Gemini range la phrase dans une
liste fermée (`inscription`, `connexion`, `deconnexion`, `mes_donnees`, `supprimer_compte`,
`confidentialite`, `aide`, `annuler`, `aucune`) et écrit une réponse courte.

Il n'a aucun outil et ne fait aucune action : c'est le workflow qui décide.

## Les protections

- Si l'IA répond autre chose qu'un mot de la liste, la réponse est ignorée.
- Une phrase ne peut jamais supprimer un compte : il faut taper exactement
  `confirmer suppression`. Un test essaie toutes les intentions possibles pour le vérifier.
- Un non connecté ne peut pas obtenir un export ni une suppression.
- Les liens sont retirés de la réponse de l'IA, et elle est limitée à 400 caractères. Un test
  simule une IA qui écrit un lien de phishing.
- Pendant l'inscription et la connexion, rien ne part vers l'IA.
- Seules les phrases de 200 caractères ou moins sont interprétées.
- Si Gemini ne répond pas (quota), le chatbot garde ses phrases fixes.

## Le prompt change selon l'étape de l'utilisateur

Depuis le 12/11, le prompt de l'agent n'est plus le même pour tout le monde. Un nœud lit en base
l'étape de l'utilisateur (newsletter en pause, choix des sujets, premier envoi, avis, tout est
réglé) et assemble le prompt. Le détail est dans [prompts.md](../prompts.md). Côté sécurité :

- chaque étape reprend les mêmes règles de sécurité : un test vérifie les 5 étapes
- le message de l'utilisateur reste séparé du prompt : c'est une donnée, jamais une consigne
- les préférences recopiées dans le prompt viennent de la base, où elles sont limitées par des
  listes ou des contraintes (sujets, sources, ton, format, fuseau, heures) : une valeur libre ne
  peut pas y arriver
- la lecture de l'étape utilise l'identifiant de la session, comme les outils de l'agent
- pour l'intention, il y a un prompt pour le visiteur et un autre pour l'abonné, choisis par le
  code : une valeur inconnue donne le prompt du visiteur, qui ne promet aucune action
