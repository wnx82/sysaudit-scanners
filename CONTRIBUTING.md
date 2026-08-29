# Contribuer

Merci de l'intérêt. Deux choses à savoir avant d'écrire une ligne, parce
qu'elles décident si votre travail pourra être intégré.

## Ce dépôt ne couvre pas tout SysAudit

Seuls les **scanners**, le **format de rapport** et leur documentation y sont
développés. Le moteur d'analyse, le scoring, l'API, l'interface Web et les
applications sont propriétaires et vivent ailleurs.

Une proposition qui les concerne ne peut pas être traitée ici — non par manque
d'intérêt, mais parce que le code n'y est pas. Passez par
[sysaudit.me](https://sysaudit.me).

## Vos contributions sont distribuées sous LICENSE

SysAudit est **source-available, pas open source**. En proposant une
modification, vous acceptez qu'elle soit distribuée aux conditions de
[LICENSE](LICENSE). Si cela ne vous convient pas, ouvrez plutôt une issue
décrivant le problème : un bon rapport vaut souvent mieux qu'un correctif.

---

## Avant de publier quoi que ce soit

Ce projet lit des machines réelles. Ce qui circule dans une issue, un
commentaire ou un diff sort de votre réseau et n'y rentre plus.

**Ne publiez jamais :** mot de passe, jeton, clé d'API, clé privée, adresse IP
privée, hostname interne, adresse MAC, numéro de série, UUID de machine,
chemin personnel, adresse e-mail, capture montrant l'un de ces éléments, ni
**rapport SysAudit non anonymisé**.

Un rapport contient par construction ce qui identifie une machine. Rejouez le
scan avec `--anonymize` avant de joindre quoi que ce soit.

Les fixtures ajoutées aux tests doivent être **synthétiques** — construites,
pas dérivées d'une machine réelle par masquage partiel. Un masquage incomplet
laisse passer ce qu'il prétend cacher.

## Mise en route

```bash
npm ci
npm run verify        # lint + typecheck + tests + build
npm run test:scanner  # suite du scanner Linux, hors Vitest
```

Le scanner Windows a sa propre suite : `npm run test:scanner:windows`. Elle
demande PowerShell, et **s'arrête sans échouer** s'il est absent — un `verify`
vert ne prouve donc pas que le scanner Windows a été vérifié.

## Branches et commits

**Jamais de développement direct sur `main`.** Créez une branche préfixée :
`feat/`, `fix/`, `docs/`, `refactor/`, `ci/`, `chore/`.

Les commits suivent les [Conventional Commits](https://www.conventionalcommits.org/),
**rédigés en français** :

```text
feat(scanner-linux): relever la température des NVMe sans sudo
fix(report-schema): refuser un compteur SMART négatif
```

La documentation, les commentaires de code et les messages de commit de ce
dépôt sont en français.

## Règles de code non négociables

Elles ne sont pas stylistiques : chacune vient d'un défaut réel.

- **Ne jamais conclure à partir d'une donnée absente.** « Section absente » et
  marqueur `unknown` sont le même cas, et ce cas n'autorise aucune conclusion.
- **Ne jamais inventer de valeur.** Une donnée non collectée porte un marqueur
  et sa raison. Un compteur SMART non lu n'est pas un compteur nul.
- **Échapper toute valeur issue d'un rapport** au rendu. Un nom de conteneur ou
  un modèle de disque est une donnée non fiable : elle vient de la machine
  auditée, pas de vous.
- `any` et les `catch` silencieux sont refusés par ESLint.

## Règles propres aux scanners

- **Aucune dépendance à Node.js à l'exécution.** Le scanner doit tourner sur une
  machine où il n'est pas installé.
- **Lecture seule** aux niveaux Rapide et Normale : aucune écriture hors du
  répertoire de sortie, aucune installation, aucune modification de service.
- **Aucun secret collecté.** Ni mot de passe, ni hash, ni cookie, ni jeton, ni
  clé privée, ni clé Wi-Fi. Le SSID peut l'être ; la PSK, jamais.
- Toute commande externe est documentée dans `docs/scanners/`, avec ce que son
  absence coûte.
- `SCHEMA_VERSION` existe dans `packages/report-schema` **et** dans chaque
  scanner. Un test de contrat échoue si l'un d'eux diverge.

## Faire évoluer le format de rapport

Le test d'empreinte du JSON Schema échoue **volontairement** dès que la
définition Zod change : c'est un garde-fou, pas une régression. La procédure
est dans [`docs/format-rapport/VERSIONING.md`](docs/format-rapport/VERSIONING.md).

Un rapport déjà produit doit rester lisible. C'est la seule promesse que ce
dépôt fait à des fichiers qui existent déjà sur les disques d'autres gens.

## Signaler une vulnérabilité

**Pas par une issue publique.** Voir [SECURITY.md](SECURITY.md).
