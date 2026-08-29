# ADR 0007 — Photo du matériel : téléversée, jamais cherchée

- **Statut** : **révisé** le 2026-08-20 — voir « Révision » en fin de document
- **Date** : 2026-07-29
- **Contexte** : étape 10 de la roadmap V2

## Contexte

La roadmap demandait d'illustrer les rapports et les fiches machine : image
produit officielle pour un portable ou un serveur identifié, photo de la carte
mère pour un poste assemblé. Elle posait elle-même la limite : « ne pas prendre
aveuglément la première image Google, qui peut être fausse, protégée ou non
durable », et suggérait une API de recherche d'images avec attribution, cache S3
et repli neutre.

## Décision

**Aucune recherche d'image automatique.** Une photo n'apparaît que si
l'utilisateur la téléverse. À défaut, un repli neutre — la silhouette du type de
châssis déjà connu du rapport — et rien d'autre.

## Pourquoi

**Une image fausse est pire qu'une absence d'image.** Le modèle exact rapporté
par le SMBIOS est souvent approximatif — « To Be Filled By O.E.M. », un nom de
carte partagé par cinq variantes, un châssis OEM rebadgé. Une recherche
d'images renverrait quelque chose dans tous les cas, et ce quelque chose aurait
l'apparence d'un fait vérifié. C'est exactement le défaut que la base de
compatibilité (`platforms.ts`) et le registre des sources constructeurs
(`vendor-sources.ts`) existent pour empêcher : le reste du produit refuse
d'affirmer sans preuve, et une illustration n'est pas moins une affirmation.

**Le droit d'usage n'est pas vérifiable automatiquement.** Une image trouvée par
API arrive avec une licence déclarée, pas garantie. Republier la photo produit
d'un constructeur dans un rapport archivé et partageable engage le projet, et
aucune vérification programmatique ne remplace la lecture des conditions.

**Un rapport doit rester lisible dans dix ans.** Une image chargée depuis un
domaine tiers disparaît ; une image copiée dans notre stockage pose la question
précédente. Le rapport HTML autonome est distribué comme un fichier unique : y
embarquer des images tierces le ferait grossir sans rien ajouter de mesuré.

**Aucune connexion sortante n'est faite pendant un audit.** Ajouter une
recherche d'images côté backend n'y contreviendrait pas directement, mais
créerait une dépendance réseau pour un élément purement décoratif — au moment
précis où l'ADR 0006 vient d'écarter des dépendances qui, elles, apportaient des
mesures.

## Conséquences

- Le champ prévu pour l'illustration accepte une image **téléversée par
  l'utilisateur**, et elle seule. Elle lui appartient, et le droit d'usage est le
  sien.
- À défaut, un repli neutre dérivé du `chassisType` déjà collecté : ordinateur
  portable, tour, rack, machine virtuelle. Ce n'est pas une photo, c'est une
  catégorie — et le rapport ne prétend pas autre chose.
- Cette décision ne coûte aucune donnée de diagnostic : aucune illustration n'a
  jamais servi à établir un constat.
- Si un constructeur publiait un jour un flux d'images explicitement
  redistribuables, indexé par référence exacte, cet ADR devra être révisé
  explicitement. Le déclencheur serait une **licence** claire, pas une facilité
  technique.

## Alternatives écartées

| Voie                               | Pourquoi non                                                                                             |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Recherche d'images automatique     | Rend toujours un résultat, y compris faux, avec l'apparence d'un fait vérifié.                           |
| Scraping des pages constructeur    | Fragile, non autorisé par la plupart des conditions d'utilisation, et lié à une structure de page.       |
| Banque d'images générique par type | Une photo de « tour noire » ne décrit pas cette machine-ci ; le repli par catégorie le dit sans feindre. |
| Image générée                      | Une illustration inventée présentée à côté de données mesurées est la pire des deux options.             |

---

## Révision du 2026-08-20 — la recherche est autorisée, sous conditions

**Statut** : accepté. Cette révision **remplace** la décision ci-dessus pour la
carte mère, la carte graphique et la mémoire. Elle la laisse intacte pour la
référence visuelle de **l'appareil** — un ordinateur, un serveur, un NAS —, qui
reste téléversée ou absente.

### Ce qui change

Une image de composant peut désormais être **cherchée automatiquement**, à
condition d'être validée, téléchargée, ré-encodée, stockée dans le S3 de
SysAudit et mémorisée en PostgreSQL. Le détail est dans
docs/technique/CATALOGUE-VISUEL-MATERIEL.md.

### Pourquoi la décision d'origine est révisée

L'ADR de juillet posait quatre objections. Trois tiennent toujours, et la
révision les traite ; la quatrième s'est révélée mal posée.

**« Une recherche rend toujours un résultat, y compris faux. »** C'était vrai
d'une recherche dont on prend le premier résultat. Ce n'est plus le cadre : un
candidat est **refusé avant d'être noté** si l'intitulé nomme un autre
assembleur, s'il ne porte pas la référence exacte, ou s'il diffère par un
marqueur de variante — `Ti`, `WIFI`, `Laptop`, `DDR4`. Le module de score
refuse plus qu'il n'accepte, et ses tests de faux positifs sont écrits avant
ses tests de succès. Surtout, le résultat retenu porte son **niveau de
confiance** : une carte graphique dont le relevé ne nomme pas l'assembleur ne
peut jamais valoir « photo exacte », et la carte du rapport affiche alors la
réserve correspondante. L'objection visait une affirmation non qualifiée ; ce
qui est livré n'en est pas une.

**« Le droit d'usage n'est pas vérifiable automatiquement. »** Objection
maintenue, et c'est la limite réelle de cette révision. Ce qui est fait :
l'image est stockée avec sa **provenance** — domaine, page d'origine, adresse
d'origine —, la console d'administration l'affiche, et un geste retire une
image en un clic. Ce qui n'est **pas** fait : aucune licence n'est vérifiée. Le
projet s'appuie sur le fait qu'une photographie de produit affichée à côté du
matériel qu'elle représente, sourcée, retirable sur demande, relève d'un usage
que les constructeurs tolèrent en pratique — ce qui est un constat d'usage, pas
un droit acquis. **Un ayant droit qui demande le retrait doit l'obtenir
immédiatement**, et l'interdiction de recherche par référence existe pour cela.

**« Un rapport doit rester lisible dans dix ans. »** Traitée : l'image n'est
jamais chargée depuis un domaine tiers. Elle est copiée dans le stockage de
SysAudit et servie par une adresse signée. Le rapport HTML autonome, lui,
n'embarque **aucune** image de composant — il reste le fichier unique qu'il
était.

**« Aucune connexion sortante pendant un audit. »** Toujours vraie, et la
révision ne l'entame pas : l'ingestion n'appelle rien. Elle enregistre une
identité, ce qui coûte une écriture, et une boucle de fond résout plus tard,
hors de toute requête. Un audit ne dépend à aucun moment d'un moteur de
recherche.

### Ce qui a fait pencher la balance

Le mécanisme d'affichage à quatre crans — `exact`, `reference`, `generic`,
`none` — n'existait pas en juillet. Il a été livré en `0.119.0` pour le
catalogue tenu à la main, et c'est lui qui change la nature du problème : une
image peut être montrée **en disant ce qu'elle vaut**. L'ADR d'origine
raisonnait dans un monde où afficher une image, c'était affirmer qu'elle
montrait la machine. Ce monde-là n'existe plus dans ce produit.

### Ce qui reste interdit

- afficher une image sans son niveau de confiance ;
- pointer vers l'hébergeur d'un tiers depuis un rapport ;
- chercher une image pour l'**appareil** — la décision de juillet tient ;
- chercher pour un cœur graphique intégré, qui ne se photographie pas ;
- présenter une image de famille comme la photographie de l'exemplaire audité ;
- laisser une résolution automatique écraser une validation humaine.

### Ce qui doit rester vrai pour que cette révision tienne

Si l'un de ces points cesse d'être vrai, la révision doit être rediscutée :

- le taux de faux positifs constatés en administration reste marginal ;
- aucun ayant droit n'a demandé un retrait que le produit n'a pas su honorer ;
- le coût des recherches reste borné par un budget explicite ;
- la fonctionnalité reste **désactivée par défaut**.
