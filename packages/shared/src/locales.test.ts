// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';
import {
  DEFAULT_UI_LOCALE,
  htmlLangOf,
  LOCALES,
  LOCALE_NAMES,
  LOCALE_TAGS,
  localePrefix,
  localizedPath,
  normalizeLocale,
  ogLocaleOf,
  preferredLocale,
  splitLocalePath,
} from './locales.js';

/**
 * Ce que ces tests protègent.
 *
 * Le routage par langue est l'endroit où une erreur devient une **boucle de
 * redirection** : `/` renvoie vers `/en`, qui renvoie vers `/`, et le site
 * devient inaccessible pour tout le monde à la fois. Les cas limites sont donc
 * tous écrits — barre finale, préfixe absent, langue par défaut, langue qui
 * ressemble à une langue sans en être une.
 */

describe('vocabulaire des langues', () => {
  it('sert deux langues, français par défaut', () => {
    expect(LOCALES).toEqual(['fr', 'en']);
    expect(DEFAULT_UI_LOCALE).toBe('fr');
  });

  it('nomme chaque langue dans sa propre langue', () => {
    // C'est ainsi qu'on choisit la sienne : « Anglais » écrit en français
    // n'aide pas quelqu'un qui ne lit pas le français.
    expect(LOCALE_NAMES.fr).toBe('Français');
    expect(LOCALE_NAMES.en).toBe('English');
  });

  it('porte une région, parce que les formats en dépendent', () => {
    // `08/09` ne désigne pas le même jour en `en-GB` et en `en-US`, et se
    // tromper de convention sur un rapport daté n'est pas anodin.
    expect(LOCALE_TAGS.fr).toBe('fr-BE');
    expect(LOCALE_TAGS.en).toBe('en-GB');
    expect(ogLocaleOf('fr')).toBe('fr_BE');
    expect(htmlLangOf('en')).toBe('en');
  });
});

describe('normalisation', () => {
  it('accepte une étiquette régionale et rend la langue', () => {
    expect(normalizeLocale('fr-BE')).toBe('fr');
    expect(normalizeLocale('EN-us')).toBe('en');
  });

  it('refuse ce qu’elle ne sert pas, plutôt que de le rapprocher', () => {
    expect(normalizeLocale('es')).toBeNull();
    expect(normalizeLocale('')).toBeNull();
    expect(normalizeLocale(42)).toBeNull();
  });
});

describe('chemins localisés', () => {
  it('laisse le français sans préfixe', () => {
    /*
     * La décision qui gouverne tout le reste. Déplacer le français sous `/fr/`
     * casserait tous les liens de rapport déjà partagés, tout le référencement
     * acquis et chaque adresse recopiée dans un ticket.
     */
    expect(localePrefix('fr')).toBe('');
    expect(localizedPath('/documentation', 'fr')).toBe('/documentation');
    expect(localizedPath('/', 'fr')).toBe('/');
  });

  it('préfixe l’anglais sans barre finale', () => {
    expect(localizedPath('/documentation', 'en')).toBe('/en/documentation');
    // `/en` et non `/en/` : une barre finale crée une seconde adresse pour la
    // même page, que les moteurs comptent séparément.
    expect(localizedPath('/', 'en')).toBe('/en');
  });

  it('accepte un chemin sans barre initiale', () => {
    expect(localizedPath('contact', 'en')).toBe('/en/contact');
  });
});

describe('lecture d’un chemin reçu', () => {
  it('sépare la langue du chemin canonique', () => {
    expect(splitLocalePath('/en/documentation')).toEqual({ locale: 'en', path: '/documentation' });
    expect(splitLocalePath('/en')).toEqual({ locale: 'en', path: '/' });
    expect(splitLocalePath('/documentation')).toEqual({ locale: 'fr', path: '/documentation' });
    expect(splitLocalePath('/')).toEqual({ locale: 'fr', path: '/' });
  });

  it('ne consomme pas `/fr`, qui n’est pas une adresse du site', () => {
    // Le français n'a pas de préfixe : `/fr/documentation` est un chemin
    // français vers une page qui n'existe pas, pas une page française.
    expect(splitLocalePath('/fr/documentation')).toEqual({
      locale: 'fr',
      path: '/fr/documentation',
    });
  });

  it('ne consomme pas un préfixe qui ressemble à une langue sans en être une', () => {
    // `/es/...` doit rendre un 404 franc, pas une page espagnole vide.
    expect(splitLocalePath('/es/documentation')).toEqual({
      locale: 'fr',
      path: '/es/documentation',
    });
  });

  it('fait l’aller-retour sans se déplacer', () => {
    /*
     * La propriété qui empêche les boucles de redirection : découper puis
     * recomposer doit rendre le chemin de départ, pour les deux langues.
     */
    for (const path of ['/', '/documentation', '/contact', '/deposer']) {
      for (const locale of LOCALES) {
        const localized = localizedPath(path, locale);
        expect(splitLocalePath(localized)).toEqual({ locale, path });
      }
    }
  });
});

describe('préférence du navigateur', () => {
  it('respecte les qualités déclarées', () => {
    // Les ignorer ferait choisir l'anglais ici, c'est-à-dire l'inverse de ce
    // que le visiteur a demandé.
    expect(preferredLocale('fr;q=0.9, en;q=0.1')).toBe('fr');
    expect(preferredLocale('en;q=0.9, fr;q=0.1')).toBe('en');
  });

  it('traite une absence de `q` comme la préférence la plus forte', () => {
    expect(preferredLocale('en, fr;q=0.9')).toBe('en');
  });

  it('ignore les langues qui ne sont pas servies', () => {
    expect(preferredLocale('es, de, en')).toBe('en');
    expect(preferredLocale('es, de')).toBeNull();
  });

  it('ne décide rien sans en-tête', () => {
    expect(preferredLocale(undefined)).toBeNull();
    expect(preferredLocale('')).toBeNull();
    expect(preferredLocale('   ')).toBeNull();
  });

  it('écarte une langue explicitement refusée', () => {
    // `q=0` signifie « pas celle-ci » : la retenir ferait exactement le
    // contraire de ce qui est demandé.
    expect(preferredLocale('en;q=0, fr;q=0.5')).toBe('fr');
  });
});

describe('langue de rapport, distincte de celle de l’interface', () => {
  it('sépare les deux réglages par construction', () => {
    /*
     * Ce test ne vérifie pas un comportement : il **épingle une décision**.
     *
     * Un prestataire belge peut lire sa console en français et livrer un
     * rapport que son client néerlandophone puisse lire. Les deux langues sont
     * deux réglages, et `LOCALE_TAGS` est ce qui permet de les formater
     * séparément — `formatDate(iso, LOCALE_TAGS.en)` dans le moteur de rendu.
     *
     * Ce qui n'existe pas encore, et qu'il faut dire : le **contenu** d'un
     * rapport n'est pas traduit. Seuls les formats de date et de nombre le
     * sont. Prétendre le contraire ferait promettre un rapport anglais qui
     * n'existe pas.
     */
    expect(LOCALE_TAGS.fr).not.toBe(LOCALE_TAGS.en);
    expect(new Intl.NumberFormat(LOCALE_TAGS.en).format(1234)).toBe('1,234');
    expect(new Intl.NumberFormat(LOCALE_TAGS.fr).format(1234)).not.toBe('1,234');
  });
});
