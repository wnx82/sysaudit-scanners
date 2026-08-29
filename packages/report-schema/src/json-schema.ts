// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { z } from 'zod';
import { reportSchema } from './report.js';
import { SCHEMA_VERSION } from './version.js';

/**
 * JSON Schema du rapport, **généré** depuis la définition Zod (ADR 0002).
 *
 * Il n'est jamais écrit à la main : c'est l'artefact que consomment les
 * scanners non-TypeScript (Bash, PowerShell) et les outils externes pour
 * valider leur sortie sans dépendre de Node.js.
 */
export function buildJsonSchema(): Record<string, unknown> {
  const generated = z.toJSONSchema(reportSchema, { io: 'input' }) as Record<string, unknown>;

  return {
    $schema: 'https://json-schema.org/draft/2020-12/schema',
    $id: `https://sysaudit.app/schema/report/${SCHEMA_VERSION}.json`,
    title: 'SysAudit Report',
    description:
      "Rapport d'audit SysAudit. Contient uniquement des faits mesurés : " +
      'les scores, recommandations et comparaisons sont calculés séparément.',
    ...generated,
  };
}

export const JSON_SCHEMA_FILENAME = `sysaudit-report-${SCHEMA_VERSION}.schema.json`;
