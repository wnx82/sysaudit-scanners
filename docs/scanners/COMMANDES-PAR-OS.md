# Commandes par système

Ce qu'il faut taper, système par système, pour produire un rapport SysAudit.

Un principe traverse tout ce document : **le scanner ne dépend de rien**. Ni
Node.js, ni serveur, ni base de données sur la machine auditée. Node ne sert
qu'à _rendre_ le rapport, et ce rendu peut se faire ailleurs.

## Avant tout : quel scanner, et ce qu'il vaut

Cinq scanners, et ils n'ont pas tous le même statut. Le confondre ferait lire un
rapport expérimental comme une mesure.

| Système                                                                           | Scanner                         | Statut                                   |
| --------------------------------------------------------------------------------- | ------------------------------- | ---------------------------------------- |
| Linux (Debian, Ubuntu, Mint, Fedora, Rocky, Alma, Arch, Manjaro, Raspberry Pi OS) | `scanners/linux/sysaudit.sh`    | **Utilisable**                           |
| Proxmox VE 8 et 9                                                                 | `scanners/linux/sysaudit.sh`    | **Utilisable** — collectes PVE en plus   |
| Windows 11, 10, Server                                                            | `scanners/windows/sysaudit.ps1` | **Utilisable**                           |
| Windows 8.1, 8, 7, Vista, XP                                                      | —                               | **N'existe pas** (étape 7 non commencée) |
| macOS                                                                             | `scanners/macos/sysaudit.sh`    | 🧪 **EXPERIMENTAL / UNVALIDATED**        |
| FreeBSD, pfSense, OPNsense                                                        | `scanners/bsd/sysaudit.sh`      | 🧪 **EXPERIMENTAL / UNVALIDATED**        |
| Android                                                                           | `scanners/android/sysaudit.sh`  | 🧪 **EXPERIMENTAL / UNVALIDATED**        |

> **Ce que « EXPERIMENTAL / UNVALIDATED » veut dire :** le scanner n'a **jamais**
> été exécuté sur la plateforme qu'il cible. Il est écrit d'après la
> documentation, et ses tests prouvent qu'il dégrade proprement — pas que ses
> sorties ressemblent au terrain. Chaque rapport qu'il produit porte cette
> mention dans `report.notes`, et l'interface l'affiche.
>
> Ces trois scanners ne sont pas non plus proposés au téléchargement par
> l'amorçage : il faut cloner le dépôt.

---

## Linux — Debian, Ubuntu, Mint, Fedora, Rocky, AlmaLinux, Arch, Manjaro

### Sans rien installer

```bash
curl -fsSL https://scan.sysaudit.me -o sysaudit.sh
sha256sum sysaudit.sh        # à comparer au SHA-256 publié dans la release
chmod +x sysaudit.sh
sudo ./sysaudit.sh
```

> `scan.sysaudit.me` n'est pas encore actif — voir
> ../exploitation/MANUAL_ACTIONS.md. En attendant : le dépôt, ou l'artefact
> de la release GitHub.

### Depuis le dépôt

```bash
git clone https://github.com/wnx82/sysaudit-scanners.git
cd sysAudit/scanners/linux
sudo ./sysaudit.sh
```

Produit `sysaudit-HOSTNAME.json` et `.md` dans le dossier personnel de
l'utilisateur qui a lancé l'audit — sous `sudo`, celui de l'utilisateur
d'origine, et non `/root`.

### Les profils

| Commande                        | Ce qu'elle ajoute                            | Durée             |
| ------------------------------- | -------------------------------------------- | ----------------- |
| `sudo ./sysaudit.sh --quick`    | inventaire de base                           | ~10 s             |
| `sudo ./sysaudit.sh --security` | pare-feu, chiffrement, correctifs, comptes   | ~20 s             |
| `sudo ./sysaudit.sh`            | profil normal : logiciels, SMART, historique | ~40 s             |
| `sudo ./sysaudit.sh --full`     | inventaire fin : périphériques, pilotes      | ~1 min            |
| `sudo ./sysaudit.sh --stress`   | banc d'essai — **charge la machine**         | plusieurs minutes |

`sudo` n'est pas décoratif : sans lui, SMART, `dmidecode` et la moitié des
journaux ne répondent pas, et le rapport porte des marqueurs
`PERMISSION_DENIED` là où il y aurait eu des valeurs.

### Les options qui comptent

```bash
# Observer la machine pendant 60 s — min/max/moyenne, fréquence, bridage
sudo ./sysaudit.sh --monitor 60

# Masquer nom de machine, IP publiques, MAC, numéros de série, UUID et SSID
sudo ./sysaudit.sh --anonymize

# Ne pas relever l'adresse WAN — elle l'est par défaut dès qu'une API est connue
sudo ./sysaudit.sh --no-public-ip --api-url https://sysaudit.example.com

# Écarter une section, et le déclarer dans le rapport
sudo ./sysaudit.sh --skip software --skip benchmark

# Choisir où écrire
sudo ./sysaudit.sh --output-dir /tmp/audit

# JSON sur la sortie standard, pour un pipe
sudo ./sysaudit.sh --stdout --no-markdown --quiet | jq .

# Ce qui serait collecté sur cette machine, sans rien scanner
./sysaudit.sh --capabilities
```

Sections acceptées par `--skip` : `system`, `os`, `motherboard`, `bios`, `cpus`,
`memory`, `gpus`, `audio`, `sensors`, `power`, `storage`, `network`, `devices`,
`drivers`, `software`, `startup`, `security`, `virtualization`, `stability`,
`boot`, `shutdown`, `events`, `benchmark`. Un nom inconnu est **refusé**, jamais
ignoré : accepter `--skip storag` en silence collecterait le stockage tout en
laissant croire le contraire.

### Valider le scanner sur cette machine

C'est la campagne : elle enchaîne les profils, valide chaque rapport contre le
schéma, et dit **colonne par colonne** ce qui a réellement été collecté.

```bash
npm ci
npm run build:packages          # indispensable — voir plus bas
npm run lint:shell
npm run test:scanner            # doit afficher 360 tests réussis
sudo -E env "PATH=$PATH" ./scripts/validate-linux-scanner.sh
```

Trois pièges, tous rencontrés en vrai sur une Ubuntu 24.04 :

- **`npm run build:packages` n'est pas optionnel.** `npm ci` ne compile pas les
  paquets. Sans `packages/report-schema/dist`, la suite du scanner **saute trois
  contrôles en le disant** — elle affiche alors 357 tests au lieu de 360, avec la
  ligne « validation de schéma ignorée ». Ces trois-là sont ceux qui confrontent
  les rapports au JSON Schema, exactement comme l'API à l'ingestion. Le script de
  campagne, lui, refuse carrément de démarrer sans eux.
- **`sudo -E env "PATH=$PATH"` n'est pas une superstition.** `sudo` remet le PATH
  à `secure_path`, où un Node installé par **nvm** n'apparaît pas : le script
  refuserait de démarrer en annonçant un Node absent qui est pourtant là. Avec un
  Node de `/usr/bin`, `sudo ./scripts/…` suffit.
- **Un compte de tests inférieur à 360 n'est pas un échec**, mais il n'est pas
  neutre : chaque bloc sauté est annoncé, et dit ce que la suite ne prouve pas.

Le script détecte la distribution et nomme la **ligne de `compatibility.ts`** que
la campagne alimente. Sous WSL ou dans un conteneur, il avertit que le matériel,
le stockage, SMART et l'alimentation ne mesurent pas la machine.

Procédure complète et checklist : ../qualite/VALIDATION-CAMPAIGNS.md.

### Si votre `awk` est `mawk`

Debian et Ubuntu installent **mawk** par défaut, pas gawk. Les deux ne
comprennent pas le même sous-ensemble d'expressions régulières, et une locale à
virgule décimale ne leur fait pas écrire les nombres de la même façon. Deux
défauts en sont sortis, corrigés depuis :

- le regroupement d'incidents était **silencieusement inopérant** sous mawk ;
- le résumé affichait « 1,0 Kio » et le banc d'essai un débit faux.

```bash
readlink -f /etc/alternatives/awk   # /usr/bin/mawk ou /usr/bin/gawk
locale | grep -E 'LANG|LC_NUMERIC'
```

Si vous êtes sous mawk **et** en locale française, votre campagne éprouve le
chemin le moins couvert du produit. Dites-le dans la fiche : c'est une
information, pas un avertissement.

### Envoyer à une instance

```bash
sudo ./sysaudit.sh --upload --api-url https://api.exemple.test
sudo ./sysaudit.sh --upload --public          # publie dans la vitrine
sudo ./sysaudit.sh --claim ABCD-EFGH          # rattache la machine à un compte
sudo ./sysaudit.sh --retry-upload sysaudit-HOSTNAME.json   # renvoi seul
```

Sans `--upload`, **rien ne quitte la machine**. `--public` n'implique pas
`--upload` : publier ce qu'on n'envoie pas n'aurait pas de sens, et le déduire
ferait partir un rapport que l'utilisateur croyait garder local.

### Rattacher la machine à un compte, en une commande

Depuis `/compte` → **Mes machines** → « + Ajouter une machine », SysAudit
affiche la commande d'amorçage habituelle, avec un code de liaison dans l'URL :

```bash
curl -fsSL "https://api.exemple.test/audit/l?link=SA-7K4M-P2Q9" | bash
```

```powershell
irm "https://api.exemple.test/audit/w?link=SA-7K4M-P2Q9" | iex
```

**Les guillemets ne sont pas décoratifs** : `?` est un caractère de globbing, et
zsh refuse l'URL nue avec « no matches found ».

Le code ne vaut **qu'une fois**, une heure, et il n'est pas un identifiant de
compte : il sert au premier rattachement, puis il est consommé. Les audits
suivants de cette machine rejoignent le compte d'eux-mêmes, par l'empreinte
matérielle du rapport — **sauf** avec `--anonymize`, qui produit une empreinte
différente à chaque scan et empêche donc tout rapprochement, y compris celui-ci.

Rien d'obligatoire : les commandes sans `?link=` restent valables, et un audit
anonyme reste un audit complet.

### Dépendances optionnelles

Le scanner tourne sans aucune, et dit ce qui lui manque et pourquoi :

```bash
sudo apt install dmidecode smartmontools pciutils usbutils lm-sensors nvme-cli
```

Détail complet, distribution par distribution, dans
[./DEPENDENCIES.md](./DEPENDENCIES.md).

---

## Proxmox VE 8 et 9

C'est **le scanner Linux**, qui reconnaît l'hyperviseur et collecte en plus les
invités, les stockages, la grappe, les sauvegardes et les services PVE.

```bash
apt-get install -y git
git clone https://github.com/wnx82/sysaudit-scanners.git /opt/sysaudit
cd /opt/sysaudit/scanners/linux
./sysaudit.sh                       # en root
```

`root` est indispensable : `pvesh`, `pvecm`, `pvesr`, `ha-manager` et `ceph`
n'y répondent pas autrement, et le rapport annoncerait `PERMISSION_DENIED` sur
tout ce qui fait l'intérêt d'un audit Proxmox.

> **Hôte en production.** Le scanner est read-only, mais `--stress` charge
> délibérément le processeur et les disques. Sur un hôte qui porte des invités
> actifs, garder le profil normal et réserver `--stress` à une fenêtre de
> maintenance.

### Campagne de validation

C'est **le même script** que pour Linux : il détecte Proxmox et ajoute sept
colonnes propres à PVE — version, VM, conteneurs, stockages, grappe,
sauvegardes, services.

```bash
npm ci && npm run build:packages
./scripts/validate-linux-scanner.sh --output-dir /root/sysaudit-validation
./scripts/validate-linux-scanner.sh --skip-stress --monitor 30   # en production
```

Sans Node.js sur l'hôte — le cas courant — la procédure « produire ici, relire
ailleurs » est dans ../qualite/VALIDATION-CAMPAIGNS.md.

---

## Windows 11, 10 et Server

### Depuis une instance SysAudit

Console PowerShell **administrateur**. L'amorçage télécharge le scanner, vérifie
l'empreinte SHA-256 de chaque fichier, puis l'exécute :

```powershell
irm https://api.exemple.test/audit/w | iex
```

### Depuis le dépôt

```powershell
git clone https://github.com/wnx82/sysaudit-scanners.git
cd sysAudit
powershell -ExecutionPolicy Bypass -File .\scanners\windows\sysaudit.ps1
```

`-ExecutionPolicy Bypass` ne vaut **que pour ce processus** : la politique de la
machine n'est pas modifiée.

### Les profils

```powershell
.\sysaudit.ps1 -Profile quick       # sans élévation
.\sysaudit.ps1 -Profile security    # sans élévation
.\sysaudit.ps1 -Profile standard    # élévation requise
.\sysaudit.ps1 -Profile full        # élévation requise
.\sysaudit.ps1 -Profile stress      # élévation requise — lance WinSAT
```

`quick` et `security` fonctionnent sans élévation ; les autres l'**exigent**,
faute de quoi logiciels, SMART et banc d'essai resteraient hors de portée.

### Les options

```powershell
.\sysaudit.ps1 -Monitor 60                          # observation dans la durée
.\sysaudit.ps1 -Skip software,benchmark             # écarter des sections
.\sysaudit.ps1 -OutputPath C:\audit\rapport.json
.\sysaudit.ps1 -NoMarkdown -Quiet
.\sysaudit.ps1 -Upload -ApiUrl https://api.exemple.test
.\sysaudit.ps1 -Upload -Public
.\sysaudit.ps1 -Claim ABCD-EFGH
.\sysaudit.ps1 -Upload -NoOpen                      # ne pas ouvrir le navigateur
.\sysaudit.ps1 -NoPublicIp -ApiUrl https://sysaudit.example.com # ne relève pas l'adresse WAN
```

> **Sans `-Upload`, il n'y a ni adresse, ni QR Code, ni fenêtre.** Le scanner
> écrit son JSON et s'arrête : c'est le comportement par défaut, et non un
> envoi qui aurait échoué. Après un envoi réussi, en revanche, l'adresse du
> rapport s'affiche, le QR Code l'accompagne et le navigateur s'ouvre dessus —
> `-NoOpen` s'en dispense, et `-Quiet` s'en dispense aussi.

> **Pas d'anonymisation côté Windows.** `sysaudit.ps1` n'a aucun commutateur
> équivalent au `--anonymize` du scanner Linux : il écrit toujours
> `anonymized = false`. Le **fichier** produit sous Windows porte donc toujours
> les identifiants en clair. C'est une limite connue, pas un oubli de ce
> document.
>
> Cela ne dit rien de ce que l'API **sert** : la rédaction côté serveur ne
> dépend pas du scanner, et retire adresses IP, passerelles, résolveurs, MAC,
> numéros de série et nom de machine à tout lecteur qui n'est pas propriétaire —
> rapport Windows compris. Les deux protections répondent à deux questions
> différentes : ce qui est **écrit dans le fichier**, et ce qui est **servi, à
> qui**.

### Campagne de validation

```powershell
npm run lint:powershell
npm run test:scanner:windows
npm run validate:windows
```

Détail et checklist dans ../qualite/VALIDATION-CAMPAIGNS.md.

---

## Windows 8.1, 8, 7, Vista et XP

**Aucun scanner n'existe pour ces systèmes.**

Ce n'est pas un oubli. Il faudrait une couche de compatibilité PowerShell 2.0,
des replis `Get-WmiObject` et `Get-EventLog`, et une matrice de capacités par
version — donc cinq systèmes hors support à éprouver. Écrire cette couche sans
en avoir vu un seul produirait du code qui suppose ce qu'une plateforme répond.

Lancer `sysaudit.ps1` sur l'un d'eux échouerait, et l'échec serait franc.

---

## macOS — 🧪 EXPERIMENTAL

> **Jamais exécuté sur un Mac.** Le rapport produit se lit comme une hypothèse,
> pas comme une mesure.

```bash
git clone https://github.com/wnx82/sysaudit-scanners.git
cd sysAudit/scanners/macos
./sysaudit.sh --capabilities        # ce qui serait collecté, sans rien scanner
./sysaudit.sh                       # rapport dans le répertoire courant
./sysaudit.sh --stdout | jq .
./sysaudit.sh --output-dir /tmp/audit
```

Le scanner **refuse de tourner ailleurs que sur macOS** : lancé sur un Linux, il
produirait un rapport plein de marqueurs qu'on lirait comme « macOS ne sait pas
répondre ».

Ce qui n'est **pas** collecté, et pourquoi : `log show` (coût prohibitif), les
disques physiques (`diskutil list -plist` exigerait un analyseur XML), la durée
de démarrage (macOS n'en publie aucune), les températures (interface privée
d'Apple). Détail dans [`scanners/macos/README.md`](../../scanners/macos/README.md).

SIP, FileVault et Gatekeeper sont publiés dans `report.notes` : le schéma n'a
pas encore de sous-section de sécurité macOS.

---

## FreeBSD, pfSense et OPNsense — 🧪 EXPERIMENTAL

> **Jamais exécuté sur aucun des trois.**

```sh
git clone https://github.com/wnx82/sysaudit-scanners.git
cd sysAudit/scanners/bsd
./sysaudit.sh --capabilities
sudo ./sysaudit.sh --output-dir /root/audit
```

`root` change ce que le rapport contient : sans lui, `pfctl` refuse et l'état du
pare-feu sort en `PERMISSION_DENIED`. Sur une appliance, c'est le fait le plus
important du rapport — `pf` **est** la fonction de la machine.

Le scanner reconnaît la distribution sur ses fichiers de version, jamais sur le
nom d'hôte :

| Système  | Marqueur                           |
| -------- | ---------------------------------- |
| OPNsense | `/usr/local/opnsense/version/core` |
| pfSense  | `/etc/version` **et** `/cf/conf`   |
| FreeBSD  | aucun des deux                     |

La version de l'appliance et celle de sa base FreeBSD sont **deux champs
distincts** : les confondre ferait conclure à une fin de support qui n'existe
pas. Détail dans [`scanners/bsd/README.md`](../../scanners/bsd/README.md).

---

## Android — 🧪 EXPERIMENTAL

> **Jamais exécuté sur un appareil.**

### Depuis l'appareil (Termux)

```sh
git clone https://github.com/wnx82/sysaudit-scanners.git
cd sysAudit/scanners/android
./sysaudit.sh --capabilities
./sysaudit.sh --stdout
```

### Depuis un poste, par ADB

```bash
adb push scanners/android/sysaudit.sh scanners/android/lib /data/local/tmp/sysaudit/
adb shell sh /data/local/tmp/sysaudit/sysaudit.sh --stdout > rapport-android.json
```

Le mode de collecte — `root`, `adb` ou `application` — change ce qui est
lisible, et le rapport le publie dans ses notes. Sans cette mention, deux
rapports du même téléphone paraîtraient contradictoires et on chercherait la
panne dans l'appareil.

**Aucune donnée d'application n'est collectée** : ni la liste des paquets
installés, ni leurs données, ni `logcat`. C'est une décision de portée, pas une
limite technique. Détail dans
[`scanners/android/README.md`](../../scanners/android/README.md).

---

## Rendre le rapport

Le scanner écrit un JSON et un Markdown de base sans Node.js. Le rapport complet
— constats, scores, HTML autonome, PDF — se produit ensuite, sur **n'importe
quelle** machine disposant de Node.

```bash
npm run build:packages
node packages/report-renderer/dist/cli.js sysaudit-HOSTNAME.json \
  --html rapport.html --md rapport.md --pdf rapport.pdf

# Ou, dans le dépôt, via le lien de workspace
npx sysaudit-render sysaudit-HOSTNAME.json
```

Sans option de sortie, écrit `<rapport>.html` et `<rapport>.md` à côté du JSON.
Le HTML est **autonome** : aucune requête réseau, aucun script.

> `npx sysaudit-render` ne fonctionne **que depuis le dépôt** :
> `@sysaudit/report-renderer` porte `private: true` et n'est pas publié sur npm.
> Ailleurs, c'est la commande `node packages/report-renderer/dist/cli.js` qui
> s'applique.

## Vérifier qu'un rapport est conforme

Le même contrôle que celui appliqué par l'API à l'arrivée. Un rapport refusé ici
serait refusé à l'upload :

```bash
npm run build:packages
node --input-type=module -e "
import { readFileSync } from 'node:fs';
import { validateReport } from './packages/report-schema/dist/index.js';
const r = validateReport(JSON.parse(readFileSync(process.argv[1], 'utf8')));
console.log(r.ok ? 'conforme' : r.issues.map((i) => i.path + ' : ' + i.message).join('\n'));
" sysaudit-HOSTNAME.json
```

## Ce que chaque scanner écrit, et où

| Scanner | Fichier produit                           | Répertoire par défaut   |
| ------- | ----------------------------------------- | ----------------------- |
| Linux   | `sysaudit-HOSTNAME.json` + `.md`          | dossier personnel       |
| Windows | `sysaudit-HOSTNAME.json` + `.md`          | dossier Téléchargements |
| macOS   | `sysaudit-macos-<AAAAMMJJ-HHMMSS>.json`   | répertoire courant      |
| BSD     | `sysaudit-bsd-<AAAAMMJJ-HHMMSS>.json`     | répertoire courant      |
| Android | `sysaudit-android-<AAAAMMJJ-HHMMSS>.json` | répertoire courant      |

Aucun n'écrit ailleurs que dans son répertoire de sortie, et **aucun ne modifie
la configuration du système**. C'est vérifié par test pour les trois scanners
expérimentaux (`scanners/experimental-parity.test.ts`).

## Lancer les suites de tests des scanners

Depuis le dépôt, sur une machine de développement :

```bash
npm run test:scanner            # Linux   — 353 tests
npm run test:scanner:windows    # Windows — 183 tests, exige PowerShell
npm run test:scanner:macos      # macOS   —  75 tests
npm run test:scanner:bsd        # BSD     —  76 tests
npm run test:scanner:android    # Android —  85 tests

npm run lint:shell              # ShellCheck
npm run lint:powershell         # PSScriptAnalyzer
```

> **Sans PowerShell installé, les deux commandes Windows s'arrêtent sans
> échouer.** Un `npm run verify` vert ne prouve donc pas que le scanner Windows
> a été vérifié. `npm run ci:local` refuse de démarrer dans ce cas plutôt que de
> rendre un vert qui ne prouve rien.

## À lire ensuite

- [./LINUX.md](./LINUX.md) — ce que le scanner Linux collecte, source par source
- [./WINDOWS.md](./WINDOWS.md) — scanner Windows et sa distribution
- [../produit/DIAGNOSTIC-LEVELS.md](../produit/DIAGNOSTIC-LEVELS.md) — ce que chaque profil collecte
- [./DEPENDENCIES.md](./DEPENDENCIES.md) — outils optionnels, par distribution
- [COMPATIBILITY.md](../../COMPATIBILITY.md) — matrice OS × capacités, générée
- ../qualite/VALIDATION-CAMPAIGNS.md — campagnes sur machines
  réelles, avec checklists
