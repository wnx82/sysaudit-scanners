// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { renderMarkdownTable } from './markdown.js';
import {
  PACKAGE_FAMILIES,
  PACKAGE_FAMILY_COMMANDS,
  PACKAGE_FAMILY_LABELS,
  TOOL_APPLICABILITY_LABELS,
  TOOL_DEPENDENCIES,
  TOOL_REQUIREMENT_LABELS,
  toolsForScanner,
  type ToolScanner,
} from './tool-dependencies.js';

/**
 * Projection Markdown de la table des dépendances externes.
 *
 * Même dispositif que la compatibilité et les niveaux : la documentation est
 * rendue, jamais saisie. Un outil retiré du scanner disparaît donc de la
 * documentation le jour même, et non le jour où quelqu'un s'en aperçoit.
 */

/**
 * Ce que chaque outil apporte, ce qu'il coûte, et ce qui se passe sans lui.
 *
 * La colonne « Exigence » porte aussi la condition matérielle, quand il y en a
 * une. Sans elle, un lecteur sur x86 chercherait pourquoi `vcgencmd` ne lui est
 * jamais proposé — et pourrait l'installer à la main, pour rien.
 */
export function renderToolTable(scanner: ToolScanner): string {
  const headers = ['Outil', 'Débloque', 'Exigence', 'Privilèges', 'Licence amont', 'Sans lui'];
  const rows = toolsForScanner(scanner).map((tool) => [
    `\`${tool.id}\`${tool.label === tool.id ? '' : ` (${tool.label})`}`,
    tool.unlocks,
    tool.appliesWhen === undefined
      ? TOOL_REQUIREMENT_LABELS[tool.requirement]
      : `${TOOL_REQUIREMENT_LABELS[tool.requirement]} — ${TOOL_APPLICABILITY_LABELS[tool.appliesWhen]}`,
    tool.privileges === 'root' ? 'root / administrateur' : 'aucun',
    tool.licence,
    tool.fallback,
  ]);
  return renderMarkdownTable(headers, rows);
}

/** Comment installer ce qui manque, par famille de distribution. */
export function renderInstallTable(): string {
  const installable = TOOL_DEPENDENCIES.filter(
    (tool) => tool.packages !== undefined && Object.keys(tool.packages).length > 0,
  );

  const headers = ['Outil', ...PACKAGE_FAMILIES.map((family) => PACKAGE_FAMILY_LABELS[family])];
  const rows = installable.map((tool) => [
    `\`${tool.id}\``,
    ...PACKAGE_FAMILIES.map((family) => {
      const packageName = tool.packages?.[family];
      return packageName === undefined ? '—' : `\`${packageName}\``;
    }),
  ]);
  return renderMarkdownTable(headers, rows);
}

/** Commande d'installation de chaque famille, sans les noms de paquets. */
export function renderPackageCommands(): string {
  return PACKAGE_FAMILIES.map(
    (family) =>
      `- **${PACKAGE_FAMILY_LABELS[family]}** — \`sudo ${PACKAGE_FAMILY_COMMANDS[family]} <paquet>\``,
  ).join('\n');
}

/**
 * Ce qu'un audit perd, outil manquant par outil manquant.
 *
 * Trié par exigence : ce qui coûte le plus cher d'abord. C'est la seule liste
 * qu'un utilisateur pressé lira.
 */
export function renderRecommendedTools(): string {
  return TOOL_DEPENDENCIES.filter((tool) => tool.requirement === 'recommended')
    .map((tool) => `- \`${tool.id}\` — ${tool.unlocks}`)
    .join('\n');
}
