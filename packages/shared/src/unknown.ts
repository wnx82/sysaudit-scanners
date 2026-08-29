// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

/**
 * Représentation explicite d'une information non collectée.
 *
 * Règle absolue de SysAudit : une valeur qui n'a pas pu être déterminée de manière
 * fiable ne doit jamais être inventée ni remplacée par une valeur par défaut
 * plausible. Elle est marquée avec l'une des raisons ci-dessous.
 */
export const UNKNOWN_REASONS = [
  /** L'information devrait être disponible mais n'a pas pu être lue. */
  'UNKNOWN',
  /** La source de l'information (outil, fichier, API) est absente du système. */
  'NOT_AVAILABLE',
  /** Le système ou le scanner ne supporte pas cette collecte. */
  'UNSUPPORTED',
  /** L'accès a été refusé (privilèges insuffisants). */
  'PERMISSION_DENIED',
  /**
   * La question ne se pose pas sur cette machine : il n'y a rien à mesurer.
   *
   * Distincte d'`UNSUPPORTED`, qui dit « ce système ne sait pas répondre », et
   * de `NOT_AVAILABLE`, qui dit « l'outil manque ». Un hôte Proxmox hors cluster
   * n'a pas un quorum illisible ni un quorum non supporté : il n'a pas de
   * quorum. Sans cette raison, l'absence de cluster se lirait comme un cluster
   * en panne — exactement l'alarme que ce produit s'interdit de fabriquer.
   */
  'NOT_APPLICABLE',
  /**
   * La collecte n'a pas été tentée : le niveau de diagnostic choisi ne la
   * prévoit pas.
   *
   * Cette raison est distincte de `NOT_AVAILABLE` : la source existe peut-être
   * très bien sur cette machine. Sans elle, un audit `Rapide` se lirait comme
   * un audit `Complète` dont la moitié du matériel aurait échoué — c'est-à-dire
   * comme une machine en mauvais état. Le niveau qui aurait collecté la donnée
   * se dit dans `detail`.
   */
  'NOT_COLLECTED',
] as const;

export type UnknownReason = (typeof UNKNOWN_REASONS)[number];

/** Marqueur d'absence de valeur, accompagné de sa raison et d'un détail optionnel. */
export interface UnknownValue {
  readonly unknown: true;
  readonly reason: UnknownReason;
  readonly detail?: string;
}

/**
 * Valeur potentiellement absente : soit la donnée, soit la raison de son absence.
 * Utilisé dans tout le schéma de rapport pour rendre l'incertitude explicite.
 */
export type Maybe<T> = T | UnknownValue;

/**
 * Ce que chaque raison d'absence dit, en français.
 *
 * ## Pourquoi cette table vit ici, en amont de tout
 *
 * Elle a existé en **trois** exemplaires — dans le moteur de rendu, dans
 * l'interface, et dans le résumé système —, et chaque copie a divergé à sa
 * façon : l'une oubliait `NOT_APPLICABLE` et affichait le sigle brut, une autre
 * traduisait `UNSUPPORTED` par « sans objet », qui est la définition de
 * `NOT_APPLICABLE`. Le moteur d'analyse, lui, écrivait le sigle tel quel dans le
 * message rendu au lecteur : « Compteurs de secteurs SMART : UNSUPPORTED ».
 *
 * `shared` est le seul paquet dont tous dépendent : la table y est unique, et
 * les mots employés sont les mêmes dans la page, dans les exports et dans les
 * motifs d'analyse.
 *
 * ## Deux mots qui ne se confondent pas
 *
 * « non pris en charge » — ce système ne sait pas répondre — et « sans objet » —
 * la question ne se pose pas ici. Les deux raisons existent pour cette
 * distinction ; les traduire pareil la perdrait.
 */
export const REASON_LABELS: Readonly<Record<UnknownReason, string>> = {
  UNKNOWN: 'non déterminé',
  NOT_AVAILABLE: 'non disponible',
  UNSUPPORTED: 'non pris en charge',
  PERMISSION_DENIED: 'accès refusé',
  NOT_COLLECTED: 'non collecté à ce niveau',
  NOT_APPLICABLE: 'sans objet',
};

/**
 * Le libellé d'une raison, ou la clé brute si elle est inconnue.
 *
 * Le repli est délibéré : un rapport archivé peut porter une raison retirée du
 * schéma depuis, et son rendu doit sortir — fût-ce avec le sigle. C'est aussi ce
 * qui rendait les omissions invisibles, d'où les tests qui vérifient que chaque
 * raison de `UNKNOWN_REASONS` a bien son libellé.
 */
export function reasonLabel(reason: string): string {
  return REASON_LABELS[reason as UnknownReason] ?? reason;
}

export function unknown(reason: UnknownReason = 'UNKNOWN', detail?: string): UnknownValue {
  return detail === undefined ? { unknown: true, reason } : { unknown: true, reason, detail };
}

export function isUnknown(value: unknown): value is UnknownValue {
  return (
    typeof value === 'object' &&
    value !== null &&
    (value as { unknown?: unknown }).unknown === true &&
    typeof (value as { reason?: unknown }).reason === 'string'
  );
}

export function isKnown<T>(value: Maybe<T>): value is T {
  return !isUnknown(value);
}

/** Retourne la valeur si elle est connue, sinon `fallback`. Ne fabrique jamais de donnée. */
export function valueOr<T, F>(value: Maybe<T>, fallback: F): T | F {
  return isKnown(value) ? value : fallback;
}

/**
 * Lecture d'un champ potentiellement absent d'un rapport.
 *
 * Un champ peut manquer de deux façons : la section entière est absente (le
 * scanner n'a pas tenté la collecte, `undefined`), ou le champ porte un
 * marqueur `unknown` (la collecte a échoué). Les deux cas se traitent
 * identiquement — on ne conclut rien — d'où cet accesseur unique qui les ramène
 * à `undefined`.
 *
 * Aucun consommateur de rapport ne doit lire un champ autrement : c'est ce qui
 * empêche de confondre « valeur nulle » et « valeur non mesurée ».
 *
 * L'implémentation s'appuie sur `isUnknown` plutôt que sur `isKnown` : appliqué
 * à `Maybe<T>`, ce dernier fait inférer `T = T | UnknownValue` et ne restreint
 * donc rien. Écarter explicitement le cas « inconnu » donne le bon type.
 */
export function read<T>(value: Maybe<T> | undefined): Exclude<T, UnknownValue> | undefined {
  if (value === undefined || isUnknown(value)) return undefined;
  return value as Exclude<T, UnknownValue>;
}

/**
 * Convertit une donnée brute en `Maybe`. Les chaînes vides et les placeholders
 * courants des BIOS (« To Be Filled By O.E.M. », « Default string », …) sont
 * traités comme des valeurs inconnues plutôt que rapportés tels quels.
 */
const BIOS_PLACEHOLDERS = new Set([
  'to be filled by o.e.m.',
  'to be filled by o.e.m',
  'default string',
  'system manufacturer',
  'system product name',
  'system serial number',
  'system version',
  'not specified',
  'not available',
  'unknown',
  'none',
  'n/a',
  'na',
  '0123456789',
  'xxxxxxxx',
  'undefined',
  'oem',
  'o.e.m.',
  'chassis manufacture',
  'default',
  // Numéros de série jamais programmés. `00000000` est celui que les deux
  // barrettes de `QJVJVFA6` portent : huit zéros ne désignent pas un module,
  // et deux machines qui les portent toutes deux ne sont pas la même.
  '00000000',
  '000000000000',
  'null',
  'invalid',
  'not applicable',
  'to be filled by oem',
  // UUID SMBIOS jamais programmés, ou recopiés à l'identique sur toute une
  // série. Ils entrent dans cette table pour la même raison que `00000000` :
  // ce sont des chaînes valides que deux machines distinctes peuvent porter
  // toutes les deux, donc des non-identités.
  //
  // L'enjeu dépasse le rendu. Depuis que l'empreinte machine retient le premier
  // identifiant lisible — `system.uuid` en tête —, un UUID générique laissé ici
  // fusionnerait en une seule machine toutes celles d'une même série. C'est
  // `machineCount` qui s'en trouverait faux, donc la population d'un rang.
  //
  // La liste ne prétend pas être complète : elle ne peut pas l'être, et
  // `fingerprintOf` documente pourquoi son résidu se trompe du côté sûr.
  '00000000-0000-0000-0000-000000000000',
  'ffffffff-ffff-ffff-ffff-ffffffffffff',
  '03000200-0400-0500-0006-000700080009',
  '12345678-1234-5678-1234-567812345678',
]);

/**
 * Motif écrit sur un champ qu'un firmware a laissé à sa valeur d'usine.
 *
 * Un seul texte, employé partout : c'est ce que le lecteur voit à la place de
 * « Unknown » ou « To be filled by O.E.M. », et deux formulations pour la même
 * cause l'obligeraient à se demander si elles disent la même chose.
 */
export const FACTORY_PLACEHOLDER_DETAIL = 'placeholder constructeur non significatif';

/**
 * Ce texte est-il une valeur d'usine plutôt qu'une donnée ?
 *
 * La liste est celle de `fromRaw`, et c'est l'intérêt : un scanner qui verse la
 * chaîne brute et un scanner qui verse un marqueur doivent produire la même
 * lecture. En tenir deux les ferait diverger au premier ajout.
 */
export function isFactoryPlaceholder(raw: unknown): boolean {
  if (typeof raw !== 'string') return false;
  const trimmed = raw.trim();
  if (trimmed === '') return false;
  return BIOS_PLACEHOLDERS.has(trimmed.toLowerCase());
}

/**
 * Un champ de texte, débarrassé des valeurs d'usine que les firmwares laissent.
 *
 * ## Pourquoi une seconde lecture existe à côté de `read()`
 *
 * `read()` ramène « section absente » et marqueur `unknown` au même cas, et
 * c'est tout ce qu'on lui demande. Il ne peut rien pour un troisième cas, plus
 * sournois : le scanner a bien collecté quelque chose, mais ce quelque chose
 * est le texte que le fabricant n'a jamais remplacé — `Unknown` sur une
 * barrette, `To be filled by O.E.M.` sur un châssis, `00000000` sur un numéro
 * de série. Ce sont des chaînes valides pour le schéma, et des non-valeurs pour
 * le lecteur.
 *
 * Les publier telles quelles est le défaut que l'audit `QJVJVFA6` a rendu
 * visible : trois barrettes affichées « Unknown » laissent croire que SysAudit
 * n'a pas su lire, quand c'est le firmware qui n'a pas su écrire.
 *
 * ## Ce que cette fonction ne fait pas
 *
 * Elle ne réécrit **aucun rapport**. Elle se lit au rendu, comme les
 * résolutions de `@sysaudit/hardware-base` : le JSON conserve ce que la machine
 * a dit, et un audit relu dans deux ans montre toujours son `Unknown` d'origine.
 */
export function meaningful(value: Maybe<string> | undefined): Maybe<string> | undefined {
  if (value === undefined) return undefined;
  if (isUnknown(value)) return value;
  if (typeof value !== 'string') return value;
  const trimmed = value.trim();
  if (trimmed === '') return unknown('UNKNOWN', FACTORY_PLACEHOLDER_DETAIL);
  if (BIOS_PLACEHOLDERS.has(trimmed.toLowerCase())) {
    return unknown('UNKNOWN', FACTORY_PLACEHOLDER_DETAIL);
  }
  return trimmed;
}

export function fromRaw(
  raw: string | null | undefined,
  reason: UnknownReason = 'UNKNOWN',
): Maybe<string> {
  if (raw === null || raw === undefined) return unknown(reason);
  const trimmed = raw.trim();
  if (trimmed === '') return unknown(reason);
  if (BIOS_PLACEHOLDERS.has(trimmed.toLowerCase())) {
    return unknown('UNKNOWN', FACTORY_PLACEHOLDER_DETAIL);
  }
  return trimmed;
}

/** Variante numérique : rejette NaN et Infinity plutôt que de les propager. */
export function numberFromRaw(
  raw: string | number | null | undefined,
  reason: UnknownReason = 'UNKNOWN',
): Maybe<number> {
  if (raw === null || raw === undefined || raw === '') return unknown(reason);
  const parsed = typeof raw === 'number' ? raw : Number(raw);
  if (!Number.isFinite(parsed)) return unknown(reason, 'valeur non numérique');
  return parsed;
}
