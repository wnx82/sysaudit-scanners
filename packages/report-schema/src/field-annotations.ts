// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

/**
 * Ce que le schéma ne dit pas de ses propres champs.
 *
 * `field-catalog.ts` extrait du schéma Zod tout ce qu'il porte : chemin, type,
 * optionalité, bornes, valeurs admises, acceptation du marqueur « non
 * collecté ». Restent quatre colonnes qu'aucun schéma ne peut porter — le
 * **sens**, l'**outil qui collecte**, la **version d'introduction** et la
 * **confidentialité**. Elles sont ici.
 *
 * ## Pourquoi par sous-arbre et non par champ
 *
 * Une annotation par feuille ferait 534 lignes à tenir à jour, dont la plupart
 * répéteraient la même phrase : les dix-neuf compteurs de
 * `storage.disks[].smart` viennent tous de `smartctl`, ont tous été introduits
 * en même temps, et disent tous la même chose — l'usure du disque telle que le
 * disque la rapporte. Annoter le sous-arbre dit la vérité une fois ; annoter
 * chaque feuille inviterait à laisser dériver les copies.
 *
 * Le lecteur voit la granularité : la table générée affiche le préfixe dont
 * chaque ligne hérite son annotation.
 *
 * ## Ce qui est vérifié, et ce qui ne peut pas l'être
 *
 * `field-annotations.test.ts` refuse un préfixe qui ne désigne plus aucun champ
 * — c'est ce qui empêche cette table de survivre à une refonte du schéma en
 * décrivant des chemins disparus. Il refuse aussi qu'un champ reste sans
 * annotation : une couverture partielle publierait une documentation de format
 * à trous, ce qui est pire qu'une absence assumée.
 *
 * La **version d'introduction** est celle où le sous-arbre est apparu, relevée
 * dans l'historique Git à la date d'ajout de son fichier de section. Le dépôt ne
 * garde aucun historique champ par champ : prétendre à cette précision serait
 * inventer une donnée, ce que le reste du produit refuse.
 */

/**
 * Traitement d'un champ à la lecture par un tiers.
 *
 * - `public` — servi tel quel à quiconque ouvre le rapport.
 * - `restricted` — stocké **en clair**, servi en clair au demandeur et à son
 *   organisation, remplacé par un marqueur pour les autres. C'est le cas des
 *   données qui identifient une machine ou son réseau.
 * - `anonymizable` — remplacé par un pseudonyme stable **à la collecte** si le
 *   scanner a reçu `--anonymize`. Cette perte est définitive : elle a lieu avant
 *   l'envoi, et le propriétaire lui-même ne retrouvera pas la valeur.
 */
export type FieldPrivacy = 'public' | 'restricted' | 'anonymizable';

export interface FieldAnnotation {
  /** Préfixe de chemin ; la correspondance la plus longue l'emporte. */
  readonly prefix: string;
  /** Ce que le champ décrit, en une phrase. */
  readonly meaning: string;
  /** Outils réellement appelés, par plateforme. `null` : section non collectée. */
  readonly collector: { readonly linux: string | null; readonly windows: string | null };
  /** Version de schéma où ce sous-arbre est apparu. */
  readonly since: string;
  readonly privacy?: FieldPrivacy;
  /**
   * Pourquoi ce champ **ne peut pas** exister sur une plateforme, par
   * conception.
   *
   * ## La distinction que ce champ introduit, et pourquoi elle manquait
   *
   * `collector.windows === null` dit aujourd'hui deux choses très différentes
   * sous une seule forme : « ce scanner ne le collecte pas encore » et « ce
   * système ne l'expose pas, et ne l'exposera pas ». La première est une dette,
   * la seconde un fait — et les confondre fait ouvrir des tâches pour combler
   * ce qui n'a pas de fond.
   *
   * L'exemple qui l'a rendue nécessaire : `storage.disks[].link` porte
   * `windows: null`. Ce n'est pas un oubli du scanner PowerShell — CIM n'expose
   * simplement pas la largeur de lien PCIe, et aucune version future ne le
   * fera. La roadmap le notait déjà en marge d'une fixture : « la laisser ferait
   * croire `PRF-005` évaluable sous Windows ».
   *
   * ## Ce que ce champ n'est pas
   *
   * Un fourre-tout pour tout ce qui n'est pas collecté. Il porte une **raison**,
   * et une raison qui tient à la plateforme, pas au calendrier. « Pas encore
   * fait » ne s'écrit pas ici : cela s'écrit dans une roadmap.
   */
  readonly undetectable?: {
    readonly linux?: string;
    readonly windows?: string;
  };
}

const NONE = null;

/**
 * Annotations, du général au particulier.
 *
 * L'ordre du tableau n'a pas d'importance : la résolution prend le préfixe le
 * plus long qui corresponde, jamais le premier trouvé.
 */
export const FIELD_ANNOTATIONS: readonly FieldAnnotation[] = [
  // --- En-tête et métadonnées -------------------------------------------------
  {
    prefix: 'schemaVersion',
    meaning: 'Version du schéma de rapport que ce document respecte.',
    collector: { linux: 'sysaudit.sh', windows: 'sysaudit.ps1' },
    since: '1.0.0',
  },
  {
    prefix: 'scannerVersion',
    meaning: 'Version du scanner qui a produit le rapport.',
    collector: { linux: 'sysaudit.sh', windows: 'sysaudit.ps1' },
    since: '1.0.0',
  },
  {
    prefix: 'platformVersion',
    meaning: 'Version de la plateforme ayant reçu le rapport, ajoutée à l’ingestion.',
    collector: { linux: NONE, windows: NONE },
    since: '1.0.0',
  },
  {
    prefix: 'report',
    meaning: 'Circonstances de l’exécution : quand, avec quel profil, sous quel scanner.',
    collector: { linux: 'sysaudit.sh', windows: 'sysaudit.ps1' },
    since: '1.0.0',
  },
  {
    prefix: 'report.localId',
    meaning:
      'Identifiant produit sur la machine, qui rend un renvoi du même audit inoffensif côté serveur.',
    collector: { linux: 'sysaudit.sh', windows: 'sysaudit.ps1' },
    since: '1.0.0',
  },
  {
    prefix: 'report.anonymized',
    meaning:
      'Vrai si le scanner a été lancé avec --anonymize. La substitution a eu lieu avant l’envoi : elle est irréversible.',
    collector: { linux: 'sysaudit.sh', windows: 'sysaudit.ps1' },
    since: '1.0.0',
  },
  {
    prefix: 'capabilities',
    meaning:
      'Ce que le scanner pouvait faire sur cette machine : privilèges, outils présents, contexte virtualisé. Sert à distinguer « absent » de « pas mesurable ici ».',
    collector: { linux: 'lib/core/capabilities.sh', windows: 'lib/core/capabilities.ps1' },
    since: '1.0.0',
  },
  {
    prefix: 'collection',
    meaning:
      'Journal de la collecte : sections ignorées et incidents rencontrés, avec leur gravité.',
    collector: { linux: 'lib/core/collect.sh', windows: 'lib/core/collect.ps1' },
    since: '1.0.0',
  },
  {
    prefix: 'notes',
    meaning: 'Remarques libres saisies par l’opérateur au lancement.',
    collector: { linux: 'sysaudit.sh --note', windows: 'sysaudit.ps1 -Note' },
    since: '1.0.0',
  },

  // --- Identité et système ----------------------------------------------------
  {
    prefix: 'system',
    meaning: 'Identité de la machine : constructeur, modèle, châssis, temps de fonctionnement.',
    collector: { linux: 'dmidecode, /sys/class/dmi', windows: 'CIM Win32_ComputerSystem' },
    since: '1.0.0',
  },
  {
    prefix: 'system.hostname',
    meaning: 'Nom de la machine sur le réseau.',
    collector: { linux: 'hostname', windows: '$env:COMPUTERNAME' },
    since: '1.0.0',
    privacy: 'restricted',
  },
  {
    prefix: 'system.uuid',
    meaning: 'Identifiant unique inscrit dans le SMBIOS de la carte mère.',
    collector: { linux: 'dmidecode -s system-uuid', windows: 'CIM Win32_ComputerSystemProduct' },
    since: '1.0.0',
    privacy: 'restricted',
  },
  {
    prefix: 'system.serialNumber',
    meaning: 'Numéro de série du châssis — celui que demande un service après-vente.',
    collector: { linux: 'dmidecode -s system-serial-number', windows: 'CIM Win32_BIOS' },
    since: '1.0.0',
    privacy: 'restricted',
  },
  {
    prefix: 'system.fqdn',
    meaning:
      'Nom pleinement qualifié de la machine, lorsque la résolution locale en rend un. Jamais recomposé à partir du nom court et d’un domaine.',
    collector: { linux: 'hostname -f', windows: 'CIM Win32_ComputerSystem' },
    since: '1.25.0',
    privacy: 'restricted',
  },
  {
    prefix: 'system.domain',
    meaning: 'Domaine DNS ou Active Directory dont la machine fait partie.',
    collector: { linux: 'hostname -d', windows: 'CIM Win32_ComputerSystem (PartOfDomain)' },
    since: '1.25.0',
    privacy: 'restricted',
  },
  {
    prefix: 'system.workgroup',
    meaning:
      'Groupe de travail Windows, renseigné uniquement lorsque la machine n’est pas jointe à un domaine.',
    collector: { linux: NONE, windows: 'CIM Win32_ComputerSystem (Workgroup)' },
    since: '1.25.0',
    privacy: 'restricted',
    undetectable: {
      linux: 'notion propre à Windows : un poste Linux n’appartient à aucun groupe de travail SMB',
    },
  },
  {
    prefix: 'system.assetTag',
    meaning:
      'Étiquette d’inventaire du châssis, posée par l’exploitant. Elle nomme un parc et sa numérotation interne, là où le numéro de série ne nomme qu’un exemplaire.',
    collector: { linux: 'dmidecode -t chassis', windows: 'CIM Win32_SystemEnclosure' },
    since: '1.25.0',
    privacy: 'restricted',
  },
  {
    prefix: 'system.machineGuid',
    meaning:
      'Identifiant de l’installation Windows. Il survit à un changement de carte mère et suit un disque cloné : il désigne le système, non le matériel.',
    collector: { linux: NONE, windows: 'HKLM\\SOFTWARE\\Microsoft\\Cryptography' },
    since: '1.25.0',
    privacy: 'restricted',
    undetectable: {
      linux: 'identifiant d’une installation Windows ; il n’a pas d’équivalent Linux',
    },
  },
  {
    prefix: 'system.machineSid',
    meaning: 'SID de la machine, racine des identifiants de ses comptes locaux.',
    collector: { linux: NONE, windows: 'SID du compte Administrateur intégré' },
    since: '1.25.0',
    privacy: 'restricted',
    undetectable: {
      linux: 'les SID sont un mécanisme Windows ; Linux identifie ses comptes par UID',
    },
  },
  {
    prefix: 'os',
    meaning: 'Système installé : famille, édition, version, noyau, date d’installation.',
    collector: { linux: '/etc/os-release, uname', windows: 'CIM Win32_OperatingSystem' },
    since: '1.0.0',
  },
  {
    prefix: 'os.support',
    meaning:
      'Fin de support annoncée par l’éditeur, avec sa source et son degré de confiance. Information externe, jamais mesurée sur la machine.',
    collector: { linux: 'catalogue @sysaudit/platform', windows: 'catalogue @sysaudit/platform' },
    since: '1.0.0',
  },

  // --- Matériel ---------------------------------------------------------------
  {
    prefix: 'motherboard',
    meaning: 'Carte mère : constructeur, modèle, chipset, socket, connecteurs PCIe et mémoire.',
    collector: { linux: 'dmidecode -t baseboard', windows: 'CIM Win32_BaseBoard' },
    since: '1.0.0',
  },
  {
    prefix: 'motherboard.serialNumber',
    meaning: 'Numéro de série de la carte mère.',
    collector: { linux: 'dmidecode -t baseboard', windows: 'CIM Win32_BaseBoard' },
    since: '1.0.0',
    privacy: 'restricted',
  },
  {
    prefix: 'bios',
    meaning: 'Micrologiciel de démarrage : version, date, mode UEFI ou Legacy, Secure Boot.',
    collector: { linux: 'dmidecode -t bios, /sys/firmware/efi', windows: 'CIM Win32_BIOS' },
    since: '1.0.0',
  },
  {
    prefix: 'cpus',
    meaning:
      'Processeurs installés : modèle, cœurs, fréquences, caches, jeux d’instructions et support de virtualisation.',
    collector: { linux: 'lscpu, /proc/cpuinfo', windows: 'CIM Win32_Processor' },
    since: '1.0.0',
  },
  {
    prefix: 'memory',
    meaning: 'Mémoire vive : capacité installée et disponible, connecteurs, espace d’échange.',
    collector: { linux: '/proc/meminfo, dmidecode -t memory', windows: 'CIM Win32_PhysicalMemory' },
    since: '1.0.0',
  },
  {
    prefix: 'memory.modules',
    meaning:
      'Barrettes installées, connecteur par connecteur : capacité, type, fréquence nominale et configurée, ECC, profil XMP/EXPO actif.',
    collector: { linux: 'dmidecode -t memory', windows: 'CIM Win32_PhysicalMemory' },
    since: '1.0.0',
  },
  {
    prefix: 'memory.modules[].serialNumber',
    meaning: 'Numéro de série de la barrette.',
    collector: { linux: 'dmidecode -t memory', windows: 'CIM Win32_PhysicalMemory' },
    since: '1.0.0',
    privacy: 'restricted',
  },
  {
    prefix: 'gpus',
    meaning:
      'Cartes graphiques : modèle, mémoire vidéo, pilote, et — quand un capteur existe — température, charge et fréquences.',
    collector: {
      linux: 'lspci, nvidia-smi, /sys/class/drm',
      windows: 'CIM Win32_VideoController',
    },
    since: '1.0.0',
  },
  {
    prefix: 'gpus[].displays',
    meaning: 'Écrans réellement raccordés à cette carte : définition, taux de rafraîchissement.',
    collector: { linux: 'xrandr, /sys/class/drm', windows: 'CIM WmiMonitorID' },
    since: '1.1.0',
  },
  {
    prefix: 'gpus[].displays[].serialNumber',
    meaning:
      'Numéro de série publié par l’écran dans son EDID — le seul identifiant d’exemplaire d’une dalle.',
    collector: { linux: '/sys/class/drm/*/edid', windows: 'CIM WmiMonitorID' },
    since: '1.25.0',
    privacy: 'restricted',
  },
  {
    prefix: 'audio',
    meaning: 'Contrôleurs et périphériques audio, avec la pile logicielle qui les pilote.',
    collector: { linux: 'pactl, aplay, lspci', windows: 'CIM Win32_SoundDevice' },
    since: '1.13.0',
  },
  {
    prefix: 'sensors',
    meaning:
      'Relevés matériels bruts : températures, ventilateurs, tensions, alimentations. Ce sont les valeurs rendues par les capteurs, sans correction.',
    collector: {
      linux: 'sensors (lm-sensors), /sys/class/hwmon',
      windows: 'CIM MSAcpi/OpenHardware',
    },
    since: '1.0.0',
  },
  {
    prefix: 'sensors.temperatures',
    meaning:
      'Relevés thermiques normalisés : composant mesuré, matériel porteur, interface interrogée, valeur brute d’origine et statistiques des relevés réellement pris. Aucune valeur n’y est estimée.',
    collector: {
      linux: '/sys/class/hwmon, /sys/class/thermal, sensors, smartctl, nvme, nvidia-smi',
      windows: 'LibreHardwareMonitor, OpenHardwareMonitor, SMART/NVMe, nvidia-smi',
    },
    since: '1.23.0',
  },
  {
    prefix: 'sensors.temperatures[].sourcePath',
    meaning:
      'Chemin exact de la sonde interrogée, conservé pour le diagnostic. Une arborescence de périphériques décrit une machine précise : elle n’est servie qu’à son propriétaire.',
    collector: { linux: '/sys/class/hwmon, /sys/class/thermal', windows: NONE },
    since: '1.23.0',
    privacy: 'restricted',
    undetectable: {
      windows:
        'les providers WMI rendent un identifiant de capteur, jamais un chemin de système de fichiers',
    },
  },
  {
    prefix: 'sensors.temperatureCollection',
    meaning:
      'Ce que la collecte thermique a pu faire : sondes rencontrées, exploitables, écartées, et pourquoi rien n’a été relevé le cas échéant.',
    collector: {
      linux: '/sys/class/hwmon, /sys/class/thermal, sensors',
      windows: 'LibreHardwareMonitor, OpenHardwareMonitor',
    },
    since: '1.23.0',
  },
  {
    prefix: 'sensors.temperatureCollection.discardedReadings[].sourcePath',
    meaning:
      'Chemin de la sonde dont la lecture a été écartée. Même traitement que les sondes retenues : réservé au propriétaire.',
    collector: { linux: '/sys/class/hwmon, /sys/class/thermal', windows: NONE },
    since: '1.23.0',
    privacy: 'restricted',
  },
  {
    prefix: 'power',
    meaning:
      'Alimentation secteur et batteries : capacité de conception, capacité actuelle, cycles, état de charge.',
    collector: { linux: '/sys/class/power_supply, upower', windows: NONE },
    since: '1.1.0',
  },
  {
    prefix: 'power.batteries[].serialNumber',
    meaning: 'Numéro de série de la batterie.',
    collector: { linux: '/sys/class/power_supply', windows: NONE },
    since: '1.1.0',
    privacy: 'restricted',
  },
  {
    prefix: 'power.powerSupply',
    meaning:
      'Bloc d’alimentation : ce qu’une source a réellement établi de son identité, ses rails et la consommation des composants. Aucune puissance nominale n’y est déduite d’une consommation observée.',
    collector: {
      linux:
        'dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool',
      windows: 'CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor',
    },
    since: '1.24.0',
  },
  {
    prefix: 'power.powerSupply.units[].serialNumber',
    meaning:
      'Numéro de série du bloc d’alimentation. Il identifie un exemplaire au même titre que celui du châssis ou d’un disque.',
    collector: { linux: 'dmidecode --type 39, ipmitool fru', windows: 'table SMBIOS brute' },
    since: '1.24.0',
    privacy: 'restricted',
  },
  {
    prefix: 'power.powerSupply.units[].assetTag',
    meaning:
      'Étiquette d’inventaire du bloc, posée par l’exploitant. Elle nomme un parc et sa numérotation interne.',
    collector: { linux: 'dmidecode --type 39', windows: 'table SMBIOS brute' },
    since: '1.24.0',
    privacy: 'restricted',
  },
  {
    prefix: 'power.powerSupply.rails[].sourcePath',
    meaning:
      'Chemin exact de la sonde de tension. Même traitement que les sondes thermiques : une arborescence de périphériques décrit une machine précise.',
    collector: { linux: '/sys/class/hwmon', windows: NONE },
    since: '1.24.0',
    privacy: 'restricted',
  },
  {
    prefix: 'power.powerSupply.componentPower[].sourcePath',
    meaning: 'Chemin du compteur d’énergie interrogé, conservé pour le diagnostic.',
    collector: { linux: '/sys/class/powercap, /sys/class/hwmon', windows: NONE },
    since: '1.24.0',
    privacy: 'restricted',
  },

  // --- Stockage ---------------------------------------------------------------
  {
    prefix: 'storage',
    meaning: 'Capacité totale et occupée, et état de la maintenance TRIM.',
    collector: { linux: 'lsblk, df, fstrim', windows: 'CIM Win32_DiskDrive, Get-Volume' },
    since: '1.0.0',
  },
  {
    prefix: 'storage.disks',
    meaning:
      'Disques physiques : modèle, interface, taille, type de média, table de partitions, support du TRIM.',
    collector: { linux: 'lsblk, smartctl', windows: 'Get-PhysicalDisk' },
    since: '1.0.0',
  },
  {
    prefix: 'storage.disks[].serialNumber',
    meaning: 'Numéro de série du disque, utile pour une garantie ou un remplacement.',
    collector: { linux: 'smartctl -i', windows: 'Get-PhysicalDisk' },
    since: '1.0.0',
    privacy: 'restricted',
  },
  {
    prefix: 'storage.disks[].wwn',
    meaning:
      'World Wide Name du support — identifiant mondial lisible sans privilège, là où le numéro de série en demande.',
    collector: { linux: '/sys/block/*/wwid, lsblk -o WWN', windows: 'Get-Disk' },
    since: '1.25.0',
    privacy: 'restricted',
  },
  {
    prefix: 'storage.disks[].nguid',
    meaning: 'Identifiant global de l’espace de noms NVMe, quand le contrôleur en publie un.',
    collector: { linux: '/sys/block/nvme*/nguid', windows: NONE },
    since: '1.25.0',
    privacy: 'restricted',
  },
  {
    prefix: 'storage.disks[].eui64',
    meaning: 'Identifiant IEEE EUI-64 de l’espace de noms NVMe, quand il est publié.',
    collector: { linux: '/sys/block/nvme*/eui', windows: NONE },
    since: '1.25.0',
    privacy: 'restricted',
  },
  {
    prefix: 'storage.disks[].smart',
    meaning:
      'Santé du disque telle que le disque la rapporte : heures d’allumage, secteurs réalloués, usure, erreurs non corrigées. Un compteur non lu est marqué absent, jamais mis à zéro.',
    collector: { linux: 'smartctl -A', windows: 'Get-StorageReliabilityCounter' },
    since: '1.0.0',
  },
  {
    prefix: 'storage.disks[].link',
    meaning: 'Négociation du lien PCIe/SATA : vitesse et largeur obtenues face aux maximales.',
    collector: { linux: '/sys/bus/pci, nvme id-ctrl', windows: NONE },
    since: '1.1.0',
    undetectable: { windows: 'CIM n’expose ni la vitesse ni la largeur de lien PCIe négociées' },
  },
  {
    prefix: 'storage.disks[].partitions',
    meaning: 'Partitions montées : système de fichiers, occupation, chiffrement.',
    collector: { linux: 'lsblk, df, cryptsetup', windows: 'Get-Volume, Get-BitLockerVolume' },
    since: '1.0.0',
  },
  {
    prefix: 'storage.disks[].partitions[].uuid',
    meaning:
      'Identifiant du système de fichiers — clé d’un /etc/fstab, et clé de rapprochement d’un même volume entre deux audits.',
    collector: { linux: 'lsblk -o UUID', windows: 'Get-Volume (UniqueId)' },
    since: '1.25.0',
    privacy: 'restricted',
  },
  {
    prefix: 'storage.disks[].partitions[].partitionUuid',
    meaning:
      'Identifiant de la partition dans la table GPT, distinct de celui du système de fichiers : un reformatage change l’un sans l’autre.',
    collector: { linux: 'lsblk -o PARTUUID', windows: 'Get-Partition (Guid)' },
    since: '1.25.0',
    privacy: 'restricted',
  },
  {
    prefix: 'storage.pools',
    meaning: 'Ensembles logiques — RAID logiciel, LVM, ZFS — avec leur état de redondance.',
    collector: { linux: 'mdadm, lvs, zpool', windows: 'Get-StoragePool' },
    since: '1.4.0',
  },
  {
    prefix: 'firmware',
    meaning:
      'Micrologiciels de composants et mises à jour disponibles. Information externe : elle porte sa source et sa date de vérification.',
    collector: { linux: 'fwupdmgr', windows: NONE },
    since: '1.0.0',
  },

  // --- Réseau -----------------------------------------------------------------
  //
  // Pas d'annotation `network` nue : les sept clés de la section en ont chacune
  // une, et une entrée qui ne serait plus la correspondance la plus longue
  // d'aucun champ décrirait un chemin sans lecteur — ce qu'un test refuse. Un
  // champ ajouté ici sans annotation sera signalé par le test de couverture.
  {
    prefix: 'network.publicIp',
    meaning:
      'Adresse publique (WAN) vue depuis Internet. Collectée uniquement sur demande explicite : c’est le seul champ du rapport dont la lecture émet un paquet vers l’extérieur.',
    collector: { linux: '--public-ip', windows: '-PublicIp' },
    since: '1.0.0',
    privacy: 'restricted',
  },
  {
    prefix: 'network.searchDomains',
    meaning: 'Domaines de recherche DNS — souvent le nom du domaine d’entreprise.',
    collector: { linux: 'resolvectl', windows: 'Get-DnsClientGlobalSetting' },
    since: '1.0.0',
    privacy: 'restricted',
  },
  {
    prefix: 'network.dnsServers',
    meaning:
      'Résolveurs configurés. Sur la quasi-totalité des postes, le premier est la box ou le contrôleur de domaine : son adresse **est** le plan d’adressage local.',
    collector: { linux: 'resolvectl, /etc/resolv.conf', windows: 'Get-DnsClientServerAddress' },
    since: '1.0.0',
    privacy: 'restricted',
  },
  {
    prefix: 'network.interfaces',
    meaning:
      'Cartes réseau : type, état du lien, débit négocié, duplex, VLAN, MTU, pilote, et adresses attribuées.',
    collector: { linux: 'ip -j addr, ethtool', windows: 'Get-NetAdapter' },
    since: '1.0.0',
  },
  {
    prefix: 'network.interfaces[].mac',
    meaning: 'Adresse matérielle de l’interface.',
    collector: { linux: 'ip -j link', windows: 'Get-NetAdapter' },
    since: '1.0.0',
    privacy: 'restricted',
  },
  {
    prefix: 'network.interfaces[].ipv4',
    meaning: 'Adresses IPv4 attribuées à l’interface, avec leur longueur de préfixe.',
    collector: { linux: 'ip -j addr', windows: 'Get-NetIPAddress' },
    since: '1.0.0',
    privacy: 'restricted',
  },
  {
    prefix: 'network.interfaces[].ipv6',
    meaning: 'Adresses IPv6 attribuées à l’interface, avec leur longueur de préfixe.',
    collector: { linux: 'ip -j addr', windows: 'Get-NetIPAddress' },
    since: '1.0.0',
    privacy: 'restricted',
  },
  {
    prefix: 'network.interfaces[].gateway',
    meaning:
      'Passerelle par défaut de l’interface. Protéger les adresses de la machine en publiant sa passerelle ne protège rien : les deux désignent le même réseau.',
    collector: { linux: 'ip route show default', windows: 'Get-NetIPConfiguration' },
    since: '1.0.0',
    privacy: 'restricted',
  },
  {
    prefix: 'network.interfaces[].wifi',
    meaning: 'Lien sans fil en cours : réseau associé, qualité du signal, canal, norme.',
    collector: { linux: 'iw, nmcli', windows: 'netsh wlan' },
    since: '1.0.0',
  },
  {
    prefix: 'network.interfaces[].wifi.ssid',
    meaning: 'Nom du réseau sans fil associé — il situe géographiquement la machine.',
    collector: { linux: 'iw dev', windows: 'netsh wlan show interfaces' },
    since: '1.0.0',
    privacy: 'anonymizable',
  },
  {
    prefix: 'network.listeningPorts',
    meaning:
      'Ports en écoute, avec le processus qui les tient et le fait qu’ils soient joignables hors de la machine.',
    collector: { linux: 'ss -tulpn', windows: 'Get-NetTCPConnection' },
    since: '1.0.0',
  },
  {
    prefix: 'network.listeningPorts[].address',
    meaning:
      'Adresse de liaison. Générique le plus souvent (`0.0.0.0`, `127.0.0.1`), mais un service lié à une interface précise y inscrit l’adresse LAN de la machine. Ce que cette adresse apprend d’utile à un tiers — l’écoute déborde-t-elle la boucle locale — est déjà porté par `exposed`.',
    collector: { linux: 'ss -tulpn', windows: 'Get-NetTCPConnection' },
    since: '1.0.0',
    privacy: 'restricted',
  },
  {
    prefix: 'network.routes',
    meaning:
      'Table de routage : destination, passerelle, interface, métrique. La table entière est retirée à un lecteur non propriétaire, et non expurgée ligne à ligne : une destination `192.168.1.0/24` est le plan d’adressage écrit en toutes lettres, et une route dont la destination et la passerelle seraient toutes deux retenues ne porterait plus qu’un nom d’interface et une métrique.',
    collector: { linux: 'ip -j route', windows: 'Get-NetRoute' },
    since: '1.5.0',
  },
  {
    // `destination` n'est délibérément pas marqué : il vaut `default` aussi
    // souvent qu'un préfixe CIDR, et « default » n'est le secret de personne.
    // Le marquer ferait échouer la couverture de rédaction sur un mot courant
    // présent ailleurs dans le rapport — un test rouge pour une donnée qui ne
    // fuit pas, donc un test qu'on finirait par contourner. Le vidage de la
    // table couvre la destination de fait ; c'est la passerelle qui porte ici
    // l'obligation vérifiable.
    prefix: 'network.routes[].gateway',
    meaning: 'Prochain saut. Même adresse que la passerelle d’interface, par un autre chemin.',
    collector: { linux: 'ip -j route', windows: 'Get-NetRoute' },
    since: '1.5.0',
    privacy: 'restricted',
  },
  {
    prefix: 'network.proxy',
    meaning: 'Mandataire HTTP configuré au niveau du système.',
    collector: {
      linux: 'variables d’environnement, /etc/environment',
      windows: 'Registre WinINET',
    },
    since: '1.5.0',
  },

  // --- Périphériques et pilotes -----------------------------------------------
  {
    prefix: 'devices',
    meaning:
      'Énumération PCI, USB et autres bus : identifiants constructeur, classe, pilote attaché, état.',
    collector: { linux: 'lspci, lsusb', windows: NONE },
    since: '1.0.0',
  },
  {
    prefix: 'drivers',
    meaning:
      'Pilotes chargés, avec leur signature et — quand un catalogue le sait — la version disponible en amont.',
    collector: { linux: 'lsmod, modinfo', windows: NONE },
    since: '1.0.0',
  },

  // --- Logiciels --------------------------------------------------------------
  {
    prefix: 'software',
    meaning:
      'Inventaire logiciel : paquets installés, gestionnaires, environnements d’exécution et services.',
    collector: {
      linux: 'dpkg, rpm, snap, flatpak, systemctl',
      windows: 'registre de désinstallation, Get-AppxPackage, Win32_Service',
    },
    since: '1.0.0',
  },
  {
    prefix: 'software.packagesTruncated',
    meaning:
      'Vrai si la liste des paquets a été tronquée. Le compte total reste juste : c’est le détail qui manque, et il est dit.',
    collector: { linux: 'lib/collectors/software.sh', windows: NONE },
    since: '1.0.0',
  },
  {
    prefix: 'startup',
    meaning: 'Éléments lancés au démarrage de la session ou du système, avec leur origine.',
    collector: {
      linux: 'systemd --user, XDG autostart',
      windows: 'Registre Run, Get-ScheduledTask',
    },
    since: '1.13.0',
  },

  // --- Sécurité ---------------------------------------------------------------
  {
    prefix: 'security',
    meaning: 'Posture de sécurité observée : pare-feu, mises à jour, démarrage sécurisé.',
    collector: { linux: 'ufw/firewalld/nft, apt, mokutil', windows: 'Get-NetFirewallProfile' },
    since: '1.0.0',
  },
  {
    prefix: 'security.accounts',
    meaning:
      'Comptes locaux : droits d’administration, activation, absence de mot de passe, dernière connexion.',
    collector: { linux: '/etc/passwd, /etc/shadow (métadonnées)', windows: 'Get-LocalUser' },
    since: '1.0.0',
    privacy: 'restricted',
  },
  {
    prefix: 'security.windows',
    meaning:
      'Contrôles propres à Windows : Defender, TPM, BitLocker, UAC, Credential Guard, RDP, SMB.',
    collector: { linux: NONE, windows: 'Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume' },
    since: '1.0.0',
  },
  {
    prefix: 'security.linux',
    meaning:
      'Contrôles propres à Linux : SSH, AppArmor/SELinux, LUKS, prévention d’intrusion, durcissement noyau.',
    collector: { linux: 'sshd -T, aa-status, sestatus, cryptsetup, sysctl', windows: NONE },
    since: '1.0.0',
  },
  {
    prefix: 'security.linux.intrusionPrevention',
    meaning: 'fail2ban ou CrowdSec : présence, exécution, prisons actives.',
    collector: { linux: 'fail2ban-client, cscli', windows: NONE },
    since: '1.6.0',
  },
  {
    prefix: 'security.obsoleteProtocols',
    meaning: 'Protocoles dépassés encore actifs — chacun est une porte ouverte connue.',
    collector: { linux: 'lib/collectors/security.sh', windows: 'lib/collectors/security.ps1' },
    since: '1.0.0',
  },

  // --- Virtualisation ---------------------------------------------------------
  {
    prefix: 'virtualization',
    meaning:
      'Ce que la machine héberge et ce qui l’héberge : hyperviseur détecté, conteneurs, invités.',
    collector: {
      linux: 'systemd-detect-virt, docker, podman, virsh, pvesh',
      windows: 'Win32_ComputerSystem, Get-VM, docker',
    },
    since: '1.0.0',
  },
  {
    prefix: 'virtualization.docker',
    meaning:
      'Conteneurs Docker : image, état, réseau, ports publiés, montages sensibles et accès au socket.',
    collector: { linux: 'docker inspect', windows: 'docker inspect' },
    since: '1.0.0',
  },
  {
    prefix: 'virtualization.podman',
    meaning: 'Conteneurs Podman, décrits exactement comme les conteneurs Docker.',
    collector: { linux: 'podman inspect', windows: NONE },
    since: '1.6.0',
  },
  {
    prefix: 'virtualization.libvirt',
    meaning: 'Machines virtuelles libvirt : état, vCPU, mémoire, démarrage automatique.',
    collector: { linux: 'virsh list, virsh dominfo', windows: NONE },
    since: '1.6.0',
  },
  {
    prefix: 'virtualization.hyperv',
    meaning:
      'Machines virtuelles Hyper-V hébergées par cette machine : état, vCPU, mémoire, démarrage automatique. À ne pas confondre avec l’hyperviseur qui héberge la machine elle-même.',
    collector: { linux: NONE, windows: 'Get-VM' },
    since: '1.14.0',
  },
  {
    prefix: 'virtualization.proxmox',
    meaning: 'Nœud Proxmox : grappe, machines virtuelles, conteneurs LXC et stockages.',
    collector: { linux: 'pvesh, pvesm, qm, pct', windows: NONE },
    since: '1.0.0',
  },
  {
    prefix: 'virtualization.proxmox.node.name',
    meaning: 'Nom du nœud Proxmox — c’est le nom de la machine, sous un autre chemin.',
    collector: { linux: 'pvesh get /nodes', windows: NONE },
    since: '1.0.0',
    privacy: 'restricted',
  },

  // --- Mesures dans la durée --------------------------------------------------
  {
    prefix: 'monitoring',
    meaning:
      'Échantillons relevés pendant toute la durée de l’audit : charge processeur, température, mémoire, disque et réseau. Une série, non une moyenne.',
    collector: {
      linux: 'lib/collectors/monitoring.sh',
      windows: 'lib/collectors/monitoring.ps1',
    },
    since: '1.7.0',
  },
  {
    prefix: 'monitoring.samples[].cpuCoreVoltageVolts',
    meaning:
      'Tension d’alimentation du cœur processeur au moment du relevé. Lue avec la fréquence et la puissance, elle distingue un bridage thermique d’un bridage par limite de puissance : la fréquence chute dans les deux cas, la tension seulement dans le second.',
    collector: { linux: 'hwmon (`in*_input`)', windows: 'LibreHardwareMonitor si présent' },
    since: '1.18.0',
  },
  {
    prefix: 'monitoring.samples[].cpuPackagePowerWatts',
    meaning:
      'Puissance consommée par le paquet processeur pendant le relevé. C’est la grandeur que le micrologiciel plafonne (PL1/PL2) ; sans elle, une fréquence basse reste inexpliquée.',
    collector: { linux: 'RAPL (`/sys/class/powercap/intel-rapl`)', windows: 'compteurs CIM' },
    since: '1.18.0',
  },
  {
    prefix: 'monitoring.samples[].gpuTemperatureCelsius',
    meaning: 'Température du GPU au relevé, capteur principal.',
    collector: { linux: 'nvidia-smi, hwmon amdgpu', windows: 'compteurs du pilote' },
    since: '1.18.0',
  },
  {
    prefix: 'monitoring.samples[].gpuHotspotCelsius',
    meaning:
      'Point le plus chaud de la puce, distinct de la température de bord. L’écart entre les deux est ce qui révèle un contact pâte thermique dégradé ; publier une moyenne l’effacerait.',
    collector: { linux: 'hwmon amdgpu (`junction`)', windows: 'compteurs du pilote' },
    since: '1.18.0',
  },
  {
    prefix: 'monitoring.samples[].gpuCoreClockMhz',
    meaning: 'Fréquence du cœur graphique à l’instant du relevé.',
    collector: { linux: 'nvidia-smi, sysfs amdgpu', windows: 'compteurs du pilote' },
    since: '1.18.0',
  },
  {
    prefix: 'monitoring.samples[].gpuMemoryClockMhz',
    meaning: 'Fréquence de la mémoire graphique à l’instant du relevé.',
    collector: { linux: 'nvidia-smi, sysfs amdgpu', windows: 'compteurs du pilote' },
    since: '1.18.0',
  },
  {
    prefix: 'monitoring.samples[].gpuCoreVoltageVolts',
    meaning: 'Tension du cœur graphique au relevé — même lecture croisée que côté processeur.',
    collector: { linux: 'hwmon amdgpu', windows: 'LibreHardwareMonitor si présent' },
    since: '1.18.0',
  },
  {
    prefix: 'monitoring.samples[].gpuBoardPowerWatts',
    meaning:
      'Puissance à la carte entière, mémoire et étages d’alimentation compris — non celle de la seule puce.',
    collector: { linux: 'nvidia-smi, hwmon amdgpu', windows: 'compteurs du pilote' },
    since: '1.18.0',
  },
  {
    prefix: 'monitoring.samples[].cpuThrottleReason',
    meaning:
      'Motif du bridage, tel que le matériel le publie — thermique, plafond de puissance, plafond de courant, sous-tension. `cpuThrottled` dit qu’il y a bridage, celui-ci dit lequel : nettoyer un ventilateur ne corrige pas un plafond de puissance, et l’inverse non plus.',
    collector: {
      linux: 'thermal_throttle, RAPL, vcgencmd get_throttled',
      windows: 'LibreHardwareMonitor si présent',
    },
    since: '1.27.0',
  },
  {
    prefix: 'monitoring.samples[].gpuUsagePercent',
    meaning: 'Occupation du processeur graphique au relevé.',
    collector: {
      linux: 'nvidia-smi, sysfs amdgpu (`gpu_busy_percent`)',
      windows: 'compteurs du pilote',
    },
    since: '1.27.0',
  },
  {
    prefix: 'monitoring.samples[].gpuVramUsedBytes',
    meaning:
      'Mémoire graphique occupée au relevé. Une charge qui sature la VRAM et une charge qui sature la puce ne se corrigent pas de la même façon.',
    collector: {
      linux: 'nvidia-smi, sysfs amdgpu (`mem_info_vram_used`)',
      windows: 'compteurs du pilote',
    },
    since: '1.27.0',
  },
  {
    prefix: 'monitoring.samples[].gpuThrottleReason',
    meaning:
      'Motif de limitation rapporté par le pilote graphique, jamais déduit d’une fréquence basse.',
    collector: { linux: 'nvidia-smi (`clocks_throttle_reasons`)', windows: 'compteurs du pilote' },
    since: '1.27.0',
  },
  {
    prefix: 'monitoring.samples[].cpuFanRpm',
    meaning:
      'Vitesse du ventilateur processeur au relevé. C’est ce qui manque pour lire une montée en température : à 90 °C, une machine dont les ventilateurs sont à fond et une machine dont ils ne tournent pas ne décrivent pas la même panne.',
    collector: { linux: 'hwmon (`fan*_input`)', windows: 'LibreHardwareMonitor si présent' },
    since: '1.27.0',
  },
  {
    prefix: 'monitoring.samples[].gpuFanRpm',
    meaning: 'Vitesse du ventilateur de la carte graphique au relevé.',
    collector: { linux: 'hwmon amdgpu, nvidia-smi', windows: 'LibreHardwareMonitor si présent' },
    since: '1.27.0',
  },
  {
    prefix: 'monitoring.samples[].chassisFanRpm',
    meaning: 'Vitesse du ventilateur de boîtier le plus rapide au relevé.',
    collector: { linux: 'hwmon (`fan*_input`)', windows: 'LibreHardwareMonitor si présent' },
    since: '1.27.0',
  },
  {
    prefix: 'monitoring.samples[].gpuAuxiliaryFanRpm',
    meaning:
      'Les autres ventilateurs de la carte graphique, quand elle en a plusieurs. Une carte à trois ventilateurs dont un est bloqué se voit ici et nulle part ailleurs : la moyenne reste plausible et le maximum la masque.',
    collector: { linux: 'hwmon amdgpu, nvidia-smi', windows: 'LibreHardwareMonitor si présent' },
    since: '1.29.0',
  },
  {
    prefix: 'monitoring.samples[].cpuCoreClocksMhz',
    meaning:
      'Fréquence de chaque cœur au relevé, dans l’ordre des identifiants système. La moyenne répond « 3,1 GHz » ; ce tableau répond « deux cœurs à 4,9 et quatorze à 2,8 », qui ne décrit pas la même machine. Sur une architecture hybride, la moyenne ne décrit aucun cœur réel.',
    collector: {
      linux: 'sysfs cpufreq (`scaling_cur_freq`), /proc/cpuinfo en repli',
      windows: 'compteurs de performance',
    },
    since: '1.29.0',
  },
  {
    prefix: 'monitoring.samples[].cpuCoreUsagePercent',
    meaning:
      'Charge de chaque cœur au relevé, même indexation que les fréquences. C’est ce qui distingue une mesure mono-cœur réussie — un cœur saturé — d’une charge qui n’a pas démarré.',
    collector: { linux: '/proc/stat, ligne par cœur', windows: 'compteurs de performance' },
    since: '1.29.0',
  },
  {
    prefix: 'monitoring.samples[].gpuIndex',
    meaning:
      'Quelle carte graphique les champs `gpu*` de cet échantillon décrivent. Sans lui, la série d’une machine à deux cartes est ambiguë : rien ne dit laquelle a chauffé.',
    collector: { linux: 'nvidia-smi -i, ordre d’énumération hwmon', windows: NONE },
    since: '1.29.0',
  },
  {
    prefix: 'monitoring.samples[].framesPerSecond',
    meaning:
      'Cadence de rendu instantanée, publiée seulement pendant une phase de rendu. Hors de celles-ci il n’y a pas d’images à compter, et zéro décrirait une machine bloquée. **Charge synthétique — ce n’est pas une cadence de jeu.**',
    collector: { linux: 'glmark2 --off-screen', windows: NONE },
    since: '1.29.0',
  },
  {
    prefix: 'monitoring.samples[].frameTimeMs',
    meaning:
      'Temps de trame au relevé. Redondant avec la cadence, et publié quand même : c’est lui qui porte l’irrégularité qu’une moyenne par seconde efface.',
    collector: { linux: 'glmark2 --off-screen', windows: NONE },
    since: '1.29.0',
  },
  {
    prefix: 'benchmark.results[].frameStability',
    meaning:
      'Centiles bas de la cadence et saccades comptées. La moyenne est la statistique qui ment le plus sur un rendu : 60 images par seconde régulières et une alternance 110/30 donnent la même moyenne, et une seule des deux est jouable. Le seuil de saccade est relatif à la médiane du rendu, jamais absolu, et il est publié avec le compte.',
    collector: { linux: 'glmark2 --off-screen', windows: NONE },
    since: '1.29.0',
  },
  {
    prefix: 'monitoring.samples[].phase',
    meaning:
      'Phase de charge en cours au moment du relevé. Sans elle, un pic de température au repos et un pic sous charge multi-cœur produisent le même tracé — et n’appellent pas la même conclusion.',
    collector: { linux: 'lib/collectors/benchmark.sh', windows: NONE },
    since: '1.27.0',
  },
  {
    prefix: 'sensors.powers',
    meaning:
      'Capteurs de puissance nommés par le micrologiciel, tels quels. Les noms varient d’une carte à l’autre : les normaliser inventerait une correspondance que rien n’atteste.',
    collector: { linux: 'hwmon (`power*_input`)', windows: 'CIM / LibreHardwareMonitor' },
    since: '1.18.0',
  },
  {
    prefix: 'benchmark.results[].framesPerSecond',
    meaning:
      'Cadence de rendu relevée scène par scène, quand l’outil la publie. Le score global n’en est qu’une moyenne pondérée : une carte qui rend 56 000 images par seconde sur une scène légère et 300 sur une scène d’ombrage n’a pas le même défaut qu’une carte régulière. **Charge synthétique et hors écran — ce n’est pas une cadence de jeu.**',
    collector: { linux: 'glmark2 --off-screen', windows: NONE },
    since: '1.28.0',
  },
  {
    prefix: 'benchmark.results[].frameTimeMs',
    meaning:
      'Temps de trame correspondant. Redondant avec la cadence, et publié quand même : l’outil donne les deux, et recalculer l’un depuis l’autre introduirait un arrondi là où il y a une mesure.',
    collector: { linux: 'glmark2 --off-screen', windows: NONE },
    since: '1.28.0',
  },
  {
    prefix: 'benchmark.telemetry',
    meaning:
      'Ce que la machine a vécu pendant les mesures, relevé seconde par seconde et étiqueté par phase. Le score dit ce qu’elle a produit ; cette série dit à quel prix — fréquence tenue ou non, température stabilisée ou non, ventilateurs ayant répondu ou non.',
    collector: { linux: 'lib/collectors/benchmark.sh', windows: NONE },
    since: '1.27.0',
  },
  {
    prefix: 'benchmark',
    meaning:
      'Banc d’essai, exécuté uniquement sur demande explicite : outil employé, paramètres, score, unité, et relevé thermique pendant la charge.',
    collector: { linux: 'sysbench, fio, glmark2', windows: 'WinSAT, débit disque' },
    since: '1.8.0',
  },

  // --- Historique, stabilité, démarrage et arrêt ------------------------------
  // `collector: NONE` là où la collecte n'est pas encore écrite : le schéma
  // précède les scanners d'une étape. Annoncer un collecteur avant qu'il
  // existe ferait exactement ce que ce fichier interdit — décrire au jugé.
  {
    prefix: 'stability',
    meaning:
      'Ce que la machine a vécu : redémarrages, arrêts inattendus, paniques noyau, erreurs matérielles, de stockage, de réseau et de pilotes, services en échec et vidanges mémoire. Chaque compteur porte la fenêtre qu’il couvre — sans elle, un nombre ne veut rien dire.',
    collector: { linux: 'journalctl, systemctl, coredumpctl, /proc', windows: NONE },
    since: '1.15.0',
  },
  {
    prefix: 'stability.coredumps',
    meaning:
      'Vidanges mémoire recensées : exécutable, signal et date. Jamais le contenu de la vidange, qui expose la mémoire du processus.',
    collector: { linux: 'coredumpctl list', windows: NONE },
    since: '1.15.0',
    privacy: 'anonymizable',
  },
  {
    prefix: 'boot',
    meaning:
      'Séquence de démarrage : durée par phase native, éléments les plus lents, unités en échec au démarrage, mode du micrologiciel et historique des démarrages précédents.',
    collector: { linux: 'systemd-analyze, journalctl --list-boots', windows: NONE },
    since: '1.15.0',
  },
  {
    prefix: 'virtualization.proxmox.failedTasks',
    meaning:
      'Tâches Proxmox terminées en erreur sur les sept derniers jours, statut natif conservé. Une sauvegarde qui échoue toutes les nuits est un fait qu’aucun inventaire ne montre : l’hôte va bien, les invités tournent, et il n’y a plus de sauvegarde exploitable.',
    collector: { linux: 'pvesh get /nodes/<nœud>/tasks', windows: NONE },
    since: '1.16.0',
  },
  {
    prefix: 'virtualization.proxmox.lastBackup',
    meaning:
      'Dernière sauvegarde vzdump observée, réussie ou non. Sa réussite est un fait, sa date en est un autre : une sauvegarde réussie il y a six semaines n’est pas une sauvegarde.',
    collector: { linux: 'pvesh get /nodes/<nœud>/tasks --typefilter vzdump', windows: NONE },
    since: '1.16.0',
  },
  {
    prefix: 'virtualization.proxmox.failedServices',
    meaning:
      'Services propres à Proxmox en échec. Nommés à part des unités systemd générales : un pvestatd arrêté rend toute l’interface aveugle sans qu’aucun invité ne s’arrête.',
    collector: { linux: 'systemctl is-active', windows: NONE },
    since: '1.16.0',
  },
  {
    prefix: 'virtualization.proxmox.ceph',
    meaning:
      'Santé Ceph, quand le nœud en a un. `present: false` ne vaut pas « dégradé » : une grappe sans Ceph n’a pas de Ceph en panne.',
    collector: { linux: 'ceph health, /etc/pve/ceph.conf', windows: NONE },
    since: '1.16.0',
  },
  {
    prefix: 'virtualization.proxmox.replication',
    meaning:
      'Réplication ZFS entre nœuds, quand elle est configurée. Absente sur un nœud isolé, ce qui est « sans objet » et non « en panne ».',
    collector: { linux: 'pvesr status, /etc/pve/replication.cfg', windows: NONE },
    since: '1.16.0',
  },
  {
    prefix: 'virtualization.proxmox.highAvailability',
    meaning:
      'Haute disponibilité, quand des ressources y sont déclarées. `ha-manager` existe sur tout nœud PVE : c’est la configuration qui dit si la HA est en service.',
    collector: { linux: 'ha-manager status, /etc/pve/ha/resources.cfg', windows: NONE },
    since: '1.16.0',
  },
  {
    prefix: 'virtualization.proxmox.taskWindowMs',
    meaning:
      'Fenêtre couverte par la lecture des tâches — indissociable de leur compte : « trois échecs » ne veut rien dire sans la durée sur laquelle ils sont survenus.',
    collector: { linux: 'pvesh get /nodes/<nœud>/tasks', windows: NONE },
    since: '1.16.0',
  },
  {
    prefix: 'power.activePlan',
    meaning:
      'Plan ou profil d’alimentation actif, nom natif. Il explique des mesures qui sembleraient sinon contradictoires : un processeur bridé à la moitié de sa fréquence sous un profil « économie d’énergie » n’a rien d’anormal.',
    collector: { linux: '/sys/firmware/acpi/platform_profile', windows: 'Win32_PowerPlan' },
    since: '1.17.0',
  },
  {
    prefix: 'power.cpuGovernor',
    meaning:
      'Gouverneur de fréquence Linux (`performance`, `powersave`, `schedutil`). Sans objet sous Windows, qui n’a pas cpufreq.',
    collector: { linux: '/sys/devices/system/cpu/cpu0/cpufreq', windows: NONE },
    since: '1.17.0',
  },
  {
    prefix: 'security.windows.dmaProtection',
    meaning:
      'Protection DMA du noyau contre les attaques par port Thunderbolt ou PCIe. `PARTIAL` y signifie « le matériel l’annonce » : le lire comme actif promettrait une protection qui ne l’est peut-être pas.',
    collector: { linux: NONE, windows: 'Win32_DeviceGuard.AvailableSecurityProperties' },
    since: '1.17.0',
  },
  {
    prefix: 'security.windows.smartAppControl',
    meaning:
      'Smart App Control (Windows 11 22H2+). `PARTIAL` correspond au mode évaluation, qui n’est pas une protection : Windows observe l’usage avant de décider.',
    collector: { linux: NONE, windows: 'HKLM\\SYSTEM\\CurrentControlSet\\Control\\CI\\Policy' },
    since: '1.17.0',
  },
  {
    prefix: 'boot.kernels',
    meaning:
      'Noyaux installés et celui qui tourne. Une machine peut tourner depuis des semaines sur un noyau plus ancien que le plus récent installé — un correctif appliqué mais pas encore chargé. Le scanner compare sans conclure.',
    collector: { linux: 'dpkg-query, rpm, pacman, /lib/modules', windows: NONE },
    since: '1.16.0',
  },
  {
    prefix: 'shutdown',
    meaning:
      'Dernier arrêt : date, propreté, motif natif, durée et unités ayant retardé l’extinction.',
    collector: { linux: 'journalctl --list-boots', windows: NONE },
    since: '1.15.0',
  },
  {
    prefix: 'events',
    meaning:
      'Incidents des journaux natifs, normalisés et regroupés par empreinte, avec leur identifiant d’origine et la fenêtre réellement couverte — distincte de la fenêtre demandée.',
    collector: { linux: 'journalctl, dmesg, /var/log', windows: NONE },
    since: '1.15.0',
  },
  {
    prefix: 'events.entries[].evidence',
    meaning:
      'Au plus trois extraits bruts du journal, tronqués et anonymisés : une alerte sans la ligne qui la fonde n’est pas vérifiable.',
    collector: { linux: 'journalctl, dmesg, /var/log', windows: NONE },
    since: '1.15.0',
    privacy: 'restricted',
  },
];

/**
 * Annotation applicable à un chemin — correspondance la plus longue.
 *
 * Rend `null` plutôt qu'une annotation approchante si aucun préfixe ne
 * correspond : un sens voisin serait lu comme le bon.
 */
export function annotationFor(path: string): FieldAnnotation | null {
  let best: FieldAnnotation | null = null;
  for (const annotation of FIELD_ANNOTATIONS) {
    // `[` autant que `.` : `cpus` couvre `cpus[].model`, sans quoi tout
    // sous-arbre traversant un tableau resterait non annoté.
    const next = path.slice(annotation.prefix.length, annotation.prefix.length + 1);
    const matches =
      path === annotation.prefix ||
      (path.startsWith(annotation.prefix) && (next === '.' || next === '['));
    if (!matches) continue;
    if (best === null || annotation.prefix.length > best.prefix.length) best = annotation;
  }
  return best;
}

/**
 * Colonnes PostgreSQL projetées depuis le rapport.
 *
 * `raw` garde le rapport entier : ces colonnes n'existent que pour les
 * agrégations, et se recalculent intégralement depuis `raw`. En cas de
 * désaccord, c'est le JSON qui a raison.
 *
 * Un test dans `apps/api` vérifie que chaque colonne listée ici existe
 * réellement dans la projection : la table ne peut donc pas annoncer un
 * stockage disparu.
 */
export const POSTGRES_PROJECTIONS: Readonly<Record<string, string>> = {
  schemaVersion: 'Scan.schemaVersion',
  scannerVersion: 'Scan.scannerVersion',
  'report.generatedAt': 'Scan.generatedAt',
  'report.durationMs': 'Scan.durationMs',
  'report.scannerKind': 'Scan.scannerKind',
  'report.profile': 'Scan.profile',
  'report.anonymized': 'Scan.anonymized',
  'os.family': 'Scan.osFamily',
  'os.name': 'Scan.osName',
  'os.version': 'Scan.osVersion',
  'system.chassisType': 'Scan.deviceType (dérivé)',
  'cpus[].manufacturer': 'Scan.cpuVendor',
  'cpus[].model': 'Scan.cpuModel',
  'cpus[].physicalCores': 'Scan.cpuCores',
  'gpus[].vendor': 'Scan.gpuVendor',
  'memory.installedBytes': 'Scan.memoryBytes',
  'storage.totalBytes': 'Scan.storageBytes',
  'virtualization.runningUnder': 'Scan.virtualization',
};
