<!--
SPDX-FileCopyrightText: 2026 SysAudit
SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available
-->

# Exemples de rapports

Deux rapports conformes au schéma courant, destinés à être lus, parsés et
utilisés comme référence.

| Fichier                                        | Ce qu'il montre                                                            |
| ---------------------------------------------- | -------------------------------------------------------------------------- |
| [`rapport-minimal.json`](rapport-minimal.json) | Le plus petit rapport valide : ce qu'un scanner doit produire au minimum   |
| [`rapport-complet.json`](rapport-complet.json) | Toutes les sections renseignées, y compris les marqueurs de donnée absente |

## Ils ne viennent pas d'une machine réelle

C'est la seule chose à retenir, et elle n'est pas une formalité.

Ces fichiers sont **construits**, pas dérivés d'un audit existant par masquage.
La différence compte : un masquage à la main laisse toujours passer quelque
chose — une route qui redit le plan d'adressage, un suffixe DNS interne, le
numéro de série d'une barrette qu'on n'avait pas pensé à regarder.

Les valeurs identifiantes sont fixées à des constantes de démonstration, et les
adresses sont prises dans les plages que les RFC réservent à la documentation :

| Donnée             | Valeur                                 | Origine                  |
| ------------------ | -------------------------------------- | ------------------------ |
| Nom de machine     | `demo-host`                            | —                        |
| Domaine            | `demo.invalid`                         | RFC 2606 (`.invalid`)    |
| Numéro de série    | `DEMO-000000`                          | —                        |
| UUID / identifiant | `00000000-0000-0000-0000-000000000000` | UUID nul                 |
| Adresse IPv4       | `192.0.2.x`                            | RFC 5737 (TEST-NET-1)    |
| Adresse MAC        | `00:00:5e:00:53:xx`                    | RFC 7042 (documentation) |

`scripts/examples-sanitized.test.mjs` vérifie à chaque exécution de la suite que
ces fichiers valident contre le schéma **et** qu'aucune valeur ne sort de ces
plages. Un exemple régénéré un jour depuis un rapport réel échouerait.

## Les rejouer

```bash
node -e "
  const { reportSchema } = await import('@sysaudit/report-schema');
  const report = JSON.parse(require('node:fs').readFileSync('docs/examples/sanitized/rapport-complet.json', 'utf8'));
  console.log(reportSchema.safeParse(report).success ? 'valide' : 'invalide');
" --input-type=module
```

La spécification du format est dans
[`docs/format-rapport/REPORT_SCHEMA.md`](../../format-rapport/REPORT_SCHEMA.md),
et sa politique de version dans
[`docs/format-rapport/VERSIONING.md`](../../format-rapport/VERSIONING.md).
