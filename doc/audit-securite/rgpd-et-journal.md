# RGPD et journal

[Retour au sommaire](README.md)

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
On peut donc voir si un compte précis est attaqué.

Pour un email qui n'existe pas (`login_failed_unknown`), on n'enregistre rien qui permette de le
retrouver : il n'y a pas de compte à relier, et on évite de garder l'adresse d'un inconnu. C'est le
compromis choisi entre détecter les attaques et garder le moins de données possible.

Les événements du code d'inscription sont aussi notés : `register_otp_sent`, `register_otp_failed`
(avec le numéro de l'essai) et `register_ok`.
