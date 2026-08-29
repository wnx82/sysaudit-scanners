// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import {
  COLLECTION_DEPTHS,
  DIAGNOSTIC_LEVELS,
  DIAGNOSTIC_LEVEL_PROFILES,
  LEGACY_LEVEL_ALIASES,
  LEVEL_SECTIONS,
  SCANNER_LEVEL_PLANS,
  type CollectionDepth,
  type DiagnosticLevel,
  type LevelScanner,
  type LevelSection,
} from './diagnostic-levels.js';

/**
 * Contrat entre les scanners et la table des niveaux.
 *
 * Un scanner embarque sa matrice en dur : il doit tourner sur une machine sans
 * Node.js, donc sans lire ce package. Ce test empêche les copies de diverger —
 * c'est-à-dire le cas où le site promettrait une collecte que le scanner ne
 * ferait pas, ou l'inverse.
 *
 * Il lit les tables comme les scanners les lisent : par colonnes, sur la même
 * grille. Un scanner qui changerait de format de table casserait ce test plutôt
 * que de le contourner.
 */
/**
 * Les fins de ligne sont **normalisées à la lecture**.
 *
 * Ce contrat compare des sources de scanner à des expressions régulières
 * écrites en `
`. Sur une copie extraite en CRLF — le défaut de Git sous
 * Windows —, aucune ne correspond, et le test annonce que la table est
 * introuvable alors qu'elle est là. Un contrat qui dépend de la façon dont le
 * dépôt a été extrait ne contrôle plus rien.
 */
const ROOT = fileURLToPath(new URL('../../../', import.meta.url));

const MATRIX_FILES: Readonly<Record<LevelScanner, { path: string; extract: RegExp }>> = {
  linux: {
    path: 'scanners/linux/lib/core/levels.sh',
    extract: /readonly LEVEL_MATRIX='\n([\s\S]*?)'\n/,
  },
  windows: {
    path: 'scanners/windows/lib/core/levels.ps1',
    extract: /\$script:LevelMatrix = @'\r?\n([\s\S]*?)\r?\n'@/,
  },
};

function parseMatrix(scanner: LevelScanner): Record<LevelSection, readonly string[]> {
  const { path, extract } = MATRIX_FILES[scanner];
  const source = readFileSync(`${ROOT}${path}`, 'utf8').replace(/\r\n/g, '\n');
  const block = extract.exec(source)?.[1];
  expect(block, `table des niveaux introuvable dans ${path}`).toBeDefined();

  const rows: Record<string, readonly string[]> = {};
  for (const line of (block ?? '').split('\n')) {
    const cells = line.trim().split(/\s+/).filter(Boolean);
    if (cells.length === 0) continue;
    expect(cells, `ligne mal formée dans ${path} : « ${line} »`).toHaveLength(
      DIAGNOSTIC_LEVELS.length + 1,
    );
    const [section, ...depths] = cells;
    rows[section as string] = depths;
  }
  return rows as Record<LevelSection, readonly string[]>;
}

describe.each(['linux', 'windows'] as const)('contrat scanner %s ↔ niveaux', (scanner) => {
  const rows = parseMatrix(scanner);

  it('déclare exactement les sections de la table', () => {
    expect(Object.keys(rows).sort()).toEqual([...LEVEL_SECTIONS].sort());
  });

  it('n’emploie que des profondeurs connues', () => {
    for (const [section, depths] of Object.entries(rows)) {
      for (const depth of depths) {
        expect(COLLECTION_DEPTHS, `profondeur inconnue pour ${section} : ${depth}`).toContain(
          depth as CollectionDepth,
        );
      }
    }
  });

  it.each(DIAGNOSTIC_LEVELS)('applique le plan du niveau %s', (level: DiagnosticLevel) => {
    const column = DIAGNOSTIC_LEVELS.indexOf(level);
    for (const section of LEVEL_SECTIONS) {
      expect(
        rows[section]?.[column],
        `${scanner} : ${section} au niveau ${level} diverge de la table`,
      ).toBe(SCANNER_LEVEL_PLANS[scanner][level][section]);
    }
  });
});

describe('contrat scanners ↔ niveaux — options et alias', () => {
  it('le scanner Linux accepte l’option de chaque niveau', () => {
    const source = readFileSync(`${ROOT}scanners/linux/sysaudit.sh`, 'utf8').replace(/\r\n/g, '\n');
    for (const level of DIAGNOSTIC_LEVELS) {
      const flag = DIAGNOSTIC_LEVEL_PROFILES[level].cliFlag;
      if (flag === null) continue;
      expect(source, `${flag} n’est pas reconnue par le scanner Linux`).toContain(`${flag})`);
    }
  });

  it('les deux scanners résolvent les alias historiques au même niveau', () => {
    const bash = readFileSync(`${ROOT}scanners/linux/lib/core/levels.sh`, 'utf8').replace(
      /\r\n/g,
      '\n',
    );
    const powershell = readFileSync(`${ROOT}scanners/windows/lib/core/levels.ps1`, 'utf8').replace(
      /\r\n/g,
      '\n',
    );

    for (const [alias, level] of Object.entries(LEGACY_LEVEL_ALIASES)) {
      // Bash : `quick | security) printf 'quick'` — l'alias partage la branche
      // du niveau cible.
      expect(bash, `${alias} n’est pas résolu par le scanner Linux`).toMatch(
        new RegExp(`${alias}\\)[^\\n]*|\\b${alias}\\b[^\\n]*printf '${level}'`),
      );
      expect(powershell, `${alias} n’est pas résolu par le scanner Windows`).toContain(
        `'${alias}' { return '${level}' }`,
      );
    }
  });

  it('le scanner Linux n’installe qu’aux niveaux qui le déclarent', () => {
    /*
     * `provision_decide` est le seul endroit du produit qui autorise une
     * installation, et il filtre par niveau. Le site, lui, annonce la
     * possibilité depuis `systemImpact.mayInstallTools`. Les deux listes
     * doivent être la même : une divergence ferait dire à la page « lecture
     * seule » d'un niveau qui installe, ou l'inverse.
     */
    const source = readFileSync(`${ROOT}scanners/linux/lib/core/provision.sh`, 'utf8').replace(
      /\r\n/g,
      '\n',
    );
    const gate = /case "\$\(current_level\)" in\s*\n\s*([a-z |]+)\)/.exec(source)?.[1];
    expect(gate, 'le filtre de niveau de provision_decide est introuvable').toBeDefined();

    const allowed = (gate ?? '')
      .split('|')
      .map((level) => level.trim())
      .filter(Boolean)
      .sort();
    const declared = DIAGNOSTIC_LEVELS.filter(
      (level) => DIAGNOSTIC_LEVEL_PROFILES[level].systemImpact.mayInstallTools,
    )
      .slice()
      .sort();

    expect(allowed).toEqual(declared);
  });

  it('les deux scanners nomment les niveaux comme la plateforme', () => {
    const bash = readFileSync(`${ROOT}scanners/linux/lib/core/levels.sh`, 'utf8').replace(
      /\r\n/g,
      '\n',
    );
    for (const level of DIAGNOSTIC_LEVELS) {
      expect(bash, `le libellé de ${level} manque au scanner Linux`).toContain(
        `${level}) printf '${DIAGNOSTIC_LEVEL_PROFILES[level].label}'`,
      );
    }
  });
});
