// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { isUnknown, read, unknown } from '@sysaudit/shared';
import { describe, expect, it } from 'vitest';
import { fullReport } from './fixtures.js';
import { memoryMaxCapacityBytes, memoryMaxCapacityIsIncoherent } from './memory-capacity.js';
import type { Report } from './report.js';

const GIB = 1024 ** 3;

function rapport(memory: Partial<NonNullable<Report['memory']>>): Report {
  const base = fullReport();
  return { ...base, memory: { ...base.memory!, ...memory } };
}

describe('memoryMaxCapacityBytes', () => {
  it('rend la valeur déclarée quand elle est plausible', () => {
    const lu = memoryMaxCapacityBytes(
      rapport({ installedBytes: 32 * GIB, maxCapacityBytes: 128 * GIB }),
    );
    expect(read(lu)).toBe(128 * GIB);
  });

  /**
   * Le cas exact de `QJVJVFA6` : 33 157 378 048 octets installés pour
   * 134 217 728 octets déclarés supportés. `MaxCapacityEx` est en kilo-octets,
   * et le scanner la versait telle quelle — le facteur 1024 manquant.
   */
  it('refuse de publier une capacité maximale que la mémoire installée contredit', () => {
    const lu = memoryMaxCapacityBytes(
      rapport({ installedBytes: 33_157_378_048, maxCapacityBytes: 134_217_728 }),
    );

    expect(isUnknown(lu)).toBe(true);
    expect(isUnknown(lu) ? lu.detail : '').toContain('incohérente');
  });

  it('retient la même valeur limite : égale à l’installé reste plausible', () => {
    // Une machine dont tous les emplacements portent le maximum est un cas
    // réel. Seul le strictement inférieur est impossible.
    const lu = memoryMaxCapacityBytes(
      rapport({ installedBytes: 32 * GIB, maxCapacityBytes: 32 * GIB }),
    );
    expect(read(lu)).toBe(32 * GIB);
  });

  it('se rabat sur la somme des modules quand le total installé manque', () => {
    const base = fullReport();
    const module = base.memory!.modules[0]!;
    const lu = memoryMaxCapacityBytes(
      rapport({
        installedBytes: unknown('UNKNOWN'),
        maxCapacityBytes: 134_217_728,
        modules: [
          { ...module, sizeBytes: 16 * GIB },
          { ...module, sizeBytes: 16 * GIB },
        ],
      }),
    );

    expect(isUnknown(lu)).toBe(true);
  });

  it('laisse passer un marqueur déjà posé sans le réécrire', () => {
    const marqueur = unknown('NOT_AVAILABLE', 'aucun tableau mémoire SMBIOS');
    const lu = memoryMaxCapacityBytes(rapport({ maxCapacityBytes: marqueur }));
    expect(lu).toBe(marqueur);
  });

  it('ne conclut rien quand rien ne contredit la valeur', () => {
    // Ni total installé ni module dimensionné : aucune contradiction possible,
    // donc aucune raison de retenir la valeur.
    const lu = memoryMaxCapacityBytes(
      rapport({ installedBytes: unknown('UNKNOWN'), maxCapacityBytes: 134_217_728, modules: [] }),
    );
    expect(read(lu)).toBe(134_217_728);
  });

  it('rend « section absente » quand le rapport n’a pas de mémoire', () => {
    const base = fullReport();
    expect(memoryMaxCapacityBytes({ ...base, memory: undefined })).toBeUndefined();
  });
});

describe('memoryMaxCapacityIsIncoherent', () => {
  it('distingue « contredite » de « non collectée »', () => {
    expect(
      memoryMaxCapacityIsIncoherent(
        rapport({ installedBytes: 33_157_378_048, maxCapacityBytes: 134_217_728 }),
      ),
    ).toBe(true);

    expect(
      memoryMaxCapacityIsIncoherent(rapport({ maxCapacityBytes: unknown('NOT_AVAILABLE') })),
    ).toBe(false);
  });
});
