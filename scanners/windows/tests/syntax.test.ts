import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

/**
 * Contrôles de syntaxe du scanner Windows, **sans PowerShell**.
 *
 * PSScriptAnalyzer et la suite `tests/run.ps1` ne tournent que là où PowerShell
 * est installé — en pratique, la CI Windows. Un développeur sous Linux peut
 * donc casser le scanner et voir `npm run verify` rester vert.
 *
 * C'est exactement ce qui est arrivé : l'extraction du collecteur depuis
 * `apps/api` a emporté par erreur une trentaine de lignes de l'ancien script
 * d'amorçage à la fin de `benchmark.ps1`, dont une accolade non fermée et des
 * interpolations TypeScript. Le fichier était syntaxiquement invalide, et rien
 * ne l'a signalé avant qu'un utilisateur lance un audit.
 *
 * Ces contrôles ne remplacent pas un analyseur PowerShell : ils attrapent la
 * classe de défauts qu'une manipulation de fichiers produit — troncature,
 * déséquilibre, reliquat de gabarit.
 *
 * ## Ce qu'ils n'attrapent pas, et où c'est vérifié
 *
 * Une erreur de **syntaxe** au sens du parseur leur échappe : compter des
 * délimiteurs ne dit rien d'un `-Value [System.Type]::Membre` sans parenthèses,
 * qui est pourtant un fichier entier refusé à l'analyse. Ce défaut a existé
 * dans `events.ps1` pendant plusieurs versions, et il a fallu un vrai Windows
 * pour le voir : le scanner n'y démarrait pas.
 *
 * Le seul contrôle qui tranche est le parseur lui-même, et il vit dans
 * `scripts/lint-powershell.ps1` — donc dans `npm run lint:powershell`, que
 * `npm run ci:local` exige. Il tourne sur un agent Linux avec PowerShell 7 ;
 * ce qui manquait n'était pas l'outil, c'était de l'appeler.
 */

const scannerRoot = new URL('../', import.meta.url);

const FILES = [
  'sysaudit.ps1',
  'lib/core/json.ps1',
  'lib/core/core.ps1',
  'lib/core/transport.ps1',
  'lib/core/legacy.ps1',
  'lib/core/paths.ps1',
  'lib/core/levels.ps1',
  'lib/core/provision.ps1',
  'lib/collectors/system.ps1',
  'lib/collectors/hardware.ps1',
  'lib/collectors/media.ps1',
  'lib/collectors/power.ps1',
  'lib/collectors/storage.ps1',
  'lib/collectors/network.ps1',
  'lib/collectors/security.ps1',
  'lib/collectors/devices.ps1',
  'lib/collectors/software.ps1',
  'lib/collectors/virtualization.ps1',
  'lib/collectors/events.ps1',
  'lib/collectors/benchmark.ps1',
  'lib/collectors/monitoring.ps1',
  'lib/output/console.ps1',
  'lib/output/markdown.ps1',
  'tests/run.ps1',
] as const;

function read(relativePath: string): string {
  return readFileSync(fileURLToPath(new URL(relativePath, scannerRoot)), 'utf8');
}

/**
 * Retire commentaires et chaînes, pour ne compter que les délimiteurs de code.
 *
 * PowerShell échappe par accent grave, double les apostrophes dans une chaîne
 * simple, et connaît les chaînes littérales multi-lignes (`@' '@`, `@" "@`).
 * Sans ce traitement, une accolade dans un message fausserait le comptage.
 */
export function stripLiterals(source: string): string {
  let out = '';
  let index = 0;

  while (index < source.length) {
    const rest = source.slice(index);

    if (rest.startsWith('<#')) {
      const end = source.indexOf('#>', index + 2);
      index = end === -1 ? source.length : end + 2;
      continue;
    }

    if (source[index] === '#') {
      const end = source.indexOf('\n', index);
      index = end === -1 ? source.length : end;
      continue;
    }

    if (rest.startsWith("@'") || rest.startsWith('@"')) {
      const terminator = rest.startsWith("@'") ? "\n'@" : '\n"@';
      const end = source.indexOf(terminator, index + 2);
      index = end === -1 ? source.length : end + terminator.length;
      continue;
    }

    const quote = source[index];
    if (quote === "'" || quote === '"') {
      index += 1;
      while (index < source.length) {
        if (source[index] === '`' && quote === '"') {
          index += 2;
          continue;
        }
        if (source[index] === quote) {
          // Une apostrophe doublée reste dans la chaîne.
          if (source[index + 1] === quote) {
            index += 2;
            continue;
          }
          index += 1;
          break;
        }
        index += 1;
      }
      continue;
    }

    out += source[index];
    index += 1;
  }

  return out;
}

function balance(source: string, open: string, close: string): number {
  let depth = 0;
  for (const character of source) {
    if (character === open) depth += 1;
    else if (character === close) depth -= 1;
  }
  return depth;
}

describe('syntaxe du scanner Windows', () => {
  it.each(FILES)('%s : accolades, parenthèses et crochets équilibrés', (file) => {
    const code = stripLiterals(read(file));

    expect(balance(code, '{', '}'), 'accolades').toBe(0);
    expect(balance(code, '(', ')'), 'parenthèses').toBe(0);
    expect(balance(code, '[', ']'), 'crochets').toBe(0);
  });

  it.each(FILES)('%s : aucun reliquat d’interpolation TypeScript', (file) => {
    // `${…}` n'a aucun sens en PowerShell hors nom de variable délimité ; sa
    // présence signe un gabarit TypeScript recopié tel quel.
    const source = read(file);
    const leftovers = [...source.matchAll(/\$\{[^}]*\}/g)].map((match) => match[0]);

    expect(leftovers).toEqual([]);
  });

  it.each(FILES)('%s : se termine par une ligne complète', (file) => {
    const source = read(file);
    expect(source.endsWith('\n')).toBe(true);
  });

  it('définit toutes les fonctions que l’orchestrateur appelle', () => {
    // Garde-fou de la couture entre `sysaudit.ps1` et ses collecteurs : une
    // fonction perdue au découpage ne se verrait qu'à l'exécution.
    const definitions = new Set<string>();
    for (const file of FILES) {
      for (const match of read(file).matchAll(/^function\s+([A-Za-z]+-[A-Za-z]+)/gm)) {
        if (match[1] !== undefined) definitions.add(match[1]);
      }
    }

    const orchestrator = read('sysaudit.ps1');
    const called = new Set<string>();
    for (const match of orchestrator.matchAll(/-Body\s*\{\s*([A-Za-z]+-[A-Za-z]+)/g)) {
      if (match[1] !== undefined) called.add(match[1]);
    }
    for (const match of orchestrator.matchAll(/\b(Get-(?:System|Os|Report)[A-Za-z]*)\b/g)) {
      if (match[1] !== undefined) called.add(match[1]);
    }

    expect(called.size).toBeGreaterThan(4);
    for (const name of called) {
      expect(definitions.has(name), `${name} n’est définie nulle part`).toBe(true);
    }
  });

  it('ne redéclare aucun paramètre commun de PowerShell', () => {
    // `[CmdletBinding()]` fournit déjà `-Verbose`, `-Debug`, `-ErrorAction` et
    // les autres. En redéclarer un fait échouer la liaison des paramètres au
    // lancement — un défaut invisible à la lecture, et impossible à voir sans
    // interpréteur.
    const RESERVED = [
      'Verbose',
      'Debug',
      'ErrorAction',
      'ErrorVariable',
      'WarningAction',
      'WarningVariable',
      'InformationAction',
      'InformationVariable',
      'OutVariable',
      'OutBuffer',
      'PipelineVariable',
      'WhatIf',
      'Confirm',
    ];

    for (const file of FILES) {
      const source = read(file);
      if (!/\[CmdletBinding\(/.test(source)) continue;

      const paramBlock = /\[CmdletBinding\([^)]*\)\]\s*param\s*\(([\s\S]*?)\n\)/.exec(source);
      if (paramBlock === null) continue;

      for (const reserved of RESERVED) {
        expect(
          new RegExp(`\\$${reserved}\\b`).test(paramBlock[1] ?? ''),
          `${file} redéclare le paramètre commun -${reserved}`,
        ).toBe(false);
      }
    }
  });

  it('n’oublie aucun fichier du manifeste', () => {
    // Un fichier ajouté au scanner sans l'être ici échapperait à ces contrôles.
    const manifest = read('MANIFEST')
      .split('\n')
      .map((line) => line.trim())
      .filter((line) => line.endsWith('.ps1'));

    for (const path of manifest) {
      expect(FILES, `${path} n’est pas contrôlé`).toContain(path);
    }
  });
});
