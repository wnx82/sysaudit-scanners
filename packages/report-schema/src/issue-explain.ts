// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { annotationFor } from './field-annotations.js';
import { fieldCatalog, sectionOf } from './field-catalog.js';

/**
 * **Ce qu'un refus de validation dit à la personne qui dépose l'audit.**
 *
 * ## Le message qui a rendu ce fichier nécessaire
 *
 * ```text
 * Le rapport ne respecte pas le schéma SysAudit.
 * {"path":"$.power.batteries.0.cycleCount","message":"Too small: expected number to be >=0"}
 * ```
 *
 * Tout y était — et rien d'utile. Le chemin nomme le champ, pas la pièce ; le
 * message est en anglais, écrit par une bibliothèque de validation pour un
 * développeur ; et surtout, rien ne dit **quoi faire**. La cause réelle était un
 * firmware de batterie qui refusait de compter ses cycles, et le geste correct
 * était de relancer l'audit avec un scanner à jour. Ni l'un ni l'autre ne
 * figurait à l'écran.
 *
 * ## Deux niveaux, et les deux comptent
 *
 * Le détail technique ne disparaît pas : il reste dans la réponse, chemin JSON
 * compris, parce que c'est lui qui permet de diagnostiquer. Il cesse simplement
 * d'être la **seule** chose affichée.
 *
 * ## Pourquoi aucun message n'est écrit champ par champ
 *
 * Parce qu'il y a 534 feuilles au schéma, et qu'une table de messages saisie à
 * la main en couvrirait quelques-unes — celles dont un défaut a déjà été
 * constaté. Les autres continueraient de rendre du JSON brut, c'est-à-dire que
 * le produit serait lisible exactement là où le problème est déjà connu.
 *
 * La phrase se compose donc de trois sources qui existent déjà et que des tests
 * tiennent complètes :
 *
 * - la **section**, lue du chemin, pour dire de quelle pièce on parle ;
 * - le **sens du champ**, pris dans `FIELD_ANNOTATIONS`, dont un test refuse
 *   qu'un champ reste sans annotation ;
 * - la **nature du refus**, tirée du code d'erreur.
 *
 * Ajouter un champ au schéma lui donne donc un message lisible sans qu'une
 * seconde table ait à être tenue à jour.
 */

/** La nature d'un refus, indépendante de la bibliothèque de validation. */
export const VALIDATION_ISSUE_CODES = [
  'VALUE_BELOW_MINIMUM',
  'VALUE_ABOVE_MAXIMUM',
  'VALUE_MISSING',
  'VALUE_WRONG_TYPE',
  'VALUE_NOT_ALLOWED',
  'VALUE_MALFORMED',
] as const;

export type ValidationIssueCode = (typeof VALIDATION_ISSUE_CODES)[number];

/**
 * Nom lisible des sections de premier niveau.
 *
 * Les clés sont les sections du rapport ; une section absente de cette table
 * rend son propre nom, ce qui reste plus lisible qu'un chemin JSON et évite
 * qu'un ajout au schéma se retrouve sans libellé.
 */
export const SECTION_LABELS: Readonly<Record<string, string>> = {
  audio: 'Audio',
  benchmark: 'Banc d’essai',
  bios: 'BIOS',
  boot: 'Démarrage',
  capabilities: 'Capacités du scanner',
  collection: 'Collecte',
  cpus: 'Processeur',
  devices: 'Périphériques',
  drivers: 'Pilotes',
  events: 'Journal d’événements',
  firmware: 'Micrologiciel',
  gpus: 'Carte graphique',
  memory: 'Mémoire',
  monitoring: 'Observation',
  motherboard: 'Carte mère',
  network: 'Réseau',
  notes: 'Remarques',
  os: 'Système',
  platformVersion: 'Version de la plateforme',
  power: 'Alimentation',
  report: 'Rapport',
  scannerVersion: 'Version du scanner',
  schemaVersion: 'Version du format',
  security: 'Sécurité',
  sensors: 'Capteurs',
  shutdown: 'Extinction',
  software: 'Logiciels',
  stability: 'Stabilité',
  startup: 'Démarrage automatique',
  storage: 'Stockage',
  system: 'Machine',
  virtualization: 'Virtualisation',
};

/**
 * Nom lisible de certains champs, par chemin sans index.
 *
 * ## Pourquoi une table partielle, et pourquoi c'est le bon compromis
 *
 * Le schéma a 534 feuilles. Les nommer toutes en français serait une seconde
 * documentation à tenir en phase avec la première, et elle divergerait — c'est
 * le défaut que ce dépôt corrige partout ailleurs.
 *
 * Cette table ne couvre donc que les champs qu'un refus atteint réellement :
 * ceux que le matériel remplit et peut mal remplir. Tout le reste tombe sur le
 * **repli**, qui reste lisible — la section en clair, le nom du champ entre
 * guillemets, et la phrase de `FIELD_ANNOTATIONS` en contexte.
 *
 * Le repli n'est pas un pis-aller à corriger un jour : c'est ce qui garantit
 * qu'un champ ajouté au schéma demain rend déjà un message utile, sans que
 * personne ait à penser à cette table.
 */
export const FIELD_LABELS: Readonly<Record<string, string>> = {
  // Alimentation — la famille par laquelle le défaut est arrivé.
  'power.batteries.cycleCount': 'compteur de cycles de la batterie',
  'power.batteries.chargePercent': 'niveau de charge de la batterie',
  'power.batteries.designCapacityWh': 'capacité de conception de la batterie',
  'power.batteries.fullChargeCapacityWh': 'capacité à pleine charge de la batterie',
  'power.batteries.voltageVolts': 'tension de la batterie',
  'power.powerSupply.units.ratedPowerWatts': 'puissance nominale du bloc d’alimentation',

  // Stockage.
  'storage.disks.sizeBytes': 'capacité du disque',
  'storage.disks.smart.temperatureCelsius': 'température du disque',
  'storage.disks.smart.powerOnHours': 'heures de fonctionnement du disque',
  'storage.disks.smart.wearPercent': 'usure du disque',
  'storage.disks.smart.nvmePercentageUsed': 'usure NVMe du disque',
  'storage.disks.partitions.usagePercent': 'taux d’occupation de la partition',

  // Mémoire.
  'memory.installedBytes': 'quantité de mémoire installée',
  'memory.modules.sizeBytes': 'capacité de la barrette',
  'memory.modules.configuredSpeedMts': 'fréquence configurée de la barrette',
  'memory.modules.voltage': 'tension de la barrette',

  // Réseau.
  'network.interfaces.speedMbps': 'débit négocié de l’interface',
  'network.interfaces.mtu': 'MTU de l’interface',
  'network.interfaces.wifi.signalDbm': 'puissance du signal Wi-Fi',
  'network.interfaces.wifi.signalPercent': 'qualité du signal Wi-Fi',

  // Bancs d'essai.
  'benchmark.results.score': 'score du banc d’essai',
  'benchmark.results.durationMs': 'durée du banc d’essai',
  'benchmark.results.temperatureCelsius': 'température relevée pendant le banc d’essai',

  // Processeur et carte graphique.
  'cpus.temperatureCelsius': 'température du processeur',
  'cpus.usagePercent': 'charge du processeur',
  'gpus.temperatureCelsius': 'température de la carte graphique',
  'gpus.vramBytes': 'mémoire de la carte graphique',
};

/** Un refus, tel qu'il se raconte. */
export interface ExplainedIssue {
  /** Chemin JSON, inchangé. C'est lui qui sert au diagnostic. */
  readonly path: string;
  /** Message de la bibliothèque de validation, inchangé. */
  readonly message: string;
  readonly code: ValidationIssueCode;
  /** Section de premier niveau, en clair. */
  readonly section: string;
  /** Titre court : la pièce concernée, et le champ quand il porte un nom. */
  readonly title: string;
  /** Ce qui s'est passé, en français, sans chemin JSON. */
  readonly userMessage: string;
  /** Ce que le champ décrit, pour qui veut situer. `null` si le schéma se tait. */
  readonly context: string | null;
  /** Le geste qui corrige, quand il y en a un. */
  readonly remediation: string | null;
  readonly received?: unknown;
  readonly minimum?: number;
  readonly maximum?: number;
  readonly expected?: string;
  readonly allowed?: readonly string[];
}

/** Le chemin sans son préfixe `$.` ni ses index de tableau. */
export function normalizeIssuePath(path: string): string {
  return path
    .replace(/^\$\.?/, '')
    .split('.')
    .filter((segment) => !/^\d+$/.test(segment))
    .join('.');
}

/** Le dernier segment nommé d'un chemin : le champ lui-même. */
function champDe(chemin: string): string {
  const segments = normalizeIssuePath(chemin).split('.');
  return segments[segments.length - 1] ?? chemin;
}

/**
 * Le champ accepte-t-il le marqueur « non collecté » ?
 *
 * C'est ce qui décide du conseil donné. Un champ qui l'accepte **aurait pu**
 * porter une absence : si le rapport publie à la place une valeur hors bornes,
 * c'est le scanner qui a mal traduit un aveu du matériel, et la mise à jour du
 * scanner corrige. Un champ qui ne l'accepte pas décrit autre chose, et
 * conseiller la même chose serait une promesse en l'air.
 */
function accepteUnMarqueur(cheminNormalise: string): boolean {
  const catalogue = fieldCatalog();
  const exact = catalogue.find((entree) => entree.path.replace(/\[\]/g, '') === cheminNormalise);
  return exact?.maybeUnknown ?? false;
}

/** Le chemin du catalogue correspondant, index de tableau rétablis. */
function cheminAnnote(cheminNormalise: string): string {
  const catalogue = fieldCatalog();
  const exact = catalogue.find((entree) => entree.path.replace(/\[\]/g, '') === cheminNormalise);
  return exact?.path ?? cheminNormalise;
}

/**
 * La phrase qui décrit le refus, par nature.
 *
 * Construite en « sujet : grief » plutôt qu'en phrase pleine. Ce n'est pas un
 * choix de style : une phrase pleine exigerait un article, donc le genre de
 * chaque libellé — « **le** compteur de cycles », « **la** température » — soit
 * une colonne de plus à tenir sur chaque entrée de `FIELD_LABELS`, et une
 * faute d'accord à chaque oubli. Le deux-points dit la même chose sans rien
 * demander au français.
 */
function phrase(code: ValidationIssueCode, sujet: string, détail: ExplainedIssueParts): string {
  const recu = détail.received === undefined ? '' : ` (valeur reçue : ${String(détail.received)})`;
  switch (code) {
    case 'VALUE_BELOW_MINIMUM':
      return `${sujet} : valeur trop basse${recu}${
        détail.minimum === undefined ? '' : `, le minimum admis étant ${détail.minimum}`
      }.`;
    case 'VALUE_ABOVE_MAXIMUM':
      return `${sujet} : valeur trop haute${recu}${
        détail.maximum === undefined ? '' : `, le maximum admis étant ${détail.maximum}`
      }.`;
    case 'VALUE_MISSING':
      return `${sujet} : absent du rapport, alors que le format l’exige.`;
    case 'VALUE_WRONG_TYPE':
      return `${sujet} : type inattendu${
        détail.expected === undefined ? '' : ` (${détail.expected} attendu)`
      }${recu}.`;
    case 'VALUE_NOT_ALLOWED':
      return `${sujet} : valeur que le format n’admet pas${
        détail.allowed === undefined ? '' : ` (admises : ${détail.allowed.join(', ')})`
      }.`;
    case 'VALUE_MALFORMED':
      return `${sujet} : forme inattendue.`;
  }
}

interface ExplainedIssueParts {
  readonly received?: unknown;
  readonly minimum?: number;
  readonly maximum?: number;
  readonly expected?: string;
  readonly allowed?: readonly string[];
}

/**
 * Le geste qui corrige, ou `null` s'il n'y en a pas d'honnête à proposer.
 *
 * **Rien n'est conseillé au hasard.** Une valeur hors bornes sur un champ qui
 * accepte le marqueur « non collecté » est une traduction ratée d'un aveu du
 * matériel : le scanner à jour la corrige, et c'est vérifiable. Ailleurs, le
 * rapport est abîmé ou modifié, et conseiller « relancez avec la dernière
 * version » serait envoyer répéter une manœuvre qui échouera pareil.
 */
function remediation(code: ValidationIssueCode, marqueurPossible: boolean): string | null {
  const horsBornes = code === 'VALUE_BELOW_MINIMUM' || code === 'VALUE_ABOVE_MAXIMUM';
  if (horsBornes && marqueurPossible) {
    return (
      'Le matériel a rendu une valeur que le scanner aurait dû déclarer indisponible. ' +
      'Relancez l’audit avec la dernière version du scanner.'
    );
  }
  if (code === 'VALUE_MISSING' || code === 'VALUE_MALFORMED') {
    return 'Le fichier semble incomplet ou modifié. Relancez l’audit et déposez le rapport produit.';
  }
  return null;
}

/**
 * Traduit un refus de validation en message lisible, sans rien perdre.
 *
 * `received` est fourni par l'appelant plutôt que relu ici : la valeur refusée
 * se trouve dans le rapport soumis, que ce module n'a pas — et lui faire relire
 * le document entier pour une phrase serait payer cher un confort.
 */
export function explainIssue(
  issue: { readonly path: string; readonly message: string },
  parts: ExplainedIssueParts & { readonly code: ValidationIssueCode },
): ExplainedIssue {
  const normalise = normalizeIssuePath(issue.path);
  const section = sectionOf(normalise);
  const sectionLisible = SECTION_LABELS[section] ?? section;
  const annotation = annotationFor(cheminAnnote(normalise));

  /*
   * Le sujet de la phrase nomme le champ, jamais le sous-arbre.
   *
   * `FIELD_ANNOTATIONS` décrit une famille — « capacité de conception, capacité
   * actuelle, cycles, état de charge » — ce qui situe très bien mais ne dit pas
   * lequel des quatre a échoué. L'employer comme sujet produisait une phrase qui
   * énumérait tout sauf la réponse. Il devient donc le **contexte**, à côté.
   */
  const nomTechnique = champDe(issue.path);
  const libelle = FIELD_LABELS[normalise] ?? `champ « ${nomTechnique} »`;
  const sujet = libelle.charAt(0).toLocaleUpperCase('fr') + libelle.slice(1);
  const titre =
    FIELD_LABELS[normalise] === undefined
      ? sectionLisible
      : `${sectionLisible} — ${FIELD_LABELS[normalise]}`;

  return {
    path: issue.path,
    message: issue.message,
    code: parts.code,
    section,
    title: titre,
    userMessage: phrase(parts.code, sujet, parts),
    context: annotation?.meaning ?? null,
    remediation: remediation(parts.code, accepteUnMarqueur(normalise)),
    ...(parts.received === undefined ? {} : { received: parts.received }),
    ...(parts.minimum === undefined ? {} : { minimum: parts.minimum }),
    ...(parts.maximum === undefined ? {} : { maximum: parts.maximum }),
    ...(parts.expected === undefined ? {} : { expected: parts.expected }),
    ...(parts.allowed === undefined ? {} : { allowed: parts.allowed }),
  };
}
