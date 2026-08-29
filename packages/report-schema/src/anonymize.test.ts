// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { unknown } from '@sysaudit/shared';
import { describe, expect, it } from 'vitest';
import { anonymizeReport } from './anonymize.js';
import { fullReport, minimalReport } from './fixtures.js';
import type { Report } from './report.js';
import { validateReport } from './validate.js';

const SALT = 'sel-de-test-constant';

/** Toutes les chaînes du rapport, quelle que soit leur profondeur. */
function strings(value: unknown, found: string[] = []): string[] {
  if (typeof value === 'string') found.push(value);
  else if (Array.isArray(value)) for (const item of value) strings(item, found);
  else if (value !== null && typeof value === 'object') {
    for (const item of Object.values(value)) strings(item, found);
  }
  return found;
}

describe('anonymizeReport', () => {
  it('remplace les valeurs identifiantes par des pseudonymes', () => {
    const anonymized = anonymizeReport(fullReport(), { salt: SALT });

    expect(anonymized.system.hostname).toMatch(/^HOST-[0-9A-F]{10}$/);
    expect(anonymized.system.serialNumber).toMatch(/^SN-[0-9A-F]{10}$/);
    expect(anonymized.network?.interfaces[0]?.mac).toMatch(/^MAC-[0-9A-F]{10}$/);
  });

  it('ne laisse aucune valeur identifiante de la machine dans le rapport', () => {
    const source = fullReport();
    const anonymized = anonymizeReport(source, { salt: SALT });
    const remaining = strings(anonymized);

    for (const identifying of [
      'pve-lab',
      'MB1234567890',
      'A1B2C3D4',
      'S5GXNX0T123456',
      '00:1a:2b:3c:4d:5e',
      'lan',
    ]) {
      expect(remaining).not.toContain(identifying);
    }
  });

  it('conserve les adresses privées, qui ne désignent personne', () => {
    const anonymized = anonymizeReport(fullReport(), { salt: SALT });
    const iface = anonymized.network?.interfaces[0];

    expect(iface?.ipv4[0]?.address).toBe('192.168.1.20');
    expect(iface?.ipv6[0]?.address).toBe('fe80::21a:2bff:fe3c:4d5e');
  });

  it('masque une adresse publique', () => {
    const source = fullReport();
    const network = source.network;
    if (network === undefined) throw new Error('fixture sans section réseau');

    const anonymized = anonymizeReport(
      { ...source, network: { ...network, publicIp: '203.0.113.7' } },
      { salt: SALT },
    );

    expect(anonymized.network?.publicIp).toMatch(/^IP-[0-9A-F]{10}$/);
    expect(anonymized.report.anonymizedCategories).toContain('publicIp');
  });

  it('ne transforme jamais un marqueur d’absence en pseudonyme', () => {
    // Un numéro de série non lisible faute de privilèges doit rester « non
    // collecté » : le masquer laisserait croire qu'il a été collecté.
    const anonymized = anonymizeReport(minimalReport(), { salt: SALT });

    expect(anonymized.system.serialNumber).toEqual(unknown('PERMISSION_DENIED'));
    expect(anonymized.report.anonymizedCategories).not.toContain('serialNumber');
  });

  it('ne déclare que les catégories réellement masquées', () => {
    const anonymized = anonymizeReport(minimalReport(), { salt: SALT });

    expect(anonymized.report.anonymized).toBe(true);
    expect(anonymized.report.anonymizedCategories).toEqual(['hostname']);
  });

  it('donne le même pseudonyme à la même valeur dans tout le rapport', () => {
    // La carte mère et le châssis portent le même numéro de série dans la
    // fixture : la corrélation interne doit survivre à l'anonymisation.
    const anonymized = anonymizeReport(fullReport(), { salt: SALT });

    expect(anonymized.motherboard?.serialNumber).toBe(anonymized.system.serialNumber);
  });

  it('remplace le numéro de série et l’étiquette d’un bloc d’alimentation', () => {
    // Un bloc qui s'identifie n'existe que sur les machines où l'alimentation
    // parle — serveurs et blocs numériques —, c'est-à-dire précisément le parc
    // où un exemplaire se retrouve dans un inventaire.
    const base = fullReport();
    const report = {
      ...base,
      power: {
        ...base.power!,
        powerSupply: {
          detected: true,
          type: 'STANDARD_ATX' as const,
          units: [
            {
              label: 'PWS-751-1R',
              type: 'STANDARD_ATX' as const,
              model: 'PWS-751-1R',
              serialNumber: 'P751ABC123',
              assetTag: 'SRV-CABINET-042',
              source: 'SMBIOS' as const,
              confidence: 'MEDIUM' as const,
            },
          ],
          rails: [],
          componentPower: [],
          sources: ['SMBIOS' as const],
          limitations: [],
        },
      },
    } as unknown as Report;

    const unit = anonymizeReport(report, { salt: SALT }).power?.powerSupply?.units[0];
    expect(unit?.serialNumber).toMatch(/^SN-[0-9A-F]{10}$/);
    expect(unit?.assetTag).toMatch(/^SN-[0-9A-F]{10}$/);
    // Le modèle reste : il désigne une référence commerciale, pas un exemplaire.
    expect(unit?.model).toBe('PWS-751-1R');
  });

  it('est déterministe à sel constant, et décorrélé sinon', () => {
    const first = anonymizeReport(fullReport(), { salt: SALT });
    const second = anonymizeReport(fullReport(), { salt: SALT });
    const other = anonymizeReport(fullReport(), { salt: 'un-autre-sel' });

    expect(second.system.hostname).toBe(first.system.hostname);
    expect(other.system.hostname).not.toBe(first.system.hostname);
  });

  it('produit un rapport qui reste valide au regard du schéma', () => {
    const anonymized = anonymizeReport(fullReport(), { salt: SALT });
    const validation = validateReport(anonymized, { rejectSecrets: false });

    expect(validation.ok).toBe(true);
  });

  it('laisse intact un rapport déjà anonymisé par le scanner', () => {
    const source = fullReport();
    const already = {
      ...source,
      report: { ...source.report, anonymized: true, anonymizedCategories: ['hostname' as const] },
    };

    expect(anonymizeReport(already, { salt: SALT })).toBe(already);
  });

  it('ne modifie pas le rapport d’origine', () => {
    const source = fullReport();
    anonymizeReport(source, { salt: SALT });

    expect(source.system.hostname).toBe('pve-lab');
  });
});
