# Modèle de données — SNDS (Health Data Hub, Oracle)

> **Priorité des sources** : `references/profils/hdh_oracle.md` décrit
> l'environnement réel (mapping validé, pièges, défauts recommandés) et
> **fait foi** en cas de contradiction avec ce document. Ce document reste
> utile pour la vue d'ensemble et ce que le profil ne couvre pas encore
> (notamment HAD/RIP, non validés).

## Organisation générale — les 6 catégories Kwikly

Le dictionnaire SNDS (export HTML « Kwikly ») organise les tables en 6
catégories :

| Catégorie      | Contenu                                             | Nb tables |
|----------------|------------------------------------------------------|-----------|
| DCIR           | Consommation de soins de ville (datamart inter-régimes) | 17     |
| PMSI           | Séjours hospitaliers (MCO, SSR, HAD, RIP/psychiatrie) | 189      |
| CAUSE_DECES    | Cause médicale de décès (CépiDc)                     | 2         |
| CARTOGRAPHIE   | Cartographie des pathologies (agrégats populationnels) | 5       |
| VALEUR         | Tables de valeurs / codes (nomenclatures)             | 478       |
| AUTRE          | Les 478 tables de VALEUR + 13 tables de référence propres, notamment `IR_BEN_R` (bénéficiaires) et `IR_PHA_R` (médicaments) | 491 |

Les tables PMSI/DCIR millésimées portent, dans Kwikly, un nom générique avec
`AA` en guise de millésime (ex. `T_MCOAAB`) ; en base Oracle, le nom réel
porte l'année sur 2 chiffres (ex. `T_MCO23B` pour 2023, `T_MCO09B` pour 2009).
Reconstituer systématiquement `paste0("T_MCO", aa, "B")` (avec `aa` sur 2
chiffres, zéro-paddé) avant toute requête.

## DCIR — soins de ville

Clé technique de jointure commune à toutes les tables « flux » DCIR (9
colonnes) : `FLX_DIS_DTD`, `FLX_TRT_DTD`, `FLX_EMT_TYP`, `FLX_EMT_NUM`,
`FLX_EMT_ORD`, `ORG_CLE_NUM`, `DCT_ORD_NUM`, `PRS_ORD_NUM`, `REM_TYP_AFF`.

Tables clés : `ER_PRS_F` (en-tête prestation, table pivot), `ER_PHA_F`
(pharmacie), `ER_CAM_F` (actes CCAM en ville), `IR_PHA_R` (référentiel
médicament, catégorie AUTRE), `IR_BEN_R` (référentiel bénéficiaire, catégorie
AUTRE), `ER_GEO_LOC_R` (géolocalisation du professionnel de santé). Détail
des colonnes : voir `profils/hdh_oracle.md`.

Filtres qualité DCIR standard : `CPL_MAJ_TOP < 2` et
`(DPN_QLF IS NULL OR DPN_QLF <> 71)` — attention à la gestion des `NULL` (un
simple `!= 71` les exclut silencieusement en SQL Oracle).

## PMSI — séjours hospitaliers

Familles de tables par champ et par lettre (clé technique
`(ETA_NUM, RSA_NUM)` en MCO, `(ETA_NUM, RHA_NUM)` en SSR) :

| Champ | En-tête/chaînage | Diagnostics/GHM | Actes | DAS |
|---|---|---|---|---|
| MCO | `T_MCO{aa}C` | `T_MCO{aa}B` | `T_MCO{aa}A` | `T_MCO{aa}D` |
| SSR | `T_SSR{aa}C` | `T_SSR{aa}B` | `T_SSR{aa}CCAM`/`CSARR` | `T_SSR{aa}D` |
| HAD | `T_HAD{aa}C`* | `T_HAD{aa}B`* | `T_HAD{aa}A`* | `T_HAD{aa}D`* |
| RIP (psychiatrie) | `T_RIP{aa}C`* | `T_RIP{aa}RSA`* | `T_RIP{aa}CCAM`* | `T_RIP{aa}RSAD`* |

\* HAD et RIP existent dans le dictionnaire Kwikly mais n'ont pas encore été
validés dans cet environnement — vérifier les colonnes exactes dans les
pages détail avant utilisation (voir « Comment utiliser le dictionnaire
Kwikly » ci-dessous), et le signaler à l'utilisateur comme périmètre moins
éprouvé.

Diagnostics « principaux » selon le champ :

| Champ | Variables diagnostiques | DAS |
|---|---|---|
| MCO | `DGN_PAL` (DP), `DGN_REL` (DR) — table `T_MCO{aa}B` | `ASS_DGN` — table `T_MCO{aa}D` |
| SSR | `FP_PEC` (finalité principale), `MOR_PRP` (manifestation morbide principale), `ETL_AFF` (affection étiologique) — table `T_SSR{aa}B` | `DGN_COD` — table `T_SSR{aa}D` |

Filtres qualité PMSI standard (à appliquer sur la table d'en-tête/chaînage
`C`) :
`NIR_RET='0' AND NAI_RET='0' AND SEX_RET='0' AND SEJ_RET='0' AND FHO_RET='0'
AND PMS_RET='0'` (+ `DAT_RET='0'` pour les millésimes récents si les dates
réelles sont utilisées), et exclusion des doublons de transmission
`ETA_NUM NOT IN ('130786049','690781810','750712184')` (APHP/APHM/HCL).
Exclusion GHM/GME en erreur : `SUBSTR(GRG_GHM,1,2) <> '90'` (MCO),
`GRG_CMC <> '90'` ou `SUBSTR(GRG_GME,1,2) <> '90'` (SSR).

## CAUSE_DECES — mortalité (CépiDc)

`KI_CCI_R` (1 ligne/décès, cause initiale `DCD_CIM_COD`) et `KI_ECD_R`
(1 ligne/cause mentionnée, `ECD_CIM_COD` + rang `ECD_CAU_RNG` — `1` = cause
initiale). Identifiant patient : `BEN_NIR_ANO` — **différent** des
identifiants PMSI et DCIR (voir chaînage ci-dessous). Utiliser `KI_CCI_R`
pour une cause de décès unique (mortalité par cause), `KI_ECD_R` pour capter
les causes associées/contributives (ex. comorbidités mentionnées au
certificat).

## CARTOGRAPHIE, VALEUR, AUTRE

- **CARTOGRAPHIE** : tables d'agrégats de la cartographie des pathologies
  CNAM (`CRTO_CT_*`), millésimées, granularité départementale/nationale — utile
  pour des comparaisons de prévalence à un niveau agrégé, pas pour une
  extraction patient.
- **VALEUR** : 478 tables de correspondance code → libellé (nomenclatures,
  suffixe `_V`). À utiliser pour libeller un résultat, pas comme table de
  faits.
- **AUTRE** : contient les 478 tables VALEUR **plus** 13 tables de référence
  propres, dont les deux les plus utiles en pratique : `IR_BEN_R`
  (référentiel bénéficiaire — décès, résidence, naissance) et `IR_PHA_R`
  (référentiel médicament — classe ATC, CIP13/UCD). Les 11 autres
  (`DA_PRA_R`, `IR_ACS_R`(+`_ARC`), `IR_ETM_R`, `IR_IBA_R`, `IR_IMB_R`,
  `IR_MAT_R`, `IR_MTT_R`, `IR_ORC_R`(+`_ARC`)) n'ont pas encore d'usage
  documenté dans cet environnement — à explorer via leur page Kwikly au cas
  par cas.

## Chaînage patient — 3 identifiants distincts, pas de clé universelle

Contrairement à ATIH (une seule clé `anonyme` commune à tous les champs), le
SNDS utilise **trois variantes d'identifiant pseudonymisé selon la source**,
sans table de passage directe fournie dans cet export :

| Source          | Colonne(s) identifiant patient      |
|------------------|----------------------------------------|
| PMSI             | `NIR_ANO_17`                           |
| DCIR             | `BEN_NIR_PSA` + `BEN_RNG_GEM` (le couple, pas `BEN_NIR_PSA` seul) |
| CAUSE_DECES      | `BEN_NIR_ANO`                          |

Pour toute analyse croisant plusieurs sources (ex. hospitalisation PMSI +
consommation DCIR, ou séjour PMSI + décès CépiDc), le chaînage inter-source
doit être traité comme une étape à part entière du protocole, pas une simple
jointure : documenter la méthode retenue, signaler la perte éventuelle, et
garder à l'esprit qu'un même `BEN_NIR_PSA` peut être associé à plusieurs
`BEN_IDT_ANO`/`BEN_RNG_GEM` dans `IR_BEN_R` (ambiguïté à quantifier avant
de compter des patients uniques).

Qualité du chaînage intra-PMSI : filtrer sur les codes retour de
`T_MCO{aa}C` (`NIR_RET`, `NAI_RET`, `SEX_RET`, `SEJ_RET`, `FHO_RET`,
`PMS_RET` = `'0'`) avant tout comptage de patients uniques.

## Raccourcis de classification usuels

- Séance / HDJ / HC (MCO) :
  `case_when(substr(GRG_GHM,1,2) == "28" ~ "Séance", SEJ_NBJ == 0 ~ "HDJ", .default = "HC")`
  (pattern validé).
- Racine de GHM (5 caractères) : `substr(GRG_GHM, 1, 5)` ; CMD (2 car.) :
  `substr(GRG_GHM, 1, 2)`.
- GHM en erreur : `substr(GRG_GHM, 1, 2) != "90"`. GME (SSR) en erreur :
  `GRG_CMC != "90"` ou `substr(GRG_GME, 1, 2) != "90"`.
- Actes CCAM en ville : un acte = triplet `(CAM_PRS_IDE, CAM_ACT_COD,
  CAM_TRT_PHA)`, pas `CAM_PRS_IDE` seul.
- Chaînage mère-enfant (MCO) : `ID_MAM_ENF` / `NIR_ANO_MAM` (table
  `T_MCO{aa}C`).

## Filtres CIM-10/CCAM/ATC : `substr`/`%in%` ou `REGEXP_LIKE` Oracle

- Listes simples de codes : `substr(DGN_PAL, 1, 3) %in% c("E10", ...)`.
- Motifs complexes ou multi-racines : `REGEXP_LIKE` en SQL brut via `sql()` —
  c'est le pattern maison SNDS (contrairement à ATIH qui utilise
  `REGEXP_SIMILAR` côté Teradata) :
  `filter(sql("REGEXP_LIKE(CDC_ACT, '^[A-Z]{3}L')"))` (exemple validé,
  `snds-brouillon.R`) ou `filter(sql("REGEXP_LIKE(PHA_ATC_CLA, '^B01|^N06AB')"))`
  côté pharmacie.
- Le style historique `glue()` + chaîne SQL Oracle brute (`dbGetQuery(conn,
  glue(query, an = ..., table = ...))`) reste répandu dans des scripts R
  existants : à savoir reconnaître et relire si l'utilisateur colle un script
  existant dans cette convention, mais ce n'est **pas** le style de
  génération par défaut de cette skill (voir SKILL.md, étape 5 — dbplyr
  lazy + `sql()` est le défaut).

## Pièges classiques (à vérifier / signaler systématiquement)

1. **Année PMSI = année de sortie**, comme ATIH : un séjour à cheval compte
   sur le millésime de sortie. L'incidence par date d'entrée nécessite les
   dates réelles (`EXE_SOI_DTD`), indisponibles avant 2009 (forcées au 1er du
   mois/année).
2. **Séances (MCO)** : GHM commençant par `28` — un patient dialysé peut
   générer des dizaines de « séjours »/an ; toujours demander l'inclusion.
3. **GHM/GME en erreur** : exclusion par défaut (`90*`).
4. **Trois identifiants patient distincts** selon la source (`NIR_ANO_17`
   PMSI/CAUSE_DECES-`KI_CCI_R`/`KI_ECD_R`, `BEN_NIR_PSA`+`BEN_RNG_GEM` DCIR,
   `BEN_NIR_ANO` CAUSE_DECES) — pas de table de passage directe ; le
   chaînage inter-source est une étape de protocole à part entière, pas une
   jointure anodine.
5. **`DPN_QLF`/filtres qualité DCIR sur colonnes potentiellement `NULL`** :
   un simple `col != valeur` exclut silencieusement les `NULL` en SQL Oracle
   — utiliser `is.na(col) | col != valeur` quand la colonne peut être vide.
6. **Doublons de transmission** : `ETA_NUM` APHP/APHM/HCL
   (`'130786049'`,`'690781810'`,`'750712184'`) — à exclure systématiquement,
   ils ne sont pas filtrés par défaut par les tables sources.
7. **Évolutions de codage et de structure de table** : ex. `EXT_PMSI`
   (actes CCAM MCO) absent avant 2015 — deux formes de requête selon le
   millésime ; plus généralement, toujours croiser la période demandée avec
   les colonnes annuelles Kwikly avant de figer une requête pluriannuelle.
8. **Colonnes annuelles DCIR incomplètement documentées** : Kwikly ne
   détaille les millésimes DCIR que jusqu'en 2012 (colonne `*` ensuite,
   portée exacte non précisée) — prudence sur un périmètre < 2013.
9. **Fuseau horaire Oracle/R** : sans `Sys.setenv(TZ=...)` et
   `Sys.setenv(ORA_SDTZ=...)` posés à `Europe/Paris` en tout début de
   script, les dates remontées par `ROracle` peuvent être décalées d'un jour
   (conversion UTC) — critique sur les dates de décès notamment.
10. **Indexation après jointure** : toute table créée par jointure et
    destinée à être réutilisée doit être indexée via `%m_stats_table()`
    (SAS) — sinon jointures suivantes très lentes.

## Comment utiliser le dictionnaire Kwikly (recherche en deux niveaux)

Il n'existe pas de CSV variable-par-variable unique comme pour ATIH. La
recherche se fait en deux temps :

1. **Trouver la ou les tables candidates** dans
   `references/dictionnaire/index-tables.csv` (colonnes
   `categorie;table;libelle;chemin`) :
   ```bash
   grep -i "ccam" references/dictionnaire/index-tables.csv     # notion dans les libellés
   grep "^DCIR;" references/dictionnaire/index-tables.csv       # toutes les tables d'une catégorie
   ```
   Si ce fichier est absent ou semble périmé, chercher directement dans la
   page d'index de la catégorie (`Kwikly/DCIR.html`, `Kwikly/PMSI.html`,
   etc.), qui liste toutes les tables de la catégorie avec leur libellé et
   le lien vers la page détail.

2. **Lire la page détail** (`references/dictionnaire/Kwikly/<CATEGORIE>/<TABLE>.html`,
   via l'outil Read) pour la liste exhaustive des colonnes : variable,
   libellé, type, longueur, remarques, et — pour DCIR/PMSI/CARTOGRAPHIE
   uniquement — une colonne par millésime avec un `X` si la variable existe
   cette année-là. Pour cibler une variable précise sans tout relire :
   ```bash
   grep -A1 '>CAM_ACT_COD<' references/dictionnaire/Kwikly/DCIR/ER_CAM_F.html
   ```

Les pièges propres à l'environnement (disponibilité exacte des schémas…)
sont dans `profils/hdh_oracle.md`, qui fait foi.
