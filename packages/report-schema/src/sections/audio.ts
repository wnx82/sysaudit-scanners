// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { z } from 'zod';
import { maybe, shortText } from '../primitives.js';

export const audioDeviceKindSchema = z.enum([
  'PLAYBACK',
  'CAPTURE',
  'PLAYBACK_CAPTURE',
  'MIDI',
  'CONTROLLER',
  'UNKNOWN',
]);

export const audioDeviceStateSchema = z.enum(['ENABLED', 'DISABLED', 'UNKNOWN']);

/**
 * Périphérique audio local.
 *
 * Aucun volume, aucun flux en cours, aucune session applicative : seul
 * l'inventaire matériel et logique est collecté.
 */
export const audioDeviceSchema = z.object({
  name: shortText,
  vendor: maybe(shortText),
  driver: maybe(shortText),
  /** `alsa`, `pulse`, `pipewire`, `wdm`, `wasapi`… tel que connu du scanner. */
  stack: maybe(shortText),
  kind: audioDeviceKindSchema,
  state: audioDeviceStateSchema,
  /** Le périphérique par défaut pour la sortie ou l'entrée, si la notion existe. */
  default: maybe(z.boolean()),
});

export const audioSchema = z.object({
  devices: z.array(audioDeviceSchema).max(256).default([]),
});

export type Audio = z.infer<typeof audioSchema>;
export type AudioDevice = z.infer<typeof audioDeviceSchema>;
