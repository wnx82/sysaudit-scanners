# ADR 0010 — Le moteur de recherche d'images est auto-hébergé

- **Statut** : accepté
- **Date** : 2026-08-20
- **Contexte** : chantier « Hardware Visual Resolver », suite de la révision de
  l'[ADR 0007](0007-photo-materiel.md)

## Contexte

La révision du 2026-08-20 de l'ADR 0007 a autorisé la recherche automatique
d'images pour la carte mère, la carte graphique et la mémoire. Elle a été livrée
en `0.125.0` avec **un** fournisseur : Serper, une passerelle commerciale vers
les résultats de Google, facturée à la requête.

Trois faits ont suivi ce déploiement, dans l'ordre :

1. le compte gratuit refuse — `HTTP 400`, « Query pattern not allowed for free
   accounts. » — toute requête à guillemets demandant plus de dix résultats. Les
   guillemets sont précisément ce qui donne sa précision à la recherche d'une
   référence de pièce ;
2. la quatrième condition posée par l'ADR 0007 révisé — « le coût des recherches
   reste borné par un budget explicite » — se paie en `HARDWARE_SEARCH_DAILY_BUDGET`,
   c'est-à-dire en références non résolues dès que le parc grandit ;
3. le produit est auto-hébergeable. Une installation qui doit ouvrir un compte
   chez un tiers et lui donner une carte bancaire pour illustrer ses rapports
   n'est pas auto-hébergeable au sens où le reste du projet l'entend.

## Décision

**Le fournisseur de recherche d'images par défaut est une instance SearXNG
auto-hébergée, jointe à la pile de déploiement de SysAudit.**

Le résolveur ne connaît plus de fournisseur nommé : il consomme une interface
`ImageSearchProvider`. `HARDWARE_IMAGE_SEARCH_PROVIDER` choisit l'implémentation
et vaut `searxng` par défaut.

Serper **n'est pas supprimé**. Il reste sélectionnable pour une installation qui
l'utilise déjà, et son code reste testé. Il n'est simplement plus nécessaire,
plus recommandé, et plus le défaut.

## Pourquoi SearXNG

**C'est un métamoteur, pas un moteur.** Il interroge les moteurs publics et
agrège leurs résultats. SysAudit ne dépend donc d'aucun moteur en particulier :
la liste est une configuration, et la panne de l'un ne fait pas la panne de la
recherche. La sous-roadmap 03 en fait une exigence, et c'est la bonne — coder en
dur une dépendance à Bing Images reviendrait à remplacer un fournisseur unique
par un autre.

**Il rend du JSON.** `search.formats` doit l'inclure explicitement ; c'est une
ligne de configuration, et elle est écrite dans `infra/searxng/settings.yml`.

**Il sait se protéger.** SearXNG suspend de lui-même un moteur qui répond `403`,
`429` ou par un CAPTCHA. Cette protection n'est pas désactivée : elle fait
exactement ce que nous ferions à la main, en mieux.

**Il ne coûte rien par requête.** Le budget journalier reste en place — il borne
la charge, plus la facture — mais sa valeur cesse d'être une contrainte
économique.

## Ce que cela ne change pas

L'ADR 0007 révisé gouverne toujours **ce qui peut s'afficher**. Changer de
fournisseur ne change ni le score, ni les crans de confiance, ni les gardes du
téléchargement, ni la règle « une image sans niveau de confiance ne s'affiche
pas ». Un métamoteur gratuit rend des résultats aussi faux qu'un moteur payant ;
c'est le score qui protège, et il ne bouge pas.

En particulier :

- la fonctionnalité reste **éteinte par défaut** ;
- l'ingestion d'un audit n'appelle toujours rien ;
- une image trouvée est toujours copiée dans le stockage de SysAudit ;
- la provenance est toujours conservée, et l'ADR 0007 le renforce ici : le
  **moteur** qui a rendu le résultat et la **requête** posée entrent en base,
  ce qu'ils ne faisaient pas.

## Conséquences

- **Une instance SearXNG doit tourner.** C'est un service de plus dans
  `docker-compose.yml`, sur le réseau interne, **sans port publié**. Une
  instance SearXNG ouverte au public est un proxy ouvert, et l'exposer serait
  offrir à des tiers une machine à contourner leurs propres blocages.
- **Sans instance, pas de recherche.** Le comportement est celui, déjà éprouvé,
  d'une clé absente : les identités sont enregistrées, aucune recherche ne part,
  les rapports affichent leur pictogramme. Ce n'est pas une panne.
- **La qualité des résultats dépend des moteurs configurés**, donc d'une liste
  qui vieillira. Elle est une variable d'environnement, pas une constante du
  code, et la documentation dit comment la vérifier sur l'instance réellement
  déployée.
- **Les moteurs demandant une clé payante restent désactivés.** C'est la
  contrainte qui a motivé cette décision ; l'annuler par configuration
  reviendrait à revenir au point de départ sans le dire.
- **Un fournisseur de plus est un chemin de code de plus.** Le résolveur ne
  connaît qu'une interface, et c'est ce qui rend le coût supportable : les deux
  implémentations sont testées contre le même contrat.

## Alternatives écartées

| Voie                                         | Pourquoi non                                                                                                            |
| -------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| Garder Serper comme unique fournisseur       | Facturé à la requête, refuse les requêtes précises en compte gratuit, et rend le produit non auto-hébergeable.          |
| Un autre agrégateur payant (SerpApi, Brave)  | Même objection, transportée ailleurs.                                                                                   |
| Interroger Bing Images directement           | Remplace une dépendance unique par une autre, sans le filet de suspension automatique qu'un métamoteur apporte.         |
| Récupérer les pages constructeur             | Fragile, lié à une structure de page, et non autorisé par la plupart des conditions d'utilisation. Déjà écarté en 0007. |
| Un catalogue d'images embarqué dans le dépôt | Ne couvre que ce que quelqu'un a saisi, et le dépôt grossit d'images dont le droit d'usage est le vrai problème.        |
| Aucune recherche du tout                     | C'est la décision de juillet, et elle a été revue en connaissance de cause. Ce document ne la rouvre pas.               |

## Ce qui doit rester vrai

Aux quatre conditions posées par l'ADR 0007 révisé, celle-ci s'ajoute :

- **l'instance SearXNG n'est jamais joignable depuis l'extérieur du réseau de
  déploiement.** Si cela cesse d'être vrai, ce n'est plus la même décision.
