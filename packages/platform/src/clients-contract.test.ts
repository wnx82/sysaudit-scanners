// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import {
  CLIENT_KINDS,
  CLIENT_SUPPORT,
  COMPATIBILITY_TARGETS,
  clientSupport,
} from './compatibility.js';
import { renderClientReasons, renderClientTable, parseMarkdownTable } from './markdown.js';

/**
 * Ce que les façades installables promettent.
 *
 * Ce fichier existe pour une seule raison, et elle est écrite en tête de
 * `compatibility.ts` : **une case ne se coche pas parce que le code compile.**
 * Les tests ci-dessous rendent cette phrase exécutable — exhaustivité, motif
 * obligatoire, date d'exécution pour toute validation, et non-dérive du document
 * publié.
 */

const ROOT = fileURLToPath(new URL('../../../', import.meta.url));

function lireCompatibilite(): string {
  return readFileSync(`${ROOT}COMPATIBILITY.md`, 'utf8').replace(/\r\n/g, '\n');
}

function bloc(markdown: string, marqueur: string): string {
  const debut = markdown.indexOf(`<!-- ${marqueur}:start -->`);
  const fin = markdown.indexOf(`<!-- ${marqueur}:end -->`);
  expect(debut, `marqueur ${marqueur} absent de COMPATIBILITY.md`).toBeGreaterThan(-1);
  return markdown.slice(debut, fin);
}

describe('exhaustivité', () => {
  it('couvre **toutes** les cibles de la matrice', () => {
    // Une cible ajoutée demain sans entrée ici passerait pour « rien à
    // installer » sans que personne l'ait décidé.
    for (const target of COMPATIBILITY_TARGETS) {
      expect(CLIENT_SUPPORT[target.id], `cible sans façade déclarée : ${target.id}`).toBeDefined();
    }
  });

  it('ne déclare aucune façade pour une cible qui n’existe pas', () => {
    // L'autre sens compte autant : une entrée orpheline est une promesse que
    // personne ne lira, et qui survivra à la cible qu'elle décrivait.
    const connues = new Set(COMPATIBILITY_TARGETS.map((target) => target.id));
    for (const id of Object.keys(CLIENT_SUPPORT)) {
      expect(connues.has(id), `façade déclarée pour une cible inconnue : ${id}`).toBe(true);
    }
  });

  it('déclare les deux façades pour chaque cible', () => {
    for (const target of COMPATIBILITY_TARGETS) {
      for (const kind of CLIENT_KINDS) {
        expect(clientSupport(target.id, kind), `${target.id} / ${kind}`).not.toBeNull();
      }
    }
  });
});

describe('une case ne se coche pas parce que le code compile', () => {
  it('toute façade validée porte une date d’exécution', () => {
    /*
     * Le type l'exige déjà — `VALIDATED` sans `verifiedOn` ne compile pas — et
     * ce test le redit à l'exécution : le jour où quelqu'un élargit l'union
     * pour se simplifier la vie, il tombera ici.
     */
    for (const target of COMPATIBILITY_TARGETS) {
      for (const kind of CLIENT_KINDS) {
        const support = clientSupport(target.id, kind);
        if (support?.level !== 'VALIDATED') continue;
        expect(support.verifiedOn, `${target.id} / ${kind}`).toMatch(/^\d{4}-\d{2}-\d{2}$/);
      }
    }
  });

  it('aucune façade non validée ne porte de date', () => {
    for (const target of COMPATIBILITY_TARGETS) {
      for (const kind of CLIENT_KINDS) {
        const support = clientSupport(target.id, kind);
        if (support === null || support.level === 'VALIDATED') continue;
        expect(support.verifiedOn, `${target.id} / ${kind}`).toBeUndefined();
      }
    }
  });

  it('toute façade porte un motif qui dit quelque chose', () => {
    // Un motif vide ferait de ce tableau une liste de symboles, c'est-à-dire
    // exactement ce qu'il remplace.
    for (const target of COMPATIBILITY_TARGETS) {
      for (const kind of CLIENT_KINDS) {
        const support = clientSupport(target.id, kind);
        expect(support?.reason.length ?? 0, `${target.id} / ${kind}`).toBeGreaterThan(20);
      }
    }
  });
});

describe('Windows d’avant 10 1809', () => {
  /*
   * La case la plus tentante du tableau, et la seule dont une erreur se paierait
   * chez l'utilisateur : il téléchargerait un installeur qui ne démarre pas.
   */
  it('n’a **aucune** façade, ni prévue ni implémentée', () => {
    for (const id of ['windows-legacy', 'windows-minimal']) {
      for (const kind of CLIENT_KINDS) {
        expect(clientSupport(id, kind)?.level, `${id} / ${kind}`).toBe('PLANNED');
      }
    }
  });

  it('nomme les **deux** obstacles, parce que lever l’un ne lève pas l’autre', () => {
    const motif = clientSupport('windows-legacy', 'desktop')?.reason ?? '';
    expect(motif).toMatch(/Windows 10 1809/);
    expect(motif).toMatch(/Legacy/);
  });
});

describe('le document publié', () => {
  it('contient le tableau des façades, à jour', () => {
    const rendu = parseMarkdownTable(renderClientTable());
    const publie = parseMarkdownTable(bloc(lireCompatibilite(), 'clients:table'));
    expect(publie).toEqual(rendu);
  });

  it('publie une ligne par cible, plus l’en-tête et le séparateur', () => {
    expect(parseMarkdownTable(renderClientTable())).toHaveLength(COMPATIBILITY_TARGETS.length + 1);
  });

  it('contient les motifs, à jour', () => {
    const publie = bloc(lireCompatibilite(), 'clients:reasons');
    for (const ligne of renderClientReasons().split('\n')) {
      if (ligne.trim().length === 0) continue;
      expect(publie, `ligne absente du document : ${ligne}`).toContain(ligne);
    }
  });

  it('regroupe les cibles qui partagent un motif, plutôt que de le répéter', () => {
    // Sept lignes Linux identiques noyaient les deux qui apprennent quelque
    // chose. Un document qu'on cesse de lire ne dit plus rien.
    const rendu = renderClientReasons();
    const titres = rendu.split('\n').filter((ligne) => ligne.startsWith('**'));
    expect(titres.length).toBeLessThan(COMPATIBILITY_TARGETS.length);
    expect(titres.some((titre) => titre.includes(' · '))).toBe(true);
  });

  it('publie la date des cases validées', () => {
    expect(renderClientReasons()).toMatch(/exécuté le \d{4}-\d{2}-\d{2}/);
  });
});
