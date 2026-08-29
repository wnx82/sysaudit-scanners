// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { z } from 'zod';
import {
  anonymizableText,
  byteSize,
  celsius,
  isoDate,
  maybe,
  mediumText,
  megahertz,
  percent,
  positiveInt,
  shortText,
} from '../primitives.js';

/** Carte mère (§14). */
export const motherboardSchema = z.object({
  manufacturer: maybe(shortText),
  model: maybe(shortText),
  revision: maybe(shortText),
  serialNumber: maybe(anonymizableText),
  chipset: maybe(shortText),
  socket: maybe(shortText),
  /**
   * Nombre total de slots mémoire physiques. Ne jamais déduire la RAM maximale
   * supportée sans source constructeur (§17) : ce champ ne dit rien de la
   * capacité maximale.
   */
  memorySlots: maybe(positiveInt),
  pcieSlots: z
    .array(
      z.object({
        designation: shortText,
        type: maybe(shortText),
        used: maybe(z.boolean()),
      }),
    )
    .max(64)
    .optional(),
});

/** BIOS / UEFI (§15). */
export const biosSchema = z.object({
  manufacturer: maybe(shortText),
  version: maybe(shortText),
  releaseDate: maybe(isoDate),
  mode: maybe(z.enum(['UEFI', 'LEGACY'])),
  secureBoot: maybe(z.enum(['ENABLED', 'DISABLED', 'UNSUPPORTED'])),
  smbiosVersion: maybe(shortText),
});

export const cpuSchema = z.object({
  manufacturer: maybe(shortText),
  model: maybe(shortText),
  family: maybe(shortText),
  /** Génération commerciale, uniquement si elle est déterminable avec certitude. */
  generation: maybe(shortText),
  socket: maybe(shortText),
  physicalCores: maybe(positiveInt),
  logicalCores: maybe(positiveInt),
  baseFrequencyMhz: maybe(megahertz),
  maxFrequencyMhz: maybe(megahertz),
  currentFrequencyMhz: maybe(megahertz),
  cacheBytes: z
    .object({
      l1: maybe(byteSize).optional(),
      l2: maybe(byteSize).optional(),
      l3: maybe(byteSize).optional(),
    })
    .optional(),
  /** Jeux d'instructions pertinents pour la compatibilité (`avx2`, `aes`, `sse4_2`…). */
  instructionSets: z.array(shortText).max(256).optional(),
  virtualization: maybe(
    z.object({
      supported: z.boolean(),
      enabled: maybe(z.boolean()),
      technology: maybe(shortText),
    }),
  ),
  temperatureCelsius: maybe(celsius),
  usagePercent: maybe(percent),
});

/** Module mémoire physique (§17). */
export const memoryModuleSchema = z.object({
  slot: maybe(shortText),
  /** Absent lorsque le slot est vide — un slot vide reste rapporté. */
  sizeBytes: maybe(byteSize),
  manufacturer: maybe(shortText),
  partNumber: maybe(shortText),
  serialNumber: maybe(anonymizableText),
  type: maybe(shortText),
  /** Vitesse nominale du module, distincte de la vitesse réellement configurée. */
  ratedSpeedMts: maybe(positiveInt),
  configuredSpeedMts: maybe(positiveInt),
  /**
   * Profil mémoire de performance (XMP/EXPO/DOCP…), uniquement lorsqu'une
   * source fiable l'expose explicitement. À défaut, le profil reste inconnu :
   * une fréquence conservatrice ne prouve pas, à elle seule, qu'il soit
   * désactivé.
   */
  performanceProfile: z
    .object({
      technology: maybe(shortText),
      active: maybe(z.boolean()),
      profileName: maybe(shortText),
    })
    .optional(),
  voltage: maybe(z.number().min(0).max(10)),
  ecc: maybe(z.boolean()),
  formFactor: maybe(shortText),
});

export const memorySchema = z.object({
  modules: z.array(memoryModuleSchema).max(64).default([]),
  installedBytes: maybe(byteSize),
  availableBytes: maybe(byteSize),
  slotsTotal: maybe(positiveInt),
  slotsUsed: maybe(positiveInt),
  /**
   * Capacité maximale supportée. N'est renseignée que si elle provient du SMBIOS
   * ou d'une source constructeur — jamais estimée (§17).
   */
  maxCapacityBytes: maybe(byteSize),
  swapTotalBytes: maybe(byteSize),
  swapUsedBytes: maybe(byteSize),
});

export const displaySchema = z.object({
  name: maybe(shortText),
  manufacturer: maybe(shortText),
  /**
   * Modèle publié par l'écran dans son EDID, jamais déduit du connecteur.
   *
   * Un écran ne dit pas toujours son nom commercial : le descripteur `0xFC` est
   * facultatif, et beaucoup de dalles n'exposent qu'un code produit numérique.
   * Le champ reste alors inconnu plutôt que rempli du code, qui ne nomme rien.
   */
  model: maybe(shortText).optional(),
  /**
   * Numéro de série lu dans l'EDID (descripteur `0xFF`).
   *
   * C'est le seul identifiant d'exemplaire d'un écran, et il sert à retrouver
   * une dalle dans un parc — donc réservé au propriétaire, comme celui d'un
   * disque. Beaucoup de fabricants ne le renseignent pas.
   */
  serialNumber: maybe(anonymizableText).optional(),
  resolution: maybe(shortText),
  refreshRateHz: maybe(positiveInt),
  connection: maybe(shortText),
});

export const gpuSchema = z.object({
  vendor: maybe(shortText),
  model: maybe(shortText),
  /** Identifiant PCI `vendor:device`, base fiable de recherche de pilote. */
  pciId: maybe(shortText),
  vramBytes: maybe(byteSize),
  driver: maybe(shortText),
  driverVersion: maybe(shortText),
  driverDate: maybe(isoDate),
  temperatureCelsius: maybe(celsius),
  usagePercent: maybe(percent),
  coreClockMhz: maybe(megahertz),
  memoryClockMhz: maybe(megahertz),
  displays: z.array(displaySchema).max(16).optional(),
});

/**
 * Nature du composant mesuré, choisie par le collecteur d'après la source.
 *
 * Elle existe pour une raison unique : **un seuil n'a de sens que rapporté à un
 * composant**. Quarante-cinq degrés sont normaux sur un processeur, banals sur
 * un NVMe, et déjà élevés sur un disque mécanique. Une liste de capteurs sans
 * catégorie condamne le lecteur à appliquer le même seuil à tout, c'est-à-dire
 * à se tromper partout sauf sur une ligne.
 *
 * `OTHER` n'est pas un fourre-tout honteux : c'est le refus explicite de deviner
 * à quoi correspond une sonde de carte mère nommée `temp3`. Un capteur classé
 * `OTHER` est affiché sans jugement thermique, faute de savoir ce qu'il mesure.
 */
export const temperatureCategorySchema = z.enum([
  'CPU',
  'GPU',
  'MOTHERBOARD',
  'CHIPSET',
  'VRM',
  'MEMORY',
  'DRIVE_HDD',
  'DRIVE_SSD',
  'DRIVE_NVME',
  'NETWORK',
  'BATTERY',
  'AMBIENT',
  'OTHER',
]);

/**
 * Confiance accordée à la **lecture**, distincte de ce qu'elle vaut.
 *
 * - `MEASURED` — lecture plausible, exploitable pour un jugement thermique ;
 * - `SUSPECT` — lecture dans le domaine physique mais incohérente avec le
 *   composant (un processeur en fonctionnement à 0 °C). Elle reste affichée,
 *   parce que la masquer effacerait la panne de capteur qu'elle signale, mais
 *   elle ne déclenche **aucune** alerte thermique.
 *
 * Les lectures hors domaine physique (`-127 °C`, `255 °C`) ne sont pas ici :
 * elles ne sont pas des températures et ne rejoignent jamais `temperatures[]`.
 * Elles sont conservées, brutes, dans `sensors.temperatureCollection.discarded`.
 */
export const temperatureQualitySchema = z.enum(['MEASURED', 'SUSPECT']);

/**
 * À quel matériel la mesure appartient.
 *
 * Un conteneur ou une VM lit les sondes de l'hôte quand l'hyperviseur les lui
 * expose. Les rapporter sans distinction ferait croire au lecteur que sa machine
 * virtuelle possède un VRM — et lui ferait chercher un ventilateur qu'elle n'a
 * pas.
 */
export const temperatureScopeSchema = z.enum(['LOCAL', 'HYPERVISOR_HOST']);

/**
 * Un relevé thermique, tel qu'un capteur l'a réellement rendu.
 *
 * `celsius` est la valeur retenue — la dernière lue lorsqu'il y a eu plusieurs
 * relevés. `minCelsius`/`averageCelsius`/`maxCelsius` ne sont **jamais** des
 * interpolations : ce sont les statistiques des `sampleCount` mesures
 * réellement prises, et elles sont absentes quand il n'y en a eu qu'une.
 */
export const temperatureReadingSchema = z.object({
  /** Nom rendu par le capteur (`Tctl`, `CPU Package`, `Composite`), jamais reformulé. */
  label: shortText,
  celsius,
  /** Seuil critique rapporté par le capteur, non inventé. */
  criticalCelsius: maybe(celsius).optional(),
  /**
   * Seuil « élevé » rapporté par le capteur (`tempN_max` sous hwmon), lorsqu'il
   * existe. Distinct du critique : franchir l'un n'est pas franchir l'autre.
   */
  highCelsius: maybe(celsius).optional(),
  category: temperatureCategorySchema.optional(),
  /**
   * Matériel porteur du capteur, tel qu'il est nommé ailleurs dans le rapport
   * (`Intel Core i7-13700K`, `Samsung SSD 990 PRO 2TB`). Sans lui, trois lignes
   * `Composite` à 43, 51 et 38 °C ne désignent aucun disque en particulier.
   */
  device: shortText.optional(),
  /**
   * Interface réellement interrogée : `hwmon`, `thermal_zone`, `lm-sensors`,
   * `LibreHardwareMonitor`, `nvidia-smi`, `NVMe SMART`, `smartctl`…
   *
   * Ce n'est pas une décoration. Un `CPU Package` à 54 °C venant de
   * `LibreHardwareMonitor` et le même venant d'une zone ACPI n'ont pas la même
   * valeur de preuve, et seul ce champ permet de le savoir après coup.
   */
  source: shortText.optional(),
  /**
   * Chemin ou identifiant exact de la sonde, pour le diagnostic
   * (`/sys/class/hwmon/hwmon2/temp1_input`).
   *
   * Marqué réservé au demandeur : une arborescence de périphériques décrit une
   * machine précise, et un rapport partagé n'a aucune raison de la publier.
   */
  sourcePath: maybe(mediumText).optional(),
  scope: temperatureScopeSchema.optional(),
  quality: temperatureQualitySchema.optional(),
  minCelsius: celsius.optional(),
  averageCelsius: celsius.optional(),
  maxCelsius: celsius.optional(),
  /** Nombre de relevés réellement pris. Absent vaut « un seul », jamais « aucun ». */
  sampleCount: positiveInt.optional(),
  /**
   * Valeur telle que la source l'a rendue, avant conversion — `52300` avec
   * `rawUnit: 'millidegree_celsius'` sous hwmon, `3252` en dixièmes de kelvin
   * sous ACPI.
   *
   * Conservée parce que les conversions sont exactement l'endroit où un relevé
   * juste devient un chiffre faux, et qu'un rapport sans la valeur d'origine ne
   * permet pas de trancher entre un capteur en panne et une division ratée.
   */
  rawValue: z.number().optional(),
  rawUnit: shortText.optional(),
});

/**
 * Relevé écarté : ce que la source a rendu et qui n'est pas une température.
 *
 * `-127 °C` est la réponse d'une sonde 1-Wire absente, `255 °C` celle d'un
 * registre non initialisé. Les publier comme des températures ferait surchauffer
 * ou geler des machines en parfait état. Les taire ferait disparaître la panne
 * de capteur avec elles — d'où cette liste : elles sortent du jugement thermique
 * sans sortir du rapport.
 */
export const discardedTemperatureSchema = z.object({
  label: shortText,
  source: shortText.optional(),
  sourcePath: maybe(mediumText).optional(),
  rawValue: z.number(),
  rawUnit: shortText.optional(),
  /** Valeur convertie, hors domaine physique, si la conversion a pu se faire. */
  celsius: z.number().optional(),
  reason: z.enum(['OUT_OF_PHYSICAL_RANGE', 'UNIT_UNDETERMINED', 'NOT_A_THERMAL_SENSOR']),
});

/**
 * Ce que la collecte thermique a réellement pu faire, indépendamment de son
 * résultat.
 *
 * Un tableau `temperatures` vide est ambigu : machine sans sonde, sonde présente
 * mais illisible faute de droits, ou outil absent. Ces trois cas appellent trois
 * réponses différentes de l'utilisateur — n'en montrer aucune revient à lui dire
 * « débrouillez-vous ».
 */
export const temperatureCollectionSchema = z.object({
  /** Sondes rencontrées, y compris celles dont rien n'a pu être tiré. */
  probed: positiveInt.optional(),
  /** Sondes ayant produit une entrée de `temperatures[]`. */
  usable: positiveInt.optional(),
  /** Sondes rencontrées mais écartées, toutes raisons confondues. */
  discarded: positiveInt.optional(),
  /**
   * Le détail des relevés écartés, borné. Le compteur ci-dessus reste le nombre
   * réel : tronquer la liste ne doit pas faire baisser le décompte.
   */
  discardedReadings: z.array(discardedTemperatureSchema).max(64).optional(),
  /** Interfaces réellement interrogées pendant l'audit, dans l'ordre d'essai. */
  sources: z.array(shortText).max(16).optional(),
  /**
   * Pourquoi aucune température n'a pu être relevée. Renseigné **uniquement**
   * lorsque `temperatures[]` est vide : sans cela, l'absence de sonde et
   * l'absence d'outil se liraient pareil.
   */
  unavailableReason: z
    .enum([
      'NO_SENSOR_EXPOSED',
      'SENSORS_UNREADABLE',
      'TOOL_MISSING',
      'VIRTUALIZED',
      'NOT_COLLECTED',
    ])
    .optional(),
  /** Outil dont l'installation permettrait une collecte plus complète (`lm-sensors`). */
  suggestedTool: shortText.optional(),
  /** Nombre de passes demandées et intervalle, quand plusieurs relevés ont été pris. */
  sampleCount: positiveInt.optional(),
  sampleIntervalMs: positiveInt.optional(),
});

export const sensorsSchema = z.object({
  temperatures: z.array(temperatureReadingSchema).max(256).default([]),
  /**
   * Métadonnées de la collecte thermique. Facultative : un rapport produit avant
   * son introduction reste valide, et son absence ne dit rien de plus que
   * « scanner plus ancien ».
   */
  temperatureCollection: temperatureCollectionSchema.optional(),
  fans: z
    .array(
      z.object({
        label: shortText,
        rpm: maybe(positiveInt),
      }),
    )
    .max(64)
    .default([]),
  voltages: z
    .array(
      z.object({
        label: shortText,
        volts: z.number().min(0).max(1000),
      }),
    )
    .max(64)
    .default([]),
  powers: z
    .array(
      z.object({
        label: shortText,
        watts: z.number().min(0).max(10000),
      }),
    )
    .max(128)
    .default([]),
  powerSupplies: z
    .array(
      z.object({
        label: shortText,
        status: maybe(shortText),
        watts: maybe(positiveInt),
      }),
    )
    .max(16)
    .optional(),
});

export type Motherboard = z.infer<typeof motherboardSchema>;
export type Bios = z.infer<typeof biosSchema>;
export type Cpu = z.infer<typeof cpuSchema>;
export type Memory = z.infer<typeof memorySchema>;
export type MemoryModule = z.infer<typeof memoryModuleSchema>;
export type Gpu = z.infer<typeof gpuSchema>;
export type Display = z.infer<typeof displaySchema>;
export type Sensors = z.infer<typeof sensorsSchema>;
export type TemperatureCategory = z.infer<typeof temperatureCategorySchema>;
export type TemperatureQuality = z.infer<typeof temperatureQualitySchema>;
export type TemperatureScope = z.infer<typeof temperatureScopeSchema>;
export type TemperatureReading = z.infer<typeof temperatureReadingSchema>;
export type DiscardedTemperature = z.infer<typeof discardedTemperatureSchema>;
export type TemperatureCollection = z.infer<typeof temperatureCollectionSchema>;
