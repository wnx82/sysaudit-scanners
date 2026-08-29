<!--
SPDX-FileCopyrightText: 2026 SysAudit
SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available
-->

# Protocole de banc d'essai

> Publié dans chaque mesure sous `benchmark.results[].protocolVersion`, et
> **dimension de la clé de cohorte** : deux mesures produites par des protocoles
> différents ne se comparent jamais.
>
> **Une version par couple cible + outil**, et non une par scanner. Toutes
> valent `1.0.0` aujourd'hui, et c'est un état, pas une règle : elles peuvent
> désormais diverger.

## Pourquoi ce document existe

`toolVersion` dit quel binaire a tourné. Il ne dit pas **comment il a été
employé** — durée, taille de bloc, nombre de passes, ordre des phases. Deux
`openssl 3.0.13` mesurés l'un sur trois secondes et l'autre sur trente ne
rendent pas des chiffres comparables, et pendant longtemps rien dans le rapport
ne permettait de le savoir.

Ce fichier dit ce que chaque version recouvre. Sans lui, le numéro serait un
talisman : il changerait quand quelqu'un y penserait, et personne ne pourrait
dire ce qu'il distingue.

## Quand incrémenter

**Dès qu'une des conditions ci-dessous change, même si l'outil ne bouge pas.**
C'est ce qui permet à la base comparative de refuser une comparaison au lieu de
publier un rang faux.

- une durée, un nombre de passes, une taille de bloc ou d'échantillon ;
- l'outil employé pour une cible, ou l'algorithme qu'on lui demande ;
- l'ordre des phases, ou la présence d'un répit entre elles ;
- ce qui décide qu'une mesure est écartée plutôt que tentée.

Corriger un libellé ou un commentaire ne change pas le protocole.

## Le numéro est **par couple cible + outil**

Il l'a longtemps été par scanner — une constante unique, publiée sur toutes les
mesures. Elle ne pouvait pas être juste : elle était censée changer dès qu'une
mesure changeait, et elle invalidait alors **toutes** les autres. Changer la
liste des scènes de glmark2 aurait cassé la comparabilité des débits disque, qui
n'avaient pas bougé — si bien que personne ne la changeait jamais, et qu'elle ne
distinguait plus rien.

Découpée par mesure, elle redevient un contrat. Trois endroits la déclarent, et
aucun ne peut appeler les deux autres :

| Où                                              | Quoi                                                         |
| ----------------------------------------------- | ------------------------------------------------------------ |
| `scanners/linux/lib/collectors/benchmark.sh`    | `bench_protocol_version`, un `case` par couple cible + outil |
| `scanners/windows/lib/collectors/benchmark.ps1` | `$script:BenchmarkProtocols`, une table de hachage           |
| `apps/api/src/catalog/benchmarks.ts`            | `protocols[]` de chaque définition, avec son contrat écrit   |

Les scanners doivent tourner sans Node.js ; l'analyse ne lit ni Bash ni
PowerShell. C'est exactement la situation de `SCHEMA_VERSION`, et elle appelle le
même remède : `benchmark-protocol-contract.test.ts` **échoue dans les deux
sens** — quand un scanner publie une version que l'analyse ne sait pas lire, et
quand l'analyse déclare une version qu'aucun scanner n'émet.

Une version que l'analyse ne connaît pas n'est pas « probablement compatible » :
la mesure est écartée avec le motif `unsupported-protocol`, distinct de
`unknown-protocol` qui dit qu'aucune version n'a été publiée. Les deux se
corrigent à des endroits opposés — monter le scanner, ou monter la plateforme —
et un seul chiffre pour les deux enverrait la moitié des exploitants au mauvais
endroit.

Deux scanners ne mesurent pas de la même façon, et le couple porte l'outil :
`storage-sequential-read|dd` et `storage-sequential-read|dotnet` sont deux
protocoles distincts, donc deux populations distinctes.

## Ce que `1.0.0` recouvre — scanner Linux

| Cible                                                 | Outil     | Ce qui est fixé                                                                                                                                                                                                    |
| ----------------------------------------------------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `cpu-single`, `cpu-multi`                             | `openssl` | `AES-128-CBC`. Durée par mesure : **5 s** au niveau ordinaire, **20 s** au niveau Poussée, surchargeable par `SYSAUDIT_BENCH_SECONDS` et **bornée à 120 s**.                                                       |
| `cpu-soak`                                            | `openssl` | Charge découpée en segments, pour contrôler la sécurité **pendant** la mesure et comparer le débit du dernier segment au premier. Ce n'est pas une mesure de pointe : elle répond à « la fréquence tient-elle ? ». |
| `memory-read`, `memory-write`, `memory-copy`          | `dd`      | Mêmes bornes de durée que ci-dessus.                                                                                                                                                                               |
| `storage-sequential-read`, `storage-sequential-write` | `dd`      | Débit séquentiel. La cible est le disque système.                                                                                                                                                                  |
| `gpu`, `cpu-gpu`, `gaming`                            | `glmark2` | `cpu-gpu` mesure le rendu **pendant** une charge processeur ; `gpu` le mesure seul. Seul leur rapport est lu.                                                                                                      |

Entre deux mesures, un **répit** de 1 s au niveau ordinaire et 5 s au niveau
Poussée : sans lui, la suivante partirait d'un processeur déjà chaud et
mesurerait le refroidissement de la précédente.

## Ce que `1.0.0` recouvre — scanner Windows

| Cible                                                 | Outil          | Ce qui est fixé                                                                                                                                                |
| ----------------------------------------------------- | -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `cpu-multi`                                           | `winsat`       | Évaluation `cpuformal` — compression et chiffrement, multi-thread. L'indice va de 1,0 à 9,9 et **ne se compare qu'à un autre indice WinSAT** ; l'unité le dit. |
| `storage-sequential-read`, `storage-sequential-write` | mesure directe | Débit séquentiel sur le volume système.                                                                                                                        |

**`cpu-soak` n'existe pas sous Windows**, et c'est une limite du protocole, pas
un oubli : la sonde `responsiveness.sustained` du SysScore exige `cpu-multi`
**et** `cpu-soak`, elle ne peut donc jamais se déclencher sur une machine
Windows. C'est relevé dans la baseline du 2026-08-24 et c'est un chantier
distinct.

## Ce qui n'est pas une mesure de banc d'essai

Trois choses vivent ailleurs dans le rapport et ne se confondent pas :

- **`benchmark`** — une charge provoquée, sous conditions connues ;
- **`monitoring.samples`** — une observation dans la durée, sans provoquer quoi
  que ce soit ;
- les sections d'inventaire (`cpus[].usagePercent`…) — un **instantané**, pris au
  moment du scan.

Un instantané n'est pas une mesure : c'est ce que la machine faisait quand on a
regardé. Les sondes du SysScore les traitent séparément, et les pénalités d'un
instantané sont volontairement trois fois plus faibles que celles d'une série.

## Reproductibilité mesurée — 2026-08-24

La question que pose la roadmap n'est pas « le protocole est-il fixé ? » mais
« deux exécutions du même protocole, sur la même machine, rendent-elles le même
chiffre ? ». Elle ne se répond pas en relisant du code.

**Méthode.** Trois exécutions successives de `sysaudit.sh --quick --benchmark`,
espacées de vingt secondes, sur une machine au repos par ailleurs. Scanner
`0.32.0`, protocole `1.0.0`. AMD Ryzen 7 9800X3D (8c/8t), 30 Gio, disque système
NVMe, GeForce RTX 5070 et Radeon intégrée — d'où deux séries pour chaque cible
graphique.

**Dispersion observée**, coefficient de variation sur les trois passes :

| Cible                      |        CV |     Étendue |
| -------------------------- | --------: | ----------: |
| `memory-write`             |     0,5 % |       1,1 % |
| `memory-copy`              |     1,2 % |       2,6 % |
| `cpu-gpu` (carte dédiée)   |     1,8 % |       4,4 % |
| `cpu-multi`                |     2,3 % |       4,9 % |
| `storage-random-read`      |     2,8 % |       6,0 % |
| `memory-read`              |     4,2 % |       9,4 % |
| `storage-sequential-write` |     4,3 % |      10,5 % |
| `storage-sequential-read`  |     5,9 % |      12,9 % |
| `cpu-single`               |     7,6 % |      18,3 % |
| `gpu`, `gaming`            | 4,9–8,7 % | 10,8–19,1 % |
| `cpu-gpu` (carte intégrée) |    12,0 % |      25,7 % |

**Ce que ces chiffres disent.** La mémoire est reproductible au point que
l'écart entre deux passes ne se voit pas. Le processeur multi-thread l'est
presque autant. Ce qui l'est mal, ce sont les mesures dont le résultat dépend
d'autre chose que du composant visé : `cpu-single` court sur un seul cœur et
suit donc les décisions d'ordonnancement et de fréquence turbo du moment, et
toutes les mesures graphiques dépendent de l'état du compositeur et de ce que la
carte affichait déjà.

**Ce qu'ils ne disent pas.** Trois passes sur **une** machine ne donnent pas un
intervalle de confiance ; elles donnent un ordre de grandeur. Elles ne disent
rien de la dispersion entre machines, qui est la seule qui compte pour un rang
centile — et c'est précisément pourquoi `MINIMUM_RANKING_SAMPLES` vaut 20 plutôt
que 5.

**Conséquence retenue.** Aucun seuil ne change. Un écart de rang bâti sur
`cpu-single` ou sur une cible graphique porte une incertitude propre à la mesure
de l'ordre de dix pour cent, et cela mérite d'être su avant d'expliquer un écart
de centile par une différence de matériel. Une comparaison sur `memory-*` ou
`cpu-multi`, elle, mesure bien la machine.

## Ce qu'une mesure écartée dit

`status` distingue trois sorts, et les confondre ferait passer une limite
d'environnement pour un défaut de la machine :

- **`completed`** — la mesure a abouti ;
- **`skipped`** — l'outil ou la place manquait. La machine n'y est pour rien ;
- **`failed`** — l'outil était là et n'a rien rendu d'exploitable. C'est un
  défaut.

Les sondes du SysScore n'acceptent que `completed`, et
`responsiveness.failures` ne compte que les `failed`.

**La version du protocole est publiée sur les trois** dès que le couple cible +
outil en a une : elle identifie la méthode qui était en vigueur, pas le sort de
la mesure.

Elle est **absente** quand le couple n'en a pas — une charge mixte annoncée avec
le seul `glmark2` parce que c'est lui qui manque, une mesure aléatoire écartée
avant que `fio` n'entre en jeu. Aucune mesure n'a eu lieu selon une méthode
nommable ; lui donner un numéro affirmerait un protocole qui n'a pas été employé.

## Quel composant une mesure désigne

`benchmark.results[].device` nomme le composant chargé, et c'est ce qui décide
qu'un rang est publiable :

| Cible                 | Ce que `device` porte                                                |
| --------------------- | -------------------------------------------------------------------- |
| `storage-*` (Linux)   | `/dev/<nom>` du disque porteur du fichier de travail                 |
| `storage-*` (Windows) | `\\.\PHYSICALDRIVEn` du disque porteur du répertoire temporaire      |
| `gpu` (Linux)         | le modèle inventorié de la carte, résolu par son adresse PCI         |
| `gpu` (Windows)       | l'adaptateur que WinSAT déclare avoir évalué                         |
| `cpu-*`, `memory-*`   | rien : la mesure décrit le seul processeur, ou la plateforme mémoire |
| `gaming`, `cpu-gpu`   | une étiquette d'affichage ; ces cibles ne décrivent aucun composant  |

**Une valeur vide est un résultat, et le bon.** Un volume réparti sur plusieurs
disques n'a pas de disque unique à nommer ; une carte dont l'adresse PCI n'est
pas lisible n'est pas identifiable. L'analyse écarte alors la mesure plutôt que
de la créditer au voisin — et surtout, une mesure **qui nomme** un composant
introuvable à l'inventaire n'est jamais rattachée « au seul composant présent » :
c'est ce raccourci qui attribuait le débit d'un disque externe au disque système,
et l'indice d'une carte dédiée à un adaptateur d'affichage virtuel.

## Voir aussi

- ../technique/BANC-ESSAI-PAR-OS.md — la matrice cible × système :
  ce que chaque scanner sait mesurer, ce qu'il relit au lieu de mesurer, et les
  durées, dépendances et privilèges que cela demande.
