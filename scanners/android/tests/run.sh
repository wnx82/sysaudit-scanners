#!/usr/bin/env bash
#
# Tests du scanner Android expérimental.
#
# Aucun téléphone n'est disponible pour les écrire. Ce que ces tests peuvent
# néanmoins prouver :
#
#  1. **les fonctions pures** produisent du JSON valide, échappent ce qu'il
#     faut, et ne convertissent jamais une absence en zéro ;
#  2. **sur un système nu**, où ni `getprop` ni `dumpsys` n'existent, le scanner
#     produit tout de même un rapport conforme au schéma, entièrement composé de
#     marqueurs motivés ;
#  3. **sur un Android simulé**, les propriétés remontent aux bons champs, et
#     les trois conversions qui peuvent silencieusement mentir sont vérifiées :
#     la température en dixièmes de degré, le statut de batterie en entier, et
#     l'état de Verified Boot en couleur.
#
# Un quatrième point est propre à Android : le scanner doit distinguer « pas
# le droit » de « pas de donnée ». Un test le vérifie, parce que confondre les
# deux invite à chercher une panne là où il n'y a qu'une politique.
#
# Ce que ces tests ne prouvent **pas** : que les fixtures ressemblent à un vrai
# téléphone. Elles viennent de la documentation d'Android, pas d'un appareil.

set -uo pipefail

SCANNER_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly SCANNER_DIR
readonly FIXTURES="$SCANNER_DIR/tests/fixtures"

# shellcheck source=../lib/json.sh
. "$SCANNER_DIR/lib/json.sh"
# shellcheck source=../lib/core.sh
. "$SCANNER_DIR/lib/core.sh"

PASSED=0
FAILED=0

suite() { printf '\n\033[1m%s\033[0m\n' "$1"; }

assert_eq() {
  if [ "$1" = "$2" ]; then
    PASSED=$((PASSED + 1))
    printf '  \033[32m✓\033[0m %s\n' "$3"
  else
    FAILED=$((FAILED + 1))
    printf '  \033[31m✗\033[0m %s\n      attendu : %s\n      obtenu  : %s\n' "$3" "$1" "$2"
  fi
}

assert_contains() {
  case "$1" in
    *"$2"*)
      PASSED=$((PASSED + 1))
      printf '  \033[32m✓\033[0m %s\n' "$3"
      ;;
    *)
      FAILED=$((FAILED + 1))
      printf '  \033[31m✗\033[0m %s\n      « %s » introuvable\n' "$3" "$2"
      ;;
  esac
}

assert_not_contains() {
  case "$1" in
    *"$2"*)
      FAILED=$((FAILED + 1))
      printf '  \033[31m✗\033[0m %s\n      « %s » ne devait pas apparaître\n' "$3" "$2"
      ;;
    *)
      PASSED=$((PASSED + 1))
      printf '  \033[32m✓\033[0m %s\n' "$3"
      ;;
  esac
}

# --- Fonctions pures --------------------------------------------------------

suite 'Construction JSON'

assert_eq '"simple"' "$(j_str 'simple')" 'chaîne simple'
assert_eq '"guillemet \" interne"' "$(j_str 'guillemet " interne')" 'guillemet échappé'
assert_eq '"anti\\slash"' "$(j_str 'anti\slash')" 'anti-slash échappé'
assert_eq '"deux\nlignes"' "$(printf 'deux\nlignes' | xargs -0 -I{} sh -c 'true'; j_str "$(printf 'deux\nlignes')")" \
  'saut de ligne échappé'

assert_eq '42' "$(j_num 42)" 'entier'
assert_eq '3.14' "$(j_num '3,14')" 'virgule décimale convertie'
assert_eq 'null' "$(j_num 'abc')" 'valeur non numérique rendue null, jamais 0'
assert_eq 'null' "$(j_num '')" 'valeur vide rendue null'

suite 'Marqueurs d’absence'

# Le test décisif de tout le produit : une valeur absente ne devient jamais 0,
# false ou une chaîne vide.
assert_contains "$(jf_maybe_num total '' NOT_AVAILABLE 'outil absent')" '"unknown":true' \
  'un nombre absent porte un marqueur'
assert_not_contains "$(jf_maybe_num total '' NOT_AVAILABLE 'outil absent')" '"total":0' \
  'un nombre absent ne devient pas zéro'
assert_contains "$(jf_maybe_num total '' NOT_AVAILABLE 'outil absent')" 'outil absent' \
  'le motif accompagne le marqueur'
assert_contains "$(jf_maybe_bool actif '' UNSUPPORTED 'notion inexistante ici')" '"reason":"UNSUPPORTED"' \
  'un booléen absent n’est pas false'
assert_not_contains "$(jf_maybe_bool actif '' UNSUPPORTED 'x')" '"actif":false' \
  'un booléen absent ne devient pas false'
assert_eq '"actif":true' "$(jf_maybe_bool actif true)" 'un booléen lu passe tel quel'

# Zéro **mesuré** reste zéro : c'est un fait, pas une absence.
assert_eq '"total":0' "$(jf_maybe_num total 0)" 'un zéro mesuré est publié comme zéro'

suite 'Assemblage'

assert_eq '{"a":1,"b":2}' "$(json_object "$(jf_raw a 1)" "$(jf_raw b 2)")" 'objet à deux champs'
assert_eq '{"a":1}' "$(json_object "$(jf_raw a 1)" '')" 'fragment vide ignoré, pas de virgule orpheline'
assert_eq '' "$(section storage '')" 'une section vide est omise, jamais émise vide'
assert_eq '"storage":{}' "$(section storage '{}')" 'une section renseignée porte sa clé'

suite 'Détection d’outils'

assert_eq '0' "$(
  have sh
  printf '%s' $?
)" 'une commande présente est détectée'
assert_eq '1' "$(
  have commande-qui-nexiste-pas-42
  printf '%s' $?
)" 'une commande absente est signalée, sans erreur'
assert_eq '127' "$(
  try commande-qui-nexiste-pas-42 >/dev/null
  printf '%s' $?
)" 'try rend 127 sur commande absente, sans interrompre le scan'
assert_eq '' "$(try commande-qui-nexiste-pas-42 2>/dev/null)" \
  'try n’émet jamais le message d’erreur, qui finirait dans un champ'

suite 'Horodatage'

# GNU et BSD n'ont pas la même syntaxe ; au moins l'une des deux doit répondre.
assert_contains "$(epoch_to_iso 1785000000)" '2026-' 'une date Unix devient un ISO 8601'
assert_eq '' "$(epoch_to_iso 'pas-un-nombre')" 'une entrée non numérique ne produit aucune date'
assert_eq '' "$(epoch_to_iso '')" 'une entrée vide ne produit aucune date'
assert_contains "$(now_iso)" 'T' 'l’instant courant est en ISO 8601'
assert_contains "$(now_iso)" 'Z' 'l’instant courant est en UTC'

suite 'Première ligne utile'

assert_eq 'valeur' "$(printf '\n\nvaleur\nautre\n' | first_line)" \
  'les lignes vides de tête sont ignorées'
assert_eq '' "$(printf '\n\n' | first_line)" 'une sortie sans ligne utile ne rend rien'

# --- Refus de plateforme ----------------------------------------------------

suite 'Refus de plateforme'

# `uname -s` rend « Linux » sur Android comme sur une Debian : il ne distingue
# rien. La marque d'Android est `getprop` ou `/system/build.prop`.
REFUSAL=$(sh "$SCANNER_DIR/sysaudit.sh" --stdout 2>&1)
REFUSAL_CODE=$?
assert_eq '1' "$REFUSAL_CODE" 'le scanner refuse de tourner hors d’Android'
assert_contains "$REFUSAL" 'cible Android' 'le refus dit quelle plateforme est visée'
assert_contains "$REFUSAL" 'ne distingue rien' \
  'le refus explique pourquoi uname ne suffit pas à reconnaître Android'

# --- Système nu -------------------------------------------------------------

suite 'Système nu — ni getprop ni dumpsys'

BARE=$(SYSAUDIT_ALLOW_FOREIGN_HOST=1 sh "$SCANNER_DIR/sysaudit.sh" --stdout --quiet 2>/dev/null)

assert_contains "$BARE" '"scannerKind":"android"' 'le rapport se déclare Android'
assert_contains "$BARE" '"platform":"android"' 'la plateforme est android'
# Android **est** un Linux, et l'énumération du schéma n'a pas de valeur
# `android` : la distinction se fait par `capabilities.platform`.
assert_contains "$BARE" '"family":"linux"' 'la famille de système reste linux'
assert_contains "$BARE" 'EXPERIMENTAL' 'le rapport porte la mention EXPERIMENTAL'
assert_contains "$BARE" 'UNVALIDATED' 'le rapport porte la mention UNVALIDATED'
assert_contains "$BARE" 'Aucune donnée d’application' \
  'la décision de portée est écrite dans le rapport'
assert_not_contains "$BARE" '"chargePercent":0' 'aucun niveau de batterie nul n’est fabriqué'
assert_not_contains "$BARE" '"installedBytes":0' 'aucune mémoire nulle n’est fabriquée'

suite 'Permission refusée ≠ donnée absente'

# La confusion la plus coûteuse d'un audit Android. Hors root, un `dumpsys`
# muet est presque toujours un refus, pas une absence — et les confondre invite
# à chercher une panne là où il n'y a qu'une politique.
assert_contains "$BARE" '"reason":"PERMISSION_DENIED"' \
  'hors root, une absence de lecture se lit « permission refusée »'
assert_contains "$BARE" 'réservé au système depuis Android 10' \
  'le numéro de série non lu porte le motif exact'
assert_contains "$BARE" 'Mode de collecte' 'le mode de collecte est publié dans les notes'

suite 'Notions sans objet sur Android'

assert_contains "$BARE" 'Android emploie SELinux, jamais AppArmor' 'AppArmor est sans objet'
assert_contains "$BARE" 'aucun emplacement mémoire sur un système sur puce' \
  'les emplacements mémoire sont sans objet'
assert_contains "$BARE" 'notion propre à Windows' 'le démarrage rapide est sans objet'

# --- Android simulé ---------------------------------------------------------

FAKE_BIN=$(mktemp -d "${TMPDIR:-/tmp}/sysaudit-android-fakebin-XXXXXX")
FAKE_PROC=$(mktemp -d "${TMPDIR:-/tmp}/sysaudit-android-proc-XXXXXX")
trap 'rm -rf "$FAKE_BIN" "$FAKE_PROC"' EXIT

cat >"$FAKE_BIN/getprop" <<FAKE
#!/bin/sh
grep -v '^#' '$FIXTURES/getprop.txt' | awk -v k="\$1" '\$1 == k { \$1 = ""; sub(/^ /, ""); print; exit }'
FAKE

cat >"$FAKE_BIN/dumpsys" <<FAKE
#!/bin/sh
[ "\$1" = 'battery' ] && cat '$FIXTURES/dumpsys-battery.txt'
FAKE

cat >"$FAKE_BIN/df" <<FAKE
#!/bin/sh
cat '$FIXTURES/df.txt'
FAKE

cat >"$FAKE_BIN/getenforce" <<'FAKE'
#!/bin/sh
printf 'Enforcing\n'
FAKE

chmod +x "$FAKE_BIN"/*

# `/proc` est simulé par `SYSAUDIT_PROC_ROOT`, la seule couture de test du
# scanner. Sans elle, l'analyse de `meminfo` et de `cpuinfo` — la partie la plus
# facile à écrire de travers — ne serait vérifiable que sur un appareil Android,
# c'est-à-dire jamais.
cp "$FIXTURES/meminfo.txt" "$FAKE_PROC/meminfo"
cp "$FIXTURES/cpuinfo.txt" "$FAKE_PROC/cpuinfo"
printf '318472.90 2401234.12\n' >"$FAKE_PROC/uptime"

SIM=$(PATH="$FAKE_BIN:$PATH" SYSAUDIT_ALLOW_FOREIGN_HOST=1 SYSAUDIT_PROC_ROOT="$FAKE_PROC" \
  sh "$SCANNER_DIR/sysaudit.sh" --stdout --quiet 2>/dev/null)

suite 'Android simulé — identité et système'

assert_contains "$SIM" '"manufacturer":"Google"' 'le fabricant vient de getprop'
assert_contains "$SIM" '"model":"Pixel 8"' 'le modèle vient de getprop'
assert_contains "$SIM" '"version":"14"' 'la version d’Android vient de getprop'
assert_contains "$SIM" '"build":"UQ1A.240205.004"' 'le build vient de getprop'
assert_contains "$SIM" '"architecture":"arm64-v8a"' 'l’architecture vient de getprop'

suite 'Correctif de sécurité — la donnée centrale d’un audit Android'

# C'est elle qui dit si l'appareil reçoit encore des correctifs. Elle porte sa
# propre note pour être lisible sans dérouler le rapport.
assert_contains "$SIM" 'Niveau de correctif de sécurité : 2026-06-05' \
  'le niveau de correctif est publié en clair'

# La fin de support d'un appareil Android dépend du **constructeur**, pas de la
# version d'Android. La déduire de l'API serait une supposition, et le rapport
# le dit plutôt que de conclure.
assert_contains "$SIM" '"status":"UNKNOWN"' 'aucune fin de support n’est déduite du niveau d’API'
assert_contains "$SIM" 'dépend du constructeur' 'le motif de cette réserve est écrit'

suite 'Verified Boot — la couleur n’est pas un booléen'

# `verifiedbootstate` vaut green, yellow, orange ou red. Seul `green` signifie
# « chaîne intacte et signée par le constructeur ». Traiter `yellow` — signé par
# une clé tierce — comme `green` ferait passer un appareil modifié pour
# un appareil d'origine.
assert_contains "$SIM" '"secureBoot":"ENABLED"' 'un état vert vaut ENABLED'
assert_contains "$SIM" 'Verified Boot : vert' 'l’état est aussi publié en clair'
assert_contains "$SIM" 'Chargeur d’amorçage : verrouillé' 'le verrouillage est publié'

suite 'Batterie — trois conversions qui peuvent mentir'

# `dumpsys battery` rend la température en **dixièmes de degré**. La publier
# telle quelle donnerait 352 °C sur une batterie à 35,2 °C.
assert_contains "$SIM" 'Température de la batterie : 35.2 °C' \
  'la température est convertie depuis les dixièmes de degré'
assert_not_contains "$SIM" '352 °C' 'aucune température en dixièmes ne part telle quelle'

# `status` est un entier : 2 en charge. Le publier tel quel dans un champ
# énuméré serait faux.
assert_contains "$SIM" '"status":"CHARGING"' 'le code de statut 2 devient CHARGING'
assert_not_contains "$SIM" '"status":"2"' 'aucun code numérique ne part tel quel'

assert_contains "$SIM" '"chargePercent":64' 'le niveau de charge est lu'
# Alimenté par USB, pas par secteur : les deux comptent comme « branché ».
assert_contains "$SIM" '"acConnected":true' 'une alimentation USB compte comme branchée'
assert_contains "$SIM" '"technology":"Li-ion"' 'la technologie de la batterie est lue'

# L'usure d'une batterie Android n'est pas calculable : `dumpsys battery` ne
# publie pas la capacité de conception. Le dire vaut mieux que de l'estimer.
assert_contains "$SIM" 'n’est donc pas calculable ici' \
  'l’impossibilité de calculer l’usure est écrite'

suite 'Stockage — seuls les points de montage utiles'

# Lister tous les points de montage d'un Android en produirait plusieurs
# dizaines, dont aucun ne renseigne sur l'espace réellement disponible.
assert_contains "$SIM" '"mountPoint":"/data"' '/data est retenu'
assert_not_contains "$SIM" '"mountPoint":"/dev"' 'les montages internes sont écartés'

suite 'Mémoire et processeur — lus dans un /proc simulé'

assert_contains "$SIM" '"installedBytes":8096276480' 'MemTotal est converti en octets'
assert_contains "$SIM" '"availableBytes":3539751936' 'MemAvailable est converti en octets'
# SwapTotal 4194304 kio, SwapFree 3145728 kio : 1048576 kio utilisés.
assert_contains "$SIM" '"swapUsedBytes":1073741824' 'le swap utilisé est la différence, pas SwapTotal'
assert_contains "$SIM" '"logicalCores":9' 'les lignes « processor » sont comptées'
assert_contains "$SIM" '"model":"Google Tensor G3"' 'la puce vient de la ligne Hardware'

# Un big.LITTLE n'a pas « la moitié » de ses cœurs logiques en cœurs physiques :
# les clusters ont des tailles différentes. Le champ reste inconnu.
assert_contains "$SIM" 'ne se déduisent pas du nombre de lignes' \
  'les cœurs physiques restent inconnus, avec leur motif'
assert_not_contains "$SIM" '"physicalCores":4' 'aucun nombre de cœurs physiques n’est déduit'

assert_contains "$SIM" '"uptimeSeconds":318472' 'l’uptime vient de /proc/uptime'

suite 'SELinux'

assert_contains "$SIM" '"selinux":"ENFORCING"' 'l’état SELinux est lu et normalisé'

# --- Schéma -----------------------------------------------------------------

suite 'Validation contre le schéma'

if command -v node >/dev/null 2>&1; then
  SCHEMA_MODULE="$SCANNER_DIR/../../packages/report-schema/dist/index.js"
  if [ -f "$SCHEMA_MODULE" ]; then
    TMP=$(mktemp -d "${TMPDIR:-/tmp}/sysaudit-android-test-XXXXXX")
    printf '%s' "$BARE" >"$TMP/bare.json"
    printf '%s' "$SIM" >"$TMP/sim.json"

    for CASE in bare sim; do
      RESULT=$(node --input-type=module -e "
        import { readFileSync } from 'node:fs';
        import { validateReport } from '$SCHEMA_MODULE';
        const r = validateReport(JSON.parse(readFileSync('$TMP/$CASE.json', 'utf8')));
        console.log(r.ok ? 'OK' : r.issues.slice(0, 5).map((i) => i.path + ' : ' + i.message).join(' | '));
      " 2>&1)
      assert_eq 'OK' "$RESULT" "le rapport « $CASE » est conforme au schéma"
    done

    rm -rf "$TMP"
  else
    printf '  \033[33m·\033[0m validation de schéma ignorée (report-schema non compilé)\n'
  fi
else
  printf '  \033[33m·\033[0m validation de schéma ignorée (node absent)\n'
fi

suite 'Aucune donnée d’application'

# Décision de portée, et non limite technique : l'inventaire applicatif d'un
# téléphone personnel est la donnée la plus intime qu'un audit puisse produire.
SOURCE=$(grep -v '^\s*#' "$SCANNER_DIR/sysaudit.sh")
assert_not_contains "$SOURCE" 'pm list packages' 'la liste des paquets n’est jamais demandée'
assert_not_contains "$SOURCE" 'logcat -d' 'le journal applicatif n’est jamais lu'
assert_not_contains "$SOURCE" 'settings put' 'aucun réglage n’est modifié'
assert_not_contains "$SOURCE" 'setprop' 'aucune propriété n’est écrite'

suite 'Contrat de version'

DECLARED=$(sed -n "s/^SCHEMA_VERSION='\([^']*\)'\$/\1/p" "$SCANNER_DIR/sysaudit.sh")
assert_contains "$DECLARED" '.' 'le scanner déclare une version de schéma'
assert_contains "$(cat "$SCANNER_DIR/VERSION")" '.' 'le scanner porte une version SemVer'

# --- Bilan ------------------------------------------------------------------

printf '\n'
if [ "$FAILED" -gt 0 ]; then
  printf '\033[31m%d test(s) en échec, %d réussi(s).\033[0m\n\n' "$FAILED" "$PASSED"
  exit 1
fi
printf '\033[32m%d tests réussis.\033[0m\n' "$PASSED"
printf '\033[33mRappel : ce scanner n’a jamais tourné sur un appareil Android. Ces tests\n'
printf 'prouvent qu’il dégrade proprement, qu’il distingue un refus d’une absence,\n'
printf 'et qu’il lit correctement des fixtures — pas que ces fixtures ressemblent\n'
printf 'à un vrai téléphone.\033[0m\n\n'
