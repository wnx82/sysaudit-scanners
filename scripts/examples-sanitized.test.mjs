// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

/**
 * Les exemples publiés restent valides **et** anonymes.
 *
 * Deux façons de rater un exemple public, et ce test couvre les deux.
 *
 * La première est de le laisser vieillir : un exemple qui ne valide plus contre
 * le schéma courant apprend au lecteur une forme qui n'existe pas, et c'est
 * pire que pas d'exemple du tout.
 *
 * La seconde est de le régénérer un jour depuis un rapport réel « qu'on aura
 * masqué ». Un masquage à la main laisse toujours quelque chose — une route,
 * un suffixe DNS, un numéro de série de barrette. Ce test vérifie donc que
 * chaque valeur identifiante est exactement l'une des valeurs de démonstration
 * prévues, et refuse tout ce qui ressemble à une adresse, une MAC ou un UUID
 * en dehors des plages que les RFC réservent à la documentation.
 */

import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

import { reportSchema } from '@sysaudit/report-schema';

const ROOT = resolve(import.meta.dirname, '..');
const DIR = resolve(ROOT, 'docs/examples/sanitized');

/** Plages que les RFC réservent explicitement à la documentation. */
const ALLOWED_IPV4 =
  /^(?:192\.0\.2\.\d{1,3}|198\.51\.100\.\d{1,3}|203\.0\.113\.\d{1,3})(?:\/\d{1,2})?$/;
const ALLOWED_MAC = /^00:00:5e:00:53:[0-9a-f]{2}$/i;
const ALLOWED_UUID = /^0{8}-0{4}-0{4}-0{4}-0{12}$/;

const ANY_IPV4 = /\b\d{1,3}(?:\.\d{1,3}){3}(?:\/\d{1,2})?\b/g;
const ANY_MAC = /\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b/gi;
const ANY_UUID = /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/gi;

const files = readdirSync(DIR).filter((name) => name.endsWith('.json'));

describe('exemples publiés', () => {
  it('en publie au moins un', () => {
    expect(files.length).toBeGreaterThan(0);
  });

  for (const name of files) {
    const raw = readFileSync(resolve(DIR, name), 'utf8');

    describe(name, () => {
      it('valide contre le schéma courant', () => {
        const parsed = reportSchema.safeParse(JSON.parse(raw));
        expect(parsed.error?.issues.slice(0, 5) ?? [], 'exemple invalide').toEqual([]);
        expect(parsed.success).toBe(true);
      });

      it("n'expose aucune adresse hors des plages de documentation", () => {
        // La version du schéma ressemble à une adresse ; elle n'en est pas une.
        const suspects = [...raw.matchAll(ANY_IPV4)]
          .map(([value]) => value)
          .filter((value) => !ALLOWED_IPV4.test(value))
          .filter((value) => !/^\d+\.\d+\.\d+$/.test(value));
        expect([...new Set(suspects)]).toEqual([]);
      });

      it("n'expose aucune adresse MAC hors de la plage de documentation", () => {
        const suspects = [...raw.matchAll(ANY_MAC)]
          .map(([value]) => value)
          .filter((value) => !ALLOWED_MAC.test(value));
        expect([...new Set(suspects)]).toEqual([]);
      });

      it("n'expose aucun UUID réel", () => {
        const suspects = [...raw.matchAll(ANY_UUID)]
          .map(([value]) => value)
          .filter((value) => !ALLOWED_UUID.test(value));
        expect([...new Set(suspects)]).toEqual([]);
      });

      it("n'expose ni hostname, ni utilisateur, ni numéro de série réels", () => {
        const report = JSON.parse(raw);
        const wrong = [];
        const expected = {
          hostname: 'demo-host',
          serialNumber: 'DEMO-000000',
          domain: 'demo.invalid',
        };

        const walk = (node) => {
          if (Array.isArray(node)) return node.forEach(walk);
          if (node === null || typeof node !== 'object') return;
          for (const [key, value] of Object.entries(node)) {
            if (typeof value === 'string' && key in expected && value !== expected[key]) {
              wrong.push(key);
            }
            walk(value);
          }
        };
        walk(report);

        expect([...new Set(wrong)]).toEqual([]);
      });
    });
  }
});
