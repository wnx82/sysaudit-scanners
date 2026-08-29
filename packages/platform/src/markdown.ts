// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import {
  CAPABILITY_LABELS,
  CLIENT_KINDS,
  CLIENT_LABELS,
  COMPATIBILITY_TARGETS,
  clientSupport,
  SUPPORT_LEVELS,
  SUPPORT_LEVEL_LABELS,
  SUPPORT_LEVEL_SYMBOLS,
  type CapabilityKey,
  type CompatibilityTarget,
} from './compatibility.js';

/**
 * Projection Markdown de la matrice de compatibilité.
 *
 * La documentation n'est plus saisie : elle est rendue depuis
 * `compatibility.ts`. Deux tableaux ne peuvent donc plus diverger, et un test
 * échoue si un fichier Markdown a été modifié à la main.
 */

/** Cellule d'un domaine : symbole, plus la précision éventuelle. */
export function cellFor(target: CompatibilityTarget, capability: CapabilityKey): string {
  const support = target.capabilities[capability];
  const symbol = SUPPORT_LEVEL_SYMBOLS[support.level];
  return support.note === undefined ? symbol : `${symbol} ${support.note}`;
}

/** Lignes brutes de la matrice, avant mise en forme. */
export function compatibilityRows(
  columns: readonly CapabilityKey[],
): readonly (readonly string[])[] {
  return COMPATIBILITY_TARGETS.map((target) => [
    target.label,
    target.scannerLabel,
    ...columns.map((capability) => cellFor(target, capability)),
  ]);
}

export function compatibilityHeaders(columns: readonly CapabilityKey[]): readonly string[] {
  return ['OS', 'Scanner', ...columns.map((capability) => CAPABILITY_LABELS[capability])];
}

/**
 * Rend un tableau Markdown à colonnes alignées.
 *
 * La largeur se mesure en points de code et non en octets : les symboles de la
 * matrice sont hors ASCII, et compter des octets décalerait chaque ligne. Cet
 * alignement reste indicatif — Prettier réaligne à sa façon, et les tests
 * comparent le contenu des cellules, jamais les espaces.
 */
export function renderMarkdownTable(
  headers: readonly string[],
  rows: readonly (readonly string[])[],
): string {
  const widths = headers.map((header, index) =>
    Math.max([...header].length, ...rows.map((row) => [...(row[index] ?? '')].length)),
  );

  const pad = (text: string, index: number): string =>
    text + ' '.repeat(Math.max(0, (widths[index] ?? 0) - [...text].length));

  const line = (cells: readonly string[]): string =>
    `| ${cells.map((cell, index) => pad(cell, index)).join(' | ')} |`;

  const separator = `| ${widths.map((width) => '-'.repeat(Math.max(3, width))).join(' | ')} |`;

  return [line(headers), separator, ...rows.map((row) => line(row))].join('\n');
}

export function renderCompatibilityTable(columns: readonly CapabilityKey[]): string {
  return renderMarkdownTable(compatibilityHeaders(columns), compatibilityRows(columns));
}

/** Légende des symboles, elle aussi dérivée de la source structurée. */
export function renderLegend(): string {
  return SUPPORT_LEVELS.map(
    (level) => `- ${SUPPORT_LEVEL_SYMBOLS[level]} ${SUPPORT_LEVEL_LABELS[level]}`,
  ).join('\n');
}

/**
 * Ce que les façades installables savent faire, cible par cible.
 *
 * Tableau distinct de la matrice de collecte, et non colonnes de plus : les deux
 * répondent à des questions différentes, et les mêler ferait lire « le scanner
 * collecte » là où il faut lire « je peux installer quelque chose ».
 */
export function renderClientTable(): string {
  const headers = ['OS', ...CLIENT_KINDS.map((kind) => CLIENT_LABELS[kind])];
  const rows = COMPATIBILITY_TARGETS.map((target) => [
    target.label,
    ...CLIENT_KINDS.map((kind) => {
      const support = clientSupport(target.id, kind);
      return support === null ? SUPPORT_LEVEL_SYMBOLS.ABSENT : SUPPORT_LEVEL_SYMBOLS[support.level];
    }),
  ]);
  return renderMarkdownTable(headers, rows);
}

/**
 * Le motif de chaque case, en clair.
 *
 * **Sans ce bloc, le tableau ne vaudrait rien.** Un symbole dit qu'une façade
 * n'est pas disponible ; il ne dira jamais pourquoi, ni ce qu'il faudrait pour
 * qu'elle le soit. C'est le même raisonnement que pour les capacités partielles,
 * et la même conclusion : un motif obligatoire n'a de valeur que publié.
 *
 * Les cases validées portent leur **date d'exécution**. C'est ce qui distingue
 * une case cochée parce que le code compile d'une case cochée parce que le
 * programme a tourné.
 */
export function renderClientReasons(): string {
  /*
   * Les cibles sont **regroupées par motif identique**.
   *
   * Sept lignes Linux répétant mot pour mot la même phrase noyaient les deux
   * qui apprennent quelque chose — Windows 7 et le Raspberry Pi. Un document
   * qu'on cesse de lire ne dit plus rien, quelle que soit son exactitude.
   */
  const groupes = new Map<string, { readonly cibles: string[]; readonly lignes: string[] }>();

  for (const target of COMPATIBILITY_TARGETS) {
    const lignes: string[] = [];
    for (const kind of CLIENT_KINDS) {
      const support = clientSupport(target.id, kind);
      if (support === null) continue;
      const date = support.level === 'VALIDATED' ? ` (exécuté le ${support.verifiedOn})` : '';
      lignes.push(
        `- **${CLIENT_LABELS[kind]}** — ${SUPPORT_LEVEL_SYMBOLS[support.level]} ${SUPPORT_LEVEL_LABELS[support.level]}${date} : ${support.reason}`,
      );
    }
    if (lignes.length === 0) continue;

    const cle = lignes.join('|');
    const groupe = groupes.get(cle);
    if (groupe === undefined) groupes.set(cle, { cibles: [target.label], lignes });
    else groupe.cibles.push(target.label);
  }

  return [...groupes.values()]
    .map((groupe) => [`**${groupe.cibles.join(' · ')}**`, '', ...groupe.lignes].join('\n'))
    .join('\n\n');
}

/**
 * Ce que chaque 🟠 laisse de côté, cible par cible.
 *
 * **Sans ce bloc, le niveau `PARTIAL` ne servirait à rien.** Un symbole dit
 * qu'il manque quelque chose ; il ne dira jamais quoi. Or c'est exactement
 * l'information qui manquait au lecteur d'un ✅ sur la Sécurité de Windows — et
 * le motif obligatoire n'a de valeur que s'il est publié.
 *
 * Rendu vide quand aucune capacité n'est partielle : une section « ce qui
 * manque » vide se lit mal, mieux vaut qu'elle disparaisse.
 */
export function renderPartialCaveats(columns: readonly CapabilityKey[]): string {
  const blocks: string[] = [];

  for (const target of COMPATIBILITY_TARGETS) {
    const partial = columns
      .map((capability) => ({ capability, support: target.capabilities[capability] }))
      .filter((entry) => entry.support.level === 'PARTIAL');
    if (partial.length === 0) continue;

    blocks.push(
      `**${target.label}**\n\n` +
        partial
          .map(
            (entry) =>
              `- ${SUPPORT_LEVEL_SYMBOLS.PARTIAL} **${CAPABILITY_LABELS[entry.capability]}** — ${entry.support.caveat}`,
          )
          .join('\n'),
    );
  }

  return blocks.join('\n\n');
}

/**
 * Extrait les cellules d'un tableau Markdown.
 *
 * Sert aux tests de synchronisation : ils comparent des cellules, jamais la
 * mise en forme, pour rester insensibles au réalignement de Prettier.
 */
export function parseMarkdownTable(markdown: string): readonly (readonly string[])[] {
  return markdown
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.startsWith('|') && line.endsWith('|'))
    .map((line) =>
      line
        .slice(1, -1)
        .split('|')
        .map((cell) => cell.trim()),
    )
    .filter((cells) => !cells.every((cell) => /^-+$/.test(cell)));
}
