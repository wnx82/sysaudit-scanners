# Avast et le scanner Windows — `IDP.Generic`

Avast signale régulièrement `sysaudit.ps1` comme **`IDP.Generic`**, avec pour
motif « actions suspectes ».

Ce document dit ce que cette détection veut dire, ce qu'elle ne veut pas dire,
ce que le scanner fait réellement, et comment vérifier par vous-même le fichier
que vous vous apprêtez à exécuter.

## Ce que `IDP.Generic` signifie

`IDP` désigne l'**Identity Protection** d'Avast : un moteur **comportemental**.
Il ne compare pas le fichier à une empreinte de logiciel malveillant connu ; il
observe ce que le processus fait et le rapproche de schémas d'action qu'il juge
préoccupants.

Deux conséquences, et il faut tenir les deux :

- **Une détection heuristique ne prouve pas qu'un fichier est malveillant.**
  Elle dit qu'un comportement ressemble à autre chose.
- **Son absence ne prouve pas qu'un fichier est sain.** Aucune section de ce
  document ne doit se lire comme « SysAudit est sûr parce qu'un antivirus ne dit
  rien ».

Ce que vous pouvez établir vous-même est plus modeste et plus solide : **quel
fichier exactement vous exécutez**. C'est l'objet de la section
« Vérifier ce que vous exécutez ».

## Pourquoi un scanner système ressemble à ce qu'un antivirus surveille

Un outil d'audit fait, par construction, ce qu'un logiciel de reconnaissance
ferait avant une attaque. La liste ci-dessous n'est pas une excuse : c'est
l'énoncé de ce qui, dans SysAudit, est légitimement présent et légitimement
observé.

| Comportement                                              | Pourquoi SysAudit le fait                           |
| --------------------------------------------------------- | --------------------------------------------------- |
| Inventaire matériel par WMI/CIM                           | C'est l'objet du produit : décrire la machine       |
| Relevé d'identifiants matériels (numéros de série, UUID)  | Reconnaître la même machine d'un audit à l'autre    |
| Inventaire réseau : interfaces, adresses, ports en écoute | Diagnostiquer la connectivité et la surface exposée |
| Inventaire des processus, services et logiciels installés | Constater ce qui tourne et ce qui est installé      |
| Lecture du registre                                       | Version du système, logiciels, réglages de sécurité |
| Envoi d'un rapport JSON à une API                         | Rendre le rapport lisible et comparable             |
| Téléchargement de fichiers puis exécution de l'un d'eux   | C'est la commande d'installation en une ligne       |

Le dernier point est celui qui pèse le plus lourd dans une heuristique : un
processus qui télécharge du code puis l'exécute est la forme que prend un
installeur malveillant. SysAudit ne peut pas ne pas le faire — c'est ce qu'une
commande d'installation _est_ — mais il peut le faire de la façon la plus
vérifiable possible, et c'est ce que la section suivante décrit.

## Ce que SysAudit a changé pour réduire les causes légitimes

Aucune de ces mesures ne vise à **échapper** à une détection. Elles suppriment
des caractéristiques qui rendaient le scanner inutilement difficile à
distinguer d'un programme hostile.

- **Le répertoire de travail est stable.** Il était
  `%LOCALAPPDATA%\SysAudit\scanner-<identifiant aléatoire>`. Un nom de dossier
  tiré au hasard, créé juste avant d'y écrire des fichiers téléchargés puis d'en
  exécuter un, est exactement ce qu'un installeur malveillant fait pour ne
  jamais être retrouvé deux fois au même endroit. Il est désormais
  `%LOCALAPPDATA%\SysAudit\Scanner`, et l'isolation de deux audits simultanés
  passe par un verrou de fichier.
- **Chaque requête s'annonce.** L'en-tête `User-Agent` porte
  `SysAudit-Windows-Bootstrap/<version>`. Un en-tête se forge, donc cela ne
  prouve rien ; mais son absence est un signal, et ce signal est retiré.
- **Rien n'est exécuté avant vérification.** Les fichiers sont téléchargés vers
  des chemins explicites, leur empreinte SHA-256 est comparée à un manifeste,
  et ce manifeste porte une signature détachée vérifiée avec une clé publique
  intégrée au script. Une empreinte qui ne correspond pas interrompt tout.
- **`-Verify` répond à « qu'est-ce que je m'apprête à exécuter ? »** — voir
  ci-dessous.

Ce que SysAudit **ne fait pas**, et ne fera pas :

- aucun contournement AMSI ;
- aucune désactivation d'Avast ou de Microsoft Defender ;
- aucune exclusion antivirus ajoutée automatiquement ;
- aucune obfuscation, aucun `EncodedCommand`, aucun Base64 portant du code ;
- aucune injection de processus, aucun _process hollowing_ ;
- aucune persistance, aucune tâche planifiée ;
- aucune altération des journaux antivirus.

Le scanner ne contient ni `Invoke-Expression`, ni `Add-Type`, ni P/Invoke, ni
réflexion .NET, ni chargement dynamique de DLL. C'est vérifiable dans le dépôt.

### Le point qui reste, et pourquoi

Le scanner est lancé dans un processus dédié avec `-ExecutionPolicy Bypass`.
Cela mérite d'être expliqué plutôt que tu.

La stratégie d'exécution de Windows vaut `Restricted` par défaut sur une édition
client : **aucun** fichier `.ps1` ne s'y exécute. Le drapeau s'applique au seul
processus lancé — il n'écrit rien dans le registre, ne relâche aucune stratégie
au-delà, et ne survit pas à la fin de l'audit. Une stratégie imposée par
stratégie de groupe reste d'ailleurs plus forte et n'est pas contournée : dans
ce cas le scanner s'arrête et le dit.

Ce n'est donc pas un contournement de sécurité, mais ce n'est pas non plus
anodin, et vous avez le droit de le refuser : le dépôt se clone, et le scanner
s'exécute depuis une copie locale.

## Vérifier ce que vous exécutez

```powershell
# Depuis le répertoire du scanner
.\sysaudit.ps1 -Verify
```

La sortie donne :

- le nom et la **version** du scanner ;
- la version du format de rapport ;
- le **chemin** exécuté ;
- l'édition et la version de PowerShell ;
- l'**empreinte SHA-256 de chaque fichier** listé au manifeste ;
- l'**état de la signature Authenticode**.

`-Verify` ne collecte rien, n'envoie rien, ne touche à aucun antivirus.

Comparez les empreintes à celles publiées par le dépôt
<https://github.com/wnx82/sysaudit-scanners>. Une empreinte identique prouve que le
fichier est **celui-là** ; elle ne prouve pas qu'il est sain, ce qui est une
question distincte et que vous seul pouvez trancher en lisant le code.

### Signature Authenticode

**Le scanner n'est pas signé.** SysAudit ne dispose pas de certificat de
signature de code : en acquérir un demande une identité vérifiée auprès d'une
autorité de certification et un coût annuel. Le dire est plus honnête que de
laisser croire à une vérification qui n'existe pas.

Les empreintes SHA-256 et la signature détachée du manifeste sont donc les
seules vérifications disponibles aujourd'hui. La signature Authenticode est
prévue et non réalisée — voir
la roadmap de durcissement
si elle est encore présente dans votre copie du dépôt.

## Ce que le scanner collecte, et ce qu'il ne collecte pas

La liste faisant foi est le **schéma de rapport versionné**
(`packages/report-schema`) : c'est lui qui décrit, champ par champ, tout ce
qu'un rapport peut porter — et un rapport ne peut rien porter d'autre, un test
d'empreinte du schéma échouant à la moindre dérive. Sa documentation
d'ensemble est dans [`../format-rapport/`](../format-rapport/).

Ne sont **jamais** collectés :

- aucun mot de passe, aucun secret, aucune clé d'API ;
- aucun cookie, aucun jeton de session ;
- aucun contenu de profil de navigateur, d'historique ou de favoris ;
- aucun contenu de fichier personnel ;
- aucune frappe clavier, aucune capture d'écran ;
- aucun contenu de courriel, de document ou de presse-papiers.

Le scanner **ne modifie rien** sur la machine auditée. Le seul mode qui la
sollicite est un banc d'essai, et il faut le demander explicitement.

## Si Avast bloque le scanner

Dans cet ordre, et pas dans un autre.

1. **Vérifiez le fichier** avec `-Verify`, et comparez les empreintes à celles
   du dépôt. Ne passez à la suite que si elles correspondent.
2. **Lisez le code** si le doute subsiste. Le scanner est en PowerShell, en
   clair, sans obfuscation, et publié — vous pouvez le lire avant de l'exécuter.
3. **Signalez le faux positif à Avast.** C'est la seule action qui corrige le
   problème pour tout le monde, et non pour vous seul. Le formulaire officiel
   de signalement de fichier se trouve sur le site d'Avast, dans l'espace de
   soumission d'échantillons du support ; sa localisation exacte change
   régulièrement, et ce document ne recopie pas une adresse qu'il ne peut pas
   garantir à jour. Cherchez « Avast report false positive file » depuis le
   domaine officiel `avast.com`.
4. **N'autorisez le fichier manuellement qu'après l'étape 1**, et seulement
   pour ce fichier.

Ce document ne recommande **pas** :

- d'ajouter une exclusion sur un dossier entier ;
- de désactiver durablement l'antivirus ;
- d'exécuter un fichier dont vous n'avez pas vérifié l'empreinte.

Un antivirus qui se trompe reste un antivirus qui vous protège le reste du
temps. Le désactiver pour faire passer un audit système est un mauvais échange.

## Ce que ce document ne prétend pas

Il ne prétend pas que SysAudit est sûr. Il vous donne de quoi décider : ce que
le programme fait, ce qu'il ne fait pas, comment identifier exactement le
fichier que vous exécutez, et où lire son code.

C'est tout ce qu'un éditeur peut honnêtement fournir. Le reste est votre
décision.
