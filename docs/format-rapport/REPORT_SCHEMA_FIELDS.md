# Référence des champs du rapport

**Ce document est généré.** Il est produit par `npm run docs:schema-fields` à
partir du schéma Zod (`packages/report-schema/src/report.ts`), de la table
d'annotations (`packages/report-schema/src/field-annotations.ts`) et des
rapports de référence. Le modifier à la main n'a aucun effet : un test le
regénère et échoue en cas de dérive.

[`./REPORT_SCHEMA.md`](./REPORT_SCHEMA.md) explique **pourquoi** le format est ce
qu'il est ; ce document dit **ce qu'il contient**, champ par champ.

## Vue d'ensemble

<!-- fields:summary:start -->

- **929 champs** répartis en **32 sections** de premier niveau.
- **32** sont obligatoires sans réserve ; **650** le sont seulement si leur section est collectée, et tous les autres peuvent être absents — une absence portant toujours son motif.
- **43** sont réservés au demandeur : stockés en clair, servis en clair à leur propriétaire, remplacés par un marqueur pour les autres.
- **18** sont projetés en colonne PostgreSQL pour les agrégations ; les 911 autres ne vivent que dans `Scan.raw`.

<!-- fields:summary:end -->

## Comment lire la table

**Type.** Tel qu'il apparaît dans le JSON, bornes comprises. Toutes les chaînes
sont bornées : une longueur libre est un vecteur de déni de service au stockage.

**Obligatoire.** « Obligatoire » sans réserve engage tout rapport. « Obligatoire
si présent » n'engage que les rapports où la section a effectivement été
collectée — un audit rapide qui n'a pas lu le stockage reste conforme.

**Non collecté.** « oui » signifie que le champ accepte le marqueur
`{ "unknown": true, "reason": … }`. C'est le mécanisme central du format :
lorsqu'un scanner _tente_ une collecte et échoue, il le dit au lieu de se taire.
Un compteur SMART non lu n'est pas un compteur nul.

**Exemple.** Lu dans les rapports de référence du dépôt, jamais fabriqué. Un
champ sans exemple est un champ qu'aucun jeu d'essai ne porte.

**OS et collecteur.** Les outils réellement appelés. « non collecté » désigne une
section qu'un scanner n'écrit pas encore — pas une donnée absente sur la
machine.

**Confidentialité.**

- _Public_ — servi tel quel à quiconque ouvre le rapport.
- _Réservé au demandeur_ — stocké **en clair**, servi en clair au propriétaire de
  l'audit et à son organisation, remplacé par un marqueur pour les autres. Le
  nom de machine, l'UUID, les numéros de série et les adresses le sont.
- _Anonymisable à la collecte_ — remplacé par un pseudonyme stable **avant
  l'envoi** si le scanner a reçu `--anonymize`. Cette perte est définitive : le
  propriétaire lui-même ne retrouvera pas la valeur.

**PostgreSQL.** `Scan.raw` contient toujours le rapport entier. Les colonnes
citées ne sont qu'une projection destinée aux agrégations : elles se recalculent
depuis `raw`, et un désaccord se tranche en faveur du JSON.

## Ce que ce document ne peut pas dire

La **version d'introduction** est donnée par sous-arbre, pas par champ : le dépôt
ne conserve aucun historique champ par champ, et la reconstituer au jugé
reviendrait à inventer une donnée. Elle est relevée dans l'historique Git à la
date d'ajout du fichier de section correspondant.

Le **sens** est lui aussi porté par sous-arbre. Chaque section liste, sous sa
table, le préfixe dont chaque ligne hérite sa description.

## Champs, section par section

<!-- fields:reference:start -->

### `schemaVersion`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `schemaVersion` | chaîne | — | **obligatoire** | non | `1.33.0` | Linux, Windows | Linux : `sysaudit.sh` · Windows : `sysaudit.ps1` | Public | `Scan.schemaVersion` |

**Sens des champs de cette section**

- `schemaVersion` — Version du schéma de rapport que ce document respecte. *(depuis le schéma 1.0.0)*

### `scannerVersion`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `scannerVersion` | chaîne | — | **obligatoire** | non | `0.1.0` | Linux, Windows | Linux : `sysaudit.sh` · Windows : `sysaudit.ps1` | Public | `Scan.scannerVersion` |

**Sens des champs de cette section**

- `scannerVersion` — Version du scanner qui a produit le rapport. *(depuis le schéma 1.0.0)*

### `platformVersion`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `platformVersion` | chaîne | — | facultatif | non | `0.1.0` | aucun | non collecté | Public | `raw` uniquement |

**Sens des champs de cette section**

- `platformVersion` — Version de la plateforme ayant reçu le rapport, ajoutée à l’ingestion. *(depuis le schéma 1.0.0)*

### `report`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `report.localId` | chaîne [1 à 256] | — | facultatif | non | `scan-2026-07-25-164200` | Linux, Windows | Linux : `sysaudit.sh` · Windows : `sysaudit.ps1` | Public | `raw` uniquement |
| `report.generatedAt` | date-heure ISO 8601 (UTC) | — | **obligatoire** | non | `2026-07-25T16:42:00Z` | Linux, Windows | Linux : `sysaudit.sh` · Windows : `sysaudit.ps1` | Public | `Scan.generatedAt` |
| `report.durationMs` | entier [0 à 31536000000] | ms | facultatif | non | `8420` | Linux, Windows | Linux : `sysaudit.sh` · Windows : `sysaudit.ps1` | Public | `Scan.durationMs` |
| `report.scannerKind` | linux \| proxmox \| windows \| windows-legacy \| macos \| freebsd \| android | — | **obligatoire** | non | `proxmox` | Linux, Windows | Linux : `sysaudit.sh` · Windows : `sysaudit.ps1` | Public | `Scan.scannerKind` |
| `report.profile` | quick \| standard \| full \| stress \| security | — | facultatif | non | `full` | Linux, Windows | Linux : `sysaudit.sh` · Windows : `sysaudit.ps1` | Public | `Scan.profile` |
| `report.anonymized` | booléen | — | **obligatoire** | non | `false` | Linux, Windows | Linux : `sysaudit.sh` · Windows : `sysaudit.ps1` | Public | `Scan.anonymized` |
| `report.anonymizedCategories[]` | hostname \| username \| domain \| publicIp \| macAddress \| serialNumber \| uuid \| wifiSsid | — | obligatoire si présent | non | — | Linux, Windows | Linux : `sysaudit.sh` · Windows : `sysaudit.ps1` | Public | `raw` uniquement |
| `report.collectionMode` | online \| offline | — | facultatif | non | — | Linux, Windows | Linux : `sysaudit.sh` · Windows : `sysaudit.ps1` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `report.localId` — Identifiant produit sur la machine, qui rend un renvoi du même audit inoffensif côté serveur. *(depuis le schéma 1.0.0)*
- `report` — Circonstances de l’exécution : quand, avec quel profil, sous quel scanner. *(depuis le schéma 1.0.0)*
- `report.anonymized` — Vrai si le scanner a été lancé avec --anonymize. La substitution a eu lieu avant l’envoi : elle est irréversible. *(depuis le schéma 1.0.0)*

### `capabilities`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `capabilities.platform` | linux \| windows \| macos \| freebsd \| android \| unknown | — | **obligatoire** | non | `linux` | Linux, Windows | Linux : `lib/core/capabilities.sh` · Windows : `lib/core/capabilities.ps1` | Public | `raw` uniquement |
| `capabilities.distribution` | chaîne [1 à 256] | — | facultatif | non | `Debian` | Linux, Windows | Linux : `lib/core/capabilities.sh` · Windows : `lib/core/capabilities.ps1` | Public | `raw` uniquement |
| `capabilities.architecture` | chaîne [1 à 256] | — | **obligatoire** | non | `x86_64` | Linux, Windows | Linux : `lib/core/capabilities.sh` · Windows : `lib/core/capabilities.ps1` | Public | `raw` uniquement |
| `capabilities.privileged` | booléen | — | **obligatoire** | non | `true` | Linux, Windows | Linux : `lib/core/capabilities.sh` · Windows : `lib/core/capabilities.ps1` | Public | `raw` uniquement |
| `capabilities.virtualized` | chaîne [1 à 256] | — | facultatif | non | — | Linux, Windows | Linux : `lib/core/capabilities.sh` · Windows : `lib/core/capabilities.ps1` | Public | `raw` uniquement |
| `capabilities.proxmox` | booléen | — | **obligatoire** | non | `true` | Linux, Windows | Linux : `lib/core/capabilities.sh` · Windows : `lib/core/capabilities.ps1` | Public | `raw` uniquement |
| `capabilities.docker` | booléen | — | **obligatoire** | non | `true` | Linux, Windows | Linux : `lib/core/capabilities.sh` · Windows : `lib/core/capabilities.ps1` | Public | `raw` uniquement |
| `capabilities.tools` | objet à clés libres | — | **obligatoire** | non | — | Linux, Windows | Linux : `lib/core/capabilities.sh` · Windows : `lib/core/capabilities.ps1` | Public | `raw` uniquement |
| `capabilities.features` | objet à clés libres | — | facultatif | non | — | Linux, Windows | Linux : `lib/core/capabilities.sh` · Windows : `lib/core/capabilities.ps1` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `capabilities` — Ce que le scanner pouvait faire sur cette machine : privilèges, outils présents, contexte virtualisé. Sert à distinguer « absent » de « pas mesurable ici ». *(depuis le schéma 1.0.0)*

### `system`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `system.hostname` | chaîne [1 à 256] | — | **obligatoire** | oui | `pve-lab` | Linux, Windows | Linux : `hostname` · Windows : `$env:COMPUTERNAME` | Réservé au demandeur | `raw` uniquement |
| `system.fqdn` | chaîne [1 à 256] | — | facultatif | oui | `pve-lab.cabinet.lan` | Linux, Windows | Linux : `hostname -f` · Windows : `CIM Win32_ComputerSystem` | Réservé au demandeur | `raw` uniquement |
| `system.domain` | chaîne [1 à 256] | — | facultatif | oui | `cabinet.lan` | Linux, Windows | Linux : `hostname -d` · Windows : `CIM Win32_ComputerSystem (PartOfDomain)` | Réservé au demandeur | `raw` uniquement |
| `system.workgroup` | chaîne [1 à 256] | — | facultatif | oui | — | Windows | Linux : impossible — notion propre à Windows : un poste Linux n’appartient à aucun groupe de travail SMB · Windows : `CIM Win32_ComputerSystem (Workgroup)` | Réservé au demandeur | `raw` uniquement |
| `system.manufacturer` | chaîne [1 à 256] | — | **obligatoire** | oui | `ASUSTeK COMPUTER INC.` | Linux, Windows | Linux : `dmidecode, /sys/class/dmi` · Windows : `CIM Win32_ComputerSystem` | Public | `raw` uniquement |
| `system.model` | chaîne [1 à 256] | — | **obligatoire** | oui | `PRIME B550-PLUS` | Linux, Windows | Linux : `dmidecode, /sys/class/dmi` · Windows : `CIM Win32_ComputerSystem` | Public | `raw` uniquement |
| `system.chassisType` | chaîne [1 à 256] | — | **obligatoire** | oui | `desktop` | Linux, Windows | Linux : `dmidecode, /sys/class/dmi` · Windows : `CIM Win32_ComputerSystem` | Public | `Scan.deviceType (dérivé)` |
| `system.uuid` | chaîne [1 à 256] | — | **obligatoire** | oui | `4c4c4544-0037-5810-8055-b7c04f594d32` | Linux, Windows | Linux : `dmidecode -s system-uuid` · Windows : `CIM Win32_ComputerSystemProduct` | Réservé au demandeur | `raw` uniquement |
| `system.serialNumber` | chaîne [1 à 256] | — | **obligatoire** | oui | `MB1234567890` | Linux, Windows | Linux : `dmidecode -s system-serial-number` · Windows : `CIM Win32_BIOS` | Réservé au demandeur | `raw` uniquement |
| `system.assetTag` | chaîne [1 à 256] | — | facultatif | oui | `POSTE-COMPTA-014` | Linux, Windows | Linux : `dmidecode -t chassis` · Windows : `CIM Win32_SystemEnclosure` | Réservé au demandeur | `raw` uniquement |
| `system.machineGuid` | chaîne [1 à 256] | — | facultatif | oui | — | Windows | Linux : impossible — identifiant d’une installation Windows ; il n’a pas d’équivalent Linux · Windows : `HKLM\SOFTWARE\Microsoft\Cryptography` | Réservé au demandeur | `raw` uniquement |
| `system.machineSid` | chaîne [1 à 256] | — | facultatif | oui | — | Windows | Linux : impossible — les SID sont un mécanisme Windows ; Linux identifie ses comptes par UID · Windows : `SID du compte Administrateur intégré` | Réservé au demandeur | `raw` uniquement |
| `system.architecture` | chaîne [1 à 256] | — | **obligatoire** | oui | `x86_64` | Linux, Windows | Linux : `dmidecode, /sys/class/dmi` · Windows : `CIM Win32_ComputerSystem` | Public | `raw` uniquement |
| `system.uptimeSeconds` | entier [≥ 0] | s | **obligatoire** | oui | `1209600` | Linux, Windows | Linux : `dmidecode, /sys/class/dmi` · Windows : `CIM Win32_ComputerSystem` | Public | `raw` uniquement |
| `system.timezone` | chaîne [1 à 256] | — | **obligatoire** | oui | `Europe/Brussels` | Linux, Windows | Linux : `dmidecode, /sys/class/dmi` · Windows : `CIM Win32_ComputerSystem` | Public | `raw` uniquement |
| `system.localTime` | date-heure ISO 8601 (UTC) | — | **obligatoire** | oui | `2026-07-25T18:42:00+02:00` | Linux, Windows | Linux : `dmidecode, /sys/class/dmi` · Windows : `CIM Win32_ComputerSystem` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `system.hostname` — Nom de la machine sur le réseau. *(depuis le schéma 1.0.0)*
- `system.fqdn` — Nom pleinement qualifié de la machine, lorsque la résolution locale en rend un. Jamais recomposé à partir du nom court et d’un domaine. *(depuis le schéma 1.25.0)*
- `system.domain` — Domaine DNS ou Active Directory dont la machine fait partie. *(depuis le schéma 1.25.0)*
- `system.workgroup` — Groupe de travail Windows, renseigné uniquement lorsque la machine n’est pas jointe à un domaine. *(depuis le schéma 1.25.0)*
- `system` — Identité de la machine : constructeur, modèle, châssis, temps de fonctionnement. *(depuis le schéma 1.0.0)*
- `system.uuid` — Identifiant unique inscrit dans le SMBIOS de la carte mère. *(depuis le schéma 1.0.0)*
- `system.serialNumber` — Numéro de série du châssis — celui que demande un service après-vente. *(depuis le schéma 1.0.0)*
- `system.assetTag` — Étiquette d’inventaire du châssis, posée par l’exploitant. Elle nomme un parc et sa numérotation interne, là où le numéro de série ne nomme qu’un exemplaire. *(depuis le schéma 1.25.0)*
- `system.machineGuid` — Identifiant de l’installation Windows. Il survit à un changement de carte mère et suit un disque cloné : il désigne le système, non le matériel. *(depuis le schéma 1.25.0)*
- `system.machineSid` — SID de la machine, racine des identifiants de ses comptes locaux. *(depuis le schéma 1.25.0)*

### `os`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `os.family` | linux \| windows \| macos \| freebsd \| unknown | — | **obligatoire** | non | `linux` | Linux, Windows | Linux : `/etc/os-release, uname` · Windows : `CIM Win32_OperatingSystem` | Public | `Scan.osFamily` |
| `os.name` | chaîne [1 à 256] | — | **obligatoire** | oui | `Debian GNU/Linux` | Linux, Windows | Linux : `/etc/os-release, uname` · Windows : `CIM Win32_OperatingSystem` | Public | `Scan.osName` |
| `os.edition` | chaîne [1 à 256] | — | **obligatoire** | oui | `Pro` | Linux, Windows | Linux : `/etc/os-release, uname` · Windows : `CIM Win32_OperatingSystem` | Public | `raw` uniquement |
| `os.distribution` | chaîne [1 à 256] | — | **obligatoire** | oui | `Debian` | Linux, Windows | Linux : `/etc/os-release, uname` · Windows : `CIM Win32_OperatingSystem` | Public | `raw` uniquement |
| `os.version` | chaîne [1 à 256] | — | **obligatoire** | oui | `12` | Linux, Windows | Linux : `/etc/os-release, uname` · Windows : `CIM Win32_OperatingSystem` | Public | `Scan.osVersion` |
| `os.build` | chaîne [1 à 256] | — | **obligatoire** | oui | `26100` | Linux, Windows | Linux : `/etc/os-release, uname` · Windows : `CIM Win32_OperatingSystem` | Public | `raw` uniquement |
| `os.kernel` | chaîne [1 à 256] | — | **obligatoire** | oui | `6.8.12-4-pve` | Linux, Windows | Linux : `/etc/os-release, uname` · Windows : `CIM Win32_OperatingSystem` | Public | `raw` uniquement |
| `os.architecture` | chaîne [1 à 256] | — | **obligatoire** | oui | `x86_64` | Linux, Windows | Linux : `/etc/os-release, uname` · Windows : `CIM Win32_OperatingSystem` | Public | `raw` uniquement |
| `os.installDate` | date ISO 8601 | — | **obligatoire** | oui | `2024-03-14` | Linux, Windows | Linux : `/etc/os-release, uname` · Windows : `CIM Win32_OperatingSystem` | Public | `raw` uniquement |
| `os.locale` | chaîne [1 à 256] | — | **obligatoire** | oui | `fr_BE.UTF-8` | Linux, Windows | Linux : `/etc/os-release, uname` · Windows : `CIM Win32_OperatingSystem` | Public | `raw` uniquement |
| `os.timezone` | chaîne [1 à 256] | — | **obligatoire** | oui | `Europe/Brussels` | Linux, Windows | Linux : `/etc/os-release, uname` · Windows : `CIM Win32_OperatingSystem` | Public | `raw` uniquement |
| `os.support.status` | SUPPORTED \| EXTENDED \| END_OF_LIFE \| UNKNOWN | — | obligatoire si présent | non | `SUPPORTED` | Linux, Windows | Linux : `catalogue @sysaudit/platform` · Windows : `catalogue @sysaudit/platform` | Public | `raw` uniquement |
| `os.support.endOfLife` | date ISO 8601 | — | facultatif | non | `2028-06-30` | Linux, Windows | Linux : `catalogue @sysaudit/platform` · Windows : `catalogue @sysaudit/platform` | Public | `raw` uniquement |
| `os.support.endOfExtendedSupport` | date ISO 8601 | — | facultatif | non | `2023-01-10` | Linux, Windows | Linux : `catalogue @sysaudit/platform` · Windows : `catalogue @sysaudit/platform` | Public | `raw` uniquement |
| `os.support.confidence` | HIGH \| MEDIUM \| LOW | — | obligatoire si présent | non | `HIGH` | Linux, Windows | Linux : `catalogue @sysaudit/platform` · Windows : `catalogue @sysaudit/platform` | Public | `raw` uniquement |
| `os.support.source.name` | chaîne [1 à 256] | — | obligatoire si présent | non | `Debian Security Team` | Linux, Windows | Linux : `catalogue @sysaudit/platform` · Windows : `catalogue @sysaudit/platform` | Public | `raw` uniquement |
| `os.support.source.vendor` | chaîne [1 à 256] | — | facultatif | non | — | Linux, Windows | Linux : `catalogue @sysaudit/platform` · Windows : `catalogue @sysaudit/platform` | Public | `raw` uniquement |
| `os.support.source.title` | chaîne [1 à 1024] | — | facultatif | non | `Debian Long Term Support` | Linux, Windows | Linux : `catalogue @sysaudit/platform` · Windows : `catalogue @sysaudit/platform` | Public | `raw` uniquement |
| `os.support.source.url` | URL | — | facultatif | non | `https://wiki.debian.org/LTS` | Linux, Windows | Linux : `catalogue @sysaudit/platform` · Windows : `catalogue @sysaudit/platform` | Public | `raw` uniquement |
| `os.support.source.checkedAt` | date-heure ISO 8601 (UTC) | — | facultatif | non | `2026-07-25T16:42:00Z` | Linux, Windows | Linux : `catalogue @sysaudit/platform` · Windows : `catalogue @sysaudit/platform` | Public | `raw` uniquement |
| `os.support.note` | chaîne [1 à 1024] | — | facultatif | non | — | Linux, Windows | Linux : `catalogue @sysaudit/platform` · Windows : `catalogue @sysaudit/platform` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `os` — Système installé : famille, édition, version, noyau, date d’installation. *(depuis le schéma 1.0.0)*
- `os.support` — Fin de support annoncée par l’éditeur, avec sa source et son degré de confiance. Information externe, jamais mesurée sur la machine. *(depuis le schéma 1.0.0)*

### `motherboard`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `motherboard.manufacturer` | chaîne [1 à 256] | — | obligatoire si présent | oui | `ASUSTeK COMPUTER INC.` | Linux, Windows | Linux : `dmidecode -t baseboard` · Windows : `CIM Win32_BaseBoard` | Public | `raw` uniquement |
| `motherboard.model` | chaîne [1 à 256] | — | obligatoire si présent | oui | `PRIME B550-PLUS` | Linux, Windows | Linux : `dmidecode -t baseboard` · Windows : `CIM Win32_BaseBoard` | Public | `raw` uniquement |
| `motherboard.revision` | chaîne [1 à 256] | — | obligatoire si présent | oui | `Rev X.0x` | Linux, Windows | Linux : `dmidecode -t baseboard` · Windows : `CIM Win32_BaseBoard` | Public | `raw` uniquement |
| `motherboard.serialNumber` | chaîne [1 à 256] | — | obligatoire si présent | oui | `MB1234567890` | Linux, Windows | Linux : `dmidecode -t baseboard` · Windows : `CIM Win32_BaseBoard` | Réservé au demandeur | `raw` uniquement |
| `motherboard.chipset` | chaîne [1 à 256] | — | obligatoire si présent | oui | `AMD B550` | Linux, Windows | Linux : `dmidecode -t baseboard` · Windows : `CIM Win32_BaseBoard` | Public | `raw` uniquement |
| `motherboard.socket` | chaîne [1 à 256] | — | obligatoire si présent | oui | `AM4` | Linux, Windows | Linux : `dmidecode -t baseboard` · Windows : `CIM Win32_BaseBoard` | Public | `raw` uniquement |
| `motherboard.memorySlots` | entier [≥ 0] | — | obligatoire si présent | oui | `4` | Linux, Windows | Linux : `dmidecode -t baseboard` · Windows : `CIM Win32_BaseBoard` | Public | `raw` uniquement |
| `motherboard.pcieSlots[].designation` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Linux, Windows | Linux : `dmidecode -t baseboard` · Windows : `CIM Win32_BaseBoard` | Public | `raw` uniquement |
| `motherboard.pcieSlots[].type` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `dmidecode -t baseboard` · Windows : `CIM Win32_BaseBoard` | Public | `raw` uniquement |
| `motherboard.pcieSlots[].used` | booléen | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `dmidecode -t baseboard` · Windows : `CIM Win32_BaseBoard` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `motherboard` — Carte mère : constructeur, modèle, chipset, socket, connecteurs PCIe et mémoire. *(depuis le schéma 1.0.0)*
- `motherboard.serialNumber` — Numéro de série de la carte mère. *(depuis le schéma 1.0.0)*

### `bios`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `bios.manufacturer` | chaîne [1 à 256] | — | obligatoire si présent | oui | `American Megatrends Inc.` | Linux, Windows | Linux : `dmidecode -t bios, /sys/firmware/efi` · Windows : `CIM Win32_BIOS` | Public | `raw` uniquement |
| `bios.version` | chaîne [1 à 256] | — | obligatoire si présent | oui | `2803` | Linux, Windows | Linux : `dmidecode -t bios, /sys/firmware/efi` · Windows : `CIM Win32_BIOS` | Public | `raw` uniquement |
| `bios.releaseDate` | date ISO 8601 | — | obligatoire si présent | oui | `2024-11-08` | Linux, Windows | Linux : `dmidecode -t bios, /sys/firmware/efi` · Windows : `CIM Win32_BIOS` | Public | `raw` uniquement |
| `bios.mode` | UEFI \| LEGACY | — | obligatoire si présent | oui | `UEFI` | Linux, Windows | Linux : `dmidecode -t bios, /sys/firmware/efi` · Windows : `CIM Win32_BIOS` | Public | `raw` uniquement |
| `bios.secureBoot` | ENABLED \| DISABLED \| UNSUPPORTED | — | obligatoire si présent | oui | `DISABLED` | Linux, Windows | Linux : `dmidecode -t bios, /sys/firmware/efi` · Windows : `CIM Win32_BIOS` | Public | `raw` uniquement |
| `bios.smbiosVersion` | chaîne [1 à 256] | — | obligatoire si présent | oui | `3.3` | Linux, Windows | Linux : `dmidecode -t bios, /sys/firmware/efi` · Windows : `CIM Win32_BIOS` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `bios` — Micrologiciel de démarrage : version, date, mode UEFI ou Legacy, Secure Boot. *(depuis le schéma 1.0.0)*

### `cpus`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `cpus[].manufacturer` | chaîne [1 à 256] | — | obligatoire si présent | oui | `AMD` | Linux, Windows | Linux : `lscpu, /proc/cpuinfo` · Windows : `CIM Win32_Processor` | Public | `Scan.cpuVendor` |
| `cpus[].model` | chaîne [1 à 256] | — | obligatoire si présent | oui | `AMD Ryzen 7 5700X 8-Core Processor` | Linux, Windows | Linux : `lscpu, /proc/cpuinfo` · Windows : `CIM Win32_Processor` | Public | `Scan.cpuModel` |
| `cpus[].family` | chaîne [1 à 256] | — | obligatoire si présent | oui | `Zen 3` | Linux, Windows | Linux : `lscpu, /proc/cpuinfo` · Windows : `CIM Win32_Processor` | Public | `raw` uniquement |
| `cpus[].generation` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `lscpu, /proc/cpuinfo` · Windows : `CIM Win32_Processor` | Public | `raw` uniquement |
| `cpus[].socket` | chaîne [1 à 256] | — | obligatoire si présent | oui | `AM4` | Linux, Windows | Linux : `lscpu, /proc/cpuinfo` · Windows : `CIM Win32_Processor` | Public | `raw` uniquement |
| `cpus[].physicalCores` | entier [≥ 0] | — | obligatoire si présent | oui | `8` | Linux, Windows | Linux : `lscpu, /proc/cpuinfo` · Windows : `CIM Win32_Processor` | Public | `Scan.cpuCores` |
| `cpus[].logicalCores` | entier [≥ 0] | — | obligatoire si présent | oui | `16` | Linux, Windows | Linux : `lscpu, /proc/cpuinfo` · Windows : `CIM Win32_Processor` | Public | `raw` uniquement |
| `cpus[].baseFrequencyMhz` | entier [0 à 100000] | MHz | obligatoire si présent | oui | `3400` | Linux, Windows | Linux : `lscpu, /proc/cpuinfo` · Windows : `CIM Win32_Processor` | Public | `raw` uniquement |
| `cpus[].maxFrequencyMhz` | entier [0 à 100000] | MHz | obligatoire si présent | oui | `4600` | Linux, Windows | Linux : `lscpu, /proc/cpuinfo` · Windows : `CIM Win32_Processor` | Public | `raw` uniquement |
| `cpus[].currentFrequencyMhz` | entier [0 à 100000] | MHz | obligatoire si présent | oui | `2200` | Linux, Windows | Linux : `lscpu, /proc/cpuinfo` · Windows : `CIM Win32_Processor` | Public | `raw` uniquement |
| `cpus[].cacheBytes.l1` | entier [≥ 0] | — | facultatif | oui | `524288` | Linux, Windows | Linux : `lscpu, /proc/cpuinfo` · Windows : `CIM Win32_Processor` | Public | `raw` uniquement |
| `cpus[].cacheBytes.l2` | entier [≥ 0] | — | facultatif | oui | `4194304` | Linux, Windows | Linux : `lscpu, /proc/cpuinfo` · Windows : `CIM Win32_Processor` | Public | `raw` uniquement |
| `cpus[].cacheBytes.l3` | entier [≥ 0] | — | facultatif | oui | `33554432` | Linux, Windows | Linux : `lscpu, /proc/cpuinfo` · Windows : `CIM Win32_Processor` | Public | `raw` uniquement |
| `cpus[].instructionSets[]` | chaîne [1 à 256] | — | obligatoire si présent | non | `sse4_2` | Linux, Windows | Linux : `lscpu, /proc/cpuinfo` · Windows : `CIM Win32_Processor` | Public | `raw` uniquement |
| `cpus[].virtualization.supported` | booléen | — | obligatoire si présent | non | `true` | Linux, Windows | Linux : `lscpu, /proc/cpuinfo` · Windows : `CIM Win32_Processor` | Public | `raw` uniquement |
| `cpus[].virtualization.enabled` | booléen | — | obligatoire si présent | oui | `true` | Linux, Windows | Linux : `lscpu, /proc/cpuinfo` · Windows : `CIM Win32_Processor` | Public | `raw` uniquement |
| `cpus[].virtualization.technology` | chaîne [1 à 256] | — | obligatoire si présent | oui | `AMD-V` | Linux, Windows | Linux : `lscpu, /proc/cpuinfo` · Windows : `CIM Win32_Processor` | Public | `raw` uniquement |
| `cpus[].temperatureCelsius` | nombre [-100 à 200] | °C | obligatoire si présent | oui | `42.5` | Linux, Windows | Linux : `lscpu, /proc/cpuinfo` · Windows : `CIM Win32_Processor` | Public | `raw` uniquement |
| `cpus[].usagePercent` | nombre [0 à 100] | % | obligatoire si présent | oui | `12.4` | Linux, Windows | Linux : `lscpu, /proc/cpuinfo` · Windows : `CIM Win32_Processor` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `cpus` — Processeurs installés : modèle, cœurs, fréquences, caches, jeux d’instructions et support de virtualisation. *(depuis le schéma 1.0.0)*

### `memory`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `memory.modules[].slot` | chaîne [1 à 256] | — | obligatoire si présent | oui | `DIMM_A2` | Linux, Windows | Linux : `dmidecode -t memory` · Windows : `CIM Win32_PhysicalMemory` | Public | `raw` uniquement |
| `memory.modules[].sizeBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `17179869184` | Linux, Windows | Linux : `dmidecode -t memory` · Windows : `CIM Win32_PhysicalMemory` | Public | `raw` uniquement |
| `memory.modules[].manufacturer` | chaîne [1 à 256] | — | obligatoire si présent | oui | `Kingston` | Linux, Windows | Linux : `dmidecode -t memory` · Windows : `CIM Win32_PhysicalMemory` | Public | `raw` uniquement |
| `memory.modules[].partNumber` | chaîne [1 à 256] | — | obligatoire si présent | oui | `KF3200C16D4/16GX` | Linux, Windows | Linux : `dmidecode -t memory` · Windows : `CIM Win32_PhysicalMemory` | Public | `raw` uniquement |
| `memory.modules[].serialNumber` | chaîne [1 à 256] | — | obligatoire si présent | oui | `A1B2C3D4` | Linux, Windows | Linux : `dmidecode -t memory` · Windows : `CIM Win32_PhysicalMemory` | Réservé au demandeur | `raw` uniquement |
| `memory.modules[].type` | chaîne [1 à 256] | — | obligatoire si présent | oui | `DDR4` | Linux, Windows | Linux : `dmidecode -t memory` · Windows : `CIM Win32_PhysicalMemory` | Public | `raw` uniquement |
| `memory.modules[].ratedSpeedMts` | entier [≥ 0] | — | obligatoire si présent | oui | `3200` | Linux, Windows | Linux : `dmidecode -t memory` · Windows : `CIM Win32_PhysicalMemory` | Public | `raw` uniquement |
| `memory.modules[].configuredSpeedMts` | entier [≥ 0] | — | obligatoire si présent | oui | `3200` | Linux, Windows | Linux : `dmidecode -t memory` · Windows : `CIM Win32_PhysicalMemory` | Public | `raw` uniquement |
| `memory.modules[].performanceProfile.technology` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `dmidecode -t memory` · Windows : `CIM Win32_PhysicalMemory` | Public | `raw` uniquement |
| `memory.modules[].performanceProfile.active` | booléen | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `dmidecode -t memory` · Windows : `CIM Win32_PhysicalMemory` | Public | `raw` uniquement |
| `memory.modules[].performanceProfile.profileName` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `dmidecode -t memory` · Windows : `CIM Win32_PhysicalMemory` | Public | `raw` uniquement |
| `memory.modules[].voltage` | nombre [0 à 10] | — | obligatoire si présent | oui | `1.2` | Linux, Windows | Linux : `dmidecode -t memory` · Windows : `CIM Win32_PhysicalMemory` | Public | `raw` uniquement |
| `memory.modules[].ecc` | booléen | — | obligatoire si présent | oui | `false` | Linux, Windows | Linux : `dmidecode -t memory` · Windows : `CIM Win32_PhysicalMemory` | Public | `raw` uniquement |
| `memory.modules[].formFactor` | chaîne [1 à 256] | — | obligatoire si présent | oui | `DIMM` | Linux, Windows | Linux : `dmidecode -t memory` · Windows : `CIM Win32_PhysicalMemory` | Public | `raw` uniquement |
| `memory.installedBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `34359738368` | Linux, Windows | Linux : `/proc/meminfo, dmidecode -t memory` · Windows : `CIM Win32_PhysicalMemory` | Public | `Scan.memoryBytes` |
| `memory.availableBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `12884901888` | Linux, Windows | Linux : `/proc/meminfo, dmidecode -t memory` · Windows : `CIM Win32_PhysicalMemory` | Public | `raw` uniquement |
| `memory.slotsTotal` | entier [≥ 0] | — | obligatoire si présent | oui | `4` | Linux, Windows | Linux : `/proc/meminfo, dmidecode -t memory` · Windows : `CIM Win32_PhysicalMemory` | Public | `raw` uniquement |
| `memory.slotsUsed` | entier [≥ 0] | — | obligatoire si présent | oui | `2` | Linux, Windows | Linux : `/proc/meminfo, dmidecode -t memory` · Windows : `CIM Win32_PhysicalMemory` | Public | `raw` uniquement |
| `memory.maxCapacityBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `137438953472` | Linux, Windows | Linux : `/proc/meminfo, dmidecode -t memory` · Windows : `CIM Win32_PhysicalMemory` | Public | `raw` uniquement |
| `memory.swapTotalBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `8589934592` | Linux, Windows | Linux : `/proc/meminfo, dmidecode -t memory` · Windows : `CIM Win32_PhysicalMemory` | Public | `raw` uniquement |
| `memory.swapUsedBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `0` | Linux, Windows | Linux : `/proc/meminfo, dmidecode -t memory` · Windows : `CIM Win32_PhysicalMemory` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `memory.modules` — Barrettes installées, connecteur par connecteur : capacité, type, fréquence nominale et configurée, ECC, profil XMP/EXPO actif. *(depuis le schéma 1.0.0)*
- `memory.modules[].serialNumber` — Numéro de série de la barrette. *(depuis le schéma 1.0.0)*
- `memory` — Mémoire vive : capacité installée et disponible, connecteurs, espace d’échange. *(depuis le schéma 1.0.0)*

### `gpus`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `gpus[].vendor` | chaîne [1 à 256] | — | obligatoire si présent | oui | `NVIDIA` | Linux, Windows | Linux : `lspci, nvidia-smi, /sys/class/drm` · Windows : `CIM Win32_VideoController` | Public | `Scan.gpuVendor` |
| `gpus[].model` | chaîne [1 à 256] | — | obligatoire si présent | oui | `GeForce RTX 2060` | Linux, Windows | Linux : `lspci, nvidia-smi, /sys/class/drm` · Windows : `CIM Win32_VideoController` | Public | `raw` uniquement |
| `gpus[].pciId` | chaîne [1 à 256] | — | obligatoire si présent | oui | `10de:1f08` | Linux, Windows | Linux : `lspci, nvidia-smi, /sys/class/drm` · Windows : `CIM Win32_VideoController` | Public | `raw` uniquement |
| `gpus[].vramBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `6442450944` | Linux, Windows | Linux : `lspci, nvidia-smi, /sys/class/drm` · Windows : `CIM Win32_VideoController` | Public | `raw` uniquement |
| `gpus[].driver` | chaîne [1 à 256] | — | obligatoire si présent | oui | `nvidia` | Linux, Windows | Linux : `lspci, nvidia-smi, /sys/class/drm` · Windows : `CIM Win32_VideoController` | Public | `raw` uniquement |
| `gpus[].driverVersion` | chaîne [1 à 256] | — | obligatoire si présent | oui | `550.127.05` | Linux, Windows | Linux : `lspci, nvidia-smi, /sys/class/drm` · Windows : `CIM Win32_VideoController` | Public | `raw` uniquement |
| `gpus[].driverDate` | date ISO 8601 | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `lspci, nvidia-smi, /sys/class/drm` · Windows : `CIM Win32_VideoController` | Public | `raw` uniquement |
| `gpus[].temperatureCelsius` | nombre [-100 à 200] | °C | obligatoire si présent | oui | `38` | Linux, Windows | Linux : `lspci, nvidia-smi, /sys/class/drm` · Windows : `CIM Win32_VideoController` | Public | `raw` uniquement |
| `gpus[].usagePercent` | nombre [0 à 100] | % | obligatoire si présent | oui | `0` | Linux, Windows | Linux : `lspci, nvidia-smi, /sys/class/drm` · Windows : `CIM Win32_VideoController` | Public | `raw` uniquement |
| `gpus[].coreClockMhz` | entier [0 à 100000] | MHz | obligatoire si présent | oui | `300` | Linux, Windows | Linux : `lspci, nvidia-smi, /sys/class/drm` · Windows : `CIM Win32_VideoController` | Public | `raw` uniquement |
| `gpus[].memoryClockMhz` | entier [0 à 100000] | MHz | obligatoire si présent | oui | `405` | Linux, Windows | Linux : `lspci, nvidia-smi, /sys/class/drm` · Windows : `CIM Win32_VideoController` | Public | `raw` uniquement |
| `gpus[].displays[].name` | chaîne [1 à 256] | — | obligatoire si présent | oui | `DP-1` | Linux, Windows | Linux : `xrandr, /sys/class/drm` · Windows : `CIM WmiMonitorID` | Public | `raw` uniquement |
| `gpus[].displays[].manufacturer` | chaîne [1 à 256] | — | obligatoire si présent | oui | `DEL` | Linux, Windows | Linux : `xrandr, /sys/class/drm` · Windows : `CIM WmiMonitorID` | Public | `raw` uniquement |
| `gpus[].displays[].model` | chaîne [1 à 256] | — | facultatif | oui | `DELL U2720Q` | Linux, Windows | Linux : `xrandr, /sys/class/drm` · Windows : `CIM WmiMonitorID` | Public | `raw` uniquement |
| `gpus[].displays[].serialNumber` | chaîne [1 à 256] | — | facultatif | oui | `CN-0ABCD-72` | Linux, Windows | Linux : `/sys/class/drm/*/edid` · Windows : `CIM WmiMonitorID` | Réservé au demandeur | `raw` uniquement |
| `gpus[].displays[].resolution` | chaîne [1 à 256] | — | obligatoire si présent | oui | `3840x2160` | Linux, Windows | Linux : `xrandr, /sys/class/drm` · Windows : `CIM WmiMonitorID` | Public | `raw` uniquement |
| `gpus[].displays[].refreshRateHz` | entier [≥ 0] | — | obligatoire si présent | oui | `60` | Linux, Windows | Linux : `xrandr, /sys/class/drm` · Windows : `CIM WmiMonitorID` | Public | `raw` uniquement |
| `gpus[].displays[].connection` | chaîne [1 à 256] | — | obligatoire si présent | oui | `DP` | Linux, Windows | Linux : `xrandr, /sys/class/drm` · Windows : `CIM WmiMonitorID` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `gpus` — Cartes graphiques : modèle, mémoire vidéo, pilote, et — quand un capteur existe — température, charge et fréquences. *(depuis le schéma 1.0.0)*
- `gpus[].displays` — Écrans réellement raccordés à cette carte : définition, taux de rafraîchissement. *(depuis le schéma 1.1.0)*
- `gpus[].displays[].serialNumber` — Numéro de série publié par l’écran dans son EDID — le seul identifiant d’exemplaire d’une dalle. *(depuis le schéma 1.25.0)*

### `audio`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `audio.devices[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `HDA Intel PCH` | Linux, Windows | Linux : `pactl, aplay, lspci` · Windows : `CIM Win32_SoundDevice` | Public | `raw` uniquement |
| `audio.devices[].vendor` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `pactl, aplay, lspci` · Windows : `CIM Win32_SoundDevice` | Public | `raw` uniquement |
| `audio.devices[].driver` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `pactl, aplay, lspci` · Windows : `CIM Win32_SoundDevice` | Public | `raw` uniquement |
| `audio.devices[].stack` | chaîne [1 à 256] | — | obligatoire si présent | oui | `alsa` | Linux, Windows | Linux : `pactl, aplay, lspci` · Windows : `CIM Win32_SoundDevice` | Public | `raw` uniquement |
| `audio.devices[].kind` | PLAYBACK \| CAPTURE \| PLAYBACK_CAPTURE \| MIDI \| CONTROLLER \| UNKNOWN | — | obligatoire si présent | non | `PLAYBACK_CAPTURE` | Linux, Windows | Linux : `pactl, aplay, lspci` · Windows : `CIM Win32_SoundDevice` | Public | `raw` uniquement |
| `audio.devices[].state` | ENABLED \| DISABLED \| UNKNOWN | — | obligatoire si présent | non | `ENABLED` | Linux, Windows | Linux : `pactl, aplay, lspci` · Windows : `CIM Win32_SoundDevice` | Public | `raw` uniquement |
| `audio.devices[].default` | booléen | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `pactl, aplay, lspci` · Windows : `CIM Win32_SoundDevice` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `audio` — Contrôleurs et périphériques audio, avec la pile logicielle qui les pilote. *(depuis le schéma 1.13.0)*

### `sensors`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `sensors.temperatures[].label` | chaîne [1 à 256] | — | obligatoire si présent | non | `Tctl` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors, smartctl, nvme, nvidia-smi` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor, SMART/NVMe, nvidia-smi` | Public | `raw` uniquement |
| `sensors.temperatures[].celsius` | nombre [-100 à 200] | °C | obligatoire si présent | non | `42.5` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors, smartctl, nvme, nvidia-smi` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor, SMART/NVMe, nvidia-smi` | Public | `raw` uniquement |
| `sensors.temperatures[].criticalCelsius` | nombre [-100 à 200] | °C | facultatif | oui | `95` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors, smartctl, nvme, nvidia-smi` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor, SMART/NVMe, nvidia-smi` | Public | `raw` uniquement |
| `sensors.temperatures[].highCelsius` | nombre [-100 à 200] | °C | facultatif | oui | — | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors, smartctl, nvme, nvidia-smi` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor, SMART/NVMe, nvidia-smi` | Public | `raw` uniquement |
| `sensors.temperatures[].category` | CPU \| GPU \| MOTHERBOARD \| CHIPSET \| VRM \| MEMORY \| DRIVE_HDD \| DRIVE_SSD \| DRIVE_NVME \| NETWORK \| BATTERY \| AMBIENT \| OTHER | — | facultatif | non | `CPU` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors, smartctl, nvme, nvidia-smi` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor, SMART/NVMe, nvidia-smi` | Public | `raw` uniquement |
| `sensors.temperatures[].device` | chaîne [1 à 256] | — | facultatif | non | `AMD Ryzen 7 5800X` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors, smartctl, nvme, nvidia-smi` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor, SMART/NVMe, nvidia-smi` | Public | `raw` uniquement |
| `sensors.temperatures[].source` | chaîne [1 à 256] | — | facultatif | non | `hwmon` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors, smartctl, nvme, nvidia-smi` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor, SMART/NVMe, nvidia-smi` | Public | `raw` uniquement |
| `sensors.temperatures[].sourcePath` | chaîne [1 à 1024] | — | facultatif | oui | `/sys/class/hwmon/hwmon2/temp1_input` | Linux | Linux : `/sys/class/hwmon, /sys/class/thermal` · Windows : impossible — les providers WMI rendent un identifiant de capteur, jamais un chemin de système de fichiers | Réservé au demandeur | `raw` uniquement |
| `sensors.temperatures[].scope` | LOCAL \| HYPERVISOR_HOST | — | facultatif | non | `LOCAL` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors, smartctl, nvme, nvidia-smi` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor, SMART/NVMe, nvidia-smi` | Public | `raw` uniquement |
| `sensors.temperatures[].quality` | MEASURED \| SUSPECT | — | facultatif | non | `MEASURED` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors, smartctl, nvme, nvidia-smi` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor, SMART/NVMe, nvidia-smi` | Public | `raw` uniquement |
| `sensors.temperatures[].minCelsius` | nombre [-100 à 200] | °C | facultatif | non | `41.8` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors, smartctl, nvme, nvidia-smi` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor, SMART/NVMe, nvidia-smi` | Public | `raw` uniquement |
| `sensors.temperatures[].averageCelsius` | nombre [-100 à 200] | °C | facultatif | non | `42.2` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors, smartctl, nvme, nvidia-smi` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor, SMART/NVMe, nvidia-smi` | Public | `raw` uniquement |
| `sensors.temperatures[].maxCelsius` | nombre [-100 à 200] | °C | facultatif | non | `42.5` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors, smartctl, nvme, nvidia-smi` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor, SMART/NVMe, nvidia-smi` | Public | `raw` uniquement |
| `sensors.temperatures[].sampleCount` | entier [≥ 0] | — | facultatif | non | `3` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors, smartctl, nvme, nvidia-smi` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor, SMART/NVMe, nvidia-smi` | Public | `raw` uniquement |
| `sensors.temperatures[].rawValue` | nombre | — | facultatif | non | `42500` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors, smartctl, nvme, nvidia-smi` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor, SMART/NVMe, nvidia-smi` | Public | `raw` uniquement |
| `sensors.temperatures[].rawUnit` | chaîne [1 à 256] | — | facultatif | non | `millidegree_celsius` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors, smartctl, nvme, nvidia-smi` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor, SMART/NVMe, nvidia-smi` | Public | `raw` uniquement |
| `sensors.temperatureCollection.probed` | entier [≥ 0] | — | facultatif | non | `14` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor` | Public | `raw` uniquement |
| `sensors.temperatureCollection.usable` | entier [≥ 0] | — | facultatif | non | `2` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor` | Public | `raw` uniquement |
| `sensors.temperatureCollection.discarded` | entier [≥ 0] | — | facultatif | non | `1` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor` | Public | `raw` uniquement |
| `sensors.temperatureCollection.discardedReadings[].label` | chaîne [1 à 256] | — | obligatoire si présent | non | `temp3` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor` | Public | `raw` uniquement |
| `sensors.temperatureCollection.discardedReadings[].source` | chaîne [1 à 256] | — | facultatif | non | `hwmon` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor` | Public | `raw` uniquement |
| `sensors.temperatureCollection.discardedReadings[].sourcePath` | chaîne [1 à 1024] | — | facultatif | oui | `/sys/class/hwmon/hwmon0/temp3_input` | Linux | Linux : `/sys/class/hwmon, /sys/class/thermal` | Réservé au demandeur | `raw` uniquement |
| `sensors.temperatureCollection.discardedReadings[].rawValue` | nombre | — | obligatoire si présent | non | `-127000` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor` | Public | `raw` uniquement |
| `sensors.temperatureCollection.discardedReadings[].rawUnit` | chaîne [1 à 256] | — | facultatif | non | `millidegree_celsius` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor` | Public | `raw` uniquement |
| `sensors.temperatureCollection.discardedReadings[].celsius` | nombre | — | facultatif | non | `-127` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor` | Public | `raw` uniquement |
| `sensors.temperatureCollection.discardedReadings[].reason` | OUT_OF_PHYSICAL_RANGE \| UNIT_UNDETERMINED \| NOT_A_THERMAL_SENSOR | — | obligatoire si présent | non | `OUT_OF_PHYSICAL_RANGE` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor` | Public | `raw` uniquement |
| `sensors.temperatureCollection.sources[]` | chaîne [1 à 256] | — | obligatoire si présent | non | `hwmon` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor` | Public | `raw` uniquement |
| `sensors.temperatureCollection.unavailableReason` | NO_SENSOR_EXPOSED \| SENSORS_UNREADABLE \| TOOL_MISSING \| VIRTUALIZED \| NOT_COLLECTED | — | facultatif | non | — | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor` | Public | `raw` uniquement |
| `sensors.temperatureCollection.suggestedTool` | chaîne [1 à 256] | — | facultatif | non | — | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor` | Public | `raw` uniquement |
| `sensors.temperatureCollection.sampleCount` | entier [≥ 0] | — | facultatif | non | `3` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor` | Public | `raw` uniquement |
| `sensors.temperatureCollection.sampleIntervalMs` | entier [≥ 0] | ms | facultatif | non | `1000` | Linux, Windows | Linux : `/sys/class/hwmon, /sys/class/thermal, sensors` · Windows : `LibreHardwareMonitor, OpenHardwareMonitor` | Public | `raw` uniquement |
| `sensors.fans[].label` | chaîne [1 à 256] | — | obligatoire si présent | non | `fan1` | Linux, Windows | Linux : `sensors (lm-sensors), /sys/class/hwmon` · Windows : `CIM MSAcpi/OpenHardware` | Public | `raw` uniquement |
| `sensors.fans[].rpm` | entier [≥ 0] | — | obligatoire si présent | oui | `980` | Linux, Windows | Linux : `sensors (lm-sensors), /sys/class/hwmon` · Windows : `CIM MSAcpi/OpenHardware` | Public | `raw` uniquement |
| `sensors.voltages[].label` | chaîne [1 à 256] | — | obligatoire si présent | non | `+12V` | Linux, Windows | Linux : `sensors (lm-sensors), /sys/class/hwmon` · Windows : `CIM MSAcpi/OpenHardware` | Public | `raw` uniquement |
| `sensors.voltages[].volts` | nombre [0 à 1000] | — | obligatoire si présent | non | `12.096` | Linux, Windows | Linux : `sensors (lm-sensors), /sys/class/hwmon` · Windows : `CIM MSAcpi/OpenHardware` | Public | `raw` uniquement |
| `sensors.powers[].label` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Linux, Windows | Linux : `hwmon (`power*_input`)` · Windows : `CIM / LibreHardwareMonitor` | Public | `raw` uniquement |
| `sensors.powers[].watts` | nombre [0 à 10000] | W | obligatoire si présent | non | — | Linux, Windows | Linux : `hwmon (`power*_input`)` · Windows : `CIM / LibreHardwareMonitor` | Public | `raw` uniquement |
| `sensors.powerSupplies[].label` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Linux, Windows | Linux : `sensors (lm-sensors), /sys/class/hwmon` · Windows : `CIM MSAcpi/OpenHardware` | Public | `raw` uniquement |
| `sensors.powerSupplies[].status` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `sensors (lm-sensors), /sys/class/hwmon` · Windows : `CIM MSAcpi/OpenHardware` | Public | `raw` uniquement |
| `sensors.powerSupplies[].watts` | entier [≥ 0] | W | obligatoire si présent | oui | — | Linux, Windows | Linux : `sensors (lm-sensors), /sys/class/hwmon` · Windows : `CIM MSAcpi/OpenHardware` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `sensors.temperatures` — Relevés thermiques normalisés : composant mesuré, matériel porteur, interface interrogée, valeur brute d’origine et statistiques des relevés réellement pris. Aucune valeur n’y est estimée. *(depuis le schéma 1.23.0)*
- `sensors.temperatures[].sourcePath` — Chemin exact de la sonde interrogée, conservé pour le diagnostic. Une arborescence de périphériques décrit une machine précise : elle n’est servie qu’à son propriétaire. *(depuis le schéma 1.23.0)*
- `sensors.temperatureCollection` — Ce que la collecte thermique a pu faire : sondes rencontrées, exploitables, écartées, et pourquoi rien n’a été relevé le cas échéant. *(depuis le schéma 1.23.0)*
- `sensors.temperatureCollection.discardedReadings[].sourcePath` — Chemin de la sonde dont la lecture a été écartée. Même traitement que les sondes retenues : réservé au propriétaire. *(depuis le schéma 1.23.0)*
- `sensors` — Relevés matériels bruts : températures, ventilateurs, tensions, alimentations. Ce sont les valeurs rendues par les capteurs, sans correction. *(depuis le schéma 1.0.0)*
- `sensors.powers` — Capteurs de puissance nommés par le micrologiciel, tels quels. Les noms varient d’une carte à l’autre : les normaliser inventerait une correspondance que rien n’atteste. *(depuis le schéma 1.18.0)*

### `power`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `power.batteries[].name` | chaîne [1 à 256] | — | obligatoire si présent | oui | `BAT0` | Linux | Linux : `/sys/class/power_supply, upower` | Public | `raw` uniquement |
| `power.batteries[].manufacturer` | chaîne [1 à 256] | — | obligatoire si présent | oui | `LGC` | Linux | Linux : `/sys/class/power_supply, upower` | Public | `raw` uniquement |
| `power.batteries[].model` | chaîne [1 à 256] | — | obligatoire si présent | oui | `5B10W13930` | Linux | Linux : `/sys/class/power_supply, upower` | Public | `raw` uniquement |
| `power.batteries[].serialNumber` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `/sys/class/power_supply` | Réservé au demandeur | `raw` uniquement |
| `power.batteries[].technology` | chaîne [1 à 256] | — | obligatoire si présent | oui | `Li-poly` | Linux | Linux : `/sys/class/power_supply, upower` | Public | `raw` uniquement |
| `power.batteries[].chargePercent` | nombre [0 à 100] | % | obligatoire si présent | oui | `87` | Linux | Linux : `/sys/class/power_supply, upower` | Public | `raw` uniquement |
| `power.batteries[].status` | CHARGING \| DISCHARGING \| FULL \| NOT_CHARGING \| UNKNOWN | — | obligatoire si présent | oui | `DISCHARGING` | Linux | Linux : `/sys/class/power_supply, upower` | Public | `raw` uniquement |
| `power.batteries[].designCapacityWh` | nombre [0 à 10000] | — | obligatoire si présent | oui | `57` | Linux | Linux : `/sys/class/power_supply, upower` | Public | `raw` uniquement |
| `power.batteries[].fullChargeCapacityWh` | nombre [0 à 10000] | — | obligatoire si présent | oui | `43.12` | Linux | Linux : `/sys/class/power_supply, upower` | Public | `raw` uniquement |
| `power.batteries[].cycleCount` | entier [≥ 0] | — | obligatoire si présent | oui | `412` | Linux | Linux : `/sys/class/power_supply, upower` | Public | `raw` uniquement |
| `power.batteries[].voltageVolts` | nombre [0 à 1000] | — | obligatoire si présent | oui | `11.52` | Linux | Linux : `/sys/class/power_supply, upower` | Public | `raw` uniquement |
| `power.acConnected` | booléen | — | obligatoire si présent | oui | `false` | Linux | Linux : `/sys/class/power_supply, upower` | Public | `raw` uniquement |
| `power.activePlan` | chaîne [1 à 256] | — | facultatif | oui | — | Linux, Windows | Linux : `/sys/firmware/acpi/platform_profile` · Windows : `Win32_PowerPlan` | Public | `raw` uniquement |
| `power.cpuGovernor` | chaîne [1 à 256] | — | facultatif | oui | — | Linux | Linux : `/sys/devices/system/cpu/cpu0/cpufreq` | Public | `raw` uniquement |
| `power.powerSupply.detected` | booléen | — | obligatoire si présent | non | `false` | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.type` | STANDARD_ATX \| DIGITAL_ATX \| LAPTOP_ADAPTER \| USB_PD \| UPS \| SERVER_MANAGED \| UNKNOWN | — | obligatoire si présent | non | `UNKNOWN` | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].label` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].type` | STANDARD_ATX \| DIGITAL_ATX \| LAPTOP_ADAPTER \| USB_PD \| UPS \| SERVER_MANAGED \| UNKNOWN | — | obligatoire si présent | non | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].location` | chaîne [1 à 256] | — | facultatif | oui | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].manufacturer` | chaîne [1 à 256] | — | facultatif | oui | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].model` | chaîne [1 à 256] | — | facultatif | oui | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].serialNumber` | chaîne [1 à 256] | — | facultatif | oui | — | Linux, Windows | Linux : `dmidecode --type 39, ipmitool fru` · Windows : `table SMBIOS brute` | Réservé au demandeur | `raw` uniquement |
| `power.powerSupply.units[].partNumber` | chaîne [1 à 256] | — | facultatif | oui | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].assetTag` | chaîne [1 à 256] | — | facultatif | oui | — | Linux, Windows | Linux : `dmidecode --type 39` · Windows : `table SMBIOS brute` | Réservé au demandeur | `raw` uniquement |
| `power.powerSupply.units[].revision` | chaîne [1 à 256] | — | facultatif | oui | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].firmware` | chaîne [1 à 256] | — | facultatif | oui | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].ratedPowerWatts` | nombre [0 à 30000] | W | facultatif | oui | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].status` | chaîne [1 à 256] | — | facultatif | oui | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].present` | booléen | — | facultatif | oui | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].hotReplaceable` | booléen | — | facultatif | oui | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].telemetry.available` | booléen | — | obligatoire si présent | non | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].telemetry.inputPowerWatts` | nombre [0 à 30000] | W | facultatif | oui | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].telemetry.outputPowerWatts` | nombre [0 à 30000] | W | facultatif | oui | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].telemetry.inputVoltageVolts` | nombre [0 à 1000] | — | facultatif | oui | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].telemetry.outputVoltageVolts` | nombre [0 à 1000] | — | facultatif | oui | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].telemetry.currentAmps` | nombre [0 à 1000] | — | facultatif | oui | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].telemetry.temperatureCelsius` | nombre [-100 à 200] | °C | facultatif | oui | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].telemetry.fanRpm` | entier [≥ 0] | — | facultatif | oui | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].telemetry.efficiencyPercent` | nombre [0 à 100] | % | facultatif | oui | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].telemetry.source` | SMBIOS \| CIM_POWER_SUPPLY \| SYSFS_POWER_SUPPLY \| HWMON \| HARDWARE_MONITOR \| USB_HID \| IPMI \| RAPL \| NVIDIA_SMI \| USER_PROVIDED | — | facultatif | non | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].source` | SMBIOS \| CIM_POWER_SUPPLY \| SYSFS_POWER_SUPPLY \| HWMON \| HARDWARE_MONITOR \| USB_HID \| IPMI \| RAPL \| NVIDIA_SMI \| USER_PROVIDED | — | obligatoire si présent | non | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.units[].confidence` | HIGH \| MEDIUM \| LOW | — | obligatoire si présent | non | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.rails[].label` | chaîne [1 à 256] | — | obligatoire si présent | non | `+12V` | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.rails[].volts` | nombre [-1000 à 1000] | — | obligatoire si présent | non | `12.096` | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.rails[].measuredBy` | MOTHERBOARD \| POWER_SUPPLY \| UNKNOWN | — | obligatoire si présent | non | `MOTHERBOARD` | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.rails[].source` | SMBIOS \| CIM_POWER_SUPPLY \| SYSFS_POWER_SUPPLY \| HWMON \| HARDWARE_MONITOR \| USB_HID \| IPMI \| RAPL \| NVIDIA_SMI \| USER_PROVIDED | — | obligatoire si présent | non | `HWMON` | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.rails[].chip` | chaîne [1 à 256] | — | facultatif | non | `nct6798` | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.rails[].sourcePath` | chaîne [1 à 1024] | — | facultatif | oui | `/sys/class/hwmon/hwmon1/in0_input` | Linux | Linux : `/sys/class/hwmon` | Réservé au demandeur | `raw` uniquement |
| `power.powerSupply.componentPower[].label` | chaîne [1 à 256] | — | obligatoire si présent | non | `package-0` | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.componentPower[].component` | CPU \| GPU \| SYSTEM \| OTHER | — | obligatoire si présent | non | `CPU` | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.componentPower[].watts` | nombre [0 à 10000] | W | obligatoire si présent | non | `31.4` | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.componentPower[].source` | SMBIOS \| CIM_POWER_SUPPLY \| SYSFS_POWER_SUPPLY \| HWMON \| HARDWARE_MONITOR \| USB_HID \| IPMI \| RAPL \| NVIDIA_SMI \| USER_PROVIDED | — | obligatoire si présent | non | `RAPL` | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.componentPower[].device` | chaîne [1 à 256] | — | facultatif | non | `AMD Ryzen 7 5800X` | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.componentPower[].windowMs` | entier [≥ 0] | ms | facultatif | non | `300` | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.componentPower[].sourcePath` | chaîne [1 à 1024] | — | facultatif | oui | `/sys/class/powercap/intel-rapl:0/energy_uj` | Linux | Linux : `/sys/class/powercap, /sys/class/hwmon` | Réservé au demandeur | `raw` uniquement |
| `power.powerSupply.sources[]` | SMBIOS \| CIM_POWER_SUPPLY \| SYSFS_POWER_SUPPLY \| HWMON \| HARDWARE_MONITOR \| USB_HID \| IPMI \| RAPL \| NVIDIA_SMI \| USER_PROVIDED | — | obligatoire si présent | non | `SYSFS_POWER_SUPPLY` | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.limitations[]` | ATX_NOT_SELF_DESCRIBING \| SMBIOS_TYPE_39_ABSENT \| NO_DIGITAL_INTERFACE \| RAILS_FROM_MOTHERBOARD \| SENSORS_UNREADABLE \| PRIVILEGE_REQUIRED \| TOOL_MISSING \| VIRTUALIZED \| NOT_COLLECTED | — | obligatoire si présent | non | `SMBIOS_TYPE_39_ABSENT` | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |
| `power.powerSupply.suggestedTool` | chaîne [1 à 256] | — | facultatif | non | — | Linux, Windows | Linux : `dmidecode --type 39, /sys/class/power_supply, /sys/class/hwmon, intel-rapl, nvidia-smi, ipmitool` · Windows : `CIM Win32_PowerSupply, table SMBIOS brute, LibreHardwareMonitor` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `power` — Alimentation secteur et batteries : capacité de conception, capacité actuelle, cycles, état de charge. *(depuis le schéma 1.1.0)*
- `power.batteries[].serialNumber` — Numéro de série de la batterie. *(depuis le schéma 1.1.0)*
- `power.activePlan` — Plan ou profil d’alimentation actif, nom natif. Il explique des mesures qui sembleraient sinon contradictoires : un processeur bridé à la moitié de sa fréquence sous un profil « économie d’énergie » n’a rien d’anormal. *(depuis le schéma 1.17.0)*
- `power.cpuGovernor` — Gouverneur de fréquence Linux (`performance`, `powersave`, `schedutil`). Sans objet sous Windows, qui n’a pas cpufreq. *(depuis le schéma 1.17.0)*
- `power.powerSupply` — Bloc d’alimentation : ce qu’une source a réellement établi de son identité, ses rails et la consommation des composants. Aucune puissance nominale n’y est déduite d’une consommation observée. *(depuis le schéma 1.24.0)*
- `power.powerSupply.units[].serialNumber` — Numéro de série du bloc d’alimentation. Il identifie un exemplaire au même titre que celui du châssis ou d’un disque. *(depuis le schéma 1.24.0)*
- `power.powerSupply.units[].assetTag` — Étiquette d’inventaire du bloc, posée par l’exploitant. Elle nomme un parc et sa numérotation interne. *(depuis le schéma 1.24.0)*
- `power.powerSupply.rails[].sourcePath` — Chemin exact de la sonde de tension. Même traitement que les sondes thermiques : une arborescence de périphériques décrit une machine précise. *(depuis le schéma 1.24.0)*
- `power.powerSupply.componentPower[].sourcePath` — Chemin du compteur d’énergie interrogé, conservé pour le diagnostic. *(depuis le schéma 1.24.0)*

### `storage`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `storage.disks[].device` | chaîne [1 à 256] | — | obligatoire si présent | non | `/dev/nvme0n1` | Linux, Windows | Linux : `lsblk, smartctl` · Windows : `Get-PhysicalDisk` | Public | `raw` uniquement |
| `storage.disks[].manufacturer` | chaîne [1 à 256] | — | obligatoire si présent | oui | `Samsung` | Linux, Windows | Linux : `lsblk, smartctl` · Windows : `Get-PhysicalDisk` | Public | `raw` uniquement |
| `storage.disks[].model` | chaîne [1 à 256] | — | obligatoire si présent | oui | `Samsung SSD 980 PRO 1TB` | Linux, Windows | Linux : `lsblk, smartctl` · Windows : `Get-PhysicalDisk` | Public | `raw` uniquement |
| `storage.disks[].serialNumber` | chaîne [1 à 256] | — | obligatoire si présent | oui | `S5GXNX0T123456` | Linux, Windows | Linux : `smartctl -i` · Windows : `Get-PhysicalDisk` | Réservé au demandeur | `raw` uniquement |
| `storage.disks[].wwn` | chaîne [1 à 256] | — | facultatif | oui | `0x5002538e40a1b2c3` | Linux, Windows | Linux : `/sys/block/*/wwid, lsblk -o WWN` · Windows : `Get-Disk` | Réservé au demandeur | `raw` uniquement |
| `storage.disks[].nguid` | chaîne [1 à 256] | — | facultatif | oui | `00000000000000000026b7683d5a1f2e` | Linux | Linux : `/sys/block/nvme*/nguid` | Réservé au demandeur | `raw` uniquement |
| `storage.disks[].eui64` | chaîne [1 à 256] | — | facultatif | oui | `0026b7683d5a1f2e` | Linux | Linux : `/sys/block/nvme*/eui` | Réservé au demandeur | `raw` uniquement |
| `storage.disks[].firmware` | chaîne [1 à 256] | — | obligatoire si présent | oui | `5B2QGXA7` | Linux, Windows | Linux : `lsblk, smartctl` · Windows : `Get-PhysicalDisk` | Public | `raw` uniquement |
| `storage.disks[].sizeBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `1000204886016` | Linux, Windows | Linux : `lsblk, smartctl` · Windows : `Get-PhysicalDisk` | Public | `raw` uniquement |
| `storage.disks[].kind` | HDD \| SSD \| NVME \| SAS \| USB \| SD \| VIRTUAL \| UNKNOWN | — | obligatoire si présent | non | `NVME` | Linux, Windows | Linux : `lsblk, smartctl` · Windows : `Get-PhysicalDisk` | Public | `raw` uniquement |
| `storage.disks[].mediaType` | HDD \| SSD \| OPTICAL \| TAPE \| UNKNOWN | — | facultatif | oui | `SSD` | Linux, Windows | Linux : `lsblk, smartctl` · Windows : `Get-PhysicalDisk` | Public | `raw` uniquement |
| `storage.disks[].busType` | NVME \| SATA \| SAS \| SCSI \| ATA \| USB \| RAID \| SD \| MMC \| FIBRE_CHANNEL \| ISCSI \| VIRTUAL \| UNKNOWN | — | facultatif | oui | `NVME` | Linux, Windows | Linux : `lsblk, smartctl` · Windows : `Get-PhysicalDisk` | Public | `raw` uniquement |
| `storage.disks[].protocol` | chaîne [1 à 256] | — | facultatif | oui | `NVMe` | Linux, Windows | Linux : `lsblk, smartctl` · Windows : `Get-PhysicalDisk` | Public | `raw` uniquement |
| `storage.disks[].interface` | chaîne [1 à 256] | — | obligatoire si présent | oui | `nvme` | Linux, Windows | Linux : `lsblk, smartctl` · Windows : `Get-PhysicalDisk` | Public | `raw` uniquement |
| `storage.disks[].rotationRpm` | entier [≥ 0] | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `lsblk, smartctl` · Windows : `Get-PhysicalDisk` | Public | `raw` uniquement |
| `storage.disks[].partitionTable` | GPT \| MBR \| UNKNOWN | — | obligatoire si présent | oui | `GPT` | Linux, Windows | Linux : `lsblk, smartctl` · Windows : `Get-PhysicalDisk` | Public | `raw` uniquement |
| `storage.disks[].removable` | booléen | — | obligatoire si présent | oui | `false` | Linux, Windows | Linux : `lsblk, smartctl` · Windows : `Get-PhysicalDisk` | Public | `raw` uniquement |
| `storage.disks[].trimSupported` | booléen | — | obligatoire si présent | oui | `true` | Linux, Windows | Linux : `lsblk, smartctl` · Windows : `Get-PhysicalDisk` | Public | `raw` uniquement |
| `storage.disks[].link.currentSpeed` | chaîne [1 à 256] | — | obligatoire si présent | oui | `16.0 GT/s PCIe` | Linux | Linux : `/sys/bus/pci, nvme id-ctrl` · Windows : impossible — CIM n’expose ni la vitesse ni la largeur de lien PCIe négociées | Public | `raw` uniquement |
| `storage.disks[].link.maxSpeed` | chaîne [1 à 256] | — | obligatoire si présent | oui | `16.0 GT/s PCIe` | Linux | Linux : `/sys/bus/pci, nvme id-ctrl` · Windows : impossible — CIM n’expose ni la vitesse ni la largeur de lien PCIe négociées | Public | `raw` uniquement |
| `storage.disks[].link.currentWidth` | entier [≥ 0] | — | obligatoire si présent | oui | `4` | Linux | Linux : `/sys/bus/pci, nvme id-ctrl` · Windows : impossible — CIM n’expose ni la vitesse ni la largeur de lien PCIe négociées | Public | `raw` uniquement |
| `storage.disks[].link.maxWidth` | entier [≥ 0] | — | obligatoire si présent | oui | `4` | Linux | Linux : `/sys/bus/pci, nvme id-ctrl` · Windows : impossible — CIM n’expose ni la vitesse ni la largeur de lien PCIe négociées | Public | `raw` uniquement |
| `storage.disks[].smart.status` | PASSED \| FAILED \| WARNING | — | obligatoire si présent | oui | `PASSED` | Linux, Windows | Linux : `smartctl -A` · Windows : `Get-StorageReliabilityCounter` | Public | `raw` uniquement |
| `storage.disks[].smart.temperatureCelsius` | nombre [-100 à 200] | °C | obligatoire si présent | oui | `51` | Linux, Windows | Linux : `smartctl -A` · Windows : `Get-StorageReliabilityCounter` | Public | `raw` uniquement |
| `storage.disks[].smart.powerOnHours` | entier [≥ 0] | — | obligatoire si présent | oui | `18240` | Linux, Windows | Linux : `smartctl -A` · Windows : `Get-StorageReliabilityCounter` | Public | `raw` uniquement |
| `storage.disks[].smart.powerCycles` | entier [≥ 0] | — | obligatoire si présent | oui | `412` | Linux, Windows | Linux : `smartctl -A` · Windows : `Get-StorageReliabilityCounter` | Public | `raw` uniquement |
| `storage.disks[].smart.reallocatedSectors` | entier [≥ 0] | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `smartctl -A` · Windows : `Get-StorageReliabilityCounter` | Public | `raw` uniquement |
| `storage.disks[].smart.pendingSectors` | entier [≥ 0] | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `smartctl -A` · Windows : `Get-StorageReliabilityCounter` | Public | `raw` uniquement |
| `storage.disks[].smart.uncorrectableErrors` | entier [≥ 0] | — | obligatoire si présent | oui | `0` | Linux, Windows | Linux : `smartctl -A` · Windows : `Get-StorageReliabilityCounter` | Public | `raw` uniquement |
| `storage.disks[].smart.wearPercent` | nombre [0 à 100] | % | obligatoire si présent | oui | — | Linux, Windows | Linux : `smartctl -A` · Windows : `Get-StorageReliabilityCounter` | Public | `raw` uniquement |
| `storage.disks[].smart.nvmePercentageUsed` | nombre [0 à 255] | — | obligatoire si présent | oui | `87` | Linux, Windows | Linux : `smartctl -A` · Windows : `Get-StorageReliabilityCounter` | Public | `raw` uniquement |
| `storage.disks[].smart.availableSparePercent` | nombre [0 à 100] | % | obligatoire si présent | oui | `32` | Linux, Windows | Linux : `smartctl -A` · Windows : `Get-StorageReliabilityCounter` | Public | `raw` uniquement |
| `storage.disks[].smart.availableSpareThresholdPercent` | nombre [0 à 100] | % | obligatoire si présent | oui | `10` | Linux, Windows | Linux : `smartctl -A` · Windows : `Get-StorageReliabilityCounter` | Public | `raw` uniquement |
| `storage.disks[].smart.mediaErrors` | entier [≥ 0] | — | obligatoire si présent | oui | `0` | Linux, Windows | Linux : `smartctl -A` · Windows : `Get-StorageReliabilityCounter` | Public | `raw` uniquement |
| `storage.disks[].smart.unsafeShutdowns` | entier [≥ 0] | — | facultatif | oui | `3` | Linux, Windows | Linux : `smartctl -A` · Windows : `Get-StorageReliabilityCounter` | Public | `raw` uniquement |
| `storage.disks[].smart.dataUnitsRead` | entier [≥ 0] | — | facultatif | oui | `286114552` | Linux, Windows | Linux : `smartctl -A` · Windows : `Get-StorageReliabilityCounter` | Public | `raw` uniquement |
| `storage.disks[].smart.dataUnitsWritten` | entier [≥ 0] | — | obligatoire si présent | oui | `412884221` | Linux, Windows | Linux : `smartctl -A` · Windows : `Get-StorageReliabilityCounter` | Public | `raw` uniquement |
| `storage.disks[].smart.attributes[].id` | entier [≥ 0] | — | facultatif | non | — | Linux, Windows | Linux : `smartctl -A` · Windows : `Get-StorageReliabilityCounter` | Public | `raw` uniquement |
| `storage.disks[].smart.attributes[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Linux, Windows | Linux : `smartctl -A` · Windows : `Get-StorageReliabilityCounter` | Public | `raw` uniquement |
| `storage.disks[].smart.attributes[].value` | nombre | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `smartctl -A` · Windows : `Get-StorageReliabilityCounter` | Public | `raw` uniquement |
| `storage.disks[].smart.attributes[].raw` | chaîne [1 à 256] | — | facultatif | non | — | Linux, Windows | Linux : `smartctl -A` · Windows : `Get-StorageReliabilityCounter` | Public | `raw` uniquement |
| `storage.disks[].partitions[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `/dev/nvme0n1p2` | Linux, Windows | Linux : `lsblk, df, cryptsetup` · Windows : `Get-Volume, Get-BitLockerVolume` | Public | `raw` uniquement |
| `storage.disks[].partitions[].uuid` | chaîne [1 à 256] | — | facultatif | oui | `b3e1f0a2-5c7d-4e8b-9a10-2f4c6d8e0b13` | Linux, Windows | Linux : `lsblk -o UUID` · Windows : `Get-Volume (UniqueId)` | Réservé au demandeur | `raw` uniquement |
| `storage.disks[].partitions[].partitionUuid` | chaîne [1 à 256] | — | facultatif | oui | `7c9e6679-7425-40de-944b-e07fc1f90ae7` | Linux, Windows | Linux : `lsblk -o PARTUUID` · Windows : `Get-Partition (Guid)` | Réservé au demandeur | `raw` uniquement |
| `storage.disks[].partitions[].mountPoint` | chaîne [1 à 256] | — | obligatoire si présent | oui | `/` | Linux, Windows | Linux : `lsblk, df, cryptsetup` · Windows : `Get-Volume, Get-BitLockerVolume` | Public | `raw` uniquement |
| `storage.disks[].partitions[].filesystem` | chaîne [1 à 256] | — | obligatoire si présent | oui | `ext4` | Linux, Windows | Linux : `lsblk, df, cryptsetup` · Windows : `Get-Volume, Get-BitLockerVolume` | Public | `raw` uniquement |
| `storage.disks[].partitions[].sizeBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `100000000000` | Linux, Windows | Linux : `lsblk, df, cryptsetup` · Windows : `Get-Volume, Get-BitLockerVolume` | Public | `raw` uniquement |
| `storage.disks[].partitions[].usedBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `93000000000` | Linux, Windows | Linux : `lsblk, df, cryptsetup` · Windows : `Get-Volume, Get-BitLockerVolume` | Public | `raw` uniquement |
| `storage.disks[].partitions[].freeBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `7000000000` | Linux, Windows | Linux : `lsblk, df, cryptsetup` · Windows : `Get-Volume, Get-BitLockerVolume` | Public | `raw` uniquement |
| `storage.disks[].partitions[].usagePercent` | nombre [0 à 100] | % | obligatoire si présent | oui | `93` | Linux, Windows | Linux : `lsblk, df, cryptsetup` · Windows : `Get-Volume, Get-BitLockerVolume` | Public | `raw` uniquement |
| `storage.disks[].partitions[].encrypted` | booléen | — | obligatoire si présent | oui | `false` | Linux, Windows | Linux : `lsblk, df, cryptsetup` · Windows : `Get-Volume, Get-BitLockerVolume` | Public | `raw` uniquement |
| `storage.disks[].partitions[].encryptionType` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `lsblk, df, cryptsetup` · Windows : `Get-Volume, Get-BitLockerVolume` | Public | `raw` uniquement |
| `storage.pools[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `rpool` | Linux, Windows | Linux : `mdadm, lvs, zpool` · Windows : `Get-StoragePool` | Public | `raw` uniquement |
| `storage.pools[].type` | chaîne [1 à 256] | — | obligatoire si présent | non | `zfs` | Linux, Windows | Linux : `mdadm, lvs, zpool` · Windows : `Get-StoragePool` | Public | `raw` uniquement |
| `storage.pools[].state` | chaîne [1 à 256] | — | obligatoire si présent | oui | `ONLINE` | Linux, Windows | Linux : `mdadm, lvs, zpool` · Windows : `Get-StoragePool` | Public | `raw` uniquement |
| `storage.pools[].sizeBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `2000398934016` | Linux, Windows | Linux : `mdadm, lvs, zpool` · Windows : `Get-StoragePool` | Public | `raw` uniquement |
| `storage.pools[].usedBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `812000000000` | Linux, Windows | Linux : `mdadm, lvs, zpool` · Windows : `Get-StoragePool` | Public | `raw` uniquement |
| `storage.pools[].members[]` | chaîne [1 à 256] | — | obligatoire si présent | non | `/dev/sda` | Linux, Windows | Linux : `mdadm, lvs, zpool` · Windows : `Get-StoragePool` | Public | `raw` uniquement |
| `storage.pools[].raidLevel` | chaîne [1 à 256] | — | facultatif | oui | `mirror` | Linux, Windows | Linux : `mdadm, lvs, zpool` · Windows : `Get-StoragePool` | Public | `raw` uniquement |
| `storage.pools[].redundant` | booléen | — | facultatif | oui | `true` | Linux, Windows | Linux : `mdadm, lvs, zpool` · Windows : `Get-StoragePool` | Public | `raw` uniquement |
| `storage.totalBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `3000603820032` | Linux, Windows | Linux : `lsblk, df, fstrim` · Windows : `CIM Win32_DiskDrive, Get-Volume` | Public | `Scan.storageBytes` |
| `storage.usedBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `905000000000` | Linux, Windows | Linux : `lsblk, df, fstrim` · Windows : `CIM Win32_DiskDrive, Get-Volume` | Public | `raw` uniquement |
| `storage.trimScheduled` | booléen | — | obligatoire si présent | oui | `false` | Linux, Windows | Linux : `lsblk, df, fstrim` · Windows : `CIM Win32_DiskDrive, Get-Volume` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `storage.disks` — Disques physiques : modèle, interface, taille, type de média, table de partitions, support du TRIM. *(depuis le schéma 1.0.0)*
- `storage.disks[].serialNumber` — Numéro de série du disque, utile pour une garantie ou un remplacement. *(depuis le schéma 1.0.0)*
- `storage.disks[].wwn` — World Wide Name du support — identifiant mondial lisible sans privilège, là où le numéro de série en demande. *(depuis le schéma 1.25.0)*
- `storage.disks[].nguid` — Identifiant global de l’espace de noms NVMe, quand le contrôleur en publie un. *(depuis le schéma 1.25.0)*
- `storage.disks[].eui64` — Identifiant IEEE EUI-64 de l’espace de noms NVMe, quand il est publié. *(depuis le schéma 1.25.0)*
- `storage.disks[].link` — Négociation du lien PCIe/SATA : vitesse et largeur obtenues face aux maximales. *(depuis le schéma 1.1.0)*
- `storage.disks[].smart` — Santé du disque telle que le disque la rapporte : heures d’allumage, secteurs réalloués, usure, erreurs non corrigées. Un compteur non lu est marqué absent, jamais mis à zéro. *(depuis le schéma 1.0.0)*
- `storage.disks[].partitions` — Partitions montées : système de fichiers, occupation, chiffrement. *(depuis le schéma 1.0.0)*
- `storage.disks[].partitions[].uuid` — Identifiant du système de fichiers — clé d’un /etc/fstab, et clé de rapprochement d’un même volume entre deux audits. *(depuis le schéma 1.25.0)*
- `storage.disks[].partitions[].partitionUuid` — Identifiant de la partition dans la table GPT, distinct de celui du système de fichiers : un reformatage change l’un sans l’autre. *(depuis le schéma 1.25.0)*
- `storage.pools` — Ensembles logiques — RAID logiciel, LVM, ZFS — avec leur état de redondance. *(depuis le schéma 1.4.0)*
- `storage` — Capacité totale et occupée, et état de la maintenance TRIM. *(depuis le schéma 1.0.0)*

### `network`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `network.interfaces[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `enp4s0` | Linux, Windows | Linux : `ip -j addr, ethtool` · Windows : `Get-NetAdapter` | Public | `raw` uniquement |
| `network.interfaces[].manufacturer` | chaîne [1 à 256] | — | obligatoire si présent | oui | `Realtek Semiconductor Co., Ltd.` | Linux, Windows | Linux : `ip -j addr, ethtool` · Windows : `Get-NetAdapter` | Public | `raw` uniquement |
| `network.interfaces[].model` | chaîne [1 à 256] | — | obligatoire si présent | oui | `RTL8125 2.5GbE Controller` | Linux, Windows | Linux : `ip -j addr, ethtool` · Windows : `Get-NetAdapter` | Public | `raw` uniquement |
| `network.interfaces[].mac` | chaîne | — | obligatoire si présent | oui | `00:1a:2b:3c:4d:5e` | Linux, Windows | Linux : `ip -j link` · Windows : `Get-NetAdapter` | Réservé au demandeur | `raw` uniquement |
| `network.interfaces[].type` | ethernet \| wifi \| bridge \| bond \| vlan \| vpn \| loopback \| virtual \| other | — | obligatoire si présent | oui | `ethernet` | Linux, Windows | Linux : `ip -j addr, ethtool` · Windows : `Get-NetAdapter` | Public | `raw` uniquement |
| `network.interfaces[].status` | UP \| DOWN \| UNKNOWN | — | obligatoire si présent | oui | `UP` | Linux, Windows | Linux : `ip -j addr, ethtool` · Windows : `Get-NetAdapter` | Public | `raw` uniquement |
| `network.interfaces[].speedMbps` | entier [≥ 0] | — | obligatoire si présent | oui | `2500` | Linux, Windows | Linux : `ip -j addr, ethtool` · Windows : `Get-NetAdapter` | Public | `raw` uniquement |
| `network.interfaces[].duplex` | FULL \| HALF | — | obligatoire si présent | oui | `FULL` | Linux, Windows | Linux : `ip -j addr, ethtool` · Windows : `Get-NetAdapter` | Public | `raw` uniquement |
| `network.interfaces[].vlanId` | entier [0 à 4094] | — | facultatif | oui | — | Linux, Windows | Linux : `ip -j addr, ethtool` · Windows : `Get-NetAdapter` | Public | `raw` uniquement |
| `network.interfaces[].mtu` | entier [≥ 0] | — | obligatoire si présent | oui | `1500` | Linux, Windows | Linux : `ip -j addr, ethtool` · Windows : `Get-NetAdapter` | Public | `raw` uniquement |
| `network.interfaces[].driver` | chaîne [1 à 256] | — | obligatoire si présent | oui | `r8169` | Linux, Windows | Linux : `ip -j addr, ethtool` · Windows : `Get-NetAdapter` | Public | `raw` uniquement |
| `network.interfaces[].dhcp` | booléen | — | obligatoire si présent | oui | `false` | Linux, Windows | Linux : `ip -j addr, ethtool` · Windows : `Get-NetAdapter` | Public | `raw` uniquement |
| `network.interfaces[].ipv4[].address` | adresse IPv4 \| chaîne | — | obligatoire si présent | non | `192.168.1.20` | Linux, Windows | Linux : `ip -j addr` · Windows : `Get-NetIPAddress` | Réservé au demandeur | `raw` uniquement |
| `network.interfaces[].ipv4[].prefixLength` | entier [0 à 32] | — | facultatif | non | `24` | Linux, Windows | Linux : `ip -j addr` · Windows : `Get-NetIPAddress` | Réservé au demandeur | `raw` uniquement |
| `network.interfaces[].ipv6[].address` | adresse IPv6 \| chaîne | — | obligatoire si présent | non | `fe80::21a:2bff:fe3c:4d5e` | Linux, Windows | Linux : `ip -j addr` · Windows : `Get-NetIPAddress` | Réservé au demandeur | `raw` uniquement |
| `network.interfaces[].ipv6[].prefixLength` | entier [0 à 128] | — | facultatif | non | `64` | Linux, Windows | Linux : `ip -j addr` · Windows : `Get-NetIPAddress` | Réservé au demandeur | `raw` uniquement |
| `network.interfaces[].gateway` | chaîne [1 à 256] | — | obligatoire si présent | oui | `192.168.1.1` | Linux, Windows | Linux : `ip route show default` · Windows : `Get-NetIPConfiguration` | Réservé au demandeur | `raw` uniquement |
| `network.interfaces[].wifi.ssid` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `iw dev` · Windows : `netsh wlan show interfaces` | Anonymisable à la collecte | `raw` uniquement |
| `network.interfaces[].wifi.signalPercent` | nombre [0 à 100] | % | obligatoire si présent | oui | — | Linux, Windows | Linux : `iw, nmcli` · Windows : `netsh wlan` | Public | `raw` uniquement |
| `network.interfaces[].wifi.signalDbm` | nombre [-120 à 0] | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `iw, nmcli` · Windows : `netsh wlan` | Public | `raw` uniquement |
| `network.interfaces[].wifi.frequencyMhz` | entier [≥ 0] | MHz | obligatoire si présent | oui | — | Linux, Windows | Linux : `iw, nmcli` · Windows : `netsh wlan` | Public | `raw` uniquement |
| `network.interfaces[].wifi.channel` | entier [≥ 0] | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `iw, nmcli` · Windows : `netsh wlan` | Public | `raw` uniquement |
| `network.interfaces[].wifi.standard` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `iw, nmcli` · Windows : `netsh wlan` | Public | `raw` uniquement |
| `network.interfaces[].wifi.linkSpeedMbps` | entier [≥ 0] | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `iw, nmcli` · Windows : `netsh wlan` | Public | `raw` uniquement |
| `network.dnsServers[]` | chaîne [1 à 256] | — | obligatoire si présent | non | `192.168.1.1` | Linux, Windows | Linux : `resolvectl, /etc/resolv.conf` · Windows : `Get-DnsClientServerAddress` | Réservé au demandeur | `raw` uniquement |
| `network.searchDomains[]` | chaîne [1 à 256] | — | obligatoire si présent | non | `lan` | Linux, Windows | Linux : `resolvectl` · Windows : `Get-DnsClientGlobalSetting` | Réservé au demandeur | `raw` uniquement |
| `network.publicIp` | chaîne [1 à 256] | — | facultatif | oui | `198.51.100.7` | Linux, Windows | Linux : `--public-ip` · Windows : `-PublicIp` | Réservé au demandeur | `raw` uniquement |
| `network.listeningPorts[].protocol` | tcp \| tcp6 \| udp \| udp6 | — | obligatoire si présent | non | `tcp` | Linux, Windows | Linux : `ss -tulpn` · Windows : `Get-NetTCPConnection` | Public | `raw` uniquement |
| `network.listeningPorts[].port` | entier [0 à 65535] | — | obligatoire si présent | non | `22` | Linux, Windows | Linux : `ss -tulpn` · Windows : `Get-NetTCPConnection` | Public | `raw` uniquement |
| `network.listeningPorts[].address` | chaîne [1 à 256] | — | obligatoire si présent | oui | `0.0.0.0` | Linux, Windows | Linux : `ss -tulpn` · Windows : `Get-NetTCPConnection` | Réservé au demandeur | `raw` uniquement |
| `network.listeningPorts[].process` | chaîne [1 à 256] | — | obligatoire si présent | oui | `sshd` | Linux, Windows | Linux : `ss -tulpn` · Windows : `Get-NetTCPConnection` | Public | `raw` uniquement |
| `network.listeningPorts[].exposed` | booléen | — | obligatoire si présent | non | `true` | Linux, Windows | Linux : `ss -tulpn` · Windows : `Get-NetTCPConnection` | Public | `raw` uniquement |
| `network.routes[].destination` | chaîne [1 à 256] | — | obligatoire si présent | non | `default` | Linux, Windows | Linux : `ip -j route` · Windows : `Get-NetRoute` | Public | `raw` uniquement |
| `network.routes[].gateway` | chaîne [1 à 256] | — | obligatoire si présent | oui | `192.168.1.1` | Linux, Windows | Linux : `ip -j route` · Windows : `Get-NetRoute` | Réservé au demandeur | `raw` uniquement |
| `network.routes[].interface` | chaîne [1 à 256] | — | obligatoire si présent | oui | `enp4s0` | Linux, Windows | Linux : `ip -j route` · Windows : `Get-NetRoute` | Public | `raw` uniquement |
| `network.routes[].metric` | entier [≥ 0] | — | obligatoire si présent | oui | `100` | Linux, Windows | Linux : `ip -j route` · Windows : `Get-NetRoute` | Public | `raw` uniquement |
| `network.proxy.http` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `variables d’environnement, /etc/environment` · Windows : `Registre WinINET` | Public | `raw` uniquement |
| `network.proxy.https` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `variables d’environnement, /etc/environment` · Windows : `Registre WinINET` | Public | `raw` uniquement |
| `network.proxy.noProxy` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `variables d’environnement, /etc/environment` · Windows : `Registre WinINET` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `network.interfaces` — Cartes réseau : type, état du lien, débit négocié, duplex, VLAN, MTU, pilote, et adresses attribuées. *(depuis le schéma 1.0.0)*
- `network.interfaces[].mac` — Adresse matérielle de l’interface. *(depuis le schéma 1.0.0)*
- `network.interfaces[].ipv4` — Adresses IPv4 attribuées à l’interface, avec leur longueur de préfixe. *(depuis le schéma 1.0.0)*
- `network.interfaces[].ipv6` — Adresses IPv6 attribuées à l’interface, avec leur longueur de préfixe. *(depuis le schéma 1.0.0)*
- `network.interfaces[].gateway` — Passerelle par défaut de l’interface. Protéger les adresses de la machine en publiant sa passerelle ne protège rien : les deux désignent le même réseau. *(depuis le schéma 1.0.0)*
- `network.interfaces[].wifi.ssid` — Nom du réseau sans fil associé — il situe géographiquement la machine. *(depuis le schéma 1.0.0)*
- `network.interfaces[].wifi` — Lien sans fil en cours : réseau associé, qualité du signal, canal, norme. *(depuis le schéma 1.0.0)*
- `network.dnsServers` — Résolveurs configurés. Sur la quasi-totalité des postes, le premier est la box ou le contrôleur de domaine : son adresse **est** le plan d’adressage local. *(depuis le schéma 1.0.0)*
- `network.searchDomains` — Domaines de recherche DNS — souvent le nom du domaine d’entreprise. *(depuis le schéma 1.0.0)*
- `network.publicIp` — Adresse publique (WAN) vue depuis Internet. Collectée uniquement sur demande explicite : c’est le seul champ du rapport dont la lecture émet un paquet vers l’extérieur. *(depuis le schéma 1.0.0)*
- `network.listeningPorts` — Ports en écoute, avec le processus qui les tient et le fait qu’ils soient joignables hors de la machine. *(depuis le schéma 1.0.0)*
- `network.listeningPorts[].address` — Adresse de liaison. Générique le plus souvent (`0.0.0.0`, `127.0.0.1`), mais un service lié à une interface précise y inscrit l’adresse LAN de la machine. Ce que cette adresse apprend d’utile à un tiers — l’écoute déborde-t-elle la boucle locale — est déjà porté par `exposed`. *(depuis le schéma 1.0.0)*
- `network.routes` — Table de routage : destination, passerelle, interface, métrique. La table entière est retirée à un lecteur non propriétaire, et non expurgée ligne à ligne : une destination `192.168.1.0/24` est le plan d’adressage écrit en toutes lettres, et une route dont la destination et la passerelle seraient toutes deux retenues ne porterait plus qu’un nom d’interface et une métrique. *(depuis le schéma 1.5.0)*
- `network.routes[].gateway` — Prochain saut. Même adresse que la passerelle d’interface, par un autre chemin. *(depuis le schéma 1.5.0)*
- `network.proxy` — Mandataire HTTP configuré au niveau du système. *(depuis le schéma 1.5.0)*

### `devices`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `devices.pci[].bus` | PCI \| PCIE \| USB \| OTHER | — | obligatoire si présent | non | `PCI` | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.pci[].hardwareId` | chaîne [1 à 256] | — | obligatoire si présent | oui | `10de:1f08` | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.pci[].vendorId` | chaîne [1 à 256] | — | obligatoire si présent | oui | `10de` | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.pci[].deviceId` | chaîne [1 à 256] | — | obligatoire si présent | oui | `1f08` | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.pci[].vendor` | chaîne [1 à 256] | — | obligatoire si présent | oui | `NVIDIA Corporation` | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.pci[].name` | chaîne [1 à 256] | — | obligatoire si présent | oui | `TU106 [GeForce RTX 2060 Rev. A]` | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.pci[].class` | chaîne [1 à 256] | — | obligatoire si présent | oui | `VGA compatible controller` | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.pci[].driver` | chaîne [1 à 256] | — | obligatoire si présent | oui | `nvidia` | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.pci[].status` | OK \| DRIVER_MISSING \| DRIVER_ERROR \| DISABLED \| UNKNOWN_DEVICE \| UNKNOWN | — | obligatoire si présent | non | `OK` | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.pci[].address` | chaîne [1 à 256] | — | obligatoire si présent | oui | `01:00.0` | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.pci[].link.currentSpeed` | chaîne [1 à 256] | — | obligatoire si présent | oui | `2.5 GT/s PCIe` | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.pci[].link.maxSpeed` | chaîne [1 à 256] | — | obligatoire si présent | oui | `16.0 GT/s PCIe` | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.pci[].link.currentWidth` | entier [≥ 0] | — | obligatoire si présent | oui | `4` | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.pci[].link.maxWidth` | entier [≥ 0] | — | obligatoire si présent | oui | `16` | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.usb[].bus` | PCI \| PCIE \| USB \| OTHER | — | obligatoire si présent | non | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.usb[].hardwareId` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.usb[].vendorId` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.usb[].deviceId` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.usb[].vendor` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.usb[].name` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.usb[].class` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.usb[].driver` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.usb[].status` | OK \| DRIVER_MISSING \| DRIVER_ERROR \| DISABLED \| UNKNOWN_DEVICE \| UNKNOWN | — | obligatoire si présent | non | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.usb[].address` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.usb[].link.currentSpeed` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.usb[].link.maxSpeed` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.usb[].link.currentWidth` | entier [≥ 0] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.usb[].link.maxWidth` | entier [≥ 0] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.other[].bus` | PCI \| PCIE \| USB \| OTHER | — | obligatoire si présent | non | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.other[].hardwareId` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.other[].vendorId` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.other[].deviceId` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.other[].vendor` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.other[].name` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.other[].class` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.other[].driver` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.other[].status` | OK \| DRIVER_MISSING \| DRIVER_ERROR \| DISABLED \| UNKNOWN_DEVICE \| UNKNOWN | — | obligatoire si présent | non | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.other[].address` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.other[].link.currentSpeed` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.other[].link.maxSpeed` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.other[].link.currentWidth` | entier [≥ 0] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |
| `devices.other[].link.maxWidth` | entier [≥ 0] | — | obligatoire si présent | oui | — | Linux | Linux : `lspci, lsusb` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `devices` — Énumération PCI, USB et autres bus : identifiants constructeur, classe, pilote attaché, état. *(depuis le schéma 1.0.0)*

### `drivers`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `drivers[].device` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `lsmod, modinfo` | Public | `raw` uniquement |
| `drivers[].hardwareId` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `lsmod, modinfo` | Public | `raw` uniquement |
| `drivers[].vendor` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `lsmod, modinfo` | Public | `raw` uniquement |
| `drivers[].name` | chaîne [1 à 256] | — | obligatoire si présent | oui | `nvidia` | Linux | Linux : `lsmod, modinfo` | Public | `raw` uniquement |
| `drivers[].version` | chaîne [1 à 256] | — | obligatoire si présent | oui | `550.54.14` | Linux | Linux : `lsmod, modinfo` | Public | `raw` uniquement |
| `drivers[].date` | date ISO 8601 | — | obligatoire si présent | oui | — | Linux | Linux : `lsmod, modinfo` | Public | `raw` uniquement |
| `drivers[].provider` | chaîne [1 à 256] | — | obligatoire si présent | oui | `noyau Linux` | Linux | Linux : `lsmod, modinfo` | Public | `raw` uniquement |
| `drivers[].signed` | booléen | — | obligatoire si présent | oui | — | Linux | Linux : `lsmod, modinfo` | Public | `raw` uniquement |
| `drivers[].infName` | chaîne [1 à 256] | — | obligatoire si présent | oui | `nvidia` | Linux | Linux : `lsmod, modinfo` | Public | `raw` uniquement |
| `drivers[].status` | CURRENT \| POTENTIALLY_OUTDATED \| UPDATE_AVAILABLE \| MISSING \| ERROR \| UNKNOWN | — | obligatoire si présent | non | `UNKNOWN` | Linux | Linux : `lsmod, modinfo` | Public | `raw` uniquement |
| `drivers[].availableVersion` | chaîne [1 à 256] | — | facultatif | oui | — | Linux | Linux : `lsmod, modinfo` | Public | `raw` uniquement |
| `drivers[].source.name` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Linux | Linux : `lsmod, modinfo` | Public | `raw` uniquement |
| `drivers[].source.vendor` | chaîne [1 à 256] | — | facultatif | non | — | Linux | Linux : `lsmod, modinfo` | Public | `raw` uniquement |
| `drivers[].source.title` | chaîne [1 à 1024] | — | facultatif | non | — | Linux | Linux : `lsmod, modinfo` | Public | `raw` uniquement |
| `drivers[].source.url` | URL | — | facultatif | non | — | Linux | Linux : `lsmod, modinfo` | Public | `raw` uniquement |
| `drivers[].source.checkedAt` | date-heure ISO 8601 (UTC) | — | facultatif | non | — | Linux | Linux : `lsmod, modinfo` | Public | `raw` uniquement |
| `drivers[].note` | chaîne [1 à 1024] | — | facultatif | non | — | Linux | Linux : `lsmod, modinfo` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `drivers` — Pilotes chargés, avec leur signature et — quand un catalogue le sait — la version disponible en amont. *(depuis le schéma 1.0.0)*

### `firmware`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `firmware[].component` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Linux | Linux : `fwupdmgr` | Public | `raw` uniquement |
| `firmware[].kind` | BIOS \| SSD \| NVME \| NIC \| GPU \| DEVICE \| OTHER | — | obligatoire si présent | non | — | Linux | Linux : `fwupdmgr` | Public | `raw` uniquement |
| `firmware[].installedVersion` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `fwupdmgr` | Public | `raw` uniquement |
| `firmware[].availableVersion` | chaîne [1 à 256] | — | facultatif | oui | — | Linux | Linux : `fwupdmgr` | Public | `raw` uniquement |
| `firmware[].releaseDate` | date ISO 8601 | — | facultatif | oui | — | Linux | Linux : `fwupdmgr` | Public | `raw` uniquement |
| `firmware[].source.name` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Linux | Linux : `fwupdmgr` | Public | `raw` uniquement |
| `firmware[].source.vendor` | chaîne [1 à 256] | — | facultatif | non | — | Linux | Linux : `fwupdmgr` | Public | `raw` uniquement |
| `firmware[].source.title` | chaîne [1 à 1024] | — | facultatif | non | — | Linux | Linux : `fwupdmgr` | Public | `raw` uniquement |
| `firmware[].source.url` | URL | — | facultatif | non | — | Linux | Linux : `fwupdmgr` | Public | `raw` uniquement |
| `firmware[].source.checkedAt` | date-heure ISO 8601 (UTC) | — | facultatif | non | — | Linux | Linux : `fwupdmgr` | Public | `raw` uniquement |
| `firmware[].checkedAt` | date-heure ISO 8601 (UTC) | — | facultatif | non | — | Linux | Linux : `fwupdmgr` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `firmware` — Micrologiciels de composants et mises à jour disponibles. Information externe : elle porte sa source et sa date de vérification. *(depuis le schéma 1.0.0)*

### `software`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `software.packages[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `openssh-server` | Linux, Windows | Linux : `dpkg, rpm, snap, flatpak, systemctl` · Windows : `registre de désinstallation, Get-AppxPackage, Win32_Service` | Public | `raw` uniquement |
| `software.packages[].version` | chaîne [1 à 256] | — | obligatoire si présent | oui | `1:9.2p1-2` | Linux, Windows | Linux : `dpkg, rpm, snap, flatpak, systemctl` · Windows : `registre de désinstallation, Get-AppxPackage, Win32_Service` | Public | `raw` uniquement |
| `software.packages[].source` | chaîne [1 à 256] | — | obligatoire si présent | oui | `apt` | Linux, Windows | Linux : `dpkg, rpm, snap, flatpak, systemctl` · Windows : `registre de désinstallation, Get-AppxPackage, Win32_Service` | Public | `raw` uniquement |
| `software.packages[].installDate` | date ISO 8601 | — | facultatif | oui | — | Linux, Windows | Linux : `dpkg, rpm, snap, flatpak, systemctl` · Windows : `registre de désinstallation, Get-AppxPackage, Win32_Service` | Public | `raw` uniquement |
| `software.packages[].vendor` | chaîne [1 à 256] | — | facultatif | oui | — | Linux, Windows | Linux : `dpkg, rpm, snap, flatpak, systemctl` · Windows : `registre de désinstallation, Get-AppxPackage, Win32_Service` | Public | `raw` uniquement |
| `software.packageCount` | entier [≥ 0] | — | facultatif | oui | `1284` | Linux, Windows | Linux : `dpkg, rpm, snap, flatpak, systemctl` · Windows : `registre de désinstallation, Get-AppxPackage, Win32_Service` | Public | `raw` uniquement |
| `software.packagesTruncated` | booléen | — | facultatif | non | `true` | Linux | Linux : `lib/collectors/software.sh` | Public | `raw` uniquement |
| `software.packageManagers[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `apt` | Linux, Windows | Linux : `dpkg, rpm, snap, flatpak, systemctl` · Windows : `registre de désinstallation, Get-AppxPackage, Win32_Service` | Public | `raw` uniquement |
| `software.packageManagers[].version` | chaîne [1 à 256] | — | obligatoire si présent | oui | `2.6.1` | Linux, Windows | Linux : `dpkg, rpm, snap, flatpak, systemctl` · Windows : `registre de désinstallation, Get-AppxPackage, Win32_Service` | Public | `raw` uniquement |
| `software.packageManagers[].packageCount` | entier [≥ 0] | — | obligatoire si présent | oui | `1282` | Linux, Windows | Linux : `dpkg, rpm, snap, flatpak, systemctl` · Windows : `registre de désinstallation, Get-AppxPackage, Win32_Service` | Public | `raw` uniquement |
| `software.runtimes[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `node` | Linux, Windows | Linux : `dpkg, rpm, snap, flatpak, systemctl` · Windows : `registre de désinstallation, Get-AppxPackage, Win32_Service` | Public | `raw` uniquement |
| `software.runtimes[].version` | chaîne [1 à 256] | — | obligatoire si présent | oui | `22.11.0` | Linux, Windows | Linux : `dpkg, rpm, snap, flatpak, systemctl` · Windows : `registre de désinstallation, Get-AppxPackage, Win32_Service` | Public | `raw` uniquement |
| `software.runtimes[].path` | chaîne [1 à 256] | — | obligatoire si présent | oui | `/usr/bin/node` | Linux, Windows | Linux : `dpkg, rpm, snap, flatpak, systemctl` · Windows : `registre de désinstallation, Get-AppxPackage, Win32_Service` | Public | `raw` uniquement |
| `software.services[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `ssh` | Linux, Windows | Linux : `dpkg, rpm, snap, flatpak, systemctl` · Windows : `registre de désinstallation, Get-AppxPackage, Win32_Service` | Public | `raw` uniquement |
| `software.services[].displayName` | chaîne [1 à 256] | — | facultatif | oui | — | Linux, Windows | Linux : `dpkg, rpm, snap, flatpak, systemctl` · Windows : `registre de désinstallation, Get-AppxPackage, Win32_Service` | Public | `raw` uniquement |
| `software.services[].state` | RUNNING \| STOPPED \| FAILED \| UNKNOWN | — | obligatoire si présent | oui | `RUNNING` | Linux, Windows | Linux : `dpkg, rpm, snap, flatpak, systemctl` · Windows : `registre de désinstallation, Get-AppxPackage, Win32_Service` | Public | `raw` uniquement |
| `software.services[].startup` | ENABLED \| DISABLED \| MANUAL \| UNKNOWN | — | obligatoire si présent | oui | `ENABLED` | Linux, Windows | Linux : `dpkg, rpm, snap, flatpak, systemctl` · Windows : `registre de désinstallation, Get-AppxPackage, Win32_Service` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `software` — Inventaire logiciel : paquets installés, gestionnaires, environnements d’exécution et services. *(depuis le schéma 1.0.0)*
- `software.packagesTruncated` — Vrai si la liste des paquets a été tronquée. Le compte total reste juste : c’est le détail qui manque, et il est dit. *(depuis le schéma 1.0.0)*

### `startup`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `startup.items[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `ssh` | Linux, Windows | Linux : `systemd --user, XDG autostart` · Windows : `Registre Run, Get-ScheduledTask` | Public | `raw` uniquement |
| `startup.items[].kind` | SERVICE \| REGISTRY \| STARTUP_FOLDER \| SCHEDULED_TASK \| DESKTOP_AUTOSTART \| OTHER | — | obligatoire si présent | non | `SERVICE` | Linux, Windows | Linux : `systemd --user, XDG autostart` · Windows : `Registre Run, Get-ScheduledTask` | Public | `raw` uniquement |
| `startup.items[].scope` | SYSTEM \| USER \| UNKNOWN | — | obligatoire si présent | non | `SYSTEM` | Linux, Windows | Linux : `systemd --user, XDG autostart` · Windows : `Registre Run, Get-ScheduledTask` | Public | `raw` uniquement |
| `startup.items[].enabled` | booléen | — | obligatoire si présent | oui | `true` | Linux, Windows | Linux : `systemd --user, XDG autostart` · Windows : `Registre Run, Get-ScheduledTask` | Public | `raw` uniquement |
| `startup.items[].command` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `systemd --user, XDG autostart` · Windows : `Registre Run, Get-ScheduledTask` | Public | `raw` uniquement |
| `startup.items[].location` | chaîne [1 à 256] | — | obligatoire si présent | oui | `systemd` | Linux, Windows | Linux : `systemd --user, XDG autostart` · Windows : `Registre Run, Get-ScheduledTask` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `startup` — Éléments lancés au démarrage de la session ou du système, avec leur origine. *(depuis le schéma 1.13.0)*

### `security`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `security.firewall.engine` | chaîne [1 à 256] | — | obligatoire si présent | oui | `nftables` | Linux, Windows | Linux : `ufw/firewalld/nft, apt, mokutil` · Windows : `Get-NetFirewallProfile` | Public | `raw` uniquement |
| `security.firewall.state` | ENABLED \| DISABLED \| UNSUPPORTED \| PARTIAL | — | obligatoire si présent | oui | `DISABLED` | Linux, Windows | Linux : `ufw/firewalld/nft, apt, mokutil` · Windows : `Get-NetFirewallProfile` | Public | `raw` uniquement |
| `security.firewall.defaultInputPolicy` | chaîne [1 à 256] | — | obligatoire si présent | oui | `accept` | Linux, Windows | Linux : `ufw/firewalld/nft, apt, mokutil` · Windows : `Get-NetFirewallProfile` | Public | `raw` uniquement |
| `security.firewall.ruleCount` | entier [≥ 0] | — | obligatoire si présent | oui | `0` | Linux, Windows | Linux : `ufw/firewalld/nft, apt, mokutil` · Windows : `Get-NetFirewallProfile` | Public | `raw` uniquement |
| `security.firewall.profiles[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Linux, Windows | Linux : `ufw/firewalld/nft, apt, mokutil` · Windows : `Get-NetFirewallProfile` | Public | `raw` uniquement |
| `security.firewall.profiles[].state` | ENABLED \| DISABLED \| UNSUPPORTED \| PARTIAL | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `ufw/firewalld/nft, apt, mokutil` · Windows : `Get-NetFirewallProfile` | Public | `raw` uniquement |
| `security.updates.pending` | entier [≥ 0] | — | obligatoire si présent | oui | `34` | Linux, Windows | Linux : `ufw/firewalld/nft, apt, mokutil` · Windows : `Get-NetFirewallProfile` | Public | `raw` uniquement |
| `security.updates.securityPending` | entier [≥ 0] | — | obligatoire si présent | oui | `6` | Linux, Windows | Linux : `ufw/firewalld/nft, apt, mokutil` · Windows : `Get-NetFirewallProfile` | Public | `raw` uniquement |
| `security.updates.rebootRequired` | booléen | — | obligatoire si présent | oui | `true` | Linux, Windows | Linux : `ufw/firewalld/nft, apt, mokutil` · Windows : `Get-NetFirewallProfile` | Public | `raw` uniquement |
| `security.updates.lastCheck` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | `2026-07-25T04:00:00Z` | Linux, Windows | Linux : `ufw/firewalld/nft, apt, mokutil` · Windows : `Get-NetFirewallProfile` | Public | `raw` uniquement |
| `security.updates.lastUpdate` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | `2026-06-02T04:12:00Z` | Linux, Windows | Linux : `ufw/firewalld/nft, apt, mokutil` · Windows : `Get-NetFirewallProfile` | Public | `raw` uniquement |
| `security.updates.automaticUpdates` | ENABLED \| DISABLED \| UNSUPPORTED \| PARTIAL | — | obligatoire si présent | oui | `DISABLED` | Linux, Windows | Linux : `ufw/firewalld/nft, apt, mokutil` · Windows : `Get-NetFirewallProfile` | Public | `raw` uniquement |
| `security.secureBoot` | ENABLED \| DISABLED \| UNSUPPORTED \| PARTIAL | — | facultatif | oui | `DISABLED` | Linux, Windows | Linux : `ufw/firewalld/nft, apt, mokutil` · Windows : `Get-NetFirewallProfile` | Public | `raw` uniquement |
| `security.accounts[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `root` | Linux, Windows | Linux : `/etc/passwd, /etc/shadow (métadonnées)` · Windows : `Get-LocalUser` | Réservé au demandeur | `raw` uniquement |
| `security.accounts[].admin` | booléen | — | obligatoire si présent | oui | `true` | Linux, Windows | Linux : `/etc/passwd, /etc/shadow (métadonnées)` · Windows : `Get-LocalUser` | Réservé au demandeur | `raw` uniquement |
| `security.accounts[].enabled` | booléen | — | obligatoire si présent | oui | `true` | Linux, Windows | Linux : `/etc/passwd, /etc/shadow (métadonnées)` · Windows : `Get-LocalUser` | Réservé au demandeur | `raw` uniquement |
| `security.accounts[].passwordless` | booléen | — | obligatoire si présent | oui | `false` | Linux, Windows | Linux : `/etc/passwd, /etc/shadow (métadonnées)` · Windows : `Get-LocalUser` | Réservé au demandeur | `raw` uniquement |
| `security.accounts[].lastLogin` | date-heure ISO 8601 (UTC) | — | facultatif | oui | — | Linux, Windows | Linux : `/etc/passwd, /etc/shadow (métadonnées)` · Windows : `Get-LocalUser` | Réservé au demandeur | `raw` uniquement |
| `security.windows.defender.name` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.defender.enabled` | booléen | — | obligatoire si présent | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.defender.upToDate` | booléen | — | obligatoire si présent | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.defender.realtimeProtection` | booléen | — | obligatoire si présent | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.defender.lastScan` | date-heure ISO 8601 (UTC) | — | facultatif | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.defender.vendor` | chaîne [1 à 256] | — | facultatif | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.defender.version` | chaîne [1 à 256] | — | facultatif | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.defender.state` | ACTIVE \| PASSIVE \| DISABLED \| OUTDATED \| INSTALLED_UNKNOWN_STATE \| UNAVAILABLE | — | facultatif | non | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.defender.kind` | ANTIVIRUS \| ON_DEMAND_SCANNER \| EDR \| FIREWALL \| IDS_IPS \| UNKNOWN | — | facultatif | non | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.defender.source` | WINDOWS_SECURITY_CENTER \| DEFENDER_POWERSHELL \| PACKAGE_MANAGER \| SERVICE_MANAGER \| PROCESS_LIST \| PRODUCT_CLI | — | facultatif | non | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.defender.daemonRunning` | booléen | — | facultatif | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.defender.signatureDate` | date-heure ISO 8601 (UTC) | — | facultatif | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.thirdPartyAntivirus[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.thirdPartyAntivirus[].enabled` | booléen | — | obligatoire si présent | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.thirdPartyAntivirus[].upToDate` | booléen | — | obligatoire si présent | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.thirdPartyAntivirus[].realtimeProtection` | booléen | — | obligatoire si présent | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.thirdPartyAntivirus[].lastScan` | date-heure ISO 8601 (UTC) | — | facultatif | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.thirdPartyAntivirus[].vendor` | chaîne [1 à 256] | — | facultatif | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.thirdPartyAntivirus[].version` | chaîne [1 à 256] | — | facultatif | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.thirdPartyAntivirus[].state` | ACTIVE \| PASSIVE \| DISABLED \| OUTDATED \| INSTALLED_UNKNOWN_STATE \| UNAVAILABLE | — | facultatif | non | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.thirdPartyAntivirus[].kind` | ANTIVIRUS \| ON_DEMAND_SCANNER \| EDR \| FIREWALL \| IDS_IPS \| UNKNOWN | — | facultatif | non | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.thirdPartyAntivirus[].source` | WINDOWS_SECURITY_CENTER \| DEFENDER_POWERSHELL \| PACKAGE_MANAGER \| SERVICE_MANAGER \| PROCESS_LIST \| PRODUCT_CLI | — | facultatif | non | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.thirdPartyAntivirus[].daemonRunning` | booléen | — | facultatif | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.thirdPartyAntivirus[].signatureDate` | date-heure ISO 8601 (UTC) | — | facultatif | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.tpm.present` | booléen | — | obligatoire si présent | non | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.tpm.version` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.tpm.enabled` | booléen | — | obligatoire si présent | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.tpm.ready` | booléen | — | obligatoire si présent | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.bitlocker.state` | ENABLED \| DISABLED \| UNSUPPORTED \| PARTIAL | — | obligatoire si présent | non | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.bitlocker.protectedVolumes[]` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.uac` | ENABLED \| DISABLED \| UNSUPPORTED \| PARTIAL | — | obligatoire si présent | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.rdp.enabled` | booléen | — | obligatoire si présent | non | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.rdp.networkLevelAuthentication` | booléen | — | obligatoire si présent | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.smb.v1Enabled` | booléen | — | obligatoire si présent | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.smb.signingRequired` | booléen | — | obligatoire si présent | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.credentialGuard` | ENABLED \| DISABLED \| UNSUPPORTED \| PARTIAL | — | obligatoire si présent | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.hvci` | ENABLED \| DISABLED \| UNSUPPORTED \| PARTIAL | — | obligatoire si présent | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.vbs` | ENABLED \| DISABLED \| UNSUPPORTED \| PARTIAL | — | obligatoire si présent | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.windows.dmaProtection` | ENABLED \| DISABLED \| UNSUPPORTED \| PARTIAL | — | facultatif | oui | — | Windows | Windows : `Win32_DeviceGuard.AvailableSecurityProperties` | Public | `raw` uniquement |
| `security.windows.smartAppControl` | ENABLED \| DISABLED \| UNSUPPORTED \| PARTIAL | — | facultatif | oui | — | Windows | Windows : `HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy` | Public | `raw` uniquement |
| `security.windows.unsignedDrivers` | entier [≥ 0] | — | obligatoire si présent | oui | — | Windows | Windows : `Get-MpComputerStatus, Get-Tpm, Get-BitLockerVolume` | Public | `raw` uniquement |
| `security.linux.ssh.installed` | booléen | — | obligatoire si présent | non | `true` | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.ssh.running` | booléen | — | obligatoire si présent | oui | `true` | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.ssh.port` | entier [1 à 65535] | — | obligatoire si présent | oui | `22` | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.ssh.permitRootLogin` | chaîne [1 à 256] | — | obligatoire si présent | oui | `yes` | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.ssh.passwordAuthentication` | booléen | — | obligatoire si présent | oui | `true` | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.ssh.pubkeyAuthentication` | booléen | — | obligatoire si présent | oui | `true` | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.ssh.protocolVersion` | chaîne [1 à 256] | — | obligatoire si présent | oui | `2` | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.apparmor` | ENABLED \| DISABLED \| UNSUPPORTED \| PARTIAL | — | obligatoire si présent | oui | `ENABLED` | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.selinux` | ENFORCING \| PERMISSIVE \| DISABLED \| UNSUPPORTED | — | obligatoire si présent | oui | `UNSUPPORTED` | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.luks.present` | booléen | — | obligatoire si présent | non | `false` | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.luks.devices[]` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.sudoUsers` | entier [≥ 0] | — | obligatoire si présent | oui | `1` | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.intrusionPrevention[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `fail2ban` | Linux | Linux : `fail2ban-client, cscli` | Public | `raw` uniquement |
| `security.linux.intrusionPrevention[].installed` | booléen | — | obligatoire si présent | non | `true` | Linux | Linux : `fail2ban-client, cscli` | Public | `raw` uniquement |
| `security.linux.intrusionPrevention[].running` | booléen | — | obligatoire si présent | oui | `false` | Linux | Linux : `fail2ban-client, cscli` | Public | `raw` uniquement |
| `security.linux.intrusionPrevention[].activeJails` | entier [≥ 0] | — | obligatoire si présent | oui | — | Linux | Linux : `fail2ban-client, cscli` | Public | `raw` uniquement |
| `security.linux.securityProducts[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.securityProducts[].enabled` | booléen | — | obligatoire si présent | oui | — | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.securityProducts[].upToDate` | booléen | — | obligatoire si présent | oui | — | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.securityProducts[].realtimeProtection` | booléen | — | obligatoire si présent | oui | — | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.securityProducts[].lastScan` | date-heure ISO 8601 (UTC) | — | facultatif | oui | — | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.securityProducts[].vendor` | chaîne [1 à 256] | — | facultatif | oui | — | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.securityProducts[].version` | chaîne [1 à 256] | — | facultatif | oui | — | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.securityProducts[].state` | ACTIVE \| PASSIVE \| DISABLED \| OUTDATED \| INSTALLED_UNKNOWN_STATE \| UNAVAILABLE | — | facultatif | non | — | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.securityProducts[].kind` | ANTIVIRUS \| ON_DEMAND_SCANNER \| EDR \| FIREWALL \| IDS_IPS \| UNKNOWN | — | facultatif | non | — | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.securityProducts[].source` | WINDOWS_SECURITY_CENTER \| DEFENDER_POWERSHELL \| PACKAGE_MANAGER \| SERVICE_MANAGER \| PROCESS_LIST \| PRODUCT_CLI | — | facultatif | non | — | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.securityProducts[].daemonRunning` | booléen | — | facultatif | oui | — | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.securityProducts[].signatureDate` | date-heure ISO 8601 (UTC) | — | facultatif | oui | — | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.passwordlessAccounts` | entier [≥ 0] | — | obligatoire si présent | oui | `0` | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.linux.kernelHardening.sysctl` | objet à clés libres | — | facultatif | non | — | Linux | Linux : `sshd -T, aa-status, sestatus, cryptsetup, sysctl` | Public | `raw` uniquement |
| `security.obsoleteProtocols[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Linux, Windows | Linux : `lib/collectors/security.sh` · Windows : `lib/collectors/security.ps1` | Public | `raw` uniquement |
| `security.obsoleteProtocols[].enabled` | booléen | — | obligatoire si présent | non | — | Linux, Windows | Linux : `lib/collectors/security.sh` · Windows : `lib/collectors/security.ps1` | Public | `raw` uniquement |
| `security.obsoleteProtocols[].note` | chaîne [1 à 1024] | — | facultatif | non | — | Linux, Windows | Linux : `lib/collectors/security.sh` · Windows : `lib/collectors/security.ps1` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `security` — Posture de sécurité observée : pare-feu, mises à jour, démarrage sécurisé. *(depuis le schéma 1.0.0)*
- `security.accounts` — Comptes locaux : droits d’administration, activation, absence de mot de passe, dernière connexion. *(depuis le schéma 1.0.0)*
- `security.windows` — Contrôles propres à Windows : Defender, TPM, BitLocker, UAC, Credential Guard, RDP, SMB. *(depuis le schéma 1.0.0)*
- `security.windows.dmaProtection` — Protection DMA du noyau contre les attaques par port Thunderbolt ou PCIe. `PARTIAL` y signifie « le matériel l’annonce » : le lire comme actif promettrait une protection qui ne l’est peut-être pas. *(depuis le schéma 1.17.0)*
- `security.windows.smartAppControl` — Smart App Control (Windows 11 22H2+). `PARTIAL` correspond au mode évaluation, qui n’est pas une protection : Windows observe l’usage avant de décider. *(depuis le schéma 1.17.0)*
- `security.linux` — Contrôles propres à Linux : SSH, AppArmor/SELinux, LUKS, prévention d’intrusion, durcissement noyau. *(depuis le schéma 1.0.0)*
- `security.linux.intrusionPrevention` — fail2ban ou CrowdSec : présence, exécution, prisons actives. *(depuis le schéma 1.6.0)*
- `security.obsoleteProtocols` — Protocoles dépassés encore actifs — chacun est une porte ouverte connue. *(depuis le schéma 1.0.0)*

### `virtualization`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `virtualization.runningUnder` | chaîne [1 à 256] | — | facultatif | oui | — | Linux, Windows | Linux : `systemd-detect-virt, docker, podman, virsh, pvesh` · Windows : `Win32_ComputerSystem, Get-VM, docker` | Public | `Scan.virtualization` |
| `virtualization.docker.version` | chaîne [1 à 256] | — | obligatoire si présent | oui | `27.3.1` | Linux, Windows | Linux : `docker inspect` · Windows : `docker inspect` | Public | `raw` uniquement |
| `virtualization.docker.containers[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `homeassistant` | Linux, Windows | Linux : `docker inspect` · Windows : `docker inspect` | Public | `raw` uniquement |
| `virtualization.docker.containers[].image` | chaîne [1 à 256] | — | obligatoire si présent | oui | `ghcr.io/home-assistant/home-assistant:stable` | Linux, Windows | Linux : `docker inspect` · Windows : `docker inspect` | Public | `raw` uniquement |
| `virtualization.docker.containers[].state` | chaîne [1 à 256] | — | obligatoire si présent | oui | `running` | Linux, Windows | Linux : `docker inspect` · Windows : `docker inspect` | Public | `raw` uniquement |
| `virtualization.docker.containers[].privileged` | booléen | — | obligatoire si présent | oui | `true` | Linux, Windows | Linux : `docker inspect` · Windows : `docker inspect` | Public | `raw` uniquement |
| `virtualization.docker.containers[].networkMode` | chaîne [1 à 256] | — | obligatoire si présent | oui | `host` | Linux, Windows | Linux : `docker inspect` · Windows : `docker inspect` | Public | `raw` uniquement |
| `virtualization.docker.containers[].publishedPorts[].hostPort` | entier [0 à 65535] | — | obligatoire si présent | non | — | Linux, Windows | Linux : `docker inspect` · Windows : `docker inspect` | Public | `raw` uniquement |
| `virtualization.docker.containers[].publishedPorts[].containerPort` | entier [0 à 65535] | — | obligatoire si présent | non | — | Linux, Windows | Linux : `docker inspect` · Windows : `docker inspect` | Public | `raw` uniquement |
| `virtualization.docker.containers[].publishedPorts[].protocol` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `docker inspect` · Windows : `docker inspect` | Public | `raw` uniquement |
| `virtualization.docker.containers[].publishedPorts[].hostAddress` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `docker inspect` · Windows : `docker inspect` | Public | `raw` uniquement |
| `virtualization.docker.containers[].sensitiveMounts[]` | chaîne [1 à 256] | — | obligatoire si présent | non | `/run/dbus` | Linux, Windows | Linux : `docker inspect` · Windows : `docker inspect` | Public | `raw` uniquement |
| `virtualization.docker.containers[].dockerSocketMounted` | booléen | — | obligatoire si présent | oui | `false` | Linux, Windows | Linux : `docker inspect` · Windows : `docker inspect` | Public | `raw` uniquement |
| `virtualization.docker.networks[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `bridge` | Linux, Windows | Linux : `docker inspect` · Windows : `docker inspect` | Public | `raw` uniquement |
| `virtualization.docker.networks[].driver` | chaîne [1 à 256] | — | obligatoire si présent | oui | `bridge` | Linux, Windows | Linux : `docker inspect` · Windows : `docker inspect` | Public | `raw` uniquement |
| `virtualization.docker.volumeCount` | entier [≥ 0] | — | facultatif | oui | `4` | Linux, Windows | Linux : `docker inspect` · Windows : `docker inspect` | Public | `raw` uniquement |
| `virtualization.podman.version` | chaîne [1 à 256] | — | obligatoire si présent | oui | `4.9.3` | Linux | Linux : `podman inspect` | Public | `raw` uniquement |
| `virtualization.podman.containers[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `registre` | Linux | Linux : `podman inspect` | Public | `raw` uniquement |
| `virtualization.podman.containers[].image` | chaîne [1 à 256] | — | obligatoire si présent | oui | `docker.io/library/registry:2` | Linux | Linux : `podman inspect` | Public | `raw` uniquement |
| `virtualization.podman.containers[].state` | chaîne [1 à 256] | — | obligatoire si présent | oui | `running` | Linux | Linux : `podman inspect` | Public | `raw` uniquement |
| `virtualization.podman.containers[].privileged` | booléen | — | obligatoire si présent | oui | — | Linux | Linux : `podman inspect` | Public | `raw` uniquement |
| `virtualization.podman.containers[].networkMode` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `podman inspect` | Public | `raw` uniquement |
| `virtualization.podman.containers[].publishedPorts[].hostPort` | entier [0 à 65535] | — | obligatoire si présent | non | — | Linux | Linux : `podman inspect` | Public | `raw` uniquement |
| `virtualization.podman.containers[].publishedPorts[].containerPort` | entier [0 à 65535] | — | obligatoire si présent | non | — | Linux | Linux : `podman inspect` | Public | `raw` uniquement |
| `virtualization.podman.containers[].publishedPorts[].protocol` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `podman inspect` | Public | `raw` uniquement |
| `virtualization.podman.containers[].publishedPorts[].hostAddress` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `podman inspect` | Public | `raw` uniquement |
| `virtualization.podman.containers[].sensitiveMounts[]` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Linux | Linux : `podman inspect` | Public | `raw` uniquement |
| `virtualization.podman.containers[].dockerSocketMounted` | booléen | — | obligatoire si présent | oui | — | Linux | Linux : `podman inspect` | Public | `raw` uniquement |
| `virtualization.podman.networks[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Linux | Linux : `podman inspect` | Public | `raw` uniquement |
| `virtualization.podman.networks[].driver` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `podman inspect` | Public | `raw` uniquement |
| `virtualization.podman.volumeCount` | entier [≥ 0] | — | facultatif | oui | — | Linux | Linux : `podman inspect` | Public | `raw` uniquement |
| `virtualization.libvirt.version` | chaîne [1 à 256] | — | obligatoire si présent | oui | `10.0.0` | Linux | Linux : `virsh list, virsh dominfo` | Public | `raw` uniquement |
| `virtualization.libvirt.guests[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `vm-test` | Linux | Linux : `virsh list, virsh dominfo` | Public | `raw` uniquement |
| `virtualization.libvirt.guests[].state` | chaîne [1 à 256] | — | obligatoire si présent | oui | `running` | Linux | Linux : `virsh list, virsh dominfo` | Public | `raw` uniquement |
| `virtualization.libvirt.guests[].vcpus` | entier [≥ 0] | — | obligatoire si présent | oui | `2` | Linux | Linux : `virsh list, virsh dominfo` | Public | `raw` uniquement |
| `virtualization.libvirt.guests[].memoryBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `4294967296` | Linux | Linux : `virsh list, virsh dominfo` | Public | `raw` uniquement |
| `virtualization.libvirt.guests[].autostart` | booléen | — | obligatoire si présent | oui | `true` | Linux | Linux : `virsh list, virsh dominfo` | Public | `raw` uniquement |
| `virtualization.hyperv.version` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Windows | Windows : `Get-VM` | Public | `raw` uniquement |
| `virtualization.hyperv.guests[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Windows | Windows : `Get-VM` | Public | `raw` uniquement |
| `virtualization.hyperv.guests[].state` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Windows | Windows : `Get-VM` | Public | `raw` uniquement |
| `virtualization.hyperv.guests[].vcpus` | entier [≥ 0] | — | obligatoire si présent | oui | — | Windows | Windows : `Get-VM` | Public | `raw` uniquement |
| `virtualization.hyperv.guests[].memoryBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | — | Windows | Windows : `Get-VM` | Public | `raw` uniquement |
| `virtualization.hyperv.guests[].autostart` | booléen | — | obligatoire si présent | oui | — | Windows | Windows : `Get-VM` | Public | `raw` uniquement |
| `virtualization.proxmox.version` | chaîne [1 à 256] | — | obligatoire si présent | oui | `pve-manager/8.3.2/1d1c4e1e` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.node.name` | chaîne [1 à 256] | — | obligatoire si présent | oui | `pve-lab` | Linux | Linux : `pvesh get /nodes` | Réservé au demandeur | `raw` uniquement |
| `virtualization.proxmox.node.kernel` | chaîne [1 à 256] | — | obligatoire si présent | oui | `6.8.12-4-pve` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.node.uptimeSeconds` | entier [≥ 0] | s | obligatoire si présent | oui | `1209600` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.node.cpuCores` | entier [≥ 0] | — | obligatoire si présent | oui | `16` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.node.memoryTotalBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `34359738368` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.node.memoryUsedBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `21474836480` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.cluster.mode` | STANDALONE \| CLUSTER \| UNKNOWN | — | obligatoire si présent | non | `STANDALONE` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.cluster.name` | chaîne [1 à 256] | — | facultatif | oui | — | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.cluster.nodeCount` | entier [≥ 0] | — | facultatif | oui | `1` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.cluster.quorate` | booléen | — | facultatif | oui | — | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.vms[].vmid` | entier [≥ 0] | — | obligatoire si présent | non | `100` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.vms[].name` | chaîne [1 à 256] | — | obligatoire si présent | oui | `win11-test` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.vms[].status` | chaîne [1 à 256] | — | obligatoire si présent | oui | `stopped` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.vms[].cpuCores` | entier [≥ 0] | — | obligatoire si présent | oui | `4` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.vms[].memoryBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `8589934592` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.vms[].autostart` | booléen | — | obligatoire si présent | oui | `false` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.vms[].tags[]` | chaîne [1 à 256] | — | obligatoire si présent | non | `lab` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.vms[].networkInterfaces[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `net0` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.vms[].networkInterfaces[].bridge` | chaîne [1 à 256] | — | obligatoire si présent | oui | `vmbr0` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.vms[].networkInterfaces[].model` | chaîne [1 à 256] | — | obligatoire si présent | oui | `virtio` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.vms[].disks[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `scsi0` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.vms[].disks[].storage` | chaîne [1 à 256] | — | obligatoire si présent | oui | `local-lvm` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.vms[].disks[].sizeBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `68719476736` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.vms[].machineType` | chaîne [1 à 256] | — | obligatoire si présent | oui | `q35` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.vms[].bios` | chaîne [1 à 256] | — | obligatoire si présent | oui | `ovmf` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.containers[].ctid` | entier [≥ 0] | — | obligatoire si présent | non | `200` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.containers[].name` | chaîne [1 à 256] | — | obligatoire si présent | oui | `nginx-proxy` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.containers[].status` | chaîne [1 à 256] | — | obligatoire si présent | oui | `running` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.containers[].cpuCores` | entier [≥ 0] | — | obligatoire si présent | oui | `2` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.containers[].memoryBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `1073741824` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.containers[].autostart` | booléen | — | obligatoire si présent | oui | `true` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.containers[].tags[]` | chaîne [1 à 256] | — | obligatoire si présent | non | `prod` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.containers[].networkInterfaces[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `eth0` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.containers[].networkInterfaces[].bridge` | chaîne [1 à 256] | — | obligatoire si présent | oui | `vmbr0` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.containers[].networkInterfaces[].model` | chaîne [1 à 256] | — | obligatoire si présent | oui | `veth` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.containers[].rootfsBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `8589934592` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.containers[].storage` | chaîne [1 à 256] | — | obligatoire si présent | oui | `local-lvm` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.containers[].unprivileged` | booléen | — | obligatoire si présent | oui | `true` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.storages[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `local-lvm` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.storages[].type` | chaîne [1 à 256] | — | obligatoire si présent | non | `lvmthin` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.storages[].status` | chaîne [1 à 256] | — | obligatoire si présent | oui | `active` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.storages[].totalBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `800000000000` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.storages[].usedBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `412000000000` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.storages[].availableBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `388000000000` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.storages[].usagePercent` | nombre [0 à 100] | % | obligatoire si présent | oui | `51.5` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.storages[].shared` | booléen | — | obligatoire si présent | oui | `false` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.storages[].content[]` | chaîne [1 à 256] | — | obligatoire si présent | non | `images` | Linux | Linux : `pvesh, pvesm, qm, pct` | Public | `raw` uniquement |
| `virtualization.proxmox.failedServices[]` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Linux | Linux : `systemctl is-active` | Public | `raw` uniquement |
| `virtualization.proxmox.failedTasks[].type` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Linux | Linux : `pvesh get /nodes/<nœud>/tasks` | Public | `raw` uniquement |
| `virtualization.proxmox.failedTasks[].target` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `pvesh get /nodes/<nœud>/tasks` | Public | `raw` uniquement |
| `virtualization.proxmox.failedTasks[].startedAt` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | — | Linux | Linux : `pvesh get /nodes/<nœud>/tasks` | Public | `raw` uniquement |
| `virtualization.proxmox.failedTasks[].status` | chaîne [1 à 1024] | — | obligatoire si présent | oui | — | Linux | Linux : `pvesh get /nodes/<nœud>/tasks` | Public | `raw` uniquement |
| `virtualization.proxmox.failedTasks[].durationMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | — | Linux | Linux : `pvesh get /nodes/<nœud>/tasks` | Public | `raw` uniquement |
| `virtualization.proxmox.lastBackup.type` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Linux | Linux : `pvesh get /nodes/<nœud>/tasks --typefilter vzdump` | Public | `raw` uniquement |
| `virtualization.proxmox.lastBackup.target` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `pvesh get /nodes/<nœud>/tasks --typefilter vzdump` | Public | `raw` uniquement |
| `virtualization.proxmox.lastBackup.startedAt` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | — | Linux | Linux : `pvesh get /nodes/<nœud>/tasks --typefilter vzdump` | Public | `raw` uniquement |
| `virtualization.proxmox.lastBackup.status` | chaîne [1 à 1024] | — | obligatoire si présent | oui | — | Linux | Linux : `pvesh get /nodes/<nœud>/tasks --typefilter vzdump` | Public | `raw` uniquement |
| `virtualization.proxmox.lastBackup.durationMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | — | Linux | Linux : `pvesh get /nodes/<nœud>/tasks --typefilter vzdump` | Public | `raw` uniquement |
| `virtualization.proxmox.taskWindowMs` | entier [0 à 31536000000] | ms | facultatif | oui | — | Linux | Linux : `pvesh get /nodes/<nœud>/tasks` | Public | `raw` uniquement |
| `virtualization.proxmox.ceph.present` | booléen | — | obligatoire si présent | non | — | Linux | Linux : `ceph health, /etc/pve/ceph.conf` | Public | `raw` uniquement |
| `virtualization.proxmox.ceph.health` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `ceph health, /etc/pve/ceph.conf` | Public | `raw` uniquement |
| `virtualization.proxmox.ceph.detail` | chaîne [1 à 1024] | — | obligatoire si présent | oui | — | Linux | Linux : `ceph health, /etc/pve/ceph.conf` | Public | `raw` uniquement |
| `virtualization.proxmox.ceph.degraded` | entier [≥ 0] | — | obligatoire si présent | oui | — | Linux | Linux : `ceph health, /etc/pve/ceph.conf` | Public | `raw` uniquement |
| `virtualization.proxmox.replication.present` | booléen | — | obligatoire si présent | non | — | Linux | Linux : `pvesr status, /etc/pve/replication.cfg` | Public | `raw` uniquement |
| `virtualization.proxmox.replication.health` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `pvesr status, /etc/pve/replication.cfg` | Public | `raw` uniquement |
| `virtualization.proxmox.replication.detail` | chaîne [1 à 1024] | — | obligatoire si présent | oui | — | Linux | Linux : `pvesr status, /etc/pve/replication.cfg` | Public | `raw` uniquement |
| `virtualization.proxmox.replication.degraded` | entier [≥ 0] | — | obligatoire si présent | oui | — | Linux | Linux : `pvesr status, /etc/pve/replication.cfg` | Public | `raw` uniquement |
| `virtualization.proxmox.highAvailability.present` | booléen | — | obligatoire si présent | non | — | Linux | Linux : `ha-manager status, /etc/pve/ha/resources.cfg` | Public | `raw` uniquement |
| `virtualization.proxmox.highAvailability.health` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `ha-manager status, /etc/pve/ha/resources.cfg` | Public | `raw` uniquement |
| `virtualization.proxmox.highAvailability.detail` | chaîne [1 à 1024] | — | obligatoire si présent | oui | — | Linux | Linux : `ha-manager status, /etc/pve/ha/resources.cfg` | Public | `raw` uniquement |
| `virtualization.proxmox.highAvailability.degraded` | entier [≥ 0] | — | obligatoire si présent | oui | — | Linux | Linux : `ha-manager status, /etc/pve/ha/resources.cfg` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `virtualization` — Ce que la machine héberge et ce qui l’héberge : hyperviseur détecté, conteneurs, invités. *(depuis le schéma 1.0.0)*
- `virtualization.docker` — Conteneurs Docker : image, état, réseau, ports publiés, montages sensibles et accès au socket. *(depuis le schéma 1.0.0)*
- `virtualization.podman` — Conteneurs Podman, décrits exactement comme les conteneurs Docker. *(depuis le schéma 1.6.0)*
- `virtualization.libvirt` — Machines virtuelles libvirt : état, vCPU, mémoire, démarrage automatique. *(depuis le schéma 1.6.0)*
- `virtualization.hyperv` — Machines virtuelles Hyper-V hébergées par cette machine : état, vCPU, mémoire, démarrage automatique. À ne pas confondre avec l’hyperviseur qui héberge la machine elle-même. *(depuis le schéma 1.14.0)*
- `virtualization.proxmox` — Nœud Proxmox : grappe, machines virtuelles, conteneurs LXC et stockages. *(depuis le schéma 1.0.0)*
- `virtualization.proxmox.node.name` — Nom du nœud Proxmox — c’est le nom de la machine, sous un autre chemin. *(depuis le schéma 1.0.0)*
- `virtualization.proxmox.failedServices` — Services propres à Proxmox en échec. Nommés à part des unités systemd générales : un pvestatd arrêté rend toute l’interface aveugle sans qu’aucun invité ne s’arrête. *(depuis le schéma 1.16.0)*
- `virtualization.proxmox.failedTasks` — Tâches Proxmox terminées en erreur sur les sept derniers jours, statut natif conservé. Une sauvegarde qui échoue toutes les nuits est un fait qu’aucun inventaire ne montre : l’hôte va bien, les invités tournent, et il n’y a plus de sauvegarde exploitable. *(depuis le schéma 1.16.0)*
- `virtualization.proxmox.lastBackup` — Dernière sauvegarde vzdump observée, réussie ou non. Sa réussite est un fait, sa date en est un autre : une sauvegarde réussie il y a six semaines n’est pas une sauvegarde. *(depuis le schéma 1.16.0)*
- `virtualization.proxmox.taskWindowMs` — Fenêtre couverte par la lecture des tâches — indissociable de leur compte : « trois échecs » ne veut rien dire sans la durée sur laquelle ils sont survenus. *(depuis le schéma 1.16.0)*
- `virtualization.proxmox.ceph` — Santé Ceph, quand le nœud en a un. `present: false` ne vaut pas « dégradé » : une grappe sans Ceph n’a pas de Ceph en panne. *(depuis le schéma 1.16.0)*
- `virtualization.proxmox.replication` — Réplication ZFS entre nœuds, quand elle est configurée. Absente sur un nœud isolé, ce qui est « sans objet » et non « en panne ». *(depuis le schéma 1.16.0)*
- `virtualization.proxmox.highAvailability` — Haute disponibilité, quand des ressources y sont déclarées. `ha-manager` existe sur tout nœud PVE : c’est la configuration qui dit si la HA est en service. *(depuis le schéma 1.16.0)*

### `stability`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `stability.uptimeSeconds` | entier [≥ 0] | s | obligatoire si présent | oui | `3600` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.bootedAt` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | `2026-07-25T15:42:00Z` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.reboots.count` | entier [≥ 0] | — | obligatoire si présent | oui | `4` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.reboots.observationWindowMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | `2592000000` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.reboots.lastAt` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | `2026-07-25T15:42:00Z` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.reboots.source` | chaîne [1 à 256] | — | obligatoire si présent | oui | `last reboot` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.unexpectedShutdowns.count` | entier [≥ 0] | — | obligatoire si présent | oui | `1` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.unexpectedShutdowns.observationWindowMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | `2592000000` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.unexpectedShutdowns.lastAt` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | `2026-07-12T03:17:44Z` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.unexpectedShutdowns.source` | chaîne [1 à 256] | — | obligatoire si présent | oui | `journalctl --list-boots` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.kernelCrashes.count` | entier [≥ 0] | — | obligatoire si présent | oui | `0` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.kernelCrashes.observationWindowMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | `2592000000` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.kernelCrashes.lastAt` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | — | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.kernelCrashes.source` | chaîne [1 à 256] | — | obligatoire si présent | oui | `journalctl -k -p emerg` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.hardwareErrors.count` | entier [≥ 0] | — | obligatoire si présent | oui | — | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.hardwareErrors.observationWindowMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | — | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.hardwareErrors.lastAt` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | — | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.hardwareErrors.source` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.storageErrors.count` | entier [≥ 0] | — | obligatoire si présent | oui | `47` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.storageErrors.observationWindowMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | `1814400000` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.storageErrors.lastAt` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | `2026-07-25T04:12:09Z` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.storageErrors.source` | chaîne [1 à 256] | — | obligatoire si présent | oui | `journalctl -k -p err` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.filesystemErrors.count` | entier [≥ 0] | — | obligatoire si présent | oui | `0` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.filesystemErrors.observationWindowMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | `1814400000` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.filesystemErrors.lastAt` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | — | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.filesystemErrors.source` | chaîne [1 à 256] | — | obligatoire si présent | oui | `journalctl -k -p err` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.memoryPressureEvents.count` | entier [≥ 0] | — | obligatoire si présent | oui | `0` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.memoryPressureEvents.observationWindowMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | `1814400000` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.memoryPressureEvents.lastAt` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | — | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.memoryPressureEvents.source` | chaîne [1 à 256] | — | obligatoire si présent | oui | `journalctl -k` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.networkErrors.count` | entier [≥ 0] | — | obligatoire si présent | oui | `3` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.networkErrors.observationWindowMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | `1814400000` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.networkErrors.lastAt` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | `2026-07-20T11:02:41Z` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.networkErrors.source` | chaîne [1 à 256] | — | obligatoire si présent | oui | `journalctl -k -p warning` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.driverErrors.count` | entier [≥ 0] | — | obligatoire si présent | oui | `0` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.driverErrors.observationWindowMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | `1814400000` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.driverErrors.lastAt` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | — | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.driverErrors.source` | chaîne [1 à 256] | — | obligatoire si présent | oui | `journalctl -k -p err` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.serviceFailures.count` | entier [≥ 0] | — | obligatoire si présent | oui | `2` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.serviceFailures.observationWindowMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | `2592000000` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.serviceFailures.lastAt` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | `2026-07-24T22:05:00Z` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.serviceFailures.source` | chaîne [1 à 256] | — | obligatoire si présent | oui | `journalctl -u` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.applicationCrashes.count` | entier [≥ 0] | — | obligatoire si présent | oui | `2` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.applicationCrashes.observationWindowMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | `2592000000` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.applicationCrashes.lastAt` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | `2026-07-23T19:44:12Z` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.applicationCrashes.source` | chaîne [1 à 256] | — | obligatoire si présent | oui | `coredumpctl list` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.thermalEvents.count` | entier [≥ 0] | — | obligatoire si présent | oui | `0` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.thermalEvents.observationWindowMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | `1814400000` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.thermalEvents.lastAt` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | — | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.thermalEvents.source` | chaîne [1 à 256] | — | obligatoire si présent | oui | `journalctl -k` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.failedUpdates.count` | entier [≥ 0] | — | obligatoire si présent | oui | `0` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.failedUpdates.observationWindowMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | `2592000000` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.failedUpdates.lastAt` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | — | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.failedUpdates.source` | chaîne [1 à 256] | — | obligatoire si présent | oui | `journalctl -u apt-daily` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.failedUnits[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `backup-nightly.service` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.failedUnits[].state` | chaîne [1 à 256] | — | obligatoire si présent | oui | `failed` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.failedUnits[].result` | chaîne [1 à 256] | — | obligatoire si présent | oui | `exit-code` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.failedUnits[].since` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | `2026-07-24T22:05:00Z` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.failedUnits[].restarts` | entier [≥ 0] | — | obligatoire si présent | oui | `3` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.failedUnits[].startup` | chaîne [1 à 256] | — | facultatif | oui | — | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.failedUnits[].reason` | chaîne [1 à 256] | — | facultatif | oui | — | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.failedUnits[].source` | chaîne [1 à 256] | — | facultatif | oui | — | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.stoppedUnits[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.stoppedUnits[].state` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.stoppedUnits[].result` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.stoppedUnits[].since` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | — | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.stoppedUnits[].restarts` | entier [≥ 0] | — | obligatoire si présent | oui | — | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.stoppedUnits[].startup` | chaîne [1 à 256] | — | facultatif | oui | — | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.stoppedUnits[].reason` | chaîne [1 à 256] | — | facultatif | oui | — | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.stoppedUnits[].source` | chaîne [1 à 256] | — | facultatif | oui | — | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.coredumps[].executable` | chaîne [1 à 256] | — | obligatoire si présent | oui | `firefox` | Linux | Linux : `coredumpctl list` | Anonymisable à la collecte | `raw` uniquement |
| `stability.coredumps[].signal` | chaîne [1 à 256] | — | obligatoire si présent | oui | `SIGSEGV` | Linux | Linux : `coredumpctl list` | Anonymisable à la collecte | `raw` uniquement |
| `stability.coredumps[].at` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | `2026-07-23T19:44:12Z` | Linux | Linux : `coredumpctl list` | Anonymisable à la collecte | `raw` uniquement |
| `stability.coredumps[].count` | entier [≥ 0] | — | obligatoire si présent | non | `2` | Linux | Linux : `coredumpctl list` | Anonymisable à la collecte | `raw` uniquement |
| `stability.coredumps[].present` | booléen | — | obligatoire si présent | oui | `false` | Linux | Linux : `coredumpctl list` | Anonymisable à la collecte | `raw` uniquement |
| `stability.kernelTainted` | entier [≥ 0] | — | obligatoire si présent | oui | `512` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.meta.source` | chaîne [1 à 256] | — | facultatif | non | `journalctl` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.meta.method` | chaîne [1 à 256] | — | facultatif | non | `commande shell` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.meta.collectedAt` | date-heure ISO 8601 (UTC) | — | facultatif | non | `2026-07-25T16:42:00Z` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |
| `stability.meta.observationWindowMs` | entier [0 à 31536000000] | ms | facultatif | non | `2592000000` | Linux | Linux : `journalctl, systemctl, coredumpctl, /proc` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `stability` — Ce que la machine a vécu : redémarrages, arrêts inattendus, paniques noyau, erreurs matérielles, de stockage, de réseau et de pilotes, services en échec et vidanges mémoire. Chaque compteur porte la fenêtre qu’il couvre — sans elle, un nombre ne veut rien dire. *(depuis le schéma 1.15.0)*
- `stability.coredumps` — Vidanges mémoire recensées : exécutable, signal et date. Jamais le contenu de la vidange, qui expose la mémoire du processus. *(depuis le schéma 1.15.0)*

### `boot`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `boot.phases[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `firmware` | Linux | Linux : `systemd-analyze, journalctl --list-boots` | Public | `raw` uniquement |
| `boot.phases[].durationMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | `4820000` | Linux | Linux : `systemd-analyze, journalctl --list-boots` | Public | `raw` uniquement |
| `boot.totalMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | `4846220` | Linux | Linux : `systemd-analyze, journalctl --list-boots` | Public | `raw` uniquement |
| `boot.measuredAt` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | `2026-07-25T16:42:00Z` | Linux | Linux : `systemd-analyze, journalctl --list-boots` | Public | `raw` uniquement |
| `boot.slowestItems[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `NetworkManager-wait-online.service` | Linux | Linux : `systemd-analyze, journalctl --list-boots` | Public | `raw` uniquement |
| `boot.slowestItems[].durationMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | `12100` | Linux | Linux : `systemd-analyze, journalctl --list-boots` | Public | `raw` uniquement |
| `boot.slowestItems[].kind` | chaîne [1 à 256] | — | obligatoire si présent | oui | `unit` | Linux | Linux : `systemd-analyze, journalctl --list-boots` | Public | `raw` uniquement |
| `boot.failedAtBoot[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `backup-nightly.service` | Linux | Linux : `systemd-analyze, journalctl --list-boots` | Public | `raw` uniquement |
| `boot.failedAtBoot[].state` | chaîne [1 à 256] | — | obligatoire si présent | oui | `failed` | Linux | Linux : `systemd-analyze, journalctl --list-boots` | Public | `raw` uniquement |
| `boot.failedAtBoot[].result` | chaîne [1 à 256] | — | obligatoire si présent | oui | `exit-code` | Linux | Linux : `systemd-analyze, journalctl --list-boots` | Public | `raw` uniquement |
| `boot.failedAtBoot[].since` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | `2026-07-25T15:42:31Z` | Linux | Linux : `systemd-analyze, journalctl --list-boots` | Public | `raw` uniquement |
| `boot.failedAtBoot[].restarts` | entier [≥ 0] | — | obligatoire si présent | oui | — | Linux | Linux : `systemd-analyze, journalctl --list-boots` | Public | `raw` uniquement |
| `boot.failedAtBoot[].startup` | chaîne [1 à 256] | — | facultatif | oui | — | Linux | Linux : `systemd-analyze, journalctl --list-boots` | Public | `raw` uniquement |
| `boot.failedAtBoot[].reason` | chaîne [1 à 256] | — | facultatif | oui | — | Linux | Linux : `systemd-analyze, journalctl --list-boots` | Public | `raw` uniquement |
| `boot.failedAtBoot[].source` | chaîne [1 à 256] | — | facultatif | oui | — | Linux | Linux : `systemd-analyze, journalctl --list-boots` | Public | `raw` uniquement |
| `boot.firmwareMode` | UEFI \| LEGACY_BIOS \| UNKNOWN | — | obligatoire si présent | oui | `UEFI` | Linux | Linux : `systemd-analyze, journalctl --list-boots` | Public | `raw` uniquement |
| `boot.fastStartupEnabled` | booléen | — | obligatoire si présent | oui | `false` | Linux | Linux : `systemd-analyze, journalctl --list-boots` | Public | `raw` uniquement |
| `boot.history[].at` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | non | `2026-07-25T15:42:00Z` | Linux | Linux : `systemd-analyze, journalctl --list-boots` | Public | `raw` uniquement |
| `boot.history[].totalMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | `4846220` | Linux | Linux : `systemd-analyze, journalctl --list-boots` | Public | `raw` uniquement |
| `boot.kernels.running` | chaîne [1 à 256] | — | obligatoire si présent | oui | `6.8.12-4-pve` | Linux | Linux : `dpkg-query, rpm, pacman, /lib/modules` | Public | `raw` uniquement |
| `boot.kernels.installed[]` | chaîne [1 à 256] | — | obligatoire si présent | non | `6.8.12-4-pve` | Linux | Linux : `dpkg-query, rpm, pacman, /lib/modules` | Public | `raw` uniquement |
| `boot.kernels.newestInstalled` | chaîne [1 à 256] | — | obligatoire si présent | oui | `6.8.12-4-pve` | Linux | Linux : `dpkg-query, rpm, pacman, /lib/modules` | Public | `raw` uniquement |
| `boot.kernels.source` | chaîne [1 à 256] | — | obligatoire si présent | oui | `dpkg-query` | Linux | Linux : `dpkg-query, rpm, pacman, /lib/modules` | Public | `raw` uniquement |
| `boot.meta.source` | chaîne [1 à 256] | — | facultatif | non | `systemd-analyze` | Linux | Linux : `systemd-analyze, journalctl --list-boots` | Public | `raw` uniquement |
| `boot.meta.method` | chaîne [1 à 256] | — | facultatif | non | `commande shell` | Linux | Linux : `systemd-analyze, journalctl --list-boots` | Public | `raw` uniquement |
| `boot.meta.collectedAt` | date-heure ISO 8601 (UTC) | — | facultatif | non | `2026-07-25T16:42:00Z` | Linux | Linux : `systemd-analyze, journalctl --list-boots` | Public | `raw` uniquement |
| `boot.meta.observationWindowMs` | entier [0 à 31536000000] | ms | facultatif | non | — | Linux | Linux : `systemd-analyze, journalctl --list-boots` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `boot` — Séquence de démarrage : durée par phase native, éléments les plus lents, unités en échec au démarrage, mode du micrologiciel et historique des démarrages précédents. *(depuis le schéma 1.15.0)*
- `boot.kernels` — Noyaux installés et celui qui tourne. Une machine peut tourner depuis des semaines sur un noyau plus ancien que le plus récent installé — un correctif appliqué mais pas encore chargé. Le scanner compare sans conclure. *(depuis le schéma 1.16.0)*

### `shutdown`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `shutdown.lastShutdownAt` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | `2026-07-25T15:41:12Z` | Linux | Linux : `journalctl --list-boots` | Public | `raw` uniquement |
| `shutdown.lastShutdownWasClean` | booléen | — | obligatoire si présent | oui | `true` | Linux | Linux : `journalctl --list-boots` | Public | `raw` uniquement |
| `shutdown.lastShutdownReason` | chaîne [1 à 1024] | — | obligatoire si présent | oui | `systemd-shutdown: powering off` | Linux | Linux : `journalctl --list-boots` | Public | `raw` uniquement |
| `shutdown.lastShutdownDurationMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | `9400` | Linux | Linux : `journalctl --list-boots` | Public | `raw` uniquement |
| `shutdown.slowestItems[].name` | chaîne [1 à 256] | — | obligatoire si présent | non | `docker.service` | Linux | Linux : `journalctl --list-boots` | Public | `raw` uniquement |
| `shutdown.slowestItems[].durationMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | `6200` | Linux | Linux : `journalctl --list-boots` | Public | `raw` uniquement |
| `shutdown.slowestItems[].kind` | chaîne [1 à 256] | — | obligatoire si présent | oui | `unit` | Linux | Linux : `journalctl --list-boots` | Public | `raw` uniquement |
| `shutdown.meta.source` | chaîne [1 à 256] | — | facultatif | non | `journalctl --list-boots` | Linux | Linux : `journalctl --list-boots` | Public | `raw` uniquement |
| `shutdown.meta.method` | chaîne [1 à 256] | — | facultatif | non | `commande shell` | Linux | Linux : `journalctl --list-boots` | Public | `raw` uniquement |
| `shutdown.meta.collectedAt` | date-heure ISO 8601 (UTC) | — | facultatif | non | `2026-07-25T16:42:00Z` | Linux | Linux : `journalctl --list-boots` | Public | `raw` uniquement |
| `shutdown.meta.observationWindowMs` | entier [0 à 31536000000] | ms | facultatif | non | — | Linux | Linux : `journalctl --list-boots` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `shutdown` — Dernier arrêt : date, propreté, motif natif, durée et unités ayant retardé l’extinction. *(depuis le schéma 1.15.0)*

### `events`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `events.window.requestedMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | `7776000000` | Linux | Linux : `journalctl, dmesg, /var/log` | Public | `raw` uniquement |
| `events.window.coveredMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | `1814400000` | Linux | Linux : `journalctl, dmesg, /var/log` | Public | `raw` uniquement |
| `events.window.since` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | `2026-07-04T16:42:00Z` | Linux | Linux : `journalctl, dmesg, /var/log` | Public | `raw` uniquement |
| `events.window.until` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | `2026-07-25T16:42:00Z` | Linux | Linux : `journalctl, dmesg, /var/log` | Public | `raw` uniquement |
| `events.window.persistent` | booléen | — | obligatoire si présent | oui | `true` | Linux | Linux : `journalctl, dmesg, /var/log` | Public | `raw` uniquement |
| `events.examined` | entier [≥ 0] | — | obligatoire si présent | oui | `18432` | Linux | Linux : `journalctl, dmesg, /var/log` | Public | `raw` uniquement |
| `events.truncated` | booléen | — | obligatoire si présent | oui | `false` | Linux | Linux : `journalctl, dmesg, /var/log` | Public | `raw` uniquement |
| `events.entries[].category` | KERNEL_CRASH \| HARDWARE \| STORAGE \| FILESYSTEM \| MEMORY \| NETWORK \| DRIVER \| SERVICE \| APPLICATION_CRASH \| SECURITY \| POWER \| THERMAL \| UPDATE \| BOOT \| VIRTUALIZATION \| OTHER | — | obligatoire si présent | non | `STORAGE` | Linux | Linux : `journalctl, dmesg, /var/log` | Public | `raw` uniquement |
| `events.entries[].severity` | CRITICAL \| ERROR \| WARNING \| INFO | — | obligatoire si présent | non | `ERROR` | Linux | Linux : `journalctl, dmesg, /var/log` | Public | `raw` uniquement |
| `events.entries[].provider` | chaîne [1 à 256] | — | obligatoire si présent | non | `kernel` | Linux | Linux : `journalctl, dmesg, /var/log` | Public | `raw` uniquement |
| `events.entries[].nativeId` | chaîne [1 à 256] | — | obligatoire si présent | oui | `ata3.00` | Linux | Linux : `journalctl, dmesg, /var/log` | Public | `raw` uniquement |
| `events.entries[].firstSeenAt` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | `2026-07-04T22:31:07Z` | Linux | Linux : `journalctl, dmesg, /var/log` | Public | `raw` uniquement |
| `events.entries[].lastSeenAt` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | oui | `2026-07-25T04:12:09Z` | Linux | Linux : `journalctl, dmesg, /var/log` | Public | `raw` uniquement |
| `events.entries[].occurrences` | entier [≥ 1] | — | obligatoire si présent | non | `47` | Linux | Linux : `journalctl, dmesg, /var/log` | Public | `raw` uniquement |
| `events.entries[].summary` | chaîne [1 à 1024] | — | obligatoire si présent | non | `ata3.00: failed command: READ FPDMA QUEUED` | Linux | Linux : `journalctl, dmesg, /var/log` | Public | `raw` uniquement |
| `events.entries[].fingerprint` | chaîne [1 à 256] | — | obligatoire si présent | non | `ata-failed-command-read-fpdma` | Linux | Linux : `journalctl, dmesg, /var/log` | Public | `raw` uniquement |
| `events.entries[].source` | chaîne [1 à 256] | — | obligatoire si présent | non | `journalctl -k -p err` | Linux | Linux : `journalctl, dmesg, /var/log` | Public | `raw` uniquement |
| `events.entries[].evidence[]` | chaîne [1 à 1024] | — | obligatoire si présent | non | `ata3.00: exception Emask 0x0 SAct 0x400000 …` | Linux | Linux : `journalctl, dmesg, /var/log` | Réservé au demandeur | `raw` uniquement |
| `events.meta.source` | chaîne [1 à 256] | — | facultatif | non | `journalctl` | Linux | Linux : `journalctl, dmesg, /var/log` | Public | `raw` uniquement |
| `events.meta.method` | chaîne [1 à 256] | — | facultatif | non | `commande shell` | Linux | Linux : `journalctl, dmesg, /var/log` | Public | `raw` uniquement |
| `events.meta.collectedAt` | date-heure ISO 8601 (UTC) | — | facultatif | non | `2026-07-25T16:42:00Z` | Linux | Linux : `journalctl, dmesg, /var/log` | Public | `raw` uniquement |
| `events.meta.observationWindowMs` | entier [0 à 31536000000] | ms | facultatif | non | `1814400000` | Linux | Linux : `journalctl, dmesg, /var/log` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `events` — Incidents des journaux natifs, normalisés et regroupés par empreinte, avec leur identifiant d’origine et la fenêtre réellement couverte — distincte de la fenêtre demandée. *(depuis le schéma 1.15.0)*
- `events.entries[].evidence` — Au plus trois extraits bruts du journal, tronqués et anonymisés : une alerte sans la ligne qui la fonde n’est pas vérifiable. *(depuis le schéma 1.15.0)*

### `monitoring`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `monitoring.startedAt` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | non | `2026-07-25T16:41:00Z` | Linux, Windows | Linux : `lib/collectors/monitoring.sh` · Windows : `lib/collectors/monitoring.ps1` | Public | `raw` uniquement |
| `monitoring.intervalMs` | entier [≥ 0] | ms | obligatoire si présent | non | `1000` | Linux, Windows | Linux : `lib/collectors/monitoring.sh` · Windows : `lib/collectors/monitoring.ps1` | Public | `raw` uniquement |
| `monitoring.durationMs` | entier [≥ 0] | ms | obligatoire si présent | oui | `3000` | Linux, Windows | Linux : `lib/collectors/monitoring.sh` · Windows : `lib/collectors/monitoring.ps1` | Public | `raw` uniquement |
| `monitoring.samples[].at` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | non | `2026-07-25T16:41:01Z` | Linux, Windows | Linux : `lib/collectors/monitoring.sh` · Windows : `lib/collectors/monitoring.ps1` | Public | `raw` uniquement |
| `monitoring.samples[].cpuUsagePercent` | nombre [0 à 100] | % | obligatoire si présent | oui | `92.4` | Linux, Windows | Linux : `lib/collectors/monitoring.sh` · Windows : `lib/collectors/monitoring.ps1` | Public | `raw` uniquement |
| `monitoring.samples[].cpuTemperatureCelsius` | nombre [-100 à 200] | °C | obligatoire si présent | oui | `78` | Linux, Windows | Linux : `lib/collectors/monitoring.sh` · Windows : `lib/collectors/monitoring.ps1` | Public | `raw` uniquement |
| `monitoring.samples[].cpuCoreVoltageVolts` | nombre [0 à 10] | — | facultatif | oui | — | Linux, Windows | Linux : `hwmon (`in*_input`)` · Windows : `LibreHardwareMonitor si présent` | Public | `raw` uniquement |
| `monitoring.samples[].cpuPackagePowerWatts` | nombre [0 à 10000] | W | facultatif | oui | — | Linux, Windows | Linux : `RAPL (`/sys/class/powercap/intel-rapl`)` · Windows : `compteurs CIM` | Public | `raw` uniquement |
| `monitoring.samples[].gpuTemperatureCelsius` | nombre [-100 à 200] | °C | facultatif | oui | — | Linux, Windows | Linux : `nvidia-smi, hwmon amdgpu` · Windows : `compteurs du pilote` | Public | `raw` uniquement |
| `monitoring.samples[].gpuHotspotCelsius` | nombre [-100 à 200] | °C | facultatif | oui | — | Linux, Windows | Linux : `hwmon amdgpu (`junction`)` · Windows : `compteurs du pilote` | Public | `raw` uniquement |
| `monitoring.samples[].gpuCoreClockMhz` | entier [0 à 100000] | MHz | facultatif | oui | — | Linux, Windows | Linux : `nvidia-smi, sysfs amdgpu` · Windows : `compteurs du pilote` | Public | `raw` uniquement |
| `monitoring.samples[].gpuMemoryClockMhz` | entier [0 à 100000] | MHz | facultatif | oui | — | Linux, Windows | Linux : `nvidia-smi, sysfs amdgpu` · Windows : `compteurs du pilote` | Public | `raw` uniquement |
| `monitoring.samples[].gpuCoreVoltageVolts` | nombre [0 à 10] | — | facultatif | oui | — | Linux, Windows | Linux : `hwmon amdgpu` · Windows : `LibreHardwareMonitor si présent` | Public | `raw` uniquement |
| `monitoring.samples[].gpuBoardPowerWatts` | nombre [0 à 10000] | W | facultatif | oui | — | Linux, Windows | Linux : `nvidia-smi, hwmon amdgpu` · Windows : `compteurs du pilote` | Public | `raw` uniquement |
| `monitoring.samples[].memoryUsedBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `12884901888` | Linux, Windows | Linux : `lib/collectors/monitoring.sh` · Windows : `lib/collectors/monitoring.ps1` | Public | `raw` uniquement |
| `monitoring.samples[].swapUsedBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `1073741824` | Linux, Windows | Linux : `lib/collectors/monitoring.sh` · Windows : `lib/collectors/monitoring.ps1` | Public | `raw` uniquement |
| `monitoring.samples[].diskReadBytesPerSecond` | entier [≥ 0] | — | obligatoire si présent | oui | `4194304` | Linux, Windows | Linux : `lib/collectors/monitoring.sh` · Windows : `lib/collectors/monitoring.ps1` | Public | `raw` uniquement |
| `monitoring.samples[].diskWriteBytesPerSecond` | entier [≥ 0] | — | obligatoire si présent | oui | `12582912` | Linux, Windows | Linux : `lib/collectors/monitoring.sh` · Windows : `lib/collectors/monitoring.ps1` | Public | `raw` uniquement |
| `monitoring.samples[].networkRxBytesPerSecond` | entier [≥ 0] | — | obligatoire si présent | oui | `131072` | Linux, Windows | Linux : `lib/collectors/monitoring.sh` · Windows : `lib/collectors/monitoring.ps1` | Public | `raw` uniquement |
| `monitoring.samples[].networkTxBytesPerSecond` | entier [≥ 0] | — | obligatoire si présent | oui | `65536` | Linux, Windows | Linux : `lib/collectors/monitoring.sh` · Windows : `lib/collectors/monitoring.ps1` | Public | `raw` uniquement |
| `monitoring.samples[].cpuFrequencyMhz` | entier [0 à 100000] | MHz | facultatif | oui | — | Linux, Windows | Linux : `lib/collectors/monitoring.sh` · Windows : `lib/collectors/monitoring.ps1` | Public | `raw` uniquement |
| `monitoring.samples[].cpuThrottled` | booléen | — | facultatif | oui | — | Linux, Windows | Linux : `lib/collectors/monitoring.sh` · Windows : `lib/collectors/monitoring.ps1` | Public | `raw` uniquement |
| `monitoring.samples[].cpuThrottleReason` | thermal \| power-limit \| current-limit \| under-voltage \| user-defined \| other | — | facultatif | oui | — | Linux, Windows | Linux : `thermal_throttle, RAPL, vcgencmd get_throttled` · Windows : `LibreHardwareMonitor si présent` | Public | `raw` uniquement |
| `monitoring.samples[].gpuUsagePercent` | nombre [0 à 100] | % | facultatif | oui | — | Linux, Windows | Linux : `nvidia-smi, sysfs amdgpu (`gpu_busy_percent`)` · Windows : `compteurs du pilote` | Public | `raw` uniquement |
| `monitoring.samples[].gpuVramUsedBytes` | entier [≥ 0] | octets | facultatif | oui | — | Linux, Windows | Linux : `nvidia-smi, sysfs amdgpu (`mem_info_vram_used`)` · Windows : `compteurs du pilote` | Public | `raw` uniquement |
| `monitoring.samples[].gpuThrottleReason` | thermal \| power-limit \| current-limit \| under-voltage \| user-defined \| other | — | facultatif | oui | — | Linux, Windows | Linux : `nvidia-smi (`clocks_throttle_reasons`)` · Windows : `compteurs du pilote` | Public | `raw` uniquement |
| `monitoring.samples[].cpuFanRpm` | entier [≥ 0] | — | facultatif | oui | — | Linux, Windows | Linux : `hwmon (`fan*_input`)` · Windows : `LibreHardwareMonitor si présent` | Public | `raw` uniquement |
| `monitoring.samples[].gpuFanRpm` | entier [≥ 0] | — | facultatif | oui | — | Linux, Windows | Linux : `hwmon amdgpu, nvidia-smi` · Windows : `LibreHardwareMonitor si présent` | Public | `raw` uniquement |
| `monitoring.samples[].chassisFanRpm` | entier [≥ 0] | — | facultatif | oui | — | Linux, Windows | Linux : `hwmon (`fan*_input`)` · Windows : `LibreHardwareMonitor si présent` | Public | `raw` uniquement |
| `monitoring.samples[].gpuAuxiliaryFanRpm[]` | entier [≥ 0] | — | obligatoire si présent | oui | — | Linux, Windows | Linux : `hwmon amdgpu, nvidia-smi` · Windows : `LibreHardwareMonitor si présent` | Public | `raw` uniquement |
| `monitoring.samples[].cpuCoreClocksMhz[]` | entier [0 à 100000] | MHz | obligatoire si présent | oui | — | Linux, Windows | Linux : `sysfs cpufreq (`scaling_cur_freq`), /proc/cpuinfo en repli` · Windows : `compteurs de performance` | Public | `raw` uniquement |
| `monitoring.samples[].cpuCoreUsagePercent[]` | nombre [0 à 100] | % | obligatoire si présent | oui | — | Linux, Windows | Linux : `/proc/stat, ligne par cœur` · Windows : `compteurs de performance` | Public | `raw` uniquement |
| `monitoring.samples[].gpuIndex` | entier [0 à 15] | — | facultatif | non | — | Linux | Linux : `nvidia-smi -i, ordre d’énumération hwmon` | Public | `raw` uniquement |
| `monitoring.samples[].framesPerSecond` | nombre [0 à 100000] | — | facultatif | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `monitoring.samples[].frameTimeMs` | nombre [0 à 60000] | ms | facultatif | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `monitoring.samples[].phase` | idle \| cpu-single \| cpu-multi \| cpu-soak \| memory-read \| memory-write \| memory-copy \| storage-sequential-write \| storage-sequential-read \| storage-random-read \| gpu \| gaming \| cpu-gpu | — | facultatif | non | — | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `monitoring.aggregates` | objet à clés libres | — | facultatif | non | — | Linux, Windows | Linux : `lib/collectors/monitoring.sh` · Windows : `lib/collectors/monitoring.ps1` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `monitoring` — Échantillons relevés pendant toute la durée de l’audit : charge processeur, température, mémoire, disque et réseau. Une série, non une moyenne. *(depuis le schéma 1.7.0)*
- `monitoring.samples[].cpuCoreVoltageVolts` — Tension d’alimentation du cœur processeur au moment du relevé. Lue avec la fréquence et la puissance, elle distingue un bridage thermique d’un bridage par limite de puissance : la fréquence chute dans les deux cas, la tension seulement dans le second. *(depuis le schéma 1.18.0)*
- `monitoring.samples[].cpuPackagePowerWatts` — Puissance consommée par le paquet processeur pendant le relevé. C’est la grandeur que le micrologiciel plafonne (PL1/PL2) ; sans elle, une fréquence basse reste inexpliquée. *(depuis le schéma 1.18.0)*
- `monitoring.samples[].gpuTemperatureCelsius` — Température du GPU au relevé, capteur principal. *(depuis le schéma 1.18.0)*
- `monitoring.samples[].gpuHotspotCelsius` — Point le plus chaud de la puce, distinct de la température de bord. L’écart entre les deux est ce qui révèle un contact pâte thermique dégradé ; publier une moyenne l’effacerait. *(depuis le schéma 1.18.0)*
- `monitoring.samples[].gpuCoreClockMhz` — Fréquence du cœur graphique à l’instant du relevé. *(depuis le schéma 1.18.0)*
- `monitoring.samples[].gpuMemoryClockMhz` — Fréquence de la mémoire graphique à l’instant du relevé. *(depuis le schéma 1.18.0)*
- `monitoring.samples[].gpuCoreVoltageVolts` — Tension du cœur graphique au relevé — même lecture croisée que côté processeur. *(depuis le schéma 1.18.0)*
- `monitoring.samples[].gpuBoardPowerWatts` — Puissance à la carte entière, mémoire et étages d’alimentation compris — non celle de la seule puce. *(depuis le schéma 1.18.0)*
- `monitoring.samples[].cpuThrottleReason` — Motif du bridage, tel que le matériel le publie — thermique, plafond de puissance, plafond de courant, sous-tension. `cpuThrottled` dit qu’il y a bridage, celui-ci dit lequel : nettoyer un ventilateur ne corrige pas un plafond de puissance, et l’inverse non plus. *(depuis le schéma 1.27.0)*
- `monitoring.samples[].gpuUsagePercent` — Occupation du processeur graphique au relevé. *(depuis le schéma 1.27.0)*
- `monitoring.samples[].gpuVramUsedBytes` — Mémoire graphique occupée au relevé. Une charge qui sature la VRAM et une charge qui sature la puce ne se corrigent pas de la même façon. *(depuis le schéma 1.27.0)*
- `monitoring.samples[].gpuThrottleReason` — Motif de limitation rapporté par le pilote graphique, jamais déduit d’une fréquence basse. *(depuis le schéma 1.27.0)*
- `monitoring.samples[].cpuFanRpm` — Vitesse du ventilateur processeur au relevé. C’est ce qui manque pour lire une montée en température : à 90 °C, une machine dont les ventilateurs sont à fond et une machine dont ils ne tournent pas ne décrivent pas la même panne. *(depuis le schéma 1.27.0)*
- `monitoring.samples[].gpuFanRpm` — Vitesse du ventilateur de la carte graphique au relevé. *(depuis le schéma 1.27.0)*
- `monitoring.samples[].chassisFanRpm` — Vitesse du ventilateur de boîtier le plus rapide au relevé. *(depuis le schéma 1.27.0)*
- `monitoring.samples[].gpuAuxiliaryFanRpm` — Les autres ventilateurs de la carte graphique, quand elle en a plusieurs. Une carte à trois ventilateurs dont un est bloqué se voit ici et nulle part ailleurs : la moyenne reste plausible et le maximum la masque. *(depuis le schéma 1.29.0)*
- `monitoring.samples[].cpuCoreClocksMhz` — Fréquence de chaque cœur au relevé, dans l’ordre des identifiants système. La moyenne répond « 3,1 GHz » ; ce tableau répond « deux cœurs à 4,9 et quatorze à 2,8 », qui ne décrit pas la même machine. Sur une architecture hybride, la moyenne ne décrit aucun cœur réel. *(depuis le schéma 1.29.0)*
- `monitoring.samples[].cpuCoreUsagePercent` — Charge de chaque cœur au relevé, même indexation que les fréquences. C’est ce qui distingue une mesure mono-cœur réussie — un cœur saturé — d’une charge qui n’a pas démarré. *(depuis le schéma 1.29.0)*
- `monitoring.samples[].gpuIndex` — Quelle carte graphique les champs `gpu*` de cet échantillon décrivent. Sans lui, la série d’une machine à deux cartes est ambiguë : rien ne dit laquelle a chauffé. *(depuis le schéma 1.29.0)*
- `monitoring.samples[].framesPerSecond` — Cadence de rendu instantanée, publiée seulement pendant une phase de rendu. Hors de celles-ci il n’y a pas d’images à compter, et zéro décrirait une machine bloquée. **Charge synthétique — ce n’est pas une cadence de jeu.** *(depuis le schéma 1.29.0)*
- `monitoring.samples[].frameTimeMs` — Temps de trame au relevé. Redondant avec la cadence, et publié quand même : c’est lui qui porte l’irrégularité qu’une moyenne par seconde efface. *(depuis le schéma 1.29.0)*
- `monitoring.samples[].phase` — Phase de charge en cours au moment du relevé. Sans elle, un pic de température au repos et un pic sous charge multi-cœur produisent le même tracé — et n’appellent pas la même conclusion. *(depuis le schéma 1.27.0)*

### `benchmark`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `benchmark.startedAt` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | non | `2026-07-25T16:40:00Z` | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.finishedAt` | date-heure ISO 8601 (UTC) | — | facultatif | non | `2026-07-25T16:41:01Z` | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.durationMs` | entier [≥ 0] | ms | obligatoire si présent | oui | `61000` | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.secondsPerTargetPlanned` | entier [≥ 0] | — | facultatif | oui | `20` | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.stoppedEarlyReason` | chaîne [1 à 256] | — | facultatif | non | — | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].target` | cpu-single \| cpu-multi \| cpu-soak \| memory-read \| memory-write \| memory-copy \| storage-sequential-write \| storage-sequential-read \| storage-random-read \| gpu \| gaming \| cpu-gpu | — | obligatoire si présent | non | `cpu-single` | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].status` | completed \| skipped \| failed | — | facultatif | non | `completed` | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].detail` | chaîne [1 à 256] | — | facultatif | non | — | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].startedAt` | date-heure ISO 8601 (UTC) | — | facultatif | non | `2026-07-25T16:40:00Z` | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].finishedAt` | date-heure ISO 8601 (UTC) | — | facultatif | non | `2026-07-25T16:40:30Z` | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].device` | chaîne [1 à 256] | — | facultatif | non | — | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].protocolVersion` | chaîne [1 à 256] | — | facultatif | oui | `1.0.0` | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].tool` | chaîne [1 à 256] | — | obligatoire si présent | non | `openssl` | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].toolVersion` | chaîne [1 à 256] | — | obligatoire si présent | oui | `3.0.13` | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].algorithm` | chaîne [1 à 256] | — | obligatoire si présent | oui | `AES-128-CBC` | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].parameters` | chaîne [1 à 256] | — | obligatoire si présent | oui | `-evp aes-128-cbc -seconds 20 -bytes 16384` | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].durationMs` | entier [≥ 0] | ms | obligatoire si présent | oui | `30400` | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].score` | nombre | — | obligatoire si présent | oui | `1738` | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].unit` | chaîne [1 à 256] | — | obligatoire si présent | oui | `MiB/s` | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].temperatureCelsius` | nombre [-100 à 200] | °C | obligatoire si présent | oui | `79` | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].temperatureBeforeCelsius` | nombre [-100 à 200] | °C | facultatif | oui | `42` | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].temperatureMaxCelsius` | nombre [-100 à 200] | °C | facultatif | oui | `84` | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].throttled` | booléen | — | obligatoire si présent | oui | `true` | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].gpu.utilizationPercent` | nombre [0 à 100] | % | obligatoire si présent | oui | — | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].gpu.coreClockMhz` | entier [≥ 0] | MHz | obligatoire si présent | oui | — | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].gpu.memoryClockMhz` | entier [≥ 0] | MHz | obligatoire si présent | oui | — | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].gpu.vramUsedBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | — | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].gpu.vramTotalBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | — | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].gpu.temperatureCelsius` | nombre [-100 à 200] | °C | obligatoire si présent | oui | — | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].gpu.powerWatts` | nombre [0 à 2000] | W | obligatoire si présent | oui | — | Linux, Windows | Linux : `sysbench, fio, glmark2` · Windows : `WinSAT, débit disque` | Public | `raw` uniquement |
| `benchmark.results[].framesPerSecond.current` | nombre | — | obligatoire si présent | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].framesPerSecond.minimum` | nombre | — | obligatoire si présent | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].framesPerSecond.maximum` | nombre | — | obligatoire si présent | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].framesPerSecond.average` | nombre | — | obligatoire si présent | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].framesPerSecond.first` | nombre | — | facultatif | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].framesPerSecond.p95` | nombre | — | facultatif | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].framesPerSecond.unit` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].framesPerSecond.sampleCount` | entier [≥ 0] | — | obligatoire si présent | non | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].framesPerSecond.sampleIntervalMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].framesPerSecond.sampleDurationMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].framesPerSecond.source` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].frameTimeMs.current` | nombre | — | obligatoire si présent | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].frameTimeMs.minimum` | nombre | — | obligatoire si présent | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].frameTimeMs.maximum` | nombre | — | obligatoire si présent | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].frameTimeMs.average` | nombre | — | obligatoire si présent | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].frameTimeMs.first` | nombre | — | facultatif | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].frameTimeMs.p95` | nombre | — | facultatif | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].frameTimeMs.unit` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].frameTimeMs.sampleCount` | entier [≥ 0] | — | obligatoire si présent | non | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].frameTimeMs.sampleIntervalMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].frameTimeMs.sampleDurationMs` | entier [0 à 31536000000] | ms | obligatoire si présent | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].frameTimeMs.source` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].frameStability.frameCount` | entier [≥ 0] | — | obligatoire si présent | non | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].frameStability.onePercentLowFps` | nombre [≥ 0] | — | obligatoire si présent | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].frameStability.zeroPointOnePercentLowFps` | nombre [≥ 0] | — | obligatoire si présent | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].frameStability.stutterCount` | entier [≥ 0] | — | obligatoire si présent | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].frameStability.stutterThresholdMs` | nombre [≥ 0] | ms | obligatoire si présent | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.results[].frameStability.stutterRule` | chaîne [1 à 256] | — | obligatoire si présent | oui | — | Linux | Linux : `glmark2 --off-screen` | Public | `raw` uniquement |
| `benchmark.telemetry.intervalMs` | entier [≥ 0] | ms | obligatoire si présent | non | `1000` | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].at` | date-heure ISO 8601 (UTC) | — | obligatoire si présent | non | `2026-07-25T16:39:57Z` | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].cpuUsagePercent` | nombre [0 à 100] | % | obligatoire si présent | oui | `3.1` | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].cpuTemperatureCelsius` | nombre [-100 à 200] | °C | obligatoire si présent | oui | `41` | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].cpuCoreVoltageVolts` | nombre [0 à 10] | — | facultatif | oui | — | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].cpuPackagePowerWatts` | nombre [0 à 10000] | W | facultatif | oui | `14.2` | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].gpuTemperatureCelsius` | nombre [-100 à 200] | °C | facultatif | oui | — | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].gpuHotspotCelsius` | nombre [-100 à 200] | °C | facultatif | oui | — | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].gpuCoreClockMhz` | entier [0 à 100000] | MHz | facultatif | oui | — | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].gpuMemoryClockMhz` | entier [0 à 100000] | MHz | facultatif | oui | — | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].gpuCoreVoltageVolts` | nombre [0 à 10] | — | facultatif | oui | — | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].gpuBoardPowerWatts` | nombre [0 à 10000] | W | facultatif | oui | — | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].memoryUsedBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `8589934592` | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].swapUsedBytes` | entier [≥ 0] | octets | obligatoire si présent | oui | `1073741824` | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].diskReadBytesPerSecond` | entier [≥ 0] | — | obligatoire si présent | oui | `0` | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].diskWriteBytesPerSecond` | entier [≥ 0] | — | obligatoire si présent | oui | `131072` | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].networkRxBytesPerSecond` | entier [≥ 0] | — | obligatoire si présent | oui | `8192` | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].networkTxBytesPerSecond` | entier [≥ 0] | — | obligatoire si présent | oui | `4096` | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].cpuFrequencyMhz` | entier [0 à 100000] | MHz | facultatif | oui | `1400` | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].cpuThrottled` | booléen | — | facultatif | oui | — | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].cpuThrottleReason` | thermal \| power-limit \| current-limit \| under-voltage \| user-defined \| other | — | facultatif | oui | — | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].gpuUsagePercent` | nombre [0 à 100] | % | facultatif | oui | — | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].gpuVramUsedBytes` | entier [≥ 0] | octets | facultatif | oui | — | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].gpuThrottleReason` | thermal \| power-limit \| current-limit \| under-voltage \| user-defined \| other | — | facultatif | oui | — | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].cpuFanRpm` | entier [≥ 0] | — | facultatif | oui | `720` | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].gpuFanRpm` | entier [≥ 0] | — | facultatif | oui | — | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].chassisFanRpm` | entier [≥ 0] | — | facultatif | oui | — | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].gpuAuxiliaryFanRpm[]` | entier [≥ 0] | — | obligatoire si présent | oui | — | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].cpuCoreClocksMhz[]` | entier [0 à 100000] | MHz | obligatoire si présent | oui | — | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].cpuCoreUsagePercent[]` | nombre [0 à 100] | % | obligatoire si présent | oui | — | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].gpuIndex` | entier [0 à 15] | — | facultatif | non | — | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].framesPerSecond` | nombre [0 à 100000] | — | facultatif | oui | — | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].frameTimeMs` | nombre [0 à 60000] | ms | facultatif | oui | — | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |
| `benchmark.telemetry.samples[].phase` | idle \| cpu-single \| cpu-multi \| cpu-soak \| memory-read \| memory-write \| memory-copy \| storage-sequential-write \| storage-sequential-read \| storage-random-read \| gpu \| gaming \| cpu-gpu | — | facultatif | non | `idle` | Linux | Linux : `lib/collectors/benchmark.sh` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `benchmark` — Banc d’essai, exécuté uniquement sur demande explicite : outil employé, paramètres, score, unité, et relevé thermique pendant la charge. *(depuis le schéma 1.8.0)*
- `benchmark.results[].framesPerSecond` — Cadence de rendu relevée scène par scène, quand l’outil la publie. Le score global n’en est qu’une moyenne pondérée : une carte qui rend 56 000 images par seconde sur une scène légère et 300 sur une scène d’ombrage n’a pas le même défaut qu’une carte régulière. **Charge synthétique et hors écran — ce n’est pas une cadence de jeu.** *(depuis le schéma 1.28.0)*
- `benchmark.results[].frameTimeMs` — Temps de trame correspondant. Redondant avec la cadence, et publié quand même : l’outil donne les deux, et recalculer l’un depuis l’autre introduirait un arrondi là où il y a une mesure. *(depuis le schéma 1.28.0)*
- `benchmark.results[].frameStability` — Centiles bas de la cadence et saccades comptées. La moyenne est la statistique qui ment le plus sur un rendu : 60 images par seconde régulières et une alternance 110/30 donnent la même moyenne, et une seule des deux est jouable. Le seuil de saccade est relatif à la médiane du rendu, jamais absolu, et il est publié avec le compte. *(depuis le schéma 1.29.0)*
- `benchmark.telemetry` — Ce que la machine a vécu pendant les mesures, relevé seconde par seconde et étiqueté par phase. Le score dit ce qu’elle a produit ; cette série dit à quel prix — fréquence tenue ou non, température stabilisée ou non, ventilateurs ayant répondu ou non. *(depuis le schéma 1.27.0)*

### `notes`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `notes[]` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Linux, Windows | Linux : `sysaudit.sh --note` · Windows : `sysaudit.ps1 -Note` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `notes` — Remarques libres saisies par l’opérateur au lancement. *(depuis le schéma 1.0.0)*

### `collection`

| Chemin | Type | Unité | Obligatoire | Non collecté | Exemple | OS | Collecteur | Confidentialité | PostgreSQL |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `collection.issues[].section` | chaîne [1 à 256] | — | obligatoire si présent | non | — | Linux, Windows | Linux : `lib/core/collect.sh` · Windows : `lib/core/collect.ps1` | Public | `raw` uniquement |
| `collection.issues[].severity` | warning \| error | — | obligatoire si présent | non | — | Linux, Windows | Linux : `lib/core/collect.sh` · Windows : `lib/core/collect.ps1` | Public | `raw` uniquement |
| `collection.issues[].message` | chaîne [1 à 1024] | — | obligatoire si présent | non | — | Linux, Windows | Linux : `lib/core/collect.sh` · Windows : `lib/core/collect.ps1` | Public | `raw` uniquement |
| `collection.issues[].source` | chaîne [1 à 256] | — | facultatif | non | — | Linux, Windows | Linux : `lib/core/collect.sh` · Windows : `lib/core/collect.ps1` | Public | `raw` uniquement |
| `collection.issues[].reason` | NOT_COLLECTED \| NOT_REQUESTED \| NOT_APPLICABLE \| UNSUPPORTED \| PERMISSION_DENIED \| NOT_AVAILABLE \| TIMEOUT \| COLLECTOR_ERROR | — | facultatif | non | — | Linux, Windows | Linux : `lib/core/collect.sh` · Windows : `lib/core/collect.ps1` | Public | `raw` uniquement |
| `collection.skippedSections[]` | chaîne [1 à 256] | — | obligatoire si présent | non | `drivers` | Linux, Windows | Linux : `lib/core/collect.sh` · Windows : `lib/core/collect.ps1` | Public | `raw` uniquement |
| `collection.timings[].section` | chaîne [1 à 256] | — | obligatoire si présent | non | `system` | Linux, Windows | Linux : `lib/core/collect.sh` · Windows : `lib/core/collect.ps1` | Public | `raw` uniquement |
| `collection.timings[].durationMs` | entier [≥ 0] | ms | obligatoire si présent | non | `38` | Linux, Windows | Linux : `lib/core/collect.sh` · Windows : `lib/core/collect.ps1` | Public | `raw` uniquement |
| `collection.provenance` | objet à clés libres | — | facultatif | non | — | Linux, Windows | Linux : `lib/core/collect.sh` · Windows : `lib/core/collect.ps1` | Public | `raw` uniquement |
| `collection.dependencies[].tool` | chaîne [1 à 256] | — | obligatoire si présent | non | `smartctl` | Linux, Windows | Linux : `lib/core/collect.sh` · Windows : `lib/core/collect.ps1` | Public | `raw` uniquement |
| `collection.dependencies[].package` | chaîne [1 à 256] | — | facultatif | non | `smartmontools` | Linux, Windows | Linux : `lib/core/collect.sh` · Windows : `lib/core/collect.ps1` | Public | `raw` uniquement |
| `collection.dependencies[].outcome` | PRESENT_BEFORE \| INSTALLED \| INSTALL_FAILED \| DECLINED \| NOT_OFFERED | — | obligatoire si présent | non | `PRESENT_BEFORE` | Linux, Windows | Linux : `lib/core/collect.sh` · Windows : `lib/core/collect.ps1` | Public | `raw` uniquement |
| `collection.dependencies[].version` | chaîne [1 à 256] | — | facultatif | non | `smartctl 7.4 2023-08-01 r5530` | Linux, Windows | Linux : `lib/core/collect.sh` · Windows : `lib/core/collect.ps1` | Public | `raw` uniquement |
| `collection.dependencies[].method` | chaîne [1 à 256] | — | facultatif | non | — | Linux, Windows | Linux : `lib/core/collect.sh` · Windows : `lib/core/collect.ps1` | Public | `raw` uniquement |
| `collection.dependencies[].unlocks` | chaîne [1 à 1024] | — | facultatif | non | `santé SMART et usure des disques` | Linux, Windows | Linux : `lib/core/collect.sh` · Windows : `lib/core/collect.ps1` | Public | `raw` uniquement |
| `collection.dependencies[].used` | booléen | — | facultatif | non | `true` | Linux, Windows | Linux : `lib/core/collect.sh` · Windows : `lib/core/collect.ps1` | Public | `raw` uniquement |
| `collection.dependencies[].removal` | NOT_APPLICABLE \| REMOVED \| KEPT \| REMOVAL_FAILED | — | facultatif | non | `NOT_APPLICABLE` | Linux, Windows | Linux : `lib/core/collect.sh` · Windows : `lib/core/collect.ps1` | Public | `raw` uniquement |
| `collection.dependencies[].error` | chaîne [1 à 1024] | — | facultatif | non | — | Linux, Windows | Linux : `lib/core/collect.sh` · Windows : `lib/core/collect.ps1` | Public | `raw` uniquement |
| `collection.dependenciesInspected` | booléen | — | facultatif | non | `true` | Linux, Windows | Linux : `lib/core/collect.sh` · Windows : `lib/core/collect.ps1` | Public | `raw` uniquement |
| `collection.plannedSections[]` | chaîne [1 à 256] | — | obligatoire si présent | non | `system` | Linux, Windows | Linux : `lib/core/collect.sh` · Windows : `lib/core/collect.ps1` | Public | `raw` uniquement |
| `collection.knownSections[]` | chaîne [1 à 256] | — | obligatoire si présent | non | `system` | Linux, Windows | Linux : `lib/core/collect.sh` · Windows : `lib/core/collect.ps1` | Public | `raw` uniquement |

**Sens des champs de cette section**

- `collection` — Journal de la collecte : sections ignorées et incidents rencontrés, avec leur gravité. *(depuis le schéma 1.0.0)*

<!-- fields:reference:end -->
