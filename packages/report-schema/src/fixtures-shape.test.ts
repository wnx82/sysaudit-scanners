// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { isUnknown } from '@sysaudit/shared';
import { describe, expect, it } from 'vitest';
import { SHAPE_FIXTURE_KEYS, shapeFixture, shapeFixtures } from './fixtures-shape.js';
import { validateReport } from './validate.js';
import { SCHEMA_VERSION } from './version.js';

/**
 * Les formes de machine, et ce qu'elles éprouvent.
 *
 * Les onze fixtures OS décrivent onze systèmes sur **une seule** machine : une
 * tour complète, avec capteurs, batterie, une carte graphique et un disque.
 * C'est le cas le plus favorable, et c'était le seul que la plupart des tests
 * voyaient.
 *
 * Les défauts que ce dépôt existe pour empêcher n'arrivent pas là. Ils arrivent
 * sur la machine à laquelle il **manque** quelque chose.
 */

describe('fixtures par forme de machine', () => {
  it.each(shapeFixtures())('$label : rapport valide au regard du schéma', ({ report }) => {
    const validation = validateReport(report, { rejectSecrets: true });

    if (!validation.ok) {
      throw new Error(
        `${validation.code} — ${validation.issues
          .slice(0, 5)
          .map((issue) => `${issue.path} : ${issue.message}`)
          .join(' ; ')}`,
      );
    }

    expect(validation.ok).toBe(true);
  });

  it.each(shapeFixtures())('$label : annonce la version de schéma courante', ({ report }) => {
    expect(report.schemaVersion).toBe(SCHEMA_VERSION);
  });

  it('donne à chaque forme une identité distincte', () => {
    const identities = shapeFixtures().map(({ report }) => String(report.system.uuid));
    expect(new Set(identities).size).toBe(identities.length);
  });

  it('produit un rapport identique à chaque construction', () => {
    for (const key of SHAPE_FIXTURE_KEYS) {
      expect(JSON.stringify(shapeFixture(key))).toBe(JSON.stringify(shapeFixture(key)));
    }
  });
});

describe('fixtures par forme — ce que chacune éprouve réellement', () => {
  /*
   * Une fixture qui ne porte pas le trait qu'elle annonce est pire qu'une
   * fixture absente : elle donne l'assurance sans la couverture. Ces
   * assertions vérifient que chaque forme est bien celle qu'elle dit être.
   */

  it('« sans capteur » retire la section, elle ne la vide pas', () => {
    // Une section absente dit « rien n'a été lu » ; une section vide dit
    // « rien n'existe ». Un tableau de capteurs vide se lirait « cette machine
    // n'a pas de sonde », ce qui est faux d'un serveur en baie.
    const report = shapeFixture('sans-capteur');
    expect(report.sensors).toBeUndefined();
    expect(isUnknown(report.cpus?.[0]?.temperatureCelsius)).toBe(true);
  });

  it('« sans batterie » rend un tableau vide, et non une batterie absente', () => {
    // Ici l'inverse : la section `power` existe, la machine est alimentée, et
    // c'est bien « zéro batterie » qu'il faut lire — pas « batterie non lue ».
    const report = shapeFixture('sans-batterie');
    expect(report.power?.batteries).toHaveLength(0);
    expect(report.power?.acConnected).toBe(true);
  });

  it('« portable » porte une batterie usée, dans la zone qui fait basculer un verdict', () => {
    const battery = shapeFixture('portable').power?.batteries?.[0];
    expect(battery?.designCapacityWh).toBe(56);
    expect(battery?.fullChargeCapacityWh).toBe(39.8);
    // 39,8 / 56 = 71,07 % : au-dessus du seuil d'alerte, en dessous du neuf.
    expect(battery?.cycleCount).toBe(612);
  });

  it('« tour » ne nomme ni constructeur ni modèle', () => {
    const system = shapeFixture('tour').system;
    expect(isUnknown(system.manufacturer)).toBe(true);
    expect(isUnknown(system.model)).toBe(true);
  });

  it('« machine virtuelle » n’a ni capteur, ni alimentation, ni SMART', () => {
    const report = shapeFixture('machine-virtuelle');
    expect(report.sensors).toBeUndefined();
    expect(report.power).toBeUndefined();
    expect(report.storage?.disks?.[0]?.smart).toBeUndefined();
    expect(report.virtualization?.runningUnder).toBe('kvm');
  });

  it('« multi-GPU » porte deux cartes, dont une intégrée', () => {
    const gpus = shapeFixture('multi-gpu').gpus ?? [];
    expect(gpus).toHaveLength(2);
    // La VRAM d'un cœur intégré n'est pas « inconnue » : elle est partagée,
    // donc sans objet. Les deux ne se lisent pas pareil.
    expect(isUnknown(gpus[0]?.vramBytes)).toBe(true);
    expect(String(gpus[1]?.pciId)).toContain('SUBSYS_403B1458');
  });

  it('« valeurs d’usine » porte les chaînes qui ressemblent à des mesures', () => {
    const report = shapeFixture('valeurs-usine');
    expect(report.system.manufacturer).toBe('System manufacturer');
    expect(report.motherboard?.serialNumber).toBe('Default string');
    expect(report.memory?.modules?.[0]?.manufacturer).toBe('Unknown');
  });

  /*
   * Le garde-fou global. Une forme qui perdrait son trait en route — un
   * refactor de `fullReport()`, un champ renommé — passerait les assertions
   * ci-dessus une à une et ne prouverait plus rien collectivement.
   */
  it('ne se réduit pas toutes au même rapport', () => {
    const rendered = shapeFixtures().map(({ report }) => {
      const { system: _system, ...rest } = report;
      return JSON.stringify(rest);
    });
    expect(new Set(rendered).size).toBe(rendered.length);
  });
});
