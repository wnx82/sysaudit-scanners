# ADR 0012 — Traduire un audit demande des codes, pas un catalogue de phrases

- **Statut** : **accepté** le 2026-08-22
- **Date** : 2026-08-22
- **Contexte** : roadmap « Internationalisation, Analytics & User Insights »,
  sous-roadmap SR-04

## Ce que cet ADR décide, et ce qu'il ne décide pas

Il ne traduit rien. Il établit **ce que la traduction des audits coûte
réellement**, parce que ce chiffre n'existait nulle part et que la sous-roadmap
qui la demande le suppose connu.

Le reste de la roadmap a été livré. SR-04 ne l'a pas été, et cet ADR est ce qui
tient sa place : la conclusion de l'analyse, pas son ajournement silencieux.

## Contexte

SR-04 demande qu'« un même audit puisse être consulté en FR et EN », que « les
valeurs techniques restent inchangées », et — c'est la ligne qui compte —
qu'on « préfère des codes structurés + paramètres aux phrases stockées en base ».

Cette dernière phrase décrit une **architecture que le produit n'a pas**. Elle
n'est pas un détail d'implémentation à trancher en cours de route : c'est le
chantier lui-même.

### Ce qui existe

Le moteur d'analyse compte **97 règles**, réparties sur sept fichiers, et chacune
produit un constat portant cinq champs de prose française :

| Champ         | Rôle                                              |
| ------------- | ------------------------------------------------- |
| `title`       | l'intitulé du constat                             |
| `summary`     | la formulation non technique, affichée par défaut |
| `message`     | ce qui a été mesuré                               |
| `explanation` | pourquoi cela compte                              |
| `remediation` | ce qu'il faut faire                               |

Ces phrases sont **écrites en français dans le code des règles**, souvent
assemblées avec les valeurs mesurées — un nombre de secteurs réalloués, un nom
d'interface, une température. Trois des cinq sont ensuite **stockées en base**
dans `Finding` (`title`, `summary`, `message`), pour qu'un rapport archivé reste
lisible tel qu'il a été présenté.

Ce qui existe déjà, en revanche, et qui est la moitié du travail : **chaque
constat porte un `ruleId` stable** (`SEC-001`, `STA-014`). Il est indexé, il sert
déjà de clé de comparaison entre deux audits d'une même machine, et il ne change
pas. C'est le code structuré que SR-04 réclame — il ne lui manque que des
paramètres nommés et un catalogue.

### Ce que « traduire les audits » demande donc

1. **Séparer la phrase de la donnée dans 97 règles.** Chaque `message` assemblé
   devient un identifiant plus un jeu de paramètres nommés. C'est une réécriture
   mécanique, mais elle touche le fichier le plus sensible du produit — celui
   dont chaque règle doit conserver ses deux tests, de déclenchement **et** de
   non-déclenchement sur donnée absente.
2. **Écrire 97 × 5 entrées de catalogue en français**, puis autant en anglais.
   Environ 970 phrases, dont la moitié dans une langue que ce dépôt n'a jamais
   écrite.
3. **Décider ce que devient l'existant.** Les constats déjà en base portent leur
   prose française et pas de paramètres. On ne peut pas la retraduire : les
   valeurs ont été fondues dans le texte. Un audit ancien reste donc lisible en
   français, quelle que soit la langue demandée — c'est le repli que SR-04
   appelle, et il doit se voir à l'écran plutôt que de laisser croire à une
   traduction partielle.
4. **Traiter les six autres sources de prose** que le rapport affiche :
   `labels.ts`, les libellés de couverture, les motifs d'absence
   (`absence.ts`), les niveaux de criticité, les commandes de remédiation et le
   moteur de rendu — Markdown, HTML autonome et PDF, qui produisent chacun leurs
   propres intitulés.

## Décision

**Ne pas traduire les audits dans ce lot, et ne pas le faire sans que les 970
phrases anglaises aient un auteur humain.**

> **Adoptée le 2026-08-22.** Cet ADR est resté « proposé » deux jours pendant
> que le relevé « reste à faire » l'inscrivait en tête de ses décisions en
> attente — c'est-à-dire pendant que rien ne pouvait avancer autour. Une analyse
> dont la conclusion est « ne pas faire, et voici dans quel ordre reprendre » ne
> gagne rien à rester ouverte : elle bloque au lieu de trancher.
>
> Ce que l'adoption change concrètement : le fait qu'un audit reste en français
> dans les deux langues d'interface cesse d'être un défaut qu'on découvre pour
> devenir un choix écrit et daté. La reprise du chantier, elle, garde son ordre
> — le lot de séparation phrase/donnée d'abord, sans ajouter aucune langue.

Trois raisons, dans l'ordre de leur poids.

**Une traduction automatique dirait le contraire de ce que ce produit promet.**
Le dépôt tient une règle qu'il applique partout : ne jamais conclure d'une donnée
absente, ne jamais inventer une valeur. Un constat de sécurité rendu en anglais
approximatif — « the SMART counter was not read » confondu avec « the SMART
counter is zero » — est exactement l'erreur que tout le reste du code existe pour
empêcher. Le commentaire de `routes.ts` le dit déjà de la documentation : « les
traduire à la chaîne produirait un anglais approximatif sur des pages qui
expliquent précisément qu'on ne devine pas ».

**La réécriture des règles est le vrai risque, et il n'est pas dans la
traduction.** Séparer la phrase de la donnée dans 97 règles, c'est toucher 97
fois à du code dont chaque branche décide si une machine est saine. Une règle qui
perd son cas « donnée non collectée » en route rendra un constat parfaitement
formé, parfaitement traduit, et faux. Ce chantier mérite son propre lot, avec sa
propre revue.

**Rien de ce qui a été livré ne dépend de ce choix.** Le sélecteur de langue, la
résolution par le chemin, la 404 traduite et les métadonnées bilingues sont en
place et fonctionnent. Le jour où les catalogues existeront, ils s'y brancheront
sans rien déplacer.

## Conséquences

- **Un audit reste en français**, dans les deux langues d'interface. C'est un
  fait connu et écrit, pas un défaut qu'on découvre.
- **Le sélecteur ne s'affiche pas sur les pages de rapport**, et c'est déjà le
  cas : `TRANSLATED_PATHS` ne les contient pas, et un test vérifie que chaque
  page annoncée existe réellement dans chaque langue. Aucun visiteur ne se voit
  proposer une traduction qui n'existe pas.
- **Le `ruleId` est acquis.** Le jour où les catalogues seront écrits, la clé
  qui les indexe existe déjà, elle est stable, indexée, et déjà employée par la
  comparaison d'audits.

## Ce qu'il faudrait pour reprendre ce chantier

Dans cet ordre, et pas dans un autre :

1. Un lot qui **n'ajoute aucune langue** : il remplace les cinq champs de prose
   par un identifiant et des paramètres nommés, et régénère le français depuis
   un catalogue. Les tests existants doivent passer **inchangés** — c'est la
   preuve que rien n'a bougé.
2. Une décision sur le repli des audits archivés : régénérer les constats depuis
   `raw`, qui reste la source de vérité, ou les laisser dans leur langue d'origine
   en le disant à l'écran.
3. Alors seulement, le catalogue anglais — relu par quelqu'un dont c'est la
   langue, sur un domaine où « unknown » et « zero » ne se confondent pas.
