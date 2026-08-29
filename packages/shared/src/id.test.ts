// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';
import { generatePublicId, generateShareToken, isValidPublicId, normalizePublicId } from './id.js';

describe('generatePublicId', () => {
  it('produit un identifiant de 8 caractères par défaut', () => {
    expect(generatePublicId()).toMatch(/^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{8}$/);
  });

  it('n’utilise jamais les caractères ambigus I, L, O, U', () => {
    const sample = Array.from({ length: 200 }, () => generatePublicId()).join('');
    expect(sample).not.toMatch(/[ILOU]/);
  });

  it('ne produit pas de collision immédiate', () => {
    const ids = new Set(Array.from({ length: 500 }, () => generatePublicId()));
    expect(ids.size).toBe(500);
  });

  it('refuse une longueur trop courte pour être sûre', () => {
    expect(() => generatePublicId(4)).toThrow(/longueur minimale/);
  });
});

describe('isValidPublicId', () => {
  it.each(['8XK4G9H2', 'ABCDEF12'])('accepte %s', (id) => {
    expect(isValidPublicId(id)).toBe(true);
  });

  it.each(['8xk4g9h2', 'ABC', 'ABCDEFGI', '8XK4-G9H2', ''])('rejette %p', (id) => {
    expect(isValidPublicId(id)).toBe(false);
  });

  it('rejette les caractères ambigus exclus de l’alphabet', () => {
    for (const id of ['8XK4G9LH', '8XK4G9OH', '8XK4G9IH', '8XK4G9UH']) {
      expect(isValidPublicId(id)).toBe(false);
    }
  });
});

describe('normalizePublicId', () => {
  it('corrige les confusions de saisie', () => {
    expect(normalizePublicId(' 8xk4-g9h2 ')).toBe('8XK4G9H2');
  });

  it('mappe les caractères ambigus vers leur équivalent Crockford', () => {
    expect(normalizePublicId('OI1L0')).toBe('01110');
    expect(normalizePublicId('8XK4G9LH')).toBe('8XK4G91H');
  });
});

describe('generateShareToken', () => {
  it('produit un jeton de 32 caractères', () => {
    expect(generateShareToken()).toHaveLength(32);
  });

  it('est unique à chaque appel', () => {
    expect(generateShareToken()).not.toBe(generateShareToken());
  });
});
