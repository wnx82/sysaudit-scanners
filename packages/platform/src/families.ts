// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

/**
 * Taxonomie des plateformes auditées.
 *
 * Trois notions distinctes, souvent confondues :
 *
 * - la **famille** répond à « quel noyau, quelle culture système » ;
 * - la **distribution** répond à « quel assemblage précis » ;
 * - le **profil de scanner** répond à « quel collecteur sait auditer ceci ».
 *
 * Proxmox VE illustre pourquoi les trois ne peuvent pas fusionner : c'est une
 * distribution de la famille `linux`, mais elle exige son propre profil de
 * scanner. En faire une famille rendrait `family` ambigu pour un hôte Proxmox,
 * qui est bel et bien Linux.
 */

/** Familles de systèmes d'exploitation reconnues par la plateforme. */
export const OS_FAMILIES = ['linux', 'windows', 'macos', 'bsd', 'android', 'unknown'] as const;
export type OsFamily = (typeof OS_FAMILIES)[number];

/**
 * Familles telles que le schéma de rapport les nomme aujourd'hui
 * (`osSchema.family`). Le schéma dit `freebsd` là où la taxonomie dit `bsd` :
 * la correspondance est explicite plutôt que devinée, et le schéma reste
 * inchangé — aucun rapport existant n'est cassé.
 */
export const SCHEMA_FAMILY_TO_OS_FAMILY: Readonly<Record<string, OsFamily>> = {
  linux: 'linux',
  windows: 'windows',
  macos: 'macos',
  freebsd: 'bsd',
  unknown: 'unknown',
};

/**
 * Profils de scanner.
 *
 * `linux`, `proxmox`, `windows`, `windows-legacy` et `macos` existent déjà dans
 * `scannerKindSchema`. `windows-minimal`, `bsd` et `android` sont prévus par la
 * roadmap : ils figurent ici pour que la matrice de compatibilité puisse les
 * désigner, **sans** être ajoutés au schéma tant qu'aucun scanner ne les
 * produit.
 */
export const SCANNER_PROFILES = [
  'linux',
  'proxmox',
  'windows',
  'windows-legacy',
  'windows-minimal',
  'macos',
  'bsd',
  'android',
  'unknown',
] as const;
export type ScannerProfile = (typeof SCANNER_PROFILES)[number];

/** Profils réellement produits par un scanner existant, à ce jour. */
export const IMPLEMENTED_SCANNER_PROFILES: readonly ScannerProfile[] = [
  'linux',
  'proxmox',
  'windows',
];

export function isImplementedScannerProfile(profile: ScannerProfile): boolean {
  return IMPLEMENTED_SCANNER_PROFILES.includes(profile);
}

/**
 * Profil de scanner à proposer par défaut pour une famille.
 *
 * Windows en compte trois (`windows`, `windows-legacy`, `windows-minimal`) :
 * seule la version du système, absente à ce stade, permet de trancher. Le
 * profil moderne est donc le défaut, et le raffinement vient du rapport.
 */
export const DEFAULT_SCANNER_PROFILE_BY_FAMILY: Readonly<Record<OsFamily, ScannerProfile>> = {
  linux: 'linux',
  windows: 'windows',
  macos: 'macos',
  bsd: 'bsd',
  android: 'android',
  unknown: 'unknown',
};

/** Libellé affichable d'une famille. */
export const OS_FAMILY_LABELS: Readonly<Record<OsFamily, string>> = {
  linux: 'Linux',
  windows: 'Windows',
  macos: 'macOS',
  bsd: 'BSD',
  android: 'Android',
  unknown: 'Famille non déterminée',
};
