// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import {
  renderDepthLegend,
  renderDepthNotes,
  renderLevelOverviewTable,
  renderLevelPlanTable,
  renderLevelSummaries,
  renderScannerCaps,
  renderScannerPlanTable,
} from './diagnostic-levels-markdown.js';
import { parseMarkdownTable } from './markdown.js';

/**
 * `docs/produit/DIAGNOSTIC-LEVELS.md` est une projection de la matrice, jamais une
 * saisie. Ce test échoue dès qu'il est modifié à la main — c'est-à-dire dès
 * qu'une promesse de documentation cesse de correspondre au code.
 *
 * Les tableaux sont comparés cellule par cellule : Prettier réaligne les
 * tableaux Markdown, et cet alignement n'est pas une information.
 */
const ROOT = fileURLToPath(new URL('../../../', import.meta.url));
const FILE = 'docs/produit/DIAGNOSTIC-LEVELS.md';

function blockOf(marker: string): string {
  const source = readFileSync(`${ROOT}${FILE}`, 'utf8');
  const start = source.indexOf(`<!-- ${marker}:start -->`);
  const end = source.indexOf(`<!-- ${marker}:end -->`);
  expect(start, `marqueur « ${marker}:start » absent de ${FILE}`).toBeGreaterThan(-1);
  expect(end, `marqueur « ${marker}:end » absent de ${FILE}`).toBeGreaterThan(start);
  return source.slice(start, end);
}

function textOf(marker: string): string {
  return blockOf(marker).split('\n').slice(1).join('\n').trim();
}

describe('documentation générée des niveaux', () => {
  it.each([
    ['levels:overview', renderLevelOverviewTable()],
    ['levels:plan', renderLevelPlanTable()],
    ['levels:plan:linux', renderScannerPlanTable('linux')],
    ['levels:plan:windows', renderScannerPlanTable('windows')],
  ])('le tableau « %s » reflète la matrice', (marker, expected) => {
    expect(parseMarkdownTable(blockOf(marker))).toEqual(parseMarkdownTable(expected));
  });

  it.each([
    ['levels:summaries', renderLevelSummaries()],
    ['levels:legend', renderDepthLegend()],
    ['levels:notes', renderDepthNotes()],
    ['levels:caps:linux', renderScannerCaps('linux')],
    ['levels:caps:windows', renderScannerCaps('windows')],
  ])('le bloc « %s » reflète la source', (marker, expected) => {
    expect(textOf(marker)).toBe(expected.trim());
  });
});
