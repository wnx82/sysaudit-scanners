// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';

import {
  BRAND_NAME,
  BRAND_SLUG,
  BRAND_TAGLINE,
  COPYRIGHT_HOLDER,
  COPYRIGHT_SINCE,
  copyrightNotice,
} from './brand.js';

describe('nom du produit', () => {
  it('porte le domaine, que le nom court ne porte pas', () => {
    expect(BRAND_NAME).toBe('SysAudit.me');
    expect(BRAND_SLUG).toBe('SysAudit');
  });

  /*
   * L'un dérive de l'autre : si le nom visible cessait de contenir le nom
   * court, les identifiants techniques laissés en `SysAudit` deviendraient des
   * vestiges inexplicables plutôt qu'un raccourci délibéré.
   */
  it('reste le nom court, augmenté', () => {
    expect(BRAND_NAME.startsWith(BRAND_SLUG)).toBe(true);
  });
});

describe('promesse du produit', () => {
  /*
   * Le garde-fou qui compte.
   *
   * « Lecture seule » sans réserve était faux d'un niveau sur quatre : Complète
   * peut installer un outil avec accord, et Poussée charge volontairement la
   * machine en écrivant un fichier temporaire. La promesse est revenue deux fois
   * dans le produit — page d'accueil et signature d'e-mail — parce que rien ne
   * l'interdisait.
   *
   * Le test n'interdit pas de parler de lecture seule : il interdit d'en faire
   * la promesse **globale** du produit, celle qui s'affiche avant que l'on ait
   * choisi un niveau.
   */
  it('ne promet pas la lecture seule sans réserve', () => {
    expect(BRAND_TAGLINE.toLowerCase()).not.toContain('lecture seule');
  });

  it('dit ce que la collecte ne fait pas, plutôt que ce qu’elle ne fait jamais', () => {
    expect(BRAND_TAGLINE).toContain('non destructive');
    expect(BRAND_TAGLINE).toContain('par défaut');
  });

  it('tient en une phrase, sans concaténation à l’exécution', () => {
    // Une phrase assemblée morceau par morceau est intraduisible : l'ordre des
    // syntagmes n'est pas le même d'une langue à l'autre.
    expect(BRAND_TAGLINE.split('.').filter((part) => part.trim() !== '')).toHaveLength(1);
  });
});

describe('mention de droit d’auteur', () => {
  it('n’affiche qu’une année tant que la publication n’a pas duré', () => {
    expect(copyrightNotice(COPYRIGHT_SINCE)).toBe('© 2026 SysAudit');
  });

  it('ouvre une plage dès l’année suivante', () => {
    expect(copyrightNotice(COPYRIGHT_SINCE + 2)).toBe('© 2026–2028 SysAudit');
  });

  it('ne recule jamais avant la première publication', () => {
    // Une horloge déréglée — machine de compilation mal réglée, conteneur sans
    // NTP — ne doit pas produire « © 2026–1970 ». Mieux vaut une mention juste
    // qu'une plage inventée.
    for (const year of [2025, 1970, 0, -1, Number.NaN, Number.POSITIVE_INFINITY]) {
      expect(copyrightNotice(year), String(year)).toBe('© 2026 SysAudit');
    }
  });

  it('tronque une année fractionnaire au lieu de l’arrondir', () => {
    expect(copyrightNotice(2027.9)).toBe('© 2026–2027 SysAudit');
  });

  /*
   * Le titulaire affiché est la **marque**, pas l'éditeur.
   *
   * Les surfaces produit ne portent aucune identité d'entreprise, sur décision
   * du propriétaire du projet — `apps/web/src/lib/identity.test.ts` le vérifie
   * en relisant les sources. L'identité complète vit dans `LICENSE`, qui fait
   * foi juridiquement et que personne ne confond avec un pied de page.
   */
  it('affiche la marque et non l’éditeur', () => {
    expect(COPYRIGHT_HOLDER).toBe(BRAND_SLUG);
    expect(copyrightNotice(2026).toLowerCase()).not.toContain('ekreativ');
  });

  it('n’est jamais assemblée morceau par morceau chez l’appelant', () => {
    // La mention entière sort d'ici : un appelant qui écrirait « © » puis
    // l'année puis le nom produirait une chaîne intraduisible, et la première
    // surface oubliée resterait sur l'ancienne forme.
    expect(copyrightNotice(2026).startsWith('©')).toBe(true);
    expect(copyrightNotice(2026).endsWith(COPYRIGHT_HOLDER)).toBe(true);
  });
});
