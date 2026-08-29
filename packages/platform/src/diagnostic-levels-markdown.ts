// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import {
  COLLECTION_DEPTHS,
  DEPTH_LABELS,
  DEPTH_SYMBOLS,
  DIAGNOSTIC_LEVELS,
  DIAGNOSTIC_LEVEL_PROFILES,
  LEVEL_PLAN,
  LEVEL_SECTIONS,
  SCANNER_LEVEL_PLANS,
  SCANNER_SECTION_CAPS,
  SECTION_DEPTH_NOTES,
  SECTION_LABELS,
  type LevelScanner,
} from './diagnostic-levels.js';
import { renderMarkdownTable } from './markdown.js';

/**
 * Projection Markdown de la matrice des niveaux de diagnostic.
 *
 * Comme pour la compatibilité : la documentation est rendue, jamais saisie.
 * Une promesse faite au lecteur ne peut donc pas survivre à la suppression du
 * code qui la tenait.
 */

const SCANNER_LABELS: Readonly<Record<LevelScanner, string>> = {
  linux: 'Linux / Proxmox',
  windows: 'Windows',
};

function durationLabel(minSeconds: number, maxSeconds: number): string {
  const format = (seconds: number): string =>
    seconds < 60 ? `${seconds} s` : `${Math.round(seconds / 60)} min`;
  return `${format(minSeconds)} à ${format(maxSeconds)}`;
}

/** Tableau de présentation des quatre niveaux. */
export function renderLevelOverviewTable(): string {
  const headers = ['Niveau', 'Option', 'URL', 'Durée cible', 'Privilèges', 'Charge la machine'];
  const rows = DIAGNOSTIC_LEVELS.map((level) => {
    const profile = DIAGNOSTIC_LEVEL_PROFILES[level];
    return [
      `${profile.label} (\`${level}\`)`,
      profile.cliFlag === null ? '_(défaut)_' : `\`${profile.cliFlag}\``,
      profile.urlAlias === '' ? '`/audit/l`' : `\`/audit/l/${profile.urlAlias}\``,
      durationLabel(profile.targetDurationSeconds.min, profile.targetDurationSeconds.max),
      profile.privileges === 'required' ? 'requis' : 'recommandés',
      profile.loadsMachine ? '**oui**' : 'non',
    ];
  });
  return renderMarkdownTable(headers, rows);
}

/** Matrice section × niveau : ce que chaque niveau exige. */
export function renderLevelPlanTable(): string {
  const headers = ['Section', ...DIAGNOSTIC_LEVELS.map((l) => DIAGNOSTIC_LEVEL_PROFILES[l].label)];
  const rows = LEVEL_SECTIONS.map((section) => [
    SECTION_LABELS[section],
    ...DIAGNOSTIC_LEVELS.map((level) => DEPTH_SYMBOLS[LEVEL_PLAN[level][section]]),
  ]);
  return renderMarkdownTable(headers, rows);
}

/** Ce qu'un scanner donné atteint réellement, plafonds compris. */
export function renderScannerPlanTable(scanner: LevelScanner): string {
  const plan = SCANNER_LEVEL_PLANS[scanner];
  const headers = ['Section', ...DIAGNOSTIC_LEVELS.map((l) => DIAGNOSTIC_LEVEL_PROFILES[l].label)];
  const rows = LEVEL_SECTIONS.map((section) => [
    SECTION_LABELS[section],
    ...DIAGNOSTIC_LEVELS.map((level) => DEPTH_SYMBOLS[plan[level][section]]),
  ]);
  return renderMarkdownTable(headers, rows);
}

/** Écarts assumés d'un scanner par rapport à la matrice, avec leur motif. */
export function renderScannerCaps(scanner: LevelScanner): string {
  const caps = SCANNER_SECTION_CAPS[scanner];
  const entries = LEVEL_SECTIONS.filter((section) => caps[section] !== undefined);
  if (entries.length === 0) {
    return `_${SCANNER_LABELS[scanner]} atteint la matrice à tous les niveaux._`;
  }
  return entries
    .map((section) => {
      const cap = caps[section];
      /* c8 ignore next -- `entries` ne retient que les sections plafonnées. */
      if (cap === undefined) return '';
      return `- **${SECTION_LABELS[section]}** — plafonnée à « ${DEPTH_LABELS[cap.depth]} » : ${cap.reason}`;
    })
    .join('\n');
}

export function renderDepthLegend(): string {
  return COLLECTION_DEPTHS.map((depth) => `- ${DEPTH_SYMBOLS[depth]} ${DEPTH_LABELS[depth]}`).join(
    '\n',
  );
}

/** Ce que la profondeur change, section par section. */
export function renderDepthNotes(): string {
  return LEVEL_SECTIONS.filter((section) => SECTION_DEPTH_NOTES[section] !== undefined)
    .map((section) => `- **${SECTION_LABELS[section]}** — ${SECTION_DEPTH_NOTES[section]}`)
    .join('\n');
}

/** Description d'un niveau, telle que le site et la documentation l'affichent. */
export function renderLevelSummaries(): string {
  return DIAGNOSTIC_LEVELS.map((level) => {
    const profile = DIAGNOSTIC_LEVEL_PROFILES[level];
    const duration = durationLabel(
      profile.targetDurationSeconds.min,
      profile.targetDurationSeconds.max,
    );
    return `- **${profile.label}** (${duration}) — ${profile.summary}`;
  }).join('\n');
}
