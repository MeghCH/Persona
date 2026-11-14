# Persona - Documentation RGPD

Mise à jour : 14 novembre 2026

Persona ne collecte que l'email, les centres d'intérêt et l'heure d'envoi de ses utilisateurs, les supprime automatiquement une fois leur durée de conservation dépassée, et trace chaque action sensible dans un journal.

## Politique de confidentialité

Ce texte est affiché par le chatbot quand l'utilisateur tape « en savoir plus » avant d'accepter, ou demande ce que Persona fait de ses données. Version v2 (suppression du compte 6 mois après la désinscription), à faire passer en v3 dans `consent_version` à chaque modification.

**Qui est responsable de vos données ?** L'équipe Persona. Contact : personaepitech26@gmail.com.

**Quelles données collectons-nous ?**

- votre adresse email, pour vous envoyer la newsletter et vous identifier ;
- votre mot de passe, conservé uniquement sous forme chiffrée (haché) ;
- vos centres d'intérêt, votre heure et vos jours d'envoi, votre fuseau horaire et vos réglages de newsletter ;
- l'historique des newsletters envoyées et les retours que vous nous laissez ;
- un journal des actions sensibles (connexions, désinscriptions, suppressions), pour la sécurité du service.

Nous ne collectons ni votre nom, ni votre adresse, ni votre âge.

**Pourquoi ?** Uniquement pour vous envoyer une newsletter personnalisée et protéger votre compte. Vos données ne sont ni vendues, ni utilisées pour de la publicité.

**Combien de temps ?** Votre compte et vos préférences sont conservés jusqu'à sa suppression, ou 6 mois après votre désinscription. L'historique des envois est supprimé après 6 mois, le journal et vos retours après 1 an. Un nettoyage automatique s'exécute chaque nuit.

**Qui y a accès ?** L'équipe Persona, et deux prestataires techniques : Google Gemini, qui classe et résume les articles et répond dans le chat, et Gmail, qui envoie les emails.

**Vos droits.** À tout moment, depuis le chat, vous pouvez consulter et exporter vos données, modifier vos préférences, vous désinscrire ou supprimer votre compte. La suppression efface toutes vos données liées. Chaque newsletter contient aussi un lien de désinscription en un clic. Vous pouvez enfin adresser une réclamation à la CNIL.

## Registre des traitements

Chaque donnée personnelle a une finalité, une base légale et une durée ; les suppressions sont automatiques (`persona_cleanup()`, chaque nuit à 3 h) ou en cascade à la suppression du compte.

| Traitement | Données | Finalité | Base légale | Durée de conservation | Où |
| --- | --- | --- | --- | --- | --- |
| Compte | email, mot de passe haché (bcrypt), date et version du consentement, jeton de désinscription | identifier l'utilisateur, prouver son consentement | consentement | jusqu'à la suppression du compte, ou 6 mois après la désinscription | `users` |
| Préférences | thèmes, heure et jours d'envoi, fuseau, ton, format, sources exclues, statut d'abonnement | personnaliser la newsletter | consentement | jusqu'à la suppression du compte, ou 6 mois après la désinscription | `preferences` |
| Sessions du chat | identifiant de session, utilisateur, expiration | maintenir la connexion | sécurité du service | quelques heures, puis suppression nocturne | `sessions` |
| Inscription en cours | identifiant de session, étape, email ; à l'inscription, mot de passe haché, code haché, nombre d'essais et d'envois du code | guider l'inscription ou la connexion | consentement en cours de recueil | 1 heure | `auth_pending` |
| Historique des envois | utilisateur, articles envoyés, date | éviter les doublons, répondre aux demandes | intérêt légitime | 6 mois | `sent_newsletters` |
| Retours | utilisateur, message | améliorer les newsletters | consentement | 1 an | `feedback` |
| Journal de sécurité | type d'événement, identifiant utilisateur, détails, date | sécurité, preuve des désinscriptions et des nettoyages | intérêt légitime (sécurité) | 1 an | `audit_log` |
| Comptage des messages vers l'IA | identifiant de session, identifiant utilisateur (vidé si le compte est supprimé), connecté ou non, date ; jamais le texte du message | limiter les abus qui épuiseraient le quota de l'IA | intérêt légitime (sécurité) | 2 jours | `chat_ai_requests` |
| Historique d'exécution n8n | messages envoyés à l'agent (`[A] Chat - Agent`), emails et newsletters envoyés (`[B] News - Envoi`) ; rien pour `[A] Chat - Entrée` et `[A] Chat - Intention`, qui reçoivent les messages tapés dans le chat | débogage | intérêt légitime | 14 jours (réglage par défaut de n8n) ; Entrée et Intention : effacées au plus tard une minute après | base interne de n8n |

Le journal ne stocke pas l'email mais l'identifiant de l'utilisateur : après la suppression d'un compte, ses lignes restent comme preuve mais ne permettent plus de l'identifier.

Historique d'exécution de n8n : `[A] Chat - Entrée`, qui reçoit les mots de passe, et `[A] Chat - Intention` n'enregistrent pas leurs exécutions. n8n les garde quand même, invisibles, jusqu'à son nettoyage suivant, réglé sur toutes les minutes (`EXECUTIONS_DATA_PRUNE_HARD_DELETE_INTERVAL` dans `docker-compose.yml`). Les autres workflows gardent leurs exécutions 14 jours (`EXECUTIONS_DATA_MAX_AGE`, 336 h par défaut) : à réduire si on veut garder moins longtemps les messages envoyés à l'agent et les emails des destinataires.

## Sous-traitants

Deux prestataires reçoivent des données ; n8n et PostgreSQL sont auto-hébergés et ne transmettent rien à un tiers.

| Sous-traitant | Service | Données transmises | Offre actuelle | En production |
| --- | --- | --- | --- | --- |
| Google (Gemini) | classement et résumé des articles ; agent du chat | contenu des articles (pas de donnée personnelle) ; messages des utilisateurs dans le chat | gratuite : les données envoyées peuvent servir à améliorer les produits de Google | offre payante sans réutilisation des données, ou fournisseur européen (Mistral) |
| Google (Gmail, SMTP) | envoi des newsletters | adresse email, contenu de la newsletter | compte Gmail dédié au projet | service d'envoi professionnel avec un domaine propre (SPF, DKIM) |

Google est une entreprise américaine : ces deux services impliquent un transfert de données hors de l'Union européenne, à encadrer par un contrat de sous-traitance avant toute mise en production.

Le chatbot ne doit jamais transmettre à l'agent IA un message saisi pendant une étape d'authentification, pour qu'aucun mot de passe ne parte chez Google.