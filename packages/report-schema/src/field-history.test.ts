// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';
import { fieldCatalog } from './field-catalog.js';
import { HISTORICAL_FIELD_PATHS } from './field-history.js';

/**
 * Non-régression du contrat de données (roadmap audits v2, P0).
 *
 * La règle du produit est qu'une évolution de format est **additive** : un
 * rapport produit il y a six mois doit rester lisible, et une section du rapport
 * ne disparaît pas parce qu'une refonte l'a jugée redondante.
 *
 * L'empreinte du JSON Schema ne suffit pas à le garantir : elle échoue autant
 * pour un ajout que pour un retrait, et se répare du même geste. Ce test-ci
 * n'échoue que dans un sens.
 */
describe('champs historiques', () => {
  const current = new Set(fieldCatalog().map((entry) => entry.path));

  it('n’en supprime aucun', () => {
    const missing = HISTORICAL_FIELD_PATHS.filter((path) => !current.has(path));
    expect(
      missing,
      'Ces chemins étaient publiés et ne le sont plus. Une suppression de champ est une ' +
        'rupture MAJOR : voir docs/format-rapport/VERSIONING.md, ajouter un adaptateur dans src/migrations/, ' +
        'puis retirer le chemin de field-history.ts à la main.',
    ).toEqual([]);
  });

  it('reste à jour des champs ajoutés depuis la dernière régénération', () => {
    const added = [...current].filter((path) => !HISTORICAL_FIELD_PATHS.includes(path));
    expect(
      added,
      'Champs ajoutés au schéma mais absents de l’inventaire : lancer ' +
        '`npm run docs:field-history`.',
    ).toEqual([]);
  });
});
