# ADR 0014 — Ce qui est traduit, ce qui ne le sera pas, et pourquoi

- **Statut** : accepté
- **Date** : 2026-08-22
- **Contexte** : sous-roadmap SR-03 de « Internationalisation, Analytics & User
  Insights », et ligne **A2** du relevé « reste à faire » du 2026-08-22

## Le problème que cet ADR ferme

La portée de l'internationalisation avait été décidée, appliquée, testée — et
**écrite nulle part**, sinon dans la cellule d'un tableau de roadmap. Une
roadmap n'est pas un lieu de décision durable : elle est locale, non versionnée,
et elle disparaît quand le chantier se clôt. La règle « console française »
allait donc se perdre, puis être redécouverte comme un oubli, puis être
« corrigée » par quelqu'un qui ne saurait pas qu'elle était voulue.

## Ce qui est traduit aujourd'hui

`TRANSLATED_PATHS` contient `/` et `/contact`. Deux pages, **entièrement**
traduites, avec leurs métadonnées, leur 404 et leur sélecteur de langue.

La liste est courte par construction, et `i18n-routes.test.ts` vérifie qu'un
fichier de page existe pour chaque entrée dans chaque langue : **le sélecteur ne
peut pas proposer une traduction qui n'existe pas.** C'est le garde-fou qui
compte, bien plus que la longueur de la liste.

## La décision, en trois périmètres

### 1. Les pages publiques : traduites au fur et à mesure, jamais à la chaîne

Une page rejoint `TRANSLATED_PATHS` quand sa traduction est écrite et relue,
jamais avant. Le site compte plusieurs milliers de lignes de prose française
écrites avec soin ; les traduire à la chaîne produirait un anglais approximatif
sur des pages qui expliquent précisément qu'on ne devine pas.

### 2. La console d'administration : **française, et elle le reste**

C'est la décision qui n'était écrite nulle part, et c'est celle-ci.

Trois raisons, dans l'ordre de leur poids.

**Son public est connu et il est d'un seul.** La console d'administration
s'adresse à l'exploitant de l'instance. Sur celle-ci, c'est une personne, qui
écrit en français. Traduire une interface pour un public qui n'existe pas est du
travail qui ne sert personne, et de la surface à maintenir qui, elle, sert à se
tromper.

**Son vocabulaire est le plus dangereux à traduire du produit.** « Aucun
résultat fiable » et « image inexploitable » désignent deux états distincts d'une
même recherche, et la console existe pour ne pas les confondre. Une traduction
approximative de ces libellés-là ne rendrait pas l'écran moins lisible : elle le
rendrait faux.

**Rien ne dépend de ce choix.** Les mécanismes d'internationalisation — la
résolution par le chemin, le sélecteur, les métadonnées par langue — sont
généraux. Le jour où la console devrait être traduite, elle s'y brancherait sans
rien déplacer.

### 3. La documentation et les rapports : hors périmètre, pour deux raisons différentes

**La documentation** (`docs/`, y compris ce fichier) est en français, et le
`CLAUDE.md` du dépôt en fait une règle. Elle s'adresse à qui travaille sur le
code.

**Les rapports d'audit** relèvent de l'[ADR 0012](0012-traduction-des-audits.md),
qui a sa propre analyse et sa propre décision : 97 règles × 5 champs de prose,
soit environ 970 phrases, et une architecture que le produit n'a pas. Ce n'est
pas une question de portée, c'est un chantier.

## Conséquences

- **Le sélecteur de langue n'apparaît que là où il mène quelque part.** C'est
  déjà le cas, et un test le tient.
- **Une page anglaise incomplète n'existe pas.** Il n'y a pas d'état
  intermédiaire où une moitié de page serait traduite : l'entrée est dans
  `TRANSLATED_PATHS` ou elle n'y est pas.
- **La console reste française**, et ce fichier est désormais l'endroit où on
  l'apprend. Le tableau de roadmap qui le disait n'est pas versionné.
- **La ligne A2 du relevé « reste à faire » est close** : elle demandait
  exactement cela — « à consigner dans un ADR ou à rouvrir ».

## Ce qui rouvrirait ce choix

Un second exploitant qui ne lit pas le français. Rien d'autre : ni le nombre de
visiteurs anglophones du site public, qui ne touchent pas la console, ni le
volume de prose, qui n'est un argument que dans un sens.
