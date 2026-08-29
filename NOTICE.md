<!--
SPDX-FileCopyrightText: 2026 SysAudit
SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available
-->

# NOTICE

**SysAudit** — audit et diagnostic système.
Copyright © 2026 **eKreativ.be**. Tous droits réservés.

« SysAudit », « SysAudit.me » et le logo associé sont des marques d'eKreativ.be.
Leur usage n'est pas concédé par la mise à disposition des sources.

## Ce dépôt n'est pas le produit complet

SysAudit est distribué en deux parties, et cette distinction n'est pas
accidentelle : elle est la raison pour laquelle le dépôt peut être ouvert à la
lecture sans ouvrir le produit à la duplication.

**Publié ici — ce qui tourne sur la machine auditée, et ce qu'elle produit :**

| Composant                | Pourquoi il est public                                                    |
| ------------------------ | ------------------------------------------------------------------------- |
| `scanners/`              | Vous exécutez ces scripts sur vos machines. Vous devez pouvoir les lire.  |
| `packages/report-schema` | Le format de rapport est un contrat : il vous permet de relire vos audits |
| `packages/shared`        | Valeurs inconnues, anonymisation, détection de secrets                    |
| `packages/platform`      | Taxonomie des OS et matrice de compatibilité des scanners publiés         |
| `docs/`                  | Mode d'emploi des composants ci-dessus                                    |

**Non publié — propriétaire :** le moteur d'analyse et son scoring, la base
matérielle et l'appariement visuel, le moteur de rendu, le moteur d'audit,
l'API, l'interface Web, les applications de bureau et en ligne de commande,
l'administration, le schéma et les migrations de base de données, ainsi que
l'ensemble de l'infrastructure d'exploitation.

Un clone de ce dépôt ne permet donc ni de recalculer un SysScore, ni de
reproduire la plateforme. C'est délibéré.

## Droits

Aucune licence open source n'est concédée. Les conditions exactes de lecture,
d'exécution et de citation sont dans [LICENSE](LICENSE).

## Composants tiers

Les dépendances conservent leurs propres licences : voir
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Les scanners publiés lisent également des sources de données tierces sous leurs
licences respectives (notamment `pci.ids` sous BSD-3-Clause et la base de
disques de smartmontools sous GPL-2.0-or-later). Ces données ne sont pas
redistribuées dans ce dépôt : elles sont lues sur la machine auditée, où elles
sont déjà installées.
