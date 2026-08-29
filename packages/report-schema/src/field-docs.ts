// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { annotationFor, POSTGRES_PROJECTIONS, type FieldPrivacy } from './field-annotations.js';
import { fieldCatalog, sectionOf, type FieldEntry } from './field-catalog.js';
import { fullReport } from './fixtures.js';
import { osFixtures } from './fixtures-os.js';

/**
 * Rendu Markdown du catalogue de champs.
 *
 * La table est **entièrement dérivée** : le schéma Zod donne la forme,
 * `field-annotations.ts` le sens, et les jeux d'essai fournissent les exemples.
 * Rien n'y est saisi à la main, et `field-docs-sync.test.ts` échoue si le
 * fichier généré a été modifié.
 *
 * ## Pourquoi les exemples viennent des jeux d'essai
 *
 * Un exemple inventé finit par illustrer un format que plus rien ne produit —
 * une date sans fuseau, une taille en gigaoctets là où le schéma veut des
 * octets. Ceux-ci sont lus dans les rapports de référence, qui sont validés par
 * le schéma à chaque exécution des tests. Un champ absent de tous les jeux
 * d'essai n'a **pas** d'exemple : en fabriquer un serait inventer une valeur.
 */

const PRIVACY_LABELS: Readonly<Record<FieldPrivacy, string>> = {
  public: 'Public',
  restricted: 'Réservé au demandeur',
  anonymizable: 'Anonymisable à la collecte',
};

/** Chaque jeu d'essai disponible, du plus complet au plus particulier. */
function sampleReports(): readonly unknown[] {
  return [fullReport(), ...osFixtures().map((fixture) => fixture.report)];
}

/**
 * Valeur trouvée à un chemin dans un rapport, en traversant les tableaux.
 *
 * Le premier élément d'un tableau suffit : la table documente la forme d'une
 * entrée, pas le contenu d'une collection.
 */
function valueAt(source: unknown, path: string): unknown {
  let current: unknown = source;
  for (const segment of path.split('.')) {
    const array = segment.endsWith('[]');
    const key = array ? segment.slice(0, -2) : segment;
    if (current === null || typeof current !== 'object') return undefined;
    current = (current as Record<string, unknown>)[key];
    if (!array) continue;
    if (!Array.isArray(current)) return undefined;
    current = current[0];
  }
  return current;
}

/** Rend une valeur d'exemple, ou `null` si aucun jeu d'essai n'en porte. */
export function exampleFor(path: string): string | null {
  for (const report of sampleReports()) {
    const value = valueAt(report, path);
    if (value === undefined || value === null) continue;
    // Le marqueur « non collecté » n'est pas un exemple de la valeur : c'est un
    // exemple de son absence, que la colonne « non collecté » dit déjà.
    if (typeof value === 'object' && !Array.isArray(value)) {
      if ((value as Record<string, unknown>).unknown === true) continue;
      continue;
    }
    if (Array.isArray(value)) {
      if (value.length === 0) continue;
      return truncate(value.map((item) => String(item)).join(', '));
    }
    return truncate(String(value));
  }
  return null;
}

function truncate(text: string): string {
  const flat = text.replace(/\s+/g, ' ').trim();
  return flat.length > 44 ? `${flat.slice(0, 43)}…` : flat;
}

/** Neutralise les caractères qui casseraient une cellule de tableau Markdown. */
function cell(text: string): string {
  return text.replace(/\|/g, '\\|').replace(/\n/g, ' ');
}

function osLabel(entry: FieldEntry): string {
  const annotation = annotationFor(entry.path);
  if (annotation === null) return '—';
  const targets: string[] = [];
  if (annotation.collector.linux !== null) targets.push('Linux');
  if (annotation.collector.windows !== null) targets.push('Windows');
  return targets.length === 0 ? 'aucun' : targets.join(', ');
}

/**
 * Le collecteur réellement appelé, et **pourquoi il n'y en a pas** le cas
 * échéant.
 *
 * La colonne disait « non collecté » de deux situations très différentes : un
 * scanner qui ne le fait pas encore, et un système qui ne l'expose pas. La
 * première est une dette, la seconde un fait — et les confondre fait ouvrir des
 * tâches pour combler ce qui n'a pas de fond.
 *
 * Quand la raison est connue, elle est écrite ici plutôt que laissée à deviner.
 */
function collectorLabel(entry: FieldEntry): string {
  const annotation = annotationFor(entry.path);
  if (annotation === null) return '—';
  const parts: string[] = [];
  if (annotation.collector.linux !== null) parts.push(`Linux : \`${annotation.collector.linux}\``);
  else if (annotation.undetectable?.linux !== undefined)
    parts.push(`Linux : impossible — ${annotation.undetectable.linux}`);
  if (annotation.collector.windows !== null)
    parts.push(`Windows : \`${annotation.collector.windows}\``);
  else if (annotation.undetectable?.windows !== undefined)
    parts.push(`Windows : impossible — ${annotation.undetectable.windows}`);
  return parts.length === 0 ? 'non collecté' : parts.join(' · ');
}

function privacyLabel(entry: FieldEntry): string {
  return PRIVACY_LABELS[annotationFor(entry.path)?.privacy ?? 'public'];
}

/**
 * Obligation réelle du champ.
 *
 * « Obligatoire » sans réserve ne vaut que pour les champs dont toute la chaîne
 * de parents est obligatoire. Ailleurs, l'obligation est **conditionnelle** :
 * `storage.disks[].device` n'existe que si `storage` a été collecté. Les
 * confondre ferait lire des centaines d'obligations là où le format en impose
 * quelques dizaines — et conclure qu'un rapport partiel est non conforme.
 */
function requirement(entry: FieldEntry): string {
  if (entry.optional) return 'facultatif';
  return entry.underOptional ? 'obligatoire si présent' : '**obligatoire**';
}

/** Table d'une section, une ligne par feuille. */
function renderSection(section: string, entries: readonly FieldEntry[]): string {
  const lines = [
    `### \`${section}\``,
    '',
    '| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |',
    '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |',
  ];

  const meanings = new Map<string, string>();
  for (const entry of entries) {
    const annotation = annotationFor(entry.path);
    if (annotation !== null) meanings.set(annotation.prefix, annotation.meaning);
    const example = exampleFor(entry.path);
    lines.push(
      `| \`${cell(entry.path)}\` | ${cell(entry.type)} | ${entry.unit ?? '—'} | ${requirement(
        entry,
      )} | ${entry.maybeUnknown ? 'oui' : 'non'} | ${
        example === null ? '—' : `\`${cell(example)}\``
      } | ${osLabel(entry)} | ${collectorLabel(entry)} | ${privacyLabel(entry)} | ${
        POSTGRES_PROJECTIONS[entry.path] === undefined
          ? '`raw` uniquement'
          : `\`${POSTGRES_PROJECTIONS[entry.path]}\``
      } |`,
    );
  }

  lines.push('', '**Sens des champs de cette section**', '');
  for (const [prefix, meaning] of meanings) {
    const annotation = annotationFor(prefix);
    const since = annotation === null ? '' : ` *(depuis le schéma ${annotation.since})*`;
    lines.push(`- \`${prefix}\` — ${meaning}${since}`);
  }

  return lines.join('\n');
}

/** Ensemble du catalogue, section par section, dans l'ordre du schéma. */
export function renderFieldReference(): string {
  const bySection = new Map<string, FieldEntry[]>();
  for (const entry of fieldCatalog()) {
    const section = sectionOf(entry.path);
    const bucket = bySection.get(section) ?? [];
    bucket.push(entry);
    bySection.set(section, bucket);
  }

  return [...bySection.entries()]
    .map(([section, entries]) => renderSection(section, entries))
    .join('\n\n');
}

/** Compte des champs, pour l'introduction du document. */
export function renderFieldSummary(): string {
  const entries = fieldCatalog();
  const sections = new Set(entries.map((entry) => sectionOf(entry.path)));
  const required = entries.filter((entry) => !entry.optional && !entry.underOptional).length;
  const conditional = entries.filter((entry) => !entry.optional && entry.underOptional).length;
  const restricted = entries.filter(
    (entry) => annotationFor(entry.path)?.privacy === 'restricted',
  ).length;
  const projected = entries.filter(
    (entry) => POSTGRES_PROJECTIONS[entry.path] !== undefined,
  ).length;

  return [
    `- **${entries.length} champs** répartis en **${sections.size} sections** de premier niveau.`,
    `- **${required}** sont obligatoires sans réserve ; **${conditional}** le sont seulement si leur section est collectée, et tous les autres peuvent être absents — une absence portant toujours son motif.`,
    `- **${restricted}** sont réservés au demandeur : stockés en clair, servis en clair à leur propriétaire, remplacés par un marqueur pour les autres.`,
    `- **${projected}** sont projetés en colonne PostgreSQL pour les agrégations ; les ${entries.length - projected} autres ne vivent que dans \`Scan.raw\`.`,
  ].join('\n');
}
