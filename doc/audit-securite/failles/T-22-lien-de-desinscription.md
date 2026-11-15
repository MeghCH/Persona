# T-22 Attaquer le lien de désinscription

[Retour au sommaire](../README.md)

- **Type** : Attaque testée
- **Statut** : Bloquée
- **Catégorie** : Workflows de B
- **Codes MITRE** : `T1190`, `CWE-89`
- **Premier essai** : attaque jouée sur l'instance de test (29/10)
- **Rejoué le 15/11/2026** : OK, en direct

## Ce qu'on teste

Injection SQL et jeton inconnu ou mal formé.

## Comment le reproduire

Avant de commencer, lancer Persona et préparer les outils de [methode.md](../methode.md) : `chat`, `nouvelle_session` et `psql_persona`.

1. Ouvrir le lien de désinscription avec trois jetons invalides :
   ```bash
   for t in abc 00000000-0000-0000-0000-000000000000 "x'%20OR%20'1'='1"; do curl -s "http://localhost:5678/webhook/unsubscribe?token=$t"; echo; done
   ```

## Résultat attendu

Les trois réponses sont la même page « Lien invalide ». Personne n'est désinscrit.

## Résultat du test (15/11/2026)

Rejoué en direct sur Persona : **OK**.

```
3 jetons sur 3 donnent la page « Lien invalide »
```

## Pourquoi ça bloque

Le workflow vérifie d'abord que le jeton est un UUID bien formé, puis le cherche avec un paramètre SQL. Jeton mal formé ou inconnu : même page, pour ne pas révéler si un jeton existe.

## Codes MITRE

- [`T1190`](https://attack.mitre.org/techniques/T1190/) Exploit Public-Facing Application
- [`CWE-89`](https://cwe.mitre.org/data/definitions/89.html) Improper Neutralization of Special Elements used in an SQL Command

Les codes sont expliqués dans [mitre.md](../mitre.md).
