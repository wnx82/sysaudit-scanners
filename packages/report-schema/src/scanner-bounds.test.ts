// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { bornesDuSchema } from '../../../scripts/generate-scanner-bounds.mjs';

/**
 * Le scanner Bash ne peut pas lire le schéma Zod : il doit tourner sur une
 * machine sans Node.js. Les bornes qu'il applique sont donc **générées** dans
 * `scanners/linux/lib/core/schema-bounds.sh`, et cette suite garde les deux
 * propriétés dont dépend la garantie.
 *
 * ## Ce que ce fichier existe pour empêcher
 *
 * Le 2026-08-27, `cycle_count = -1` sur une batterie a fait refuser un audit
 * entier : le scanner publiait la valeur, le schéma la refusait, et le rapport
 * était perdu en bloc pour une grandeur que personne ne regardait.
 *
 * La correction ne vaut que si la table reste alignée sur le schéma. Une table
 * périmée redonnerait exactement le défaut d'origine — en pire, parce qu'elle
 * aurait l'air d'un garde-fou.
 */

const RACINE = new URL('../../../', import.meta.url).pathname;
const GENERE = `${RACINE}scanners/linux/lib/core/schema-bounds.sh`;
const SCHEMA = `${RACINE}packages/report-schema/schema/sysaudit-report-latest.schema.json`;

/** Les entrées telles que le scanner les lira. */
function tableDuFichier(): Map<string, { minimum: number | null; maximum: number | null }> {
  const table = new Map<string, { minimum: number | null; maximum: number | null }>();
  for (const ligne of readFileSync(GENERE, 'utf8').split('\n')) {
    const m = ligne.match(/^SCHEMA_BOUNDS\[([A-Za-z0-9_]+)\]='(-?[0-9]*) (-?[0-9]*)'$/);
    if (m === null) continue;
    table.set(m[1]!, {
      minimum: m[2] === '' ? null : Number(m[2]),
      maximum: m[3] === '' ? null : Number(m[3]),
    });
  }
  return table;
}

describe('bornes du scanner', () => {
  const attendu = bornesDuSchema(JSON.parse(readFileSync(SCHEMA, 'utf8')));
  const obtenu = tableDuFichier();

  it('n’a pas dérivé du schéma', () => {
    // Le message compte : sans lui, l'échec envoie chercher dans le scanner un
    // défaut qui vit dans le schéma.
    expect(
      [...obtenu.keys()].sort(),
      'schema-bounds.sh a dérivé — régénérer avec `npm run docs:scanner-bounds`',
    ).toEqual([...attendu.keys()].sort());

    for (const [champ, bornes] of attendu) {
      expect(obtenu.get(champ), `bornes de ${champ}`).toEqual(bornes);
    }
  });

  it('borne les champs par lesquels un audit a déjà été perdu', () => {
    // Pas un échantillon au hasard : le champ qui a coûté l'audit du
    // 2026-08-27, et son voisin immédiat dans la même fonction de collecte.
    expect(obtenu.get('cycleCount')).toEqual({ minimum: 0, maximum: Number.MAX_SAFE_INTEGER });
    expect(obtenu.get('chargePercent')).toEqual({ minimum: 0, maximum: 100 });
  });

  it('n’inscrit que des champs qui peuvent porter un marqueur', () => {
    // `prefixLength` est déclaré `optional()`, pas `maybe()` : le rendre
    // « inconnu » ferait refuser le rapport aussi sûrement qu'une valeur fausse.
    // Le borner ici donnerait l'illusion d'une protection.
    expect(obtenu.has('prefixLength')).toBe(false);
  });

  it('réunit les domaines quand un nom porte plusieurs contrats', () => {
    // Un même nom de champ peut vivre sous deux contrats — la table n'en garde
    // qu'une entrée, et prend la réunion. Élargir ne peut pas transformer une
    // mesure publiable en inconnue ; restreindre le pourrait.
    for (const [champ, bornes] of attendu) {
      const local = obtenu.get(champ)!;
      if (bornes.minimum !== null) expect(local.minimum, champ).toBeLessThanOrEqual(bornes.minimum);
      if (bornes.maximum !== null) {
        expect(local.maximum, champ).toBeGreaterThanOrEqual(bornes.maximum);
      }
    }
  });
});
