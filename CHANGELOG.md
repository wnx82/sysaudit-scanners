<!--
SPDX-FileCopyrightText: 2026 SysAudit
SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available
-->

# Journal des modifications

Ce journal couvre les **composants publiés** : les scanners, le format de
rapport et leur documentation. Les évolutions des composants propriétaires n'y
figurent pas.

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/), et le
versionnement [SemVer](https://semver.org/lang/fr/). Le numéro de version est
celui de SysAudit dans son ensemble : un dépôt public qui aurait sa propre
numérotation rendrait impossible de dire quel scanner produit quel rapport.

Ce texte est écrit à la main, mais sa version la plus récente est **vérifiée** :
la construction de cette surface refuse de produire un dépôt dont le journal
annoncerait une autre version que celle du `package.json`.

## [0.158.0] — 2026-08-29

Première publication.

### Ajouté

- Scanners **Linux** et **Windows** (stables), **macOS**, **BSD** et
  **Android** (expérimentaux) — lecture seule aux niveaux Rapide et Normale.
- `packages/report-schema` — le format de rapport : définition Zod, JSON Schema
  généré, migrations de version et politique de compatibilité.
- `packages/shared` — valeurs inconnues, anonymisation, détection de secrets.
- `packages/platform` — taxonomie des systèmes et matrice de compatibilité,
  source de `COMPATIBILITY.md`.
- Deux rapports d'exemple **synthétiques**, vérifiés valides et anonymes par un
  test à chaque exécution de la suite.
- Documentation des scanners, du format et des décisions d'architecture.

### Ce que ce dépôt ne contient pas

Le moteur d'analyse et son scoring, la base matérielle, le moteur de rendu,
l'API, l'interface Web, les applications et l'infrastructure. C'est délibéré :
voir [NOTICE.md](NOTICE.md).

Ce dépôt ne reprend pas non plus l'historique du développement de SysAudit. Il
démarre sur une base propre — un historique privé de plusieurs milliers de
commits ne se publie pas rétroactivement sans risquer d'y avoir laissé quelque
chose.
