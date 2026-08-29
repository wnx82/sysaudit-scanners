# Scanner Windows

Collecteur PowerShell **read-only**, sous les mêmes règles que le scanner Linux.

## Où il vit

```text
scanners/windows/
├── sysaudit.ps1            Orchestrateur : arguments, isolation, assemblage
├── VERSION                 Version du scanner
├── MANIFEST                Fichiers distribués, dans l'ordre de chargement
├── lib/core/json.ps1       Marqueurs d'absence et conversions
├── lib/core/core.ps1       Élévation, isolation des collecteurs, problèmes
├── lib/collectors/*.ps1    Un collecteur par domaine
├── lib/output/markdown.ps1 Résumé lisible sans Node.js
└── tests/run.ps1           Suite de tests du scanner
```

Il vivait auparavant dans une **chaîne de caractères** au sein d'`apps/api` :
une application hébergeait un collecteur, ce qui inversait le sens des
dépendances du dépôt. Surtout, ces lignes échappaient à toute analyse statique,
à toute suite de tests et à toute validation de leur sortie contre le schéma :
une régression de collecte Windows n'était détectable par aucune barrière
automatique.

## Ce qu'il garantit

- **il ne modifie rien.** Aucune écriture système, aucun service touché. Seul le
  profil `stress` sollicite volontairement la machine, et il faut le demander ;
- **il n'invente rien.** Une donnée non collectée porte un marqueur avec sa
  raison — `UNKNOWN`, `NOT_AVAILABLE`, `UNSUPPORTED`, `PERMISSION_DENIED`. Une
  valeur négative rapportée par le système devient un marqueur plutôt qu'un
  zéro : ramener à zéro fabriquerait un compteur nul là où la lecture a échoué ;
- **l'échec d'un collecteur n'interrompt pas l'audit.** Chaque collecteur passe
  par `Invoke-Collector` : une exception devient un problème dans
  `collection.issues` et une section absente, jamais un audit perdu ;
- **il ne dépend d'aucun paquet Node.js.** Il doit tourner sur une machine qui
  n'en a pas.

## Lancer un audit

```powershell
# Local, sans rien envoyer
powershell -ExecutionPolicy Bypass -File .\sysaudit.ps1 -Profile standard

# Depuis l'API, avec téléchargement et vérification d'empreinte
irm https://api.exemple.test/audit/w | iex
```

| Profil     | Élévation requise | Contenu                            |
| ---------- | ----------------- | ---------------------------------- |
| `quick`    | non               | Système, sécurité, réseau          |
| `security` | non               | Idem, orienté sécurité             |
| `standard` | **oui**           | + matériel, mémoire, GPU, stockage |
| `full`     | **oui**           | Idem `standard`                    |
| `stress`   | **oui**           | + banc d'essai                     |

Les profils légers se contentent de ce qu'un utilisateur standard peut lire. Les
autres exigent l'élévation pour ne pas produire un rapport majoritairement vide,
qui se lirait comme une machine sans matériel.

### « Impossible de se connecter au serveur distant »

```console
PS C:\> irm https://sysaudit.me/audit/w | iex
irm : Impossible de se connecter au serveur distant
```

Ce message n'est **pas** une erreur HTTP : la connexion a été coupée avant
qu'une réponse existe. Il ne dit donc rien de l'URL, du chemin, ni du serveur —
inutile de chercher du côté de `/audit/w`.

**Mesurer avant de supposer.** Deux causes très différentes produisent ce même
message, et une seule commande les sépare :

```powershell
Test-NetConnection sysaudit.me -Port 443
```

`Test-NetConnection` ouvre une connexion TCP brute : ni TLS, ni proxy, ni HTTP.
Sa ligne `TcpTestSucceeded` tranche.

#### `TcpTestSucceeded : False` — le réseau, pas TLS

La connexion n'est jamais établie. `PingSucceeded : True` sur la même sortie ne
contredit rien : ICMP et TCP/443 ne suivent pas les mêmes règles de filtrage, et
un pare-feu qui laisse passer le premier bloque très bien le second.

```powershell
# Est-ce cet hôte, ou tout le 443 sortant ?
Test-NetConnection 1.1.1.1 -Port 443
Test-NetConnection github.com -Port 443

# Un proxy imposé ? Test-NetConnection l'ignore, un navigateur l'emprunte.
netsh winhttp show proxy
(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings').ProxyServer

# Le DNS rend-il les adresses attendues ?
Resolve-DnsName sysaudit.me -Type A
```

La question qui va le plus vite : **un navigateur, sur cette même machine,
ouvre-t-il le site ?** Si oui et que le TCP brut échoue, c'est un proxy
d'entreprise — le navigateur l'emprunte, `Test-NetConnection` non ; voir
« Derrière un proxy » ci-dessous. Si non, c'est un filtrage sortant, et il faut
le lever côté réseau : **aucune option de la commande d'audit n'y peut quoi que
ce soit**, et prétendre le contraire ferait perdre du temps.

La commande qui tranche définitivement entre les deux, parce qu'elle dit ce que
.NET fera vraiment :

```powershell
[System.Net.WebRequest]::GetSystemWebProxy().GetProxy('https://sysaudit.me')
```

Elle rend l'adresse d'un proxy s'il y en a un. Si elle rend **l'URL demandée
elle-même**, c'est la façon dont .NET dit « connexion directe » : il n'y a aucun
proxy, et un `TcpTestSucceeded : False` désigne alors un pare-feu.

#### `TcpTestSucceeded : True` — alors c'est TLS

Le port répond, mais la poignée de main échoue. Sur Windows PowerShell 5.1,
`.NET Framework` propose encore « SSL 3.0, TLS 1.0 » sur une partie du parc, et
tout hôte correctement configuré — `sysaudit.me` compris — refuse ces versions.

```powershell
# « Ssl3, Tls » ou « Tls » = c'est la cause.
# « SystemDefault » ou une valeur contenant « Tls12 » = ce n'est pas ça.
[Net.ServicePointManager]::SecurityProtocol

# La commande, avec TLS 1.2 ajouté pour cette console uniquement.
[Net.ServicePointManager]::SecurityProtocol =
  [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
irm https://sysaudit.me/audit/w | iex
```

Rien à installer, rien à modifier durablement : le réglage disparaît à la
fermeture de la console. **Le script d'amorçage et le scanner posent eux-mêmes
cette ligne** depuis la 0.89.4 — l'amorçage télécharge ensuite une vingtaine de
fichiers, et le scanner téléverse son rapport depuis un processus distinct qui
n'hérite d'aucun réglage. Seul le tout premier `irm`, celui qui va chercher
l'amorçage, échappe par nature à cette barrière : c'est celui que la commande
ci-dessus répare.

### Derrière un proxy d'entreprise

Le scanner **emprunte** le proxy, il ne le contourne pas — un outil d'audit qui
esquive les contrôles réseau est le premier qu'un RSSI interdit. Ce qu'il faut,
c'est qu'il s'y authentifie avec les identifiants de l'administrateur qui le
lance.

Deux manques de Windows PowerShell 5.1 rendaient cela impossible, et sont
comblés depuis la 0.89.6, **dans le script d'amorçage comme dans le scanner** :

- il emprunte bien le proxy système, mais ne lui présente **jamais**
  d'identifiants. Un proxy NTLM ou Kerberos répondait 407 — et pour le scanner,
  après une collecte pourtant réussie, ce qui est le pire ordre possible ;
- il ne lit ni `HTTPS_PROXY` ni `HTTP_PROXY`, contrairement à PowerShell 7 : sur
  un poste où ces variables sont la convention, rien ne permettait de désigner
  un proxy.

Les identifiants de la session ouverte ne quittent pas la machine : c'est
Windows qui répond au défi du proxy. Rien n'est écrit dans le registre ni dans
l'environnement — le réglage vaut pour le processus et disparaît avec lui.

**Le proxy système suffit dans la plupart des cas** : s'il est déclaré dans les
options Internet, il n'y a rien à faire. Sinon, par ordre de priorité :

```powershell
# 1. À la main, pour cette console. Vaut aussi pour l'amorçage : c'est le seul
#    canal qu'il ait, puisqu'il tourne avant que le scanner n'existe.
$env:HTTPS_PROXY = 'http://proxy.exemple.local:8080'
irm https://sysaudit.me/audit/w | iex

# 2. En option du scanner, quand on l'appelle directement ou par la forme longue.
#    Elle l'emporte sur toutes les variables.
& ([scriptblock]::Create((irm https://sysaudit.me/audit/w))) -Proxy http://proxy.exemple.local:8080
.\sysaudit.ps1 -Profile full -Upload -ApiUrl https://sysaudit.me -Proxy http://proxy.exemple.local:8080
```

L'ordre de décision est le même partout : `-Proxy`, puis `SYSAUDIT_PROXY`, puis
`HTTPS_PROXY`, puis `HTTP_PROXY`, puis le proxy système. `SYSAUDIT_PROXY` existe
pour désigner un proxy **à ce seul outil**, sans toucher aux variables que le
reste de la session utilise.

Un proxy qui exige des identifiants autres que ceux de la session ouverte les
accepte dans l'URL, chacun encodé : `http://domaine%5Cutilisateur:s%40cret@proxy:8080`
— un `\` ou un `@` dans un mot de passe ne peut voyager autrement. Ils ne sont
jamais affichés : seuls l'hôte et le port apparaissent à l'écran.

**`NO_PROXY` n'est pas lue**, et c'est délibéré. Sa syntaxe — suffixes, jokers,
plages — ne se traduit pas fidèlement en liste d'exclusion .NET, qui attend des
expressions régulières ; une exclusion mal traduite enverrait au proxy un hôte
qui devait l'éviter, sans que rien ne le signale. Les adresses locales, elles,
contournent le proxy (`BypassProxyOnLocal`).

**Ce que rien de tout cela ne répare :** un pare-feu qui refuse le 443 sortant,
sans proxy déclaré. La section précédente donne la commande qui distingue les
deux cas. Là, il faut ouvrir le flux côté réseau — vers l'hôte SysAudit
uniquement, qui est aussi celui qui reçoit le rapport — ou passer par le
parcours hors ligne ci-dessous.

### Auditer une machine hors ligne

Quand le flux ne peut pas être ouvert — réseau isolé, poste sensible, pare-feu
dont on n'obtiendra pas d'exception — l'audit se fait sans que la machine ne
joigne jamais le site. Rien n'y perd en garanties : le scanner reste en lecture
seule, et l'intégrité se vérifie hors ligne.

**1. Emporter le scanner**, depuis un poste qui a accès. L'archive contient
exactement les fichiers du manifeste, ce dernier compris :

```powershell
Invoke-WebRequest https://sysaudit.me/api/v1/scanners/windows/archive -OutFile sysaudit-windows.zip
```

**2. Vérifier ce qu'on a reçu**, sur la machine à auditer, avant de l'exécuter.
Le `MANIFEST` porte l'empreinte SHA-256 de chaque fichier et voyage avec eux :

```powershell
Expand-Archive .\sysaudit-windows.zip -DestinationPath .\sysaudit
Get-Content .\sysaudit\MANIFEST |
  Where-Object { $_ -notmatch '^#' -and $_.Trim() -ne '' } |
  ForEach-Object {
    $attendu = (Get-FileHash (Join-Path .\sysaudit $_) -Algorithm SHA256).Hash.ToLower()
    '{0}  {1}' -f $attendu, $_
  }
```

Le `MANIFEST` liste les chemins ; les empreintes attendues sont publiées par
`GET /api/v1/scanners/windows/manifest`, à consulter depuis le poste connecté.
Quand une clé de signature est configurée sur l'instance, l'archive porte aussi
`MANIFEST.sig` et `MANIFEST.pub` : l'origine se vérifie alors comme dans
l'amorçage. La limite est la même, et `docs/exploitation/SUPPLY-CHAIN.md` la traite — une clé
qui voyage avec ce qu'elle signe ne prouve rien seule.

**3. Auditer sans rien envoyer.** Sans `-Upload`, rien ne quitte la machine :

```powershell
.\sysaudit\sysaudit.ps1 -Profile full -OutputPath .\audit.json
```

**4. Déposer le rapport** depuis un poste qui atteint le site, par la page
[`/deposer`](https://sysaudit.me/deposer) — ou en ligne de commande, ce que
cette page ne fait que rendre confortable :

```powershell
curl.exe -X POST -H "Content-Type: application/json" `
  --data-binary "@audit.json" https://sysaudit.me/api/v1/scans/upload
```

Un rapport déposé ainsi est traité exactement comme un rapport envoyé par le
scanner : validé contre le schéma, débarrassé de ce qui ressemble à un secret,
et jamais répertorié publiquement sans que l'audit l'ait demandé. **L'envoi
n'exige aucun jeton d'amorçage** — les en-têtes de session sont facultatifs, et
c'est ce qui rend ce parcours possible sans passe-droit.

**Rattacher la machine à un compte**, si on le souhaite — rien ne l'exige. Le
code de liaison voyage normalement dans l'URL d'amorçage (`?link=SA-…`), que ce
parcours n'emprunte pas ; et l'option `-Claim` du scanner **exige `-Upload`**,
puisque le code se présente en en-tête au moment de l'envoi et n'entre jamais
dans le rapport — un rapport s'archive et se repartage, un code de rattachement
n'a rien à y faire.

Le code se saisit donc au moment du dépôt, dans le champ prévu sur
[`/deposer`](https://sysaudit.me/deposer). En ligne de commande, c'est le même
en-tête :

```powershell
curl.exe -X POST -H "Content-Type: application/json" -H "X-Machine-Claim: SA-ABCD-EFGH" `
  --data-binary "@audit.json" https://sysaudit.me/api/v1/scans/upload
```

Le code ne vaut qu'une fois et expire. Il s'obtient depuis « Mes machines », ou
**directement sur `/deposer`** quand on y est connecté : un bouton « Obtenir un
code » y évite l'aller-retour, puisque c'est là qu'on en a besoin. Sans code, le
rapport est simplement anonyme — le fonctionnement normal du produit.

### Banc d'essai

Le niveau `stress` **charge volontairement la machine** ; tout le reste du
scanner est en lecture seule.

`-Benchmark` ajoute la mesure à n'importe quel profil, sans basculer tout
l'audit en `stress` :

```powershell
.\sysaudit.ps1 -Profile full -Benchmark
```

C'est le symétrique de `--benchmark` sous Linux, et son absence se lisait dans
le parc : au 2026-08-27, 9 % des audits Windows portaient une mesure contre 23 %
des audits Linux, et les 36 audits `full` du parc n'en portaient aucune.
Réclamer une mesure ne devrait pas obliger à demander tout le reste.

La charge et le fichier temporaire sont les mêmes qu'en profil `stress` :
l'en-tête de session l'annonce avant de commencer, et un audit qui n'a pas
mesuré le rappelle en une ligne à la fin — sans jamais rien lancer de lui-même.

| Sous-système | Mesure                                           | Unité         |
| ------------ | ------------------------------------------------ | ------------- |
| Processeur   | WinSAT `cpuformal`                               | indice WinSAT |
| Mémoire      | WinSAT `memformal`                               | indice WinSAT |
| GPU          | WinSAT `d3d`                                     | indice WinSAT |
| Stockage     | Écriture et lecture séquentielles, lecture 4 Kio | Mio/s         |

Un **indice WinSAT** va de 1,0 à 9,9 : il se compare à un autre indice WinSAT,
jamais à un débit. Le stockage, lui, est mesuré en débit réel — WinSAT n'en
publie qu'un indice composite, dont aucun débit n'est déductible.

Cette mesure de stockage n'utilise que .NET : aucun outil tiers n'est
redistribué ni téléchargé. `diskspd` aurait demandé une analyse de licence et de
provenance, et le télécharger à l'exécution reviendrait à exécuter du code non
vérifié sur la machine auditée.

Les mêmes bornes que sous Linux s'appliquent : fichier de travail limité à un
dixième de la place libre (256 Mio au plus), volume écrit plafonné à 1 Gio — 2
Gio au niveau Poussée —, fichier supprimé quoi qu'il arrive. Les paramètres de
chaque mesure disent si le cache du système a été contourné.

WinSAT n'est pas installé partout, notamment sur Windows Server. Son absence
prive des trois indices, **pas** des débits disque : elle est déclarée mesure
par mesure.

Aucune température n'est relevée : Windows n'expose pas de capteur thermique
fiable sans composant tiers (voir [COMPATIBILITY.md](../../COMPATIBILITY.md)).

Sans `-Upload`, **rien ne quitte la machine** : le rapport est écrit sur le
disque, avec un résumé Markdown.

### Portée d'un envoi

`-Public` rend l'audit **répertoriable** — susceptible d'apparaître dans la
liste des diagnostics récents. Il ne le rend pas lisible : il l'était déjà par
son adresse, dès l'envoi.

`-Private` n'est pas une redondance du défaut. Sans en-tête, c'est le réglage
`DEFAULT_SCAN_VISIBILITY` de **l'instance** qui tranche, et il peut valoir
`PUBLIC` — c'est le cas de `sysaudit.me`, qui sert une vitrine. Sur une telle
instance, ne rien dire n'est pas demander le privé.

Poser `-Private` sur un audit de validation, de test ou d'exploitation est donc
le seul moyen de garantir qu'il n'apparaîtra pas en page d'accueil. Les deux
commutateurs ensemble sont refusés plutôt qu'arbitrés en silence.

### Où va le fichier

Dans le **dossier Téléchargements de l'utilisateur**, et non dans le répertoire
courant :

```text
C:\Users\wnx\Downloads\sysaudit-LAPTOP-WNX.json
```

Le répertoire courant a longtemps décidé, et il décidait mal. Une console
ouverte depuis le menu Démarrer, un clic droit « Exécuter en tant
qu'administrateur », un `powershell` lancé depuis CMD : tous ont
`C:\WINDOWS\system32` pour répertoire courant, et le rapport s'appelait alors
`C:\WINDOWS\system32\sysaudit-LAPTOP-WNX.json` — introuvable pour qui doit le
déposer, quand il n'était pas simplement refusé.

Le dossier Téléchargements est celui que **Windows déclare**, pas
`%USERPROFILE%\Downloads` : la valeur est lue dans le dossier connu
`FOLDERID_Downloads`, ce qui suit un dossier déplacé, renommé, redirigé par
stratégie de groupe ou repris par OneDrive. Un Téléchargements redirigé vers
`D:\Downloads` reçoit bien le rapport.

L'utilisateur visé est celui de la **session interactive**. Une élévation UAC
ordinaire conserve le compte et ne change donc rien ; un `runas /user:`, un
service ou une tâche planifiée sous LE SYSTÈME, si — le rapport suit alors la
personne devant la machine plutôt que le profil du compte qui exécute, qui vit
sous `C:\Windows\System32\config\systemprofile`.

Si ce dossier ne peut pas être utilisé, une chaîne de replis prend le relais, et
**chaque repli est annoncé en console** :

| Rang | Destination                              |
| ---- | ---------------------------------------- |
| 1    | dossier Téléchargements de l'utilisateur |
| 2    | `%USERPROFILE%\Downloads`, s'il existe   |
| 3    | `%LOCALAPPDATA%\SysAudit\Reports`        |
| 4    | `%TEMP%\SysAudit`                        |
| 5    | `%ProgramData%\SysAudit\Reports`         |

Aucun maillon n'est jamais un répertoire système : `C:\Windows`,
`C:\Windows\System32`, `C:\Program Files` et `C:\Program Files (x86)` sont
écartés même lorsqu'ils sont inscriptibles. Le cinquième rang existe pour le
seul cas où les quatre premiers tombent tous dedans — une tâche planifiée sous
LE SYSTÈME, dont le profil et le `%TEMP%` sont sous `C:\Windows`. Si rien ne
tient, le scanner le dit et s'arrête plutôt que d'écrire n'importe où.

Un `-OutputPath` demandé explicitement passe devant tout cela et n'est jamais
contourné. Un chemin relatif y est résolu depuis le répertoire courant — c'est
ce que veut dire `-OutputPath .\audit.json` tapé dans une console.

La décision vit dans `scanners/windows/lib/core/paths.ps1`.

### Stratégie d'exécution

Windows refuse par défaut d'exécuter un fichier `.ps1` — « l'exécution de scripts
est désactivée sur ce système ». C'est la valeur `Restricted`, appliquée sur les
éditions client, y compris dans une console administrateur.

Le script d'amorçage traite le cas : il lance le scanner dans un **processus
dédié** avec `-ExecutionPolicy Bypass`, ce qui ne modifie rien sur la machine —
aucune écriture de registre, aucune stratégie relâchée au-delà de ce processus.

En lancement direct depuis le dépôt, il faut le demander soi-même :

```powershell
powershell -ExecutionPolicy Bypass -File .\scanners\windows\sysaudit.ps1 -Profile standard
```

Une stratégie imposée par **stratégie de groupe** ne peut être contournée par
personne, pas même par un administrateur. Dans ce cas, le script d'amorçage le
dit explicitement plutôt que de laisser chercher.

## Distribution

Le script d'amorçage (`/audit/w`) **télécharge** le scanner fichier par fichier
et **vérifie chaque empreinte SHA-256** avant de l'exécuter. Ce script lance du
code téléchargé en administrateur : la vérification est la seule garantie qui ne
repose pas uniquement sur TLS et sur la confiance faite à l'hôte d'API.

Sous Windows, le scanner téléchargé n'est plus extrait dans `%TEMP%`, mais dans
un dossier de travail stable sous `LocalAppData\\SysAudit`, supprimé à la fin de
l'audit. Ce choix réduit les faux positifs heuristiques d'antivirus comme Avast,
qui signalent plus volontiers un script PowerShell lancé depuis un dossier
temporaire aléatoire.

La liste des fichiers vient de `MANIFEST` — source de vérité unique, lue par
`sysaudit.ps1`, par l'API et par l'amorçage. Un test échoue si le scanner charge
un fichier absent du manifeste, ou l'inverse.

| Route                                     | Contenu                       |
| ----------------------------------------- | ----------------------------- |
| `GET /api/v1/scanners/windows`            | Version et empreinte          |
| `GET /api/v1/scanners/windows/manifest`   | Fichiers servis et empreintes |
| `GET /api/v1/scanners/windows/file?path=` | Un fichier du manifeste       |

### Faux positifs antivirus (`IDP.Generic`)

Avast — et d'autres antivirus **comportementaux** (AVG, SmartScreen) — peut
signaler le bootstrap Windows comme `IDP.Generic` lorsqu'un script PowerShell
**non signé** télécharge un autre script, collecte largement le système, puis
l'exécute. Le scanner coche toutes les cases de cette heuristique sans être
malveillant : c'est un faux positif, pas une compromission, et le signalement
ne le prouve pas à lui seul.

La bonne réponse n'est **pas** d'obscurcir le scanner pour passer sous le radar —
pour un outil d'audit de sécurité, cela le rendrait plus suspect, pas moins, et
masquer le comportement réel d'un script est précisément ce que l'heuristique
cherche. La réponse est d'**authentifier** le code et de **réduire les
déclencheurs gratuits**. Quatre leviers, du plus durable au plus ponctuel.

#### 1. Signer le scanner (Authenticode) — le correctif durable

Une signature Authenticode valide, horodatée, portée par un certificat de
signature de code reconnu, est le facteur qui éteint `IDP.Generic` **et**
SmartScreen. Elle n'obscurcit rien : elle prouve l'origine du code, ce qui est
l'inverse d'une évasion.

```powershell
# Depuis un PFX (mot de passe demandé de manière interactive) :
pwsh scripts/sign-windows-scanner.ps1 -PfxPath .\sysaudit-codesign.pfx

# Ou depuis un certificat déjà installé, par empreinte :
pwsh scripts/sign-windows-scanner.ps1 -Thumbprint 1A2B3C...
```

Le script signe les 21 `.ps1` du `MANIFEST` (`VERSION` et `MANIFEST`, non
exécutables, ne sont pas signables et restent couverts par leur empreinte).

**Ordre impératif** : signer un `.ps1` lui ajoute un bloc de signature, donc
**change son empreinte SHA-256**. Le bootstrap vérifie ces empreintes contre le
manifeste servi par l'API. Il faut donc **signer avant** que les empreintes
distribuées soient calculées — signer, puis publier, jamais l'inverse.

Le bloc d'amorçage `/audit/w` lui-même est généré par l'API à chaque requête,
avec des valeurs interpolées : il ne peut pas être signé de cette façon. C'est
la couche que la signature détachée de la liste d'empreintes
(docs/exploitation/SUPPLY-CHAIN.md) et la variante « fichier » ci-dessous
protègent à sa place.

#### 2. Variante « fichier », sans `iex` en mémoire

La commande courte `irm …/audit/w | iex` exécute du code distant **en mémoire** :
c'est le motif que les antivirus comportementaux pèsent le plus lourd. La
variante suivante télécharge d'abord le bootstrap dans un fichier, puis le lance
avec `-File` — même effet, sans exécution en mémoire, donc moins de faux
positifs :

```powershell
$b = Join-Path $env:LOCALAPPDATA 'sysaudit-bootstrap.ps1'
irm https://sysaudit.me/audit/w -OutFile $b
powershell -ExecutionPolicy Bypass -File $b
Remove-Item $b
```

Elle réduit le déclencheur sans rien masquer ; elle ne remplace pas la
signature, qui reste le seul correctif de fond.

#### 3. Signaler le faux positif à Avast

Un signalement fait retirer la détection **pour tout le monde**, à la source.
Dossier à soumettre sur le formulaire de faux positif d'Avast
(`avast.com/false-positive-file-form`, section « fichier ») :

- l'URL `https://sysaudit.me/audit/w` et le ou les fichiers signalés ;
- leurs empreintes SHA-256 (`GET /api/v1/scanners/windows/manifest`) ;
- une description d'éditeur : outil d'audit système **en lecture seule**,
  open source, dont le code est vérifiable et — une fois le levier 1 en place —
  signé.

#### 4. Exclusion côté utilisateur — en dernier recours

En attendant la propagation d'un signalement, un utilisateur peut ajouter une
exception **ciblée** :

- visez le dossier `LocalAppData\\SysAudit` ou le script précis, **jamais**
  `powershell.exe` ni tout le répertoire temporaire ;
- préférez, quand c'est possible, l'exécution depuis une copie locale du dépôt
  (`git clone`), qui ne télécharge rien à l'exécution.

## Barrières automatiques

| Barrière               | Commande                       | Où elle tourne        |
| ---------------------- | ------------------------------ | --------------------- |
| Analyse statique       | `npm run lint:powershell`      | CI (`windows-latest`) |
| Tests du scanner       | `npm run test:scanner:windows` | CI (`windows-latest`) |
| Syntaxe et couture     | `npm run test`                 | Partout               |
| Version de schéma      | `npm run test`                 | Partout               |
| Manifeste ↔ chargement | `npm run test`                 | Partout               |

La ligne « syntaxe et couture » existe parce que les deux premières ne tournent
pas sous Linux : équilibre des délimiteurs, absence de reliquat de gabarit et
existence des fonctions appelées par l'orchestrateur sont vérifiés partout, par
`scanners/windows/tests/syntax.test.ts`.

Sans PowerShell installé, les deux premières commandes **le disent et
s'arrêtent** plutôt que d'échouer : un développeur sous Linux doit pouvoir
lancer le reste de la suite. La CI, elle, fournit toujours PowerShell.

Le scan de bout en bout ne peut tourner que sous Windows — les collecteurs
interrogent CIM. Sur un autre système, la suite annonce ce plan comme ignoré :
un test silencieusement absent ne prouverait rien, un test annoncé comme ignoré,
si.

## Ce qui n'est pas collecté

Déclaré dans `collection.skippedSections` de chaque rapport, pour qu'un rapport
partiel ne se lise pas comme une machine sans rien :

`devices`, `drivers`, `firmware`, `software`, `virtualization`.

Les profils légers y ajoutent le matériel et le stockage.

## Historique, stabilité, démarrage et arrêt

Le scanner lit ce que Windows a **déjà écrit**. Il n'active aucun canal, ne
change aucun niveau de trace et n'écrit nulle part.

**Le classement s'appuie sur le fournisseur et l'identifiant, pas sur le
texte.** Les identifiants sont invariants là où les messages sont traduits dans
la langue du système : un `Microsoft-Windows-Kernel-Power` 41 est un arrêt
inattendu quelle que soit la langue. Classer sur le libellé aurait produit un
scanner qui ne fonctionne qu'en anglais.

Sources lues : `System` et `Application` pour les incidents,
`Microsoft-Windows-Diagnostics-Performance/Operational` pour les durées de
démarrage, `User32` 1074 et `Kernel-Power` 41 pour l'arrêt, `Win32_Service` pour
les services en échec.

**Le canal `Security` n'est pas lu** : il exige l'élévation et contient des
données personnelles.

### Limitations connues

- **`Microsoft-Windows-Diagnostics-Performance/Operational` est absent des
  éditions Server Core.** Sans lui, aucune durée de démarrage n'est mesurée, et
  l'absence est déclarée plutôt que devinée.
- **La fenêtre demandée n'est pas la fenêtre obtenue.** Un journal Système
  limité à 20 Mo tourne en quelques jours sur une machine bavarde :
  `events.window.coveredMs` dit ce qui est réellement couvert.
- **Fréquence et bridage ne sont pas échantillonnés.** Les compteurs de
  performance ne publient pas de bridage thermique, et le déduire d'une
  fréquence basse est ce que ce scanner s'interdit.
- **Les vidanges mémoire ne sont pas recensées.** Windows en produit, mais leur
  inventaire passe par Windows Error Reporting, dont le format n'est pas
  documenté de façon stable.
- **Le compteur de cycles de batterie n'est pas lu** : `Win32_Battery` ne le
  publie pas.
- **`Win32_DeviceGuard` distingue trois états** — ce que le matériel permet, ce
  que la politique demande, ce qui tourne. La protection DMA n'est publiée qu'en
  disponibilité matérielle : elle apparaît donc en `PARTIAL`, jamais en
  `ENABLED`.
