<!--
SPDX-FileCopyrightText: 2026 SysAudit
SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available
-->

# Composants tiers

Dépendances de la **surface publiée** (`scanners/`, `packages/shared`,
`packages/report-schema`, `packages/platform`) et de son outillage de
vérification. Les composants non publiés ont leurs propres dépendances, qui ne
sont pas listées ici.

Le texte intégral de chaque licence accompagne le paquet correspondant dans
`node_modules/<paquet>/LICENSE` après `npm install`.

## Exécution

| Paquet | Version | Licence | Rôle                                          |
| ------ | ------- | ------- | --------------------------------------------- |
| `zod`  | ^4.4.3  | MIT     | Définition et validation du schéma de rapport |

C'est la seule dépendance d'exécution. Les scanners, eux, n'en ont aucune : ils
sont écrits en Bash et en PowerShell et doivent tourner sur une machine sans
Node.js.

## Développement et vérification

| Paquet                | Version | Licence    | Rôle                                |
| --------------------- | ------- | ---------- | ----------------------------------- |
| `typescript`          | ^6.0.2  | Apache-2.0 | Compilation                         |
| `typescript-native`   | ^7.0.2  | Apache-2.0 | Vérification de types               |
| `typescript-eslint`   | ^8.66.0 | MIT        | Règles de lint TypeScript           |
| `eslint`              | ^10.8.0 | MIT        | Lint                                |
| `@eslint/js`          | ^10.0.1 | MIT        | Règles ESLint de base               |
| `globals`             | ^17.9.0 | MIT        | Variables globales connues d'ESLint |
| `prettier`            | ^3.9.6  | MIT        | Formatage                           |
| `vitest`              | ^4.1.10 | MIT        | Tests                               |
| `@vitest/coverage-v8` | ^4.1.10 | MIT        | Couverture                          |
| `@types/node`         | ^26.1.2 | MIT        | Types Node.js                       |
| `ajv`                 | ^8.20.0 | MIT        | Validation du JSON Schema publié    |
| `ajv-formats`         | ^3.0.1  | MIT        | Formats pour Ajv                    |

## Outils externes des scanners

Les scanners appellent des utilitaires **déjà présents** sur la machine auditée
(`dmidecode`, `smartctl`, `lspci`, `sensors`, `Get-CimInstance`…). Ils ne sont
ni redistribués, ni installés sans accord explicite de l'administrateur.
`docs/scanners/DEPENDENCIES.md` les recense, avec leur licence et ce que leur
absence coûte.

## Compatibilité de la distribution retenue

SysAudit est distribué en **source-available**, sans licence open source. Aucune
des licences ci-dessus n'y fait obstacle : MIT, Apache-2.0 et BSD sont
permissives et n'imposent que la conservation des mentions, assurée par ce
fichier. Aucune dépendance copyleft (GPL, AGPL, MPL) n'entre dans la surface
publiée.
