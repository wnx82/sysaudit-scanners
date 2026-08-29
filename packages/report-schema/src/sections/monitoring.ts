// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { z } from 'zod';
import {
  aggregatedMetricSchema,
  byteSize,
  celsius,
  isoDateTime,
  maybe,
  megahertz,
  percent,
  positiveInt,
} from '../primitives.js';

/**
 * Motif de limitation, tel que le matériel le publie.
 *
 * L'énumération est **fermée et courte** : chaque valeur correspond à un
 * indicateur que l'une des sources sait rendre. Ouvrir le champ au texte libre
 * y ferait entrer les formulations de chaque pilote, et deux machines bridées
 * pour la même raison n'y seraient plus comparables.
 *
 * `other` existe pour la source qui signale un motif que cette liste ne couvre
 * pas : le rapport dit alors « bridé, motif hors liste », ce qui reste vrai.
 */
export const throttleReasonSchema = z.enum([
  /** Température atteinte : `thermal_throttle`, `PROCHOT`, `HW Thermal Slowdown`. */
  'thermal',
  /** Plafond de puissance atteint : PL1/PL2 côté Intel, `SW Power Cap` côté NVML. */
  'power-limit',
  /** Plafond de courant atteint, distinct du plafond de puissance. */
  'current-limit',
  /** Tension d'alimentation insuffisante : `under-voltage` du Raspberry Pi. */
  'under-voltage',
  /** Limite fixée par l'utilisateur ou l'exploitant, pas par une contrainte physique. */
  'user-defined',
  /** La source signale un motif que cette liste ne couvre pas. */
  'other',
]);

/**
 * Phase de charge pendant laquelle un échantillon a été relevé.
 *
 * Les valeurs reprennent les cibles du banc d'essai (`benchmarkTargetSchema`),
 * plus `idle` pour les relevés pris hors charge — le répit entre deux mesures,
 * qui est la référence sans laquelle aucune montée n'est mesurable.
 *
 * Elles ne sont pas importées de `benchmark.ts` : ce module ne doit pas en
 * dépendre, et un couplage inverse rendrait `monitoring` inutilisable seul. Un
 * test de contrat vérifie que les deux listes restent alignées.
 */
export const telemetryPhaseSchema = z.enum([
  'idle',
  'cpu-single',
  'cpu-multi',
  'cpu-soak',
  'memory-read',
  'memory-write',
  'memory-copy',
  'storage-sequential-write',
  'storage-sequential-read',
  'storage-random-read',
  'gpu',
  'gaming',
  'cpu-gpu',
]);

/**
 * Échantillon de métriques, pris à un instant donné (§30).
 *
 * Les débits sont des **taux mesurés entre deux relevés**, pas des compteurs
 * cumulés : un compteur brut n'a de sens que rapporté à son prédécesseur, et le
 * rapport doit rester lisible sans recalcul.
 *
 * Le premier relevé ne produit aucun échantillon : sans point précédent, il n'y
 * a pas de delta, et inventer une valeur nulle ferait passer une machine
 * chargée pour une machine au repos.
 */
export const monitoringSampleSchema = z.object({
  at: isoDateTime,
  cpuUsagePercent: maybe(percent),
  cpuTemperatureCelsius: maybe(celsius),
  cpuCoreVoltageVolts: maybe(z.number().min(0).max(10)).optional(),
  cpuPackagePowerWatts: maybe(z.number().min(0).max(10000)).optional(),
  gpuTemperatureCelsius: maybe(celsius).optional(),
  gpuHotspotCelsius: maybe(celsius).optional(),
  gpuCoreClockMhz: maybe(megahertz).optional(),
  gpuMemoryClockMhz: maybe(megahertz).optional(),
  gpuCoreVoltageVolts: maybe(z.number().min(0).max(10)).optional(),
  gpuBoardPowerWatts: maybe(z.number().min(0).max(10000)).optional(),
  memoryUsedBytes: maybe(byteSize),
  swapUsedBytes: maybe(byteSize),
  diskReadBytesPerSecond: maybe(byteSize),
  diskWriteBytesPerSecond: maybe(byteSize),
  networkRxBytesPerSecond: maybe(byteSize),
  networkTxBytesPerSecond: maybe(byteSize),
  /**
   * Fréquence effective, moyenne des cœurs exposés à l'instant du relevé.
   *
   * `.optional()` et non `maybe()` seul : les champs ci-dessus sont obligatoires
   * dans un échantillon, et les rendre obligatoires ici refuserait tous les
   * rapports produits avant leur introduction. Un ajout de champ reste MINOR à
   * cette condition (docs/format-rapport/VERSIONING.md).
   */
  cpuFrequencyMhz: maybe(megahertz).optional(),
  /**
   * Limitation de fréquence active, telle que le matériel la signale
   * (`thermal_throttle`, `PROCHOT`, `get_throttled` du Raspberry Pi).
   *
   * Jamais déduite d'une fréquence basse : un processeur au repos tourne bas
   * sans être bridé, et confondre les deux inventerait une panne.
   */
  cpuThrottled: maybe(z.boolean()).optional(),
  /**
   * *Pourquoi* le matériel bride, quand il le dit lui-même.
   *
   * `cpuThrottled` répond « oui », ce champ répond « pour cette raison-là » — et
   * les deux réponses n'appellent pas la même intervention. Un bridage thermique
   * se corrige avec un tournevis et de la pâte thermique ; un plafond de
   * puissance se corrige dans le micrologiciel, et nettoyer le ventilateur n'y
   * changera rien.
   *
   * La raison vient de la source qui l'a signalée, jamais d'une déduction. Un
   * bridage constaté sans motif publié reste `cpuThrottled: true` sans raison :
   * c'est exact, et c'est tout ce qui est connu.
   */
  cpuThrottleReason: maybe(throttleReasonSchema).optional(),
  /** Utilisation du processeur graphique au relevé. */
  gpuUsagePercent: maybe(percent).optional(),
  /** Mémoire graphique occupée au relevé, en octets. */
  gpuVramUsedBytes: maybe(byteSize).optional(),
  /**
   * Motif de limitation rapporté par le pilote graphique
   * (`clocks_throttle_reasons` de NVML, `pp_od_clk_voltage` côté AMD).
   */
  gpuThrottleReason: maybe(throttleReasonSchema).optional(),
  /**
   * Vitesses de rotation relevées, en tours par minute.
   *
   * Elles sont ce qui manque pour lire une montée en température : deux machines
   * à 90 °C ne décrivent pas la même panne selon que les ventilateurs tournent à
   * fond ou ne tournent pas. Une machine sans capteur de rotation — la plupart
   * des portables, toutes les machines virtuelles — n'en publie aucune, ce qui
   * n'est pas « 0 tr/min ».
   */
  cpuFanRpm: maybe(positiveInt).optional(),
  gpuFanRpm: maybe(positiveInt).optional(),
  chassisFanRpm: maybe(positiveInt).optional(),
  /**
   * Les autres ventilateurs de la carte graphique, quand elle en a plusieurs.
   *
   * `gpuFanRpm` reste le premier — il est publié depuis plus longtemps, et le
   * renommer casserait les rapports existants. Ce tableau porte donc **les
   * suivants**, dans l'ordre où le pilote les expose, et il est absent sur une
   * carte à un seul ventilateur plutôt que vide : un tableau vide se lirait
   * comme des ventilateurs à l'arrêt.
   *
   * Une carte à trois ventilateurs dont un seul est bloqué se voit ici et
   * nulle part ailleurs : la moyenne des trois reste plausible, et le maximum
   * la masque complètement.
   */
  gpuAuxiliaryFanRpm: z.array(maybe(positiveInt)).max(8).optional(),
  /**
   * Fréquence de chaque cœur au relevé, dans l'ordre des identifiants système.
   *
   * La moyenne de `cpuFrequencyMhz` répond « le processeur tourne à 3,1 GHz » ;
   * ce tableau répond « deux cœurs à 4,9 et quatorze à 2,8 », ce qui n'est pas
   * la même machine. Sur les architectures hybrides — cœurs performants et
   * cœurs efficients — la moyenne ne décrit **aucun** cœur réel.
   *
   * Chaque position accepte le marqueur : un cœur hors ligne, ou dont
   * `scaling_cur_freq` est illisible, n'est pas un cœur à 0 MHz. La longueur du
   * tableau reste celle de la topologie, sans quoi la position n'identifierait
   * plus le cœur.
   *
   * Absent quand la collecte ne l'a pas relevé — elle coûte une lecture par
   * cœur et par seconde, et ne se justifie que pendant une charge.
   */
  cpuCoreClocksMhz: z.array(maybe(megahertz)).max(512).optional(),
  /**
   * Charge de chaque cœur au relevé, même indexation que `cpuCoreClocksMhz`.
   *
   * C'est la donnée qui distingue une mesure mono-cœur d'une mesure multi-cœur
   * dégradée : 12 % de charge globale sur seize cœurs peut être un cœur saturé
   * — ce que la mesure mono-cœur veut — ou seize cœurs qui traînent, ce qui
   * décrit une charge qui ne démarre pas.
   */
  cpuCoreUsagePercent: z.array(maybe(percent)).max(512).optional(),
  /**
   * Quelle carte graphique les champs `gpu*` de cet échantillon décrivent.
   *
   * Sur une machine à une seule carte, l'index vaut 0 et n'apprend rien. Sur
   * une machine qui en compte deux, son absence rendait la série ambiguë : rien
   * ne disait si la montée en température concernait la carte mesurée ou
   * l'autre. L'index est celui de la source qui a produit le relevé —
   * `nvidia-smi -i`, ou l'ordre d'énumération hwmon — et il est repris tel quel
   * dans `benchmark.results[].device`.
   */
  gpuIndex: z.number().int().min(0).max(15).optional(),
  /**
   * Cadence de rendu instantanée, quand une charge graphique tourne pendant le
   * relevé.
   *
   * Elle n'existe **que** pendant les phases de rendu : hors de celles-ci, il
   * n'y a pas d'images à compter, et publier zéro décrirait une machine
   * bloquée. Comme partout ailleurs dans ce produit, la charge est nommée par
   * `benchmark.results[].tool` et `parameters` — une cadence relevée sur un
   * rendu synthétique n'est pas une cadence de jeu, et le rendu le rappelle.
   */
  framesPerSecond: maybe(z.number().min(0).max(100_000)).optional(),
  /**
   * Temps de trame correspondant, en millisecondes.
   *
   * Redondant avec la cadence, et publié quand même : c'est lui qui porte
   * l'irrégularité. Une seconde à 60 images peut être soixante trames de
   * 16,7 ms ou cinquante-neuf trames rapides suivies d'une trame de 100 ms, et
   * seule la seconde se voit à l'écran.
   */
  frameTimeMs: maybe(z.number().min(0).max(60_000)).optional(),
  /**
   * Phase de charge en cours au moment du relevé.
   *
   * C'est ce champ qui transforme une courbe en diagnostic. Une température de
   * 92 °C ne veut rien dire seule : au repos elle décrit une machine malade,
   * pendant une charge multi-cœur soutenue elle décrit une machine qui travaille.
   * Sans l'étiquette, les deux tracés sont identiques.
   *
   * Absent hors banc d'essai : une observation lancée par `--monitor` n'impose
   * aucune charge, et lui coller `idle` affirmerait que rien ne tournait sur la
   * machine — ce que le scanner ne sait pas.
   */
  phase: telemetryPhaseSchema.optional(),
});

/**
 * Série temporelle collectée pendant le scan.
 *
 * Elle est **facultative et bornée**. Un audit reste par défaut un instantané :
 * l'observation dans la durée est demandée explicitement, parce qu'elle
 * rallonge le scan d'autant.
 *
 * Sa présence change ce que les règles ont le droit d'affirmer. Sur un
 * instantané, une fréquence basse sous charge est une corrélation ; sur une
 * série, une charge tenue sur toute la fenêtre est un fait observé.
 */
export const monitoringSchema = z.object({
  startedAt: isoDateTime,
  /** Intervalle demandé entre deux relevés. Le pas réel figure dans `at`. */
  intervalMs: positiveInt,
  durationMs: maybe(positiveInt),
  samples: z.array(monitoringSampleSchema).max(3600).default([]),
  /**
   * Statistiques min/max/moyenne, calculées par le scanner sur les échantillons
   * qu'il vient de prendre.
   *
   * Elles sont **redondantes avec `samples` et c'est voulu** : une observation
   * d'une heure au pas de la seconde dépasse la borne du tableau, et le rapport
   * doit rester exploitable une fois les échantillons tronqués. Elles portent
   * leur propre `sampleCount`, qui peut donc excéder `samples.length`.
   *
   * Clé = nom du champ échantillonné (`cpuUsagePercent`,
   * `cpuTemperatureCelsius`, `cpuFrequencyMhz`…), pour que la statistique et la
   * série se rejoignent sans table de correspondance.
   */
  aggregates: z.record(z.string().max(64), aggregatedMetricSchema).optional(),
});

export type ThrottleReason = z.infer<typeof throttleReasonSchema>;
export type TelemetryPhase = z.infer<typeof telemetryPhaseSchema>;
export type MonitoringSample = z.infer<typeof monitoringSampleSchema>;
export type Monitoring = z.infer<typeof monitoringSchema>;
