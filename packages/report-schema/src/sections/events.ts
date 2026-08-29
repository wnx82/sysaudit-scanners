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
 * Incidents relevés dans les journaux natifs, ramenés à une forme commune.
 *
 * Le scanner **normalise sans traduire** : chaque événement conserve son
 * identifiant natif et le nom de la source qui l'a produit. Un `1001` de
 * `BugCheck` et un `Kernel panic` de `journalctl` deviennent tous deux un
 * incident de catégorie `KERNEL_CRASH`, mais un administrateur doit pouvoir
 * retrouver la ligne d'origine dans son propre journal — sans quoi le rapport
 * n'est pas vérifiable, et un rapport invérifiable n'est qu'une opinion.
 */

/**
 * Catégories communes à toutes les plateformes.
 *
 * Elles décrivent **ce qui a échoué**, jamais l'outil qui l'a dit. Un `OTHER`
 * assumé vaut mieux qu'un rangement approximatif : une erreur mal catégorisée
 * pèserait sur le mauvais score.
 */
export const eventCategorySchema = z.enum([
  /** Panique noyau, BugCheck, écran bleu. */
  'KERNEL_CRASH',
  /** Erreur matérielle rapportée par le firmware ou le noyau (WHEA, MCE, EDAC). */
  'HARDWARE',
  /** Erreur de bus ou de contrôleur de stockage (NVMe, SATA, StorPort, AHCI). */
  'STORAGE',
  /** Erreur de système de fichiers (ext4, NTFS, ZFS, APFS). */
  'FILESYSTEM',
  /** Pression mémoire, OOM killer, échec d'allocation. */
  'MEMORY',
  /** Perte de lien, erreurs d'interface, échecs répétés de résolution. */
  'NETWORK',
  /** Pilote ou module noyau en défaut, chargement refusé, taint. */
  'DRIVER',
  /** Service ou unité qui s'arrête en erreur ou boucle en redémarrage. */
  'SERVICE',
  /** Crash d'application en espace utilisateur, coredump, Windows Error Reporting. */
  'APPLICATION_CRASH',
  /** Refus d'accès, AVC SELinux, déni AppArmor, alerte antivirus. */
  'SECURITY',
  /** Coupure secteur, batterie critique, arrêt inattendu (Kernel-Power). */
  'POWER',
  /** Dépassement thermique, limitation de fréquence, sous-tension. */
  'THERMAL',
  /** Mise à jour ou correctif ayant échoué. */
  'UPDATE',
  /** Anomalie au démarrage ou à l'arrêt. */
  'BOOT',
  /** Incident propre à l'hyperviseur, au cluster ou aux invités. */
  'VIRTUALIZATION',
  /** Incident réel qui n'entre dans aucune catégorie ci-dessus. */
  'OTHER',
]);

/**
 * Sévérité **rapportée par la source**, jamais recalculée par le scanner.
 *
 * Décider qu'un avertissement est en réalité critique est une analyse : elle
 * appartient au moteur de règles, qui peut la réviser sur des rapports déjà
 * collectés (ADR 0003).
 */
export const eventSeveritySchema = z.enum(['CRITICAL', 'ERROR', 'WARNING', 'INFO']);

/**
 * Incident normalisé, avec son regroupement.
 *
 * Un incident revient rarement seul : un disque qui meurt écrit la même ligne
 * des milliers de fois. Le scanner regroupe donc par `fingerprint` et compte,
 * plutôt que de transmettre un journal brut — puis borne le tableau. Sans
 * regroupement, la limite de taille couperait au millième doublon et cacherait
 * les autres incidents, c'est-à-dire exactement ceux qu'on cherche.
 */
export const normalizedEventSchema = z.object({
  category: eventCategorySchema,
  severity: eventSeveritySchema,
  /**
   * Sous-système ou fournisseur d'origine : unité systemd, nom de fournisseur
   * ETW Windows, sous-système `syslog`, sous-système macOS.
   */
  provider: shortText,
  /** Identifiant natif (`1001`, `41`, `BugCheck`), tel qu'écrit par la source. */
  nativeId: maybe(shortText),
  firstSeenAt: maybe(isoDateTime),
  lastSeenAt: maybe(isoDateTime),
  /** Nombre d'occurrences regroupées. Toujours ≥ 1 : un incident compté existe. */
  occurrences: z.number().int().min(1),
  /** Message résumé, tronqué et passé par l'anonymisation. */
  summary: mediumText,
  /**
   * Empreinte de regroupement — stable entre deux scans de la même machine.
   *
   * Elle est calculée par le scanner sur la forme du message, débarrassée des
   * horodatages, PID et adresses. C'est ce qui permet de dire « ce même
   * incident dure depuis trois semaines » plutôt que « trois cents incidents ».
   */
  fingerprint: shortText,
  /** Journal ou commande d'où l'incident sort (`journalctl -p err`, `System`). */
  source: shortText,
  /**
   * Extraits bruts, **au plus trois**, anonymisés comme le reste du rapport.
   *
   * Une alerte sans preuve n'est pas actionnable : l'administrateur doit voir la
   * ligne. Trois suffisent — première, dernière, et une du milieu — et bornent
   * ce qu'un journal verbeux peut faire entrer dans le rapport.
   */
  evidence: z.array(mediumText).max(3).optional(),
});

/**
 * Fenêtre d'observation des journaux.
 *
 * `requestedMs` et `coveredMs` sont distincts **volontairement**. Demander
 * quatre-vingt-dix jours à un système dont le journal est volatile ne donne pas
 * quatre-vingt-dix jours : sans cette distinction, « aucun incident » se lirait
 * comme un trimestre sain alors qu'il ne couvre que le dernier démarrage.
 */
export const eventWindowSchema = z.object({
  requestedMs: maybe(durationMs),
  coveredMs: maybe(durationMs),
  since: maybe(isoDateTime),
  until: maybe(isoDateTime),
  /**
   * Le journal survit-il au redémarrage ? Sur beaucoup de distributions,
   * `journald` écrit en mémoire par défaut : la fenêtre repart de zéro à chaque
   * démarrage, et l'historique long est structurellement impossible.
   */
  persistent: maybe(z.boolean()),
});

export const eventsSchema = z.object({
  window: eventWindowSchema,
  /** Nombre de lignes examinées avant regroupement, quand la source le dit. */
  examined: maybe(positiveInt),
  /**
   * La collecte a-t-elle été interrompue par une limite (taille, temps) ?
   * Un tableau tronqué présenté comme complet ferait lire un extrait comme un
   * bilan.
   */
  truncated: maybe(z.boolean()),
  entries: z.array(normalizedEventSchema).max(500).default([]),
  meta: measurementMetaSchema.optional(),
});

export type EventCategory = z.infer<typeof eventCategorySchema>;
export type EventSeverity = z.infer<typeof eventSeveritySchema>;
export type NormalizedEvent = z.infer<typeof normalizedEventSchema>;
export type EventWindow = z.infer<typeof eventWindowSchema>;
export type Events = z.infer<typeof eventsSchema>;
