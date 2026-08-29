// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';
import {
  FACTORY_PLACEHOLDER_DETAIL,
  REASON_LABELS,
  UNKNOWN_REASONS,
  fromRaw,
  isFactoryPlaceholder,
  isKnown,
  isUnknown,
  meaningful,
  numberFromRaw,
  reasonLabel,
  unknown,
  valueOr,
} from './unknown.js';

describe('UNKNOWN_REASONS', () => {
  /**
   * Les sept états que le chantier « Cross-Platform Insight » exige de savoir
   * distinguer. Le huitième — `available` — est l'absence de marqueur.
   */
  it('distingue l’indisponibilité, l’absence d’outil, le refus et le hors-sujet', () => {
    expect(UNKNOWN_REASONS).toContain('UNKNOWN');
    expect(UNKNOWN_REASONS).toContain('NOT_AVAILABLE');
    expect(UNKNOWN_REASONS).toContain('UNSUPPORTED');
    expect(UNKNOWN_REASONS).toContain('PERMISSION_DENIED');
    expect(UNKNOWN_REASONS).toContain('NOT_APPLICABLE');
  });

  it('ne confond pas « rien à mesurer » avec « mesure impossible »', () => {
    expect(unknown('NOT_APPLICABLE').reason).not.toBe(unknown('UNSUPPORTED').reason);
  });
});

describe('unknown', () => {
  it('construit un marqueur avec sa raison', () => {
    expect(unknown('PERMISSION_DENIED')).toEqual({
      unknown: true,
      reason: 'PERMISSION_DENIED',
    });
  });

  it('conserve le détail lorsqu’il est fourni', () => {
    expect(unknown('NOT_AVAILABLE', 'smartctl absent')).toEqual({
      unknown: true,
      reason: 'NOT_AVAILABLE',
      detail: 'smartctl absent',
    });
  });

  it('n’ajoute pas de clé detail undefined (le JSON resterait pollué)', () => {
    expect(Object.keys(unknown())).toEqual(['unknown', 'reason']);
  });
});

describe('isUnknown / isKnown', () => {
  it('reconnaît un marqueur', () => {
    expect(isUnknown(unknown())).toBe(true);
    expect(isKnown(unknown())).toBe(false);
  });

  it('ne confond pas une valeur métier avec un marqueur', () => {
    expect(isUnknown('UNKNOWN')).toBe(false);
    expect(isUnknown({ unknown: true })).toBe(false);
    expect(isUnknown(null)).toBe(false);
    expect(isUnknown({ reason: 'UNKNOWN' })).toBe(false);
  });
});

describe('valueOr', () => {
  it('retourne la valeur connue', () => {
    expect(valueOr('Debian', 'fallback')).toBe('Debian');
  });

  it('retourne le fallback pour une valeur inconnue', () => {
    expect(valueOr(unknown(), null)).toBeNull();
  });
});

describe('fromRaw', () => {
  it('nettoie les espaces', () => {
    expect(fromRaw('  Dell Inc.  ')).toBe('Dell Inc.');
  });

  it.each([undefined, null, '', '   '])('traite %p comme inconnu', (input) => {
    expect(isUnknown(fromRaw(input))).toBe(true);
  });

  it.each([
    'To Be Filled By O.E.M.',
    'Default string',
    'System Product Name',
    'Not Specified',
    'n/a',
  ])('rejette le placeholder BIOS %s', (input) => {
    const result = fromRaw(input);
    expect(isUnknown(result)).toBe(true);
    expect(isUnknown(result) && result.detail).toContain('placeholder');
  });

  it('propage la raison demandée', () => {
    const result = fromRaw(null, 'PERMISSION_DENIED');
    expect(isUnknown(result) && result.reason).toBe('PERMISSION_DENIED');
  });
});

describe('numberFromRaw', () => {
  it('convertit une chaîne numérique', () => {
    expect(numberFromRaw('42')).toBe(42);
  });

  it('accepte 0 comme valeur légitime', () => {
    expect(numberFromRaw(0)).toBe(0);
  });

  it.each(['abc', '', null, undefined, Number.NaN, Number.POSITIVE_INFINITY])(
    'rejette %p',
    (input) => {
      expect(isUnknown(numberFromRaw(input))).toBe(true);
    },
  );
});

describe('libellés des raisons d’absence', () => {
  /**
   * Ce que ces tests protègent, et pourquoi ils sont ici plutôt qu'ailleurs.
   *
   * Cette table a existé en trois exemplaires — moteur de rendu, interface,
   * résumé système — et chaque copie a divergé à sa façon : l'une oubliait
   * `NOT_APPLICABLE` et affichait le sigle brut au lecteur, l'autre traduisait
   * `UNSUPPORTED` par « sans objet », qui est la définition de
   * `NOT_APPLICABLE`. Le moteur d'analyse écrivait le sigle tel quel dans ses
   * messages. Une seule table, dans le paquet dont tous dépendent, et un test à
   * la source.
   */
  it('nomme **toutes** les raisons du schéma', () => {
    for (const raison of UNKNOWN_REASONS) {
      expect(REASON_LABELS[raison], `« ${raison} » n’a pas de libellé`).toBeTruthy();
      expect(reasonLabel(raison), `« ${raison} » sort en sigle`).not.toBe(raison);
    }
  });

  it('distingue « non pris en charge » de « sans objet »', () => {
    // « Ce système ne sait pas répondre » n'est pas « la question ne se pose pas
    // ici ». Les deux raisons existent pour cette distinction ; les traduire
    // pareil la perdrait.
    expect(reasonLabel('UNSUPPORTED')).toBe('non pris en charge');
    expect(reasonLabel('NOT_APPLICABLE')).toBe('sans objet');
  });

  it('rend une raison inconnue telle quelle plutôt que d’échouer', () => {
    // Un rapport archivé peut porter une raison retirée du schéma depuis : son
    // rendu doit sortir, fût-ce avec le sigle. C'est aussi ce repli qui rendait
    // les omissions invisibles, d'où le test ci-dessus.
    expect(reasonLabel('RAISON_DISPARUE')).toBe('RAISON_DISPARUE');
  });
});

describe('meaningful', () => {
  /**
   * Le cas de `QJVJVFA6` : deux barrettes CORSAIR dont le SMBIOS porte
   * littéralement la chaîne `Unknown`. Le schéma l'accepte — c'est un texte —
   * et l'interface l'affichait telle quelle, ce qui se lit « SysAudit n'a pas
   * su lire » alors que c'est le firmware qui n'a pas écrit.
   */
  it('ramène un placeholder d’usine au marqueur qu’il aurait dû être', () => {
    const lu = meaningful('Unknown');
    expect(isUnknown(lu)).toBe(true);
    expect(isUnknown(lu) ? lu.detail : null).toBe(FACTORY_PLACEHOLDER_DETAIL);
  });

  it('traite « To be filled by O.E.M. » comme une absence', () => {
    expect(isUnknown(meaningful('To be filled by O.E.M.'))).toBe(true);
  });

  it('traite un numéro de série de huit zéros comme une absence', () => {
    // Deux modules qui portent tous deux `00000000` ne sont pas le même
    // module : s'en servir pour dédupliquer effacerait l'un des deux.
    expect(isUnknown(meaningful('00000000'))).toBe(true);
  });

  it('laisse passer une vraie valeur, débarrassée de ses bords', () => {
    expect(meaningful('  Corsair ')).toBe('Corsair');
  });

  it('ne touche pas à un marqueur déjà posé', () => {
    const marqueur = unknown('PERMISSION_DENIED');
    expect(meaningful(marqueur)).toBe(marqueur);
  });

  it('distingue « section absente » de « valeur d’usine »', () => {
    // `undefined` doit rester `undefined` : le rendu écrit « non collecté »,
    // ce qui n'est pas la même chose qu'un champ collecté mais vide.
    expect(meaningful(undefined)).toBeUndefined();
  });

  it('n’efface pas une marque dont le nom contient un mot de la liste', () => {
    // La comparaison est exacte, jamais une inclusion : `Unknown Technology`
    // est une société, et un motif large la ferait disparaître.
    expect(meaningful('Unknown Technology Ltd')).toBe('Unknown Technology Ltd');
  });
});

describe('isFactoryPlaceholder', () => {
  it('reconnaît les valeurs d’usine, quelle que soit la casse', () => {
    expect(isFactoryPlaceholder('UNKNOWN')).toBe(true);
    expect(isFactoryPlaceholder('Default string')).toBe(true);
  });

  it('rend faux sur autre chose qu’une chaîne', () => {
    expect(isFactoryPlaceholder(unknown('UNKNOWN'))).toBe(false);
    expect(isFactoryPlaceholder(42)).toBe(false);
  });

  it('rend faux sur une chaîne vide : c’est une absence, pas un placeholder', () => {
    expect(isFactoryPlaceholder('   ')).toBe(false);
  });
});
