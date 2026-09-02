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
cellule < 11) à prévoir dans les sorties — seuil `SEUIL <- 11`, convention
usuelle sur les extractions SNDS.

## Chaînage inter-source

Dès qu'un protocole combine plusieurs sources SNDS (DCIR, PMSI,
CAUSE_DECES), rappeler que le chaînage patient n'est pas automatique : trois
identifiants distincts selon la source (voir `modele-donnees.md`), pas de
table de passage directe dans le dictionnaire fourni, et un même identifiant
DCIR peut être associé à plusieurs identifiants pivots dans `IR_BEN_R`.
Quantifier et signaler la perte ou l'ambiguïté de chaînage plutôt que de la
passer sous silence.

## Confidentialité — non-persistance locale

**Ne jamais enregistrer localement un extrait SNDS contenant un identifiant,
une date ou une localisation individuelle potentiellement ré-identifiante.**
Le rappeler explicitement à la livraison (étape 6 du workflow) : tout export
destiné à quitter l'environnement HDH doit être agrégé et respecter le seuil
de diffusion.
