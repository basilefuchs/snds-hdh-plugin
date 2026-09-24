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
# Connexion  : bloc « Connexion » du profil actif (profils/hdh_oracle.md)
# Tables     : PMSI = tables suffixées par l'année de sortie (2 chiffres),
#              pas de schéma millésimé (ex. T_MCO24C, T_MCO24B, T_MCO24A, T_MCO24D)
#              DCIR = tables continues (ER_PRS_F, ER_CAM_F, ER_PHA_F...), filtrées
#              par date de soins (EXE_SOI_DTD) ou par flux (FLX_DIS_DTD)
#
# Séjour MCO (RSA, 1 ligne)    : T_MCO{aa}B, clé (ETA_NUM, RSA_NUM)
# Chaînage / qualité MCO       : T_MCO{aa}C (mêmes clés ETA_NUM, RSA_NUM)
# Pseudonyme patient PMSI      : NIR_ANO_17 (tous champs PMSI) = BEN_NIR_PSA du DCIR
# Jointure DCIR -> référentiel : BEN_NIR_PSA + BEN_RNG_GEM (clé de IR_BEN_R, PAS un
#   identifiant d'individu : un individu peut porter plusieurs BEN_NIR_PSA)
# Individu (tous SNDS)         : IR_BEN_R.BEN_IDT_ANO ; causes de décès reliées par
#   KI_CCI_R.BEN_IDT_ANO = IR_BEN_R.BEN_IDT_ANO — voir modele-donnees.md,
#   section « Chaînage patient », avant tout rapprochement inter-sources.
# GHM (6 car) / CMD (2 car)    : GRG_GHM / substr(GRG_GHM, 1, 2)
# Géo. résidence patient (DCIR): BEN_RES_COM / BEN_RES_DPT (sur ER_PRS_F)
# Géo. professionnel de santé  : ER_GEO_LOC_R (PAS ER_GEO_LOC_F), clé NUM_PS =
#   ER_PRS_F.PFS_EXE_NUM (exécutant) ou PFS_PRE_NUM (prescripteur) —
#   c'est la localisation du PS, PAS celle du patient
# ==========================================
# NB : lister ci-dessus UNIQUEMENT les éléments réellement utilisés par le script,
#      vérifiés dans le dictionnaire (variables.tsv), millésimes compris.
# Dictionnaire : schema-snds (Health Data Hub, MPL-2.0), commit <SOURCE.txt>

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

# NIR_ANO_17 fictifs (documentation officielle HDH) : à exclure avant tout
# comptage de patients, sinon chaque valeur fictive compte comme un patient.
NIR_FICTIFS <- c("xxxxxxxxxxxxxxxxx", "XXXXXXXXXXXXXXXXD", "BXXXXXXXXXXXXXXXX",
                 "XXXXXXXXXXXXXXXXS", "XXXXXXXXXXXXXXXXE")

# Clé de jointure composite DCIR (ER_PRS_F <-> ER_CAM_F/ER_PHA_F/ER_BIO_F/ER_ETE_F...) —
# les 9 colonnes techniques identifiant une ligne de prestation.
# Exception : ER_DCT_F (niveau décompte) n'a pas PRS_ORD_NUM et REM_TYP_AFF n'y
# est documenté qu'en 2006 — voir modele-donnees.md.
DCIR_JOIN_KEY <- c(
  "FLX_DIS_DTD", "FLX_TRT_DTD", "FLX_EMT_TYP", "FLX_EMT_NUM", "FLX_EMT_ORD",
  "ORG_CLE_NUM", "DCT_ORD_NUM", "PRS_ORD_NUM", "REM_TYP_AFF"
)

# Littéral DATE Oracle : dbplyr traduit une date R en simple chaîne '2020-01-01',
# que Oracle convertit selon NLS_DATE_FORMAT (erreur ORA-01861 ou filtre faux).
# Toujours écrire les bornes de date avec !!ora_date(d) dans filter().
ora_date <- function(d) dbplyr::sql(sprintf("DATE '%s'", format(as.Date(d), "%Y-%m-%d")))

# ==== CONNEXION (profil Health Data Hub — cf. profils/hdh_oracle.md) ====
# Fuseau posé AVANT l'ouverture de session : ORA_SDTZ est lu par le client
# Oracle à la connexion ; posé après dbConnect(), il est sans effet et une date
# de soin ou de décès remontée par ROracle peut changer de jour (conversion UTC).
Sys.setenv(TZ = "Europe/Paris")
Sys.setenv(ORA_SDTZ = "Europe/Paris")
.drv <- dbDriver("Oracle")
options(connectionObserver = NULL)
conn <- dbConnect(.drv, dbname = "IPIAMPR2.WORLD")

# ==== RÉFÉRENTIELS (si besoin de libellés) ====
# ref_etab <- tbl(conn, I(paste0("T_MCO", an[length(an)], "E"))) |>   # dernier millésime
#   select(ETA_NUM, SOC_RAI) |>                                        # raison sociale
#   distinct() |>
#   collect()

# ==== EXTRACTION ====
# Étapes du protocole, dans l'ORDRE de l'extraction ET du flowchart d'attrition
# (une seule définition, réutilisée par les deux : l'attrition décrit ainsi
# exactement le protocole exécuté).
etapes_mco <- function(an) {
  mco_c <- tbl(conn, I(paste0("T_MCO", an, "C")))   # chaînage / codes retour
  mco_b <- tbl(conn, I(paste0("T_MCO", an, "B")))   # séjour (GHM, DP, DR, SEJ_TYP...)

  # 0. population brute : séjours MCO de l'année
  e0 <- mco_c |> inner_join(mco_b, by = c("ETA_NUM", "RSA_NUM"))
  # 1. qualité de chaînage (source : documentation officielle HDH) --
  #    COH_NAI_RET/COH_SEX_RET disponibles depuis 2013 uniquement ; retirer ces
  #    2 conditions si le protocole remonte avant 2013.
  e1 <- e0 |> filter(
    NIR_RET == '0', NAI_RET == '0', SEX_RET == '0', SEJ_RET == '0',
    FHO_RET == '0', PMS_RET == '0', DAT_RET == '0',            # DAT_RET absent avant 2006
    COH_NAI_RET == '0', COH_SEX_RET == '0',                    # depuis 2013 seulement
    !NIR_ANO_17 %in% NIR_FICTIFS
    #   Doublons de transmission APHP/APHM/HCL : NE S'APPLIQUE QU'AUX SÉJOURS
    #   2005-2017 (remontées corrigées depuis). Si le protocole couvre cette
    #   période, récupérer la liste à jour des FINESS sur la fiche officielle
    #   (voir profils/hdh_oracle.md) plutôt que la coder en dur :
    #   !ETA_NUM %in% c(<liste FINESS 2023-12-11_synthese_filtres_snds_v1>)
  )
  # 2. hors prestations inter-établissements (PIE, séjours de type B) -- SEJ_TYP
  #    est dans T_MCO{aa}B : filtre appliqué APRÈS la jointure.
  e2 <- e1 |> filter(SEJ_TYP != 'B' | is.na(SEJ_TYP))
  # 3. inclusion : position du diagnostic
  #    variante DP ou DR : | substr(DGN_REL, 1, 3) %in% codes_cim3
  e3 <- e2 |> filter(substr(DGN_PAL, 1, 3) %in% codes_cim3)
  # 4. hors GHM en erreur (CMD 90)
  e4 <- e3 |> filter(substr(GRG_GHM, 1, 2) != "90")

  list("0. Sejours MCO (population brute)" = e0,
       "1. Qualite du chainage"            = e1,
       "2. Hors prestations inter-etab."   = e2,
       "3. DP cible"                       = e3,
       "4. Hors GHM en erreur"             = e4)
}

# Pattern A (par défaut) — agrégats PAR ANNÉE PMSI : map_dfr + collect() par
# millésime. L'agrégation est faite par Oracle, seul le résultat agrégé est rapatrié.
resultat_annuel <- purrr::map2_dfr(annees, an, function(annee, an) {
  etapes <- etapes_mco(an)
  etapes[[length(etapes)]] |>
    mutate(sejour_id = paste0(ETA_NUM, "-", RSA_NUM)) |>
    summarise(
      nb_sejours  = n_distinct(sejour_id),
      nb_patients = n_distinct(NIR_ANO_17)   # pseudonymes PMSI ; individus au sens
                                             # strict : passer par IR_BEN_R.BEN_IDT_ANO
    ) |>
    collect() |>
    mutate(annee = annee)
})

# Pattern B — patients uniques SUR TOUTE LA PÉRIODE : la déduplication
# inter-années impose d'empiler les requêtes lazy AVANT le n_distinct
# (on ne peut pas sommer des comptes distincts annuels).
requete_annee <- function(an) {
  etapes <- etapes_mco(an)
  etapes[[length(etapes)]] |> select(NIR_ANO_17)
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

# Les variantes ci-dessous s'insèrent DANS une fonction par millésime
# (etapes_mco(an) / requete_annee(an)) : `an` = suffixe 2 chiffres de l'année courante.

# -- Variante : inclusion sur DAS (diagnostics associés significatifs) ---------
# ident_das <- tbl(conn, I(paste0("T_MCO", an, "D"))) |>
#   filter(substr(ASS_DGN, 1, 3) %in% codes_cim3) |>
#   distinct(RSA_NUM, ETA_NUM)
# e2 |> semi_join(ident_das, by = c("RSA_NUM", "ETA_NUM"))

# -- Variante : critère CCAM côté PMSI (table des actes) -----------------------
# actes_cible <- tbl(conn, I(paste0("T_MCO", an, "A"))) |>
#   filter(sql("REGEXP_LIKE(CDC_ACT, '^[A-Z]{3}L')")) |>   # ex. motif de code CCAM
#   distinct(RSA_NUM, ETA_NUM)
# EXT_PMSI (extension documentaire) n'existe qu'à partir de 2015.

# -- Variante : même critère CCAM côté DCIR (ER_CAM_F, clé composite 9 col.) ---
# Code CCAM = CAM_PRS_IDE (CAM_ACT_COD est le code ACTIVITÉ sur 1 caractère).
# Un acte = triplet (CAM_PRS_IDE, CAM_ACT_COD, CAM_TRT_PHA) : dédupliquer sur ce
# triplet (+ prestation) pour ne pas compter deux fois activité 1 et anesthésie 4.
# actes_dcir <- tbl(conn, I("ER_PRS_F")) |>
#   filter((is.na(DPN_QLF) | !DPN_QLF %in% c(71, 72)),
#          (is.na(PRS_DPN_QLP) | !PRS_DPN_QLP %in% c(71, 72))) |>  # filtres qualité DCIR (NULL = OK)
#   left_join(tbl(conn, I("ER_ETE_F")) |> select(all_of(DCIR_JOIN_KEY), ETE_IND_TAA),
#             by = DCIR_JOIN_KEY) |>
#   filter(is.na(ETE_IND_TAA) | ETE_IND_TAA != 1) |>              # hors ES ex-DG en facturation directe
#   inner_join(tbl(conn, I("ER_CAM_F")), by = DCIR_JOIN_KEY) |>
#   filter(sql("REGEXP_LIKE(CAM_PRS_IDE, '^[A-Z]{3}L')"))
# ATTENTION : non batchée, cette forme n'est exécutable que sur quelques mois
# (filtrer FLX_DIS_DTD) — au-delà, Pattern C ci-dessous.

# -- Variante : critère médicamenteux DCIR (classe ATC, ER_PHA_F + IR_PHA_R) ---
# IR_PHA_R est un référentiel PRODUIT non millésimé (pas de suffixe année).
# Garder la liste de CIP13 cible LAZY (semi_join) : une classe ATC large peut
# dépasser 1000 codes, limite Oracle d'une liste IN (...) (ORA-01795).
# cip_cible <- tbl(conn, I("IR_PHA_R")) |>
#   filter(sql("REGEXP_LIKE(PHA_ATC_CLA, '^N06AB')")) |>   # ex. ISRS
#   filter(!is.na(PHA_CIP_C13)) |>
#   distinct(PHA_CIP_C13)
# delivrances <- tbl(conn, I("ER_PRS_F")) |>
#   filter((is.na(DPN_QLF) | !DPN_QLF %in% c(71, 72)),
#          (is.na(PRS_DPN_QLP) | !PRS_DPN_QLP %in% c(71, 72))) |>
#   inner_join(tbl(conn, I("ER_PHA_F")), by = DCIR_JOIN_KEY) |>
#   semi_join(cip_cible, by = c("PHA_PRS_C13" = "PHA_CIP_C13")) |>
#   transmute(anonyme = BEN_NIR_PSA, rang = BEN_RNG_GEM, dte_exe = EXE_SOI_DTD)
# ATTENTION : la forme ci-dessus ne doit PAS être exécutée telle quelle au-delà
# de quelques mois — ER_PRS_F est trop volumineuse (voir modele-donnees.md,
# piège n°11). Batcher sur FLX_DIS_DTD : voir Pattern C ci-dessous.

# -- Pattern C — extraction DCIR volumineuse (ER_PRS_F) : itération par flux --
# mensuel (FLX_DIS_DTD). Reprend la variante médicamenteuse ci-dessus, batchée.
#
# FLX_DIS_DTD (date de flux technique) != EXE_SOI_DTD (date de soin réelle) :
# une prestation de fin de période peut être remontée dans un flux ultérieur.
# La boucle de flux court donc jusqu'à la fin de la période clinique PLUS UNE
# MARGE (documentation officielle HDH, fiche filtres : au minimum 5 mois de
# données après la période, 12 mois pour une extraction exhaustive, jamais plus
# de 24 — voir points-de-vigilance.md), chaque batch filtrant ensuite
# précisément sur EXE_SOI_DTD.
#
# date_debut  <- as.Date("2020-01-01")   # début période clinique demandée
# date_fin    <- as.Date("2023-12-31")   # fin période clinique demandée
# marge_flux  <- 6                       # mois de flux après date_fin : 6 = minimum
#                                        # officiel (5 mois de données) ; 12 = exhaustif ; <= 24
#
# # Bornes calculées sur le 1er du mois (seq.Date depuis un 31 décalerait les mois)
# mois_fin      <- as.Date(format(date_fin, "%Y-%m-01"))
# flux_max      <- seq.Date(mois_fin, by = "month", length.out = marge_flux + 1)[marge_flux + 1]
# flux_mensuels <- seq.Date(as.Date(format(date_debut, "%Y-%m-01")), flux_max, by = "month")
#
# extraction_batch <- function(flx) {
#   # Connexion PROPRE à ce batch : indispensable avec furrr (workers = process R
#   # séparés) ; fuseau posé avant dbConnect(), comme en tête de script.
#   Sys.setenv(TZ = "Europe/Paris"); Sys.setenv(ORA_SDTZ = "Europe/Paris")
#   .drv <- dbDriver("Oracle")
#   options(connectionObserver = NULL)
#   conn_batch <- dbConnect(.drv, dbname = "IPIAMPR2.WORLD")
#   on.exit(dbDisconnect(conn_batch))
#
#   cip_cible <- tbl(conn_batch, I("IR_PHA_R")) |>          # référentiel produit, lazy
#     filter(sql("REGEXP_LIKE(PHA_ATC_CLA, '^N06AB')")) |>
#     filter(!is.na(PHA_CIP_C13)) |>
#     distinct(PHA_CIP_C13)
#
#   prs <- tbl(conn_batch, I("ER_PRS_F")) |>
#     filter(
#       FLX_DIS_DTD == !!ora_date(flx),                     # même filtre de flux des 2 côtés de la jointure
#       (is.na(DPN_QLF) | !DPN_QLF %in% c(71, 72)),
#       (is.na(PRS_DPN_QLP) | !PRS_DPN_QLP %in% c(71, 72)),  # filtres qualité DCIR (NULL = OK)
#       EXE_SOI_DTD >= !!ora_date(date_debut),
#       EXE_SOI_DTD <= !!ora_date(date_fin)                  # période CLINIQUE, appliquée DANS le batch de flux
#     )
#   ete <- tbl(conn_batch, I("ER_ETE_F")) |>
#     filter(FLX_DIS_DTD == !!ora_date(flx)) |>
#     select(all_of(DCIR_JOIN_KEY), ETE_IND_TAA)
#   pha <- tbl(conn_batch, I("ER_PHA_F")) |>
#     filter(FLX_DIS_DTD == !!ora_date(flx))
#
#   prs |>
#     left_join(ete, by = DCIR_JOIN_KEY) |>
#     filter(is.na(ETE_IND_TAA) | ETE_IND_TAA != 1) |>      # hors ES ex-DG en facturation directe
#     inner_join(pha, by = DCIR_JOIN_KEY) |>
#     semi_join(cip_cible, by = c("PHA_PRS_C13" = "PHA_CIP_C13")) |>
#     transmute(anonyme = BEN_NIR_PSA, rang = BEN_RNG_GEM, dte_exe = EXE_SOI_DTD, cip = PHA_PRS_C13) |>
#     collect()                                              # collect PAR BATCH : exception documentée à la
#                                                             # règle "jamais de collect() avant agrégation
#                                                             # finale" (SKILL.md § 5) -- itération sur
#                                                             # plusieurs connexions, impossible à garder lazy
# }
#
# future::plan(future::multisession(workers = 4))            # cf. profils/hdh_oracle.md, "Défauts recommandés"
# delivrances <- furrr::future_map_dfr(
#   flux_mensuels, extraction_batch, .progress = TRUE
# )   # extrait ligne à ligne -- agréger/dédupliquer ensuite selon le protocole ;
#     # patients uniques : joindre IR_BEN_R (BEN_NIR_PSA, BEN_RNG_GEM) et compter BEN_IDT_ANO

# -- Variante : motif CIM-10 complexe (Oracle REGEXP_LIKE, pas REGEXP_SIMILAR) --
# filter(sql("REGEXP_LIKE(DGN_PAL, '^(F0[0-3]|G30|A810|B220)')"))

# -- Variante : analyse par site géographique -----------------------------------
# Résidence du PATIENT (DCIR) : déjà sur ER_PRS_F (BEN_RES_COM / BEN_RES_DPT).
# Localisation du PROFESSIONNEL DE SANTÉ : ER_GEO_LOC_R, clé NUM_PS = ER_PRS_F.PFS_EXE_NUM
# (exécutant) ou PFS_PRE_NUM (prescripteur) -- le professionnel, PAS le patient.
# Plusieurs lignes possibles par NUM_PS (colonne CABINET) : vérifier l'unicité
# avant la jointure, sous peine de dupliquer les prestations.
# geo_ps <- tbl(conn, I("ER_GEO_LOC_R")) |> distinct(NUM_PS, CODE_COM, CODE_DEPT, CODEREG)
# prestations |> inner_join(geo_ps, by = c("PFS_EXE_NUM" = "NUM_PS"))   # prestations issues de ER_PRS_F

# ==== FLOWCHART D'ATTRITION (systématique) ====
# Mêmes étapes, même ordre que l'extraction (etapes_mco) : rend l'analyse auditable.
attrition <- purrr::map2_dfr(annees, an, function(annee, an) {
  purrr::imap_dfr(etapes_mco(an), function(req, etape) {
    req |>
      mutate(sejour_id = paste0(ETA_NUM, "-", RSA_NUM)) |>
      summarise(nb_sejours = n_distinct(sejour_id)) |>
      collect() |>
      mutate(etape = etape)
  }) |>
    mutate(annee = annee)
})

attrition <- attrition |>
  group_by(annee) |>
  mutate(
    nb_exclus = lag(nb_sejours) - nb_sejours,
    pct_perdu = round(100 * nb_exclus / lag(nb_sejours), 1)
  ) |>
  ungroup() |>
  select(annee, etape, nb_sejours, nb_exclus, pct_perdu)

# Contrôle : la dernière étape de l'attrition = résultat de l'extraction
derniere <- attrition |> filter(etape == last(names(etapes_mco(an[1]))))
stopifnot(all(derniere$nb_sejours == resultat_annuel$nb_sejours[match(derniere$annee, resultat_annuel$annee)]))

# ==== SECRET STATISTIQUE (SEUIL = 11) ====
# À vérifier AVANT toute impression/export de résultat agrégé, dès que la
# finalité (bloc 0 des clarifications) implique une diffusion externe --
# y compris l'attrition (effectifs ET nombres d'exclus entre étapes).
verifier_seuil <- function(df, col_effectif, seuil = SEUIL) {
  # 0 est diffusable (convention usuelle : secret sur les effectifs de 1 à
  # seuil - 1) ; à ajuster si le projet HDH impose une autre règle.
  n_masque <- sum(df[[col_effectif]] > 0 & df[[col_effectif]] < seuil, na.rm = TRUE)
  if (n_masque > 0) {
    warning(sprintf(
      "%d cellule(s) < %d (%s) - à regrouper sous 'Autre' avant toute diffusion externe.",
      n_masque, seuil, col_effectif
    ))
  }
  df
}

resultat_annuel     <- resultat_annuel |> verifier_seuil("nb_patients") |> verifier_seuil("nb_sejours")
nb_patients_periode <- nb_patients_periode |> verifier_seuil("nb_patients")
attrition           <- attrition |> verifier_seuil("nb_sejours") |> verifier_seuil("nb_exclus")

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
#   DCIR/référentiels non millésimés.
# - Vérifier chaque colonne dans le dictionnaire POUR CHAQUE MILLÉSIME demandé,
#   et sur la table où elle est filtrée (ex. SEJ_TYP est dans B, pas dans C).
# - substr(x, 1, 3) -> SUBSTR pour les listes simples ; motifs complexes :
#   filter(sql("REGEXP_LIKE(col, '<regex>')")) — fonction Oracle. Pas de RIGHT()
#   en Oracle : SUBSTR(x, -n).
# - %in% -> IN (...) limité à 1000 valeurs en Oracle (ORA-01795) ; au-delà,
#   semi_join sur une requête lazy ou une table temporaire.
# - Dates : une date R dans filter() devient une chaîne ; utiliser !!ora_date(d)
#   (littéral DATE 'AAAA-MM-JJ'). Vérifier avec show_query().
# - Tables temporaires : copy_to(conn, df, "TMP_X", temporary = FALSE,
#   analyze = TRUE, indexes = list("col")) ou compute(..., analyze = TRUE) —
#   statistiques Oracle calculées ; table créée par dbExecute(CREATE TABLE) :
#   dbExecute(conn, "BEGIN DBMS_STATS.GATHER_TABLE_STATS(USER, 'TMP_X'); END;").
#   (%m_stats_table() est l'équivalent côté SAS uniquement.)
# - n_distinct(x) -> COUNT(DISTINCT x). Pas d'identifiant séjour unique en
#   PMSI/SNDS : construire une clé composite via paste0(ETA_NUM, "-", RSA_NUM)
#   plutôt que n_distinct(x, y) (traduction SQL multi-colonnes fragile).
# - collect() : jamais sur une table de séjours/prestations entière, toujours
#   après agrégation — sauf Pattern C (collect() PAR BATCH de flux DCIR).
# - DCIR volumineux et non millésimé : filtrer par date (EXE_SOI_DTD) ou par
#   flux mensuel (FLX_DIS_DTD) ; au-delà de quelques mois sur ER_PRS_F, itérer
#   par flux avec furrr::future_map_dfr (une connexion Oracle PAR WORKER) —
#   Pattern C et modele-donnees.md piège n°11 ; marge de flux après la période
#   clinique (points-de-vigilance.md).
# - Chaînage inter-sources : NIR_ANO_17 (PMSI) = BEN_NIR_PSA (DCIR) ; individu
#   et causes de décès via IR_BEN_R.BEN_IDT_ANO — modele-donnees.md.
# - Contrôle du SQL généré : requete |> show_query().
# ==============================================================================
