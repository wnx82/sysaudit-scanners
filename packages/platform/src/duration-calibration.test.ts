// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';

import { DIAGNOSTIC_LEVELS } from './diagnostic-levels.js';
import {
  MIN_CALIBRATION_SAMPLE,
  levelDurationEstimate,
  levelDurationMinutes,
  percentile,
  targetDurationMinutes,
  type MeasuredLevelDuration,
} from './duration-calibration.js';

function sample(over: Partial<MeasuredLevelDuration> = {}): MeasuredLevelDuration {
  return {
    level: 'full',
    sampleSize: MIN_CALIBRATION_SAMPLE,
    p50Seconds: 95,
    p90Seconds: 240,
    ...over,
  };
}

describe('percentile', () => {
  it('n’a pas de percentile de rien', () => {
    expect(percentile([], 0.5)).toBeNull();
  });

  it('rend l’unique valeur d’un échantillon de un', () => {
    expect(percentile([42], 0.9)).toBe(42);
  });

  it('interpole entre les deux rangs encadrants', () => {
    // P50 de [10, 20, 30, 40] tombe entre 20 et 30 : la moitié exacte.
    expect(percentile([10, 20, 30, 40], 0.5)).toBe(25);
  });

  it('ne dépend pas de l’ordre d’entrée', () => {
    expect(percentile([40, 10, 30, 20], 0.5)).toBe(percentile([10, 20, 30, 40], 0.5));
  });

  it('rend les bornes aux extrémités', () => {
    expect(percentile([5, 9, 14], 0)).toBe(5);
    expect(percentile([5, 9, 14], 1)).toBe(14);
  });
});

describe('levelDurationEstimate', () => {
  it('publie une plage mesurée dès le seuil atteint', () => {
    const estimate = levelDurationEstimate('full', [sample()]);

    expect(estimate.source).toBe('measured');
    expect(estimate).toMatchObject({ minSeconds: 95, maxSeconds: 240 });
  });

  /*
   * Le cœur du module. Sans cette règle, un P90 calculé sur cinq audits — donc
   * le maximum observé, c'est-à-dire la machine la plus lente rencontrée —
   * deviendrait la durée promise à tout le monde.
   */
  it('ne publie rien en dessous du seuil, plutôt qu’une plage fragile', () => {
    const estimate = levelDurationEstimate('full', [
      sample({ sampleSize: MIN_CALIBRATION_SAMPLE - 1 }),
    ]);

    expect(estimate.source).toBe('calibrating');
    expect(estimate.sampleSize).toBe(MIN_CALIBRATION_SAMPLE - 1);
  });

  it('déclare la calibration en cours quand le niveau n’a aucune mesure', () => {
    const estimate = levelDurationEstimate('quick', [sample()]);

    expect(estimate).toEqual({ level: 'quick', source: 'calibrating', sampleSize: 0 });
  });

  it('ne confond pas les niveaux entre eux', () => {
    const measured = [
      sample({ level: 'quick', p50Seconds: 30, p90Seconds: 60 }),
      sample({ level: 'stress', p50Seconds: 900, p90Seconds: 1800 }),
    ];

    expect(levelDurationEstimate('quick', measured)).toMatchObject({ maxSeconds: 60 });
    expect(levelDurationEstimate('stress', measured)).toMatchObject({ maxSeconds: 1800 });
  });

  it('n’annonce jamais zéro minute sur un audit très court', () => {
    const estimate = levelDurationEstimate('quick', [
      sample({ level: 'quick', p50Seconds: 4, p90Seconds: 11 }),
    ]);

    expect(levelDurationMinutes(estimate)).toEqual({ min: 1, max: 1 });
  });
});

describe('levelDurationMinutes', () => {
  it('convertit une plage mesurée en minutes', () => {
    expect(levelDurationMinutes(levelDurationEstimate('full', [sample()]))).toEqual({
      min: 2,
      max: 4,
    });
  });

  /*
   * Un `null` explicite, et surtout pas un repli sur `targetDurationSeconds` :
   * ce repli ferait passer la constante pour une mesure, ce que tout ce module
   * existe pour empêcher.
   */
  it('ne rend aucune plage tant que la calibration n’est pas faite', () => {
    expect(levelDurationMinutes(levelDurationEstimate('full', []))).toBeNull();
  });
});

describe('targetDurationMinutes', () => {
  it('reste disponible pour la documentation, qui décrit une intention', () => {
    expect(targetDurationMinutes('full')).toEqual({ min: 5, max: 12 });
  });

  it('rend une plage croissante et non nulle pour chaque niveau', () => {
    for (const level of DIAGNOSTIC_LEVELS) {
      const { min, max } = targetDurationMinutes(level);
      expect(min).toBeGreaterThan(0);
      expect(max).toBeGreaterThanOrEqual(min);
    }
  });
});
