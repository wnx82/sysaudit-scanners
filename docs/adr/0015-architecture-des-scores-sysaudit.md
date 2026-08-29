<!--
SPDX-FileCopyrightText: 2026 SysAudit
SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available
-->

# ADR 0015 — Cinq familles de chiffres, et une seule qui note la machine

- **Statut** : accepté
- **Date** : 2026-08-24
- **Contexte** : phase 1 de la roadmap « SysScore complet », après la baseline du
  2026-08-24
- **Complète** : l'[ADR 0003](0003-scanner-architecture.md), qui pose le rapport
  comme source de vérité, et la documentation du moteur
  (SYSSCORE.md)

## Contexte

Le moteur `performance-first` publie aujourd'hui un SysScore, quatre
composantes, six axes, une couverture et une confiance. La roadmap propose d'y
ajouter des sous-scores GPU, réseau et pilotes, des indices de banc d'essai, des
percentiles de cohorte et un historique.

Le risque n'est pas la difficulté de ces calculs : il est qu'ils finissent tous
dans le même chiffre. Un score qui mélange « cette machine fonctionne-t-elle
bien ? », « quelle puissance a-t-elle ? » et « comment se situe-t-elle face aux
autres ? » ne répond plus à aucune des trois. C'est exactement le défaut que la
refonte 2.0 avait corrigé pour la sécurité, et il se représente ici sous une
autre forme.

La baseline a par ailleurs établi un fait qui contraint toute la suite : **trois
sondes sur dix-neuf ne se déclenchent sur aucune fixture**, et deux signaux
majeurs ne sont produits que par un seul scanner. Toute famille de chiffres
définie ici doit donc savoir dire « non mesurable » sans se dégrader en zéro.

## Décision

**Cinq familles de chiffres coexistent. Une seule note la machine.**

| Famille                       | Répond à                                   |      Entre dans le SysScore      | Vaut `null` quand                                     |
| ----------------------------- | ------------------------------------------ | :------------------------------: | ----------------------------------------------------- |
| **SysScore opérationnel**     | « Cette machine fonctionne-t-elle bien ? » |       — _il est le total_        | moins de 50 % du poids est mesuré                     |
| **Sous-scores diagnostiques** | « Qu'est-ce qui ne va pas, et où ? »       | oui, par les axes et les piliers | moins d'un tiers des contrôles applicables ont abouti |
| **Indices de capacité**       | « Quelle puissance a cette machine ? »     |             **non**              | aucun banc d'essai n'a tourné                         |
| **Couverture**                | « Qu'a-t-on réellement regardé ? »         |            **jamais**            | rien : elle est toujours publiée                      |
| **Percentiles de cohorte**    | « Comment se situe-t-elle ? »              |            **jamais**            | l'échantillon est sous le minimum statistique         |

Les trois « jamais » sont la substance de cette décision. Un indice de capacité
élevé ne relève pas le SysScore : une machine puissante qui rame reste une
machine qui rame. Une couverture faible ne l'abaisse pas : elle abaisse la
confiance. Un percentile ne le touche pas davantage : la note d'une machine ne
dépend pas des machines des autres.

### Ce qui devient constitutif, et ce qui reste informatif

**Le GPU devient le septième axe de Performance.** Le schéma porte déjà
température, charge, fréquences et mémoire vidéo, et les cibles de banc `gpu`,
`cpu-gpu` et `gaming` existent. Une machine dont le GPU chauffe, se bride ou
s'effondre sous charge est une machine lente, et l'absence d'axe l'obligeait
jusqu'ici à se loger sur `responsiveness` — ce que `PRF-011` fait aujourd'hui,
en s'excusant en commentaire de ne pas nommer sa cause.

**Le réseau reçoit un score, borné à ce qui appartient à la machine.** Lien,
négociation, erreurs d'interface, pilote. Rien qui traverse Internet : un débit
faible peut être l'opérateur, et noter une machine sur son fournisseur d'accès
serait noter autre chose qu'elle. Ce score est **diagnostique et informatif** :
il n'est pas un axe de Performance, et les six règles `NET-*` conservent leur
impact déclaré sans axe.

**Les pilotes reçoivent un sous-score informatif dédié.** Ils pèsent déjà sur la
stabilité et la sécurité par sept règles `DRV-*`, et cela ne change pas — le
sous-score ne fait que rendre visible ce qui est aujourd'hui dispersé dans deux
piliers. Il n'entre dans aucun total. **Un pilote ancien n'est pas un défaut** :
seule une erreur démontrée en est un, et c'est déjà ce que les règles exigent.

**Les bancs d'essai restent en opt-in explicite**, réservés à l'audit complet.
Ils chargent réellement le processeur, le GPU et le disque de la machine
auditée ; les lancer sans que personne ne l'ait demandé serait une action que
l'utilisateur n'a pas consentie. Conséquence assumée : les sondes qui en
dépendent restent souvent non mesurables, et la couverture le dit.

### Ce que l'arrivée d'un septième axe ne doit pas faire

Ajouter un axe redistribue les poids, et redistribuer les poids re-hiérarchise
les autres axes sans que personne ne l'ait décidé. **Les six poids existants sont
donc multipliés par un facteur unique**, ce qui laisse leurs rapports exactement
inchangés :

| Axe                   | Avant |    Après |
| --------------------- | ----: | -------: |
| Processeur            |  20 % |     18 % |
| Mémoire               |  20 % |     18 % |
| Stockage              |  20 % |     18 % |
| Démarrage et services |  15 % |   13,5 % |
| Réactivité            |  15 % |   13,5 % |
| Températures          |  10 % |      9 % |
| **GPU**               |     — | **10 %** |

Ces chiffres sont un **point de départ de calibration**, pas une vérité, et le
`10 %` du GPU est le seul choix réellement neuf — il le place au niveau du
thermique, en dessous des trois axes qui décident du ressenti sur toute machine.
Il sera ajusté sur des fixtures portant des mesures GPU réelles, jamais sur
intuition.

**Une machine sans GPU mesurable ne perd rien.** L'axe vaut `null`, son poids
est redistribué sur les six autres, et la couverture le signale. C'est le
mécanisme existant, et c'est précisément pourquoi un septième axe est
supportable : un serveur sans affichage n'est pas une machine dont on ignore
10 % de la performance, c'est une machine dont la performance ne dépend pas d'un
GPU.

### Plafond global : un mécanisme explicite, jamais dérivé

Un incident matériel réellement grave doit pouvoir borner le **SysScore entier**,
et pas seulement l'axe qu'il touche : un disque en train de mourir ne rend pas
une machine « moyenne sur le stockage », il rend la machine entière peu sûre à
utiliser.

Ce plafond est déclaré **règle par règle**, dans une table distincte de
`PERFORMANCE_IMPACT_BY_RULE`, et chaque entrée doit répondre par écrit : quelle
preuve, pourquoi un plafond **global** plutôt qu'un plafond d'axe, quelle fixture
le valide, quel score maximal, quelle version du moteur l'introduit.

**Il ne se dérive jamais de la sévérité.** C'est la même interdiction que pour
l'impact performance, et pour la même raison : `SEC-002` est `critical` et ne
ralentit rien. Une table qui plafonnerait le SysScore de toute règle `critical`
ferait reculer la note d'une machine rapide et saine parce qu'elle autorise SSH
par mot de passe — soit exactement le défaut que la 2.0 a corrigé.

Aucune entrée n'est créée avant qu'une fixture ne la justifie. La table naît
vide.

### Compatibilité entre versions

`SYSSCORE_VERSION` suit SemVer, et chaque rang a un sens **opérationnel** :

| Rang          | Signifie                                                                                            | Deux notes se soustraient-elles ? |
| ------------- | --------------------------------------------------------------------------------------------------- | :-------------------------------: |
| **Majeur**    | La question posée a changé — un axe apparaît ou disparaît, une composante est repondérée            |                non                |
| **Mineur**    | La méthode a changé de façon mesurable — seuil, pénalité, plafond, traitement d'une valeur inconnue |                non                |
| **Correctif** | Aucun effet numérique — libellé, commentaire, refactorisation                                       |              **oui**              |

`comparable` cesse donc d'exiger l'égalité stricte : il exige le même moteur et
les mêmes rangs **majeur et mineur**. Un correctif ne doit plus rendre
incomparables deux audits que rien ne sépare.

En contrepartie, **le rang mineur devient une obligation**, pas une politesse. La
baseline a trouvé un contre-exemple : le passage au plancher d'un tiers de
couverture pour les piliers, livré le 2026-08-17, a modifié le traitement des
valeurs inconnues — donc quand un pilier vaut `null`, donc le SysScore — sans
que la version bouge. Deux audits encadrant cette date se déclarent `2.1.0` tous
les deux et sont comparés comme s'ils partageaient une méthode.

L'arrivée du septième axe est un changement **majeur** : `3.0.0`.

### Invariants, et comment ils se testent

Ils sont énoncés ici pour être vérifiés par des tests de propriété, sur des
rapports engendrés, et non seulement sur les fixtures écrites à la main :

1. **Bornes** — tout score vaut `null`, ou un entier de 0 à 100. Jamais `NaN`,
   jamais une valeur hors bornes.
2. **Rien de gratuit** — un axe sans sonde mesurée **ni** plafond vaut `null`. Un
   pilier sous le tiers de ses contrôles applicables vaut `null`.
3. **Total recalculable** — la somme des contributions publiées égale le score,
   à l'arrondi d'affichage près, et la somme des poids appliqués vaut 1.
4. **Monotonie** — ajouter une pénalité ne fait jamais monter un axe ; ajouter un
   constat ne fait jamais monter un score. Sans cette propriété, une machine
   pourrait s'améliorer en tombant en panne.
5. **Le plafond plafonne** — il ne relève jamais un axe au-dessus de ce que ses
   sondes ont donné.
6. **La couverture ne multiplie pas** — à signaux mesurés identiques, le score est
   identique, quelle que soit la couverture. Seule la confiance bouge.
7. **Le goulot est mesuré** — l'axe désigné n'est jamais `null`.
8. **Déterminisme** — deux exécutions sur le même rapport rendent le même
   résultat, champ par champ.

## Ce que cela ne change pas

- La **notation par domaines** (`SCORING.md`, moteur 1.x) continue d'exister et
  de répondre à « qu'est-ce qui ne va pas ? ». Les deux ne fusionnent pas.
- La séparation **performance / santé matérielle** reste entière. Un disque qui
  vieillit n'est pas une machine lente, et une machine lente n'a pas
  nécessairement un défaut matériel.
- Le **rapport reste la source canonique** (ADR 0003). Les colonnes de score en
  base sont un index de tri, pas une source de vérité : elles se recalculent, et
  elles portent la version du moteur qui les a écrites.
- **La sécurité garde ses 5 %** et son score propre, affiché en clair.

## Conséquences

- **Toute la calibration est à refaire.** Sept axes ne se calibrent pas comme
  six, et les huit profils bougeront ensemble. C'est le coût annoncé de D1, et
  la baseline existe pour le mesurer.
- **Les fixtures doivent porter des mesures GPU.** Sans elles, le septième axe
  serait `null` partout et la calibration ne validerait rien — le défaut que la
  baseline a déjà relevé sur trois autres sondes.
- **Un audit rapide notera moins de choses qu'avant**, en proportion : le GPU
  s'ajoute aux axes dont les signaux les plus parlants viennent d'un banc
  d'essai en opt-in.
- **Les audits archivés deviennent incomparables** aux nouveaux. L'écart reste
  publié, l'interface dit « méthode de calcul différente », et c'est le
  comportement voulu — mais l'historique d'une machine s'interrompt visuellement
  à la montée en `3.0.0`.
- **Trois chiffres de plus à expliquer dans l'interface.** Un sous-score que
  l'utilisateur ne sait pas distinguer du SysScore est un chiffre qui nuit ;
  l'écran « Comment ce score est-il calculé ? » devient une condition de
  livraison, pas un agrément.

## Alternatives écartées

| Voie                                                                          | Pourquoi non                                                                                                                                                               |
| ----------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GPU en sous-score informatif                                                  | Un GPU qui se bride ralentit réellement la machine. Le laisser hors du total obligerait à continuer de loger ces constats sur `responsiveness`, qui ne les représente pas. |
| GPU en axe conditionnel, présent seulement si un usage graphique est démontré | Un axe qui apparaît et disparaît rend deux audits de la même machine non comparables sans qu'aucune méthode n'ait changé.                                                  |
| Réseau en axe de Performance                                                  | Ferait dépendre la note d'une machine de son fournisseur d'accès.                                                                                                          |
| Pilotes en quatrième pilier                                                   | Redécouperait les 30 % non-performance et rendrait les anciens audits incomparables, pour un signal déjà porté par la stabilité et la sécurité.                            |
| Plafond global dérivé de la sévérité `critical`                               | Reproduit exactement le défaut corrigé par la 2.0 : une faille sans effet sur la vitesse ferait passer une machine rapide pour une machine lente.                          |
| Bancs d'essai lancés par défaut                                               | Charge réelle non consentie sur la machine auditée.                                                                                                                        |
| Multiplier le score par la couverture                                         | Une performance de 95 mesurée sur deux signaux reste 95 sur ce qui a été vu. C'est la confiance qui doit reculer, pas la note.                                             |

## Compléments — 2026-08-24

Trois décisions prises en appliquant cet ADR, consignées ici parce qu'elles en
précisent la portée plutôt que de la contredire.

**Le goulot publie ses preuves, et cela reste un rang correctif.** `topSignals`,
`ceiling`, `runnerUp` et `certainty` s'ajoutent à `Bottleneck` sans qu'aucune
note ne bouge — même facteur, mêmes seuils. C'est exactement ce que la table de
compatibilité appelle un correctif : `3.1.1`, et deux audits qui l'encadrent se
soustraient toujours. `certainty` ne borne pas le calcul, il borne
l'**affirmation** : sous 0,75 de confiance, l'interface écrit « Goulot
probable ».

**Une cohorte peut s'élargir, jamais se diluer.** La hiérarchie de
`COHORT_TIERS` descend d'un cran quand le niveau le plus étroit ne réunit pas
`MINIMUM_COMPARISON_SAMPLES` machines, et s'arrête au premier qui se remplit.
Quatre dimensions ne s'élargissent jamais — cible, outil, unité, protocole —
parce qu'elles ne décrivent pas la machine mais ce que le nombre veut dire.
Plusieurs cibles n'ont aucun niveau plus large, et c'est la même exigence :
comparer un NVMe à un disque mécanique ne produit pas une cohorte plus grande,
mais une cohorte qui compare autre chose. Le repli est **publié** (`broadened`,
`narrowerAttempts`) : un repli silencieux donnerait un chiffre qui a l'air du
même et qui n'en est pas un.

**« Un seul calcul » interdit une formule dupliquée, pas un appel au moteur.**
`GET /api/v1/reports/:id` publie désormais le SysScore entier, obtenu en
appelant `analyzeReport()` — donc `computeSysScore()`, le point unique — sur le
JSON brut. C'est ce que `/compare` faisait déjà. Ce que l'ADR interdit reste
interdit : réécrire la formule ailleurs, ou servir une note stockée comme si
elle était à jour. Les colonnes `sysScore` d'`Analysis` continuent de ne servir
qu'au tri d'une liste.

## Ce qui doit rester vrai

- **Aucun chiffre publié ne se dérive d'une donnée absente.** Une famille qui ne
  sait pas dire « non mesurable » n'a pas sa place dans ce document.
- **Un seul calcul.** `computeSysScore()` reste le point unique ; aucun rendu, ni
  l'API, ni l'interface ne recalcule.
- **Les percentiles ne viennent que d'audits SysAudit admissibles**, jamais d'une
  source externe présentée comme telle.

Si l'un des trois cesse d'être vrai, ce n'est plus la même décision.
