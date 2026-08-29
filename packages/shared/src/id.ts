// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { randomInt } from 'node:crypto';

/**
 * Alphabet Crockford base32 sans I, L, O, U : évite les confusions à la lecture
 * (1/I/L, 0/O) et les mots offensants dans les identifiants de rapport partagés.
 */
const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/**
 * Identifiant public d'un rapport, tel qu'affiché dans `https://sysaudit.app/r/8XK4G9LH`.
 * 8 caractères ≈ 40 bits : suffisant contre l'énumération quand il est combiné au
 * rate limiting, tout en restant lisible à voix haute.
 */
export function generatePublicId(length = 8): string {
  if (length < 6) throw new Error('generatePublicId: longueur minimale de 6 caractères');
  let id = '';
  for (let i = 0; i < length; i += 1) {
    id += ALPHABET[randomInt(ALPHABET.length)];
  }
  return id;
}

const PUBLIC_ID_RE = /^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{6,32}$/;

export function isValidPublicId(id: string): boolean {
  return PUBLIC_ID_RE.test(id);
}

/** Normalise une saisie humaine (minuscules, O→0, I/L→1) avant recherche. */
export function normalizePublicId(input: string): string {
  return input
    .trim()
    .toUpperCase()
    .replace(/[OU]/g, '0')
    .replace(/[IL]/g, '1')
    .replace(/[^0-9A-Z]/g, '');
}

/** Jeton de partage : 32 caractères, jamais dérivé de l'identifiant public. */
export function generateShareToken(): string {
  return generatePublicId(32);
}
