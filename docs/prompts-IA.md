# Les prompts du chatbot

Le chatbot appelle Gemini à deux endroits :

- `[A] Chat - Intention` comprend une phrase libre (« je voudrais créer un compte ») et la range
  dans une liste fermée d'actions.
- `[A] Chat - Agent` règle la newsletter d'un utilisateur connecté, avec ses outils.

Au début, chacun avait un seul prompt, le même pour tout le monde. Maintenant, le prompt change
selon l'étape où en est l'utilisateur. Dans les deux workflows, un nœud Code `Choisir le prompt`
assemble le prompt juste avant l'appel à Gemini.

Le modèle est `gemini-3.5-flash-lite` depuis le 14/11. Avant, c'était `gemini-3-flash-preview` :
les versions plus bas datées d'avant le 14/11 ont été écrites et testées avec lui (voir
[optimisation-IA.md](optimisation-IA.md#les-deux-modèles-essayés)).

## L'agent : un prompt par étape

Le nœud `Lire l'étape` lit en SQL les préférences de l'utilisateur, la date de sa dernière
newsletter et celle de son dernier avis. `Choisir le prompt` en déduit l'étape, dans cet ordre :

1. **pause** : la newsletter est en pause. L'agent demande s'il veut la reprendre, et s'il dit
   pourquoi il l'a arrêtée, propose le réglage qui corrige le problème.
2. **interets** (étape 1 sur 3) : aucun centre d'intérêt choisi, donc la newsletter est vide.
   L'agent pousse vers `modifier_interets`, avec des exemples. Prochaine étape annoncée : les
   jours et l'heure d'envoi.
3. **premier_envoi** (étape 2 sur 3) : les sujets sont choisis, mais aucune newsletter n'est
   partie. L'agent fait vérifier les réglages d'envoi, une question à la fois, et dit quand
   partira la première. Prochaine étape annoncée : donner son avis.
4. **avis** (étape 3 sur 3) : une newsletter reçue il y a moins de 7 jours, sans avis depuis.
   L'agent demande ce qu'il en a pensé, l'enregistre avec `donner_feedback` et propose le
   réglage qui va avec (« trop long » = format titres).
5. **suivi** : tout le reste. L'agent répond à la demande, sans rien proposer de plus.

Le prompt final est fait de 5 morceaux :

- la base commune : le rôle, les règles de sécurité et les valeurs autorisées, identiques à
  toutes les étapes
- le bloc de l'étape : l'objectif, l'outil à utiliser et la prochaine étape
- la date et l'heure du jour, dans le fuseau de l'utilisateur : Gemini ne les connaît pas
- les préférences actuelles (sujets, jours, heure, ton, format, dernière newsletter), pour que
  l'agent n'ait pas besoin d'appeler `lire_preferences` à chaque message. On y ajoute le
  premier créneau qu'on peut encore régler et le prochain envoi prévu, calculés par le code avec
  la même règle que `[B] News - Envoi` (un passage toutes les 5 minutes, les jours choisis, et
  une seule newsletter toutes les 20 h) : Gemini se trompe quand il compte les jours lui-même
- le ton : tutoiement si l'utilisateur a choisi le ton décontracté, vouvoiement sinon

Exemple de parcours : un nouvel inscrit écrit « salut », l'agent lui demande ses sujets (étape
1). Il répond « le foot et l'espace », l'agent enregistre `sport, espace`. Au message suivant,
il passe à l'étape 2 et l'agent lui fait vérifier son heure d'envoi. Après la première
newsletter de B, il passe à l'étape 3.

## L'intention : un prompt visiteur, un prompt abonné

- **visiteur** (non connecté) : le mot de la liste, puis une réponse courte et naturelle qui se
  termine en invitant à taper `inscription` ou `connexion`. C'est cette réponse que la bulle
  affiche.
- **abonné** (connecté) : le mot seul. Pour un abonné, la réponse vient de l'agent, ou d'une
  phrase fixe pour les actions (déconnexion, mes données…). Rédiger une réponse ici ne servait
  à rien. Une seule exception : `aide`. `Répondre aide` affiche la réponse de Gemini, connecté
  ou non. Pour ce mot, l'abonné reçoit donc une réponse courte qui ne cite que ce que le service
  sait faire.

Si la valeur `connecte` est absente ou inconnue, on prend le prompt visiteur, qui ne promet
aucune action.

## Les versions

Chaque version est notée dans le code (`VERSION`), et ressort avec le prompt dans l'exécution
n8n du nœud `Choisir le prompt`.

**Agent**

- **v1** (29/10, commit `f985585`) : un seul prompt pour tout le monde, le rôle et les règles
  de sécurité. Ce qui n'allait pas :
  - rien ne disait à Gemini qu'un nouvel inscrit n'a pas encore de sujets, et donc pas de
    newsletter ;
  - pour savoir quoi que ce soit sur l'utilisateur, il devait appeler `lire_preferences`, ce qui
    fait un aller-retour de plus avec Gemini, compté dans le quota de 20 requêtes par jour ;
  - il parlait de la même façon à tout le monde, alors que l'utilisateur choisit un ton.
- **v2** (12/11) : la base de v1, plus un bloc par étape, les préférences dans le prompt et le
  ton de l'utilisateur.
- **v2, réglage du modèle** (12/11) : en testant v2 dans la bulle, une réponse s'arrêtait au
  milieu d'une phrase. L'exécution n8n montrait `MAX_TOKENS` : sur les 600 tokens autorisés,
  Gemini 3 en avait utilisé 577 pour réfléchir et 23 pour répondre. La limite passe à 2048 pour
  l'agent, et de 256 à 1024 pour l'intention, qui avait le même problème. Le prompt ne
  changeait rien : c'était le réglage du modèle.
- **v2, date du jour** (12/11) : à l'étape 2, l'agent devait dire quand partirait la première
  newsletter, mais le prompt ne lui donnait ni la date ni le jour. Il ne pouvait que l'inventer.
  Le prompt donne maintenant la date et l'heure dans le fuseau de l'utilisateur, plus le
  prochain envoi calculé par le code, et l'étape 2 interdit à Gemini de calculer une date
  lui-même. La date de la dernière newsletter est aussi écrite dans le fuseau de l'utilisateur
  (elle l'était en `Europe/Paris`).
- **v2, réintégrer une source** (14/11) : en testant dans la bulle, « je souhaite réinclure la
  source Le Monde ». Aucun outil ne savait le faire : l'agent a appelé deux fois `exclure_source`
  avec France Info, puis a répondu qu'il ne pouvait pas réinclure Le Monde, sans dire qu'il venait
  d'exclure France Info. Deux corrections :
  - un outil `reinclure_source`, l'inverse de `exclure_source`, avec la même liste de sources ;
  - une règle de plus dans la base : « N'utilise un outil que pour faire ce que l'utilisateur a
    demandé, jamais pour autre chose. Si aucun outil ne permet sa demande, dis-le et ne modifie
    rien d'autre. »

  Les descriptions de `exclure_source` et `reinclure_source` disent aussi quand utiliser l'un ou
  l'autre.
- **v3** (14/11) : les créneaux de 5 minutes. Avant, l'envoi ne passait qu'à l'heure pile, et on
  ne pouvait pas montrer un envoi programmé sans attendre jusqu'à une heure. Ce qui change :
  - la base dit que les envois partent par créneaux de 5 minutes, qu'on arrondit au créneau
    suivant (8 h 07 = 8 h 10), et comment faire pour « dans 10 minutes » ;
  - le prompt donne l'heure avec les minutes et le premier créneau possible (au moins 2 minutes
    d'avance, pour que le réglage soit enregistré avant le passage de l'envoi) ;
  - le prochain envoi prévu tient compte de la minute et de la règle des 20 h. Avant, l'agent
    pouvait annoncer un envoi que `[B] News - Envoi` allait sauter ; la ligne « pas de nouvelle
    newsletter avant » lui dit maintenant de prévenir l'utilisateur ;
  - `modifier_horaire` prend une minute (0, 5… 55), et `Lire l'étape` lit `send_minute` et
    `last_sent_at`.

**Intention**

- **v1** (09/11, commit `9079630`) : « Réponds par UN seul mot de cette liste », température 0.
  Le classement marchait, mais le chatbot répondait toujours avec les mêmes phrases fixes : c'est
  le retour qu'on a eu en testant.
- **v2** (09/11, commit `5d7dd2d`) : le mot, puis une réponse naturelle, température 0.4. Le cas
  connecté / non connecté était une condition écrite au milieu du prompt. Ce qui n'allait pas :
  - les deux cas étaient dans un seul texte, difficile à relire et impossible à tester sans
    lancer n8n ;
  - pour un abonné, Gemini écrivait le plus souvent une réponse que personne n'affiche.
- **v3** (12/11) : deux prompts séparés, choisis par le code et testés (ces tests ont été retirés
  le 14/11 : le prompt de l'intention se vérifie maintenant à la main). L'abonné garde une
  réponse rédigée pour `aide` seulement : sans elle, « tu sais faire quoi ? » retombait sur la
  phrase fixe, alors que v2 avait justement été faite pour éviter les phrases fixes.

## Tester une nouvelle version

1. Modifier le bloc dans `Choisir le prompt` et changer `VERSION` (par exemple `agent-v4`).
2. Lancer les tests : `docker compose exec -T n8n node - < scripts/test_scenarios.js`.
3. Rejouer les mêmes conversations dans la bulle, une par étape, et comparer les réponses avec
   la version précédente :
   - nouveau compte, « salut » : l'agent doit demander les sujets, avec des exemples
   - « j'aime le foot et l'espace », puis « c'est bon ? » : sujets enregistrés, puis question
     sur l'heure d'envoi
   - « mets ma newsletter en pause », puis « salut » : il propose de la reprendre
   - après une newsletter reçue, « merci » : il demande ce qu'on en a pensé
   - « exclus Le Monde », puis « en fait remets Le Monde » : Le Monde est exclue puis remise,
     et aucune autre source ne change
   - une demande qu'aucun outil ne sait faire (« ajoute Le Figaro ») : il le dit, et rien ne change
   - « envoie-moi la newsletter dans 10 minutes » : il règle le bon créneau et annonce l'heure,
     puis la newsletter arrive dans Mailpit (voir le [README](../README.md#6-tester-un-envoi-programmé))

Pour l'agent, `scripts/test_scenarios.js` a 4 tests. Dans la section `[A] Chat - Agent : prompt
par étape` : sans centre d'intérêt, l'agent est à l'étape 1 (choisir ses sujets), et le prochain
envoi tient compte de la minute et de la règle des 20 h. Dans `[A] Chat - Agent : outil
modifier_horaire` : une minute hors créneau est refusée. Voir [tests-scenarios.md](tests-scenarios.md).

Tout le reste se vérifie avec les conversations ci-dessus : les autres étapes, les règles de
sécurité et la règle « un outil seulement pour ce que l'utilisateur a demandé » à chaque étape,
l'outil `reinclure_source`, l'arrondi des minutes par Gemini, le ton et le prompt de l'intention.
