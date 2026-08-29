<!--
SPDX-FileCopyrightText: 2026 SysAudit
SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available
-->

# Documentation — composants publiés

Cette documentation couvre ce que ce dépôt contient : les **scanners**, le
**format de rapport** et les décisions d'architecture qui les expliquent.

La documentation du service en ligne — comptes, organisations, analyse IA,
administration, exploitation — n'est pas ici, parce que les composants
correspondants ne sont pas publiés. Voir [NOTICE.md](../NOTICE.md) pour la
frontière exacte, et [sysaudit.me](https://sysaudit.me) pour le service.

## [`scanners/`](scanners/) — collecter sur une machine

| Fichier                                                             | Ce qu'il dit                                                               |
| ------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| [COMMANDES-PAR-OS.md](scanners/COMMANDES-PAR-OS.md)                 | La commande de scan, système par système                                   |
| [LINUX.md](scanners/LINUX.md)                                       | Scanner Linux / Proxmox : commandes et privilèges                          |
| [WINDOWS.md](scanners/WINDOWS.md)                                   | Scanner Windows et sa distribution                                         |
| [PROXMOX.md](scanners/PROXMOX.md)                                   | Ce que Proxmox VE ajoute, et ce qu'il exige                                |
| [MACOS-BSD.md](scanners/MACOS-BSD.md)                               | macOS, FreeBSD, pfSense et OPNsense — expérimental                         |
| [ANDROID.md](scanners/ANDROID.md)                                   | Android via Termux — expérimental                                          |
| [DEPENDENCIES.md](scanners/DEPENDENCIES.md)                         | Outils externes : ce qu'ils apportent, ce qui se passe sans eux _(généré)_ |
| [COMPATIBILITY-VALIDATION.md](scanners/COMPATIBILITY-VALIDATION.md) | Comment valider la matrice de compatibilité                                |
| [TROUBLESHOOTING.md](scanners/TROUBLESHOOTING.md)                   | « Pourquoi cette donnée n'est-elle pas là ? »                              |

La matrice de compatibilité elle-même est à la racine :
[COMPATIBILITY.md](../COMPATIBILITY.md). Elle est **générée** depuis
`packages/platform` — un test échoue si elle dérive de sa source.

## [`format-rapport/`](format-rapport/) — le contrat

Le format est publié pour une raison précise : un rapport produit aujourd'hui
doit rester lisible sans SysAudit, y compris dans dix ans, y compris si vous
n'utilisez plus le service.

| Fichier                                                           | Ce qu'il dit                                       |
| ----------------------------------------------------------------- | -------------------------------------------------- |
| [REPORT_SCHEMA.md](format-rapport/REPORT_SCHEMA.md)               | Structure du rapport, section par section          |
| [REPORT_SCHEMA_FIELDS.md](format-rapport/REPORT_SCHEMA_FIELDS.md) | Chaque champ, son sens et sa provenance _(généré)_ |
| [VERSIONING.md](format-rapport/VERSIONING.md)                     | Comment le format évolue sans casser l'existant    |
| [PROTOCOLE-BANC-ESSAI.md](format-rapport/PROTOCOLE-BANC-ESSAI.md) | Protocole des mesures de performance               |

## [`examples/sanitized/`](examples/sanitized/) — des rapports à lire

Deux rapports valides, **construits** et non dérivés d'une machine réelle.
Un test refuse qu'ils cessent de valider, ou qu'une valeur identifiante y entre.

## [`produit/`](produit/) — ce que le scanner collecte

| Fichier                                              | Ce qu'il dit                                            |
| ---------------------------------------------------- | ------------------------------------------------------- |
| [DIAGNOSTIC-LEVELS.md](produit/DIAGNOSTIC-LEVELS.md) | Les quatre niveaux et ce que chacun collecte _(généré)_ |

## [`adr/`](adr/) — pourquoi c'est fait comme ça

Les [décisions d'architecture](adr/README.md), avec leur contexte et leurs
conséquences. Certaines concernent des composants non publiés : elles restent
ici parce qu'elles expliquent des choix visibles depuis l'extérieur — la
stratégie mobile, la politique de dépendances externes, le versionnement du
format.

## [`antivirus/`](antivirus/)

[avast-false-positive.md](antivirus/avast-false-positive.md) — pourquoi un
antivirus signale parfois le scanner Windows, et quoi faire. À lire avant de
supposer une compromission.

## [`offline-audit/`](offline-audit/)

[README.md](offline-audit/README.md) — auditer une machine sans accès réseau.
