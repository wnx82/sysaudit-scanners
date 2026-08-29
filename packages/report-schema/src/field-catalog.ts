// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import type { z } from 'zod';
import { reportSchema } from './report.js';

/**
 * Catalogue des champs du rapport — **dérivé du schéma Zod**, jamais saisi.
 *
 * ## Pourquoi le générer
 *
 * La documentation demandait une table champ par champ : chemin, type,
 * obligatoire ou non, unité, confidentialité, stockage. Le schéma compte plus de
 * cinq cents feuilles et bouge à chaque version. Une table écrite à la main
 * serait fausse au premier `feat(schema)` — et une documentation de format qui
 * ment est pire que pas de documentation : on la croit.
 *
 * Le dépôt applique déjà ce principe ailleurs (`npm run docs:compatibility`,
 * `npm run docs:levels`). Ici la source est le schéma lui-même.
 *
 * ## Ce que le schéma dit, et ce qu'il ne dit pas
 *
 * Le schéma porte le **chemin**, le **type**, l'**optionalité**, les **bornes**,
 * les **valeurs admises** et le fait qu'un champ accepte le marqueur « non
 * collecté ». Tout cela est extrait ici.
 *
 * Il ne porte **ni** le sens métier, **ni** l'outil qui collecte, **ni** le
 * système d'exploitation concerné, **ni** la version d'introduction. Ces
 * colonnes viennent d'une table d'annotations séparée
 * (`field-annotations.ts`), dont un test vérifie qu'aucune entrée ne désigne un
 * chemin disparu. Un champ non annoté est affiché **non documenté** plutôt que
 * décrit au jugé : inventer un sens serait exactement la faute que le reste du
 * produit refuse de commettre sur une donnée absente.
 */

/** Nature d'une feuille, telle qu'un lecteur du JSON la rencontre. */
export type FieldKind =
  | 'chaîne'
  | 'entier'
  | 'nombre'
  | 'booléen'
  | 'date-heure ISO 8601'
  | 'date ISO 8601'
  | 'énumération'
  | 'littéral'
  | 'objet libre'
  | 'union';

export interface FieldEntry {
  /** Chemin JSON pointé, notation par points ; `[]` marque un élément de tableau. */
  readonly path: string;
  readonly kind: FieldKind;
  /** Type détaillé tel qu'affiché en documentation (bornes et valeurs comprises). */
  readonly type: string;
  readonly optional: boolean;
  /**
   * Un ancêtre du champ est facultatif : le champ est donc obligatoire
   * *lorsque sa section est présente*, et absent avec elle sinon. Sans cette
   * distinction, les feuilles d'une section facultative se liraient comme
   * autant d'obligations du format.
   */
  readonly underOptional: boolean;
  readonly nullable: boolean;
  /**
   * Le champ accepte le marqueur `{ unknown: true, reason }` : le scanner
   * *tente* la collecte, et son échec est dit plutôt que tu.
   */
  readonly maybeUnknown: boolean;
  /** Unité déduite de la primitive, quand le schéma la fixe. */
  readonly unit: string | null;
  /** Valeurs admises, pour une énumération ou un littéral. */
  readonly values: readonly string[];
}

/** Retire les enveloppes qui ne changent pas la forme lue dans le JSON. */
interface Peeled {
  readonly schema: z.ZodType;
  readonly optional: boolean;
  readonly nullable: boolean;
}

function defOf(schema: z.ZodType): { readonly type: string } & Record<string, unknown> {
  return (schema as unknown as { _zod: { def: { type: string } & Record<string, unknown> } })._zod
    .def;
}

function bagOf(schema: z.ZodType): Record<string, unknown> {
  return (
    (schema as unknown as { _zod: { bag?: Record<string, unknown> } })._zod.bag ??
    ({} as Record<string, unknown>)
  );
}

function peel(schema: z.ZodType): Peeled {
  let current = schema;
  let optional = false;
  let nullable = false;

  for (;;) {
    const def = defOf(current);
    if (def.type === 'optional' || def.type === 'default' || def.type === 'prefault') {
      optional = true;
      current = def.innerType as z.ZodType;
      continue;
    }
    if (def.type === 'nullable') {
      nullable = true;
      current = def.innerType as z.ZodType;
      continue;
    }
    if (def.type === 'readonly' || def.type === 'catch') {
      current = def.innerType as z.ZodType;
      continue;
    }
    if (def.type === 'pipe') {
      current = def.out as z.ZodType;
      continue;
    }
    return { schema: current, optional, nullable };
  }
}

/** Reconnaît le marqueur « non collecté », qui n'est pas une valeur du champ. */
function isUnknownMarker(schema: z.ZodType): boolean {
  const def = defOf(schema);
  if (def.type !== 'object') return false;
  const shape = def.shape as Record<string, z.ZodType>;
  const unknown = shape.unknown;
  if (unknown === undefined || shape.reason === undefined) return false;
  return defOf(unknown).type === 'literal';
}

/**
 * Unités portées par les primitives partagées.
 *
 * Elles se reconnaissent à leurs bornes, qui sont uniques dans le schéma : une
 * température est le seul nombre borné à [-100, 200], une fréquence le seul
 * entier borné à 100 000. C'est une reconnaissance de forme, donc faillible en
 * théorie — mais un test vérifie qu'elle rend bien l'unité attendue sur les
 * champs témoins, et une primitive qui changerait de bornes le ferait échouer.
 */
function unitOf(schema: z.ZodType, path: string): string | null {
  const def = defOf(schema);
  const bag = bagOf(schema);
  if (def.type !== 'number') return null;

  const min = bag.minimum;
  const max = bag.maximum;
  if (min === -100 && max === 200) return '°C';
  if (min === 0 && max === 100_000 && bag.format === 'safeint') return 'MHz';
  if (min === 0 && max === 100) return '%';

  // Les octets et les durées ne se distinguent que par le nom : le schéma leur
  // donne les mêmes bornes. Le nom du champ est ici la seule source honnête.
  const leaf = path.split('.').at(-1) ?? '';
  if (/bytes$|Bytes$/.test(leaf)) return 'octets';
  if (/Seconds$|seconds$/.test(leaf)) return 's';
  if (/Ms$|Millis$/.test(leaf)) return 'ms';
  if (/Mhz$|MHz$/.test(leaf)) return 'MHz';
  if (/Watts$|watts$/.test(leaf)) return 'W';
  if (/Celsius$/.test(leaf)) return '°C';
  if (/Percent$|percent$/.test(leaf)) return '%';
  return null;
}

function boundsLabel(schema: z.ZodType): string {
  const bag = bagOf(schema);
  const min = typeof bag.minimum === 'number' ? bag.minimum : null;
  // `z.number().int()` pose `Number.MAX_SAFE_INTEGER` comme borne haute. Ce
  // n'est pas une contrainte métier mais la limite de représentation d'un
  // entier JavaScript : l'afficher ferait lire « au plus 9007199254740991 »
  // comme une règle du format.
  const rawMax = typeof bag.maximum === 'number' ? bag.maximum : null;
  const max = rawMax === Number.MAX_SAFE_INTEGER ? null : rawMax;
  if (min === null && max === null) return '';
  if (min !== null && max !== null) return ` [${min} à ${max}]`;
  if (max !== null) return ` [≤ ${max}]`;
  return ` [≥ ${min}]`;
}

interface Described {
  readonly kind: FieldKind;
  readonly type: string;
  readonly values: readonly string[];
}

function describeLeaf(schema: z.ZodType): Described {
  const def = defOf(schema);
  const bag = bagOf(schema);

  switch (def.type) {
    case 'string': {
      if (bag.format === 'datetime')
        return { kind: 'date-heure ISO 8601', type: 'date-heure ISO 8601 (UTC)', values: [] };
      if (bag.format === 'date')
        return { kind: 'date ISO 8601', type: 'date ISO 8601', values: [] };
      if (bag.format === 'ipv4') return { kind: 'chaîne', type: 'adresse IPv4', values: [] };
      if (bag.format === 'ipv6') return { kind: 'chaîne', type: 'adresse IPv6', values: [] };
      if (bag.format === 'uuid') return { kind: 'chaîne', type: 'UUID', values: [] };
      if (bag.format === 'email') return { kind: 'chaîne', type: 'adresse courriel', values: [] };
      if (bag.format === 'url') return { kind: 'chaîne', type: 'URL', values: [] };
      return { kind: 'chaîne', type: `chaîne${boundsLabel(schema)}`, values: [] };
    }
    case 'number': {
      const integer = bag.format === 'safeint' || bag.format === 'int32';
      return {
        kind: integer ? 'entier' : 'nombre',
        type: `${integer ? 'entier' : 'nombre'}${boundsLabel(schema)}`,
        values: [],
      };
    }
    case 'boolean':
      return { kind: 'booléen', type: 'booléen', values: [] };
    case 'enum': {
      const values = Object.values(def.entries as Record<string, string>).map(String);
      return { kind: 'énumération', type: values.join(' | '), values };
    }
    case 'literal': {
      const values = (def.values as readonly unknown[]).map(String);
      return { kind: 'littéral', type: values.join(' | '), values };
    }
    case 'record':
      return { kind: 'objet libre', type: 'objet à clés libres', values: [] };
    case 'unknown':
    case 'any':
      return { kind: 'objet libre', type: 'valeur libre', values: [] };
    default:
      return { kind: 'union', type: def.type, values: [] };
  }
}

/**
 * Aplatit une union en ses branches utiles.
 *
 * `maybe(x)` produit `x | marqueur non collecté`. Le marqueur est retiré et
 * signalé à part : il concerne tous les champs collectés et noierait la table
 * s'il apparaissait comme une variante de chacun.
 */
function branchesOf(schema: z.ZodType): { branches: z.ZodType[]; maybeUnknown: boolean } {
  const def = defOf(schema);
  if (def.type !== 'union') return { branches: [schema], maybeUnknown: false };

  const branches: z.ZodType[] = [];
  let maybeUnknown = false;
  for (const option of def.options as readonly z.ZodType[]) {
    const inner = peel(option).schema;
    if (isUnknownMarker(inner)) {
      maybeUnknown = true;
      continue;
    }
    const nested = branchesOf(inner);
    maybeUnknown = maybeUnknown || nested.maybeUnknown;
    branches.push(...nested.branches);
  }
  return { branches, maybeUnknown };
}

function walk(
  schema: z.ZodType,
  path: string,
  out: FieldEntry[],
  seen: Set<z.ZodType>,
  underOptional: boolean,
): void {
  const peeled = peel(schema);
  const { branches, maybeUnknown } = branchesOf(peeled.schema);

  // Un objet unique : on descend. Une union d'objets se décrit comme une union,
  // parce que descendre dans une seule branche mentirait sur les autres.
  const only = branches.length === 1 ? branches[0] : undefined;
  if (only !== undefined) {
    const def = defOf(only);

    if (def.type === 'object' && !isUnknownMarker(only)) {
      // Les schémas récursifs (arborescence de périphériques) se coupent ici.
      if (seen.has(only)) return;
      seen.add(only);
      for (const [key, child] of Object.entries(def.shape as Record<string, z.ZodType>)) {
        walk(
          child,
          path === '' ? key : `${path}.${key}`,
          out,
          seen,
          underOptional || peeled.optional,
        );
      }
      seen.delete(only);
      return;
    }

    if (def.type === 'array') {
      walk(def.element as z.ZodType, `${path}[]`, out, seen, underOptional || peeled.optional);
      return;
    }
  }

  const described =
    branches.length === 1 && branches[0] !== undefined
      ? describeLeaf(branches[0])
      : {
          kind: 'union' as const,
          type: branches.map((branch) => describeLeaf(branch).type).join(' | '),
          values: [] as readonly string[],
        };

  out.push({
    path,
    kind: described.kind,
    type: described.type,
    optional: peeled.optional,
    underOptional,
    nullable: peeled.nullable,
    maybeUnknown,
    unit: branches[0] === undefined ? null : unitOf(branches[0], path),
    values: described.values,
  });
}

let cache: readonly FieldEntry[] | null = null;

/**
 * Toutes les feuilles du rapport, dans l'ordre de déclaration du schéma.
 *
 * L'ordre de déclaration est conservé volontairement : il groupe les champs par
 * section, ce qu'un tri alphabétique détruirait.
 */
export function fieldCatalog(): readonly FieldEntry[] {
  if (cache !== null) return cache;
  const entries: FieldEntry[] = [];
  walk(reportSchema as unknown as z.ZodType, '', entries, new Set(), false);
  cache = entries;
  return cache;
}

/** Section de premier niveau d'un chemin (`hardware`, `network`, `meta`…). */
export function sectionOf(path: string): string {
  return path.split('.')[0]?.replace(/\[\]$/, '') ?? '';
}
