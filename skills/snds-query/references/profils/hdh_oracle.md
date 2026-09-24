# Profil — SNDS via Health Data Hub (Oracle)

| Méta              | Valeur                                                        |
|-------------------|----------------------------------------------------------------|
| Base              | SNDS (Système National des Données de Santé), accès Health Data Hub |
| SGBD              | Oracle (via `ROracle` + `dbplyr`)                              |
| Connexion         | `dbConnect(dbDriver("Oracle"), dbname = "IPIAMPR2.WORLD")` |
| Schéma            | tables interrogées sans préfixe de schéma (résolution implicite au schéma courant du projet) ; en cas d'erreur Oracle `ORA-00942` (table introuvable), demander à l'utilisateur le schéma exact de son projet HDH |
| Années couvertes  | variable par table — DCIR/PMSI vont jusqu'à 2006 pour les tables les plus anciennes, jusqu'à 2024 pour les colonnes PMSI documentées ; la profondeur réellement accessible dépend de l'autorisation HDH du projet en cours, pas seulement du dictionnaire — toujours confirmer avec l'utilisateur |
| Chaînage          | PMSI `NIR_ANO_17` = DCIR `BEN_NIR_PSA` ; individu et causes de décès via `IR_BEN_R.BEN_IDT_ANO` — voir `modele-donnees.md`, « Chaînage patient » |

## Connexion — bloc standard à reproduire en tête de script

```r
library(ROracle)
library(dplyr)
library(dbplyr)

# Fuseau AVANT la connexion : ORA_SDTZ est lu à l'ouverture de session
Sys.setenv(TZ = "Europe/Paris")
Sys.setenv(ORA_SDTZ = "Europe/Paris")

.drv <- dbDriver("Oracle")
options(connectionObserver = NULL)
conn <- dbConnect(.drv, dbname = "IPIAMPR2.WORLD")

# Littéral DATE Oracle pour toute borne de date dans filter() : !!ora_date(d)
# (une date R brute est traduite en chaîne, convertie selon NLS_DATE_FORMAT)
ora_date <- function(d) dbplyr::sql(sprintf("DATE '%s'", format(as.Date(d), "%Y-%m-%d")))
```

`options(connectionObserver = NULL)` désactive l'observateur de connexion
RStudio — indispensable en pratique pour éviter les ralentissements liés à
l'introspection de connexion lors d'une session Oracle longue.

## Documentation officielle en ligne (référence vivante)

La documentation collaborative officielle du Health Data Hub —
https://documentation-snds.health-data-hub.fr/ — fait foi sur les filtres
recommandés et les points méthodologiques, au même titre que ce profil (elle
en est la source pour les corrections ci-dessous). Elle est activement
maintenue (GitLab) et évolue plus vite qu'une copie statique : quand l'outil
WebFetch est disponible, la consulter en complément de ce profil plutôt que
de se fier uniquement à un extrait figé, en particulier pour :

- **`snds/fiches/2023-12-11_synthese_filtres_snds_v1`** — synthèse des
  filtres recommandés par table (DCIR, PMSI MCO/HAD/SSR/RIP). Contient
  notamment la liste complète (~50 codes) des FINESS géographiques
  APHP/APHM/HCL à exclure pour doublon de transmission — **volontairement
  non recopiée ici** (liste longue, sujette à erreur de recopie, et
  périmée après mise à jour) : la récupérer en direct sur cette fiche au
  moment de la génération si le protocole porte sur des années 2005-2017.
- **`snds/fiches/valeurs_manquantes`** — gestion des valeurs manquantes
  (`NULL`) dans les requêtes SNDS sous Oracle.
- **`snds/tables/`** — schéma officiel des tables (variables, types, clés),
  alimentant le dictionnaire interactif
  https://health-data-hub.shinyapps.io/dico-snds/ ; à croiser avec le
  dictionnaire Kwikly embarqué (`references/dictionnaire/`) en cas de doute
  ou d'absence dans Kwikly.
- Les ~80 fiches thématiques (`snds/fiches/`) pour un sujet précis (chaînage
  mère-enfant, cartographie des pathologies, ALD…) non couvert par ce profil.

En cas de contradiction entre ce profil et la documentation officielle en
ligne, **la documentation officielle l'emporte** — ce profil doit alors être
mis à jour en conséquence plutôt que de faire confiance à l'ancienne valeur.

**Si le site est inaccessible** (proxy, WebFetch refusé), lire la source brute
sur GitLab :
`https://gitlab.com/healthdatahub/applications-du-hdh/documentation-snds/-/raw/master/snds/fiches/<Fichier>.md`
(nom de fichier sensible à la casse, ex. `2023-12-11_Synthese_Filtres_SNDS_V1.md`,
alors que l'URL du site est en minuscules).

**Les requêtes de la fiche filtres sont écrites en MySQL** : les traduire avant
usage sous Oracle — `RIGHT(x, n)` → `SUBSTR(x, -n)`, littéraux de date
`'AAAA-MM-JJ'` → `DATE 'AAAA-MM-JJ'` (en dbplyr : `!!ora_date(d)`).

**Sites connexes** (non autoritatifs, voir `SKILL.md` § « Ressources
complémentaires » pour leur usage précis dans le workflow) :
[forum d'entraide](https://entraide.health-data-hub.fr/) (dépannage
communautaire) et
[cartographie de l'écosystème SNDS](https://ecosysteme-snds.health-data-hub.fr/)
(annuaire de projets/algorithmes, utile pour sourcer une définition de
cohorte à l'étape 3).

## DCIR — `ER_PRS_F` (en-tête de prestation, 1 ligne / prestation)

Clé technique de jointure DCIR (9 colonnes, à répéter à l'identique sur les
tables de niveau prestation `ER_CAM_F`/`ER_PHA_F`/`ER_BIO_F`/`ER_ETE_F`/…) :
`FLX_DIS_DTD`, `FLX_TRT_DTD`, `FLX_EMT_TYP`, `FLX_EMT_NUM`, `FLX_EMT_ORD`,
`ORG_CLE_NUM`, `DCT_ORD_NUM`, `PRS_ORD_NUM`, `REM_TYP_AFF`. Exceptions :
`ER_UCD_F` n'a cette clé que depuis 2007, `ER_LOT_F`/`ER_TRS_F` depuis 2008 ;
`ER_DCT_F` (niveau décompte) n'a pas `PRS_ORD_NUM` et `REM_TYP_AFF` n'y est
documenté qu'en 2006 — jointure sur les 7 autres colonnes (à confirmer dans la
documentation officielle).

| Concept                              | Colonne        |
|---------------------------------------|----------------|
| Pseudonyme de l'ouvreur de droit (= `NIR_ANO_17` du PMSI) | `BEN_NIR_PSA`  |
| Rang du bénéficiaire (avec le précédent : clé de jointure vers `IR_BEN_R`, pas un identifiant d'individu) | `BEN_RNG_GEM` |
| Professionnel exécutant / prescripteur (= `ER_GEO_LOC_R.NUM_PS`) | `PFS_EXE_NUM` / `PFS_PRE_NUM` |
| Année de naissance                    | `BEN_NAI_ANN`  |
| Sexe                                  | `BEN_SEX_COD`  |
| Commune / département de résidence    | `BEN_RES_COM` / `BEN_RES_DPT` |
| Date d'exécution de la prestation     | `EXE_SOI_DTD`  |
| Nature de la prestation                | `PRS_NAT_REF`  |
| FINESS établissement prescripteur      | `ETB_PRE_FIN`  |
| Spécialité / statut juridique du PS prescripteur | `PSP_SPE_COD` / `PSP_STJ_COD` |
| Top qualité complément/majoration     | `CPL_MAJ_TOP`  |
| Qualificatif de la dépense (prestation) | `DPN_QLF`    |
| Qualificatif de la dépense (ligne de prestation) | `PRS_DPN_QLP` |

Filtre qualité DCIR recommandé (source : documentation officielle HDH,
fiche filtres) — exclure l'activité hospitalière publique en co-remontée
DCIR/PMSI, sur les **deux** variables : `DPN_QLF NOT IN (71, 72)` **et**
`PRS_DPN_QLP NOT IN (71, 72)` (les deux colonnes portent le même type
d'information à des granularités différentes — filtrer uniquement `DPN_QLF`
laisse passer des lignes en double). `CPL_MAJ_TOP <> 2` est optionnel,
utile seulement pour un dénombrement de lignes (exclut les lignes de
majoration pures).

Même fiche : exclure aussi l'activité des établissements ex-DG en facturation
directe, par jointure gauche sur `ER_ETE_F` (clé 9 colonnes) :
`ETE_IND_TAA <> 1 OR ETE_IND_TAA IS NULL` (en dbplyr :
`left_join(tbl(conn, I("ER_ETE_F")) |> select(all_of(DCIR_JOIN_KEY), ETE_IND_TAA), by = DCIR_JOIN_KEY) |> filter(is.na(ETE_IND_TAA) | ETE_IND_TAA != 1)`).

## DCIR — `ER_CAM_F` (actes CCAM en ville, jointure 9 colonnes vers `ER_PRS_F`)

| Concept                                    | Colonne        |
|----------------------------------------------|----------------|
| Code CCAM (identifiant acte — c'est lui qu'on filtre) | `CAM_PRS_IDE`  |
| Code activité (1 caractère)                  | `CAM_ACT_COD`  |
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
`filter(sql("REGEXP_LIKE(PHA_ATC_CLA, '^B01|^B02AA02|^N06AB')"))`. Garder la
liste de CIP13 obtenue en requête lazy (`semi_join`) : une classe large peut
dépasser 1000 codes, limite Oracle d'une liste `IN (...)` (ORA-01795).

## `IR_BEN_R` (référentiel bénéficiaire, catégorie AUTRE)

| Concept                                    | Colonne         |
|-----------------------------------------------|-----------------|
| Clé de jointure depuis le DCIR (avec `BEN_RNG_GEM`) | `BEN_NIR_PSA`   |
| Rang du bénéficiaire                          | `BEN_RNG_GEM`   |
| Identifiant de l'individu (patients uniques ; clé vers `KI_CCI_R`/`KI_ECD_R`) | `BEN_IDT_ANO` (= `BEN_NIR_ANO` si `BEN_IDT_TOP = 1`) |
| NIR pseudonymisé de l'individu                | `BEN_NIR_ANO`   |
| Date de décès                                 | `BEN_DCD_DTE`   |
| Résidence (commune / département)             | `BEN_RES_COM` / `BEN_RES_DPT` |
| Naissance (année / mois)                      | `BEN_NAI_ANN` / `BEN_NAI_MOI` |

`BEN_DCD_DTE` vaut `01-01-1600` quand **aucun décès n'est connu** — patient
vivant OU date manquante (Kwikly signale aussi `0001-01-01` pour une donnée
non valide). Filtre « pas de décès connu » :
`EXTRACT(YEAR FROM BEN_DCD_DTE) IN (1600, 1)`. Ce n'est pas un statut vital
exhaustif : il n'est fiable que pour le régime général hors SLM depuis juillet
2009 (MSA depuis 2009 ; RSI/SLM peu renseignés) — voir
`points-de-vigilance.md`, « Statut vital ».

**Filtres de qualité de la population** (source : documentation officielle
HDH, fiche filtres) — à appliquer pour constituer une base bénéficiaires
propre, notamment en vue d'un chaînage :
- Identifiant certifié : `BEN_CDI_NIR = '00'` (certifié), ou provisoire
  `BEN_CDI_NIR IN ('03', '04')` selon la tolérance voulue.
- Naissance/sexe renseignés : `BEN_NAI_ANN <> '1600'` (même convention
  sentinelle que `BEN_DCD_DTE`) et `BEN_SEX_COD <> 0`.
- Bénéficiaire actif sur la période : `MAX_TRT_DTD >= DATE '<AAAA-MM-JJ début>'`
  (dernière date de traitement d'une prestation ; en dbplyr
  `MAX_TRT_DTD >= !!ora_date(date_debut)`).
- Vivant au début de la période d'étude : `BEN_DCD_AME >= '<AAAAMM début>'`
  OU `BEN_DCD_AME = '160001'` (sentinelle « non décédé », variante AAAAMM
  de `BEN_DCD_DTE`).

## AUTRE — `IR_IMB_R` (référentiel médicalisé — ALD, catégorie AUTRE)

Table de référence pour les affections de longue durée (ALD), utile pour
une population/comorbidité définie par exonération plutôt que par
diagnostic PMSI. Filtres recommandés (source : documentation officielle
HDH, fiche filtres) :
- Nature d'exonération ALD (exclut accidents du travail/maladies
  professionnelles et motifs non exonérants) : `IMB_ETM_NAT IN (41, 43, 45)`.
- Bornes de validité de l'ALD : `IMB_ALD_DTD <= DATE '<fin AAAA-MM-JJ>'` ET
  (`IMB_ALD_DTF >= DATE '<début AAAA-MM-JJ>'` OU
  `EXTRACT(YEAR FROM IMB_ALD_DTF) = 1600` [pas de date de fin, même
  sentinelle que `BEN_DCD_DTE`]). En dbplyr :
  `filter(IMB_ALD_DTD <= !!ora_date(date_fin), IMB_ALD_DTF >= !!ora_date(date_debut) | sql("EXTRACT(YEAR FROM IMB_ALD_DTF) = 1600"))`.
- Diagnostic CIM-10 de l'ALD : `MED_MTF_COD`, décodé par `IR_CIM_V` (code
  complet) ou `IR_CCI_V` (catégorie 3 caractères) ; numéro d'ALD
  `IMB_ALD_NUM` décodé par `IR_ALD_V` ; nature d'exonération `IMB_ETM_NAT`
  (41/43/45) décodée par `IR_ETM_V`.
- ALD sans date de fin (`IMB_ALD_DTF` = 1600) : optionnellement, ne les
  retenir que si elles ont débuté dans les 5 ans précédant la période
  d'étude (ex. `IMB_ALD_DTD >= DATE '2016-01-01'` pour une étude 2021) ; les
  ALD avec une date de fin renseignée ne sont pas concernées. Des dates de
  fin au 31/12/2099 (ALD accordées à vie avant 2011) subsistent.

## DCIR — `ER_GEO_LOC_R` (géolocalisation du professionnel de santé)

| Concept                             | Colonne      |
|-----------------------------------------|--------------|
| Identifiant du professionnel de santé (clé) | `NUM_PS` (= `ER_PRS_F.PFS_EXE_NUM` exécutant, ou `PFS_PRE_NUM` prescripteur) |
| Commune / département / région du cabinet | `CODE_COM` / `CODE_DEPT` / `CODEREG` |

Attention : cette table géolocalise le **prescripteur/exécutant**, pas le
patient. Plusieurs lignes possibles par `NUM_PS` (colonne `CABINET`) :
vérifier l'unicité avant la jointure, sous peine de dupliquer les prestations. Pour la résidence du patient, utiliser `ER_PRS_F.BEN_RES_COM`/`BEN_RES_DPT`.
Table présente uniquement à partir des millésimes récents (aucun `X` avant la
colonne `*` dans le dictionnaire Kwikly) — vérifier avant d'utiliser sur une
période ancienne.

## PMSI — MCO, tables clés (millésime réel = 2 chiffres, ex. `T_MCO23B`)

| Table Kwikly (générique `AA`) | Rôle                              | Clé de jointure |
|---|---|---|
| `T_MCO{aa}C` | Chaînage / codes retour (1 ligne/séjour) | `(ETA_NUM, RSA_NUM)` |
| `T_MCO{aa}B` | Séjour / RSA (1 ligne/séjour : DP, DR, GHM, durée, `SEJ_TYP`) | `(ETA_NUM, RSA_NUM)` |
| `T_MCO{aa}UM` | RUM (unités médicales, plusieurs lignes par séjour) | `(ETA_NUM, RSA_NUM)` + n° d'UM |
| `T_MCO{aa}A` | Actes CCAM du séjour               | `(ETA_NUM, RSA_NUM)` |
| `T_MCO{aa}D` | Diagnostics associés (DAS)          | `(ETA_NUM, RSA_NUM)` |

`T_MCO{aa}C` :

| Concept                        | Colonne         |
|------------------------------------|-----------------|
| Identifiant patient (PMSI)         | `NIR_ANO_17`    |
| N° séjour / FINESS (clé)           | `RSA_NUM` / `ETA_NUM` |
| Dates d'entrée / sortie            | `EXE_SOI_DTD` / `EXE_SOI_DTF` (**2009+ seulement**, colonnes absentes avant) |
| Mois/année de sortie               | `SOR_ANN` / `SOR_MOI` (2006-2018 ; toujours présents dans `T_MCO{aa}B`) |
| Mois/année d'entrée                | `ENT_ANN` / `ENT_MOI` (2019+) |
| Codes retour qualité (depuis 2005) | `NIR_RET`, `NAI_RET`, `SEX_RET`, `SEJ_RET`, `FHO_RET`, `PMS_RET` |
| Code retour date (depuis 2006)     | `DAT_RET` |
| Codes retour cohérence (depuis 2013) | `COH_NAI_RET`, `COH_SEX_RET` |
| Chaînage mère-enfant                | `NIR_ANO_MAM` (2013-2018) puis `ID_MAM_ENF` (2019+) |

Filtre qualité de chaînage complet (source : documentation officielle HDH,
fiche filtres) : `NIR_RET = '0' AND NAI_RET = '0' AND SEX_RET = '0' AND
SEJ_RET = '0' AND FHO_RET = '0' AND PMS_RET = '0'` (depuis 2005), `AND
DAT_RET = '0'` (depuis 2006), `AND COH_NAI_RET = '0' AND COH_SEX_RET = '0'`
(depuis 2013), et exclusion des NIR fictifs : `NIR_ANO_17 NOT IN
('xxxxxxxxxxxxxxxxx', 'XXXXXXXXXXXXXXXXD', 'BXXXXXXXXXXXXXXXX',
'XXXXXXXXXXXXXXXXS', 'XXXXXXXXXXXXXXXXE')`. Exclusion des prestations
inter-établissements (PIE : séjours de type B, prestation de moins de 2 jours
réalisée pour le compte d'un autre établissement et déclarée par les deux —
pas un transfert classique) : `SEJ_TYP <> 'B' OR SEJ_TYP IS NULL`, sur
`T_MCO{aa}B` (la colonne n'existe pas dans `T_MCO{aa}C`).

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

Activité externe `T_MCO{aa}CSTC` (ACE des ex-DG) : filtres propres —
`NIR_RET = '0' AND NAI_RET = '0' AND SEX_RET = '0' AND IAS_RET = '0'` (2008+),
`+ ENT_DAT_RET = '0'` (2009+), exclusion des FINESS APHP/APHM/HCL
(2005-2017). `SEJ_RET`, `FHO_RET`, `PMS_RET`, `DAT_RET` et `COH_*` n'existent
pas dans cette table.

## PMSI — SSR/SMR, tables clés

Clé technique `(ETA_NUM, RHA_NUM)` pour `T_SSR{aa}C`/`B`/`D`/`GME` ;
`T_SSR{aa}CSTC` (activité externe, 2013+) a sa propre clé `(ETA_NUM, SEQ_NUM)`.
Le SSR est devenu SMR au 1er juin 2023 (réforme du financement en juillet
2023) : les tables gardent le nom `T_SSR{aa}*`, mais `FP_PEC` n'est plus codé
après le 01/03/2023 (absent du millésime 2023+).

Disponibilité : `T_SSR{aa}D` depuis 2009 (2006-2008 : DAS en colonnes
`ASS_DGN_1`..`ASS_DGN_20` de `T_SSR{aa}B`) ; actes CCAM `T_SSR{aa}CCAM` depuis
2009 (`CCAM_ACT` + `CCAM_COD_ACT` + `CCAM_PHA_ACT`) ; CSARR `T_SSR{aa}CSARR`
depuis 2014 ; CdARR `T_SSR{aa}CCAR` 2009-2013.

| Concept                                  | Colonne (`T_SSR{aa}B` sauf mention) |
|----------------------------------------------|---------------------------|
| Identifiant patient                          | `NIR_ANO_17` (`T_SSR{aa}C`) |
| Finalité principale de prise en charge (**2006-2022**) | `FP_PEC`     |
| Manifestation morbide principale              | `MOR_PRP`    |
| Affection étiologique                         | `ETL_AFF`    |
| Groupage GME (2013+) / CMC (2006-2012)        | `GRG_GME` / `GRG_CMC` (`T_SSR{aa}B`) ; `GME_COD` dans `T_SSR{aa}GME` (2013+) |
| Diagnostic associé (`T_SSR{aa}D`)             | `DGN_COD`    |
| Type de génération du RHA (depuis 2015)       | `TYP_GEN_RHA` |
| Mois/année du RHA (format MMAAAA)             | `MOI_ANN`     |
| Dates d'entrée / sortie (`T_SSR{aa}C`)        | `EXE_SOI_DTD` / `EXE_SOI_DTF` (2009+) ; `SOR_ANN`/`SOR_MOI` (2006-2008) |

Trio diagnostique SSR (`FP_PEC`/`MOR_PRP`/`ETL_AFF`) — à toujours faire
préciser lequel (ou lesquels) correspond au périmètre demandé, cf.
`clarifications.md`.

Filtres qualité SSR recommandés (source : documentation officielle HDH,
fiche filtres) :
- erreur de groupage (2013+) : au niveau RHA, `GRG_GME NOT LIKE '90%'` sur
  `T_SSR{aa}B` ; ou, au niveau séjour, `GME_COD NOT LIKE '90%'` sur
  `T_SSR{aa}GME`. Un seul des deux, chacun sur sa table — ne pas les combiner
  par `OR`. Avant 2013, ni l'une ni l'autre colonne n'existe (groupage en
  `GRG_CMC`, `T_SSR{aa}B`) ;
- exclusion des RHA auto-générés depuis 2015 : `TYP_GEN_RHA IN ('0', '4')` ;
- exclusion des RHA d'une année antérieure remontés en retard :
  `SUBSTR(MOI_ANN, 3, 4) = '<aaaa>'` (la fiche l'écrit en MySQL avec `RIGHT()`,
  qui n'existe pas en Oracle ; dbplyr : `filter(substr(MOI_ANN, 3, 6) == "2023")`) ;
- mêmes filtres de chaînage que MCO sur `T_SSR{aa}C` (`NIR_RET`…`PMS_RET`
  depuis 2005, `COH_NAI_RET`/`COH_SEX_RET` depuis 2013, NIR fictifs) — pas de
  piège doublon FINESS contrairement au MCO.

Activité externe (`T_SSR{aa}CSTC`, 2013+) : `NIR_RET = '0' AND NAI_RET = '0'
AND SEX_RET = '0' AND IAS_RET = '0' AND ENT_DAT_RET = '0'` uniquement
(`SEJ_RET`, `FHO_RET`, `PMS_RET`, `DAT_RET` et `COH_*` n'existent pas dans
cette table).

## PMSI — HAD (hospitalisation à domicile)

Filtres validés via la documentation officielle HDH (fiche filtres), sans
script local de référence — seules les tables et variables listées
ci-dessous sont confirmées ; pour toute autre table de la famille `T_HAD{aa}*`
(diagnostics, actes), vérifier sa structure exacte dans le dictionnaire
Kwikly (`references/dictionnaire/Kwikly/PMSI/`) avant usage.

Clé technique HAD : `(ETA_NUM_EPMSI, RHAD_NUM)` — pas de colonne `ETA_NUM`.

| Table | Rôle | Filtres qualité |
|---|---|---|
| `T_HAD{aa}B` | Séquence (RAPSS) : diagnostic principal `DGN_PAL`, modes de prise en charge `PEC_PAL`/`PEC_ASS` | `DGN_PAL` absent de Kwikly pour 2012-2013 : vérifier en base (`COUNT(DGN_PAL)`) avant toute série HAD ; DA 2007-2009 en `DGN_PAL1`..`DGN_PAL7` |
| `T_HAD{aa}GRP` | Groupage de la séquence | Exclusion des sous-séquences non groupées : `GHT_NUM <> '99'` |
| `T_HAD{aa}A` / `T_HAD{aa}D` | Actes / diagnostics associés | Tables existantes depuis 2010 seulement |
| `T_HAD{aa}C` | Chaînage / en-tête séjour | Mêmes filtres de chaînage que MCO (NIR fictifs compris) : `NIR_RET='0' AND NAI_RET='0' AND SEX_RET='0' AND SEJ_RET='0' AND FHO_RET='0' AND PMS_RET='0'` (depuis 2005), `+ DAT_RET='0'` (depuis 2006), `+ COH_NAI_RET='0' AND COH_SEX_RET='0'` (depuis 2013). Pas de piège doublon FINESS (spécifique au MCO). |

## PMSI — RIP (psychiatrie, équivalent RIM-P)

Filtres validés via la documentation officielle HDH (fiche filtres), sans
script local de référence — seules les tables et variables listées
ci-dessous sont confirmées ; pour toute autre table de la famille `T_RIP{aa}*`
(diagnostics, actes), vérifier sa structure exacte dans le dictionnaire
Kwikly (`references/dictionnaire/Kwikly/PMSI/`) avant usage.

Clé technique RIP : `(ETA_NUM_EPMSI, RIP_NUM)` — pas de colonne `ETA_NUM`.
Actes CCAM (`T_RIP{aa}CCAM`) depuis 2017 seulement.

| Table | Rôle | Filtres qualité |
|---|---|---|
| `T_RIP{aa}RSA` | Séjour/séquence | Exclusion des sorties d'essai (jusqu'en 2016) : `SEQ_IND <> 'E'` ; exclusion des RPSA auto-générés (depuis 2015) : `TYP_GEN_RSA = '0'` |
| `T_RIP{aa}C` | Chaînage | Mêmes filtres de chaînage que MCO, disponibles depuis 2007 (renforcés `COH_NAI_RET`/`COH_SEX_RET` depuis 2013) |

## CAUSE_DECES — `KI_CCI_R` (certificat, 1 ligne / décès) et `KI_ECD_R` (causes multiples)

| Concept                              | `KI_CCI_R`     | `KI_ECD_R`      |
|------------------------------------------|----------------|-----------------|
| Identifiant de l'individu (clé vers `IR_BEN_R.BEN_IDT_ANO`) | `BEN_IDT_ANO` | `BEN_IDT_ANO` |
| Top d'appariement avec `IR_BEN_R` (appariement incomplet : à contrôler) | `DCD_IDT_TOP` | — |
| NIR pseudonymisé (aussi présent dans `IR_BEN_R`) | `BEN_NIR_ANO` | `BEN_NIR_ANO` |
| Clé de jointure `KI_CCI_R` ↔ `KI_ECD_R` | `DCD_IDT_ENC` | `DCD_IDT_ENC` |
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
| `DPN_QLF`/`PRS_DPN_QLP` potentiellement `NULL` | `filter((is.na(DPN_QLF) | !DPN_QLF %in% c(71,72)) & (is.na(PRS_DPN_QLP) | !PRS_DPN_QLP %in% c(71,72)))` — un simple `DPN_QLF != 71` exclut silencieusement les lignes `NULL` en SQL Oracle (logique ternaire), et laisse passer le code 72 ainsi que les doublons visibles seulement sur `PRS_DPN_QLP` |
| `ORDER BY` sur colonne contenant des `NULL` (Oracle) | Oracle trie les `NULL` en dernier (SAS les traite comme valeur minimale) — éviter de trier côté Oracle sur une colonne à `NULL`, reporter le tri après `collect()` |
| Colonnes annuelles DCIR détaillées 2006-2012 seulement dans Kwikly (`*` ensuite) | Une variable sans aucun `X` est apparue après 2012 à une date inconnue : pour un périmètre ≥ 2013 qui l'utilise, vérifier empiriquement (`COUNT(*)` par année de `FLX_DIS_DTD`) |
| Chaînage inter-sources | PMSI `NIR_ANO_17` = DCIR `BEN_NIR_PSA` ; individu = `IR_BEN_R.BEN_IDT_ANO` ; causes de décès via `BEN_IDT_ANO` (appariement incomplet) — voir `modele-donnees.md`, « Chaînage patient » |
| Requêtes de la fiche filtres HDH (MySQL) | Traduire `RIGHT()` → `SUBSTR(x, -n)` et les littéraux de date → `DATE 'AAAA-MM-JJ'` |
| Liste `IN (...)` de plus de 1000 valeurs | ORA-01795 : `semi_join` sur une requête lazy ou une table temporaire |
| `BEN_DCD_DTE`/`BEN_DCD_AME` — valeur sentinelle | `01-01-1600` (resp. `160001`) = aucun décès connu (vivant OU date manquante) ; statut vital exhaustif seulement pour le RG hors SLM depuis 07/2009 — croiser avec `KI_CCI_R` et `SOR_MOD = 9` du PMSI |
| Doublons de transmission APHP/APHM/HCL          | Uniquement pertinent pour les séjours **2005-2017** (remontées corrigées depuis) ; liste complète (~50 FINESS) à récupérer en direct sur la fiche officielle (voir « Documentation officielle en ligne » ci-dessus), pas codée en dur ici |
| `EXT_PMSI` absent avant 2015 (actes CCAM MCO)      | Adapter la requête au millésime (2 formes de requête selon année < 15 ou ≥ 15) |
| Dates réelles absentes avant 2009 (`EXE_SOI_DTD`/`DTF` de `T_MCO{aa}C`/`T_SSR{aa}C`) | Colonnes inexistantes (ORA-00904) : pour 2006-2008, n'utiliser que le mois/année de sortie (`SOR_ANN`/`SOR_MOI`) et écrire une forme de requête par période |
| Statistiques d'une table temporaire | `copy_to()`/`compute()` avec `analyze = TRUE` (défaut) ; table créée par `dbExecute(CREATE TABLE)` : `DBMS_STATS.GATHER_TABLE_STATS` (`%m_stats_table()` est l'équivalent SAS) |
| Fuseau horaire Oracle/R                            | Poser `TZ`/`ORA_SDTZ` = `Europe/Paris` AVANT `dbDriver()`/`dbConnect()` (`ORA_SDTZ` est lu à l'ouverture de session ; sinon décalage UTC, notamment sur les dates de décès) |
| Dates R dans `filter()` | Traduites en chaîne, converties selon `NLS_DATE_FORMAT` : écrire `!!ora_date(d)` |

## Défauts recommandés

| Paramètre                          | Valeur                                                        |
|----------------------------------------|------------------------------------------------------------------|
| Connexion                              | `dbConnect(dbDriver("Oracle"), dbname = "IPIAMPR2.WORLD")`      |
| Fuseau                                 | `TZ = "Europe/Paris"`, `ORA_SDTZ = "Europe/Paris"`               |
| Seuil de diffusion (secret statistique) | 11 (`SEUIL`), convention usuelle sur les extractions SNDS        |
| Filtres qualité PMSI par défaut         | `NIR_RET`/`NAI_RET`/`SEX_RET`/`SEJ_RET`/`FHO_RET`/`PMS_RET` = `'0'` (depuis 2005), `+ DAT_RET = '0'` (depuis 2006), `+ COH_NAI_RET`/`COH_SEX_RET` = `'0'` (depuis 2013), `+` NIR fictifs exclus |
| Exclusion prestations inter-établissements (MCO) | `SEJ_TYP <> 'B' OR SEJ_TYP IS NULL` (table `T_MCO{aa}B`) |
| Exclusion doublons de transmission (MCO, 2005-2017 uniquement) | Liste de ~50 FINESS APHP/APHM/HCL — à récupérer en direct sur la fiche officielle (voir ci-dessus), non codée en dur |
| Exclusion GHM/GME en erreur             | `SUBSTR(GRG_GHM,1,2) <> '90'` (MCO) ; SSR 2013+ : `GRG_GME NOT LIKE '90%'` (`T_SSR{aa}B`) ou `GME_COD NOT LIKE '90%'` (`T_SSR{aa}GME`), un seul des deux |
| Filtres qualité DCIR par défaut         | `DPN_QLF NOT IN (71,72)` et `PRS_DPN_QLP NOT IN (71,72)` (en gérant les `NULL`) ; ES ex-DG en facturation directe exclus via `ER_ETE_F.ETE_IND_TAA` ; `CPL_MAJ_TOP <> 2` optionnel (dénombrement) |
| Marge de flux DCIR (`FLX_DIS_DTD`)      | Au moins 5 mois de données après la période clinique (6 flux) ; 12 pour une extraction exhaustive ; jamais plus de 24 |
| Filtres qualité population (`IR_BEN_R`) | `BEN_CDI_NIR = '00'`, `BEN_NAI_ANN <> '1600'`, `BEN_SEX_COD <> 0` — à appliquer avant tout chaînage ou comptage de patients uniques |
| Parallélisation par millésime           | `future::plan(future::multisession(workers = 4))` (générique — adapter à la machine de l'utilisateur) |
| Persistance locale                      | Jamais d'export local avec identifiants (ID, date, localisation) — voir `points-de-vigilance.md` |
