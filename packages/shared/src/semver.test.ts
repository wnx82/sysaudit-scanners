// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';
import {
  compareSemVer,
  isPrerelease,
  isSchemaReadable,
  isValidSemVer,
  parseSemVer,
} from './semver.js';

describe('parseSemVer', () => {
  it('analyse une version simple', () => {
    expect(parseSemVer('1.2.3')).toEqual({ major: 1, minor: 2, patch: 3, prerelease: [] });
  });

  it('analyse une pré-release', () => {
    expect(parseSemVer('1.0.0-rc.1')).toEqual({
      major: 1,
      minor: 0,
      patch: 0,
      prerelease: ['rc', 1],
    });
  });

  it('conserve les métadonnées de build', () => {
    expect(parseSemVer('0.9.0-beta.1+abc1234')?.build).toBe('abc1234');
  });

  it.each(['1.2', 'v1.2.3', '01.2.3', '1.2.3.4', 'latest', ''])('rejette %p', (input) => {
    expect(parseSemVer(input)).toBeNull();
    expect(isValidSemVer(input)).toBe(false);
  });
});

describe('compareSemVer', () => {
  it.each([
    ['1.0.0', '2.0.0', -1],
    ['2.0.0', '1.0.0', 1],
    ['1.1.0', '1.2.0', -1],
    ['1.0.1', '1.0.2', -1],
    ['1.0.0', '1.0.0', 0],
  ])('%s vs %s → %i', (a, b, expected) => {
    expect(compareSemVer(a, b)).toBe(expected);
  });

  it('classe une pré-release avant la version finale', () => {
    expect(compareSemVer('1.0.0-rc.1', '1.0.0')).toBe(-1);
    expect(compareSemVer('1.0.0', '1.0.0-rc.1')).toBe(1);
  });

  it('ordonne les pré-releases entre elles', () => {
    expect(compareSemVer('1.0.0-alpha.1', '1.0.0-alpha.2')).toBe(-1);
    expect(compareSemVer('1.0.0-alpha', '1.0.0-beta')).toBe(-1);
    expect(compareSemVer('1.0.0-alpha.1', '1.0.0-alpha.beta')).toBe(-1);
    expect(compareSemVer('1.0.0-alpha', '1.0.0-alpha.1')).toBe(-1);
  });

  it('ignore les métadonnées de build', () => {
    expect(compareSemVer('1.0.0+build1', '1.0.0+build2')).toBe(0);
  });

  it('échoue explicitement sur une version invalide', () => {
    expect(() => compareSemVer('1.0', '1.0.0')).toThrow(/version invalide/);
  });

  it('trie une liste de versions', () => {
    const sorted = ['1.0.0', '0.2.0', '1.0.0-rc.1', '0.10.0'].sort(compareSemVer);
    expect(sorted).toEqual(['0.2.0', '0.10.0', '1.0.0-rc.1', '1.0.0']);
  });
});

describe('isPrerelease', () => {
  it('détecte une RC', () => {
    expect(isPrerelease('1.0.0-rc.1')).toBe(true);
    expect(isPrerelease('1.0.0')).toBe(false);
  });
});

describe('isSchemaReadable', () => {
  it('accepte une version MINOR antérieure ou égale', () => {
    expect(isSchemaReadable('1.0.0', '1.1.0')).toBe(true);
    expect(isSchemaReadable('1.1.0', '1.1.0')).toBe(true);
  });

  it('refuse un rapport plus récent que le lecteur', () => {
    expect(isSchemaReadable('1.2.0', '1.1.0')).toBe(false);
  });

  it('refuse un changement de version MAJOR', () => {
    expect(isSchemaReadable('2.0.0', '1.9.0')).toBe(false);
    expect(isSchemaReadable('1.0.0', '2.0.0')).toBe(false);
  });

  it('refuse une version invalide plutôt que de deviner', () => {
    expect(isSchemaReadable('abc', '1.0.0')).toBe(false);
  });
});
