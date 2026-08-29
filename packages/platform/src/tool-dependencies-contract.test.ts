// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import {
  PACKAGE_FAMILIES,
  TOOL_DEPENDENCIES,
  TOOL_REQUIREMENTS,
  installCommand,
  toolById,
  toolsForScanner,
  toolsInGroup,
  type PackageFamily,
} from './tool-dependencies.js';

/**
 * Contrat entre les scanners et la table des dépendances.
 *
 * Un outil sondé par un scanner mais absent de la table est un outil dont
 * personne ne sait ce qu'il apporte ni comment l'installer — c'était le cas de
 * tous, avant cette étape. Un outil déclaré dans la table mais sondé par aucun
 * scanner est une promesse morte : la documentation dirait d'installer un
 * paquet qui ne changerait rien.
 *
 * Les deux sens sont donc vérifiés, en relisant les scanners.
 */
const ROOT = fileURLToPath(new URL('../../../', import.meta.url));

/**
 * Les fins de ligne sont **normalisées à la lecture**.
 *
 * Ce test compare des sources de scanner à des expressions régulières écrites
 * avec des sauts de ligne simples. Sur une copie de travail extraite en CRLF —
 * le défaut de Git sous Windows —, aucune ne correspond, et le test annonce que
 * la table est introuvable alors qu'elle est là. Un contrat qui dépend de la
 * façon dont le dépôt a été extrait ne contrôle plus rien.
 */
function read(relativePath: string): string {
  return readFileSync(`${ROOT}${relativePath}`, 'utf8').replace(/\r\n/g, '\n');
}

/** Outils sondés par le scanner Linux, lus dans `CAPABILITY_TOOLS`. */
function linuxProbedTools(): readonly string[] {
  const source = read('scanners/linux/lib/core/capabilities.sh');
  const block = /CAPABILITY_TOOLS=\(\n([\s\S]*?)\n\)/.exec(source)?.[1];
  expect(block, 'CAPABILITY_TOOLS introuvable dans capabilities.sh').toBeDefined();
  return (block ?? '')
    .split(/\s+/)
    .map((entry) => entry.trim())
    .filter((entry) => entry !== '' && !entry.startsWith('#'));
}

/** Outils publiés par le scanner Windows dans `capabilities.tools`. */
function windowsProbedTools(): readonly string[] {
  const source = read('scanners/windows/sysaudit.ps1');
  // La table est déclarée une fois, dans `$toolAvailability`, et `capabilities`
  // s'y réfère. Elle vivait auparavant inline sous `tools = @{` ; depuis que
  // `collection.dependencies` la lit aussi, la dupliquer aurait ouvert la porte
  // à deux inventaires contradictoires dans le même rapport.
  const block = /\$toolAvailability = @\{\n([\s\S]*?)\n\}/.exec(source)?.[1];
  expect(block, 'bloc `tools` introuvable dans sysaudit.ps1').toBeDefined();
  return [...(block ?? '').matchAll(/^\s*([A-Za-z][A-Za-z0-9]*)\s*=/gm)].map((match) => match[1]!);
}

/**
 * Table des paquets embarquée dans le scanner Bash, colonne par colonne.
 *
 * Colonnes : outil, puis un paquet par famille dans l'ordre de
 * `PACKAGE_FAMILIES`, puis le texte de description. `-` marque une famille où
 * l'outil n'existe pas sous ce nom.
 */
function embeddedPackages(): Map<string, Partial<Record<PackageFamily, string>>> {
  const source = read('scanners/linux/lib/core/dependencies.sh');
  const block = /readonly DEPENDENCY_TABLE='\n([\s\S]*?)\n'/.exec(source)?.[1];
  expect(block, 'DEPENDENCY_TABLE introuvable dans dependencies.sh').toBeDefined();

  const rows = new Map<string, Partial<Record<PackageFamily, string>>>();
  for (const line of (block ?? '').split('\n')) {
    const cells = line.trim().split(/\s+/).filter(Boolean);
    if (cells.length < PACKAGE_FAMILIES.length + 2) continue;

    const packages: Partial<Record<PackageFamily, string>> = {};
    PACKAGE_FAMILIES.forEach((family, index) => {
      const cell = cells[index + 1];
      if (cell !== undefined && cell !== '-') packages[family] = cell;
    });
    rows.set(cells[0]!, packages);
  }
  return rows;
}

describe('contrat scanners ↔ dépendances externes', () => {
  it('le scanner Linux ne sonde aucun outil non déclaré', () => {
    const declared = new Set(toolsForScanner('linux').map((tool) => tool.id));
    for (const probed of linuxProbedTools()) {
      expect(
        declared.has(probed),
        `${probed} est sondé par le scanner Linux mais absent de la table des dépendances`,
      ).toBe(true);
    }
  });

  it('la table ne déclare aucun outil Linux que le scanner ignore', () => {
    const probed = new Set(linuxProbedTools());
    for (const tool of toolsForScanner('linux')) {
      expect(
        probed.has(tool.id),
        `${tool.id} est déclaré dans la table mais le scanner Linux ne le sonde pas`,
      ).toBe(true);
    }
  });

  it('le scanner Windows ne publie aucun outil non déclaré', () => {
    const declared = new Set(toolsForScanner('windows').map((tool) => tool.id));
    for (const probed of windowsProbedTools()) {
      expect(
        declared.has(probed),
        `${probed} est publié par le scanner Windows mais absent de la table des dépendances`,
      ).toBe(true);
    }
  });

  it('la table ne déclare aucun outil Windows que le scanner ignore', () => {
    const probed = new Set(windowsProbedTools());
    for (const tool of toolsForScanner('windows')) {
      expect(
        probed.has(tool.id),
        `${tool.id} est déclaré dans la table mais le scanner Windows ne le publie pas`,
      ).toBe(true);
    }
  });

  it('le scanner Linux embarque les mêmes noms de paquets que la table', () => {
    // Le scanner conseille l'installation sans pouvoir lire ce package : il
    // recopie donc les noms de paquets. Une divergence enverrait l'utilisateur
    // installer un paquet qui n'existe pas.
    //
    // La comparaison porte sur **la colonne**, pas sur la présence du nom
    // quelque part dans le fichier : `smartmontools` apparaît cinq fois par
    // ligne, une par famille, et un test qui se contenterait de le chercher
    // laisserait passer une faute de frappe dans la colonne Debian.
    const embedded = embeddedPackages();

    for (const tool of TOOL_DEPENDENCIES) {
      if (tool.packages === undefined) continue;
      const row = embedded.get(tool.id);
      expect(row, `${tool.id} est installable mais absent de dependencies.sh`).toBeDefined();

      for (const family of PACKAGE_FAMILIES) {
        expect(
          row?.[family] ?? null,
          `le paquet ${family} de ${tool.id} diverge entre le scanner et la table`,
        ).toBe(tool.packages[family] ?? null);
      }
    }
  });

  it('la table embarquée ne conseille aucun outil absent de la table', () => {
    for (const id of embeddedPackages().keys()) {
      const tool = toolById(id);
      expect(tool, `${id} est conseillé par le scanner mais absent de la table`).toBeDefined();
      expect(
        tool?.packages,
        `${id} est conseillé par le scanner alors que la table le dit fourni d’office`,
      ).toBeDefined();
    }
  });

  it('embarque les mêmes conditions d’applicabilité', () => {
    /*
     * Le défaut qui a motivé ces conditions : `vcgencmd` était proposé à chaque
     * audit sur un poste x86, avec `sudo apt install raspi-utils` à la clé. Le
     * paquet n'y débloque rien — le micrologiciel qu'il interroge n'existe que
     * sur un Raspberry Pi — et le conseil revenait à chaque exécution.
     *
     * Deux tables portent désormais ces conditions, et une seule des deux mise à
     * jour redonnerait exactement le même bruit, sans que rien n'échoue.
     */
    const source = read('scanners/linux/lib/core/dependencies.sh');
    const block = /readonly DEPENDENCY_APPLIES='\n([\s\S]*?)\n'/.exec(source)?.[1];
    expect(block, 'DEPENDENCY_APPLIES introuvable dans dependencies.sh').toBeDefined();

    const conditions = new Map<string, string>();
    for (const line of (block ?? '').split('\n')) {
      const cells = line.trim().split(/\s+/).filter(Boolean);
      if (cells.length < 2) continue;
      conditions.set(cells[0]!, cells[1]!);
    }

    const declared = new Map(
      TOOL_DEPENDENCIES.filter((tool) => tool.appliesWhen !== undefined).map((tool) => [
        tool.id,
        tool.appliesWhen!,
      ]),
    );

    expect([...conditions.entries()].sort()).toEqual([...declared.entries()].sort());

    // Et chaque condition doit être **évaluée** par le scanner : une valeur que
    // `dependency_applies` ne connaît pas retombe sur « applicable », donc sur
    // le bruit qu'on vient de retirer.
    for (const condition of conditions.values()) {
      expect(source, `dependency_applies ne traite pas la condition « ${condition} »`).toContain(
        `${condition})`,
      );
    }
  });

  it('embarque les mêmes groupes d’outils interchangeables', () => {
    const source = read('scanners/linux/lib/core/dependencies.sh');
    const block = /readonly DEPENDENCY_GROUPS='\n([\s\S]*?)\n'/.exec(source)?.[1];
    expect(block, 'DEPENDENCY_GROUPS introuvable dans dependencies.sh').toBeDefined();

    const groups = new Map<string, readonly string[]>();
    for (const line of (block ?? '').split('\n')) {
      const cells = line.trim().split(/\s+/).filter(Boolean);
      if (cells.length < 2) continue;
      groups.set(cells[0]!, cells.slice(1));
    }

    const declared = new Set(
      TOOL_DEPENDENCIES.map((tool) => tool.group).filter(
        (group): group is string => group !== undefined,
      ),
    );

    expect([...groups.keys()].sort()).toEqual([...declared].sort());
    for (const [group, members] of groups) {
      expect(
        [...members].sort(),
        `les membres du groupe ${group} divergent entre le scanner et la table`,
      ).toEqual(
        toolsInGroup(group)
          .map((tool) => tool.id)
          .sort(),
      );
    }
  });
});

describe('table des dépendances — invariants', () => {
  it('donne un identifiant unique à chaque outil', () => {
    const ids = TOOL_DEPENDENCIES.map((tool) => tool.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it('rattache chaque outil à au moins un scanner', () => {
    for (const tool of TOOL_DEPENDENCIES) {
      expect(tool.scanners.length, `${tool.id} n’est rattaché à aucun scanner`).toBeGreaterThan(0);
    }
  });

  it('dit toujours ce que l’outil apporte et ce qui se passe sans lui', () => {
    for (const tool of TOOL_DEPENDENCIES) {
      expect(tool.unlocks.length, `${tool.id} : « débloque » trop court`).toBeGreaterThan(20);
      expect(tool.fallback.length, `${tool.id} : « sans lui » trop court`).toBeGreaterThan(20);
      expect(TOOL_REQUIREMENTS).toContain(tool.requirement);
      expect(tool.licence.length, `${tool.id} : licence non renseignée`).toBeGreaterThan(2);
    }
  });

  it('ne propose pas d’installer ce qui vient avec le système', () => {
    // Conseiller `apt install util-linux` serait au mieux inutile.
    for (const tool of TOOL_DEPENDENCIES.filter((entry) => entry.requirement === 'native')) {
      for (const family of PACKAGE_FAMILIES) {
        expect(
          installCommand(tool.id, family),
          `${tool.id} est présent d’office mais propose une installation`,
        ).toBeNull();
      }
    }
  });

  it('construit une commande d’installation utilisable', () => {
    expect(installCommand('smartctl', 'debian')).toBe('apt install smartmontools');
    expect(installCommand('smartctl', 'arch')).toBe('pacman -S smartmontools');
    expect(installCommand('smartctl', 'inexistant' as never)).toBeNull();
    expect(installCommand('outil-inconnu', 'debian')).toBeNull();
  });

  it('retrouve un outil par son identifiant', () => {
    expect(toolById('smartctl')?.label).toBe('smartmontools');
    expect(toolById('inexistant')).toBeUndefined();
  });
});
