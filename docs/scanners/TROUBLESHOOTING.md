# Dépannage

Ce document répond à une seule catégorie de question : **« pourquoi cette donnée
n'est-elle pas là ? »**

La réponse est presque toujours écrite dans le rapport lui-même. SysAudit
n'omet jamais silencieusement : une donnée non collectée porte un **marqueur**
avec sa raison. Lire ce marqueur évite de chercher un défaut là où il n'y en a
pas.

## Lire un marqueur avant de chercher un bug

| Raison              | Ce qu'elle dit                                               | Que faire                                                                           |
| ------------------- | ------------------------------------------------------------ | ----------------------------------------------------------------------------------- |
| `NOT_COLLECTED`     | Le niveau de diagnostic choisi ne prévoit pas cette collecte | Relancer à un niveau supérieur — le niveau qui l'aurait collectée est dans `detail` |
| `NOT_AVAILABLE`     | L'outil ou le fichier source est absent de la machine        | Installer l'outil, voir [./DEPENDENCIES.md](./DEPENDENCIES.md)                      |
| `PERMISSION_DENIED` | La lecture exige des privilèges                              | Relancer en `root` / administrateur                                                 |
| `NOT_APPLICABLE`    | La question ne se pose pas sur cette machine                 | **Rien.** C'est la bonne réponse                                                    |
| `UNSUPPORTED`       | Ce système ou ce scanner ne sait pas répondre                | Vérifier [../../COMPATIBILITY.md](../../COMPATIBILITY.md)                           |
| `UNKNOWN`           | La donnée aurait dû être lisible et ne l'a pas été           | Le seul cas qui mérite une enquête                                                  |

Ces cinq premières raisons ne sont pas des échecs. `UNKNOWN` en est un.

**Un marqueur n'est jamais un zéro.** Un compteur SMART non lu n'est pas un
compteur nul ; un pare-feu illisible n'est pas un pare-feu désactivé. Si une
interface affiche `0` là où le rapport porte un marqueur, c'est l'interface qui
a tort.

## Une section entière manque

Une section **absente** et une section **vide** ne disent pas la même chose.

- **Absente** : le sous-système n'existe pas sur cette machine. Pas de Docker,
  pas de section Docker. C'est délibéré : une section Docker vide se lirait
  comme « Docker installé, aucun conteneur ».
- **Vide** : le sous-système existe et ne contient rien.

`collection.skippedSections` liste ce qui a été volontairement sauté, et
`collection.issues` ce qui a échoué. Les deux figurent dans tous les rendus.

## Le scan est lent

Le facteur dominant est le **niveau de diagnostic** :
[../produit/DIAGNOSTIC-LEVELS.md](../produit/DIAGNOSTIC-LEVELS.md) dit ce que chacun collecte.

Deux collectes coûtent structurellement cher :

- **La surveillance dans la durée** (`monitoring`) : elle échantillonne pendant
  toute la durée demandée. Le premier relevé ne produit aucun échantillon —
  sans point précédent il n'y a pas de delta, et inventer une valeur nulle
  ferait passer une machine chargée pour une machine au repos.
- **Le banc d'essai** (`benchmark`) : jamais exécuté sans demande explicite.

Si un scan traîne sans ces deux-là, le suspect est un disque qui ne répond pas
à `smartctl` ou un montage réseau injoignable.

## Le rapport est refusé à l'envoi

| Symptôme                      | Cause                                                                                                                         |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `413`                         | Rapport au-delà de `MAX_REPORT_BYTES` (10 Mio par défaut)                                                                     |
| `429`                         | Quota d'ingestion atteint — fenêtre dans `RATE_LIMIT_WINDOW`                                                                  |
| `400` avec un chemin de champ | Le rapport ne valide pas contre le schéma : le chemin exact est dans la réponse                                               |
| Version de schéma refusée     | Le rapport vient d'un scanner plus récent que l'API — voir [../format-rapport/VERSIONING.md](../format-rapport/VERSIONING.md) |

Un rapport dont la version MINOR dépasse celle que l'API sait lire est **refusé
explicitement** plutôt qu'interprété partiellement. Monter l'API, ou rescanner
avec le scanner correspondant.

## Un audit n'apparaît pas sur la page d'accueil

C'est le comportement attendu : **seuls les audits publiés y figurent.** Un
audit est privé par défaut, et le reste tant qu'il n'a pas été envoyé avec la
portée publique explicite.

Le scanner exige les deux drapeaux, `--upload` **et** `--public` : `--public`
seul échoue plutôt que de déclencher un envoi non demandé.

Cette règle a été perdue une fois — `v0.68.0` publiait tous les audits, privés
compris. Si une page d'accueil vous paraît anormalement vide, vérifiez d'abord
la visibilité des audits en base avant de conclure à une panne.

## Voir aussi

- [../produit/DIAGNOSTIC-LEVELS.md](../produit/DIAGNOSTIC-LEVELS.md) — ce que chaque niveau collecte
- [./DEPENDENCIES.md](./DEPENDENCIES.md) — ce qu'apporte chaque outil, et ce qui se passe sans lui
- [./LINUX.md](./LINUX.md) · [./WINDOWS.md](./WINDOWS.md) · [./PROXMOX.md](./PROXMOX.md)
