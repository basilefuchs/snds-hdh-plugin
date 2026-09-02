# ==============================================================================
# Indicateur : <titre court de l'indicateur / de la question>
# Question   : <question en langage naturel de l'utilisateur>
# Protocole  : <résumé 1 ligne : population, exclusions, critère de jugement>
# Source     : <si indicateur documenté : référence biblio, DOI>          [optionnel]
# Catégorie  : <ex. 02_casemix_patientele, 04_efficience_capacitaire>     [optionnel]
# Fiche      : <chemin de la fiche indicateur si elle existe>             [optionnel]
# ==============================================================================

# ==== PROFIL DE BASE (mapping utilisé — profils/hdh_oracle.md) =====
# Base       : SNDS via le Health Data Hub — Oracle, interrogé en dbplyr
# Connexion  : dbConnect(dbDriver("Oracle"), dbname = "IPIAMPR2.WORLD")
# Tables     : PMSI = tables suffixées par l'année de sortie (2 chiffres),
#              pas de schéma millésimé (ex. T_MCO24C, T_MCO24B, T_MCO24A, T_MCO24D)
#              DCIR = tables continues (ER_PRS_F, ER_CAM_F, ER_PHA_F...), filtrées
#              par date de soins (EXE_SOI_DTD) ou par flux (FLX_DIS_DTD)
#
# Séjour MCO (1 ligne)         : T_MCO{aa}B, clé (ETA_NUM, RSA_NUM)
# Chaînage / qualité MCO       : T_MCO{aa}C (mêmes clés ETA_NUM, RSA_NUM)
# Clé de chaînage patient PMSI : NIR_ANO_17 (tous champs PMSI)
# Clé de chaînage patient DCIR : BEN_NIR_PSA + BEN_RNG_GEM (BEN_NIR_PSA seul ne
#   distingue pas les ayants droit d'un même NIR). NIR_ANO_17 et BEN_NIR_PSA
#   sont directement comparables (même NIR crypté) pour le chaînage PMSI <-> DCIR.
# Clé de chaînage CAUSE_DECES  : BEN_NIR_ANO — 3e identifiant, DISTINCT des deux
#   précédents (pas de comparaison directe) : voir modele-donnees.md pour la
#   table de passage avant tout chaînage MCO/DCIR <-> causes de décès.
# GHM (6 car) / CMD (2 car)    : GRG_GHM / substr(GRG_GHM, 1, 2)
# Géo. résidence patient (DCIR): BEN_RES_COM / BEN_RES_DPT (sur ER_PRS_F)
# Géo. professionnel de santé  : ER_GEO_LOC_R (PAS ER_GEO_LOC_F), clé NUM_PS —
#   c'est la localisation du PS exécutant, PAS celle du patient
# ==========================================
# NB : lister ci-dessus UNIQUEMENT les éléments réellement utilisés par le script,
#      vérifiés dans le dictionnaire (dossier dictionnaire/Kwikly, ou
#      index-tables.csv pour trouver la bonne page de détail).

library(ROracle)
library(dplyr)
library(dbplyr)
library(purrr)
# library(ggplot2)   # si graphique demandé

# ==== PARAMÈTRES ====
annees     <- 2021:2024                                # années PMSI (année de sortie)
an         <- sprintf("%02d", annees %% 100)            # suffixe table PMSI (2 chiffres)
codes_cim3 <- c("E10", "E11", "E12", "E13", "E14")      # codes CIM-10 (3 caractères)

SEUIL <- 11   # secret statistique SNDS : effectif non diffusable si < SEUIL
              # (nécessaire seulement si finalité = diffusion externe/publication —
              # cf. clarifications.md bloc 0 ; sans objet pour un dénombrement interne)

# Clé de jointure composite DCIR (ER_PRS_F <-> ER_CAM_F/ER_PHA_F/ER_BIO_F/...) —
# les 9 colonnes techniques identifiant une ligne de décompte
DCIR_JOIN_KEY <- c(
  "FLX_DIS_DTD", "FLX_TRT_DTD", "FLX_EMT_TYP", "FLX_EMT_NUM", "FLX_EMT_ORD",
  "ORG_CLE_NUM", "DCT_ORD_NUM", "PRS_ORD_NUM", "REM_TYP_AFF"
)

# ==== CONNEXION (profil Health Data Hub — cf. profils/hdh_oracle.md) ====
.drv <- dbDriver("Oracle")
options(connectionObserver = NULL)
conn <- dbConnect(.drv, dbname = "IPIAMPR2.WORLD")

# Fuseau posé côté R ET côté client Oracle : sans ORA_SDTZ, une date/heure de
# soin ou de décès remontée par ROracle peut changer de jour (conversion UTC).
Sys.setenv(TZ = "Europe/Paris")
Sys.setenv(ORA_SDTZ = "Europe/Paris")

# ==== RÉFÉRENTIELS (si besoin de libellés) ====
# ref_etab <- tbl(conn, I(paste0("T_MCO", an[length(an)], "E"))) %>%   # dernier millésime
#   select(ETA_NUM, RS) %>%
#   distinct() %>%
#   collect()

# ==== EXTRACTION ====
# Pattern A (par défaut) — agrégats PAR ANNÉE PMSI : map_dfr + collect() par
# millésime. L'agrégation est faite par Oracle, seul le résultat agrégé est rapatrié.
resultat_annuel <- purrr::map2_dfr(annees, an, function(annee, an) {

  mco_c <- tbl(conn, I(paste0("T_MCO", an, "C")))   # chaînage / entête séjour
  mco_b <- tbl(conn, I(paste0("T_MCO", an, "B")))   # séjour (GHM, DP, DR...)

  mco_c |>
    # -- Liability MCO (qualité de chaînage) --
    filter(
      NIR_RET == '0', NAI_RET == '0', SEX_RET == '0', SEJ_RET == '0',
      FHO_RET == '0', PMS_RET == '0', DAT_RET == '0',            # DAT_RET absent avant 2006
      !ETA_NUM %in% c('130786049', '690781810', '750712184')     # doublons APHP/APHM/HCL
    ) |>
    inner_join(mco_b, by = c("ETA_NUM", "RSA_NUM")) |>
    filter(
      substr(DGN_PAL, 1, 3) %in% codes_cim3,          # inclusion : position du diagnostic
      #   variante DP ou DR : | substr(DGN_REL, 1, 3) %in% codes_cim3
      !GRG_RET %in% c('076', '077', '081', '102'),     # groupage en erreur
      substr(GRG_GHM, 1, 2) != "90"                    # séjours en erreur (CMD 90)
    ) |>
    mutate(sejour_id = paste0(ETA_NUM, "-", RSA_NUM)) |>
    summarise(
      nb_sejours  = n_distinct(sejour_id),
      nb_patients = n_distinct(NIR_ANO_17)
    ) |>
    collect() |>
    mutate(annee = annee)
})

# Pattern B — patients uniques SUR TOUTE LA PÉRIODE : la déduplication
# inter-années impose d'empiler les requêtes lazy AVANT le n_distinct
# (on ne peut pas sommer des comptes distincts annuels).
requete_annee <- function(an) {
  mco_c <- tbl(conn, I(paste0("T_MCO", an, "C")))
  mco_b <- tbl(conn, I(paste0("T_MCO", an, "B")))

  mco_c |>
    filter(
      NIR_RET == '0', NAI_RET == '0', SEX_RET == '0', SEJ_RET == '0',
      FHO_RET == '0', PMS_RET == '0', DAT_RET == '0',
      !ETA_NUM %in% c('130786049', '690781810', '750712184')
    ) |>
    inner_join(mco_b, by = c("ETA_NUM", "RSA_NUM")) |>
    filter(
      substr(DGN_PAL, 1, 3) %in% codes_cim3,
      !GRG_RET %in% c('076', '077', '081', '102'),
      substr(GRG_GHM, 1, 2) != "90"
    ) |>
    select(NIR_ANO_17)
}

nb_patients_periode <- an |>
  purrr::map(requete_annee) |>
  purrr::reduce(union_all) |>                 # UNION exécuté par Oracle
  summarise(nb_patients = n_distinct(NIR_ANO_17)) |>
  collect()

# -- Dérivation classique : type de séjour (Séance / HDJ / HC) -----------------
# mutate(type_sejour = case_when(
#   substr(GRG_GHM, 1, 2) == "28" ~ "Séance",
#   substr(GRG_GHM, 1, 2) != "28" & SEJ_NBJ == 0 ~ "HDJ",
#   .default = "HC"
# ))

# -- Variante : inclusion sur DAS (diagnostics associés significatifs) ---------
# ident_das <- tbl(conn, I(paste0("T_MCO", an1, "D"))) |>
#   filter(substr(ASS_DGN, 1, 3) %in% codes_cim3) |>
#   distinct(RSA_NUM, ETA_NUM)
# mco_c |> semi_join(ident_das, by = c("RSA_NUM", "ETA_NUM"))

# -- Variante : critère CCAM côté PMSI (table des actes) -----------------------
# actes_cible <- tbl(conn, I(paste0("T_MCO", an1, "A"))) |>
#   filter(sql("REGEXP_LIKE(CDC_ACT, '^[A-Z]{3}L')")) |>   # ex. lettre-clé technique
#   distinct(RSA_NUM, ETA_NUM)

# -- Variante : même critère CCAM côté DCIR (ER_CAM_F, clé composite 9 col.) ---
# actes_dcir <- tbl(conn, I("ER_PRS_F")) |>
#   filter(CPL_MAJ_TOP < 2, DPN_QLF != 71) |>              # filtres qualité DCIR
#   inner_join(tbl(conn, I("ER_CAM_F")), by = DCIR_JOIN_KEY) |>
#   filter(sql("REGEXP_LIKE(CAM_ACT_COD, '^[A-Z]{3}L')"))

# -- Variante : critère médicamenteux DCIR (classe ATC, ER_PHA_F + IR_PHA_R) ---
# IR_PHA_R est un référentiel PRODUIT non millésimé (pas de suffixe année).
# cip_cible <- tbl(conn, I("IR_PHA_R")) |>
#   filter(sql("REGEXP_LIKE(PHA_ATC_CLA, '^N06AB')")) |>   # ex. ISRS
#   filter(!is.na(PHA_CIP_C13)) |>
#   distinct(PHA_CIP_C13)
# delivrances <- tbl(conn, I("ER_PRS_F")) |>
#   filter(CPL_MAJ_TOP < 2, DPN_QLF != 71) |>
#   inner_join(tbl(conn, I("ER_PHA_F")), by = DCIR_JOIN_KEY) |>
#   inner_join(cip_cible, by = c("PHA_PRS_C13" = "PHA_CIP_C13")) |>
#   transmute(anonyme = BEN_NIR_PSA, rang = BEN_RNG_GEM, dte_exe = EXE_SOI_DTD)
# NB volumétrie DCIR : au-delà de quelques mois, préférer itérer par flux mensuel
# (FLX_DIS_DTD) avec purrr::future_map_dfr — cf. snds-brouillon.R pour
# l'idiome complet (une connexion Oracle par worker).

# -- Variante : motif CIM-10 complexe (Oracle REGEXP_LIKE, pas REGEXP_SIMILAR) --
# filter(sql("REGEXP_LIKE(DGN_PAL, '^(F0[0-3]|G30|A810|B220)')"))

# -- Variante : analyse par site géographique -----------------------------------
# Résidence du PATIENT (DCIR) : déjà sur ER_PRS_F (BEN_RES_COM / BEN_RES_DPT).
# Localisation du PROFESSIONNEL DE SANTÉ exécutant : ER_GEO_LOC_R, clé NUM_PS
# (le professionnel, PAS le patient) :
# geo_ps <- tbl(conn, I("ER_GEO_LOC_R"))
# actes_dcir |> inner_join(geo_ps, by = "NUM_PS")   # géo. du lieu de soins, pas du domicile

# ==== SECRET STATISTIQUE (SEUIL = 11) ====
# À vérifier AVANT toute impression/export de résultat agrégé, dès que la
# finalité (bloc 0 des clarifications) implique une diffusion externe.
verifier_seuil <- function(df, col_effectif, seuil = SEUIL) {
  n_masque <- sum(df[[col_effectif]] < seuil, na.rm = TRUE)
  if (n_masque > 0) {
    warning(sprintf(
      "%d cellule(s) < %d (%s) - à regrouper sous 'Autre' avant toute diffusion externe.",
      n_masque, seuil, col_effectif
    ))
  }
  df
}

resultat_annuel <- resultat_annuel |> verifier_seuil("nb_patients")

# ==== FLOWCHART D'ATTRITION (systématique) ====
# Décompte des séjours à chaque étape du protocole : rend l'analyse auditable.
# Adapter les étapes au protocole réel (mêmes filtres, même ordre que l'extraction).
attrition <- purrr::map2_dfr(annees, an, function(annee, an) {

  mco_c <- tbl(conn, I(paste0("T_MCO", an, "C")))
  mco_b <- tbl(conn, I(paste0("T_MCO", an, "B")))

  e1 <- mco_c |> inner_join(mco_b, by = c("ETA_NUM", "RSA_NUM")) |>
    filter(substr(DGN_PAL, 1, 3) %in% codes_cim3)
  e2 <- e1 |> filter(
    NIR_RET == '0', NAI_RET == '0', SEX_RET == '0', SEJ_RET == '0',
    FHO_RET == '0', PMS_RET == '0', DAT_RET == '0'
  )
  e3 <- e2 |> filter(!ETA_NUM %in% c('130786049', '690781810', '750712184'))
  e4 <- e3 |> filter(!GRG_RET %in% c('076', '077', '081', '102'), substr(GRG_GHM, 1, 2) != "90")

  purrr::imap_dfr(
    list("1. Sejours DP cible"           = e1,
         "2. chainage/qualite (liability)" = e2,
         "3. hors doublons etablissement" = e3,
         "4. hors GHM en erreur"          = e4),
    function(req, etape) {
      req |> summarise(nb_sejours = n()) |> collect() |> mutate(etape = etape)
    }
  ) |>
    mutate(annee = annee)
})

attrition <- attrition |>
  group_by(annee) |>
  mutate(pct_perdu = round(100 * (lag(nb_sejours) - nb_sejours) / lag(nb_sejours), 1)) |>
  ungroup() |>
  select(annee, etape, nb_sejours, pct_perdu)

# ==== RÉSULTAT ====
attrition |> arrange(annee, etape) |> print(n = Inf)   # à reporter dans la note méthodologique
resultat_annuel |> arrange(annee) |> print()
print(nb_patients_periode)

# ==== VISUALISATION (si demandée) ====
# ggplot(resultat_annuel, aes(x = annee, y = nb_patients)) +
#   geom_point() + geom_smooth(se = FALSE, method = "loess") +
#   scale_x_continuous(breaks = annees) +
#   theme_minimal()

# ==== EXPORT (décommenter si besoin) ====
# ⚠️ Règle SNDS : ne jamais persister en local un fichier contenant des
# identifiants potentiels (ID patient, date de soin, localisation fine) —
# seuls des AGRÉGATS (déjà vérifiés par verifier_seuil() ci-dessus) sortent.
# readr::write_csv(resultat_annuel, "resultat_annuel.csv")

dbDisconnect(conn)

# ==============================================================================
# Patterns dbplyr/Oracle — rappels
# - Tables : tbl(conn, I("NOM_TABLE")) — PMSI suffixé par année (2 chiffres),
#   DCIR/référentiels non millésimés (pas de schéma comme sur le portail ATIH).
# - substr(x, 1, 3) -> SUBSTR pour les listes simples ; motifs complexes :
#   filter(sql("REGEXP_LIKE(col, '<regex>')")) — Oracle utilise REGEXP_LIKE,
#   PAS REGEXP_SIMILAR (spécifique Teradata).
# - %in% sur petit vecteur -> IN (...) ; longues listes de codes : copy_to() +
#   semi_join sur table temporaire (penser à l'indexation Oracle si la table
#   est matérialisée : %m_stats_table(nom_table=...) côté SAS après un
#   dbSendStatement/CREATE TABLE).
# - n_distinct(x) -> COUNT(DISTINCT x). Pas d'identifiant séjour unique en
#   PMSI/SNDS : construire une clé composite via paste0(ETA_NUM, "-", RSA_NUM)
#   plutôt que n_distinct(x, y) (traduction SQL multi-colonnes fragile).
# - collect() : jamais sur une table de séjours/prestations entière, toujours
#   après agrégation.
# - DCIR volumineux et non millésimé : filtrer par date (EXE_SOI_DTD) ou par
#   flux mensuel (FLX_DIS_DTD) plutôt que de tout rapatrier ; au-delà de
#   quelques mois, itérer par flux avec purrr::future_map_dfr (une connexion
#   Oracle PAR WORKER, cf. snds-brouillon.R).
# - Trois identifiants patient DISTINCTS selon la source (PMSI: NIR_ANO_17,
#   DCIR: BEN_NIR_PSA+BEN_RNG_GEM, CAUSE_DECES: BEN_NIR_ANO) — vérifier
#   modele-donnees.md avant tout chaînage inter-sources.
# - Contrôle du SQL généré : requete |> show_query().
# ==============================================================================
