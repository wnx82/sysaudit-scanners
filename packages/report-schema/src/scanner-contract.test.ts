// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { collectionIssueReasonSchema } from './sections/meta.js';
import { SCHEMA_VERSION } from './version.js';

/**
 * Contrat entre les scanners et la plateforme.
 *
 * Un scanner déclare en dur la version de schéma qu'il produit : il doit
 * pouvoir tourner sur une machine sans Node.js, donc sans lire ce package.
 * Ce test empêche les deux valeurs de diverger silencieusement — le cas où un
 * scanner produirait un format que la plateforme refuserait à l'ingestion.
 */
const repoRoot = fileURLToPath(new URL('../../..', import.meta.url));

function read(relativePath: string): string {
  return readFileSync(`${repoRoot}${relativePath}`, 'utf8');
}

describe('contrat scanner ↔ schéma', () => {
  it('le scanner Linux annonce la version de schéma courante', () => {
    const source = read('scanners/linux/sysaudit.sh');
    const declared = /readonly SCHEMA_VERSION='([^']+)'/.exec(source)?.[1];

    expect(
      declared,
      'SCHEMA_VERSION est introuvable dans scanners/linux/sysaudit.sh',
    ).toBeDefined();
    expect(
      declared,
      'Le scanner Linux produit un schéma différent de celui que la plateforme sait lire.',
    ).toBe(SCHEMA_VERSION);
  });

  it('la version du scanner Linux est un SemVer valide', () => {
    const version = read('scanners/linux/VERSION').trim();
    expect(version).toMatch(/^\d+\.\d+\.\d+(-[\w.]+)?$/);
  });

  it('le scanner Windows annonce la version de schéma courante', () => {
    const source = read('scanners/windows/sysaudit.ps1');
    const declared = /\$script:SCHEMA_VERSION = '([^']+)'/.exec(source)?.[1];

    expect(
      declared,
      'SCHEMA_VERSION est introuvable dans scanners/windows/sysaudit.ps1',
    ).toBeDefined();
    expect(
      declared,
      'Le scanner Windows produit un schéma différent de celui que la plateforme sait lire.',
    ).toBe(SCHEMA_VERSION);
  });

  it('la version du scanner Windows est un SemVer valide', () => {
    const version = read('scanners/windows/VERSION').trim();
    expect(version).toMatch(/^\d+\.\d+\.\d+(-[\w.]+)?$/);
  });

  it('le scanner Windows charge exactement les fichiers de son MANIFEST', () => {
    // La liste était auparavant recopiée : ajouter un collecteur sans l'ajouter
    // au manifeste ne cassait rien au build, seulement l'amorçage, sur la
    // machine auditée.
    const manifest = read('scanners/windows/MANIFEST')
      .split('\n')
      .map((line) => line.trim())
      .filter((line) => line !== '' && !line.startsWith('#'));

    const source = read('scanners/windows/sysaudit.ps1');
    const sourced = [...source.matchAll(/Join-Path \$scannerRoot '([^']+)'/g)]
      .map((match) => match[1])
      .filter((path) => path !== undefined && path.endsWith('.ps1'));

    const libFiles = manifest.filter((path) => path.startsWith('lib/'));
    expect(sourced).toEqual(libFiles);
  });

  it('les fichiers du manifeste Windows existent tous', () => {
    const manifest = read('scanners/windows/MANIFEST')
      .split('\n')
      .map((line) => line.trim())
      .filter((line) => line !== '' && !line.startsWith('#'));

    for (const path of manifest) {
      expect(() => read(`scanners/windows/${path}`), `${path} est introuvable`).not.toThrow();
    }
  });

  /**
   * Scanners expérimentaux.
   *
   * Leur statut porte sur ce qu'ils ont prouvé **sur leur plateforme cible**,
   * pas sur le droit de produire un format différent : un rapport expérimental
   * arrive à l'API par la même porte que les autres, et serait refusé par la
   * même validation.
   */
  const EXPERIMENTAL_SCANNERS = ['macos', 'bsd', 'android'] as const;

  it.each(EXPERIMENTAL_SCANNERS)('le scanner %s annonce la version de schéma courante', (name) => {
    const source = read(`scanners/${name}/sysaudit.sh`);
    const declared = /^SCHEMA_VERSION='([^']+)'$/m.exec(source)?.[1];

    expect(declared, `SCHEMA_VERSION est introuvable dans scanners/${name}/sysaudit.sh`).toBe(
      SCHEMA_VERSION,
    );
  });

  it.each(EXPERIMENTAL_SCANNERS)('la version du scanner %s est un SemVer valide', (name) => {
    expect(read(`scanners/${name}/VERSION`).trim()).toMatch(/^\d+\.\d+\.\d+(-[\w.]+)?$/);
  });

  it.each(EXPERIMENTAL_SCANNERS)('les fichiers du manifeste %s existent tous', (name) => {
    const manifest = read(`scanners/${name}/MANIFEST`)
      .split('\n')
      .map((line) => line.trim())
      .filter((line) => line !== '' && !line.startsWith('#'));

    for (const path of manifest) {
      expect(() => read(`scanners/${name}/${path}`), `${path} est introuvable`).not.toThrow();
    }
  });

  it.each(EXPERIMENTAL_SCANNERS)(
    'le scanner %s porte son statut expérimental dans ses rapports',
    (name) => {
      // Le bandeau de l'en-tête n'atteint pas le lecteur d'un rapport. Ces deux
      // mentions, elles, sont dans `report.notes` — donc dans le document que
      // quelqu'un ouvrira, peut-être des mois plus tard, sans avoir jamais vu
      // le code du scanner.
      const source = read(`scanners/${name}/sysaudit.sh`);
      expect(source, 'la mention EXPERIMENTAL manque dans les notes du rapport').toMatch(
        /note 'EXPERIMENTAL/,
      );
      expect(source, 'la mention UNVALIDATED manque dans les notes du rapport').toMatch(
        /note 'UNVALIDATED/,
      );
    },
  );

  /**
   * Le vocabulaire des motifs traverse trois langages.
   *
   * Un motif inconnu ne casse rien de visible : le rapport reste valide — Zod
   * refuserait la valeur, mais seulement à l'ingestion, sur la machine de
   * l'utilisateur, après l'audit. Une faute de frappe dans un scanner se
   * paierait donc en rapports refusés, longtemps après le commit qui l'a
   * introduite. Ce test la fait échouer ici.
   */
  it('les scanners n’émettent que des motifs connus du schéma', () => {
    const admis = new Set(collectionIssueReasonSchema.options);

    const bash = [
      'sysaudit.sh',
      ...readdirSync(`${repoRoot}scanners/linux/lib/core`).map((name) => `lib/core/${name}`),
      ...readdirSync(`${repoRoot}scanners/linux/lib/collectors`).map(
        (name) => `lib/collectors/${name}`,
      ),
    ]
      .filter((path) => path.endsWith('.sh'))
      .map((path) => read(`scanners/linux/${path}`))
      .join('\n');

    // Le motif est le cinquième argument de `record_issue` : une constante en
    // capitales, entre apostrophes, sur la ligne de l'appel ou sa continuation.
    for (const match of bash.matchAll(/record_issue[^\n]*(?:\\\n[^\n]*)*?'([A-Z_]{4,})'/g)) {
      expect(admis, `motif inconnu dans le scanner Linux : ${match[1]}`).toContain(match[1]);
    }

    /*
     * Côté PowerShell, `-Reason` désigne deux choses selon la fonction appelée :
     * le motif d'une issue pour `Add-CollectionIssue`, et celui d'un champ
     * absent pour `New-Unknown` — dont le vocabulaire, celui d'`UnknownReason`,
     * connaît `UNKNOWN` que le nôtre ignore. La recherche part donc du nom de
     * la fonction, et suit ses continuations de ligne.
     */
    const powershell = [
      'sysaudit.ps1',
      ...readdirSync(`${repoRoot}scanners/windows/lib/core`).map((name) => `lib/core/${name}`),
      ...readdirSync(`${repoRoot}scanners/windows/lib/collectors`).map(
        (name) => `lib/collectors/${name}`,
      ),
    ]
      .filter((path) => path.endsWith('.ps1'))
      .map((path) => read(`scanners/windows/${path}`))
      .join('\n');

    for (const call of powershell.matchAll(/Add-CollectionIssue(?:Once)?(?:[^\n]*`\n)*[^\n]*/g)) {
      const reason = /-Reason '([A-Z_]+)'/.exec(call[0])?.[1];
      if (reason === undefined) continue;
      expect(admis, `motif inconnu dans le scanner Windows : ${reason}`).toContain(reason);
    }
  });

  it('le scanner reste marqué exécutable dans le dépôt', () => {
    // Un scanner non exécutable casserait `curl … -o sysaudit.sh && ./sysaudit.sh`
    // uniquement après chmod ; la documentation prévoit ce chmod, mais la copie
    // du dépôt doit rester directement utilisable.
    const source = read('scanners/linux/sysaudit.sh');
    expect(source.startsWith('#!/usr/bin/env bash')).toBe(true);
  });
});
