#!/usr/bin/env node
/**
 * Régénère les tableaux de compatibilité de la documentation depuis la source
 * structurée `packages/platform/src/compatibility.ts`.
 *
 * La matrice était auparavant saisie à la main dans deux fichiers, sans moyen
 * de vérifier qu'ils disaient la même chose (dette `D-09`). Ce script rend la
 * documentation dérivée, et `packages/platform/src/docs-sync.test.ts` échoue
 * si un fichier a été modifié à la main.
 *
 * Prérequis : le package doit être compilé (`npm run build:packages`).
 *
 *   node scripts/generate-compatibility.mjs           écrit les fichiers
 *   node scripts/generate-compatibility.mjs --check   signale une dérive
 */
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  CURRENT_CAPABILITY_COLUMNS,
  TARGET_CAPABILITY_COLUMNS,
  renderCompatibilityTable,
  renderLegend,
  renderClientReasons,
  renderClientTable,
  renderPartialCaveats,
} from '@sysaudit/platform';

const rootDir = resolve(fileURLToPath(new URL('..', import.meta.url)));

/** Blocs générés, repérés par des marqueurs HTML dans les fichiers Markdown. */
const BLOCKS = [
  {
    file: 'COMPATIBILITY.md',
    marker: 'compatibility:legend',
    content: () => renderLegend(),
  },
  {
    file: 'COMPATIBILITY.md',
    marker: 'compatibility:current',
    content: () => renderCompatibilityTable(CURRENT_CAPABILITY_COLUMNS),
  },
  {
    file: 'COMPATIBILITY.md',
    marker: 'compatibility:caveats',
    content: () => renderPartialCaveats(CURRENT_CAPABILITY_COLUMNS),
  },
  {
    file: 'COMPATIBILITY.md',
    marker: 'clients:table',
    content: () => renderClientTable(),
  },
  {
    file: 'COMPATIBILITY.md',
    marker: 'clients:reasons',
    content: () => renderClientReasons(),
  },
  {
    file: 'COMPATIBILITY.md',
    marker: 'compatibility:target',
    content: () => renderCompatibilityTable(TARGET_CAPABILITY_COLUMNS),
  },
  {
    file: 'docs/roadmaps/_archive/2026-07-28-sysaudit-platform-expansion/00-MASTER-PLAN.md',
    marker: 'compatibility:current',
    content: () => renderCompatibilityTable(CURRENT_CAPABILITY_COLUMNS),
  },
  {
    file: 'docs/roadmaps/_archive/2026-07-28-sysaudit-platform-expansion/00-MASTER-PLAN.md',
    marker: 'compatibility:target',
    content: () => renderCompatibilityTable(TARGET_CAPABILITY_COLUMNS),
  },
];

/**
 * Remplace le contenu situé entre deux marqueurs.
 *
 * Un marqueur absent est une erreur et non un silence : sans cela, la
 * documentation cesserait d'être régénérée sans que personne ne le remarque.
 */
export function replaceBlock(source, marker, content) {
  const start = `<!-- ${marker}:start -->`;
  const end = `<!-- ${marker}:end -->`;
  const startIndex = source.indexOf(start);
  const endIndex = source.indexOf(end);

  if (startIndex === -1 || endIndex === -1 || endIndex < startIndex) {
    throw new Error(`Marqueurs « ${marker} » introuvables ou mal ordonnés.`);
  }

  return source.slice(0, startIndex + start.length) + `\n\n${content}\n\n` + source.slice(endIndex);
}

function main() {
  const check = process.argv.includes('--check');
  const updated = new Map();

  for (const block of BLOCKS) {
    const path = resolve(rootDir, block.file);
    /*
     * Une cible absente est sautée, pas signalée. Le plan directeur archivé vit
     * dans `docs/roadmaps/`, un dossier non versionné dont il est l'unique
     * exception : il n'existe pas dans la surface publique, où ce générateur
     * tourne aussi. Régénérer les tableaux ne doit pas y échouer sur un fichier
     * dont l'absence est le comportement attendu.
     */
    if (!existsSync(path)) continue;
    const source = updated.get(path) ?? readFileSync(path, 'utf8');
    updated.set(path, replaceBlock(source, block.marker, block.content()));
  }

  let drifted = false;
  const written = [];
  for (const [path, content] of updated) {
    const current = readFileSync(path, 'utf8');
    if (current === content) continue;

    drifted = true;
    if (check) {
      console.error(`Dérive détectée : ${path}`);
    } else {
      writeFileSync(path, content, 'utf8');
      console.log(`Régénéré : ${path}`);
      written.push(path);
    }
  }

  // Prettier repasse sur ce qui vient d'être écrit.
  //
  // Le générateur remplit les colonnes des tableaux à sa façon, Prettier à la
  // sienne — les emoji ne comptent pas pour la même largeur chez les deux. Les
  // données sont identiques, mais `npm run format:check` échouait juste après
  // une régénération. Quiconque suivait la procédure « modifier le `.ts`, puis
  // `npm run docs:compatibility` » livrait donc un dépôt non formaté, et
  // découvrait le problème à la porte suivante.
  if (written.length > 0) {
    const prettier = spawnSync('npx', ['prettier', '--write', ...written], {
      stdio: 'ignore',
      shell: process.platform === 'win32',
    });
    if (prettier.status !== 0) {
      console.warn('Prettier n’a pas pu reformater : lancez `npm run format`.');
    }
  }

  if (check && drifted) {
    console.error('Lancez `npm run docs:compatibility` puis `npm run format`.');
    process.exit(1);
  }
  if (!check && !drifted) console.log('Documentation déjà à jour.');
}

// `replaceBlock` est réutilisé par `generate-diagnostic-levels.mjs` : importer
// ce fichier ne doit donc pas régénérer la matrice de compatibilité au passage.
if (process.argv[1] === fileURLToPath(import.meta.url)) main();
