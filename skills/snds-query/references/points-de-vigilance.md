# Points de vigilance (registres à examiner)

Checklist des risques méthodologiques classiques à évaluer pour un protocole
SNDS. Utilisée par `SKILL.md` à deux moments :

- **étape 3 (clarification)** : dès qu'une réponse fait apparaître un des
  risques ci-dessous, le signaler immédiatement — c'est le moment le moins
  coûteux pour corriger ;
- **étape 4 (synthèse)** : pour les risques qui n'apparaissent qu'une fois
  l'ensemble des choix connus (interactions entre plusieurs critères). Ne
  jamais répéter en étape 4 une alerte déjà donnée en étape 3.

Dans les deux cas, ne signaler que les alertes **ciblées sur le protocole
précis** en cours (pas de liste générique) : 2 à 3 alertes bien choisies
valent mieux qu'un passage en revue exhaustif. Le détail des pièges
techniques (colonnes, filtres) est dans `modele-donnees.md` et
`profils/hdh_oracle.md` — ce document se concentre sur le raisonnement
méthodologique, pas sur la syntaxe.

## Rupture d'interprétation

Années Covid (2020–2021) dans une tendance ; changements de nomenclature ou
de consignes de codage sur la période (CIM-10, CCAM) ; rupture structurelle
de table (ex. `EXT_PMSI` absent avant 2015 — cf. `modele-donnees.md`, pièges).

**SSR → SMR (1er juin 2023, réforme du financement en juillet 2023)** : les
tables restent `T_SSR{aa}*`, mais `FP_PEC` n'est plus codé après le
01/03/2023 (absent du millésime 2023+) — ne pas l'utiliser comme critère sur
2023+, et signaler la rupture pour toute série SSR traversant 2023.

## Biais de définition

- DP seul sous-estime une prévalence hospitalière.
- Choisir une seule source SNDS (ex. PMSI seul) ignore la consommation de
  soins de ville (DCIR) ou la cause médicale de décès (CAUSE_DECES) — à
  signaler explicitement si le phénomène étudié déborde naturellement du
  périmètre choisi (ex. « suivi du diabète » sans regarder la pharmacie).
- Cause initiale de décès (`KI_CCI_R`) vs causes multiples (`KI_ECD_R`) ne
  captent pas la même chose : une pathologie mentionnée comme cause associée
  n'apparaît pas dans un comptage limité à la cause initiale.
- Motif CCAM partiel peut sur-inclure des actes hors cible si la nomenclature
  a évolué sur la période.

## Instabilité

Petits effectifs attendus (géographie ou pathologie rare) → rappeler les
seuils de robustesse, proposer un lissage ou un regroupement de périodes/zones.

## Diffusion

Si la finalité implique une sortie externe, secret statistique (aucune
cellule de 1 à 10 ; 0 reste diffusable sauf règle contraire du projet) à prévoir dans les sorties — seuil `SEUIL <- 11`, convention
usuelle sur les extractions SNDS.

## Chaînage inter-source

Dès qu'un protocole combine plusieurs sources SNDS (DCIR, PMSI,
CAUSE_DECES), rappeler que le chaînage patient n'est pas automatique (voir
`modele-donnees.md`, « Chaînage patient ») : `NIR_ANO_17` (PMSI) =
`BEN_NIR_PSA` (DCIR), l'individu est `IR_BEN_R.BEN_IDT_ANO` (un individu peut
porter plusieurs `BEN_NIR_PSA`), et les causes de décès ne sont appariées à
`IR_BEN_R` que partiellement (`DCD_IDT_TOP`). Quantifier et signaler la perte
ou l'ambiguïté de chaînage plutôt que de la passer sous silence.

## Statut vital

`BEN_DCD_DTE` = 1600 signifie « aucun décès connu » (vivant OU date
manquante). L'exhaustivité n'est garantie que pour le régime général hors SLM
depuis juillet 2009 (MSA depuis 2009 ; RSI et SLM peu renseignés) : utiliser
`IR_BEN_R` seul sous-estime la mortalité, différemment selon le régime.
Croiser avec `KI_CCI_R` (via `BEN_IDT_ANO`) et les décès hospitaliers
(`SOR_MOD = 9` en PMSI), et fixer une règle de priorité entre dates.

## Délai de remontée DCIR (`FLX_DIS_DTD` vs `EXE_SOI_DTD`)

Toute extraction `ER_PRS_F` batchée par flux technique (`FLX_DIS_DTD`, voir
`modele-donnees.md` piège n°11 et `template.R` Pattern C) risque de perdre
les prestations de fin de période remontées en retard si la boucle de flux
s'arrête pile à la fin de la période clinique demandée (`EXE_SOI_DTD`).
Marge officielle (documentation HDH, fiche synthèse des filtres) : au minimum
5 mois de données après la période d'étude (flux `FLX_DIS_DTD` jusqu'au 1er
du mois fin + 6), 12 mois pour une extraction exhaustive, jamais plus de 24
mois. Le signaler dans le protocole, avec la marge retenue.

## Confidentialité — non-persistance locale

**Ne jamais enregistrer localement un extrait SNDS contenant un identifiant,
une date ou une localisation individuelle potentiellement ré-identifiante.**
Le rappeler explicitement à la livraison (étape 6 du workflow) : tout export
destiné à quitter l'environnement HDH doit être agrégé et respecter le seuil
de diffusion.
