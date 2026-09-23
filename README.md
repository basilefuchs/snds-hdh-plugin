# snds-hdh — statisticien DIM virtuel pour Claude

Skill [Claude Code](https://claude.com/claude-code) (plugin) et [claude.ai](https://claude.ai)
(Skill web) destinée aux statisticiens de DIM travaillant sur le **SNDS via le
Health Data Hub** (Oracle). Elle traduit une question en langage naturel —
« combien de patients diabétiques hospitalisés entre 2020 et 2023 ? » — en un
script R dplyr/dbplyr prêt à exécuter sur l'environnement du Health Data Hub,
**en passant par les mêmes étapes qu'un statisticien** : clarification,
protocole validé, puis script.

## Comment ça se passe concrètement

1. **Vous posez la question** en langage naturel, comme un clinicien la poserait.
2. **La skill fait préciser** ce qu'un DIM ferait préciser, en commençant par la
   **finalité** (dénombrement interne, rapport, diffusion externe, publication —
   qui conditionne rigueur, seuils et secret statistique), puis : codes CIM-10
   exacts (proposés d'après les définitions publiées trouvées par recherche web —
   sources citées, liste amendable), source(s) mobilisée(s) (PMSI hospitalier,
   DCIR ambulatoire, causes de décès), position du diagnostic, période, patients
   vs séjours vs délivrances, exclusions (GHM en erreur, doublons, qualité de
   chaînage), stratification.
3. **Elle soumet un protocole** synthétique, accompagné de ses **points de
   vigilance** (chaînage inter-sources NIR_ANO_17/BEN_NIR_PSA/BEN_NIR_ANO,
   années Covid dans une tendance, petits effectifs...) :
   > **Population** : séjours MCO 2020–2023, DP en E10–E14, France entière.
   > **Exclusions** : GHM en erreur (CMD 90), doublons établissement, chaînage défaillant.
   > **Critère de jugement** : patients uniques (`NIR_ANO_17`), par année.
   > **Stratification** : année, sexe, classe d'âge.
4. **Après votre validation seulement**, elle génère le script `.R` : paramétré
   en tête, commenté, avec en-tête normalisé (question, protocole, « PROFIL DE
   BASE » listant tables et variables utilisées), un **flowchart d'attrition**
   (effectifs et % perdus à chaque étape d'exclusion), une vérification
   **secret statistique** (seuil de diffusion) et une note méthodologique
   (limites, pistes de sensibilité).

Vous exécutez le script vous-même sur l'environnement du Health Data Hub :
**Claude n'accède jamais aux données** — il ne voit que la question, le
protocole et le code généré. Le dictionnaire embarqué (export Kwikly,
propriété de la CNAM — voir [Licence](#licence)) est le document de
description de la base (métadonnées), sans aucune donnée patient.

## Ce que la skill sait (et vérifie)

- Les conventions de l'environnement : `ROracle`/`dbConnect(dbDriver("Oracle"),
  dbname = "IPIAMPR2.WORLD")`, fuseau `Europe/Paris` (R et `ORA_SDTZ`), tables
  référencées par `tbl(conn, I("NOM_TABLE"))`, calcul côté Oracle et `collect()`
  uniquement sur les agrégats.
- Le modèle de données PMSI (tables suffixées par année de sortie) et DCIR
  (tables continues, filtrées par date/flux) : grain des tables, clés de
  jointure, chaînage patient.
- Les pièges classiques du SNDS, signalés ou traités d'office : **trois
  identifiants patient distincts** selon la source (PMSI = `NIR_ANO_17`, DCIR =
  `BEN_NIR_PSA` + `BEN_RNG_GEM`, causes de décès = `BEN_NIR_ANO`), qualité de
  chaînage PMSI (`NIR_RET`/`NAI_RET`/`SEX_RET`/`SEJ_RET`/`FHO_RET`/`PMS_RET`/`COH_SEX_RET`),
  doublons APHP/APHM/HCL (2005-2017 uniquement), GHM en erreur (CMD 90),
  filtres qualité DCIR (`DPN_QLF`+`PRS_DPN_QLP`, `CPL_MAJ_TOP`), clé composite
  à 9 colonnes des tables DCIR, `ER_GEO_LOC_R` géolocalise le professionnel de
  santé (`NUM_PS`) et non le patient, patients uniques pluriannuels par union
  avant `n_distinct`.
- L'existence et la disponibilité de **chaque table utilisée**, via l'index du
  dictionnaire Kwikly (`dictionnaire/index-tables.csv`) qui pointe vers la
  page de détail correspondante (variables, millésimes couverts), les tables
  de référence `IR_BEN_R` (filtres population) et `IR_IMB_R` (ALD), et les
  filtres PMSI HAD/RIP, validés au même titre que MCO/SSR.
- La documentation officielle en ligne du Health Data Hub, consultée en
  complément (via WebFetch) quand elle est disponible : elle **fait foi** sur
  les filtres recommandés et la méthodologie, y compris en cas de
  contradiction avec le reste de la skill. Le forum d'entraide et la
  cartographie de l'écosystème SNDS complètent ponctuellement (dépannage,
  définitions de cohortes déjà validées).

Le script généré reste **à relire avant exécution**, comme celui d'un interne :
la skill fiabilise la traduction question → code, elle ne remplace pas la
validation métier ni le respect du secret statistique sur les sorties.

## Prérequis

- [Claude Code](https://claude.com/claude-code) (CLI ou application) **ou** un
  compte [claude.ai](https://claude.ai) avec la capacité Skills (et Code
  execution, pour l'option D — Skill web).
- Un accès à l'environnement du Health Data Hub (pour exécuter les scripts ;
  la génération elle-même n'en a pas besoin).
- Aucune compétence particulière en dbplyr : les scripts sont autoportants.

## Installation

### Option A — plugin Claude Code depuis le dépôt Git (recommandé pour une équipe de DIM)

Le dépôt [basilefuchs/snds-hdh-plugin](https://github.com/basilefuchs/snds-hdh-plugin)
est à la fois une *marketplace* Claude Code (`snds-hdh-marketplace`, déclarée
dans `.claude-plugin/marketplace.json`) et le plugin qu'elle distribue
(`snds-hdh`). Le dépôt étant public, aucun identifiant n'est nécessaire.

1. **Ouvrir Claude Code** (terminal : `claude` ; ou application desktop / IDE).
2. **Déclarer le dépôt comme marketplace** :
   ```
   /plugin marketplace add basilefuchs/snds-hdh-plugin
   ```
   Variantes :
   - URL complète : `/plugin marketplace add https://github.com/basilefuchs/snds-hdh-plugin.git`
   - branche ou tag précis : `/plugin marketplace add https://github.com/basilefuchs/snds-hdh-plugin.git#main`
   - clone local (poste sans accès GitHub, test d'une modification) :
     `git clone https://github.com/basilefuchs/snds-hdh-plugin.git` puis
     `/plugin marketplace add ./snds-hdh-plugin`
3. **Installer le plugin** :
   ```
   /plugin install snds-hdh@snds-hdh-marketplace
   ```
   Claude Code demande la portée de l'installation :
   - **user** : pour vous, dans tous vos projets ;
   - **project** : pour tous les collaborateurs du projet courant (écrit dans
     `.claude/settings.json`, à committer) ;
   - **local** : pour vous seul, dans le projet courant.
4. **Activer** : fermer le menu `/plugin` suffit (Claude Code exécute alors
   `/reload-plugins`) ; sinon, taper `/reload-plugins`. Aucun redémarrage n'est
   nécessaire.
5. **Vérifier** : `/plugin` → onglet **Installed** doit lister `snds-hdh` ;
   taper `/snds-hdh:` doit proposer `/snds-hdh:snds-hdh` (raccourci) et
   `/snds-hdh:snds-query` (skill).

Équivalent en ligne de commande, pour scripter l'installation d'un poste :

```
claude plugin marketplace add basilefuchs/snds-hdh-plugin
claude plugin install snds-hdh@snds-hdh-marketplace --scope user
```

**Mettre à jour** (dictionnaire, profils, nouveaux patterns validés) :

```
/plugin marketplace update snds-hdh-marketplace
/reload-plugins
```

`.claude-plugin/plugin.json` déclarant un champ `version`, Claude Code ne
propose une nouvelle version que si ce numéro change : l'incrémenter à chaque
livraison, sinon les postes déjà installés ne reçoivent pas les modifications.

**Désinstaller** : `/plugin uninstall snds-hdh@snds-hdh-marketplace` ; retirer
la marketplace : `/plugin marketplace remove snds-hdh-marketplace` (désinstalle
aussi le plugin).

**Déployer pour toute une équipe** : dans le dépôt de projet partagé par
l'équipe, ajouter à `.claude/settings.json` puis committer :

```json
{
  "extraKnownMarketplaces": {
    "snds-hdh-marketplace": {
      "source": { "source": "github", "repo": "basilefuchs/snds-hdh-plugin" }
    }
  },
  "enabledPlugins": {
    "snds-hdh@snds-hdh-marketplace": true
  }
}
```

Chaque membre qui ouvre ce projet dans Claude Code (et accorde sa confiance au
dossier) se voit proposer la marketplace et le plugin, sans étape manuelle.

**Fork privé** (ex. dépôt interne au DIM) : Claude Code réutilise les
identifiants git du poste (`gh auth setup-git`, clé SSH) ; pour que les mises à
jour automatiques en arrière-plan fonctionnent, définir aussi la variable
d'environnement `GITHUB_TOKEN`.

### Option B — skill personnelle

Copier `skills/snds-query/` dans `~/.claude/skills/` :

```
cp -r skills/snds-query ~/.claude/skills/
```

La skill est alors disponible dans tous vos projets.

### Option C — skill de projet

Copier `skills/snds-query/` dans `.claude/skills/` du projet et committer :
toute personne qui clone le projet a la skill.

### Option D — Skill web (claude.ai)

`skills/snds-query/` est aussi packagée pour l'upload de Skill sur claude.ai
(**Customize → Skills**), sans passer par Claude Code :

```
powershell -File scripts/build-web-skill.ps1
```

Génère `dist/snds-query.zip`, prêt à uploader tel quel. À vérifier côté compte
claude.ai avant utilisation :

- la capacité **Code execution** doit être activée (nécessaire pour que la
  skill puisse consulter le dictionnaire Kwikly embarqué via des commandes shell) ;
- sans outil de choix multiple équivalent à celui de Claude Code, la skill
  pose ses questions de clarification à l'écrit — répondre en langage naturel ;
- le paquet est volumineux (dictionnaire Kwikly complet, plusieurs milliers de
  pages HTML) — vérifier la limite de taille d'upload Skill du compte
  claude.ai avant de packager.

Le zip n'est pas versionné (`dist/` est ignoré) : relancer le script après
toute modification de `skills/snds-query/` pour repackager.

## Utilisation

Poser une question SNDS en langage naturel — la skill se déclenche d'elle-même —
ou l'invoquer explicitement :

- installée en **plugin** (option A, Claude Code) : `/snds-hdh:snds-hdh <question>`
  (les commandes et skills d'un plugin sont toujours préfixées par le nom du
  plugin ; la skill seule : `/snds-hdh:snds-query`) ;
- installée en **skill** dans Claude Code (options B et C) : `/snds-query <question>`
  (le raccourci `/snds-hdh:snds-hdh` fait partie du plugin et n'est pas copié
  avec la skill) ;
- installée en **skill web** (option D, claude.ai) : pas d'invocation par
  commande vérifiée — poser directement la question, la skill se déclenche sur
  sa description.

Exemples de questions :

- « Combien de patients diabétiques ont été hospitalisés en 2023, par région ? »
- « Évolution des délivrances d'antidépresseurs (DCIR) 2019–2024 dans mon département »
- « Taux de recours à l'HAD pour soins palliatifs, pour 100 000 habitants »

## Structure du dépôt

```
commands/snds-hdh.md                # raccourci /snds-hdh:snds-hdh (installation plugin uniquement)
scripts/build-web-skill.ps1         # packaging skill web (option D) : skills/snds-query/ -> dist/snds-query.zip
scripts/build-kwikly-index.ps1      # régénère dictionnaire/index-tables.csv depuis l'export Kwikly
skills/snds-query/
├── SKILL.md                        # workflow : clarifier → protocole → script
└── references/
    ├── profils/
    │   └── hdh_oracle.md           # environnement Health Data Hub (fait foi) : connexion, mapping, défauts
    ├── dictionnaire/
    │   ├── Kwikly/                 # export HTML Kwikly (pages catégorie + détail par table)
    │   └── index-tables.csv        # index plat categorie;table;libelle;chemin (généré)
    ├── modele-donnees.md           # tables, jointures, chaînage (3 identifiants), pièges
    ├── clarifications.md           # checklist du statisticien
    ├── points-de-vigilance.md      # registres de risques méthodologiques (biais, instabilité...)
    ├── template.R                  # squelette de script R, patterns dbplyr/Oracle
    └── template.Rmd                # squelette de rapport R Markdown (même patterns)
```

## Adapter à un autre environnement que le Health Data Hub

Toute la connaissance spécifique à l'environnement (connexion, tables,
mapping colonne, défauts) vit dans `skills/snds-query/references/profils/`.
Pour un autre environnement (base locale, export parquet/DuckDB…), dupliquer
`hdh_oracle.md`, adapter les valeurs, et la skill l'utilisera — le reste ne
change pas. Les profils **font foi** : c'est aussi là que capitaliser vos
mappings validés et pièges découverts, pour que les scripts suivants en
profitent.

## Mise à jour du dictionnaire (export Kwikly)

Le dictionnaire n'est pas un simple CSV : c'est le **miroir HTML complet** de
l'export Kwikly (une page par catégorie — DCIR, PMSI,
CAUSE_DECES, CARTOGRAPHIE, VALEUR, AUTRE — et une page de détail par table,
listant ses variables et les millésimes où elles existent).

1. Remplacer le contenu de `skills/snds-query/references/dictionnaire/Kwikly/`
   par le nouvel export Kwikly de la CNAM, en conservant la même
   arborescence (les 6 pages de catégorie + leurs sous-dossiers par table).
2. Régénérer l'index plat des tables :
   ```
   powershell -File scripts/build-kwikly-index.ps1
   ```
   Produit `dictionnaire/index-tables.csv` (`categorie;table;libelle;chemin`),
   que la skill utilise pour retrouver la bonne page de détail sans parcourir
   tout le miroir HTML. Le script est **idempotent** : à relancer à chaque
   rafraîchissement de l'export (date affichée en pied de page des pages
   Kwikly, ex. « Version du 19/06/2026 »).
3. Incrémenter `version` dans `.claude-plugin/plugin.json` avant de pousser,
   pour que les installations existantes reçoivent la mise à jour (voir
   Option A, « Mettre à jour »).

## Licence

Le code et le contenu propres au plugin (skill, références, templates,
scripts) sont sous licence MIT, © 2026 Basile Fuchs et CHU de Brest — voir
[LICENSE](LICENSE) et [NOTICE](NOTICE).

**Le dictionnaire des données du SNDS n'est pas couvert par cette licence.**
L'export Kwikly (`skills/snds-query/references/dictionnaire/Kwikly/`, logos
compris), l'index qui en est dérivé (`dictionnaire/index-tables.csv`) et les
versions JSON de ce dictionnaire (exports CNAM ou conversions locales au format
pivot [CHU-Brest/kwikly-json](https://github.com/CHU-Brest/kwikly-json)) sont
la propriété de la Caisse nationale de l'Assurance Maladie (CNAM). Leur
réutilisation et leur redistribution relèvent des conditions fixées par la
CNAM, y compris lorsqu'ils sont diffusés avec ce plugin (dépôt Git, paquet
`dist/snds-query.zip`).
