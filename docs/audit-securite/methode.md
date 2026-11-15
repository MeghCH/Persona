# Comment on a testé, et comment le refaire

[Retour au sommaire](README.md)

## Les trois sortes de tests

**1. Attaques sur une deuxième installation (29/10).** On a monté une copie de Persona, à part, pour
ne pas toucher aux vraies données. On y a remplacé Gemini par un faux serveur qui répond ce qu'on
veut, y compris des réponses malveillantes : c'est comme si quelqu'un avait réussi à manipuler
l'IA. On voit donc ce que le système laisse passer même dans le pire cas. Un faux serveur mail
récupérait aussi les newsletters envoyées par B.

**2. Les tests automatiques.** Le fichier `scripts/test_scenarios.js` lance le vrai code des nœuds
des workflows. 105 tests, tous passent (relancés le 15/11/2026). Ils couvrent la collecte, l'envoi,
les limites de messages, la lecture des réponses de l'IA, le chemin vers l'agent, le code
d'inscription et les prompts par étape. La CI de GitHub les relance à chaque pull request.

**3. Les étapes à la main de chaque fiche.** Chaque fiche donne les commandes pour refaire
l'attaque contre Persona : on envoie de vrais messages au chatbot, et on regarde la base. Le
15/11/2026, 24 attaques ont été rejouées en direct : toutes OK. Les commandes écrites dans les
fiches ont été lancées telles quelles pour vérifier qu'elles marchent.

## Rejouer une attaque

Il faut Persona lancé (`bash scripts/setup.sh`), et être dans le dossier du projet. Puis suivre les
étapes de la fiche.

**Lancer les tests automatiques** (avec Docker Compose v2, écrire `docker compose` au lieu de
`docker-compose`) :

```bash
docker-compose exec -T n8n node - < scripts/test_scenarios.js
```

## Les outils des fiches

Les fiches donnent les étapes à la main. Elles utilisent trois petits outils à coller dans le
terminal :

```bash
URL=http://localhost:5678/webhook/9d5a3c0e-6c1e-4b6e-9a53-2f0c7a8f4a11/chat

# envoie un message au chatbot : chat "<session>" "<message>"
chat() { curl -s -X POST "$URL" -H "Content-Type: application/json" -H "Origin: http://localhost:8090" \
  -d "{\"action\":\"sendMessage\",\"sessionId\":\"$1\",\"chatInput\":\"$2\"}"; echo; }

# une session de 40 caractères
nouvelle_session() { head -c 60 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 40; }

# du SQL dans la base : echo "SELECT 1;" | psql_persona
psql_persona() { docker-compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d persona -At'; }
```

## Un compte de test

Plusieurs fiches ont besoin d'un compte dont on connaît le mot de passe. On le crée directement
dans la base (aucun email n'est envoyé) :

```bash
echo "WITH u AS (INSERT INTO users (email, password_hash, consent_given_at, consent_version)
  VALUES ('audit.test@example.com', crypt('Zx-Test-12345-Qw9!', gen_salt('bf', 12)), now(), 'v2') RETURNING id)
INSERT INTO preferences (user_id) SELECT id FROM u;" | psql_persona
```

On se connecte ensuite avec `chat "$S" "connexion audit.test@example.com Zx-Test-12345-Qw9!"`, où `S`
vaut `$(nouvelle_session)`.

Pour le supprimer à la fin :

```bash
echo "DELETE FROM users WHERE email LIKE 'audit.%@example.com';" | psql_persona
```

## Ce qui ne se rejoue pas en direct

Les attaques qui demandent une IA manipulée ou l'envoi d'un vrai email ne se rejouent pas en
direct : T-02, T-03, T-19 et T-21, et les failles F-02 et F-03. Elles sont couvertes par les tests
automatiques, qui simulent les réponses de l'IA, et chaque fiche donne la commande pour les lancer.
