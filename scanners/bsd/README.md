# Scanner FreeBSD · pfSense · OPNsense — EXPERIMENTAL / UNVALIDATED

> **Ce scanner n'a jamais été exécuté sur un FreeBSD, un pfSense ni un
> OPNsense.**
>
> Il est écrit d'après les pages de manuel de FreeBSD et la documentation des
> deux appliances. Aucune de ses sorties n'a été confrontée à une machine
> réelle.

## Ce que ce statut signifie

Identique à celui du [scanner macOS](../macos/README.md) : aucune case validée
dans la matrice de compatibilité, un rapport qui se lit comme une hypothèse, et
aucune distribution par l'amorçage.

## Une appliance n'est pas un serveur

pfSense et OPNsense **sont** des FreeBSD, et ce scanner les traite comme tels
pour tout ce qui vient du système. Deux différences changent pourtant la
lecture d'un rapport, et il les publie plutôt que de les gommer.

### L'appliance est le pare-feu

Sur un serveur, un pare-feu inactif est un défaut parmi d'autres. Sur un
routeur de bordure, `pf` **est** la fonction de la machine : un `pf` désactivé y
est un incident majeur, pas un durcissement manquant. Le scanner écrit cette
phrase dans `report.notes` dès qu'il reconnaît une appliance.

Conséquence directe sur le vocabulaire d'absence : `pfctl` exige root, et sans
élévation son échec est rapporté **`PERMISSION_DENIED`**, jamais
`NOT_AVAILABLE`. Dire « pare-feu non disponible » d'une machine dont c'est la
raison d'être serait le pire contresens que ce rapport puisse commettre.

### La version de l'appliance n'est pas celle de FreeBSD

OPNsense 24.7 tourne sur une base FreeBSD 13, pfSense 2.7 sur une autre.
Confondre les deux ferait conclure à une fin de support qui n'existe pas. Le
scanner publie donc `os.version` (l'appliance) et `os.build` (la base) comme
deux champs distincts, et écrit une note qui rappelle de ne pas les confondre.

### La détection se fait sur des fichiers, jamais sur un nom

| Système  | Marqueur                           |
| -------- | ---------------------------------- |
| OPNsense | `/usr/local/opnsense/version/core` |
| pfSense  | `/etc/version` **et** `/cf/conf`   |
| FreeBSD  | aucun des deux                     |

`/etc/version` seul ne suffit pas : d'autres systèmes en ont un. Et un FreeBSD
sur lequel quelqu'un aurait installé un paquet nommé « pfSense » reste un
FreeBSD — le déclarer appliance ferait lire tout le reste du rapport de travers.
Quatre tests couvrent ces cas, racine simulée à l'appui.

## Le piège de `hw.model`

Sur FreeBSD, `sysctl hw.model` nomme le **processeur**. Sur macOS, il nomme la
**machine**. Le recopier dans `system.model` produirait une machine
« Intel(R) Xeon(R) », ce qui est faux deux fois : ce n'est ni le modèle ni le
fabricant. Le modèle et le fabricant viennent donc de `kenv smbios.system.*`, et
restent inconnus si `kenv` ne répond pas.

De même, `hw.ncpu` compte les processeurs **logiques**. Les cœurs physiques
exigeraient d'analyser `kern.sched.topology_spec`, un document XML : le champ
reste inconnu plutôt que déduit d'une division par deux, qui serait fausse sur
tout processeur sans SMT.

## Ce qui n'est pas collecté, et pourquoi

| Donnée                       | Raison                                                                                                                                                                                                                                                                 |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Journal normalisé (`events`) | Les lignes de `dmesg` ne sont pas classées : classer sans avoir observé de sortie réelle rangerait tout en `OTHER`, et un `OTHER` généralisé pèserait sur le mauvais score.                                                                                            |
| Disques physiques            | `camcontrol devlist` et `geom disk list` ne sont pas analysés. Les partitions viennent de `df -k -P`.                                                                                                                                                                  |
| Taille des pools ZFS         | `zpool list` rend « 1.81T ». Convertir par une table d'unités écrite à la main introduirait une erreur d'arrondi silencieuse. L'**état** du pool, lui, est publié tel quel : un pool `DEGRADED` est le fait le plus important qu'un rapport de stockage puisse porter. |
| Températures                 | `dev.cpu.0.temperature` exige le module `coretemp` ou `amdtemp`, dont le chargement n'est pas tenté — un scanner read-only ne charge pas de module.                                                                                                                    |
| Chiffrement GELI             | `geli status` demande l'élévation.                                                                                                                                                                                                                                     |

## La fenêtre d'observation est l'uptime

`dmesg` ne couvre que le **démarrage courant**, et son tampon est circulaire :
sur une machine chargée, les lignes du démarrage ont pu être écrasées. La
fenêtre annoncée est donc l'uptime, jamais une durée choisie, et
`events.window.persistent` vaut `false`.

## Lancer

```sh
./sysaudit.sh --capabilities
./sysaudit.sh --stdout
sudo ./sysaudit.sh --output-dir /root/audit   # root pour lire pf
```

Le scanner refuse de tourner ailleurs que sur FreeBSD.
`SYSAUDIT_ALLOW_FOREIGN_HOST=1` lève ce refus et n'existe que pour les tests.

## Pour valider ce scanner

Un FreeBSD, un pfSense **et** un OPNsense, chacun avec une campagne du type de
celles décrites dans
docs/qualite/VALIDATION-CAMPAIGNS.md. Valider sur
l'un ne vaut pas pour les deux autres : c'est exactement la confusion que la
détection sur fichiers cherche à éviter.
