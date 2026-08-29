// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';
import {
  ANONYMIZED_CATEGORIES,
  createAnonymizer,
  isPrivateIpv4,
  isPrivateIpv6,
  machineFingerprint,
} from './anonymize.js';

describe('createAnonymizer', () => {
  it('produit un pseudonyme stable pour une même valeur', () => {
    const anon = createAnonymizer('sel-de-test');
    expect(anon.mask('hostname', 'PC-GRENIER')).toBe(anon.mask('hostname', 'PC-GRENIER'));
  });

  it('est insensible à la casse', () => {
    const anon = createAnonymizer('sel-de-test');
    expect(anon.mask('hostname', 'PC-GRENIER')).toBe(anon.mask('hostname', 'pc-grenier'));
  });

  it('ne laisse jamais fuiter la valeur d’origine', () => {
    const anon = createAnonymizer('sel-de-test');
    const masked = anon.mask('serialNumber', 'CN-0X1Y2Z-74261');
    expect(masked).not.toContain('CN-0X1Y2Z');
    expect(masked).toMatch(/^SN-[0-9A-F]{10}$/);
  });

  it('sépare les espaces de noms par catégorie', () => {
    const anon = createAnonymizer('sel-de-test');
    expect(anon.mask('hostname', 'alpha')).not.toBe(anon.mask('username', 'alpha'));
  });

  it('empêche la corrélation entre deux rapports (sels différents)', () => {
    const a = createAnonymizer('sel-a');
    const b = createAnonymizer('sel-b');
    expect(a.mask('macAddress', '00:1a:2b:3c:4d:5e')).not.toBe(
      b.mask('macAddress', '00:1a:2b:3c:4d:5e'),
    );
  });

  it('génère un sel aléatoire par défaut', () => {
    expect(createAnonymizer().salt).not.toBe(createAnonymizer().salt);
  });

  it.each([null, undefined, '', '   '])('laisse %p inchangé', (value) => {
    const anon = createAnonymizer('sel-de-test');
    expect(anon.mask('hostname', value)).toBe(value);
  });

  it('couvre toutes les catégories annoncées à l’utilisateur', () => {
    const anon = createAnonymizer('sel-de-test');
    for (const category of ANONYMIZED_CATEGORIES) {
      expect(anon.mask(category, 'valeur')).toMatch(/^[A-Z]+-[0-9A-F]{10}$/);
    }
  });
});

describe('machineFingerprint', () => {
  it('est stable quel que soit l’ordre des composants', () => {
    expect(machineFingerprint(['uuid-1', 'SN-2'])).toBe(machineFingerprint(['SN-2', 'uuid-1']));
  });

  it('ignore les valeurs vides', () => {
    expect(machineFingerprint(['uuid-1', null, '', undefined])).toBe(
      machineFingerprint(['uuid-1']),
    );
  });

  it('distingue deux machines', () => {
    expect(machineFingerprint(['uuid-1'])).not.toBe(machineFingerprint(['uuid-2']));
  });

  it('refuse de produire une empreinte sans donnée identifiante', () => {
    expect(() => machineFingerprint([null, '', undefined])).toThrow(/aucune donnée/);
  });
});

describe('isPrivateIpv4', () => {
  it.each(['10.0.0.1', '192.168.1.10', '172.16.0.1', '172.31.255.254', '127.0.0.1', '169.254.1.1'])(
    'considère %s comme privée',
    (ip) => {
      expect(isPrivateIpv4(ip)).toBe(true);
    },
  );

  it.each(['8.8.8.8', '172.32.0.1', '172.15.0.1', '1.1.1.1'])(
    'considère %s comme publique',
    (ip) => {
      expect(isPrivateIpv4(ip)).toBe(false);
    },
  );
});

describe('isPrivateIpv6', () => {
  it.each(['::1', 'fe80::1', 'fd00::1', 'FC00::1'])('considère %s comme privée', (ip) => {
    expect(isPrivateIpv6(ip)).toBe(true);
  });

  it('considère une adresse globale comme publique', () => {
    expect(isPrivateIpv6('2001:db8::1')).toBe(false);
  });
});
