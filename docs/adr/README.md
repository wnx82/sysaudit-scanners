# Décisions d'architecture

Une décision structurante par fichier, numérotée dans l'ordre où elle a été
prise, jamais réécrite après coup. Une décision qu'on remplace ne s'efface pas :
elle reçoit une note de portée, et la nouvelle arrive avec son propre numéro.
C'est ce qui permet de comprendre pourquoi le code est ainsi plutôt que de
constater qu'il l'est.

| #                                                               | Décision                                                                          | Date       | Statut                                                                                                  |
| --------------------------------------------------------------- | --------------------------------------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------- |
| [0001](0001-monorepo-npm-workspaces.md)                         | Monorepo avec npm workspaces                                                      | 2026-07-25 | accepté                                                                                                 |
| [0002](0002-report-schema-versioning.md)                        | Schéma de rapport : Zod comme source unique, versionné à part                     | 2026-07-25 | accepté                                                                                                 |
| [0003](0003-scanner-architecture.md)                            | Scanners : collecte native, analyse déportée                                      | 2026-07-25 | accepté                                                                                                 |
| [0004](0004-analysis-engine-single-package.md)                  | Un seul package d'analyse plutôt que trois                                        | 2026-07-25 | accepté                                                                                                 |
| [0005](0005-strategie-mobile.md)                                | Le scanner Android est une application, pas un script                             | 2026-07-28 | accepté                                                                                                 |
| [0006](0006-dependances-externes.md)                            | Dépendances externes : nommer, jamais installer                                   | 2026-07-29 | accepté, **partiellement révisé** par la [0008](0008-installation-consentie-en-audit-administrateur.md) |
| [0007](0007-photo-materiel.md)                                  | Photo du matériel : téléversée, jamais cherchée                                   | 2026-07-29 | **révisé le 2026-08-20** — recherche autorisée pour carte mère, GPU et mémoire, sous conditions         |
| [0008](0008-installation-consentie-en-audit-administrateur.md)  | Installation consentie, bornée à l'audit administrateur local                     | 2026-08-07 | accepté                                                                                                 |
| [0009](0009-integrite-et-propriete-des-rapports-deposes.md)     | Intégrité et propriété d'un rapport déposé à la main                              | 2026-08-12 | accepté                                                                                                 |
| [0010](0010-moteur-recherche-auto-heberge.md)                   | Le moteur de recherche d'images est auto-hébergé                                  | 2026-08-20 | accepté                                                                                                 |
| [0011](0011-application-desktop-electron.md)                    | L'application Desktop est un workspace TypeScript                                 | 2026-08-20 | accepté                                                                                                 |
| [0012](0012-traduction-des-audits.md)                           | Traduire un audit demande des codes, pas un catalogue                             | 2026-08-22 | accepté                                                                                                 |
| [0013](0013-deux-resumes-systeme.md)                            | Deux résumés système : arbitrer, pas fusionner                                    | 2026-08-22 | accepté                                                                                                 |
| [0014](0014-portee-de-l-internationalisation.md)                | Portée de l'internationalisation : la console reste française                     | 2026-08-22 | accepté                                                                                                 |
| [0015](0015-architecture-des-scores-sysaudit.md)                | Cinq familles de chiffres, et une seule qui note la machine                       | 2026-08-24 | accepté                                                                                                 |
| [0016](0016-moteur-audit-en-package-applications-en-facades.md) | Le moteur d'audit devient un package ; les applications n'en sont que des façades | 2026-08-27 | accepté                                                                                                 |

## Écrire la suivante

Reprendre la forme d'une existante : date, statut, contexte, décision,
conséquences — y compris celles qu'on assume à contrecœur. Une ADR qui ne liste
que des avantages n'a pas été écrite au moment du choix, mais après.

Le numéro suit le dernier, sans réutiliser celui d'une décision abandonnée : ces
numéros sont cités depuis le code et le changelog, et deux décisions différentes
sous un même numéro sont un piège dont personne ne sort.

**Réviser plutôt que réécrire.** La 0006 en donne l'exemple : sa portée a changé
le 2026-08-07, et c'est une note en tête du fichier qui le dit, suivie du texte
d'origine intact. Le lecteur voit alors ce qui a été décidé, et ce qui a été
revu.
