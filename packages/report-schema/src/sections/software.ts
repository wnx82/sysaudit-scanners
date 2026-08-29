// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { z } from 'zod';
import { isoDate, maybe, positiveInt, shortText } from '../primitives.js';

export const packageSchema = z.object({
  name: shortText,
  version: maybe(shortText),
  /** Gestionnaire d'origine : `apt`, `dnf`, `pacman`, `msi`, `winget`… */
  source: maybe(shortText),
  installDate: maybe(isoDate).optional(),
  vendor: maybe(shortText).optional(),
});

export const serviceSchema = z.object({
  name: shortText,
  displayName: maybe(shortText).optional(),
  state: maybe(z.enum(['RUNNING', 'STOPPED', 'FAILED', 'UNKNOWN'])),
  startup: maybe(z.enum(['ENABLED', 'DISABLED', 'MANUAL', 'UNKNOWN'])),
});

/**
 * Gestionnaire de paquets présent sur la machine.
 *
 * L'inventaire des gestionnaires est distinct de celui des paquets : savoir que
 * `flatpak` est installé mais ne gère aucune application est une information,
 * et un `packageCount` global masquerait la répartition entre gestionnaires.
 */
export const packageManagerSchema = z.object({
  /** `apt`, `dpkg`, `rpm`, `dnf`, `pacman`, `snap`, `flatpak`, `winget`… */
  name: shortText,
  /** Version du gestionnaire, quand il l'expose. */
  version: maybe(shortText),
  /** Nombre de paquets qu'il gère. Absent plutôt qu'à zéro s'il n'a pas répondu. */
  packageCount: maybe(positiveInt),
});

/**
 * Environnement d'exécution installé (§81).
 *
 * Uniquement des runtimes dont la version est **lue** en exécutant la commande
 * avec son option de version. Rien n'est déduit de la présence d'un fichier ni
 * d'un nom de paquet.
 */
export const runtimeSchema = z.object({
  /** `node`, `python`, `java`, `dotnet`, `go`, `php`… */
  name: shortText,
  version: maybe(shortText),
  /** Chemin de l'exécutable retenu, utile quand plusieurs versions coexistent. */
  path: maybe(shortText),
});

export const softwareSchema = z.object({
  /**
   * Inventaire logiciel. Volontairement borné : au-delà, seul le décompte est
   * conservé pour éviter des rapports de plusieurs mégaoctets (§80).
   */
  packages: z.array(packageSchema).max(5000).default([]),
  packageCount: maybe(positiveInt).optional(),
  /** Vrai si `packages` a été tronqué par rapport à `packageCount`. */
  packagesTruncated: z.boolean().default(false),
  packageManagers: z.array(packageManagerSchema).max(32).optional(),
  runtimes: z.array(runtimeSchema).max(64).optional(),
  services: z.array(serviceSchema).max(2000).default([]),
});

export type SoftwarePackage = z.infer<typeof packageSchema>;
export type PackageManager = z.infer<typeof packageManagerSchema>;
export type Runtime = z.infer<typeof runtimeSchema>;
export type Service = z.infer<typeof serviceSchema>;
export type Software = z.infer<typeof softwareSchema>;
