// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

/**
 * Conversions de tailles. SysAudit stocke **toujours** les tailles en octets dans
 * le JSON ; le formatage est une préoccupation de rendu uniquement.
 */
const BINARY_UNITS = ['o', 'Kio', 'Mio', 'Gio', 'Tio', 'Pio'] as const;
const DECIMAL_UNITS = ['o', 'ko', 'Mo', 'Go', 'To', 'Po'] as const;

export interface FormatBytesOptions {
  /** `binary` (1024, unités Kio/Mio) ou `decimal` (1000, unités ko/Mo). */
  readonly base?: 'binary' | 'decimal';
  readonly decimals?: number;
}

export function formatBytes(bytes: number, options: FormatBytesOptions = {}): string {
  const { base = 'binary', decimals = 1 } = options;
  if (!Number.isFinite(bytes)) throw new Error('formatBytes: valeur non finie');

  const negative = bytes < 0;
  const abs = Math.abs(bytes);
  const step = base === 'binary' ? 1024 : 1000;
  const units = base === 'binary' ? BINARY_UNITS : DECIMAL_UNITS;

  if (abs < step) return `${negative ? '-' : ''}${abs} ${units[0]}`;

  let value = abs;
  let index = 0;
  while (value >= step && index < units.length - 1) {
    value /= step;
    index += 1;
  }

  // Les zéros non significatifs sont retirés : `1.50 Gio` se lit `1.5 Gio`.
  let rounded = value.toFixed(decimals);
  if (rounded.includes('.')) {
    rounded = rounded.replace(/0+$/, '').replace(/\.$/, '');
  }
  return `${negative ? '-' : ''}${rounded} ${units[index]}`;
}

const SIZE_RE = /^\s*([\d.,]+)\s*([a-zA-Z]*)\s*$/;

const UNIT_MULTIPLIERS: Record<string, number> = {
  b: 1,
  o: 1,
  byte: 1,
  bytes: 1,
  k: 1024,
  kb: 1024,
  kib: 1024,
  ko: 1024,
  m: 1024 ** 2,
  mb: 1024 ** 2,
  mib: 1024 ** 2,
  mo: 1024 ** 2,
  g: 1024 ** 3,
  gb: 1024 ** 3,
  gib: 1024 ** 3,
  go: 1024 ** 3,
  t: 1024 ** 4,
  tb: 1024 ** 4,
  tib: 1024 ** 4,
  to: 1024 ** 4,
  p: 1024 ** 5,
  pb: 1024 ** 5,
  pib: 1024 ** 5,
};

/**
 * Analyse une taille telle que la rapportent `dmidecode`, `lsblk` ou WMI
 * (« 16384 MB », « 1.8T », « 512 GB »). Retourne `null` si l'entrée n'est pas
 * interprétable de façon certaine — jamais une estimation.
 */
export function parseSize(input: string): number | null {
  const match = SIZE_RE.exec(input);
  if (!match) return null;

  const [, rawNumber, rawUnit] = match;
  if (rawNumber === undefined) return null;

  const value = Number(rawNumber.replace(',', '.'));
  if (!Number.isFinite(value)) return null;

  const unit = (rawUnit ?? '').toLowerCase();
  if (unit === '') return Math.round(value);

  const multiplier = UNIT_MULTIPLIERS[unit];
  if (multiplier === undefined) return null;

  return Math.round(value * multiplier);
}

/** Pourcentage borné à [0, 100], arrondi à `decimals`. */
export function percentage(used: number, total: number, decimals = 1): number | null {
  if (!Number.isFinite(used) || !Number.isFinite(total) || total <= 0) return null;
  const factor = 10 ** decimals;
  return Math.round(Math.min(Math.max((used / total) * 100, 0), 100) * factor) / factor;
}
