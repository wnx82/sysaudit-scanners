// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { compareSemVer, isSchemaReadable, parseSemVer, scanForSecrets } from '@sysaudit/shared';
import type { SecretFinding } from '@sysaudit/shared';
import type { z } from 'zod';
import { reportEnvelopeSchema, reportSchema, type Report } from './report.js';
import { explainIssue, type ExplainedIssue, type ValidationIssueCode } from './issue-explain.js';
import { SUPPORTED_SCHEMA_VERSION } from './version.js';

export type ValidationErrorCode =
  /** L'entrée n'est pas un objet JSON exploitable. */
  | 'MALFORMED'
  /** `schemaVersion` absent ou non conforme à SemVer. */
  | 'MISSING_SCHEMA_VERSION'
  /** Version MAJOR différente : le rapport n'est pas lisible par ce lecteur. */
  | 'INCOMPATIBLE_MAJOR'
  /** Version MINOR plus récente : produit par un scanner plus récent. */
  | 'UNSUPPORTED_MINOR'
  /** Le rapport ne respecte pas le schéma. */
  | 'SCHEMA_VIOLATION'
  /** Un secret a été détecté : le rapport est refusé sans être stocké. */
  | 'SECRET_DETECTED';

/**
 * Un refus, chemin JSON compris.
 *
 * `path` et `message` sont là depuis l'origine et ne bougent pas : c'est le
 * contrat que lisent les clients déjà déployés, et le chemin reste ce qui permet
 * de diagnostiquer. Tout ce que `explainIssue` ajoute est **facultatif** — une
 * réponse sans ces champs reste valide, et un lecteur qui les ignore continue de
 * fonctionner.
 *
 * Ils manquaient parce que `toIssues` jetait la structure de l'erreur pour n'en
 * garder que la prose anglaise de la bibliothèque de validation. Le refus du
 * 2026-08-27 — un compteur de cycles de batterie à `-1` — arrivait donc à
 * l'écran sous la forme d'un objet JSON, sans dire de quelle pièce il parlait ni
 * quoi faire.
 */
export interface ValidationIssue extends Partial<Omit<ExplainedIssue, 'path' | 'message'>> {
  readonly path: string;
  readonly message: string;
}

export interface ValidationFailure {
  readonly ok: false;
  readonly code: ValidationErrorCode;
  readonly message: string;
  readonly issues: readonly ValidationIssue[];
  /** Renseigné uniquement pour `SECRET_DETECTED` ; ne contient jamais le secret. */
  readonly secrets?: readonly SecretFinding[];
}

export interface ValidationSuccess {
  readonly ok: true;
  /** Rapport normalisé : seuls les champs connus du schéma sont conservés. */
  readonly report: Report;
  /** Vrai si le rapport provient d'une version MINOR antérieure. */
  readonly upgradedFrom?: string;
}

export type ValidationResult = ValidationSuccess | ValidationFailure;

export interface ValidateOptions {
  /**
   * Rejeter le rapport si un secret y est détecté. Activé par défaut : c'est le
   * filet de sécurité de l'ingestion, un scanner correct ne devant jamais en
   * produire.
   */
  readonly rejectSecrets?: boolean;
  /** Version maximale lisible. Surchargeable pour les tests de compatibilité. */
  readonly supportedVersion?: string;
}

/**
 * La nature d'un refus, traduite du vocabulaire de la bibliothèque au nôtre.
 *
 * Le passage par un code à nous n'est pas une coquetterie : les codes de Zod
 * changent d'une version majeure à l'autre — `invalid_enum_value` est devenu
 * `invalid_value` en v4 — et les laisser fuiter jusqu'à l'API en ferait un
 * contrat public que personne n'a décidé de tenir.
 */
function codeDe(issue: z.core.$ZodIssue, present: boolean): ValidationIssueCode {
  switch (issue.code) {
    case 'too_small':
      return 'VALUE_BELOW_MINIMUM';
    case 'too_big':
      return 'VALUE_ABOVE_MAXIMUM';
    case 'invalid_type':
    case 'invalid_value':
      /*
       * Zod ne distingue pas « absent » de « mal rempli » : un champ manquant
       * est un `undefined` là où autre chose était attendu, et sur une
       * énumération c'est même un `invalid_value`. La distinction est pourtant
       * la première que fait le lecteur — « je n'ai pas ça » n'appelle pas le
       * même geste que « ce que j'ai est faux ».
       *
       * Elle se tranche sur le document soumis, pas sur le grief : le champ
       * est-il là ? C'est la seule source qui réponde sans ambiguïté.
       */
      if (!present) return 'VALUE_MISSING';
      return issue.code === 'invalid_value' ? 'VALUE_NOT_ALLOWED' : 'VALUE_WRONG_TYPE';
    default:
      return 'VALUE_MALFORMED';
  }
}

/**
 * Le vrai grief derrière un refus d'union.
 *
 * Presque tout champ collecté est déclaré `maybe(T)`, c'est-à-dire
 * `union([T, marqueur])`. Quand aucune branche ne passe, Zod rend un
 * `invalid_union` dont le code ne dit rien — « la forme attendue » — et le
 * détail utile est enfermé dans `errors`.
 *
 * `maybe()` place **toujours** le schéma réel en première branche et le marqueur
 * en seconde. Le premier grief de la première branche est donc le grief du
 * champ ; celui de la seconde ne dirait que « ce n'est pas un marqueur », ce qui
 * n'apprend rien à personne.
 */
function griefReel(issue: z.core.$ZodIssue): z.core.$ZodIssue {
  if (issue.code !== 'invalid_union') return issue;
  const premiereBranche = issue.errors[0];
  const premierGrief = premiereBranche?.[0];
  return premierGrief === undefined ? issue : griefReel(premierGrief as z.core.$ZodIssue);
}

/** La valeur refusée, relue dans le document soumis au chemin de l'erreur. */
function valeurRefusee(racine: unknown, chemin: readonly PropertyKey[]): unknown {
  let courant: unknown = racine;
  for (const segment of chemin) {
    if (courant === null || typeof courant !== 'object') return undefined;
    courant = (courant as Record<PropertyKey, unknown>)[segment];
  }
  return courant;
}

function toIssues(error: z.ZodError, input: unknown): ValidationIssue[] {
  return error.issues.slice(0, 50).map((externe) => {
    const path = externe.path.length === 0 ? '$' : `$.${externe.path.join('.')}`;
    // Le chemin et le message restent ceux de l'erreur telle qu'elle a été
    // rendue : c'est le contrat existant. Seul le grief interne sert à qualifier.
    const issue = griefReel(externe);
    const received = valeurRefusee(input, externe.path);
    const code = codeDe(issue, received !== undefined);

    return explainIssue(
      { path, message: externe.message },
      {
        code,
        // Un objet reçu n'apprend rien et alourdirait la réponse : seules les
        // valeurs simples sont renvoyées, et jamais une chaîne entière, qui
        // pourrait porter une donnée de la machine auditée.
        ...(typeof received === 'number' || typeof received === 'boolean' ? { received } : {}),
        ...('minimum' in issue && typeof issue.minimum === 'number'
          ? { minimum: issue.minimum }
          : {}),
        ...('maximum' in issue && typeof issue.maximum === 'number'
          ? { maximum: issue.maximum }
          : {}),
        ...('expected' in issue && typeof issue.expected === 'string'
          ? { expected: issue.expected }
          : {}),
        ...('values' in issue && Array.isArray(issue.values)
          ? { allowed: issue.values.map((valeur) => String(valeur)) }
          : {}),
      },
    );
  });
}

/**
 * Valide un rapport en trois temps : version, schéma, puis absence de secrets.
 *
 * L'ordre est délibéré — un rapport produit par un scanner plus récent doit
 * recevoir un message de version explicite, pas une avalanche d'erreurs de
 * champs inconnus.
 */
export function validateReport(input: unknown, options: ValidateOptions = {}): ValidationResult {
  const { rejectSecrets = true, supportedVersion = SUPPORTED_SCHEMA_VERSION } = options;

  if (typeof input !== 'object' || input === null || Array.isArray(input)) {
    return {
      ok: false,
      code: 'MALFORMED',
      message: 'Le rapport doit être un objet JSON.',
      issues: [],
    };
  }

  const envelope = reportEnvelopeSchema.safeParse(input);
  if (!envelope.success) {
    return {
      ok: false,
      code: 'MISSING_SCHEMA_VERSION',
      message: 'Le champ `schemaVersion` est absent ou n’est pas une version SemVer valide.',
      issues: toIssues(envelope.error, input),
    };
  }

  const actual = envelope.data.schemaVersion;
  const actualParsed = parseSemVer(actual);
  const supportedParsed = parseSemVer(supportedVersion);

  if (actualParsed && supportedParsed && actualParsed.major !== supportedParsed.major) {
    return {
      ok: false,
      code: 'INCOMPATIBLE_MAJOR',
      message:
        `Rapport en schéma ${actual}, incompatible avec le schéma ${supportedVersion} ` +
        'supporté par cette version de SysAudit.',
      issues: [],
    };
  }

  if (!isSchemaReadable(actual, supportedVersion)) {
    return {
      ok: false,
      code: 'UNSUPPORTED_MINOR',
      message:
        `Rapport en schéma ${actual}, plus récent que le schéma ${supportedVersion} supporté. ` +
        'Mettez à jour SysAudit plutôt que de lire ce rapport partiellement.',
      issues: [],
    };
  }

  const parsed = reportSchema.safeParse(input);
  if (!parsed.success) {
    return {
      ok: false,
      code: 'SCHEMA_VIOLATION',
      message: 'Le rapport ne respecte pas le schéma SysAudit.',
      issues: toIssues(parsed.error, input),
    };
  }

  if (rejectSecrets) {
    // Analyse la sortie normalisée : les champs inconnus ayant été retirés, un
    // secret glissé dans un champ hors schéma ne peut de toute façon pas être
    // stocké.
    const secrets = scanForSecrets(parsed.data);
    if (secrets.length > 0) {
      return {
        ok: false,
        code: 'SECRET_DETECTED',
        message:
          `${secrets.length} secret(s) potentiel(s) détecté(s) dans le rapport. ` +
          'Le rapport a été refusé et n’a pas été conservé.',
        issues: secrets.map((finding) => ({
          path: finding.path,
          message: `${finding.label} (${finding.patternId})`,
        })),
        secrets,
      };
    }
  }

  const result: ValidationSuccess = { ok: true, report: parsed.data };
  return compareSemVer(actual, supportedVersion) < 0 ? { ...result, upgradedFrom: actual } : result;
}

/**
 * Variante levant une exception, pour le code interne manipulant des rapports
 * déjà validés (rendu, règles) où un échec est un bug, pas une entrée invalide.
 */
export function parseReport(input: unknown, options: ValidateOptions = {}): Report {
  const result = validateReport(input, options);
  if (!result.ok) {
    const detail = result.issues
      .slice(0, 5)
      .map((issue) => `${issue.path}: ${issue.message}`)
      .join(' ; ');
    throw new Error(`[${result.code}] ${result.message}${detail ? ` — ${detail}` : ''}`);
  }
  return result.report;
}
