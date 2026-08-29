// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

/**
 * Support SemVer minimal et strict (§48-50).
 *
 * Volontairement limité à ce dont SysAudit a besoin — comparaison de versions
 * d'application, de scanner et de schéma — plutôt que d'ajouter une dépendance.
 */
export interface SemVer {
  readonly major: number;
  readonly minor: number;
  readonly patch: number;
  /** Identifiants de pré-release (`1.0.0-rc.1` → `['rc', 1]`). */
  readonly prerelease: readonly (string | number)[];
  readonly build?: string;
}

const SEMVER_RE =
  /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$/;

export function parseSemVer(version: string): SemVer | null {
  const match = SEMVER_RE.exec(version.trim());
  if (!match) return null;

  const [, major, minor, patch, prerelease, build] = match;
  const parsed: SemVer = {
    major: Number(major),
    minor: Number(minor),
    patch: Number(patch),
    prerelease:
      prerelease === undefined
        ? []
        : prerelease.split('.').map((part) => (/^\d+$/.test(part) ? Number(part) : part)),
    ...(build === undefined ? {} : { build }),
  };
  return parsed;
}

export function isValidSemVer(version: string): boolean {
  return parseSemVer(version) !== null;
}

/** Retourne -1, 0 ou 1. Les métadonnées de build sont ignorées (spec SemVer §10). */
export function compareSemVer(a: string, b: string): number {
  const left = parseSemVer(a);
  const right = parseSemVer(b);
  if (!left || !right) {
    throw new Error(`compareSemVer: version invalide (${!left ? a : b})`);
  }

  for (const key of ['major', 'minor', 'patch'] as const) {
    if (left[key] !== right[key]) return left[key] < right[key] ? -1 : 1;
  }

  // Une version sans pré-release est supérieure à la même version avec pré-release.
  if (left.prerelease.length === 0 && right.prerelease.length > 0) return 1;
  if (left.prerelease.length > 0 && right.prerelease.length === 0) return -1;

  const length = Math.max(left.prerelease.length, right.prerelease.length);
  for (let i = 0; i < length; i += 1) {
    const l = left.prerelease[i];
    const r = right.prerelease[i];
    if (l === undefined) return -1;
    if (r === undefined) return 1;
    if (l === r) continue;

    const lNum = typeof l === 'number';
    const rNum = typeof r === 'number';
    if (lNum && rNum) return l < r ? -1 : 1;
    if (lNum) return -1; // numérique < alphanumérique
    if (rNum) return 1;
    return String(l) < String(r) ? -1 : 1;
  }

  return 0;
}

export function isPrerelease(version: string): boolean {
  const parsed = parseSemVer(version);
  return parsed !== null && parsed.prerelease.length > 0;
}

/**
 * Compatibilité de lecture d'un rapport : un consommateur qui implémente
 * `supported` sait lire un rapport `actual` si la version MAJOR est identique et
 * que la version MINOR du rapport n'est pas plus récente que celle supportée.
 */
export function isSchemaReadable(actual: string, supported: string): boolean {
  const a = parseSemVer(actual);
  const s = parseSemVer(supported);
  if (!a || !s) return false;
  if (a.major !== s.major) return false;
  return a.minor <= s.minor;
}
