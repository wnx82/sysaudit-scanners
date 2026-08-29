// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';
import { annotationFor, FIELD_ANNOTATIONS, POSTGRES_PROJECTIONS } from './field-annotations.js';
import { fieldCatalog, sectionOf } from './field-catalog.js';

/**
 * Le catalogue de champs est la source de la documentation du format. S'il se
 * trompe, la documentation se trompe **avec l'air d'être générée**, ce qui est
 * la pire des combinaisons : personne ne relit une table dérivée.
 *
 * Ces tests le confrontent donc à des champs témoins connus, pas à lui-même.
 */

const catalog = fieldCatalog();
const byPath = new Map(catalog.map((entry) => [entry.path, entry]));

describe('catalogue de champs', () => {
  it('parcourt tout le schéma, y compris à travers les tableaux', () => {
    expect(catalog.length).toBeGreaterThan(400);
    expect(byPath.has('storage.disks[].smart.powerOnHours')).toBe(true);
    expect(byPath.has('network.interfaces[].wifi.ssid')).toBe(true);
    expect(byPath.has('virtualization.proxmox.vms[].disks[].sizeBytes')).toBe(true);
  });

  it('ne produit aucun chemin en double', () => {
    expect(byPath.size).toBe(catalog.length);
  });

  it('distingue obligatoire, obligatoire-si-présent et facultatif', () => {
    // `schemaVersion` est à la racine et sans parent facultatif.
    expect(byPath.get('schemaVersion')).toMatchObject({ optional: false, underOptional: false });
    // `storage` est facultatif : ses feuilles ne sont dues que s'il est là.
    expect(byPath.get('storage.disks[].device')).toMatchObject({
      optional: false,
      underOptional: true,
    });
    expect(byPath.get('storage.disks[].smart.unsafeShutdowns')?.optional).toBe(true);
    // `rotationRpm` illustre la distinction que le schéma tient : il est **dû**
    // dès qu'un disque est décrit, mais peut valoir « non collecté ». Absence
    // du champ et absence de la mesure ne sont pas la même chose.
    expect(byPath.get('storage.disks[].rotationRpm')).toMatchObject({
      optional: false,
      maybeUnknown: true,
    });
  });

  it('reconnaît les champs qui acceptent le marqueur « non collecté »', () => {
    expect(byPath.get('storage.disks[].smart.powerOnHours')?.maybeUnknown).toBe(true);
    // Le marqueur ne doit pas apparaître comme une variante du type.
    expect(byPath.get('storage.disks[].smart.powerOnHours')?.type).not.toContain('unknown');
    // Une version de schéma est toujours connue : elle n'a pas de marqueur.
    expect(byPath.get('schemaVersion')?.maybeUnknown).toBe(false);
  });

  it('rend les unités des primitives partagées', () => {
    expect(byPath.get('storage.disks[].sizeBytes')?.unit).toBe('octets');
    expect(byPath.get('sensors.temperatures[].celsius')?.unit).toBe('°C');
    expect(byPath.get('cpus[].baseFrequencyMhz')?.unit).toBe('MHz');
    expect(byPath.get('storage.disks[].partitions[].usagePercent')?.unit).toBe('%');
    expect(byPath.get('system.uptimeSeconds')?.unit).toBe('s');
    // Un identifiant n'a pas d'unité, et ne doit pas s'en voir attribuer une.
    expect(byPath.get('system.uuid')?.unit).toBeNull();
  });

  it('n’affiche pas la borne technique des entiers JavaScript', () => {
    // `z.number().int()` pose MAX_SAFE_INTEGER : ce n'est pas une règle du
    // format, et l'afficher la ferait lire comme telle.
    for (const entry of catalog) {
      expect(entry.type).not.toContain(String(Number.MAX_SAFE_INTEGER));
    }
  });

  it('énumère les valeurs admises', () => {
    expect(byPath.get('report.scannerKind')?.values).toContain('proxmox');
    expect(byPath.get('storage.disks[].kind')?.values).toContain('NVME');
  });

  it('groupe par section de premier niveau', () => {
    expect(sectionOf('storage.disks[].smart.status')).toBe('storage');
    expect(sectionOf('cpus[].model')).toBe('cpus');
  });
});

describe('annotations de champs', () => {
  it('couvre chaque champ du schéma', () => {
    const orphans = catalog.filter((entry) => annotationFor(entry.path) === null);
    // Une couverture partielle publierait une documentation de format à trous.
    expect(orphans.map((entry) => entry.path)).toEqual([]);
  });

  it('ne décrit aucun chemin disparu', () => {
    const dangling = FIELD_ANNOTATIONS.filter(
      (annotation) => !catalog.some((entry) => annotationFor(entry.path) === annotation),
    );
    // C'est ce qui empêche la table de survivre à une refonte du schéma en
    // documentant des champs qui n'existent plus.
    expect(dangling.map((annotation) => annotation.prefix)).toEqual([]);
  });

  it('retient le préfixe le plus long, jamais le premier trouvé', () => {
    expect(annotationFor('system.hostname')?.prefix).toBe('system.hostname');
    expect(annotationFor('system.model')?.prefix).toBe('system');
    expect(annotationFor('storage.disks[].smart.wearPercent')?.prefix).toBe(
      'storage.disks[].smart',
    );
  });

  it('classe en « réservé au demandeur » ce qui identifie une machine', () => {
    for (const path of [
      'system.hostname',
      'system.uuid',
      'system.serialNumber',
      'motherboard.serialNumber',
      'storage.disks[].serialNumber',
      'memory.modules[].serialNumber',
      'network.publicIp',
      'network.interfaces[].mac',
      'virtualization.proxmox.node.name',
    ]) {
      expect(annotationFor(path)?.privacy, path).toBe('restricted');
    }
  });

  it('laisse public tout fait technique qui n’identifie personne', () => {
    for (const path of [
      'cpus[].model',
      'memory.installedBytes',
      'sensors.temperatures[].celsius',
    ]) {
      expect(annotationFor(path)?.privacy ?? 'public', path).toBe('public');
    }
  });

  it('ne projette en colonne que des chemins réels', () => {
    for (const path of Object.keys(POSTGRES_PROJECTIONS)) {
      expect(byPath.has(path), path).toBe(true);
    }
  });
});

/**
 * L'indétectable et l'omission ne se lisent plus pareil.
 *
 * `collector.windows === null` disait deux choses très différentes sous une
 * seule forme : « ce scanner ne le collecte pas encore » et « ce système ne
 * l'expose pas, et ne l'exposera pas ». La première est une dette, la seconde
 * un fait — et les confondre fait ouvrir des tâches pour combler ce qui n'a pas
 * de fond.
 */
describe('champs non détectables par conception', () => {
  it('n’annonce une impossibilité que là où il n’y a pas de collecteur', () => {
    // Une raison posée sur un champ que le scanner collecte bel et bien serait
    // pire qu'aucune raison : elle contredirait le collecteur d'à côté.
    for (const annotation of FIELD_ANNOTATIONS) {
      if (annotation.undetectable?.linux !== undefined) {
        expect(annotation.collector.linux, annotation.prefix).toBeNull();
      }
      if (annotation.undetectable?.windows !== undefined) {
        expect(annotation.collector.windows, annotation.prefix).toBeNull();
      }
    }
  });

  it('donne une raison de plateforme, jamais un délai', () => {
    /*
     * « Pas encore fait » n'a rien à faire ici : cela s'écrit dans une roadmap.
     * Ce champ porte une raison qui tient à la plateforme, et qu'aucune version
     * future ne lèvera.
     */
    const CALENDRIER = /pas encore|à faire|prochainement|bientôt|todo|plus tard/i;
    for (const annotation of FIELD_ANNOTATIONS) {
      for (const raison of [annotation.undetectable?.linux, annotation.undetectable?.windows]) {
        if (raison === undefined) continue;
        expect(raison.trim().length, annotation.prefix).toBeGreaterThan(20);
        expect(CALENDRIER.test(raison), `${annotation.prefix} : « ${raison} »`).toBe(false);
      }
    }
  });

  it('couvre les cas que le dépôt connaît déjà', () => {
    const raisonDe = (prefix: string) =>
      FIELD_ANNOTATIONS.find((annotation) => annotation.prefix === prefix)?.undetectable;

    // CIM n'expose pas la largeur de lien PCIe, et aucune version future ne le
    // fera : la fixture Windows la retire déjà pour cette raison.
    expect(raisonDe('storage.disks[].link')?.windows).toBeDefined();
    // Les SID et les groupes de travail sont des mécanismes Windows.
    expect(raisonDe('system.machineSid')?.linux).toBeDefined();
    expect(raisonDe('system.workgroup')?.linux).toBeDefined();
  });
});
