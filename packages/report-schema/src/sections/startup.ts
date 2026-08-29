// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { z } from 'zod';
import { maybe, shortText } from '../primitives.js';

export const startupItemKindSchema = z.enum([
  'SERVICE',
  'REGISTRY',
  'STARTUP_FOLDER',
  'SCHEDULED_TASK',
  'DESKTOP_AUTOSTART',
  'OTHER',
]);

export const startupScopeSchema = z.enum(['SYSTEM', 'USER', 'UNKNOWN']);

/**
 * Élément exécuté automatiquement au démarrage de la machine ou de la session.
 *
 * Le scanner décrit le mécanisme de départ, pas l'effet du programme : il ne
 * suit aucun processus ni aucune activité après lancement.
 */
export const startupItemSchema = z.object({
  name: shortText,
  kind: startupItemKindSchema,
  scope: startupScopeSchema,
  enabled: maybe(z.boolean()),
  command: maybe(shortText),
  /** `systemd`, `Run`, `Startup`, `Task Scheduler`… */
  location: maybe(shortText),
});

export const startupSchema = z.object({
  items: z.array(startupItemSchema).max(2000).default([]),
});

export type Startup = z.infer<typeof startupSchema>;
export type StartupItem = z.infer<typeof startupItemSchema>;
