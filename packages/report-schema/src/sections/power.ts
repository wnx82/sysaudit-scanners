// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { z } from 'zod';
import {
  anonymizableText,
  celsius,
  confidenceSchema,
  maybe,
  mediumText,
  percent,
  positiveInt,
  shortText,
} from '../primitives.js';

/**
 * Batterie et alimentation (§18).
 *
 * Le scanner rapporte les deux capacités **mesurées** — celle de conception et
 * celle en pleine charge — mais **pas** l'état de santé qui s'en déduit. Une
 * usure est une interprétation : elle appartient au moteur d'analyse, qui peut
 * la recalculer quand la règle évolue, sur des données déjà collectées
 * (ADR 0003).
 */
export const batterySchema = z.object({
  /** Identifiant système (`BAT0`, `BAT1`…). */
  name: maybe(shortText),
  manufacturer: maybe(shortText),
  model: maybe(shortText),
  serialNumber: maybe(anonymizableText),
  /** Chimie rapportée par le firmware (`Li-ion`, `Li-poly`…). */
  technology: maybe(shortText),
  chargePercent: maybe(percent),
  status: maybe(z.enum(['CHARGING', 'DISCHARGING', 'FULL', 'NOT_CHARGING', 'UNKNOWN'])),
  /**
   * Capacité de conception, en wattheures. Convertie depuis des microwattheures
   * ou depuis un couple ampères/volts selon ce que le firmware expose ; absente
   * plutôt qu'estimée lorsque la conversion n'est pas certaine.
   */
  designCapacityWh: maybe(z.number().min(0).max(10000)),
  /** Capacité réelle à pleine charge, même unité. */
  fullChargeCapacityWh: maybe(z.number().min(0).max(10000)),
  cycleCount: maybe(positiveInt),
  voltageVolts: maybe(z.number().min(0).max(1000)),
});

/**
 * Nature de l'alimentation, **telle qu'une source l'a établie**.
 *
 * Aucune de ces valeurs ne se déduit de la forme de la machine. Un boîtier de
 * bureau contient presque toujours une alimentation ATX, mais « presque
 * toujours » n'est pas un fait mesuré : un PC de marque peut embarquer un bloc
 * propriétaire, et une machine de bureau alimentée en 12 V externe n'en a aucun.
 * En l'absence de source, la valeur reste `UNKNOWN` — et la limitation
 * `ATX_NOT_SELF_DESCRIBING` dit pourquoi.
 *
 * - `STANDARD_ATX` — le SMBIOS décrit une alimentation à découpage interne
 *   (type 39, `Type: Switching`). Elle est décrite, pas télémesurée ;
 * - `DIGITAL_ATX` — l'alimentation expose une interface numérique et se nomme
 *   elle-même (pilote `corsairpsu`, capteur de type PSU d'un moniteur matériel) ;
 * - `LAPTOP_ADAPTER` — bloc secteur d'un portable, vu comme source `Mains` ;
 * - `USB_PD` — chargeur USB Power Delivery, négocié par le contrôleur USB-C ;
 * - `UPS` — onduleur, y compris quand il se présente en batterie au noyau ;
 * - `SERVER_MANAGED` — alimentation gérée par un BMC, avec état et redondance ;
 * - `UNKNOWN` — rien de fiable n'a été établi.
 */
export const powerSupplyTypeSchema = z.enum([
  'STANDARD_ATX',
  'DIGITAL_ATX',
  'LAPTOP_ADAPTER',
  'USB_PD',
  'UPS',
  'SERVER_MANAGED',
  'UNKNOWN',
]);

/**
 * Interface réellement interrogée.
 *
 * Ce n'est pas une décoration : une tension `+12V` lue sur le Super-I/O de la
 * carte mère et la même lue sur le bloc d'alimentation lui-même n'ont ni la
 * même précision ni le même sens. La première mesure ce qui **arrive** à la
 * carte mère, à travers un diviseur résistif dont la tolérance est celle d'un
 * composant à quelques centimes ; la seconde est ce que l'alimentation
 * **déclare** produire. Sans ce champ, le lecteur ne peut pas savoir laquelle
 * il regarde.
 */
export const powerSupplySourceSchema = z.enum([
  /** Table SMBIOS type 39, via `dmidecode --type 39` ou la table brute Windows. */
  'SMBIOS',
  /** Classe CIM `Win32_PowerSupply`. */
  'CIM_POWER_SUPPLY',
  /** `/sys/class/power_supply` — secteur, USB-PD, onduleur, batterie. */
  'SYSFS_POWER_SUPPLY',
  /** `/sys/class/hwmon` — Super-I/O de la carte mère, ou pilote d'alimentation. */
  'HWMON',
  /** LibreHardwareMonitor ou OpenHardwareMonitor, quand l'un des deux tourne. */
  'HARDWARE_MONITOR',
  /** Interface numérique d'un bloc, exposée en USB HID. */
  'USB_HID',
  /** Contrôleur de gestion d'un serveur, via `ipmitool`. */
  'IPMI',
  /** Compteurs d'énergie du processeur (`intel-rapl`), lus sur une fenêtre réelle. */
  'RAPL',
  /** `nvidia-smi`, pour la puissance instantanée d'une carte NVIDIA. */
  'NVIDIA_SMI',
  /**
   * Saisie par le propriétaire de la machine. Une valeur lue sur l'étiquette du
   * bloc est un fait — mais un fait rapporté par un humain, jamais détecté par
   * le système, et le rapport ne doit pas laisser confondre les deux.
   */
  'USER_PROVIDED',
]);

/**
 * Ce que la collecte n'a **pas** pu faire, en clair.
 *
 * Une section vide se lit « cette machine n'a pas d'alimentation », ce qui est
 * absurde. Ces motifs disent laquelle des situations on rencontre, et chacun
 * appelle un geste différent — installer un outil, relancer en root, lire
 * l'étiquette du bloc, ou ne rien faire du tout parce qu'il n'y a rien à
 * réparer.
 */
export const powerSupplyLimitationSchema = z.enum([
  /**
   * Le cas normal sur un PC de bureau : une alimentation ATX standard n'a aucun
   * canal pour se présenter au système. Ce n'est pas une erreur d'audit.
   */
  'ATX_NOT_SELF_DESCRIBING',
  /** Le SMBIOS de cette machine ne publie pas de structure type 39. */
  'SMBIOS_TYPE_39_ABSENT',
  /** Aucune interface numérique d'alimentation n'a été trouvée. */
  'NO_DIGITAL_INTERFACE',
  /**
   * Les tensions publiées viennent de la carte mère, pas du bloc. Elle est
   * déclarée systématiquement quand des rails de cette provenance figurent au
   * rapport : c'est la confusion la plus facile à faire, et la plus coûteuse.
   */
  'RAILS_FROM_MOTHERBOARD',
  /** Des sondes existent mais ne sont pas lisibles — droits insuffisants. */
  'SENSORS_UNREADABLE',
  /** La lecture SMBIOS ou IPMI demande des privilèges dont le scan ne dispose pas. */
  'PRIVILEGE_REQUIRED',
  /** Un outil optionnel manque ; `suggestedTool` le nomme. */
  'TOOL_MISSING',
  /** Machine virtualisée : l'hyperviseur ne transmet pas l'alimentation de l'hôte. */
  'VIRTUALIZED',
  /** Le niveau de diagnostic choisi n'a pas prévu cette collecte. */
  'NOT_COLLECTED',
]);

/**
 * Tension d'un rail, avec l'endroit exact où elle a été mesurée.
 *
 * `nominalVolts` n'est délibérément pas ici : il serait une lecture du *nom* du
 * capteur, pas une mesure. Le rapprochement entre `+12V` et douze volts est un
 * jugement, il appartient au moteur d'analyse — qui sait dire, lui, quand
 * l'étiquette ne permet pas de conclure.
 */
export const powerRailSchema = z.object({
  /** Étiquette rendue par le capteur (`+12V`, `in0`, `VBAT`), jamais reformulée. */
  label: shortText,
  volts: z.number().min(-1000).max(1000),
  /**
   * Qui mesure. `MOTHERBOARD` est le cas ordinaire : le Super-I/O expose ce qui
   * lui parvient. `POWER_SUPPLY` n'est employé que lorsque la valeur vient du
   * bloc lui-même, par une interface numérique.
   */
  measuredBy: z.enum(['MOTHERBOARD', 'POWER_SUPPLY', 'UNKNOWN']),
  source: powerSupplySourceSchema,
  /** Puce ayant rendu la valeur (`nct6798`, `corsairpsu`), quand la source la nomme. */
  chip: shortText.optional(),
  /**
   * Chemin exact de la sonde, pour le diagnostic. Une arborescence de
   * périphériques décrit une machine précise : réservée à son propriétaire.
   */
  sourcePath: maybe(mediumText).optional(),
});

/**
 * Consommation d'un composant, mesurée.
 *
 * Elle vit **à part** de l'alimentation, et c'est tout l'objet de cette
 * séparation : additionner un processeur à 32 W et une carte graphique à 54 W
 * ne donne pas la puissance d'un bloc d'alimentation, et lire l'un pour l'autre
 * est exactement l'erreur que ce rapport refuse de commettre. Un PC qui
 * consomme 300 W peut avoir un bloc de 500, 750 ou 1000 W.
 */
export const componentPowerSchema = z.object({
  /** Nom rendu par la source (`package-0`, `CPU Package`, `GPU`). */
  label: shortText,
  component: z.enum(['CPU', 'GPU', 'SYSTEM', 'OTHER']),
  watts: z.number().min(0).max(10000),
  source: powerSupplySourceSchema,
  /** Matériel porteur, tel qu'il est nommé ailleurs dans le rapport. */
  device: shortText.optional(),
  /**
   * Fenêtre réellement couverte par la mesure. Un compteur d'énergie ne donne
   * une puissance qu'à travers une durée : publier l'une sans l'autre laisserait
   * croire à une valeur instantanée.
   */
  windowMs: positiveInt.optional(),
  sourcePath: maybe(mediumText).optional(),
});

/**
 * Ce qu'une alimentation numérique rapporte d'elle-même.
 *
 * `available` vaut `false` sur l'immense majorité des machines, et c'est une
 * information : elle distingue « le bloc ne mesure rien » de « personne n'a
 * regardé ».
 *
 * `efficiencyPercent` n'est renseigné que si le matériel le publie. Le calculer
 * depuis l'entrée et la sortie serait arithmétiquement correct et pratiquement
 * faux : les deux mesures n'ont ni la même incertitude ni le même instant, et
 * leur rapport produit couramment des rendements supérieurs à 100 %.
 */
export const powerSupplyTelemetrySchema = z.object({
  available: z.boolean(),
  inputPowerWatts: maybe(z.number().min(0).max(30000)).optional(),
  outputPowerWatts: maybe(z.number().min(0).max(30000)).optional(),
  inputVoltageVolts: maybe(z.number().min(0).max(1000)).optional(),
  outputVoltageVolts: maybe(z.number().min(0).max(1000)).optional(),
  currentAmps: maybe(z.number().min(0).max(1000)).optional(),
  temperatureCelsius: maybe(celsius).optional(),
  fanRpm: maybe(positiveInt).optional(),
  efficiencyPercent: maybe(percent).optional(),
  source: powerSupplySourceSchema.optional(),
});

/**
 * Une alimentation, telle qu'une source l'a décrite.
 *
 * Le schéma n'a **qu'une** forme, pour un bloc unique comme pour les deux
 * alimentations redondantes d'un serveur : une liste d'unités. Une machine
 * ordinaire en produit zéro — pas une unité vide dont tous les champs seraient
 * inconnus, ce qui donnerait à lire une alimentation là où rien n'a été trouvé.
 */
export const powerSupplyUnitSchema = z.object({
  /** Nom rendu par la source (`PSU 1`, `System Power Supply 1`, `ACAD`). */
  label: shortText,
  type: powerSupplyTypeSchema,
  /** Emplacement physique tel que le SMBIOS le nomme (`Internal`, `Bay 1`). */
  location: maybe(shortText).optional(),
  manufacturer: maybe(shortText).optional(),
  model: maybe(shortText).optional(),
  serialNumber: maybe(anonymizableText).optional(),
  partNumber: maybe(shortText).optional(),
  assetTag: maybe(anonymizableText).optional(),
  revision: maybe(shortText).optional(),
  firmware: maybe(shortText).optional(),
  /**
   * Puissance **nominale déclarée par le matériel**, en watts.
   *
   * Jamais déduite d'une consommation observée, jamais d'une configuration :
   * la présence d'une carte graphique de 300 W n'apprend rien sur le bloc qui
   * l'alimente. Absente vaut « non détectable », et le rendu l'écrit ainsi.
   */
  ratedPowerWatts: maybe(z.number().min(0).max(30000)).optional(),
  /** État rapporté par la source (`OK`, `Present`, `Failed`), non traduit. */
  status: maybe(shortText).optional(),
  present: maybe(z.boolean()).optional(),
  hotReplaceable: maybe(z.boolean()).optional(),
  telemetry: powerSupplyTelemetrySchema.optional(),
  source: powerSupplySourceSchema,
  /**
   * Ce que vaut cette identification.
   *
   * - `HIGH` — le matériel s'est nommé lui-même (interface numérique, BMC) ;
   * - `MEDIUM` — une table du firmware le décrit, sans que le bloc réponde ;
   * - `LOW` — une source ambiguë a été retenue faute de mieux, et le rendu doit
   *   le dire. `LOW` ne sert **jamais** à publier une supposition : une donnée
   *   qui n'a pas été détectée n'entre pas dans le rapport, à aucun niveau de
   *   confiance.
   */
  confidence: confidenceSchema,
});

/**
 * Alimentation électrique de la machine (§18).
 *
 * ## Ce que cette section refuse de faire
 *
 * Elle ne devine **aucune** puissance nominale. C'est la règle qui a présidé à
 * sa forme : sur la majorité des PC équipés d'une alimentation ATX standard, le
 * système d'exploitation n'a aucun moyen d'en connaître le fabricant, le modèle,
 * la puissance ni le numéro de série. Ces informations demandent une lecture
 * physique de l'étiquette du bloc. C'est une limite **normale**, pas un échec de
 * collecte, et le rapport la nomme au lieu de la combler.
 */
export const powerSupplySchema = z.object({
  /**
   * Une alimentation s'est-elle réellement identifiée ?
   *
   * `false` avec des rails et une consommation renseignés est le cas le plus
   * fréquent, et il se lit exactement comme il faut : la machine est mesurée,
   * son bloc reste anonyme.
   */
  detected: z.boolean(),
  /** Nature retenue pour l'ensemble. `UNKNOWN` tant qu'aucune source ne tranche. */
  type: powerSupplyTypeSchema,
  units: z.array(powerSupplyUnitSchema).max(8).default([]),
  rails: z.array(powerRailSchema).max(64).default([]),
  componentPower: z.array(componentPowerSchema).max(32).default([]),
  /** Interfaces réellement interrogées, dans l'ordre d'essai. */
  sources: z.array(powerSupplySourceSchema).max(16).default([]),
  limitations: z.array(powerSupplyLimitationSchema).max(16).default([]),
  /** Outil dont l'installation permettrait une collecte plus complète. */
  suggestedTool: shortText.optional(),
});

export const powerSchema = z.object({
  batteries: z.array(batterySchema).max(8).default([]),
  /** Alimentation secteur branchée. Inconnue sur une machine sans capteur. */
  acConnected: maybe(z.boolean()),
  /**
   * Plan ou profil d'alimentation actif, tel que le système le nomme.
   *
   * Il explique des mesures qui sembleraient sinon contradictoires : un
   * processeur bridé à la moitié de sa fréquence sous un profil « économie
   * d'énergie » n'a rien d'anormal, et l'attribuer à un défaut matériel serait
   * un faux diagnostic. Le scanner rapporte le nom natif sans le traduire ni
   * le juger.
   */
  activePlan: maybe(shortText).optional(),
  /** Gouverneur de fréquence Linux (`performance`, `powersave`, `schedutil`). */
  cpuGovernor: maybe(shortText).optional(),
  /**
   * Bloc d'alimentation, rails et consommation des composants.
   *
   * Facultative : son absence dit « scanner antérieur à son introduction », et
   * rien d'autre. Un rapport produit avant la 1.24.0 reste valide et lisible.
   */
  powerSupply: powerSupplySchema.optional(),
});

export type Battery = z.infer<typeof batterySchema>;
export type Power = z.infer<typeof powerSchema>;
export type PowerSupply = z.infer<typeof powerSupplySchema>;
export type PowerSupplyUnit = z.infer<typeof powerSupplyUnitSchema>;
export type PowerSupplyType = z.infer<typeof powerSupplyTypeSchema>;
export type PowerSupplySource = z.infer<typeof powerSupplySourceSchema>;
export type PowerSupplyLimitation = z.infer<typeof powerSupplyLimitationSchema>;
export type PowerSupplyTelemetry = z.infer<typeof powerSupplyTelemetrySchema>;
export type PowerRail = z.infer<typeof powerRailSchema>;
export type ComponentPower = z.infer<typeof componentPowerSchema>;
