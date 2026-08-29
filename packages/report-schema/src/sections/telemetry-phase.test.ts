// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';
import { benchmarkTargetSchema } from './benchmark.js';
import { telemetryPhaseSchema } from './monitoring.js';

/**
 * `telemetryPhaseSchema` recopie les cibles du banc d'essai plutôt que de les
 * importer : `monitoring` ne doit pas dépendre de `benchmark`, sans quoi la
 * série temporelle deviendrait inutilisable seule.
 *
 * Le prix de ce découplage est une duplication, et le prix d'une duplication est
 * la dérive : une cible ajoutée d'un côté et pas de l'autre produirait des
 * échantillons dont la phase serait rejetée par la validation — après la
 * collecte, donc trop tard. Ce test rend la dérive impossible à commettre en
 * silence.
 */
describe('phases de télémétrie et cibles du banc d’essai', () => {
  it('couvre exactement les cibles du banc d’essai, plus le repos', () => {
    const phases = new Set<string>(telemetryPhaseSchema.options);
    const targets = new Set<string>(benchmarkTargetSchema.options);

    expect(phases.has('idle')).toBe(true);

    // Chaque cible mesurable doit pouvoir étiqueter un échantillon.
    for (const target of targets) {
      expect(phases.has(target), `cible « ${target} » sans phase correspondante`).toBe(true);
    }

    // Et l'inverse : une phase sans cible désignerait une charge que le banc
    // d'essai n'exécute pas, donc un état qu'aucun échantillon ne peut porter.
    for (const phase of phases) {
      if (phase === 'idle') continue;
      expect(targets.has(phase), `phase « ${phase} » sans cible correspondante`).toBe(true);
    }
  });

  it('n’accepte pas une phase inventée', () => {
    expect(telemetryPhaseSchema.safeParse('cpu-turbo').success).toBe(false);
  });
});
