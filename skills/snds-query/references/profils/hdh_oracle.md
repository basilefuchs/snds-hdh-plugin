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

**Sites connexes** (non autoritatifs, voir `SKILL.md` § « Ressources
complémentaires » pour leur usage précis dans le workflow) :
[forum d'entraide](https://entraide.health-data-hub.fr/) (dépannage
communautaire) et
[cartographie de l'écosystème SNDS](https://ecosysteme-snds.health-data-hub.fr/)
(annuaire de projets/algorithmes, utile pour sourcer une définition de
cohorte à l'étape 3).

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

**Filtres de qualité de la population** (source : documentation officielle
HDH, fiche filtres) — à appliquer pour constituer une base bénéficiaires
propre, notamment en vue d'un chaînage :
- Identifiant certifié : `BEN_CDI_NIR = '00'` (certifié), ou provisoire
  `BEN_CDI_NIR IN ('03', '04')` selon la tolérance voulue.
- Naissance/sexe renseignés : `BEN_NAI_ANN <> '1600'` (même convention
  sentinelle que `BEN_DCD_DTE`) et `BEN_SEX_COD <> 0`.
- Bénéficiaire actif sur la période : `MAX_TRT_DTD >= '<début période>'`
  (dernière date de traitement d'une prestation).
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
- Bornes de validité de l'ALD : `IMB_ALD_DTD <= '<fin période>'` ET
  (`IMB_ALD_DTF >= '<début période>'` OU `IMB_ALD_DTF = '1600-01-01'`
  [ALD toujours active, même sentinelle que `BEN_DCD_DTE`]).
- Diagnostic CIM-10 associé à l'ALD : via la table de valeurs `IR_CIM_V`
  (catégorie VALEUR) pour la classification ALD en vigueur.
- ALD anciennes sans date de fin connue : se limiter à
  `IMB_ALD_DTD >= '2016-01-01'` (les ALD accordées avant cette date sans
  date de fin explicite sont soumises à une limite réglementaire de 2 à 5
  ans post-2011, non déductible directement de la table).

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
| Codes retour qualité (depuis 2005) | `NIR_RET`, `NAI_RET`, `SEX_RET`, `SEJ_RET`, `FHO_RET`, `PMS_RET` |
| Code retour date (depuis 2006)     | `DAT_RET` |
| Codes retour cohérence (depuis 2013) | `COH_NAI_RET`, `COH_SEX_RET` |
| Type de séjour (transfert inter-établissement) | `SEJ_TYP` |
| Chaînage mère-enfant                | `ID_MAM_ENF` / `NIR_ANO_MAM` |

Filtre qualité de chaînage complet (source : documentation officielle HDH,
fiche filtres) : `NIR_RET = '0' AND NAI_RET = '0' AND SEX_RET = '0' AND
SEJ_RET = '0' AND FHO_RET = '0' AND PMS_RET = '0'` (depuis 2005), `AND
DAT_RET = '0'` (depuis 2006), `AND COH_NAI_RET = '0' AND COH_SEX_RET = '0'`
(depuis 2013). Exclusion des transferts inter-établissements (recommandée
pour éviter un double compte du même séjour) : `SEJ_TYP <> 'B' OR SEJ_TYP
IS NULL`.

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

Même clé technique `(ETA_NUM, RHA_NUM)`, tables `T_SSR{aa}C`/`B`/`D`
(+ `T_SSR{aa}GME` pour le groupage, `T_SSR{aa}CSTC` pour l'activité externe).

| Concept                                  | Colonne (`T_SSR{aa}B` sauf mention) |
|----------------------------------------------|---------------------------|
| Identifiant patient                          | `NIR_ANO_17` (`T_SSR{aa}C`) |
| Finalité principale de prise en charge        | `FP_PEC`     |
| Manifestation morbide principale              | `MOR_PRP`    |
| Affection étiologique                         | `ETL_AFF`    |
| Groupage GME / CMC                            | `GRG_GME` / `GRG_CMC` (`T_SSR{aa}GME`) |
| Diagnostic associé (`T_SSR{aa}D`)             | `DGN_COD`    |
| Type de génération du RHA (depuis 2015)       | `TYP_GEN_RHA` (`T_SSR{aa}C`) |
| Mois/année du RHA                             | `MOI_ANN` (`T_SSR{aa}C`) |

Trio diagnostique SSR (`FP_PEC`/`MOR_PRP`/`ETL_AFF`) = équivalent fonctionnel
du `finalp`/`morbidp`/`etiolp` ATIH — à toujours faire préciser lequel (ou
lesquels) correspond au périmètre demandé, cf. `clarifications.md`.

Filtres qualité SSR recommandés (source : documentation officielle HDH,
fiche filtres) : erreur de groupage `GRG_GME NOT LIKE '90%' OR GME_COD NOT
LIKE '90%'` (nom de colonne selon le millésime) ; exclusion des RHA
auto-générés depuis 2015 : `TYP_GEN_RHA IN ('0', '4')` ; exclusion des RHA
d'une année antérieure remontés en retard : `RIGHT(MOI_ANN, 4) = <année
étudiée>` ; mêmes filtres de chaînage que MCO (`NIR_RET`…`PMS_RET` depuis
2005, `COH_NAI_RET`/`COH_SEX_RET` depuis 2013 — pas de piège doublon
FINESS contrairement au MCO). Activité externe (`T_SSR{aa}CSTC`) : mêmes
filtres + `IAS_RET = '0' AND ENT_DAT_RET = '0'` (depuis 2013).

## PMSI — HAD (hospitalisation à domicile)

Filtres validés via la documentation officielle HDH (fiche filtres), sans
script local de référence — seules les tables et variables listées
ci-dessous sont confirmées ; pour toute autre table de la famille `T_HAD{aa}*`
(diagnostics, actes), vérifier sa structure exacte dans le dictionnaire
Kwikly (`references/dictionnaire/Kwikly/PMSI/`) avant usage.

| Table | Rôle | Filtres qualité |
|---|---|---|
| `T_HAD{aa}GRP` | Groupage de la séquence | Exclusion des sous-séquences non groupées : `GHT_NUM <> '99'` |
| `T_HAD{aa}C` | Chaînage / en-tête séjour | Mêmes filtres de chaînage que MCO : `NIR_RET='0' AND NAI_RET='0' AND SEX_RET='0' AND SEJ_RET='0' AND FHO_RET='0' AND PMS_RET='0'` (depuis 2005), `+ DAT_RET='0'` (depuis 2006), `+ COH_NAI_RET='0' AND COH_SEX_RET='0'` (depuis 2013). Pas de piège doublon FINESS (spécifique au MCO). |

## PMSI — RIP (psychiatrie, équivalent RIM-P)

Filtres validés via la documentation officielle HDH (fiche filtres), sans
script local de référence — seules les tables et variables listées
ci-dessous sont confirmées ; pour toute autre table de la famille `T_RIP{aa}*`
(diagnostics, actes), vérifier sa structure exacte dans le dictionnaire
Kwikly (`references/dictionnaire/Kwikly/PMSI/`) avant usage.

| Table | Rôle | Filtres qualité |
|---|---|---|
| `T_RIP{aa}RSA` | Séjour/séquence | Exclusion des sorties d'essai (jusqu'en 2016) : `SEQ_IND <> 'E'` ; exclusion des RPSA auto-générés (depuis 2015) : `TYP_GEN_RSA = '0'` |
| `T_RIP{aa}C` | Chaînage | Mêmes filtres de chaînage que MCO, disponibles depuis 2007 (renforcés `COH_NAI_RET`/`COH_SEX_RET` depuis 2013) |

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
| `DPN_QLF`/`PRS_DPN_QLP` potentiellement `NULL` | `filter((is.na(DPN_QLF) | !DPN_QLF %in% c(71,72)) & (is.na(PRS_DPN_QLP) | !PRS_DPN_QLP %in% c(71,72)))` — un simple `DPN_QLF != 71` exclut silencieusement les lignes `NULL` en SQL Oracle (logique ternaire), et laisse passer le code 72 ainsi que les doublons visibles seulement sur `PRS_DPN_QLP` |
| `ORDER BY` sur colonne contenant des `NULL` (Oracle) | Oracle trie les `NULL` en dernier (SAS les traite comme valeur minimale) — éviter de trier côté Oracle sur une colonne à `NULL`, reporter le tri après `collect()` |
| Colonnes annuelles DCIR limitées à 2012 dans Kwikly (`*` ensuite) | Ne pas conclure à une absence/présence sur un périmètre < 2013 sans vérification empirique |
| 3 identifiants patient différents selon la source | `NIR_ANO_17` (PMSI, `KI_CCI_R`/`KI_ECD_R`) ≠ `BEN_NIR_PSA`+`BEN_RNG_GEM` (DCIR) ≠ `BEN_NIR_ANO` (CAUSE_DECES) — aucune table de passage directe dans cet export ; valider le chaînage avant tout croisement inter-source |
| `BEN_DCD_DTE`/`BEN_DCD_AME` — valeur sentinelle | `01-01-1600` (resp. `160001`) = patient encore considéré comme vivant ; toute autre date = date de décès |
| Doublons de transmission APHP/APHM/HCL          | Uniquement pertinent pour les séjours **2005-2017** (remontées corrigées depuis) ; liste complète (~50 FINESS) à récupérer en direct sur la fiche officielle (voir « Documentation officielle en ligne » ci-dessus), pas codée en dur ici |
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
| Filtres qualité PMSI par défaut         | `NIR_RET`/`NAI_RET`/`SEX_RET`/`SEJ_RET`/`FHO_RET`/`PMS_RET` = `'0'` (depuis 2005), `+ DAT_RET = '0'` (depuis 2006), `+ COH_NAI_RET`/`COH_SEX_RET` = `'0'` (depuis 2013) |
| Exclusion transferts inter-établissements (MCO) | `SEJ_TYP <> 'B' OR SEJ_TYP IS NULL` |
| Exclusion doublons de transmission (MCO, 2005-2017 uniquement) | Liste de ~50 FINESS APHP/APHM/HCL — à récupérer en direct sur la fiche officielle (voir ci-dessus), non codée en dur |
| Exclusion GHM/GME en erreur             | `SUBSTR(GRG_GHM,1,2) <> '90'` (MCO) ; `GRG_GME NOT LIKE '90%' OR GME_COD NOT LIKE '90%'` (SSR) |
| Filtres qualité DCIR par défaut         | `DPN_QLF NOT IN (71,72)` et `PRS_DPN_QLP NOT IN (71,72)` (en gérant les `NULL`) ; `CPL_MAJ_TOP <> 2` optionnel (dénombrement) |
| Filtres qualité population (`IR_BEN_R`) | `BEN_CDI_NIR = '00'`, `BEN_NAI_ANN <> '1600'`, `BEN_SEX_COD <> 0` — à appliquer avant tout chaînage ou comptage de patients uniques |
| Parallélisation par millésime           | `future::plan(future::multisession(workers = 4))` (générique — adapter à la machine de l'utilisateur) |
| Persistance locale                      | Jamais d'export local avec identifiants (ID, date, localisation) — voir `points-de-vigilance.md` |
