# SysAudit — composants publiés

> Audit et diagnostic système. Une commande collecte l'inventaire technique
> d'une machine et produit un rapport JSON versionné, sans rien y écrire.

**Ce dépôt ne contient pas tout SysAudit.** Il contient ce qui s'exécute sur
votre machine et ce que cette exécution produit — les scanners et le format de
rapport. Le moteur d'analyse, le scoring, l'API, l'interface Web et les
applications sont propriétaires et ne sont pas publiés. Le détail de cette
frontière est dans [NOTICE.md](NOTICE.md).

Cette distinction est délibérée, et elle a une conséquence utile pour vous :
**vous pouvez lire l'intégralité du code qui tournera sur vos machines**, en
privilège élevé, avant de le lancer. C'est exactement ce qu'un scanner système
doit permettre.

Le service complet vit sur **[sysaudit.me](https://sysaudit.me)**.

---

## Ce qui est ici

| Chemin                   | Ce que c'est                                                             |
| ------------------------ | ------------------------------------------------------------------------ |
| `scanners/linux/`        | Scanner Bash — Linux, Proxmox VE. Stable.                                |
| `scanners/windows/`      | Scanner PowerShell — Windows 10/11, Windows Server. Stable.              |
| `scanners/macos/`        | Scanner macOS. **Expérimental.**                                         |
| `scanners/bsd/`          | Scanner FreeBSD, pfSense, OPNsense. **Expérimental.**                    |
| `scanners/android/`      | Scanner Android via Termux. **Expérimental.**                            |
| `packages/report-schema` | Le format de rapport : définition Zod, JSON Schema, politique de version |
| `packages/shared`        | Valeurs inconnues, anonymisation, détection de secrets                   |
| `packages/platform`      | Taxonomie des OS et matrice de compatibilité des scanners                |
| `docs/`                  | Mode d'emploi de tout ce qui précède                                     |

## Auditer une machine

### Linux, Proxmox VE

```bash
sudo ./scanners/linux/sysaudit.sh --output-dir ./reports
```

### Windows

```powershell
# Windows refuse par défaut d'exécuter un .ps1. Le contournement ci-dessous est
# limité à ce seul processus : rien n'est modifié sur la machine.
powershell -ExecutionPolicy Bypass -File .\scanners\windows\sysaudit.ps1 -Profile standard
```

Le scanner écrit `sysaudit-<machine>.json`. **Aucun envoi n'a lieu sans
`--upload` explicite.**

Ajoutez `--anonymize` pour masquer hostname, utilisateurs, domaine, adresses IP
publiques, adresses MAC, numéros de série, UUID et SSID avant tout partage.

### Ce que « non destructive » veut dire, niveau par niveau

| Niveau       | Effet sur la machine                                                                                       |
| ------------ | ---------------------------------------------------------------------------------------------------------- |
| **Rapide**   | Lecture seule. Aucun outil installé, aucun banc d'essai.                                                   |
| **Normale**  | Lecture seule. Niveau par défaut.                                                                          |
| **Complète** | Lecture seule, sauf installation d'un outil manquant — **jamais sans accord**, retrait proposé.            |
| **Poussée**  | Tout Complète, plus un banc d'essai qui **charge volontairement** la machine, sous surveillance thermique. |

Trois niveaux sur quatre n'écrivent rien. Le quatrième le fait, et le dit.

## Le rapport

Le format est un **contrat versionné**, et c'est la raison pour laquelle il est
publié : un rapport produit aujourd'hui doit rester lisible sans SysAudit.

- Définition : [`packages/report-schema`](packages/report-schema)
- Spécification : [`docs/format-rapport/REPORT_SCHEMA.md`](docs/format-rapport/REPORT_SCHEMA.md)
- Politique de version : [`docs/format-rapport/VERSIONING.md`](docs/format-rapport/VERSIONING.md)
- Exemple synthétique : [`docs/examples/sanitized/`](docs/examples/sanitized/)

Une donnée non collectée n'est **jamais** remplacée par une valeur par défaut :
elle porte un marqueur et sa raison. Un compteur SMART non lu n'est pas un
compteur nul, et le format vous permet de faire la différence.

## Ce qui n'est pas ici

Le moteur d'analyse et son scoring, la base matérielle et l'appariement visuel,
le moteur de rendu, le moteur d'audit, l'API, l'interface Web, les applications
de bureau et en ligne de commande, l'administration, le schéma de base de
données et l'infrastructure d'exploitation.

Un clone de ce dépôt ne permet donc ni de recalculer un score, ni de reproduire
la plateforme. Nous préférons l'écrire que de laisser croire l'inverse.

## Développer

```bash
npm ci
npm run verify        # lint + typecheck + tests + build
npm run test:scanner  # suite du scanner Linux (Bash)
```

La suite du scanner Windows demande PowerShell : `npm run test:scanner:windows`.

Le scanner ne dépend d'**aucun** paquet TypeScript à l'exécution — il doit
tourner sur une machine où Node.js n'est pas installé.

## Sécurité

Ne signalez jamais une vulnérabilité par une issue publique.
Voir [SECURITY.md](SECURITY.md).

Si vous ouvrez une issue : **aucun mot de passe, jeton, clé, adresse IP privée,
numéro de série, donnée personnelle ni rapport SysAudit non anonymisé.**

## Contribuer

Voir [CONTRIBUTING.md](CONTRIBUTING.md). La documentation, les commentaires de
code et les messages de commit de ce dépôt sont **en français**.

## Droits

**SysAudit n'est pas un logiciel open source.** Les sources publiées ici le sont
pour être lues, vérifiées et exécutées sur vos propres machines. La
redistribution, les travaux dérivés et l'usage concurrent demandent un accord
écrit préalable.

Conditions exactes : [LICENSE](LICENSE) · Frontière publique/propriétaire :
[NOTICE.md](NOTICE.md) · Dépendances tierces :
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

© 2026 [eKreativ.be](https://www.ekreativ.be). Tous droits réservés.
