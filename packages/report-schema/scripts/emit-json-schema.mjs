#!/usr/bin/env node
/**
 * Écrit le JSON Schema du rapport dans `schema/`.
 *
 * Ce fichier est committé : c'est l'artefact que consomment les scanners Bash
 * et PowerShell pour valider leur sortie sans Node.js. Un test vérifie qu'il
 * reste synchronisé avec la définition Zod.
 */
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildJsonSchema, JSON_SCHEMA_FILENAME } from '../dist/index.js';

const packageRoot = join(dirname(fileURLToPath(import.meta.url)), '..');
const outputDir = join(packageRoot, 'schema');

await mkdir(outputDir, { recursive: true });

const document = `${JSON.stringify(buildJsonSchema(), null, 2)}\n`;

// Le nom versionné permet de conserver les anciens schémas côte à côte ;
// `latest` sert de cible stable aux scanners.
for (const filename of [JSON_SCHEMA_FILENAME, 'sysaudit-report-latest.schema.json']) {
  await writeFile(join(outputDir, filename), document, 'utf8');
  console.log(`écrit : schema/${filename}`);
}
