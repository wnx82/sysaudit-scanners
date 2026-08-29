# ADR 0005 — Le scanner Android est une application, pas un script

- **Statut :** accepté
- **Date :** 2026-07-28

## Contexte

L'étape 18 demandait de préparer l'étude technique et l'architecture d'un
SysAudit Android. L'étude complète est dans [ANDROID.md](../scanners/ANDROID.md).

Elle établit un fait qui contraint tout le reste : Android n'est pas un Linux
dont on aurait retiré quelques commandes. Depuis Android 10, la plateforme
**refuse par conception** les identifiants matériels persistants — IMEI, numéro
de série, adresse MAC réelle. Depuis Android 11, elle restreint la visibilité
des applications installées. Il n'y a ni `dmidecode`, ni `smartctl`, ni accès
privilégié à `/sys`.

Un scanner y est une application soumise au modèle de permissions, pas un script
lancé par root.

## Décision

**Ne pas implémenter le scanner Android dans ce dépôt pour l'instant**, et fixer
par écrit le périmètre atteignable.

Trois décisions de conception sont prises dès maintenant, pour que
l'implémentation future n'ait pas à les rejouer :

1. **Une donnée refusée par la plateforme porte `unsupported`, jamais
   `unknown`.** `unknown` dit « la lecture a échoué » ; `unsupported` dit « la
   plateforme ne le permet pas ». Les confondre ferait croire à un défaut de
   collecte là où il y a un choix d'Android, et un utilisateur chercherait
   indéfiniment à corriger ce qui ne peut pas l'être.

2. **La détection de root est une heuristique, pas une mesure.** Elle porte une
   confiance et une source, et le rapport n'écrit jamais « appareil non rooté » —
   seulement « aucun indice de root parmi ceux testés ». Aucune méthode connue ne
   prouve l'absence de root.

3. **Aucune permission n'est demandée sans donnée en face**, et un refus produit
   `permission_required` plutôt qu'un rapport bloqué.

Le schéma n'évolue pas maintenant. Les deux ajouts identifiés — `android` dans
`capabilities.platform` et une section `mobile` — attendront un scanner capable
de les remplir.

## Alternatives considérées

**Un scanner shell via ADB ou Termux.** Écarté : il mesurerait un appareil de
développeur, pas un téléphone d'utilisateur. Les données supplémentaires
obtenues par ADB ne sont pas représentatives, et l'exiger fermerait l'usage à
tout le monde sauf à ceux qui n'en ont pas besoin.

**Ajouter dès maintenant les champs `mobile` au schéma.** Écarté : une section
qu'aucun scanner ne remplit apparaîtrait vide dans tous les rapports, et le
tableau de compatibilité annoncerait une capacité inexistante — exactement ce
que ce dépôt s'interdit.

**Marquer Android « partiellement supporté ».** Écarté pour la même raison : rien
n'est collecté aujourd'hui. La case reste ⏳.

## Conséquences

- Android reste **⏳ prévu** dans la matrice de compatibilité, et le restera tant
  qu'aucun rapport Android réel ne sera validé contre le schéma.
- L'implémentation future demande un dépôt d'application, une chaîne de
  compilation Kotlin/NDK et une distribution — hors du cadre de ce monorepo
  TypeScript et Bash. Le rapport JSON reste le seul contrat entre les deux.
- Un rapport Android sera **structurellement plus pauvre** qu'un rapport PC. Le
  rendu devra le dire, sans quoi la comparaison entre une machine et un
  téléphone paraîtrait accablante pour le second alors qu'elle mesure une
  différence de plateforme, pas de matériel.
