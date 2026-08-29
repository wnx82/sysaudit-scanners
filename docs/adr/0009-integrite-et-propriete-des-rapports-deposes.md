# ADR 0009 — Intégrité et propriété d'un rapport déposé à la main

- **Statut** : accepté
- **Date** : 2026-08-12
- **Contexte** : chantier « SysAudit Relay »
  (`docs/roadmaps/2026-08-12-Roadmap SysAudit Relay/`), étapes RELAY-11 et
  RELAY-12
- **Complète** : [ADR 0003](0003-scanner-architecture.md), qui pose que le
  scanner ne dépend d'aucun paquet TypeScript à l'exécution

## Contexte

Le parcours hors ligne fait voyager un fichier JSON hors de tout canal
contrôlé : une clé USB, un partage interne, une pièce jointe. Il est ensuite
déposé sur `/deposer`, qui le remet à `POST /api/v1/scans/upload`.

Deux questions se posent, et la roadmap les posait séparément :

- **RELAY-12** — faut-il un mécanisme permettant de détecter qu'un rapport a été
  modifié entre sa production et son dépôt ?
- **RELAY-11** — que se passe-t-il quand la personne qui dépose n'est pas celle
  qui a audité ? Notamment pour un **technicien** intervenant sur le parc d'un
  client.

Elles ont la même racine : **de qui ce fichier est-il la parole ?**

## Ce qui existe déjà, et qu'il faut nommer avant de décider

`apps/api/src/scanner-signature.ts` signe les sommes de contrôle **du scanner**
avec une clé RSA d'au moins 2048 bits, et le script d'amorçage les vérifie avant
d'exécuter quoi que ce soit. La brique cryptographique est donc en place — mais
elle porte sur l'outil, pas sur ce que l'outil produit.

Ce module contient déjà l'avertissement décisif :

> un site compromis reçoit aussi la clé de l'attaquant, et la signature vérifie
> alors parfaitement — celle du faussaire.

Côté propriété, il n'existe **aucun identifiant de compte dans le rapport**. Le
rattachement passe par un code de liaison (`SA-ABCD-EFGH`) transmis en en-tête
`X-Machine-Claim`, valable une fois, vingt-quatre heures, pour une machine.

## Décision

### 1. Aucun rapport n'est signé, et aucun ne le sera par le scanner

Les quatre mécanismes envisagés par RELAY-12 sont écartés, chacun pour une
raison propre :

| Mécanisme                        | Pourquoi il ne tient pas ici                                                                                                    |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| HMAC calculé par le scanner      | Suppose un secret **sur la machine auditée**, donc extractible par son utilisateur. Il ne prouve rien contre l'adversaire visé. |
| Signature asymétrique locale     | Même défaut : la clé privée devrait vivre sur la machine, ou être distribuée avec le scanner — donc connue de tous.             |
| Empreinte publiée par le serveur | Suppose que le serveur ait vu le rapport avant son dépôt. C'est exactement ce que le parcours hors ligne rend impossible.       |
| Identifiant unique + validation  | `ingestKey` le fait déjà, mais il déduplique ; il n'authentifie pas.                                                            |

**Le fond du problème n'est pas cryptographique.** Dans le parcours hors ligne,
la personne qui produit le rapport, celle qui le transporte et celle qui le
dépose sont la même — ou se font confiance. L'adversaire dont on se protégerait
en signant est **l'utilisateur lui-même**, qui pourrait maquiller l'état de sa
machine avant de le déposer. Or aucun secret posé sur sa machine ne résiste à
son propriétaire. Une signature donnerait donc une garantie **apparente**,
c'est-à-dire pire que pas de garantie : elle ferait traiter comme prouvé ce qui
ne l'est pas.

### 2. Ce que la plateforme garantit réellement, et qui doit être écrit ainsi

Un rapport déposé à la main est **une déclaration**, pas une mesure certifiée.
Ce qui est garanti :

- **son intégrité en transit** — TLS jusqu'à l'API, plafond de taille, corps
  refusé s'il est vide ;
- **sa conformité** — validation Zod contre le schéma versionné, avec refus
  explicite et motivé ;
- **son innocuité** — détection de secrets, refus en `422` si le document en
  contient un ;
- **son unicité** — `ingestKey` empêche qu'un même audit devienne deux ;
- **sa traçabilité** — `transportMode` retient qu'il est arrivé à la main, et
  `report.collectionMode` qu'il a été collecté hors ligne.

Ce qui **n'est pas** garanti, et que la documentation doit dire sans détour : que
le contenu décrit fidèlement la machine. C'était déjà vrai d'un envoi direct —
un scanner modifié envoie ce qu'on lui fait envoyer — et le dépôt manuel n'y
change rien. **Il n'y a donc aucune raison de traiter un audit déposé comme
moins fiable**, et l'interface ne le fait pas.

### 3. Un technicien dépose comme n'importe qui, et rattache comme n'importe qui

Le rôle `TECHNICIAN` existe (`apps/api/src/roles.ts`) et donne la capacité
`write` : créer et modifier clients, machines et interventions. Il **ne reçoit
aucun droit particulier au dépôt**, et c'est délibéré.

Le dépôt n'a pas besoin d'être authentifié — `POST /api/v1/scans/upload` accepte
déjà un rapport sans jeton, et le faisait avant ce chantier. Ajouter une voie
réservée aux techniciens ne fermerait rien : elle créerait une seconde porte à
maintenir, à tester et à garder cohérente avec la première.

Le parcours d'un technicien est donc :

1. il audite la machine du client, hors ligne ;
2. il dépose le fichier depuis un poste connecté ;
3. **pour rattacher la machine au parc du client**, il saisit un code de liaison
   obtenu depuis l'organisation concernée.

Le code de liaison porte donc toute la décision de propriété, et c'est le bon
endroit : il est délivré par quelqu'un qui a déjà les droits sur
l'organisation, il ne vaut qu'une fois, et il n'entre jamais dans le fichier —
un rapport transmis à un tiers ne lui donne aucun accès au parc.

### 4. La comparaison « UID du fichier contre UID de la session » est abandonnée

RELAY-11 décrivait un contrôle refusant l'import quand l'identifiant de compte
du JSON ne correspond pas à celui de la session. **Ce contrôle est sans objet** :
aucun identifiant de compte ne transite par le fichier.

L'attaque qu'il visait — « modifier `accountUid` → importer → rattacher l'audit
à un autre utilisateur » — n'est pas possible aujourd'hui, et l'ajout d'un tel
champ la rendrait possible avant de la corriger. C'est le seul cas de ce
chantier où **implémenter la protection demandée créerait la faille qu'elle
prétend fermer.**

## Conséquences

- Aucun champ de signature n'est ajouté au schéma de rapport.
- Aucun `accountUid` ni `auditId` n'est ajouté au rapport.
- La documentation du parcours hors ligne dit ce qui est garanti **et ce qui ne
  l'est pas** : voir `docs/offline-audit/README.md`.
- Si le besoin d'un audit _opposable_ apparaît un jour — attestation
  contractuelle, conformité —, il ne se résoudra pas par une signature côté
  scanner mais par une **collecte que l'audité ne contrôle pas** : agent géré,
  clé matérielle, ou attestation à distance. Cela relèvera d'un autre chantier
  et d'un autre ADR.

## Ce qui ferait rouvrir cette décision

- Un déploiement où la machine auditée porte déjà un secret que son utilisateur
  ne peut pas extraire — TPM, module matériel — rendrait un HMAC significatif.
- Une exigence réglementaire nommée, avec l'usage qui la motive. Une signature
  posée « au cas où » n'ajoute que de la confiance mal placée.
