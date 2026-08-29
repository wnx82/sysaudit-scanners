# Scanner Linux / Proxmox

Audit **READ ONLY** d'une machine Linux. Le scanner ne modifie jamais la
configuration du système audité, et n'émet aucune connexion réseau sortante sauf
upload explicitement demandé.

Une seule exception, et elle se demande : `--install-deps`, en audit `--full` ou
`--stress`, propose d'installer les outils manquants — un par un, chacun décrit
avant la question — et propose leur retrait en fin d'audit. Sans ce drapeau,
rien n'est installé. Voir
[adr/0008](../adr/0008-installation-consentie-en-audit-administrateur.md).

## Utilisation

### Depuis le dépôt

```bash
sudo ./scanners/linux/sysaudit.sh --output-dir ./reports
```

### Méthode recommandée en production

Télécharger, inspecter, puis exécuter :

```bash
curl -fsSL https://scan.sysaudit.me -o sysaudit.sh
sha256sum sysaudit.sh        # comparer au SHA256 publié dans la release
less sysaudit.sh
chmod +x sysaudit.sh
sudo ./sysaudit.sh
```

La forme courte `curl -fsSL https://scan.sysaudit.me | sudo bash` fonctionne
également, mais exécute du code non inspecté avec les privilèges root.

Le rapport est écrit en `0600` — il peut contenir des données personnelles — et
il **revient à l'utilisateur qui a lancé `sudo`**, pas à `root`. C'était un
défaut jusqu'à la version 0.29.1 du scanner : le fichier restait la propriété de
`root` dans le dossier personnel de quelqu'un qui ne pouvait plus l'ouvrir, et
le dépôt par le navigateur échouait sur un « Failed to fetch » qui accusait le
réseau. Sur un rapport produit par une version antérieure :

```bash
sudo chown "$USER" sysaudit-*.json sysaudit-*.md
```

> Le domaine `scan.sysaudit.me` n'est pas encore actif — voir
> ../exploitation/MANUAL_ACTIONS.md. En attendant, utiliser le dépôt ou
> l'artefact de la release GitHub.

## Options

| Option                  | Effet                                                            |
| ----------------------- | ---------------------------------------------------------------- |
| _(aucune)_              | Niveau Normale : inventaire matériel, SMART, réseau, sécurité    |
| `--quick`               | Niveau Rapide : inventaire essentiel, aucune sonde coûteuse      |
| `--full`                | Niveau Complète : ajoute logiciels, pilotes, USB, SMART détaillé |
| `--stress`              | Niveau Poussée : banc d'essai — **charge la machine**            |
| `--security`            | Alias historique du niveau Rapide                                |
| `--anonymize`           | Masque les identifiants avant écriture                           |
| `--public-ip`           | **Exige** l'adresse WAN : refuse de démarrer sans `--api-url`    |
| `--no-public-ip`        | Ne relève pas l'adresse WAN, même avec une API sous la main      |
| `--output-dir <chemin>` | Répertoire de sortie (défaut : dossier personnel, voir plus bas) |
| `--stdout`              | Écrit le JSON sur la sortie standard                             |
| `--no-markdown`         | Ne produit que le JSON                                           |
| `--upload`              | Envoie le rapport (nécessite `--api-url`)                        |
| `--public`              | Rend l'audit répertoriable dans la vitrine (exige `--upload`)    |
| `--private`             | Exige le privé, même si l'instance publie par défaut             |
| `--api-url <url>`       | URL de l'API SysAudit, HTTPS obligatoire                         |
| `--benchmark`           | Mesure les performances — **charge la machine**                  |
| `--monitor <secondes>`  | Observe la machine dans la durée (max 3600 s)                    |
| `--capabilities`        | Affiche ce qui pourrait être collecté, sans scanner              |
| `--version`             | Versions du scanner et du schéma produit                         |

### Portée d'un envoi

`--public` rend l'audit **répertoriable** — susceptible d'apparaître dans la
liste des diagnostics récents. Il ne le rend pas lisible : il l'était déjà par
son adresse, dès l'envoi.

`--private` n'est pas une redondance du défaut. Sans en-tête, c'est le réglage
`DEFAULT_SCAN_VISIBILITY` de **l'instance** qui tranche, et il peut valoir
`PUBLIC` — c'est le cas de `sysaudit.me`, qui sert une vitrine. Sur une telle
instance, ne rien dire n'est pas demander le privé.

Poser `--private` sur un audit de validation, de test ou d'exploitation est donc
le seul moyen de garantir qu'il n'apparaîtra pas en page d'accueil. Les deux
drapeaux ensemble sont refusés plutôt qu'arbitrés en silence.

## Banc d'essai

Le banc d'essai n'a lieu qu'au niveau Poussée, ou sur demande explicite avec
`--benchmark`. Il **charge volontairement la machine** ; tout le reste du
scanner est en lecture seule.

Un audit qui n'a pas mesuré le rappelle en une ligne, à la fin, et ne lance
jamais rien de lui-même. Le silence coûtait cher : au 2026-08-27, le parc
comptait **36 audits `--full` et pas une seule mesure**. Leurs auteurs avaient
demandé « complet » ; rien ne leur avait jamais dit que la mesure n'en faisait
pas partie. Un audit rapide, une section écartée par `--skip benchmark` et un
banc d'essai qui a tourné ne se voient rien rappeler.

Dix mesures, dans cet ordre : processeur mono-fil, multi-fil et **soutenu**,
mémoire en lecture, écriture et copie, stockage en écriture et lecture
séquentielles, stockage en lecture aléatoire, puis GPU — une mesure **par carte
graphique**.

| Réglage                    | Hors niveau Poussée | Niveau Poussée |
| -------------------------- | ------------------- | -------------- |
| Durée visée par mesure     | 5 s                 | 20 s           |
| Charge soutenue            | aucune              | 10 min         |
| Répit entre deux mesures   | 1 s                 | 5 s            |
| Échauffement processeur    | 2 s                 | 5 s            |
| Volume écrit sur le disque | 1 Gio au plus       | 2 Gio au plus  |

`SYSAUDIT_BENCH_SECONDS` remplace la durée visée, entre 1 et 120 secondes ;
`SYSAUDIT_SOAK_SECONDS` la durée de la charge soutenue, entre 10 s et 1 h.

La **charge soutenue** est la raison d'être du niveau Poussée : le bridage
thermique n'apparaît pas en vingt secondes. Elle est découpée en segments de
trente secondes, ce qui permet à la fois d'arrêter la machine en cours de route
si elle chauffe trop, et de comparer le débit du dernier segment à celui du
premier. Une perte de plus de 10 % est rapportée telle quelle — un portable qui
bride à 85 % de son débit initial est conçu ainsi, et le rapport ne prétend pas
trancher.

Le **GPU** est mesuré carte par carte : `DRI_PRIME` désigne la carte à
`glmark2`, et chaque mesure porte l'étiquette de la sienne. Sur les cartes
NVIDIA, `nvidia-smi` fournit en plus l'utilisation, les fréquences, la VRAM, la
température et la puissance relevées juste après la charge.

Quatre garde-fous, parce qu'un diagnostic ne doit pas être ce qui provoque la
panne :

- **la mémoire manipulée** vaut un huitième de la mémoire _disponible_, plafonnée
  à 256 Mio : aucune mesure ne doit déclencher de swap ;
- **le fichier de travail sur disque** vaut un dixième de la place libre, plafonné
  à 256 Mio. En dessous de 64 Mio disponibles, la mesure est écartée ;
- **le volume écrit est borné**, indépendamment de la durée : mesurer un débit ne
  doit pas coûter des dizaines de gibioctets de cycles d'écriture à un SSD ;
- **la température est surveillée** pendant chaque mesure. Si elle atteint 95 % du
  seuil critique publié par le capteur, le banc d'essai s'arrête et le rapport
  dit pourquoi. Sans seuil publié par le matériel, aucun seuil n'est inventé.

Chaque mesure porte son état — `completed`, `skipped` ou `failed` —, ses
horodatages de début et de fin, l'outil et ses paramètres exacts, ainsi que les
températures avant, maximale et finale. Une mesure écartée nomme ce qui lui
manque.

Aucun outil n'est embarqué ni téléchargé : `openssl`, `dd`, `fio` et `glmark2`
sont utilisés s'ils sont présents, et déclarés absents sinon.

Ce que chaque niveau collecte, et à quelle profondeur, est décrit par
[../produit/DIAGNOSTIC-LEVELS.md](../produit/DIAGNOSTIC-LEVELS.md) — une projection de la table de
`packages/platform/src/diagnostic-levels.ts`, dont le scanner embarque une copie
vérifiée par un test de contrat.

## Sorties

```text
sysaudit-HOSTNAME.json    source de vérité, format documenté et versionné
sysaudit-HOSTNAME.md      synthèse lisible immédiatement
```

Les fichiers sont créés en `0600` : un rapport peut contenir des données
personnelles, il ne doit pas hériter d'un umask permissif.

### Où vont les fichiers

Dans le **dossier personnel de l'utilisateur qui a lancé l'audit**, et non dans
le répertoire courant :

```text
/home/wnx/sysaudit-MSI-Ubuntu.json
```

`sudo` est le cas qui compte, puisque c'est lui qu'exige un audit complet. Il
laisse `HOME=/root`, et le rapport atterrissait alors dans le dossier personnel
de root : lisible par root seul, introuvable pour l'humain qui vient de lancer
l'audit et qui doit le déposer. `SUDO_USER` porte l'identité d'origine, et son
dossier personnel est **lu dans la base des comptes** — `getent`, sinon
`/etc/passwd` — plutôt que déduit de `/home/<nom>`, faux dès qu'un annuaire ou
un chemin hérité entre en jeu.

Deux cas ne désignent personne d'autre, et n'y changent rien : un `sudo -u root`
et un audit lancé directement en root, sans `sudo`. `HOME` reste alors la seule
réponse honnête.

Si le dossier personnel est absent ou fermé à l'écriture — compte de service,
`HOME` non défini, conteneur minimal —, le répertoire temporaire prend le
relais et le repli est annoncé. Un audit qui a réussi n'est pas perdu pour une
question de droits sur un dossier.

Un `--output-dir` demandé explicitement passe devant tout cela : s'il refuse
l'écriture, l'erreur remonte plutôt que d'écrire ailleurs en silence.

Le rapport est enfin **rendu à son propriétaire** : sous `sudo`, il sortirait
sinon en `root:root` dans le dossier personnel de quelqu'un qui ne pourrait ni
le lire ni le déposer. Voir `restore_report_ownership`.

## Privilèges

Le scanner fonctionne sans privilèges, en mode dégradé. Il ne demande jamais
d'élévation de lui-même.

| Contexte             | Résultat                                                                      |
| -------------------- | ----------------------------------------------------------------------------- |
| `root`               | Collecte complète, selon les outils présents                                  |
| Utilisateur standard | SMBIOS, SMART, pare-feu et état des mots de passe marqués `PERMISSION_DENIED` |

## Outils utilisés

Aucun n'est obligatoire. L'absence d'un outil dégrade la collecte **de façon
explicite** : le champ concerné porte `NOT_AVAILABLE` avec le nom de l'outil
manquant, et le scanner affiche en fin de scan la commande d'installation
correspondant à la famille détectée.

Il ne l'exécute pas de lui-même : il faut `--install-deps`, un audit `--full` ou
`--stress`, et un accord donné outil par outil. Voir
[./DEPENDENCIES.md](./DEPENDENCIES.md),
[adr/0006](../adr/0006-dependances-externes.md) et
[adr/0008](../adr/0008-installation-consentie-en-audit-administrateur.md).

| Outil                                       | Apporte                                              | Commandes exécutées (toutes en lecture)                           |
| ------------------------------------------- | ---------------------------------------------------- | ----------------------------------------------------------------- |
| `dmidecode`                                 | Carte mère, BIOS, modules RAM, châssis, alimentation | `dmidecode -s`, `-t 0`, `-t 4`, `-t 16`, `-t 17`, `--type 39`     |
| `lscpu`                                     | Détail CPU                                           | `lscpu`                                                           |
| `lsblk`                                     | Disques, partitions, identifiants de volumes         | `lsblk -dn`, `-bnrp`, `-dno UUID/PARTUUID/WWN`                    |
| `smartctl`                                  | Santé SMART / NVMe                                   | `smartctl -i`, `-A -H`                                            |
| `lspci` / `lsusb`                           | Périphériques, GPU                                   | `lspci -nn`, `-k -s`, `lsusb`                                     |
| `ip` / `ss`                                 | Réseau, ports en écoute                              | `ip addr/route show`, `ss -Hlntup`                                |
| `iw`                                        | Wi-Fi (SSID uniquement)                              | `iw dev … link`                                                   |
| `zpool`                                     | Pools ZFS                                            | `zpool list -Hp`, `zpool status`                                  |
| `vgs` / `pvs`                               | Groupes de volumes LVM                               | `vgs --noheadings`, `pvs --noheadings`                            |
| `docker`                                    | Conteneurs                                           | `docker info/ps/inspect/port/network ls`                          |
| `podman`                                    | Conteneurs Podman                                    | `podman version`, `podman ps -a`                                  |
| `virsh`                                     | Invités KVM/QEMU hébergés                            | `virsh list`, `virsh dominfo`, `virsh domstate`                   |
| `pveversion`, `qm`, `pct`, `pvesm`, `pvecm` | Proxmox                                              | voir [./PROXMOX.md](./PROXMOX.md)                                 |
| `apt` / `dnf` / `pacman`                    | Paquets et mises à jour                              | `apt-get -s upgrade`, `dnf -C check-update`, `pacman -Qu`         |
| `snap` / `flatpak`                          | Applications hors gestionnaire système               | `snap list`, `flatpak list --app`                                 |
| `fail2ban-client` / `cscli`                 | Protection contre le bruteforce                      | `fail2ban-client status`, `cscli scenarios list`                  |
| `lsmod`                                     | Pilotes (modules noyau)                              | `lsmod`                                                           |
| `journalctl`                                | Historique des incidents, dernier arrêt              | `journalctl -p`, `-b 0`, `-b -1`, `-o short-unix`                 |
| `dmesg`                                     | Anneau du noyau, si `journalctl` manque              | `dmesg --level=… --time-format=iso`                               |
| `systemd-analyze`                           | Durées de démarrage, unités lentes                   | `systemd-analyze time`, `systemd-analyze blame`                   |
| `coredumpctl`                               | Vidanges mémoire recensées                           | `coredumpctl list`                                                |
| `last`                                      | Nombre de redémarrages                               | `last -F reboot`                                                  |
| `vcgencmd`                                  | Bridage et sous-tension Raspberry Pi                 | `vcgencmd get_throttled`                                          |
| `ipmitool`                                  | Alimentations et puissance d'un serveur              | `ipmitool sdr type 'Power Supply'`, `ipmitool dcmi power reading` |

Aucune de ces commandes ne modifie l'état du système. `apt-get -s upgrade`
s'exécute en simulation et lit le cache local — il n'émet aucune requête réseau.

## Identifiants lus sans aucun outil

Une part des identifiants ne demande aucun paquet : ils sont lus directement
dans `/sys`, ce qui les rend disponibles là où `dmidecode` et `smartctl` ne le
sont pas — c'est-à-dire sur la majorité des machines auditées sans privilèges.

| Source                   | Apporte                                               |
| ------------------------ | ----------------------------------------------------- |
| `/sys/class/dmi/id`      | Constructeur, modèle, châssis, étiquette d'inventaire |
| `/sys/block/*/wwid`      | Identifiant mondial du disque (WWN)                   |
| `/sys/block/nvme*/nguid` | Identifiant d'espace de noms NVMe                     |
| `/sys/class/drm/*/edid`  | Constructeur, modèle et numéro de série d'un écran    |

Le bloc EDID est décodé par le scanner lui-même. `edid-decode`, `read-edid` et
`xrandr --verbose` savent le faire, mais les deux premiers sont absents de
presque toutes les machines et le troisième suppose une session graphique
ouverte, qu'un scan lancé par SSH n'a pas. Le constructeur reste l'identifiant
PNP que l'écran déclare (`DEL`, `SAM`, `AUO`), jamais traduit en nom commercial :
cette correspondance est un annuaire externe, et l'écrire de mémoire produirait
un nom faux sur les fabricants rares.

Le nom qualifié et le domaine viennent de `hostname -f` et `hostname -d`, qui
interrogent le résolveur local. Un résolveur muet laisse les deux champs
inconnus : le nom qualifié n'est jamais recomposé en collant un domaine
plausible au nom court.

## Historique, stabilité, démarrage et arrêt

Le scanner lit ce que le système a **déjà écrit**. Il n'active aucune
journalisation, ne change aucun niveau de trace et n'écrit nulle part.

Trois précautions gouvernent cette collecte.

**Un compteur ne part jamais sans sa fenêtre.** « Trois pannes » est rassurant
sur un an et alarmant sur une journée : chaque compteur de `stability` porte
`observationWindowMs`.

**La fenêtre demandée n'est pas la fenêtre obtenue.** `events.window` porte les
deux. Beaucoup de distributions configurent `journald` en mémoire
(`Storage=volatile`) : le journal repart alors de zéro à chaque démarrage, et
`persistent: false` le dit. Sans cette distinction, « aucun incident » se lirait
comme un trimestre sain sur une fenêtre qui ne couvre que le dernier démarrage.
La fenêtre demandée se règle par `SYSAUDIT_HISTORY_DAYS` (trente jours par
défaut).

**Une fréquence basse ne prouve pas un bridage.** Un processeur au repos tourne
bas sans être bridé. `cpuThrottled` n'est affirmé que sur la **progression** d'un
compteur `thermal_throttle` entre deux relevés, ou sur le masque de bits que
`vcgencmd get_throttled` publie sur un Raspberry Pi. Au premier échantillon, il
n'y a pas encore deux points à comparer : le champ reste inconnu, jamais `false`.

### Limitations connues

- **`journalctl` installé ne veut pas dire journal lisible.** Sans appartenance
  au groupe `systemd-journal` ni privilèges, il rend un journal **vide** au lieu
  d'échouer. Le scanner tente donc une lecture réelle avant de conclure, et
  déclare `PERMISSION_DENIED` dans `capabilities.features` plutôt que zéro
  incident.
- **Sans `journalctl`, le repli sur `dmesg` ne couvre que le démarrage courant**
  et le seul noyau. La fenêtre annoncée devient l'uptime, pas les trente jours
  demandés. `kernel.dmesg_restrict=1`, défaut sur Ubuntu et Debian récents, le
  réserve de surcroît à root.
- **Le nombre de redémarrages vient de `wtmp`**, dont la rotation est
  indépendante de celle du journal. Sa fenêtre reste donc `NOT_AVAILABLE` : elle
  n'est pas datable de façon portable.
- **La durée du dernier arrêt n'est pas mesurable** : le journal ne chronomètre
  pas l'extinction.
- **`systemd-analyze` n'écrit « = total » que s'il a plusieurs phases.** À
  défaut, le total publié est la somme des phases mesurées — une addition de
  valeurs lues, pas une estimation.

## Ce que le scanner ne collecte jamais

- Mots de passe, hashes (`/etc/shadow` n'est jamais ouvert), clés, tokens
- Clés SSH privées, `authorized_keys`, `known_hosts`
- Clés Wi-Fi (le SSID peut l'être, jamais la PSK)
- Variables d'environnement des conteneurs Docker
- Contenu de fichiers de configuration — seules quelques directives SSH
  précises sont lues (`Port`, `PermitRootLogin`, `PasswordAuthentication`,
  `PubkeyAuthentication`)
- Contenu de documents, historique de navigation, e-mails

Ces garanties sont vérifiées par `scanners/linux/tests/run.sh` et par la
validation à l'ingestion côté API.

## Anonymisation

```bash
sudo ./sysaudit.sh --anonymize
```

Sont remplacés par un pseudonyme stable (`HOST-A1B2C3D4E5`) :

- nom de machine, noms d'utilisateurs, domaines de recherche ;
- adresses IP **publiques**, adresses MAC, SSID Wi-Fi ;
- numéros de série et UUID matériels.

Les adresses IP privées sont conservées **par l'anonymisation**, qui n'a rien à
protéger là : `192.168.1.20` ne désigne personne hors du réseau où elle vit.
Elles sont en revanche **retirées à la lecture** pour qui n'est pas propriétaire
de la machine — voir « Adresses IP » ci-dessous. Les deux mécanismes répondent à
deux questions différentes et se cumulent :

- `--anonymize` décide de **ce qui est écrit dans le fichier**, avant tout envoi.
  La perte est définitive : le propriétaire lui-même ne retrouvera pas la valeur.
- La rédaction serveur décide de **ce qui est servi, et à qui**. Le rapport est
  conservé en clair ; c'est la réponse qui change selon le lecteur.

Le pseudonyme est déterministe **au sein d'un rapport** — la même valeur donne
toujours le même pseudonyme, ce qui préserve les corrélations internes — mais un
sel aléatoire par exécution empêche de corréler deux rapports entre eux ou de
retrouver une valeur par dictionnaire.

## Adresses IP

### Ce qui est collecté

Les adresses **locales** (LAN) le sont toujours : elles sont lues sur les
interfaces de la machine, sans qu'aucun paquet ne sorte.

L'adresse **publique** (WAN) est relevée **dès qu'une API est connue** :

```bash
# Relevée : une API est désignée
sudo ./sysaudit.sh --api-url https://sysaudit.example.com

# Pas relevée : aucun correspondant à interroger, et aucun paquet ne sort
sudo ./sysaudit.sh

# Pas relevée non plus : le relevé est refusé explicitement
sudo ./sysaudit.sh --no-public-ip --api-url https://sysaudit.example.com
```

C'est la **seule collecte de ce scanner qui émette un paquet vers l'extérieur**.
Une adresse WAN n'existe nulle part sur le poste : aucune interface ne la porte,
aucun fichier ne l'écrit — seul un correspondant distant l'observe. Ce
correspondant est l'API SysAudit elle-même (`GET /api/v1/public-ip`), jamais un
service d'écho tiers : envoyer l'empreinte réseau des machines auditées à un
inconnu pour _protéger_ leur adresse serait l'exact contraire du but.

Trois états, et non un simple drapeau :

| Invocation        | Comportement                                                   |
| ----------------- | -------------------------------------------------------------- |
| _(aucune option)_ | Relevée si `--api-url` est connue, ignorée sinon — sans erreur |
| `--public-ip`     | **Exigée** : le scanner refuse de démarrer sans `--api-url`    |
| `--no-public-ip`  | Jamais relevée, même avec une API sous la main                 |

Le défaut ne fait donc **pas** échouer un audit hors ligne : sans API, il n'y a
personne à interroger, ce qui est une réponse et non une erreur. Le champ reste
alors absent du rapport. C'est aussi pourquoi `--public-ip` existe encore : qui
_exige_ ce champ doit apprendre tout de suite qu'il manque une API, plutôt que
de le découvrir en lisant le rapport.

Si l'API est joignable mais ne répond pas, le champ porte un marqueur avec sa
raison — jamais une valeur inventée, jamais un champ tu.

### Qui peut les lire

Adresses LAN et WAN sont toutes deux des **informations protégées**. Le rapport
les conserve — c'est ce qui les rend utiles au diagnostic réseau — mais le
serveur ne les sert qu'au propriétaire de la machine, aux membres de son
organisation et à un administrateur de la plateforme. Sont concernés :

| Champ                              | Traitement pour un autre lecteur  |
| ---------------------------------- | --------------------------------- |
| `network.publicIp` (WAN)           | marqueur « information protégée » |
| `network.interfaces[].ipv4/ipv6`   | liste vidée                       |
| `network.interfaces[].gateway`     | marqueur                          |
| `network.interfaces[].mac`         | marqueur                          |
| `network.dnsServers`               | liste vidée                       |
| `network.searchDomains`            | liste vidée                       |
| `network.routes`                   | table vidée                       |
| `network.listeningPorts[].address` | marqueur — le port, lui, reste    |

Le retrait a lieu **côté serveur** : la valeur n'est ni dans le JSON, ni dans le
HTML, ni dans l'export, ni dans le cache du navigateur du lecteur. Un lien de
partage, un export public et une consultation anonyme passent tous par cette
rédaction, sans exception de portée. Le nom de l'interface reste public : `eth0`
ou `enp4s0` ne désigne aucune machine en particulier.

## Upload

Aucun envoi n'a lieu sans `--upload` explicite. Avant l'envoi, le scanner
affiche ce qui sera transmis et avertit si le rapport n'est pas anonymisé.
HTTPS est obligatoire, sauf vers `localhost` pour le développement.

```bash
sudo ./sysaudit.sh --anonymize --upload --api-url https://sysaudit.example.com
```

## Fonctionnement interne

```text
1. Détection des capacités    OS, distribution, privilèges, hyperviseur, outils
2. Collecte adaptée           uniquement ce que les capacités permettent
3. Marquage des absences      UNKNOWN / NOT_AVAILABLE / UNSUPPORTED / PERMISSION_DENIED
4. Écriture JSON + Markdown   en 0600
5. Upload facultatif          jamais sans consentement explicite
```

Chaque commande externe s'exécute avec un timeout (15 s par défaut,
`SYSAUDIT_CMD_TIMEOUT`). Aucun argument de commande n'est construit à partir de
données non fiables.

Le scanner **collecte** ; il n'analyse pas. Aucun score ni recommandation n'est
calculé sur la machine auditée : ces analyses sont produites à partir du JSON,
ce qui permet de les recalculer quand une règle évolue (ADR 0003).

## Développement

```text
scanners/linux/
├── sysaudit.sh              point d'entrée, options, assemblage du rapport
├── VERSION                  version du scanner (SemVer)
├── MANIFEST                 fichiers distribuables, dans l'ordre de chargement
├── lib/
│   ├── core/
│   │   ├── json.sh          construction de JSON valide
│   │   ├── core.sh          journalisation, exécution maîtrisée, isolation
│   │   ├── anonymize.sh     pseudonymisation
│   │   └── capabilities.sh  détection des capacités
│   ├── collectors/
│   │   ├── system.sh        identité machine et OS
│   │   ├── hardware.sh      carte mère, BIOS, CPU, RAM, GPU, écrans, capteurs
│   │   ├── power.sh         batterie et alimentation secteur
│   │   ├── storage.sh       disques, partitions, SMART, ZFS
│   │   ├── network.sh       interfaces, DNS, Wi-Fi, ports
│   │   ├── security.sh      pare-feu, mises à jour, comptes, SSH
│   │   ├── software.sh      paquets, services, périphériques
│   │   ├── virtualization.sh Docker, Podman, libvirt et Proxmox
│   │   ├── monitoring.sh    série temporelle (`--monitor`)
│   │   └── benchmark.sh    banc d’essai (`--benchmark`)
│   └── output/
│       └── markdown.sh      rapport Markdown local
└── tests/
    ├── run.sh               148 tests
    └── fixtures/            sorties de commandes réelles
```

### Manifeste

`MANIFEST` est la **source de vérité unique** de la liste des fichiers du
scanner. Trois consommateurs la lisent : `sysaudit.sh` pour charger ses modules,
l'API pour n'accepter de servir que ces chemins, et le script d'amorçage pour
les télécharger. Un test vérifie que les `source` de `sysaudit.sh` lui
correspondent exactement, et qu'aucun module livré n'y manque.

Ajouter un collecteur, c'est donc : créer `lib/collectors/<nom>.sh`, l'ajouter
au manifeste, l'ajouter aux `source` de `sysaudit.sh`, et l'appeler via
`run_collector`.

### Isolation des collecteurs

Chaque section passe par `run_collector`, qui exécute le collecteur dans un
sous-shell. Un collecteur qui échoue, qui `exit`, ou qui ne produit rien donne
une **section absente accompagnée de sa raison** dans `collection.issues` ; il
n'interrompt jamais l'audit. Seules `system` et `os` sont obligatoires : sans
elles, le rapport ne serait pas valide et le scan s'arrête avec un message
explicite.

Le temps d'exécution est borné **par commande** (`SYSAUDIT_CMD_TIMEOUT`,
15 s par défaut), seul endroit où un blocage se produit réellement.

Vérifications :

```bash
npm run lint:shell     # ShellCheck
npm run test:scanner   # tests unitaires + bout en bout
```

La suite de bout en bout exécute un vrai scan et **valide sa sortie contre le
JSON Schema** : c'est le contrat entre le scanner et la plateforme. Un test
distinct vérifie que la version de schéma déclarée en dur dans le script
correspond à celle du package `@sysaudit/report-schema`.
