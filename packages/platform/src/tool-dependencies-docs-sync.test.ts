// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { parseMarkdownTable } from './markdown.js';
import {
  renderInstallTable,
  renderPackageCommands,
  renderRecommendedTools,
  renderToolTable,
} from './tool-dependencies-markdown.js';

/**
 * `docs/scanners/DEPENDENCIES.md` est une projection de la table des outils, jamais une
 * saisie. Ce test échoue dès qu'il est modifié à la main — c'est-à-dire dès
 * qu'une page dit installer un paquet que le scanner n'interroge plus, ou tait
 * un outil qu'il interroge.
 */
const ROOT = fileURLToPath(new URL('../../../', import.meta.url));
const FILE = 'docs/scanners/DEPENDENCIES.md';

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

describe('documentation générée des dépendances', () => {
  it.each([
    ['tools:linux', renderToolTable('linux')],
    ['tools:windows', renderToolTable('windows')],
    ['tools:packages', renderInstallTable()],
  ])('le tableau « %s » reflète la table', (marker, expected) => {
    expect(parseMarkdownTable(blockOf(marker))).toEqual(parseMarkdownTable(expected));
  });

  it.each([
    ['tools:recommended', renderRecommendedTools()],
    ['tools:commands', renderPackageCommands()],
  ])('le bloc « %s » reflète la table', (marker, expected) => {
    expect(textOf(marker)).toBe(expected.trim());
  });
});
