#!/usr/bin/env node
/**
 * Régénère la référence des champs du rapport depuis le schéma Zod.
 *
 * Même dispositif que `generate-compatibility.mjs` et
 * `generate-diagnostic-levels.mjs` : la documentation est une projection, et
 * `packages/report-schema/src/field-docs-sync.test.ts` échoue si le fichier a
 * été modifié à la main.
 *
 * Le schéma compte plus de cinq cents feuilles et bouge à chaque version : une
 * table écrite à la main serait fausse au premier `feat(schema)`, et une
 * documentation de format qui ment est pire que pas de documentation.
 *
 * Prérequis : le package doit être compilé (`npm run build:packages`).
 *
 *   node scripts/generate-schema-fields.mjs           écrit le fichier
 *   node scripts/generate-schema-fields.mjs --check   signale une dérive
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { renderFieldReference, renderFieldSummary } from '@sysaudit/report-schema';
import { replaceBlock } from './generate-compatibility.mjs';

const rootDir = resolve(fileURLToPath(new URL('..', import.meta.url)));
const FILE = 'docs/format-rapport/REPORT_SCHEMA_FIELDS.md';

const BLOCKS = [
  { marker: 'fields:summary', content: () => renderFieldSummary() },
  { marker: 'fields:reference', content: () => renderFieldReference() },
];

function main() {
  const check = process.argv.includes('--check');
  const path = resolve(rootDir, FILE);

  const before = readFileSync(path, 'utf8');
  let content = before;
  for (const block of BLOCKS) {
    content = replaceBlock(content, block.marker, block.content());
  }

  /*
   * Comparaison à fins de ligne normalisées.
   *
   * Le générateur écrit ses blocs en LF ; sous Windows, Git extrait le fichier
   * en CRLF faute de `.gitattributes`. La comparaison brute rendait donc
   * « dérive » sur un dépôt parfaitement à jour — mesuré le 2026-08-28 : 1 394
   * octets d'écart, et un contenu identique caractère pour caractère une fois
   * les fins de ligne ramenées à LF.
   *
   * C'est le même défaut que celui corrigé le 2026-08-27 dans trois contrats de
   * scanner, et la même règle : un contrôle dont le verdict dépend de la façon
   * dont le dépôt a été extrait ne contrôle rien. Régénérer sur cette foi-là
   * aurait réécrit 232 Ko sans qu'un seul champ ait bougé.
   */
  const memeContenu = (a, b) => a.replaceAll('\r\n', '\n') === b.replaceAll('\r\n', '\n');

  if (memeContenu(content, before)) {
    if (!check) console.log('Référence des champs déjà à jour.');
    return;
  }

  if (check) {
    console.error(`Dérive détectée : ${path}`);
    console.error('Lancez `npm run docs:schema-fields` puis `npm run format`.');
    process.exit(1);
  }

  writeFileSync(path, content);
  console.log(`Écrit : ${path}`);
}

main();
