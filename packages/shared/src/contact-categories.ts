// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

/**
 * De quoi parle un message de contact.
 *
 * ## Pourquoi une catégorie, et pourquoi celle-ci
 *
 * Le formulaire ne demandait qu'un sujet libre. Une boîte de contact triée à la
 * main marche tant qu'elle reçoit trois messages par semaine, et cesse de
 * marcher exactement au moment où elle devient utile.
 *
 * La liste est **courte et fermée**. Une taxonomie à quinze entrées ne trie
 * rien : personne ne sait plus dans laquelle ranger son message, et tout finit
 * dans « autre ». Sept familles, dont une qui appelle une obligation légale.
 *
 * ## `privacy` n'est pas une catégorie comme les autres
 *
 * Une demande relative aux données personnelles ouvre un délai de réponse
 * réglementaire. La nommer permet de la voir arriver ; la noyer dans « autre »
 * garantit qu'on la découvrira en retard.
 *
 * ## Pourquoi ce module vit dans le paquet partagé
 *
 * L'API normalise ce qu'elle reçoit ; le site propose ce qu'on peut choisir. Une
 * liste tenue à la main des deux côtés offrirait un choix que l'API rangerait
 * dans « autre » sans rien dire — l'utilisateur aurait catégorisé son message,
 * et la boîte de réception ne le saurait pas.
 *
 * ## Ce que la catégorie ne fait pas
 *
 * Elle ne route rien, ne priorise rien et ne déclenche aucun automatisme. Elle
 * dit ce que l'auteur pense de son propre message — c'est une déclaration, pas
 * un classement vérifié, et l'exploitant reste libre de la corriger.
 */

export const CONTACT_CATEGORIES = [
  'general',
  'audit',
  'bug',
  'suggestion',
  'professional',
  'privacy',
  'other',
] as const;

export type ContactCategory = (typeof CONTACT_CATEGORIES)[number];

export const CONTACT_CATEGORY_LABELS: Readonly<Record<ContactCategory, string>> = {
  general: 'Question générale',
  audit: 'Problème sur un audit',
  bug: 'Anomalie du produit',
  suggestion: 'Suggestion',
  professional: 'Demande professionnelle',
  privacy: 'Protection des données',
  other: 'Autre',
};

/**
 * Ramène une valeur reçue à une catégorie connue.
 *
 * Une valeur inconnue devient `other`, et non une erreur : refuser un message
 * parce que le champ le moins important du formulaire a été recopié de travers
 * ferait perdre le message. C'est la seule concession — tous les autres champs
 * sont vérifiés.
 */
export function normalizeContactCategory(value: unknown): ContactCategory {
  return typeof value === 'string' && (CONTACT_CATEGORIES as readonly string[]).includes(value)
    ? (value as ContactCategory)
    : 'other';
}

export function contactCategoryLabel(value: string): string {
  return CONTACT_CATEGORY_LABELS[normalizeContactCategory(value)];
}
