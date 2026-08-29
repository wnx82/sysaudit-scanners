// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

/**
 * Version du **format** de rapport, indépendante de la version de la plateforme
 * et de celle des scanners (voir docs/format-rapport/VERSIONING.md).
 *
 * - Ajout d'un champ optionnel → MINOR.
 * - Suppression, renommage ou changement de sémantique d'un champ → MAJOR.
 * - Précision d'une contrainte sans changer les données acceptées → PATCH.
 *
 * Toute modification de cette constante doit s'accompagner d'une entrée dans
 * CHANGELOG.md et, en cas de MAJOR, d'un adaptateur dans `src/migrations/`.
 */
export const SCHEMA_VERSION = '1.33.0';

/**
 * Version la plus élevée que ce package sait lire. Un rapport dont la version
 * MINOR est supérieure est refusé explicitement plutôt qu'interprété
 * partiellement (`isSchemaReadable` dans `@sysaudit/shared`).
 */
export const SUPPORTED_SCHEMA_VERSION = SCHEMA_VERSION;
