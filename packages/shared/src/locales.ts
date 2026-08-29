// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

/**
 * Les langues du produit.
 *
 * ## Ce que ce module change par rapport à `locale.ts`
 *
 * `locale.ts` disait — honnêtement — que le produit était monolingue et le
 * restait : une constante `fr-BE`, rassemblée là pour n'avoir pas à la chercher
 * dans trente fichiers le jour venu. Ce jour est arrivé.
 *
 * Ce module ouvre **deux** langues et ne prétend rien de plus. Il ne contient
 * aucune traduction : seulement le vocabulaire — quelles langues existent,
 * comment elles s'écrivent en BCP 47, comment on reconnaît celle qu'un visiteur
 * demande. Les catalogues vivent dans l'application qui les affiche.
 *
 * ## Le français n'a pas de préfixe, et c'est une décision
 *
 * `/documentation` reste `/documentation`. Déplacer le français sous `/fr/`
 * casserait tous les liens de rapport déjà partagés, tout le référencement
 * acquis, et chaque adresse recopiée dans un ticket — pour une symétrie
 * d'URL que personne ne réclame. L'anglais vit donc sous `/en/`, et la
 * canonique de chaque page dit laquelle des deux fait foi.
 */

/** Les langues servies. L'ordre est celui du sélecteur. */
export const LOCALES = ['fr', 'en'] as const;
export type Locale = (typeof LOCALES)[number];

/** La langue servie sans préfixe d'URL. */
export const DEFAULT_UI_LOCALE: Locale = 'fr';

/**
 * L'étiquette BCP 47 complète, région comprise.
 *
 * Elle gouverne les formats de date et de nombre. `fr-BE` et non `fr-FR` :
 * l'exploitant comme ses premiers utilisateurs sont belges, et les deux ne
 * séparent pas les milliers de la même façon. `en-GB` et non `en-US` : une date
 * `08/09` ne désigne pas le même jour dans les deux, et se tromper de convention
 * sur un rapport d'audit daté n'est pas anodin.
 */
export const LOCALE_TAGS: Readonly<Record<Locale, string>> = {
  fr: 'fr-BE',
  en: 'en-GB',
};

/** Nom de la langue **dans cette langue** : c'est ainsi qu'on choisit la sienne. */
export const LOCALE_NAMES: Readonly<Record<Locale, string>> = {
  fr: 'Français',
  en: 'English',
};

/** Étiquette Open Graph, qui veut des tirets bas là où BCP 47 veut des tirets. */
export function ogLocaleOf(locale: Locale): string {
  return LOCALE_TAGS[locale].replace('-', '_');
}

/** Valeur de l'attribut `lang` de `<html>` : la langue seule, sans région. */
export function htmlLangOf(locale: Locale): string {
  return locale;
}

export function isLocale(value: unknown): value is Locale {
  return typeof value === 'string' && (LOCALES as readonly string[]).includes(value);
}

/** Ramène une valeur quelconque à une langue servie, ou `null`. */
export function normalizeLocale(value: unknown): Locale | null {
  if (typeof value !== 'string') return null;
  const lowered = value.trim().toLowerCase();
  if (isLocale(lowered)) return lowered;
  // `fr-BE`, `en-US` : la région ne change pas la langue servie.
  const base = lowered.split('-')[0];
  return isLocale(base) ? base : null;
}

/** Nom du cookie qui retient le choix d'un visiteur. */
export const LOCALE_COOKIE = 'sysaudit_locale';

/**
 * Le préfixe d'URL d'une langue. Vide pour le français.
 *
 * Rendu par une fonction plutôt que par une table : la table serait consultée
 * puis concaténée à chaque appel, et un `''` concaténé produit `//chemin` une
 * fois sur deux selon l'ordre des barres obliques.
 */
export function localePrefix(locale: Locale): string {
  return locale === DEFAULT_UI_LOCALE ? '' : `/${locale}`;
}

/**
 * Le chemin d'une page dans une langue donnée.
 *
 * `path` est toujours écrit **en français**, c'est-à-dire dans sa forme sans
 * préfixe : c'est la forme canonique du site, et la seule qui existe dans le
 * code des composants.
 */
export function localizedPath(path: string, locale: Locale): string {
  const normalized = path.startsWith('/') ? path : `/${path}`;
  if (locale === DEFAULT_UI_LOCALE) return normalized;
  // `/` devient `/en`, et non `/en/` : une barre finale crée une seconde
  // adresse pour la même page, que les moteurs comptent séparément.
  return normalized === '/' ? `/${locale}` : `/${locale}${normalized}`;
}

/**
 * Sépare un chemin reçu en langue et chemin canonique.
 *
 * `/en/documentation` → `{ locale: 'en', path: '/documentation' }`
 * `/documentation` → `{ locale: 'fr', path: '/documentation' }`
 * `/en` → `{ locale: 'en', path: '/' }`
 *
 * Un préfixe qui **ressemble** à une langue sans en être une n'est pas
 * consommé : `/es/documentation` reste un chemin français vers une page qui
 * n'existe pas, et rend un 404 franc plutôt qu'une page espagnole vide.
 */
export function splitLocalePath(pathname: string): { locale: Locale; path: string } {
  const segments = pathname.split('/').filter((segment) => segment !== '');
  const first = segments[0];

  // Le français n'a pas de préfixe : `/fr/...` n'est donc pas une adresse du
  // site, et `first === 'fr'` ne doit rien consommer.
  if (first !== undefined && isLocale(first) && first !== DEFAULT_UI_LOCALE) {
    const rest = segments.slice(1).join('/');
    return { locale: first, path: rest === '' ? '/' : `/${rest}` };
  }

  return { locale: DEFAULT_UI_LOCALE, path: pathname === '' ? '/' : pathname };
}

/**
 * La langue préférée d'après un en-tête `Accept-Language`.
 *
 * Une **suggestion**, jamais une décision : le choix explicite d'un visiteur
 * (cookie) et le préfixe d'URL passent tous deux devant. Un navigateur configuré
 * en anglais par défaut ne doit pas empêcher quelqu'un de lire le site en
 * français après l'avoir demandé.
 *
 * Les qualités (`;q=`) sont respectées, parce que les ignorer ferait choisir
 * l'anglais pour `fr;q=0.9, en;q=0.1` — c'est-à-dire l'inverse de ce que le
 * visiteur a demandé.
 */
export function preferredLocale(header: string | undefined | null): Locale | null {
  if (typeof header !== 'string' || header.trim() === '') return null;

  const ranked = header
    .split(',')
    .map((part) => {
      const [tag, ...params] = part.trim().split(';');
      const quality = params
        .map((param) => /^\s*q=([0-9.]+)\s*$/.exec(param))
        .find((match) => match !== null);
      return {
        locale: normalizeLocale(tag),
        // Absence de `q` vaut 1, comme le veut la spécification.
        quality: quality === null || quality === undefined ? 1 : Number(quality[1]),
      };
    })
    .filter(
      (entry): entry is { locale: Locale; quality: number } =>
        entry.locale !== null && Number.isFinite(entry.quality) && entry.quality > 0,
    )
    .sort((left, right) => right.quality - left.quality);

  return ranked[0]?.locale ?? null;
}
