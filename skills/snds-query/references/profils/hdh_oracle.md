# Profil — SNDS via Health Data Hub (Oracle)

| Méta              | Valeur                                                        |
|-------------------|----------------------------------------------------------------|
| Base              | SNDS (Système National des Données de Santé), accès Health Data Hub |
| SGBD              | Oracle (via `ROracle` + `dbplyr`)                              |
| Connexion         | `dbConnect(dbDriver("Oracle"), dbname = "IPIAMPR2.WORLD")` |
| Schéma            | tables interrogées sans préfixe de schéma (résolution implicite au schéma courant du projet) ; en cas d'erreur Oracle `ORA-00942` (table introuvable), demander à l'utilisateur le schéma exact de son projet HDH |
| Années couvertes  | variable par table — DCIR/PMSI vont jusqu'à 2006 pour les tables les plus anciennes, jusqu'à 2024 pour les colonnes PMSI documentées ; la profondeur réellement accessible dépend de l'autorisation HDH du projet en cours, pas seulement du dictionnaire — toujours confirmer avec l'utilisateur |
| Clé universelle   | **aucune** — 3 identifiants patient distincts selon la source (voir « Chaînage » ci-dessous) |

## Connexion — bloc standard à reproduire en tête de script

```r
library(ROracle)
library(dplyr)
library(dbplyr)

.drv <- dbDriver("Oracle")
options(connectionObserver = NULL)
conn <- dbConnect(.drv, dbname = "IPIAMPR2.WORLD")

Sys.setenv(TZ = "Europe/Paris")
Sys.setenv(ORA_SDTZ = "Europe/Paris")
```

`options(connectionObserver = NULL)` désactive l'observateur de connexion
RStudio — indispensable en pratique pour éviter les ralentissements liés à
l'introspection de connexion lors d'une session Oracle longue.

## DCIR — `ER_PRS_F` (en-tête de prestation, 1 ligne / prestation)

Clé technique de jointure DCIR (9 colonnes, à répéter à l'identique sur
`ER_CAM_F`/`ER_PHA_F`/…) : `FLX_DIS_DTD`, `FLX_TRT_DTD`, `FLX_EMT_TYP`,
`FLX_EMT_NUM`, `FLX_EMT_ORD`, `ORG_CLE_NUM`, `DCT_ORD_NUM`, `PRS_ORD_NUM`,
`REM_TYP_AFF`.

| Concept                              | Colonne        |
|---------------------------------------|----------------|
| Identifiant patient (DCIR)            | `BEN_NIR_PSA`  |
| Rang du bénéficiaire (à combiner avec le précédent) | `BEN_RNG_GEM` |
| Année de naissance                    | `BEN_NAI_ANN`  |
| Sexe                                  | `BEN_SEX_COD`  |
| Commune / département de résidence    | `BEN_RES_COM` / `BEN_RES_DPT` |
| Date d'exécution de la prestation     | `EXE_SOI_DTD`  |
| Nature de la prestation                | `PRS_NAT_REF`  |
| FINESS établissement prescripteur      | `ETB_PRE_FIN`  |
| Spécialité / statut juridique du PS prescripteur | `PSP_SPE_COD` / `PSP_STJ_COD` |
| Top qualité complément/majoration     | `CPL_MAJ_TOP`  |
| Qualificatif de la dépense            | `DPN_QLF`      |

## DCIR — `ER_CAM_F` (actes CCAM en ville, jointure 9 colonnes vers `ER_PRS_F`)

| Concept                                    | Colonne        |
|----------------------------------------------|----------------|
| Code CCAM (identifiant acte)                | `CAM_PRS_IDE`  |
| Code activité                                | `CAM_ACT_COD`  |
| Phase de traitement                          | `CAM_TRT_PHA`  |
| Localisation dentaire                        | `CAM_QUA_DEN`  |

Le triplet `CAM_PRS_IDE` + `CAM_ACT_COD` + `CAM_TRT_PHA` identifie un acte de
façon unique — ne pas compter sur `CAM_PRS_IDE` seul (un même acte génère
plusieurs lignes : activité chirurgicale et anesthésie, par exemple).

## DCIR — `ER_PHA_F` + `IR_PHA_R` (pharmacie)

`ER_PHA_F` (jointure 9 colonnes vers `ER_PRS_F`) :

| Concept                        | Colonne         |
|----------------------------------|-----------------|
| Code CIP13 délivré               | `PHA_PRS_C13`   |
| Quantité                         | `PHA_ACT_QSN`   |
| Top / quantité de déconditionnement | `PHA_DEC_TOP` / `PHA_DEC_QSU` |

`IR_PHA_R` (référentiel médicament, catégorie AUTRE — jointure
`ER_PHA_F.PHA_PRS_C13 = IR_PHA_R.PHA_CIP_C13`) :

| Concept                          | Colonne         |
|-------------------------------------|-----------------|
| Code CIP13 (clé de jointure)        | `PHA_CIP_C13`   |
| Classe ATC complète                 | `PHA_ATC_CLA`   |
| 2ᵉ niveau de la classe ATC + libellé | `PHA_ATC_C03` / `PHA_ATC_L03` |
| Code UCD (médicament hospitalier)   | `PHA_CIP_UCD`   |

Filtre ATC classique (motif multi-classes) :
`filter(sql("REGEXP_LIKE(PHA_ATC_CLA, '^B01|^B02AA02|^N06AB')"))`.

## `IR_BEN_R` (référentiel bénéficiaire, catégorie AUTRE)

| Concept                                    | Colonne         |
|-----------------------------------------------|-----------------|
| Clé (avec `BEN_RNG_GEM`)                      | `BEN_NIR_PSA`   |
| Rang du bénéficiaire                          | `BEN_RNG_GEM`   |
| Identifiant anonymisé (pivot potentiel, à valider avant usage) | `BEN_IDT_ANO` |
| Date de décès                                 | `BEN_DCD_DTE`   |
| Résidence (commune / département)             | `BEN_RES_COM` / `BEN_RES_DPT` |
| Naissance (année / mois)                      | `BEN_NAI_ANN` / `BEN_NAI_MOI` |

`BEN_DCD_DTE` porte une valeur sentinelle pour « non décédé » : en base
Oracle, la date vaut `01-01-1600` tant que le patient est considéré comme
vivant. Filtre « patient vivant » : `EXTRACT(YEAR FROM BEN_DCD_DTE) = 1600` ;
filtre « patient décédé » : `EXTRACT(YEAR FROM BEN_DCD_DTE) <> 1600`.

## DCIR — `ER_GEO_LOC_R` (géolocalisation du professionnel de santé)

| Concept                             | Colonne      |
|-----------------------------------------|--------------|
| Identifiant du professionnel de santé (clé) | `NUM_PS` |
| Commune / département / région du cabinet | `CODE_COM` / `CODE_DEPT` / `CODEREG` |

Attention : cette table géolocalise le **prescripteur/exécutant**, pas le
patient. Pour la résidence du patient, utiliser `ER_PRS_F.BEN_RES_COM`/`BEN_RES_DPT`.
Table présente uniquement à partir des millésimes récents (aucun `X` avant la
colonne `*` dans le dictionnaire Kwikly) — vérifier avant d'utiliser sur une
période ancienne.

## PMSI — MCO, tables clés (millésime réel = 2 chiffres, ex. `T_MCO23B`)

| Table Kwikly (générique `AA`) | Rôle                              | Clé de jointure |
|---|---|---|
| `T_MCO{aa}C` | Chaînage / en-tête séjour (1 ligne/séjour) | `(ETA_NUM, RSA_NUM)` |
| `T_MCO{aa}B` | RUM (diagnostics, GHM, durée)     | `(ETA_NUM, RSA_NUM)` |
| `T_MCO{aa}A` | Actes CCAM du séjour               | `(ETA_NUM, RSA_NUM)` |
| `T_MCO{aa}D` | Diagnostics associés (DAS)          | `(ETA_NUM, RSA_NUM)` |

`T_MCO{aa}C` :

| Concept                        | Colonne         |
|------------------------------------|-----------------|
| Identifiant patient (PMSI)         | `NIR_ANO_17`    |
| N° séjour / FINESS (clé)           | `RSA_NUM` / `ETA_NUM` |
| Dates d'entrée / sortie            | `EXE_SOI_DTD` / `EXE_SOI_DTF` |
| Codes retour qualité                | `NIR_RET`, `NAI_RET`, `SEX_RET`, `SEJ_RET`, `FHO_RET`, `PMS_RET`, `DAT_RET` |
| Chaînage mère-enfant                | `ID_MAM_ENF` / `NIR_ANO_MAM` |

`T_MCO{aa}B` :

| Concept                          | Colonne     |
|--------------------------------------|-------------|
| Diagnostic principal / relié          | `DGN_PAL` / `DGN_REL` |
| GHM (calculé)                         | `GRG_GHM`   |
| Code retour groupage                  | `GRG_RET`   |
| Âge (années / jours)                  | `AGE_ANN` / `AGE_JOU` |
| Géographie de résidence (dépt / code) | `BDI_DEP` / `BDI_COD` |
| Durée totale du séjour (vide si séance) | `SEJ_NBJ` |

`T_MCO{aa}A` :

| Concept                       | Colonne       |
|-----------------------------------|---------------|
| Code CCAM                         | `CDC_ACT`     |
| Extension PMSI (**disponible seulement à partir de 2015**) | `EXT_PMSI` |

`T_MCO{aa}D` :

| Concept              | Colonne    |
|--------------------------|------------|
| Diagnostic associé       | `ASS_DGN`  |

## PMSI — SSR, tables clés

Même clé technique `(ETA_NUM, RHA_NUM)`, tables `T_SSR{aa}C`/`B`/`D`.

| Concept                                  | Colonne (`T_SSR{aa}B` sauf mention) |
|----------------------------------------------|---------------------------|
| Identifiant patient                          | `NIR_ANO_17` (`T_SSR{aa}C`) |
| Finalité principale de prise en charge        | `FP_PEC`     |
| Manifestation morbide principale              | `MOR_PRP`    |
| Affection étiologique                         | `ETL_AFF`    |
| Groupage GME / CMC                            | `GRG_GME` / `GRG_CMC` |
| Diagnostic associé (`T_SSR{aa}D`)             | `DGN_COD`    |

Trio diagnostique SSR (`FP_PEC`/`MOR_PRP`/`ETL_AFF`) = équivalent fonctionnel
du `finalp`/`morbidp`/`etiolp` ATIH — à toujours faire préciser lequel (ou
lesquels) correspond au périmètre demandé, cf. `clarifications.md`.

## PMSI — HAD, RIP (psychiatrie) : non validées dans cet environnement

Les familles de tables `T_HAD{aa}*` et `T_RIP{aa}*` existent dans le
dictionnaire Kwikly (HAD, et RIP = équivalent RIM-P psychiatrie), mais
n'ont pas encore été utilisées ni validées dans cet environnement — à ne
documenter dans ce profil qu'après une première requête validée dessus. En
attendant, s'appuyer
uniquement sur le dictionnaire Kwikly (`references/dictionnaire/Kwikly/PMSI/`)
et le signaler comme périmètre moins éprouvé si l'utilisateur les demande.

## CAUSE_DECES — `KI_CCI_R` (certificat, 1 ligne / décès) et `KI_ECD_R` (causes multiples)

| Concept                              | `KI_CCI_R`     | `KI_ECD_R`      |
|------------------------------------------|----------------|-----------------|
| Identifiant patient (**3ᵉ variante, distincte de PMSI et DCIR**) | `BEN_NIR_ANO` | `BEN_NIR_ANO` |
| Cause de décès (CIM-10)                  | `DCD_CIM_COD` (cause initiale) | `ECD_CIM_COD` (une ligne par cause) |
| Rang de la cause                          | —              | `ECD_CAU_RNG` (1 = initiale) |
| Libellé de la cause                       | —              | `ECD_CAU_LIB`   |
| Année de décès                            | `FLX_PER_ANN`  | `FLX_PER_ANN`   |
| Naissance / sexe / résidence              | `BEN_NAI_ANN`/`BEN_NAI_MOI`/`BEN_SEX_COD`/`BEN_RES_COM`/`BEN_RES_DPT` | — |

`KI_CCI_R` porte aussi des variables obstétricales/certificat (grossesse,
accouchement) hors du périmètre mortalité générale — ne les utiliser que sur
demande explicite.

## Pièges

| Piège                                          | Traitement                                    |
|--------------------------------------------------|------------------------------------------------|
| `DPN_QLF` peut être `NULL` sur les millésimes anciens | `filter(is.na(DPN_QLF) | DPN_QLF != 71)` — un simple `DPN_QLF != 71` exclut silencieusement les lignes `NULL` en SQL Oracle (logique ternaire) |
| Qualité DCIR                                      | `CPL_MAJ_TOP < 2` en plus du filtre `DPN_QLF` |
| Colonnes annuelles DCIR limitées à 2012 dans Kwikly (`*` ensuite) | Ne pas conclure à une absence/présence sur un périmètre < 2013 sans vérification empirique |
| 3 identifiants patient différents selon la source | `NIR_ANO_17` (PMSI, `KI_CCI_R`/`KI_ECD_R`) ≠ `BEN_NIR_PSA`+`BEN_RNG_GEM` (DCIR) ≠ `BEN_NIR_ANO` (CAUSE_DECES) — aucune table de passage directe dans cet export ; valider le chaînage avant tout croisement inter-source |
| `BEN_DCD_DTE` — valeur sentinelle           | `01-01-1600` = patient encore considéré comme vivant ; toute autre date = date de décès |
| `EXT_PMSI` absent avant 2015 (actes CCAM MCO)      | Adapter la requête au millésime (2 formes de requête selon année < 15 ou ≥ 15) |
| Dates réelles indisponibles avant 2009             | Forcées au 1er jour du mois/année |
| Indexation après jointure                          | `%m_stats_table(nom_table=...)` (SAS) obligatoire après création d'une table jointe, sous peine de jointures très lentes |
| Fuseau horaire Oracle/R                            | Toujours poser `TZ`/`ORA_SDTZ` = `Europe/Paris` avant toute requête (sinon décalage UTC, notamment sur les dates de décès) |

## Défauts recommandés

| Paramètre                          | Valeur                                                        |
|----------------------------------------|------------------------------------------------------------------|
| Connexion                              | `dbConnect(dbDriver("Oracle"), dbname = "IPIAMPR2.WORLD")`      |
| Fuseau                                 | `TZ = "Europe/Paris"`, `ORA_SDTZ = "Europe/Paris"`               |
| Seuil de diffusion (secret statistique) | 11 (`SEUIL`, cf. `snds-brouillon.R`)                             |
| Filtres qualité PMSI par défaut         | `NIR_RET`/`NAI_RET`/`SEX_RET`/`SEJ_RET`/`FHO_RET`/`PMS_RET` = `'0'` (+`DAT_RET = '0'` si dates réelles nécessaires) |
| Exclusion doublons de transmission      | `ETA_NUM NOT IN ('130786049','690781810','750712184')` (APHP/APHM/HCL) |
| Exclusion GHM/GME en erreur             | `SUBSTR(GRG_GHM,1,2) <> '90'` (MCO) ; `GRG_CMC <> '90'` ou `SUBSTR(GRG_GME,1,2) <> '90'` (SSR) |
| Filtres qualité DCIR par défaut         | `CPL_MAJ_TOP < 2`, `(DPN_QLF IS NULL OR DPN_QLF <> 71)`          |
| Parallélisation par millésime           | `future::plan(future::multisession(workers = 4))` (générique — adapter à la machine de l'utilisateur) |
| Persistance locale                      | Jamais d'export local avec identifiants (ID, date, localisation) — voir `points-de-vigilance.md` |
