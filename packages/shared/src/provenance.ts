// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { isUnknown, type Maybe, type UnknownValue } from './unknown.js';

/**
 * D'où vient une valeur présente — et à quel titre elle a le droit d'être lue.
 *
 * ## Le problème que ce module résout
 *
 * `unknown.ts` répond à « pourquoi cette donnée manque ». Il ne dit rien du cas
 * inverse, qui est en train de devenir le plus dangereux : une donnée
 * **présente** dont on ignore si la machine l'a dite, ou si le produit l'a
 * retrouvée.
 *
 * L'exemple qui a motivé ce module est une barrette mémoire dont le SMBIOS rend
 * `Manufacturer=Unknown`, et dont la référence permet pourtant de retrouver
 * « Crucial » dans un catalogue. Afficher `Crucial` est utile. L'afficher au
 * même titre que la capacité, qui elle vient bien du SMBIOS, ne l'est pas : le
 * lecteur croit lire la machine alors qu'il lit une table de correspondance.
 * Le jour où la table se trompe, rien dans le rapport ne permet de le voir.
 *
 * **Une marque retrouvée depuis une référence n'est pas une donnée SMBIOS.**
 * Une alimentation « attendue » d'après le modèle d'un portable n'est pas la
 * preuve du chargeur réellement branché. C'est la même règle que « ne jamais
 * inventer de valeur », appliquée un cran plus loin : ne jamais présenter une
 * déduction comme une mesure.
 *
 * ## Ce qui existait déjà, et pourquoi ce module ne le remplace pas
 *
 * Trois mécanismes voisins vivent dans le dépôt, et en ajouter un quatrième qui
 * les recouvre serait la faute que ce projet documente ailleurs — deux
 * documents qui répondent à la même question sans dire la même chose :
 *
 * - `UnknownValue` porte l'**absence** et sa raison. Ce module ne la redéclare
 *   donc pas : les statuts `unavailable` et `not_applicable` du contrat de
 *   sortie sont produits à partir de `NOT_AVAILABLE` et `NOT_APPLICABLE`, par
 *   `provenanceStatusOf()`. Deux façons d'écrire « absent » finiraient par
 *   diverger, et un lecteur ne saurait plus laquelle fait foi.
 * - `measurementMetaSchema` (report-schema) documente la source d'une **mesure**
 *   agrégée : commande, méthode, fenêtre d'observation. Il reste le bon outil
 *   pour une série temporelle ; celui-ci sert à une valeur scalaire enrichie.
 * - `confidenceSchema` (report-schema) porte `HIGH | MEDIUM | LOW` pour une
 *   information déduite. La confiance est ici un nombre, parce qu'une méthode
 *   d'appariement en produit un naturellement — une référence exacte vaut 1, un
 *   préfixe de fabricant beaucoup moins. `confidenceBand()` fait la conversion
 *   dans l'unique sens utile, afin que le rapport et le moteur d'analyse
 *   gardent un seul vocabulaire visible.
 *
 * ## Ce que ce module refuse
 *
 * Les constructeurs **lèvent** plutôt que de fabriquer une provenance
 * approximative : une confiance hors de `[0, 1]`, une source vide, ou un
 * `resolved` sans méthode d'appariement ni horodatage. Ce sont des erreurs de
 * programmation, pas des données douteuses — elles se corrigent à l'écriture du
 * collecteur, et un test les attrape.
 *
 * Cette sévérité s'arrête au code. Une graine JSON lue à l'exécution doit être
 * validée à la frontière avant d'arriver ici : un catalogue mal rempli ne doit
 * pas faire échouer un audit (règle 10 de la roadmap).
 */

/**
 * D'où l'information sort physiquement.
 *
 * L'ordre n'a rien d'anodin : il va du plus proche de la machine au plus
 * éloigné. `os`, `firmware` et `driver` sont des mesures — la machine parle
 * d'elle-même. Tout le reste est une déduction, y compris `tool`, qui désigne
 * un utilitaire tiers dont on croit la lecture sans pouvoir la vérifier.
 */
export const SOURCE_TYPES = [
  /** Le système d'exploitation : sysfs, CIM/WMI, appel système. */
  'os',
  /** Le micrologiciel : SMBIOS/DMI, EDID, ACPI. */
  'firmware',
  /** Un pilote qui expose ses propres compteurs. */
  'driver',
  /** Une table embarquée dans le produit, versionnée avec lui. */
  'local_catalog',
  /** Une résolution déjà faite, conservée côté serveur. */
  'backend_cache',
  /** Une source publiée par le constructeur, consultée en ligne. */
  'official_web',
  /** Saisi par un humain, parce que rien ne l'expose. */
  'manual',
  /** Un utilitaire tiers interrogé pour sa lecture (`smartctl`, `nvidia-smi`). */
  'tool',
] as const;

export type SourceType = (typeof SOURCE_TYPES)[number];

/**
 * Les types de source qui constituent une **mesure** de la machine elle-même.
 *
 * Tout le reste est une déduction, et doit être présenté comme telle. La liste
 * est délibérément courte : c'est elle qui décide de ce que le rendu a le droit
 * d'afficher sans mention de provenance.
 */
const MEASURED_SOURCE_TYPES: ReadonlySet<SourceType> = new Set<SourceType>([
  'os',
  'firmware',
  'driver',
]);

/** Statut d'une valeur **présente**. L'absence est portée par `UnknownValue`. */
export type PresentStatus = 'collected' | 'resolved' | 'manual';

/**
 * Statut tel qu'il sort dans un rapport : les trois ci-dessus, plus les deux
 * formes d'absence que `UnknownValue` sait déjà décrire.
 */
export type ProvenanceStatus = PresentStatus | 'unavailable' | 'not_applicable';

export interface Provenance {
  readonly status: PresentStatus;
  /** Ce qui a été interrogé : `dmidecode:memory-device`, `catalog:jedec-ids`. */
  readonly source: string;
  readonly sourceType: SourceType;
  /** Entre 0 et 1. Une référence exacte vaut 1 ; un préfixe ambigu, bien moins. */
  readonly confidence: number;
  /** Comment l'appariement a été fait. Obligatoire dès que le statut est `resolved`. */
  readonly matchMethod?: string;
  /** Adresse de la source publiée, quand il y en a une. */
  readonly sourceUrl?: string;
  /** Quand la résolution a été faite, en ISO 8601. Obligatoire si `resolved`. */
  readonly retrievedAt?: string;
  /**
   * Ce que la machine disait réellement, quand la valeur rendue en diffère.
   *
   * C'est ce champ qui permet de revenir en arrière : sans lui, une résolution
   * erronée efface définitivement le `Unknown` d'origine, et plus personne ne
   * peut constater que la table s'est trompée.
   */
  readonly rawValue?: string;
}

/** Une valeur et sa provenance, indissociables. */
export interface Sourced<T> {
  readonly value: T;
  readonly provenance: Provenance;
}

/** Soit une valeur sourcée, soit la raison de son absence. */
export type MaybeSourced<T> = Sourced<T> | UnknownValue;

function requireText(value: string | undefined, field: string): string {
  if (value === undefined || value.trim() === '') {
    throw new Error(`provenance : \`${field}\` est requis et ne peut pas être vide`);
  }
  return value.trim();
}

function requireConfidence(confidence: number): number {
  if (!Number.isFinite(confidence) || confidence < 0 || confidence > 1) {
    throw new Error(`provenance : \`confidence\` doit être dans [0, 1], reçu ${confidence}`);
  }
  return confidence;
}

export interface CollectedOptions {
  readonly source: string;
  readonly sourceType?: SourceType;
  /** Une mesure vaut 1 par défaut : la machine s'est décrite elle-même. */
  readonly confidence?: number;
  readonly rawValue?: string;
  readonly retrievedAt?: string;
}

/**
 * Une valeur lue **sur la machine**.
 *
 * `sourceType` est restreint aux sources qui constituent une mesure : appeler
 * `collected()` avec `local_catalog` serait précisément la confusion que ce
 * module existe pour empêcher, et le type l'interdit.
 */
export function collected<T>(
  value: T,
  options: CollectedOptions & { readonly sourceType?: 'os' | 'firmware' | 'driver' | 'tool' },
): Sourced<T> {
  const provenance: Mutable<Provenance> = {
    status: 'collected',
    source: requireText(options.source, 'source'),
    sourceType: options.sourceType ?? 'os',
    confidence: requireConfidence(options.confidence ?? 1),
  };
  if (options.rawValue !== undefined) provenance.rawValue = options.rawValue;
  if (options.retrievedAt !== undefined) provenance.retrievedAt = options.retrievedAt;
  return { value, provenance };
}

export interface ResolvedOptions {
  readonly source: string;
  readonly sourceType: 'local_catalog' | 'backend_cache' | 'official_web';
  /** `exact_normalized_part_number`, `vendor_alias`… Jamais « heuristique ». */
  readonly matchMethod: string;
  readonly confidence: number;
  readonly retrievedAt: string;
  readonly rawValue?: string;
  readonly sourceUrl?: string;
}

/**
 * Une valeur **retrouvée**, pas mesurée.
 *
 * Les quatre champs obligatoires ne sont pas de la cérémonie : sans méthode
 * d'appariement ni horodatage, une résolution est indiscernable d'une mesure au
 * moment où on relit le rapport six mois plus tard. Les rendre obligatoires ici
 * est le seul endroit où l'oubli est impossible.
 */
export function resolved<T>(value: T, options: ResolvedOptions): Sourced<T> {
  const provenance: Mutable<Provenance> = {
    status: 'resolved',
    source: requireText(options.source, 'source'),
    sourceType: options.sourceType,
    confidence: requireConfidence(options.confidence),
    matchMethod: requireText(options.matchMethod, 'matchMethod'),
    retrievedAt: requireText(options.retrievedAt, 'retrievedAt'),
  };
  if (options.rawValue !== undefined) provenance.rawValue = options.rawValue;
  if (options.sourceUrl !== undefined) provenance.sourceUrl = options.sourceUrl;
  return { value, provenance };
}

export interface ManualOptions {
  /** Qui ou quoi a saisi : `admin:console`, `import:inventaire`. */
  readonly source?: string;
  readonly retrievedAt?: string;
  readonly confidence?: number;
}

/**
 * Une valeur **saisie par un humain**, parce que rien sur la machine ne
 * l'expose — la puissance d'un bloc d'alimentation de tour, par exemple.
 *
 * L'exemple n'est plus théorique depuis la `0.135.0` : `MachinePowerSupply`
 * porte la déclaration du propriétaire, rattachée à la **machine** et non au
 * scan, et le rapport n'en sait rien. C'est la règle que ce module applique
 * partout, appliquée à une source de plus — le rapport reste ce que la machine
 * a dit, et l'enrichissement se voit.
 *
 * Sa confiance vaut 1 par défaut, et ce n'est pas une contradiction : la
 * personne qui a lu l'étiquette sait mieux que n'importe quelle table. Ce qui
 * doit rester visible, c'est que la machine, elle, n'a rien dit — d'où le
 * statut, pas d'où une confiance rabaissée.
 */
export function manual<T>(value: T, options: ManualOptions = {}): Sourced<T> {
  const provenance: Mutable<Provenance> = {
    status: 'manual',
    source: options.source ?? 'saisie manuelle',
    sourceType: 'manual',
    confidence: requireConfidence(options.confidence ?? 1),
  };
  if (options.retrievedAt !== undefined) provenance.retrievedAt = options.retrievedAt;
  return { value, provenance };
}

/** Écriture interne : le type public reste `readonly`. */
type Mutable<T> = { -readonly [K in keyof T]: T[K] };

export function isSourced<T>(candidate: unknown): candidate is Sourced<T> {
  if (typeof candidate !== 'object' || candidate === null) return false;
  const provenance = (candidate as { provenance?: unknown }).provenance;
  if (typeof provenance !== 'object' || provenance === null) return false;
  const status = (provenance as { status?: unknown }).status;
  return status === 'collected' || status === 'resolved' || status === 'manual';
}

/**
 * La valeur, ou `undefined` si elle est absente.
 *
 * Pendant de `read()` pour les valeurs sourcées : un consommateur qui ne
 * s'intéresse pas à la provenance ne doit pas avoir à la déballer à la main,
 * sans quoi il finira par lire `.value` sans vérifier l'absence.
 */
export function sourcedValue<T>(value: MaybeSourced<T> | undefined): T | undefined {
  if (value === undefined || isUnknown(value)) return undefined;
  return value.value;
}

/** La provenance, ou `undefined` si la valeur est absente. */
export function provenanceOf<T>(value: MaybeSourced<T> | undefined): Provenance | undefined {
  if (value === undefined || isUnknown(value)) return undefined;
  return value.provenance;
}

/**
 * Le statut de sortie, absence comprise.
 *
 * C'est ici que les deux modèles se rejoignent : `NOT_APPLICABLE` devient
 * `not_applicable`, et **toutes les autres raisons** deviennent `unavailable`.
 * La distinction conservée est celle qui change ce que le lecteur doit faire —
 * « il n'y a rien à mesurer ici » n'appelle aucune action, « je n'ai pas pu
 * lire » peut en appeler une. Le détail exact reste dans l'`UnknownValue`, qui
 * n'est pas jetée.
 */
export function provenanceStatusOf<T>(value: MaybeSourced<T>): ProvenanceStatus {
  if (isUnknown(value)) {
    return value.reason === 'NOT_APPLICABLE' ? 'not_applicable' : 'unavailable';
  }
  return value.provenance.status;
}

/**
 * La valeur vient-elle de la machine elle-même ?
 *
 * C'est la question que le rendu doit poser avant d'afficher une valeur sans
 * mention de provenance. Faux pour une résolution, une saisie, un cache — et
 * faux pour une absence, qui n'est pas une mesure de zéro.
 */
export function isMeasured<T>(value: MaybeSourced<T>): boolean {
  if (isUnknown(value)) return false;
  return (
    value.provenance.status === 'collected' &&
    MEASURED_SOURCE_TYPES.has(value.provenance.sourceType)
  );
}

/**
 * La confiance numérique, ramenée au vocabulaire déjà employé par le rapport.
 *
 * Les seuils sont volontairement grossiers. Une échelle fine donnerait à croire
 * qu'on sait distinguer 0,82 de 0,79, alors que ces nombres sortent de règles
 * d'appariement écrites à la main : afficher « MEDIUM » est honnête, afficher
 * « 79 % » ne le serait pas.
 *
 * Le seuil haut est **strictement** 1 : seule une correspondance exacte mérite
 * `HIGH`. Une résolution à 0,95 reste une résolution, et le rappeler est tout
 * l'objet de ce module.
 */
export function confidenceBand(confidence: number): 'HIGH' | 'MEDIUM' | 'LOW' {
  if (confidence >= 1) return 'HIGH';
  if (confidence >= 0.7) return 'MEDIUM';
  return 'LOW';
}

/**
 * Adapte une valeur sourcée vers le `Maybe<T>` du schéma de rapport.
 *
 * Utile tant que le schéma ne porte pas la provenance champ par champ : la
 * valeur passe, la provenance est perdue. À n'employer que là où le rendu ne
 * l'exploite pas encore — sinon c'est exactement l'effacement que ce module
 * cherche à empêcher.
 */
export function toMaybe<T>(value: MaybeSourced<T>): Maybe<T> {
  return isUnknown(value) ? value : value.value;
}
