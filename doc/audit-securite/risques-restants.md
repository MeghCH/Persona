# Ce qui reste à améliorer

[Retour au sommaire](README.md)

**11 risques restent.** Ils ne sont pas des attaques rejouées : ce sont des faiblesses connues qu'on n'a pas
encore traitées. Ils sont classés du plus important au moins important. Chacun a une gravité, une
solution et ses codes MITRE ([mitre.md](mitre.md)).

## À traiter avant une mise en ligne

### R-01 Postgres et n8n sont ouverts sur toutes les interfaces réseau

- **Gravité** : Haute
- **Ce qui se passe** : Dans `docker-compose.yml`, on a `5432:5432` et `5678:5678`. Sur un réseau partagé, n'importe qui peut essayer de se connecter à la base.
- **Solution** : `127.0.0.1:5432:5432` (ou ne pas ouvrir Postgres du tout) et `127.0.0.1:5678:5678`.
- **Codes MITRE** : `T1190`, `T1110`

### R-02 Tout passe en HTTP

- **Gravité** : Haute
- **Ce qui se passe** : Les mots de passe passent par le chat : sur un réseau, quelqu'un peut les lire.
- **Solution** : Du HTTPS dès que le projet est en ligne.
- **Codes MITRE** : `T1040`, `CWE-319`

### R-03 Pas de limite d'envois de codes par adresse email

- **Gravité** : Moyenne
- **Ce qui se passe** : On limite à 3 codes par inscription, mais avec une nouvelle session on recommence : quelqu'un peut envoyer beaucoup d'emails à la même personne. La limite des messages ne s'applique pas, parce que ces messages ne passent pas par l'IA.
- **Solution** : Compter les codes envoyés par adresse et par heure.
- **Codes MITRE** : `T1499`

## Importants

### R-04 On peut changer d'email sans confirmer la nouvelle adresse

- **Gravité** : Moyenne
- **Ce qui se passe** : L'outil `modifier_email` de l'agent change l'adresse tout de suite.
- **Solution** : Envoyer un code à la nouvelle adresse, comme à l'inscription.
- **Codes MITRE** : `T1098`

### R-05 Pas de limite par adresse IP ni sur le nombre d'inscriptions

- **Gravité** : Moyenne
- **Ce qui se passe** : Le workflow ne reçoit pas l'adresse de l'appelant. Quelqu'un avec beaucoup de vraies adresses peut créer beaucoup de comptes.
- **Solution** : Mettre `limit_req` dans nginx devant la page.
- **Codes MITRE** : `T1499`, `CWE-770`

### R-06 Le quota gratuit de Gemini est trop petit

- **Gravité** : Moyenne
- **Ce qui se passe** : 20 requêtes par jour : la collecte de B le dépasse à elle seule, et ses appels ne passent pas par notre limite. Quand il est épuisé, le chatbot n'a plus que ses phrases fixes.
- **Solution** : Un forfait payant, ou un autre modèle pour la collecte.
- **Codes MITRE** : `AML.T0029`

## Petits risques

### R-07 La désinscription se fait avec un simple clic

- **Gravité** : Faible
- **Ce qui se passe** : Certains antivirus ouvrent les liens des emails tout seuls et peuvent désinscrire quelqu'un sans qu'il le sache.
- **Solution** : Un bouton de confirmation.
- **Codes MITRE** : aucun code précis

### R-08 Un problème d'envoi d'email arrête l'envoi des autres

- **Gravité** : Faible
- **Ce qui se passe** : Le nœud d'envoi n'est pas en `On Error : Continue`. Une adresse mal vue par le serveur mail peut bloquer la suite de la liste.
- **Solution** : Mettre `On Error : Continue` sur l'envoi.
- **Codes MITRE** : aucun code précis

### R-09 Le filtre anti-injection marche avec des mots-clés

- **Gravité** : Faible
- **Ce qui se passe** : Une reformulation peut passer. Ce n'est pas grave : même sans filtre, l'IA ne peut toucher qu'au compte connecté.
- **Solution** : Garder le filtre comme une couche de plus, sans compter dessus.
- **Codes MITRE** : `AML.T0051.000`

### R-10 Le chat est public

- **Gravité** : Faible
- **Ce qui se passe** : N'importe qui peut écrire au chatbot sans compte, c'est voulu pour l'inscription. Seules les origines `localhost` sont autorisées (`allowedOrigins`).
- **Solution** : Changer les origines autorisées pour la mise en ligne.
- **Codes MITRE** : aucun code précis

### R-11 Les préférences sont recopiées dans le prompt de l'agent

- **Gravité** : Faible
- **Ce qui se passe** : Aujourd'hui, toutes les valeurs sont limitées par la base ou par les outils (sujets, sources, ton, format, fuseau, heures) : une valeur libre ne peut pas y arriver.
- **Solution** : Si on ajoute un champ libre un jour, ne pas le copier dans le prompt sans le contrôler.
- **Codes MITRE** : `AML.T0051`

## Conclusion

Le chatbot est bien protégé contre les attaques qu'on a essayées : l'IA n'a pas la main sur les
comptes, les mots de passe et les codes ne lui arrivent jamais, et les données de chaque
utilisateur sont séparées. Les ajouts récents (limite des messages, code par email, prompts par
étape) ont chacun été testés, et la seule faille trouvée parmi eux (F-05) est corrigée.

Avant de mettre Persona en ligne, il faut au minimum traiter R-01, R-02 et R-03 : fermer les ports
de Postgres et de n8n, passer en HTTPS et limiter les envois de codes par adresse.
