// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { CURRENT_CAPABILITY_COLUMNS, TARGET_CAPABILITY_COLUMNS } from './compatibility.js';
import { compatibilityHeaders, compatibilityRows, parseMarkdownTable } from './markdown.js';

/**
 * Garde-fou de la dette `D-09` : les tableaux de compatibilité de la
 * documentation étaient saisis à la main dans deux fichiers, et divergeaient
 * déjà. Ils sont désormais générés ; ce test échoue dès que l'un d'eux est
 * modifié directement.
 *
 * La comparaison porte sur le **contenu des cellules**, jamais sur les espaces :
 * Prettier réaligne les tableaux Markdown à sa façon, et cet alignement n'est
 * pas une information.
 */

const ROOT = fileURLToPath(new URL('../../../', import.meta.url));

function blockOf(file: string, marker: string): string {
  const source = readFileSync(`${ROOT}${file}`, 'utf8');
  const start = source.indexOf(`<!-- ${marker}:start -->`);
  const end = source.indexOf(`<!-- ${marker}:end -->`);
  expect(start, `marqueur « ${marker}:start » absent de ${file}`).toBeGreaterThan(-1);
  expect(end, `marqueur « ${marker}:end » absent de ${file}`).toBeGreaterThan(start);
  return source.slice(start, end);
}

/**
 * Documents porteurs d'un tableau généré.
 *
 * Filtrés sur leur présence réelle, et pas par confort : le plan directeur
 * archivé vit dans `docs/roadmaps/`, un dossier non versionné dont il est
 * l'unique exception. Il n'existe donc pas dans la surface publique, où ce même
 * test tourne. Un document absent n'est pas une dérive de la matrice — c'est un
 * document absent, et le confondre avec l'autre ferait rougir un dépôt sain.
 *
 * `COMPATIBILITY.md`, lui, est exigé : voir le test qui suit cette liste.
 */
const DOCUMENTS = [
  'COMPATIBILITY.md',
  'docs/roadmaps/_archive/2026-07-28-sysaudit-platform-expansion/00-MASTER-PLAN.md',
].filter((file) => existsSync(resolve(ROOT, file)));

describe('tableaux de compatibilité générés', () => {
  const expectedCurrent = [
    compatibilityHeaders(CURRENT_CAPABILITY_COLUMNS),
    ...compatibilityRows(CURRENT_CAPABILITY_COLUMNS),
  ];
  const expectedTarget = [
    compatibilityHeaders(TARGET_CAPABILITY_COLUMNS),
    ...compatibilityRows(TARGET_CAPABILITY_COLUMNS),
  ];

  it.each(DOCUMENTS)('%s reflète la matrice actuelle', (file) => {
    expect(parseMarkdownTable(blockOf(file, 'compatibility:current'))).toEqual(expectedCurrent);
  });

  it.each(DOCUMENTS)('%s reflète la matrice cible', (file) => {
    expect(parseMarkdownTable(blockOf(file, 'compatibility:target'))).toEqual(expectedTarget);
  });

  it('la légende de COMPATIBILITY.md couvre tous les niveaux', () => {
    const legend = blockOf('COMPATIBILITY.md', 'compatibility:legend');
    for (const symbol of ['✅', '🟡', '⏳', '—', '❌', 'n/a']) {
      expect(legend, `symbole « ${symbol} » absent de la légende`).toContain(symbol);
    }
  });
});
