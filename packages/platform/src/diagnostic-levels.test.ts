// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';
import {
  DEPTH_RANK,
  DIAGNOSTIC_LEVELS,
  DIAGNOSTIC_LEVEL_PROFILES,
  LEGACY_LEVEL_ALIASES,
  LEVEL_PLAN,
  LEVEL_SCANNERS,
  LEVEL_SECTIONS,
  SCANNER_LEVEL_PLANS,
  SCANNER_SECTION_CAPS,
  SECTION_LABELS,
  levelHighlights,
  levelScannerGaps,
  normalizeDiagnosticLevel,
  scannerDepth,
  sectionsAtLevel,
} from './diagnostic-levels.js';

/**
 * Invariants de la matrice des niveaux.
 *
 * Ils formalisent les promesses faites à l'utilisateur : un niveau plus long
 * collecte au moins autant qu'un niveau plus court, un seul niveau charge la
 * machine, et aucun scanner ne prétend faire plus que ce que le niveau prévoit.
 */
describe('matrice des niveaux de diagnostic', () => {
  it('couvre toutes les sections à tous les niveaux', () => {
    for (const level of DIAGNOSTIC_LEVELS) {
      expect(Object.keys(LEVEL_PLAN[level]).sort()).toEqual([...LEVEL_SECTIONS].sort());
    }
  });

  it('nomme chaque section', () => {
    for (const section of LEVEL_SECTIONS) {
      expect(SECTION_LABELS[section], `libellé manquant pour ${section}`).toBeTruthy();
    }
  });

  it('ne collecte jamais moins quand le niveau monte', () => {
    for (let index = 1; index < DIAGNOSTIC_LEVELS.length; index += 1) {
      const previous = DIAGNOSTIC_LEVELS[index - 1] ?? 'quick';
      const level = DIAGNOSTIC_LEVELS[index] ?? 'quick';
      for (const section of LEVEL_SECTIONS) {
        expect(
          DEPTH_RANK[LEVEL_PLAN[level][section]],
          `${level} collecte moins que ${previous} pour ${section}`,
        ).toBeGreaterThanOrEqual(DEPTH_RANK[LEVEL_PLAN[previous][section]]);
      }
    }
  });

  it('réserve le banc d’essai au seul niveau qui annonce charger la machine', () => {
    for (const level of DIAGNOSTIC_LEVELS) {
      const runsBenchmark = LEVEL_PLAN[level].benchmark !== 'skipped';
      expect(runsBenchmark, `${level} : banc d’essai et charge annoncée divergent`).toBe(
        DIAGNOSTIC_LEVEL_PROFILES[level].loadsMachine,
      );
    }
  });

  it('énonce des durées cibles croissantes et cohérentes', () => {
    let previousMax = 0;
    for (const level of DIAGNOSTIC_LEVELS) {
      const { min, max } = DIAGNOSTIC_LEVEL_PROFILES[level].targetDurationSeconds;
      expect(min, `${level} : durée minimale non positive`).toBeGreaterThan(0);
      expect(max, `${level} : borne haute inférieure à la borne basse`).toBeGreaterThan(min);
      expect(min, `${level} : chevauchement avec le niveau précédent`).toBeGreaterThanOrEqual(
        previousMax,
      );
      previousMax = max;
    }
  });

  it('donne un chemin d’accès unique à chaque niveau', () => {
    const aliases = DIAGNOSTIC_LEVELS.map((level) => DIAGNOSTIC_LEVEL_PROFILES[level].urlAlias);
    expect(new Set(aliases).size).toBe(aliases.length);
    const flags = DIAGNOSTIC_LEVELS.map((level) => DIAGNOSTIC_LEVEL_PROFILES[level].cliFlag);
    expect(flags.filter((flag) => flag === null)).toHaveLength(1);
  });

  it('ramène les profils historiques à un niveau existant', () => {
    for (const [alias, level] of Object.entries(LEGACY_LEVEL_ALIASES)) {
      expect(DIAGNOSTIC_LEVELS).toContain(level);
      expect(normalizeDiagnosticLevel(alias)).toBe(level);
    }
    expect(normalizeDiagnosticLevel('full')).toBe('full');
    expect(normalizeDiagnosticLevel('inexistant')).toBeNull();
    expect(normalizeDiagnosticLevel(undefined)).toBeNull();
  });

  it('n’autorise aucun scanner à collecter plus que le niveau ne prévoit', () => {
    for (const scanner of LEVEL_SCANNERS) {
      for (const level of DIAGNOSTIC_LEVELS) {
        for (const section of LEVEL_SECTIONS) {
          expect(
            DEPTH_RANK[scannerDepth(scanner, level, section)],
            `${scanner}/${level} : ${section} dépasse la matrice`,
          ).toBeLessThanOrEqual(DEPTH_RANK[LEVEL_PLAN[level][section]]);
        }
      }
    }
  });

  it('exige un motif écrit pour chaque écart de scanner', () => {
    for (const scanner of LEVEL_SCANNERS) {
      for (const level of DIAGNOSTIC_LEVELS) {
        for (const section of LEVEL_SECTIONS) {
          if (scannerDepth(scanner, level, section) === LEVEL_PLAN[level][section]) continue;
          const cap = SCANNER_SECTION_CAPS[scanner][section];
          expect(cap, `${scanner} : ${section} est en retrait sans motif déclaré`).toBeDefined();
          expect(cap?.reason.length ?? 0).toBeGreaterThan(20);
        }
      }
    }
  });

  it('ne déclare pas de plafond qui ne plafonne rien', () => {
    for (const scanner of LEVEL_SCANNERS) {
      for (const [section, cap] of Object.entries(SCANNER_SECTION_CAPS[scanner])) {
        const binds = DIAGNOSTIC_LEVELS.some(
          (level) =>
            DEPTH_RANK[cap.depth] <
            DEPTH_RANK[LEVEL_PLAN[level][section as (typeof LEVEL_SECTIONS)[number]]],
        );
        expect(binds, `${scanner} : le plafond de ${section} est sans effet`).toBe(true);
      }
    }
  });

  it('liste les sections d’un niveau sans celles qui sont ignorées', () => {
    expect(sectionsAtLevel('quick')).not.toContain('benchmark');
    expect(sectionsAtLevel('stress')).toContain('benchmark');
    // Windows produit désormais un banc d'essai, mais en retrait : des indices
    // WinSAT, pas des débits — d'où « summary » plutôt que « standard ».
    expect(scannerDepth('windows', 'stress', 'benchmark')).toBe('summary');
    expect(scannerDepth('windows', 'full', 'benchmark')).toBe('skipped');
    expect(sectionsAtLevel('quick').length).toBeLessThan(sectionsAtLevel('full').length);
  });

  it('déduit les apports d’un niveau de la matrice, sans texte libre', () => {
    expect(levelHighlights('quick')).toContain('Identité machine');
    expect(levelHighlights('quick').join(' ')).toContain('résumé');
    // `sensors` a rejoint le niveau Rapide le 2026-08-16 : ce n'est donc plus
    // un apport de Normale. `events` l'est, et le reste — sa fenêtre est le
    // journal entier, dont le coût ne se laisse pas borner d'avance.
    expect(levelHighlights('quick').join(' ')).toContain(SECTION_LABELS.sensors);
    expect(levelHighlights('standard').join(' ')).toContain(SECTION_LABELS.events);
    // Le niveau Complète n'ajoute plus de section : les logiciels sont passés à
    // Normale le 2026-08-16. Ce qu'il apporte est une profondeur — la table
    // SMART complète et les sondes thermiques approfondies —, et c'est un
    // engagement plus honnête : il regarde mieux, il ne regarde plus ailleurs.
    expect(levelHighlights('full').join(' ')).toContain(SECTION_LABELS.storage);
    expect(levelHighlights('full').join(' ')).toContain('approfondie');
    expect(levelHighlights('standard').join(' ')).toContain(SECTION_LABELS.software);
    expect(levelHighlights('stress')).toEqual([SECTION_LABELS.benchmark]);
    // Rien n'apparaît deux fois : un niveau ne réannonce pas ce que le
    // précédent collectait déjà à la même profondeur.
    for (const level of DIAGNOSTIC_LEVELS) {
      const highlights = levelHighlights(level);
      expect(new Set(highlights).size).toBe(highlights.length);
    }
  });

  it('Windows tient au moins l’inventaire de base à tous les niveaux', () => {
    for (const level of DIAGNOSTIC_LEVELS) {
      for (const section of ['system', 'os', 'network', 'security'] as const) {
        expect(SCANNER_LEVEL_PLANS.windows[level][section]).not.toBe('skipped');
      }
    }
  });
});

/**
 * Charge, tests actifs et risques.
 *
 * Ces trois listes disent la même chose de trois façons, et c'est précisément
 * pourquoi elles peuvent diverger : on ajoute un test actif à un niveau sans
 * relever sa charge, ou l'inverse. Un lecteur croirait alors qu'un audit
 * discret ne l'est pas — ou, bien pire, qu'un audit qui charge la machine l'est.
 */
describe('charge annoncée', () => {
  it('ne déclare une charge soutenue que sur un niveau qui charge la machine', () => {
    for (const level of DIAGNOSTIC_LEVELS) {
      const profile = DIAGNOSTIC_LEVEL_PROFILES[level];
      const sustained = Object.values(profile.load).some((load) => load === 'sustained');
      expect(sustained, `${level} : charge et loadsMachine divergent`).toBe(profile.loadsMachine);
    }
  });

  it('ne déclare de test actif que sur un niveau qui charge la machine', () => {
    for (const level of DIAGNOSTIC_LEVELS) {
      const profile = DIAGNOSTIC_LEVEL_PROFILES[level];
      expect(profile.activeTests.length > 0, `${level} : tests actifs sans charge déclarée`).toBe(
        profile.loadsMachine,
      );
    }
  });

  it('donne une charge à chacune des quatre ressources', () => {
    // Une ressource oubliée se lirait comme « non concernée », ce qui est une
    // affirmation, pas une absence.
    for (const level of DIAGNOSTIC_LEVELS) {
      const load = DIAGNOSTIC_LEVEL_PROFILES[level].load;
      expect(Object.keys(load).sort()).toEqual(['cpu', 'disk', 'gpu', 'memory']);
    }
  });

  it('dit au moins un risque par niveau, y compris pour dire qu’il n’y en a pas', () => {
    // Une liste vide se lirait comme « pas encore documenté ». Le niveau Rapide
    // dit donc explicitement qu'il ne présente aucun risque.
    for (const level of DIAGNOSTIC_LEVELS) {
      expect(DIAGNOSTIC_LEVEL_PROFILES[level].risks.length, level).toBeGreaterThan(0);
    }
  });

  it('ne charge la machine qu’au niveau le plus profond', () => {
    const charging = DIAGNOSTIC_LEVELS.filter(
      (level) => DIAGNOSTIC_LEVEL_PROFILES[level].loadsMachine,
    );
    expect(charging).toEqual([DIAGNOSTIC_LEVELS.at(-1)]);
  });
});

/**
 * Effet sur la machine auditée.
 *
 * L'interface a longtemps affiché « Lecture seule » sur tout niveau qui ne
 * déclarait pas charger la machine. Deux niveaux sur les trois concernés
 * pouvaient installer un paquet, et le quatrième écrit un fichier temporaire :
 * la mention était donc fausse là où elle comptait le plus, sur la carte que
 * lit un administrateur avant de lancer l'audit sur un serveur.
 *
 * Ces tests interdisent le retour du défaut : une étiquette ne peut plus
 * prétendre à la lecture seule sans que le reste du profil le confirme.
 */
describe('effet sur la machine', () => {
  it('ne prétend à la lecture seule sans réserve que si rien ne touche la machine', () => {
    /*
     * Trois cas, et un seul autorise l'étiquette nue :
     *
     *   rien du tout            → « Lecture seule », sans réserve ;
     *   installation possible   → une réserve est obligatoire (« par défaut ») ;
     *   écriture déclarée       → l'étiquette ne parle plus de lecture seule.
     *
     * C'est la nuance qui manquait : l'ancienne étiquette était nue sur un
     * niveau qui pouvait installer un paquet.
     */
    for (const level of DIAGNOSTIC_LEVELS) {
      const { systemImpact } = DIAGNOSTIC_LEVEL_PROFILES[level];
      const badge = systemImpact.badge;
      const unqualified = /^lecture seule$/i.test(badge.trim());
      const mentions = /lecture seule/i.test(badge);

      if (systemImpact.writes.length > 0) {
        expect(mentions, `${level} : « ${badge} » nie une écriture déclarée`).toBe(false);
        continue;
      }
      if (systemImpact.mayInstallTools) {
        expect(mentions, `${level} : « ${badge} » devrait rester une lecture seule réservée`).toBe(
          true,
        );
        expect(unqualified, `${level} : « ${badge} » ne réserve pas l’installation d’outils`).toBe(
          false,
        );
        continue;
      }
      expect(
        unqualified,
        `${level} : « ${badge} » devrait être la lecture seule sans réserve`,
      ).toBe(true);
    }
  });

  it('n’affirme « aucune écriture » sur aucun niveau qui écrit', () => {
    for (const level of DIAGNOSTIC_LEVELS) {
      const { systemImpact } = DIAGNOSTIC_LEVEL_PROFILES[level];
      if (systemImpact.writes.length === 0) continue;
      expect(systemImpact.statement, `${level} : la phrase nie une écriture déclarée`).not.toMatch(
        /aucune écriture|rien n’est écrit/i,
      );
    }
  });

  it('n’écrit qu’au niveau qui charge la machine', () => {
    // L'écriture du produit est celle du banc d'essai, et le banc d'essai est
    // le niveau Poussée. Toute autre écriture serait une nouveauté à décider,
    // pas un détail d'implémentation.
    for (const level of DIAGNOSTIC_LEVELS) {
      const profile = DIAGNOSTIC_LEVEL_PROFILES[level];
      expect(profile.systemImpact.writes.length > 0, `${level} : écrit sans charger`).toBe(
        profile.loadsMachine,
      );
    }
  });

  it('réserve l’installation d’outils aux niveaux à privilèges requis', () => {
    for (const level of DIAGNOSTIC_LEVELS) {
      const profile = DIAGNOSTIC_LEVEL_PROFILES[level];
      if (!profile.systemImpact.mayInstallTools) continue;
      expect(profile.privileges, `${level} : installe sans exiger les privilèges`).toBe('required');
    }
  });

  it('dit ce que chaque niveau fait subir à la machine, en une phrase', () => {
    for (const level of DIAGNOSTIC_LEVELS) {
      const { statement } = DIAGNOSTIC_LEVEL_PROFILES[level].systemImpact;
      expect(statement.length, level).toBeGreaterThan(40);
    }
  });
});

describe('écarts entre un niveau et un scanner', () => {
  it('n’en trouve aucun pour Linux, qui n’a aucun plafond', () => {
    for (const level of DIAGNOSTIC_LEVELS) {
      expect(levelScannerGaps(level, 'linux'), level).toEqual([]);
    }
  });

  it('signale les périphériques et les pilotes que Windows collecte moins loin', () => {
    // Le défaut d'origine : `/diagnostics` promettait ces deux sections au
    // niveau Complète, que le scanner Windows ne collectait à aucun niveau.
    // Elles le sont depuis la v0.113.0, mais moins profondément que sous Linux,
    // et l'écart doit continuer d'apparaître : promettre la profondeur Linux
    // sous Windows serait le même mensonge, en plus discret.
    const sections = levelScannerGaps('full', 'windows').map((gap) => gap.section);
    expect(sections).toContain('devices');
    expect(sections).toContain('drivers');
  });

  it('distingue une section absente d’une section amputée', () => {
    const gaps = levelScannerGaps('full', 'windows');
    // Les périphériques sont désormais collectés, en résumé : c'est un écart de
    // profondeur, plus une absence.
    expect(gaps.find((gap) => gap.section === 'devices')?.absent).toBe(false);
    // Le réseau est bien collecté sous Windows, mais moins profondément.
    expect(gaps.find((gap) => gap.section === 'network')?.absent).toBe(false);
  });

  it('ne laisse plus aucune section entièrement absente sous Windows', () => {
    // Étape franchie avec le collecteur PnP : toutes les sections qu'un niveau
    // annonce sont désormais collectées par le scanner Windows, à une
    // profondeur ou à une autre. Ce qui subsiste sont des écarts de
    // profondeur — tous motivés dans `SCANNER_SECTION_CAPS`.
    //
    // Le test se lira comme une régression le jour où une section repassera à
    // `skipped`, ce qui est exactement l'alerte voulue.
    for (const level of DIAGNOSTIC_LEVELS) {
      const absent = levelScannerGaps(level, 'windows').filter((gap) => gap.absent);
      expect(
        absent.map((gap) => gap.section),
        level,
      ).toEqual([]);
    }
  });

  it('porte le motif écrit dans le plafond, sans le réécrire', () => {
    const gap = levelScannerGaps('full', 'windows').find((entry) => entry.section === 'security');
    expect(gap?.reason).toBe(SCANNER_SECTION_CAPS.windows.security?.reason);
  });

  it('ne signale rien au niveau Rapide, qui ne promet rien que Windows n’ait', () => {
    expect(levelScannerGaps('quick', 'windows')).toEqual([]);
  });

  it('ne promet plus, pour un scanner donné, que ce que ce scanner collecte', () => {
    // La correction de fond : `levelHighlights` lisait la matrice sans les
    // plafonds. Aucune section qu'un scanner saute ne doit apparaître dans ce
    // qu'on annonce pour lui.
    //
    // La règle est vérifiée sur **toutes** les sections plutôt que sur deux
    // libellés nommés : la version d'avant citait « Périphériques PCI/USB » et
    // « Pilotes », et elle a cessé de rien prouver le jour où le collecteur PnP
    // Windows a été écrit — le test échouait alors sur un progrès.
    for (const scanner of LEVEL_SCANNERS) {
      for (const level of DIAGNOSTIC_LEVELS) {
        const promised = levelHighlights(level, scanner);
        const skipped = LEVEL_SECTIONS.filter(
          (section) => SCANNER_LEVEL_PLANS[scanner][level][section] === 'skipped',
        );

        for (const section of skipped) {
          expect(
            promised.some((item) => item.startsWith(SECTION_LABELS[section])),
            `${scanner} / ${level} / ${section}`,
          ).toBe(false);
        }
      }
    }
  });

  it('garde la promesse commune quand aucun scanner n’est précisé', () => {
    // Le comportement d'avant reste disponible : la page l'affiche toujours, et
    // liste les écarts à côté plutôt que de rabattre tout le monde sur Windows.
    expect(levelHighlights('full').length).toBeGreaterThan(
      levelHighlights('full', 'windows').length,
    );
  });
});
