// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';
import { DISTRIBUTIONS, distributionById, identifyDistribution } from './distributions.js';

describe('catalogue de distributions', () => {
  it('n’a pas deux entrées portant le même identifiant', () => {
    const ids = DISTRIBUTIONS.map((definition) => definition.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('n’associe jamais un même ID d’os-release à deux distributions', () => {
    const seen = new Map<string, string>();
    for (const definition of DISTRIBUTIONS) {
      for (const osReleaseId of definition.osReleaseIds) {
        expect(seen.get(osReleaseId), `ID « ${osReleaseId} » déjà pris`).toBeUndefined();
        seen.set(osReleaseId, definition.id);
      }
    }
  });

  it('couvre les distributions exigées par la roadmap', () => {
    const required = [
      'ubuntu',
      'debian',
      'linuxmint',
      'fedora',
      'rocky',
      'almalinux',
      'arch',
      'manjaro',
      'raspberry-pi-os',
      'proxmox-ve',
    ];
    for (const id of required) {
      expect(distributionById(id), `distribution « ${id} » absente du catalogue`).toBeDefined();
    }
  });
});

describe('identifyDistribution', () => {
  it.each([
    ['ubuntu', 'ubuntu'],
    ['debian', 'debian'],
    ['linuxmint', 'linuxmint'],
    ['fedora', 'fedora'],
    ['rocky', 'rocky'],
    ['almalinux', 'almalinux'],
    ['arch', 'arch'],
    ['manjaro', 'manjaro'],
    ['raspbian', 'raspberry-pi-os'],
  ])('reconnaît ID=%s', (osReleaseId, expected) => {
    expect(identifyDistribution({ osReleaseId })?.id).toBe(expected);
  });

  it('ignore la casse et les espaces de l’identifiant', () => {
    expect(identifyDistribution({ osReleaseId: '  Ubuntu ' })?.id).toBe('ubuntu');
  });

  it('identifie Proxmox VE par la capacité, pas par os-release', () => {
    // Proxmox VE se présente comme Debian : sans ce test, une régression
    // renverrait « Debian » sur un hyperviseur et choisirait le mauvais profil.
    const identified = identifyDistribution({ osReleaseId: 'debian', proxmox: true });
    expect(identified?.id).toBe('proxmox-ve');
    expect(identified?.scannerProfile).toBe('proxmox');
  });

  it('retombe sur le nom quand l’identifiant est absent', () => {
    expect(identifyDistribution({ osName: 'Fedora Linux' })?.id).toBe('fedora');
  });

  it('préfère le motif le plus long en repli par nom', () => {
    // « Linux Mint » contient aussi « mint » : le motif le plus spécifique doit
    // l'emporter.
    expect(identifyDistribution({ osName: 'Linux Mint 22' })?.id).toBe('linuxmint');
  });

  it('ne rattache pas une distribution inconnue à la plus proche', () => {
    expect(identifyDistribution({ osReleaseId: 'gentoo' })).toBeUndefined();
    expect(identifyDistribution({ osName: 'Une distribution maison' })).toBeUndefined();
  });

  it('ne conclut rien sans aucun signal', () => {
    expect(identifyDistribution({})).toBeUndefined();
    expect(identifyDistribution({ osReleaseId: '', osName: '   ' })).toBeUndefined();
  });

  it('déclare la limite d’identification de Raspberry Pi OS', () => {
    // La donnée est ambiguë sur les versions 64 bits : elle doit être exposée,
    // pas masquée par une identification optimiste.
    expect(distributionById('raspberry-pi-os')?.caveat).toMatch(/ID=debian/);
    expect(identifyDistribution({ osReleaseId: 'debian' })?.id).toBe('debian');
  });
});
