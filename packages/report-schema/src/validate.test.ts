// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';
import { fullReport, minimalReport } from './fixtures.js';
import { parseReport, validateReport } from './validate.js';
import { SCHEMA_VERSION } from './version.js';

describe('validateReport — fixtures de référence', () => {
  it('accepte le rapport minimal', () => {
    const result = validateReport(minimalReport());
    expect(result.ok, result.ok ? '' : JSON.stringify(result.issues, null, 2)).toBe(true);
  });

  it('accepte le rapport complet', () => {
    const result = validateReport(fullReport());
    expect(result.ok, result.ok ? '' : JSON.stringify(result.issues, null, 2)).toBe(true);
  });

  it('conserve les données du rapport complet après normalisation', () => {
    const result = validateReport(fullReport());
    if (!result.ok) throw new Error('rapport de référence invalide');
    expect(result.report.virtualization?.proxmox?.vms[0]?.vmid).toBe(100);
    expect(result.report.storage?.disks[0]?.smart?.nvmePercentageUsed).toBe(87);
  });
});

describe('validateReport — version du schéma', () => {
  it('refuse une entrée qui n’est pas un objet', () => {
    for (const input of ['{}', 42, null, [], undefined]) {
      const result = validateReport(input);
      expect(result.ok).toBe(false);
      expect(!result.ok && result.code).toBe('MALFORMED');
    }
  });

  it('refuse un rapport sans schemaVersion', () => {
    const { schemaVersion: _omitted, ...rest } = minimalReport();
    const result = validateReport(rest);
    expect(!result.ok && result.code).toBe('MISSING_SCHEMA_VERSION');
  });

  it('refuse un schemaVersion non SemVer', () => {
    const result = validateReport({ ...minimalReport(), schemaVersion: 'v1' });
    expect(!result.ok && result.code).toBe('MISSING_SCHEMA_VERSION');
  });

  it('refuse une version MAJOR incompatible avec un message explicite', () => {
    const result = validateReport({ ...minimalReport(), schemaVersion: '2.0.0' });
    expect(!result.ok && result.code).toBe('INCOMPATIBLE_MAJOR');
    expect(!result.ok && result.message).toContain('2.0.0');
  });

  it('refuse un rapport produit par un scanner plus récent', () => {
    const result = validateReport({ ...minimalReport(), schemaVersion: '1.99.0' });
    expect(!result.ok && result.code).toBe('UNSUPPORTED_MINOR');
    expect(!result.ok && result.message).toContain('Mettez à jour SysAudit');
  });

  it('accepte un rapport plus ancien et signale sa version d’origine', () => {
    const result = validateReport(
      { ...minimalReport(), schemaVersion: '1.0.0' },
      { supportedVersion: '1.4.0' },
    );
    expect(result.ok).toBe(true);
    expect(result.ok && result.upgradedFrom).toBe('1.0.0');
  });

  it('ne signale pas d’ancienneté pour un rapport de la version courante', () => {
    const result = validateReport(minimalReport());
    expect(result.ok && result.upgradedFrom).toBeUndefined();
  });

  it('vérifie la version avant le schéma (message utile plutôt qu’avalanche d’erreurs)', () => {
    const result = validateReport({ schemaVersion: '3.0.0', scannerVersion: '0.1.0' });
    expect(!result.ok && result.code).toBe('INCOMPATIBLE_MAJOR');
    expect(!result.ok && result.issues).toHaveLength(0);
  });
});

describe('validateReport — conformité au schéma', () => {
  it('refuse un rapport auquel il manque une section obligatoire', () => {
    const { capabilities: _omitted, ...rest } = minimalReport();
    const result = validateReport(rest);
    expect(!result.ok && result.code).toBe('SCHEMA_VIOLATION');
  });

  it('indique le chemin JSON exact du champ fautif', () => {
    const report = minimalReport();
    const broken = { ...report, capabilities: { ...report.capabilities, platform: 'solaris' } };
    const result = validateReport(broken);
    expect(!result.ok && result.issues.map((i) => i.path)).toContain('$.capabilities.platform');
  });

  it('refuse une valeur hors bornes physiques', () => {
    const report = fullReport();
    const result = validateReport({
      ...report,
      sensors: { temperatures: [{ label: 'Tctl', celsius: 5000 }], fans: [] },
    });
    expect(!result.ok && result.code).toBe('SCHEMA_VIOLATION');
  });

  /*
   * Rétrocompatibilité de la section thermique (§20 de la feuille de route).
   *
   * Les machines déjà déployées tournent avec des scanners plus anciens et
   * continueront de le faire longtemps. Un rapport qui ne porte ni catégorie, ni
   * source, ni métadonnées de collecte doit passer l'ingestion exactement comme
   * avant — sinon la montée de version arrête d'un coup le parc entier.
   */
  it('accepte un rapport thermique au format antérieur', () => {
    const report = fullReport();
    const result = validateReport({
      ...report,
      sensors: {
        temperatures: [{ label: 'Tctl', celsius: 42.5, criticalCelsius: 95 }],
        fans: [],
        voltages: [],
        powers: [],
      },
    });
    expect(result.ok).toBe(true);
  });

  it('accepte un rapport sans section capteurs du tout', () => {
    const { sensors: _sensors, ...withoutSensors } = fullReport();
    expect(validateReport(withoutSensors).ok).toBe(true);
  });

  it('refuse une lecture aberrante déguisée en température', () => {
    // `-127 °C` est la réponse d'une sonde 1-Wire absente. Sa place est dans
    // `discardedReadings`, jamais dans la liste des températures.
    const report = fullReport();
    const result = validateReport({
      ...report,
      sensors: { temperatures: [{ label: 'AUXTIN2', celsius: -127 }], fans: [] },
    });
    expect(!result.ok && result.code).toBe('SCHEMA_VIOLATION');
  });

  it('refuse une famille de composant inventée', () => {
    const report = fullReport();
    const result = validateReport({
      ...report,
      sensors: {
        temperatures: [{ label: 'Tctl', celsius: 42, category: 'REFROIDISSEUR' }],
        fans: [],
      },
    });
    expect(!result.ok && result.code).toBe('SCHEMA_VIOLATION');
  });

  // Un audit Ubuntu réel, le 2026-08-06 : l'horloge de la machine virtuelle a
  // sauté en cours de scan et la durée mesurée valait environ 285 000 ans. Le
  // champ étant alors non borné, le refus citait le plus grand entier
  // représentable — un message qui n'apprenait rien à l'exploitant dont le
  // rapport venait d'être rejeté en entier.
  it('refuse une durée d’audit qui ne mesure plus un audit', () => {
    const report = minimalReport();
    const result = validateReport({
      ...report,
      report: { ...report.report, durationMs: 1_786_017_462_123_456 },
    });
    expect(!result.ok && result.code).toBe('SCHEMA_VIOLATION');
    expect(!result.ok && result.issues.map((i) => i.path)).toContain('$.report.durationMs');
    expect(!result.ok && result.issues.map((i) => i.message).join(' ')).toContain('31536000000');
  });

  it('accepte un rapport dont la durée d’audit est absente', () => {
    const report = minimalReport();
    const { durationMs: _omitted, ...meta } = report.report;
    expect(validateReport({ ...report, report: meta }).ok).toBe(true);
  });

  it('refuse un marqueur unknown dont la raison n’existe pas', () => {
    const report = minimalReport();
    const result = validateReport({
      ...report,
      system: { ...report.system, model: { unknown: true, reason: 'BECAUSE' } },
    });
    expect(!result.ok && result.code).toBe('SCHEMA_VIOLATION');
  });

  it('retire les champs inconnus au lieu de les stocker', () => {
    const result = validateReport({
      ...minimalReport(),
      champInattendu: 'valeur arbitraire',
    });
    expect(result.ok).toBe(true);
    expect(result.ok && 'champInattendu' in result.report).toBe(false);
  });

  it('borne le nombre d’erreurs rapportées', () => {
    const result = validateReport({ schemaVersion: SCHEMA_VERSION, scannerVersion: '0.1.0' });
    expect(!result.ok && result.issues.length).toBeLessThanOrEqual(50);
  });
});

describe('validateReport — détection de secrets', () => {
  const withSecret = () => {
    const report = minimalReport();
    return {
      ...report,
      notes: ['POSTGRES_PASSWORD=Sup3rS3cretValue'],
    };
  };

  it('refuse un rapport contenant un secret', () => {
    const result = validateReport(withSecret());
    expect(!result.ok && result.code).toBe('SECRET_DETECTED');
  });

  it('ne recopie jamais le secret dans le message d’erreur', () => {
    const result = validateReport(withSecret());
    const serialized = JSON.stringify(result);
    expect(serialized).not.toContain('Sup3rS3cretValue');
  });

  it('indique où le secret se trouve', () => {
    const result = validateReport(withSecret());
    expect(!result.ok && result.issues[0]?.path).toBe('$.notes[0]');
  });

  it('permet de désactiver la détection pour un usage hors ingestion', () => {
    const result = validateReport(withSecret(), { rejectSecrets: false });
    expect(result.ok).toBe(true);
  });

  it('n’émet pas de faux positif sur un rapport de sécurité légitime', () => {
    const result = validateReport(fullReport());
    expect(result.ok).toBe(true);
  });
});

describe('parseReport', () => {
  it('retourne le rapport validé', () => {
    expect(parseReport(minimalReport()).schemaVersion).toBe(SCHEMA_VERSION);
  });

  it('lève une erreur contenant le code et le détail', () => {
    expect(() => parseReport({ schemaVersion: '2.0.0' })).toThrow(/INCOMPATIBLE_MAJOR/);
    expect(() => parseReport({ ...minimalReport(), capabilities: {} })).toThrow(
      /SCHEMA_VIOLATION.*capabilities/s,
    );
  });
});

describe('pollution de prototype', () => {
  /*
   * Un rapport est une donnée **non fiable** : il arrive par une page de dépôt
   * ouverte, et son contenu est écrit par une machine qu'on ne contrôle pas.
   *
   * Zod reconstruit son résultat champ par champ à partir du schéma, ce qui
   * neutralise `__proto__` et `constructor` : ils n'y survivent pas, faute
   * d'être déclarés. C'était vrai avant ce test — mais rien ne le démontrait,
   * et une bascule vers un validateur qui recopie l'entrée (`passthrough`, un
   * `structuredClone` bien intentionné) la casserait sans bruit.
   */
  const POLLUANTS = ['__proto__', 'constructor', 'prototype'] as const;

  it('ne laisse pas un rapport modifier Object.prototype', () => {
    const empoisonne = JSON.parse(
      JSON.stringify({ ...minimalReport(), __proto__: { pollue: 'oui' } }),
    ) as Record<string, unknown>;

    const result = validateReport(empoisonne);

    // Le rapport passe ou non — peu importe ici. Ce qui compte est qu'aucun
    // objet de ce processus n'ait gagné une propriété au passage.
    expect(({} as Record<string, unknown>).pollue).toBeUndefined();
    expect(Object.prototype).not.toHaveProperty('pollue');
    if (result.ok) {
      expect(result.report).not.toHaveProperty('pollue');
    }
  });

  it('n’emporte aucune clé dangereuse dans le rapport validé', () => {
    // `JSON.parse` conserve `__proto__` comme clé propre — c'est précisément ce
    // qui rend l'entrée dangereuse pour un code qui la recopierait.
    const brut = `{"schemaVersion":"${SCHEMA_VERSION}","__proto__":{"x":1},"constructor":{"y":2}}`;
    const entree = { ...minimalReport(), ...(JSON.parse(brut) as object) };

    const result = validateReport(entree);
    if (!result.ok) return; // Un refus est une réponse acceptable : rien n'est recopié.

    const serialise = JSON.stringify(result.report);
    for (const cle of POLLUANTS) {
      expect(serialise, `« ${cle} » ne doit pas survivre à la validation`).not.toContain(
        `"${cle}"`,
      );
    }
  });

  it('ne laisse pas une section imbriquée polluer le prototype', () => {
    // La surface n'est pas la seule voie : une section profonde recopiée telle
    // quelle ferait le même dégât.
    const entree = JSON.parse(
      JSON.stringify({
        ...minimalReport(),
        system: { ...minimalReport().system, __proto__: { profond: true } },
      }),
    ) as Record<string, unknown>;

    validateReport(entree);
    expect(({} as Record<string, unknown>).profond).toBeUndefined();
  });
});
