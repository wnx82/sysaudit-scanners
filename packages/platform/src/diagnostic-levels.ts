// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

/**
 * Niveaux de diagnostic — **source de vérité unique**.
 *
 * Les quatre niveaux (Rapide, Normale, Complète, Poussée) existaient jusqu'ici
 * en quatre exemplaires : les options du scanner Bash, le branchement du
 * scanner PowerShell, les cartes du site et la documentation. Trois d'entre eux
 * décrivaient un comportement que le quatrième n'avait pas — le site promettait
 * un « stress GPU prolongé » à un niveau qui ne lançait aucun test GPU, et
 * `full` ne se distinguait de `standard` que par deux collecteurs.
 *
 * Ce fichier décrit ce que chaque niveau **exige**. Les scanners en sont des
 * projections vérifiées : `scanners/linux/lib/core/levels.sh` et
 * `scanners/windows/lib/core/levels.ps1` embarquent la même matrice sous forme
 * de table lisible sans Node.js, et `diagnostic-levels-contract.test.ts` échoue
 * dès que l'une diverge.
 *
 * Une case ne monte de profondeur que lorsque le collecteur correspondant fait
 * réellement quelque chose de plus. Promettre plus que ce qui est collecté est
 * exactement le défaut que cette table corrige.
 */

/** Niveaux exposés au public, du plus léger au plus lourd. */
export const DIAGNOSTIC_LEVELS = ['quick', 'standard', 'full', 'stress'] as const;
export type DiagnosticLevel = (typeof DIAGNOSTIC_LEVELS)[number];

/**
 * Profils historiques encore acceptés en entrée.
 *
 * `security` a existé comme profil à part entière dans le scanner et dans
 * `reportMetaSchema`. Il ne collectait rien de plus que `quick` : il est
 * conservé comme alias pour ne pas casser les rapports ni les commandes
 * existantes, mais il n'a pas de ligne propre dans la matrice.
 */
export const LEGACY_LEVEL_ALIASES: Readonly<Record<string, DiagnosticLevel>> = {
  security: 'quick',
};

/**
 * Profondeur de collecte d'une section, pour un niveau donné.
 *
 * L'échelle est ordonnée : `skipped` < `summary` < `standard` < `extended`.
 * Cet ordre porte une garantie — un niveau plus élevé ne collecte jamais moins
 * qu'un niveau plus bas — que `diagnostic-levels.test.ts` vérifie.
 */
export const COLLECTION_DEPTHS = ['skipped', 'summary', 'standard', 'extended'] as const;
export type CollectionDepth = (typeof COLLECTION_DEPTHS)[number];

export const DEPTH_RANK: Readonly<Record<CollectionDepth, number>> = {
  skipped: 0,
  summary: 1,
  standard: 2,
  extended: 3,
};

export const DEPTH_SYMBOLS: Readonly<Record<CollectionDepth, string>> = {
  skipped: '—',
  summary: '◔',
  standard: '◕',
  extended: '●',
};

export const DEPTH_LABELS: Readonly<Record<CollectionDepth, string>> = {
  skipped: 'non collectée',
  summary: 'résumé',
  standard: 'complète',
  extended: 'approfondie',
};

/**
 * Sections dont la collecte dépend du niveau.
 *
 * `capabilities` et `collection` en sont absentes : elles décrivent le scan
 * lui-même et sont toujours produites. `monitoring` en est absente aussi : elle
 * dépend de `--monitor <secondes>`, une demande explicite orthogonale au
 * niveau. `firmware` également : aucun scanner ne la produit, faute de source
 * constructeur interrogeable.
 */
export const LEVEL_SECTIONS = [
  'system',
  'os',
  'motherboard',
  'bios',
  'cpus',
  'memory',
  'gpus',
  'audio',
  'sensors',
  'power',
  'storage',
  'network',
  'devices',
  'drivers',
  'software',
  'startup',
  'security',
  'virtualization',
  'stability',
  'boot',
  'shutdown',
  'events',
  'benchmark',
] as const;
export type LevelSection = (typeof LEVEL_SECTIONS)[number];

export const SECTION_LABELS: Readonly<Record<LevelSection, string>> = {
  system: 'Identité machine',
  os: 'Système d’exploitation',
  motherboard: 'Carte mère',
  bios: 'BIOS / UEFI',
  cpus: 'Processeur',
  memory: 'Mémoire',
  gpus: 'Carte graphique',
  audio: 'Audio',
  sensors: 'Capteurs et températures',
  power: 'Alimentation et batterie',
  storage: 'Stockage et santé disque',
  network: 'Réseau',
  devices: 'Périphériques PCI/USB',
  drivers: 'Pilotes',
  software: 'Logiciels et services',
  startup: 'Éléments au démarrage',
  security: 'Sécurité',
  virtualization: 'Virtualisation et conteneurs',
  stability: 'Stabilité observée',
  boot: 'Séquence de démarrage',
  shutdown: 'Séquence d’arrêt',
  events: 'Historique des incidents',
  benchmark: 'Banc d’essai',
};

/**
 * Ce que chaque section apporte de plus quand la profondeur augmente.
 *
 * Une section n'y figure que si sa profondeur **varie** réellement d'un niveau
 * à l'autre. L'audit des niveaux du 2026-08-09 en a retiré trois notes qui
 * décrivaient une montée en profondeur qu'aucun collecteur ne faisait : `audio`
 * et `startup`, dont les deux scanners rendaient exactement la même chose à
 * tous les niveaux, et `events`, dont la fenêtre est celle du journal entier
 * dès le niveau Normale.
 */
export const SECTION_DEPTH_NOTES: Readonly<Partial<Record<LevelSection, string>>> = {
  cpus: 'Le résumé n’échantillonne pas la charge et n’interroge pas le SMBIOS pour le socket.',
  memory: 'Le résumé ne lit pas les modules DIMM un par un (SMBIOS, privilèges requis).',
  gpus: 'Le résumé n’énumère pas les sorties d’affichage connectées.',
  storage:
    'Le résumé n’interroge pas SMART ni les ensembles RAID/ZFS/LVM ; l’approfondie ajoute la table complète des attributs SMART.',
  network: 'Le résumé ne liste ni les ports en écoute, ni les routes, ni le proxy.',
  security:
    'Le résumé se limite au pare-feu et au démarrage sécurisé : ni mises à jour en attente, ni comptes, ni durcissement.',
  devices: 'Le résumé énumère le bus PCI ; la collecte complète ajoute le bus USB.',
  virtualization: 'Le résumé compte les invités sans détailler leur configuration.',
  stability:
    'Le résumé lit l’uptime, les unités en échec et le noyau souillé ; la collecte complète y ajoute les compteurs d’incidents par catégorie, qui exigent de parcourir le journal.',
};

/**
 * Charge imposée à une ressource pendant l'audit.
 *
 * `idle` ne veut pas dire « aucun cycle consommé » — lire des compteurs en
 * coûte toujours quelques-uns — mais « rien qui se remarque sur une machine en
 * production ». La distinction compte : c'est elle qui permet de dire à un
 * administrateur s'il peut lancer l'audit sur un serveur en pleine journée.
 */
export type ResourceLoad = 'idle' | 'light' | 'sustained';

export interface LevelResourceLoad {
  readonly cpu: ResourceLoad;
  readonly gpu: ResourceLoad;
  readonly memory: ResourceLoad;
  readonly disk: ResourceLoad;
}

/**
 * Ce que le niveau fait subir à la machine auditée, au-delà de la lecture.
 *
 * Cette structure existe parce que l'interface disait « Lecture seule » de trois
 * niveaux sur quatre en se contentant de nier `loadsMachine`. C'était faux deux
 * fois : le niveau Complète accepte `--install-deps`, qui installe un paquet
 * après accord, et le banc d'essai du niveau Poussée écrit un fichier
 * temporaire. Un administrateur qui lit « aucune écriture » sur un serveur de
 * production a le droit que ce soit vrai.
 *
 * `badge` et `statement` sont écrits ici, et non déduits, parce qu'une phrase
 * fabriquée par concaténation aurait été moins claire que celle qu'on aurait
 * écrite ; un test vérifie en revanche qu'aucun des deux ne peut prétendre à la
 * lecture seule quand `writes` ou `mayInstallTools` disent le contraire.
 */
export interface LevelSystemImpact {
  /** Étiquette courte des cartes de niveau. */
  readonly badge: string;
  /** La phrase complète, telle que la page du niveau l'affiche. */
  readonly statement: string;
  /**
   * Le niveau accepte-t-il `--install-deps` ?
   *
   * Il ne dit pas qu'une installation aura lieu : elle exige en plus l'option
   * explicite, les privilèges, un terminal et un accord outil par outil
   * (ADR 0008). Il dit que ce niveau est le seul endroit où la question peut
   * être posée — et une commande copiée depuis le site ne la pose jamais, car
   * elle ne passe pas l'option.
   */
  readonly mayInstallTools: boolean;
  /**
   * Écritures faites par le niveau lui-même, hors installation d'outils.
   *
   * Vide pour trois niveaux sur quatre, et c'est l'information utile.
   */
  readonly writes: readonly string[];
}

export interface DiagnosticLevelProfile {
  readonly label: string;
  /** Option du scanner Linux (`--full`) ; `standard` est le défaut, sans option. */
  readonly cliFlag: string | null;
  /** Suffixe d'URL d'amorçage (`/audit/l/f`). */
  readonly urlAlias: string;
  readonly summary: string;
  /** Cible UX, en secondes. Mesurée puis ajustée, jamais promise à l'aveugle. */
  readonly targetDurationSeconds: { readonly min: number; readonly max: number };
  /** Le niveau charge-t-il volontairement la machine ? */
  readonly loadsMachine: boolean;
  /** Privilèges administrateur : indispensables ou seulement souhaitables. */
  readonly privileges: 'recommended' | 'required';
  /**
   * Charge imposée, ressource par ressource.
   *
   * Un test exige que seuls les niveaux `loadsMachine` déclarent une charge
   * `sustained` : les deux affirmations ne peuvent plus diverger, et la page ne
   * peut plus promettre un audit discret sur un niveau qui ne l'est pas.
   */
  readonly load: LevelResourceLoad;
  /** Écritures et installations possibles à ce niveau, et rien de plus. */
  readonly systemImpact: LevelSystemImpact;
  /**
   * Ce que ce niveau **exécute** activement, par opposition à ce qu'il lit.
   *
   * Vide pour les niveaux purement passifs, et c'est l'information la plus utile
   * de la liste : elle dit qu'il n'y a rien à craindre.
   */
  readonly activeTests: readonly string[];
  /** Ce qui peut mal se passer, et ce qui l'empêche. */
  readonly risks: readonly string[];
}

export const DIAGNOSTIC_LEVEL_PROFILES: Readonly<Record<DiagnosticLevel, DiagnosticLevelProfile>> =
  {
    quick: {
      label: 'Rapide',
      cliFlag: '--quick',
      urlAlias: 'q',
      summary:
        'Inventaire essentiel sans dépendance lourde : identité machine, résumé CPU/RAM/stockage, réseau et premiers signaux de sécurité.',
      targetDurationSeconds: { min: 30, max: 120 },
      loadsMachine: false,
      privileges: 'recommended',
      load: { cpu: 'idle', gpu: 'idle', memory: 'idle', disk: 'idle' },
      systemImpact: {
        badge: 'Lecture seule',
        statement:
          'Collecte en lecture seule : rien n’est écrit sur la machine, et aucun outil ne peut y être installé — à ce niveau, l’option d’installation est refusée même si elle est demandée.',
        mayInstallTools: false,
        writes: [],
      },
      activeTests: [],
      risks: [
        'Aucun. Le niveau ne lit que des compteurs déjà tenus par le système.',
        'Sans privilèges, une partie du matériel reste non lisible : l’absence est déclarée, jamais devinée.',
      ],
    },
    standard: {
      label: 'Normale',
      cliFlag: null,
      urlAlias: '',
      summary:
        'Inventaire matériel complet, santé SMART principale, capteurs, réseau et sécurité. Le point de départ de la plupart des audits.',
      targetDurationSeconds: { min: 120, max: 300 },
      loadsMachine: false,
      privileges: 'required',
      load: { cpu: 'idle', gpu: 'idle', memory: 'idle', disk: 'light' },
      systemImpact: {
        badge: 'Lecture seule',
        statement:
          'Collecte en lecture seule : rien n’est écrit sur la machine, et aucun outil ne peut y être installé — à ce niveau, l’option d’installation est refusée même si elle est demandée.',
        mayInstallTools: false,
        writes: [],
      },
      activeTests: [],
      risks: [
        'Aucune écriture. La lecture SMART interroge le contrôleur du disque, sans y écrire.',
        'Sur un disque déjà mourant, une lecture SMART peut être lente : l’audit poursuit et déclare l’incident plutôt que de s’interrompre.',
      ],
    },
    full: {
      label: 'Complète',
      cliFlag: '--full',
      urlAlias: 'f',
      summary:
        'Ajoute l’inventaire logiciel, les pilotes, les périphériques USB et la table SMART détaillée. La meilleure base pour les règles et l’analyse IA.',
      targetDurationSeconds: { min: 300, max: 720 },
      loadsMachine: false,
      privileges: 'required',
      load: { cpu: 'light', gpu: 'idle', memory: 'idle', disk: 'light' },
      systemImpact: {
        badge: 'Lecture seule par défaut',
        statement:
          'Collecte approfondie, en lecture seule par défaut : la commande proposée par ce site n’installe rien. Lancé à la main avec `--install-deps`, ce niveau peut proposer d’installer un outil manquant depuis les dépôts de la distribution — un par un, chacun affiché avant d’être accepté, puis retiré en fin d’audit si SysAudit l’avait ajouté.',
        mayInstallTools: true,
        writes: [],
      },
      activeTests: [],
      risks: [
        'Aucune écriture. L’inventaire logiciel interroge le gestionnaire de paquets, qui n’installe rien.',
        'Sur une machine à plusieurs milliers de paquets, l’énumération occupe un cœur quelques dizaines de secondes.',
        'La liste est bornée : au-delà, le rapport le déclare tronqué plutôt que de grossir sans fin.',
      ],
    },
    stress: {
      label: 'Poussée',
      cliFlag: '--stress',
      urlAlias: 's',
      summary:
        'Tout le niveau Complète, plus un banc d’essai qui sollicite volontairement la machine sous surveillance thermique, dont dix minutes de charge soutenue.',
      /**
       * Plancher **mesuré**, pas estimé : 13 min 39 s sur la machine de
       * référence (docs/technique/PERFORMANCE.md), deux mesures y ayant été écartées
       * faute d'outil. La borne basse est ramenée à douze minutes pour ne pas
       * annoncer plus long que ce qui a été observé ; la borne haute couvre les
       * machines lentes et les mesures que celle-ci n'a pas pu exécuter.
       */
      targetDurationSeconds: { min: 720, max: 2700 },
      loadsMachine: true,
      privileges: 'required',
      load: { cpu: 'sustained', gpu: 'light', memory: 'sustained', disk: 'sustained' },
      systemImpact: {
        badge: 'Charge et écriture temporaire',
        statement:
          'Diagnostic poussé : le banc d’essai sollicite volontairement le matériel sous surveillance thermique et écrit un fichier temporaire pour mesurer le débit du stockage — la seule écriture de tout le produit, supprimée dès la mesure terminée. Lancé à la main avec `--install-deps`, ce niveau peut en outre proposer d’installer un outil manquant, chacun affiché avant d’être accepté.',
        mayInstallTools: true,
        writes: [
          'Un fichier temporaire, le temps de mesurer le débit du stockage, supprimé ensuite. Le test s’abstient s’il n’y a pas assez d’espace libre.',
        ],
      },
      activeTests: [
        'Charge processeur mono-cœur et multi-cœur, puis dix minutes de charge soutenue',
        'Débit mémoire en lecture, écriture et copie',
        'Débit de stockage séquentiel et accès aléatoires, dans un fichier temporaire supprimé ensuite',
      ],
      risks: [
        'La machine est **volontairement** sollicitée : ventilateurs audibles, réactivité réduite, consommation en hausse. À éviter sur un serveur en production aux heures ouvrées.',
        'Le banc d’essai surveille la température et **s’arrête de lui-même** au-delà des seuils publiés par les capteurs. L’arrêt est déclaré dans le rapport, il ne se lit pas comme une mesure manquante.',
        'Le test de stockage écrit dans un fichier temporaire — c’est la seule écriture de tout le produit — puis le supprime. Il exige de l’espace libre, et s’abstient s’il n’y en a pas assez.',
        'Sur un portable sur batterie, la charge soutenue vide l’accumulateur et fait souvent brider le processeur : la mesure décrit alors le bridage, pas la machine.',
      ],
    },
  };

export const RESOURCE_LOAD_LABELS: Readonly<Record<ResourceLoad, string>> = {
  idle: 'Négligeable',
  light: 'Légère',
  sustained: 'Soutenue',
};

type Plan = Readonly<Record<DiagnosticLevel, Readonly<Record<LevelSection, CollectionDepth>>>>;

/**
 * La matrice. Une colonne par niveau, une ligne par section.
 *
 * Elle se lit comme un engagement : ce que l'utilisateur obtient en échange du
 * temps qu'il accepte de donner.
 */
export const LEVEL_PLAN: Plan = {
  /*
   * Le niveau Rapide s'est enrichi le 2026-08-16 de six sections, sur mesure et
   * non au jugé.
   *
   * Il annonce 30 à 120 secondes et en prenait **dix** : le budget promis était
   * dépensé au tiers de sa borne basse, et six sections en étaient absentes
   * pour un coût cumulé de 1,9 seconde — la carte mère et le BIOS coûtent
   * 40 et 30 millisecondes, l'alimentation 190. Les laisser dehors ne
   * protégeait rien ; cela privait simplement l'utilisateur d'un diagnostic
   * qu'il aurait eu pour presque rien.
   *
   * `events` reste dehors, et c'est la seule exclusion motivée par autre chose
   * que le coût mesuré : sa fenêtre est le journal entier, dont la taille ne
   * dépend pas de SysAudit. Ce qu'il coûte sur une machine de bureau ne dit
   * rien de ce qu'il coûterait sur un serveur qui journalise depuis six mois.
   *
   * Les trois grosses sections — `devices` (7,4 s), `software` (9,9 s),
   * `startup` (4,4 s) — restent au niveau supérieur : chacune, à elle seule,
   * pèse plus lourd que les six nouvelles réunies.
   */
  quick: {
    system: 'standard',
    os: 'standard',
    motherboard: 'standard',
    bios: 'standard',
    cpus: 'summary',
    memory: 'summary',
    gpus: 'summary',
    audio: 'summary',
    sensors: 'standard',
    power: 'standard',
    storage: 'summary',
    network: 'summary',
    devices: 'skipped',
    drivers: 'skipped',
    software: 'skipped',
    startup: 'skipped',
    security: 'summary',
    virtualization: 'summary',
    stability: 'summary',
    boot: 'standard',
    shutdown: 'standard',
    events: 'skipped',
    benchmark: 'skipped',
  },
  /*
   * Le niveau Normale a reçu l'inventaire complet le 2026-08-16.
   *
   * Il annonce 2 à 5 minutes et en prenait 27 secondes. Trois sections
   * l'attendaient au niveau supérieur pour un coût mesuré de 20 secondes :
   * les périphériques USB, les pilotes et les logiciels. Un audit « complet
   * sans charge lourde » qui ne dit pas quels logiciels sont installés ne
   * mérite pas son nom, et le temps qu'il fallait pour le savoir tenait dans
   * le budget annoncé six fois.
   *
   * Ce que le niveau Complète garde pour lui n'est donc plus une liste de
   * sections, mais une **profondeur** : la table SMART complète et les sondes
   * thermiques approfondies. C'est un engagement plus honnête que le précédent
   * — le niveau supérieur regarde mieux, il ne regarde plus ailleurs.
   */
  standard: {
    system: 'standard',
    os: 'standard',
    motherboard: 'standard',
    bios: 'standard',
    cpus: 'standard',
    memory: 'standard',
    gpus: 'standard',
    // `summary` à tous les niveaux : les deux scanners rendent le même
    // inventaire de périphériques audio, sans topologie des flux. Voir l'audit
    // des niveaux (roadmap ATLAS, chantier 06).
    audio: 'summary',
    sensors: 'standard',
    power: 'standard',
    storage: 'standard',
    network: 'standard',
    devices: 'standard',
    drivers: 'standard',
    software: 'standard',
    startup: 'summary',
    security: 'standard',
    virtualization: 'standard',
    stability: 'standard',
    boot: 'standard',
    shutdown: 'standard',
    // `standard` dès ce niveau : la fenêtre du journal est celle des trente
    // jours, et les deux sévérités sont lues. Le `summary` qui figurait ici
    // décrivait une collecte moins coûteuse que celle réellement faite.
    events: 'standard',
    benchmark: 'skipped',
  },
  full: {
    system: 'standard',
    os: 'standard',
    motherboard: 'standard',
    bios: 'standard',
    cpus: 'standard',
    memory: 'standard',
    gpus: 'standard',
    audio: 'summary',
    sensors: 'extended',
    power: 'standard',
    storage: 'extended',
    network: 'standard',
    devices: 'standard',
    drivers: 'standard',
    software: 'standard',
    // `summary` : aucun scanner ne reconstitue la chaîne de dépendances ni la
    // ligne de commande des unités. Monter la case ici promettait une collecte
    // que le niveau Normale rendait déjà à l'identique.
    startup: 'summary',
    security: 'standard',
    virtualization: 'standard',
    stability: 'standard',
    boot: 'standard',
    shutdown: 'standard',
    events: 'standard',
    benchmark: 'skipped',
  },
  stress: {
    system: 'standard',
    os: 'standard',
    motherboard: 'standard',
    bios: 'standard',
    cpus: 'standard',
    memory: 'standard',
    gpus: 'standard',
    audio: 'summary',
    sensors: 'extended',
    power: 'standard',
    storage: 'extended',
    network: 'standard',
    devices: 'standard',
    drivers: 'standard',
    software: 'standard',
    startup: 'summary',
    security: 'standard',
    virtualization: 'standard',
    stability: 'standard',
    boot: 'standard',
    shutdown: 'standard',
    events: 'standard',
    benchmark: 'standard',
  },
};

/** Scanners soumis à la matrice. */
export const LEVEL_SCANNERS = ['linux', 'windows'] as const;
export type LevelScanner = (typeof LEVEL_SCANNERS)[number];

/**
 * Plafonds propres à un scanner, avec la raison.
 *
 * Un scanner peut collecter **moins** que ce que le niveau demande — jamais
 * plus. Chaque écart est déclaré ici avec son motif : c'est ce qui distingue
 * une limite connue d'un oubli, et ce que la documentation générée affiche.
 */
export interface ScannerSectionCap {
  readonly depth: CollectionDepth;
  readonly reason: string;
}

export const SCANNER_SECTION_CAPS: Readonly<
  Record<LevelScanner, Readonly<Partial<Record<LevelSection, ScannerSectionCap>>>>
> = {
  linux: {},
  windows: {
    /*
     * L'énumération PnP est écrite depuis la v0.113.0 (`Win32_PnPEntity`,
     * `Win32_PnPSignedDriver`) : l'état, le constructeur, la classe et le pilote
     * associé de chaque périphérique sont collectés, et les six contrôles
     * pilotes du moteur d'analyse s'évaluent enfin sous Windows.
     *
     * Le plafond reste, à `summary` et non plus `skipped`, pour une raison qui
     * ne se lèvera pas en écrivant du code : **Windows n'expose pas la largeur
     * négociée des liens PCIe par CIM**. Là où Linux lit `lspci -vv` et permet
     * de constater une carte en x4 sur un lien x16, Windows n'a pas de source
     * équivalente, et la déduire du modèle serait une supposition. `PRF-005`
     * reste donc non évaluable sous Windows, et le rapport le dit au lieu de
     * conclure que le lien est correct.
     */
    devices: {
      depth: 'summary',
      reason:
        'L’énumération PnP donne l’état, le constructeur et la classe de chaque périphérique, mais Windows n’expose pas la largeur négociée des liens PCIe : un lien bridé y reste indétectable.',
    },
    drivers: {
      depth: 'summary',
      reason:
        'Version, date, éditeur et signature de chaque pilote sont lus ; aucune version disponible n’est établie, faute d’une source constructeur qu’un scanner hors ligne ne peut pas consulter.',
    },
    // Le plafond de `startup` a disparu d'ici : la matrice elle-même s'arrête
    // désormais à `summary` pour cette section, sur les deux scanners. Ce qui
    // manque à Windows — l'ensemble des mécanismes d'auto-démarrage, au-delà
    // des clés Run — n'est donc plus un écart, mais la limite commune.
    network: {
      depth: 'summary',
      reason:
        'La table de routage est lue (`Get-NetRoute`), mais ni les ports en écoute ni le proxy : deux des trois sondes du niveau Normale ne sont pas écrites pour Windows, et les suffixes de recherche DNS pas davantage.',
    },
    security: {
      depth: 'summary',
      reason:
        'Pare-feu, Defender et démarrage sécurisé sont lus, mais les mises à jour en attente, les comptes et les protocoles obsolètes ne le sont pas — le collecteur n’est pas écrit, la source existe.',
    },
    storage: {
      depth: 'standard',
      reason:
        '`Get-StorageReliabilityCounter` donne l’usure, la température et les compteurs d’erreurs, mais pas la table complète des attributs SMART : le stockage n’atteint donc pas la profondeur approfondie (étape 04).',
    },
    benchmark: {
      depth: 'summary',
      reason:
        'Le stockage est mesuré en débit réel, mais le processeur, la mémoire et le GPU ne le sont qu’en indices WinSAT — comparables entre machines Windows, pas à un débit. Aucune charge soutenue, aucun relevé thermique : Windows n’expose pas de capteur fiable sans composant tiers.',
    },
  },
};

function capPlan(
  plan: Plan,
  caps: Readonly<Partial<Record<LevelSection, ScannerSectionCap>>>,
): Plan {
  const result = {} as Record<DiagnosticLevel, Record<LevelSection, CollectionDepth>>;
  for (const level of DIAGNOSTIC_LEVELS) {
    const row = {} as Record<LevelSection, CollectionDepth>;
    for (const section of LEVEL_SECTIONS) {
      const wanted = plan[level][section];
      const cap = caps[section];
      row[section] =
        cap !== undefined && DEPTH_RANK[cap.depth] < DEPTH_RANK[wanted] ? cap.depth : wanted;
    }
    result[level] = row;
  }
  return result;
}

/** Ce que chaque scanner fait réellement, une fois ses plafonds appliqués. */
export const SCANNER_LEVEL_PLANS: Readonly<Record<LevelScanner, Plan>> = {
  linux: capPlan(LEVEL_PLAN, SCANNER_SECTION_CAPS.linux),
  windows: capPlan(LEVEL_PLAN, SCANNER_SECTION_CAPS.windows),
};

/** Profondeur exigée par un niveau, indépendamment du scanner. */
export function levelDepth(level: DiagnosticLevel, section: LevelSection): CollectionDepth {
  return LEVEL_PLAN[level][section];
}

/** Profondeur réellement atteinte par un scanner à ce niveau. */
export function scannerDepth(
  scanner: LevelScanner,
  level: DiagnosticLevel,
  section: LevelSection,
): CollectionDepth {
  return SCANNER_LEVEL_PLANS[scanner][level][section];
}

/** Normalise un profil reçu (alias historique compris) ; `null` si inconnu. */
export function normalizeDiagnosticLevel(value: string | undefined): DiagnosticLevel | null {
  if (value === undefined) return null;
  if ((DIAGNOSTIC_LEVELS as readonly string[]).includes(value)) return value as DiagnosticLevel;
  return LEGACY_LEVEL_ALIASES[value] ?? null;
}

/**
 * Niveau désigné par un suffixe d'URL d'amorçage (`/audit/l/f`).
 *
 * Le suffixe vide désigne le niveau par défaut. `null` pour un suffixe inconnu :
 * l'API répond alors 404 plutôt que de lancer un audit qui ne serait pas celui
 * demandé.
 */
export function levelForUrlAlias(alias: string): DiagnosticLevel | null {
  const match = DIAGNOSTIC_LEVELS.find(
    (level) => DIAGNOSTIC_LEVEL_PROFILES[level].urlAlias === alias,
  );
  return match ?? null;
}

/*
 * `bootstrapCommand` vivait ici. Il est parti dans `audit-command.ts`, avec
 * tout ce qui compose une commande SysAudit : le chemin d'URL, les options et
 * le code de liaison se décidaient à trois endroits, et le troisième avait
 * fini par diverger des deux autres.
 */

/** Sections collectées à ce niveau, dans l'ordre de la matrice. */
export function sectionsAtLevel(
  level: DiagnosticLevel,
  scanner?: LevelScanner,
): readonly LevelSection[] {
  const plan = scanner === undefined ? LEVEL_PLAN : SCANNER_LEVEL_PLANS[scanner];
  return LEVEL_SECTIONS.filter((section) => plan[level][section] !== 'skipped');
}

/**
 * Ce que ce niveau apporte de plus que le précédent, en clair.
 *
 * Déduit de la matrice — donc incapable de promettre une profondeur que la
 * matrice n'annonce pas. Il restait pourtant un écart, et il était réel : la
 * matrice ignore les **plafonds de scanner**, si bien que `/diagnostics`
 * annonçait « Périphériques » et « Pilotes » au niveau Complète, que le scanner
 * Windows ne collecte à aucun niveau.
 *
 * Passer un `scanner` rend ce que **ce** scanner collecte réellement. Sans
 * argument, le comportement d'avant est conservé : la promesse commune, tous
 * scanners confondus.
 */
export function levelHighlights(level: DiagnosticLevel, scanner?: LevelScanner): readonly string[] {
  const index = DIAGNOSTIC_LEVELS.indexOf(level);
  const previous = index > 0 ? DIAGNOSTIC_LEVELS[index - 1] : undefined;
  const plan = scanner === undefined ? LEVEL_PLAN : SCANNER_LEVEL_PLANS[scanner];

  return LEVEL_SECTIONS.flatMap((section) => {
    const depth = plan[level][section];
    if (depth === 'skipped') return [];
    const before = previous === undefined ? 'skipped' : plan[previous][section];
    if (previous !== undefined && DEPTH_RANK[depth] <= DEPTH_RANK[before]) return [];
    const label = SECTION_LABELS[section];
    if (depth === 'summary') return [`${label} (résumé)`];
    if (depth === 'extended') return [`${label} — collecte approfondie`];
    return [before === 'skipped' ? label : `${label} — collecte complète`];
  });
}

/** Ce qu'un scanner ne collecte pas, alors que le niveau l'annonce. */
export interface LevelScannerGap {
  readonly section: LevelSection;
  readonly label: string;
  /** `true` quand la section n'est pas collectée du tout à ce niveau. */
  readonly absent: boolean;
  readonly reason: string;
}

/**
 * Écarts entre ce que le niveau promet et ce qu'un scanner livre.
 *
 * **C'est la moitié manquante de `levelHighlights`.** Afficher la seule
 * promesse commune fait mentir la page pour Windows ; afficher la seule
 * intersection la ferait mentir pour Linux, qui est la majorité des audits.
 * Publier les deux — ce que ce niveau ajoute, puis ce qui manque sur telle
 * plateforme — est la seule option qui ne remplace pas une phrase fausse par
 * une autre.
 *
 * La page les affiche côte à côte plutôt que de choisir selon l'OS détecté :
 * `/diagnostics` se lit **avant** de choisir la machine à auditer, et un
 * technicien la consulte souvent depuis un poste qui n'est pas celui qu'il
 * auditera. C'est le raisonnement qui a déjà fait garder les trois onglets du
 * panneau de commande.
 */
export function levelScannerGaps(
  level: DiagnosticLevel,
  scanner: LevelScanner,
): readonly LevelScannerGap[] {
  const caps = SCANNER_SECTION_CAPS[scanner];

  return LEVEL_SECTIONS.flatMap((section) => {
    const wanted = LEVEL_PLAN[level][section];
    if (wanted === 'skipped') return [];

    const actual = SCANNER_LEVEL_PLANS[scanner][level][section];
    if (DEPTH_RANK[actual] >= DEPTH_RANK[wanted]) return [];

    const cap = caps[section];
    if (cap === undefined) return [];

    return [
      {
        section,
        label: SECTION_LABELS[section],
        absent: actual === 'skipped',
        reason: cap.reason,
      },
    ];
  });
}
