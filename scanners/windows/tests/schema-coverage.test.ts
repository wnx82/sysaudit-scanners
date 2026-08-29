import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { buildJsonSchema } from '@sysaudit/report-schema';
import { UNKNOWN_REASONS } from '@sysaudit/shared';

/**
 * Le scanner Windows suit-il encore le schéma ?
 *
 * Ce contrôle existe à cause d'une panne réelle : `network.interfaces[].duplex`
 * et `storage.disks[].trimSupported` ont été ajoutés au schéma en cours de
 * route, et le collecteur Windows ne les a jamais produits. Il vivait alors dans
 * une chaîne de caractères au sein d'`apps/api` — aucune barrière ne pouvait
 * voir la divergence, et chaque upload Windows était refusé.
 *
 * La vérification est **statique** : elle cherche, dans les fichiers PowerShell,
 * une affectation portant le nom de chaque champ requis. Elle ne prouve pas que
 * la valeur produite est correcte — c'est le rôle de la validation de sortie,
 * qui ne tourne que sur un agent Windows. Elle prouve qu'aucun champ requis n'a
 * été purement oublié, et c'est précisément le défaut qui s'est produit.
 */

const repoRoot = new URL('../../../', import.meta.url);

/**
 * Les fins de ligne sont **normalisées à la lecture**.
 *
 * Ce test compare des sources PowerShell à des expressions régulières écrites
 * avec des sauts de ligne simples. Sur une copie de travail extraite en CRLF —
 * le défaut de Git sous Windows —, plusieurs ne correspondent plus, et le test
 * annonce qu'un champ manque alors qu'il est là. Un contrôle qui dépend de la
 * façon dont le dépôt a été extrait ne contrôle plus rien.
 */
function read(relativePath: string): string {
  return readFileSync(fileURLToPath(new URL(relativePath, repoRoot)), 'utf8').replace(
    /\r\n/g,
    '\n',
  );
}

interface JsonSchemaNode {
  readonly $ref?: string;
  readonly type?: string;
  readonly required?: readonly string[];
  readonly properties?: Readonly<Record<string, JsonSchemaNode>>;
  readonly items?: JsonSchemaNode;
  readonly anyOf?: readonly JsonSchemaNode[];
  readonly oneOf?: readonly JsonSchemaNode[];
  readonly allOf?: readonly JsonSchemaNode[];
  readonly [key: string]: unknown;
}

/**
 * Le schéma est **construit ici**, pas lu sur le disque.
 *
 * Ce test lisait `packages/report-schema/schema/sysaudit-report-latest.schema.json`,
 * un fichier non versionné qu'émet la build de `report-schema`. Or `npm run test`
 * s'exécute **avant** `npm run build`, en CI comme dans `ci:local` : le fichier
 * n'existait qu'en local, laissé par une build précédente. Le test passait donc
 * sur les machines de développement et échouait sur toute installation propre —
 * l'inverse exact de ce qu'on attend d'une barrière.
 */
const schema = buildJsonSchema() as JsonSchemaNode;

/** Sections que le scanner Windows produit réellement aujourd'hui. */
const COVERED_SECTIONS = [
  '$.system',
  '$.os',
  '$.report',
  '$.capabilities',
  '$.motherboard',
  '$.bios',
  '$.cpus[]',
  '$.gpus[]',
  '$.memory',
  '$.memory.modules[]',
  '$.sensors',
  '$.sensors.temperatures[]',
  '$.sensors.fans[]',
  '$.sensors.voltages[]',
  '$.storage',
  '$.storage.disks[]',
  '$.network',
  '$.network.interfaces[]',
  '$.audio',
  '$.audio.devices[]',
  '$.security',
  '$.security.firewall',
  '$.security.updates',
  '$.startup',
  '$.startup.items[]',
  '$.benchmark',
  '$.benchmark.results[]',
  '$.monitoring',
  '$.monitoring.samples[]',
  '$.software',
  '$.software.packages[]',
  '$.software.packageManagers[]',
  '$.software.runtimes[]',
  '$.software.services[]',
  '$.virtualization',
  '$.virtualization.hyperv',
  '$.virtualization.hyperv.guests[]',
  '$.virtualization.docker',
  '$.virtualization.docker.containers[]',
  '$.collection',
] as const;

function resolve(node: JsonSchemaNode): JsonSchemaNode {
  let current = node;
  while (typeof current.$ref === 'string') {
    let target: unknown = schema;
    for (const part of current.$ref.split('/').slice(1)) {
      target = (target as Record<string, unknown>)[part];
    }
    current = target as JsonSchemaNode;
  }
  return current;
}

/**
 * Champs requis par chemin, et ensemble des chemins connus du schéma.
 *
 * Les deux sont distingués : une section **sans aucun champ requis** est
 * parfaitement légitime — `network` n'en a pas, tous ses champs ayant une
 * valeur par défaut. Confondre « section absente du schéma » et « section sans
 * champ requis » ferait échouer le contrôle sur une section valide, et
 * apprendrait à l'ignorer.
 */
function requiredByPath(): { required: Map<string, readonly string[]>; paths: Set<string> } {
  const found = new Map<string, readonly string[]>();
  const paths = new Set<string>();

  const walk = (path: string, raw: JsonSchemaNode, depth: number): void => {
    if (depth > 12) return;
    const node = resolve(raw);
    paths.add(path);

    if (node.required !== undefined && !found.has(path)) found.set(path, node.required);

    for (const [key, child] of Object.entries(node.properties ?? {})) {
      walk(`${path}.${key}`, child, depth + 1);
    }
    if (node.items !== undefined) walk(`${path}[]`, node.items, depth + 1);
    for (const branch of [...(node.anyOf ?? []), ...(node.oneOf ?? []), ...(node.allOf ?? [])]) {
      walk(path, branch, depth + 1);
    }
  };

  walk('$', schema, 0);
  return { required: found, paths };
}

const POWERSHELL_FILES = [
  'scanners/windows/sysaudit.ps1',
  'scanners/windows/lib/collectors/system.ps1',
  'scanners/windows/lib/collectors/hardware.ps1',
  'scanners/windows/lib/collectors/storage.ps1',
  'scanners/windows/lib/collectors/network.ps1',
  'scanners/windows/lib/collectors/media.ps1',
  'scanners/windows/lib/collectors/security.ps1',
  'scanners/windows/lib/collectors/software.ps1',
  'scanners/windows/lib/collectors/virtualization.ps1',
  'scanners/windows/lib/collectors/benchmark.ps1',
  'scanners/windows/lib/collectors/monitoring.ps1',
] as const;

const POWERSHELL = POWERSHELL_FILES.map((file) => read(file)).join('\n');

describe('scanner Windows ↔ schéma de rapport', () => {
  const { required, paths } = requiredByPath();

  it.each(COVERED_SECTIONS)('%s : aucun champ requis oublié', (section) => {
    // La section doit exister dans le schéma — sans quoi la liste ci-dessus
    // contiendrait une faute de frappe, et le contrôle passerait sur du vide.
    expect(paths.has(section), `${section} est introuvable dans le JSON Schema`).toBe(true);

    const missing = (required.get(section) ?? []).filter(
      (field) => !new RegExp(`^\\s*${field}\\s*=`, 'm').test(POWERSHELL),
    );

    expect(missing, `champs requis absents du collecteur : ${missing.join(', ')}`).toEqual([]);
  });

  it('n’emploie que des motifs d’absence que le schéma accepte', () => {
    // `reason` est une énumération fermée. Un motif inventé — `NOT_APPLICABLE`,
    // qui semble pourtant naturel — fait refuser le rapport **entier** par
    // `validateReport()`, et l'erreur ne pointe qu'un champ perdu au milieu de
    // huit cents paquets. C'est arrivé : tout rapport Windows de niveau Complète
    // était rejeté à cause d'une seule ligne.
    //
    // Le contrôle est statique, donc il tourne partout — y compris là où le
    // scanner ne peut pas s'exécuter, c'est-à-dire précisément là où ce genre de
    // faute s'écrit.
    /*
     * `-Reason` désigne deux vocabulaires distincts, et c'est voulu : celui
     * d'un **champ** absent (`New-Unknown`, `Get-StringOrUnknown`), contrôlé
     * ici, et celui d'une **collecte** absente (`Add-CollectionIssue`), qui
     * connaît en plus `NOT_REQUESTED`, `TIMEOUT` et `COLLECTOR_ERROR` et que
     * `scanner-contract.test.ts` contrôle de son côté. Les appels du second
     * sont retirés du texte avant la recherche, faute de quoi ce test
     * refuserait des motifs parfaitement valides.
     */
    const invalid = new Map<string, string>();
    for (const file of POWERSHELL_FILES) {
      const source = read(file).replace(/Add-CollectionIssue(?:Once)?(?:[^\n]*`\n)*[^\n]*/g, '');
      for (const match of source.matchAll(/-Reason\s+'([A-Z_]+)'/g)) {
        const reason = match[1];
        if (reason !== undefined && !(UNKNOWN_REASONS as readonly string[]).includes(reason)) {
          invalid.set(reason, file);
        }
      }
    }

    expect(
      [...invalid.entries()].map(([reason, file]) => `${reason} (${file})`),
      `motifs valides : ${UNKNOWN_REASONS.join(', ')}`,
    ).toEqual([]);
  });

  it('honore la profondeur approfondie sur les deux sources de capteurs', () => {
    /*
     * Le niveau Complète promet trois relevés par sonde. Le collecteur ne les
     * prenait que sur LibreHardwareMonitor — un composant tiers que presque
     * personne n'a installé. Sur les zones thermiques ACPI, qui servent partout
     * ailleurs, `sampleCount` était écrit 1 en dur : la Complète rendait donc
     * exactement ce que rendait la Normale, tout en l'annonçant plus profonde.
     *
     * C'est le défaut que la matrice des niveaux existe pour empêcher —
     * promettre plus que ce qui est collecté —, et il vivait sous la matrice,
     * dans le collecteur.
     */
    const source = read('scanners/windows/lib/collectors/hardware.ps1');
    const acpi = source.slice(source.indexOf('function Get-AcpiThermalReadings'));

    // Le contrôle vise l'affectation, pas la chaîne : « sampleCount = 1 »
    // apparaît légitimement dans le commentaire qui raconte le défaut, et un
    // test qui l'interdirait punirait l'explication plutôt que la régression.
    expect(acpi, 'la source ACPI ignore le nombre de passes demandé').toContain('[int]$Passes = 1');
    expect(acpi, 'sampleCount ne compte plus les relevés').toContain('sampleCount = $values.Count');
    expect(source, 'la source ACPI n’est plus alimentée par la profondeur').toContain(
      '-Passes $passes',
    );
  });

  it('ne compte pas un service arrêté comme une donnée manquante', () => {
    /*
     * Docker Desktop passe l'essentiel de son temps éteint sur un poste
     * ordinaire. Un démon arrêté signifie « aucun conteneur en exécution » —
     * la question a une réponse, ce n'est pas une lecture qui a échoué. Classer
     * ce cas `NOT_AVAILABLE` faisait sortir `partial` un poste Windows aux
     * trois niveaux, et revenait à exiger qu'on démarre Docker pour obtenir un
     * audit propre : le `partial` fabriqué que ce produit s'interdit.
     *
     * Le démon **actif** qui ne répond pas reste un vrai manque, et les deux
     * branches doivent donc coexister dans le collecteur.
     */
    const source = read('scanners/windows/lib/collectors/virtualization.ps1');

    expect(source).toContain("-Reason 'NOT_APPLICABLE'");
    expect(source, 'la distinction service actif / arrêté a disparu').toMatch(
      /Get-Service -Name 'com\.docker\.service'/,
    );
  });

  it('n’échappe pas les antislashs d’une requête ASSOCIATORS', () => {
    /*
     * `Get-CimInstance -Query` prend le chemin **tel quel**.
     *
     * `\\.\PHYSICALDRIVE2` trouve ses partitions ; la même chaîne aux
     * antislashs doublés échoue sur « Non trouvé ». Le doublement venait de WQL
     * passé à `wmic`, où il était juste, et faisait manquer **toutes** les
     * partitions de **tous** les disques, sur toutes les machines Windows.
     * Personne ne pouvait le voir sans exécuter le scanner sur un vrai poste :
     * la requête est syntaxiquement correcte, elle ne rend simplement rien.
     */
    for (const file of POWERSHELL_FILES) {
      const associators = [...read(file).matchAll(/ASSOCIATORS OF[^\n]*/g)].map((m) => m[0]);
      for (const query of associators) {
        expect(query, `${file} : la requête double ses antislashs`).not.toContain("Replace('\\'");
      }
    }
  });

  it('couvre toutes les sections que le scanner déclare produire', () => {
    /**
     * Sections qu'aucun collecteur Windows ne produit, et qui ont donc le droit
     * d'être ignorées à tous les niveaux.
     *
     * La liste est vide, et c'est le fait à retenir : depuis le collecteur PnP,
     * chaque section de la matrice a son collecteur. Un ajout ici doit
     * s'accompagner d'un motif écrit dans `SCANNER_SECTION_CAPS`.
     */
    const COLLECTORLESS_SECTIONS: readonly string[] = [];

    /** Lignes de la matrice, section par section, profondeurs séparées. */
    function matrixRows(source: string): readonly (readonly [string, readonly string[]])[] {
      const block = /\$script:LevelMatrix = @'\r?\n([\s\S]*?)\r?\n'@/.exec(source)?.[1] ?? '';
      return block
        .split('\n')
        .map((line) => line.trim())
        .filter((line) => line.length > 0)
        .map((line) => {
          const [section, ...depths] = line.split(/\s+/);
          return [section as string, depths] as const;
        });
    }

    // Les sections ignorées ne sont plus énumérées dans l'orchestrateur : elles
    // se lisent dans la matrice des niveaux, qui décide aussi du branchement.
    // Une section retirée de la matrice sans collecteur correspondant sortirait
    // silencieusement du contrôle.
    const matrix = read('scanners/windows/lib/core/levels.ps1');

    // `power` avait quitté cette liste quand le plan d'alimentation et les
    // batteries sont devenus collectables sous Windows ; `devices` et `drivers`
    // l'ont quittée à leur tour avec le collecteur PnP de la v0.113.0.
    //
    // Ce qui reste hors de portée n'est plus une section entière mais des
    // champs — le compteur de cycles que `Win32_Battery` ne publie pas, la
    // largeur des liens PCIe que CIM n'expose pas — et cela se lit champ par
    // champ dans le rapport, avec son marqueur.
    //
    // Le contrôle porte donc désormais sur l'inverse : **aucune** section de la
    // matrice Windows ne doit être ignorée à tous les niveaux sans que le
    // scanner ait un collecteur pour elle.
    for (const [section, depths] of matrixRows(matrix)) {
      if (depths.every((depth) => depth === 'skipped')) {
        expect(
          COLLECTORLESS_SECTIONS,
          `${section} est ignorée à tous les niveaux sans motif déclaré`,
        ).toContain(section);
      }
    }

    // `firmware` ne figure dans aucune matrice : aucun scanner ne la produit,
    // faute de source constructeur. Elle est donc déclarée en dur.
    const orchestrator = read('scanners/windows/sysaudit.ps1');
    expect(/\$skippedSections = @\(([^)]*)\)/.exec(orchestrator)?.[1] ?? '').toContain('firmware');
  });
});
