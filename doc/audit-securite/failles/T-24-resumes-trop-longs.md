# T-24 Résumés trop longs

[Retour au sommaire](../README.md)

- **Type** : Attaque testée
- **Statut** : Bloquée
- **Catégorie** : Workflows de B
- **Codes MITRE** : `CWE-20`
- **Premier essai** : attaque jouée sur l'instance de test (29/10)
- **Rejoué le 15/11/2026** : OK, en direct et par les tests automatiques

## Ce qu'on teste

L'IA écrit un résumé de plusieurs paragraphes.

## Comment le reproduire

Avant de commencer, lancer Persona et préparer les outils de [methode.md](../methode.md) : `chat`, `nouvelle_session` et `psql_persona`.

1. Créer deux articles de test (A est le premier identifiant affiché, B le deuxième) :
   ```bash
   echo "INSERT INTO articles (url, title, source) VALUES ('https://audit.example/a', 'A', 'test'), ('https://audit.example/b', 'B', 'test') RETURNING id;" | psql_persona
   ```
2. Lancer la vraie requête du nœud `Enregistrer thèmes et résumés` (`[B] News - Collecte`) avec un lot piégé : pour l'article A, un thème inventé (`piratage`) et un résumé de 800 caractères ; pour l'article B, un résumé alors qu'il ne fait pas partie du lot en cours. Remplacer `ID_A` et `ID_B` par les deux identifiants :
   ```sql
   WITH journal AS (
     INSERT INTO audit_log (event, details)
     SELECT 'summary_review', jsonb_build_object('rejets', '[]'::jsonb, 'ia_disponible', true)
     WHERE jsonb_array_length('[]'::jsonb) > 0 OR NOT true
   )
   UPDATE articles a
   SET tags = COALESCE(
         NULLIF(ARRAY(
           SELECT t FROM json_array_elements_text(x.tags) AS t
           WHERE t = ANY (ARRAY['politique','international','économie','société','sport','culture',
                                'technologie','science','espace','santé','environnement',
                                'jeux-vidéo','faits-divers','autre'])
         ), '{}'),
         ARRAY['autre']),
       summary = left(x.summary, 500)
   FROM json_to_recordset(json_build_array(json_build_object('id', ID_A, 'tags', json_build_array('politique', 'piratage', 'sport'), 'summary', repeat('x', 800)), json_build_object('id', ID_B, 'tags', json_build_array('sport'), 'summary', 'résumé qui ne doit pas être écrit'))::json) AS x(id bigint, tags json, summary text)
   WHERE a.id = x.id
     AND a.id IN (SELECT json_array_elements_text(json_build_array(ID_A)::json)::bigint)
   RETURNING a.id, a.tags;
   ```
3. Regarder les deux articles :
   ```bash
   echo "SELECT id, tags, length(summary) AS taille_resume, summary IS NULL AS vide FROM articles WHERE url LIKE 'https://audit.example/%' ORDER BY id;" | psql_persona
   ```
4. Supprimer les articles de test :
   ```bash
   echo "DELETE FROM articles WHERE url LIKE 'https://audit.example/%';" | psql_persona
   ```

**Tests automatiques** (chaque ligne doit commencer par OK) :

```bash
docker-compose exec -T n8n node - < scripts/test_scenarios.js | grep -F -e "un résumé trop long est rejeté"
```

## Résultat attendu

Pour l'article A, `taille_resume` vaut 500 : le résumé de 800 caractères est coupé. Le contrôle automatique rejette en plus un résumé de plus de 3 phrases ou de plus de 500 caractères.

## Résultat du test (15/11/2026)

Rejoué en direct sur Persona : **OK**.

```
T-23 thème inventé retiré : True | T-24 résumé coupé à 500 : True | T-25 article hors du lot modifié : False | article A : {politique,sport} | résumé de 500 caractères | article B : vide | {}
```

Ces tests passent (les 105 tests du script passent) :

- un résumé trop long est rejeté

## Pourquoi ça bloque

La requête coupe le résumé (`left(x.summary, 500)`), et `Contrôler les résumés` rejette ceux qui dépassent.

## Codes MITRE

- [`CWE-20`](https://cwe.mitre.org/data/definitions/20.html) Improper Input Validation

Les codes sont expliqués dans [mitre.md](../mitre.md).
