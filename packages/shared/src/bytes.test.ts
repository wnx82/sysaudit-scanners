// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';
import { formatBytes, parseSize, percentage } from './bytes.js';

describe('formatBytes', () => {
  it.each([
    [0, '0 o'],
    [512, '512 o'],
    [1024, '1 Kio'],
    [1536, '1.5 Kio'],
    [16 * 1024 ** 3, '16 Gio'],
    [1024 ** 4, '1 Tio'],
  ])('formate %i octets en %s', (input, expected) => {
    expect(formatBytes(input)).toBe(expected);
  });

  it('supporte la base décimale (capacité annoncée des disques)', () => {
    expect(formatBytes(1_000_000_000_000, { base: 'decimal' })).toBe('1 To');
  });

  it('respecte le nombre de décimales', () => {
    expect(formatBytes(1_610_612_736, { decimals: 2 })).toBe('1.5 Gio');
    expect(formatBytes(1_395_864_371, { decimals: 3 })).toBe('1.3 Gio');
  });

  it('gère les valeurs négatives (deltas d’historique)', () => {
    expect(formatBytes(-1024)).toBe('-1 Kio');
  });

  it('refuse une valeur non finie', () => {
    expect(() => formatBytes(Number.NaN)).toThrow(/non finie/);
  });
});

describe('parseSize', () => {
  it.each([
    ['16384 MB', 16384 * 1024 ** 2],
    ['1.8T', Math.round(1.8 * 1024 ** 4)],
    ['512 GB', 512 * 1024 ** 3],
    ['8192', 8192],
    ['  4 GiB ', 4 * 1024 ** 3],
    ['1,5 Go', Math.round(1.5 * 1024 ** 3)],
  ])('analyse %s', (input, expected) => {
    expect(parseSize(input)).toBe(expected);
  });

  it.each(['', 'inconnu', '12 parsecs', 'No Module Installed'])(
    'retourne null plutôt que d’estimer pour %p',
    (input) => {
      expect(parseSize(input)).toBeNull();
    },
  );
});

describe('percentage', () => {
  it('calcule un pourcentage arrondi', () => {
    expect(percentage(50, 200)).toBe(25);
    expect(percentage(1, 3, 2)).toBe(33.33);
  });

  it('borne le résultat à [0, 100]', () => {
    expect(percentage(300, 200)).toBe(100);
    expect(percentage(-5, 200)).toBe(0);
  });

  it('retourne null pour un total invalide', () => {
    expect(percentage(10, 0)).toBeNull();
    expect(percentage(10, Number.NaN)).toBeNull();
  });
});
