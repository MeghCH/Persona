# Audit de sécurité - Persona

Partie A (chatbot et sécurité). Version du 15/11/2026, sur la branche `main`.

Cet audit dit ce qu'on a audité, ce qu'on a essayé de casser, ce qu'on a trouvé, ce qu'on a
corrigé et ce qui reste à faire. **Chaque faille a sa fiche** dans [failles/](failles/) : ce qu'on
teste, comment le refaire, le résultat et le code MITRE.

## En bref

- **Périmètre** : le chatbot (3 workflows, la base, la page web) et les workflows de B
  ([scope.md](scope.md)).
- **5 failles trouvées, 5 corrigées** : 2 de gravité haute, 3 de gravité moyenne.
- **25 attaques testées**, toutes bloquées aujourd'hui.
- **Tout est rejouable** : chaque fiche donne les étapes. 24 attaques ont été rejouées en
  direct le 15/11/2026 (24 OK), et les 105 tests automatiques passent.
- **11 risques restent**, dont 3 à traiter avant une mise en ligne : Postgres et n8n ouverts sur
  tout le réseau (R-01), pas de HTTPS (R-02) et pas de limite d'envois de codes par adresse (R-03).
- **Les codes MITRE** (ATT&CK, ATLAS, CWE) sont donnés dans chaque fiche, et expliqués dans
  [mitre.md](mitre.md).

## Failles trouvées

Elles ont réussi avant d'être corrigées.

- [F-01 Un fuseau horaire invalide bloque l'envoi pour tout le monde](failles/F-01-fuseau-horaire-invalide.md) : gravité moyenne, corrigée
- [F-02 Le HTML des articles passe tel quel dans l'email](failles/F-02-html-dans-email.md) : gravité haute, corrigée
- [F-03 L'IA de la collecte peut écrire un lien de phishing dans un résumé](failles/F-03-phishing-par-ia-de-collecte.md) : gravité haute, corrigée
- [F-04 Une adresse email piégée détourne la newsletter](failles/F-04-email-piege-bcc.md) : gravité moyenne, corrigée
- [F-05 Des messages envoyés en même temps dépassent la limite](failles/F-05-limite-messages-simultanes.md) : gravité moyenne, corrigée

## Attaques testées

Toutes sont bloquées.

### Authentification et comptes

- [T-01 Deviner le mot de passe](failles/T-01-mot-de-passe-devine.md)
- [T-02 Deviner le code reçu par email](failles/T-02-code-email-devine.md)
- [T-03 Demander des codes en boucle](failles/T-03-codes-envoyes-en-boucle.md)
- [T-04 Réutiliser une session](failles/T-04-reutilisation-de-session.md)
- [T-05 Savoir qui est inscrit](failles/T-05-enumeration-de-comptes.md)
- [T-06 Créer un compte avec l'email de quelqu'un d'autre](failles/T-06-compte-avec-email-dautrui.md)

### Données et droits

- [T-07 Injection SQL](failles/T-07-injection-sql.md)
- [T-08 Lire ou modifier les données d'un autre utilisateur par l'IA](failles/T-08-donnees-dun-autre-utilisateur.md)
- [T-09 Prendre l'email d'un autre compte](failles/T-09-email-dun-autre-compte.md)
- [T-10 Retrouver la mémoire de l'IA d'un autre compte](failles/T-10-memoire-de-lia-dun-autre-compte.md)
- [T-11 Se donner le rôle admin par l'IA](failles/T-11-role-admin-par-lia.md)
- [T-12 Valeurs absurdes](failles/T-12-valeurs-absurdes.md)
- [T-13 Retrouver un mot de passe dans le journal ou les exécutions](failles/T-13-mot-de-passe-dans-les-journaux.md)
- [T-14 Entrées invalides](failles/T-14-entrees-invalides.md)

### L'IA

- [T-15 Injection de prompt directe](failles/T-15-injection-de-prompt.md)
- [T-16 Jailbreak](failles/T-16-jailbreak.md)
- [T-17 Une IA qui recrache des données internes](failles/T-17-ia-qui-recrache-des-donnees.md)
- [T-18 Faire supprimer un compte par une phrase](failles/T-18-suppression-de-compte-par-phrase.md)
- [T-19 Un lien de phishing dans la réponse de l'IA](failles/T-19-lien-de-phishing-dans-reponse-ia.md)
- [T-20 Envoyer trop de messages pour épuiser le quota](failles/T-20-epuisement-du-quota.md)
- [T-21 Détourner les prompts par étape](failles/T-21-prompts-par-etape.md)

### Workflows de B

- [T-22 Attaquer le lien de désinscription](failles/T-22-lien-de-desinscription.md)
- [T-23 Thèmes hors liste renvoyés par l'IA de collecte](failles/T-23-themes-hors-liste.md)
- [T-24 Résumés trop longs](failles/T-24-resumes-trop-longs.md)
- [T-25 Une IA qui modifie un article hors de son lot](failles/T-25-article-hors-du-lot.md)

## Les autres fichiers

- [scope.md](scope.md) : ce qui est dans le périmètre, ce qui n'y est pas, l'échelle de gravité
- [methode.md](methode.md) : comment on a testé, et les outils pour tout rejouer
- [protections-chatbot.md](protections-chatbot.md) : le trajet d'un message et les protections
- [protections-IA.md](protections-IA.md) : ce que l'IA a le droit de faire, et les prompts par étape
- [mitre.md](mitre.md) : ce que sont les codes MITRE, et l'index des codes utilisés
- [risques-restants.md](risques-restants.md) : les risques qui restent, et la conclusion
- [rgpd-et-journal.md](rgpd-et-journal.md) : les droits des utilisateurs et le journal de sécurité

## Documents liés

- [protection-deni-de-service.md](../protection-deni-de-service.md) : le détail de la limite des
  messages
- [code-inscription.md](../code-inscription.md) : le détail du code par email
- [prompts.md](../prompts.md) : les prompts par étape et leurs versions
- [normes-RGPD.md](../normes-RGPD.md) : la politique de confidentialité
- [tests-evaluation.md](../tests-evaluation.md) : les tests de la collecte et de l'envoi
