// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';

import { DEFAULT_LOCALE, HTML_LANG, OG_LOCALE } from './locale.js';

describe('langue du produit', () => {
  it('porte langue et région, au format BCP 47', () => {
    expect(DEFAULT_LOCALE).toBe('fr-BE');
    expect(DEFAULT_LOCALE).toMatch(/^[a-z]{2}-[A-Z]{2}$/);
  });

  /*
   * Les trois valeurs disaient la même chose dans trois orthographes, chacune
   * écrite à la main : `fr-BE` dans les appels de formatage, `fr` sur `<html>`,
   * `fr_BE` en Open Graph. Rien ne les reliait, et une traduction future en
   * aurait manqué au moins une.
   */
  it('dérive les deux autres formes, plutôt que de les recopier', () => {
    expect(HTML_LANG).toBe('fr');
    expect(OG_LOCALE).toBe('fr_BE');
  });

  it('garde les trois formes cohérentes entre elles', () => {
    expect(DEFAULT_LOCALE.startsWith(HTML_LANG)).toBe(true);
    expect(OG_LOCALE.replace('_', '-')).toBe(DEFAULT_LOCALE);
  });

  /*
   * Open Graph veut un tiret bas ; BCP 47 veut un tiret. La confusion produit
   * une balise que les réseaux ignorent en silence — c'est-à-dire un défaut
   * qu'aucun rendu ne révèle.
   */
  it('ne laisse pas passer un tiret dans l’étiquette Open Graph', () => {
    expect(OG_LOCALE).not.toContain('-');
  });
});
