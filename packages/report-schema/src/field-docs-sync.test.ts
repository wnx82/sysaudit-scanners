// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { exampleFor, renderFieldReference, renderFieldSummary } from './field-docs.js';

/**
 * `docs/format-rapport/REPORT_SCHEMA_FIELDS.md` est une projection du schéma. Ce test rejoue
 * le générateur en mode `--check` : il échoue si le document a été modifié à la
 * main, ou si le schéma a bougé sans que la documentation suive.
 *
 * Même dispositif que pour la matrice de compatibilité et les niveaux de
 * diagnostic. Sans lui, la documentation dériverait en silence — et une
 * documentation de format fausse est crue.
 */

const rootDir = resolve(import.meta.dirname, '../../..');

describe('référence des champs', () => {
  it('reste synchronisée avec le schéma', () => {
    // Le générateur importe le package compilé : `npm run verify` construit
    // avant de tester, et ce test s'exécute donc sur la même source que lui.
    expect(() =>
      execFileSync(process.execPath, ['scripts/generate-schema-fields.mjs', '--check'], {
        cwd: rootDir,
        stdio: 'pipe',
      }),
    ).not.toThrow();
  });

  it('rend une table complète, sans cellule vide', () => {
    const markdown = renderFieldReference();
    const rows = markdown.split('\n').filter((line) => line.startsWith('| `'));
    expect(rows.length).toBeGreaterThan(400);
    for (const row of rows) {
      // Dix colonnes plus les deux barres extrêmes.
      expect(row.split(' | ').length, row).toBe(10);
      expect(row, row).not.toContain('undefined');
      expect(row, row).not.toContain('| |');
    }
  });

  it('compte les champs plutôt que d’annoncer un total figé', () => {
    expect(renderFieldSummary()).toMatch(/\*\*\d+ champs\*\*/);
  });

  it('tire ses exemples des jeux d’essai, et n’en invente aucun', () => {
    expect(exampleFor('report.scannerKind')).not.toBeNull();
    expect(exampleFor('storage.disks[].sizeBytes')).not.toBeNull();
    // Un chemin qui n'existe pas ne doit pas produire d'exemple plausible.
    expect(exampleFor('storage.disks[].champInexistant')).toBeNull();
  });

  it('ne présente jamais le marqueur « non collecté » comme un exemple de valeur', () => {
    const markdown = renderFieldReference();
    expect(markdown).not.toContain('[object Object]');
    expect(markdown).not.toMatch(/\| `\{.*unknown/);
  });
});
