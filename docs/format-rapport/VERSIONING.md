# Versioning

SysAudit suit strictement le [Semantic Versioning 2.0.0](https://semver.org/lang/fr/).

## 1. Trois versions indépendantes

SysAudit publie trois artefacts dont les cycles de vie diffèrent. Chacun a sa
propre version, et un rapport les expose toutes les trois.

| Version           | Source de vérité                        | Décrit                               |
| ----------------- | --------------------------------------- | ------------------------------------ |
| `platformVersion` | `package.json` racine                   | L'application (API + Web + packages) |
| `scannerVersion`  | `scanners/<os>/VERSION`                 | Le scanner qui a produit le rapport  |
| `schemaVersion`   | `packages/report-schema/src/version.ts` | Le format JSON du rapport            |

Exemple dans un rapport :

```json
{
  "schemaVersion": "1.0.0",
  "scannerVersion": "0.3.0",
  "platformVersion": "0.3.0"
}
```

**Règle :** la version n'est jamais recopiée manuellement dans plusieurs
fichiers. Tout consommateur lit la source de vérité ci-dessus.

## 2. MAJOR / MINOR / PATCH

### PATCH — `0.4.2` → `0.4.3`

Correction rétrocompatible :

- correction de bug ;
- correctif de sécurité sans changement d'interface ;
- correction d'analyse d'une sortie de commande ;
- correction visuelle mineure.

### MINOR — `0.4.3` → `0.5.0`

Nouvelle fonctionnalité rétrocompatible. Le numéro PATCH repasse à `0`.

- support d'un nouvel OS ou d'un nouveau module (Proxmox, Docker…) ;
- nouvel onglet ou nouvelle vue ;
- nouveau champ **optionnel** dans le schéma ;
- nouvel endpoint d'API.

### MAJOR — **jamais**

Le numéro MAJOR de SysAudit ne s'incrémente pas. Ni pour la plateforme, ni pour
un scanner, ni pour le schéma de rapport.

Ce n'est pas une préférence esthétique : un rapport stocké il y a deux ans doit
rester lisible aujourd'hui. Un passage en `2.0.0` du schéma rendrait
`isSchemaReadable()` faux pour tout l'historique d'un parc, et l'utilisateur
perdrait la comparaison qui fait l'intérêt du produit.

MINOR et PATCH, eux, montent sans retenue. Passer à `0.147.3` n'est pas un
problème — c'est même le signe attendu d'un projet qui livre souvent.

#### Que faire d'un changement qui _semble_ appeler un MAJOR

| Envie                            | Faire à la place                                                  |
| -------------------------------- | ----------------------------------------------------------------- |
| Renommer un champ                | Ajouter le nouveau, garder l'ancien, le documenter comme déprécié |
| Supprimer un champ               | Le laisser optionnel et cesser de l'alimenter                     |
| Changer la sémantique d'un champ | Créer un champ voisin ; deux sens sous un même nom sont un piège  |
| Supprimer un endpoint            | Le conserver et documenter son remplaçant                         |

Ces contournements coûtent un peu de dette assumée. Ils coûtent moins cher que
de casser la lecture des données déjà collectées.

Si aucune formulation additive ne convient, **poser la question plutôt que
d'incrémenter MAJOR**.

## 3. Version du schéma de rapport

Le format JSON **est une API** : il est lu par le scanner, l'API, le Web, les
rapports archivés et les comparaisons d'historique.

- Ajouter un champ optionnel → MINOR du schéma.
- Corriger une description ou une contrainte sans changer les données acceptées
  → PATCH du schéma.
- Rendre un champ obligatoire, le supprimer ou le renommer → **à ne pas faire**,
  puisque cela appellerait un MAJOR. Voir les contournements ci-dessus.

Un lecteur implémentant le schéma `X.Y.Z` accepte tout rapport de version
`X.y.z` avec `y ≤ Y` (`isSchemaReadable()` dans `@sysaudit/shared`). Un rapport
plus récent est refusé explicitement plutôt qu'interprété partiellement.

Un ancien rapport n'est **jamais** cassé silencieusement : lorsqu'une migration
est nécessaire, un adaptateur de lecture est fourni dans
`packages/report-schema/src/migrations/`.

## 4. Commit ≠ release

Une feature peut représenter 3, 8 ou 15 commits sans produire 15 versions.
Toutes les modifications s'accumulent dans la section `[Unreleased]` du
CHANGELOG. La version n'est incrémentée que lorsqu'un ensemble cohérent devient
publiable.

## 5. Procédure de release

1. Vérifier la checklist de release (voir `CONTRIBUTING.md`).
2. Décider du niveau MINOR ou PATCH à partir du contenu de `[Unreleased]`.
   MAJOR n'est pas une option (§2).
3. Mettre à jour la version dans `package.json` (et le `VERSION` du scanner s'il
   a évolué).
4. Transformer `[Unreleased]` en `[X.Y.Z] - AAAA-MM-JJ` et recréer une section
   `[Unreleased]` vide.
5. Committer : `chore(release): v X.Y.Z`.
6. Taguer :

   ```bash
   git tag -a v0.5.0 -m "SysAudit v0.5.0"
   git push origin v0.5.0
   ```

7. Créer la GitHub Release avec les notes, les artefacts de scanner et leurs
   SHA256.

Le tag correspond **exactement** à la version du `package.json`.

## 6. Pré-releases

Format SemVer standard :

```text
0.9.0-beta.1
1.0.0-rc.1
```

Une pré-release n'est jamais présentée comme stable et n'est pas marquée
« latest » sur GitHub.

## 7. Hotfix

Pour une correction urgente en production :

```bash
git checkout main
git pull --ff-only origin main
git checkout -b hotfix/description-courte
```

Puis : correction → tests → version PATCH → CHANGELOG → merge `--no-ff` → tag →
release.

## 8. Automatisation

Changesets, release-please et semantic-release sont des pistes envisagées mais
volontairement non adoptées tant que le processus manuel n'est pas stabilisé :
l'objectif est une automatisation fiable, pas l'automatisation pour elle-même.
Le sujet est suivi dans `TODO.md`.
