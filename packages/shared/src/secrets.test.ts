// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';
import { containsSecret, scanForSecrets, scanString } from './secrets.js';

describe('scanString — détections', () => {
  it.each([
    ['clé privée PEM', '-----BEGIN RSA PRIVATE KEY-----\nMIIEow…', 'private-key-block'],
    ['clé OpenSSH', '-----BEGIN OPENSSH PRIVATE KEY-----', 'openssh-private-key'],
    [
      'hash shadow',
      'root:$6$rounds=5000$abcdefgh$Xy1Z2aBcDeFgHiJkLmNoP:19000:0',
      'unix-shadow-hash',
    ],
    ['clé AWS', 'AKIAIOSFODNN7EXAMPLE', 'aws-access-key'],
    ['token GitHub', 'ghp_1234567890abcdefghijklmnopqrstuvwxyz', 'github-token'],
    ['clé Google', 'AIzaSyA1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6Q', 'google-api-key'],
    ['clé Stripe', 'sk_live_51H1234567890abcdef', 'stripe-key'],
    [
      'chaîne de connexion',
      'postgresql://sysaudit:SuperSecret42@db:5432/sysaudit',
      'connection-string-credentials',
    ],
    ['affectation', 'DB_PASSWORD=Tr0ub4dor&3xyz', 'assigned-credential'],
    ['PSK Wi-Fi', 'wpa_passphrase=MonReseauSecret', 'wifi-psk'],
  ])('détecte une %s', (_label, input, patternId) => {
    const ids = scanString(input).map((f) => f.patternId);
    expect(ids).toContain(patternId);
  });

  it('détecte un JWT', () => {
    const jwt =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk';
    expect(scanString(jwt).map((f) => f.patternId)).toContain('jwt');
  });
});

describe('scanString — non-détections (éviter les faux positifs)', () => {
  it.each([
    'PasswordAuthentication: disabled',
    'password authentication no',
    'PermitRootLogin: prohibit-password',
    'BitLocker: enabled',
    'api_key: <none>',
    'token: null',
    'DB_PASSWORD=***',
    'secret: xxxxxxxx',
    'Le mot de passe administrateur n’est pas collecté',
    'https://sysaudit.app/r/8XK4G9LH',
    'Serial number: CN0X1Y2Z74261',
    'https://user@example.com/doc',
  ])('ne signale pas %p', (input) => {
    expect(scanString(input)).toEqual([]);
  });
});

describe('scanForSecrets', () => {
  const report = {
    system: { hostname: 'pc-grenier' },
    security: {
      ssh: { passwordAuthentication: 'disabled', permitRootLogin: 'no' },
    },
    docker: {
      containers: [
        { name: 'web', env: ['NODE_ENV=production'] },
        { name: 'db', env: ['POSTGRES_PASSWORD=Sup3rS3cretValue'] },
      ],
    },
  };

  it('trouve le secret et son chemin JSON exact', () => {
    const findings = scanForSecrets(report);
    expect(findings).toHaveLength(1);
    expect(findings[0]?.path).toBe('$.docker.containers[1].env[0]');
    expect(findings[0]?.patternId).toBe('assigned-credential');
  });

  it('ne divulgue jamais le secret dans l’extrait', () => {
    const preview = scanForSecrets(report)[0]?.preview ?? '';
    expect(preview).not.toContain('Sup3rS3cretValue');
    expect(preview).toContain('•');
  });

  it('inspecte aussi les clés d’objet', () => {
    const findings = scanForSecrets({ ghp_1234567890abcdefghijklmnopqrstuvwxyz: true });
    expect(findings[0]?.path).toContain('(clé)');
  });

  it('accepte un rapport propre', () => {
    expect(containsSecret({ system: { hostname: 'pc-grenier' } })).toBe(false);
    expect(containsSecret(report.security)).toBe(false);
  });

  it('ne boucle pas sur une structure cyclique', () => {
    const cyclic: Record<string, unknown> = { name: 'node' };
    cyclic.self = cyclic;
    expect(() => scanForSecrets(cyclic)).not.toThrow();
  });

  it('traverse les types primitifs sans erreur', () => {
    expect(scanForSecrets({ a: 1, b: true, c: null, d: undefined })).toEqual([]);
  });
});
