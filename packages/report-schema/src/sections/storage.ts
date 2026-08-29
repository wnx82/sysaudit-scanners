// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { z } from 'zod';
import {
  anonymizableText,
  byteSize,
  celsius,
  maybe,
  percent,
  positiveInt,
  shortText,
} from '../primitives.js';
import { pcieLinkSchema } from './devices.js';

export const diskKindSchema = z.enum([
  'HDD',
  'SSD',
  'NVME',
  'SAS',
  'USB',
  'SD',
  'VIRTUAL',
  'UNKNOWN',
]);

/**
 * De quoi le support est **fait**.
 *
 * Séparé de `kind`, qui mélange trois questions sans le dire : `HDD` et `SSD`
 * décrivent le support, `NVME` et `SAS` le protocole, `USB` et `SD` le bus.
 * Tant qu'ils partagent un champ, il faut en choisir un — et le choix se fait
 * au détriment des deux autres.
 *
 * Le défaut concret : sous Windows, `Win32_DiskDrive` présente les NVMe
 * derrière le pilote de stockage, avec `InterfaceType = SCSI` et
 * `MediaType = Fixed hard disk media`. Un SSD NVMe s'affichait donc
 * « HDD — SCSI », ce qui est faux deux fois. Séparer les champs ne suffit pas à
 * le corriger, mais rend le correctif possible : chacun se lit de sa propre
 * source, et aucun n'a besoin de mentir pour que l'autre soit juste.
 *
 * `UNKNOWN` reste la réponse honnête quand la source ne tranche pas. Un
 * `Fixed hard disk media` de CIM ne dit **pas** qu'un disque tourne : il dit
 * qu'il est fixe.
 */
export const diskMediaTypeSchema = z.enum(['HDD', 'SSD', 'OPTICAL', 'TAPE', 'UNKNOWN']);

/**
 * Par quel bus le support est **branché**.
 *
 * `SCSI` y figure sans être une erreur : c'est ce que rendent les couches
 * d'abstraction, et le rapporter tel quel vaut mieux que de le traduire en
 * devinant. Ce qui était faux n'était pas de lire `SCSI`, c'était d'en conclure
 * un support mécanique.
 */
export const diskBusTypeSchema = z.enum([
  'NVME',
  'SATA',
  'SAS',
  'SCSI',
  'ATA',
  'USB',
  'RAID',
  'SD',
  'MMC',
  'FIBRE_CHANNEL',
  'ISCSI',
  'VIRTUAL',
  'UNKNOWN',
]);

/**
 * Santé SMART / NVMe (§20).
 *
 * Chaque champ reste `unknown` s'il n'a pas été lu : une valeur manquante n'est
 * jamais remplacée par 0, ce qui ferait passer un disque non mesuré pour un
 * disque sain.
 */
export const smartSchema = z.object({
  /** Verdict global rapporté par le disque lui-même, non recalculé. */
  status: maybe(z.enum(['PASSED', 'FAILED', 'WARNING'])),
  temperatureCelsius: maybe(celsius),
  powerOnHours: maybe(positiveInt),
  powerCycles: maybe(positiveInt),
  reallocatedSectors: maybe(positiveInt),
  pendingSectors: maybe(positiveInt),
  uncorrectableErrors: maybe(positiveInt),
  /** Usure SSD en pourcentage de vie consommée (0 = neuf). */
  wearPercent: maybe(percent),
  /** NVMe : `percentage_used` du log SMART. Peut dépasser 100 sur un disque en fin de vie. */
  nvmePercentageUsed: maybe(z.number().min(0).max(255)),
  /** NVMe : réserve de blocs restante, en pourcentage. */
  availableSparePercent: maybe(percent),
  availableSpareThresholdPercent: maybe(percent),
  mediaErrors: maybe(positiveInt),
  unsafeShutdowns: maybe(positiveInt).optional(),
  dataUnitsRead: maybe(positiveInt).optional(),
  dataUnitsWritten: maybe(positiveInt),
  /** Attributs bruts conservés pour l'analyse ultérieure et la comparaison. */
  attributes: z
    .array(
      z.object({
        id: positiveInt.optional(),
        name: shortText,
        value: maybe(z.number()),
        raw: shortText.optional(),
      }),
    )
    .max(128)
    .optional(),
});

export const partitionSchema = z.object({
  name: shortText,
  /**
   * Identifiant du système de fichiers — `UUID=` sous Linux, GUID de volume
   * sous Windows.
   *
   * Il désigne le **contenu**, et survit donc à un déplacement du disque d'une
   * machine à l'autre. C'est ce qui en fait la clé d'un `/etc/fstab` — et ce
   * qui permet de reconnaître un même volume dans deux audits, raison pour
   * laquelle il est réservé au propriétaire.
   */
  uuid: maybe(anonymizableText).optional(),
  /**
   * Identifiant de la **partition** dans la table GPT (`PARTUUID`), distinct de
   * celui du système de fichiers : reformater change l'un et pas l'autre.
   * Absent sur une table MBR, qui n'en a pas.
   */
  partitionUuid: maybe(anonymizableText).optional(),
  mountPoint: maybe(shortText),
  filesystem: maybe(shortText),
  sizeBytes: maybe(byteSize),
  usedBytes: maybe(byteSize),
  freeBytes: maybe(byteSize),
  usagePercent: maybe(percent),
  /** Chiffrement détecté (LUKS, BitLocker) — jamais la clé ni la passphrase. */
  encrypted: maybe(z.boolean()),
  encryptionType: maybe(shortText),
});

export const diskSchema = z.object({
  device: shortText,
  manufacturer: maybe(shortText),
  model: maybe(shortText),
  serialNumber: maybe(anonymizableText),
  /**
   * World Wide Name — identifiant mondial du support, tel que le contrôleur le
   * publie (`0x5002538e40a1b2c3`).
   *
   * Il ne remplace pas le numéro de série : il reste lisible **sans**
   * privilège ni `smartctl`, là où le numéro de série demande les deux. Sur une
   * machine où SMART n'est pas interrogeable, c'est souvent le seul identifiant
   * de disque que le rapport puisse porter.
   */
  wwn: maybe(anonymizableText).optional(),
  /**
   * Identifiant global d'un espace de noms NVMe (`nguid`), quand le contrôleur
   * en publie un. Distinct du WWN : il désigne l'espace de noms, non le
   * support.
   */
  nguid: maybe(anonymizableText).optional(),
  /** Identifiant IEEE EUI-64 d'un espace de noms NVMe, quand il est publié. */
  eui64: maybe(anonymizableText).optional(),
  firmware: maybe(shortText),
  sizeBytes: maybe(byteSize),
  kind: diskKindSchema,
  /**
   * Nature du support, lue d'une source qui la connaît.
   *
   * Facultative : un rapport produit par un scanner antérieur ne la porte pas.
   * Son absence n'autorise **pas** à la déduire de `kind` — c'est précisément
   * la confusion qui produisait « HDD » sur des NVMe.
   */
  mediaType: maybe(diskMediaTypeSchema).optional(),
  /** Bus d'attachement, distinct du support et du protocole. */
  busType: maybe(diskBusTypeSchema).optional(),
  /**
   * Jeu de commandes réellement parlé par le périphérique (`NVMe`, `ATA`,
   * `SCSI`), tel que la source le nomme.
   *
   * Distinct du bus : un NVMe branché en USB parle NVMe derrière un pont
   * SCSI, et les trois faits sont vrais en même temps.
   */
  protocol: maybe(shortText).optional(),
  /** `sata`, `nvme`, `usb`, `sas`… tel que rapporté par le système. */
  interface: maybe(shortText),
  rotationRpm: maybe(positiveInt),
  partitionTable: maybe(z.enum(['GPT', 'MBR', 'UNKNOWN'])),
  removable: maybe(z.boolean()),
  /**
   * Le périphérique accepte les commandes de rejet de blocs (TRIM / UNMAP).
   * Lu depuis la granularité de rejet déclarée par le noyau, jamais déduit du
   * type de disque : un SSD derrière un contrôleur RAID peut ne pas l'exposer.
   */
  trimSupported: maybe(z.boolean()),
  /** Lien actuel / maximal quand le support l’expose (NVMe PCIe, parfois SATA). */
  link: pcieLinkSchema.optional(),
  smart: smartSchema.optional(),
  partitions: z.array(partitionSchema).max(256).default([]),
});

/** Ensemble RAID / LVM / ZFS, lorsqu'il est détectable. */
export const storagePoolSchema = z.object({
  name: shortText,
  type: shortText,
  state: maybe(shortText),
  sizeBytes: maybe(byteSize),
  usedBytes: maybe(byteSize),
  members: z.array(shortText).max(128).default([]),
  /**
   * Niveau RAID tel que rapporté par le système (`raid0`, `raid1`, `raid5`,
   * `mirror`, `linear`…). Jamais déduit du nombre de membres.
   */
  raidLevel: maybe(shortText).optional(),
  /**
   * L'ensemble tolère la perte d'un membre.
   *
   * Déduit du **niveau rapporté**, et uniquement lorsque ce niveau est connu et
   * sans ambiguïté. Un niveau inconnu laisse le champ inconnu : mieux vaut ne
   * rien dire que d'affirmer à tort qu'un ensemble est protégé.
   */
  redundant: maybe(z.boolean()).optional(),
});

export const storageSchema = z.object({
  disks: z.array(diskSchema).max(128).default([]),
  pools: z.array(storagePoolSchema).max(64).default([]),
  totalBytes: maybe(byteSize),
  usedBytes: maybe(byteSize),
  /**
   * Un `fstrim` périodique est planifié à l'échelle du système. La notion est
   * globale et non par disque : c'est un timer, pas une propriété du matériel.
   */
  trimScheduled: maybe(z.boolean()),
});

export type Disk = z.infer<typeof diskSchema>;
export type Smart = z.infer<typeof smartSchema>;
export type Partition = z.infer<typeof partitionSchema>;
export type Storage = z.infer<typeof storageSchema>;
export type DiskMediaType = z.infer<typeof diskMediaTypeSchema>;
export type DiskBusType = z.infer<typeof diskBusTypeSchema>;
