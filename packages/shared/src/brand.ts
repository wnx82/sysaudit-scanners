// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

/**
 * Le nom du produit, à un seul endroit.
 *
 * ## Pourquoi une constante pour une chaîne de onze caractères
 *
 * Le nom vivait en littéral dans une vingtaine de fichiers : titre HTML,
 * Open Graph, en-tête de PDF, signature d'e-mail, commentaire d'export CSV,
 * description OpenAPI. Le renommer revenait à les retrouver tous — et
 * l'expérience de ce dépôt est qu'on en oublie : c'est ainsi qu'un pied de page
 * annonce encore l'ancien nom six mois après une bascule.
 *
 * La constante rend l'oubli impossible dans un sens (on ne peut plus manquer une
 * surface déjà branchée) et visible dans l'autre (un littéral qui réapparaît se
 * repère à la revue).
 *
 * ## Ce qu'elle ne couvre pas, délibérément
 *
 * Les **identifiants techniques** gardent `SysAudit` sans point : noms de
 * paquets `@sysaudit/*`, préfixes de variables d'environnement, `User-Agent`
 * OAuth, et surtout le répertoire de travail du scanner Windows
 * (`%LOCALAPPDATA%\SysAudit`). Renommer ce dernier n'apporterait rien et
 * orphelinerait les répertoires déjà créés sur les machines auditées.
 *
 * La règle est simple : **ce qu'un humain lit porte le nom complet ; ce qu'une
 * machine compare garde l'ancien.**
 *
 * ## Rapport avec l'internationalisation
 *
 * Ce fichier est le premier pas du chantier i18n, et le moins coûteux : un nom
 * de marque ne se traduit pas, mais il montre où doivent aller les textes qui,
 * eux, se traduiront. Les phrases construites autour de lui sont écrites en
 * entier plutôt que concaténées morceau par morceau — une phrase assemblée à
 * l'exécution est une phrase intraduisible.
 */

/** Nom visible du produit. Tout ce qu'un utilisateur lit porte celui-ci. */
export const BRAND_NAME = 'SysAudit.me';

/**
 * Nom court, sans domaine, pour les identifiants techniques.
 *
 * Exporté pour que les rares endroits qui en ont besoin le désignent
 * explicitement, plutôt que d'écrire un littéral qu'on prendrait plus tard pour
 * une surface oubliée.
 */
export const BRAND_SLUG = 'SysAudit';

/**
 * Promesse du produit, en une ligne.
 *
 * « Collecte non destructive par défaut », et non « lecture seule » tout court :
 * les niveaux Complète et Poussée peuvent installer un outil avec accord, et le
 * second charge volontairement la machine. Promettre la lecture seule sans
 * réserve était faux pour la moitié des niveaux — et c'est le genre de promesse
 * qu'on ne découvre fausse qu'après l'avoir crue.
 *
 * Ce que fait réellement le niveau choisi est affiché à côté de ce texte, par
 * `DIAGNOSTIC_LEVEL_PROFILES`.
 */
export const BRAND_TAGLINE = 'Audit et diagnostic système — collecte non destructive par défaut.';

/**
 * Première année de publication. Le point de départ de la mention de droit
 * d'auteur, et la seule date qui ne changera plus.
 */
export const COPYRIGHT_SINCE = 2026;

/**
 * Titulaire affiché.
 *
 * La **marque**, et non l'entreprise qui l'édite. Ce n'est pas un oubli : les
 * surfaces produit ne portent aucune identité d'éditeur, sur décision du
 * propriétaire du projet, et un test le vérifie en relisant les sources
 * (`apps/web/src/lib/identity.test.ts`). L'identité complète a son endroit —
 * le fichier `LICENSE`, qui fait foi juridiquement et que personne ne confond
 * avec un pied de page.
 */
export const COPYRIGHT_HOLDER = BRAND_SLUG;

/**
 * Mention de droit d'auteur, pour une année donnée.
 *
 * ## Pourquoi l'année est un paramètre
 *
 * Écrire `new Date().getFullYear()` ici paraîtrait plus simple et serait faux
 * deux fois.
 *
 * D'abord parce qu'un **rapport doit rester reproductible** : rendu deux fois,
 * il doit produire le même document, or une horloge lue au rendu changerait la
 * page au passage d'une nouvelle année. Le rendu passe donc l'année de
 * production du rapport — un document daté de 2026 porte 2026, quelle que soit
 * la date à laquelle on le rouvre.
 *
 * Ensuite parce que dans une page compilée à l'avance, l'horloge serait celle
 * de la **machine de compilation** : c'est déjà arrivé dans ce dépôt avec la
 * politique de sécurité du contenu, figée au build avec les valeurs d'un autre
 * environnement. Le site passe donc l'année de la requête, qu'il lit lui-même.
 *
 * ## Ce que rend la fonction
 *
 * `© 2026 SysAudit` la première année, `© 2026–2028 SysAudit` ensuite. Une
 * année antérieure au début de publication est ramenée à celui-ci : mieux vaut
 * une mention juste qu'une plage inventée par une horloge déréglée.
 */
export function copyrightNotice(year: number): string {
  const end = Number.isFinite(year) ? Math.max(Math.trunc(year), COPYRIGHT_SINCE) : COPYRIGHT_SINCE;
  // Demi-cadratin et non trait d'union : c'est une plage, pas un mot composé.
  const span = end > COPYRIGHT_SINCE ? `${COPYRIGHT_SINCE}–${end}` : `${COPYRIGHT_SINCE}`;
  return `© ${span} ${COPYRIGHT_HOLDER}`;
}
