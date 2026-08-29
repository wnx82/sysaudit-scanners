// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import type { Report } from '@sysaudit/report-schema';
import { read, unknown, type Maybe } from '@sysaudit/shared';
import {
  SCHEMA_FAMILY_TO_OS_FAMILY,
  type OsFamily,
  type ScannerProfile,
  SCANNER_PROFILES,
} from './families.js';
import { identifyDistribution, type DistributionDefinition } from './distributions.js';

/**
 * Vue normalisée de la plateforme auditée.
 *
 * C'est une **dérivation** d'un rapport, pas une nouvelle collecte : elle ne
 * contient rien que le rapport ne dise déjà. Elle existe pour que l'interface,
 * les règles et la documentation cessent chacune de réinterpréter
 * `os.distribution` à leur façon.
 *
 * Tout champ incertain reste un `Maybe` : la normalisation ne comble aucun
 * trou.
 */
export interface NormalizedPlatform {
  readonly family: OsFamily;
  /** Identifiant du catalogue, ou marqueur si la distribution n'est pas reconnue. */
  readonly distribution: Maybe<string>;
  /** Libellé affichable. Reprend la valeur brute du rapport si elle est connue. */
  readonly distributionLabel: Maybe<string>;
  readonly distributionVersion: Maybe<string>;
  readonly kernel: Maybe<string>;
  readonly architecture: Maybe<string>;
  readonly scannerProfile: ScannerProfile;
  /** Limite connue de l'identification, à afficher plutôt qu'à taire. */
  readonly caveat?: string;
}

function isScannerProfile(value: string): value is ScannerProfile {
  return (SCANNER_PROFILES as readonly string[]).includes(value);
}

/**
 * Profil de scanner effectivement utilisé pour produire ce rapport.
 *
 * La source est `report.report.scannerKind`, écrit par le scanner lui-même :
 * c'est un fait, pas une déduction. Un `scannerKind` inconnu de cette version
 * de la plateforme donne `unknown` — jamais un repli silencieux sur `linux`,
 * qui laisserait croire qu'un rapport a été compris alors qu'il ne l'a pas été.
 */
function resolveScannerProfile(report: Report): ScannerProfile {
  const kind: string = report.report.scannerKind;
  if (kind === 'linux' && report.capabilities.proxmox === true) return 'proxmox';
  return isScannerProfile(kind) ? kind : 'unknown';
}

function resolveFamily(report: Report, definition?: DistributionDefinition): OsFamily {
  const fromSchema = SCHEMA_FAMILY_TO_OS_FAMILY[report.os.family];
  if (fromSchema !== undefined && fromSchema !== 'unknown') return fromSchema;
  // Le schéma ne connaît pas encore `android` : la famille du catalogue prend
  // le relais lorsqu'il ne sait rien dire.
  return definition?.family ?? 'unknown';
}

/** Dérive la vue normalisée d'un rapport validé. */
export function normalizePlatform(report: Report): NormalizedPlatform {
  const osReleaseId = read(report.os.distribution);
  const osName = read(report.os.name);
  const proxmox = report.capabilities.proxmox;

  const definition = identifyDistribution({ osReleaseId, osName, proxmox });
  const family = resolveFamily(report, definition);

  // L'architecture est reportée à trois endroits par le scanner. Elles disent
  // normalement la même chose ; on prend la première connue plutôt que
  // d'échouer si l'une manque.
  const architecture =
    read(report.os.architecture) ??
    read(report.system.architecture) ??
    report.capabilities.architecture;

  const distributionVersion = read(report.os.version);
  const kernel = read(report.os.kernel);

  return {
    family,
    distribution:
      definition?.id ??
      unknown(
        'UNKNOWN',
        osReleaseId
          ? `distribution non répertoriée : ${osReleaseId}`
          : 'aucun identifiant de distribution dans le rapport',
      ),
    // Faute d'entrée au catalogue, la valeur brute du rapport reste préférable
    // à un marqueur : elle vient de la machine auditée, elle n'est pas inventée.
    distributionLabel:
      definition?.label ??
      osName ??
      osReleaseId ??
      unknown('UNKNOWN', 'aucun nom de distribution dans le rapport'),
    distributionVersion:
      distributionVersion ?? unknown('UNKNOWN', 'aucune version dans le rapport'),
    kernel: kernel ?? unknown('UNKNOWN', 'aucune version de noyau dans le rapport'),
    architecture: architecture ?? unknown('UNKNOWN', 'aucune architecture dans le rapport'),
    scannerProfile: resolveScannerProfile(report),
    ...(definition?.caveat === undefined ? {} : { caveat: definition.caveat }),
  };
}
