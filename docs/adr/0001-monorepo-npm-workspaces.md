# ADR 0001 — Monorepo avec npm workspaces

- **Statut :** accepté
- **Date :** 2026-07-25

## Contexte

SysAudit regroupe des artefacts au cycle de vie différent : deux applications
(Web, API), plusieurs scanners par plateforme et des packages partagés (schéma,
règles, rendu). Le schéma de rapport est consommé par presque tous ces
artefacts : il doit être versionné une seule fois et partagé sans publication
sur un registre.

Le dépôt démarre vide, avec un seul développeur, sur Node 24 / npm 11.

## Décision

Utiliser **npm workspaces** avec trois racines : `packages/*`, `apps/*`,
`scanners/*`. Les packages internes sont préfixés `@sysaudit/` et restent
`private: true`. La compilation est orchestrée par les _project references_
TypeScript (`tsc --build`).

## Alternatives considérées

**pnpm workspaces.** Meilleure gestion du disque et isolation stricte des
dépendances fantômes. Écarté pour l'instant : pnpm n'est pas installé sur la
machine de développement et l'activation par corepack a échoué ; le gain réel
sur un dépôt de cette taille ne justifie pas d'imposer un gestionnaire
supplémentaire à toute personne clonant le projet.

**Turborepo.** Cache de tâches distribué et graphe de dépendances. Écarté :
avec moins d'une dizaine de packages, `tsc --build` fournit déjà le graphe et
l'incrémentalité. Ajouter Turborepo maintenant complexifierait l'outillage sans
bénéfice mesurable — ce que le cahier des charges demande explicitement d'éviter.

**Dépôts séparés.** Écarté : le schéma de rapport devrait être publié et
versionné à chaque itération, et une modification traversant scanner + schéma +
API demanderait trois PR coordonnées.

## Conséquences

Positives :

- Une seule commande `npm install` à la racine ; aucun outil supplémentaire.
- Un changement traversant plusieurs modules tient dans un commit atomique.
- `tsc --build` ne recompile que ce qui a changé.

Négatives :

- Le hoisting de npm autorise l'usage accidentel d'une dépendance non déclarée
  par un package (dépendance fantôme). Atténuation : chaque package déclare
  explicitement ses dépendances, et le build par références échoue si un import
  n'est pas résolvable depuis le package lui-même.
- Pas de cache de tâches distribué : la CI recompile tout. Acceptable tant que
  le build dure moins de quelques minutes.

Réévaluation : si le dépôt dépasse une dizaine de packages ou si le temps de CI
devient gênant, reconsidérer pnpm + Turborepo dans une nouvelle ADR.
