// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { z } from 'zod';
import { isoDate, maybe, mediumText, positiveInt, shortText, sourceSchema } from '../primitives.js';

/**
 * Lien PCI Express négocié, et ce que le lien permettrait au mieux.
 *
 * Les deux sont indispensables ensemble : une carte en x4 n'est un problème que
 * si le lien accepte davantage. Rapporter la seule valeur négociée conduirait à
 * signaler comme dégradé un périphérique qui fonctionne à son maximum.
 */
export const pcieLinkSchema = z.object({
  /** Vitesse négociée telle que rapportée par le noyau (`8.0 GT/s PCIe`). */
  currentSpeed: maybe(shortText),
  maxSpeed: maybe(shortText),
  /** Nombre de voies, sans le préfixe `x`. */
  currentWidth: maybe(positiveInt),
  maxWidth: maybe(positiveInt),
});

export const deviceStatusSchema = z.enum([
  'OK',
  'DRIVER_MISSING',
  'DRIVER_ERROR',
  'DISABLED',
  'UNKNOWN_DEVICE',
  'UNKNOWN',
]);

/**
 * Périphérique PCI/PCIe/USB. Le `hardwareId` est la seule base fiable pour
 * chercher un pilote : un nom commercial approximatif ne suffit pas (§24).
 */
export const deviceSchema = z.object({
  bus: z.enum(['PCI', 'PCIE', 'USB', 'OTHER']),
  /** Identifiant complet (`PCI\VEN_8086&DEV_1533`, `8086:1533`). */
  hardwareId: maybe(shortText),
  vendorId: maybe(shortText),
  deviceId: maybe(shortText),
  vendor: maybe(shortText),
  name: maybe(shortText),
  /** Classe du périphérique (`Network controller`, `VGA compatible controller`…). */
  class: maybe(shortText),
  driver: maybe(shortText),
  status: deviceStatusSchema,
  address: maybe(shortText),
  /** Renseigné pour les périphériques PCIe qui exposent leur lien. */
  link: pcieLinkSchema.optional(),
});

export const driverStatusSchema = z.enum([
  'CURRENT',
  'POTENTIALLY_OUTDATED',
  'UPDATE_AVAILABLE',
  'MISSING',
  'ERROR',
  'UNKNOWN',
]);

/**
 * Pilote installé (§23). Le statut `UPDATE_AVAILABLE` exige une version
 * disponible **et** sa source ; sans preuve, le statut reste `UNKNOWN` ou
 * `POTENTIALLY_OUTDATED`.
 */
export const driverSchema = z.object({
  device: maybe(shortText),
  hardwareId: maybe(shortText),
  vendor: maybe(shortText),
  name: maybe(shortText),
  version: maybe(shortText),
  date: maybe(isoDate),
  provider: maybe(shortText),
  signed: maybe(z.boolean()),
  /** Fichier INF sous Windows, module noyau sous Linux. */
  infName: maybe(shortText),
  status: driverStatusSchema,
  availableVersion: maybe(shortText).optional(),
  source: sourceSchema.optional(),
  note: mediumText.optional(),
});

/** Firmware d'un composant (§25). */
export const firmwareSchema = z.object({
  component: shortText,
  kind: z.enum(['BIOS', 'SSD', 'NVME', 'NIC', 'GPU', 'DEVICE', 'OTHER']),
  installedVersion: maybe(shortText),
  availableVersion: maybe(shortText).optional(),
  releaseDate: maybe(isoDate).optional(),
  source: sourceSchema.optional(),
  checkedAt: z.iso.datetime({ offset: true }).optional(),
});

export const devicesSchema = z.object({
  pci: z.array(deviceSchema).max(512).default([]),
  usb: z.array(deviceSchema).max(512).default([]),
  other: z.array(deviceSchema).max(512).default([]),
});

export type Device = z.infer<typeof deviceSchema>;
export type PcieLink = z.infer<typeof pcieLinkSchema>;
export type Driver = z.infer<typeof driverSchema>;
export type Firmware = z.infer<typeof firmwareSchema>;
