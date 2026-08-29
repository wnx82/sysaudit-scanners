// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import type { OsFamily, ScannerProfile } from './families.js';

/**
 * Catalogue des distributions reconnues.
 *
 * L'identification part de `ID` de `/etc/os-release`, que le scanner Linux
 * reporte tel quel dans `os.distribution`. `NAME` (reporté dans `os.name`) ne
 * sert qu'en repli, car il varie davantage entre versions.
 *
 * Aucune heuristique de ressemblance : une distribution non répertoriée n'est
 * pas rattachée « au plus proche ». Elle reste non identifiée, et le rapport
 * conserve la valeur brute lue sur la machine.
 */
export interface DistributionDefinition {
  /** Identifiant stable interne, utilisé par la matrice de compatibilité. */
  readonly id: string;
  readonly label: string;
  readonly family: OsFamily;
  readonly scannerProfile: ScannerProfile;
  /** Valeurs de `ID` (`/etc/os-release`) qui désignent cette distribution. */
  readonly osReleaseIds: readonly string[];
  /**
   * Fragments de `NAME` acceptés en repli, en minuscules. Utilisés uniquement
   * quand `ID` est absent ou inconnu.
   */
  readonly namePatterns?: readonly string[];
  /** Gestionnaire de paquets attendu — sert aux collecteurs logiciels. */
  readonly packageManager?: 'apt' | 'dnf' | 'yum' | 'pacman' | 'pkg' | 'msi' | 'brew';
  /** Limite connue de l'identification, à afficher plutôt qu'à taire. */
  readonly caveat?: string;
}

export const DISTRIBUTIONS: readonly DistributionDefinition[] = [
  {
    id: 'ubuntu',
    label: 'Ubuntu',
    family: 'linux',
    scannerProfile: 'linux',
    osReleaseIds: ['ubuntu'],
    namePatterns: ['ubuntu'],
    packageManager: 'apt',
  },
  {
    id: 'debian',
    label: 'Debian',
    family: 'linux',
    scannerProfile: 'linux',
    osReleaseIds: ['debian'],
    namePatterns: ['debian'],
    packageManager: 'apt',
  },
  {
    id: 'linuxmint',
    label: 'Linux Mint',
    family: 'linux',
    scannerProfile: 'linux',
    osReleaseIds: ['linuxmint', 'mint'],
    namePatterns: ['linux mint'],
    packageManager: 'apt',
  },
  {
    id: 'fedora',
    label: 'Fedora',
    family: 'linux',
    scannerProfile: 'linux',
    osReleaseIds: ['fedora'],
    namePatterns: ['fedora'],
    packageManager: 'dnf',
  },
  {
    id: 'rocky',
    label: 'Rocky Linux',
    family: 'linux',
    scannerProfile: 'linux',
    osReleaseIds: ['rocky'],
    namePatterns: ['rocky'],
    packageManager: 'dnf',
  },
  {
    id: 'almalinux',
    label: 'AlmaLinux',
    family: 'linux',
    scannerProfile: 'linux',
    osReleaseIds: ['almalinux', 'alma'],
    namePatterns: ['almalinux'],
    packageManager: 'dnf',
  },
  {
    id: 'arch',
    label: 'Arch Linux',
    family: 'linux',
    scannerProfile: 'linux',
    osReleaseIds: ['arch'],
    namePatterns: ['arch linux'],
    packageManager: 'pacman',
  },
  {
    id: 'manjaro',
    label: 'Manjaro',
    family: 'linux',
    scannerProfile: 'linux',
    osReleaseIds: ['manjaro', 'manjaro-arm'],
    namePatterns: ['manjaro'],
    packageManager: 'pacman',
  },
  {
    id: 'raspberry-pi-os',
    label: 'Raspberry Pi OS',
    family: 'linux',
    scannerProfile: 'linux',
    osReleaseIds: ['raspbian'],
    namePatterns: ['raspbian', 'raspberry pi os'],
    packageManager: 'apt',
    caveat:
      'Les versions 64 bits récentes déclarent ID=debian : elles sont alors ' +
      'identifiées comme Debian, faute de signal distinctif dans le rapport.',
  },
  {
    id: 'proxmox-ve',
    label: 'Proxmox VE',
    family: 'linux',
    scannerProfile: 'proxmox',
    // Proxmox VE conserve ID=debian : il n'est jamais identifié par
    // `/etc/os-release` seul, mais par `capabilities.proxmox`, que le scanner
    // établit sur la présence conjointe de `pveversion` et de `/etc/pve`.
    osReleaseIds: [],
    namePatterns: ['proxmox'],
    packageManager: 'apt',
    caveat: 'Identifié par capabilities.proxmox, pas par /etc/os-release.',
  },
  {
    id: 'windows',
    label: 'Windows',
    family: 'windows',
    scannerProfile: 'windows',
    osReleaseIds: [],
    namePatterns: ['windows'],
    packageManager: 'msi',
  },
  {
    id: 'macos',
    label: 'macOS',
    family: 'macos',
    scannerProfile: 'macos',
    osReleaseIds: [],
    namePatterns: ['macos', 'mac os', 'darwin'],
    packageManager: 'brew',
  },
  {
    id: 'freebsd',
    label: 'FreeBSD',
    family: 'bsd',
    scannerProfile: 'bsd',
    osReleaseIds: ['freebsd'],
    namePatterns: ['freebsd'],
    packageManager: 'pkg',
  },
  {
    id: 'pfsense',
    label: 'pfSense',
    family: 'bsd',
    scannerProfile: 'bsd',
    osReleaseIds: ['pfsense'],
    namePatterns: ['pfsense'],
    packageManager: 'pkg',
  },
  {
    id: 'opnsense',
    label: 'OPNsense',
    family: 'bsd',
    scannerProfile: 'bsd',
    osReleaseIds: ['opnsense'],
    namePatterns: ['opnsense'],
    packageManager: 'pkg',
  },
  {
    id: 'android',
    label: 'Android',
    family: 'android',
    scannerProfile: 'android',
    osReleaseIds: ['android'],
    namePatterns: ['android'],
  },
];

const BY_OS_RELEASE_ID = new Map<string, DistributionDefinition>(
  DISTRIBUTIONS.flatMap((definition) =>
    definition.osReleaseIds.map((id) => [id, definition] as const),
  ),
);

export function distributionById(id: string): DistributionDefinition | undefined {
  return DISTRIBUTIONS.find((definition) => definition.id === id);
}

export interface DistributionSignals {
  /** `ID` de `/etc/os-release`, reporté dans `os.distribution`. */
  readonly osReleaseId?: string | undefined;
  /** `NAME` de `/etc/os-release`, reporté dans `os.name`. */
  readonly osName?: string | undefined;
  /** `capabilities.proxmox` — seul signal fiable d'un hôte Proxmox VE. */
  readonly proxmox?: boolean | undefined;
}

/**
 * Identifie une distribution à partir des signaux réellement présents dans un
 * rapport. Retourne `undefined` plutôt qu'une approximation : ne rien savoir
 * est une réponse valide, pas un échec à masquer.
 *
 * L'ordre des signaux n'est pas arbitraire. `capabilities.proxmox` passe en
 * premier parce que Proxmox VE se présente comme Debian dans
 * `/etc/os-release` : s'en remettre à `ID` renverrait « Debian » sur un
 * hyperviseur, et masquerait le seul profil de scanner correct.
 */
export function identifyDistribution(
  signals: DistributionSignals,
): DistributionDefinition | undefined {
  if (signals.proxmox === true) return distributionById('proxmox-ve');

  const osReleaseId = signals.osReleaseId?.trim().toLowerCase();
  if (osReleaseId) {
    const byId = BY_OS_RELEASE_ID.get(osReleaseId);
    if (byId) return byId;
  }

  const name = signals.osName?.trim().toLowerCase();
  if (!name) return undefined;

  // Le repli par nom prend le motif le plus long qui correspond : « linux mint »
  // doit l'emporter sur « mint » comme sur « linux ».
  let best: DistributionDefinition | undefined;
  let bestLength = 0;
  for (const definition of DISTRIBUTIONS) {
    for (const pattern of definition.namePatterns ?? []) {
      if (name.includes(pattern) && pattern.length > bestLength) {
        best = definition;
        bestLength = pattern.length;
      }
    }
  }
  return best;
}
