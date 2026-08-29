// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';
import { fullReport, minimalReport } from './fixtures.js';
import type { Report } from './report.js';
import { sectionProvenance, sectionProvenanceNote } from './section-provenance.js';

/**
 * Le pont entre les deux provenances, et l'interdiction d'en inventer une.
 *
 * `collection.provenance` dit par quoi une section a été lue ; `Sourced<T>` dit
 * d'où vient une valeur. Les deux répondaient à la même question du lecteur
 * dans deux vocabulaires, sans se croiser. Ce module traduit le premier dans le
 * second — et le danger est évident : une traduction qui comblerait les trous
 * ferait croire à une provenance documentée là où le scanner s'est tu.
 */

function withProvenance(entries: Record<string, unknown>): Report {
  const report = fullReport();
  return {
    ...report,
    collection: { ...report.collection, provenance: entries },
  } as Report;
}

describe('sectionProvenance', () => {
  it('traduit une lecture de fichier dans le vocabulaire des valeurs', () => {
    const provenance = sectionProvenance(fullReport(), 'audio.devices');
    expect(provenance?.status).toBe('collected');
    expect(provenance?.source).toBe('/proc/asound/cards');
    // La machine s'est décrite elle-même : c'est une mesure, pas une déduction.
    expect(provenance?.sourceType).toBe('os');
  });

  it('reconnaît un utilitaire tiers, dont on croit la lecture sans la vérifier', () => {
    const report = withProvenance({
      'storage.disks[0].smart': { source: 'smartctl -a', method: 'commande shell' },
    });
    expect(sectionProvenance(report, 'storage.disks[0].smart')?.sourceType).toBe('tool');
  });

  it('reconnaît le micrologiciel, qui n’est pas le système', () => {
    const report = withProvenance({
      'memory.modules': { source: 'dmidecode -t memory', method: 'commande shell' },
    });
    expect(sectionProvenance(report, 'memory.modules')?.sourceType).toBe('firmware');
  });

  it('conserve l’horodatage de la lecture', () => {
    expect(sectionProvenance(fullReport(), 'audio.devices')?.retrievedAt).toBe(
      '2026-07-25T16:42:00Z',
    );
  });

  /*
   * Le refus qui compte. « Le scanner ne documente que les chemins où l'origine
   * change la lecture » — un chemin absent n'est pas « lu autrement », il est
   * « non documenté », et lui fabriquer une provenance générique ferait croire
   * à une couverture qui n'existe pas.
   */
  it('ne fabrique aucune provenance pour un chemin non documenté', () => {
    expect(sectionProvenance(fullReport(), 'cpus[0].temperatureCelsius')).toBeUndefined();
  });

  it('ne fabrique rien quand le scanner n’a documenté aucun chemin', () => {
    expect(sectionProvenance(minimalReport(), 'audio.devices')).toBeUndefined();
  });
});

describe('sectionProvenance — remontée aux ancêtres', () => {
  /*
   * Le scanner documente `storage.disks[0].smart` ; le rendu demande
   * `storage.disks[].smart.temperatureCelsius`, parce qu'il décrit une forme et
   * non une occurrence. Exiger l'égalité stricte rendrait la table inutilisable
   * depuis son seul lecteur.
   */
  it('ramène les crochets vides du rendu à l’indice que le scanner documente', () => {
    const report = withProvenance({
      'storage.disks[0].smart': { source: 'smartctl -a' },
    });
    expect(sectionProvenance(report, 'storage.disks[].smart')?.source).toBe('smartctl -a');
  });

  it('remonte au premier ancêtre documenté', () => {
    const report = withProvenance({ 'storage.disks': { source: 'lsblk -J' } });
    expect(sectionProvenance(report, 'storage.disks[0].model')?.source).toBe('lsblk -J');
  });

  it('prend le premier champ d’un chemin composé', () => {
    const report = withProvenance({ 'bios.mode': { source: 'dmidecode -t bios' } });
    expect(sectionProvenance(report, 'bios.mode|boot.firmwareMode')?.source).toBe(
      'dmidecode -t bios',
    );
  });

  it('ne remonte pas jusqu’à une racine non documentée', () => {
    const report = withProvenance({ 'audio.devices': { source: '/proc/asound/cards' } });
    expect(sectionProvenance(report, 'storage.disks[0].model')).toBeUndefined();
  });
});

describe('sectionProvenanceNote', () => {
  it('nomme ce qui a été interrogé, et sa précision', () => {
    expect(sectionProvenanceNote(fullReport(), 'audio.devices')).toBe(
      'lu par /proc/asound/cards, carte',
    );
  });

  /*
   * Une provenance héritée de `storage.disks` est vraie de tous les disques,
   * mais elle n'a pas été écrite pour celui-ci. Taire l'héritage la ferait
   * passer pour une documentation propre au chemin demandé.
   */
  it('dit sur quel chemin la provenance a réellement été documentée', () => {
    const report = withProvenance({ 'storage.disks': { source: 'lsblk -J' } });
    expect(sectionProvenanceNote(report, 'storage.disks[0].model')).toBe(
      'lu par lsblk -J (documenté sur storage.disks)',
    );
  });

  it('ne mentionne aucun héritage quand le chemin est celui documenté', () => {
    const report = withProvenance({ 'storage.disks[0].model': { source: 'lsblk -J' } });
    expect(sectionProvenanceNote(report, 'storage.disks[].model')).toBe('lu par lsblk -J');
  });

  it('reste muet sur un chemin non documenté', () => {
    expect(sectionProvenanceNote(fullReport(), 'cpus[0].model')).toBeUndefined();
  });
});
