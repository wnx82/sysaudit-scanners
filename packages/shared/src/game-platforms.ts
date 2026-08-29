// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

/**
 * Les plateformes de jeu que SysAudit sait nommer.
 *
 * ## Pourquoi cette liste vit ici
 *
 * Elle existait en deux exemplaires : l'API validait ce qu'elle acceptait, le
 * site proposait ce qu'on pouvait choisir, et les deux listes étaient tenues à
 * la main. Une divergence n'y produit pas d'erreur bruyante — elle offre un
 * choix que l'API refusera, ou en cache un qu'elle accepterait.
 *
 * ## Les marques, et ce que ce module refuse de faire
 *
 * Il n'y a **aucun logo** ici, et ce n'est pas un oubli. Les emblèmes de Steam,
 * Xbox ou PlayStation sont des marques déposées : les vendre dans le dépôt
 * demanderait de suivre une licence par marque, chacune avec ses conditions
 * d'usage, pour une vignette de seize pixels. Le dépôt ne porte pas non plus de
 * bibliothèque d'icônes dont on pourrait les tirer.
 *
 * Chaque plateforme reçoit donc un **monogramme** et une couleur d'accent :
 * deux lettres suffisent à distinguer neuf entrées dans une liste, et rien de ce
 * qui est dessiné n'appartient à personne. Si un pack d'icônes sous licence
 * compatible entre un jour dans le dépôt, seul ce fichier changera.
 */

export const GAME_PLATFORMS = [
  'steam',
  'discord',
  'battlenet',
  'riot',
  'epic',
  'gog',
  'ubisoft',
  'ea',
  'xbox',
  'playstation',
  'nintendo',
  'other',
] as const;

export type GamePlatform = (typeof GAME_PLATFORMS)[number];

export const GAME_PLATFORM_LABELS: Readonly<Record<GamePlatform, string>> = {
  steam: 'Steam',
  discord: 'Discord',
  battlenet: 'Battle.net',
  riot: 'Riot Games',
  epic: 'Epic Games',
  gog: 'GOG',
  ubisoft: 'Ubisoft Connect',
  ea: 'EA',
  xbox: 'Xbox / Microsoft',
  playstation: 'PlayStation Network',
  nintendo: 'Nintendo',
  other: 'Autre',
};

/**
 * Un monogramme, une couleur.
 *
 * La couleur n'est pas celle de la marque : elle sert à séparer les entrées
 * d'une liste, pas à imiter une identité visuelle. Le contraste avec du texte
 * blanc est vérifié pour chacune — une pastille illisible ne distingue rien.
 */
export interface GamePlatformMark {
  /** Une ou deux lettres. Au-delà, la pastille cesse d'être une pastille. */
  readonly mark: string;
  /** Couleur de fond de la pastille, en hexadécimal. */
  readonly accent: string;
}

export const GAME_PLATFORM_MARKS: Readonly<Record<GamePlatform, GamePlatformMark>> = {
  steam: { mark: 'St', accent: '#1b2838' },
  discord: { mark: 'Dc', accent: '#4a54b3' },
  battlenet: { mark: 'Bn', accent: '#00558c' },
  riot: { mark: 'Ri', accent: '#a8332f' },
  epic: { mark: 'Ep', accent: '#2f2f2f' },
  gog: { mark: 'Go', accent: '#6b2f7a' },
  ubisoft: { mark: 'Ub', accent: '#0a5fa8' },
  ea: { mark: 'EA', accent: '#3a3a3a' },
  xbox: { mark: 'Xb', accent: '#1a6b2a' },
  playstation: { mark: 'Ps', accent: '#123a94' },
  nintendo: { mark: 'Ni', accent: '#a02020' },
  other: { mark: '··', accent: '#4a4a4a' },
};

export function isGamePlatform(value: unknown): value is GamePlatform {
  return typeof value === 'string' && (GAME_PLATFORMS as readonly string[]).includes(value);
}

/**
 * Le monogramme d'une plateforme, connue ou non.
 *
 * Une plateforme inconnue — une valeur ancienne restée en base, un
 * renommage — reçoit celui d'`other` plutôt que rien : une pastille vide se
 * lirait comme un défaut d'affichage.
 */
export function gamePlatformMark(platform: string): GamePlatformMark {
  return isGamePlatform(platform) ? GAME_PLATFORM_MARKS[platform] : GAME_PLATFORM_MARKS.other;
}

/**
 * Le nom lisible d'une plateforme.
 *
 * `other` porte le libellé saisi par l'utilisateur : sans lui, la liste
 * vieillirait mal et personne ne saurait où chercher.
 */
export function gamePlatformLabel(platform: string, label: string | null): string {
  if (platform === 'other') return label ?? GAME_PLATFORM_LABELS.other;
  return isGamePlatform(platform) ? GAME_PLATFORM_LABELS[platform] : platform;
}
