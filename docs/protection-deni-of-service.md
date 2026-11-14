# Protection contre le déni de service du modèle

Le risque : quelqu'un envoie beaucoup de messages (ou des messages qui coûtent cher) pour
épuiser le quota de Gemini ou ralentir le chatbot. Les autres utilisateurs n'ont alors plus
de réponse. C'est le risque « Model Denial of Service » de l'OWASP pour les applications à base d'IA.

Avant, le chatbot limitait seulement la taille d'un message (1000 caractères). Rien ne limitait
le nombre de messages, et l'agent réessayait 3 fois quand Gemini échouait, ce qui triplait les appels.

## Ce qu'on a ajouté

**1. Une limite du nombre de messages qui passent par l'IA.** Chaque message qui va coûter un
appel à Gemini est compté dans la table `chat_ai_requests` (une ligne : la session, le compte,
l'heure, jamais le texte). Avant l'appel, le workflow `[A] Chat - Entrée` regarde les comptages :

| Limite | Valeur | Contre quoi |
|---|---|---|
| messages par minute, pour une session | 6 | les rafales |
| messages par jour, pour une session | 100 | une session qui ne s'arrête jamais |
| messages par jour, pour un compte | 200 | quelqu'un qui ouvre plusieurs sessions |
| messages par jour, tous les non connectés ensemble | 150 | quelqu'un qui change d'identifiant de session à chaque message |
| messages par jour, tout le monde | 600 | le quota Gemini |

Les non connectés ont une petite part du total : même si quelqu'un change d'identifiant à chaque
message, il ne peut pas épuiser le quota des utilisateurs connectés.

Un message peut coûter jusqu'à 2 appels à Gemini (comprendre la phrase, puis l'agent). Pour
changer les valeurs, modifier le haut du code du nœud `Contrôler le débit`.

Attention, le quota du jour dépend du modèle. Les valeurs ont été choisies pour laisser une marge
sous le quota, mais avec `gemini-3-flash-preview`, le premier modèle, il n'était que de 20 requêtes
par jour : la limite de 600 ne protégeait rien. Le modèle actuel, `gemini-3.5-flash-lite`, a un
quota plus haut, dont on ne connaît pas encore la valeur exacte. Il faudra régler la limite de 600
dessus (voir [optimisation-IA.md](optimisation-IA.md)). Cette limite ne contrôle pas les appels de B (collecte, évaluation), qui
utilisent le même quota.

Compter et enregistrer le message se font en une seule fois, dans la fonction SQL
`reserver_appel_ia` (nœud `Compter les appels IA`). Elle pose un verrou : des messages envoyés
au même moment passent un par un, et chacun voit les précédents. Sans ça, dix messages envoyés
ensemble lisaient le même comptage et passaient tous (on l'a constaté : 9 sur 10 passaient pour
une limite de 6). Si le message est refusé, sa réservation est supprimée : les refus n'usent pas
les limites du jour.

Quand une limite est atteinte, le chatbot répond par une phrase claire et n'appelle pas Gemini.
Les commandes exactes (`inscription`, `connexion`, `aide`, `mes données`…) marchent toujours,
parce qu'elles n'ont pas besoin de l'IA.

Chaque refus est noté dans `audit_log` (`rate_limited`, avec la raison), au plus une ligne par
raison et par minute, pour qu'un attaquant ne puisse pas remplir le journal.

**2. Moins de tentatives et une durée maximale.**

- l'agent réessaie 2 fois au lieu de 3
- chaque exécution est coupée au bout de 60 secondes (`executionTimeout`)
- ce qui existait déjà : 1000 caractères par message, 2048 tokens de réponse au maximum pour
  l'agent et 1024 pour l'intention (Gemini 3 compte sa réflexion dedans, voir `docs/prompts-IA.md`),
  6 étapes d'outils au maximum, 8 messages gardés en mémoire

## Comprendre les phrases

Avant, le chatbot ne reconnaissait qu'une liste exacte de mots (`inscription`, `se connecter`…).
Maintenant, une phrase comme « je voudrais créer un compte » ou « comment je récupère mes
données ? » est comprise.

Le workflow `[A] Chat - Intention` demande à Gemini de classer la phrase dans une liste fermée :
`inscription`, `connexion`, `deconnexion`, `mes_donnees`, `supprimer_compte`, `confidentialite`,
`aide`, `annuler`, `aucune`. Dans le même appel, il écrit une réponse courte et naturelle, que le
chatbot affiche à la place de sa phrase habituelle (non connecté, aide). Les liens sont retirés de
cette réponse. Gemini ne fait aucune action : c'est le workflow d'entrée qui décide.

Ce qui reste protégé :

- **Le mot de passe ne part jamais à l'IA.** Pendant l'inscription ou la connexion guidée, rien
  n'est envoyé : le message est traité en SQL comme avant.
- **Seules les phrases de 200 caractères ou moins** sont interprétées. Les autres vont directement
  à l'agent (si on est connecté), comme avant.
- **Une phrase ne peut pas supprimer un compte.** `supprimer_compte` donne seulement la demande :
  le chatbot répond de taper exactement `confirmer suppression`. Cette commande-là reste une
  correspondance exacte, jamais une interprétation.
- **Chaque intention a un public.** Un non connecté ne peut pas demander un export ni une
  suppression. Un utilisateur connecté qui dit « je veux m'inscrire » continue avec l'agent.
- **Une réponse hors liste devient `aucune`.** Si l'IA répond autre chose qu'un mot de la liste
  (parce qu'une phrase piégée l'a manipulée), rien ne change.
- **Si l'IA ne répond pas**, le chatbot continue comme avant.

## Tests

```bash
docker compose exec -T n8n node - < scripts/test_scenarios.js
```

Ces tests lancent le vrai code des nœuds. Pour cette partie, il y en a 4, dans deux sections du
script (détail dans [tests-scenarios.md](tests-scenarios.md)) :

- `[A] Chat - Entrée : messages envoyés à l'IA`
  - pendant l'inscription ou la connexion guidée, rien ne part vers l'IA (le mot de passe n'y va
    jamais)
  - 6 messages en une minute : le suivant est refusé
- `[A] Chat - Entrée : comprendre les phrases`
  - un non connecté qui veut s'inscrire démarre l'inscription
  - le cas grave : aucune intention ne mène à `delete_confirm`

Les autres limites (par jour, par compte, pour les non connectés), le comptage en une seule requête
et la lecture de la réponse de l'IA ne sont plus testés automatiquement. Ils ont été vérifiés
quand ils ont été écrits (voir l'audit), et les protections sont toujours dans le workflow.

## Base de données

La table `chat_ai_requests` est dans `db/schema/02-schema.sql`. Une base déjà créée la reçoit
au prochain `bash scripts/setup.sh`, sans rien effacer.

Le nettoyage de nuit (`persona_cleanup()`) efface ces lignes au bout de 2 jours. Quand un compte
est supprimé, ses lignes restent jusque-là, mais elles ne sont plus liées à lui (`user_id` passe à
`NULL`, `ON DELETE SET NULL`). Sinon, quelqu'un pourrait s'inscrire, envoyer ses 200 messages,
supprimer son compte et recommencer : ses messages ne compteraient plus dans la limite du jour.
La colonne `connecte` garde le fait que le message venait d'un utilisateur connecté, pour qu'il ne
soit pas compté avec les non connectés.

### Mettre à jour une installation existante

`bash scripts/setup.sh` met à jour la base, mais il n'importe les workflows que s'ils n'ont jamais
été importés. Sur une installation existante, il ne remplace pas `[A] Chat - Entrée` et n'ajoute
pas `[A] Chat - Intention`. Il faut le faire à la main, dans cet ordre :

1. `bash scripts/setup.sh`, pour la base. À faire **avant** l'import : le nouveau
   `[A] Chat - Entrée` appelle `reserver_appel_ia`, et sans elle tous les messages qui passent par
   l'IA échouent.
2. Importer les workflows :
   ```bash
   docker compose exec n8n n8n import:workflow --separate --input=/home/node/exports
   ```
3. Ré-associer les credentials comme après chaque import (voir le README), dont `LLM Persona`
   dans le nœud `Modèle Gemini` de `[A] Chat - Intention`, puis réactiver les workflows : un
   import les désactive.

## Ce qui n'est pas couvert

- Une limite par adresse IP : le workflow ne reçoit pas l'adresse de l'appelant, tel qu'on utilise
  le Chat Trigger. Le plus simple serait de la mettre dans nginx (`limit_req`) devant `web`.
- Un attaquant avec beaucoup de comptes (6 messages chacun). Les non connectés sont bornés, les
  comptes créés non : il faudrait limiter les inscriptions par heure.
- Les appels de B (collecte, évaluation) utilisent le même quota Gemini mais ne passent pas par
  cette limite.
