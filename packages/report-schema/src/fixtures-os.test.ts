// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';
import { OS_FIXTURE_KEYS, osFixture, osFixtures } from './fixtures-os.js';
import { validateReport } from './validate.js';
import { SCHEMA_VERSION } from './version.js';

/**
 * Chaque fixture doit être un rapport que la plateforme accepterait à
 * l'ingestion. Une fixture invalide testerait un format que rien ne produit, et
 * donnerait une fausse assurance à tout ce qui s'appuie sur elle.
 */

describe('fixtures multi-OS', () => {
  it('couvre les onze systèmes demandés', () => {
    // Onze depuis le 2026-08-22 : Windows 10 et Windows 7 ont rejoint la liste.
    // Le second est le seul où l'absence est **structurelle** — ni Secure Boot,
    // ni TPM 2.0, ni démarrage rapide —, et c'est ce cas-là qu'aucune fixture
    // n'éprouvait.
    expect(OS_FIXTURE_KEYS).toHaveLength(11);
  });

  it.each(osFixtures())('$label : rapport valide au regard du schéma', ({ report }) => {
    const validation = validateReport(report, { rejectSecrets: true });

    if (!validation.ok) {
      throw new Error(
        `${validation.code} — ${validation.issues
          .slice(0, 5)
          .map((issue) => `${issue.path} : ${issue.message}`)
          .join(' ; ')}`,
      );
    }

    expect(validation.ok).toBe(true);
  });

  it.each(osFixtures())('$label : annonce la version de schéma courante', ({ report }) => {
    expect(report.schemaVersion).toBe(SCHEMA_VERSION);
  });

  it('donne à chaque fixture une identité distincte', () => {
    // Deux fixtures partageant une identité seraient fusionnées par l'empreinte
    // machine, et les tests d'historique deviendraient faux.
    const identities = osFixtures().map(({ report }) => String(report.system.uuid));
    expect(new Set(identities).size).toBe(identities.length);

    const hostnames = osFixtures().map(({ report }) => String(report.system.hostname));
    expect(new Set(hostnames).size).toBe(hostnames.length);
  });

  it('couvre les trois types de scanner', () => {
    const kinds = new Set(osFixtures().map(({ report }) => report.report.scannerKind));
    expect(kinds).toEqual(new Set(['linux', 'proxmox', 'windows']));
  });

  it('couvre les gestionnaires de paquets des principales familles', () => {
    const managers = osFixtures()
      .flatMap(({ report }) => report.software?.packageManagers ?? [])
      .map((manager) => manager.name);

    for (const expected of ['apt', 'dnf', 'pacman']) {
      expect(managers).toContain(expected);
    }
  });

  it('couvre une architecture non x86', () => {
    const architectures = osFixtures().map(({ report }) => String(report.system.architecture));
    expect(architectures).toContain('aarch64');
  });

  it('déclare ce que le scanner Windows ne collecte pas', () => {
    // Un rapport Windows sans ces sections doit dire qu'elles sont ignorées,
    // faute de quoi il se lirait comme une machine sans logiciels.
    const windows = osFixture('windows-11');

    expect(windows.software).toBeUndefined();
    expect(windows.collection.skippedSections).toContain('software');
    expect(windows.collection.skippedSections).toContain('virtualization');
  });

  it('n’expose aucune adresse réelle', () => {
    // Les fixtures sont fabriquées, pas expurgées : un expurgement raté
    // publierait une donnée réelle. Seules les plages privées sont admises.
    const PRIVATE = /^(?:10\.|127\.|169\.254\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.)/;
    // L'adresse publique, elle, ne *peut pas* être privée — c'est sa
    // définition. Le garde-fou porte donc sur les plages de documentation
    // (RFC 5737), les seules qui ne désignent aucun abonné réel.
    const DOCUMENTATION = /^(?:192\.0\.2\.|198\.51\.100\.|203\.0\.113\.)/;

    for (const { label, report } of osFixtures()) {
      for (const iface of report.network?.interfaces ?? []) {
        for (const address of iface.ipv4) {
          expect(PRIVATE.test(address.address), `${label} — ${address.address}`).toBe(true);
        }
      }

      const publicIp = report.network?.publicIp;
      if (publicIp !== undefined) {
        expect(typeof publicIp, label).toBe('string');
        expect(DOCUMENTATION.test(publicIp as string), `${label} — ${String(publicIp)}`).toBe(true);
      }
    }
  });

  it('produit un rapport identique à chaque construction', () => {
    // Une fixture non déterministe ferait échouer un test un jour sur deux sans
    // qu'aucun code n'ait changé.
    expect(JSON.stringify(osFixture('debian-12'))).toBe(JSON.stringify(osFixture('debian-12')));
  });
});
