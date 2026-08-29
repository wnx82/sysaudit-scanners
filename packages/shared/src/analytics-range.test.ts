// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';
import {
  ANALYTICS_RANGES,
  clampUnit,
  defaultUnit,
  MAX_CUSTOM_DAYS,
  normalizeAnalyticsRange,
  normalizeAnalyticsUnit,
  relativeChange,
  resolveRange,
  startOfDay,
} from './analytics-range.js';

/**
 * Ce que ces tests protègent.
 *
 * Une fenêtre temporelle fausse ne se voit pas : elle rend des chiffres
 * plausibles, simplement décalés. Le seul moment où l'erreur devient visible
 * est celui où l'on compare deux périodes — et c'est trop tard, on cherche
 * alors une cause métier à un défaut d'arithmétique.
 *
 * Le fuseau retenu pour les tests est `Europe/Brussels` : il change d'heure
 * deux fois par an, ce qui est exactement le cas qu'un décalage codé en dur
 * rate.
 */

const BRUSSELS = 'Europe/Brussels';
const DAY_MS = 86_400_000;

describe('début de journée locale', () => {
  it('ramène un instant d’après-midi à minuit local, en heure d’été', () => {
    // 2026-08-21 14:30 à Bruxelles, soit 12:30 UTC (UTC+2 en août).
    const start = startOfDay(new Date('2026-08-21T12:30:00.000Z'), BRUSSELS);
    expect(start.toISOString()).toBe('2026-08-20T22:00:00.000Z');
  });

  it('suit le changement d’heure au lieu de figer un décalage', () => {
    // En janvier, Bruxelles est à UTC+1 : minuit local est à 23:00 UTC la
    // veille, et non 22:00. Un décalage codé en dur se trompe ici.
    const hiver = startOfDay(new Date('2026-01-15T12:30:00.000Z'), BRUSSELS);
    expect(hiver.toISOString()).toBe('2026-01-14T23:00:00.000Z');
  });

  it('ne déplace pas un instant déjà à minuit local', () => {
    const minuit = new Date('2026-08-20T22:00:00.000Z');
    expect(startOfDay(minuit, BRUSSELS).toISOString()).toBe(minuit.toISOString());
  });

  it('traite UTC comme n’importe quel autre fuseau', () => {
    expect(startOfDay(new Date('2026-08-21T12:30:00.000Z'), 'UTC').toISOString()).toBe(
      '2026-08-21T00:00:00.000Z',
    );
  });
});

describe('normalisation des paramètres', () => {
  it('refuse ce qu’elle ne connaît pas plutôt que de le deviner', () => {
    expect(normalizeAnalyticsRange('7d')).toBe('7d');
    expect(normalizeAnalyticsRange('7 jours')).toBeNull();
    expect(normalizeAnalyticsRange(7)).toBeNull();
    expect(normalizeAnalyticsUnit('hour')).toBe('hour');
    expect(normalizeAnalyticsUnit('heure')).toBeNull();
  });

  it('propose sept fenêtres, sans doublon', () => {
    expect(new Set(ANALYTICS_RANGES).size).toBe(ANALYTICS_RANGES.length);
    expect(ANALYTICS_RANGES).toContain('custom');
  });
});

describe('granularité', () => {
  const start = new Date('2026-08-01T00:00:00.000Z');

  it('choisit la plus fine qui reste lisible', () => {
    expect(defaultUnit(start, new Date(start.getTime() + DAY_MS))).toBe('hour');
    expect(defaultUnit(start, new Date(start.getTime() + 30 * DAY_MS))).toBe('day');
    expect(defaultUnit(start, new Date(start.getTime() + 200 * DAY_MS))).toBe('week');
    expect(defaultUnit(start, new Date(start.getTime() + 900 * DAY_MS))).toBe('month');
  });

  it('ramène une granularité horaire demandée sur douze mois', () => {
    // 8760 points sur une courbe : ni le navigateur, ni l'œil, ni la plupart
    // des fournisseurs. Ramener vaut mieux que refuser — l'utilisateur a
    // changé de période, pas de granularité.
    expect(clampUnit('hour', start, new Date(start.getTime() + 365 * DAY_MS))).toBe('day');
  });

  it('laisse une granularité horaire sur une fenêtre courte', () => {
    expect(clampUnit('hour', start, new Date(start.getTime() + 2 * DAY_MS))).toBe('hour');
  });
});

describe('résolution des fenêtres', () => {
  const now = new Date('2026-08-21T12:30:00.000Z');
  const base = { timeZone: BRUSSELS, now };

  it('compare aujourd’hui à la même tranche d’hier, pas à hier en entier', () => {
    const resolved = resolveRange({ ...base, range: 'today' });

    expect(resolved.start.toISOString()).toBe('2026-08-20T22:00:00.000Z');
    expect(resolved.end.toISOString()).toBe(now.toISOString());
    // Le point du test : la fenêtre précédente a exactement la même durée.
    // Comparer une matinée à une journée complète rendrait toute matinée
    // catastrophique.
    const span = resolved.end.getTime() - resolved.start.getTime();
    expect(resolved.previous).not.toBeNull();
    expect(resolved.previous!.end.getTime() - resolved.previous!.start.getTime()).toBe(span);
    expect(resolved.previous!.end.toISOString()).toBe(resolved.start.toISOString());
  });

  it('rend hier comme une journée pleine, close à minuit', () => {
    const resolved = resolveRange({ ...base, range: 'yesterday' });

    expect(resolved.start.toISOString()).toBe('2026-08-19T22:00:00.000Z');
    expect(resolved.end.toISOString()).toBe('2026-08-20T22:00:00.000Z');
  });

  it('inclut la journée en cours dans « 7 derniers jours »', () => {
    const resolved = resolveRange({ ...base, range: '7d' });

    // Six journées pleines avant celle en cours : « la semaine écoulée », et
    // non les sept journées complètes qui précèdent.
    expect(resolved.start.toISOString()).toBe('2026-08-14T22:00:00.000Z');
    expect(resolved.end.toISOString()).toBe(now.toISOString());
  });

  it('retombe sur trente jours quand la fenêtre demandée n’existe pas', () => {
    // Un paramètre d'URL recopié de travers ne doit pas vider un écran
    // d'administration.
    expect(resolveRange({ ...base, range: 'la-semaine-dernière' }).range).toBe('30d');
  });

  it('compte la journée de fin d’une période personnalisée', () => {
    const resolved = resolveRange({
      ...base,
      range: 'custom',
      from: '2026-08-10',
      to: '2026-08-12',
    });

    expect(resolved.start.toISOString()).toBe('2026-08-09T22:00:00.000Z');
    // `to` est inclus : trois journées, du 10 au 12 compris.
    expect(resolved.end.toISOString()).toBe('2026-08-12T22:00:00.000Z');
    expect(resolved.days).toBe(3);
  });

  it('accepte une période personnalisée d’un seul jour', () => {
    const resolved = resolveRange({
      ...base,
      range: 'custom',
      from: '2026-08-10',
      to: '2026-08-10',
    });

    expect(resolved.days).toBe(1);
    expect(resolved.end.getTime()).toBeGreaterThan(resolved.start.getTime());
  });

  it('refuse une période inversée en retombant sur trente jours', () => {
    // Une fenêtre inversée partirait telle quelle chez trois fournisseurs, dont
    // deux facturent leurs quotas.
    const resolved = resolveRange({
      ...base,
      range: 'custom',
      from: '2026-08-20',
      to: '2026-08-01',
    });
    expect(resolved.range).toBe('30d');
  });

  it('borne une période personnalisée démesurée', () => {
    const resolved = resolveRange({
      ...base,
      range: 'custom',
      from: '2010-01-01',
      to: '2026-08-20',
    });

    expect(resolved.days).toBeLessThanOrEqual(MAX_CUSTOM_DAYS);
  });

  it('ne dépasse jamais l’instant présent', () => {
    const resolved = resolveRange({
      ...base,
      range: 'custom',
      from: '2026-08-19',
      to: '2027-01-01',
    });

    expect(resolved.end.getTime()).toBeLessThanOrEqual(now.getTime());
  });

  it('respecte une granularité choisie quand elle est tenable', () => {
    expect(resolveRange({ ...base, range: '7d', unit: 'week' }).unit).toBe('week');
    expect(resolveRange({ ...base, range: '12m', unit: 'hour' }).unit).toBe('day');
  });
});

describe('écart entre deux périodes', () => {
  it('calcule un pourcentage quand les deux mesures existent', () => {
    expect(relativeChange(150, 100)).toBe(50);
    expect(relativeChange(50, 100)).toBe(-50);
  });

  it('refuse un pourcentage qui mentirait', () => {
    // Passer de 0 à 5 n'est pas « +∞ % » : c'est un début, et l'écran doit le
    // dire autrement qu'avec un nombre.
    expect(relativeChange(5, 0)).toBeNull();
    expect(relativeChange(null, 100)).toBeNull();
    expect(relativeChange(100, null)).toBeNull();
  });
});
