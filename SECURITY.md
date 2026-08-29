# Politique de sécurité

## Portée

Ce dépôt contient les **composants publiés** de SysAudit : les scanners, le
format de rapport et leur documentation. Cette politique les couvre.

Une faille du service en ligne, des comptes ou de l'analyse hébergée se signale
par le même canal, mais le correctif n'apparaîtra pas ici : ces composants ne
sont pas publiés.

## Versions supportées

SysAudit est en développement actif (pré-1.0). Seule la dernière version
publiée reçoit des correctifs de sécurité. Cette table sera étendue à partir de
la `1.0.0`.

| Version                  | Supportée |
| ------------------------ | --------- |
| Dernière version publiée | ✅        |
| Versions antérieures     | ❌        |

## Signaler une vulnérabilité

**N'ouvrez jamais d'issue publique pour une vulnérabilité.**

Utilisez l'onglet _Security → Report a vulnerability_ de ce dépôt (avis de
sécurité privé GitHub). À défaut, passez par le formulaire de contact de
<https://sysaudit.me>.

Un rapport utile contient : la version concernée, une description, l'impact
estimé, les étapes de reproduction et, si vous en avez une, une proposition de
correction.

Nous visons un premier retour sous **7 jours ouvrés**. Ce délai est un
engagement de réponse, pas de correctif : la durée d'un correctif dépend de ce
qui est trouvé, et nous préférons ne pas promettre un chiffre que nous ne
saurions pas tenir.

**Ne joignez à un rapport aucun secret, aucune adresse IP privée, aucun numéro
de série, aucune capture montrant un nom de machine, ni aucun rapport SysAudit
non anonymisé.** Si un élément identifiant est nécessaire pour comprendre la
faille, dites-le et nous conviendrons d'un canal.

## Modèle de menace du scanner

Le scanner s'exécute avec des privilèges élevés sur une machine de confiance et
produit un fichier destiné, éventuellement, à être partagé. Les garanties
suivantes sont donc structurelles, et vérifiables : le code est publié.

### Lecture seule

Aux niveaux **Rapide** et **Normale**, le scanner ne modifie rien : aucune
installation de paquet, aucune modification de service, aucune écriture hors de
son répertoire de sortie.

Au niveau **Complète**, il peut proposer d'installer un outil manquant —
**jamais sans accord explicite** de l'administrateur — et propose son retrait à
la fin. Au niveau **Poussée**, il charge volontairement la machine pour un banc
d'essai, sous surveillance thermique.

Les commandes utilisées sont documentées, système par système, dans
[`docs/scanners/`](docs/scanners/).

### Aucun secret collecté

Ne sont jamais collectés :

- mots de passe, empreintes de mots de passe, cookies, jetons, secrets d'API ;
- clés privées, clés SSH privées, certificats privés ;
- contenu de documents, historique de navigation, courriels ;
- clés Wi-Fi — le SSID peut l'être, la PSK jamais ;
- variables d'environnement de conteneurs : seuls les métadonnées et les
  indicateurs de configuration à risque le sont.

Cette garantie est tenue par des tests automatisés
([`packages/shared/src/secrets.ts`](packages/shared/src/secrets.ts)), et
rejouée à la réception côté service : un rapport contenant un secret détecté
est refusé.

### Exécution maîtrisée

- Aucune commande n'est construite à partir de données non fiables.
- Chaque collecte a un délai maximal et des limites de ressources.
- Moindre privilège : les collectes exigeant `root` sont identifiées, et une
  exécution non privilégiée reste possible — les champs concernés portent alors
  le marqueur `PERMISSION_DENIED` plutôt qu'une valeur inventée.

### Distribution

Chaque version de scanner publie son numéro, son empreinte SHA-256, sa date et
l'URL de sa release. Le téléchargement se fait en TLS.

La méthode **« télécharger, vérifier l'empreinte, lire, exécuter »** est
documentée avant toute forme `curl | bash`. Nous vous encourageons à l'employer :
c'est pour cela que le code est publié.

## Vie privée des rapports

- Aucun envoi sans consentement explicite (`--upload`).
- `--anonymize` masque hostname, utilisateurs, domaine, adresses IP publiques,
  adresses MAC, numéros de série, UUID et SSID. Vous voyez ce qui partira.
- Les rapports envoyés sont **privés et non indexables** par défaut.
- Le partage est explicite, temporaire et révocable ; un rapport peut être
  supprimé.

## Ce que cette politique ne décrit pas

Les mécanismes défensifs internes du service — limitation de débit, détection
d'abus, journalisation, contrôles d'accès administratifs — ne sont pas détaillés
ici, et ne le seront pas. Les décrire aiderait davantage à les contourner qu'à
les auditer.

Cela ne les soustrait pas au signalement : si vous en trouvez un défaut,
la procédure ci-dessus s'applique pleinement.
