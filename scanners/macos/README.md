# Scanner macOS — EXPERIMENTAL / UNVALIDATED

> **Ce scanner n'a jamais été exécuté sur un Mac.**
>
> Il est écrit d'après la documentation d'Apple et les pages de manuel des
> outils employés. Aucune de ses sorties n'a été confrontée à une machine
> réelle.

## Ce que ce statut signifie concrètement

- Aucune de ses collectes ne justifie une case validée dans
  `packages/platform/src/compatibility.ts`.
- Un rapport qu'il produit se lit comme une **hypothèse**, pas comme une mesure.
  Les deux premières entrées de `report.notes` le disent, et l'interface les
  affiche.
- Il n'est pas distribué par l'amorçage : `BOOTSTRAPPABLE_PROFILES` ne le
  contient pas. Proposer le téléchargement d'un script jamais essayé
  reviendrait à le présenter comme utilisable.
- `report.profile` reste `quick` : les profils qui chargent la machine n'ont
  pas de sens tant que les collectes de base ne sont pas vérifiées.

## Ce qui est néanmoins garanti, et testé

`scanners/macos/tests/run.sh` — 73 tests — établit trois choses qui ne
demandent aucun Mac :

1. **Aucune commande n'est appelée sans avoir été détectée.** Toute la collecte
   passe par `have`, et un outil absent produit un marqueur motivé, jamais un
   champ vide ni un arrêt.
2. **Sur un système où aucune commande macOS n'existe**, le scanner produit tout
   de même un rapport conforme au schéma, entièrement composé de marqueurs avec
   leur raison. C'est le cas le plus dangereux : celui où un scanner mal écrit
   inventerait des zéros.
3. **Sur un macOS simulé** — de fausses commandes rendant des sorties tirées de
   la documentation — les valeurs remontent aux bons champs.

Ce que ces tests **ne prouvent pas** : que les fixtures ressemblent à un vrai
Mac. Un format de sortie qui aurait changé passerait ici et échouerait là-bas.

## Lancer

```sh
./sysaudit.sh --capabilities   # ce qui serait collecté, sans rien scanner
./sysaudit.sh --stdout         # rapport JSON sur la sortie standard
./sysaudit.sh --output-dir /tmp
```

Le scanner **refuse de tourner ailleurs que sur macOS**. Lancé sur un Linux, il
produirait un rapport plein de marqueurs qu'on lirait comme « macOS ne sait pas
répondre » — une preuve à charge contre un système qu'il n'a même pas rencontré.
Les tests contournent ce refus par `SYSAUDIT_ALLOW_FOREIGN_HOST=1`, qui n'a
aucune autre raison d'exister.

## Ce qui n'est pas collecté, et pourquoi

| Donnée                                 | Raison                                                                                                                                                           |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Journal unifié (`events`)              | `log show --last 30d` produit plusieurs gigaoctets et occupe la machine de longues minutes. Le coût est prohibitif pour un scanner qu'on n'a pas encore éprouvé. |
| Disques physiques                      | `diskutil list -plist` exige un analyseur XML, hors de portée d'un scanner shell. Les partitions viennent de `df -k -P`, dont le format est fixé par POSIX.      |
| Durée de démarrage                     | macOS ne publie aucune décomposition en phases comparable à `systemd-analyze`. En fabriquer une serait inventer.                                                 |
| Températures                           | Les capteurs thermiques d'Apple passent par une interface privée.                                                                                                |
| Capacité de batterie                   | `ioreg -rc AppleSmartBattery` n'est pas analysé par ce scanner.                                                                                                  |
| Modèle de processeur sur Apple Silicon | `machdep.cpu.brand_string` n'existe pas. Le champ reste inconnu au lieu d'être rempli avec `hw.model`, qui est le modèle de la **machine**.                      |

## Sécurité : SIP, FileVault et Gatekeeper vont dans `notes`

Le schéma porte une sous-section `security.windows` et une `security.linux`. Il
n'a **pas** d'équivalent macOS. En ajouter une serait une évolution de schéma —
et une évolution de schéma décidée par un scanner que personne n'a jamais
exécuté serait décidée à l'aveugle.

Les trois faits sont donc publiés en clair dans `report.notes`, le champ prévu
pour ce que le scanner constate sans que rien ne l'interprète automatiquement.
Une protection **non lue** y apparaît « non lu », jamais « désactivé » : les
deux n'appellent pas la même réaction.

## Pour valider ce scanner

Il faut un Mac, et une campagne du type de celles décrites dans
docs/qualite/VALIDATION-CAMPAIGNS.md. Tant qu'elle
n'a pas eu lieu, ce bandeau reste.
