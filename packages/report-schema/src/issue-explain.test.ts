// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';
import { fullReport } from './fixtures.js';
import { FIELD_LABELS, SECTION_LABELS, normalizeIssuePath } from './issue-explain.js';
import { validateReport } from './validate.js';
import type { Report } from './report.js';
import { fieldCatalog } from './field-catalog.js';

/**
 * Ce que cette suite garde : **le refus reste diagnosticable, et devient
 * lisible.** Les deux, pas l'un à la place de l'autre.
 *
 * Le message qui a motivé ce travail était complet et inutilisable :
 *
 * ```text
 * {"path":"$.power.batteries.0.cycleCount","message":"Too small: expected number to be >=0"}
 * ```
 *
 * Le chemin JSON reste donc exigé par chaque cas ci-dessous : c'est lui qui
 * permet de trouver le champ. Ce qui s'y ajoute est la phrase que la personne
 * qui dépose l'audit peut lire, et le geste qui corrige.
 */

/** Le premier refus d'un rapport volontairement abîmé. */
function refus(abimer: (report: Report) => void) {
  const report = JSON.parse(JSON.stringify(fullReport())) as Report;
  abimer(report);
  const resultat = validateReport(report);
  expect(resultat.ok, 'le rapport devait être refusé').toBe(false);
  if (resultat.ok) throw new Error('inatteignable');
  const premier = resultat.issues[0];
  expect(premier, 'aucun grief rendu').toBeDefined();
  return premier!;
}

describe('refus de validation expliqués', () => {
  it('nomme la pièce, la cause et le geste sur le défaut du 2026-08-27', () => {
    const issue = refus((r) => {
      r.power.batteries![0]!.cycleCount = -1 as never;
    });

    expect(issue.code).toBe('VALUE_BELOW_MINIMUM');
    expect(issue.section).toBe('power');
    expect(issue.title).toContain('compteur de cycles');
    expect(issue.userMessage).toContain('trop basse');
    expect(issue.received).toBe(-1);
    expect(issue.minimum).toBe(0);

    // Le champ accepte le marqueur « non collecté » : le scanner aurait donc dû
    // traduire l'aveu du firmware. C'est cela qui rend le conseil honnête.
    expect(issue.remediation).toContain('dernière version du scanner');

    // Et le niveau technique n'a pas bougé d'un caractère.
    expect(issue.path).toBe('$.power.batteries.0.cycleCount');
    expect(issue.message).toContain('Too small');
  });

  it('distingue un champ absent d’un champ mal rempli', () => {
    const absent = refus((r) => {
      delete (r.system as Record<string, unknown>).hostname;
    });
    expect(absent.code).toBe('VALUE_MISSING');
    expect(absent.userMessage).toContain('absent du rapport');

    const malRempli = refus((r) => {
      (r.memory as Record<string, unknown>).installedBytes = 'beaucoup';
    });
    expect(malRempli.code).toBe('VALUE_WRONG_TYPE');
    expect(malRempli.userMessage).toContain('type inattendu');
  });

  it('rend les valeurs admises quand une énumération est refusée', () => {
    const issue = refus((r) => {
      r.benchmark!.results[0]!.status = 'bizarre' as never;
    });

    expect(issue.code).toBe('VALUE_NOT_ALLOWED');
    expect(issue.allowed).toEqual(['completed', 'skipped', 'failed']);
    expect(issue.userMessage).toContain('completed');
    expect(issue.path).toBe('$.benchmark.results.0.status');
  });

  it('traverse l’union « valeur ou marqueur » au lieu de rendre « forme inattendue »', () => {
    /*
     * Presque tout champ collecté est `maybe(T)`. Sans le déroulage de l'union,
     * chacun de ces refus rendait `invalid_union` — c'est-à-dire le mot
     * « invalide » et rien d'autre, sur la quasi-totalité du schéma.
     */
    const issue = refus((r) => {
      r.power.batteries![0]!.chargePercent = 140 as never;
    });

    expect(issue.code).toBe('VALUE_ABOVE_MAXIMUM');
    expect(issue.maximum).toBe(100);
    expect(issue.userMessage).toContain('trop haute');
  });

  it('ne conseille rien quand aucun geste ne corrige', () => {
    // Une énumération hors domaine ne se répare pas en relançant le scan : le
    // rapport a été modifié. Conseiller « relancez l'audit » enverrait répéter
    // une manœuvre qui échouera pareil.
    const issue = refus((r) => {
      r.power.batteries![0]!.status = 'EXPLOSEE' as never;
    });
    expect(issue.remediation).toBeNull();
  });

  it('reste lisible sur un champ qu’aucune table ne nomme', () => {
    /*
     * La moitié importante de l'architecture. `FIELD_LABELS` est délibérément
     * partielle ; ce cas prouve que l'absence d'entrée ne ramène pas au JSON
     * brut. Un champ ajouté au schéma demain rend déjà un message utile.
     */
    const issue = refus((r) => {
      r.stability!.uptimeSeconds = -4 as never;
    });

    expect(FIELD_LABELS['stability.uptimeSeconds']).toBeUndefined();
    expect(issue.title).toBe('Stabilité');
    expect(issue.userMessage).toContain('uptimeSeconds');
    expect(issue.userMessage).toContain('trop basse');
    expect(issue.context, 'le contexte vient de FIELD_ANNOTATIONS').not.toBeNull();
  });
});

describe('tables de libellés', () => {
  it('ne nomme que des chemins qui existent', () => {
    // Le défaut qu'un tel test ferme : une table qui survit à une refonte du
    // schéma en décrivant des champs disparus, et qui retombe silencieusement
    // sur le repli en prétendant couvrir.
    const connus = new Set(fieldCatalog().map((entree) => entree.path.replace(/\[\]/g, '')));
    for (const chemin of Object.keys(FIELD_LABELS)) {
      expect(connus.has(chemin), `${chemin} ne désigne aucun champ du schéma`).toBe(true);
    }
  });

  it('nomme chaque section de premier niveau du schéma', () => {
    const sections = new Set(
      fieldCatalog().map((entree) => entree.path.split('.')[0]!.replace(/\[\]$/, '')),
    );
    for (const section of sections) {
      // Une section sans libellé rendrait son nom technique en titre. Ce n'est
      // pas illisible, mais c'est une régression silencieuse : autant l'exiger.
      expect(SECTION_LABELS[section], `section « ${section} » sans libellé`).toBeDefined();
    }
  });

  it('efface les index de tableau du chemin, jamais les noms', () => {
    expect(normalizeIssuePath('$.power.batteries.0.cycleCount')).toBe('power.batteries.cycleCount');
    expect(normalizeIssuePath('$.storage.disks.12.smart.wearPercent')).toBe(
      'storage.disks.smart.wearPercent',
    );
    expect(normalizeIssuePath('$')).toBe('');
  });
});
