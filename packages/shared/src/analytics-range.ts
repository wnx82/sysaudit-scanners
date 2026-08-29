// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

/**
 * Les fenêtres temporelles d'un tableau de bord d'audience.
 *
 * ## Pourquoi le serveur décide, et pas le navigateur
 *
 * Une fenêtre calculée dans le navigateur porte le fuseau du visiteur. Un
 * administrateur en déplacement verrait « aujourd'hui » commencer à une autre
 * heure que son collègue, et les deux liraient des chiffres différents sans
 * qu'aucun ne soit faux. Pire : les bornes partent telles quelles chez trois
 * fournisseurs, dont deux facturent leurs quotas — une borne fantaisiste coûte
 * de l'argent avant de coûter une explication.
 *
 * Le fuseau est donc **celui de l'instance**, posé une fois, et les bornes sont
 * calculées ici.
 *
 * ## Ce que ce module refuse de faire
 *
 * Il ne devine pas une granularité illisible. Demander une courbe à l'heure sur
 * douze mois produirait huit mille sept cents points, que ni le navigateur ni
 * l'œil ne traitent — et surtout que la plupart des fournisseurs refusent de
 * rendre. Une granularité incompatible avec la fenêtre est donc **ramenée** à
 * la plus fine qui reste lisible, jamais servie telle quelle.
 *
 * Il ne rend pas non plus de période précédente pour une fenêtre qui n'en a pas
 * de comparable : « aujourd'hui » se compare à hier à la même heure, et cette
 * comparaison-là est honnête ; comparer une journée entamée à une journée
 * complète ne l'est pas.
 */

/** Les fenêtres proposées, telles qu'elles s'écrivent dans une URL. */
export const ANALYTICS_RANGES = [
  'today',
  'yesterday',
  '7d',
  '30d',
  '90d',
  '12m',
  'custom',
] as const;

export type AnalyticsRange = (typeof ANALYTICS_RANGES)[number];

export const ANALYTICS_RANGE_LABELS: Readonly<Record<AnalyticsRange, string>> = {
  today: 'Aujourd’hui',
  yesterday: 'Hier',
  '7d': '7 derniers jours',
  '30d': '30 derniers jours',
  '90d': '90 derniers jours',
  '12m': '12 derniers mois',
  custom: 'Période personnalisée',
};

/** Granularités d'une série temporelle, de la plus fine à la plus grossière. */
export const ANALYTICS_UNITS = ['hour', 'day', 'week', 'month'] as const;
export type AnalyticsUnit = (typeof ANALYTICS_UNITS)[number];

export const ANALYTICS_UNIT_LABELS: Readonly<Record<AnalyticsUnit, string>> = {
  hour: 'Par heure',
  day: 'Par jour',
  week: 'Par semaine',
  month: 'Par mois',
};

/** Une fenêtre résolue : deux instants, et rien d'ambigu. */
export interface AnalyticsWindow {
  /** Borne inférieure, incluse. */
  readonly start: Date;
  /** Borne supérieure, exclue. */
  readonly end: Date;
}

export interface ResolvedRange extends AnalyticsWindow {
  readonly range: AnalyticsRange;
  /** Granularité effectivement servie, après ramenée à ce qui est lisible. */
  readonly unit: AnalyticsUnit;
  /**
   * La fenêtre de même durée qui précède immédiatement, ou `null`.
   *
   * `null` n'est pas un cas d'erreur : il dit qu'aucune comparaison honnête
   * n'est possible, et l'écran doit alors ne rien afficher plutôt qu'un écart
   * calculé sur des durées inégales.
   */
  readonly previous: AnalyticsWindow | null;
  /** Nombre de jours entamés couverts — ce que les fournisseurs facturent. */
  readonly days: number;
  /** Fuseau utilisé pour découper les journées. Jamais deviné côté client. */
  readonly timeZone: string;
}

const DAY_MS = 86_400_000;

/** Ramène une valeur reçue à une fenêtre connue. `null` si elle ne l'est pas. */
export function normalizeAnalyticsRange(value: unknown): AnalyticsRange | null {
  return typeof value === 'string' && (ANALYTICS_RANGES as readonly string[]).includes(value)
    ? (value as AnalyticsRange)
    : null;
}

export function normalizeAnalyticsUnit(value: unknown): AnalyticsUnit | null {
  return typeof value === 'string' && (ANALYTICS_UNITS as readonly string[]).includes(value)
    ? (value as AnalyticsUnit)
    : null;
}

/**
 * Décalage du fuseau par rapport à UTC, à cet instant précis.
 *
 * Calculé par `Intl` plutôt que codé en dur : un décalage figé se trompe deux
 * fois par an, et l'écran d'audience se lit précisément le lendemain d'un
 * changement d'heure quand on cherche pourquoi la courbe a un creux.
 */
function offsetMs(instant: Date, timeZone: string): number {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    hour12: false,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(instant);

  const read = (type: string): number => Number(parts.find((part) => part.type === type)?.value);
  // `Intl` écrit minuit « 24 » dans certaines implémentations : le ramener à 0
  // évite un décalage d'une journée entière une fois par jour.
  const hour = read('hour') % 24;

  return (
    Date.UTC(read('year'), read('month') - 1, read('day'), hour, read('minute'), read('second')) -
    instant.getTime()
  );
}

/**
 * L'instant UTC où commence la journée locale contenant `instant`.
 *
 * Deux passes, et c'est nécessaire : la première estime le décalage à partir de
 * l'instant donné, la seconde le corrige avec le décalage réellement en vigueur
 * à minuit. Sans elle, la nuit d'un changement d'heure décale la borne d'une
 * heure — et c'est justement cette nuit-là qu'on regarde la courbe.
 */
export function startOfDay(instant: Date, timeZone: string): Date {
  const local = new Date(instant.getTime() + offsetMs(instant, timeZone));
  const midnightUtc = Date.UTC(
    local.getUTCFullYear(),
    local.getUTCMonth(),
    local.getUTCDate(),
    0,
    0,
    0,
  );
  const first = new Date(midnightUtc - offsetMs(instant, timeZone));
  return new Date(midnightUtc - offsetMs(first, timeZone));
}

/**
 * La granularité la plus fine qui reste lisible sur cette durée.
 *
 * Les seuils ne sont pas ronds par hasard : au-delà de deux jours, une courbe
 * horaire dépasse cinquante points et cesse de se lire ; au-delà de trois mois,
 * une courbe journalière en dépasse quatre-vingt-dix et devient une texture.
 */
export function defaultUnit(start: Date, end: Date): AnalyticsUnit {
  const spanDays = (end.getTime() - start.getTime()) / DAY_MS;
  if (spanDays <= 2) return 'hour';
  if (spanDays <= 92) return 'day';
  if (spanDays <= 400) return 'week';
  return 'month';
}

/**
 * La granularité demandée, ou la plus fine acceptable si elle ne l'est pas.
 *
 * Refuser franchement serait plus simple, et pire : l'écran devrait alors
 * gérer une erreur pour un choix que l'utilisateur n'a pas eu l'intention de
 * faire — il a simplement changé de période sans changer de granularité.
 */
export function clampUnit(requested: AnalyticsUnit, start: Date, end: Date): AnalyticsUnit {
  const spanDays = (end.getTime() - start.getTime()) / DAY_MS;
  if (requested === 'hour' && spanDays > 8) return 'day';
  if (requested === 'day' && spanDays > 400) return 'week';
  return requested;
}

/** Une date `YYYY-MM-DD` lue comme minuit local, ou `null`. */
function parseDay(raw: string | undefined, timeZone: string): Date | null {
  if (raw === undefined || !/^\d{4}-\d{2}-\d{2}$/.test(raw)) return null;
  const [year, month, day] = raw.split('-').map(Number) as [number, number, number];
  const naive = Date.UTC(year, month - 1, day);
  if (!Number.isFinite(naive)) return null;
  const probe = new Date(naive);
  return new Date(naive - offsetMs(probe, timeZone));
}

export interface RangeRequest {
  readonly range?: unknown;
  readonly unit?: unknown;
  /** `YYYY-MM-DD`, borne incluse, pour `custom` uniquement. */
  readonly from?: string | undefined;
  /** `YYYY-MM-DD`, borne **incluse** — la journée entière est comptée. */
  readonly to?: string | undefined;
  readonly timeZone: string;
  readonly now: Date;
}

/** Nombre maximal de jours qu'une fenêtre personnalisée peut couvrir. */
export const MAX_CUSTOM_DAYS = 400;

/**
 * Résout une demande en fenêtre exploitable.
 *
 * Rien n'échoue : une demande incompréhensible retombe sur trente jours, la
 * fenêtre la plus utile. Un écran d'administration qui refuse d'afficher parce
 * qu'un paramètre d'URL a été recopié de travers n'aide personne.
 */
export function resolveRange(request: RangeRequest): ResolvedRange {
  const { timeZone, now } = request;
  const range = normalizeAnalyticsRange(request.range) ?? '30d';
  const midnight = startOfDay(now, timeZone);

  let start: Date;
  let end: Date;

  switch (range) {
    case 'today':
      start = midnight;
      // La journée est **en cours** : la borne est l'instant présent, et non
      // minuit prochain. Compter une journée entière ferait plonger toutes les
      // moyennes jusqu'au soir.
      end = now;
      break;
    case 'yesterday':
      start = new Date(midnight.getTime() - DAY_MS);
      end = midnight;
      break;
    case '7d':
    case '30d':
    case '90d':
    case '12m': {
      const spanDays = range === '7d' ? 7 : range === '30d' ? 30 : range === '90d' ? 90 : 365;
      // La journée en cours est incluse, d'où `spanDays - 1` journées pleines
      // avant elle : « 7 derniers jours » se lit comme la semaine écoulée, pas
      // comme les sept journées complètes qui précèdent.
      start = new Date(midnight.getTime() - (spanDays - 1) * DAY_MS);
      end = now;
      break;
    }
    case 'custom': {
      const from = parseDay(request.from, timeZone);
      const to = parseDay(request.to, timeZone);
      if (from === null || to === null || to.getTime() < from.getTime()) {
        // Bornes inutilisables : on retombe sur trente jours plutôt que de
        // rendre une fenêtre inversée, qu'un fournisseur interpréterait mal.
        return resolveRange({ ...request, range: '30d' });
      }
      start = from;
      // `to` est **inclus** : l'utilisateur qui saisit deux fois le même jour
      // attend cette journée-là, pas une fenêtre vide.
      end = new Date(Math.min(to.getTime() + DAY_MS, now.getTime()));
      if (end.getTime() <= start.getTime()) end = new Date(start.getTime() + DAY_MS);
      if ((end.getTime() - start.getTime()) / DAY_MS > MAX_CUSTOM_DAYS) {
        end = new Date(start.getTime() + MAX_CUSTOM_DAYS * DAY_MS);
      }
      break;
    }
  }

  const requestedUnit = normalizeAnalyticsUnit(request.unit);
  const unit =
    requestedUnit === null ? defaultUnit(start, end) : clampUnit(requestedUnit, start, end);

  const span = end.getTime() - start.getTime();

  /*
   * La période précédente est de **même durée**, immédiatement antérieure.
   *
   * « Aujourd'hui » est ainsi comparé à la même tranche d'hier — de minuit à
   * la même heure — et non à la journée complète d'hier, qui rendrait toute
   * matinée catastrophique.
   */
  const previous: AnalyticsWindow | null =
    span > 0 ? { start: new Date(start.getTime() - span), end: new Date(start.getTime()) } : null;

  return {
    range,
    start,
    end,
    unit,
    previous,
    days: Math.max(1, Math.ceil(span / DAY_MS)),
    timeZone,
  };
}

/**
 * Écart relatif entre deux mesures, en pourcentage, ou `null`.
 *
 * `null` dans les deux cas où un pourcentage mentirait : quand l'une des deux
 * mesures manque, et quand la précédente vaut zéro — passer de 0 à 5 n'est pas
 * « +∞ % », c'est un début, et l'écran doit le dire autrement.
 */
export function relativeChange(current: number | null, previous: number | null): number | null {
  if (current === null || previous === null || previous === 0) return null;
  return ((current - previous) / previous) * 100;
}
