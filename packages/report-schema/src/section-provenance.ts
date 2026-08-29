// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { collected, type Provenance, type SourceType } from '@sysaudit/shared';
import type { Report } from './report.js';

/**
 * Le pont entre les deux provenances du produit.
 *
 * ## Deux mécanismes qui ne se connaissaient pas
 *
 * `collection.provenance` du rapport dit **par quoi une section a été lue** :
 * la commande, la méthode, l'horodatage, la précision. C'est le scanner qui
 * l'écrit, sur la machine auditée, pour les chemins où l'origine change la
 * lecture — un compteur SMART lu par `smartctl` et un compteur déduit d'une API
 * système n'ont ni la même précision ni la même autorité.
 *
 * `Sourced<T>` de `@sysaudit/shared` dit **d'où vient une valeur** : mesurée,
 * retrouvée au catalogue, ou saisie à la main. C'est le rendu qui l'écrit, sur
 * le serveur, au moment d'enrichir.
 *
 * Les deux répondent à la même question du lecteur — « d'où sort ce chiffre ? »
 * — dans deux vocabulaires différents, et sans se croiser. Un rendu qui voulait
 * afficher l'origine complète d'une valeur devait donc lire deux structures et
 * savoir les rapprocher lui-même.
 *
 * ## Ce que ce module fait
 *
 * Il traduit la provenance **de section** dans le vocabulaire de la provenance
 * **de valeur**, et rien d'autre. Une section lue par `smartctl` devient un
 * `Provenance` de statut `collected` et de type `tool` : le rendu n'a plus
 * qu'un seul vocabulaire à connaître.
 *
 * ## Ce qu'il ne fait pas
 *
 * **Il n'invente aucune provenance.** Un chemin absent de la table rend
 * `undefined`, jamais une provenance générique : « le scanner ne documente que
 * les chemins où l'origine change la lecture », et un chemin non documenté
 * n'est pas « lu autrement », il est « non documenté ». C'est la règle que la
 * section « Provenance des données » de la vue web affiche déjà en toutes
 * lettres.
 *
 * **Il ne remplace pas `collection.provenance`.** La table brute reste affichée
 * telle quelle, chemin par chemin : c'est elle qui fait le lien avec le JSON
 * exporté, qui est la source de vérité.
 */

/** La table du rapport, ou un objet vide quand le scanner n'a rien documenté. */
type ProvenanceTable = NonNullable<Report['collection']['provenance']>;

/**
 * Type de source déduit de la **méthode** déclarée par le scanner.
 *
 * L'appariement est volontairement littéral : ce sont les valeurs que les
 * collecteurs écrivent réellement, et non une classification ouverte. Une
 * méthode inconnue rend `os`, qui est le cas de très loin le plus fréquent et
 * le moins engageant des trois — la machine s'est décrite elle-même.
 *
 * Les trois types possibles ici sont **tous des mesures** : cette table
 * n'existe que pour des lectures faites sur la machine. Un `local_catalog` ne
 * peut pas en sortir, et le type l'interdit.
 */
function sourceTypeOf(source: string, method: string | undefined): 'os' | 'firmware' | 'tool' {
  const text = `${source} ${method ?? ''}`.toLowerCase();

  // Le micrologiciel : ce que la carte mère raconte d'elle-même.
  if (/\b(smbios|dmi|dmidecode|edid|acpi|efi|uefi)\b/.test(text)) return 'firmware';

  // Un utilitaire tiers dont on croit la lecture sans pouvoir la vérifier.
  if (/\b(smartctl|nvme|nvidia-smi|lspci|lsblk|lsusb|glmark2|sysbench|ipmitool)\b/.test(text)) {
    return 'tool';
  }

  return 'os';
}

/**
 * Provenance d'un chemin du rapport, dans le vocabulaire de `Sourced<T>`.
 *
 * Rend `undefined` quand le scanner n'a rien documenté pour ce chemin ni pour
 * aucun de ses ancêtres.
 */
export function sectionProvenance(report: Report, path: string): Provenance | undefined {
  const table: ProvenanceTable = report.collection.provenance ?? {};
  const entry = nearestEntry(table, path);
  if (entry === undefined) return undefined;

  const sourceType: SourceType = sourceTypeOf(entry.value.source, entry.value.method);
  return collected(null, {
    source: entry.value.source,
    sourceType,
    ...(entry.value.collectedAt === undefined ? {} : { retrievedAt: entry.value.collectedAt }),
  }).provenance;
}

/**
 * Mention lisible de l'origine d'une valeur mesurée, ou `undefined`.
 *
 * C'est la forme qu'un rendu affiche au survol : « lu par `smartctl` », « lu au
 * SMBIOS ». Elle nomme **ce qui a été interrogé**, parce que c'est la question
 * qu'un technicien qui conteste une valeur se pose en premier — il veut savoir
 * laquelle des deux lectures il conteste.
 */
export function sectionProvenanceNote(report: Report, path: string): string | undefined {
  const table: ProvenanceTable = report.collection.provenance ?? {};
  const entry = nearestEntry(table, path);
  if (entry === undefined) return undefined;

  const precision = entry.value.precision === undefined ? '' : `, ${entry.value.precision}`;
  // Le chemin réellement documenté est nommé quand il n'est pas celui demandé :
  // sans cela, une provenance héritée de `storage.disks` passerait pour une
  // provenance propre à `storage.disks[0].smart`.
  const inherited = entry.path === normalizePath(path) ? '' : ` (documenté sur ${entry.path})`;
  return `lu par ${entry.value.source}${precision}${inherited}`;
}

/**
 * L'entrée documentée la plus proche : le chemin lui-même, sinon son ancêtre.
 *
 * ## Pourquoi remonter, et jusqu'où
 *
 * Le scanner documente `storage.disks[0].smart` ; le rendu, lui, demande
 * `storage.disks[].smart.temperatureCelsius` — il décrit une forme, pas une
 * occurrence. Exiger l'égalité stricte rendrait la table inutilisable depuis le
 * rendu, qui est pourtant son seul lecteur.
 *
 * La remontée s'arrête au **premier ancêtre documenté**, et la mention dit
 * lequel : une provenance héritée de `storage.disks` est vraie de tous les
 * disques, mais elle ne prétend pas avoir été écrite pour celui-ci.
 */
function nearestEntry(
  table: ProvenanceTable,
  path: string,
): { path: string; value: ProvenanceTable[string] } | undefined {
  let candidate = normalizePath(path);

  while (candidate !== '') {
    const direct = table[candidate];
    if (direct !== undefined) return { path: candidate, value: direct };

    // Le même chemin sans son indice : `storage.disks[0]` → `storage.disks`.
    const unindexed = candidate.replace(/\[\d+\]$/, '');
    if (unindexed !== candidate) {
      const value = table[unindexed];
      if (value !== undefined) return { path: unindexed, value };
      candidate = unindexed;
      continue;
    }

    const cut = candidate.lastIndexOf('.');
    if (cut < 0) return undefined;
    candidate = candidate.slice(0, cut);
  }
  return undefined;
}

/**
 * Ramène la notation du rendu à celle du scanner.
 *
 * Le rendu écrit `storage.disks[].model` pour désigner « le modèle d'un
 * disque » ; le scanner écrit `storage.disks[0]` pour désigner le premier. Les
 * crochets vides deviennent donc l'indice zéro, qui est celui que le scanner
 * documente quand il en documente un.
 *
 * Un chemin composé — `bios.mode|boot.firmwareMode`, que le rendu emploie
 * lorsqu'il lit deux champs pour une même valeur — se ramène au premier : c'est
 * celui qui l'emporte à l'affichage.
 */
function normalizePath(path: string): string {
  const first = path.split('|')[0] ?? '';
  return first.trim().replace(/\[\]/g, '[0]');
}
