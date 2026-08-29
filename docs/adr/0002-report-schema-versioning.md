# ADR 0002 — Schéma de rapport : Zod comme source unique, versionné indépendamment

- **Statut :** accepté
- **Date :** 2026-07-25

## Contexte

Le JSON SysAudit est la source de vérité de tout le produit. Il est écrit par
des scanners qui ne sont pas écrits en TypeScript (Bash, PowerShell), lu par
l'API, le rendu Markdown/HTML, le Web, les moteurs de règles et les
comparaisons d'historique. Des rapports seront archivés pendant des années et
devront rester lisibles.

Il faut donc, à partir d'une définition unique :

- des types TypeScript pour les consommateurs internes ;
- une validation à l'exécution à la frontière de l'API ;
- un artefact lisible par des outils non-TypeScript (JSON Schema) ;
- une version propre au format, distincte de celle de l'application.

## Décision

1. Le schéma est défini **une seule fois** en Zod dans
   `packages/report-schema`. Les types TypeScript sont inférés (`z.infer`) et le
   JSON Schema est **généré** à partir des mêmes définitions, jamais écrit à la
   main.
2. Le format porte sa propre version SemVer, `schemaVersion`, indépendante de
   `platformVersion` et `scannerVersion`. Les trois figurent dans chaque
   rapport.
3. Compatibilité de lecture : un lecteur implémentant `X.Y` accepte tout
   rapport `X.y` avec `y ≤ Y`. Une version MAJOR différente ou une MINOR plus
   récente est **refusée explicitement**, jamais interprétée partiellement.
4. Tout nouveau champ est optionnel (MINOR). Supprimer, renommer un champ ou
   changer sa sémantique est un MAJOR et impose un adaptateur de lecture dans
   `src/migrations/`.
5. Une donnée non collectée est représentée par un marqueur explicite
   (`UNKNOWN`, `NOT_AVAILABLE`, `UNSUPPORTED`, `PERMISSION_DENIED`) et non par
   l'absence du champ ou une valeur par défaut : l'absence de disque et
   l'absence de `smartctl` ne doivent pas produire le même rapport.

## Alternatives considérées

**JSON Schema écrit à la main comme source.** Interopérable par nature, mais
impose de maintenir en parallèle des types TypeScript, qui divergent
inévitablement. Écarté.

**TypeBox.** Produit nativement du JSON Schema et s'intègre bien à Fastify.
Écarté de justesse : Zod offre une meilleure ergonomie de transformation et de
messages d'erreur, ce qui compte pour renvoyer au scanner une raison de rejet
compréhensible. La génération de JSON Schema depuis Zod couvre le besoin.

**Types TypeScript seuls.** Aucune validation à l'exécution : un rapport
malformé ou malveillant atteindrait la base. Inacceptable pour une frontière
publique.

**Une seule version pour tout le projet.** Écarté : un correctif d'interface Web
forcerait une nouvelle version de format, et l'historique des rapports
deviendrait illisible.

## Conséquences

Positives :

- Une seule définition à maintenir ; types et validation ne peuvent pas diverger.
- Les scanners non-TypeScript valident leur sortie contre le JSON Schema publié.
- Un rapport ancien reste lisible, ou est refusé avec un message explicite.

Négatives :

- Toutes les constructions Zod ne se traduisent pas en JSON Schema. Atténuation :
  se limiter au sous-ensemble traduisible, vérifié par un test qui génère le
  JSON Schema et valide les fixtures avec un validateur JSON Schema standard.
- Le versionnement du schéma exige de la discipline à chaque modification.
  Atténuation : un test échoue si le schéma change sans que `schemaVersion` ait
  été révisé.
