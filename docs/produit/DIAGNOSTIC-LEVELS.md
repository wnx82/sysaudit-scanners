# Niveaux de diagnostic

SysAudit expose quatre niveaux. Ils ne diffèrent pas seulement par leur durée :
chacun collecte un ensemble de sections précis, à une profondeur précise.

> **Ce qu'un niveau ne collecte pas** est déclaré dans le rapport avec le
> motif `NOT_COLLECTED` et le niveau qui l'aurait collecté. Voir
> `../analyse/COUVERTURE.md`.

> **Ce document n'est pas saisi à la main.** Sa source de vérité est
> `packages/platform/src/diagnostic-levels.ts`. Régénérer avec
> `npm run docs:levels` ; un test échoue si le fichier a dérivé.

## Les quatre niveaux

<!-- levels:overview:start -->

| Niveau               | Option     | URL          | Durée cible     | Privilèges  | Charge la machine |
| -------------------- | ---------- | ------------ | --------------- | ----------- | ----------------- |
| Rapide (`quick`)     | `--quick`  | `/audit/l/q` | 30 s à 2 min    | recommandés | non               |
| Normale (`standard`) | _(défaut)_ | `/audit/l`   | 2 min à 5 min   | requis      | non               |
| Complète (`full`)    | `--full`   | `/audit/l/f` | 5 min à 12 min  | requis      | non               |
| Poussée (`stress`)   | `--stress` | `/audit/l/s` | 12 min à 45 min | requis      | **oui**           |

<!-- levels:overview:end -->

<!-- levels:summaries:start -->

- **Rapide** (30 s à 2 min) — Inventaire essentiel sans dépendance lourde : identité machine, résumé CPU/RAM/stockage, réseau et premiers signaux de sécurité.
- **Normale** (2 min à 5 min) — Inventaire matériel complet, santé SMART principale, capteurs, réseau et sécurité. Le point de départ de la plupart des audits.
- **Complète** (5 min à 12 min) — Ajoute l’inventaire logiciel, les pilotes, les périphériques USB et la table SMART détaillée. La meilleure base pour les règles et l’analyse IA.
- **Poussée** (12 min à 45 min) — Tout le niveau Complète, plus un banc d’essai qui sollicite volontairement la machine sous surveillance thermique, dont dix minutes de charge soutenue.

<!-- levels:summaries:end -->

## Ce que chaque niveau collecte

<!-- levels:legend:start -->

- — non collectée
- ◔ résumé
- ◕ complète
- ● approfondie

<!-- levels:legend:end -->

<!-- levels:plan:start -->

| Section                      | Rapide | Normale | Complète | Poussée |
| ---------------------------- | ------ | ------- | -------- | ------- |
| Identité machine             | ◕      | ◕       | ◕        | ◕       |
| Système d’exploitation       | ◕      | ◕       | ◕        | ◕       |
| Carte mère                   | ◕      | ◕       | ◕        | ◕       |
| BIOS / UEFI                  | ◕      | ◕       | ◕        | ◕       |
| Processeur                   | ◔      | ◕       | ◕        | ◕       |
| Mémoire                      | ◔      | ◕       | ◕        | ◕       |
| Carte graphique              | ◔      | ◕       | ◕        | ◕       |
| Audio                        | ◔      | ◔       | ◔        | ◔       |
| Capteurs et températures     | ◕      | ◕       | ●        | ●       |
| Alimentation et batterie     | ◕      | ◕       | ◕        | ◕       |
| Stockage et santé disque     | ◔      | ◕       | ●        | ●       |
| Réseau                       | ◔      | ◕       | ◕        | ◕       |
| Périphériques PCI/USB        | —      | ◕       | ◕        | ◕       |
| Pilotes                      | —      | ◕       | ◕        | ◕       |
| Logiciels et services        | —      | ◕       | ◕        | ◕       |
| Éléments au démarrage        | —      | ◔       | ◔        | ◔       |
| Sécurité                     | ◔      | ◕       | ◕        | ◕       |
| Virtualisation et conteneurs | ◔      | ◕       | ◕        | ◕       |
| Stabilité observée           | ◔      | ◕       | ◕        | ◕       |
| Séquence de démarrage        | ◕      | ◕       | ◕        | ◕       |
| Séquence d’arrêt             | ◕      | ◕       | ◕        | ◕       |
| Historique des incidents     | —      | ◕       | ◕        | ◕       |
| Banc d’essai                 | —      | —       | —        | ◕       |

<!-- levels:plan:end -->

<!-- levels:notes:start -->

- **Processeur** — Le résumé n’échantillonne pas la charge et n’interroge pas le SMBIOS pour le socket.
- **Mémoire** — Le résumé ne lit pas les modules DIMM un par un (SMBIOS, privilèges requis).
- **Carte graphique** — Le résumé n’énumère pas les sorties d’affichage connectées.
- **Stockage et santé disque** — Le résumé n’interroge pas SMART ni les ensembles RAID/ZFS/LVM ; l’approfondie ajoute la table complète des attributs SMART.
- **Réseau** — Le résumé ne liste ni les ports en écoute, ni les routes, ni le proxy.
- **Périphériques PCI/USB** — Le résumé énumère le bus PCI ; la collecte complète ajoute le bus USB.
- **Sécurité** — Le résumé se limite au pare-feu et au démarrage sécurisé : ni mises à jour en attente, ni comptes, ni durcissement.
- **Virtualisation et conteneurs** — Le résumé compte les invités sans détailler leur configuration.
- **Stabilité observée** — Le résumé lit l’uptime, les unités en échec et le noyau souillé ; la collecte complète y ajoute les compteurs d’incidents par catégorie, qui exigent de parcourir le journal.

<!-- levels:notes:end -->

## Ce que les scanners atteignent réellement

La matrice ci-dessus est un contrat. Un scanner peut être **en retrait** —
jamais en avance — et chaque écart porte son motif. Le contrat est vérifié par
`packages/platform/src/diagnostic-levels-contract.test.ts`, qui relit les tables
embarquées dans les scanners.

### Linux / Proxmox

<!-- levels:plan:linux:start -->

| Section                      | Rapide | Normale | Complète | Poussée |
| ---------------------------- | ------ | ------- | -------- | ------- |
| Identité machine             | ◕      | ◕       | ◕        | ◕       |
| Système d’exploitation       | ◕      | ◕       | ◕        | ◕       |
| Carte mère                   | ◕      | ◕       | ◕        | ◕       |
| BIOS / UEFI                  | ◕      | ◕       | ◕        | ◕       |
| Processeur                   | ◔      | ◕       | ◕        | ◕       |
| Mémoire                      | ◔      | ◕       | ◕        | ◕       |
| Carte graphique              | ◔      | ◕       | ◕        | ◕       |
| Audio                        | ◔      | ◔       | ◔        | ◔       |
| Capteurs et températures     | ◕      | ◕       | ●        | ●       |
| Alimentation et batterie     | ◕      | ◕       | ◕        | ◕       |
| Stockage et santé disque     | ◔      | ◕       | ●        | ●       |
| Réseau                       | ◔      | ◕       | ◕        | ◕       |
| Périphériques PCI/USB        | —      | ◕       | ◕        | ◕       |
| Pilotes                      | —      | ◕       | ◕        | ◕       |
| Logiciels et services        | —      | ◕       | ◕        | ◕       |
| Éléments au démarrage        | —      | ◔       | ◔        | ◔       |
| Sécurité                     | ◔      | ◕       | ◕        | ◕       |
| Virtualisation et conteneurs | ◔      | ◕       | ◕        | ◕       |
| Stabilité observée           | ◔      | ◕       | ◕        | ◕       |
| Séquence de démarrage        | ◕      | ◕       | ◕        | ◕       |
| Séquence d’arrêt             | ◕      | ◕       | ◕        | ◕       |
| Historique des incidents     | —      | ◕       | ◕        | ◕       |
| Banc d’essai                 | —      | —       | —        | ◕       |

<!-- levels:plan:linux:end -->

<!-- levels:caps:linux:start -->

_Linux / Proxmox atteint la matrice à tous les niveaux._

<!-- levels:caps:linux:end -->

### Windows

<!-- levels:plan:windows:start -->

| Section                      | Rapide | Normale | Complète | Poussée |
| ---------------------------- | ------ | ------- | -------- | ------- |
| Identité machine             | ◕      | ◕       | ◕        | ◕       |
| Système d’exploitation       | ◕      | ◕       | ◕        | ◕       |
| Carte mère                   | ◕      | ◕       | ◕        | ◕       |
| BIOS / UEFI                  | ◕      | ◕       | ◕        | ◕       |
| Processeur                   | ◔      | ◕       | ◕        | ◕       |
| Mémoire                      | ◔      | ◕       | ◕        | ◕       |
| Carte graphique              | ◔      | ◕       | ◕        | ◕       |
| Audio                        | ◔      | ◔       | ◔        | ◔       |
| Capteurs et températures     | ◕      | ◕       | ●        | ●       |
| Alimentation et batterie     | ◕      | ◕       | ◕        | ◕       |
| Stockage et santé disque     | ◔      | ◕       | ◕        | ◕       |
| Réseau                       | ◔      | ◔       | ◔        | ◔       |
| Périphériques PCI/USB        | —      | ◔       | ◔        | ◔       |
| Pilotes                      | —      | ◔       | ◔        | ◔       |
| Logiciels et services        | —      | ◕       | ◕        | ◕       |
| Éléments au démarrage        | —      | ◔       | ◔        | ◔       |
| Sécurité                     | ◔      | ◔       | ◔        | ◔       |
| Virtualisation et conteneurs | ◔      | ◕       | ◕        | ◕       |
| Stabilité observée           | ◔      | ◕       | ◕        | ◕       |
| Séquence de démarrage        | ◕      | ◕       | ◕        | ◕       |
| Séquence d’arrêt             | ◕      | ◕       | ◕        | ◕       |
| Historique des incidents     | —      | ◕       | ◕        | ◕       |
| Banc d’essai                 | —      | —       | —        | ◔       |

<!-- levels:plan:windows:end -->

<!-- levels:caps:windows:start -->

- **Stockage et santé disque** — plafonnée à « complète » : `Get-StorageReliabilityCounter` donne l’usure, la température et les compteurs d’erreurs, mais pas la table complète des attributs SMART : le stockage n’atteint donc pas la profondeur approfondie (étape 04).
- **Réseau** — plafonnée à « résumé » : La table de routage est lue (`Get-NetRoute`), mais ni les ports en écoute ni le proxy : deux des trois sondes du niveau Normale ne sont pas écrites pour Windows, et les suffixes de recherche DNS pas davantage.
- **Périphériques PCI/USB** — plafonnée à « résumé » : L’énumération PnP donne l’état, le constructeur et la classe de chaque périphérique, mais Windows n’expose pas la largeur négociée des liens PCIe : un lien bridé y reste indétectable.
- **Pilotes** — plafonnée à « résumé » : Version, date, éditeur et signature de chaque pilote sont lus ; aucune version disponible n’est établie, faute d’une source constructeur qu’un scanner hors ligne ne peut pas consulter.
- **Sécurité** — plafonnée à « résumé » : Pare-feu, Defender et démarrage sécurisé sont lus, mais les mises à jour en attente, les comptes et les protocoles obsolètes ne le sont pas — le collecteur n’est pas écrit, la source existe.
- **Banc d’essai** — plafonnée à « résumé » : Le stockage est mesuré en débit réel, mais le processeur, la mémoire et le GPU ne le sont qu’en indices WinSAT — comparables entre machines Windows, pas à un débit. Aucune charge soutenue, aucun relevé thermique : Windows n’expose pas de capteur fiable sans composant tiers.

<!-- levels:caps:windows:end -->

## Ce qui n'est pas piloté par le niveau

Trois sections échappent à la matrice, et ce n'est pas un oubli :

- `monitoring` dépend de `--monitor <secondes>`, une demande explicite
  orthogonale au niveau ;
- `firmware` n'est produite par aucun scanner : elle exigerait une source
  constructeur que le scanner n'interroge pas ;
- `capabilities` et `collection` décrivent le scan lui-même et sont toujours
  produites — sans elles, une section absente serait indéchiffrable.

## Comment une donnée non collectée se dit

Une section ignorée à cause du niveau apparaît dans `collection.skippedSections`,
et un champ non collecté porte le marqueur `NOT_COLLECTED` avec, en détail, le
niveau qui l'aurait collecté.

C'est la différence entre « ce disque n'a pas de compteur SMART » et « ce niveau
ne lit pas SMART ». Sans elle, un audit Rapide se lirait comme un audit Complète
dont la moitié du matériel aurait échoué.
