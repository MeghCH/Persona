# Périmètre

[Retour au sommaire](README.md)

## Ce que cet audit couvre

- **Quoi** : la partie A du projet, le chatbot et sa sécurité. On a aussi attaqué les workflows de
  B (phase 2).
- **Qui** : l'équipe A, sur son propre travail, puis sur celui de B.
- **Quand** : attaques du 29/10, essais en direct début novembre, tout rejoué le 15/11/2026.
- **Quelle version** : la branche `main`, avec les prompts par étape.
- **Quelle méthode** : boîte blanche. On a le code, les workflows et la base sous les yeux.

## Dans le périmètre

- les workflows `[A] Chat - Entrée`, `[A] Chat - Agent` et `[A] Chat - Intention`
- la base de données : le schéma (`db/schema/02-schema.sql`), les droits de `persona_app`, les
  fonctions `reserver_appel_ia` et `persona_cleanup`
- la page du chatbot (`web/index.html`)
- la configuration : `docker-compose.yml`, `.env.example`, `scripts/setup.sh`, `scripts/sanitize.py`
  et la CI
- les workflows de B, mais seulement ce qui y entre : les flux RSS, les valeurs en base (email,
  fuseau), les réponses de l'IA de la collecte, le lien de désinscription et les emails envoyés

## Hors périmètre

- Gemini et Google, et le serveur mail Gmail : des services externes
- n8n, PostgreSQL, Docker et WSL : on n'a pas cherché de failles dans ces logiciels, on les utilise
  tels quels
- le réseau, la machine, l'accès physique et l'ingénierie sociale
- les attaques réseau et les tests de charge réels : on a seulement testé la limite des messages
- les autres projets (sentinelx)

## Les règles qu'on s'est données

- Tout se passe sur une installation locale, jamais sur un système qui ne nous appartient pas.
- Pour les attaques du 29/10, Gemini était remplacé par un faux serveur qui répond ce qu'on veut,
  y compris des réponses malveillantes. Aujourd'hui, les attaques qui demandent une IA manipulée se
  rejouent avec les tests automatiques, qui simulent ses réponses.
- Un faux serveur mail (Mailpit) récupère les emails.
- On n'utilise que des données de test : des comptes `audit.xxx@example.com`, supprimés à la fin.
- Pas d'outil de scan automatique : les attaques sont écrites à la main, puis rejouées avec les
  étapes de chaque fiche et avec les tests automatiques.

## Comment lire cet audit

Chaque faille a **sa propre fiche** dans le dossier [failles/](failles/). Trois sortes d'identifiants :

- `F-01`, `F-02`… : une **faille trouvée**, qui a réussi avant d'être corrigée
- `T-01`, `T-02`… : une **attaque testée**, bloquée aujourd'hui
- `R-01`, `R-02`… : un **risque qui reste**, dans [risques-restants.md](risques-restants.md)

Chaque fiche dit : ce qu'on teste, comment le reproduire, le résultat attendu, le résultat du test
et les codes MITRE (expliqués dans [mitre.md](mitre.md)).

L'**échelle de gravité** est simple :

- **Haute** : un attaquant atteint les utilisateurs (phishing, vol ou lecture d'un compte, fuite
  de données)
- **Moyenne** : on coupe ou on détourne le service, sans atteindre les comptes
- **Faible** : gêne limitée, ou difficile à exploiter

C'est une échelle à nous, pas un score CVSS.

Les **statuts** : une faille est *Corrigée* ou *Ouverte*. Une attaque est *Bloquée* quand le
système l'a refusée.
