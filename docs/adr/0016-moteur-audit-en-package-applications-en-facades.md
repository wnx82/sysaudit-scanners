<!--
SPDX-FileCopyrightText: 2026 SysAudit
SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available
-->

# ADR 0016 — Le moteur d'audit devient un package ; les applications n'en sont que des façades

- **Statut** : accepté
- **Date** : 2026-08-27
- **Contexte** : chantier « Applications SysAudit Windows & Linux »
  (`docs/roadmaps/2026-08-27-applications-natives/`), étapes 02 et 03
- **Prolonge** : l'[ADR 0011](0011-application-desktop-electron.md), qui place le
  Desktop dans le monorepo et lui interdit de collecter
- **Ne rouvre pas** : le choix d'Electron pour l'interface graphique

## Contexte

L'[ADR 0011](0011-application-desktop-electron.md) a fait de `apps/desktop` un
workspace TypeScript qui pilote les scanners sans les modifier. Elle a eu raison
sur le fond, et `apps/desktop/src/core` contient aujourd'hui, testé, tout ce
qu'un audit demande hors collecte : lancer un processus avec délai et
annulation, compter sa progression sur sa sortie d'erreur, valider le rapport,
le ranger, l'envoyer, le renvoyer.

Le chantier ouvert le 2026-08-27 demande une **seconde façade** : une ligne de
commande, `sysaudit scan`, pour les machines sans écran — serveurs, hyperviseurs,
tâches planifiées — et pour tout ce qui s'automatise.

Cette demande bute sur une règle du dépôt, écrite dans `CLAUDE.md` :

> **Aucun package ne dépend d'une application.**

Le moteur étant dans une application, aucune autre ne peut l'atteindre. Trois
issues, et deux sont mauvaises :

1. **La CLI importe `apps/desktop`.** Elle viole la règle, et installe un moteur
   Chromium de 180 Mo sur un serveur Debian qui n'ouvrira jamais de fenêtre.
2. **La CLI vit dans `apps/desktop/src/cli`.** Même paquet, même conséquence,
   avec en plus une application graphique dont un des points d'entrée n'est pas
   graphique.
3. **Le moteur sort de l'application.**

## Décision

**Le moteur d'audit devient `@sysaudit/audit-runner`, dans `packages/`.
`apps/desktop` et `apps/cli` en sont deux façades, à égalité, et aucune des deux
ne contient de logique d'audit.**

```text
packages/audit-runner        lancer · mesurer · valider · ranger · envoyer
        ↓                ↓
  apps/desktop       apps/cli
  rend dans une      rend sur un
  fenêtre            terminal
```

Trois conséquences en découlent, et ce sont elles la décision :

1. **Le déplacement n'est pas une réécriture.** Les neuf fichiers de tests qui
   couvrent le moteur suivent tels quels et doivent passer avant comme après.
   Un test qu'il faut réécrire pour passer signale que le déplacement a dérapé.
2. **Une façade ne décide de rien.** Le jour où l'on hésite à mettre une règle
   dans la CLI ou dans le Desktop, c'est qu'elle appartient au package. Deux
   façades qui divergent sur ce que « auditer » veut dire seraient le même
   défaut que `SCHEMA_VERSION` recopié à six endroits.
3. **La CLI suit la version du produit**, comme le Desktop. Deux numérotations
   pour deux façades du même moteur ne diraient rien de plus et se
   contrediraient un jour.

## Ce que cette décision assume

**`audit-runner` n'est pas un package comme les autres.** `CLAUDE.md` décrit
`entitlements` comme « pur et sans entrée/sortie » ; celui-ci est l'inverse : il
ouvre des processus, lit et écrit des fichiers, parle à l'API. Il est donc
**Node uniquement**, et `apps/web` ne doit jamais l'importer. Cette borne est
écrite dans son `README` et vérifiée par un test — la règle du sens des
dépendances existait déjà, mais rien ne l'exécutait.

**La ligne de commande exigera Node.js sur la machine auditée.** C'est un recul
face à `curl … | bash`, qui n'exige rien, et il faut le nommer plutôt que le
découvrir. Il est tenable parce que la CLI ne remplace rien : les scanners
autonomes gardent leur usage, `/audit/w` et `/audit/l` gardent le leur, et la
documentation continue de présenter le script en une ligne comme la voie par
défaut pour une machine nue.

Une CLI en Go ou en Rust lèverait cette contrainte. Elle réécrirait le format de
rapport dans un septième langage, que ni `npm run typecheck` ni Vitest ne
regardent — exactement le mode de panne que `CLAUDE.md` documente, et que
l'ADR 0011 a déjà refusé pour la même raison. La contrainte Node est le prix de
ce refus, et c'est le moins cher des deux.

**Le déplacement touche du code qui marche.** C'est le risque principal, et il
n'a pas d'autre parade que la discipline : `git mv` d'abord pour que
l'historique suive, renommages mécaniques ensuite, aucune assertion retouchée, et
`npm run smoke --workspace @sysaudit/desktop` en critère — c'est la seule
vérification du dépôt qui ouvre réellement la fenêtre.

## Conditions de réexamen

1. Si une troisième façade devait _collecter_ elle-même, l'ADR 0011 serait à
   rouvrir avant celle-ci, et Avalonia reprendrait l'avantage.
2. Si la contrainte Node sur la machine auditée devenait un grief documenté
   d'utilisateurs réels, un exécutable unique (Node SEA) serait la première
   réponse, et un binaire natif la seconde — dans cet ordre, parce que le
   premier ne duplique pas le format.
3. Si `audit-runner` se mettait à porter des règles d'analyse, il empiéterait sur
   `@sysaudit/analysis-engine`, et la frontière serait à retracer.
