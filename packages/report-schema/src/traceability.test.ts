// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';

import { reportSchema } from './report.js';
import { SECTION_TRACEABILITY } from './traceability.js';

describe('traçabilité des sections', () => {
  const schemaSections = Object.keys(reportSchema.shape).sort();
  const registered = Object.keys(SECTION_TRACEABILITY).sort();

  it('couvre toutes les sections du schéma', () => {
    // Le message importe autant que l'assertion : ce test échouera un jour
    // devant quelqu'un qui vient d'ajouter une section, et qui doit comprendre
    // qu'on lui demande une décision, pas une ligne à recopier.
    const missing = schemaSections.filter((section) => !(section in SECTION_TRACEABILITY));
    expect(
      missing,
      `Sections ajoutées au schéma sans décision de destination : ${missing.join(', ')}. ` +
        'Déclarer dans traceability.ts qui les consomme — et si la réponse est ' +
        '« personne », écrire pourquoi dans `note`.',
    ).toEqual([]);
  });

  it('ne décrit aucune section absente du schéma', () => {
    const extra = registered.filter((section) => !(section in reportSchema.shape));
    expect(extra, `Sections décrites mais absentes du schéma : ${extra.join(', ')}.`).toEqual([]);
  });

  it('exige une justification quand aucun consommateur ne lit la section', () => {
    // Une section que personne ne lit n'est pas interdite — `notes` est
    // volontairement inerte. Ce qui est interdit, c'est qu'elle le soit sans
    // que quiconque l'ait décidé.
    const orphansWithoutReason = Object.entries(SECTION_TRACEABILITY)
      .filter(
        ([, trace]) => !trace.facts && !trace.renderer && !trace.web && !trace.rules && !trace.ai,
      )
      .filter(([, trace]) => trace.note === undefined || trace.note.trim() === '')
      .map(([section]) => section);

    expect(
      orphansWithoutReason,
      `Sections collectées que rien ne consomme, et sans explication : ${orphansWithoutReason.join(', ')}.`,
    ).toEqual([]);
  });
});
