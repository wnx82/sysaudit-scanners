# Android — étude technique

Étude préalable à un scanner SysAudit pour Android. **Rien n'est implémenté** :
ce document dit ce qui serait réellement collectable, ce qui ne l'est pas, et à
quel prix.

Il est écrit pour éviter une erreur précise : concevoir un scanner Android sur
le modèle du scanner Linux, puis découvrir champ par champ que la plateforme
refuse ce que le schéma attend.

## La contrainte qui décide de tout

Android n'est pas un Linux dont on aurait retiré quelques commandes. Depuis
Android 10, la plateforme **refuse par conception** les identifiants matériels
persistants, et depuis Android 11 elle restreint fortement la visibilité des
autres applications.

Un scanner y est une **application**, pas un script exécuté par root. Il n'a ni
`/proc` complet, ni `dmidecode`, ni `smartctl`, ni accès à un shell privilégié.

Conséquence directe : plusieurs champs du schéma de rapport n'ont pas
d'équivalent, et le scanner devra les porter comme `unsupported` — pas comme
`unknown`. La distinction compte : `unknown` dit « la lecture a échoué »,
`unsupported` dit « la plateforme ne le permet pas ». Confondre les deux ferait
croire à un problème de collecte là où il y a un choix de plateforme.

## Ce qui est collectable

| Donnée                 | Source                                           | Permission          |
| ---------------------- | ------------------------------------------------ | ------------------- |
| Modèle, fabricant      | `Build.MODEL`, `Build.MANUFACTURER`              | aucune              |
| Version Android, API   | `Build.VERSION.RELEASE`, `SDK_INT`               | aucune              |
| Niveau de correctif    | `Build.VERSION.SECURITY_PATCH`                   | aucune              |
| Architecture           | `Build.SUPPORTED_ABIS`                           | aucune              |
| SoC                    | `Build.SOC_MANUFACTURER`, `SOC_MODEL` (API 31+)  | aucune              |
| Cœurs CPU              | `Runtime.availableProcessors()`                  | aucune              |
| RAM totale / dispo     | `ActivityManager.MemoryInfo`                     | aucune              |
| Stockage total / libre | `StatFs`, `StorageManager`                       | aucune              |
| Écran                  | `DisplayMetrics`, `Display.getMode()`            | aucune              |
| Batterie               | `BatteryManager`, `ACTION_BATTERY_CHANGED`       | aucune              |
| Type de réseau         | `ConnectivityManager.NetworkCapabilities`        | aucune              |
| Wi-Fi : état, débit    | `WifiManager.connectionInfo` (partiel)           | localisation        |
| Bluetooth : état       | `BluetoothAdapter`                               | `BLUETOOTH_CONNECT` |
| Capteurs présents      | `SensorManager.getSensorList()`                  | aucune              |
| Vulkan / OpenGL ES     | `PackageManager.hasSystemFeature`, `GL_VERSION`  | aucune              |
| Chiffrement            | `DevicePolicyManager.getStorageEncryptionStatus` | aucune              |
| Verrouillage écran     | `KeyguardManager.isDeviceSecure()`               | aucune              |
| Root apparent          | heuristiques (voir plus bas)                     | aucune              |

## Ce qui n'est pas collectable

C'est la partie qui doit être écrite noir sur blanc, parce qu'elle contredit
l'intuition venue du monde PC.

| Donnée                      | Statut                                                                                                       |
| --------------------------- | ------------------------------------------------------------------------------------------------------------ |
| IMEI, numéro de série       | **interdit** depuis Android 10, même avec permission privilégiée                                             |
| Adresse MAC Wi-Fi           | **randomisée** ; la valeur réelle est refusée                                                                |
| SSID courant                | exige la localisation **précise**, et l'utilisateur peut refuser                                             |
| Liste des applications      | restreinte depuis Android 11 (`QUERY_ALL_PACKAGES` est une permission sensible, justifiable auprès du store) |
| SMART, santé du stockage    | aucune API publique                                                                                          |
| Températures des composants | aucune API publique ; les capteurs thermiques ne sont pas exposés                                            |
| Fréquences CPU réelles      | lecture de `/sys/devices/system/cpu` souvent refusée depuis Android 8                                        |
| Modèle exact de la mémoire  | aucune API                                                                                                   |
| Cycles de charge batterie   | aucune API publique                                                                                          |

Un scanner Android produira donc un rapport **structurellement plus pauvre**
qu'un rapport Linux ou Windows. C'est une propriété de la plateforme, pas une
faiblesse du scanner — et le rapport doit le dire, sans quoi la comparaison
entre une machine et un téléphone paraîtrait accablante pour le second.

## La détection de root n'est pas une mesure

Toutes les méthodes connues sont des **heuristiques** : présence de `su` dans le
`PATH`, paquets de gestion de root installés, propriétés `ro.debuggable` ou
`ro.secure`, échec de `SafetyNet`/`Play Integrity`.

Aucune ne prouve l'absence de root ; toutes peuvent être contournées. Le rapport
devra donc porter une **confiance** et une **source**, comme toute information
déduite (§39), et ne jamais écrire « appareil non rooté » — seulement « aucun
indice de root parmi ceux testés ».

## Benchmarks

| Cible    | Approche réaliste                                                       |
| -------- | ----------------------------------------------------------------------- |
| CPU      | charge de calcul en code natif (NDK), durée mesurée                     |
| RAM      | débit de copie mémoire                                                  |
| Stockage | écriture/lecture d'un fichier temporaire dans le cache de l'application |
| GPU      | rendu Vulkan ou GLES hors écran                                         |

Trois réserves à écrire dans le rapport :

- **le thermal throttling est la norme**, pas l'exception. Une mesure de trente
  secondes et une mesure de trois minutes ne mesurent pas la même chose ;
- **la charge concurrente n'est pas contrôlable.** Un scanner n'a aucun moyen de
  suspendre les autres applications ;
- **les cœurs sont hétérogènes** (big.LITTLE). Un score agrégé masque cette
  asymétrie, qui est précisément ce qui distingue deux SoC.

Sans ces réserves, une comparaison entre deux appareils serait trompeuse — le
même écueil que celui traité pour la base comparative à l'étape 14.

## Architecture envisagée

```text
Application Android (Kotlin)
        │
        ├── Collecteurs (un par domaine, isolés)
        │     └── chaque échec devient une entrée collection.issues
        ▼
   Rapport JSON, schéma SysAudit versionné
        │
        ├── partage local (fichier, aucune sortie réseau)
        └── upload explicite vers l'API SysAudit
```

Deux principes repris des scanners existants, sans discussion :

- **aucun upload implicite.** L'envoi est une action de l'utilisateur ;
- **l'échec d'un collecteur n'interrompt pas l'audit.**

Deux principes propres à Android :

- **aucune permission demandée sans donnée en face.** Demander la localisation
  pour lire un SSID doit être un choix explicite de l'utilisateur, et le refus
  doit produire `permission_required`, pas un rapport bloqué ;
- **le scanner reste hors magasin d'applications tant qu'il n'est pas jugeable.**
  Une application d'audit qui demande `QUERY_ALL_PACKAGES` sera examinée ; il
  faut pouvoir justifier chaque permission.

## Évolution du schéma nécessaire

Aucune, pour l'essentiel : `system`, `os`, `memory`, `storage`, `network`,
`power` et `security` couvrent déjà ce qui est collectable, et les marqueurs
d'absence portent le reste.

Deux ajouts seraient nécessaires, tous deux **optionnels** donc MINOR :

- `capabilities.platform` doit accepter `android` ;
- une section `mobile` pour l'écran, les capteurs et le niveau de correctif de
  sécurité, sans équivalent dans les sections existantes.

Ils ne sont **pas** faits ici : ajouter des champs qu'aucun scanner ne remplit
créerait une section vide dans tous les rapports, et le tableau de compatibilité
annoncerait une capacité inexistante.

## Décision

Android reste **⏳ prévu** dans la matrice de compatibilité. Cette étude fixe le
périmètre atteignable et les pièges ; l'implémentation demande un dépôt
d'application, une chaîne de compilation Kotlin/NDK et une distribution, qui
sortent du cadre de ce monorepo TypeScript et Bash.

Voir [ADR 0005](../adr/0005-strategie-mobile.md).
