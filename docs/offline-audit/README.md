# Audit hors ligne

Auditer une machine qui ne peut pas — ou ne doit pas — joindre SysAudit.

> **Le mode hors ligne n'est pas une option à activer : c'est le comportement
> par défaut.** Les scanners écrivent leur rapport sur le disque et ne
> transmettent rien tant qu'on ne le demande pas explicitement. Il n'existe donc
> pas de drapeau `--offline`, et il n'y a rien à désactiver.

---

## Les six étapes

```text
1. Télécharger le scanner        depuis un poste qui a accès
2. Copier le scanner             clé USB, partage interne, ce qu'on a
3. Exécuter l'audit              sur la machine isolée
4. Récupérer le JSON             il est écrit à côté du scanner
5. Aller sur SysAudit            depuis un poste connecté
6. Déposer le JSON               page « Déposer un rapport »
```

### 1. Télécharger le scanner

Depuis un poste qui atteint le site : page **Diagnostics**, section « Emporter
le scanner » (`/diagnostics#telecharger`), ou directement depuis la page de
dépôt (`/deposer`).

L'archive contient les fichiers du `MANIFEST`, chacun avec son empreinte
SHA-256, et — si l'instance dispose d'une clé de signature — `MANIFEST.sig` et
`MANIFEST.pub`.

> **Ce que la signature prouve, et ce qu'elle ne prouve pas.** Elle atteste que
> l'archive n'a pas été altérée **après** avoir quitté ce site. Elle n'atteste
> pas l'origine : un site compromis servirait aussi sa propre clé, et la
> vérification passerait — celle du faussaire. C'est un contrôle d'intégrité,
> pas une preuve d'authenticité.

### 2. Copier le scanner sur la machine

Aucune installation, aucun service, aucune écriture en base de registre ni dans
`/etc`. Le scanner est un ensemble de fichiers qu'on décompresse où l'on veut,
et qu'on supprime après.

### 3. Exécuter l'audit

**Windows**, dans une console PowerShell ouverte en administrateur :

```powershell
Expand-Archive .\sysaudit-windows.zip -DestinationPath .\sysaudit
.\sysaudit\sysaudit.ps1 -Profile full
```

**Linux** :

```bash
unzip sysaudit-linux.zip -d sysaudit
chmod +x sysaudit/sysaudit.sh
sudo ./sysaudit/sysaudit.sh --full
```

Sans `-Upload` / `--upload`, **rien ne quitte la machine**. Le scanner le dit en
fin d'exécution :

```text
[SysAudit] Rapport généré :
  ✓ /home/exploitation/sysaudit-serveur01.json
  ✓ /home/exploitation/sysaudit-serveur01.md
[SysAudit] Aucun envoi effectué. Utilisez --upload pour publier ce rapport.
```

Le niveau Rapide (`--quick` / `-Profile quick`) est le seul qui n'exige pas
l'élévation. Les autres la demandent pour ne pas produire un rapport
majoritairement vide, ce qui se lirait comme une machine sans matériel.

### 4. Récupérer le JSON

Il porte le nom `sysaudit-<machine>.json` et se trouve dans le répertoire
courant. Si celui-ci n'est pas inscriptible, le scanner bascule sur le
répertoire temporaire **et affiche le chemin retenu** — un audit réussi ne se
perd pas sur un détail de droits.

Un résumé Markdown est écrit à côté, lisible sans rien d'autre qu'un éditeur de
texte. `--no-markdown` / `-NoMarkdown` s'en dispense.

Le fichier est créé avec des droits restreints (`umask 077` côté Linux) : il
peut contenir des données personnelles.

### 5 et 6. Déposer le JSON

Sur un poste connecté, ouvrir **`/deposer`**, choisir le fichier, déposer.
L'adresse du rapport est renvoyée immédiatement.

**Conservez cette adresse.** Sans compte, c'est le seul moyen de retrouver le
rapport.

---

## Le scénario clé USB

```text
PC isolé
 ↓  audit
JSON
 ↓  clé USB
PC connecté
 ↓  dépôt
SysAudit → rapport
```

Rien dans ce parcours n'exige de compte, et le scanner reste en lecture seule
d'un bout à l'autre.

---

## Rattacher la machine à un compte

Un rapport déposé sans rien de plus est **anonyme** — ce qui est le
fonctionnement normal du produit, pas une dégradation.

Pour le rattacher à un compte, il faut un **code de liaison** (`SA-ABCD-EFGH`),
obtenu depuis « Mes machines » ou directement sur la page de dépôt une fois
connecté. Il se saisit dans le champ prévu au moment du dépôt.

Le code **ne voyage jamais dans le fichier**, seulement dans l'en-tête de la
requête : un rapport s'archive et se repartage, un code de rattachement n'a rien
à y faire. C'est aussi pourquoi `--claim` exige `--upload` côté scanner — un
audit hors ligne ne peut pas emporter le code dans son fichier, et le dépôt
manuel est le seul chemin qui rattache une machine coupée du réseau.

Le code ne vaut **qu'une fois**, pendant vingt-quatre heures, pour une machine.

### Le cas du technicien

Un technicien intervenant chez un client suit **exactement le même parcours** :
il audite hors ligne, dépose depuis un poste connecté, et saisit un code de
liaison obtenu depuis l'organisation du client pour rattacher la machine à son
parc.

Aucun droit particulier n'est attaché au dépôt, et c'est délibéré : le code de
liaison porte toute la décision de propriété, il est délivré par quelqu'un qui a
déjà les droits sur l'organisation, et il n'entre jamais dans le fichier — un
rapport transmis à un tiers ne lui donne donc aucun accès au parc.

Raisonnement complet : [ADR 0009](../adr/0009-integrite-et-propriete-des-rapports-deposes.md).

---

## Ce qu'un rapport prouve, et ce qu'il ne prouve pas

Il faut le dire une fois, clairement, parce que le parcours hors ligne le rend
plus visible qu'un envoi direct — sans pour autant le créer.

**Un rapport est une déclaration, pas une mesure certifiée.** Le fichier n'est
pas signé, et il ne le sera pas : une signature calculée sur la machine auditée
suppose un secret que le propriétaire de cette machine peut extraire. Elle
donnerait une garantie _apparente_, ce qui est pire que pas de garantie — on
traiterait comme prouvé ce qui ne l'est pas.

Ce qui **est** garanti, en revanche :

| Garantie             | Par quoi                                                |
| -------------------- | ------------------------------------------------------- |
| Intégrité en transit | TLS jusqu'à l'API, plafond de taille, corps vide refusé |
| Conformité           | Validation contre le schéma versionné, refus motivé     |
| Innocuité            | Détection de secrets, refus en `422`                    |
| Unicité              | `ingestKey` : un même audit ne devient jamais deux      |
| Traçabilité          | `collectionMode` et `transportMode`                     |

Cette limite vaut **identiquement pour un envoi direct** : un scanner modifié
envoie ce qu'on lui fait envoyer. Le dépôt manuel n'y change rien, et c'est
précisément pourquoi un audit déposé à la main n'est pas traité comme moins
fiable.

Détail de l'arbitrage : [ADR 0009](../adr/0009-integrite-et-propriete-des-rapports-deposes.md).

---

## Ce que le dépôt manuel ne change pas

Un rapport déposé à la main traverse la même chaîne qu'un envoi direct :

- **même validation** contre le schéma versionné ;
- **même détection de secrets** — un rapport qui en contiendrait est refusé ;
- **même déduplication** : déposer deux fois le même fichier ne crée pas deux
  audits, la seconde tentative retrouve le rapport existant ;
- **même pipeline d'analyse**, donc mêmes scores et mêmes recommandations ;
- **même confidentialité** : privé par défaut, jamais répertorié publiquement
  sans que l'audit l'ait demandé.

La page de dépôt **n'accorde aucun droit** que la ligne de commande n'avait pas :
`POST /api/v1/scans/upload` accepte déjà un rapport sans jeton d'amorçage, et un
`curl` faisait exactement la même chose. Elle existe parce que le navigateur ne
joint pas l'API directement, pas pour ouvrir quoi que ce soit qui était fermé.

### Ce que le rapport retient du trajet

Deux informations, distinctes et complémentaires :

| Champ            | Où il vit  | Ce qu'il dit                                                    |
| ---------------- | ---------- | --------------------------------------------------------------- |
| `collectionMode` | Le rapport | `online` / `offline` — comment la machine a été auditée         |
| `transportMode`  | La base    | `direct_upload` / `manual_import` — comment le fichier a voyagé |

Ils peuvent diverger, et c'est le cas intéressant : un audit lancé avec
`--upload` derrière un pare-feu se collecte `online` et se transporte à la main.

Le mode de transport n'est **pas** dans le fichier, délibérément : un rapport
archivé puis redéposé ailleurs des mois plus tard rejouerait sinon « dépôt
manuel » pour l'éternité.

**Un audit hors ligne n'est pas marqué comme moins fiable**, et ne doit pas
l'être : rien ne distingue sa collecte de celle d'un audit en ligne.

---

## Les plateformes sans envoi

Les scanners **macOS**, **BSD** et **Android** n'ont ni `--upload`, ni
`--api-url` : ils écrivent un fichier, un point. Pour ces trois plateformes, le
dépôt manuel n'est pas une solution de repli — c'est **le** parcours.

Ils ne sont pas distribués sous forme d'archive par l'API : ils se récupèrent
depuis le dépôt du projet.

---

## Avant de renoncer au réseau

Un blocage réseau se nomme avant de se contourner. Le scanner sait le faire
lui-même, sans produire d'audit :

```bash
./sysaudit.sh --network-test --api-url https://sysaudit.me
```

```powershell
.\sysaudit.ps1 -NetworkTest -ApiUrl https://sysaudit.me
```

Certaines causes se lèvent en une ligne — un proxy à déclarer, par exemple. Voir
Proxy, pare-feu et inspection TLS.

---

## Si l'envoi échoue en cours de route

Ce n'est pas une perte : le JSON est écrit **avant** toute tentative réseau. Le
scanner le rappelle et propose les deux issues :

```text
[SysAudit] Audit terminé localement
[erreur] Échec de l’envoi vers l’API (HTTP 407 — le proxy exige une authentification)
  ! Rapport conservé dans : /home/exploitation/sysaudit-serveur01.json

[SysAudit] Pour réessayer une fois l’API disponible :
[SysAudit]   ./sysaudit.sh --retry-upload '/home/exploitation/sysaudit-serveur01.json' --api-url 'https://sysaudit.me'

[SysAudit] Si ce réseau n’ouvrira pas, déposez le fichier depuis un poste connecté :
[SysAudit]   page « Déposer un rapport » (/deposer) du site SysAudit
[SysAudit] Pour savoir ce qui bloque : ./sysaudit.sh --network-test
```

`--retry-upload` renvoie un rapport déjà produit sans relancer la collecte.
L'API déduplique : un renvoi de trop est sans effet.

### Le code de sortie dit lequel des deux s'est passé

Trois valeurs, identiques sur les scanners Linux et Windows :

| Code | Ce qu'il signifie                                                                 |
| ---- | --------------------------------------------------------------------------------- |
| `0`  | l'audit a été produit, et transmis s'il devait l'être                             |
| `1`  | l'audit n'a **pas** pu être produit — usage incorrect, ou collecte impossible     |
| `2`  | l'audit a été produit, **la transmission a échoué**. Le rapport est sur le disque |

La distinction entre `1` et `2` est ce qui permet à une supervision de parc de
ne pas confondre « machine non auditable » et « réseau fermé » : sur un parc
derrière proxy, la seconde est la normale et la première l'incident.

Il n'existe **pas** de code par cause réseau. Un code par cause se figerait en
interface le jour où quelqu'un le mettrait dans un script, et devrait grandir à
chaque cause nouvellement distinguée. La cause est nommée en clair sur la sortie
d'erreur et par `--network-test` ; le code répond à la seule question qu'un
ordonnanceur pose : faut-il réveiller quelqu'un ?

---

## Vérifier soi-même les trois parcours

Le dépôt embarque un harnais qui rejoue les trois scénarios de bout en bout —
vraie API, vrai scanner, vrai proxy répondant `407` :

```bash
TEST_DATABASE_URL=postgresql://… npm run validate:relay
```

Ce qu'il éprouve réellement : la séparation entre collecte et transport, la
conservation du rapport, les codes de sortie, le dépôt manuel, la déduplication
et les métadonnées de transport.

Ce qu'il **n'éprouve pas**, et qui demande une vraie machine derrière un vrai
équipement : TLS, l'inspection HTTPS, un proxy NTLM ou Kerberos, un filtrage
DNS, un contrôle applicatif. Le script le rappelle en fin d'exécution.
