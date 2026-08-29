// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { createHash } from 'node:crypto';
import { Ajv2020 } from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';
import { describe, expect, it } from 'vitest';
import { fullReport, minimalReport } from './fixtures.js';
import { buildJsonSchema } from './json-schema.js';
import { SCHEMA_VERSION } from './version.js';

/**
 * Empreinte du JSON Schema généré.
 *
 * Ce test est un garde-fou de versionnement (ADR 0002) : toute modification du
 * schéma change cette empreinte et force à décider consciemment si
 * `SCHEMA_VERSION` doit être incrémenté — plutôt que de laisser filer une
 * évolution de format non versionnée.
 *
 * En cas d'échec : mettre à jour `SCHEMA_VERSION` selon docs/format-rapport/VERSIONING.md,
 * documenter le changement dans CHANGELOG.md, puis reporter la nouvelle
 * empreinte ici.
 */
const EXPECTED_FINGERPRINT = '3c19e07fb9238937da71f1163bd514f7dff810e3559a6d351094c290fd0854c3';

function fingerprint(value: unknown): string {
  return createHash('sha256').update(JSON.stringify(value)).digest('hex');
}

function createValidator() {
  const ajv = new Ajv2020({ strict: false, allErrors: true });
  addFormats(ajv);
  return ajv.compile(buildJsonSchema());
}

describe('buildJsonSchema', () => {
  it('produit un document JSON Schema 2020-12 identifié par sa version', () => {
    const schema = buildJsonSchema();
    expect(schema.$schema).toBe('https://json-schema.org/draft/2020-12/schema');
    expect(schema.$id).toContain(SCHEMA_VERSION);
    expect(schema.title).toBe('SysAudit Report');
  });

  it('est sérialisable en JSON (consommable par un scanner non-TypeScript)', () => {
    expect(() => JSON.parse(JSON.stringify(buildJsonSchema()))).not.toThrow();
  });

  it('signale tout changement de format non accompagné d’un changement de version', () => {
    expect(
      fingerprint(buildJsonSchema()),
      'Le schéma a changé : réviser SCHEMA_VERSION et le CHANGELOG avant de mettre à jour cette empreinte.',
    ).toBe(EXPECTED_FINGERPRINT);
  });
});

describe('JSON Schema — validation avec un validateur standard', () => {
  it('se compile sans erreur avec Ajv', () => {
    expect(() => createValidator()).not.toThrow();
  });

  it('valide le rapport minimal', () => {
    const validate = createValidator();
    const valid = validate(JSON.parse(JSON.stringify(minimalReport())));
    expect(valid, JSON.stringify(validate.errors, null, 2)).toBe(true);
  });

  it('valide le rapport complet', () => {
    const validate = createValidator();
    const valid = validate(JSON.parse(JSON.stringify(fullReport())));
    expect(valid, JSON.stringify(validate.errors, null, 2)).toBe(true);
  });

  it('rejette un rapport invalide, comme le ferait la validation Zod', () => {
    const validate = createValidator();
    const broken = JSON.parse(JSON.stringify(minimalReport())) as Record<string, unknown>;
    delete broken.capabilities;
    expect(validate(broken)).toBe(false);
  });
});
