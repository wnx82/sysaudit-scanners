// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import type { ScannerProfile } from './families.js';
import { SCANNER_SECTION_CAPS, type LevelScanner, type LevelSection } from './diagnostic-levels.js';

/**
 * Matrice de compatibilité — **source de vérité unique**.
 *
 * Elle était jusqu'ici saisie à la main dans deux fichiers Markdown, sans test
 * possible (dette `D-09` de `docs/audits/ARCHITECTURE_AUDIT.md`). Les tableaux
 * Markdown en sont désormais une projection, régénérée par
 * `scripts/generate-compatibility.mjs` et vérifiée par un test.
 *
 * Ce fichier est un **engagement envers l'utilisateur**. Une case ne monte de
 * niveau que lorsque les sept conditions du plan directeur sont réunies :
 * implémentée, fonctionnelle, réellement exécutée, présente dans le JSON,
 * exploitée par le rapport, testée, documentée.
 */

/**
 * Niveaux de support, du plus fort au plus faible.
 *
 * La distinction `VALIDATED` / `IMPLEMENTED` est le cœur du dispositif : du
 * code écrit mais jamais exécuté sur la cible réelle n'est pas du support.
 */
export const SUPPORT_LEVELS = [
  /** Implémenté **et** exécuté sur la cible réelle. */
  'VALIDATED',
  /**
   * Éprouvé sur la cible, mais **une part documentée de la capacité n'est pas
   * collectée**.
   *
   * Ce niveau existe parce que le vocabulaire n'avait pas de case pour ce cas, et
   * que son absence produisait une affirmation fausse là où elle coûte le plus
   * cher. La collecte Sécurité de Windows lit le pare-feu, Defender et le
   * démarrage sécurisé ; elle ne lit ni les comptes, ni les protocoles obsolètes,
   * ni les mises à jour en attente. Elle était pourtant marquée ✅.
   *
   * Ni `VALIDATED` ni `IMPLEMENTED` ne convenait : le premier dit « tout est là »,
   * le second « jamais exécuté sur la cible » — et la collecte Windows **est**
   * exécutée et testée. Les deux mentent, dans deux directions opposées.
   *
   * **Un motif est obligatoire.** Le type l'exige, et il n'est pas saisi à la
   * main : il est dérivé de `SCANNER_SECTION_CAPS`, où chaque plafond de scanner
   * porte déjà sa raison écrite. C'est ce qui répond à la question « à partir de
   * quel pourcentage devient-on partiel ? » — elle devient « peux-tu nommer ce
   * qui manque ? », qui a toujours une réponse.
   */
  'PARTIAL',
  /** Implémenté, non encore exécuté sur la cible réelle. */
  'IMPLEMENTED',
  /** Prévu par la roadmap, aucun code aujourd'hui. */
  'PLANNED',
  /** Rien n'est implémenté et rien n'est décidé. */
  'ABSENT',
  /** Volontairement non supporté. */
  'REFUSED',
  /** La notion n'a pas de sens sur cette cible. */
  'NOT_APPLICABLE',
] as const;
export type SupportLevel = (typeof SUPPORT_LEVELS)[number];

export const SUPPORT_LEVEL_SYMBOLS: Readonly<Record<SupportLevel, string>> = {
  VALIDATED: '✅',
  // Distinct de 🟡 et lisible en niveaux de gris : un lecteur qui parcourt le
  // tableau en diagonale doit voir que ce n'est pas un ✅.
  PARTIAL: '🟠',
  IMPLEMENTED: '🟡',
  PLANNED: '⏳',
  ABSENT: '—',
  REFUSED: '❌',
  NOT_APPLICABLE: 'n/a',
};

export const SUPPORT_LEVEL_LABELS: Readonly<Record<SupportLevel, string>> = {
  VALIDATED: 'implémenté et validé sur la cible',
  PARTIAL: 'éprouvé sur la cible, couverture partielle',
  IMPLEMENTED: 'implémenté, non validé sur la cible',
  PLANNED: 'prévu',
  ABSENT: 'non implémenté',
  REFUSED: 'non supporté volontairement',
  NOT_APPLICABLE: 'sans objet',
};

/** Domaines de collecte suivis par la matrice. */
export const CAPABILITY_KEYS = [
  'hardware',
  'software',
  'storage',
  'smart',
  'network',
  'security',
  'virtualization',
  'monitoring',
  'benchmark',
  'ai',
] as const;
export type CapabilityKey = (typeof CAPABILITY_KEYS)[number];

export const CAPABILITY_LABELS: Readonly<Record<CapabilityKey, string>> = {
  hardware: 'Matériel',
  software: 'Logiciel',
  storage: 'Stockage',
  smart: 'SMART',
  network: 'Réseau',
  security: 'Sécurité',
  virtualization: 'Virtualisation',
  monitoring: 'Monitoring',
  benchmark: 'Benchmark',
  ai: 'IA',
};

/** Colonnes du tableau publié aujourd'hui dans `docs/COMPATIBILITY.md`. */
export const CURRENT_CAPABILITY_COLUMNS: readonly CapabilityKey[] = [
  'hardware',
  'software',
  'storage',
  'smart',
  'network',
  'security',
  'virtualization',
  'ai',
];

/** Colonnes du tableau cible, monitoring et banc d'essai compris. */
export const TARGET_CAPABILITY_COLUMNS: readonly CapabilityKey[] = CAPABILITY_KEYS;

/**
 * État d'une capacité sur une cible.
 *
 * Union discriminée plutôt qu'un objet à champs facultatifs : `PARTIAL` **exige**
 * son motif, et le compilateur le refuse sans. Un niveau « partiel » sans
 * explication redeviendrait le fourre-tout que ce niveau existe pour éviter — on
 * saurait que quelque chose manque, jamais quoi.
 */
export type CapabilitySupport =
  | {
      readonly level: Exclude<SupportLevel, 'PARTIAL'>;
      /** Précision affichée à côté du symbole (« Docker », « Proxmox »…). */
      readonly note?: string;
      readonly caveat?: never;
    }
  | {
      readonly level: 'PARTIAL';
      readonly note?: string;
      /** Ce qui n'est pas collecté, en clair. Dérivé, jamais saisi à la main. */
      readonly caveat: string;
    };

/**
 * Les deux façades installables, en plus des scanners.
 *
 * Elles n'ont **pas** la même compatibilité que le scanner qu'elles pilotent, et
 * c'était le trou de cette matrice : elle graduait honnêtement ce que chaque
 * collecteur sait faire, et laissait croire par omission que l'application le
 * suivait partout. Un scanner PowerShell et un binaire Electron n'ont ni les
 * mêmes prérequis ni les mêmes planchers de version.
 */
export const CLIENT_KINDS = ['desktop', 'cli'] as const;
export type ClientKind = (typeof CLIENT_KINDS)[number];

export const CLIENT_LABELS: Readonly<Record<ClientKind, string>> = {
  desktop: 'Application',
  cli: 'Ligne de commande',
};

/**
 * État d'une façade sur une cible.
 *
 * Union discriminée, sur le modèle de `CapabilitySupport` : **`VALIDATED` exige
 * sa date d'exécution**, et le compilateur la refuse sans. C'est ce qui rend
 * impossible la case cochée « parce que le code compile » — la seule chose que
 * cette matrice existe pour empêcher.
 *
 * `reason` est obligatoire partout ailleurs aussi : une façade `PLANNED` sans
 * motif laisse chercher ce qui manque, et une façade `IMPLEMENTED` sans motif ne
 * dit pas ce qu'il resterait à faire pour la valider.
 */
export type ClientSupport =
  | {
      readonly level: 'VALIDATED';
      readonly reason: string;
      /** Date de l'exécution réelle, `AAAA-MM-JJ`. Sans elle, pas de validation. */
      readonly verifiedOn: string;
    }
  | {
      readonly level: Exclude<SupportLevel, 'VALIDATED'>;
      readonly reason: string;
      readonly verifiedOn?: never;
    };

/**
 * Ce qui interdit toute façade sur les Windows d'avant 10 1809.
 *
 * Deux obstacles **indépendants**, et lever l'un ne lèverait pas l'autre. Les
 * écrire ici plutôt qu'en note de bas de page évite qu'une page de
 * téléchargement laisse espérer le contraire.
 */
const WINDOWS_TROP_ANCIEN =
  'Electron 43 et Node 20 exigent Windows 10 1809 : ni la fenêtre ni la ligne de commande n’y démarrent. ' +
  'Et le scanner Legacy n’existe pas — le lever ne suffirait donc pas.';

/** Aucune façade ne couvre les systèmes dont le scanner est expérimental. */
const SUIT_SON_SCANNER: ClientSupport = {
  level: 'PLANNED',
  reason:
    'Aucun adaptateur : une façade au-dessus d’un scanner non éprouvé donnerait une fenêtre qui échoue proprement, ce qui n’est pas un progrès.',
};

/**
 * Linux : l'adaptateur existe et il est testé — mais il n'a **jamais tourné**.
 *
 * Ses tests s'exécutent depuis Windows, `buildArguments` étant une fonction
 * pure : ils vérifient la traduction des options, pas qu'un audit aboutit.
 */
const LINUX_JAMAIS_EXECUTE: ClientSupport = {
  level: 'IMPLEMENTED',
  reason: 'Adaptateur écrit et couvert par des tests, jamais exécuté sur une machine Linux réelle.',
};

/** Les deux façades, dans le même état, pour les cas où elles ne diffèrent pas. */
function clients(support: ClientSupport): Readonly<Record<ClientKind, ClientSupport>> {
  return { desktop: support, cli: support };
}

export interface CompatibilityTarget {
  readonly id: string;
  /** Libellé de la première colonne du tableau. */
  readonly label: string;
  readonly scannerProfile: ScannerProfile;
  /** Nom affiché dans la colonne « Scanner ». */
  readonly scannerLabel: string;
  /** Identifiants du catalogue de distributions couverts par cette ligne. */
  readonly distributions: readonly string[];
  readonly capabilities: Readonly<Record<CapabilityKey, CapabilitySupport>>;
}

/**
 * Quelle capacité chaque section de collecte alimente.
 *
 * C'est le seul chaînon entre les deux tables : `SCANNER_SECTION_CAPS` raisonne
 * en **sections** de rapport, la matrice en **capacités**. Sans cette table, il
 * faudrait recopier à la main dans la matrice ce que les plafonds disent déjà —
 * et une note recopiée diverge, exactement comme les tableaux de
 * `COMPATIBILITY.md` avant qu'ils ne soient générés.
 *
 * Toutes les sections y figurent, y compris celles qu'aucun plafond ne touche
 * aujourd'hui : un test vérifie l'exhaustivité, pour qu'une section ajoutée
 * demain ne se retrouve pas silencieusement sans capacité — donc sans motif
 * affiché le jour où elle sera plafonnée.
 *
 * `system` et `os` ne visent aucune colonne : ce sont l'identité de la machine,
 * pas une capacité de collecte. Ils rendent un tableau vide, ce qui est une
 * réponse et non un oubli.
 */
export const SECTION_CAPABILITIES: Readonly<Record<LevelSection, readonly CapabilityKey[]>> = {
  system: [],
  os: [],
  motherboard: ['hardware'],
  bios: ['hardware'],
  cpus: ['hardware'],
  memory: ['hardware'],
  gpus: ['hardware'],
  audio: ['hardware'],
  sensors: ['hardware'],
  power: ['hardware'],
  devices: ['hardware'],
  drivers: ['hardware'],
  // Le stockage alimente deux colonnes : l'inventaire des disques et leur santé
  // SMART. Un plafond sur la section touche donc les deux.
  storage: ['storage', 'smart'],
  network: ['network'],
  security: ['security'],
  software: ['software'],
  startup: ['software'],
  virtualization: ['virtualization'],
  stability: ['monitoring'],
  boot: ['monitoring'],
  shutdown: ['monitoring'],
  events: ['monitoring'],
  benchmark: ['benchmark'],
};

/**
 * Ce qui manque à chaque capacité pour ce scanner, en clair. Vide s'il ne manque
 * rien.
 *
 * Les motifs sont ceux déjà écrits dans `SCANNER_SECTION_CAPS` : cette fonction
 * ne rédige rien, elle regroupe. Plusieurs sections plafonnées visant la même
 * capacité voient leurs motifs joints — c'est le cas de `devices` et `drivers`
 * sous Windows, qui manquent tous deux à « Matériel ».
 */
export function scannerCaveats(
  scanner: LevelScanner,
): Readonly<Partial<Record<CapabilityKey, string>>> {
  const byCapability = new Map<CapabilityKey, string[]>();

  for (const [section, cap] of Object.entries(SCANNER_SECTION_CAPS[scanner])) {
    for (const capability of SECTION_CAPABILITIES[section as LevelSection]) {
      const reasons = byCapability.get(capability) ?? [];
      reasons.push(cap.reason);
      byCapability.set(capability, reasons);
    }
  }

  const result: Partial<Record<CapabilityKey, string>> = {};
  for (const [capability, reasons] of byCapability) result[capability] = reasons.join(' ');
  return result;
}

/**
 * Rabat en `PARTIAL` toute capacité `VALIDATED` qu'un plafond de scanner ampute.
 *
 * **C'est ici que la matrice cesse d'affirmer plus qu'elle ne collecte**, et le
 * fait qu'elle le fasse par calcul plutôt qu'à la main est l'essentiel : une
 * case ne peut plus rester ✅ après qu'un plafond a été déclaré, parce que
 * personne n'a à y penser.
 *
 * Seul `VALIDATED` est concerné. `IMPLEMENTED` dit déjà « non exécuté sur la
 * cible » et ne promet donc pas de couverture complète ; le rabattre n'ajouterait
 * rien et brouillerait les deux sens.
 */
function applyScannerCaveats(
  capabilities: Readonly<Record<CapabilityKey, CapabilitySupport>>,
  scanner: LevelScanner,
): Readonly<Record<CapabilityKey, CapabilitySupport>> {
  const caveats = scannerCaveats(scanner);
  const result = {} as Record<CapabilityKey, CapabilitySupport>;

  for (const key of CAPABILITY_KEYS) {
    const support = capabilities[key];
    const caveat = caveats[key];
    result[key] =
      support.level === 'VALIDATED' && caveat !== undefined
        ? {
            level: 'PARTIAL',
            caveat,
            ...(support.note === undefined ? {} : { note: support.note }),
          }
        : support;
  }
  return result;
}

/**
 * Raccourci de lecture : toutes les cases au même niveau, puis surcharges.
 *
 * `PARTIAL` en est exclu, et pas seulement pour satisfaire le compilateur :
 * « toutes les capacités partielles » n'a pas de sens, puisque chacune doit
 * nommer ce qui lui manque. Le partiel s'obtient par `applyScannerCaveats`, qui
 * le déduit des plafonds — jamais en le posant à plat.
 */
function levels(
  base: Exclude<SupportLevel, 'PARTIAL'>,
  overrides: Partial<Record<CapabilityKey, CapabilitySupport>> = {},
): Readonly<Record<CapabilityKey, CapabilitySupport>> {
  const result = {} as Record<CapabilityKey, CapabilitySupport>;
  for (const key of CAPABILITY_KEYS) result[key] = overrides[key] ?? { level: base };
  return result;
}

/**
 * L'analyse IA fonctionne sur tout rapport valide, quel que soit l'OS : elle ne
 * dépend que du JSON. Elle est donc `VALIDATED` partout où un rapport existe,
 * et `PLANNED` là où aucun scanner ne produit encore de rapport.
 */
const AI_VALIDATED: CapabilitySupport = { level: 'VALIDATED' };

/**
 * Monitoring et banc d'essai ont été livrés par les étapes 10 et 11 côté Linux,
 * puis portés sur Windows. Les deux scanners les produisent désormais ; ce qui
 * les distingue est la **profondeur**, déclarée dans `SCANNER_SECTION_CAPS` et
 * non ici : le banc d'essai Windows publie des indices WinSAT là où Linux
 * publie des débits.
 */
const LINUX_ONLY: CapabilitySupport = { level: 'IMPLEMENTED' };

const LINUX_PARTIAL = levels('IMPLEMENTED', {
  monitoring: LINUX_ONLY,
  benchmark: LINUX_ONLY,
  ai: AI_VALIDATED,
});

/**
 * Ce qu'un conteneur LXC permet — et ne permet pas — de valider.
 *
 * Un conteneur partage le noyau de l'hôte : il n'a ni `dmidecode`, ni disque
 * physique, ni compteur SMART, et son pare-feu est celui de l'hôte. Y faire
 * tourner le scanner valide donc exactement deux choses, mais réellement :
 *
 *   - le **gestionnaire de paquets** de la distribution, qui est la seule
 *     différence de fond entre les distributions du point de vue du scanner ;
 *   - l'**observation dans la durée**, qui ne lit que `/proc` et `/sys`.
 *
 * Tout le reste garde son 🟡. Faire monter une ligne entière parce que le
 * scanner a tourné dans un conteneur reviendrait à annoncer une collecte
 * matérielle que rien n'a exercée.
 */
const LINUX_VALIDATED_IN_CONTAINER = levels('IMPLEMENTED', {
  software: { level: 'VALIDATED' },
  monitoring: { level: 'VALIDATED' },
  benchmark: LINUX_ONLY,
  ai: AI_VALIDATED,
});

/**
 * Debian 13 sur machine physique, hôte Proxmox VE — profil complet, exécuté.
 *
 * Le banc d'essai reste 🟡 : il n'a pas été lancé, parce qu'il charge
 * volontairement la machine et que celle-ci héberge la production.
 */
const DEBIAN_VALIDATED = levels('VALIDATED', {
  benchmark: LINUX_ONLY,
});

/**
 * Windows 11 / 10 — validé sur machine réelle.
 *
 * Campagne `npm run validate:windows` sur un poste Windows 11 Professionnel,
 * Windows PowerShell 5.1, session administrateur : les six profils ont produit
 * un rapport accepté par `validateReport()`, et les neuf domaines ont livré une
 * valeur réelle plutôt qu'un marqueur.
 *
 * Trois défauts avaient dû être corrigés pour y parvenir, tous invisibles hors
 * d'une exécution réelle : `ipv4`/`ipv6` sérialisés en objet dès qu'une carte
 * portait une seule adresse, un motif d'absence hors énumération, et — côté
 * matrice — `smart` et `benchmark` déclarés absents alors que le code les
 * produisait.
 *
 * **La profondeur n'est plus distincte de la validation, et c'est une correction.**
 * Ce commentaire disait jusqu'au 2026-08-11 : « la case dit que la collecte a eu
 * lieu, le plafond dit jusqu'où elle va ». Le raisonnement tenait pour un
 * stockage lu moins profondément ; il ne tenait pas pour la Sécurité, où des
 * pans entiers ne sont **pas lus du tout** — ni les comptes, ni les protocoles
 * obsolètes, ni les mises à jour en attente. Un ✅ sur cette colonne se lisait
 * comme une bonne nouvelle, et c'est précisément le raisonnement que ce dépôt
 * s'interdit partout ailleurs : conclure d'une donnée absente.
 *
 * `applyScannerCaveats` rabat donc en 🟠 toute capacité qu'un plafond ampute, en
 * y joignant le motif déjà écrit dans `SCANNER_SECTION_CAPS`. Rien n'est saisi
 * ici : la liste des colonnes concernées se déduit des plafonds, et suivra
 * d'elle-même le jour où un collecteur Windows manquant sera écrit.
 */
const WINDOWS_11_10 = applyScannerCaveats(levels('VALIDATED'), 'windows');

/**
 * Windows Server — même scanner, mais **aucune exécution observée**.
 *
 * La ligne n'hérite pas de la validation du poste client, et la différence
 * n'est pas théorique : Server Core n'a pas `Get-AppxPackage`, WinSAT n'y est
 * pas installé par défaut — donc ni l'inventaire des applications empaquetées
 * ni le banc d'essai n'y sont acquis — et les profils de pare-feu diffèrent.
 * Recopier ✅ d'une ligne à l'autre serait exactement la promesse que cette
 * matrice s'interdit.
 */
const WINDOWS_SERVER = levels('IMPLEMENTED', { ai: AI_VALIDATED });

export const COMPATIBILITY_TARGETS: readonly CompatibilityTarget[] = [
  {
    id: 'ubuntu',
    label: 'Ubuntu 24.04',
    scannerProfile: 'linux',
    scannerLabel: 'Linux',
    distributions: ['ubuntu'],
    capabilities: levels('IMPLEMENTED', {
      // Exécuté sur Ubuntu 24.04 : paquets apt et snap, gestionnaires,
      // runtimes, services et modules noyau collectés, validés contre le
      // schéma et rendus par les trois sorties.
      software: { level: 'VALIDATED', note: 'apt · snap' },
      storage: { level: 'VALIDATED' },
      network: { level: 'VALIDATED' },
      security: { level: 'VALIDATED' },
      virtualization: { level: 'VALIDATED', note: 'Docker' },
      // Exécutés sur Ubuntu 24.04 : trois relevés cohérents pour l'observation,
      // et cinq mesures abouties pour le banc d'essai.
      monitoring: { level: 'VALIDATED' },
      benchmark: { level: 'VALIDATED', note: 'CPU · RAM · disque' },
      ai: AI_VALIDATED,
    }),
  },
  {
    id: 'debian',
    label: 'Debian 12/13',
    scannerProfile: 'linux',
    scannerLabel: 'Linux',
    distributions: ['debian'],
    capabilities: DEBIAN_VALIDATED,
  },
  {
    id: 'linuxmint',
    label: 'Linux Mint',
    scannerProfile: 'linux',
    scannerLabel: 'Linux',
    distributions: ['linuxmint'],
    capabilities: LINUX_PARTIAL,
  },
  {
    id: 'fedora',
    label: 'Fedora',
    scannerProfile: 'linux',
    scannerLabel: 'Linux',
    distributions: ['fedora'],
    capabilities: LINUX_VALIDATED_IN_CONTAINER,
  },
  {
    id: 'rocky-alma',
    label: 'Rocky / AlmaLinux',
    scannerProfile: 'linux',
    scannerLabel: 'Linux',
    distributions: ['rocky', 'almalinux'],
    // Rocky Linux 10 exécuté ; AlmaLinux partage la même famille RPM et le même
    // `dnf`, et le scanner ne les distingue pas. La ligne les groupe pour cette
    // raison.
    capabilities: LINUX_VALIDATED_IN_CONTAINER,
  },
  {
    id: 'arch-manjaro',
    label: 'Arch / Manjaro',
    scannerProfile: 'linux',
    scannerLabel: 'Linux',
    distributions: ['arch', 'manjaro'],
    capabilities: LINUX_VALIDATED_IN_CONTAINER,
  },
  {
    id: 'raspberry-pi-os',
    label: 'Raspberry Pi OS',
    scannerProfile: 'linux',
    scannerLabel: 'Linux',
    distributions: ['raspberry-pi-os'],
    capabilities: LINUX_PARTIAL,
  },
  {
    id: 'proxmox-ve',
    label: 'Proxmox VE 8/9',
    scannerProfile: 'proxmox',
    scannerLabel: 'Proxmox',
    distributions: ['proxmox-ve'],
    // Hôte Proxmox VE 9.2.4 sur Debian 13, profil complet exécuté : nœud,
    // sept conteneurs LXC, une machine virtuelle et cinq stockages relus.
    //
    // Banc d'essai exécuté le 2026-08-01 sur le même hôte, profil Poussé :
    // huit mesures abouties sur dix — processeur simple, multi et soutenu,
    // mémoire en lecture, écriture et copie, disque en écriture et lecture
    // séquentielles. Les deux écartées le sont pour un motif publié : pas de
    // GPU sur un hyperviseur sans affichage, et lecture aléatoire non tentée.
    capabilities: levels('VALIDATED', {
      virtualization: { level: 'VALIDATED', note: 'Proxmox' },
      benchmark: { level: 'VALIDATED', note: 'CPU · RAM · disque' },
    }),
  },
  {
    // Le collecteur Windows vit désormais dans `scanners/windows` (étape 17B),
    // avec analyse statique, suite de tests propre et validation de sa sortie
    // contre le schéma. Ces barrières ne tournent que sur un agent Windows :
    // tant qu'aucune exécution verte n'a été observée, ses cases restent
    // `IMPLEMENTED`. Une case ne monte pas sur la promesse d'un test.
    id: 'windows-modern',
    label: 'Windows 11 / 10',
    scannerProfile: 'windows',
    scannerLabel: 'Modern',
    distributions: ['windows'],
    capabilities: WINDOWS_11_10,
  },
  {
    id: 'windows-server',
    label: 'Windows Server',
    scannerProfile: 'windows',
    scannerLabel: 'Modern',
    distributions: ['windows'],
    capabilities: WINDOWS_SERVER,
  },
  {
    id: 'windows-legacy',
    label: 'Windows 8.1 / 8 / 7',
    scannerProfile: 'windows-legacy',
    scannerLabel: 'Legacy',
    distributions: ['windows'],
    capabilities: levels('ABSENT', { ai: AI_VALIDATED }),
  },
  {
    id: 'windows-minimal',
    label: 'Windows Vista / XP',
    scannerProfile: 'windows-minimal',
    scannerLabel: 'Minimal',
    distributions: ['windows'],
    capabilities: levels('PLANNED', {
      // Aucune pile SMART exploitable sur ces versions : c'est un refus, pas
      // un retard.
      smart: { level: 'REFUSED' },
      virtualization: { level: 'NOT_APPLICABLE' },
      ai: AI_VALIDATED,
    }),
  },
  {
    id: 'macos',
    label: 'macOS',
    scannerProfile: 'macos',
    scannerLabel: 'macOS',
    distributions: ['macos'],
    capabilities: levels('PLANNED', { ai: AI_VALIDATED }),
  },
  {
    id: 'bsd',
    label: 'FreeBSD / pfSense / OPNsense',
    scannerProfile: 'bsd',
    scannerLabel: 'BSD',
    distributions: ['freebsd', 'pfsense', 'opnsense'],
    capabilities: levels('PLANNED', { ai: AI_VALIDATED }),
  },
  {
    id: 'android',
    label: 'Android',
    scannerProfile: 'android',
    scannerLabel: 'Android',
    distributions: ['android'],
    capabilities: levels('PLANNED', { ai: AI_VALIDATED }),
  },
];

export function compatibilityTargetById(id: string): CompatibilityTarget | undefined {
  return COMPATIBILITY_TARGETS.find((target) => target.id === id);
}

/** Lignes de la matrice couvrant une distribution du catalogue. */
export function compatibilityForDistribution(
  distributionId: string,
): readonly CompatibilityTarget[] {
  return COMPATIBILITY_TARGETS.filter((target) => target.distributions.includes(distributionId));
}

/**
 * Ce que les façades installables savent faire, cible par cible.
 *
 * Table séparée de `COMPATIBILITY_TARGETS`, et non colonne de plus : les deux
 * répondent à des questions différentes. Celle-là dit ce que le **scanner**
 * collecte ; celle-ci dit si l'utilisateur peut installer quelque chose. Un
 * scanner PowerShell qui tourne partout ne rend pas installable une fenêtre
 * Electron, et c'est exactement l'omission que cette table comble.
 *
 * L'exhaustivité est vérifiée par `compatibility.test.ts`, dans les deux sens :
 * aucune cible sans entrée, aucune entrée sans cible.
 */
export const CLIENT_SUPPORT: Readonly<Record<string, Readonly<Record<ClientKind, ClientSupport>>>> =
  {
    /*
     * La seule cible où les deux façades ont été **exécutées**.
     *
     * `npm run smoke` a ouvert la vraie fenêtre — scanner Windows 0.29.0 trouvé,
     * pont exposé, trois profils affichés — et `sysaudit scan --profile quick` a
     * produit, validé et rangé un rapport, en comptant treize étapes.
     *
     * La ligne couvre Windows 11 **et** 10, et la campagne n'a tourné que sur
     * Windows 11 Pro. C'est le même arbitrage que celui déjà fait pour le
     * scanner sur cette ligne, et `reason` nomme la machine plutôt que de le
     * taire.
     */
    'windows-modern': {
      desktop: {
        level: 'VALIDATED',
        reason:
          'Installateur et portable produits, installés, lancés et désinstallés sur un poste Windows 11 Professionnel — ' +
          'les rapports survivent à la désinstallation. Windows 10 n’a pas été essayé.',
        verifiedOn: '2026-08-27',
      },
      cli: {
        level: 'VALIDATED',
        reason:
          'Archive extraite hors du dépôt, audit Rapide produit puis envoyé et renvoyé sans doublon, sur un poste Windows 11 ' +
          'Professionnel sans élévation. Windows 10 n’a pas été essayé.',
        verifiedOn: '2026-08-27',
      },
    },

    /*
     * Le code est le même que pour le poste client, l'exécution n'a pas eu lieu.
     * La ligne n'hérite pas : c'est la règle de cette matrice depuis le début.
     */
    'windows-server': clients({
      level: 'IMPLEMENTED',
      reason:
        'Rien ne s’y oppose, rien n’y a été exécuté. Server Core n’a par ailleurs pas d’interface graphique.',
    }),

    'windows-legacy': clients({ level: 'PLANNED', reason: WINDOWS_TROP_ANCIEN }),
    'windows-minimal': clients({ level: 'PLANNED', reason: WINDOWS_TROP_ANCIEN }),

    /*
     * Linux : l'adaptateur existe, il est testé — **et il n'a jamais tourné**.
     *
     * Les tests d'adaptateur s'exécutent depuis Windows, parce que
     * `buildArguments` est une fonction pure. Ils vérifient la traduction des
     * options, pas qu'un audit aboutit. Confondre les deux serait exactement ce
     * que `IMPLEMENTED` existe pour empêcher.
     */
    ubuntu: clients(LINUX_JAMAIS_EXECUTE),
    debian: clients(LINUX_JAMAIS_EXECUTE),
    'proxmox-ve': clients(LINUX_JAMAIS_EXECUTE),
    linuxmint: clients(LINUX_JAMAIS_EXECUTE),
    fedora: clients(LINUX_JAMAIS_EXECUTE),
    'rocky-alma': clients(LINUX_JAMAIS_EXECUTE),
    'arch-manjaro': clients(LINUX_JAMAIS_EXECUTE),

    /*
     * Le Raspberry Pi mérite sa propre entrée : le code n'a rien de particulier,
     * mais **aucun paquet ARM64 n'est produit**. Une façade qu'on ne peut pas
     * installer n'est pas une façade disponible.
     */
    /*
     * ARM64 est **déclaré et constructible**, pas produit ni démarré.
     *
     * `electron-builder` sait viser `linux-arm64` depuis le 2026-08-27, et le
     * `win-arm64` a été construit pour de bon ce jour-là — 98 Mo, sur une
     * machine x64. Mais construire n'est pas démarrer, et aucun Raspberry Pi
     * n'a lancé l'AppImage : la case reste ⏳.
     */
    'raspberry-pi-os': clients({
      level: 'PLANNED',
      reason:
        'La cible ARM64 est déclarée et se construit, mais aucun paquet n’a été produit sur une machine Linux, ni lancé sur un Pi.',
    }),

    macos: clients(SUIT_SON_SCANNER),
    bsd: clients(SUIT_SON_SCANNER),
    android: clients(SUIT_SON_SCANNER),
  };

/** Ce que cette façade sait faire sur cette cible, ou `null` si la cible est inconnue. */
export function clientSupport(targetId: string, kind: ClientKind): ClientSupport | null {
  return CLIENT_SUPPORT[targetId]?.[kind] ?? null;
}

/**
 * Un profil de scanner est « amorçable » quand la plateforme sait servir une
 * commande d'une ligne pour lui. C'est ce que consomme l'interface Web : elle
 * ne doit pas redéfinir sa propre liste d'OS supportés.
 */
export const BOOTSTRAPPABLE_PROFILES: readonly ScannerProfile[] = ['linux', 'proxmox', 'windows'];

export function isBootstrappable(profile: ScannerProfile): boolean {
  return BOOTSTRAPPABLE_PROFILES.includes(profile);
}
