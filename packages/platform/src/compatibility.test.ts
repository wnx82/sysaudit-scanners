// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';
import {
  CAPABILITY_KEYS,
  COMPATIBILITY_TARGETS,
  CURRENT_CAPABILITY_COLUMNS,
  SECTION_CAPABILITIES,
  SUPPORT_LEVEL_SYMBOLS,
  compatibilityForDistribution,
  isBootstrappable,
  scannerCaveats,
} from './compatibility.js';
import {
  DIAGNOSTIC_LEVELS,
  LEVEL_SECTIONS,
  SCANNER_SECTION_CAPS,
  scannerDepth,
} from './diagnostic-levels.js';
import { renderPartialCaveats } from './markdown.js';
import { distributionById } from './distributions.js';
import { isImplementedScannerProfile } from './families.js';

describe('matrice de compatibilité', () => {
  it('n’a pas deux lignes portant le même identifiant', () => {
    const ids = COMPATIBILITY_TARGETS.map((target) => target.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('renseigne chaque domaine pour chaque cible', () => {
    for (const target of COMPATIBILITY_TARGETS) {
      for (const capability of CAPABILITY_KEYS) {
        expect(
          target.capabilities[capability],
          `${target.id} : domaine « ${capability} » non renseigné`,
        ).toBeDefined();
      }
    }
  });

  it('ne référence que des distributions du catalogue', () => {
    for (const target of COMPATIBILITY_TARGETS) {
      for (const distribution of target.distributions) {
        expect(
          distributionById(distribution),
          `${target.id} : distribution « ${distribution} » hors catalogue`,
        ).toBeDefined();
      }
    }
  });

  /**
   * Le garde-fou central de la matrice : elle ne peut pas annoncer une collecte
   * validée là où aucun scanner n'existe. `ai` est exclue — l'analyse ne dépend
   * que d'un JSON valide, jamais du système audité.
   */
  it('n’annonce aucune collecte sur une cible sans scanner', () => {
    for (const target of COMPATIBILITY_TARGETS) {
      if (isImplementedScannerProfile(target.scannerProfile)) continue;

      for (const capability of CAPABILITY_KEYS) {
        if (capability === 'ai') continue;
        expect(
          target.capabilities[capability].level,
          `${target.id} : « ${capability} » annoncé sans scanner`,
        ).not.toBe('VALIDATED');
        expect(
          target.capabilities[capability].level,
          `${target.id} : « ${capability} » annoncé sans scanner`,
        ).not.toBe('IMPLEMENTED');
      }
    }
  });

  it('n’annonce monitoring et banc d’essai que là où un scanner les porte', () => {
    // Livrés par les étapes 10 et 11 côté Linux, puis portés sur Windows. Ce
    // test a interdit de les annoncer avant leur livraison ; il interdit
    // désormais de les annoncer sur une cible dont le scanner ne les
    // implémente pas — les deux lignes Windows héritées (Legacy, Minimal)
    // n'ayant aucun scanner du tout.
    const carryingProfiles = new Set(['linux', 'proxmox', 'windows']);

    for (const target of COMPATIBILITY_TARGETS) {
      if (carryingProfiles.has(target.scannerProfile)) continue;

      expect(
        target.capabilities.monitoring.level,
        `${target.id} : monitoring annoncé sans scanner qui le porte`,
      ).not.toBe('VALIDATED');
      expect(
        target.capabilities.benchmark.level,
        `${target.id} : banc d’essai annoncé sans scanner qui le porte`,
      ).not.toBe('VALIDATED');
    }
  });

  it('n’annonce sous Windows que ce que le scanner Windows produit', () => {
    // Garde-fou de la dérive constatée : la matrice a déclaré « non implémenté »
    // un banc d'essai et des compteurs SMART que le scanner produisait depuis
    // des mois. Le sens de l'erreur — pessimiste — ne la rend pas inoffensive :
    // elle a fait écrire dans la documentation qu'une colonne était vide.
    //
    // Le contrôle s'appuie sur la matrice des niveaux, qui décide du
    // branchement réel du scanner, plutôt que sur une seconde liste tenue à la
    // main qui finirait par diverger de la même façon.
    for (const target of COMPATIBILITY_TARGETS) {
      if (target.scannerProfile !== 'windows') continue;

      for (const [capability, section] of [
        ['software', 'software'],
        ['storage', 'storage'],
        ['network', 'network'],
        ['security', 'security'],
        ['virtualization', 'virtualization'],
        ['benchmark', 'benchmark'],
      ] as const) {
        const collected = DIAGNOSTIC_LEVELS.some(
          (level) => scannerDepth('windows', level, section) !== 'skipped',
        );
        expect(
          collected,
          `${target.id} : « ${capability} » annoncé mais le scanner ne le collecte à aucun niveau`,
        ).toBe(target.capabilities[capability].level !== 'ABSENT');
      }
    }
  });

  it('n’attribue pas deux niveaux au même symbole', () => {
    const symbols = Object.values(SUPPORT_LEVEL_SYMBOLS);
    expect(new Set(symbols).size).toBe(symbols.length);
  });

  it('retrouve les lignes couvrant une distribution', () => {
    expect(compatibilityForDistribution('almalinux').map((target) => target.id)).toEqual([
      'rocky-alma',
    ]);
    expect(compatibilityForDistribution('windows').map((target) => target.id)).toEqual([
      'windows-modern',
      'windows-server',
      'windows-legacy',
      'windows-minimal',
    ]);
  });

  it('ne déclare amorçable qu’un profil réellement servi par l’API', () => {
    expect(isBootstrappable('linux')).toBe(true);
    expect(isBootstrappable('proxmox')).toBe(true);
    expect(isBootstrappable('windows')).toBe(true);
    expect(isBootstrappable('macos')).toBe(false);
    expect(isBootstrappable('android')).toBe(false);
  });
});

describe('couverture partielle', () => {
  it('couvre toutes les sections dans la table des capacités', () => {
    // Une section ajoutée sans capacité serait plafonnée un jour sans que son
    // motif remonte jamais à la matrice : le manque resterait invisible.
    for (const section of LEVEL_SECTIONS) {
      expect(SECTION_CAPABILITIES[section], section).toBeDefined();
    }
    for (const capabilities of Object.values(SECTION_CAPABILITIES)) {
      for (const capability of capabilities) {
        expect(CAPABILITY_KEYS).toContain(capability);
      }
    }
  });

  it('ne produit aucun motif pour un scanner sans plafond', () => {
    expect(scannerCaveats('linux')).toEqual({});
  });

  it('reprend mot pour mot le motif du plafond, sans le réécrire', () => {
    const caveats = scannerCaveats('windows');
    expect(caveats.security).toBe(SCANNER_SECTION_CAPS.windows.security?.reason);
    expect(caveats.network).toBe(SCANNER_SECTION_CAPS.windows.network?.reason);
  });

  it('joint les motifs de deux sections visant la même capacité', () => {
    // `devices` et `drivers` sont tous deux plafonnés sous « Matériel » : n'en
    // garder qu'un ferait croire l'autre complet. Depuis que le collecteur PnP
    // existe, ce qui manque n'est plus la collecte mais sa profondeur — la
    // largeur des liens PCIe d'un côté, la version publiée de l'autre — et les
    // deux motifs doivent rester lisibles côte à côte.
    const caveats = scannerCaveats('windows');
    expect(caveats.hardware).toContain('PnP');
    expect(caveats.hardware).toContain('pilote');
  });

  it('n’annonce plus la Sécurité de Windows comme complète', () => {
    // Le défaut corrigé le 2026-08-11, et celui qui coûtait le plus cher : un ✅
    // sur une colonne de sécurité se lit comme une bonne nouvelle.
    const windows = COMPATIBILITY_TARGETS.find((target) => target.id === 'windows-modern');
    expect(windows).toBeDefined();
    expect(windows?.capabilities.security.level).toBe('PARTIAL');
    expect(windows?.capabilities.network.level).toBe('PARTIAL');
  });

  it('exige un motif partout où une case est partielle', () => {
    // La garantie centrale de ce niveau : il ne peut pas devenir un fourre-tout,
    // parce qu'on ne peut pas le poser sans nommer ce qui manque.
    for (const target of COMPATIBILITY_TARGETS) {
      for (const key of CAPABILITY_KEYS) {
        const support = target.capabilities[key];
        if (support.level !== 'PARTIAL') continue;
        expect(support.caveat, `${target.id}/${key}`).toBeTruthy();
        expect(support.caveat.length, `${target.id}/${key}`).toBeGreaterThan(20);
      }
    }
  });

  it('ne rabat que ce qui était validé', () => {
    // `IMPLEMENTED` dit déjà « non exécuté sur la cible » : le rabattre
    // brouillerait deux sens distincts. Windows Server garde donc ses 🟡.
    const server = COMPATIBILITY_TARGETS.find((target) => target.id === 'windows-server');
    expect(server?.capabilities.security.level).toBe('IMPLEMENTED');
  });

  it('laisse intactes les capacités qu’aucun plafond n’ampute', () => {
    const windows = COMPATIBILITY_TARGETS.find((target) => target.id === 'windows-modern');
    expect(windows?.capabilities.software.level).toBe('VALIDATED');
    expect(windows?.capabilities.virtualization.level).toBe('VALIDATED');
  });

  it('publie chaque motif dans la documentation générée', () => {
    // Un motif obligatoire mais jamais affiché ne vaudrait rien.
    const rendered = renderPartialCaveats(CURRENT_CAPABILITY_COLUMNS);
    for (const target of COMPATIBILITY_TARGETS) {
      for (const key of CURRENT_CAPABILITY_COLUMNS) {
        const support = target.capabilities[key];
        if (support.level !== 'PARTIAL') continue;
        expect(rendered).toContain(support.caveat);
      }
    }
  });
});
