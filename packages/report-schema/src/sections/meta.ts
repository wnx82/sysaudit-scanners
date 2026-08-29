// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { ANONYMIZED_CATEGORIES, UNKNOWN_REASONS } from '@sysaudit/shared';
import { z } from 'zod';
import { durationMs, isoDateTime, mediumText, shortText } from '../primitives.js';

export const platformSchema = z.enum([
  'linux',
  'windows',
  'macos',
  'freebsd',
  'android',
  'unknown',
]);

export const scannerKindSchema = z.enum([
  'linux',
  'proxmox',
  'windows',
  'windows-legacy',
  'macos',
  'freebsd',
  'android',
]);

/**
 * Disponibilité d'une capacité de collecte sur *cette* machine.
 *
 * `AVAILABLE` plus les raisons d'indisponibilité déjà définies par le produit :
 * un seul vocabulaire pour dire pourquoi une donnée manque, qu'il s'agisse d'un
 * champ ou d'un domaine entier. Deux vocabulaires parallèles finiraient par
 * diverger, et la divergence se lit comme une contradiction du rapport.
 */
export const featureStatusSchema = z.enum(['AVAILABLE', ...UNKNOWN_REASONS]);

/**
 * Ce que le scanner a réellement pu faire sur cette machine. Cette section est
 * indispensable à la lecture du reste du rapport : sans elle, un champ
 * `NOT_AVAILABLE` serait indiscernable d'un composant absent.
 */
export const capabilitiesSchema = z.object({
  platform: platformSchema,
  /** Distribution Linux ou édition Windows telle que rapportée par le système. */
  distribution: shortText.optional(),
  architecture: shortText,
  /** Le scanner s'exécutait-il avec les privilèges administrateur ? */
  privileged: z.boolean(),
  /** Hyperviseur détecté sur lequel *cette* machine tourne (`kvm`, `vmware`…). */
  virtualized: shortText.optional(),
  proxmox: z.boolean(),
  docker: z.boolean(),
  /**
   * Outils et interfaces disponibles au moment du scan.
   * Clé = nom de l'outil (`dmidecode`, `smartctl`, `pvesh`…).
   */
  tools: z.record(z.string().max(64), z.boolean()),
  /**
   * Ce que cette machine sait répondre, domaine par domaine
   * (`events`, `boot`, `shutdown`, `sensors.aggregates`, `security.secureBoot`…).
   *
   * `tools` dit quels **binaires** existent ; ceci dit quelles **questions** ont
   * une réponse. Les deux ne se déduisent pas l'un de l'autre : `journalctl`
   * peut être installé et refuser l'accès faute de privilèges, et une machine
   * sans `smartctl` peut tout de même lire des compteurs de fiabilité par une
   * autre voie. Sans cette table, un lecteur ne peut pas distinguer « SysAudit
   * ne sait pas encore faire ça ici » de « cette machine va mal ».
   */
  features: z.record(z.string().max(64), featureStatusSchema).optional(),
});

/** Métadonnées de production du rapport. */
export const reportMetaSchema = z.object({
  /** Identifiant local généré par le scanner, distinct de l'identifiant public. */
  localId: shortText.optional(),
  generatedAt: isoDateTime,
  /**
   * Durée de production du rapport. Bornée comme toute durée du schéma : au-delà
   * d'un an, la valeur ne mesure plus un audit mais un saut d'horloge, et le
   * refus doit le dire. Non bornée, elle laissait l'erreur porter sur le plus
   * grand entier représentable — un message qui n'apprenait rien à l'exploitant
   * dont le rapport venait d'être rejeté en entier.
   */
  durationMs: durationMs.optional(),
  scannerKind: scannerKindSchema,
  /** Profil d'exécution (`quick`, `standard`, `full`, `stress`, `security`). */
  profile: z.enum(['quick', 'standard', 'full', 'stress', 'security']).default('standard'),
  anonymized: z.boolean(),
  /**
   * Catégories effectivement masquées. Vide si `anonymized` est faux.
   * L'utilisateur doit pouvoir vérifier ce qui a été transformé avant upload.
   */
  anonymizedCategories: z.array(z.enum(ANONYMIZED_CATEGORIES)).default([]),

  /**
   * Comment la collecte s'est déroulée vis-à-vis du réseau.
   *
   * - `online` : la collecte s'inscrivait dans une session qui **prévoyait** de
   *   transmettre (`--upload` / `-Upload`). Que la transmission ait ensuite
   *   réussi ou échoué ne change rien à ce champ.
   * - `offline` : aucune transmission n'était prévue. Le rapport est un fichier,
   *   destiné à être lu, archivé ou déposé plus tard.
   *
   * ## Pourquoi ce champ n'est pas le mode de transport
   *
   * Il décrit **la collecte**, donc la machine et le moment — deux choses qui
   * ne changeront plus. Le mode de transport, lui, décrit ce qu'on fait de ce
   * fichier-ci : il change à chaque envoi, et un rapport archivé puis redéposé
   * ailleurs ne doit pas rejouer un choix pris un autre jour. C'est la règle
   * déjà appliquée à `X-Scan-Visibility` et à `X-Machine-Claim`, qui voyagent
   * en en-tête pour cette raison exacte. Le transport est donc retenu **côté
   * API** (`Scan.transportMode`), jamais ici.
   *
   * ## Pourquoi il est facultatif
   *
   * Les rapports produits avant son introduction n'en portent pas, et un champ
   * absent doit rester lisible comme « non renseigné » plutôt que déduit :
   * conclure `offline` d'une absence ferait passer pour hors ligne tout
   * l'historique déjà en base.
   */
  collectionMode: z.enum(['online', 'offline']).optional(),
});

/**
 * Pourquoi une collecte n'a pas eu lieu — **motif lisible par une machine**.
 *
 * Le message d'une issue disait déjà tout cela, mais en français : personne ne
 * pouvait le relire pour en déduire un statut. Le champ `source` servait
 * d'à-peu-près, en portant tantôt la commande fautive (`smartctl`), tantôt le
 * motif (`profil`, `demande`) — deux sémantiques dans un champ, donc aucune.
 *
 * Le vocabulaire reprend celui d'`UnknownReason` (`@sysaudit/shared`), qui
 * qualifie déjà l'absence d'un **champ**, et y ajoute les trois motifs qui
 * n'ont de sens qu'au niveau d'un **collecteur** : la demande explicite, le
 * délai dépassé et l'échec du collecteur lui-même. Un même mot désigne donc la
 * même chose des deux côtés du rapport.
 *
 * ## Ce que chaque motif engage
 *
 * Les quatre premiers décrivent une absence **voulue ou sans objet** : rien
 * n'a échoué, et un audit qui n'en porte que de ceux-là est un audit réussi.
 * Les deux suivants décrivent une collecte **attendue et manquée**, mais dont
 * la cause est connue et remédiable. Les deux derniers sont des anomalies.
 *
 * C'est cette partition, et elle seule, qui décide du statut d'un audit —
 * voir `collectionTimingOf` dans l'API.
 */
export const collectionIssueReasonSchema = z.enum([
  /** Le niveau de diagnostic choisi ne prévoit pas cette collecte. */
  'NOT_COLLECTED',
  /** Écartée à la demande : `--skip`, ou une option non passée (`--monitor`). */
  'NOT_REQUESTED',
  /** Il n'y a rien à mesurer ici : la question ne se pose pas sur cette machine. */
  'NOT_APPLICABLE',
  /** Aucun scanner ne sait produire cette donnée — limite du produit, pas de la machine. */
  'UNSUPPORTED',
  /** La source existe et refuse la lecture faute de privilèges. */
  'PERMISSION_DENIED',
  /** L'outil, le fichier ou l'API n'existe pas sur ce système. */
  'NOT_AVAILABLE',
  /** La source n'a pas répondu dans le délai imparti. */
  'TIMEOUT',
  /** Le collecteur a échoué, ou n'a rien produit alors qu'il le devait. */
  'COLLECTOR_ERROR',
]);

export const collectionIssueSchema = z.object({
  /** Section concernée (`storage.smart`, `security.firewall`…). */
  section: shortText,
  severity: z.enum(['warning', 'error']),
  message: mediumText,
  /** Commande ou source ayant échoué, sans argument dérivé de données non fiables. */
  source: shortText.optional(),
  /**
   * Motif structuré de l'absence.
   *
   * **Facultatif, et son absence ne se déduit pas.** Les rapports produits
   * avant son introduction n'en portent pas ; un consommateur qui le trouve
   * absent ne sait pas classer l'issue, et doit le dire plutôt que supposer.
   */
  reason: collectionIssueReasonSchema.optional(),
});

/**
 * Provenance d'un champ ou d'un sous-arbre du rapport.
 *
 * Le chemin suit la notation objet du JSON (`audio.devices`, `startup.items`,
 * `storage.disks[0].smart`). Le scanner ne remplit que les chemins utiles : un
 * support structurel existe sans imposer de dupliquer toute l'arborescence.
 */
export const collectionProvenanceSchema = z.object({
  /** Nom de la commande, API ou fichier interrogé. */
  source: shortText,
  /** Manière d'obtenir la valeur (`lecture fichier`, `CIM`, `commande shell`). */
  method: shortText.optional(),
  /** Horodatage de cette lecture. */
  collectedAt: isoDateTime.optional(),
  /** Granularité ou précision quand elle compte (`instantané`, `carte`, `service`). */
  precision: shortText.optional(),
});

/**
 * Ce qu'il est advenu d'un outil externe pendant cet audit.
 *
 * `PRESENT_BEFORE` est le seul état qui interdit toute suppression : un outil
 * que l'utilisateur avait installé lui-même n'appartient pas à SysAudit. C'est
 * la distinction que l'ADR 0008 demande au rapport de porter, et elle ne peut
 * pas être reconstruite après coup — d'où l'inventaire d'avant-collecte.
 */
export const dependencyOutcomeSchema = z.enum([
  /** Déjà installé avant l'audit. Jamais installé ni supprimé par SysAudit. */
  'PRESENT_BEFORE',
  /** Absent avant l'audit, installé par SysAudit après accord explicite. */
  'INSTALLED',
  /** Installation tentée après accord, échouée. `error` dit pourquoi. */
  'INSTALL_FAILED',
  /** Installation proposée, refusée par l'utilisateur. Ne pénalise aucun score. */
  'DECLINED',
  /**
   * Absent, et l'installation n'a pas été proposée — cas par défaut, celui de
   * tout audit sans `--install-deps`. À ne pas confondre avec `DECLINED` : ici
   * la question n'a pas été posée.
   */
  'NOT_OFFERED',
]);

/**
 * Sort de l'outil à la fin de l'audit.
 *
 * `NOT_APPLICABLE` couvre tout ce que SysAudit n'a pas installé : il n'y avait
 * rien à retirer. Un `KEPT` sur un outil préexistant laisserait croire à un
 * choix de conservation, alors qu'aucune décision n'a été prise.
 */
export const dependencyRemovalSchema = z.enum([
  'NOT_APPLICABLE',
  /** Retiré à la demande de l'utilisateur, en fin d'audit. */
  'REMOVED',
  /** Installé puis conservé, sur décision de l'utilisateur. */
  'KEPT',
  /** Retrait demandé et échoué : la machine n'est **pas** revenue à son état initial. */
  'REMOVAL_FAILED',
]);

/**
 * Un outil externe, et tout ce que l'audit en sait.
 *
 * Une seule entrée par outil, plutôt que les huit listes parallèles que
 * décrivait la roadmap (`dependenciesAlreadyPresent`,
 * `dependenciesInstalledBySysAudit`…). Les huit questions se répondent en
 * filtrant cette liste, et la forme normalisée interdit une incohérence que des
 * listes parallèles rendraient possible : un même outil présent à la fois dans
 * « déjà installé » et dans « installé par SysAudit » aurait autorisé une
 * suppression que l'ADR 0008 interdit.
 */
export const dependencyRecordSchema = z.object({
  /** Nom de la commande sondée (`smartctl`, `nvme`, `dmidecode`). */
  tool: shortText,
  /** Nom du paquet dans la famille de cette machine (`smartmontools`). */
  package: shortText.optional(),
  outcome: dependencyOutcomeSchema,
  /** Version relevée, quand l'outil est présent et sait la dire. */
  version: shortText.optional(),
  /** Commande d'installation réellement exécutée, sans le nom du paquet. */
  method: shortText.optional(),
  /** Ce que l'outil débloque, en clair — repris de la table des dépendances. */
  unlocks: mediumText.optional(),
  /**
   * L'outil a-t-il **servi** à cette collecte ? Un outil installé mais inutile
   * est un renseignement à part entière : il ne fallait pas l'installer.
   *
   * **Absent quand la question n'a pas de réponse**, et non `false`. Le scanner
   * Linux le sait : toutes ses commandes externes passent par un point unique,
   * qui note l'invocation au passage. Un scanner sans ce point de passage ne
   * peut pas le déduire, et `false` s'y lirait comme « installé pour rien » —
   * un reproche fabriqué à partir d'une donnée non collectée.
   */
  used: z.boolean().optional(),
  removal: dependencyRemovalSchema.default('NOT_APPLICABLE'),
  /** Cause d'un `INSTALL_FAILED` ou d'un `REMOVAL_FAILED`. */
  error: mediumText.optional(),
});

/**
 * Temps passé dans un collecteur.
 *
 * Sert à calibrer la durée annoncée **avant** l'audit, qui était jusqu'ici une
 * constante écrite à la main : « 5 à 12 minutes » pour le niveau Complète, sans
 * qu'aucune mesure ne l'étaye. Une estimation fausse coûte doublement — elle
 * fait renoncer à un audit court, et fait croire à un blocage sur un audit long.
 *
 * La granularité est le collecteur, pas l'audit : c'est la seule qui réponde à
 * « pourquoi celui-ci a-t-il pris trois minutes ». Un audit dont un seul
 * collecteur explique 80 % du temps se corrige ; un audit qui « dure » ne se
 * corrige pas.
 */
export const collectionTimingSchema = z.object({
  /** Section du rapport produite par ce collecteur (`storage`, `network`). */
  section: shortText,
  /**
   * Durée, en millisecondes. Toujours présente : une mesure non exploitable —
   * horloge qui saute — n'est **pas** enregistrée, plutôt que rapportée à zéro.
   * Un zéro se lirait « instantané » et tirerait chaque médiane vers le bas.
   */
  durationMs: z.number().int().nonnegative(),
});

/**
 * Problèmes rencontrés pendant la collecte. Les remonter explicitement évite de
 * présenter un rapport partiel comme complet.
 */
export const collectionSchema = z.object({
  issues: z.array(collectionIssueSchema).max(500).default([]),
  /** Sections volontairement ignorées (profil choisi, capacité absente). */
  skippedSections: z.array(shortText).max(100).default([]),
  /**
   * Durée par collecteur, dans l'ordre d'exécution.
   *
   * **Vide ne veut pas dire « instantané »** : un scanner qui ne chronomètre
   * rien produit exactement la même liste vide qu'un audit sans collecteur. Le
   * consommateur ne doit donc jamais sommer ce tableau pour en déduire une
   * durée totale — `report.durationMs` existe pour cela, et lui distingue déjà
   * l'absence de mesure du zéro.
   *
   * N'y figurent que les sections passées par le point d'exécution commun du
   * scanner ; celles qu'un niveau n'a pas prévues sont dans `skippedSections`.
   */
  timings: z.array(collectionTimingSchema).max(100).default([]),
  provenance: z.record(z.string().max(256), collectionProvenanceSchema).optional(),
  /**
   * Inventaire des outils externes, avant et après l'audit.
   *
   * Vide sur tout audit qui n'a rien sondé — l'absence de trace ne signifie
   * donc pas « aucun outil manquant », elle signifie « pas d'inventaire ».
   * `dependenciesInspected` lève cette ambiguïté, exactement comme
   * `skippedSections` la lève pour les sections.
   */
  dependencies: z.array(dependencyRecordSchema).max(100).default([]),
  /**
   * L'inventaire des outils a-t-il été fait ? Sans ce drapeau, une liste vide
   * se lirait comme « rien ne manquait », alors qu'elle peut aussi vouloir dire
   * « on n'a pas regardé » — la confusion que ce projet refuse partout ailleurs.
   */
  dependenciesInspected: z.boolean().default(false),
  /**
   * Sections que le niveau choisi prévoyait de collecter.
   *
   * C'est le **dénominateur** de toute mesure de couverture. Sans lui, personne
   * ne peut dire d'un audit qu'il a obtenu « tout ce qu'il devait » : le rapport
   * montre ce qu'il a, jamais ce qu'il visait. Compter les sections présentes
   * répondrait à une autre question, et compter celles du schéma reviendrait à
   * reprocher à un audit Rapide de ne pas être un audit Complet.
   *
   * La liste est **recopiée** de la matrice de niveaux du scanner, pas
   * recalculée par le lecteur : refaire le calcul ailleurs ouvrirait la
   * possibilité que les deux divergent, et c'est le scanner qui sait ce qu'il a
   * décidé de faire.
   *
   * Vide sur les scanners sans niveaux (macOS, BSD, Android) et sur tous les
   * rapports antérieurs : la couverture est alors **non renseignée**, jamais
   * supposée à 100 %.
   */
  plannedSections: z.array(shortText).max(100).default([]),
  /**
   * Toutes les sections que ce scanner sait collecter, niveaux confondus.
   *
   * Répond à la question que `plannedSections` ne pose pas : « qu'aurait donné
   * le niveau le plus poussé ? ». Deux audits d'une même machine à deux niveaux
   * différents portent la même liste ici, et deux listes différentes là.
   */
  knownSections: z.array(shortText).max(100).default([]),
});

export type Capabilities = z.infer<typeof capabilitiesSchema>;
export type FeatureStatus = z.infer<typeof featureStatusSchema>;
export type ReportMeta = z.infer<typeof reportMetaSchema>;
export type CollectionIssue = z.infer<typeof collectionIssueSchema>;
export type CollectionIssueReason = z.infer<typeof collectionIssueReasonSchema>;
export type DependencyOutcome = z.infer<typeof dependencyOutcomeSchema>;
export type DependencyRemoval = z.infer<typeof dependencyRemovalSchema>;
export type DependencyRecord = z.infer<typeof dependencyRecordSchema>;
export type CollectionProvenance = z.infer<typeof collectionProvenanceSchema>;
export type CollectionTiming = z.infer<typeof collectionTimingSchema>;
