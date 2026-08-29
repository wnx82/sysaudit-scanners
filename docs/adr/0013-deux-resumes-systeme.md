# ADR 0013 — Deux résumés système, et lequel fait foi

- **Statut** : accepté
- **Date** : 2026-08-22
- **Contexte** : relevé « reste à faire » du 2026-08-22, ligne **D1**

## Le problème

Deux fichiers calculent un résumé de la machine auditée, et rien dans le dépôt
ne disait lequel fait autorité :

| Fichier                                     | Lignes | Sert                         |
| ------------------------------------------- | -----: | ---------------------------- |
| `apps/web/src/lib/report-system-summary.ts` |  1 800 | la vue web du rapport        |
| `packages/report-renderer/src/machine.ts`   |    231 | Markdown, HTML autonome, PDF |

Le relevé demandait de « fusionner ou arbitrer ». Cet ADR arbitre, et dit
pourquoi la fusion serait une erreur.

## Pourquoi ne pas fusionner

Parce qu'ils ne répondent pas à la même question, et que le rapport de taille le
dit déjà.

`machine.ts` produit une **fiche d'identité** : huit faits, dans un ordre fixe,
qui répondent à « qu'est-ce que je regarde ». Elle ouvre les trois rendus
statiques, avant le score, parce qu'un lecteur qui voit une note avant de savoir
de quelle machine elle parle ne sait pas ce qu'il lit. Aucun fait n'est retiré
quand il n'a pas pu être mesuré — c'est précisément l'information à voir.

`report-system-summary.ts` produit un **tableau détaillé** : une dizaine de
cartes, deux cents valeurs, températures agrégées par capteur, séquence de
démarrage, niveaux de performance, télémétrie par carte graphique. Il existe
pour être comparé, ligne à ligne, à ce que les outils de diagnostic du marché
affichent. C'est une page, pas une fiche.

Fondre l'un dans l'autre donnerait soit une fiche d'identité de deux cents
lignes dans un PDF, soit une vue web amputée de ce qui la justifie. Le
« doublon » n'en est pas un : c'est un résumé court et un résumé long.

## La décision

**`machine.ts` fait foi sur l'identité de la machine.** Les huit faits de la
fiche — type de châssis, système, processeur, mémoire, graphique, stockage,
carte mère, uptime — s'y calculent, et nulle part ailleurs.

**`report-system-summary.ts` fait foi sur le détail de la vue web**, et n'a
autorité que là. Il importe déjà de `report-renderer` ce qui doit être commun
(`orderedGpus`, `formatMs`), et cette dépendance est le bon sens de lecture :
`report-renderer` est un paquet, `apps/web` une application, et **aucun paquet
ne dépend d'une application**.

**Une valeur enrichie se calcule dans un paquet, jamais dans une vue.** Les
identités matérielles lues au catalogue — fabricant de disque, famille de
processeur, assembleur de carte, nature d'un écran — vivent dans
`@sysaudit/hardware-base` et sont consommées à l'identique par les quatre
rendus. C'est le remède qui a déjà servi pour la table de libellés.

## Le garde-fou

Une décision écrite ne tient pas toute seule : `system-summary-coherence.test.ts`
compare, sur les rapports de référence, les faits que **les deux** chemins
calculent — modèle de processeur, mémoire installée, nombre de disques, modèle
de la première carte graphique, nom du système, modèle de carte mère. Une
divergence échoue le test.

C'est exactement le défaut que la table de libellés avait produit en août : trois
copies divergentes faisaient sortir « SELinux — UNSUPPORTED » dans la page et
dans les exports, sans qu'aucun test ne l'attrape. Le test ne dit pas quel calcul
est juste ; il dit qu'ils ne peuvent plus se répondre différemment sans que
quelqu'un l'ait voulu.

## Conséquences

- Un fait d'identité qui change se change dans `machine.ts`, et le test de
  cohérence dira si la vue web s'en est écartée.
- Une carte nouvelle dans la vue web ne concerne pas les rendus statiques, et
  n'a pas à y être portée.
- La ligne **A3** du relevé — « fusion des deux résumés système » — est close par
  le présent ADR : le travail était identifié, son opportunité ne l'était pas.
  Elle ne l'est pas : il ne faut pas fusionner.
