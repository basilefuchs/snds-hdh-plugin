# Modèle de données — SNDS (Health Data Hub, Oracle)

> **Priorité des sources** : `references/profils/hdh_oracle.md` décrit
> l'environnement réel (mapping validé, pièges, défauts recommandés) et
> **fait foi** en cas de contradiction avec ce document. La documentation
> officielle en ligne du Health Data Hub
> (https://documentation-snds.health-data-hub.fr/, cf. `profils/hdh_oracle.md`
> § « Documentation officielle en ligne ») fait elle-même foi sur les
> filtres/méthodologie et prime sur les deux si divergence constatée.

## Organisation générale — produits du dictionnaire

Le dictionnaire (`references/dictionnaire/`, généré depuis schema-snds du
Health Data Hub, licence MPL-2.0) organise les 196 tables par produit :

| Produit        | Contenu                                             | Nb tables |
|----------------|------------------------------------------------------|-----------|
| DCIR           | Consommation de soins de ville (datamart inter-régimes) | 16     |
| PMSI MCO / SSR / HAD / RIP | Séjours hospitaliers (RIP = psychiatrie) | 65 / 41 / 30 / 27 |
| Causes de décès | Cause médicale de décès (CépiDc)                    | 2         |
| CARTOGRAPHIE_PATHOLOGIES | Cartographie des pathologies (tables individuelles : tops pathologies/ALD) | 4 |
| REFERENTIELS   | Référentiels propres (`IR_BEN_R`, `IR_IMB_R`, `IR_ETM_R`…) | 11 |

Les 631 nomenclatures (tables de valeurs `ORAVAL`, référentiels `ORAREF` dont
`IR_PHA_R`) sont dans `nomenclatures.tsv` ; la colonne `nomenclature` de
`variables.tsv` indique celle qui décode chaque variable.

Les tables PMSI millésimées portent un nom générique avec `aa` en guise de
millésime (ex. `T_MCOaaB`) ; en base Oracle, le nom réel porte l'année sur 2
chiffres (ex. `T_MCO23B` pour 2023, `T_MCO09B` pour 2009). Reconstituer
systématiquement `paste0("T_MCO", aa, "B")` (avec `aa` sur 2 chiffres,
zéro-paddé) avant toute requête.

## DCIR — soins de ville

Clé technique de jointure des tables « flux » DCIR de niveau prestation
jointes à `ER_PRS_F` (9 colonnes) : `FLX_DIS_DTD`, `FLX_TRT_DTD`,
`FLX_EMT_TYP`, `FLX_EMT_NUM`, `FLX_EMT_ORD`, `ORG_CLE_NUM`, `DCT_ORD_NUM`,
`PRS_ORD_NUM`, `REM_TYP_AFF` (exceptions `ER_DCT_F`, `ER_UCD_F`, `ER_LOT_F`,
`ER_TRS_F` : voir `profils/hdh_oracle.md`).

Tables clés : `ER_PRS_F` (en-tête prestation, table pivot), `ER_PHA_F`
(pharmacie), `ER_CAM_F` (actes CCAM en ville), `IR_PHA_R` (référentiel
médicament, catégorie AUTRE), `IR_BEN_R` (référentiel bénéficiaire, catégorie
AUTRE), `ER_GEO_LOC_R` (géolocalisation du professionnel de santé). Détail
des colonnes : voir `profils/hdh_oracle.md`.

Filtres qualité DCIR standard (source : documentation officielle HDH) :
`DPN_QLF NOT IN (71, 72)` **et** `PRS_DPN_QLP NOT IN (71, 72)` (exclusion de
l'activité hospitalière publique en co-remontée), en gérant les `NULL`
explicitement (`IS NULL`/`IS NOT NULL`, un simple `!= 71` les exclut
silencieusement en SQL Oracle) ; exclusion des établissements ex-DG en
facturation directe (`ER_ETE_F.ETE_IND_TAA <> 1 OR IS NULL`, jointure gauche
9 colonnes) ; `CPL_MAJ_TOP <> 2` optionnel, utile pour un dénombrement de
lignes. Détail complet : `profils/hdh_oracle.md`.

## PMSI — séjours hospitaliers

Familles de tables par champ et par lettre (clé technique
`(ETA_NUM, RSA_NUM)` en MCO, `(ETA_NUM, RHA_NUM)` en SSR,
`(ETA_NUM_EPMSI, RHAD_NUM)` en HAD, `(ETA_NUM_EPMSI, RIP_NUM)` en RIP — pas de
colonne `ETA_NUM` en HAD/RIP) :

| Champ | En-tête/chaînage | Diagnostics/GHM/groupage | Actes | DAS |
|---|---|---|---|---|
| MCO | `T_MCO{aa}C` | `T_MCO{aa}B` | `T_MCO{aa}A` | `T_MCO{aa}D` |
| SSR/SMR | `T_SSR{aa}C` | `T_SSR{aa}B` / `T_SSR{aa}GME` | `T_SSR{aa}CCAM` (2009+), `T_SSR{aa}CSARR` (2014+), `T_SSR{aa}CCAR` (CdARR 2009-2013) | `T_SSR{aa}D` (2009+ ; avant : `ASS_DGN_1..20` dans B) |
| HAD | `T_HAD{aa}C` | `T_HAD{aa}B` (DP `DGN_PAL`, `PEC_PAL`) / `T_HAD{aa}GRP` (groupage) | `T_HAD{aa}A`* (2010+) | `T_HAD{aa}D`* (2010+ ; 2007-2009 : `DGN_PAL1..7` dans B) |
| RIP (psychiatrie) | `T_RIP{aa}C` | `T_RIP{aa}RSA` | `T_RIP{aa}CCAM`* (2017+) | `T_RIP{aa}RSAD`* |

Chaînage et filtres qualité de `T_MCO{aa}C`/`T_HAD{aa}C`/`T_RIP{aa}C` et
groupage de `T_HAD{aa}GRP`/`T_RIP{aa}RSA` **validés** via la documentation
officielle HDH (voir `profils/hdh_oracle.md`, sections HAD et RIP). \* Tables
non filtrées : diagnostics/actes détaillés HAD et actes RIP existent dans le
dictionnaire mais leur structure exacte n'a pas encore été vérifiée dans cet
environnement — vérifier les colonnes dans `variables.tsv` avant utilisation
(voir « Comment utiliser le dictionnaire » ci-dessous).

Diagnostics « principaux » selon le champ :

| Champ | Variables diagnostiques | DAS |
|---|---|---|
| MCO | `DGN_PAL` (DP), `DGN_REL` (DR) — table `T_MCO{aa}B` | `ASS_DGN` — table `T_MCO{aa}D` |
| SSR | `FP_PEC` (finalité principale, **2006-2022** : plus codée après le 01/03/2023, réforme SMR), `MOR_PRP` (manifestation morbide principale), `ETL_AFF` (affection étiologique) — table `T_SSR{aa}B` | `DGN_COD` — table `T_SSR{aa}D` (2009+) |

Filtres qualité PMSI standard (source : documentation officielle HDH, à
appliquer sur la table d'en-tête/chaînage `C`) :
`NIR_RET='0' AND NAI_RET='0' AND SEX_RET='0' AND SEJ_RET='0' AND FHO_RET='0'
AND PMS_RET='0'` — disponible depuis 2005 pour MCO/HAD/SSR, mais seulement
**depuis 2007 pour RIP** (exception documentée dans le profil, voir
`profils/hdh_oracle.md` section RIP) ; `+ DAT_RET='0'` (depuis 2006), `+
COH_NAI_RET='0' AND COH_SEX_RET='0'` (depuis 2013, tous champs), `+` exclusion
des `NIR_ANO_17` fictifs (liste dans le profil). Tables d'activité externe
(`*CSTC`) : codes retour propres, voir le profil. MCO uniquement :
exclusion des prestations inter-établissements (PIE) `SEJ_TYP <> 'B' OU NULL`
(colonne de `T_MCO{aa}B`), et
exclusion des doublons de transmission APHP/APHM/HCL (~50 FINESS, **valable
uniquement 2005-2017**, liste à récupérer en direct sur la fiche officielle
plutôt que codée en dur — voir `profils/hdh_oracle.md`). Exclusion GHM/GME
en erreur : `SUBSTR(GRG_GHM,1,2) <> '90'` (MCO) ; SSR 2013+ :
`GRG_GME NOT LIKE '90%'` sur `T_SSR{aa}B` ou `GME_COD NOT LIKE '90%'` sur
`T_SSR{aa}GME` (un seul des deux, pas de `OR`) ; `GHT_NUM <> '99'` (HAD), `SEQ_IND <> 'E'` jusqu'en 2016 + `TYP_GEN_RSA = '0'` depuis
2015 (RIP).

## CAUSE_DECES — mortalité (CépiDc)

`KI_CCI_R` (1 ligne/décès, cause initiale `DCD_CIM_COD`) et `KI_ECD_R`
(1 ligne/cause mentionnée, `ECD_CIM_COD` + rang `ECD_CAU_RNG` — `1` = cause
initiale), reliées entre elles par `DCD_IDT_ENC`. Identifiant de l'individu :
`BEN_IDT_ANO`, relié à `IR_BEN_R.BEN_IDT_ANO` (voir chaînage ci-dessous). Utiliser `KI_CCI_R`
pour une cause de décès unique (mortalité par cause), `KI_ECD_R` pour capter
les causes associées/contributives (ex. comorbidités mentionnées au
certificat).

## CARTOGRAPHIE, nomenclatures, référentiels

- **CARTOGRAPHIE** : tables individuelles de la cartographie des pathologies
  CNAM (`CRTO_CT_*`, 1 ligne par bénéficiaire et par millésime, identifiant
  `BEN_IDT_ANO`, 2015-2023) : démographie (`CRTO_CT_DEP_GN_AAAA`), tops
  pathologies/ALD (`CRTO_CT_IND_GN_AAAA`), résidence (`CRTO_CT_RES_GN_AAAA`) ;
  passage vers le DCIR via `CRTO_CT_IDE_GN` (`BEN_IDT_ANO` ↔
  `BEN_NIR_PSA`+`BEN_RNG_GEM`).
- **Nomenclatures** (tables de valeurs, suffixe `_V`, et référentiels
  `ORAREF`) : correspondance code → libellé. À utiliser pour libeller un
  résultat, pas comme table de faits ; valeurs des petites nomenclatures dans
  `valeurs.tsv`.
- **Référentiels** : les plus utiles en pratique sont `IR_BEN_R`
  (référentiel bénéficiaire — décès, résidence, naissance, table de passage
  des identifiants), `IR_PHA_R` (référentiel médicament — classe ATC,
  CIP13/UCD ; nomenclature ORAREF, colonnes dans `nomenclatures.tsv`) et
  `IR_IMB_R` (référentiel médicalisé — ALD, filtres validés dans
  `profils/hdh_oracle.md`). Les autres (`DA_PRA_R`, `IR_ACS_R`, `IR_ETM_R`,
  `IR_MAT_R`, `IR_MTT_R`, `IR_ORC_R`…) n'ont pas encore d'usage documenté
  dans cet environnement — à explorer via `variables.tsv` au cas par cas.

## Chaînage patient — identifiants et table de passage `IR_BEN_R`

Source : documentation officielle HDH (schéma relationnel SNDS, fiche
bénéficiaire). `IR_BEN_R` sert de table de passage : il porte à la fois
`BEN_NIR_PSA`, `BEN_RNG_GEM`, `BEN_NIR_ANO` et `BEN_IDT_ANO`.

| Source          | Colonne(s) | Rôle |
|------------------|------------|------|
| PMSI             | `NIR_ANO_17` | pseudonyme de l'ouvreur de droit, **égal à `BEN_NIR_PSA`** du DCIR (depuis 2006) |
| DCIR             | `BEN_NIR_PSA` + `BEN_RNG_GEM` | clé de jointure `ER_PRS_F` ↔ `IR_BEN_R`, **pas** un identifiant d'individu |
| Individu (tous SNDS) | `IR_BEN_R.BEN_IDT_ANO` (= `BEN_NIR_ANO` si `BEN_IDT_TOP = 1`) | à utiliser pour compter des patients uniques |
| CAUSE_DECES      | `BEN_IDT_ANO` (et `BEN_NIR_ANO`) | jointure `KI_CCI_R.BEN_IDT_ANO = IR_BEN_R.BEN_IDT_ANO` |

1. **PMSI ↔ DCIR** : `NIR_ANO_17 = BEN_NIR_PSA`. Ne pas chaîner sur le rang
   PMSI (`RNG_NAI`, qualité insuffisante). La jointure peut ramener plusieurs
   `BEN_RNG_GEM` pour un même pseudonyme : dédupliquer ou départager, et
   quantifier les `NIR_ANO_17` sans correspondance.
2. **Patients uniques** : un même individu peut porter plusieurs
   `BEN_NIR_PSA` (un par ouvreur de droit) et un `BEN_NIR_PSA` peut couvrir
   plusieurs `BEN_RNG_GEM` (ayants droit, jumeaux, régimes hors RG).
   Compter sur `BEN_NIR_PSA`+`BEN_RNG_GEM` surestime les effectifs : joindre
   `IR_BEN_R` sur `(BEN_NIR_PSA, BEN_RNG_GEM)` et compter `BEN_IDT_ANO`, après
   les filtres qualité population du profil.
3. **Causes de décès ↔ SNDS** : `KI_CCI_R.BEN_IDT_ANO = IR_BEN_R.BEN_IDT_ANO`,
   puis `IR_BEN_R.BEN_NIR_PSA` vers le DCIR ou `NIR_ANO_17` du PMSI.
   L'appariement est incomplet : contrôler `DCD_IDT_TOP` (apparié avec
   `IR_BEN_R`) et signaler la perte. `KI_CCI_R` ↔ `KI_ECD_R` : `DCD_IDT_ENC`.
4. **CARTOGRAPHIE** : passage `BEN_IDT_ANO` ↔ `BEN_NIR_PSA`+`BEN_RNG_GEM` via
   `CRTO_CT_IDE_GN`.

Pour toute analyse croisant plusieurs sources, le chaînage reste une étape à
part entière du protocole : documenter la méthode, quantifier la perte et les
correspondances multiples.

Qualité du chaînage intra-PMSI : appliquer les filtres qualité PMSI standard
(voir « Filtres qualité PMSI standard » ci-dessus : `*_RET`, `+ DAT_RET`
depuis 2006, `+ COH_NAI_RET`/`COH_SEX_RET` depuis 2013, NIR fictifs) avant
tout comptage de patients uniques.

## Raccourcis de classification usuels

- Séance / HDJ / HC (MCO) :
  `case_when(substr(GRG_GHM,1,2) == "28" ~ "Séance", SEJ_NBJ == 0 ~ "HDJ", .default = "HC")`
  (pattern validé).
- Racine de GHM (5 caractères) : `substr(GRG_GHM, 1, 5)` ; CMD (2 car.) :
  `substr(GRG_GHM, 1, 2)`.
- GHM en erreur : `substr(GRG_GHM, 1, 2) != "90"`. GME (SSR, 2013+) en
  erreur : `GRG_GME` (`T_SSR{aa}B`) ou `GME_COD` (`T_SSR{aa}GME`) commençant
  par `"90"` — un seul des deux, chacun sur sa table.
- Actes CCAM en ville : code CCAM = `CAM_PRS_IDE` (`CAM_ACT_COD` est le code
  activité, 1 caractère) ; un acte = triplet `(CAM_PRS_IDE, CAM_ACT_COD,
  CAM_TRT_PHA)`, pas `CAM_PRS_IDE` seul. En SSR : `CCAM_ACT` + `CCAM_COD_ACT`
  + `CCAM_PHA_ACT` (`T_SSR{aa}CCAM`).
- Chaînage mère-enfant (MCO) : `NIR_ANO_MAM` (2013-2018) puis `ID_MAM_ENF`
  (2019+), table `T_MCO{aa}C`.

## Filtres CIM-10/CCAM/ATC : `substr`/`%in%` ou `REGEXP_LIKE` Oracle

- Listes simples de codes : `substr(DGN_PAL, 1, 3) %in% c("E10", ...)`.
- Motifs complexes ou multi-racines : `REGEXP_LIKE` en SQL brut via `sql()`
  (fonction Oracle) :
  `filter(sql("REGEXP_LIKE(CDC_ACT, '^[A-Z]{3}L')"))` (PMSI),
  `filter(sql("REGEXP_LIKE(CAM_PRS_IDE, '^[A-Z]{3}L')"))` (ville) ou
  `filter(sql("REGEXP_LIKE(PHA_ATC_CLA, '^B01|^N06AB')"))` côté pharmacie.
- Le style historique `glue()` + chaîne SQL Oracle brute (`dbGetQuery(conn,
  glue(query, an = ..., table = ...))`) reste répandu dans des scripts R
  existants : à savoir reconnaître et relire si l'utilisateur colle un script
  existant dans cette convention, mais ce n'est **pas** le style de
  génération par défaut de cette skill (voir SKILL.md, étape 5 — dbplyr
  lazy + `sql()` est le défaut).

## Pièges classiques (à vérifier / signaler systématiquement)

1. **Année PMSI = année de sortie** : un séjour à cheval compte sur le
   millésime de sortie. L'incidence par date d'entrée nécessite les dates
   réelles (`EXE_SOI_DTD`/`EXE_SOI_DTF`), **absentes** de `T_MCO{aa}C` et
   `T_SSR{aa}C` avant 2009 (ORA-00904) : pour 2006-2008, n'utiliser que le
   mois/année de sortie (`SOR_ANN`/`SOR_MOI`) et écrire une forme de requête
   par période. `SOR_ANN`/`SOR_MOI` disparaissent de `T_MCO{aa}C` après 2018
   (`ENT_ANN`/`ENT_MOI` à partir de 2019 ; toujours présents dans `B`).
2. **Séances (MCO)** : GHM commençant par `28` — un patient dialysé peut
   générer des dizaines de « séjours »/an ; toujours demander l'inclusion.
3. **GHM/GME en erreur** : exclusion par défaut (`90*`).
4. **Chaînage et patients uniques** : `NIR_ANO_17` (PMSI) = `BEN_NIR_PSA`
   (DCIR), mais l'individu est `IR_BEN_R.BEN_IDT_ANO` (clé aussi des causes
   de décès) — compter sur `BEN_NIR_PSA`+`BEN_RNG_GEM` surestime les
   patients. Voir « Chaînage patient » ; le chaînage inter-source est une
   étape de protocole à part entière, pas une jointure anodine.
5. **`DPN_QLF`/`PRS_DPN_QLP`/filtres qualité DCIR sur colonnes potentiellement
   `NULL`** : un simple `col != valeur` exclut silencieusement les `NULL` en
   SQL Oracle — utiliser `is.na(col) | col != valeur` quand la colonne peut
   être vide. De plus, Oracle trie les `NULL` en **dernier** dans un
   `ORDER BY` (SAS les traite comme valeur minimale) — éviter de trier côté
   Oracle sur une colonne à `NULL`, reporter le tri après `collect()`.
6. **Doublons de transmission** : `ETA_NUM` APHP/APHM/HCL — à exclure, mais
   **uniquement pour les séjours 2005-2017** (remontées corrigées depuis) ;
   ne pas appliquer ce filtre hors de cette période, et récupérer la liste
   complète des FINESS concernés en direct sur la fiche officielle plutôt
   que de se fier à une liste partielle codée en dur.
7. **Évolutions de codage et de structure de table** : ex. `EXT_PMSI`
   (actes CCAM MCO) absent avant 2015 — deux formes de requête selon le
   millésime ; plus généralement, toujours croiser la période demandée avec
   les millésimes de `variables.tsv` (`debut`, `fin`, `absente`) avant de
   figer une requête pluriannuelle.
8. **Tables DCIR continues** : les millésimes déclarés d'une variable DCIR
   (`debut`/`fin`) disent quand elle a été créée ou supprimée, pas si elle est
   effectivement alimentée chaque année. Pour une variable récente ou peu
   utilisée, vérifier empiriquement (`COUNT(*)` par année de `FLX_DIS_DTD`).
9. **Fuseau horaire Oracle/R** : sans `Sys.setenv(TZ=...)` et
   `Sys.setenv(ORA_SDTZ=...)` posés à `Europe/Paris` AVANT `dbConnect()`
   (`ORA_SDTZ` est lu à l'ouverture de session), les dates remontées par `ROracle` peuvent être décalées d'un jour
   (conversion UTC) — critique sur les dates de décès notamment.
10. **Statistiques après matérialisation** : toute table temporaire créée et
    réutilisée doit avoir ses statistiques Oracle calculées — en R,
    `copy_to()`/`compute()` avec `analyze = TRUE` (défaut) et `indexes = ...`,
    ou `DBMS_STATS.GATHER_TABLE_STATS` après un `CREATE TABLE`
    (`%m_stats_table()` est l'équivalent côté SAS) — sinon jointures suivantes
    très lentes.
11. **Volumétrie de `ER_PRS_F`** : cette table (et celles jointes dessus —
    `ER_PHA_F`, `ER_CAM_F`...) est trop volumineuse pour être interrogée en
    une seule requête au-delà de quelques mois. Batcher systématiquement sur
    `FLX_DIS_DTD` (date de flux technique, un batch par mois), en filtrant
    les DEUX côtés de la jointure sur ce même `FLX_DIS_DTD` avant de joindre
    sur la clé composite à 9 colonnes. Piège associé : `FLX_DIS_DTD`
    (date de remontée) n'est **pas** `EXE_SOI_DTD` (date de soin réelle) —
    une prestation de fin de période clinique demandée peut être remontée
    dans un flux ultérieur. La boucle de flux doit donc courir jusqu'à la
    fin de la période clinique **plus une marge**, chaque batch filtrant
    ensuite précisément sur `EXE_SOI_DTD` pour ne garder que la période
    demandée — marge officielle : au moins 5 mois de données après la
    période (6 flux), 12 mois pour une extraction exhaustive, jamais plus de
    24 (voir `points-de-vigilance.md`). Pattern de code validé :
    `template.R`, Pattern C.

## Comment utiliser le dictionnaire

Fichiers TSV dans `references/dictionnaire/` (colonnes décrites dans son
`README.md`) : `tables.tsv`, `variables.tsv`, `jointures.tsv`,
`nomenclatures.tsv`, `valeurs.tsv`. Recherche par `grep` / `awk -F'\t'`,
jamais de lecture intégrale — exemples de commandes dans `SKILL.md`, étape 2.

Les pièges propres à l'environnement (disponibilité exacte des schémas…)
sont dans `profils/hdh_oracle.md`, qui fait foi.

## Documentation officielle en ligne (référence vivante)

En complément du dictionnaire (structure des tables) et de ce
document (modèle générique), la documentation collaborative officielle du
Health Data Hub — https://documentation-snds.health-data-hub.fr/ — est une
référence vivante à consulter via WebFetch quand elle est disponible,
en particulier pour tout ce qui n'est pas (encore) capturé statiquement ici :
les ~80 fiches thématiques (`snds/fiches/`, ex. chaînage mère-enfant,
cartographie des pathologies, ALD), et la section `snds/tables/` (schéma
officiel, alimentant https://health-data-hub.shinyapps.io/dico-snds/) à
croiser avec le dictionnaire en cas de doute (même source schema-snds). Le détail des deux fiches déjà exploitées
pour bâtir ce document (filtres recommandés, valeurs manquantes) est dans
`profils/hdh_oracle.md`, section « Documentation officielle en ligne ».

Deux ressources complémentaires, non autoritatives (voir `SKILL.md` § « Ressources
complémentaires » pour leur usage précis) : le [forum d'entraide](https://entraide.health-data-hub.fr/)
(communauté active, utile en dépannage sur un comportement de table ou un
message d'erreur Oracle non documenté ailleurs) et la
[cartographie de l'écosystème SNDS](https://ecosysteme-snds.health-data-hub.fr/)
(annuaire de projets/algorithmes déjà validés, à consulter pour sourcer une
définition de cohorte/pathologie à l'étape 3 du workflow).
