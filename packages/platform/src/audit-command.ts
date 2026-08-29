// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import {
  DIAGNOSTIC_LEVEL_PROFILES,
  type DiagnosticLevel,
  type LevelSection,
} from './diagnostic-levels.js';

/**
 * Générateur de commandes d'amorçage — **la seule source du produit**.
 *
 * Il en existait deux : une forme courte (`bootstrapCommand`) et une forme avec
 * options, recopiée dans l'interface web. Chaque évolution devait donc être
 * faite deux fois, et la seconde a fini par diverger. Tout ce qui compose une
 * commande SysAudit se décide désormais ici, et les pages ne font que
 * l'afficher.
 *
 * ## Le code de liaison voyage dans l'URL, pas en option
 *
 * Un code passé en option (`--claim`) oblige à quitter la forme courte :
 * `bash -s --` sous Linux, un bloc de script sous Windows — `irm … | iex` ne
 * transmettant aucun argument. C'est la commande que l'on ne veut pas afficher
 * dans l'espace d'un utilisateur connecté, alors même que c'est là qu'elle
 * servirait le plus.
 *
 * Le code part donc dans la chaîne de requête (`?link=…`), que l'API lit au
 * téléchargement et recopie dans le script qu'elle sert. La forme courte est
 * préservée, et la commande anonyme reste rigoureusement identique à ce qu'elle
 * était.
 */

/**
 * Alphabet des codes de liaison.
 *
 * `0`, `O`, `1`, `I` et `L` en sont absents : le code se recopie à la main dans
 * un terminal, et une confusion de caractères transformerait un échec de saisie
 * en soupçon de tentative d'usurpation. Il est repris tel quel de
 * `apps/api/src/auth.ts`, qui les tire — les deux côtés partagent désormais
 * cette constante plutôt que deux copies qui se ressemblaient.
 */
export const LINK_CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/** Longueur du code, séparateurs et préfixe exclus. */
export const LINK_CODE_LENGTH = 8;

/**
 * Préfixe d'affichage.
 *
 * Il ne fait pas partie du code : `normalizeLinkCode` le retire, et l'API ne
 * stocke que les huit caractères. Il existe pour qu'un code aperçu dans un
 * historique de shell ou sur une capture d'écran se reconnaisse immédiatement
 * comme un jeton SysAudit — donc comme quelque chose à révoquer.
 */
export const LINK_CODE_PREFIX = 'SA-';

/**
 * Les huit caractères du code, préfixe, casse et séparateurs écartés.
 *
 * Cette fonction ne dit pas si le code est **valide** : `SA-0000-0000` en
 * ressort inchangé alors que `0` n'appartient pas à l'alphabet. C'est
 * `isValidLinkCode` qui tranche, sur le résultat de celle-ci.
 */
function lettersOf(value: string): string {
  const cleaned = value.toUpperCase().replace(/[^A-Z0-9]/g, '');
  return cleaned.startsWith('SA') && cleaned.length === LINK_CODE_LENGTH + 2
    ? cleaned.slice(2)
    : cleaned;
}

/**
 * Un code tel que l'API le reconnaîtra.
 *
 * Casse, séparateurs et préfixe sont tolérés : `sa7k4mp2q9`, `SA-7K4M-P2Q9` et
 * `7K4M P2Q9` désignent le même code. Faire échouer les deux premiers serait
 * pinailler sur une saisie correcte.
 */
export function isValidLinkCode(value: string): boolean {
  const letters = lettersOf(value);
  if (letters.length !== LINK_CODE_LENGTH) return false;
  return [...letters].every((character) => LINK_CODE_ALPHABET.includes(character));
}

/**
 * Forme canonique `XXXX-XXXX`, celle que stocke et compare l'API.
 *
 * Le préfixe d'affichage n'y figure pas : il appartient à la présentation, et
 * l'inclure ici ferait dépendre l'empreinte stockée d'un choix d'habillage.
 */
export function normalizeLinkCode(value: string): string {
  const letters = lettersOf(value);
  return letters.length === LINK_CODE_LENGTH
    ? `${letters.slice(0, 4)}-${letters.slice(4)}`
    : letters;
}

/** Forme affichée et collée dans une commande : `SA-XXXX-XXXX`. */
export function formatLinkCode(value: string): string {
  const canonical = normalizeLinkCode(value);
  return canonical === '' ? '' : `${LINK_CODE_PREFIX}${canonical}`;
}

/**
 * Machine visée par la commande.
 *
 * `proxmox` produit **exactement** la commande de `linux`, et c'est voulu : un
 * hyperviseur Proxmox est une Debian, le scanner Linux s'y installe pareil et
 * détecte seul qu'il tourne sur un nœud PVE — c'est lui qui pose
 * `scannerKind: 'proxmox'` dans le rapport, pas la ligne de commande.
 */
export type AuditCommandTarget = 'windows' | 'linux' | 'proxmox';

export interface AuditCommandOptions {
  readonly target: AuditCommandTarget;
  readonly level: DiagnosticLevel;
  /**
   * Code de liaison à un compte. Usage unique, durée de vie courte.
   *
   * Il part dans l'URL, jamais en option : voir l'en-tête de ce fichier. Un
   * code mal formé est **ignoré** ici — la commande produite reste anonyme
   * plutôt que d'emporter une valeur que l'API refusera.
   */
  readonly link?: string;
  /** Répertorier l'audit dans la vitrine. L'envoi, lui, est toujours acquis. */
  readonly publish?: boolean;
  /** Durée d'observation, en secondes. `0` désactive. */
  readonly monitorSeconds?: number;
  /** Sections à écarter, déclarées comme telles dans le rapport. */
  readonly skip?: readonly LevelSection[];
}

/**
 * Les options ajoutées à celles de l'amorçage.
 *
 * Le niveau n'en fait pas partie : il voyage dans le **chemin** de l'URL
 * (`/audit/l/f`), que l'amorçage traduit lui-même. Le code de liaison non plus :
 * il voyage dans la **chaîne de requête**. Les passer aussi en option ferait
 * deux sources pour la même décision.
 */
export function auditCommandFlags(options: AuditCommandOptions): readonly string[] {
  const windows = options.target === 'windows';
  const out: string[] = [];

  for (const section of options.skip ?? []) {
    out.push(windows ? `-Skip ${section}` : `--skip ${section}`);
  }

  // Les deux scanners observent la machine dans la durée, sous des noms
  // différents : `--monitor` en Bash, `-Monitor` en PowerShell.
  if ((options.monitorSeconds ?? 0) > 0) {
    out.push(
      windows ? `-Monitor ${options.monitorSeconds}` : `--monitor ${options.monitorSeconds}`,
    );
  }

  if (options.publish === true) out.push(windows ? '-Public' : '--public');

  return out;
}

/** L'URL d'amorçage seule, sans le shell qui l'entoure. */
export function auditCommandUrl(options: AuditCommandOptions, apiBaseUrl: string): string {
  const base = apiBaseUrl.replace(/\/+$/, '');
  const alias = DIAGNOSTIC_LEVEL_PROFILES[options.level].urlAlias;
  const root = options.target === 'windows' ? '/audit/w' : '/audit/l';
  const path = alias === '' ? root : `${root}/${alias}`;
  const link = options.link ?? '';

  return isValidLinkCode(link) ? `${base}${path}?link=${formatLinkCode(link)}` : `${base}${path}`;
}

/**
 * La commande complète, prête à coller.
 *
 * Deux règles gouvernent sa forme, et elles ne sont pas cosmétiques.
 *
 * - **L'URL est protégée par des guillemets dès qu'elle porte une chaîne de
 *   requête.** `?` est un caractère de globbing : zsh — le shell par défaut de
 *   macOS et de bien des postes Linux — **échoue** sur `curl … /audit/l?link=X`
 *   avec « no matches found », là où bash le laisse passer par tolérance. Une
 *   commande qui marche chez son auteur et pas chez son destinataire est pire
 *   qu'une commande verbeuse.
 * - **Le tube est entouré d'espaces.** Il était collé à l'URL — `…/audit/l|bash`,
 *   `"…?link=SA-ABCD-EFGH"|bash` — et se lisait alors comme faisant partie de
 *   l'adresse. Deux utilisateurs l'ont échappé pour cette raison, et l'échec
 *   qui suit ne nomme jamais la cause :
 *
 *   ```text
 *   curl -fsSL https://sysaudit.me/audit/l\|bash                    → 404
 *   curl -fsSL "https://sysaudit.me/audit/l/f?link=SA-…"\|bash      → 400
 *   ```
 *
 *   L'antislash annule le tube : `|bash` part **dans l'URL**, en fin de chemin
 *   dans le premier cas, collé au code de liaison dans le second. Le serveur
 *   répond correctement à une adresse qui n'existe pas et à un code invalide ;
 *   rien ne dit que la commande a été mal recopiée. Espacer le tube n'est donc
 *   pas de la mise en forme : c'est ce qui le montre comme un opérateur de shell
 *   plutôt que comme la fin de l'adresse. C'est aussi la forme qu'emploient
 *   `rustup`, `nvm` et `homebrew`, donc celle que l'œil attend.
 * - **Sans option ni code, la forme reste la forme courte** — un `curl`, une
 *   URL, un tube. Elle gagne deux espaces, et rien d'autre.
 */
export function auditCommand(options: AuditCommandOptions, apiBaseUrl: string): string {
  const url = auditCommandUrl(options, apiBaseUrl);
  // Les guillemets ne servent que si l'URL porte une chaîne de requête ; les
  // ajouter systématiquement modifierait la commande anonyme sans raison.
  const quoted = url.includes('?') ? `"${url}"` : url;
  const suffix = auditCommandFlags(options).join(' ');

  if (options.target === 'windows') {
    return suffix === ''
      ? `irm ${quoted} | iex`
      : `& ([scriptblock]::Create((irm ${quoted}))) ${suffix}`;
  }

  return suffix === ''
    ? `curl -fsSL ${quoted} | bash`
    : `curl -fsSL ${quoted} | bash -s -- ${suffix}`;
}

/**
 * Commande d'amorçage à copier, pour un OS et un niveau.
 *
 * Forme courte, sans option : c'est celle que proposent les pages publiques.
 * Elle délègue à `auditCommand` — le chemin d'URL n'est plus réécrit nulle
 * part ailleurs.
 */
export function bootstrapCommand(
  target: 'windows' | 'linux',
  apiBaseUrl: string,
  level: DiagnosticLevel,
  link?: string,
): string {
  return auditCommand({ target, level, ...(link === undefined ? {} : { link }) }, apiBaseUrl);
}
