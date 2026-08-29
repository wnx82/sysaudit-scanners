// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { z } from 'zod';
import { maybe, semVerString, shortText } from './primitives.js';
import {
  biosSchema,
  cpuSchema,
  gpuSchema,
  memorySchema,
  motherboardSchema,
  sensorsSchema,
} from './sections/hardware.js';
import { startupSchema } from './sections/startup.js';
import { eventsSchema } from './sections/events.js';
import { bootSchema, shutdownSchema, stabilitySchema } from './sections/stability.js';
import { capabilitiesSchema, collectionSchema, reportMetaSchema } from './sections/meta.js';
import { devicesSchema, driverSchema, firmwareSchema } from './sections/devices.js';
import { benchmarkSchema } from './sections/benchmark.js';
import { monitoringSchema } from './sections/monitoring.js';
import { networkSchema } from './sections/network.js';
import { powerSchema } from './sections/power.js';
import { osSchema, systemSchema } from './sections/system.js';
import { securitySchema } from './sections/security.js';
import { softwareSchema } from './sections/software.js';
import { storageSchema } from './sections/storage.js';
import { virtualizationSchema } from './sections/virtualization.js';
import { audioSchema } from './sections/audio.js';

/**
 * Rapport SysAudit — **source de vérité** du produit.
 *
 * Ce document ne contient que des **faits mesurés**. Aucun score, aucune
 * recommandation, aucune comparaison de version n'y figure : ces analyses sont
 * calculées à partir de ce rapport et stockées séparément, afin de pouvoir être
 * recalculées quand une règle évolue (ADR 0003).
 *
 * Les sections matérielles sont optionnelles : leur absence signifie que le
 * scanner n'a pas tenté la collecte. Lorsqu'il l'a tentée sans succès, le champ
 * est présent et porte un marqueur `unknown` expliquant pourquoi.
 */
export const reportSchema = z.object({
  /** Version du format. Toujours en tête, pour permettre un aiguillage précoce. */
  schemaVersion: semVerString,
  scannerVersion: semVerString,
  /** Version de la plateforme, présente uniquement si le scanner la connaît. */
  platformVersion: semVerString.optional(),

  report: reportMetaSchema,
  capabilities: capabilitiesSchema,

  system: systemSchema,
  os: osSchema,

  motherboard: motherboardSchema.optional(),
  bios: biosSchema.optional(),
  cpus: z.array(cpuSchema).max(64).optional(),
  memory: memorySchema.optional(),
  gpus: z.array(gpuSchema).max(16).optional(),
  audio: audioSchema.optional(),
  sensors: sensorsSchema.optional(),
  power: powerSchema.optional(),

  storage: storageSchema.optional(),
  network: networkSchema.optional(),
  devices: devicesSchema.optional(),
  drivers: z.array(driverSchema).max(2000).optional(),
  firmware: z.array(firmwareSchema).max(256).optional(),

  software: softwareSchema.optional(),
  startup: startupSchema.optional(),
  security: securitySchema.optional(),
  virtualization: virtualizationSchema.optional(),

  /**
   * Ce que la machine a vécu, et non ce qu'elle contient.
   *
   * Ces quatre sections sont facultatives comme les autres : leur absence dit
   * que le scanner n'a pas tenté la collecte, jamais qu'il n'y avait rien à
   * trouver. Un rapport antérieur à leur introduction reste donc valide sans
   * migration — c'est tout l'intérêt de ne rendre obligatoire aucune d'entre
   * elles.
   */
  stability: stabilitySchema.optional(),
  boot: bootSchema.optional(),
  shutdown: shutdownSchema.optional(),
  events: eventsSchema.optional(),

  /** Série temporelle, présente uniquement si elle a été demandée. */
  monitoring: monitoringSchema.optional(),
  /** Mesures de performance, présentes uniquement si elles ont été demandées. */
  benchmark: benchmarkSchema.optional(),

  /** Notes libres du scanner, jamais interprétées automatiquement. */
  notes: z.array(shortText).max(64).optional(),
  collection: collectionSchema,
});

export type Report = z.infer<typeof reportSchema>;

/**
 * Enveloppe minimale servant à lire `schemaVersion` **avant** de valider le
 * reste : un rapport produit par un scanner plus récent doit être refusé avec
 * un message clair plutôt que de générer des dizaines d'erreurs de champs.
 */
export const reportEnvelopeSchema = z.object({
  schemaVersion: semVerString,
  scannerVersion: maybe(semVerString).optional(),
});

export type ReportEnvelope = z.infer<typeof reportEnvelopeSchema>;
