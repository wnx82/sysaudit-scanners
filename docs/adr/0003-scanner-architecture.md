# ADR 0003 — Architecture des scanners : collecte native, analyse déportée

- **Statut :** accepté
- **Date :** 2026-07-25

## Contexte

Le scanner doit fonctionner sur des machines très hétérogènes : un Debian
minimal sans Node.js, un Proxmox de production, un Windows 7 sans PowerShell
récent. L'expérience visée est « une commande, aucune installation permanente ».

Le scanner s'exécute avec des privilèges élevés sur une machine de confiance :
c'est le composant le plus sensible du produit.

## Décision

**1. Un scanner par famille de plateforme, écrit dans sa technologie native.**

| Scanner         | Technologie                   | Raison                               |
| --------------- | ----------------------------- | ------------------------------------ |
| Linux / Proxmox | Bash + outils système         | Présent partout, aucune installation |
| Windows moderne | PowerShell 5.1+ / CIM         | Présent depuis Windows 10            |
| Windows Legacy  | WMI, WMIC, registre, VBScript | Seules options sur 7/8, Vista/XP     |

Aucun runtime n'est installé sur la machine auditée.

**2. Le scanner collecte, il n'analyse pas.**

Aucun score, aucune recommandation, aucune comparaison de version de firmware
n'est calculé sur la machine auditée. Le scanner produit un JSON de faits
mesurés. Trois bénéfices : les règles évoluent sans redéployer de scanner, les
analyses sont rejouables sur des rapports archivés, et les moteurs de règles
sont testables sans machine cible.

**3. Détection des capacités avant collecte.**

Le scanner détermine d'abord OS, distribution, architecture, privilèges,
hyperviseur et outils disponibles, puis n'exécute que les collectes réellement
possibles. Cette section figure dans le rapport : elle distingue « composant
absent » de « outil de mesure absent ».

**4. Lecture seule et absence de secrets, par construction.**

Aucune écriture hors du répertoire de sortie, aucune installation de paquet,
aucune modification de service. Aucune commande construite à partir de données
non fiables. Timeout sur chaque collecte. Aucun secret collecté — garanti par
les tests.

**5. Dégradation explicite.**

Une donnée inaccessible est marquée `UNKNOWN`, `NOT_AVAILABLE`, `UNSUPPORTED`
ou `PERMISSION_DENIED`, avec la raison. Jamais de valeur inventée, jamais de
valeur par défaut plausible.

## Alternatives considérées

**Un binaire unique multiplateforme (Go, Rust).** Séduisant : un seul langage,
sortie fortement typée, distribution par binaire signé. Écarté pour le Linux et
le Legacy — il faudrait télécharger un binaire par architecture (amd64, arm64,
armv7 pour Raspberry Pi) et un binaire moderne ne tourne pas sur Windows XP.
Un binaire `SysAudit.exe` reste néanmoins l'objectif à terme côté Windows
moderne, en emballant la logique du scanner PowerShell.

**Node.js sur la machine auditée.** Écarté : impose une installation, ce que le
principe absolu du produit interdit.

**Analyse embarquée dans le scanner.** Écarté : figerait les règles dans une
version de scanner déployée sur des machines qui ne seront pas remises à jour,
et rendrait impossible le recalcul d'un rapport archivé.

**Agent permanent.** Écarté pour le produit de base : contredit « aucune
installation permanente ». Envisageable plus tard, en option, pour des audits
planifiés.

## Conséquences

Positives :

- Fonctionne sur une machine minimale, sans dépendance à installer.
- Les règles d'analyse évoluent indépendamment du parc de scanners déployés.
- Le rapport explique lui-même pourquoi une donnée manque.

Négatives :

- Duplication de logique entre plateformes (détection des capacités, sortie
  JSON, anonymisation). Atténuation : une structure de rapport identique, des
  fixtures de test partagées et la validation de toute sortie de scanner contre
  le même JSON Schema.
- Générer du JSON valide en Bash est fastidieux et sujet aux erreurs
  d'échappement. Atténuation : une fonction d'échappement unique, testée, et un
  test de CI qui valide la sortie du scanner contre le JSON Schema.
- Le Bash rend le typage impossible. Atténuation : ShellCheck en CI, `set -euo
pipefail`, et fonctions courtes à responsabilité unique.
