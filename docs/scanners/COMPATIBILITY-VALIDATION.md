# Valider la matrice de compatibilité

Ce document dit **comment faire monter correctement** les cases de
[`COMPATIBILITY.md`](../../COMPATIBILITY.md).

Il ne décrit pas l'architecture des scanners, ni toutes leurs options. Il
répond à une seule question :

> une campagne réelle a eu lieu sur une machine réelle ; qu'est-ce qu'on lance,
> qu'est-ce qu'on relève, et qu'est-ce qu'on a le droit de cocher ensuite ?

## Règle absolue

Une case de [`COMPATIBILITY.md`](../../COMPATIBILITY.md) ne passe à ✅ que si la
donnée a été **réellement produite** sur la plateforme cible.

Trois états existent pendant une campagne :

| État       | Signification                                                    | Autorise un ✅ dans la matrice ? |
| ---------- | ---------------------------------------------------------------- | -------------------------------- |
| `collecte` | une valeur réelle a été produite                                 | oui                              |
| `marqueur` | le scanner a tenté et a expliqué pourquoi il ne pouvait pas lire | non                              |
| `absent`   | la section n'est pas présente dans le rapport                    | non                              |

Un `marqueur` n'est pas un échec du scanner. C'est un comportement correct.
Mais ce n'est **pas** une validation.

## Source de vérité

`COMPATIBILITY.md` n'est pas édité à la main.

La source de vérité est :

- [`packages/platform/src/compatibility.ts`](../../packages/platform/src/compatibility.ts)

Après modification :

```bash
npm run docs:compatibility
```

Un test échoue si la documentation générée ne correspond plus à la source.

## Flux complet

Pour valider une ligne de compatibilité :

1. lancer la campagne sur la machine cible ;
2. conserver les rapports JSON produits ;
3. relever, colonne par colonne, `collecte`, `marqueur` ou `absent` ;
4. ne promouvoir en `VALIDATED` que les colonnes réellement en `collecte` ;
5. mettre à jour [`compatibility.ts`](../../packages/platform/src/compatibility.ts) ;
6. régénérer [`COMPATIBILITY.md`](../../COMPATIBILITY.md) ;
7. écrire noir sur blanc ce qui n'a **pas** été couvert.

## Avant toute campagne

Checklist commune :

- [ ] la machine cible est identifiée précisément : OS, version, édition, architecture
- [ ] le type d'environnement est noté : physique, VM, conteneur, WSL, appliance, téléphone
- [ ] le dépôt est à jour sur la branche voulue
- [ ] `npm ci` a été exécuté si la campagne dépend de Node pour valider le schéma
- [ ] les suites locales du scanner concerné passent avant la campagne réelle
- [ ] les rapports produits seront archivés avec la date, la machine et le contexte

Ce qu'il faut toujours noter dans la fiche de campagne :

- date de la campagne ;
- nom de la machine ou identifiant d'hôte ;
- OS exact ;
- privilèges réels utilisés ;
- langue du système si Windows ;
- présence ou absence des outils importants ;
- ce que l'environnement empêche de valider.

## Linux et Proxmox

Le scanner Linux et le scanner Proxmox sont le **même** scanner :

- [`scanners/linux/sysaudit.sh`](../../scanners/linux/sysaudit.sh)

La campagne dédiée est :

- `scripts/validate-linux-scanner.sh`

### Prérequis

- machine Linux ou hôte Proxmox
- `root`
- Node.js ≥ 20
- `npm ci`

### Commandes

```bash
npm ci
npm run build:packages
npm run lint:shell
npm run test:scanner
sudo -E env "PATH=$PATH" ./scripts/validate-linux-scanner.sh
```

Variantes utiles :

```bash
sudo -E env "PATH=$PATH" ./scripts/validate-linux-scanner.sh --skip-stress --monitor 30
sudo -E env "PATH=$PATH" ./scripts/validate-linux-scanner.sh --output-dir /root/validation
./scripts/validate-linux-scanner.sh --analyze-only /root/validation/rapport-normale.json
```

### Colonnes à relever

Linux standard :

- `hardware`
- `software`
- `storage`
- `smart`
- `network`
- `security`
- `virtualization`
- `monitoring`
- `benchmark`

Historique à relever aussi :

- `stability`
- `boot`
- `shutdown`
- `events`
- `power`

Proxmox ajoute ses propres domaines dans la campagne ; ils doivent être notés
dans la fiche de validation Proxmox, mais la règle reste la même : seul
`collecte` autorise un ✅.

### Ce qu'il ne faut pas surinterpréter

- Sous WSL, le matériel, le stockage, SMART et l'alimentation ne valident pas la
  machine réelle.
- Dans un conteneur LXC, les paquets et l'observation peuvent être valides, pas
  le matériel physique.
- Sur un hôte Proxmox en production, `--stress` peut être volontairement évité ;
  dans ce cas `benchmark` ne monte pas.

### Quand mettre à jour la matrice

Seulement si la campagne a produit une **vraie collecte** sur la cible qui porte
la ligne concernée :

- Ubuntu sur métal pour `hardware`/`smart`
- Raspberry Pi OS sur un vrai Raspberry Pi
- Fedora / Rocky / Alma / Arch sur machine ou VM pertinente selon la colonne
- Proxmox sur un vrai nœud PVE

## Windows 11, Windows 10 et Windows Server

Le scanner utilisé est :

- [`scanners/windows/sysaudit.ps1`](../../scanners/windows/sysaudit.ps1)

La campagne dédiée est :

- `scripts/validate-windows-scanner.ps1`

Commande npm associée :

```powershell
npm run validate:windows
```

### Prérequis

- machine Windows 10, 11 ou Server
- console PowerShell **administrateur**
- préférence pour `powershell.exe` (Windows PowerShell 5.1), qui est la cible minimale annoncée
- Node.js ≥ 20
- `npm ci`

### Commandes

Depuis une console PowerShell administrateur :

```powershell
npm ci
npm run lint:powershell
npm run test:scanner:windows
npm run validate:windows
```

Variantes utiles :

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\validate-windows-scanner.ps1 `
  -SkipStress -Monitor 30 -OutputDir C:\sysaudit-validation

powershell -ExecutionPolicy Bypass -File .\scripts\validate-windows-scanner.ps1 `
  -AnalyzeOnly C:\sysaudit-validation\rapport-normale.json
```

### Colonnes à relever

- `hardware`
- `software`
- `storage`
- `smart`
- `network`
- `security`
- `virtualization`
- `monitoring`
- `benchmark`

Historique à relever aussi :

- `stability`
- `boot`
- `shutdown`
- `events`
- `power`

### Points manuels à vérifier

- [ ] les catégories d'incidents ne sont pas toutes `OTHER` sur un Windows non anglophone
- [ ] `boot.fastStartupEnabled` est bien lu
- [ ] si `fastStartupEnabled = true`, le constat attendu apparaît
- [ ] les champs de sécurité modernes ne restent pas en `NOT_AVAILABLE` permanent
- [ ] Windows Server n'hérite pas automatiquement de la validation de Windows 11

### Ce qu'il ne faut pas surinterpréter

- Une campagne Windows 11 ne valide **pas** Windows Server.
- Une suite PowerShell verte ne valide **pas** les neuf colonnes de la matrice.
- Une VM Windows peut laisser `smart` en `marqueur` de façon légitime.
- Si WinSAT est absent, `benchmark` ne monte pas.

## Windows 8.1, 8, 7, Vista et XP

À la date du **2026-08-02**, aucune campagne réelle de compatibilité ne peut
encore valider ces lignes.

Pourquoi :

- le scanner `windows-legacy` n'est pas encore implémenté complètement ;
- le scanner `windows-minimal` n'existe pas ;
- une ligne non implémentée ou partiellement cadrée ne peut pas être promue dans
  la matrice.

Conséquence :

- `Windows 8.1 / 8 / 7` reste non validable tant que la couche legacy n'est pas prête ;
- `Windows Vista / XP` reste au stade planifié.

## Labo Windows recommandé

Si l'objectif est de faire progresser la matrice de compatibilité avec le moins
de coût possible, l'ordre rentable est le suivant :

1. commencer par une VM `Windows Server`
2. préparer ensuite des VM `Windows 8.1`, `Windows 8` et `Windows 7`
3. réserver la machine physique aux colonnes réellement bloquées par la virtualisation

### Ce qu'il faut installer en priorité

#### 1. Windows Server

À installer **tout de suite** si l'objectif est de faire monter la ligne
`Windows Server` dans [`COMPATIBILITY.md`](../../COMPATIBILITY.md).

Recommandation :

- `Windows Server 2022` ou `Windows Server 2019`
- en **VM** d'abord
- avec session administrateur locale
- avec `powershell.exe` disponible

Pourquoi la VM est le meilleur point de départ :

- elle suffit pour valider rapidement le scanner moderne ;
- elle permet d'exercer logiciel, réseau, sécurité, virtualisation et une large
  partie du stockage ;
- elle coûte peu à créer, dupliquer et jeter si la campagne doit être refaite.

Ce qu'une VM risque de ne pas valider complètement :

- `smart`
- une partie de `benchmark`
- certains signaux matériels trop abstraits derrière l'hyperviseur

#### 2. Windows 8.1, Windows 8 et Windows 7

À installer **ensuite**, non pour cocher immédiatement la matrice, mais pour
construire et éprouver le futur scanner `windows-legacy`.

Recommandation :

- une VM `Windows 8.1`
- une VM `Windows 8`
- une VM `Windows 7 SP1`

Pourquoi des VM de labo :

- le scanner legacy n'est pas encore validable officiellement ;
- le besoin immédiat est de voir le comportement réel de `WMI`,
  `Get-EventLog`, du registre et des vieilles versions de PowerShell ;
- une VM permet d'essayer, casser, rebooter et comparer plusieurs versions sans
  dépendre de matériel ancien.

Ce que ces VM servent à prouver dès maintenant :

- quelles commandes existent réellement ;
- quelles classes WMI répondent ou non ;
- quels journaux d'événements sont lisibles ;
- où il faut des replis spécifiques par version.

Ce qu'elles ne permettent pas encore, à elles seules :

- promouvoir officiellement `Windows 8.1 / 8 / 7` en ✅ dans la matrice tant que
  le scanner legacy n'est pas terminé.

#### 3. Windows Vista et Windows XP

Ne pas commencer par eux.

Ils ne deviennent utiles que lorsque la couche `windows-minimal` existera, ou si
un comportement précis doit être confirmé plus tard.

### Hyperviseur recommandé

Le document ne force pas d'hyperviseur unique. L'important est d'avoir :

- des instantanés ;
- un réseau simple à comprendre ;
- une console stable ;
- la possibilité d'ajouter ou retirer facilement disque et carte réseau.

Choix raisonnables :

- `Hyper-V` si l'hôte est déjà Windows ;
- `VirtualBox` pour un labo simple et portable ;
- `Proxmox VE` si le labo vit déjà sur un nœud d'infrastructure ;
- `VMware` si c'est déjà l'outil du parc.

### Taille minimale du labo

Le plus petit labo utile :

1. une VM `Windows Server 2022` ou `2019`
2. une VM `Windows 8.1`
3. une VM `Windows 7 SP1`

Labo plus complet :

1. une VM `Windows Server 2022`
2. une VM `Windows Server 2019`
3. une VM `Windows 8.1`
4. une VM `Windows 8`
5. une VM `Windows 7 SP1`

Pourquoi `Windows 8.1` avant `Windows 8` :

- `8.1` est le point d'arrivée le plus utile de la branche legacy ;
- si `8.1` casse déjà sur une hypothèse du scanner, il faut corriger là avant
  d'aller plus bas ;
- `8` et `7` servent ensuite à mesurer jusqu'où les replis doivent descendre.

### Ordre conseillé des campagnes

1. valider `Windows Server` en VM avec `npm run validate:windows`
2. relever les colonnes qui restent en `marqueur` à cause de la VM
3. mettre à jour `compatibility.ts` seulement pour ce qui est réellement collecté
4. monter une VM `Windows 8.1` pour exercer la couche legacy en développement
5. tester ensuite `Windows 8`
6. finir par `Windows 7`
7. n'envisager le physique que si une colonne importante ne peut pas être levée en VM

### Quand une machine physique devient nécessaire

La machine physique est utile si l'un des objectifs suivants bloque :

- lire un vrai `SMART`
- mesurer un comportement disque réel
- observer un pilote ou un périphérique masqué par la VM
- confirmer une limite de sécurité dépendante du matériel
- distinguer un problème du scanner d'un artefact de l'hyperviseur

En l'absence d'un de ces blocages, une VM reste le meilleur compromis coût /
rapidité / reproductibilité.

## macOS

Le scanner existe, mais il est encore :

- `EXPERIMENTAL / UNVALIDATED`

Fichiers concernés :

- [`scanners/macos/sysaudit.sh`](../../scanners/macos/sysaudit.sh)
- [`scanners/macos/README.md`](../../scanners/macos/README.md)

### Commandes

```bash
cd scanners/macos
./sysaudit.sh --capabilities
./sysaudit.sh
./sysaudit.sh --stdout | jq .
./sysaudit.sh --output-dir /tmp/audit
```

### Ce qu'une première campagne doit faire

- produire au moins un JSON sur un vrai Mac ;
- noter précisément la machine : Intel ou Apple Silicon ;
- relever quelles sections produisent une vraie valeur ;
- confirmer quelles sections restent en marqueur ;
- rendre le rapport en HTML pour vérifier qu'aucun zéro n'est inventé.

### Avant de modifier la matrice

Il faut au minimum :

- une exécution réelle sur Mac ;
- un relevé colonne par colonne ;
- un écrit clair de ce qui manque encore ;
- une décision explicite sur les colonnes qui peuvent passer de `PLANNED` à
  `IMPLEMENTED` ou `VALIDATED` selon le système utilisé dans `compatibility.ts`.

## FreeBSD, pfSense et OPNsense

Le scanner existe, mais il est encore :

- `EXPERIMENTAL / UNVALIDATED`

Fichiers concernés :

- [`scanners/bsd/sysaudit.sh`](../../scanners/bsd/sysaudit.sh)
- [`scanners/bsd/README.md`](../../scanners/bsd/README.md)

### Commandes

```sh
cd scanners/bsd
./sysaudit.sh --capabilities
sudo ./sysaudit.sh --output-dir /root/audit
```

### Ce qu'une première campagne doit distinguer

- FreeBSD
- pfSense
- OPNsense

Une exécution sur l'un des trois ne valide pas automatiquement les deux autres.

### Points à relever

- état du pare-feu avec et sans `root`
- détection correcte de la distribution
- séparation entre version de l'appliance et version de base FreeBSD
- colonnes réellement produites contre colonnes seulement dégradées

## Android

Le scanner existe, mais il est encore :

- `EXPERIMENTAL / UNVALIDATED`

Fichiers concernés :

- [`scanners/android/sysaudit.sh`](../../scanners/android/sysaudit.sh)
- [`scanners/android/README.md`](../../scanners/android/README.md)

### Commandes

Depuis Termux :

```sh
cd scanners/android
./sysaudit.sh --capabilities
./sysaudit.sh --stdout
```

Depuis un poste via ADB :

```bash
adb push scanners/android/sysaudit.sh scanners/android/lib /data/local/tmp/sysaudit/
adb shell sh /data/local/tmp/sysaudit/sysaudit.sh --stdout > rapport-android.json
```

### Ce qu'une première campagne doit noter

- modèle exact de l'appareil ;
- mode de collecte : Termux, ADB, root, non-root ;
- appareil sur secteur ou batterie ;
- ce qui est lisible uniquement avec privilèges ;
- ce qui est volontairement hors périmètre.

## Rendre et relire un rapport

Après une campagne, rendre au moins un rapport en HTML :

```bash
npm run build:packages
node packages/report-renderer/dist/cli.js rapport.json --html rapport.html --md rapport.md
```

Vérifications minimales :

- [ ] aucun champ non lu n'apparaît comme un zéro
- [ ] les sections absentes sont bien signalées
- [ ] les marqueurs gardent leur raison
- [ ] le rapport reste cohérent avec la machine auditée

## Modifier `compatibility.ts`

Quand la campagne est terminée :

1. ouvrir [`packages/platform/src/compatibility.ts`](../../packages/platform/src/compatibility.ts)
2. trouver la ligne de la plateforme concernée
3. ne changer que les colonnes réellement justifiées par la campagne
4. garder un commentaire ou une note si la validation dépend du contexte exact
5. régénérer la documentation

Commande :

```bash
npm run docs:compatibility
```

## Ce qu'il faut archiver avec chaque validation

- [ ] date de campagne
- [ ] machine cible
- [ ] OS exact
- [ ] type d'environnement
- [ ] privilèges utilisés
- [ ] commandes exécutées
- [ ] rapports JSON produits
- [ ] au moins un rendu HTML
- [ ] tableau colonne par colonne
- [ ] ce qui n'a pas été couvert
- [ ] commit qui met à jour `compatibility.ts`

## Pièges à éviter

- cocher une case parce que "le code existe"
- cocher Windows Server après une campagne Windows 11
- cocher du matériel validé sous WSL
- cocher une colonne sur la base d'un `marqueur`
- éditer `COMPATIBILITY.md` directement
- oublier de noter le contexte exact de la machine

## Références

- [`COMPATIBILITY.md`](../../COMPATIBILITY.md)
- `../qualite/VALIDATION-CAMPAIGNS.md`
- [`./COMMANDES-PAR-OS.md`](./COMMANDES-PAR-OS.md)
- `../technique/DEVELOPMENT.md`
- [`packages/platform/src/compatibility.ts`](../../packages/platform/src/compatibility.ts)
