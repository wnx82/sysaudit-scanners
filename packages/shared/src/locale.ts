// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

/**
 * La langue du produit, à un seul endroit.
 *
 * ## Ce que ce fichier est, et ce qu'il n'est pas
 *
 * **Ce n'est pas de l'internationalisation.** Le produit est monolingue et le
 * reste : il n'y a ni catalogue de traductions, ni sélecteur de langue, ni
 * négociation de contenu. Prétendre le contraire serait annoncer une capacité
 * qui n'existe pas — ce que ce dépôt refuse partout ailleurs.
 *
 * C'est le travail préparatoire, et seulement lui : rassembler ce qui devra
 * changer le jour où la traduction arrivera, pour qu'elle ne commence pas par
 * une chasse à travers trente fichiers.
 *
 * ## Pourquoi maintenant plutôt qu'au moment venu
 *
 * L'étiquette `fr-BE` était écrite en dur dans une dizaine d'appels à
 * `toLocaleString`, plus `lang="fr"` sur `<html>` et `fr_BE` en Open Graph —
 * trois orthographes de la même information, qu'aucun test ne reliait. Une
 * traduction future en aurait manqué au moins une, et l'oubli se serait vu là
 * où on regarde le moins : une date au format belge dans une page anglaise.
 *
 * La dette i18n ne se rembourse pas d'un coup ; elle cesse au moins de croître.
 *
 * ## La règle en attendant
 *
 * Un texte destiné à un utilisateur s'écrit **en entier**, jamais assemblé à
 * l'exécution. `« Envoyé le » + date` semble anodin et ne l'est pas : l'ordre
 * des syntagmes change d'une langue à l'autre, et une phrase concaténée ne se
 * traduit pas — elle se réécrit.
 */

/**
 * Langue et région du produit, au format BCP 47.
 *
 * `fr-BE` et non `fr-FR` : les formats de date et de nombre diffèrent, et
 * l'exploitant comme ses premiers utilisateurs sont belges.
 */
export const DEFAULT_LOCALE = 'fr-BE';

/**
 * Valeur de l'attribut `lang` de `<html>`.
 *
 * La langue seule, sans région : c'est ce que lisent les lecteurs d'écran pour
 * choisir une voix, et la région n'y change rien. Dérivée plutôt que réécrite —
 * deux constantes indépendantes divergent tôt ou tard.
 */
export const HTML_LANG = DEFAULT_LOCALE.split('-')[0] ?? 'fr';

/**
 * Étiquette Open Graph, qui veut des tirets bas là où BCP 47 veut des tirets.
 *
 * La conversion est mécanique et vit ici, pour la même raison que le reste :
 * elle était recopiée à la main dans les métadonnées du site.
 */
export const OG_LOCALE = DEFAULT_LOCALE.replace('-', '_');
