#!/usr/bin/env bash
#
# Tests du scanner macOS expérimental.
#
# Aucun Mac n'est disponible pour les écrire. Ce que ces tests peuvent
# néanmoins prouver — et ce qui compte le plus pour un scanner qu'on n'a pas pu
# essayer :
#
#  1. **les fonctions pures** produisent du JSON valide, échappent ce qu'il
#     faut, et ne convertissent jamais une absence en zéro ;
#  2. **sur un système nu**, où aucune des commandes macOS n'existe, le scanner
#     produit tout de même un rapport conforme au schéma, entièrement composé de
#     marqueurs motivés — c'est le cas le plus dangereux, celui où un scanner
#     mal écrit inventerait des valeurs ;
#  3. **sur un macOS simulé**, où de fausses commandes rendent des sorties
#     relevées dans la documentation Apple, les valeurs attendues remontent aux
#     bons champs.
#
# Ce que ces tests ne prouvent **pas**, et qu'il faut dire : que les sorties des
# fixtures ressemblent à celles d'un vrai Mac. Elles sont reprises de la
# documentation et des pages de manuel, pas relevées sur une machine. Un format
# qui aurait changé passerait ici et échouerait là-bas.

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

REFUSAL=$(sh "$SCANNER_DIR/sysaudit.sh" --stdout 2>&1)
REFUSAL_CODE=$?
assert_eq '1' "$REFUSAL_CODE" 'le scanner refuse de tourner hors de macOS'
assert_contains "$REFUSAL" 'cible macOS' 'le refus dit quelle plateforme est visée'
assert_contains "$REFUSAL" 'incapable de répondre' \
  'le refus explique pourquoi un rapport ici serait trompeur'

# --- Système nu : rien n'existe ---------------------------------------------

suite 'Système nu — aucune commande macOS'

# Le cas le plus dangereux. Un scanner mal écrit y produirait des zéros, des
# `false`, ou un document invalide. Celui-ci doit produire un rapport conforme,
# entièrement composé de marqueurs motivés.
BARE=$(SYSAUDIT_ALLOW_FOREIGN_HOST=1 sh "$SCANNER_DIR/sysaudit.sh" --stdout --quiet 2>/dev/null)

assert_contains "$BARE" '"schemaVersion"' 'un rapport est tout de même produit'
assert_contains "$BARE" '"scannerKind":"macos"' 'le rapport se déclare macOS'
assert_contains "$BARE" 'EXPERIMENTAL' 'le rapport porte la mention EXPERIMENTAL'
assert_contains "$BARE" 'UNVALIDATED' 'le rapport porte la mention UNVALIDATED'
assert_contains "$BARE" '"features"' 'la table des capacités est publiée'
assert_contains "$BARE" '"sw_vers":false' 'un outil absent est déclaré absent, pas omis'

# Aucune valeur inventée : le cas qui justifie tout le produit.
assert_not_contains "$BARE" '"installedBytes":0' 'aucune mémoire nulle n’est fabriquée'
assert_not_contains "$BARE" '"uptimeSeconds":0' 'aucun uptime nul n’est fabriqué'
assert_contains "$BARE" '"reason":"NOT_AVAILABLE"' 'les absences portent leur raison'
assert_contains "$BARE" '"detail"' 'chaque absence est motivée en clair'

# Une interface sans adresse ether ne fabrique pas la sienne à partir du reste.
#
# Défaut corrigé le 2026-08-17 : la tabulation étant un caractère blanc au sens
# d'IFS, `read` fusionnait deux séparateurs consécutifs, et un champ `mac` vide
# décalait tout le reste — l'adresse **IP** de l'interface se retrouvait publiée
# comme son adresse **MAC**. Visible seulement sur une machine portant une
# interface point-à-point (WireGuard, tunnel), donc invisible en CI.
#
# Le test lit le rapport produit sur *cette* machine : il ne prouve rien si elle
# n'a pas d'interface sans ether, mais il ne peut jamais passer à tort.
MAC_LOOKS_LIKE_IP=$(printf '%s' "$BARE" | grep -o '"mac":"[0-9.]*"' | head -1)
assert_eq '' "$MAC_LOOKS_LIKE_IP" 'aucune adresse IP n’est publiée comme adresse MAC'

suite 'Notions sans objet sur macOS'

# `NOT_APPLICABLE` et `NOT_AVAILABLE` ne disent pas la même chose : la première
# signifie « il n'y a rien à mesurer ici », la seconde « je n'ai pas pu lire ».
assert_contains "$BARE" '"reason":"NOT_APPLICABLE"' 'les notions sans objet sont distinguées'
assert_contains "$BARE" 'notion propre au noyau Linux' 'le noyau souillé est sans objet sur macOS'
assert_contains "$BARE" 'notion propre à Windows' 'le démarrage rapide est sans objet sur macOS'
assert_contains "$BARE" 'macOS n’a pas d’édition' 'l’édition est sans objet sur macOS'

# --- macOS simulé -----------------------------------------------------------

suite 'macOS simulé — de fausses commandes rendent les fixtures'

FAKE_BIN=$(mktemp -d "${TMPDIR:-/tmp}/sysaudit-fakebin-XXXXXX")
trap 'rm -rf "$FAKE_BIN"' EXIT

# Chaque fausse commande rend exactement le contenu d'une fixture. C'est une
# **simulation**, et elle vaut ce que valent les fixtures : elles viennent de la
# documentation Apple, pas d'un Mac. Le test le dit plutôt que de le taire.
cat >"$FAKE_BIN/sw_vers" <<FAKE
#!/bin/sh
case "\$1" in
  -productName) printf 'macOS\n' ;;
  -productVersion) printf '14.5\n' ;;
  -buildVersion) printf '23F79\n' ;;
  *) grep -v '^#' '$FIXTURES/sw_vers.txt' ;;
esac
FAKE

cat >"$FAKE_BIN/sysctl" <<FAKE
#!/bin/sh
# \`sysctl -n <clé>\` : rend la valeur seule, comme le vrai.
[ "\$1" = '-n' ] && shift
grep -v '^#' '$FIXTURES/sysctl.txt' | awk -v k="\$1" '\$1 == k { \$1 = ""; sub(/^ /, ""); print; exit }'
FAKE

cat >"$FAKE_BIN/pmset" <<FAKE
#!/bin/sh
cat '$FIXTURES/pmset-batt.txt'
FAKE

cat >"$FAKE_BIN/ifconfig" <<FAKE
#!/bin/sh
cat '$FIXTURES/ifconfig.txt'
FAKE

cat >"$FAKE_BIN/vm_stat" <<FAKE
#!/bin/sh
cat '$FIXTURES/vm_stat.txt'
FAKE

cat >"$FAKE_BIN/csrutil" <<'FAKE'
#!/bin/sh
printf 'System Integrity Protection status: enabled.\n'
FAKE

cat >"$FAKE_BIN/fdesetup" <<'FAKE'
#!/bin/sh
printf 'FileVault is On.\n'
FAKE

cat >"$FAKE_BIN/spctl" <<'FAKE'
#!/bin/sh
printf 'assessments enabled\n'
FAKE

cat >"$FAKE_BIN/defaults" <<'FAKE'
#!/bin/sh
printf '1\n'
FAKE

cat >"$FAKE_BIN/scutil" <<'FAKE'
#!/bin/sh
printf 'MacBook Pro de Christophe\n'
FAKE

cat >"$FAKE_BIN/ioreg" <<'FAKE'
#!/bin/sh
printf '    "IOPlatformSerialNumber" = "C02XY1234567"\n'
printf '    "IOPlatformUUID" = "11111111-2222-3333-4444-555555555555"\n'
FAKE

chmod +x "$FAKE_BIN"/*

SIM=$(PATH="$FAKE_BIN:$PATH" SYSAUDIT_ALLOW_FOREIGN_HOST=1 \
  sh "$SCANNER_DIR/sysaudit.sh" --stdout --quiet 2>/dev/null)

assert_contains "$SIM" '"name":"macOS"' 'le nom du système remonte de sw_vers'
assert_contains "$SIM" '"version":"14.5"' 'la version remonte de sw_vers'
assert_contains "$SIM" '"build":"23F79"' 'le build remonte de sw_vers'
assert_contains "$SIM" '"model":"MacBookPro18,3"' 'le modèle remonte de sysctl hw.model'
assert_contains "$SIM" '"hostname":"MacBook Pro de Christophe"' 'le nom de machine vient de scutil'
assert_contains "$SIM" '"serialNumber":"C02XY1234567"' 'le numéro de série vient d’ioreg'
assert_contains "$SIM" '"installedBytes":34359738368' 'la mémoire installée remonte de hw.memsize'

# `kern.boottime` rend « { sec = 1785000000, usec = 0 } … ». Une expression
# régulière gloutonne y attrape « usec » et rend 0 : l'uptime devenait alors
# l'instant Unix tout entier, soit cinquante-six ans — que le schéma refuse.
# Le défaut a été trouvé par le test jumeau du scanner BSD, pas par relecture.
assert_contains "$SIM" '"bootedAt":"2026-07-25T' 'la date de démarrage vient de kern.boottime'
assert_not_contains "$SIM" '"bootedAt":"1970-' 'le champ « usec » n’est pas confondu avec « sec »'
assert_contains "$SIM" '"physicalCores":10' 'le nombre de cœurs physiques remonte'

# La preuve que le scanner ne fabrique rien même quand tout le reste répond :
# `machdep.cpu.brand_string` n'existe pas sur Apple Silicon, et le champ reste
# inconnu au lieu d'être rempli avec `hw.model`, qui n'est pas le processeur.
assert_contains "$SIM" 'attendu sur Apple Silicon' \
  'le modèle de processeur reste inconnu sur Apple Silicon'
assert_not_contains "$SIM" '"model":"MacBookPro18,3","vendor"' \
  'le modèle de machine ne se substitue pas au modèle de processeur'

# La taille de page est **lue**, pas supposée : 16 Kio sur Apple Silicon contre
# 4 Kio sur Intel. Une constante en dur donnerait un chiffre faux d'un facteur
# quatre sur la moitié du parc.
# 123456 pages libres + 98765 inactives, à 16384 octets la page. Une constante
# de 4096 écrite en dur — la taille de page d'un Mac Intel — donnerait 910 Mio
# au lieu de 3,4 Gio sur cette machine.
assert_contains "$SIM" '"availableBytes":3640868864' \
  'la mémoire disponible emploie la taille de page réellement lue'

# Le schéma n'a pas de sous-section de sécurité macOS : FileVault, SIP et
# Gatekeeper partent dans `notes`, en clair. Les inventer un champ aurait été
# une évolution de schéma décidée par un scanner que personne n'a exécuté.
assert_contains "$SIM" 'FileVault : actif' 'FileVault actif est rapporté'
assert_contains "$SIM" '"state":"ENABLED"' 'le pare-feu applicatif est lu'
assert_contains "$SIM" '"engine":"com.apple.alf"' 'le moteur de pare-feu est nommé'
assert_contains "$SIM" 'SIP : actif' 'SIP est rapporté'
assert_contains "$SIM" 'Gatekeeper : actif' 'Gatekeeper est rapporté'

# Le cas qui distingue « je n'ai pas lu » de « c'est éteint ».
NOSEC=$(SYSAUDIT_ALLOW_FOREIGN_HOST=1 sh "$SCANNER_DIR/sysaudit.sh" --stdout --quiet 2>/dev/null)
assert_contains "$NOSEC" 'SIP : non lu' 'une protection non lue n’est pas rapportée désactivée'

assert_contains "$SIM" '"acConnected":true' 'l’alimentation secteur est lue'
assert_contains "$SIM" '"chargePercent":87' 'le niveau de charge est lu'

assert_contains "$SIM" '"mac":"a4:83:e7:11:22:33"' 'l’adresse MAC remonte d’ifconfig'
assert_contains "$SIM" '"address":"192.168.1.42"' 'l’adresse IPv4 remonte d’ifconfig'

# Même avec tous les outils qui répondent, l'expérimental reste expérimental.
assert_contains "$SIM" 'EXPERIMENTAL' 'un scan complet reste marqué EXPERIMENTAL'

suite 'Validation contre le schéma'

if command -v node >/dev/null 2>&1; then
  SCHEMA_MODULE="$SCANNER_DIR/../../packages/report-schema/dist/index.js"
  if [ -f "$SCHEMA_MODULE" ]; then
    TMP=$(mktemp -d "${TMPDIR:-/tmp}/sysaudit-macos-test-XXXXXX")
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
printf '\033[33mRappel : ce scanner n’a jamais tourné sur un Mac. Ces tests prouvent qu’il\n'
printf 'dégrade proprement et qu’il lit correctement des fixtures — pas que ces\n'
printf 'fixtures ressemblent à un vrai Mac.\033[0m\n\n'
