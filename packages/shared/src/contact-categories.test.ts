// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';
import {
  CONTACT_CATEGORIES,
  CONTACT_CATEGORY_LABELS,
  contactCategoryLabel,
  normalizeContactCategory,
} from './contact-categories.js';

describe('catégories de contact', () => {
  it('nomme chaque famille, sans doublon', () => {
    expect(new Set(CONTACT_CATEGORIES).size).toBe(CONTACT_CATEGORIES.length);
    for (const category of CONTACT_CATEGORIES) {
      expect(CONTACT_CATEGORY_LABELS[category]).toBeTruthy();
    }
  });

  it('garde une famille pour les demandes relatives aux données personnelles', () => {
    // Elle ouvre un délai de réponse réglementaire : la noyer dans « autre »
    // garantit qu'on la découvrira en retard.
    expect(CONTACT_CATEGORIES).toContain('privacy');
  });

  it('ramène une valeur inconnue à « autre » plutôt que de refuser le message', () => {
    /*
     * La seule concession du formulaire. Refuser un message parce que le champ
     * le moins important a été recopié de travers ferait perdre le message —
     * et c'est le message qui compte, pas son étiquette.
     */
    expect(normalizeContactCategory('bug')).toBe('bug');
    expect(normalizeContactCategory('anomalie')).toBe('other');
    expect(normalizeContactCategory(undefined)).toBe('other');
    expect(normalizeContactCategory(42)).toBe('other');
  });

  it('rend un libellé lisible pour toute valeur', () => {
    expect(contactCategoryLabel('privacy')).toBe('Protection des données');
    expect(contactCategoryLabel('n’importe quoi')).toBe('Autre');
  });
});
