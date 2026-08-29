// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { read, unknown, type Maybe } from '@sysaudit/shared';
import type { Report } from './report.js';

/**
 * La **capacité mémoire maximale**, lue sans la croire sur parole.
 *
 * ## Le fait qui a rendu ce fichier nécessaire
 *
 * L'audit `QJVJVFA6` déclare 33 157 378 048 octets installés — 32 Gio, ce qui
 * correspond aux deux barrettes relevées — et 134 217 728 octets de capacité
 * maximale, soit 128 **Mio**. La machine porterait donc deux cent cinquante
 * fois plus de mémoire que sa carte mère n'en accepte.
 *
 * La cause est une unité : `Win32_PhysicalMemoryArray.MaxCapacityEx` s'exprime
 * en **kilo-octets**, et le scanner Windows la versait telle quelle. Le facteur
 * manquant vaut exactement 1024, et 128 Mio × 1024 fait 128 Gio — la capacité
 * réelle d'une carte mère AM5 à quatre emplacements. Le scanner est corrigé.
 *
 * ## Pourquoi le correctif de scanner ne suffit pas
 *
 * Il ne vaut que pour les audits **à venir**. Les rapports déjà versés portent
 * leur valeur fausse pour toujours, et le format s'interdit de les réécrire :
 * un audit relu dans deux ans doit montrer ce que la machine a dit.
 *
 * D'où cette lecture, appliquée au rendu. Elle ne corrige rien — corriger
 * demanderait de savoir que l'unité était en cause, ce qui n'est pas déductible
 * du seul rapport — elle **refuse de publier** une valeur qu'un fait du même
 * rapport contredit. Une capacité maximale inférieure à la mémoire déjà
 * installée n'est pas une petite capacité : c'est une mesure fausse, et
 * l'afficher comme vraie apprend au lecteur quelque chose qui n'existe pas.
 *
 * ## Ce qui sert de contradiction
 *
 * La mémoire **installée** telle que le système la rapporte, et à défaut la
 * somme des modules physiques relevés. Les deux diffèrent légèrement — le
 * matériel réserve quelques mébioctets — et c'est sans importance ici : l'écart
 * qu'on cherche se compte en ordres de grandeur.
 */
export function memoryMaxCapacityBytes(report: Report): Maybe<number> | undefined {
  const memory = report.memory;
  if (memory === undefined) return undefined;

  const declaree = memory.maxCapacityBytes;
  const max = read(declaree);
  if (max === undefined) return declaree;

  const plancher = installedFloorBytes(report);
  if (plancher === null || max >= plancher) return declaree;

  return unknown(
    'UNKNOWN',
    `valeur incohérente — ${max} octets déclarés pour ${plancher} octets déjà installés`,
  );
}

/**
 * La capacité maximale est-elle contredite par la machine elle-même ?
 *
 * Distincte de « inconnue » : le champ a été collecté, et c'est précisément ce
 * qui rend son contenu remarquable. L'interface s'en sert pour dire au lecteur
 * que le firmware s'est trompé, plutôt que de laisser croire à une collecte
 * ratée.
 */
export function memoryMaxCapacityIsIncoherent(report: Report): boolean {
  const memory = report.memory;
  if (memory === undefined) return false;

  const max = read(memory.maxCapacityBytes);
  if (max === undefined) return false;

  const plancher = installedFloorBytes(report);
  return plancher !== null && max < plancher;
}

/**
 * Le minimum de mémoire dont on est sûr qu'elle est installée, ou `null`.
 *
 * La valeur rapportée par le système prime : elle est mesurée d'un bloc. La
 * somme des modules ne sert que lorsqu'elle manque — un rapport peut lister ses
 * barrettes sans savoir dire le total.
 */
function installedFloorBytes(report: Report): number | null {
  const memory = report.memory;
  if (memory === undefined) return null;

  const installee = read(memory.installedBytes);
  if (installee !== undefined && installee > 0) return installee;

  const somme = memory.modules.reduce((total, module) => {
    const taille = read(module.sizeBytes);
    return taille !== undefined && taille > 0 ? total + taille : total;
  }, 0);

  return somme > 0 ? somme : null;
}
