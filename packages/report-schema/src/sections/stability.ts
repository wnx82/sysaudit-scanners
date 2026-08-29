// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { z } from 'zod';
import {
  durationMs,
  isoDateTime,
  maybe,
  measurementMetaSchema,
  mediumText,
  positiveInt,
  shortText,
} from '../primitives.js';

/**
 * Stabilité observée, séquence de démarrage et séquence d'arrêt.
 *
 * Ces trois sections répondent à une question que l'instantané matériel ne sait
 * pas poser : *cette machine tient-elle debout dans la durée ?* Un inventaire
 * dit qu'un disque existe ; seul l'historique dit qu'il jette une erreur toutes
 * les nuits depuis trois semaines.
 *
 * Tous les compteurs sont des `maybe`. Un compteur d'incidents absent et un
 * compteur à zéro ne veulent surtout pas dire la même chose : le premier signale
 * qu'on n'a pas pu regarder, le second qu'on a regardé et qu'il n'y avait rien.
 * Les confondre est la seule manière de transformer un scanner en producteur de
 * fausses assurances.
 */

/**
 * Un compteur d'incidents, avec la fenêtre qu'il couvre.
 *
 * La valeur seule ne veut rien dire : « trois pannes » est rassurant sur un an
 * et alarmant sur une journée. Le couple compteur/fenêtre est indissociable, et
 * le schéma le rend donc indissociable aussi.
 */
export const incidentCountSchema = z.object({
  count: maybe(positiveInt),
  observationWindowMs: maybe(durationMs),
  /** Date du dernier incident de ce type, quand la source la donne. */
  lastAt: maybe(isoDateTime),
  source: maybe(shortText),
});

/** Unité, service ou tâche ayant échoué. */
export const failedUnitSchema = z.object({
  name: shortText,
  /** État natif (`failed`, `Stopped`, `activating`), non traduit. */
  state: maybe(shortText),
  /** Sous-état ou code de sortie natif. */
  result: maybe(shortText),
  since: maybe(isoDateTime),
  /** Redémarrages automatiques observés : un service qui boucle n'est pas « à l'arrêt ». */
  restarts: maybe(positiveInt),
  /** Mode de démarrage natif, quand il aide à comprendre un arrêt normal. */
  startup: maybe(shortText).optional(),
  /** Preuve factuelle ayant justifié le signalement (`ExitCode=1`, `SCM 7031`). */
  reason: maybe(shortText).optional(),
  /** Fournisseur ou commande qui porte la preuve (`Win32_Service`, `Service Control Manager`). */
  source: maybe(shortText).optional(),
});

/** Vidange mémoire d'un processus, sans son contenu. */
export const coredumpSchema = z.object({
  /** Nom d'exécutable, anonymisable. */
  executable: maybe(shortText),
  signal: maybe(shortText),
  at: maybe(isoDateTime),
  count: positiveInt,
  /** Le fichier de vidange est-il encore présent sur le disque ? */
  present: maybe(z.boolean()),
});

export const stabilitySchema = z.object({
  uptimeSeconds: maybe(positiveInt),
  bootedAt: maybe(isoDateTime),

  /** Redémarrages observés, tous motifs confondus. */
  reboots: incidentCountSchema.optional(),
  /**
   * Arrêts dont la trace montre qu'ils n'ont pas été demandés : coupure secteur,
   * blocage, `Kernel-Power 41`. Distincts d'un redémarrage propre.
   */
  unexpectedShutdowns: incidentCountSchema.optional(),
  kernelCrashes: incidentCountSchema.optional(),
  hardwareErrors: incidentCountSchema.optional(),
  storageErrors: incidentCountSchema.optional(),
  filesystemErrors: incidentCountSchema.optional(),
  memoryPressureEvents: incidentCountSchema.optional(),
  networkErrors: incidentCountSchema.optional(),
  driverErrors: incidentCountSchema.optional(),
  serviceFailures: incidentCountSchema.optional(),
  applicationCrashes: incidentCountSchema.optional(),
  thermalEvents: incidentCountSchema.optional(),
  failedUpdates: incidentCountSchema.optional(),

  /** Unités actuellement en échec, telles que le gestionnaire de services les liste. */
  failedUnits: z.array(failedUnitSchema).max(200).default([]),
  /**
   * Services automatiques arrêtés sans preuve d'échec.
   *
   * Sous Windows, `Stopped` seul est ambigu : services différés, déclenchés ou
   * ponctuels peuvent être arrêtés normalement. Ces entrées restent visibles
   * pour diagnostic, mais ne sont pas des échecs avérés.
   */
  stoppedUnits: z.array(failedUnitSchema).max(200).default([]),
  coredumps: z.array(coredumpSchema).max(100).default([]),

  /**
   * Le noyau est-il « souillé » ? Sur Linux, `/proc/sys/kernel/tainted` non nul
   * signale un module propriétaire, un module forcé ou une erreur matérielle
   * antérieure. La valeur brute est conservée : sa décomposition en bits est une
   * interprétation, donc du ressort du moteur d'analyse.
   */
  kernelTainted: maybe(positiveInt),

  meta: measurementMetaSchema.optional(),
});

/** Phase de la séquence de démarrage, telle que la plateforme la découpe. */
export const bootPhaseSchema = z.object({
  /** `firmware`, `loader`, `kernel`, `initrd`, `userspace`, `bios`, `applications`. */
  name: shortText,
  durationMs: maybe(durationMs),
});

/** Élément lent au démarrage : unité systemd, service, pilote ou application. */
export const slowStartupItemSchema = z.object({
  name: shortText,
  durationMs: maybe(durationMs),
  /** `unit`, `driver`, `application`, `service` — la nature change la remédiation. */
  kind: maybe(shortText),
});

export const bootSchema = z.object({
  /**
   * Découpage natif. Il n'est **pas** normalisé entre plateformes :
   * `systemd-analyze` et les journaux Diagnostics-Performance ne mesurent pas
   * les mêmes bornes, et forcer une correspondance produirait une comparaison
   * fausse entre un Linux et un Windows.
   */
  phases: z.array(bootPhaseSchema).max(16).default([]),
  totalMs: maybe(durationMs),
  measuredAt: maybe(isoDateTime),

  slowestItems: z.array(slowStartupItemSchema).max(50).default([]),
  failedAtBoot: z.array(failedUnitSchema).max(100).default([]),

  /** Micrologiciel : UEFI, BIOS hérité, ou indéterminé. */
  firmwareMode: maybe(z.enum(['UEFI', 'LEGACY_BIOS', 'UNKNOWN'])),
  /**
   * Démarrage rapide de Windows (hibernation partielle).
   *
   * Il fausse tout le reste de cette section : la machine ne redémarre pas
   * vraiment, l'uptime ne repart pas de zéro et les correctifs ne s'appliquent
   * pas. Le signaler évite de lire un « démarrage en huit secondes » comme une
   * performance.
   */
  fastStartupEnabled: maybe(z.boolean()),

  /**
   * Durées des démarrages précédents, quand la plateforme les conserve.
   * Une dérive est un signal ; un seul point ne l'est pas.
   */
  history: z
    .array(z.object({ at: isoDateTime, totalMs: maybe(durationMs) }))
    .max(50)
    .optional(),

  /**
   * Noyaux installés, et celui qui tourne.
   *
   * Les distributions à publication continue en gardent plusieurs, et une
   * machine peut tourner depuis des semaines sur un noyau plus ancien que le
   * plus récent installé — un correctif de sécurité appliqué mais pas encore
   * chargé. C'est un fait vérifiable, et un fait que ni `os.kernel` seul ni
   * `security.updates.rebootRequired` ne rendent : le premier ne dit pas ce qui
   * attend, le second ne dit pas quoi.
   *
   * Le scanner **compare sans conclure** : décider qu'un écart mérite une
   * alerte appartient au moteur d'analyse (ADR 0003).
   */
  kernels: z
    .object({
      running: maybe(shortText),
      installed: z.array(shortText).max(50).default([]),
      /** Le plus récent selon le gestionnaire de paquets, jamais selon un tri maison. */
      newestInstalled: maybe(shortText),
      source: maybe(shortText),
    })
    .optional(),

  meta: measurementMetaSchema.optional(),
});

export const shutdownSchema = z.object({
  lastShutdownAt: maybe(isoDateTime),
  /**
   * Le dernier arrêt s'est-il déroulé proprement ?
   *
   * `false` est une affirmation forte : elle exige une trace explicite d'arrêt
   * sale. L'absence de trace d'arrêt propre ne suffit pas et reste `unknown`.
   */
  lastShutdownWasClean: maybe(z.boolean()),
  /** Motif natif rapporté (`Power Off`, `41`, `unexpected`), non traduit. */
  lastShutdownReason: maybe(mediumText),
  lastShutdownDurationMs: maybe(durationMs),
  /** Unités ayant retardé l'arrêt, quand le journal les nomme. */
  slowestItems: z.array(slowStartupItemSchema).max(50).default([]),
  meta: measurementMetaSchema.optional(),
});

export type IncidentCount = z.infer<typeof incidentCountSchema>;
export type FailedUnit = z.infer<typeof failedUnitSchema>;
export type Coredump = z.infer<typeof coredumpSchema>;
export type Stability = z.infer<typeof stabilitySchema>;
export type BootPhase = z.infer<typeof bootPhaseSchema>;
export type SlowStartupItem = z.infer<typeof slowStartupItemSchema>;
export type Boot = z.infer<typeof bootSchema>;
export type Shutdown = z.infer<typeof shutdownSchema>;
