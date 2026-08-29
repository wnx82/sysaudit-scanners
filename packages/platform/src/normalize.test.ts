// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { fullReport, minimalReport, type Report } from '@sysaudit/report-schema';
import { isUnknown, unknown } from '@sysaudit/shared';
import { describe, expect, it } from 'vitest';
import { normalizePlatform } from './normalize.js';

describe('normalizePlatform', () => {
  it('normalise un rapport Linux minimal', () => {
    const platform = normalizePlatform(minimalReport());

    expect(platform).toMatchObject({
      family: 'linux',
      distribution: 'debian',
      distributionLabel: 'Debian',
      distributionVersion: '13',
      kernel: '6.12.0-amd64',
      architecture: 'x86_64',
      scannerProfile: 'linux',
    });
  });

  it('choisit le profil Proxmox sur un hôte Proxmox VE', () => {
    const platform = normalizePlatform(fullReport());

    expect(platform.scannerProfile).toBe('proxmox');
    expect(platform.distribution).toBe('proxmox-ve');
    expect(platform.family).toBe('linux');
  });

  it('bascule sur le profil Proxmox même si le scanner s’est annoncé « linux »', () => {
    const report: Report = {
      ...minimalReport(),
      capabilities: { ...minimalReport().capabilities, proxmox: true },
    };

    expect(normalizePlatform(report).scannerProfile).toBe('proxmox');
  });

  it('ne conclut rien quand la distribution n’est pas répertoriée', () => {
    const base = minimalReport();
    const report: Report = {
      ...base,
      os: { ...base.os, distribution: 'gentoo', name: 'Gentoo Linux' },
    };

    const platform = normalizePlatform(report);
    expect(isUnknown(platform.distribution)).toBe(true);
    // Le libellé brut vient de la machine auditée : le conserver vaut mieux
    // qu'afficher « inconnu » alors que le rapport dit quelque chose.
    expect(platform.distributionLabel).toBe('Gentoo Linux');
  });

  it('marque les champs que le rapport ne fournit pas', () => {
    const base = minimalReport();
    const report: Report = {
      ...base,
      os: {
        ...base.os,
        distribution: unknown('NOT_AVAILABLE'),
        name: unknown('NOT_AVAILABLE'),
        version: unknown('NOT_AVAILABLE'),
        kernel: unknown('NOT_AVAILABLE'),
      },
    };

    const platform = normalizePlatform(report);
    expect(isUnknown(platform.distribution)).toBe(true);
    expect(isUnknown(platform.distributionLabel)).toBe(true);
    expect(isUnknown(platform.distributionVersion)).toBe(true);
    expect(isUnknown(platform.kernel)).toBe(true);
  });

  it('retombe sur l’architecture du système puis des capacités', () => {
    const base = minimalReport();
    const report: Report = {
      ...base,
      os: { ...base.os, architecture: unknown('UNKNOWN') },
      system: { ...base.system, architecture: unknown('UNKNOWN') },
      capabilities: { ...base.capabilities, architecture: 'aarch64' },
    };

    expect(normalizePlatform(report).architecture).toBe('aarch64');
  });

  it('expose la limite d’identification lorsqu’elle existe', () => {
    const base = minimalReport();
    const report: Report = { ...base, os: { ...base.os, distribution: 'raspbian' } };

    expect(normalizePlatform(report).caveat).toMatch(/64 bits/);
  });

  it('n’attribue jamais un profil de repli à un scanner inconnu', () => {
    const base = minimalReport();
    // Un rapport produit par un scanner d'une version ultérieure ne doit pas
    // être interprété comme du Linux par défaut.
    const report = {
      ...base,
      report: { ...base.report, scannerKind: 'solaris' },
    } as unknown as Report;

    expect(normalizePlatform(report).scannerProfile).toBe('unknown');
  });
});
