// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { z } from 'zod';
import {
  aggregatedMetricSchema,
  celsius,
  isoDateTime,
  maybe,
  positiveInt,
  shortText,
} from '../primitives.js';
import { monitoringSampleSchema } from './monitoring.js';

/**
 * Cibles mesurables par le banc d'essai (§31).
 *
 * Chaque cible correspond à une mesure **distincte et reproductible**. Un
 * « score global machine » n'en fait pas partie : agréger des mesures
 * hétérogènes en un chiffre unique relève de l'interprétation, donc du moteur
 * d'analyse — pas de la collecte.
 */
export const benchmarkTargetSchema = z.enum([
  'cpu-single',
  'cpu-multi',
  /**
   * Charge processeur soutenue, plusieurs minutes durant.
   *
   * Distincte de `cpu-multi` : elle ne cherche pas le débit de pointe mais ce
   * qui se passe *après*. Le bridage thermique n'apparaît pas en vingt
   * secondes — un processeur met plusieurs minutes à atteindre son régime
   * stable, et c'est précisément là que se voit un refroidissement insuffisant.
   */
  'cpu-soak',
  'memory-read',
  'memory-write',
  'memory-copy',
  'storage-sequential-write',
  'storage-sequential-read',
  'storage-random-read',
  'gpu',
  /**
   * Charge mixte, représentative d'un jeu : rendu graphique **et** travail
   * processeur en même temps.
   *
   * Elle n'est ni la mesure `gpu` ni la mesure `cpu-multi`, et c'est tout
   * l'intérêt. Une machine dont la carte graphique tient seule et dont le
   * processeur tient seul peut très bien s'effondrer quand les deux travaillent
   * ensemble : alimentation insuffisante, budget thermique partagé dans un
   * châssis d'ordinateur portable, plafond de puissance commun. Aucune des deux
   * mesures isolées ne le montre.
   *
   * Elle n'est **jamais simulée**. Sans charge graphique exécutable, la mesure
   * est `skipped` avec son motif — pas un score obtenu sur le seul processeur.
   */
  'gaming',
  /**
   * Charge processeur multi-cœur et charge graphique menées de front, chacune
   * au maximum.
   *
   * Distincte de `gaming` : celle-ci ne cherche pas à ressembler à un jeu mais à
   * saturer les deux composants simultanément. C'est la mesure qui révèle un
   * plafond de puissance partagé — les deux tiennent séparément, aucun ne tient
   * ensemble — et elle est le pire cas thermique de la machine.
   */
  'cpu-gpu',
]);

/**
 * Sort d'une mesure.
 *
 * Une mesure absente et une mesure ratée ne se ressemblent que dans un rapport
 * qui ne dit ni l'une ni l'autre. `skipped` couvre l'outil manquant, la place
 * insuffisante et l'arrêt de sécurité ; `failed` couvre l'outil présent qui n'a
 * rien produit d'exploitable.
 */
export const benchmarkStatusSchema = z.enum(['completed', 'skipped', 'failed']);

/**
 * Télémétrie relevée sur une carte graphique pendant une mesure.
 *
 * Chaque champ vient d'une interface constructeur (NVML via `nvidia-smi`, ou
 * hwmon pour les cartes AMD). Rien n'est estimé : une valeur non exposée reste
 * un marqueur.
 */
export const gpuTelemetrySchema = z.object({
  utilizationPercent: maybe(z.number().min(0).max(100)),
  coreClockMhz: maybe(positiveInt),
  memoryClockMhz: maybe(positiveInt),
  vramUsedBytes: maybe(positiveInt),
  vramTotalBytes: maybe(positiveInt),
  temperatureCelsius: maybe(celsius),
  powerWatts: maybe(z.number().min(0).max(2000)),
});

/**
 * Résultat d'une mesure.
 *
 * Un score sans son unité, sans l'outil qui l'a produit et sans les paramètres
 * employés n'est pas comparable — ni à un autre machine, ni au même matériel
 * six mois plus tard. Les cinq champs vont donc ensemble.
 */
export const benchmarkResultSchema = z.object({
  target: benchmarkTargetSchema,
  /**
   * Sort de la mesure. Par défaut `completed` : les rapports produits avant
   * l'introduction de ce champ ne contenaient que des mesures abouties, une
   * mesure manquante y étant simplement absente.
   */
  status: benchmarkStatusSchema.default('completed'),
  /** Pourquoi la mesure a été écartée ou n'a rien produit. */
  detail: shortText.optional(),
  /** Début et fin de cette mesure : c'est ce qui donne une chronologie. */
  startedAt: isoDateTime.optional(),
  finishedAt: isoDateTime.optional(),
  /**
   * Composant mesuré, quand la machine en compte plusieurs.
   *
   * Une machine à deux cartes graphiques produit deux mesures `gpu`, et sans
   * cette étiquette elles seraient indiscernables — ou pire, la seconde
   * passerait pour un doublon de la première.
   */
  device: shortText.optional(),
  /**
   * Version du **protocole de mesure** du scanner qui a produit ce résultat.
   *
   * Distincte de `toolVersion`, et les deux répondent à des questions
   * différentes : `toolVersion` dit quel binaire a tourné, celle-ci dit
   * **comment il a été employé** — durée, taille de bloc, nombre de passes,
   * ordre des phases. Deux `openssl 3.0.13` mesurés l'un sur trois secondes et
   * l'autre sur trente ne rendent pas des chiffres comparables, et rien dans le
   * rapport ne le disait.
   *
   * C'est ce qui permet à la base comparative de refuser une comparaison plutôt
   * que de publier un rang faux : un centile calculé en mélangeant deux
   * protocoles mesure le changement de méthode, pas la machine.
   *
   * Absente des rapports produits avant son introduction — l'absence se lit
   * « protocole inconnu », et une mesure de protocole inconnu ne se compare
   * qu'à elle-même.
   *
   * Ce que chaque version recouvre, cible par cible, est écrit dans
   * `docs/format-rapport/PROTOCOLE-BANC-ESSAI.md`. Sans ce document le numéro
   * serait un talisman : il changerait quand quelqu'un y penserait, et personne
   * ne pourrait dire ce qu'il distingue.
   */
  protocolVersion: maybe(shortText).optional(),
  /** Outil ayant produit la mesure : `openssl`, `dd`, `glmark2`, `fio`… */
  tool: shortText,
  toolVersion: maybe(shortText),
  /** Algorithme ou primitive mesurée, quand la notion s'applique. */
  algorithm: maybe(shortText),
  /** Paramètres exacts, pour que la mesure puisse être rejouée. */
  parameters: maybe(shortText),
  durationMs: maybe(positiveInt),
  score: maybe(z.number()),
  /** `MB/s`, `points`, `ops/s`. Un score sans unité ne veut rien dire. */
  unit: maybe(shortText),
  /** Température relevée à la fin de la mesure, quand un capteur existe. */
  temperatureCelsius: maybe(celsius),
  /**
   * Température avant la mesure, et maximum atteint pendant.
   *
   * La seule valeur de fin ne dit rien : un processeur à 70 °C en fin de test
   * peut être parti de 68 °C ou de 35 °C, et seule la seconde situation décrit
   * une machine qui chauffe. Le maximum est échantillonné pendant la charge,
   * pas déduit des deux bornes.
   */
  temperatureBeforeCelsius: maybe(celsius).optional(),
  temperatureMaxCelsius: maybe(celsius).optional(),
  /**
   * Le processeur a-t-il été bridé pendant la mesure ?
   *
   * Établi en comparant la fréquence pendant la charge à la fréquence de base.
   * Reste inconnu si l'une des deux n'est pas lisible : un banc d'essai qui
   * affirmerait à tort l'absence de bridage fausserait toute comparaison.
   */
  throttled: maybe(z.boolean()),
  /**
   * Télémétrie du GPU pendant la mesure, quand le pilote l'expose.
   *
   * Ces valeurs ne se déduisent d'aucun score : une carte qui rend peu d'images
   * parce qu'elle plafonne en puissance et une carte qui rend peu d'images
   * parce qu'elle est lente produisent le même score, et demandent des
   * décisions opposées.
   */
  gpu: gpuTelemetrySchema.optional(),
  /**
   * Cadence de rendu relevée scène par scène, quand l'outil la publie.
   *
   * `glmark2` en publie une pour chacune de ses scènes — `FPS: 5170 FrameTime:
   * 0.193 ms` —, et le score global n'en est qu'une moyenne pondérée. La cadence
   * dit ce que le score cache : une carte qui rend 300 images par seconde sur
   * une scène et 12 sur une autre n'a pas le même défaut qu'une carte régulière
   * à 150.
   *
   * **Ce n'est pas une cadence de jeu, et le rapport ne doit jamais le laisser
   * croire.** La charge est hors-écran et synthétique ; `tool` et `parameters`
   * la nomment, et le rendu le rappelle en toutes lettres. Une valeur de 56 000
   * images par seconde, courante sur les scènes légères, n'a de sens que
   * comparée à une autre machine sur la même scène.
   *
   * `sampleCount` porte le nombre de scènes mesurées, `unit` leur unité — le
   * schéma d'agrégation existant convient sans en inventer un second.
   */
  framesPerSecond: aggregatedMetricSchema.optional(),
  /**
   * Temps de trame correspondant, en millisecondes.
   *
   * Redondant avec la cadence — l'un est l'inverse de l'autre — et publié quand
   * même : c'est l'outil qui les donne tous les deux, et recalculer l'un depuis
   * l'autre introduirait un arrondi là où il y a une mesure.
   */
  frameTimeMs: aggregatedMetricSchema.optional(),
  /**
   * Stabilité de la cadence, quand assez de trames ont été mesurées.
   *
   * La moyenne est la statistique qui ment le plus sur un rendu : une machine
   * régulière à 60 images par seconde et une machine qui alterne 110 et 30 ont
   * la même moyenne, et une seule des deux est jouable. Les centiles bas
   * décrivent ce que le lecteur ressent — le pire centième des trames — et
   * c'est la lecture qui compte.
   *
   * `frameCount` n'est pas décoratif : un centile de 0,1 % calculé sur trois
   * cents trames **est** le minimum, et le présenter autrement le maquille. Le
   * champ correspondant reste donc un marqueur tant que l'échantillon ne le
   * porte pas.
   */
  frameStability: z
    .object({
      /** Nombre de trames effectivement mesurées, base de tous les centiles. */
      frameCount: positiveInt,
      /** Cadence du 1 % de trames les plus lentes. */
      onePercentLowFps: maybe(z.number().min(0)),
      /** Cadence du 0,1 % de trames les plus lentes. */
      zeroPointOnePercentLowFps: maybe(z.number().min(0)),
      /**
       * Trames anormalement longues, comptées selon `stutterRule`.
       *
       * Jamais un seuil absolu en millisecondes : 33 ms est une saccade sur un
       * rendu à 120 images par seconde et le régime normal d'un rendu à 30. Le
       * seuil est donc **relatif à la médiane de ce rendu-là**, et il est publié
       * avec le compte pour que le chiffre soit vérifiable.
       */
      stutterCount: maybe(positiveInt),
      /** Seuil retenu, en millisecondes, tel qu'appliqué à cette série. */
      stutterThresholdMs: maybe(z.number().min(0)),
      /** La règle en toutes lettres, pour que le compte se recalcule. */
      stutterRule: maybe(shortText),
    })
    .optional(),
});

/**
 * Série temporelle relevée **pendant** le banc d'essai.
 *
 * Un résultat de mesure dit ce que la machine a produit ; cette série dit à quel
 * prix. Ce sont deux questions distinctes, et la seconde est celle qu'un
 * technicien pose devant une machine décevante : la fréquence a-t-elle tenu, la
 * température s'est-elle stabilisée ou a-t-elle continué de monter, les
 * ventilateurs ont-ils répondu ?
 *
 * Chaque échantillon porte sa `phase` : c'est ce qui distingue un pic de
 * température survenu au repos d'un pic survenu sous charge multi-cœur, alors
 * que les deux tracés sont identiques. Sans elle, la courbe est jolie et muette.
 *
 * La forme de l'échantillon est celle de `monitoring` — délibérément. Deux
 * formats pour la même grandeur obligeraient à écrire deux fois chaque
 * graphique, chaque statistique et chaque règle, et à les maintenir alignés à la
 * main.
 */
export const benchmarkTelemetrySchema = z.object({
  /** Intervalle visé entre deux relevés. Le pas réel figure dans chaque `at`. */
  intervalMs: positiveInt,
  /**
   * Les relevés, dans l'ordre chronologique.
   *
   * La borne est plus haute que celle de `monitoring` : une charge soutenue au
   * niveau Poussée dure plusieurs minutes par cible, et tronquer la série
   * effacerait précisément la fin de charge — le seul moment où un
   * refroidissement insuffisant se voit.
   */
  samples: z.array(monitoringSampleSchema).max(7200).default([]),
});

export const benchmarkSchema = z.object({
  startedAt: isoDateTime,
  finishedAt: isoDateTime.optional(),
  durationMs: maybe(positiveInt),
  /** Durée visée par mesure, en secondes. Elle borne la comparaison de deux runs. */
  secondsPerTargetPlanned: maybe(positiveInt).optional(),
  /**
   * Le banc d'essai s'est-il arrêté avant la fin, et pourquoi ?
   *
   * Un arrêt de sécurité — température au-delà du seuil publié par le capteur —
   * doit se lire dans le rapport : sans lui, les mesures restantes paraîtraient
   * simplement absentes, et la machine paraîtrait saine.
   */
  stoppedEarlyReason: shortText.optional(),
  results: z.array(benchmarkResultSchema).max(64).default([]),
  /**
   * Ce que la machine a vécu pendant les mesures, relevé seconde par seconde.
   *
   * Absente sur les rapports produits avant son introduction, et sur les
   * plateformes dont le collecteur ne l'alimente pas encore : une section vide
   * y serait pire que son absence, elle affirmerait une observation qui n'a pas
   * eu lieu.
   */
  telemetry: benchmarkTelemetrySchema.optional(),
});

export type BenchmarkTarget = z.infer<typeof benchmarkTargetSchema>;
export type BenchmarkStatus = z.infer<typeof benchmarkStatusSchema>;
export type GpuTelemetry = z.infer<typeof gpuTelemetrySchema>;
export type BenchmarkResult = z.infer<typeof benchmarkResultSchema>;
export type BenchmarkTelemetry = z.infer<typeof benchmarkTelemetrySchema>;
export type Benchmark = z.infer<typeof benchmarkSchema>;
