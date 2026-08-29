# ADR 0011 — L'application Desktop est un workspace TypeScript, pas un second projet

- **Statut** : accepté
- **Date** : 2026-08-20
- **Contexte** : fondation Desktop Windows + Linux
- **Comparaison détaillée** :
  `docs/architecture/desktop-framework-decision.md`

## Contexte

SysAudit doit fournir une application installable sous Windows et sous Linux.
La feuille de route qui ouvre ce chantier propose d'étudier en priorité .NET et
Avalonia UI, avec une architecture MVVM et une arborescence
`SysAudit.Core` / `SysAudit.Contracts` / `SysAudit.Platform.*`.

Cette proposition suppose que l'application doive contenir un cœur d'analyse.
L'audit du dépôt établit qu'elle ne le doit pas : la collecte appartient aux
scanners ([ADR 0003](0003-scanner-architecture.md)), le format appartient au
schéma Zod ([ADR 0002](0002-report-schema-versioning.md)), l'analyse appartient
à `@sysaudit/analysis-engine`, et l'ingestion appartient à l'API. Ce qu'il reste
à écrire tient en cinq gestes : lancer un processus, mesurer sa progression,
ranger le rapport, l'envoyer, le montrer.

## Décision

**L'application Desktop est `apps/desktop`, un workspace npm du monorepo,
construit avec Electron et TypeScript.**

Trois conséquences en découlent, et ce sont elles la décision :

1. **Le Desktop ne redéfinit aucun contrat.** Il dépend de
   `@sysaudit/report-schema`, `@sysaudit/analysis-engine`,
   `@sysaudit/report-renderer` et `@sysaudit/shared` comme n'importe quel autre
   workspace. Il n'existe pas de modèle de rapport propre au Desktop.
2. **Le Desktop ne collecte rien.** Il invoque les scanners existants par leur
   ligne de commande publique, celle qui est déjà documentée et déjà testée. Il
   ne les modifie pas, et leur usage autonome reste intact.
3. **Le Desktop suit la version du produit.** Celle de la racine, pas une
   numérotation à lui.

## Pourquoi pas Avalonia, qui était le candidat prioritaire

Parce qu'il aurait fallu réécrire en C# ce qui existe en TypeScript.

Le format de rapport est défini une fois, en Zod, et cette unicité est une
décision prise et tenue. `CLAUDE.md` documente ce qu'il en coûte quand elle se
relâche : `SCHEMA_VERSION` existe déjà à six endroits, et la montée en
`v0.68.0` a laissé neuf champs diverger pendant deux jours sans que personne le
remarque. Un Core en C# serait la septième copie, dans un langage que ni
`npm run typecheck` ni Vitest ne regardent.

L'échappatoire — appeler Node.js depuis C# pour valider et analyser — imposerait
un runtime Node sur la machine auditée, et annulerait ainsi le seul avantage
décisif d'Avalonia dans ce dossier : le binaire autonome.

S'ajoute, sans être la raison principale, un fait de circonstance : aucun SDK
.NET n'est installé sur la machine de développement, et l'intégration continue
GitHub est à l'arrêt pour épuisement de quota. Un socle .NET aurait été livré
sans avoir jamais été compilé. Cette objection-là disparaîtrait en installant le
SDK ; la première, non.

.NET MAUI est écarté pour une raison plus simple encore : le bureau Linux n'y
est pas officiellement pris en charge.

Tauri était le second choix, et le reste. Il a été écarté parce qu'il fait
dépendre le rendu de la vue web du système — WebKitGTK selon la distribution —
sur un produit dont la raison d'être est de tourner sur des machines
hétérogènes et mal tenues à jour.

## Conséquences

**Assumées :**

- l'application consomme 150 à 250 Mo de mémoire, contre 60 à 100 pour un
  équivalent Avalonia, et son paquet pèse 90 à 180 Mo contre 70 ;
- il n'y a pas de liaison de données MVVM native. La séparation est obtenue
  par un `core` sans aucune dépendance à Electron, testé en isolation, et une
  interface qui n'y accède que par un pont explicite et typé ;
- la solution ne s'ouvre pas dans Visual Studio 2026, critère que la feuille de
  route posait pour un socle .NET.

**Obtenues :**

- une seule chaîne de version, un seul `npm run verify`, un seul ESLint ;
- les tests du Desktop sont ramassés par Vitest sans configuration nouvelle ;
- `electron-builder` produit les quatre formats visés — `.exe`, `.msi`,
  AppImage, `.deb` — depuis un seul fichier de configuration ;
- le contenu du Desktop est vérifiable sur la machine de développement, ce qui,
  intégration continue à l'arrêt, est la seule vérification qui existe.

**Bornes :**

- le Desktop ne collecte jamais lui-même. Le jour où il le devrait, cette
  décision serait à rouvrir, et Avalonia reprendrait l'avantage ;
- le Desktop n'embarque aucun secret et ne charge aucune ressource distante ;
- l'intégration Node est coupée dans le processus de rendu, et le contexte
  isolé.
