# Schéma du rapport SysAudit

Le JSON produit par un scanner est la **source de vérité** de SysAudit. Tous les
autres artefacts (Markdown, HTML, rapport Web, historique, comparaisons,
recommandations, analyse IA) en dérivent.

- Version actuelle du schéma : **`1.13.0`**
- Définition : `packages/report-schema/src/` (Zod)
- JSON Schema généré : `packages/report-schema/schema/` après `npm run build`
- Règles de versionnement : [./VERSIONING.md](./VERSIONING.md), [ADR 0002](../adr/0002-report-schema-versioning.md)

## Principe : un rapport ne contient que des faits mesurés

Aucun score, aucune recommandation, aucune comparaison de version de firmware
n'y figure. Ces analyses sont calculées à partir du rapport et stockées
séparément, ce qui permet de les recalculer quand une règle évolue, sans
redemander de scan.

## Principe : une donnée absente dit pourquoi elle l'est

Un champ qu'un scanner **tente** de collecter porte soit sa valeur, soit un
marqueur explicite :

```json
{
  "manufacturer": "ASUSTeK COMPUTER INC.",
  "serialNumber": { "unknown": true, "reason": "PERMISSION_DENIED" },
  "chassisType": { "unknown": true, "reason": "NOT_AVAILABLE", "detail": "dmidecode absent" }
}
```

| Raison              | Signification                                                  |
| ------------------- | -------------------------------------------------------------- |
| `UNKNOWN`           | L'information devrait être disponible mais n'a pas pu être lue |
| `NOT_AVAILABLE`     | L'outil ou la source d'information est absent du système       |
| `UNSUPPORTED`       | Le système ou le scanner ne supporte pas cette collecte        |
| `PERMISSION_DENIED` | Privilèges insuffisants                                        |
| `NOT_COLLECTED`     | Le niveau de diagnostic choisi ne prévoit pas cette collecte   |
| `NOT_APPLICABLE`    | Il n'y a rien à mesurer ici : la question ne se pose pas       |

`NOT_APPLICABLE` se distingue d'`UNSUPPORTED`. Le second dit « ce système ne
sait pas répondre », le premier « il n'y a pas de réponse à donner ». Un hôte
Proxmox hors cluster n'a pas un quorum illisible : il n'a pas de quorum. Sans
cette distinction, l'absence de cluster se lirait comme un cluster en panne.

`NOT_COLLECTED` se distingue de `NOT_AVAILABLE` : la source existe peut-être
très bien sur cette machine, elle n'a simplement pas été interrogée. Le `detail`
indique le niveau qui l'aurait collectée — voir
[../produit/DIAGNOSTIC-LEVELS.md](../produit/DIAGNOSTIC-LEVELS.md).

Une **section absente** signifie que le scanner n'a pas tenté la collecte (niveau
choisi, plateforme sans objet). `collection.skippedSections` la nomme, et
`collection.issues` en donne le motif. Un **champ présent avec un marqueur** signifie
qu'il a essayé sans y parvenir. La distinction est volontaire : sans elle,
« aucun disque » et « impossible de lire les disques » seraient indiscernables.

Quand le scanner connaît précisément l’origine d’une donnée, il peut aussi
renseigner `collection.provenance` avec un chemin de rapport (`audio.devices`,
`startup.items`…), la source interrogée, la méthode et l’horodatage de lecture.
Cette provenance reste optionnelle et ciblée : elle documente les sections où
la traçabilité aide réellement à relire le scan.

Aucune valeur n'est jamais inventée, ni remplacée par une valeur par défaut
plausible. En TypeScript, `isKnown()` / `valueOr()` de `@sysaudit/shared`
permettent de manipuler ces champs.

## Structure

```jsonc
{
  "schemaVersion": "1.13.0", // version du format
  "scannerVersion": "0.12.0", // version du scanner qui a produit le rapport
  "platformVersion": "0.13.0", // optionnel

  "report": {/* métadonnées : date, durée, profil, anonymisation */},
  "capabilities": {/* ce que le scanner a pu faire sur cette machine */},

  "system": {/* hostname, constructeur, modèle, UUID, uptime */},
  "os": {/* OS, distribution, version, kernel, support éditeur */},

  "motherboard": {/* fabricant, modèle, chipset, socket, slots */},
  "bios": {/* version, date, UEFI/Legacy, Secure Boot, SMBIOS */},
  "cpus": [/* modèle, cœurs, fréquences, cache, virtualisation */],
  "memory": {/* modules, capacité installée, slots libres, profil mémoire si exposé */},
  "gpus": [/* modèle, VRAM, driver, écrans */],
  "audio": {/* périphériques audio, pile logique, état, défaut si connu */},
  "sensors": {/* températures, ventilateurs, tensions, alimentations */},
  "power": {/* batteries, capacités mesurées, alimentation secteur */},

  "storage": {
    /* disques, SMART/NVMe, lien PCIe/SATA si exposé, TRIM, partitions, ensembles RAID/LVM/ZFS */
  },
  "network": {/* interfaces, IP, DNS, Wi-Fi, routes, proxy, ports en écoute */},
  "devices": {/* PCI, USB, hardware IDs, statut des pilotes, lien PCIe */},
  "drivers": [/* pilotes installés et leur statut */],
  "firmware": [/* versions installées et disponibles */],

  "software": {/* paquets, gestionnaires, runtimes, services */},
  "startup": {/* éléments lancés au démarrage machine ou session */},
  "security": {/* firewall, mises à jour, comptes, Windows/Linux */},
  "virtualization": {/* Docker, Podman, libvirt, Proxmox */},

  "stability": {/* incidents observés, compteurs et fenêtre couverte */},
  "boot": {/* séquence de démarrage : phases, éléments lents, échecs */},
  "shutdown": {/* dernier arrêt : propreté, motif, durée */},
  "events": {/* journaux natifs normalisés et regroupés par empreinte */},

  "monitoring": {/* série temporelle, si `--monitor` a été demandé */},
  "benchmark": {/* mesures de performance, si `--benchmark` a été demandé */},

  "collection": {/* problèmes rencontrés, sections ignorées, provenance optionnelle */},
}
```

Seuls `schemaVersion`, `scannerVersion`, `report`, `capabilities`, `system`,
`os` et `collection` sont obligatoires. Un scanner minimal produit donc un
rapport valide même sans privilèges ni outil.

## `capabilities` : la clé de lecture du rapport

```json
{
  "platform": "linux",
  "distribution": "Debian",
  "architecture": "x86_64",
  "privileged": true,
  "proxmox": true,
  "docker": true,
  "tools": { "dmidecode": true, "smartctl": true, "sensors": false },
  "features": { "events": "AVAILABLE", "boot.fastStartupEnabled": "NOT_APPLICABLE" }
}
```

Sans cette section, un `NOT_AVAILABLE` serait ininterprétable. Avec elle, le
rapport Web peut expliquer à l'utilisateur qu'installer `smartctl` débloquerait
la santé des disques.

`tools` dit quels **binaires** existent ; `features` dit quelles **questions**
ont une réponse sur cette machine. Les deux ne se déduisent pas l'un de
l'autre : `journalctl` peut être installé et refuser l'accès faute de
privilèges, et une machine sans `smartctl` peut lire des compteurs de fiabilité
par une autre voie. Ses valeurs sont `AVAILABLE` plus les raisons d'absence
ci-dessus.

## `power` : ce que le rapport ne dit pas

La section `power` porte les deux capacités de batterie **mesurées** — celle de
conception et celle en pleine charge — mais **pas** l'usure qui s'en déduit.

C'est délibéré. L'usure est une interprétation : le seuil à partir duquel une
batterie est « usée » relève de la règle d'analyse, pas de la mesure. En la
laissant hors du rapport, un changement de seuil se rejoue sur les audits déjà
stockés, sans redemander de scan (ADR 0003).

Le même raisonnement s'applique au lien PCIe : `devices[].link` rapporte la
largeur négociée **et** la largeur maximale, sans conclure. Une carte en x4 sur
un lien x4 fonctionne à son maximum ; seule la comparaison des deux valeurs a un
sens, et elle appartient au moteur d'analyse.

## `stability`, `boot`, `shutdown`, `events` : ce que la machine a vécu

L'inventaire dit qu'un disque existe ; seul l'historique dit qu'il jette une
erreur toutes les nuits depuis trois semaines. Ces quatre sections portent cette
seconde question, et suivent trois règles propres.

**Un compteur ne se lit jamais sans sa fenêtre.** « Trois pannes » est rassurant
sur un an et alarmant sur une journée. Chaque compteur porte donc
`observationWindowMs` à côté de sa valeur :

```json
{
  "storageErrors": {
    "count": 47,
    "observationWindowMs": 1814400000,
    "lastAt": "2026-07-25T04:12:09Z",
    "source": "journalctl -k -p err"
  }
}
```

**La fenêtre demandée n'est pas la fenêtre obtenue.** `events.window` porte les
deux. Demander quatre-vingt-dix jours à un système dont `journald` écrit en
mémoire ne donne pas quatre-vingt-dix jours ; sans `coveredMs` et `persistent`,
« aucun incident » se lirait comme un trimestre sain alors que la fenêtre repart
de zéro à chaque démarrage.

**Les incidents sont regroupés, pas déversés.** Un disque qui meurt écrit la
même ligne des milliers de fois. Chaque entrée porte une `fingerprint` stable
entre deux scans, un compteur `occurrences`, et au plus trois `evidence` — les
lignes brutes qui la fondent, sans lesquelles l'alerte n'est pas vérifiable.
Ces extraits sont **réservés au propriétaire de la machine** : une ligne de
journal contient ce qu'elle veut, et l'API les retire pour tout autre lecteur.

Le découpage de `boot.phases` reste **natif et non normalisé** : `systemd-analyze`
et les journaux Diagnostics-Performance ne mesurent pas les mêmes bornes, et
forcer une correspondance produirait une comparaison fausse entre un Linux et un
Windows.

## Ce que le schéma interdit structurellement

- **Aucun secret.** Aucun champ ne prévoit de mot de passe, hash, clé, token ou
  cookie. Les variables d'environnement de conteneurs ne sont pas modélisées :
  seuls des indicateurs de configuration à risque le sont. La clé Wi-Fi n'a
  aucun champ ; seul le SSID en a un.
- **Aucun champ inconnu.** La validation retire tout champ hors schéma : un
  scanner modifié ne peut pas faire transiter de données arbitraires jusqu'au
  stockage.
- **Toute chaîne est bornée.** Un rapport est une entrée non fiable ; des
  longueurs non bornées seraient un vecteur de déni de service.
- **Toute recommandation externe est sourcée.** Un statut de fin de support ou
  une version de firmware disponible exige un objet `source` et un niveau de
  confiance (`HIGH` / `MEDIUM` / `LOW`).

## Où va chaque section, une fois collectée

Une donnée collectée puis jamais affichée coûte le temps de collecte, la place
en base et la surface d'attaque, sans rien rendre. Une carte d'interface
alimentée par un champ qui n'existe pas coûte pire : elle affirme.

`packages/report-schema/src/traceability.ts` déclare, pour chaque section
racine, ce qui la consomme en aval — projection en base, rendu autonome,
interface Web, règles d'analyse, contexte transmis à l'IA.

Le registre n'est pas décoratif : `traceability.test.ts` **échoue** si une
section du schéma n'y figure pas, et exige une justification écrite pour toute
section que rien ne consomme. Ajouter une section oblige donc à décider de son
sort. Ce que le test ne fait pas, c'est vérifier que la déclaration est vraie :
`renderer: true` reste une affirmation de relecture, pas une preuve.

Trois écarts sont ouverts et assumés dans le registre :

| Section     | Écart                                                           | Traité à |
| ----------- | --------------------------------------------------------------- | -------- |
| `firmware`  | définie au schéma, collectée par aucun scanner                  | étape 08 |
| `sensors`   | jamais transmise à l'IA : elle juge une machine sans sa chaleur | étape 09 |
| `benchmark` | jamais transmis à l'IA non plus                                 | étape 09 |

## Validation

En TypeScript :

```ts
import { validateReport } from '@sysaudit/report-schema';

const result = validateReport(json);
if (!result.ok) {
  console.error(result.code, result.message, result.issues);
} else {
  result.report; // typé, normalisé, sans champ inconnu
}
```

Codes d'erreur possibles :

| Code                     | Cause                                                |
| ------------------------ | ---------------------------------------------------- |
| `MALFORMED`              | L'entrée n'est pas un objet JSON                     |
| `MISSING_SCHEMA_VERSION` | `schemaVersion` absent ou non SemVer                 |
| `INCOMPATIBLE_MAJOR`     | Version MAJOR différente du lecteur                  |
| `UNSUPPORTED_MINOR`      | Rapport produit par un scanner plus récent           |
| `SCHEMA_VIOLATION`       | Rapport non conforme, avec les chemins JSON fautifs  |
| `SECRET_DETECTED`        | Un secret a été détecté : rapport refusé, non stocké |

La version est vérifiée **avant** le schéma : un rapport plus récent reçoit un
message clair au lieu d'une avalanche d'erreurs de champs.

Hors TypeScript, utiliser le JSON Schema généré (`schema/sysaudit-report-latest.schema.json`)
avec n'importe quel validateur JSON Schema 2020-12.

## Compatibilité

Un lecteur implémentant `X.Y` accepte tout rapport `X.y` avec `y ≤ Y`. Un
rapport de version MAJOR différente, ou de MINOR plus récente, est **refusé
explicitement** plutôt qu'interprété partiellement.

Les rapports plus anciens restent lisibles. Lorsqu'une rupture de format
deviendra nécessaire, un adaptateur sera ajouté dans
`packages/report-schema/src/migrations/`, dont le moteur est déjà en place et
testé.

## Faire évoluer le schéma

1. Modifier la définition Zod dans `packages/report-schema/src/`.
2. Lancer `npm run test` : le test d'empreinte du JSON Schema échoue
   volontairement, pour forcer une décision de version.
3. Déterminer le niveau (ajout d'un champ optionnel → MINOR ; suppression,
   renommage ou changement de sémantique → MAJOR).
4. Mettre à jour `SCHEMA_VERSION`, le `CHANGELOG.md`, et la nouvelle empreinte
   dans `json-schema.test.ts`.
5. En cas de MAJOR, ajouter la migration correspondante et son test.
