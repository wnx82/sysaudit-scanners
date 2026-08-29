// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { createHash, createHmac, randomBytes } from 'node:crypto';

/**
 * Catégories de données que `--anonymize` remplace par un pseudonyme stable.
 * L'utilisateur doit pouvoir consulter cette liste avant tout upload (§31).
 */
export const ANONYMIZED_CATEGORIES = [
  'hostname',
  'username',
  'domain',
  'publicIp',
  'macAddress',
  'serialNumber',
  'uuid',
  'wifiSsid',
] as const;

export type AnonymizedCategory = (typeof ANONYMIZED_CATEGORIES)[number];

/** Préfixe lisible utilisé dans le pseudonyme, par catégorie. */
const PREFIXES: Record<AnonymizedCategory, string> = {
  hostname: 'HOST',
  username: 'USER',
  domain: 'DOMAIN',
  publicIp: 'IP',
  macAddress: 'MAC',
  serialNumber: 'SN',
  uuid: 'UUID',
  wifiSsid: 'SSID',
};

export interface Anonymizer {
  /** Pseudonymise une valeur ; `null`/vide reste inchangé. */
  mask<T extends string | null | undefined>(category: AnonymizedCategory, value: T): T;
  /** Sel utilisé — à conserver hors du rapport si une ré-identification locale est voulue. */
  readonly salt: string;
}

/**
 * Crée un anonymiseur déterministe **au sein d'un rapport** : la même valeur donne
 * toujours le même pseudonyme (les corrélations internes restent analysables),
 * mais un sel aléatoire empêche la corrélation entre deux rapports et rend le
 * dictionnaire d'attaque inutilisable sur des espaces réduits (MAC, IPv4).
 */
export function createAnonymizer(salt: string = randomBytes(32).toString('hex')): Anonymizer {
  const cache = new Map<string, string>();

  return {
    salt,
    mask<T extends string | null | undefined>(category: AnonymizedCategory, value: T): T {
      if (value === null || value === undefined) return value;
      const raw = String(value);
      if (raw.trim() === '') return value;

      const key = `${category}:${raw.toLowerCase()}`;
      let masked = cache.get(key);
      if (masked === undefined) {
        const digest = createHmac('sha256', salt).update(key).digest('hex');
        masked = `${PREFIXES[category]}-${digest.slice(0, 10).toUpperCase()}`;
        cache.set(key, masked);
      }
      return masked as T;
    },
  };
}

/** Empreinte stable et non réversible d'une machine, utilisée pour relier ses scans. */
export function machineFingerprint(parts: readonly (string | null | undefined)[]): string {
  const normalized = parts
    .filter((part): part is string => typeof part === 'string' && part.trim() !== '')
    .map((part) => part.trim().toLowerCase())
    .sort();

  if (normalized.length === 0) {
    throw new Error('machineFingerprint: aucune donnée identifiante fournie');
  }

  return createHash('sha256').update(normalized.join('|')).digest('hex');
}

const PRIVATE_IPV4 =
  /^(10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.)/;

/** Une IP privée/locale n'est pas identifiante : elle n'est pas anonymisée. */
export function isPrivateIpv4(ip: string): boolean {
  return PRIVATE_IPV4.test(ip.trim());
}

export function isPrivateIpv6(ip: string): boolean {
  const normalized = ip.trim().toLowerCase();
  return (
    normalized === '::1' ||
    normalized.startsWith('fe80:') ||
    normalized.startsWith('fc') ||
    normalized.startsWith('fd')
  );
}
