// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';
import {
  collected,
  confidenceBand,
  isMeasured,
  isSourced,
  manual,
  provenanceOf,
  provenanceStatusOf,
  resolved,
  sourcedValue,
  toMaybe,
  type MaybeSourced,
} from './provenance.js';
import { unknown } from './unknown.js';

/**
 * Ce que ces tests protègent.
 *
 * Une seule règle, déclinée : **une valeur retrouvée ne doit jamais pouvoir se
 * faire passer pour une valeur mesurée**. Chaque cas est donc éprouvé dans les
 * deux sens — ce que la provenance doit dire, et ce qu'elle ne doit surtout pas
 * laisser croire. Un test qui ne vérifierait que le cas nominal passerait aussi
 * si tout devenait « mesuré ».
 */

const HORODATAGE = '2026-08-19T00:00:00.000Z';

describe('valeurs mesurées', () => {
  it('porte sa source et vaut une mesure', () => {
    const capacite = collected(16, { source: 'dmidecode:memory-device', sourceType: 'firmware' });

    expect(capacite.value).toBe(16);
    expect(capacite.provenance.status).toBe('collected');
    expect(isMeasured(capacite)).toBe(true);
  });

  it('vaut 1 de confiance par défaut : la machine s’est décrite elle-même', () => {
    expect(collected('x', { source: 'sysfs' }).provenance.confidence).toBe(1);
  });

  it('n’est plus une mesure quand elle vient d’un utilitaire tiers', () => {
    // `smartctl` est cru sur parole : sa lecture n'est pas vérifiable depuis le
    // scanner. C'est une collecte, mais pas une mesure de la machine.
    const usure = collected(3, { source: 'smartctl', sourceType: 'tool' });

    expect(usure.provenance.status).toBe('collected');
    expect(isMeasured(usure)).toBe(false);
  });
});

describe('valeurs retrouvées', () => {
  const marque = resolved('Crucial', {
    source: 'catalog:hardware-vendors',
    sourceType: 'local_catalog',
    matchMethod: 'exact_normalized_part_number',
    confidence: 1,
    retrievedAt: HORODATAGE,
    rawValue: 'Unknown',
  });

  it('n’est jamais présentée comme une mesure, même à confiance maximale', () => {
    // Le cœur du module. Une résolution parfaite reste une résolution : c'est
    // la table qui a raison, pas la machine qui a parlé.
    expect(marque.value).toBe('Crucial');
    expect(marque.provenance.confidence).toBe(1);
    expect(isMeasured(marque)).toBe(false);
  });

  it('conserve ce que la machine disait réellement', () => {
    // Sans `rawValue`, une résolution erronée efface le `Unknown` d'origine et
    // plus rien ne permet de constater que la table s'est trompée.
    expect(marque.provenance.rawValue).toBe('Unknown');
  });

  it('refuse une résolution sans méthode d’appariement', () => {
    expect(() =>
      resolved('Crucial', {
        source: 'catalog',
        sourceType: 'local_catalog',
        matchMethod: '   ',
        confidence: 1,
        retrievedAt: HORODATAGE,
      }),
    ).toThrow(/matchMethod/);
  });

  it('refuse une résolution sans horodatage', () => {
    expect(() =>
      resolved('Crucial', {
        source: 'catalog',
        sourceType: 'local_catalog',
        matchMethod: 'exact',
        confidence: 1,
        retrievedAt: '',
      }),
    ).toThrow(/retrievedAt/);
  });
});

describe('garde-fous de construction', () => {
  it('refuse une confiance hors de [0, 1]', () => {
    for (const invalide of [-0.1, 1.5, Number.NaN, Number.POSITIVE_INFINITY]) {
      expect(() => collected('x', { source: 'sysfs', confidence: invalide })).toThrow(/confidence/);
    }
  });

  it('accepte les deux bornes', () => {
    expect(collected('x', { source: 'sysfs', confidence: 0 }).provenance.confidence).toBe(0);
    expect(collected('x', { source: 'sysfs', confidence: 1 }).provenance.confidence).toBe(1);
  });

  it('refuse une source vide, qui ne documente rien', () => {
    expect(() => collected('x', { source: '  ' })).toThrow(/source/);
  });

  it('n’écrit pas les champs facultatifs absents', () => {
    // Un `rawValue: undefined` sérialisé en JSON disparaît, mais un test
    // d'empreinte de schéma, lui, verrait la clé apparaître.
    const provenance = collected('x', { source: 'sysfs' }).provenance;

    expect(Object.hasOwn(provenance, 'rawValue')).toBe(false);
    expect(Object.hasOwn(provenance, 'retrievedAt')).toBe(false);
  });
});

describe('saisie manuelle', () => {
  it('garde une confiance pleine sans se faire passer pour une mesure', () => {
    // Qui a lu l'étiquette du bloc d'alimentation sait mieux que n'importe
    // quelle table. Ce qui doit rester visible est que la machine n'a rien dit.
    const puissance = manual(650, { source: 'admin:console' });

    expect(puissance.provenance.confidence).toBe(1);
    expect(puissance.provenance.status).toBe('manual');
    expect(isMeasured(puissance)).toBe(false);
  });
});

describe('absence', () => {
  const absent: MaybeSourced<string> = unknown('NOT_AVAILABLE', 'aucun capteur');
  const sansObjet: MaybeSourced<string> = unknown('NOT_APPLICABLE');

  it('n’est pas une mesure de zéro', () => {
    expect(isMeasured(absent)).toBe(false);
    expect(sourcedValue(absent)).toBeUndefined();
    expect(provenanceOf(absent)).toBeUndefined();
  });

  it('distingue « rien à mesurer » de « je n’ai pas pu lire »', () => {
    // La distinction conservée est celle qui change ce que le lecteur doit
    // faire : l'une n'appelle aucune action, l'autre peut en appeler une.
    expect(provenanceStatusOf(sansObjet)).toBe('not_applicable');
    expect(provenanceStatusOf(absent)).toBe('unavailable');
  });

  it('ramène les autres raisons à `unavailable` sans perdre le détail', () => {
    for (const raison of [
      'UNKNOWN',
      'UNSUPPORTED',
      'PERMISSION_DENIED',
      'NOT_COLLECTED',
    ] as const) {
      expect(provenanceStatusOf(unknown(raison))).toBe('unavailable');
    }
    // Le marqueur d'origine n'est pas jeté : il reste lisible tel quel.
    expect(absent).toMatchObject({ reason: 'NOT_AVAILABLE', detail: 'aucun capteur' });
  });

  it('traverse `toMaybe` sans se transformer en valeur', () => {
    expect(toMaybe(absent)).toBe(absent);
    expect(toMaybe(collected(4, { source: 'sysfs' }))).toBe(4);
  });
});

describe('isSourced', () => {
  it('reconnaît les trois formes présentes', () => {
    expect(isSourced(collected(1, { source: 's' }))).toBe(true);
    expect(
      isSourced(
        resolved(1, {
          source: 's',
          sourceType: 'local_catalog',
          matchMethod: 'm',
          confidence: 0.5,
          retrievedAt: HORODATAGE,
        }),
      ),
    ).toBe(true);
    expect(isSourced(manual(1))).toBe(true);
  });

  it('ne se laisse pas prendre par ce qui y ressemble', () => {
    for (const imposteur of [
      null,
      undefined,
      42,
      'collected',
      {},
      { value: 1 },
      { value: 1, provenance: null },
      { value: 1, provenance: { status: 'unavailable' } },
      unknown('UNKNOWN'),
    ]) {
      expect(isSourced(imposteur), JSON.stringify(imposteur) ?? 'undefined').toBe(false);
    }
  });
});

describe('confidenceBand', () => {
  it('ne rend `HIGH` que pour une correspondance exacte', () => {
    // 0,95 reste une résolution. Le rappeler est tout l'objet du module : un
    // seuil permissif rendrait la mention de provenance inutile.
    expect(confidenceBand(1)).toBe('HIGH');
    expect(confidenceBand(0.95)).toBe('MEDIUM');
  });

  it('sépare le vraisemblable du douteux', () => {
    expect(confidenceBand(0.7)).toBe('MEDIUM');
    expect(confidenceBand(0.69)).toBe('LOW');
    expect(confidenceBand(0)).toBe('LOW');
  });
});
