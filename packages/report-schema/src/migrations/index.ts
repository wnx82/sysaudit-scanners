// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import type { SemVer } from '@sysaudit/shared';
import { compareSemVer } from '@sysaudit/shared';

/**
 * Adaptateur de lecture d'un rapport produit par une version antérieure du
 * schéma.
 *
 * Aucun ancien rapport ne doit être cassé silencieusement : dès qu'une version
 * MAJOR retire ou renomme un champ, une migration est ajoutée ici pour
 * convertir la structure lue vers la structure courante.
 */
export interface SchemaMigration {
  /** Version du rapport que cette migration sait lire. */
  readonly from: string;
  /** Version produite en sortie. */
  readonly to: string;
  readonly description: string;
  readonly migrate: (report: Record<string, unknown>) => Record<string, unknown>;
}

/**
 * Aucune migration n'existe encore : `1.0.0` est la première version publiée du
 * schéma. Le mécanisme est en place et testé pour que la première évolution
 * incompatible n'ait pas à l'inventer dans l'urgence.
 */
export const MIGRATIONS: readonly SchemaMigration[] = [];

export interface MigrationOutcome {
  readonly report: Record<string, unknown>;
  /** Chaîne de migrations réellement appliquée, dans l'ordre. */
  readonly applied: readonly string[];
}

/**
 * Applique successivement les migrations menant de `fromVersion` à la version
 * cible. Retourne le rapport inchangé si aucune migration n'est nécessaire.
 *
 * @throws si aucune chaîne complète n'existe — mieux vaut refuser que produire
 * un rapport partiellement converti.
 */
export function migrateReport(
  report: Record<string, unknown>,
  fromVersion: string,
  toVersion: string,
): MigrationOutcome {
  if (compareSemVer(fromVersion, toVersion) === 0) {
    return { report, applied: [] };
  }
  if (compareSemVer(fromVersion, toVersion) > 0) {
    throw new Error(
      `Impossible de rétrograder un rapport de ${fromVersion} vers ${toVersion} : ` +
        'un rapport plus récent doit être refusé, pas dégradé.',
    );
  }

  let current = report;
  let currentVersion = fromVersion;
  const applied: string[] = [];

  // Chaîne linéaire : une seule migration part de chaque version.
  for (;;) {
    if (compareSemVer(currentVersion, toVersion) >= 0) break;

    const next = MIGRATIONS.find((migration) => migration.from === currentVersion);
    if (!next) {
      throw new Error(
        `Aucune migration disponible depuis le schéma ${currentVersion} vers ${toVersion}.`,
      );
    }

    current = next.migrate(current);
    currentVersion = next.to;
    applied.push(`${next.from} → ${next.to}`);
  }

  return { report: current, applied };
}

export type { SemVer };
