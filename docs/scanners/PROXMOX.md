# Proxmox VE

Ce que SysAudit lit sur un hôte Proxmox VE, avec quelles commandes, ce qui exige
`root`, et ce que l'analyse en fait.

Rien n'est écrit, rien n'est démarré, rien n'est arrêté. Toutes les commandes
listées ici sont des lectures — c'est la même règle que sur un Linux ordinaire
([./LINUX.md](./LINUX.md)), et elle vaut aussi pour l'API locale : `pvesh get` est
une lecture, `pvesh set` n'apparaît nulle part.

## Reconnaissance de l'hôte

La section `virtualization.proxmox` n'est produite que si `pveversion` répond.
Un Debian ordinaire ne produit donc pas une section Proxmox vide, il n'en
produit **aucune** — la distinction compte : une section vide se lit comme « un
hyperviseur sans machine virtuelle ».

Le nom du nœud vient de `hostname`, jamais d'une valeur du rapport. Le scanner
ne construit aucun argument de commande à partir d'une donnée non fiable
([SECURITY.md](../../SECURITY.md)).

## Commandes exécutées

| Commande                                   | Ce qu'elle apporte                                  | `root`       |
| ------------------------------------------ | --------------------------------------------------- | ------------ |
| `pveversion`                               | Version de PVE — c'est elle qui déclenche tout      | non          |
| `pvecm status`                             | Mode grappe, nombre de nœuds, quorum                | non          |
| `qm list`, `qm config <vmid>`              | Machines virtuelles : état, cœurs, mémoire          | `config` oui |
| `pct list`, `pct config <ctid>`            | Conteneurs LXC : mêmes champs                       | `config` oui |
| `pvesm status`                             | Espaces de stockage, taille et occupation           | non          |
| `pvesh get /nodes/<nœud>/tasks`            | Tâches en échec sur sept jours, dernière sauvegarde | non          |
| `systemctl is-active` sur les services PVE | Services propres à l'hyperviseur en échec           | non          |
| `ceph health`                              | Santé Ceph, si `/etc/pve/ceph.conf` existe          | non          |
| `pvesr status`                             | Réplications ZFS en échec                           | non          |
| `ha-manager status`                        | Haute disponibilité, si elle est configurée         | non          |

### Ce que `root` change, exactement

`qm config` et `pct config` sont réservés à `root`. Sans lui, les machines et
les conteneurs restent **listés** — identifiant, nom, état — mais leurs cœurs,
leur mémoire et leur démarrage automatique portent le marqueur
`PERMISSION_DENIED` avec le motif. Ils ne valent pas zéro : un audit non
privilégié dit ce qu'il n'a pas pu lire, il ne le devine pas.

## Les sous-systèmes absents ne valent pas « dégradé »

Ceph, la réplication et la haute disponibilité sont **facultatifs** dans
Proxmox. Un nœud sans Ceph n'est pas un nœud dont Ceph va mal : la section porte
`NOT_APPLICABLE`, jamais `0` ni `degraded`. C'est la même règle que partout
ailleurs dans SysAudit — ne jamais conclure à partir d'une donnée absente.

Le cas du nœud isolé mérite d'être dit, parce qu'il a produit un faux constat
avant d'être traité : sur un nœud hors grappe, Proxmox laisse `corosync`,
`pve-ha-lrm` et `pve-ha-crm` **activés** mais ne les démarre pas. C'est l'état
normal. Le scanner ne les compte donc en échec que si la machine est réellement
en grappe — `pvecm status` échoue sur un nœud isolé, et cet échec **est** la
réponse.

## Fenêtre des tâches

`failedTasks` compte les tâches en échec sur **sept jours**, et le rapport
publie cette durée dans `taskWindowMs`. Les deux sont indissociables : « trois
échecs » ne veut rien dire sans la fenêtre sur laquelle ils sont survenus.

## Ce que l'analyse en fait

| Règle     | Déclenchement                                                                                                        |
| --------- | -------------------------------------------------------------------------------------------------------------------- |
| `DIA-008` | Virtualisation matérielle désactivée alors que l'hôte héberge réellement des invités — la sévérité monte dans ce cas |
| `DIA-011` | Un stockage Proxmox au-delà de 85 % d'occupation : sauvegardes et instantanés vont échouer                           |
| `DIA-012` | Grappe sans quorum : plus aucune machine ne peut être démarrée ni modifiée                                           |

Chacune a un test de déclenchement **et** un test de non-déclenchement quand la
donnée est absente. Une machine dont le stockage n'a pas pu être lu ne déclenche
pas `DIA-011`.

## Vérifier sur une vraie machine

La procédure de campagne, avec les commandes exactes et ce qu'on attend en
sortie, est dans ../qualite/VALIDATION-CAMPAIGNS.md § Campagne Proxmox VE.
Elle est la seule qui ait été menée jusqu'au bout à ce jour — PVE 9.2.4, six
rapports conformes — et elle sert de modèle aux autres.

Le script `scripts/validate-linux-scanner.sh` refuse de tourner sur un Debian
ordinaire : il produirait un rapport valide sans une seule donnée PVE, ce qui
est exactement le genre de vert qui ne prouve rien.

## Voir aussi

- [./LINUX.md](./LINUX.md) — le scanner Linux dont celui-ci est une extension
- [./TROUBLESHOOTING.md](./TROUBLESHOOTING.md) — quand une section manque
- [../../COMPATIBILITY.md](../../COMPATIBILITY.md) — état de validation par système
