// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

/**
 * Les routes du site qui portent des données d'audit.
 *
 * ## Pourquoi cette liste vit ici
 *
 * Elle gouvernait déjà trois choses côté site : l'en-tête `X-Robots-Tag` de
 * `next.config.ts`, les exclusions de `robots.txt`, et la garantie qu'aucune
 * d'elles n'entre dans le plan du site. Une quatrième s'est ajoutée — l'audit
 * de référencement, qui tourne dans l'API et doit reconnaître une route privée
 * annoncée par erreur.
 *
 * L'API ne peut pas importer depuis `apps/web` : les dépendances de ce dépôt
 * vont des paquets vers les applications, jamais l'inverse. Recopier la liste
 * aurait fonctionné le premier jour et divergé le second — et une divergence
 * ici ne se voit pas : elle laisse simplement passer une adresse de plus.
 *
 * ## Ce que cette liste n'est pas
 *
 * **Ce n'est pas une protection.** `noindex` empêche un moteur d'indexer, pas
 * un visiteur de lire. L'autorisation se décide côté API, avant sérialisation
 * (`redact.ts`, `mayReadInFull`), et resterait nécessaire même si cette liste
 * n'existait pas.
 */

/**
 * Préfixes des routes qui ne doivent jamais être indexées, ni suivies, ni
 * archivées : chacune peut nommer une machine réelle.
 */
export const PRIVATE_ROUTE_PREFIXES: readonly string[] = [
  '/id',
  '/r',
  '/s',
  '/compare',
  '/machines',
  '/admin',
  /*
   * Les relais du site vers l'API — comptes, administration, exports.
   *
   * Ils vivaient sous `/api/`, préfixe que l'API revendique aussi : un relais
   * inverse configuré avec `handle /api/*` les lui envoyait, et elle répondait
   * `{"error":"NOT_FOUND"}` à des chemins qu'elle n'a jamais servis. Le préfixe
   * `/relais/` n'appartient qu'au site, et rend la collision impossible.
   */
  '/relais',
  /*
   * `/audit/*` sert les scripts d'amorçage. Ils appartiennent à l'API, que le
   * site relaie quand le relais inverse ne le fait pas : un script portant un
   * jeton d'envoi n'a rien à faire dans un index.
   */
  '/audit',
];

/** Le chemin porte-t-il des données d'audit ? */
export function isPrivateRoute(pathname: string): boolean {
  return PRIVATE_ROUTE_PREFIXES.some(
    (prefix) => pathname === prefix || pathname.startsWith(`${prefix}/`),
  );
}
