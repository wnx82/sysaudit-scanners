// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

/**
 * Outils externes dont dépend la collecte — **source de vérité unique**.
 *
 * Le scanner ne dépend d'aucun outil pour tourner : il tourne partout, et
 * dégrade explicitement. Mais chaque outil absent coûte des données précises,
 * et l'utilisateur n'avait aucun moyen de savoir lesquelles, ni quoi installer
 * pour les obtenir. Ce fichier répond aux deux questions.
 *
 * Il répond aussi à une troisième, qui engage le projet : **rien n'est
 * redistribué**. SysAudit n'embarque aucun binaire tiers, n'en télécharge
 * aucun, et n'installe rien sur la machine auditée — voir
 * `docs/adr/0006-dependances-externes.md`. La colonne « licence » informe donc
 * le lecteur ; elle ne fonde aucune décision de redistribution, faute de
 * redistribution.
 *
 * Comme la matrice de compatibilité et celle des niveaux, cette table est
 * projetée dans `docs/scanners/DEPENDENCIES.md` par `npm run docs:dependencies`, et
 * `tool-dependencies-contract.test.ts` vérifie qu'aucun scanner ne sonde un
 * outil absent d'ici — ni l'inverse.
 */

/** Familles de gestionnaires de paquets couvertes par la table. */
export const PACKAGE_FAMILIES = ['debian', 'rhel', 'arch', 'suse', 'alpine'] as const;
export type PackageFamily = (typeof PACKAGE_FAMILIES)[number];

export const PACKAGE_FAMILY_LABELS: Readonly<Record<PackageFamily, string>> = {
  debian: 'Debian / Ubuntu / Proxmox',
  rhel: 'RHEL / Fedora / Rocky',
  arch: 'Arch / Manjaro',
  suse: 'openSUSE / SLES',
  alpine: 'Alpine',
};

export const PACKAGE_FAMILY_COMMANDS: Readonly<Record<PackageFamily, string>> = {
  debian: 'apt install',
  rhel: 'dnf install',
  arch: 'pacman -S',
  suse: 'zypper install',
  alpine: 'apk add',
};

/**
 * Niveau d'exigence d'un outil.
 *
 * Aucun outil n'est `required` au sens strict — le scanner produit un rapport
 * valide sans aucun d'eux. `required` signifie ici : sans lui, la donnée
 * annoncée n'existe pas du tout, il n'y a aucun repli.
 */
export const TOOL_REQUIREMENTS = ['native', 'recommended', 'optional'] as const;
export type ToolRequirement = (typeof TOOL_REQUIREMENTS)[number];

export const TOOL_REQUIREMENT_LABELS: Readonly<Record<ToolRequirement, string>> = {
  native: 'présent d’office',
  recommended: 'recommandé',
  optional: 'facultatif',
};

export type ToolScanner = 'linux' | 'windows';

export interface ToolDependency {
  /** Clé exacte publiée dans `capabilities.tools` du rapport. */
  readonly id: string;
  /** Nom du projet ou du paquet, quand il diffère de la commande. */
  readonly label: string;
  readonly scanners: readonly ToolScanner[];
  /** Ce que sa présence apporte, en clair. */
  readonly unlocks: string;
  readonly requirement: ToolRequirement;
  /** L'outil exige-t-il les privilèges administrateur pour être utile ? */
  readonly privileges: 'none' | 'root';
  /** Licence déclarée par le projet amont. SysAudit ne redistribue rien. */
  readonly licence: string;
  /** Paquet à installer, par famille. Absent = fourni avec le système. */
  readonly packages?: Readonly<Partial<Record<PackageFamily, string>>>;
  /** Ce que devient la donnée sans lui. Jamais « rien » : toujours un marqueur. */
  readonly fallback: string;
  /**
   * Groupe d'outils interchangeables.
   *
   * Quatre pare-feux répondent à la même question, et une machine n'en fait
   * tourner qu'un. Conseiller d'installer `ufw` à quelqu'un dont `nftables`
   * répond déjà serait un conseil activement mauvais : le groupe permet de
   * ne rien conseiller quand un membre est présent.
   */
  readonly group?: string;
  /**
   * Condition matérielle sous laquelle cet outil a un sens ici.
   *
   * Absente, l'outil vaut pour toute machine — c'est le cas courant. Présente,
   * elle **interdit** de le proposer ailleurs.
   *
   * Le besoin est venu du terrain : `vcgencmd` était proposé à chaque audit sur
   * un poste x86, avec `sudo apt install raspi-utils` à la clé. Le conseil ne
   * pouvait rien apporter — le micrologiciel qu'il interroge n'existe que sur un
   * Raspberry Pi — et il revenait à chaque exécution, ce qui apprend surtout à
   * ne plus lire ces messages.
   *
   * La condition est un identifiant, pas un bout de code : le scanner Linux
   * l'évalue en Bash, et un contrat vérifie que les deux tables déclarent les
   * mêmes.
   */
  readonly appliesWhen?: ToolApplicability;
}

/**
 * Conditions d'applicabilité connues.
 *
 * Fermée volontairement : une condition s'ajoute ici **et** dans
 * `dependency_applies` du scanner, jamais dans un seul des deux.
 */
export const TOOL_APPLICABILITIES = ['raspberry-pi', 'nvme-device'] as const;
export type ToolApplicability = (typeof TOOL_APPLICABILITIES)[number];

/** Comment la condition se lit dans la documentation. */
export const TOOL_APPLICABILITY_LABELS: Readonly<Record<ToolApplicability, string>> = {
  'raspberry-pi': 'proposé sur Raspberry Pi uniquement',
  'nvme-device': 'proposé si un disque NVMe est présent',
};

/**
 * La table.
 *
 * Une ligne par clé de `capabilities.tools`. L'ordre suit l'usage : matériel,
 * stockage, réseau, sécurité, paquets, virtualisation, banc d'essai.
 */
export const TOOL_DEPENDENCIES: readonly ToolDependency[] = [
  // --- Matériel -------------------------------------------------------------
  {
    id: 'dmidecode',
    label: 'dmidecode',
    scanners: ['linux'],
    unlocks: 'Carte mère, BIOS, châssis, socket processeur et modules mémoire (SMBIOS).',
    requirement: 'recommended',
    privileges: 'root',
    licence: 'GPL-2.0-or-later',
    packages: {
      debian: 'dmidecode',
      rhel: 'dmidecode',
      arch: 'dmidecode',
      suse: 'dmidecode',
      alpine: 'dmidecode',
    },
    fallback:
      'Carte mère, BIOS et barrettes marqués `NOT_AVAILABLE` ; le reste du matériel reste collecté.',
  },
  {
    id: 'lscpu',
    label: 'util-linux',
    scanners: ['linux'],
    unlocks: 'Détail processeur : cœurs, fils, caches, fréquences, jeux d’instructions.',
    requirement: 'native',
    privileges: 'none',
    licence: 'GPL-2.0-only',
    fallback: 'Repli sur `/proc/cpuinfo` : modèle et nombre de fils, sans les caches.',
  },
  {
    id: 'lspci',
    label: 'pciutils',
    scanners: ['linux'],
    unlocks: 'Cartes graphiques, périphériques PCI/PCIe, pilotes noyau en service.',
    requirement: 'recommended',
    privileges: 'none',
    licence: 'GPL-2.0-or-later',
    packages: {
      debian: 'pciutils',
      rhel: 'pciutils',
      arch: 'pciutils',
      suse: 'pciutils',
      alpine: 'pciutils',
    },
    fallback: 'Aucun GPU ni périphérique PCI inventorié ; la section le déclare.',
  },
  {
    id: 'lsusb',
    label: 'usbutils',
    scanners: ['linux'],
    unlocks: 'Périphériques USB (niveau Complète).',
    requirement: 'optional',
    privileges: 'none',
    licence: 'GPL-2.0-or-later',
    packages: {
      debian: 'usbutils',
      rhel: 'usbutils',
      arch: 'usbutils',
      suse: 'usbutils',
      alpine: 'usbutils',
    },
    fallback: 'Bus USB déclaré non inventorié.',
  },
  {
    id: 'sensors',
    label: 'lm-sensors',
    scanners: ['linux'],
    unlocks: 'Complète la lecture hwmon des températures, tensions et ventilateurs.',
    requirement: 'optional',
    privileges: 'none',
    licence: 'GPL-2.0-or-later',
    packages: {
      debian: 'lm-sensors',
      rhel: 'lm_sensors',
      arch: 'lm_sensors',
      suse: 'sensors',
      alpine: 'lm-sensors',
    },
    fallback: 'Les capteurs restent lus directement dans `/sys/class/hwmon` : sans perte majeure.',
  },
  // --- Stockage -------------------------------------------------------------
  {
    id: 'lsblk',
    label: 'util-linux',
    scanners: ['linux'],
    unlocks: 'Disques, partitions, systèmes de fichiers, tables de partition.',
    requirement: 'native',
    privileges: 'none',
    licence: 'GPL-2.0-only',
    fallback: 'Aucun disque inventorié : la section `storage` le déclare en erreur.',
  },
  {
    id: 'smartctl',
    label: 'smartmontools',
    scanners: ['linux'],
    unlocks: 'Santé SMART, usure, heures de fonctionnement, numéro de série et firmware disque.',
    requirement: 'recommended',
    privileges: 'root',
    licence: 'GPL-2.0-or-later',
    packages: {
      debian: 'smartmontools',
      rhel: 'smartmontools',
      arch: 'smartmontools',
      suse: 'smartmontools',
      alpine: 'smartmontools',
    },
    fallback: 'Santé disque marquée `NOT_AVAILABLE` : aucune usure, aucun compteur.',
  },
  {
    id: 'nvme',
    label: 'nvme-cli',
    scanners: ['linux'],
    // Sans disque NVMe, il n'y a pas de journal NVMe à lire : le paquet
    // s'installerait pour ne rien débloquer.
    appliesWhen: 'nvme-device',
    unlocks: 'Journal SMART NVMe étendu, au-delà de ce que `smartctl` expose.',
    requirement: 'optional',
    privileges: 'root',
    licence: 'GPL-2.0-only',
    packages: {
      debian: 'nvme-cli',
      rhel: 'nvme-cli',
      arch: 'nvme-cli',
      suse: 'nvme-cli',
      alpine: 'nvme-cli',
    },
    fallback: '`smartctl` couvre déjà l’essentiel des compteurs NVMe.',
  },
  {
    id: 'zpool',
    label: 'zfsutils-linux',
    scanners: ['linux'],
    unlocks: 'Pools ZFS : topologie, redondance, état, capacité.',
    requirement: 'optional',
    privileges: 'root',
    licence: 'CDDL-1.0',
    packages: {
      debian: 'zfsutils-linux',
      rhel: 'zfs',
      arch: 'zfs-utils',
      suse: 'zfs',
      alpine: 'zfs',
    },
    fallback: 'Aucun pool ZFS rapporté — ce qui est correct sur une machine sans ZFS.',
  },
  // --- Réseau ---------------------------------------------------------------
  {
    id: 'ip',
    label: 'iproute2',
    scanners: ['linux'],
    unlocks: 'Interfaces, adresses, routes.',
    // Fourni d'office sur un système complet, mais absent de bien des images
    // minimales et des conteneurs : la marquer « présente d'office » ferait
    // taire le seul conseil utile sur ces machines-là.
    requirement: 'recommended',
    privileges: 'none',
    licence: 'GPL-2.0-only',
    packages: { debian: 'iproute2', rhel: 'iproute', arch: 'iproute2', suse: 'iproute2' },
    fallback: 'Aucune interface réseau inventoriée.',
  },
  {
    id: 'ss',
    label: 'iproute2',
    scanners: ['linux'],
    unlocks: 'Ports en écoute et exposition des services (niveau Normale).',
    requirement: 'recommended',
    privileges: 'root',
    licence: 'GPL-2.0-only',
    packages: { debian: 'iproute2', rhel: 'iproute', arch: 'iproute2', suse: 'iproute2' },
    fallback: 'Liste des ports déclarée non collectée — jamais rendue vide.',
  },
  // --- Système et sécurité --------------------------------------------------
  {
    id: 'hostnamectl',
    label: 'systemd',
    scanners: ['linux'],
    unlocks: 'Identité machine, châssis, version du système.',
    requirement: 'optional',
    privileges: 'none',
    licence: 'LGPL-2.1-or-later',
    fallback: 'Repli sur `/etc/os-release` et `uname`.',
  },
  {
    id: 'systemctl',
    label: 'systemd',
    scanners: ['linux'],
    unlocks: 'Services, TRIM planifié, état des unités.',
    requirement: 'optional',
    privileges: 'none',
    licence: 'LGPL-2.1-or-later',
    fallback: 'Services non inventoriés ; TRIM planifié marqué `NOT_AVAILABLE`.',
  },
  // --- Proxmox : grappe, réplication et haute disponibilité --------------------
  {
    id: 'pvecm',
    label: 'proxmox-ve',
    scanners: ['linux'],
    unlocks: 'État de la grappe : quorum, nombre de nœuds, nom.',
    requirement: 'optional',
    privileges: 'root',
    licence: 'AGPL-3.0-only',
    fallback:
      'Grappe déclarée `UNKNOWN` plutôt que `STANDALONE` : sans `pvecm`, l’isolement d’un nœud ne se distingue pas d’une lecture impossible.',
  },
  {
    id: 'pvesr',
    label: 'proxmox-ve',
    scanners: ['linux'],
    unlocks: 'Réplications ZFS en échec entre nœuds.',
    requirement: 'optional',
    privileges: 'root',
    licence: 'AGPL-3.0-only',
    fallback: 'Réplication marquée `NOT_AVAILABLE` — distincte de « aucune réplication ».',
  },
  {
    id: 'ha-manager',
    label: 'proxmox-ve',
    scanners: ['linux'],
    unlocks: 'État des ressources en haute disponibilité.',
    requirement: 'optional',
    privileges: 'root',
    licence: 'AGPL-3.0-only',
    fallback: 'Haute disponibilité marquée `NOT_AVAILABLE`.',
  },
  {
    id: 'ceph',
    label: 'ceph-common',
    scanners: ['linux'],
    unlocks: 'Santé d’une grappe Ceph hyperconvergée.',
    requirement: 'optional',
    privileges: 'root',
    licence: 'LGPL-2.1-or-later',
    packages: {
      debian: 'ceph-common',
      rhel: 'ceph-common',
      arch: 'ceph',
      suse: 'ceph-common',
      alpine: 'ceph',
    },
    /*
     * Une grappe sans Ceph n'a pas un Ceph en panne : elle n'a pas de Ceph. Le
     * scanner distingue les deux par la présence de `/etc/pve/ceph.conf`, pas
     * par celle du binaire.
     */
    fallback: 'Ceph déclaré absent (`present: false`), et non dégradé.',
  },

  // --- Historique, stabilité, démarrage et arrêt ------------------------------
  {
    id: 'journalctl',
    label: 'systemd',
    scanners: ['linux'],
    unlocks:
      'Historique des incidents, fenêtre réellement couverte par le journal, et déroulement du dernier arrêt.',
    requirement: 'recommended',
    /*
     * `none` décrit le cas *nominal* : sur une machine bien configurée,
     * l'appartenance au groupe `systemd-journal` suffit. Sans elle, `journalctl`
     * ne refuse pas — il rend un journal **vide**, ce qui se lirait comme une
     * machine sans incident. Le scanner teste donc une lecture réelle avant de
     * conclure, et déclare `PERMISSION_DENIED` plutôt que zéro incident.
     */
    privileges: 'none',
    licence: 'LGPL-2.1-or-later',
    fallback:
      'Repli sur `dmesg`, qui ne couvre que le démarrage courant et le seul noyau : la fenêtre annoncée est alors l’uptime, pas la fenêtre demandée.',
  },
  {
    id: 'systemd-analyze',
    label: 'systemd',
    scanners: ['linux'],
    unlocks: 'Durée des phases de démarrage et unités les plus lentes.',
    requirement: 'optional',
    privileges: 'none',
    licence: 'LGPL-2.1-or-later',
    fallback: 'Section `boot` réduite au mode du micrologiciel : aucune durée mesurée.',
  },
  {
    id: 'coredumpctl',
    label: 'systemd-coredump',
    scanners: ['linux'],
    unlocks: 'Vidanges mémoire recensées : exécutable, signal et date — jamais leur contenu.',
    requirement: 'optional',
    privileges: 'root',
    licence: 'LGPL-2.1-or-later',
    packages: {
      debian: 'systemd-coredump',
      rhel: 'systemd-udev',
      arch: 'systemd',
      suse: 'systemd-coredump',
      alpine: 'systemd',
    },
    fallback: 'Aucune vidange recensée — ce qui est correct sur une machine sans systemd-coredump.',
  },
  {
    id: 'dmesg',
    label: 'util-linux',
    scanners: ['linux'],
    unlocks: 'Anneau du noyau, quand journald est absent : erreurs matérielles et de stockage.',
    requirement: 'optional',
    /*
     * `kernel.dmesg_restrict=1` est le défaut sur Ubuntu et Debian récents :
     * sans privilèges, la lecture échoue. C'est un refus d'accès, jamais une
     * absence d'incident.
     */
    privileges: 'root',
    licence: 'GPL-2.0-or-later',
    fallback: 'Aucun historique noyau si `journalctl` est également absent.',
  },
  {
    id: 'last',
    label: 'util-linux',
    scanners: ['linux'],
    unlocks: 'Nombre de redémarrages observés, lu dans `wtmp`.',
    requirement: 'optional',
    privileges: 'none',
    licence: 'GPL-2.0-or-later',
    fallback: 'Compteur de redémarrages marqué `NOT_AVAILABLE`.',
  },
  {
    id: 'vcgencmd',
    label: 'raspi-utils',
    scanners: ['linux'],
    // Le micrologiciel qu'il interroge n'existe que sur un Raspberry Pi :
    // ailleurs, le paquet ne débloque rien et le conseil est du bruit.
    appliesWhen: 'raspberry-pi',
    unlocks:
      'Bridage et sous-tension d’un Raspberry Pi, tels que le micrologiciel les rapporte — la seule source qui les distingue d’une simple baisse de fréquence.',
    requirement: 'optional',
    privileges: 'none',
    licence: 'BSD-3-Clause',
    packages: {
      debian: 'raspi-utils',
      rhel: 'raspi-utils',
      arch: 'raspberrypi-utils',
      suse: 'raspi-utils',
      alpine: 'raspberrypi-utils',
    },
    fallback:
      'Bridage marqué `NOT_AVAILABLE` : une fréquence basse ne suffit pas à le conclure, un processeur au repos tournant bas sans être bridé.',
  },
  {
    id: 'sshd',
    label: 'OpenSSH',
    scanners: ['linux'],
    unlocks: 'Politique SSH : authentification par mot de passe, connexion root, port.',
    requirement: 'optional',
    privileges: 'root',
    licence: 'BSD-2-Clause',
    fallback: 'Section SSH absente — correcte sur une machine sans serveur SSH.',
  },
  {
    id: 'ufw',
    label: 'ufw',
    scanners: ['linux'],
    unlocks: 'État et politique du pare-feu Ubuntu/Debian.',
    requirement: 'optional',
    privileges: 'root',
    licence: 'GPL-3.0-only',
    packages: { debian: 'ufw', arch: 'ufw', suse: 'ufw' },
    fallback: 'Le pare-feu est cherché via `nft`, `iptables` ou `firewall-cmd`.',
    group: 'firewall',
  },
  {
    id: 'firewall-cmd',
    label: 'firewalld',
    scanners: ['linux'],
    unlocks: 'État et zones du pare-feu RHEL/Fedora.',
    requirement: 'optional',
    privileges: 'root',
    licence: 'GPL-2.0-or-later',
    packages: { rhel: 'firewalld', debian: 'firewalld', suse: 'firewalld' },
    fallback: 'Le pare-feu est cherché via `ufw`, `nft` ou `iptables`.',
    group: 'firewall',
  },
  {
    id: 'nft',
    label: 'nftables',
    scanners: ['linux'],
    unlocks: 'Règles de filtrage nftables, politique par défaut.',
    requirement: 'optional',
    privileges: 'root',
    licence: 'GPL-2.0-only',
    packages: { debian: 'nftables', rhel: 'nftables', arch: 'nftables', suse: 'nftables' },
    fallback: 'Repli sur `iptables` ; sinon pare-feu marqué inconnu, jamais « désactivé ».',
    group: 'firewall',
  },
  {
    id: 'iptables',
    label: 'iptables',
    scanners: ['linux'],
    unlocks: 'Règles de filtrage héritées, sur les systèmes sans nftables.',
    requirement: 'optional',
    privileges: 'root',
    licence: 'GPL-2.0-only',
    packages: { debian: 'iptables', rhel: 'iptables', arch: 'iptables', suse: 'iptables' },
    fallback: 'Pare-feu marqué inconnu — pas « désactivé », la nuance est le sujet.',
    group: 'firewall',
  },
  // --- Paquets --------------------------------------------------------------
  {
    id: 'apt',
    label: 'APT',
    scanners: ['linux'],
    unlocks: 'Mises à jour en attente et mises à jour de sécurité (Debian/Ubuntu).',
    requirement: 'native',
    privileges: 'none',
    licence: 'GPL-2.0-or-later',
    fallback: 'Mises à jour marquées `NOT_AVAILABLE`.',
  },
  {
    id: 'dpkg',
    label: 'dpkg',
    scanners: ['linux'],
    unlocks: 'Inventaire des paquets installés (niveau Complète).',
    requirement: 'native',
    privileges: 'none',
    licence: 'GPL-2.0-or-later',
    fallback: 'Inventaire logiciel vide sur cette famille.',
  },
  {
    id: 'rpm',
    label: 'RPM',
    scanners: ['linux'],
    unlocks: 'Inventaire des paquets installés (RHEL, Fedora, SUSE).',
    requirement: 'native',
    privileges: 'none',
    licence: 'GPL-2.0-or-later',
    fallback: 'Inventaire logiciel vide sur cette famille.',
  },
  {
    id: 'dnf',
    label: 'DNF',
    scanners: ['linux'],
    unlocks: 'Mises à jour en attente (RHEL, Fedora).',
    requirement: 'native',
    privileges: 'none',
    licence: 'GPL-2.0-or-later',
    fallback: 'Mises à jour marquées `NOT_AVAILABLE`.',
  },
  {
    id: 'pacman',
    label: 'pacman',
    scanners: ['linux'],
    unlocks: 'Paquets installés et mises à jour en attente (Arch).',
    requirement: 'native',
    privileges: 'none',
    licence: 'GPL-2.0-or-later',
    fallback: 'Mises à jour et paquets marqués `NOT_AVAILABLE`.',
  },
  // --- Virtualisation -------------------------------------------------------
  {
    id: 'docker',
    label: 'Docker CLI',
    // Le même client, sous Docker Desktop côté Windows : c'est la même
    // interface en ligne de commande, interrogée par les deux scanners avec les
    // mêmes gabarits. Deux entrées porteraient le même identifiant.
    scanners: ['linux', 'windows'],
    unlocks: 'Conteneurs, images, réseaux, ports publiés.',
    requirement: 'optional',
    privileges: 'root',
    licence: 'Apache-2.0',
    fallback:
      'Aucun conteneur rapporté — correct sur une machine sans Docker. Un client présent dont le démon ne répond pas laisse la section absente, jamais vide.',
  },
  {
    id: 'pveversion',
    label: 'Proxmox VE',
    scanners: ['linux'],
    unlocks: 'Version du nœud Proxmox et activation du module dédié.',
    requirement: 'optional',
    privileges: 'root',
    licence: 'AGPL-3.0-only',
    fallback: 'Module Proxmox désactivé ; la machine est auditée comme un Linux ordinaire.',
  },
  {
    id: 'pvesh',
    label: 'Proxmox VE',
    scanners: ['linux'],
    unlocks: 'Cluster, nœuds et état de la grappe via l’API locale.',
    requirement: 'optional',
    privileges: 'root',
    licence: 'AGPL-3.0-only',
    fallback: 'État du cluster marqué inconnu.',
  },
  {
    id: 'qm',
    label: 'Proxmox VE',
    scanners: ['linux'],
    unlocks: 'Machines virtuelles : configuration, disques, interfaces.',
    requirement: 'optional',
    privileges: 'root',
    licence: 'AGPL-3.0-only',
    fallback: 'Invités KVM non détaillés.',
  },
  {
    id: 'pct',
    label: 'Proxmox VE',
    scanners: ['linux'],
    unlocks: 'Conteneurs LXC : configuration, ressources, montages.',
    requirement: 'optional',
    privileges: 'root',
    licence: 'AGPL-3.0-only',
    fallback: 'Conteneurs LXC non détaillés.',
  },
  {
    id: 'pvesm',
    label: 'Proxmox VE',
    scanners: ['linux'],
    unlocks: 'Stockages déclarés du nœud et leur occupation.',
    requirement: 'optional',
    privileges: 'root',
    licence: 'AGPL-3.0-only',
    fallback: 'Stockages Proxmox non inventoriés.',
  },
  // --- Banc d'essai ---------------------------------------------------------
  {
    id: 'openssl',
    label: 'OpenSSL',
    scanners: ['linux'],
    unlocks: 'Mesures processeur du banc d’essai, pointe et charge soutenue.',
    requirement: 'native',
    privileges: 'none',
    licence: 'Apache-2.0',
    fallback: 'Mesures processeur déclarées écartées, faute d’outil.',
  },
  {
    id: 'dd',
    label: 'coreutils',
    scanners: ['linux'],
    unlocks: 'Mesures mémoire et stockage séquentiel du banc d’essai.',
    requirement: 'native',
    privileges: 'none',
    licence: 'GPL-3.0-or-later',
    fallback: 'Mesures mémoire et stockage déclarées écartées.',
  },
  {
    id: 'fio',
    label: 'fio',
    scanners: ['linux'],
    unlocks: 'Mesure de lecture aléatoire 4 Kio du banc d’essai.',
    requirement: 'optional',
    privileges: 'none',
    licence: 'GPL-2.0-only',
    packages: { debian: 'fio', rhel: 'fio', arch: 'fio', suse: 'fio', alpine: 'fio' },
    fallback: 'Lecture aléatoire déclarée écartée ; les mesures séquentielles restent faites.',
  },
  {
    id: 'glmark2',
    label: 'glmark2',
    scanners: ['linux'],
    unlocks: 'Mesure de rendu GPU du banc d’essai, une par carte détectée.',
    requirement: 'optional',
    privileges: 'none',
    licence: 'GPL-3.0-or-later',
    packages: { debian: 'glmark2', rhel: 'glmark2', arch: 'glmark2', suse: 'glmark2' },
    fallback: 'Mesure GPU déclarée écartée, carte par carte.',
  },
  {
    id: 'nvidia-smi',
    label: 'pilote propriétaire NVIDIA',
    scanners: ['linux'],
    unlocks:
      'Télémétrie GPU NVIDIA pendant la mesure : utilisation, fréquences, VRAM, température, puissance.',
    requirement: 'optional',
    privileges: 'none',
    licence: 'Propriétaire NVIDIA (fourni avec le pilote)',
    fallback: 'Aucune télémétrie GPU ; le score de rendu reste mesuré.',
  },

  // --- Windows --------------------------------------------------------------
  {
    id: 'powershell',
    label: 'Windows PowerShell 5.1+',
    scanners: ['windows'],
    unlocks: 'Le scanner lui-même : il est écrit en PowerShell.',
    requirement: 'native',
    privileges: 'none',
    licence: 'MIT (PowerShell 7) / composant Windows (5.1)',
    fallback: 'Aucun scan possible : c’est l’interpréteur du scanner Windows.',
  },
  {
    id: 'cim',
    label: 'CIM / WMI',
    scanners: ['windows'],
    unlocks: 'Matériel, stockage, réseau, sécurité : la quasi-totalité de la collecte Windows.',
    requirement: 'native',
    privileges: 'none',
    licence: 'Composant Windows',
    fallback: 'Rapport réduit à l’identité machine.',
  },
  {
    id: 'wmi',
    label: 'Get-WmiObject (WMI hérité)',
    scanners: ['windows'],
    unlocks:
      'Repli de collecte sur les systèmes antérieurs à PowerShell 3.0, où `Get-CimInstance` n’existe pas : c’est la même donnée, lue par l’interface précédente.',
    requirement: 'native',
    privileges: 'none',
    licence: 'Composant Windows',
    fallback:
      'Aucune perte tant que CIM répond : le scanner préfère toujours CIM, plus rapide et non déprécié. Sans CIM **et** sans WMI, la lecture porte un marqueur `capability`.',
  },
  {
    id: 'winEvent',
    label: 'Get-WinEvent',
    scanners: ['windows'],
    unlocks:
      'Journaux d’événements filtrés côté service (`-FilterHashtable`) : arrêts inattendus, erreurs disque, incidents matériels.',
    requirement: 'native',
    privileges: 'root',
    licence: 'Composant Windows',
    fallback:
      'Repli sur `Get-EventLog`, qui filtre côté client. Sans les deux, la section des événements est déclarée non collectée — jamais « aucun incident ».',
  },
  {
    id: 'eventLog',
    label: 'Get-EventLog',
    scanners: ['windows'],
    unlocks:
      'Lecture des journaux classiques sur les systèmes où `Get-WinEvent` est absent (Windows 7 / Server 2008 sans mise à jour du framework).',
    requirement: 'native',
    privileges: 'root',
    licence: 'Composant Windows',
    fallback:
      'Aucune perte quand `Get-WinEvent` répond, qui reste préféré. Sans les deux, la section des événements est déclarée non collectée.',
  },
  {
    id: 'getComputerInfo',
    label: 'Get-ComputerInfo',
    scanners: ['windows'],
    unlocks: 'Édition, build et informations de démarrage sécurisé.',
    requirement: 'native',
    privileges: 'none',
    licence: 'Composant Windows',
    fallback: 'Repli sur CIM : quelques champs restent inconnus.',
  },
  {
    id: 'netFirewall',
    label: 'Module NetSecurity',
    scanners: ['windows'],
    unlocks: 'Profils du pare-feu Windows et leur état.',
    requirement: 'native',
    privileges: 'root',
    licence: 'Composant Windows',
    fallback: 'Pare-feu marqué inconnu — jamais « désactivé ».',
  },
  {
    id: 'netAdapter',
    label: 'Module NetAdapter',
    scanners: ['windows'],
    unlocks: 'Débit négocié, duplex et état des cartes réseau.',
    requirement: 'native',
    privileges: 'none',
    licence: 'Composant Windows',
    fallback: 'Repli sur CIM : le duplex reste inconnu.',
  },
  {
    id: 'bitlocker',
    label: 'Module BitLocker',
    scanners: ['windows'],
    unlocks: 'État du chiffrement de disque et volumes protégés.',
    requirement: 'native',
    privileges: 'root',
    licence: 'Composant Windows',
    fallback: 'Chiffrement marqué inconnu ; absent des éditions Famille.',
  },
  {
    id: 'defender',
    label: 'Module Defender',
    scanners: ['windows'],
    unlocks: 'État de l’antivirus, protection en temps réel, dernière analyse.',
    requirement: 'native',
    privileges: 'root',
    licence: 'Composant Windows',
    fallback: 'Antivirus marqué inconnu — un tiers peut avoir remplacé Defender.',
  },
  {
    id: 'tpm',
    label: 'Module TrustedPlatformModule',
    scanners: ['windows'],
    unlocks: 'Présence, version et état du TPM.',
    requirement: 'native',
    privileges: 'root',
    licence: 'Composant Windows',
    fallback: 'TPM marqué inconnu, jamais « absent ».',
  },
  {
    id: 'winsat',
    label: 'WinSAT',
    scanners: ['windows'],
    unlocks: 'Indices processeur, mémoire et Direct3D du banc d’essai.',
    requirement: 'optional',
    privileges: 'root',
    licence: 'Composant Windows',
    fallback:
      'Les débits disque restent mesurés en .NET ; les trois indices sont déclarés non mesurés.',
  },
  {
    id: 'hyperv',
    label: 'Module Hyper-V',
    scanners: ['windows'],
    unlocks: 'Machines virtuelles hébergées : nom, état, cœurs, mémoire, démarrage automatique.',
    requirement: 'optional',
    privileges: 'root',
    licence: 'Composant Windows',
    fallback:
      'Section Hyper-V absente. Sans élévation, elle l’est aussi : une liste vide se lirait comme un hôte sans machine virtuelle.',
  },
  {
    id: 'appx',
    label: 'Module Appx',
    scanners: ['windows'],
    unlocks: 'Applications empaquetées du Store, absentes de la base de désinstallation.',
    requirement: 'optional',
    privileges: 'none',
    licence: 'Composant Windows',
    fallback:
      'Inventaire limité aux logiciels du registre ; absent des éditions Server Core et sans Store.',
  },
  {
    id: 'winget',
    label: 'winget',
    scanners: ['windows'],
    unlocks: 'Constat de la présence du gestionnaire de paquets et de sa version.',
    requirement: 'optional',
    privileges: 'none',
    licence: 'MIT',
    fallback:
      'Le gestionnaire n’est pas listé. Son inventaire n’est de toute façon pas lu : `winget list` ne publie qu’un tableau tronqué à la largeur de la console.',
  },
];

/** Outils du même groupe interchangeable, celui-ci compris. */
export function toolsInGroup(group: string): readonly ToolDependency[] {
  return TOOL_DEPENDENCIES.filter((tool) => tool.group === group);
}

/** Outils sondés par un scanner donné. */
export function toolsForScanner(scanner: ToolScanner): readonly ToolDependency[] {
  return TOOL_DEPENDENCIES.filter((tool) => tool.scanners.includes(scanner));
}

export function toolById(id: string): ToolDependency | undefined {
  return TOOL_DEPENDENCIES.find((tool) => tool.id === id);
}

/**
 * Commande d'installation d'un outil pour une famille donnée.
 *
 * `null` quand l'outil est fourni avec le système : proposer d'installer
 * `util-linux` serait au mieux inutile, au pire dangereux.
 */
export function installCommand(id: string, family: PackageFamily): string | null {
  const tool = toolById(id);
  const packageName = tool?.packages?.[family];
  if (packageName === undefined) return null;
  return `${PACKAGE_FAMILY_COMMANDS[family]} ${packageName}`;
}
