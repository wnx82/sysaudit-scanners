#!/usr/bin/env node
// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

/**
 * Génère les **bornes numériques du schéma** pour le scanner Linux.
 *
 * ## Le défaut que ce fichier existe pour fermer
 *
 * Le 2026-08-27, un dépôt d'audit a été refusé en bloc parce que
 * `/sys/class/power_supply/BAT0/cycle_count` rendait `-1` — la façon dont une
 * partie du parc ACPI dit « ce compteur n'existe pas ». Le scanner publiait
 * `"cycleCount": -1`, le schéma borne ce champ à zéro, et **tout** l'audit était
 * perdu pour une grandeur que personne ne regardait.
 *
 * Le scanner comptait alors 182 appels à `jf_maybe_num`, dont 167 alimentent un
 * champ borné. Les sources dangereuses étaient gardées **une par une**, à la
 * main, dans la fonction de lecture — `millicelsius_to_celsius` borne à
 * ±100/200, `monitoring_fan_rpm` refuse au-delà de 30 000 tr/min, la vitesse
 * d'une interface à `-1` est effacée. Ces gardes sont justes ; leur exhaustivité
 * ne l'était pas, et rien ne le disait. La batterie était l'oubli.
 *
 * Une vigilance répartie sur 167 endroits n'est pas une garantie. Celle-ci en
 * est une : le schéma **est** la source de vérité du contrat, et le scanner en
 * lit les bornes au lieu de les redécouvrir.
 *
 * ## Pourquoi élargir quand un nom porte plusieurs contrats
 *
 * `prefixLength` vaut au plus 32 sur une adresse IPv4 et 128 sur une IPv6. La
 * table ne garde qu'une entrée par nom de champ, et elle prend la **réunion**
 * des domaines : `[0, 128]`.
 *
 * C'est le seul choix qui ne peut rien casser. Une valeur hors de la réunion
 * serait refusée par le schéma dans **tous** ses contextes : la transformer en
 * marqueur ne perd donc aucune mesure publiable. Une valeur dans la réunion mais
 * hors du contrat local reste refusée par le schéma, exactement comme
 * aujourd'hui — la table ne prétend pas remplacer la validation, elle empêche un
 * aveu du firmware d'emporter l'audit entier.
 *
 * ## Ce que la table ne contient pas
 *
 * Les champs sans borne au schéma — le score d'un banc d'essai, les séries de
 * télémétrie. `jf_maybe_num` garde pour eux son comportement d'origine : borner
 * ce que le schéma ne borne pas serait inventer une règle.
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const RACINE = new URL('..', import.meta.url);
const SCHEMA = fileURLToPath(
  new URL('packages/report-schema/schema/sysaudit-report-latest.schema.json', RACINE),
);
const CIBLE = fileURLToPath(new URL('scanners/linux/lib/core/schema-bounds.sh', RACINE));

/**
 * Les contraintes du nœud numérique d'un champ, marqueur « inconnu » compris.
 *
 * Un champ collecté par le scanner est toujours une union « nombre ou
 * marqueur » : c'est cette forme-là qu'on cherche, et le nœud nombre qu'on en
 * extrait.
 */
function contraintesNumeriques(noeud) {
  if (noeud === null || typeof noeud !== 'object') return null;
  const estNombre = noeud.type === 'number' || noeud.type === 'integer';
  const branches = noeud.anyOf ?? noeud.oneOf ?? (estNombre ? [noeud] : null);
  if (branches === null) return null;

  let nombre = null;
  let marqueur = false;
  for (const branche of branches) {
    if (branche === null || typeof branche !== 'object') continue;
    if (branche.type === 'number' || branche.type === 'integer') nombre = branche;
    if (branche.type === 'object' && branche.properties && 'unknown' in branche.properties) {
      marqueur = true;
    }
  }
  if (nombre === null) return null;

  const minimum = nombre.minimum ?? nombre.exclusiveMinimum ?? null;
  const maximum = nombre.maximum ?? nombre.exclusiveMaximum ?? null;
  if (minimum === null && maximum === null) return null;
  return { minimum, maximum, marqueur };
}

/** Parcourt le schéma et réunit les domaines, par nom de champ. */
export function bornesDuSchema(schema) {
  const table = new Map();

  const visiter = (noeud, cle) => {
    if (noeud === null || typeof noeud !== 'object') return;

    const c = contraintesNumeriques(noeud);
    if (c !== null) {
      // Un champ que le schéma n'autorise pas à porter un marqueur ne peut pas
      // être « rendu inconnu » : le refuser resterait un refus, et l'audit
      // serait perdu de la même façon. La table ne le borne donc pas.
      if (!c.marqueur || cle === null) return;
      const existant = table.get(cle);
      table.set(cle, {
        minimum:
          existant === undefined ? c.minimum : reunion(existant.minimum, c.minimum, Math.min),
        maximum:
          existant === undefined ? c.maximum : reunion(existant.maximum, c.maximum, Math.max),
      });
      return;
    }

    if (noeud.properties) {
      for (const [nom, sous] of Object.entries(noeud.properties)) visiter(sous, nom);
    }
    if (noeud.items) visiter(noeud.items, cle);
    for (const mot of ['anyOf', 'oneOf', 'allOf']) {
      if (Array.isArray(noeud[mot])) for (const branche of noeud[mot]) visiter(branche, cle);
    }
  };

  visiter(schema, null);
  return table;
}

/** Une borne absente ouvre le domaine de ce côté-là, et l'emporte donc. */
function reunion(a, b, choisir) {
  if (a === null || b === null) return null;
  return choisir(a, b);
}

function rendre(table) {
  const lignes = [...table.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(
      ([champ, { minimum, maximum }]) =>
        `SCHEMA_BOUNDS[${champ}]='${minimum ?? ''} ${maximum ?? ''}'`,
    );

  return `#!/usr/bin/env bash
# Bornes numériques du schéma de rapport, par nom de champ.
#
# **FICHIER GÉNÉRÉ — ne pas modifier à la main.**
# Source : packages/report-schema/schema/sysaudit-report-latest.schema.json
# Régénérer : npm run docs:scanner-bounds
#
# Chaque entrée vaut « minimum maximum ». Une borne vide n'en est pas une.
#
# Pourquoi ce fichier existe, et pourquoi il est généré plutôt que saisi :
# scripts/generate-scanner-bounds.mjs.
#
# Ne figurent ici que les champs dont le schéma accepte le marqueur « inconnu ».
# Un champ borné qui exige un nombre ne gagnerait rien à être rendu inconnu :
# le rapport serait refusé pareillement, et le marqueur masquerait la cause.

# SC2034 : la table n'est lue que par \`jf_maybe_num\`, dans json.sh. ShellCheck
# analyse chaque fichier isolément et ne peut pas voir cet usage ; la désactiver
# ici vaut mieux que de fondre la table dans json.sh, qui est écrit à la main.
# shellcheck disable=SC2034
declare -A SCHEMA_BOUNDS=()

${lignes.join('\n')}
`;
}

/*
 * L'écriture n'a lieu que si ce fichier est **lancé**, jamais s'il est importé.
 *
 * `scanner-bounds.test.ts` importe `bornesDuSchema` pour comparer la table
 * générée au schéma. Sans cette garde, l'import régénérerait le fichier au
 * milieu du test : la comparaison porterait sur ce qu'on vient d'écrire, elle
 * serait verte par construction, et la dérive qu'elle existe pour attraper
 * passerait inaperçue. Un test qui répare ce qu'il mesure ne mesure rien.
 */
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const table = bornesDuSchema(JSON.parse(readFileSync(SCHEMA, 'utf8')));
  const contenu = rendre(table);

  if (process.argv.includes('--check')) {
    if (readFileSync(CIBLE, 'utf8') !== contenu) {
      console.error('scanners/linux/lib/core/schema-bounds.sh a dérivé du schéma.');
      console.error('Régénérer : npm run docs:scanner-bounds');
      process.exit(1);
    }
    console.log(`schema-bounds.sh à jour — ${table.size} champs bornés.`);
  } else {
    writeFileSync(CIBLE, contenu);
    console.log(`schema-bounds.sh écrit — ${table.size} champs bornés.`);
  }
}
