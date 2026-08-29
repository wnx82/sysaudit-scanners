# ADR 0006 — Dépendances externes : nommer, jamais installer

- **Statut** : accepté, partiellement révisé par
  [ADR 0008](0008-installation-consentie-en-audit-administrateur.md)
- **Date** : 2026-07-29
- **Contexte** : étape 07 de la roadmap V2

> **Portée depuis le 2026-08-07.** Tout ce qui suit reste en vigueur pour l'audit
> rapide, l'audit standard, le script d'amorçage et tout lancement sans drapeau
> explicite — c'est-à-dire pour la totalité du chemin public. L'ADR 0008 ouvre
> une dérogation nommée et bornée : l'installation consentie, outil par outil,
> dans un audit `full` ou `stress` lancé à la main avec `--install-deps`. La
> ligne « installation automatique consentie » du tableau des alternatives
> écartées, plus bas, doit se lire avec cette réserve.

## Contexte

La collecte dépend d'outils système : `dmidecode` pour le SMBIOS, `smartctl`
pour la santé disque, `lspci` pour les cartes, `fio` et `glmark2` pour deux
mesures du banc d'essai. Aucun n'est indispensable — le scanner tourne partout
et dégrade explicitement — mais chacun coûte des données précises quand il
manque.

Jusqu'ici, l'utilisateur lisait « `NOT_AVAILABLE` : dmidecode absent » sans
apprendre qu'une commande d'installation lui rendrait sa carte mère, son BIOS et
ses barrettes. L'information existait ; le pont vers l'action, non.

La roadmap demandait de trancher entre trois voies :

1. un amorçage qui télécharge temporairement des dépendances vérifiées ;
2. un helper SysAudit natif ou packagé ;
3. un bundle installable optionnel par système.

## Décision

**Aucune des trois.** SysAudit nomme ce qui manque, affiche la commande exacte,
et n'installe rien.

Concrètement :

- aucun binaire tiers n'est embarqué dans le dépôt ni dans les artefacts ;
- rien n'est téléchargé à l'exécution, hors le scanner lui-même dont l'empreinte
  SHA-256 est vérifiée avant exécution ;
- aucun gestionnaire de paquets n'est appelé, ni en lecture d'état modifiant, ni
  a fortiori en installation ;
- la table `packages/platform/src/tool-dependencies.ts` dit ce que chaque outil
  débloque, sa licence amont, son paquet par famille et ce que devient la donnée
  sans lui ; `docs/scanners/DEPENDENCIES.md` en est la projection.

## Pourquoi

**Le scanner est en lecture seule, et c'est sa principale promesse.** Un scanner
qui installe des paquets modifie la machine auditée : il change l'état qu'il est
venu constater, peut casser une dépendance de production, et transforme un audit
en intervention. Aucune donnée collectée ne vaut cette perte.

**Télécharger un binaire tiers pour l'exécuter en root est exactement l'attaque
qu'on cherche à éviter ailleurs.** Le script d'amorçage vérifie déjà l'empreinte
de chaque fichier du scanner précisément pour cela. Étendre le mécanisme à des
binaires tiers demanderait de suivre leurs empreintes, leurs versions, leurs
signatures et leurs licences de redistribution — un travail permanent, pour un
gain que la commande `apt install` d'une ligne offre gratuitement.

**Un `.exe` Windows n'est pas justifié aujourd'hui.** La roadmap posait la
condition : il ne l'est que s'il améliore réellement la fiabilité, les
permissions, la collecte bas niveau ou l'expérience. Le scanner PowerShell
atteint déjà tout ce que Windows expose sans composant tiers, y compris les
débits disque, mesurés en .NET. La seule donnée hors de portée est la
température, et elle demanderait un pilote noyau signé — un projet en soi, pas
un effet de bord de cette étape.

**Ne rien redistribuer simplifie la question des licences.** Les licences amont
sont documentées pour informer le lecteur, pas pour fonder une décision de
redistribution : il n'y en a pas.

## Conséquences

- Un audit sur une machine minimale reste partiel, et le dit. C'est assumé.
- La table des dépendances doit rester synchronisée avec ce que les scanners
  sondent réellement : `tool-dependencies-contract.test.ts` échoue dans les deux
  sens, et vérifie aussi que les noms de paquets embarqués dans le scanner Bash
  correspondent à ceux de la table.
- Les noms de paquets sont recopiés dans `scanners/linux/lib/core/dependencies.sh`,
  le scanner devant tourner sans Node.js. C'est une duplication assumée, tenue
  par un test.
- Si un besoin futur justifiait un helper — la température Windows en est le
  candidat le plus sérieux —, cet ADR devra être révisé explicitement, avec
  signature de code, empreintes publiées, version et procédure de
  désinstallation. Il ne s'agira pas d'un ajustement discret.

## Alternatives écartées

| Voie                               | Pourquoi non                                                                                                         |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Amorçage téléchargeant les outils  | Exécuterait du code tiers en root sur la machine auditée ; exigerait un suivi permanent d'empreintes et de licences. |
| Helper natif packagé               | Ferait de SysAudit un logiciel installé, alors que sa force est de ne rien laisser derrière lui.                     |
| Bundle optionnel par OS            | Même problème de redistribution et de licences, pour un public qui sait déjà installer un paquet.                    |
| Installation automatique consentie | Un consentement obtenu au milieu d'un audit n'en est pas un : l'utilisateur veut un diagnostic, pas une décision.    |
