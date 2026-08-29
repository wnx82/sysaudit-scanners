// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { z } from 'zod';
import {
  anonymizableText,
  confidenceSchema,
  isoDate,
  isoDateTime,
  maybe,
  mediumText,
  positiveInt,
  shortText,
  sourceSchema,
} from '../primitives.js';

/** Identité de la machine (§12). */
export const systemSchema = z.object({
  hostname: maybe(anonymizableText),
  /**
   * Nom pleinement qualifié, lorsque la résolution locale en donne un.
   *
   * Distinct de `hostname` et non déductible de lui : `pve` et
   * `pve.cabinet.lan` ne se déduisent pas l'un de l'autre, et une machine dont
   * le résolveur ne rend que le nom court n'a pas de FQDN — le champ reste
   * alors inconnu plutôt que recomposé en collant un domaine plausible.
   */
  fqdn: maybe(anonymizableText).optional(),
  /**
   * Domaine DNS ou Active Directory auquel la machine appartient.
   *
   * Sous Windows, `Win32_ComputerSystem.Domain` porte **soit** le domaine
   * **soit** le groupe de travail selon `PartOfDomain` : les deux arrivent ici
   * dans des champs séparés, faute de quoi un parc en groupe de travail se
   * lirait comme un parc joint à un domaine.
   */
  domain: maybe(anonymizableText).optional(),
  /** Groupe de travail Windows, renseigné uniquement hors domaine. */
  workgroup: maybe(anonymizableText).optional(),
  manufacturer: maybe(shortText),
  model: maybe(shortText),
  /** Type de châssis : `desktop`, `laptop`, `server`, `mini-pc`… */
  chassisType: maybe(shortText),
  /** UUID SMBIOS — anonymisable, jamais utilisé seul comme identifiant public. */
  uuid: maybe(anonymizableText),
  serialNumber: maybe(anonymizableText),
  /**
   * Étiquette d'inventaire du châssis (SMBIOS type 3), posée par l'exploitant.
   *
   * Elle nomme un parc et sa numérotation interne — « POSTE-COMPTA-014 » dit
   * qui possède la machine, là où le numéro de série ne dit que laquelle. La
   * plupart des machines de bureau la laissent vide ou remplie d'un texte de
   * fabrique ; celui-ci n'est pas publié comme une valeur.
   */
  assetTag: maybe(anonymizableText).optional(),
  /**
   * `MachineGuid` du registre Windows (`HKLM\SOFTWARE\Microsoft\Cryptography`).
   *
   * Identifiant de l'**installation**, non du matériel : il survit à un
   * changement de carte mère et suit un disque cloné. C'est ce qui le rend
   * utile pour reconnaître un poste re-déployé — et strictement réservé au
   * propriétaire, puisqu'il corrèle deux audits sans rien d'autre.
   */
  machineGuid: maybe(anonymizableText).optional(),
  /** SID de la machine, racine des SID des comptes locaux (Windows). */
  machineSid: maybe(anonymizableText).optional(),
  architecture: maybe(shortText),
  uptimeSeconds: maybe(positiveInt),
  timezone: maybe(shortText),
  /** Horodatage local de la machine, utile pour détecter une horloge dérivée. */
  localTime: maybe(isoDateTime),
});

/**
 * Fin de support éditeur. Jamais déduite d'une simple version : elle n'est
 * renseignée que lorsqu'une source fiable l'établit (§13, §84).
 */
export const supportStatusSchema = z.object({
  status: z.enum(['SUPPORTED', 'EXTENDED', 'END_OF_LIFE', 'UNKNOWN']),
  endOfLife: isoDate.optional(),
  endOfExtendedSupport: isoDate.optional(),
  confidence: confidenceSchema,
  /** Obligatoire dès que le statut n'est pas `UNKNOWN`. */
  source: sourceSchema.optional(),
  note: mediumText.optional(),
});

/** Système d'exploitation (§13). */
export const osSchema = z.object({
  family: z.enum(['linux', 'windows', 'macos', 'freebsd', 'unknown']),
  name: maybe(shortText),
  edition: maybe(shortText),
  distribution: maybe(shortText),
  version: maybe(shortText),
  build: maybe(shortText),
  kernel: maybe(shortText),
  architecture: maybe(shortText),
  installDate: maybe(isoDate),
  locale: maybe(shortText),
  timezone: maybe(shortText),
  support: supportStatusSchema.optional(),
});

export type System = z.infer<typeof systemSchema>;
export type Os = z.infer<typeof osSchema>;
export type SupportStatus = z.infer<typeof supportStatusSchema>;
