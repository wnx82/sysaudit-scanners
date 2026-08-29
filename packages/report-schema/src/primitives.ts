// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { UNKNOWN_REASONS } from '@sysaudit/shared';
import { z } from 'zod';

/**
 * Marqueur d'information non collectée. Présent partout où un scanner *tente*
 * une collecte : il distingue « le composant est absent » de « l'outil de
 * mesure est absent », ce que l'omission du champ ne permettrait pas.
 */
export const unknownValueSchema = z
  .object({
    unknown: z.literal(true),
    reason: z.enum(UNKNOWN_REASONS),
    detail: z.string().max(500).optional(),
  })
  .describe('Information non collectée, avec la raison de son absence');

/** Valeur collectée, ou marqueur expliquant pourquoi elle ne l'a pas été. */
export function maybe<T extends z.ZodType>(schema: T): z.ZodUnion<[T, typeof unknownValueSchema]> {
  return z.union([schema, unknownValueSchema]);
}

/**
 * Toutes les chaînes sont bornées : un rapport est une donnée non fiable, et
 * une longueur non bornée est un vecteur de déni de service au stockage.
 */
export const shortText = z.string().trim().min(1).max(256);
export const mediumText = z.string().trim().min(1).max(1024);
export const longText = z.string().trim().min(1).max(8192);

export const semVerString = z
  .string()
  .regex(
    /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$/,
    'Version SemVer attendue (MAJOR.MINOR.PATCH)',
  );

/** Horodatage ISO 8601 en UTC. Le scanner ne rapporte jamais d'heure locale nue. */
export const isoDateTime = z.iso.datetime({ offset: true });

/** Date seule, lorsque l'heure n'a pas de sens (date de BIOS, fin de support). */
export const isoDate = z.iso.date();

/** Les tailles sont **toujours** stockées en octets ; le formatage est un rendu. */
export const byteSize = z.number().int().min(0);

export const percent = z.number().min(0).max(100);

/** Bornes larges mais physiques : hors de cet intervalle, la lecture est erronée. */
export const celsius = z.number().min(-100).max(200);

export const megahertz = z.number().int().min(0).max(100_000);
export const positiveInt = z.number().int().min(0);

/**
 * Adresse MAC normalisée en minuscules séparées par `:`, ou pseudonyme
 * d'anonymisation (`MAC-A1B2C3D4E5`).
 */
export const macAddress = z
  .string()
  .regex(
    /^(?:[0-9a-f]{2}:){5}[0-9a-f]{2}$|^MAC-[0-9A-F]{10}$/,
    'Adresse MAC ou pseudonyme attendu',
  );

export const ipv4 = z.union([z.ipv4(), z.string().regex(/^IP-[0-9A-F]{10}$/)]);
export const ipv6 = z.union([z.ipv6(), z.string().regex(/^IP-[0-9A-F]{10}$/)]);

/** Chaîne libre pouvant avoir été remplacée par un pseudonyme d'anonymisation. */
export const anonymizableText = shortText;

/** Durée en millisecondes. Bornée à un an : au-delà, la lecture est erronée. */
export const durationMs = z.number().int().min(0).max(31_536_000_000);

/**
 * Provenance d'une mesure, portée par la mesure elle-même.
 *
 * `collection.provenance` documente déjà la provenance d'une *section*. Cela ne
 * suffit plus dès qu'un même domaine mêle plusieurs sources : sur Linux, un
 * compteur d'incidents peut venir de `journalctl` et le compteur voisin de
 * `/var/log/syslog`, parce que le journal n'est pas persistant. Attribuer les
 * deux à la section entière effacerait justement la différence qui explique
 * pourquoi l'un couvre trois mois et l'autre trois jours.
 *
 * `observationWindowMs` est la durée réellement couverte, jamais la durée
 * demandée : un journal qui ne remonte qu'à hier ne devient pas trimestriel
 * parce qu'on a demandé quatre-vingt-dix jours.
 */
export const measurementMetaSchema = z.object({
  /** Commande, API ou fichier interrogé (`journalctl`, `Get-WinEvent`, `/proc/uptime`). */
  source: shortText.optional(),
  /** Manière d'obtenir la valeur (`lecture fichier`, `CIM`, `commande shell`). */
  method: shortText.optional(),
  collectedAt: isoDateTime.optional(),
  /** Durée réellement couverte par la mesure, quand elle est agrégée. */
  observationWindowMs: durationMs.optional(),
});

/**
 * Grandeur échantillonnée pendant l'observation, résumée par ses statistiques.
 *
 * `sampleCount` n'est **pas** un `maybe` : c'est un dénombrement, et zéro
 * échantillon est un fait — non une valeur manquante. C'est précisément ce qui
 * permet de lire `average` absent sans conclure « moyenne nulle » : il n'y a
 * simplement rien eu à moyenner.
 *
 * `current` reste distinct de `maximum` : sur un instantané pris en fin de
 * fenêtre, confondre les deux ferait passer un pic transitoire pour l'état
 * courant de la machine.
 */
export const aggregatedMetricSchema = z.object({
  current: maybe(z.number()),
  minimum: maybe(z.number()),
  maximum: maybe(z.number()),
  average: maybe(z.number()),
  /**
   * Valeur du **premier** relevé de la fenêtre.
   *
   * Avec `current`, qui est le dernier, elle donne le sens de l'évolution — ce
   * qu'aucune des trois autres statistiques ne dit. Un processeur passé de
   * 4,6 GHz à 3,1 GHz pendant une charge soutenue a la même moyenne qu'un
   * processeur monté de 3,1 à 4,6, et ce n'est pas du tout la même machine.
   */
  first: maybe(z.number()).optional(),
  /**
   * Quatre-vingt-quinzième centile, par rang le plus proche.
   *
   * Il existe parce que le maximum est fragile : un seul relevé aberrant — une
   * lecture prise pendant un changement de fréquence, une sonde qui hoquette —
   * suffit à le déplacer, et le rapport annonce alors une pointe que la machine
   * n'a jamais tenue. Le centile décrit ce qui s'est produit **durablement**.
   *
   * Absent en dessous de deux relevés : un centile calculé sur un point est
   * ce point, et l'annoncer comme un centile donnerait à une valeur unique
   * l'autorité d'une statistique.
   */
  p95: maybe(z.number()).optional(),
  /** Unité littérale (`°C`, `MHz`, `%`, `W`, `rpm`), jamais devinée du nom. */
  unit: maybe(shortText),
  sampleCount: positiveInt,
  sampleIntervalMs: maybe(durationMs),
  sampleDurationMs: maybe(durationMs),
  source: maybe(shortText),
});

/**
 * Niveau de confiance d'une information déduite plutôt que mesurée. Toute
 * donnée provenant d'une source externe doit en porter un (§39).
 */
export const confidenceSchema = z.enum(['HIGH', 'MEDIUM', 'LOW']);

/** Provenance d'une information externe : sans elle, l'information est une supposition. */
export const sourceSchema = z.object({
  /** Nom de la source (« Documentation ASUS », « Microsoft Learn »). */
  name: shortText,
  vendor: shortText.optional(),
  title: mediumText.optional(),
  url: z.url().max(2048).optional(),
  /** Date à laquelle la source a été consultée. */
  checkedAt: isoDateTime.optional(),
});

export type UnknownValueSchema = z.infer<typeof unknownValueSchema>;
export type Confidence = z.infer<typeof confidenceSchema>;
export type Source = z.infer<typeof sourceSchema>;
