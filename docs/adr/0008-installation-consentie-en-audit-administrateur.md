# ADR 0008 — Installation consentie, bornée à l'audit administrateur local

- **Statut** : accepté
- **Date** : 2026-08-07
- **Révise** : [ADR 0006](0006-dependances-externes.md), qui reste en vigueur
  partout où cet ADR ne s'applique pas
- **Contexte** : chantier « audits avancés, IA locale et fiabilisation »
  (`docs/roadmaps/2026-08-07-update-audits/`)

## Contexte

L'ADR 0006 a tranché il y a huit jours : SysAudit **nomme** ce qui manque et
n'installe rien. Il écartait explicitement l'« installation automatique
consentie », au motif qu'« un consentement obtenu au milieu d'un audit n'en est
pas un : l'utilisateur veut un diagnostic, pas une décision ».

Ce motif reste juste — pour le cas qu'il visait. Il visait l'audit tel qu'il se
présente à un visiteur : une commande copiée depuis le site, exécutée une fois,
sur une machine dont on veut l'état. Interrompre cet audit pour demander
l'autorisation d'installer `smartmontools` est bien une décision imposée à
quelqu'un venu chercher autre chose.

Mais l'ADR 0006 n'a pas distingué ce cas d'un second, qui existait déjà et qu'il
a traité comme le premier : l'administrateur qui lance lui-même un audit poussé
sur sa propre machine, en connaissance de cause, et pour qui « `NOT_EVALUATED` :
`nvme-cli` absent » n'est pas un diagnostic mais une invitation à recommencer
l'audit après un `apt install`. Pour celui-là, refuser l'installation ne protège
personne : il fera la commande à la main, puis relancera le scan — deux fois
plus long, pour exactement le même effet sur sa machine.

L'ADR 0006 prévoyait sa propre révision, « avec signature de code, empreintes
publiées, version et procédure de désinstallation », et exigeait qu'elle ne soit
« pas un ajustement discret ». C'est l'objet de ce document.

## Décision

**L'installation consentie devient possible, et uniquement dans un cas nommé.**
Les quatre conditions ci-dessous sont cumulatives. Si l'une manque, le
comportement de l'ADR 0006 s'applique intégralement : nommer, ne pas installer.

1. **Un drapeau explicite en ligne de commande** — `--install-deps`. Rien ne
   l'active par déduction : ni un niveau d'audit, ni une variable
   d'environnement, ni un défaut. Un utilisateur qui ne l'a pas tapé ne verra
   jamais la question.
2. **Un niveau d'audit `full` ou `stress`.** L'audit rapide et l'audit standard
   n'installent rien, quel que soit le drapeau — ce sont eux que le site
   propose, et leur promesse est de ne rien changer.
3. **Un accord donné pour chaque outil, après affichage de ce qu'il est**, de ce
   qu'il débloque, de son paquet, de son éditeur amont et de sa commande exacte.
   Un accord global, ou pré-coché, ne compte pas.
4. **Un terminal interactif.** Sans TTY, la question ne peut pas être posée, donc
   rien n'est installé. `--assume-yes` lève cette condition et **elle seule** :
   il reste soumis aux trois autres, et sert le cas où l'opérateur a déjà
   consenti en amont, dans son propre outillage.

Trois interdits complètent ces conditions :

- **Le script d'amorçage ne passe jamais `--install-deps`.** C'est la frontière
  qui sépare les deux cas de l'ADR 0006 : ce qui vient du site n'installe rien,
  point. Un test le vérifie plutôt qu'une relecture.
- **Aucun binaire tiers n'est téléchargé, ni embarqué, ni exécuté.** Seul le
  gestionnaire de paquets de la distribution est appelé, avec le nom de paquet
  de la table `packages/platform/src/tool-dependencies.ts` — jamais une URL,
  jamais un dépôt tiers ajouté. Sous Windows, seul WinGet, et seulement vers les
  sources qu'il déclare. Ce point de l'ADR 0006 n'est pas révisé : il est
  renforcé.
- **Seul ce que SysAudit a installé pendant cet audit peut être désinstallé.**
  Un outil déjà présent avant l'audit n'est jamais touché, jamais proposé à la
  suppression, et l'inventaire d'avant-audit est ce qui le garantit.

## Pourquoi cette forme

**Parce que le consentement problématique était celui qu'on n'avait pas
demandé.** L'objection de l'ADR 0006 porte sur le moment — au milieu d'un audit
qu'on n'a pas choisi d'orienter. `--install-deps` déplace le consentement avant
le lancement : l'utilisateur ne subit pas une question, il a demandé qu'elle lui
soit posée. Ce n'est pas le même acte.

**Parce que la promesse de lecture seule reste tenue là où elle est lue.** Elle
figure sur le site, dans la commande copiée, dans l'audit rapide public. Aucun
de ces chemins ne change. Ce qui change est un mode que seul quelqu'un ayant lu
la documentation peut atteindre.

**Parce que le contournement existait déjà, en moins traçable.** Sans ce mode,
l'administrateur installe à la main. Le rapport ne sait alors pas distinguer un
outil présent depuis toujours d'un outil installé trois minutes avant le scan —
alors que la Phase 8 du chantier a précisément besoin de cette distinction pour
ne jamais proposer de supprimer un outil préexistant.

**Parce qu'un audit qui modifie doit le dire dans le rapport, pas dans un log.**
La traçabilité (`dependenciesAlreadyPresent`, `dependenciesInstalledBySysAudit`,
`dependenciesRemovedAfterAudit`…) entre dans le schéma de rapport versionné, au
même titre que le reste. Un audit qui a touché la machine porte cette trace de
façon permanente, y compris relu six mois plus tard.

## Conséquences

- Le schéma de rapport gagne une trace de provisionnement, et `SCHEMA_VERSION`
  monte — aux **six** endroits, scanners compris.
- Le scanner cesse d'être _inconditionnellement_ en lecture seule. La
  documentation doit cesser de l'affirmer sans réserve : la formulation devient
  « en lecture seule, sauf `--install-deps` explicite en audit poussé ».
  `README.md`, `docs/scanners/DEPENDENCIES.md` et les pages web concernées sont à revoir
  dans le même mouvement, sans quoi la promesse affichée devient fausse.
- Un audit lancé avec `--install-deps` n'est plus comparable à un audit sans, du
  point de vue de la couverture : le second peut légitimement montrer moins.
  La comparaison d'audits doit lire la trace de provisionnement plutôt que
  conclure à une régression de couverture.
- La désinstallation est un chemin d'échec à part entière : elle peut échouer, et
  un échec doit apparaître dans le rapport plutôt que laisser croire que la
  machine a été rendue à son état initial.
- Si un besoin futur demandait d'installer depuis autre chose qu'un gestionnaire
  de paquets de distribution — un binaire téléchargé, un dépôt tiers —, cet ADR
  ne le couvre pas et devra être révisé à son tour.

## Alternatives écartées

| Voie                                          | Pourquoi non                                                                                                                                                      |
| --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Maintenir l'ADR 0006 intact                   | Laisse l'administrateur installer à la main, donc sans trace exploitable — et prive le rapport de la distinction « présent avant » / « installé pour cet audit ». |
| Installation consentie à tous les niveaux     | Ramène exactement l'objection de l'ADR 0006 sur le chemin public, celui où elle est juste.                                                                        |
| Activation par variable d'environnement seule | Une variable se pose une fois et s'oublie ; elle ne prouve pas un consentement au moment du lancement, et un environnement hérité l'activerait à l'insu de tous.  |
| Consentement global, un seul « oui »          | Ne dit pas à quoi on consent. La liste des outils varie d'une machine à l'autre : un accord unique porterait sur un contenu inconnu de qui le donne.              |

## Amendement du 2026-08-17 — l'offre faite à qui n'a rien demandé

Décidé par le propriétaire du projet, après avoir vu la fin d'un audit standard
sur une Ubuntu : sept lignes `sudo apt install …` à recopier une par une.

### Ce que l'expérience a montré

Les conditions 1 et 2 rendaient la porte **invisible à qui ne connaît pas le
produit**. Un utilisateur qui suit la commande du site n'a ni tapé
`--install-deps` — le script d'amorçage ne le passe pas — ni choisi un niveau
`full`. Il ne voyait donc jamais la question, seulement une liste à recopier.

Un défaut plus grave se cachait derrière : la condition 4 était vérifiée par
`[ -t 0 ]`, et l'entrée standard d'un `curl … | bash` **porte le script
lui-même**. La question était donc impossible à poser par le chemin
d'installation officiel, quels que soient les drapeaux — et si la garde avait
cédé, `read` aurait consommé les octets du scanner en guise de réponse.

### Ce qui change

Une cinquième porte, `provision_offer` : lorsque des outils manquent, qu'un
gestionnaire de paquets est connu, que l'audit dispose de root **et qu'un
terminal de contrôle répond**, la revue est proposée avant la collecte. Un
« oui » tapé à la main lève la borne de niveau — c'est précisément la volonté
que cette borne cherchait à protéger.

La lecture se fait sur `/dev/tty`, indépendant de l'entrée standard.

### Ce qui ne change pas

- **La condition 3 est intacte** : cette question n'ouvre que la revue, l'accord
  reste donné outil par outil, après affichage du paquet, de sa provenance et de
  sa commande exacte.
- **Le défaut est non.** Une frappe vide, une fin de fichier, un terminal qui
  disparaît : tout ce qui n'est pas un oui franc refuse.
- **Sans terminal, aucune question n'est posée** et le comportement de l'ADR
  0006 s'applique intégralement. Un audit sous `cron`, en conteneur ou en
  intégration continue se déroule exactement comme avant, sans jamais attendre.
- **Sans root ni gestionnaire de paquets connu, l'offre ne se présente pas** :
  proposer ce qu'on ne peut pas tenir est pire que se taire.

Ce qui change est donc **le moment où la question est posée**, pas ce qu'elle
engage.
