# Checklist de clarification

Poser par lots de 4 questions maximum, via l'outil de choix multiple si
disponible (ex. AskUserQuestion), sinon à l'écrit. Toujours proposer une
option par défaut marquée « (Recommandé) ». Ne poser que les questions
pertinentes pour la demande, mais le bloc 0 et les blocs A, B, C, D doivent
être couverts (par une question ou par un défaut explicitement validé au
moment du protocole — pour D, « aucune stratification » est un défaut
valable).

## Dépendances entre questions (à signaler explicitement)

- **Q0 → bloc E** : diffusion externe/publication impose le secret
  statistique (aucune cellule < 11) dans le format de sortie.
- **Q1 → Q3a/Q3b/Q3c** : la ou les sources SNDS retenues déterminent quelle(s)
  définition(s) de code s'appliquent — CIM-10 via le diagnostic PMSI et/ou la
  cause de décès CépiDc (`KI_CCI_R`/`KI_ECD_R`), CCAM via les actes PMSI et/ou
  `ER_CAM_F` (DCIR), ATC/CIP uniquement pertinent si la pharmacie DCIR
  (`ER_PHA_F`+`IR_PHA_R`) est retenue.
- **Q1 (sources combinées)** : si plusieurs sources SNDS sont retenues
  ensemble (ex. PMSI + DCIR, ou PMSI + CAUSE_DECES), le chaînage
  inter-source doit être vérifié et documenté séparément — `NIR_ANO_17`
  (PMSI) = `BEN_NIR_PSA` (DCIR), individu et causes de décès via
  `IR_BEN_R.BEN_IDT_ANO`, appariement des décès incomplet (voir
  `modele-donnees.md`, « Chaînage patient »).
- **Q2 ↔ Q4** : le nom des variables de position diagnostique change selon le
  champ PMSI (`DGN_PAL`/`DGN_REL` en MCO ; `FP_PEC` [jusqu'en 2022, réforme
  SMR]/`MOR_PRP`/`ETL_AFF` en SSR ; `DGN_PAL` de `T_HAD{aa}B` en HAD) — champ multiple = vérifier la cohérence de la question posée pour
  chacun.
- **Q3a → Q13/Q14** : troncature CIM-10 à 3 caractères (sur-inclusion) vs
  codes complets (sous-inclusion) modifie la sensibilité du critère de
  jugement.
- **Q13 (patients uniques) → Q11** : patients uniques comme unité de compte
  impose le chaînage fiable (codes retour PMSI à `'0'` et NIR fictifs exclus ;
  côté DCIR, comptage sur `IR_BEN_R.BEN_IDT_ANO` et non sur le couple
  `BEN_NIR_PSA`/`BEN_RNG_GEM`) en critère d'exclusion, pas en option.
- **Q5 (période ≥ 2013) → Q3b/Q3c si source DCIR** : Kwikly détaille la
  disponibilité des colonnes DCIR année par année de 2006 à 2012 seulement
  (`*` ensuite) — signaler l'incertitude si une variable utilisée n'a aucun
  `X` (apparue après 2012 à une date inconnue).
- **Q5 (période avant 2009) → Q13/Q15 si PMSI** : dates réelles de séjour
  absentes avant 2009, seulement le mois/année de sortie.
- **Q5 (série traversant 2023) si SSR** : réforme SMR, `FP_PEC` non codé
  après le 01/03/2023.

## 0. Finalité de l'analyse (à poser en premier)

0. **Usage des résultats** : dénombrement interne rapide, rapport ou dialogue
   de gestion, diffusion externe (ARS, tutelle), publication scientifique ?
   Conditionne le niveau de rigueur, le secret statistique des sorties
   (aucune cellule < 11 en diffusion externe) et le format de livraison.

## A. Source(s) SNDS et population — critères d'inclusion

1. **Source(s) SNDS** : DCIR (consommation de soins de ville — consultations,
   pharmacie, actes en ville, biologie…), PMSI (séjours hospitaliers),
   CAUSE_DECES (cause médicale de décès), ou une combinaison ? Si
   combinaison, préciser si l'analyse porte sur l'**intersection** (ex.
   « hospitalisés ET traités en ville pour… ») ou l'**union** (ex.
   « suivis en ville OU hospitalisés pour… ») — les deux donnent des
   effectifs très différents.
2. **Champ(s) PMSI** (si PMSI retenu) : MCO seul (recommandé pour
   « hospitalisation ») ou MCO + SSR ; HAD et RIP (psychiatrie) sur demande
   explicite (filtres qualité validés via la documentation officielle HDH,
   mais tables de diagnostics/actes détaillées à vérifier au cas par cas
   dans le dictionnaire Kwikly, voir `modele-donnees.md`).
3a. **Codes CIM-10** (si le phénomène est une pathologie) : proposer une
   liste précise et la faire valider. Si WebSearch est disponible, chercher
   d'abord une définition publiée (Santé publique France, cartographie des
   pathologies CNAM, littérature) et la proposer **source citée** ; sinon
   proposer d'après connaissances en le signalant. La liste reste amendable.
   Exemples : diabète = E10–E14 (préciser si diabète gestationnel O24
   inclus) ; AVC = I60–I64. Demander : troncature à 3 caractères ou codes
   complets ? Et, selon la source (Q1) : recherchés via le diagnostic PMSI
   (DP/DR/DAS) et/ou via la cause de décès CépiDc (cause initiale `KI_CCI_R`
   ou toutes causes mentionnées `KI_ECD_R`) ?
3b. **Codes CCAM** (si le phénomène est un acte) : même exigence qu'en Q3a —
   liste précise validée, source citée si WebSearch disponible (nomenclature,
   sociétés savantes), sinon proposer d'après connaissances en le signalant.
   Un acte CCAM se définit par le triplet (code + activité + phase de
   traitement) côté ville (`ER_CAM_F`) — préciser si l'on recherche l'acte en
   hospitalisation (PMSI, table `A`) et/ou en ville (DCIR, `ER_CAM_F`), et si
   codes complets ou motif partiel.
3c. **Codes ATC/CIP** (si le phénomène est un traitement médicamenteux) :
   classe ATC (ex. `^B01` anticoagulants, `^N06AB` antidépresseurs ISRS) via
   `IR_PHA_R.PHA_ATC_CLA`, ou liste de codes CIP13 précis. Motif `REGEXP_LIKE`
   ou liste fermée ? Préciser si l'on cherche une primo-délivrance, une
   délivrance à une date donnée, ou une exposition cumulée sur une période.
4. **Position du diagnostic** (si PMSI et pathologie) :
   - DP seul (« hospitalisé POUR ») — recommandé pour un motif d'hospitalisation ;
   - DP ou DR — capte aussi le diagnostic relié ;
   - DP, DR ou DAS (« hospitalisé AVEC ») — prévalence hospitalière, effectifs
     bien plus larges.
   En SSR, adapter : finalité principale de prise en charge (`FP_PEC`),
   manifestation morbide principale (`MOR_PRP`), affection étiologique
   (`ETL_AFF`) — préciser lequel (ou lesquels) correspond au périmètre voulu ;
   `FP_PEC` n'existe plus à partir de 2023 (réforme SMR).
5. **Période** : années couvertes. Bornes incluses. Si « évolution » : nombre
   d'années souhaité. Signaler les ruptures de disponibilité (voir
   dépendances : DCIR ≥ 2013, PMSI avant 2009, SSR après 2022).
6. **Géographie** : France entière ; sinon résidence du patient
   (`BEN_RES_DPT`/`BDI_DEP` selon la source) ou localisation de
   l'établissement (`ETA_NUM`) — les deux ne donnent pas le même résultat.
7. **Population** : tous âges ou restriction (ex. ≥ 18 ans) ; les deux sexes.

## B. Critères d'exclusion

8. **Séances** (MCO, GHM `28*`) : exclues (recommandé quand on compte des
   hospitalisations) ou incluses ?
9. **Séjours/GHM en erreur** : GHM/GME `90*` — exclus par défaut.
10. **Doublons de transmission** (MCO uniquement) : établissements
    APHP/APHM/HCL déjà déclarés en double — exclus par défaut, mais
    **seulement pour les séjours 2005-2017** (remontées corrigées depuis) ;
    liste à jour des FINESS récupérée en direct sur la documentation
    officielle plutôt que codée en dur (voir `profils/hdh_oracle.md`).
11. **Chaînage en erreur / qualité** : côté PMSI, codes retour de contrôle
    (`NIR_RET`, `NAI_RET`, `SEX_RET`, `SEJ_RET`, `FHO_RET`, `PMS_RET` depuis
    2005, `DAT_RET` depuis 2006, `COH_NAI_RET`/`COH_SEX_RET` depuis 2013)
    différents de `'0'`, et `NIR_ANO_17` fictifs — à exclure si comptage de
    patients uniques, signaler la perte. Côté DCIR, `DPN_QLF NOT IN (71,72)`
    et `PRS_DPN_QLP NOT IN (71,72)` (en gérant les `NULL`), et exclusion des
    établissements ex-DG en facturation directe (`ER_ETE_F.ETE_IND_TAA`).
12. Autres selon contexte : séjours de la même journée, nouveau-nés, IVG,
    prestations inter-établissements (PIE, `SEJ_TYP = 'B'`, exclues par défaut en MCO), décès en cours de séjour (proxy de
    ré-hospitalisation faussé)…

## C. Critère de jugement (indicateur principal)

13. **Unité de compte** : patients uniques (`NIR_ANO_17` en PMSI seul ;
    `IR_BEN_R.BEN_IDT_ANO` dès que le DCIR ou les décès sont mobilisés — voir
    Q1/dépendances), séjours, prestations/lignes DCIR,
    ou décès (CAUSE_DECES).
14. **Type d'indicateur** : effectif brut ; taux pour 100 000 habitants ; taux
    standardisé (âge/sexe) ; évolution (série annuelle, % d'évolution).
15. Pour une « évolution » : patients uniques **par année** (un patient peut
    apparaître plusieurs années) ou cohorte dédupliquée sur toute la
    période ? Les deux lectures sont valides — faire choisir.

## D. Stratification / croisements

16. Par année, sexe, classe d'âge (préciser les bornes), département/région
    (résidence ou établissement), source SNDS (si plusieurs), champ PMSI…
    Aucune stratification = total simple.

## E. Sortie attendue

17. Format : script `.R` (tableau agrégé affiché, export CSV, graphique
    ggplot2) ou **rapport `.Rmd`** (narratif méthodologique, tables
    interactives, flowchart d'attrition intégré) — recommandé dès que le
    résultat est destiné à être partagé tel quel.
18. **Environnement** : ne rien demander (connexion, schéma) quand le profil
    `references/profils/hdh_oracle.md` couvre l'environnement — voir
    SKILL.md, Ressources. Sinon, demander une fois et proposer d'enregistrer
    un nouveau profil.
