// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { z } from 'zod';
import { isoDateTime, maybe, mediumText, positiveInt, shortText } from '../primitives.js';

const enabledState = z.enum(['ENABLED', 'DISABLED', 'UNSUPPORTED', 'PARTIAL']);

export const firewallSchema = z.object({
  /** Moteur détecté : `ufw`, `firewalld`, `nftables`, `iptables`, `windows-firewall`. */
  engine: maybe(shortText),
  state: maybe(enabledState),
  defaultInputPolicy: maybe(shortText),
  /** Nombre de règles, pas leur contenu : une règle peut révéler la topologie. */
  ruleCount: maybe(positiveInt),
  profiles: z
    .array(
      z.object({
        name: shortText,
        state: maybe(enabledState),
      }),
    )
    .max(16)
    .optional(),
});

/**
 * Configuration SSH. Seuls des indicateurs de politique sont collectés :
 * aucune clé, aucun `authorized_keys`, aucun hôte connu.
 */
export const sshSchema = z.object({
  installed: z.boolean(),
  running: maybe(z.boolean()),
  port: maybe(z.number().int().min(1).max(65535)),
  permitRootLogin: maybe(shortText),
  passwordAuthentication: maybe(z.boolean()),
  pubkeyAuthentication: maybe(z.boolean()),
  protocolVersion: maybe(shortText),
});

export const updatesSchema = z.object({
  /** Nombre de mises à jour en attente, toutes catégories. */
  pending: maybe(positiveInt),
  securityPending: maybe(positiveInt),
  rebootRequired: maybe(z.boolean()),
  lastCheck: maybe(isoDateTime),
  lastUpdate: maybe(isoDateTime),
  automaticUpdates: maybe(enabledState),
});

/**
 * Ce qu'un produit de sécurité **fait réellement**, par-delà sa présence.
 *
 * Les trois booléens historiques — installé, à jour, temps réel — ne savaient
 * pas dire l'état qui compte le plus sur Windows : `PASSIVE`. Quand un
 * antivirus tiers prend la main, Defender ne s'arrête pas, il passe en mode
 * passif. Il continue de se mettre à jour, de répondre aux requêtes, et de
 * n'analyser aucun fichier à l'ouverture. `enabled: true` avec
 * `realtimeProtection: false` décrivait cet état sans le nommer, et rien ne le
 * distinguait d'un produit dont l'utilisateur a simplement coupé la protection
 * temps réel — qui est, lui, une anomalie.
 *
 * - `ACTIVE` — en fonctionnement, protection temps réel active ;
 * - `PASSIVE` — en fonctionnement **sans** protection temps réel, parce qu'un
 *   autre produit l'assure. Normal, et à ne pas signaler ;
 * - `DISABLED` — installé, arrêté ou désactivé. Personne ne protège ;
 * - `OUTDATED` — en fonctionnement, mais avec des signatures périmées ;
 * - `INSTALLED_UNKNOWN_STATE` — le produit est là, son état ne se lit pas ;
 * - `UNAVAILABLE` — l'état n'a pas pu être interrogé du tout. **Distinct de
 *   `DISABLED`** : c'est le scanner qui n'a pas su, pas la machine qui est nue,
 *   et le score ne doit pas les confondre.
 */
export const securityProductStateSchema = z.enum([
  'ACTIVE',
  'PASSIVE',
  'DISABLED',
  'OUTDATED',
  'INSTALLED_UNKNOWN_STATE',
  'UNAVAILABLE',
]);

/**
 * Nature du produit — **tout ce qui protège n'est pas un antivirus**.
 *
 * La distinction n'est pas doctrinale, elle change le diagnostic. Une machine
 * qui n'a que `clamscan` installé, sans `clamd`, n'a aucune protection à
 * l'ouverture des fichiers : elle a un outil d'analyse manuelle. La compter
 * comme protégée donnerait une fausse assurance ; la compter comme nue
 * effacerait un outil réellement présent. `ON_DEMAND_SCANNER` dit exactement ce
 * qu'il en est.
 *
 * Un EDR relève de la même prudence : il surveille des comportements et
 * remonte des alertes, sans nécessairement bloquer un fichier vérolé à
 * l'écriture. La roadmap l'interdit explicitement — « ne pas confondre EDR ou
 * agent de sécurité avec antivirus temps réel ».
 */
export const securityProductKindSchema = z.enum([
  'ANTIVIRUS',
  'ON_DEMAND_SCANNER',
  'EDR',
  'FIREWALL',
  'IDS_IPS',
  'UNKNOWN',
]);

/**
 * Interface réellement interrogée.
 *
 * Elle porte une valeur de preuve différente selon les cas, et le lecteur doit
 * pouvoir en juger. Le Centre de sécurité Windows tient un registre des
 * produits déclarés — c'est une source d'autorité. Une entrée de gestionnaire
 * de paquets prouve seulement qu'un paquet est installé, ce qui ne dit rien de
 * son exécution.
 */
export const securityProductSourceSchema = z.enum([
  'WINDOWS_SECURITY_CENTER',
  'DEFENDER_POWERSHELL',
  'PACKAGE_MANAGER',
  'SERVICE_MANAGER',
  'PROCESS_LIST',
  'PRODUCT_CLI',
]);

export const antivirusSchema = z.object({
  name: shortText,
  enabled: maybe(z.boolean()),
  upToDate: maybe(z.boolean()),
  realtimeProtection: maybe(z.boolean()),
  lastScan: maybe(isoDateTime).optional(),
  /** Éditeur, lorsque la source le nomme. Jamais déduit du nom du produit. */
  vendor: maybe(shortText).optional(),
  /** Version du produit, distincte de celle des signatures. */
  version: maybe(shortText).optional(),
  /**
   * État consolidé. Facultatif : un rapport produit par un scanner antérieur
   * n'en porte pas, et son absence ne dit rien de plus que « scanner plus
   * ancien ». Les trois booléens restent la source de vérité de ce qui a été
   * mesuré ; celui-ci est la lecture qu'en fait le collecteur, qui dispose
   * d'informations — le mode d'exécution de Defender — que les booléens ne
   * savent pas porter.
   */
  state: securityProductStateSchema.optional(),
  kind: securityProductKindSchema.optional(),
  source: securityProductSourceSchema.optional(),
  /**
   * Le démon de protection temps réel tourne-t-il ?
   *
   * Distinct de `realtimeProtection`, qui dit si la fonction est **activée**.
   * Un ClamAV dont `clamd` est installé mais arrêté a la fonction disponible et
   * personne pour l'exécuter.
   */
  daemonRunning: maybe(z.boolean()).optional(),
  /** Date des signatures, quand la source l'expose. */
  signatureDate: maybe(isoDateTime).optional(),
});

/** Comptes utilisateurs — jamais de hash, jamais de mot de passe (§30). */
export const accountSchema = z.object({
  name: shortText,
  /** Anonymisé lorsque `--anonymize` est actif. */
  admin: maybe(z.boolean()),
  enabled: maybe(z.boolean()),
  /** Le compte peut-il s'authentifier sans mot de passe ? */
  passwordless: maybe(z.boolean()),
  lastLogin: maybe(isoDateTime).optional(),
});

/** Sécurité spécifique à Windows (§26). */
export const windowsSecuritySchema = z.object({
  defender: antivirusSchema.optional(),
  thirdPartyAntivirus: z.array(antivirusSchema).max(16).default([]),
  tpm: maybe(
    z.object({
      present: z.boolean(),
      version: maybe(shortText),
      enabled: maybe(z.boolean()),
      ready: maybe(z.boolean()),
    }),
  ),
  bitlocker: maybe(
    z.object({
      state: enabledState,
      protectedVolumes: z.array(shortText).max(64).default([]),
    }),
  ),
  uac: maybe(enabledState),
  rdp: maybe(
    z.object({
      enabled: z.boolean(),
      networkLevelAuthentication: maybe(z.boolean()),
    }),
  ),
  smb: maybe(
    z.object({
      v1Enabled: maybe(z.boolean()),
      signingRequired: maybe(z.boolean()),
    }),
  ),
  credentialGuard: maybe(enabledState),
  hvci: maybe(enabledState),
  vbs: maybe(enabledState),
  /**
   * Protection DMA du noyau, contre les attaques par port Thunderbolt ou PCIe.
   *
   * `PARTIAL` y signifie « le matériel l'annonce » : `AvailableSecurityProperties`
   * dit ce que la machine **permet**, pas ce qui tourne. Le lire comme
   * `ENABLED` promettrait une protection qui n'est peut-être pas active.
   */
  dmaProtection: maybe(enabledState).optional(),
  /**
   * Smart App Control (Windows 11 22H2 et suivants).
   *
   * `PARTIAL` correspond au mode évaluation : Windows observe l'usage avant de
   * décider. Ce n'est pas une protection, et le compter comme actif
   * surestimerait la posture de sécurité de la machine. Absent sur Windows 10
   * et sur Server — `NOT_APPLICABLE`, pas `NOT_AVAILABLE`.
   */
  smartAppControl: maybe(enabledState).optional(),
  /** Pilotes non signés détectés — indicateur fort de compromission ou de bricolage. */
  unsignedDrivers: maybe(positiveInt),
});

/**
 * Protection contre les tentatives d'intrusion répétées (fail2ban, CrowdSec).
 *
 * Installé et actif sont deux faits distincts : un fail2ban installé mais
 * arrêté ne protège rien, et le confondre avec une absence d'outil enlèverait à
 * l'utilisateur l'information la plus utile — il croit être protégé.
 */
export const intrusionPreventionSchema = z.object({
  /** `fail2ban`, `crowdsec`. */
  name: shortText,
  installed: z.boolean(),
  running: maybe(z.boolean()),
  /**
   * Nombre de prisons ou de scénarios actifs. Nécessite des privilèges sur la
   * plupart des installations ; reste inconnu sans eux.
   */
  activeJails: maybe(positiveInt),
});

/** Sécurité spécifique à Linux (§27). */
export const linuxSecuritySchema = z.object({
  ssh: sshSchema.optional(),
  apparmor: maybe(enabledState),
  selinux: maybe(z.enum(['ENFORCING', 'PERMISSIVE', 'DISABLED', 'UNSUPPORTED'])),
  luks: maybe(
    z.object({
      present: z.boolean(),
      devices: z.array(shortText).max(64).default([]),
    }),
  ),
  /** Comptes disposant de `sudo`, sans détail des règles. */
  sudoUsers: maybe(positiveInt),
  intrusionPrevention: z.array(intrusionPreventionSchema).max(8).optional(),
  /**
   * Produits de sécurité inventoriés.
   *
   * Linux n'a pas d'équivalent du Centre de sécurité Windows : aucun registre
   * ne tient la liste de ce qui protège la machine. L'inventaire se reconstitue
   * source par source — paquets installés, unités systemd, processus, puis la
   * CLI du produit lorsqu'il en a une — et chaque entrée dit laquelle l'a
   * établie, parce qu'elles ne prouvent pas la même chose. Un paquet installé
   * n'est pas un démon qui tourne.
   *
   * La liste est **vide** sur une machine sans produit détecté. Elle n'est pas
   * absente : une liste vide affirme qu'on a cherché, là où son absence dirait
   * seulement qu'on n'a rien collecté.
   */
  securityProducts: z.array(antivirusSchema).max(16).optional(),
  /** Comptes sans mot de passe : anomalie majeure. */
  passwordlessAccounts: maybe(positiveInt),
  kernelHardening: z
    .object({
      /** `kernel.kptr_restrict`, `kernel.dmesg_restrict`… — valeurs, pas contenu. */
      sysctl: z.record(z.string().max(128), shortText).optional(),
    })
    .optional(),
});

export const securitySchema = z.object({
  firewall: firewallSchema.optional(),
  updates: updatesSchema.optional(),
  secureBoot: maybe(enabledState).optional(),
  accounts: z.array(accountSchema).max(512).default([]),
  windows: windowsSecuritySchema.optional(),
  linux: linuxSecuritySchema.optional(),
  /** Protocoles obsolètes encore actifs (`SMBv1`, `TLS 1.0`, `SSHv1`…). */
  obsoleteProtocols: z
    .array(
      z.object({
        name: shortText,
        enabled: z.boolean(),
        note: mediumText.optional(),
      }),
    )
    .max(64)
    .default([]),
});

export type Security = z.infer<typeof securitySchema>;
export type SecurityProduct = z.infer<typeof antivirusSchema>;
export type SecurityProductState = z.infer<typeof securityProductStateSchema>;
export type SecurityProductKind = z.infer<typeof securityProductKindSchema>;
export type SecurityProductSource = z.infer<typeof securityProductSourceSchema>;
export type Firewall = z.infer<typeof firewallSchema>;
export type Updates = z.infer<typeof updatesSchema>;
export type IntrusionPrevention = z.infer<typeof intrusionPreventionSchema>;
