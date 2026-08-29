// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { DIAGNOSTIC_LEVEL_PROFILES, type DiagnosticLevel } from './diagnostic-levels.js';

/**
 * Durée d'audit annoncée : mesurée quand on peut, avouée sinon.
 *
 * ## Le problème que ce module remplace
 *
 * `targetDurationSeconds` est une constante écrite à la main. « 5 à 12 minutes »
 * pour le niveau Complète n'a jamais été mesuré sur un parc — c'est une
 * intention de conception, pas une observation. Seul le niveau Poussée porte une
 * mesure, et sur **une** machine (docs/technique/PERFORMANCE.md).
 *
 * Une estimation fausse coûte deux fois. Trop haute, elle fait renoncer à un
 * audit qui aurait pris deux minutes. Trop basse, elle fait interrompre un audit
 * en cours qu'on croit bloqué — et un audit interrompu ne produit rien.
 *
 * ## Ce qu'il fait
 *
 * Il substitue à la constante les percentiles réellement observés, **et
 * seulement quand l'échantillon les porte**. En dessous du seuil, il ne se
 * rabat pas silencieusement sur la constante en la faisant passer pour une
 * mesure : il dit que la calibration est en cours. C'est la même règle que
 * partout ailleurs dans ce dépôt — une donnée non collectée porte son motif,
 * elle ne se laisse pas confondre avec une donnée connue.
 */

/**
 * Nombre d'audits en dessous duquel aucune plage n'est annoncée comme mesurée.
 *
 * Vingt, et non trois comme le seuil d'anonymat des statistiques publiques :
 * les deux protègent des choses différentes. Trois suffit à empêcher
 * d'identifier une machine ; il ne suffit pas à situer un P90, qui par
 * construction décrit la queue de la distribution. Sur cinq audits, le P90 est
 * le maximum observé — c'est-à-dire la machine la plus lente rencontrée, promue
 * norme.
 */
export const MIN_CALIBRATION_SAMPLE = 20;

/** Percentiles observés pour un niveau, tels que la base les a comptés. */
export interface MeasuredLevelDuration {
  readonly level: DiagnosticLevel;
  /** Audits ayant rapporté une durée. Un audit sans mesure n'est pas compté. */
  readonly sampleSize: number;
  readonly p50Seconds: number;
  readonly p90Seconds: number;
}

/**
 * Ce qu'il faut afficher pour un niveau.
 *
 * `source` n'est pas décoratif : c'est lui qui interdit de présenter une
 * constante comme une observation. L'interface s'en sert pour choisir entre une
 * plage et un aveu.
 */
export type LevelDurationEstimate =
  | {
      readonly level: DiagnosticLevel;
      readonly source: 'measured';
      readonly minSeconds: number;
      readonly maxSeconds: number;
      readonly sampleSize: number;
    }
  | {
      readonly level: DiagnosticLevel;
      readonly source: 'calibrating';
      /** Ce qui manque pour publier une plage, à afficher tel quel si utile. */
      readonly sampleSize: number;
    };

/**
 * Percentile par interpolation linéaire entre les deux rangs encadrants.
 *
 * L'interpolation plutôt que l'index arrondi : sur un petit échantillon, arrondir
 * fait sauter le P90 d'une valeur observée à la suivante, et la plage annoncée
 * bouge par à-coups visibles là où la réalité, elle, a peu changé.
 *
 * Retourne `null` sur une liste vide — il n'y a pas de percentile de rien.
 */
export function percentile(values: readonly number[], fraction: number): number | null {
  if (values.length === 0) return null;

  const sorted = [...values].sort((left, right) => left - right);
  if (sorted.length === 1) return sorted[0]!;

  const bounded = Math.min(Math.max(fraction, 0), 1);
  const position = bounded * (sorted.length - 1);
  const lower = Math.floor(position);
  const upper = Math.ceil(position);
  if (lower === upper) return sorted[lower]!;

  return sorted[lower]! + (sorted[upper]! - sorted[lower]!) * (position - lower);
}

/**
 * Plage à afficher pour un niveau.
 *
 * Sans mesure suffisante, retourne `calibrating` : l'appelant doit alors dire
 * que l'estimation se calibre, **pas** afficher la constante de
 * `targetDurationSeconds` comme si elle avait été observée.
 */
export function levelDurationEstimate(
  level: DiagnosticLevel,
  measured: readonly MeasuredLevelDuration[],
): LevelDurationEstimate {
  const match = measured.find((entry) => entry.level === level);

  if (match === undefined || match.sampleSize < MIN_CALIBRATION_SAMPLE) {
    return { level, source: 'calibrating', sampleSize: match?.sampleSize ?? 0 };
  }

  /*
   * P50 comme borne basse, P90 comme borne haute.
   *
   * Le maximum observé serait tentant pour la borne haute et serait un mauvais
   * choix : un seul audit lancé sur une machine à l'agonie, ou interrompu par
   * une mise en veille, fixerait durablement la promesse faite à tout le monde.
   * Le P90 dit « neuf audits sur dix tiennent dans cette durée », ce qui est
   * exactement la question que se pose quelqu'un devant le bouton.
   */
  return {
    level,
    source: 'measured',
    minSeconds: Math.max(1, Math.round(match.p50Seconds)),
    maxSeconds: Math.max(1, Math.round(match.p90Seconds)),
    sampleSize: match.sampleSize,
  };
}

/**
 * Plage annoncée d'un niveau, en minutes, prête à afficher.
 *
 * Retourne `null` quand la calibration est en cours : l'appelant affiche alors
 * son propre libellé d'attente. Un `null` explicite plutôt qu'un repli sur la
 * constante — le repli silencieux est précisément ce que ce module existe pour
 * empêcher.
 */
export function levelDurationMinutes(
  estimate: LevelDurationEstimate,
): { readonly min: number; readonly max: number } | null {
  if (estimate.source !== 'measured') return null;

  return {
    min: Math.max(1, Math.round(estimate.minSeconds / 60)),
    max: Math.max(1, Math.round(estimate.maxSeconds / 60)),
  };
}

/**
 * Plage cible inscrite au profil, en minutes.
 *
 * Conservée pour la documentation, qui décrit une intention de conception et
 * non un parc. Elle ne doit **pas** servir à l'interface d'audit : c'est
 * l'usage que ce module remplace.
 */
export function targetDurationMinutes(level: DiagnosticLevel): {
  readonly min: number;
  readonly max: number;
} {
  const { targetDurationSeconds } = DIAGNOSTIC_LEVEL_PROFILES[level];
  return {
    min: Math.max(1, Math.round(targetDurationSeconds.min / 60)),
    max: Math.max(1, Math.round(targetDurationSeconds.max / 60)),
  };
}
