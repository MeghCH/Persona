# Code par email à l'inscription

Le risque : sans vérification, n'importe qui pouvait créer un compte avec l'email d'une autre
personne, ou créer des comptes en masse avec de fausses adresses (un robot, par exemple).

Maintenant, le compte n'est créé qu'une fois prouvé qu'on reçoit bien les emails de l'adresse.

## Ce que voit l'utilisateur

1. `inscription`, puis son email, puis `j'accepte`, puis son mot de passe (comme avant)
2. le chatbot répond : « Je vous ai envoyé un code à 6 chiffres par email »
3. il tape le code dans le chat
4. « C'est fait ✅ Votre email est vérifié et votre compte est créé »

`renvoyer le code` envoie un nouveau code. `annuler` arrête l'inscription.

L'inscription en une ligne (`inscription EMAIL MOT_DE_PASSE j'accepte`) n'existe plus : elle
créait le compte sans passer par le code. La connexion en une ligne existe toujours.

## Comment c'est fait

Tout se passe dans `[A] Chat - Entrée`, en SQL, sans l'IA :

- `Préparer le code` : quand le mot de passe est accepté, tire le code, le hache et le garde
  dans `auth_pending` avec le mot de passe déjà haché. Aucun compte n'est encore créé.
- `Écrire l'email` puis `Envoyer le code` : envoie le code par SMTP.
- `Vérifier le code` : compare le code tapé. S'il est bon, crée le compte et efface l'étape.
- `Renvoyer le code` : tire un nouveau code, l'ancien ne marche plus.

## Les protections

- **Code vraiment aléatoire** : il vient de `gen_random_bytes` (PostgreSQL), pas de `random()`
  qu'on peut prévoir.
- **Code jamais en clair** : seulement son hash dans `auth_pending`. Il n'est ni dans le chat, ni
  dans `audit_log`, ni envoyé à l'IA. Le workflow n'enregistre pas ses exécutions : n8n les
  efface au plus tard une minute après (voir [workflows.md](workflows.md#a-chat---entrée)).
- **10 minutes et 5 essais** : après, il faut recommencer. Deviner un code sur un million en
  5 essais n'a quasiment aucune chance de marcher.
- **3 codes au maximum** par inscription, pour qu'on ne puisse pas remplir la boîte mail de
  quelqu'un avec des codes.
- **Email déjà inscrit** : le chat répond exactement pareil (« code envoyé »), on ne peut donc
  pas savoir qui a un compte. La vraie personne reçoit un email qui la prévient, sans code, et
  aucun code tapé ne marchera.
- **Journal** : `register_otp_sent`, `register_otp_failed` (avec le numéro de l'essai),
  `register_ok` et `register_duplicate` dans `audit_log`.

## Base de données

Dans `db/schema/02-schema.sql`, la table `auth_pending` a 4 colonnes de plus : `password_hash`,
`otp_hash`, `otp_attempts`, `otp_sent_count`, et une étape de plus, `register_otp`. Une base déjà
créée les reçoit au prochain `bash scripts/setup.sh`. Le nettoyage de nuit efface ces lignes
au bout d'une heure, comme avant.

## Emails en local : Mailpit

`docker-compose.yml` lance Mailpit, une fausse boîte mail. Tous les emails envoyés à Mailpit
s'affichent sur http://localhost:8025, rien ne part vraiment.

Le nœud `Envoyer le code` utilise le credential `SMTP Persona`, le même que la newsletter de B.
Pour tester, le régler sur Mailpit (host `mailpit`, port 1025, sans SSL ni mot de passe) ; pour
envoyer de vrais emails, sur Gmail. Les deux réglages sont à l'étape 2 du README.

## Tests

```bash
docker compose exec -T n8n node - < scripts/test_scenarios.js
```

2 tests pour le code, dans la section `[A] Chat - Entrée : code d'inscription` : avec le bon code,
le compte est créé, et un code n'accepte que 5 essais. Un troisième, dans la section
`[A] Chat - Entrée : messages envoyés à l'IA`, vérifie que rien ne part vers l'IA pendant
l'inscription, code compris. Détail dans [tests-scenarios.md](tests-scenarios.md).

Les autres protections (code tiré avec `gen_random_bytes`, haché, 3 envois au maximum, rien pour un
email déjà inscrit…) ne sont plus testées automatiquement. Elles sont toujours dans le workflow, et
ont été vérifiées en vrai (ci-dessous).

Le parcours complet a aussi été joué dans le vrai n8n, avec la vraie base et Mailpit : inscription
normale, mauvais code, 5 mauvais codes, renvoi de code (l'ancien ne marche plus, 4e demande
refusée), email déjà inscrit, inscription en une ligne, code tapé sans inscription en cours.

## Ce qui n'est pas couvert

- Le changement d'email depuis l'agent (`modifier_email`) ne demande toujours pas de code.
- Quelqu'un avec beaucoup de vraies adresses peut toujours créer beaucoup de comptes.
