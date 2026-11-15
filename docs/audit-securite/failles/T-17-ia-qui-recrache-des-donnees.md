# T-17 Une IA qui recrache des données internes

[Retour au sommaire](../README.md)

- **Type** : Attaque testée
- **Statut** : Bloquée
- **Catégorie** : L'IA
- **Codes MITRE** : `CWE-200`
- **Premier essai** : attaque jouée sur l'instance de test (29/10)
- **Rejoué le 15/11/2026** : OK, en direct

## Ce qu'on teste

Réponse de l'IA avec un hash de mot de passe ou un identifiant interne.

## Comment le reproduire

Avant de commencer, lancer Persona et préparer les outils de [methode.md](../methode.md) : `chat`, `nouvelle_session` et `psql_persona`.

1. Lancer le vrai nœud `Formater la réponse` avec une réponse d'IA qui contient un hash de mot de passe et un identifiant interne :
   ```bash
   docker-compose exec -T n8n node -e '
   const wf = JSON.parse(require("fs").readFileSync("/home/node/exports/a_chat_entree.json", "utf8"));
   const code = wf.nodes.find(n => n.name === "Formater la réponse").parameters.jsCode;
   const hash = "$2a$12$abcdefghijklmnopqrstuvABCDEFGHIJKLMNOPQRSTUVWXYZ01234";
   const entree = { first: () => ({ json: { output: "Voici : " + hash + " et 3f2b8c1e-1d2a-4b3c-9d4e-5f6a7b8c9d0e" } }) };
   console.log(new Function("$input", code)(entree)[0].json.output);
   '
   ```

## Résultat attendu

La réponse affichée est « Voici : [masqué] et [masqué] ».

## Résultat du test (15/11/2026)

Rejoué en direct sur Persona : **OK**.

```
réponse affichée : « Voici : [masqué] et [masqué] »
```

## Pourquoi ça bloque

Avant d'être affichée, toute réponse passe par `Formater la réponse`, qui remplace les hashes bcrypt et les identifiants (UUID) par `[masqué]`.

## Codes MITRE

- [`CWE-200`](https://cwe.mitre.org/data/definitions/200.html) Exposure of Sensitive Information to an Unauthorized Actor

Les codes sont expliqués dans [mitre.md](../mitre.md).
