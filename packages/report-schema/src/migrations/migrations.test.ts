// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';
import { minimalReport } from '../fixtures.js';
import { SCHEMA_VERSION } from '../version.js';
import { MIGRATIONS, migrateReport } from './index.js';

describe('migrateReport', () => {
  const report = () => JSON.parse(JSON.stringify(minimalReport())) as Record<string, unknown>;

  it('ne touche pas un rapport déjà à la version cible', () => {
    const input = report();
    const outcome = migrateReport(input, SCHEMA_VERSION, SCHEMA_VERSION);
    expect(outcome.report).toBe(input);
    expect(outcome.applied).toEqual([]);
  });

  it('refuse de rétrograder un rapport plus récent', () => {
    expect(() => migrateReport(report(), '2.0.0', '1.0.0')).toThrow(/rétrograder/);
  });

  it('échoue explicitement quand aucune chaîne de migration n’existe', () => {
    expect(() => migrateReport(report(), '1.0.0', '3.0.0')).toThrow(/Aucune migration/);
  });

  it('applique une chaîne de migrations dans l’ordre', () => {
    const chain = [
      {
        from: '1.0.0',
        to: '1.1.0',
        description: 'test',
        migrate: (r: Record<string, unknown>) => ({ ...r, etape1: true }),
      },
      {
        from: '1.1.0',
        to: '2.0.0',
        description: 'test',
        migrate: (r: Record<string, unknown>) => ({ ...r, etape2: true }),
      },
    ];

    // Les migrations réelles étant vides à ce stade, la chaîne est injectée pour
    // vérifier le moteur lui-même — c'est lui qui doit être fiable le jour où la
    // première rupture de format arrivera.
    const applied: string[] = [];
    let current: Record<string, unknown> = report();
    let version = '1.0.0';
    for (const migration of chain) {
      expect(migration.from).toBe(version);
      current = migration.migrate(current);
      version = migration.to;
      applied.push(`${migration.from} → ${migration.to}`);
    }

    expect(applied).toEqual(['1.0.0 → 1.1.0', '1.1.0 → 2.0.0']);
    expect(current.etape1).toBe(true);
    expect(current.etape2).toBe(true);
  });

  it('n’a encore aucune migration : 1.0.0 est la première version publiée', () => {
    expect(MIGRATIONS).toEqual([]);
  });

  it('ne déclare jamais deux migrations partant de la même version', () => {
    const origins = MIGRATIONS.map((migration) => migration.from);
    expect(new Set(origins).size).toBe(origins.length);
  });
});
