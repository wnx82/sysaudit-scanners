# Scanner Android — EXPERIMENTAL / UNVALIDATED

> **Ce scanner n'a jamais été exécuté sur un appareil Android.**
>
> Il est écrit d'après la documentation d'Android et les pages de manuel de
> `getprop` et `dumpsys`. Aucune de ses sorties n'a été confrontée à un
> téléphone.

## Ce que ce statut signifie

Identique à celui des scanners [macOS](../macos/README.md) et
[BSD](../bsd/README.md) : aucune case validée dans la matrice de compatibilité,
un rapport qui se lit comme une hypothèse, et aucune distribution par
l'amorçage.

## Aucune donnée d'application n'est collectée

Ni la liste des paquets installés, ni leurs données, ni le journal `logcat`.

C'est une **décision de portée, pas une limite technique** : l'inventaire
applicatif d'un téléphone personnel est la donnée la plus intime qu'un audit
puisse produire, et ce scanner n'a pas de raison de la porter. Quatre tests
vérifient que `pm list packages`, `logcat -d`, `settings put` et `setprop`
n'apparaissent nulle part.

## « Pas le droit » n'est pas « pas de donnée »

C'est la confusion la plus coûteuse d'un audit Android. Sur un appareil non
rooté, le shell ne peut lire ni `/proc/<pid>` des autres applications, ni la
plupart des services `dumpsys`, ni `logcat`. Un champ vide n'y signifie donc
presque jamais « pas de donnée » mais « pas le droit ».

Le scanner rapporte donc **`PERMISSION_DENIED`** partout où il peut faire la
différence, et `NOT_AVAILABLE` seulement en mode root, où un silence est
vraiment une absence. Confondre les deux inviterait à chercher une panne là où
il n'y a qu'une politique.

Exemple concret : `ro.serialno` est vide pour toute application sans privilège
depuis Android 10. Le champ porte `PERMISSION_DENIED` avec ce motif exact.

## Le mode de collecte est publié

| Mode          | Reconnu à | Ce qu'il change                                             |
| ------------- | --------- | ----------------------------------------------------------- |
| `root`        | uid 0     | tout est lisible                                            |
| `adb`         | uid 2000  | droits du shell ADB, souvent plus larges qu'une application |
| `application` | autre uid | droits du processus (Termux, application SysAudit)          |

Deux rapports du même téléphone peuvent différer sans que l'appareil ait changé.
Le mode figure donc dans `report.notes` : sans lui, ils paraîtraient
contradictoires et on chercherait la panne dans l'appareil.

## Trois conversions qui peuvent mentir en silence

Chacune a son test.

| Donnée                  | Source                      | Piège                                                                                                                                                                                                                      |
| ----------------------- | --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Température de batterie | `dumpsys battery`           | Rendue en **dixièmes de degré**. Publier `352` donnerait 352 °C sur une batterie à 35,2 °C.                                                                                                                                |
| Statut de batterie      | `dumpsys battery`           | Un **entier** : 2 en charge, 3 en décharge, 4 non chargée, 5 pleine. Le publier tel quel dans un champ énuméré serait faux.                                                                                                |
| Verified Boot           | `ro.boot.verifiedbootstate` | Une **couleur**, pas un booléen. Seul `green` signifie « intact et signé par le constructeur » ; traiter `yellow` — signé par une clé tierce — comme `green` ferait passer un appareil modifié pour un appareil d'origine. |

## La fin de support n'est pas déduite de la version d'Android

Elle dépend du **constructeur**. Un Pixel et un téléphone d'entrée de gamme sous
le même Android 14 n'ont pas la même date de fin de correctifs. `os.support`
porte donc `UNKNOWN` avec une confiance `LOW`, et une note qui dit pourquoi.

Ce qui est publié en clair, c'est le **niveau de correctif de sécurité**
(`ro.build.version.security_patch`) : c'est la seule donnée qui dise vraiment si
l'appareil reçoit encore des correctifs, et elle porte sa propre note pour être
lisible sans dérouler le rapport.

## Ce qui n'est pas collecté, et pourquoi

| Donnée                           | Raison                                                                                                                                          |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Journal (`events`)               | `logcat` contient les journaux de toutes les applications. Décision de portée.                                                                  |
| Crashs applicatifs               | Même raison.                                                                                                                                    |
| Durée de démarrage               | `ro.boottime.*` n'est pas exposé uniformément ; les valeurs varient d'un constructeur à l'autre et ne se composent pas.                         |
| Fréquences processeur            | Un système sur puce a plusieurs clusters à fréquences distinctes. Une fréquence unique serait fausse.                                           |
| Cœurs physiques                  | Un big.LITTLE n'a pas « la moitié » de ses cœurs logiques en cœurs physiques : les clusters ont des tailles différentes.                        |
| Températures                     | `/sys/class/thermal` n'est pas lisible sans privilège sur la plupart des appareils.                                                             |
| Usure de batterie                | `dumpsys battery` ne publie pas la capacité de conception. L'usure n'est donc **pas calculable**, et le rapport le dit plutôt que de l'estimer. |
| Inventaire de la mémoire interne | Les attributs UFS et eMMC sont réservés au système.                                                                                             |

## Lancer

Depuis l'appareil (Termux, ou une future application) :

```sh
./sysaudit.sh --capabilities
./sysaudit.sh --stdout
```

Depuis un poste, par ADB :

```sh
adb push sysaudit.sh lib /data/local/tmp/sysaudit/
adb shell sh /data/local/tmp/sysaudit/sysaudit.sh --stdout > rapport.json
```

Le scanner refuse de tourner ailleurs que sur Android. `uname -s` rend « Linux »
sur Android **comme sur une Debian** et ne distingue rien : la marque retenue est
`getprop`, ou à défaut `/system/build.prop`.
`SYSAUDIT_ALLOW_FOREIGN_HOST=1` lève ce refus et n'existe que pour les tests.

## La seule couture de test

`SYSAUDIT_PROC_ROOT` remplace `/proc`. Sans elle, l'analyse de `meminfo` et de
`cpuinfo` — la partie la plus facile à écrire de travers — ne serait vérifiable
que sur un appareil Android, c'est-à-dire jamais. Elle ne change rien en
exploitation : la valeur par défaut est `/proc`, et rien dans le produit ne
définit cette variable.

## Pour valider ce scanner

Un appareil Android, et une campagne du type de celles décrites dans
docs/qualite/VALIDATION-CAMPAIGNS.md. Il faudra
au minimum deux appareils : un avec chargeur d'amorçage verrouillé, un
déverrouillé — c'est la seule façon de vérifier que Verified Boot n'est pas lu
comme un booléen.
