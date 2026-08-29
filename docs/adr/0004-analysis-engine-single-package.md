# ADR 0004 — Un seul package d'analyse plutôt que trois

- **Statut :** accepté
- **Date :** 2026-07-25
- **Amende :** [ADR 0001](0001-monorepo-npm-workspaces.md)

## Contexte

Le cahier des charges décrit trois modules d'analyse distincts —
`security-rules`, `diagnostic-rules` et `upgrade-rules` — et l'architecture
initiale prévoyait trois packages npm séparés.

À l'écriture, ces trois familles de règles se sont révélées partager
l'intégralité de leur infrastructure : le type `Rule`, l'accesseur de lecture
qui distingue « donnée absente » de « donnée nulle », le moteur d'évaluation
avec isolation des erreurs, l'échelle de sévérité et le calcul des scores. Seuls
les tableaux de règles diffèrent.

Par ailleurs, le scoring a besoin des constats des trois familles simultanément
(le score général agrège sécurité et matériel), et la comparaison d'audits ne se
rattache à aucune des trois.

## Décision

Livrer un package unique `@sysaudit/analysis-engine`, organisé en modules :

```text
src/
├── types.ts            Rule, Finding, Severity, Category, scores
├── read.ts             accesseur unique des champs potentiellement absents
├── engine.ts           évaluation, tri, isolation des erreurs
├── scoring.ts          scores général / sécurité / matériel + couverture
├── compare.ts          comparaison entre deux audits
└── rules/
    ├── security.ts     SEC-*
    ├── diagnostic.ts   DIA-*
    └── upgrade.ts      UPG-*
```

La séparation logique demandée est donc conservée — les familles restent
distinctes, identifiables par préfixe et documentées séparément — mais elle est
matérialisée par des modules plutôt que par des packages.

## Alternatives considérées

**Trois packages consommant un quatrième package « core ».** Respecte la lettre
de l'architecture initiale. Écarté : quatre `package.json`, quatre `tsconfig`,
quatre entrées de build et de références de projet, pour trois fichiers de
données. Le cahier des charges demande explicitement de ne pas complexifier
inutilement l'architecture (§5), et aucun consommateur n'a de raison d'importer
les règles de sécurité sans le moteur qui les exécute.

**Trois packages dupliquant l'infrastructure.** Écarté sans hésitation :
l'accesseur de lecture est le mécanisme qui garantit qu'aucune règle ne conclut
à partir d'une donnée absente. Le dupliquer en trois exemplaires reviendrait à
accepter que les trois copies divergent.

## Conséquences

Positives :

- Une seule définition du contrat `Rule` : impossible qu'une famille de règles
  dérive de la sémantique des autres.
- Le scoring et la comparaison ont naturellement accès à tous les constats.
- Moins d'outillage à maintenir, un seul build à ordonnancer.

Négatives :

- Un consommateur qui ne voudrait que les règles de sécurité embarque tout le
  package. Impact négligeable : il s'agit de code serveur, et l'ensemble reste
  de taille modeste.
- L'écart avec l'arborescence du cahier des charges doit être documenté — c'est
  l'objet de cette ADR, et `docs/technique/ARCHITECTURE.md` a été mis à jour en
  conséquence.

Réévaluation : si l'Upgrade Intelligence acquiert ses propres dépendances
(catalogues matériels, appels à des sources constructeur), elle justifiera son
extraction dans un package dédié.
