# Codes MITRE

[Retour au sommaire](README.md)

## C'est quoi MITRE ?

MITRE est une organisation qui tient des catalogues publics sur la sécurité. Chaque attaque ou
faiblesse y a un code, pour que tout le monde parle de la même chose. On en utilise trois :

- **ATT&CK** : le catalogue des techniques utilisées par les attaquants. Le code commence par `T`
  et un nombre, par exemple `T1110` pour « Brute Force » (deviner un mot de passe en essayant
  beaucoup de possibilités). Un point et trois chiffres donnent une précision :
  `T1110.001` veut dire « deviner un mot de passe », un cas particulier de `T1110`.
- **ATLAS** : la même chose, mais pour les systèmes d'IA. Le code commence par `AML.T`, par
  exemple `AML.T0051` pour « LLM Prompt Injection » (faire obéir l'IA à un texte piégé).
- **CWE** : le catalogue des faiblesses dans un programme, comme une injection SQL. Le code est
  `CWE-` suivi d'un nombre, par exemple `CWE-89`.

Ça sert à classer ce qu'on a testé avec les mêmes mots que les outils de sécurité. Par exemple, les
règles Wazuh de l'autre projet (sentinelx) affichent `T1110` et `T1110.001` dans leurs alertes.

Les catalogues sont sur [attack.mitre.org](https://attack.mitre.org),
[atlas.mitre.org](https://atlas.mitre.org) et [cwe.mitre.org](https://cwe.mitre.org). Chaque code
ci-dessous renvoie vers sa page, et les noms ont été vérifiés le 15/11/2026.

## Comment on les a choisis

Pour chaque faille, attaque ou risque, on a cherché la technique ou la faiblesse la plus proche.
Certains codes sont une approximation : MITRE n'a pas de code précis pour « remplir la boîte mail de
quelqu'un », on a pris `T1499`. Quand rien ne convenait, on n'a pas mis de code.

## Index des codes

Pour chaque code : les fiches (`F-` et `T-`) et les risques (`R-`) qui l'utilisent.

### ATT&CK, les techniques d'attaque

- [`T1040`](https://attack.mitre.org/techniques/T1040/) Network Sniffing : [R-02](risques-restants.md)
- [`T1087`](https://attack.mitre.org/techniques/T1087/) Account Discovery : [T-05](failles/T-05-enumeration-de-comptes.md)
- [`T1098`](https://attack.mitre.org/techniques/T1098/) Account Manipulation : [T-09](failles/T-09-email-dun-autre-compte.md), [T-11](failles/T-11-role-admin-par-lia.md), [R-04](risques-restants.md)
- [`T1110`](https://attack.mitre.org/techniques/T1110/) Brute Force : [T-02](failles/T-02-code-email-devine.md), [R-01](risques-restants.md)
- [`T1110.001`](https://attack.mitre.org/techniques/T1110/001/) Brute Force: Password Guessing : [T-01](failles/T-01-mot-de-passe-devine.md)
- [`T1136`](https://attack.mitre.org/techniques/T1136/) Create Account : [T-06](failles/T-06-compte-avec-email-dautrui.md)
- [`T1190`](https://attack.mitre.org/techniques/T1190/) Exploit Public-Facing Application : [T-07](failles/T-07-injection-sql.md), [T-22](failles/T-22-lien-de-desinscription.md), [R-01](risques-restants.md)
- [`T1485`](https://attack.mitre.org/techniques/T1485/) Data Destruction : [T-07](failles/T-07-injection-sql.md), [T-18](failles/T-18-suppression-de-compte-par-phrase.md)
- [`T1499`](https://attack.mitre.org/techniques/T1499/) Endpoint Denial of Service : [F-01](failles/F-01-fuseau-horaire-invalide.md), [F-05](failles/F-05-limite-messages-simultanes.md), [T-03](failles/T-03-codes-envoyes-en-boucle.md), [T-20](failles/T-20-epuisement-du-quota.md), [R-03](risques-restants.md), [R-05](risques-restants.md)
- [`T1499.003`](https://attack.mitre.org/techniques/T1499/003/) Endpoint Denial of Service: Application Exhaustion Flood : [T-20](failles/T-20-epuisement-du-quota.md)
- [`T1550.004`](https://attack.mitre.org/techniques/T1550/004/) Use Alternate Authentication Material: Web Session Cookie : [T-04](failles/T-04-reutilisation-de-session.md)
- [`T1552`](https://attack.mitre.org/techniques/T1552/) Unsecured Credentials : [T-13](failles/T-13-mot-de-passe-dans-les-journaux.md)
- [`T1566.002`](https://attack.mitre.org/techniques/T1566/002/) Phishing: Spearphishing Link : [F-02](failles/F-02-html-dans-email.md), [F-03](failles/F-03-phishing-par-ia-de-collecte.md), [T-19](failles/T-19-lien-de-phishing-dans-reponse-ia.md)

### ATLAS, les attaques sur l'IA

- [`AML.T0029`](https://atlas.mitre.org/techniques/AML.T0029) Denial of AI Service : [F-05](failles/F-05-limite-messages-simultanes.md), [T-20](failles/T-20-epuisement-du-quota.md), [R-06](risques-restants.md)
- [`AML.T0034`](https://atlas.mitre.org/techniques/AML.T0034) Cost Harvesting : [F-05](failles/F-05-limite-messages-simultanes.md), [T-20](failles/T-20-epuisement-du-quota.md)
- [`AML.T0051`](https://atlas.mitre.org/techniques/AML.T0051) LLM Prompt Injection : [T-18](failles/T-18-suppression-de-compte-par-phrase.md), [T-19](failles/T-19-lien-de-phishing-dans-reponse-ia.md), [T-21](failles/T-21-prompts-par-etape.md), [R-11](risques-restants.md)
- [`AML.T0051.000`](https://atlas.mitre.org/techniques/AML.T0051.000) LLM Prompt Injection: Direct : [T-15](failles/T-15-injection-de-prompt.md), [R-09](risques-restants.md)
- [`AML.T0051.001`](https://atlas.mitre.org/techniques/AML.T0051.001) LLM Prompt Injection: Indirect : [F-03](failles/F-03-phishing-par-ia-de-collecte.md), [T-25](failles/T-25-article-hors-du-lot.md)
- [`AML.T0054`](https://atlas.mitre.org/techniques/AML.T0054) LLM Jailbreak : [T-16](failles/T-16-jailbreak.md)

### CWE, les faiblesses du code

- [`CWE-20`](https://cwe.mitre.org/data/definitions/20.html) Improper Input Validation : [T-12](failles/T-12-valeurs-absurdes.md), [T-14](failles/T-14-entrees-invalides.md), [T-23](failles/T-23-themes-hors-liste.md), [T-24](failles/T-24-resumes-trop-longs.md)
- [`CWE-79`](https://cwe.mitre.org/data/definitions/79.html) Improper Neutralization of Input During Web Page Generation : [F-02](failles/F-02-html-dans-email.md)
- [`CWE-89`](https://cwe.mitre.org/data/definitions/89.html) Improper Neutralization of Special Elements used in an SQL Command : [T-07](failles/T-07-injection-sql.md), [T-22](failles/T-22-lien-de-desinscription.md)
- [`CWE-93`](https://cwe.mitre.org/data/definitions/93.html) Improper Neutralization of CRLF Sequences : [F-04](failles/F-04-email-piege-bcc.md)
- [`CWE-200`](https://cwe.mitre.org/data/definitions/200.html) Exposure of Sensitive Information to an Unauthorized Actor : [T-10](failles/T-10-memoire-de-lia-dun-autre-compte.md), [T-17](failles/T-17-ia-qui-recrache-des-donnees.md)
- [`CWE-204`](https://cwe.mitre.org/data/definitions/204.html) Observable Response Discrepancy : [T-05](failles/T-05-enumeration-de-comptes.md)
- [`CWE-307`](https://cwe.mitre.org/data/definitions/307.html) Improper Restriction of Excessive Authentication Attempts : [T-01](failles/T-01-mot-de-passe-devine.md), [T-02](failles/T-02-code-email-devine.md)
- [`CWE-319`](https://cwe.mitre.org/data/definitions/319.html) Cleartext Transmission of Sensitive Information : [R-02](risques-restants.md)
- [`CWE-338`](https://cwe.mitre.org/data/definitions/338.html) Use of Cryptographically Weak Pseudo-Random Number Generator (PRNG) : [T-02](failles/T-02-code-email-devine.md)
- [`CWE-532`](https://cwe.mitre.org/data/definitions/532.html) Insertion of Sensitive Information into Log File : [T-13](failles/T-13-mot-de-passe-dans-les-journaux.md)
- [`CWE-639`](https://cwe.mitre.org/data/definitions/639.html) Authorization Bypass Through User-Controlled Key : [T-08](failles/T-08-donnees-dun-autre-utilisateur.md), [T-25](failles/T-25-article-hors-du-lot.md)
- [`CWE-770`](https://cwe.mitre.org/data/definitions/770.html) Allocation of Resources Without Limits or Throttling : [F-05](failles/F-05-limite-messages-simultanes.md), [T-20](failles/T-20-epuisement-du-quota.md), [R-05](risques-restants.md)

## Les codes qui reviennent le plus

- `T1499` Endpoint Denial of Service : 6 fois
- `CWE-20` Improper Input Validation : 4 fois
- `AML.T0051` LLM Prompt Injection : 4 fois
- `T1566.002` Phishing: Spearphishing Link : 3 fois

## À dire à l'oral

« On a rangé nos attaques avec MITRE : ATT&CK pour les techniques d'attaque, ATLAS pour celles qui
visent l'IA, et CWE pour les faiblesses du code. Par exemple, l'essai de mots de passe, c'est
T1110.001, et l'injection de prompt, c'est AML.T0051. »
