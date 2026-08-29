# Dépendances externes

Le scanner **fonctionne sans aucun de ces outils**. Il ne s'arrête jamais parce
qu'un binaire manque : il déclare la donnée non collectée, avec le nom de ce qui
lui manquait. Cette page dit ce que chaque outil apporte, et comment l'obtenir.

> **Effet sur le rapport.** Un outil absent rend les données concernées
> `NOT_AVAILABLE`, ce qui n'est jamais une panne matérielle. Le récapitulatif
> par motif est décrit dans `../analyse/COUVERTURE.md`.

> **SysAudit ne redistribue et ne télécharge rien.** Aucun binaire tiers n'est
> embarqué, aucune dépendance n'est récupérée à l'exécution, et seul le
> gestionnaire de paquets de la distribution est appelé — jamais une URL, jamais
> un dépôt tiers ajouté. La décision et ses raisons :
> [../adr/0006-dependances-externes.md](../adr/0006-dependances-externes.md).
>
> **Il n'installe rien non plus, sauf demande explicite.** Depuis le
> [2026-08-07](../adr/0008-installation-consentie-en-audit-administrateur.md),
> `--install-deps` autorise l'installation des outils manquants sous quatre
> conditions cumulatives : le drapeau tapé à la main, un audit `--full` ou
> `--stress`, un accord donné outil par outil après affichage de ce qu'il est,
> et un terminal. Hors de ce cas — donc pour tout le chemin public, script
> d'amorçage compris — le scanner nomme et n'installe pas.
>
> Ce qu'il installe, il propose de le retirer en fin d'audit, et **seulement**
> ce qu'il a installé lui-même : le rapport porte l'inventaire d'avant-collecte
> dans `collection.dependencies`, et un outil marqué `PRESENT_BEFORE` n'est
> jamais proposé à la suppression.

> **Ce document n'est pas saisi à la main.** Sa source de vérité est
> `packages/platform/src/tool-dependencies.ts`. Régénérer avec
> `npm run docs:dependencies` ; un test échoue si le fichier a dérivé.

## Les outils qui changent le plus un rapport

<!-- tools:recommended:start -->

- `dmidecode` — Carte mère, BIOS, châssis, socket processeur et modules mémoire (SMBIOS).
- `lspci` — Cartes graphiques, périphériques PCI/PCIe, pilotes noyau en service.
- `smartctl` — Santé SMART, usure, heures de fonctionnement, numéro de série et firmware disque.
- `ip` — Interfaces, adresses, routes.
- `ss` — Ports en écoute et exposition des services (niveau Normale).
- `journalctl` — Historique des incidents, fenêtre réellement couverte par le journal, et déroulement du dernier arrêt.

<!-- tools:recommended:end -->

## Linux, Proxmox VE

<!-- tools:linux:start -->

| Outil                                     | Débloque                                                                                                                                                | Exigence                                           | Privilèges            | Licence amont                               | Sans lui                                                                                                                                              |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- | --------------------- | ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `dmidecode`                               | Carte mère, BIOS, châssis, socket processeur et modules mémoire (SMBIOS).                                                                               | recommandé                                         | root / administrateur | GPL-2.0-or-later                            | Carte mère, BIOS et barrettes marqués `NOT_AVAILABLE` ; le reste du matériel reste collecté.                                                          |
| `lscpu` (util-linux)                      | Détail processeur : cœurs, fils, caches, fréquences, jeux d’instructions.                                                                               | présent d’office                                   | aucun                 | GPL-2.0-only                                | Repli sur `/proc/cpuinfo` : modèle et nombre de fils, sans les caches.                                                                                |
| `lspci` (pciutils)                        | Cartes graphiques, périphériques PCI/PCIe, pilotes noyau en service.                                                                                    | recommandé                                         | aucun                 | GPL-2.0-or-later                            | Aucun GPU ni périphérique PCI inventorié ; la section le déclare.                                                                                     |
| `lsusb` (usbutils)                        | Périphériques USB (niveau Complète).                                                                                                                    | facultatif                                         | aucun                 | GPL-2.0-or-later                            | Bus USB déclaré non inventorié.                                                                                                                       |
| `sensors` (lm-sensors)                    | Complète la lecture hwmon des températures, tensions et ventilateurs.                                                                                   | facultatif                                         | aucun                 | GPL-2.0-or-later                            | Les capteurs restent lus directement dans `/sys/class/hwmon` : sans perte majeure.                                                                    |
| `lsblk` (util-linux)                      | Disques, partitions, systèmes de fichiers, tables de partition.                                                                                         | présent d’office                                   | aucun                 | GPL-2.0-only                                | Aucun disque inventorié : la section `storage` le déclare en erreur.                                                                                  |
| `smartctl` (smartmontools)                | Santé SMART, usure, heures de fonctionnement, numéro de série et firmware disque.                                                                       | recommandé                                         | root / administrateur | GPL-2.0-or-later                            | Santé disque marquée `NOT_AVAILABLE` : aucune usure, aucun compteur.                                                                                  |
| `nvme` (nvme-cli)                         | Journal SMART NVMe étendu, au-delà de ce que `smartctl` expose.                                                                                         | facultatif — proposé si un disque NVMe est présent | root / administrateur | GPL-2.0-only                                | `smartctl` couvre déjà l’essentiel des compteurs NVMe.                                                                                                |
| `zpool` (zfsutils-linux)                  | Pools ZFS : topologie, redondance, état, capacité.                                                                                                      | facultatif                                         | root / administrateur | CDDL-1.0                                    | Aucun pool ZFS rapporté — ce qui est correct sur une machine sans ZFS.                                                                                |
| `ip` (iproute2)                           | Interfaces, adresses, routes.                                                                                                                           | recommandé                                         | aucun                 | GPL-2.0-only                                | Aucune interface réseau inventoriée.                                                                                                                  |
| `ss` (iproute2)                           | Ports en écoute et exposition des services (niveau Normale).                                                                                            | recommandé                                         | root / administrateur | GPL-2.0-only                                | Liste des ports déclarée non collectée — jamais rendue vide.                                                                                          |
| `hostnamectl` (systemd)                   | Identité machine, châssis, version du système.                                                                                                          | facultatif                                         | aucun                 | LGPL-2.1-or-later                           | Repli sur `/etc/os-release` et `uname`.                                                                                                               |
| `systemctl` (systemd)                     | Services, TRIM planifié, état des unités.                                                                                                               | facultatif                                         | aucun                 | LGPL-2.1-or-later                           | Services non inventoriés ; TRIM planifié marqué `NOT_AVAILABLE`.                                                                                      |
| `pvecm` (proxmox-ve)                      | État de la grappe : quorum, nombre de nœuds, nom.                                                                                                       | facultatif                                         | root / administrateur | AGPL-3.0-only                               | Grappe déclarée `UNKNOWN` plutôt que `STANDALONE` : sans `pvecm`, l’isolement d’un nœud ne se distingue pas d’une lecture impossible.                 |
| `pvesr` (proxmox-ve)                      | Réplications ZFS en échec entre nœuds.                                                                                                                  | facultatif                                         | root / administrateur | AGPL-3.0-only                               | Réplication marquée `NOT_AVAILABLE` — distincte de « aucune réplication ».                                                                            |
| `ha-manager` (proxmox-ve)                 | État des ressources en haute disponibilité.                                                                                                             | facultatif                                         | root / administrateur | AGPL-3.0-only                               | Haute disponibilité marquée `NOT_AVAILABLE`.                                                                                                          |
| `ceph` (ceph-common)                      | Santé d’une grappe Ceph hyperconvergée.                                                                                                                 | facultatif                                         | root / administrateur | LGPL-2.1-or-later                           | Ceph déclaré absent (`present: false`), et non dégradé.                                                                                               |
| `journalctl` (systemd)                    | Historique des incidents, fenêtre réellement couverte par le journal, et déroulement du dernier arrêt.                                                  | recommandé                                         | aucun                 | LGPL-2.1-or-later                           | Repli sur `dmesg`, qui ne couvre que le démarrage courant et le seul noyau : la fenêtre annoncée est alors l’uptime, pas la fenêtre demandée.         |
| `systemd-analyze` (systemd)               | Durée des phases de démarrage et unités les plus lentes.                                                                                                | facultatif                                         | aucun                 | LGPL-2.1-or-later                           | Section `boot` réduite au mode du micrologiciel : aucune durée mesurée.                                                                               |
| `coredumpctl` (systemd-coredump)          | Vidanges mémoire recensées : exécutable, signal et date — jamais leur contenu.                                                                          | facultatif                                         | root / administrateur | LGPL-2.1-or-later                           | Aucune vidange recensée — ce qui est correct sur une machine sans systemd-coredump.                                                                   |
| `dmesg` (util-linux)                      | Anneau du noyau, quand journald est absent : erreurs matérielles et de stockage.                                                                        | facultatif                                         | root / administrateur | GPL-2.0-or-later                            | Aucun historique noyau si `journalctl` est également absent.                                                                                          |
| `last` (util-linux)                       | Nombre de redémarrages observés, lu dans `wtmp`.                                                                                                        | facultatif                                         | aucun                 | GPL-2.0-or-later                            | Compteur de redémarrages marqué `NOT_AVAILABLE`.                                                                                                      |
| `vcgencmd` (raspi-utils)                  | Bridage et sous-tension d’un Raspberry Pi, tels que le micrologiciel les rapporte — la seule source qui les distingue d’une simple baisse de fréquence. | facultatif — proposé sur Raspberry Pi uniquement   | aucun                 | BSD-3-Clause                                | Bridage marqué `NOT_AVAILABLE` : une fréquence basse ne suffit pas à le conclure, un processeur au repos tournant bas sans être bridé.                |
| `sshd` (OpenSSH)                          | Politique SSH : authentification par mot de passe, connexion root, port.                                                                                | facultatif                                         | root / administrateur | BSD-2-Clause                                | Section SSH absente — correcte sur une machine sans serveur SSH.                                                                                      |
| `ufw`                                     | État et politique du pare-feu Ubuntu/Debian.                                                                                                            | facultatif                                         | root / administrateur | GPL-3.0-only                                | Le pare-feu est cherché via `nft`, `iptables` ou `firewall-cmd`.                                                                                      |
| `firewall-cmd` (firewalld)                | État et zones du pare-feu RHEL/Fedora.                                                                                                                  | facultatif                                         | root / administrateur | GPL-2.0-or-later                            | Le pare-feu est cherché via `ufw`, `nft` ou `iptables`.                                                                                               |
| `nft` (nftables)                          | Règles de filtrage nftables, politique par défaut.                                                                                                      | facultatif                                         | root / administrateur | GPL-2.0-only                                | Repli sur `iptables` ; sinon pare-feu marqué inconnu, jamais « désactivé ».                                                                           |
| `iptables`                                | Règles de filtrage héritées, sur les systèmes sans nftables.                                                                                            | facultatif                                         | root / administrateur | GPL-2.0-only                                | Pare-feu marqué inconnu — pas « désactivé », la nuance est le sujet.                                                                                  |
| `apt` (APT)                               | Mises à jour en attente et mises à jour de sécurité (Debian/Ubuntu).                                                                                    | présent d’office                                   | aucun                 | GPL-2.0-or-later                            | Mises à jour marquées `NOT_AVAILABLE`.                                                                                                                |
| `dpkg`                                    | Inventaire des paquets installés (niveau Complète).                                                                                                     | présent d’office                                   | aucun                 | GPL-2.0-or-later                            | Inventaire logiciel vide sur cette famille.                                                                                                           |
| `rpm` (RPM)                               | Inventaire des paquets installés (RHEL, Fedora, SUSE).                                                                                                  | présent d’office                                   | aucun                 | GPL-2.0-or-later                            | Inventaire logiciel vide sur cette famille.                                                                                                           |
| `dnf` (DNF)                               | Mises à jour en attente (RHEL, Fedora).                                                                                                                 | présent d’office                                   | aucun                 | GPL-2.0-or-later                            | Mises à jour marquées `NOT_AVAILABLE`.                                                                                                                |
| `pacman`                                  | Paquets installés et mises à jour en attente (Arch).                                                                                                    | présent d’office                                   | aucun                 | GPL-2.0-or-later                            | Mises à jour et paquets marqués `NOT_AVAILABLE`.                                                                                                      |
| `docker` (Docker CLI)                     | Conteneurs, images, réseaux, ports publiés.                                                                                                             | facultatif                                         | root / administrateur | Apache-2.0                                  | Aucun conteneur rapporté — correct sur une machine sans Docker. Un client présent dont le démon ne répond pas laisse la section absente, jamais vide. |
| `pveversion` (Proxmox VE)                 | Version du nœud Proxmox et activation du module dédié.                                                                                                  | facultatif                                         | root / administrateur | AGPL-3.0-only                               | Module Proxmox désactivé ; la machine est auditée comme un Linux ordinaire.                                                                           |
| `pvesh` (Proxmox VE)                      | Cluster, nœuds et état de la grappe via l’API locale.                                                                                                   | facultatif                                         | root / administrateur | AGPL-3.0-only                               | État du cluster marqué inconnu.                                                                                                                       |
| `qm` (Proxmox VE)                         | Machines virtuelles : configuration, disques, interfaces.                                                                                               | facultatif                                         | root / administrateur | AGPL-3.0-only                               | Invités KVM non détaillés.                                                                                                                            |
| `pct` (Proxmox VE)                        | Conteneurs LXC : configuration, ressources, montages.                                                                                                   | facultatif                                         | root / administrateur | AGPL-3.0-only                               | Conteneurs LXC non détaillés.                                                                                                                         |
| `pvesm` (Proxmox VE)                      | Stockages déclarés du nœud et leur occupation.                                                                                                          | facultatif                                         | root / administrateur | AGPL-3.0-only                               | Stockages Proxmox non inventoriés.                                                                                                                    |
| `openssl` (OpenSSL)                       | Mesures processeur du banc d’essai, pointe et charge soutenue.                                                                                          | présent d’office                                   | aucun                 | Apache-2.0                                  | Mesures processeur déclarées écartées, faute d’outil.                                                                                                 |
| `dd` (coreutils)                          | Mesures mémoire et stockage séquentiel du banc d’essai.                                                                                                 | présent d’office                                   | aucun                 | GPL-3.0-or-later                            | Mesures mémoire et stockage déclarées écartées.                                                                                                       |
| `fio`                                     | Mesure de lecture aléatoire 4 Kio du banc d’essai.                                                                                                      | facultatif                                         | aucun                 | GPL-2.0-only                                | Lecture aléatoire déclarée écartée ; les mesures séquentielles restent faites.                                                                        |
| `glmark2`                                 | Mesure de rendu GPU du banc d’essai, une par carte détectée.                                                                                            | facultatif                                         | aucun                 | GPL-3.0-or-later                            | Mesure GPU déclarée écartée, carte par carte.                                                                                                         |
| `nvidia-smi` (pilote propriétaire NVIDIA) | Télémétrie GPU NVIDIA pendant la mesure : utilisation, fréquences, VRAM, température, puissance.                                                        | facultatif                                         | aucun                 | Propriétaire NVIDIA (fourni avec le pilote) | Aucune télémétrie GPU ; le score de rendu reste mesuré.                                                                                               |

<!-- tools:linux:end -->

## Windows

Aucun outil tiers n'est employé : tout vient de Windows lui-même. Les modules
PowerShell listés ci-dessous sont présents sur une installation standard, mais
pas sur toutes les éditions — BitLocker manque aux éditions Famille, WinSAT à
certaines installations de Windows Server.

<!-- tools:windows:start -->

| Outil                                  | Débloque                                                                                                                                                  | Exigence         | Privilèges            | Licence amont                                | Sans lui                                                                                                                                                              |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- | --------------------- | -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `docker` (Docker CLI)                  | Conteneurs, images, réseaux, ports publiés.                                                                                                               | facultatif       | root / administrateur | Apache-2.0                                   | Aucun conteneur rapporté — correct sur une machine sans Docker. Un client présent dont le démon ne répond pas laisse la section absente, jamais vide.                 |
| `powershell` (Windows PowerShell 5.1+) | Le scanner lui-même : il est écrit en PowerShell.                                                                                                         | présent d’office | aucun                 | MIT (PowerShell 7) / composant Windows (5.1) | Aucun scan possible : c’est l’interpréteur du scanner Windows.                                                                                                        |
| `cim` (CIM / WMI)                      | Matériel, stockage, réseau, sécurité : la quasi-totalité de la collecte Windows.                                                                          | présent d’office | aucun                 | Composant Windows                            | Rapport réduit à l’identité machine.                                                                                                                                  |
| `wmi` (Get-WmiObject (WMI hérité))     | Repli de collecte sur les systèmes antérieurs à PowerShell 3.0, où `Get-CimInstance` n’existe pas : c’est la même donnée, lue par l’interface précédente. | présent d’office | aucun                 | Composant Windows                            | Aucune perte tant que CIM répond : le scanner préfère toujours CIM, plus rapide et non déprécié. Sans CIM **et** sans WMI, la lecture porte un marqueur `capability`. |
| `winEvent` (Get-WinEvent)              | Journaux d’événements filtrés côté service (`-FilterHashtable`) : arrêts inattendus, erreurs disque, incidents matériels.                                 | présent d’office | root / administrateur | Composant Windows                            | Repli sur `Get-EventLog`, qui filtre côté client. Sans les deux, la section des événements est déclarée non collectée — jamais « aucun incident ».                    |
| `eventLog` (Get-EventLog)              | Lecture des journaux classiques sur les systèmes où `Get-WinEvent` est absent (Windows 7 / Server 2008 sans mise à jour du framework).                    | présent d’office | root / administrateur | Composant Windows                            | Aucune perte quand `Get-WinEvent` répond, qui reste préféré. Sans les deux, la section des événements est déclarée non collectée.                                     |
| `getComputerInfo` (Get-ComputerInfo)   | Édition, build et informations de démarrage sécurisé.                                                                                                     | présent d’office | aucun                 | Composant Windows                            | Repli sur CIM : quelques champs restent inconnus.                                                                                                                     |
| `netFirewall` (Module NetSecurity)     | Profils du pare-feu Windows et leur état.                                                                                                                 | présent d’office | root / administrateur | Composant Windows                            | Pare-feu marqué inconnu — jamais « désactivé ».                                                                                                                       |
| `netAdapter` (Module NetAdapter)       | Débit négocié, duplex et état des cartes réseau.                                                                                                          | présent d’office | aucun                 | Composant Windows                            | Repli sur CIM : le duplex reste inconnu.                                                                                                                              |
| `bitlocker` (Module BitLocker)         | État du chiffrement de disque et volumes protégés.                                                                                                        | présent d’office | root / administrateur | Composant Windows                            | Chiffrement marqué inconnu ; absent des éditions Famille.                                                                                                             |
| `defender` (Module Defender)           | État de l’antivirus, protection en temps réel, dernière analyse.                                                                                          | présent d’office | root / administrateur | Composant Windows                            | Antivirus marqué inconnu — un tiers peut avoir remplacé Defender.                                                                                                     |
| `tpm` (Module TrustedPlatformModule)   | Présence, version et état du TPM.                                                                                                                         | présent d’office | root / administrateur | Composant Windows                            | TPM marqué inconnu, jamais « absent ».                                                                                                                                |
| `winsat` (WinSAT)                      | Indices processeur, mémoire et Direct3D du banc d’essai.                                                                                                  | facultatif       | root / administrateur | Composant Windows                            | Les débits disque restent mesurés en .NET ; les trois indices sont déclarés non mesurés.                                                                              |
| `hyperv` (Module Hyper-V)              | Machines virtuelles hébergées : nom, état, cœurs, mémoire, démarrage automatique.                                                                         | facultatif       | root / administrateur | Composant Windows                            | Section Hyper-V absente. Sans élévation, elle l’est aussi : une liste vide se lirait comme un hôte sans machine virtuelle.                                            |
| `appx` (Module Appx)                   | Applications empaquetées du Store, absentes de la base de désinstallation.                                                                                | facultatif       | aucun                 | Composant Windows                            | Inventaire limité aux logiciels du registre ; absent des éditions Server Core et sans Store.                                                                          |
| `winget`                               | Constat de la présence du gestionnaire de paquets et de sa version.                                                                                       | facultatif       | aucun                 | MIT                                          | Le gestionnaire n’est pas listé. Son inventaire n’est de toute façon pas lu : `winget list` ne publie qu’un tableau tronqué à la largeur de la console.               |

<!-- tools:windows:end -->

## Installer ce qui manque

Le scanner affiche, en fin de scan, les paquets qui auraient enrichi le rapport.
Il ne les installe pas.

<!-- tools:commands:start -->

- **Debian / Ubuntu / Proxmox** — `sudo apt install <paquet>`
- **RHEL / Fedora / Rocky** — `sudo dnf install <paquet>`
- **Arch / Manjaro** — `sudo pacman -S <paquet>`
- **openSUSE / SLES** — `sudo zypper install <paquet>`
- **Alpine** — `sudo apk add <paquet>`

<!-- tools:commands:end -->

<!-- tools:packages:start -->

| Outil          | Debian / Ubuntu / Proxmox | RHEL / Fedora / Rocky | Arch / Manjaro      | openSUSE / SLES    | Alpine              |
| -------------- | ------------------------- | --------------------- | ------------------- | ------------------ | ------------------- |
| `dmidecode`    | `dmidecode`               | `dmidecode`           | `dmidecode`         | `dmidecode`        | `dmidecode`         |
| `lspci`        | `pciutils`                | `pciutils`            | `pciutils`          | `pciutils`         | `pciutils`          |
| `lsusb`        | `usbutils`                | `usbutils`            | `usbutils`          | `usbutils`         | `usbutils`          |
| `sensors`      | `lm-sensors`              | `lm_sensors`          | `lm_sensors`        | `sensors`          | `lm-sensors`        |
| `smartctl`     | `smartmontools`           | `smartmontools`       | `smartmontools`     | `smartmontools`    | `smartmontools`     |
| `nvme`         | `nvme-cli`                | `nvme-cli`            | `nvme-cli`          | `nvme-cli`         | `nvme-cli`          |
| `zpool`        | `zfsutils-linux`          | `zfs`                 | `zfs-utils`         | `zfs`              | `zfs`               |
| `ip`           | `iproute2`                | `iproute`             | `iproute2`          | `iproute2`         | —                   |
| `ss`           | `iproute2`                | `iproute`             | `iproute2`          | `iproute2`         | —                   |
| `ceph`         | `ceph-common`             | `ceph-common`         | `ceph`              | `ceph-common`      | `ceph`              |
| `coredumpctl`  | `systemd-coredump`        | `systemd-udev`        | `systemd`           | `systemd-coredump` | `systemd`           |
| `vcgencmd`     | `raspi-utils`             | `raspi-utils`         | `raspberrypi-utils` | `raspi-utils`      | `raspberrypi-utils` |
| `ufw`          | `ufw`                     | —                     | `ufw`               | `ufw`              | —                   |
| `firewall-cmd` | `firewalld`               | `firewalld`           | —                   | `firewalld`        | —                   |
| `nft`          | `nftables`                | `nftables`            | `nftables`          | `nftables`         | —                   |
| `iptables`     | `iptables`                | `iptables`            | `iptables`          | `iptables`         | —                   |
| `fio`          | `fio`                     | `fio`                 | `fio`               | `fio`              | `fio`               |
| `glmark2`      | `glmark2`                 | `glmark2`             | `glmark2`           | `glmark2`          | —                   |

<!-- tools:packages:end -->

## Installation consentie — `--install-deps`

Réservée à l'administrateur qui lance lui-même un audit approfondi sur sa
machine. Quatre conditions, **toutes** requises ; si l'une manque, le scanner le
dit et se comporte comme avant, c'est-à-dire qu'il nomme sans installer.

| Condition        | Vérifiée par                                             |
| ---------------- | -------------------------------------------------------- |
| `--install-deps` | tapé à la main ; le script d'amorçage ne le passe jamais |
| niveau           | `--full` ou `--stress` uniquement                        |
| privilèges       | root, plus un gestionnaire de paquets reconnu            |
| accord           | un par outil, ou `--assume-yes` donné en amont           |

Ce que l'utilisateur voit avant chaque question : le nom de l'outil, son paquet,
ce qu'il apporte, ce que devient la donnée sans lui, la provenance — toujours un
dépôt de la distribution, jamais une URL —, la commande exacte, les privilèges
requis, et le fait que son retrait sera proposé en fin d'audit.

```text
Outil manquant : nvme
  → Paquet          nvme-cli
  → Apporte         journal SMART NVMe étendu
  → Sans lui        la donnée est marquée non évaluée, jamais inventée
  → Provenance      dépôts officiels Debian/Ubuntu (apt)
  → Commande        apt-get install -y --no-install-recommends nvme-cli
  → Privilèges      root (déjà obtenus pour cet audit)
  → Après l'audit   retrait proposé ; refuser le conserve
Installer nvme-cli ? [o/N]
```

Un code retour nul ne suffit pas à conclure : le scanner rafraîchit son `PATH`
puis vérifie que la commande **répond** réellement. Un paquet installé dont le
binaire reste introuvable est un échec, pas une réussite silencieuse.

### Retrait

Proposé en fin de collecte, avant l'écriture du rapport — sinon son issue n'y
figurerait pas. Il ne peut porter que sur les outils dont l'inventaire dit
`INSTALLED`. Aucun chemin du module ne permet de toucher un `PRESENT_BEFORE`.

`--assume-yes` **n'autorise pas** le retrait : il a été donné pour installer, et
le retrait est une seconde décision qui n'a pas été posée. Les outils sont alors
conservés.

Aucune commande de retrait n'emporte les dépendances devenues orphelines — ni
`apt autoremove`, ni `pacman -Rs`, ni leurs équivalents. En fin d'audit, sur une
machine de production, une cascade de suppression serait la pire chose que ce
scanner puisse faire.

### Sous Windows

Rien à installer, et ce n'est pas un manque. Les seize entrées de
`capabilities.tools` sont des cmdlets PowerShell, des modules livrés avec le
système ou des interfaces CIM/WMI. Aucune n'a de paquet, parce qu'aucune ne
s'installe : elle est là, ou la fonctionnalité Windows correspondante est absente
de cette édition — ce qu'aucun `winget install` ne corrige. Le scanner Windows
inventorie donc, et n'installe pas.

## Ce que le rapport en dit

Chaque outil présent ou absent est publié dans `capabilities.tools`, une entrée
par outil. C'est ce qui permet de lire un rapport partiel sans se tromper : un
compteur SMART absent parce que `smartctl` n'est pas installé n'est pas un
disque en mauvaise santé, et le rapport porte la différence.

Un outil absent produit toujours l'un de ces marqueurs, jamais une valeur par
défaut :

| Marqueur            | Signification                                            |
| ------------------- | -------------------------------------------------------- |
| `NOT_AVAILABLE`     | L'outil ou la source n'est pas sur cette machine         |
| `PERMISSION_DENIED` | L'outil est là, les privilèges manquent                  |
| `NOT_COLLECTED`     | Le niveau de diagnostic choisi ne prévoit pas la lecture |

### `collection.dependencies` — ce qu'il est advenu de chaque outil

`capabilities.tools` dit ce qui **répond** ; cette liste dit ce qui s'est
**passé**. Une entrée par outil, jamais deux : un outil présent à la fois dans
« déjà installé » et dans « installé par SysAudit » aurait autorisé une
suppression que l'ADR 0008 interdit.

| `outcome`        | Signification                                               |
| ---------------- | ----------------------------------------------------------- |
| `PRESENT_BEFORE` | Déjà là avant l'audit. **Jamais** installé ni supprimé      |
| `INSTALLED`      | Absent, installé après accord explicite                     |
| `INSTALL_FAILED` | Installation tentée et échouée ; `error` dit pourquoi       |
| `DECLINED`       | Proposée, refusée. Ne pénalise aucun score                  |
| `NOT_OFFERED`    | Absent, question non posée — le cas de tout audit ordinaire |

| `removal`        | Signification                                             |
| ---------------- | --------------------------------------------------------- |
| `NOT_APPLICABLE` | SysAudit n'avait rien installé : rien à retirer           |
| `REMOVED`        | Retiré en fin d'audit, à la demande de l'utilisateur      |
| `KEPT`           | Installé puis conservé, sur décision de l'utilisateur     |
| `REMOVAL_FAILED` | Retrait demandé et échoué : la machine **reste** modifiée |

Deux champs méritent une lecture attentive :

- **`dependenciesInspected`** distingue « aucun outil ne manquait » de « on n'a
  pas regardé ». Une liste vide seule ne sait pas dire lequel des deux, et le
  rendu du rapport se tait quand ce drapeau est faux.
- **`used`** est **absent** quand la question n'a pas de réponse, et non `false`.
  Le scanner Linux le sait parce que toutes ses commandes externes passent par
  un point unique, qui note l'invocation au passage ; le scanner Windows appelle
  ses cmdlets depuis chaque collecteur et ne peut pas le déduire. `false` s'y
  lirait comme « installé pour rien » — un reproche fabriqué à partir d'une
  donnée non collectée.

## Outils évalués puis écartés

| Outil                         | Décision | Raison                                                                                                                                                               |
| ----------------------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `diskspd` (Microsoft)         | écarté   | Binaire tiers : le redistribuer exigerait une analyse de licence, le télécharger reviendrait à exécuter du code non vérifié. Le stockage Windows est mesuré en .NET. |
| LibreHardwareMonitor / HWiNFO | reporté  | Seule voie connue vers les températures Windows, mais suppose un composant tiers signé et une décision de distribution (étape 03 pour la partie capteurs).           |
| Prime95, FurMark              | écartés  | Licences non compatibles avec une redistribution, et un banc d'essai n'a pas besoin de pousser le matériel à ses limites absolues pour être utile.                   |
| `stress-ng`, `sysbench`       | écartés  | `openssl` et `dd`, déjà présents partout, suffisent aux mesures publiées. Ajouter une dépendance pour un chiffre équivalent serait un coût sans contrepartie.        |
| CrystalDiskInfo               | écarté   | Interface graphique : rien à en tirer dans un scan non interactif.                                                                                                   |
| PresentMon                    | reporté  | Utile à une mesure de rendu en jeu, hors du périmètre d'un audit système.                                                                                            |
