# macOS, FreeBSD, pfSense et OPNsense — étude technique

Étude préalable à l'extension du scanner vers macOS et les systèmes BSD.
**Rien n'est implémenté** : ce document dit ce qui serait collectable, par quelle
commande, et où l'intuition venue de Linux se trompe.

## Trois familles, pas une

Les regrouper sous « Unix » serait l'erreur à éviter. Elles n'ont ni les mêmes
outils, ni les mêmes garanties, ni le même objet d'audit.

| Cible              | Nature               | Ce qu'on audite                   |
| ------------------ | -------------------- | --------------------------------- |
| macOS              | poste de travail     | matériel, sécurité, mises à jour  |
| FreeBSD            | serveur généraliste  | comme Linux, avec d'autres outils |
| pfSense / OPNsense | **appliance réseau** | l'infrastructure, pas le poste    |

Le troisième cas est le plus important à traiter à part : un pare-feu n'est pas
un serveur Unix qui ferait du routage. Ce qui compte sur une machine — RAM
libre, paquets installés — y est secondaire ; ce qui compte, ce sont les
interfaces, les règles, les routes, les VPN, les baux et les services.

## macOS

Le scanner s'y écrirait en shell, comme sous Linux, mais aucune commande n'est
la même.

| Donnée               | Commande                                           | Privilège |
| -------------------- | -------------------------------------------------- | --------- |
| Matériel complet     | `system_profiler -json SPHardwareDataType`         | non       |
| Modèle, numéro série | `system_profiler SPHardwareDataType`               | non       |
| CPU, mémoire, cœurs  | `sysctl -a` (`hw.*`, `machdep.cpu.*`)              | non       |
| Version du système   | `sw_vers`                                          | non       |
| Stockage et volumes  | `diskutil list -plist`, `diskutil info -plist`     | non       |
| SMART                | `diskutil info` (verdict) ; `smartctl` non fourni  | non       |
| Réseau               | `ifconfig`, `networksetup -listallhardwareports`   | non       |
| Wi-Fi                | `wdutil info` (macOS 13+)                          | **oui**   |
| Pare-feu applicatif  | `socketfilterfw --getglobalstate`                  | non       |
| FileVault            | `fdesetup status`                                  | non       |
| SIP                  | `csrutil status`                                   | non       |
| Gatekeeper           | `spctl --status`                                   | non       |
| Mises à jour         | `softwareupdate --list`                            | non       |
| Applications         | `system_profiler SPApplicationsDataType`           | non       |
| Batterie             | `pmset -g batt`, `system_profiler SPPowerDataType` | non       |
| Températures         | **aucune source publique stable**                  | —         |

Quatre pièges, tous vérifiés dans la documentation Apple :

- **`system_profiler` est lent.** `SPApplicationsDataType` peut prendre plusieurs
  dizaines de secondes. Il ne doit pas entrer dans un profil rapide ;
- **Apple Silicon et Intel ne rapportent pas les mêmes clés `sysctl`.**
  `machdep.cpu.brand_string` existe des deux côtés, mais le détail des cœurs
  diffère : les cœurs performance et efficience sont deux compteurs distincts,
  et les additionner produit un nombre qui ne veut rien dire ;
- **TCC** (le contrôle d'accès aux données) peut refuser la lecture de certains
  répertoires même à root. Un refus doit produire `permission_required` ;
- **`wdutil` exige root**, et le SSID est une donnée anonymisable — la même règle
  que sous Linux s'applique.

## FreeBSD

Le plus proche du scanner Linux existant, ce qui est un piège en soi : les
commandes se ressemblent sans se comporter pareil.

| Donnée               | Commande                                       |
| -------------------- | ---------------------------------------------- |
| Matériel, CPU, RAM   | `sysctl hw.*`, `dmesg`                         |
| SMBIOS               | `kenv smbios.*`                                |
| Disques              | `geom disk list`, `camcontrol devlist`         |
| SMART                | `smartctl` (paquet `smartmontools`)            |
| Systèmes de fichiers | `df -k`, `zpool list`, `zfs list`              |
| Réseau               | `ifconfig`, `netstat -rn`                      |
| Ports en écoute      | `sockstat -4 -6 -l`                            |
| Paquets              | `pkg info`, `pkg audit -F`                     |
| Services             | `service -e`                                   |
| Mises à jour         | `freebsd-update fetch --not-running-from-cron` |
| Jails                | `jls -N`                                       |

Différences qui cassent une réécriture naïve :

- `ps` et `df` n'acceptent pas les mêmes options qu'sous Linux ; `df -h` diffère
  dans son arrondi ;
- il n'y a **pas** de `/proc` par défaut : `sysctl` remplace la quasi-totalité
  des lectures de `/proc` et `/sys` ;
- `ifconfig` est la source de vérité réseau — `ip` n'existe pas ;
- **ZFS est courant, pas exotique.** Ignorer `zpool status` reviendrait à ne rien
  dire de la santé du stockage sur la moitié des installations.

## pfSense et OPNsense — audit d'infrastructure

Les deux dérivent de FreeBSD : tout ce qui précède s'y applique. Mais un audit
qui se contenterait de cela passerait à côté de l'objet.

Ce qu'il faut collecter, par ordre d'importance :

| Domaine        | Source                                                      |
| -------------- | ----------------------------------------------------------- |
| Interfaces     | `ifconfig`, configuration XML                               |
| Pare-feu       | `pfctl -sr` (règles), `pfctl -si` (état), `pfctl -sn` (NAT) |
| Tables d'états | `pfctl -ss` (comptage), limite `pfctl -sm`                  |
| Routes         | `netstat -rn`                                               |
| VLAN           | configuration XML, `ifconfig`                               |
| Passerelles    | état des `gateways`, surveillance de latence                |
| VPN            | `wg show`, état IPsec, sessions OpenVPN                     |
| DNS            | Unbound / Resolver : état, redirecteurs                     |
| DHCP           | baux actifs, portée, réservations                           |
| Services       | `service -e`, paquets additionnels installés                |
| Version        | `opnsense-version` / `pfSense-repo`, correctifs disponibles |

Trois points méritent d'être traités comme des constats, pas comme des mesures :

- **le nombre d'états proche de la limite** est un signal d'épuisement imminent,
  pas une statistique. Il mérite une règle d'analyse dédiée ;
- **une passerelle en surveillance dégradée** dit quelque chose que la latence
  moyenne ne dit pas ;
- **une règle « any → any »** est un constat de sécurité, au même titre qu'un SSH
  root autorisé.

Deux précautions de confidentialité, plus fortes qu'ailleurs : la configuration
d'un pare-feu contient des **adresses de réseaux internes**, des noms de sites
distants et parfois des identifiants de tunnels. Un rapport d'appliance doit
donc être anonymisable au moins aussi finement qu'un rapport de poste — et les
règles ne doivent jamais être rapportées avec leurs commentaires, qui portent
souvent des noms de clients.

**Aucun secret ne doit être lu**, jamais : ni clé pré-partagée IPsec, ni clé
privée WireGuard, ni certificat. La règle existante du dépôt s'applique sans
exception.

## Évolution du schéma nécessaire

`capabilities.platform` accepte déjà `macos` et `freebsd`, et `os.family` aussi.
Les sections existantes couvrent l'essentiel des trois familles.

Deux ajouts seraient nécessaires pour les appliances, tous deux **optionnels**
donc MINOR :

- `network.firewall.states` — compteur d'états et limite, avec leur unité ;
- une section `appliance` pour passerelles, VPN et baux DHCP, sans équivalent
  dans les sections actuelles.

Ils ne sont **pas** faits ici, pour la même raison qu'à l'étape 18 : un champ
qu'aucun scanner ne remplit apparaîtrait vide partout et ferait annoncer une
capacité inexistante.

## Décision

macOS, FreeBSD, pfSense et OPNsense restent **⏳ prévus** dans la matrice.

Le chemin le plus court vers un support réel est **FreeBSD d'abord** : il
partage la structure du scanner Linux, ne demande aucun outillage nouveau, et
sert de socle aux deux appliances qui en dérivent. macOS demande un travail
distinct, moins réutilisable.
