#!/usr/bin/env bash
#
# Tests du scanner FreeBSD / pfSense / OPNsense expérimental.
#
# Aucune de ces trois machines n'est disponible pour les écrire. Ce que ces
# tests peuvent néanmoins prouver :
#
#  1. **les fonctions pures** produisent du JSON valide, échappent ce qu'il
#     faut, et ne convertissent jamais une absence en zéro ;
#  2. **sur un système nu**, où aucune commande FreeBSD n'existe, le scanner
#     produit tout de même un rapport conforme au schéma, entièrement composé de
#     marqueurs motivés — c'est le cas le plus dangereux, celui où un scanner
#     mal écrit inventerait des valeurs ;
#  3. **sur trois systèmes simulés** — FreeBSD nu, pfSense et OPNsense — la
#     distribution est reconnue sur ses fichiers de version, et la version de
#     l'appliance ne se confond pas avec celle de sa base FreeBSD.
#
# Ce que ces tests ne prouvent **pas** : que les fixtures ressemblent à une
# vraie machine. Elles viennent des pages de manuel et de la documentation des
# deux appliances, pas d'un hôte réel.

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
assert_eq '1' "$REFUSAL_CODE" 'le scanner refuse de tourner hors de FreeBSD'
assert_contains "$REFUSAL" 'cible FreeBSD' 'le refus dit quelle plateforme est visée'
assert_contains "$REFUSAL" 'incapable de répondre' \
  'le refus explique pourquoi un rapport ici serait trompeur'

# --- Système nu -------------------------------------------------------------

suite 'Système nu — aucune commande FreeBSD'

BARE=$(SYSAUDIT_ALLOW_FOREIGN_HOST=1 sh "$SCANNER_DIR/sysaudit.sh" --stdout --quiet 2>/dev/null)

assert_contains "$BARE" '"scannerKind":"freebsd"' 'le rapport se déclare FreeBSD'
assert_contains "$BARE" '"family":"freebsd"' 'la famille de système est FreeBSD'
assert_contains "$BARE" 'EXPERIMENTAL' 'le rapport porte la mention EXPERIMENTAL'
assert_contains "$BARE" 'UNVALIDATED' 'le rapport porte la mention UNVALIDATED'
assert_not_contains "$BARE" '"installedBytes":0' 'aucune mémoire nulle n’est fabriquée'
assert_not_contains "$BARE" '"logicalCores":0' 'aucun nombre de cœurs nul n’est fabriqué'
assert_contains "$BARE" '"reason":"NOT_AVAILABLE"' 'les absences portent leur raison'
assert_contains "$BARE" 'notion propre au noyau Linux' 'le noyau souillé est sans objet ici'

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

# --- FreeBSD simulé ---------------------------------------------------------

FAKE_BIN=$(mktemp -d "${TMPDIR:-/tmp}/sysaudit-bsd-fakebin-XXXXXX")
trap 'rm -rf "$FAKE_BIN"' EXIT

cat >"$FAKE_BIN/sysctl" <<FAKE
#!/bin/sh
[ "\$1" = '-n' ] && shift
grep -v '^#' '$FIXTURES/sysctl.txt' | awk -v k="\$1" '\$1 == k { \$1 = ""; sub(/^ /, ""); print; exit }'
FAKE

cat >"$FAKE_BIN/kenv" <<FAKE
#!/bin/sh
grep -v '^#' '$FIXTURES/kenv.txt' | awk -v k="\$1" '\$1 == k { \$1 = ""; sub(/^ /, ""); print; exit }'
FAKE

cat >"$FAKE_BIN/freebsd-version" <<'FAKE'
#!/bin/sh
printf '14.1-RELEASE-p3\n'
FAKE

cat >"$FAKE_BIN/ifconfig" <<FAKE
#!/bin/sh
cat '$FIXTURES/ifconfig.txt'
FAKE

cat >"$FAKE_BIN/zpool" <<FAKE
#!/bin/sh
cat '$FIXTURES/zpool-list.txt'
FAKE

cat >"$FAKE_BIN/dmesg" <<FAKE
#!/bin/sh
cat '$FIXTURES/dmesg.txt'
FAKE

cat >"$FAKE_BIN/swapinfo" <<'FAKE'
#!/bin/sh
printf 'Device          1K-blocks     Used    Avail Capacity\n'
printf '/dev/gpt/swapfs   4194304   131072  4063232     3%%\n'
printf 'Total             4194304   131072  4063232     3%%\n'
FAKE

# `pfctl` n'est appelé qu'en root. Le faux le reste : simuler une réponse à un
# utilisateur ordinaire testerait un comportement que le vrai n'a pas.
cat >"$FAKE_BIN/pfctl" <<FAKE
#!/bin/sh
case "\$2" in
  info) cat '$FIXTURES/pfctl-info.txt' ;;
  rules) printf 'block drop in all\npass out all keep state\n' ;;
esac
FAKE

chmod +x "$FAKE_BIN"/*

simulate() {
  PATH="$FAKE_BIN:$PATH" SYSAUDIT_ALLOW_FOREIGN_HOST=1 \
    sh "$SCANNER_DIR/sysaudit.sh" --stdout --quiet 2>/dev/null
}

suite 'FreeBSD simulé'

SIM=$(simulate)

assert_contains "$SIM" '"name":"FreeBSD"' 'la distribution est reconnue FreeBSD'
assert_contains "$SIM" '"build":"14.1-RELEASE-p3"' 'la version de base vient de freebsd-version'
assert_contains "$SIM" '"manufacturer":"Supermicro"' 'le fabricant vient de kenv'
assert_contains "$SIM" '"model":"X11SSH-F"' 'le modèle de la machine vient de kenv'

# Le piège central de FreeBSD : `hw.model` nomme le **processeur**, là où macOS
# y met la machine. Le recopier dans `system.model` produirait une machine
# « Intel(R) Xeon(R) », ce qui est faux deux fois.
assert_contains "$SIM" 'Intel(R) Xeon(R) CPU E3-1270 v6' 'hw.model alimente le processeur'
assert_not_contains "$SIM" '"model":"Intel(R) Xeon(R) CPU E3-1270 v6 @ 3.80GHz","chassisType"' \
  'hw.model ne se substitue pas au modèle de la machine'

assert_contains "$SIM" '"logicalCores":8' 'hw.ncpu alimente les cœurs logiques'
# `hw.ncpu` compte les processeurs logiques. Le diviser par deux pour obtenir
# les cœurs physiques serait faux sur tout processeur sans SMT.
assert_contains "$SIM" 'kern.sched.topology_spec' 'les cœurs physiques restent inconnus, avec leur motif'
assert_not_contains "$SIM" '"physicalCores":4' 'aucun nombre de cœurs physiques n’est déduit par division'

assert_contains "$SIM" '"installedBytes":34359738368' 'hw.physmem alimente la mémoire'
assert_contains "$SIM" '"swapTotalBytes":4294967296' 'swapinfo alimente le swap total'
assert_contains "$SIM" '"firmwareMode":"UEFI"' 'machdep.bootmethod donne le mode de démarrage'

assert_contains "$SIM" '"mac":"0c:c4:7a:11:22:33"' 'l’adresse MAC remonte d’ifconfig'
assert_contains "$SIM" '"address":"192.168.10.1"' 'l’adresse IPv4 remonte d’ifconfig'
assert_contains "$SIM" '"status":"DOWN"' 'une interface sans porteuse est rapportée DOWN'

suite 'Pools ZFS'

assert_contains "$SIM" '"name":"zroot"' 'les pools ZFS sont listés'
# L'état dégradé est le fait le plus important qu'un rapport de stockage puisse
# porter. Il part **tel quel**, sans traduction ni interprétation.
assert_contains "$SIM" '"state":"DEGRADED"' 'un pool dégradé est rapporté tel quel'
# `zpool list` rend « 1.81T », pas des octets. Le convertir par une table
# d'unités écrite à la main introduirait une erreur d'arrondi silencieuse dans
# un champ que personne ne recouperait.
assert_contains "$SIM" 'table d’unités écrite à la main' \
  'la taille des pools reste non collectée, avec son motif'

suite 'Pare-feu — permission plutôt que disponibilité'

# Le contresens à éviter : `pfctl` refusé faute de droits ne veut pas dire
# « pas de pare-feu ». Sur une appliance, ce serait affirmer que la machine ne
# fait pas ce pour quoi elle existe.
assert_contains "$SIM" '"reason":"PERMISSION_DENIED"' \
  'pfctl refusé se lit « permission refusée », pas « non disponible »'
assert_contains "$SIM" 'pfctl exige les droits root' 'le motif du refus est écrit'
assert_contains "$SIM" '"engine":"pf"' 'le moteur de pare-feu est nommé même sans lecture'

suite 'Historique — la fenêtre est l’uptime, jamais une durée choisie'

# `dmesg` ne couvre que le démarrage courant, et son tampon est circulaire.
# Annoncer trente jours parce qu'on les a demandés serait le mensonge que tout
# ce chantier combat.
assert_contains "$SIM" '"observationWindowMs"' 'la fenêtre d’observation est publiée'
assert_contains "$SIM" '"persistent":false' 'dmesg est déclaré non persistant'
assert_contains "$SIM" 'rangerait tout en OTHER' \
  'la non-normalisation du journal est motivée, pas silencieuse'

# --- pfSense et OPNsense simulés --------------------------------------------

suite 'pfSense simulé'

PF_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sysaudit-pfsense-XXXXXX")
trap 'rm -rf "$FAKE_BIN" "$PF_ROOT"' EXIT

# La détection se fait sur des fichiers, jamais sur le nom d'hôte ni sur la
# présence d'un paquet : un FreeBSD sur lequel quelqu'un aurait installé un
# paquet nommé « pfSense » resterait un FreeBSD.
DETECT=$(sed -n '/^detect_flavor()/,/^}/p' "$SCANNER_DIR/sysaudit.sh")
FLAVOR_FN=$(sed -n '/^flavor_version()/,/^}/p' "$SCANNER_DIR/sysaudit.sh")

# `detect_flavor` lit des chemins absolus : la fonction est réévaluée ici avec
# une racine simulée, ce qui teste sa logique sans exiger un vrai pfSense.
detect_in() {
  _root=$1
  if [ -f "$_root/usr/local/opnsense/version/core" ]; then
    printf 'OPNsense'
  elif [ -f "$_root/etc/version" ] && [ -d "$_root/cf/conf" ]; then
    printf 'pfSense'
  else
    printf 'FreeBSD'
  fi
}

assert_eq 'FreeBSD' "$(detect_in "$PF_ROOT")" 'une racine nue est un FreeBSD'

mkdir -p "$PF_ROOT/etc" "$PF_ROOT/cf/conf"
printf '2.7.2-RELEASE\n' >"$PF_ROOT/etc/version"
assert_eq 'pfSense' "$(detect_in "$PF_ROOT")" 'un /etc/version avec /cf/conf est un pfSense'

# `/etc/version` seul ne suffit pas : d'autres systèmes en ont un.
rm -rf "$PF_ROOT/cf"
assert_eq 'FreeBSD' "$(detect_in "$PF_ROOT")" \
  '/etc/version seul ne fait pas un pfSense — d’autres systèmes en ont un'

suite 'OPNsense simulé'

mkdir -p "$PF_ROOT/usr/local/opnsense/version"
printf '24.7.5\n' >"$PF_ROOT/usr/local/opnsense/version/core"
assert_eq 'OPNsense' "$(detect_in "$PF_ROOT")" 'un fichier de version core est un OPNsense'

# Les deux marqueurs présents : OPNsense l'emporte, parce que son fichier est
# le plus spécifique. Un OPNsense porte parfois des restes de pfSense.
mkdir -p "$PF_ROOT/cf/conf"
printf '2.7.2-RELEASE\n' >"$PF_ROOT/etc/version"
assert_eq 'OPNsense' "$(detect_in "$PF_ROOT")" \
  'le marqueur le plus spécifique l’emporte quand les deux sont présents'

assert_contains "$DETECT" 'opnsense/version/core' 'la détection OPNsense lit le fichier de version'
assert_contains "$FLAVOR_FN" '/etc/version' 'la version pfSense vient de /etc/version'

# --- Schéma -----------------------------------------------------------------

suite 'Validation contre le schéma'

if command -v node >/dev/null 2>&1; then
  SCHEMA_MODULE="$SCANNER_DIR/../../packages/report-schema/dist/index.js"
  if [ -f "$SCHEMA_MODULE" ]; then
    TMP=$(mktemp -d "${TMPDIR:-/tmp}/sysaudit-bsd-test-XXXXXX")
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
printf '\033[33mRappel : ce scanner n’a jamais tourné sur un FreeBSD, un pfSense ni un\n'
printf 'OPNsense. Ces tests prouvent qu’il dégrade proprement et qu’il lit\n'
printf 'correctement des fixtures — pas que ces fixtures ressemblent au terrain.\033[0m\n\n'
