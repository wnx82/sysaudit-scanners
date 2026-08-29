// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

/**
 * Détection défensive de secrets dans un rapport (§30).
 *
 * SysAudit ne collecte volontairement aucun secret. Ce module est un filet de
 * sécurité : il est exécuté par les tests automatisés du scanner **et** par la
 * sanitisation côté API, afin qu'un secret ne puisse pas apparaître par accident
 * (message d'erreur d'une commande, variable d'environnement, ligne de conf…).
 */
export type SecretSeverity = 'critical' | 'high';

export interface SecretPattern {
  readonly id: string;
  readonly label: string;
  readonly severity: SecretSeverity;
  readonly pattern: RegExp;
}

/**
 * Chaque motif cible une forme *structurelle* de secret (préfixe connu, bloc PEM,
 * assignation explicite) plutôt qu'un mot isolé : un rapport mentionnant
 * légitimement « password authentication: disabled » ne doit pas être rejeté.
 */
export const SECRET_PATTERNS: readonly SecretPattern[] = [
  {
    id: 'private-key-block',
    label: 'Clé privée PEM',
    severity: 'critical',
    pattern: /-----BEGIN(?: [A-Z]+)* PRIVATE KEY-----/,
  },
  {
    id: 'openssh-private-key',
    label: 'Clé privée OpenSSH',
    severity: 'critical',
    pattern: /-----BEGIN OPENSSH PRIVATE KEY-----/,
  },
  {
    id: 'pgp-private-key',
    label: 'Bloc PGP privé',
    severity: 'critical',
    pattern: /-----BEGIN PGP PRIVATE KEY BLOCK-----/,
  },
  {
    id: 'unix-shadow-hash',
    label: 'Hash de mot de passe UNIX',
    severity: 'critical',
    pattern: /\$(?:1|2[aby]|5|6|y|argon2(?:id|i|d))\$[./A-Za-z0-9$,=+-]{12,}/,
  },
  {
    id: 'ntlm-hash-dump',
    label: 'Dump de hash NTLM/SAM',
    severity: 'critical',
    pattern: /\b[A-Fa-f0-9]{32}:[A-Fa-f0-9]{32}\b/,
  },
  {
    id: 'aws-access-key',
    label: 'Clé d’accès AWS',
    severity: 'critical',
    pattern: /\b(?:AKIA|ASIA|ABIA|ACCA)[0-9A-Z]{16}\b/,
  },
  {
    id: 'github-token',
    label: 'Token GitHub',
    severity: 'critical',
    pattern: /\bgh[pousr]_[A-Za-z0-9]{36,}\b/,
  },
  {
    id: 'slack-token',
    label: 'Token Slack',
    severity: 'critical',
    pattern: /\bxox[abprs]-[A-Za-z0-9-]{10,}\b/,
  },
  {
    id: 'google-api-key',
    label: 'Clé API Google',
    severity: 'critical',
    pattern: /\bAIza[0-9A-Za-z_-]{35}\b/,
  },
  {
    id: 'stripe-key',
    label: 'Clé Stripe',
    severity: 'critical',
    pattern: /\b(?:sk|rk)_(?:live|test)_[0-9A-Za-z]{16,}\b/,
  },
  {
    id: 'jwt',
    label: 'JSON Web Token',
    severity: 'high',
    pattern: /\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/,
  },
  {
    id: 'connection-string-credentials',
    label: 'Chaîne de connexion avec identifiants',
    severity: 'critical',
    pattern: /\b[a-z][a-z0-9+.-]*:\/\/[^\s/:@]+:[^\s/@]{3,}@[^\s/]+/i,
  },
  {
    id: 'assigned-credential',
    label: 'Affectation de secret',
    severity: 'high',
    // Le lookbehind (et non `\b`) permet de reconnaître `DB_PASSWORD=` : `_` étant
    // un caractère de mot, `\b` ne se déclenche pas au milieu de `DB_PASSWORD`.
    // La valeur doit être non triviale : les placeholders (***, xxx, <none>, null,
    // enabled/disabled…) sont exclus pour ne pas signaler une configuration lisible.
    pattern:
      /(?<![a-z0-9])(?:pass(?:word|wd)?|secret|api[_-]?key|token|credential|private[_-]?key)\s*[:=]\s*["']?(?!\*+|x{3,}|<|null\b|none\b|undefined\b|true\b|false\b|enabled\b|disabled\b|yes\b|no\b)[^\s"',;]{8,}/i,
  },
  {
    id: 'wifi-psk',
    label: 'Clé Wi-Fi (PSK)',
    severity: 'critical',
    pattern:
      /(?<![a-z0-9])(?:psk|wpa[_-]?(?:passphrase|psk)|network[_-]?key)\s*[:=]\s*["']?[^\s"',;]{8,}/i,
  },
];

export interface SecretFinding {
  readonly patternId: string;
  readonly label: string;
  readonly severity: SecretSeverity;
  /** Chemin JSON où le secret a été trouvé (`$.network.interfaces[0].notes`). */
  readonly path: string;
  /** Extrait tronqué et masqué — jamais le secret complet. */
  readonly preview: string;
}

function preview(value: string, index: number): string {
  const start = Math.max(0, index - 12);
  const excerpt = value.slice(start, index + 8);
  return `${start > 0 ? '…' : ''}${excerpt.replace(/[^\s:=/@$-]/g, '•')}…`;
}

/** Analyse une chaîne isolée. */
export function scanString(value: string, path = '$'): SecretFinding[] {
  const findings: SecretFinding[] = [];
  for (const { id, label, severity, pattern } of SECRET_PATTERNS) {
    const match = pattern.exec(value);
    if (match) {
      findings.push({
        patternId: id,
        label,
        severity,
        path,
        preview: preview(value, match.index),
      });
    }
  }
  return findings;
}

/**
 * Parcourt récursivement une valeur JSON et retourne tous les secrets détectés.
 * Les clés d'objet sont également inspectées : un secret peut apparaître dans un
 * nom de variable d'environnement.
 */
export function scanForSecrets(input: unknown, basePath = '$'): SecretFinding[] {
  const findings: SecretFinding[] = [];
  const seen = new WeakSet<object>();

  const walk = (value: unknown, path: string): void => {
    if (typeof value === 'string') {
      findings.push(...scanString(value, path));
      return;
    }
    if (value === null || typeof value !== 'object') return;
    if (seen.has(value)) return;
    seen.add(value);

    if (Array.isArray(value)) {
      value.forEach((item, index) => walk(item, `${path}[${index}]`));
      return;
    }

    for (const [key, item] of Object.entries(value)) {
      const childPath = `${path}.${key}`;
      findings.push(...scanString(key, `${childPath} (clé)`));
      walk(item, childPath);
    }
  };

  walk(input, basePath);
  return findings;
}

export function containsSecret(input: unknown): boolean {
  return scanForSecrets(input).length > 0;
}
