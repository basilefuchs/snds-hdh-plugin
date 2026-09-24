# Dictionnaire SNDS (dérivé de schema-snds)

Fichiers générés par `scripts/build-dictionary.py` (dossier de la skill) depuis le dépôt open source
**schema-snds** du Health Data Hub :
https://gitlab.com/healthdatahub/applications-du-hdh/schema-snds
(commit et date : `SOURCE.txt`).

**Licence** : ces fichiers sont des dérivés de schema-snds et sont distribués
sous **Mozilla Public License 2.0** (texte : `LICENSE-MPL-2.0.txt`). La source
complète est disponible à l'adresse ci-dessus. Ils ne relèvent pas de la
licence MIT du reste du plugin.

Tous les fichiers sont en TSV UTF-8 (tabulation, sans guillemets, une ligne par
enregistrement, textes multi-lignes joints par ` | `) : recherche par `grep`.

| Fichier | Une ligne par | Colonnes |
|---|---|---|
| `tables.tsv` | table | produit, table, libelle, cle_primaire, nb_variables, debut, fin, absente, observation |
| `variables.tsv` | variable d'une table | table, variable, type, type_oracle, longueur, nomenclature, debut, fin, absente, libelle, observation, regle_gestion |
| `jointures.tsv` | clé étrangère déclarée | table, colonnes, table_cible, colonnes_cible |
| `nomenclatures.tsv` | nomenclature (table de valeurs ou référentiel) | dossier, nomenclature, libelle, colonnes, colonne_code, colonne_libelle, taille_ko, valeurs_embarquees |
| `valeurs.tsv` | code d'une nomenclature (celles de moins de 50 Ko) | nomenclature, code, libelle |

Millésimes (`debut`, `fin`, `absente`) : année d'apparition, dernière année
(vide = toujours présente) et années manquantes entre les deux, tels que
déclarés dans schema-snds.

Noms de tables PMSI : génériques avec `aa` minuscule (ex. `T_MCOaaB`) ; en
base, `aa` = année sur 2 chiffres (`T_MCO23B`).

Mise à jour :

```
git clone --depth 1 https://gitlab.com/healthdatahub/applications-du-hdh/schema-snds.git
python3 scripts/build-dictionary.py schema-snds   # depuis le dossier de la skill
```
