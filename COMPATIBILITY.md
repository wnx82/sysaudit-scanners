# Matrice de compatibilité

> **Règle :** ✅ signifie _implémenté **et** validé sur la plateforme
> concernée_. Du code écrit mais jamais exécuté sur la cible réelle reste 🟡.
> Aucune case n'est cochée par anticipation.

> **🟠 depuis le 2026-08-11.** Une capacité peut être éprouvée sur la cible et
> pourtant **amputée** — le collecteur tourne, une part de ce que la colonne
> recouvre n'est pas lue. La Sécurité de Windows était dans ce cas et portait un
> ✅ : ni les comptes, ni les protocoles obsolètes, ni les mises à jour en
> attente ne sont collectés. Sur une colonne de sécurité, un ✅ se lit comme une
> bonne nouvelle — c'était donc le pire endroit pour laisser cette approximation.
> Toute case 🟠 dit ce qui lui manque, juste sous le tableau.

> **Ce tableau n'est pas saisi à la main.** Sa source de vérité est
> `packages/platform/src/compatibility.ts`. Régénérer avec
> `npm run docs:compatibility` ; un test échoue si le fichier a dérivé.

<!-- compatibility:legend:start -->

- ✅ implémenté et validé sur la cible
- 🟠 éprouvé sur la cible, couverture partielle
- 🟡 implémenté, non validé sur la cible
- ⏳ prévu
- — non implémenté
- ❌ non supporté volontairement
- n/a sans objet

<!-- compatibility:legend:end -->

## Systèmes d'exploitation

<!-- compatibility:current:start -->

| OS                           | Scanner | Matériel | Logiciel      | Stockage | SMART | Réseau | Sécurité | Virtualisation | IA  |
| ---------------------------- | ------- | -------- | ------------- | -------- | ----- | ------ | -------- | -------------- | --- |
| Ubuntu 24.04                 | Linux   | 🟡       | ✅ apt · snap | ✅       | 🟡    | ✅     | ✅       | ✅ Docker      | ✅  |
| Debian 12/13                 | Linux   | ✅       | ✅            | ✅       | ✅    | ✅     | ✅       | ✅             | ✅  |
| Linux Mint                   | Linux   | 🟡       | 🟡            | 🟡       | 🟡    | 🟡     | 🟡       | 🟡             | ✅  |
| Fedora                       | Linux   | 🟡       | ✅            | 🟡       | 🟡    | 🟡     | 🟡       | 🟡             | ✅  |
| Rocky / AlmaLinux            | Linux   | 🟡       | ✅            | 🟡       | 🟡    | 🟡     | 🟡       | 🟡             | ✅  |
| Arch / Manjaro               | Linux   | 🟡       | ✅            | 🟡       | 🟡    | 🟡     | 🟡       | 🟡             | ✅  |
| Raspberry Pi OS              | Linux   | 🟡       | 🟡            | 🟡       | 🟡    | 🟡     | 🟡       | 🟡             | ✅  |
| Proxmox VE 8/9               | Proxmox | ✅       | ✅            | ✅       | ✅    | ✅     | ✅       | ✅ Proxmox     | ✅  |
| Windows 11 / 10              | Modern  | 🟠       | ✅            | 🟠       | 🟠    | 🟠     | 🟠       | ✅             | ✅  |
| Windows Server               | Modern  | 🟡       | 🟡            | 🟡       | 🟡    | 🟡     | 🟡       | 🟡             | ✅  |
| Windows 8.1 / 8 / 7          | Legacy  | —        | —             | —        | —     | —      | —        | —              | ✅  |
| Windows Vista / XP           | Minimal | ⏳       | ⏳            | ⏳       | ❌    | ⏳     | ⏳       | n/a            | ✅  |
| macOS                        | macOS   | ⏳       | ⏳            | ⏳       | ⏳    | ⏳     | ⏳       | ⏳             | ✅  |
| FreeBSD / pfSense / OPNsense | BSD     | ⏳       | ⏳            | ⏳       | ⏳    | ⏳     | ⏳       | ⏳             | ✅  |
| Android                      | Android | ⏳       | ⏳            | ⏳       | ⏳    | ⏳     | ⏳       | ⏳             | ✅  |

<!-- compatibility:current:end -->

### Ce que 🟠 laisse de côté

Une capacité 🟠 est **éprouvée sur la cible, mais amputée** : le collecteur
tourne et il est testé, une part documentée de ce que la colonne recouvre n'est
simplement pas lue. Le détail vient des plafonds déclarés dans
`packages/platform/src/diagnostic-levels.ts` — il n'est pas rédigé ici, et ne
peut donc pas s'en écarter.

<!-- compatibility:caveats:start -->

**Windows 11 / 10**

- 🟠 **Matériel** — L’énumération PnP donne l’état, le constructeur et la classe de chaque périphérique, mais Windows n’expose pas la largeur négociée des liens PCIe : un lien bridé y reste indétectable. Version, date, éditeur et signature de chaque pilote sont lus ; aucune version disponible n’est établie, faute d’une source constructeur qu’un scanner hors ligne ne peut pas consulter.
- 🟠 **Stockage** — `Get-StorageReliabilityCounter` donne l’usure, la température et les compteurs d’erreurs, mais pas la table complète des attributs SMART : le stockage n’atteint donc pas la profondeur approfondie (étape 04).
- 🟠 **SMART** — `Get-StorageReliabilityCounter` donne l’usure, la température et les compteurs d’erreurs, mais pas la table complète des attributs SMART : le stockage n’atteint donc pas la profondeur approfondie (étape 04).
- 🟠 **Réseau** — La table de routage est lue (`Get-NetRoute`), mais ni les ports en écoute ni le proxy : deux des trois sondes du niveau Normale ne sont pas écrites pour Windows, et les suffixes de recherche DNS pas davantage.
- 🟠 **Sécurité** — Pare-feu, Defender et démarrage sécurisé sont lus, mais les mises à jour en attente, les comptes et les protocoles obsolètes ne le sont pas — le collecteur n’est pas écrit, la source existe.

<!-- compatibility:caveats:end -->

## Ce qu'on peut installer

La matrice ci-dessus décrit ce que les **scanners** collectent. Elle ne dit rien
de ce qu'un utilisateur peut installer, et la réponse n'est pas la même : un
scanner PowerShell et un binaire Electron n'ont ni les mêmes prérequis ni les
mêmes planchers de version.

Les mêmes symboles, avec le même sens — et une case ✅ **porte sa date
d'exécution**. C'est ce qui distingue une case cochée parce que le code compile
d'une case cochée parce que le programme a tourné ; le type l'impose, il n'y a
pas moyen de valider sans dater.

<!-- clients:table:start -->

| OS                           | Application | Ligne de commande |
| ---------------------------- | ----------- | ----------------- |
| Ubuntu 24.04                 | 🟡          | 🟡                |
| Debian 12/13                 | 🟡          | 🟡                |
| Linux Mint                   | 🟡          | 🟡                |
| Fedora                       | 🟡          | 🟡                |
| Rocky / AlmaLinux            | 🟡          | 🟡                |
| Arch / Manjaro               | 🟡          | 🟡                |
| Raspberry Pi OS              | ⏳          | ⏳                |
| Proxmox VE 8/9               | 🟡          | 🟡                |
| Windows 11 / 10              | ✅          | ✅                |
| Windows Server               | 🟡          | 🟡                |
| Windows 8.1 / 8 / 7          | ⏳          | ⏳                |
| Windows Vista / XP           | ⏳          | ⏳                |
| macOS                        | ⏳          | ⏳                |
| FreeBSD / pfSense / OPNsense | ⏳          | ⏳                |
| Android                      | ⏳          | ⏳                |

<!-- clients:table:end -->

### Pourquoi, cible par cible

<!-- clients:reasons:start -->

**Ubuntu 24.04 · Debian 12/13 · Linux Mint · Fedora · Rocky / AlmaLinux · Arch / Manjaro · Proxmox VE 8/9**

- **Application** — 🟡 implémenté, non validé sur la cible : Adaptateur écrit et couvert par des tests, jamais exécuté sur une machine Linux réelle.
- **Ligne de commande** — 🟡 implémenté, non validé sur la cible : Adaptateur écrit et couvert par des tests, jamais exécuté sur une machine Linux réelle.

**Raspberry Pi OS**

- **Application** — ⏳ prévu : La cible ARM64 est déclarée et se construit, mais aucun paquet n’a été produit sur une machine Linux, ni lancé sur un Pi.
- **Ligne de commande** — ⏳ prévu : La cible ARM64 est déclarée et se construit, mais aucun paquet n’a été produit sur une machine Linux, ni lancé sur un Pi.

**Windows 11 / 10**

- **Application** — ✅ implémenté et validé sur la cible (exécuté le 2026-08-27) : Installateur et portable produits, installés, lancés et désinstallés sur un poste Windows 11 Professionnel — les rapports survivent à la désinstallation. Windows 10 n’a pas été essayé.
- **Ligne de commande** — ✅ implémenté et validé sur la cible (exécuté le 2026-08-27) : Archive extraite hors du dépôt, audit Rapide produit puis envoyé et renvoyé sans doublon, sur un poste Windows 11 Professionnel sans élévation. Windows 10 n’a pas été essayé.

**Windows Server**

- **Application** — 🟡 implémenté, non validé sur la cible : Rien ne s’y oppose, rien n’y a été exécuté. Server Core n’a par ailleurs pas d’interface graphique.
- **Ligne de commande** — 🟡 implémenté, non validé sur la cible : Rien ne s’y oppose, rien n’y a été exécuté. Server Core n’a par ailleurs pas d’interface graphique.

**Windows 8.1 / 8 / 7 · Windows Vista / XP**

- **Application** — ⏳ prévu : Electron 43 et Node 20 exigent Windows 10 1809 : ni la fenêtre ni la ligne de commande n’y démarrent. Et le scanner Legacy n’existe pas — le lever ne suffirait donc pas.
- **Ligne de commande** — ⏳ prévu : Electron 43 et Node 20 exigent Windows 10 1809 : ni la fenêtre ni la ligne de commande n’y démarrent. Et le scanner Legacy n’existe pas — le lever ne suffirait donc pas.

**macOS · FreeBSD / pfSense / OPNsense · Android**

- **Application** — ⏳ prévu : Aucun adaptateur : une façade au-dessus d’un scanner non éprouvé donnerait une fenêtre qui échoue proprement, ce qui n’est pas un progrès.
- **Ligne de commande** — ⏳ prévu : Aucun adaptateur : une façade au-dessus d’un scanner non éprouvé donnerait une fenêtre qui échoue proprement, ce qui n’est pas un progrès.

<!-- clients:reasons:end -->

## Cible

Colonnes supplémentaires prévues par les étapes 10 et 11 de la roadmap. Elles
n'existent sur aucune cible aujourd'hui.

<!-- compatibility:target:start -->

| OS                           | Scanner | Matériel | Logiciel      | Stockage | SMART | Réseau | Sécurité | Virtualisation | Monitoring | Benchmark             | IA  |
| ---------------------------- | ------- | -------- | ------------- | -------- | ----- | ------ | -------- | -------------- | ---------- | --------------------- | --- |
| Ubuntu 24.04                 | Linux   | 🟡       | ✅ apt · snap | ✅       | 🟡    | ✅     | ✅       | ✅ Docker      | ✅         | ✅ CPU · RAM · disque | ✅  |
| Debian 12/13                 | Linux   | ✅       | ✅            | ✅       | ✅    | ✅     | ✅       | ✅             | ✅         | 🟡                    | ✅  |
| Linux Mint                   | Linux   | 🟡       | 🟡            | 🟡       | 🟡    | 🟡     | 🟡       | 🟡             | 🟡         | 🟡                    | ✅  |
| Fedora                       | Linux   | 🟡       | ✅            | 🟡       | 🟡    | 🟡     | 🟡       | 🟡             | ✅         | 🟡                    | ✅  |
| Rocky / AlmaLinux            | Linux   | 🟡       | ✅            | 🟡       | 🟡    | 🟡     | 🟡       | 🟡             | ✅         | 🟡                    | ✅  |
| Arch / Manjaro               | Linux   | 🟡       | ✅            | 🟡       | 🟡    | 🟡     | 🟡       | 🟡             | ✅         | 🟡                    | ✅  |
| Raspberry Pi OS              | Linux   | 🟡       | 🟡            | 🟡       | 🟡    | 🟡     | 🟡       | 🟡             | 🟡         | 🟡                    | ✅  |
| Proxmox VE 8/9               | Proxmox | ✅       | ✅            | ✅       | ✅    | ✅     | ✅       | ✅ Proxmox     | ✅         | ✅ CPU · RAM · disque | ✅  |
| Windows 11 / 10              | Modern  | 🟠       | ✅            | 🟠       | 🟠    | 🟠     | 🟠       | ✅             | ✅         | 🟠                    | ✅  |
| Windows Server               | Modern  | 🟡       | 🟡            | 🟡       | 🟡    | 🟡     | 🟡       | 🟡             | 🟡         | 🟡                    | ✅  |
| Windows 8.1 / 8 / 7          | Legacy  | —        | —             | —        | —     | —      | —        | —              | —          | —                     | ✅  |
| Windows Vista / XP           | Minimal | ⏳       | ⏳            | ⏳       | ❌    | ⏳     | ⏳       | n/a            | ⏳         | ⏳                    | ✅  |
| macOS                        | macOS   | ⏳       | ⏳            | ⏳       | ⏳    | ⏳     | ⏳       | ⏳             | ⏳         | ⏳                    | ✅  |
| FreeBSD / pfSense / OPNsense | BSD     | ⏳       | ⏳            | ⏳       | ⏳    | ⏳     | ⏳       | ⏳             | ⏳         | ⏳                    | ✅  |
| Android                      | Android | ⏳       | ⏳            | ⏳       | ⏳    | ⏳     | ⏳       | ⏳             | ⏳         | ⏳                    | ✅  |

<!-- compatibility:target:end -->

### État réel de la validation

Le scanner Linux est **écrit une seule fois** pour toutes les distributions :
il n'a pas de branche par distribution, il s'adapte aux outils présents. Les
différences entre distributions se limitent au gestionnaire de paquets et au
moteur de pare-feu.

Ce qui a été **réellement exécuté** à ce jour :

| Contexte                                                              | Résultat                                                                                                                                                                                                                             |
| --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Ubuntu 24.04 (WSL2), sans privilèges, sans `dmidecode` ni `smartctl`  | Scan complet, JSON accepté par `validateReport()`, aucune erreur shell                                                                                                                                                               |
| Idem avec `--anonymize`                                               | Aucune fuite du nom de machine ni des adresses MAC                                                                                                                                                                                   |
| Plateforme locale (API + Web + PostgreSQL 17)                         | Ingestion, historique, comparaison, partage et rapport Web validés                                                                                                                                                                   |
| Analyse IA locale via API                                             | Génération structurée validée (`quick` et `full`)                                                                                                                                                                                    |
| Analyse de sorties `dmidecode` et `smartctl` (ATA et NVMe) réelles    | Validée par fixtures                                                                                                                                                                                                                 |
| Ubuntu 24.04, profil `--full`                                         | Paquets apt et snap, gestionnaires, runtimes, services et modules noyau collectés et validés contre le schéma                                                                                                                        |
| **Debian 13 sur machine physique, hôte Proxmox VE 9.2.4, `root`**     | Profil `--full --monitor`, `dmidecode` et `smartctl` présents : BIOS, barrettes, SMART réel (`PASSED`, 14 230 h), 800 paquets, 46 ports en écoute, nœud Proxmox avec 7 LXC, 1 VM et 5 stockages. JSON accepté par `validateReport()` |
| **Fedora 44, Rocky Linux 10, Arch Linux, Debian 12** (conteneurs LXC) | Profil `--full --monitor` : `dnf`/`rpm`, `pacman` et `apt`/`dpkg` exercés, observation dans la durée relevée. JSON accepté par `validateReport()`                                                                                    |
| **Windows 11 Professionnel, PowerShell 5.1, administrateur**          | `npm run validate:windows` : les six profils ont produit un rapport accepté par `validateReport()`, et les neuf domaines ont livré une valeur réelle plutôt qu'un marqueur                                                           |

Cette campagne a fait apparaître **six défauts qu'aucun test ne pouvait voir**,
tous invisibles sur le seul environnement validé jusque-là — un WSL2 sans
`lspci`, sans `lsusb` et sans service en écoute. Le plus coûteux : `run_cmd` ne
terminait pas sa sortie par un saut de ligne, et **toute boucle `while read` qui
la consommait perdait son dernier élément**. Sur l'hôte Proxmox, le port perdu
était le 8006 — l'interface d'administration, donc le service le plus exposé de
la machine. Détail dans le [CHANGELOG](CHANGELOG.md).

**Ce qu'un conteneur LXC ne valide pas.** Il partage le noyau de l'hôte : ni
`dmidecode`, ni disque physique, ni compteur SMART, et son pare-feu est celui de
l'hôte. Faire tourner le scanner dans un conteneur Fedora valide donc `dnf` et
l'observation — c'est-à-dire ce qui distingue réellement une distribution d'une
autre du point de vue du scanner — mais **rien de matériel**. C'est pourquoi ces
trois lignes ne portent un ✅ que sur deux colonnes.

Ce qui **n'a pas encore été exécuté sur la cible** : Linux Mint et Raspberry Pi
OS, faute de modèle LXC (l'un est une distribution de bureau, l'autre vise ARM) ;
le banc d'essai sur Debian et Proxmox, parce qu'il charge volontairement une
machine qui héberge de la production ; et Windows Server.

### Windows

Le scanner Windows vit dans `scanners/windows`, avec son manifeste, son analyse
statique et sa suite de tests.

Il collecte matériel, stockage, santé SMART, réseau, sécurité, **inventaire
logiciel**, **virtualisation**, **observation dans la durée** et banc d'essai.
Les quatre domaines en gras sont les plus récents ; les deux derniers de cette
liste étaient déclarés absents par cette matrice alors que le code les
produisait déjà — une dérive corrigée depuis.

Trois limites sont **volontaires** et déclarées dans
`SCANNER_SECTION_CAPS.windows` :

- `winget` est constaté mais pas interrogé : `winget list` ne publie qu'un
  tableau destiné à l'œil, tronqué à la largeur de la console. Un inventaire
  tiré de là serait faux sur une console étroite, ce qui vaut moins que pas
  d'inventaire ;
- le sous-système Linux (WSL) n'est pas inventorié : ses distributions ne sont
  ni des machines virtuelles ni des conteneurs au sens du schéma, et les y
  ranger les rendrait comparables à ce qu'elles ne sont pas ;
- le banc d'essai publie des **indices WinSAT** pour le processeur, la mémoire
  et le GPU — comparables entre machines Windows, jamais à un débit — et un
  débit réel pour le seul stockage.

**Windows 11 / 10 est validé ; Windows Server ne l'est pas.** La campagne
`npm run validate:windows` a tourné sur un poste Windows 11 Professionnel en
Windows PowerShell 5.1 — la version minimale annoncée, pas PowerShell 7 — en
session administrateur. Les six profils ont produit un rapport accepté par
`validateReport()`, et les neuf domaines ont livré une valeur réelle plutôt
qu'un marqueur.

Trois défauts ont dû être corrigés pour y parvenir, tous invisibles hors d'une
exécution réelle. Le plus large : `network.interfaces[].ipv4` sortait en objet
dès qu'une carte portait **une seule** adresse — c'est-à-dire le cas ordinaire —
et tout rapport Windows était donc refusé.

**Windows Server n'hérite pas de cette validation**, et la différence n'est pas
théorique : Server Core n'a pas `Get-AppxPackage`, WinSAT n'y est pas installé
par défaut, et les profils de pare-feu diffèrent. Ni l'inventaire des
applications empaquetées ni le banc d'essai n'y sont acquis. La ligne reste 🟡
jusqu'à ce que la campagne y tourne.

La campagne se relance avec `npm run validate:windows`, depuis une console
administrateur sur la machine cible. La suite de tests, elle, n'exécute que le
profil Rapide et ne prouve donc rien au-delà de trois colonnes. Procédure dans
docs/technique/DEVELOPMENT.md.

Aucun scanner Windows _Legacy_ ni _Minimal_ n'existe : les lignes
correspondantes restent `—` et `⏳`.

**Et cela ne dit rien de ce qu'on peut installer.** Un scanner qui tournerait sur
Windows 7 ne rendrait pas l'application disponible pour autant : Electron 43 et
Node 20 exigent Windows 10 1809. Les deux questions sont séparées depuis le
2026-08-27, et la seconde a son propre tableau — voir
[« Ce qu'on peut installer »](#ce-quon-peut-installer).

## Niveaux de scanner

| Niveau  | Cible                                      | Technologies                                  |
| ------- | ------------------------------------------ | --------------------------------------------- |
| Linux   | Distributions modernes avec systemd ou non | Bash, outils système standards                |
| Proxmox | Proxmox VE (détecté automatiquement)       | `pveversion`, `pvesh`, `qm`, `pct`, `pvesm`   |
| Modern  | Windows 10/11, Windows Server 2016+        | PowerShell 5.1+, CIM/WMI                      |
| Legacy  | Windows 7/8/8.1                            | WMI, WMIC, registre, PowerShell si disponible |
| Minimal | Windows Vista/XP                           | WMIC, registre, VBScript, COM                 |

## Profils de scan Linux / Proxmox

| Profil     | Statut | Couverture principale                                                               |
| ---------- | ------ | ----------------------------------------------------------------------------------- |
| `quick`    | ✅     | résumé machine rapide : CPU, mémoire, GPU, stockage, réseau, sécurité               |
| `standard` | ✅     | audit général read-only : matériel, stockage, réseau, sécurité, virtualisation      |
| `full`     | ✅     | `standard` + inventaire logiciel (paquets, services, mises à jour selon plateforme) |
| `stress`   | ✅     | `full` + **banc d'essai** : CPU, mémoire, disque, et GPU si `glmark2` est là        |
| `security` | ✅     | alias orienté sécurité, basé sur le profil rapide avec collecte réseau et sécurité  |

## Dépendances optionnelles côté Linux

Aucune n'est obligatoire. Leur absence dégrade la collecte de façon explicite
(`NOT_AVAILABLE`, avec le nom de l'outil manquant) plutôt que silencieuse.

| Outil              | Apporte                                | Sans lui                        |
| ------------------ | -------------------------------------- | ------------------------------- |
| `dmidecode`        | Carte mère, BIOS, modules RAM, châssis | Champs `NOT_AVAILABLE`          |
| `smartctl`         | Santé SMART / NVMe                     | Section santé disque absente    |
| `lspci` / `lsusb`  | Périphériques PCI et USB               | Inventaire périphériques réduit |
| `lscpu`            | Détail CPU                             | Repli sur `/proc/cpuinfo`       |
| `ip` / `ss`        | Réseau détaillé, ports en écoute       | Repli sur `/sys` et `/proc`     |
| `iw`               | Wi-Fi (SSID uniquement)                | Section Wi-Fi `NOT_AVAILABLE`   |
| `zpool`            | Pools ZFS                              | Pools non inventoriés           |
| `docker`           | Inventaire des conteneurs              | Section Docker absente          |
| `snap` / `flatpak` | Applications hors gestionnaire système | Applications non inventoriées   |
| `lsmod`            | Modules noyau (pilotes Linux)          | Section pilotes absente         |
| `openssl`          | Banc d'essai CPU (AES-128-CBC)         | Mesure CPU indisponible         |
| `fio`              | Banc d'essai disque en accès aléatoire | Mesure aléatoire indisponible   |
| `glmark2`          | Banc d'essai GPU                       | Mesure GPU indisponible         |

## Privilèges

| Contexte                | Résultat                                                                       |
| ----------------------- | ------------------------------------------------------------------------------ |
| `root` / Administrateur | Collecte complète selon les outils présents                                    |
| Utilisateur standard    | Collecte partielle ; les champs inaccessibles sont marqués `PERMISSION_DENIED` |

Le scanner ne demande jamais d'élévation de privilèges de lui-même et
fonctionne, en mode dégradé, sans privilège.

## Compatibilité de la plateforme

Cette section concerne la **plateforme SysAudit** (API, base, interface Web,
comparaison, partage et analyse IA), indépendamment de l'OS scanné.

| Fonctionnalité                        | Statut | Remarques                                                                   |
| ------------------------------------- | ------ | --------------------------------------------------------------------------- |
| Ingestion et validation du rapport    | ✅     | JSON versionné validé côté API                                              |
| Analyse déterministe et scores        | ✅     | 55 règles, score global + 8 domaines                                        |
| Historique par machine                | ✅     | persistance PostgreSQL, scans successifs relus dans l'interface             |
| Comparaison entre deux audits         | ✅     | diff matériel / logiciel exposé via API et Web                              |
| Partage par lien temporaire           | ✅     | jetons révocables, page Web `/s/[token]`                                    |
| Export JSON / HTML / texte            | ✅     | routes Web dédiées + renderer autonome                                      |
| Analyse IA locale facultative         | ✅     | modes `quick` et `full`, réponse JSON stricte validée côté API              |
| IA de recommandation cross-plateforme | 🟡     | fonctionne sur tout rapport valide, mais surtout pensée pour le hardware PC |

## Plateforme

| Composant  | Version testée                                                   |
| ---------- | ---------------------------------------------------------------- |
| Node.js    | 22 (CI), 24 (développement local)                                |
| PostgreSQL | 17                                                               |
| Docker     | Image `node:22-alpine`, testée au démarrage contre PostgreSQL 17 |
