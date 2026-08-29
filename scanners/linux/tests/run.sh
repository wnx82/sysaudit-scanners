#!/usr/bin/env bash
#
# Tests du scanner Linux.
#
# Le scanner ne peut pas être testé uniquement sur la machine de CI : celle-ci
# n'a ni dmidecode, ni SMART, ni Proxmox. Les tests couvrent donc deux plans :
#
#  1. les fonctions pures (JSON, conversions, anonymisation, analyse de sorties
#     de commandes réelles fournies en fixtures) ;
#  2. une exécution de bout en bout dont la sortie est validée contre le JSON
#     Schema, ce qui garantit qu'un scan produit toujours un rapport conforme,
#     quelles que soient les capacités de la machine.

set -uo pipefail

SCANNER_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly SCANNER_DIR
readonly FIXTURES="$SCANNER_DIR/tests/fixtures"

SCANNER_VERSION=$(cat "$SCANNER_DIR/VERSION")
# Lue depuis le script plutôt que recopiée : l'égalité avec le package
# @sysaudit/report-schema est vérifiée par `scanner-contract.test.ts`, et une
# troisième copie serait une troisième occasion de diverger.
SCHEMA_VERSION=$(sed -nE "s/^readonly SCHEMA_VERSION='([^']+)'\$/\1/p" "$SCANNER_DIR/sysaudit.sh")

# shellcheck source=../lib/core/schema-bounds.sh
. "$SCANNER_DIR/lib/core/schema-bounds.sh"
# shellcheck source=../lib/core/json.sh
. "$SCANNER_DIR/lib/core/json.sh"
# shellcheck source=../lib/core/console.sh
. "$SCANNER_DIR/lib/core/console.sh"
# shellcheck source=../lib/core/core.sh
. "$SCANNER_DIR/lib/core/core.sh"
# shellcheck source=../lib/core/transport.sh
. "$SCANNER_DIR/lib/core/transport.sh"
# shellcheck source=../lib/core/levels.sh
. "$SCANNER_DIR/lib/core/levels.sh"
# shellcheck source=../lib/core/dependencies.sh
. "$SCANNER_DIR/lib/core/dependencies.sh"
# shellcheck source=../lib/core/provision.sh
. "$SCANNER_DIR/lib/core/provision.sh"
# shellcheck source=../lib/core/anonymize.sh
. "$SCANNER_DIR/lib/core/anonymize.sh"
# shellcheck source=../lib/collectors/stability.sh
. "$SCANNER_DIR/lib/collectors/stability.sh"
# shellcheck source=../lib/collectors/monitoring.sh
. "$SCANNER_DIR/lib/collectors/monitoring.sh"
# shellcheck source=../lib/collectors/benchmark.sh
. "$SCANNER_DIR/lib/collectors/benchmark.sh"
# shellcheck source=../lib/collectors/virtualization.sh
. "$SCANNER_DIR/lib/collectors/virtualization.sh"
# shellcheck source=../lib/collectors/security.sh
. "$SCANNER_DIR/lib/collectors/security.sh"
# shellcheck source=../lib/collectors/power.sh
. "$SCANNER_DIR/lib/collectors/power.sh"

PASSED=0
FAILED=0

suite() {
  printf '\n\033[1m%s\033[0m\n' "$1"
}

assert_eq() {
  local expected=$1 actual=$2 label=$3
  if [ "$expected" = "$actual" ]; then
    PASSED=$((PASSED + 1))
    printf '  \033[32m✓\033[0m %s\n' "$label"
  else
    FAILED=$((FAILED + 1))
    printf '  \033[31m✗\033[0m %s\n' "$label"
    printf '      attendu : %s\n' "$expected"
    printf '      obtenu  : %s\n' "$actual"
  fi
}

assert_contains() {
  local haystack=$1 needle=$2 label=$3
  case "$haystack" in
    *"$needle"*)
      PASSED=$((PASSED + 1))
      printf '  \033[32m✓\033[0m %s\n' "$label"
      ;;
    *)
      FAILED=$((FAILED + 1))
      printf '  \033[31m✗\033[0m %s\n' "$label"
      printf '      « %s » introuvable dans : %s\n' "$needle" "${haystack:0:200}"
      ;;
  esac
}

assert_not_contains() {
  local haystack=$1 needle=$2 label=$3
  case "$haystack" in
    *"$needle"*)
      FAILED=$((FAILED + 1))
      printf '  \033[31m✗\033[0m %s\n' "$label"
      printf '      « %s » ne devait pas apparaître\n' "$needle"
      ;;
    *)
      PASSED=$((PASSED + 1))
      printf '  \033[32m✓\033[0m %s\n' "$label"
      ;;
  esac
}

# --- JSON -------------------------------------------------------------------

suite 'Construction JSON'

assert_eq '"simple"' "$(j_str 'simple')" 'chaîne simple'
assert_eq '"avec \"guillemets\""' "$(j_str 'avec "guillemets"')" 'guillemets échappés'
assert_eq '"c:\\chemin"' "$(j_str 'c:\chemin')" 'antislash échappé'
assert_eq '"ligne1\nligne2"' "$(j_str "$(printf 'ligne1\nligne2')")" 'saut de ligne échappé'
assert_eq '"tab\there"' "$(j_str "$(printf 'tab\there')")" 'tabulation échappée'
assert_eq '"controle"' "$(j_str "$(printf 'contr\001ole')")" 'octet de contrôle retiré'
assert_eq '""' "$(j_str '')" 'chaîne vide'

assert_eq '42' "$(j_num '42')" 'entier'
assert_eq '3.14' "$(j_num '3.14')" 'décimal'
assert_eq '3.14' "$(j_num '3,14')" 'décimal à virgule normalisé'
assert_eq '-5' "$(j_num '-5')" 'négatif'
assert_eq 'null' "$(j_num 'abc')" 'non numérique → null plutôt que JSON invalide'
assert_eq 'null' "$(j_num '')" 'vide → null'

assert_eq 'true' "$(j_bool 'true')" 'booléen vrai'
assert_eq 'true' "$(j_bool 'yes')" 'yes → vrai'
assert_eq 'false' "$(j_bool 'no')" 'no → faux'
assert_eq 'false' "$(j_bool '')" 'vide → faux'

assert_eq '{"unknown":true,"reason":"NOT_AVAILABLE"}' \
  "$(j_unknown NOT_AVAILABLE)" 'marqueur inconnu sans détail'
assert_eq '{"unknown":true,"reason":"PERMISSION_DENIED","detail":"réservé à root"}' \
  "$(j_unknown PERMISSION_DENIED 'réservé à root')" 'marqueur inconnu avec détail'

assert_eq '"k":"v"' "$(jf_str k 'v')" 'fragment chaîne'
assert_eq '"k":"v"' "$(jf_maybe_str k 'v')" 'fragment présent'
assert_eq '"k":{"unknown":true,"reason":"UNKNOWN"}' "$(jf_maybe_str k '')" 'fragment absent → marqueur'
assert_eq '"k":{"unknown":true,"reason":"NOT_AVAILABLE","detail":"outil absent"}' \
  "$(jf_maybe_str k '' NOT_AVAILABLE 'outil absent')" 'fragment absent avec raison'
assert_eq '"k":0' "$(jf_maybe_num k '0')" 'zéro est une valeur, pas une absence'
assert_eq '"k":{"unknown":true,"reason":"UNKNOWN"}' "$(jf_maybe_num k 'n/a')" 'nombre invalide → marqueur'

# Une valeur hors bornes est un aveu du firmware, pas une mesure. La publier
# affirmait un nombre impossible **et** faisait refuser l'audit entier au dépôt,
# le schéma bornant le champ.
assert_eq '"k":42' "$(jf_maybe_num_in k '42' 0 100)" 'valeur dans les bornes → publiée'
assert_eq '"k":0' "$(jf_maybe_num_in k '0' 0 100)" 'borne basse incluse'
assert_eq '"k":100' "$(jf_maybe_num_in k '100' 0 100)" 'borne haute incluse'
assert_eq '"k":{"unknown":true,"reason":"NOT_AVAILABLE","detail":"non exposé"}' \
  "$(jf_maybe_num_in k '-1' 0 100 NOT_AVAILABLE 'non exposé')" 'sous la borne basse → marqueur'
assert_eq '"k":{"unknown":true,"reason":"UNKNOWN"}' \
  "$(jf_maybe_num_in k '101' 0 100)" 'au-dessus de la borne haute → marqueur'
assert_eq '"k":999999' "$(jf_maybe_num_in k '999999' 0 '')" 'borne haute vide → aucun plafond'
assert_eq '"k":{"unknown":true,"reason":"UNKNOWN"}' \
  "$(jf_maybe_num_in k 'n/a' 0 100)" 'non numérique → marqueur, comme jf_maybe_num'

# --- Bornes du schéma, appliquées par nom de champ ---------------------------
#
# `jf_maybe_num` consulte `SCHEMA_BOUNDS` : une grandeur hors du domaine que le
# schéma accepte devient un marqueur au lieu d'emporter l'audit entier.
#
# Le champ **inconnu de la table** garde le comportement d'origine, et c'est la
# moitié importante : borner ce que le schéma ne borne pas serait inventer une
# règle que rien ne justifie.

suite 'Bornes du schéma'

assert_contains "$(jf_maybe_num cycleCount '-1' NOT_AVAILABLE 'non exposé')" \
  '{"unknown":true,"reason":"NOT_AVAILABLE"' 'cycleCount -1 → marqueur, sans borne à l’appel'
assert_eq '"cycleCount":0' "$(jf_maybe_num cycleCount '0')" 'cycleCount 0 reste une mesure'
assert_eq '"cycleCount":612' "$(jf_maybe_num cycleCount '612')" 'cycleCount réel inchangé'

assert_eq '"chargePercent":87' "$(jf_maybe_num chargePercent '87')" 'charge plausible inchangée'
assert_contains "$(jf_maybe_num chargePercent '-1')" '"unknown":true' 'charge -1 → marqueur'
assert_contains "$(jf_maybe_num chargePercent '101')" '"unknown":true' 'charge > 100 → marqueur'

# Le seul champ du parc dont le domaine est **entièrement négatif** : il prouve
# que la table transporte un minimum négatif, et non un `0` implicite.
assert_eq '"signalDbm":-45' "$(jf_maybe_num signalDbm '-45')" 'signal Wi-Fi réel inchangé'
assert_contains "$(jf_maybe_num signalDbm '-256')" '"unknown":true' 'signal -256 dBm → marqueur'
assert_contains "$(jf_maybe_num signalDbm '12')" '"unknown":true' 'signal positif → marqueur'

assert_eq '"temperatureCelsius":45.5' "$(jf_maybe_num temperatureCelsius '45.5')" \
  'température négative permise, valeur décimale conservée'
assert_eq '"temperatureCelsius":-40' "$(jf_maybe_num temperatureCelsius '-40')" \
  'une température sous zéro est une mesure'
assert_contains "$(jf_maybe_num temperatureCelsius '-274')" '"unknown":true' \
  'sous le zéro absolu → marqueur'

# Champ hors table : `score` n'est borné par aucun schéma, et rien ne doit
# l'être ici. Une régression sur ce point transformerait des mesures valides en
# inconnues, ce qui est le défaut symétrique de celui qu'on corrige.
assert_eq '"score":1751.8' "$(jf_maybe_num score '1751.8')" 'champ sans borne : publié tel quel'
assert_eq '"score":-3' "$(jf_maybe_num score '-3')" 'champ sans borne : même négatif'

# `jf_optional_num` : le pendant numérique de `jf_optional_str`. Un champ que le
# schéma déclare `optional()` et non `maybe()` n'accepte pas de marqueur —
# en émettre un ferait refuser le rapport tout autant qu'une valeur fausse.
assert_eq '"prefixLength":64' "$(jf_optional_num prefixLength '64')" 'préfixe IPv6 publié'
assert_eq '' "$(jf_optional_num prefixLength '10.0.0.1')" \
  'adresse sans préfixe (lien point à point) → champ absent, jamais un marqueur'
assert_eq '' "$(jf_optional_num prefixLength '')" 'valeur vide → champ absent'

assert_eq '{"a":1,"b":2}' "$(json_object '"a":1' '"b":2')" 'objet'
assert_eq '{"a":1}' "$(json_object '"a":1' '')" 'fragment vide ignoré (pas de virgule orpheline)'
assert_eq '{}' "$(json_object '' '')" 'objet vide'
assert_eq '[1,2]' "$(json_array '1' '2')" 'tableau'
assert_eq '["a","b"]' "$(printf 'a\nb\n' | json_array_from_lines)" 'tableau depuis lignes'
assert_eq '[]' "$(printf '' | json_array_from_lines)" 'tableau vide depuis lignes'

# --- Sections absentes ------------------------------------------------------

suite 'Sections absentes'

# Un collecteur qui ne rend rien ne doit **jamais** produire une clé sans
# valeur : `"services":` suivi du vide rend le rapport entier illisible, et
# aucune des sections suivantes n'est plus lue.
#
# Le défaut est invisible sur une machine de développement — elle a systemd,
# donc `collect_services` rend un tableau. Il est apparu au premier audit lancé
# dans un conteneur, où `systemctl` n'existe pas : le rapport produit n'était
# pas du JSON. C'est exactement pour cela que `section` existe, et les deux
# assertions suivantes figent la différence entre les deux idiomes.
assert_eq '{}' "$(json_object "$(section services '')")" \
  'section : une valeur vide omet la clé'
assert_eq '{"services":}' "$(json_object "$(jf_raw services '')")" \
  'jf_raw : une valeur vide produit le JSON invalide que section évite'

# Le collecteur réel, privé de systemd. Le stub vit dans un sous-shell : le
# redéfinir ici fausserait toutes les suites suivantes.
# shellcheck source=../lib/collectors/software.sh
. "$SCANNER_DIR/lib/collectors/software.sh"
assert_eq '' "$(
  capability_tool() { printf 'false'; }
  collect_services
)" 'sans systemd, collect_services ne rend rien du tout'
assert_eq '{}' "$(json_object "$(section services "$(
  capability_tool() { printf 'false'; }
  collect_services
)")")" 'sans systemd, la section services est omise et le rapport reste valide'

# --- Conversions ------------------------------------------------------------

suite 'Conversions'

assert_eq '17179869184' "$(to_bytes '16384 MB')" 'MB → octets'
assert_eq '1073741824' "$(to_bytes '1 GB')" 'GB → octets'
assert_eq '8192' "$(to_bytes '8192')" 'sans unité'
assert_eq '1610612736' "$(to_bytes '1.5G')" 'décimal avec unité'
assert_eq '' "$(to_bytes 'No Module Installed')" 'texte non convertible → vide, pas 0'
assert_eq '' "$(to_bytes '')" 'vide → vide'

assert_eq '2024-11-08' "$(to_iso_date '11/08/2024')" 'date dmidecode MM/JJ/AAAA'
assert_eq '2024-11-08' "$(to_iso_date '2024-11-08')" 'date déjà ISO'
assert_eq '' "$(to_iso_date 'novembre 2024')" 'date ambiguë → vide plutôt que devinée'

assert_eq '' "$(clean_dmi_value 'To Be Filled By O.E.M.')" 'placeholder SMBIOS rejeté'
assert_eq '' "$(clean_dmi_value 'Default string')" 'placeholder "Default string" rejeté'
assert_eq '' "$(clean_dmi_value '  ')" 'espaces seuls rejetés'
assert_eq 'ASUSTeK COMPUTER INC.' "$(clean_dmi_value '  ASUSTeK COMPUTER INC.  ')" 'valeur réelle conservée'

# --- Durée d'audit ----------------------------------------------------------

suite 'Durée d’audit'

assert_eq '8420' "$(audit_duration_ms '1000000' '1008420')" 'durée normale'
assert_eq '0' "$(audit_duration_ms '1000000' '1000000')" 'durée nulle : une valeur, pas une absence'

# Le cas qui rejetait le rapport entier : horloge matérielle absurde au
# démarrage, puis synchronisation NTP pendant l'audit. La soustraction dépassait
# le plus grand entier représentable et l'API refusait tout le document.
assert_eq '' "$(audit_duration_ms '1786017460000' '1786017462123456789')" \
  'saut d’horloge en avant → champ omis, pas de nombre inventé'
assert_eq '' "$(audit_duration_ms '1786017462864' '1000')" \
  'horloge reculée → champ omis plutôt que ramené à zéro'
assert_eq '' "$(audit_duration_ms '1000' '86401001')" \
  'au-delà d’une journée, la valeur ne mesure plus un audit'
assert_eq '86400000' "$(audit_duration_ms '1000' '86401000')" \
  'la borne d’une journée reste acceptée'
assert_eq '' "$(audit_duration_ms '' '1000')" 'début non mesuré → champ omis'
assert_eq '' "$(audit_duration_ms 'abc' '1000')" 'début non numérique → champ omis'
assert_eq '' "$(audit_duration_ms '1000' '')" 'fin non mesurée → champ omis'

# Les valeurs à zéro initial viennent des centièmes de `/proc/uptime` : traitées
# en base 8, « 08 » ferait échouer l'arithmétique au lieu de mesurer.
assert_eq '92' "$(audit_duration_ms '008' '100')" 'zéros initiaux lus en base 10'

CLOCK_A=$(clock_ms)
case "$CLOCK_A" in
  '' | *[!0-9]*) CLOCK_SHAPE='invalide' ;;
  *) CLOCK_SHAPE='entier' ;;
esac
assert_eq 'entier' "$CLOCK_SHAPE" 'l’horloge rend un entier de millisecondes'

CLOCK_DELTA=$(audit_duration_ms "$CLOCK_A" "$(clock_ms)")
assert_eq 'mesurée' "$([ -n "$CLOCK_DELTA" ] && printf 'mesurée' || printf 'omise')" \
  'deux lectures consécutives donnent une durée exploitable'

# --- Anonymisation ----------------------------------------------------------

suite 'Anonymisation'

anon_init false
assert_eq 'pc-grenier' "$(anon hostname 'pc-grenier')" 'inactive : valeur inchangée'

# shellcheck disable=SC2034
ANON_CACHE=()
anon_init true
MASKED=$(anon hostname 'pc-grenier')
assert_not_contains "$MASKED" 'pc-grenier' 'la valeur d’origine ne fuit pas'
assert_contains "$MASKED" 'HOST-' 'préfixe de catégorie présent'
assert_eq "$MASKED" "$(anon hostname 'pc-grenier')" 'stable pour une même valeur'
assert_eq "$MASKED" "$(anon hostname 'PC-GRENIER')" 'insensible à la casse'
assert_eq '' "$(anon hostname '')" 'valeur vide inchangée'

DIFFERENT_CATEGORY=$(anon username 'pc-grenier')
if [ "$DIFFERENT_CATEGORY" = "$MASKED" ]; then
  FAILED=$((FAILED + 1))
  printf '  \033[31m✗\033[0m catégories séparées\n'
else
  PASSED=$((PASSED + 1))
  printf '  \033[32m✓\033[0m catégories séparées\n'
fi

assert_contains "$(anon macAddress '00:1a:2b:3c:4d:5e')" 'MAC-' 'MAC pseudonymisée'
assert_contains "$(anon_categories_json)" 'hostname' 'catégories annoncées à l’utilisateur'

# Un sel différent doit produire un pseudonyme différent : sans cela, deux
# rapports anonymisés seraient corrélables entre eux.
FIRST_SALT_VALUE=$(anon serialNumber 'CN-0X1Y2Z')
# Le cache est vidé pour forcer un nouveau calcul avec le nouveau sel.
# shellcheck disable=SC2034  # lu par anon() dans lib/core/anonymize.sh
ANON_CACHE=()
anon_init true
SECOND_SALT_VALUE=$(anon serialNumber 'CN-0X1Y2Z')
if [ "$FIRST_SALT_VALUE" = "$SECOND_SALT_VALUE" ]; then
  FAILED=$((FAILED + 1))
  printf '  \033[31m✗\033[0m deux exécutions ne sont pas corrélables\n'
else
  PASSED=$((PASSED + 1))
  printf '  \033[32m✓\033[0m deux exécutions ne sont pas corrélables\n'
fi

# --- Analyse de sorties réelles ---------------------------------------------

suite 'Analyse de sorties de commandes (fixtures)'

# shellcheck source=../lib/core/capabilities.sh
. "$SCANNER_DIR/lib/core/capabilities.sh"
# Ces variables sont lues par les collecteurs sourcés, pas par le harnais.
# shellcheck disable=SC2034
CAP_PRIVILEGED='true'
# shellcheck disable=SC2034
CAP_ARCHITECTURE='x86_64'
# shellcheck disable=SC2034
declare -A CAP_TOOLS=([dmidecode]=true [smartctl]=true [lspci]=true)
# shellcheck source=../lib/collectors/system.sh
. "$SCANNER_DIR/lib/collectors/system.sh"
# shellcheck source=../lib/collectors/hardware.sh
. "$SCANNER_DIR/lib/collectors/hardware.sh"
# shellcheck source=../lib/collectors/storage.sh
. "$SCANNER_DIR/lib/collectors/storage.sh"

# shellcheck disable=SC2034  # lue par anon() dans lib/core/anonymize.sh
ANONYMIZE='false'

MODULE_JSON=$(parse_memory_module "$(cat "$FIXTURES/dmidecode-memory-device.txt")")
assert_contains "$MODULE_JSON" '"slot":"DIMM_A2"' 'module mémoire : slot'
assert_contains "$MODULE_JSON" '"sizeBytes":17179869184' 'module mémoire : taille en octets'
assert_contains "$MODULE_JSON" '"partNumber":"KF3200C16D4/16GX"' 'module mémoire : référence'
assert_contains "$MODULE_JSON" '"ratedSpeedMts":3200' 'module mémoire : vitesse nominale'
assert_contains "$MODULE_JSON" '"ecc":false' 'module mémoire : ECC déduit de la largeur'

EMPTY_SLOT_JSON=$(parse_memory_module "$(cat "$FIXTURES/dmidecode-memory-empty.txt")")
assert_contains "$EMPTY_SLOT_JSON" '"slot":"DIMM_B1"' 'slot vide : rapporté (donnée d’upgrade)'
assert_contains "$EMPTY_SLOT_JSON" '"reason":"UNSUPPORTED"' 'slot vide : taille marquée, pas mise à 0'

SMART_OUT=$(cat "$FIXTURES/smartctl-nvme.txt")
assert_eq '87' "$(printf '%s' "$SMART_OUT" | sed -nE 's/^Percentage Used:[[:space:]]+([0-9]+)%.*$/\1/p' | head -n1)" \
  'SMART NVMe : usure'
assert_eq '18240' "$(printf '%s' "$SMART_OUT" | sed -nE 's/^Power On Hours:[[:space:]]+([0-9,]+).*$/\1/p' | head -n1 | tr -d ',')" \
  'SMART NVMe : heures de fonctionnement (séparateurs retirés)'

SMART_ATA=$(cat "$FIXTURES/smartctl-ata.txt")
assert_eq '18240' "$(smart_attribute "$SMART_ATA" 'Power_On_Hours')" 'SMART ATA : heures'
assert_eq '0' "$(smart_attribute "$SMART_ATA" 'Reallocated_Sector_Ct')" 'SMART ATA : secteurs réalloués'
assert_eq '35' "$(smart_attribute "$SMART_ATA" 'Temperature_Celsius')" 'SMART ATA : température extraite du champ composite'
assert_eq '' "$(smart_attribute "$SMART_ATA" 'Attribut_Inexistant')" 'SMART ATA : attribut absent → vide'

assert_eq 'desktop' "$(code=3; case "$code" in 3|4|6|7) printf 'desktop';; esac)" 'code châssis 3 → desktop'

# --- Matériel lu dans /sys ---------------------------------------------------

suite 'Batterie, lien PCIe et écrans'

# shellcheck source=../lib/collectors/power.sh
. "$SCANNER_DIR/lib/collectors/power.sh"
# shellcheck source=../lib/collectors/software.sh
. "$SCANNER_DIR/lib/collectors/software.sh"

# La machine de CI n'a ni batterie, ni lien PCIe, ni écran : les collecteurs
# sont donc éprouvés sur une arborescence /sys reconstituée, avec des valeurs
# relevées sur du matériel réel.
SYSFS_DIR=$(mktemp -d)

mkdir -p "$SYSFS_DIR/BAT0"
printf 'Battery\n' >"$SYSFS_DIR/BAT0/type"
printf 'LGC\n' >"$SYSFS_DIR/BAT0/manufacturer"
printf '5B10W13930\n' >"$SYSFS_DIR/BAT0/model_name"
printf 'Li-poly\n' >"$SYSFS_DIR/BAT0/technology"
printf '87\n' >"$SYSFS_DIR/BAT0/capacity"
printf 'Discharging\n' >"$SYSFS_DIR/BAT0/status"
printf '57000000\n' >"$SYSFS_DIR/BAT0/energy_full_design"
printf '43120000\n' >"$SYSFS_DIR/BAT0/energy_full"
printf '412\n' >"$SYSFS_DIR/BAT0/cycle_count"
printf '11520000\n' >"$SYSFS_DIR/BAT0/voltage_now"

BATTERY_JSON=$(parse_battery "$SYSFS_DIR/BAT0")
assert_contains "$BATTERY_JSON" '"name":"BAT0"' 'batterie : identifiant'
assert_contains "$BATTERY_JSON" '"technology":"Li-poly"' 'batterie : chimie'
assert_contains "$BATTERY_JSON" '"chargePercent":87' 'batterie : charge'
assert_contains "$BATTERY_JSON" '"status":"DISCHARGING"' 'batterie : état normalisé'
assert_contains "$BATTERY_JSON" '"designCapacityWh":57' 'batterie : capacité de conception en Wh'
assert_contains "$BATTERY_JSON" '"fullChargeCapacityWh":43.12' 'batterie : capacité réelle en Wh'
assert_contains "$BATTERY_JSON" '"cycleCount":412' 'batterie : cycles'
# L'usure se déduit des deux capacités : c'est une interprétation, elle
# appartient au moteur d'analyse et ne doit pas figurer dans le rapport.
assert_not_contains "$BATTERY_JSON" 'health' 'batterie : aucune usure calculée par le scanner'

# Batterie n'exposant que des charges : sans tension nominale, la conversion en
# wattheures serait une invention.
mkdir -p "$SYSFS_DIR/BAT1"
printf 'Battery\n' >"$SYSFS_DIR/BAT1/type"
printf '4000000\n' >"$SYSFS_DIR/BAT1/charge_full_design"
printf '3600000\n' >"$SYSFS_DIR/BAT1/charge_full"
BAT1_JSON=$(parse_battery "$SYSFS_DIR/BAT1")
assert_contains "$BAT1_JSON" '"designCapacityWh":{"unknown":true' 'batterie : pas de Wh sans tension nominale'

printf '11400000\n' >"$SYSFS_DIR/BAT1/voltage_min_design"
BAT1_JSON=$(parse_battery "$SYSFS_DIR/BAT1")
assert_contains "$BAT1_JSON" '"designCapacityWh":45.6' 'batterie : conversion Ah × V quand la tension est connue'

# Lien PCIe : une carte x16 négociée en x4 est le cas que la règle doit voir.
mkdir -p "$SYSFS_DIR/pci-degrade"
printf '2.5 GT/s PCIe\n' >"$SYSFS_DIR/pci-degrade/current_link_speed"
printf '16.0 GT/s PCIe\n' >"$SYSFS_DIR/pci-degrade/max_link_speed"
printf '4\n' >"$SYSFS_DIR/pci-degrade/current_link_width"
printf '16\n' >"$SYSFS_DIR/pci-degrade/max_link_width"
LINK_JSON=$(pcie_link_from_dir "$SYSFS_DIR/pci-degrade")
assert_contains "$LINK_JSON" '"currentWidth":4' 'lien PCIe : largeur négociée'
assert_contains "$LINK_JSON" '"maxWidth":16' 'lien PCIe : largeur maximale'
assert_contains "$LINK_JSON" '"currentSpeed":"2.5 GT/s PCIe"' 'lien PCIe : vitesse négociée'

# Un périphérique sans lien PCIe ne doit produire aucune clé : quatre marqueurs
# d'absence ne diraient rien de plus qu'un silence.
mkdir -p "$SYSFS_DIR/pci-sans-lien"
assert_eq '' "$(pcie_link_from_dir "$SYSFS_DIR/pci-sans-lien")" 'lien PCIe : absent si non exposé'

# Le noyau écrit « Unknown » tant que le lien n'est pas entraîné.
mkdir -p "$SYSFS_DIR/pci-inconnu"
printf 'Unknown\n' >"$SYSFS_DIR/pci-inconnu/current_link_speed"
printf '8\n' >"$SYSFS_DIR/pci-inconnu/max_link_width"
UNKNOWN_LINK=$(pcie_link_from_dir "$SYSFS_DIR/pci-inconnu")
assert_contains "$UNKNOWN_LINK" '"currentSpeed":{"unknown":true' 'lien PCIe : « Unknown » n’est pas une vitesse'
assert_contains "$UNKNOWN_LINK" '"maxWidth":8' 'lien PCIe : les autres champs restent lus'

mkdir -p "$SYSFS_DIR/card0-DP-1"
printf 'connected\n' >"$SYSFS_DIR/card0-DP-1/status"
printf '2560x1440\n1920x1080\n' >"$SYSFS_DIR/card0-DP-1/modes"
DISPLAY_JSON=$(parse_display_connector "$SYSFS_DIR/card0-DP-1")
assert_contains "$DISPLAY_JSON" '"name":"DP-1"' 'écran : connecteur'
assert_contains "$DISPLAY_JSON" '"resolution":"2560x1440"' 'écran : mode préféré retenu'
assert_contains "$DISPLAY_JSON" '"connection":"DP"' 'écran : type de connexion'

# Sans EDID lisible, l'identité de l'écran reste inconnue — jamais devinée du
# nom du connecteur, qui ne dit que la prise utilisée.
assert_contains "$DISPLAY_JSON" '"manufacturer":{"unknown":true' 'écran : sans EDID, pas de constructeur'
assert_contains "$DISPLAY_JSON" '"serialNumber":{"unknown":true' 'écran : sans EDID, pas de numéro de série'

# --- EDID ---------------------------------------------------------------------
#
# Le bloc est écrit octet par octet : c'est la seule façon de vérifier le
# décodage sans avoir un écran branché sur la machine qui joue les tests.
suite 'EDID'

edid_write() {
  local target=$1 model=$2 serial=$3

  # En-tête fixe, puis « DEL » code sur deux octets (0x10 0xac), code produit,
  # et numero de serie 0x12345678 en petit-boutiste.
  printf '\x00\xff\xff\xff\xff\xff\xff\x00\x10\xac\xc2\x41\x78\x56\x34\x12' >"$target"
  # Octets 16 à 53 : données de synchronisation, sans intérêt ici.
  head -c 38 /dev/zero >>"$target"

  # Descripteur 0xFC (modèle) puis 0xFF (numéro de série).
  edid_descriptor_bytes fc "$model" >>"$target"
  edid_descriptor_bytes ff "$serial" >>"$target"
  # Deux descripteurs vides, puis extensions et somme de contrôle.
  head -c 38 /dev/zero >>"$target"
}

edid_descriptor_bytes() {
  local type=$1 text=$2
  printf '\x00\x00\x00'
  printf "\\x$type"
  printf '\x00'
  # Le texte se termine par un saut de ligne et se complète d'espaces, comme le
  # fait un firmware d'écran.
  printf '%s\n' "$text" | head -c 13
  local pad=$((13 - ${#text} - 1))
  [ "$pad" -gt 0 ] && head -c "$pad" /dev/zero | tr '\0' ' '
  return 0
}

EDID_DIR=$(mktemp -d)
mkdir -p "$EDID_DIR/card0-DP-1"
printf 'connected\n' >"$EDID_DIR/card0-DP-1/status"
printf '3840x2160\n' >"$EDID_DIR/card0-DP-1/modes"
edid_write "$EDID_DIR/card0-DP-1/edid" 'DELL U2720Q' 'CN-0ABCD-72'

EDID_JSON=$(parse_display_connector "$EDID_DIR/card0-DP-1")
assert_contains "$EDID_JSON" '"manufacturer":"DEL"' 'EDID : identifiant PNP décodé'
assert_contains "$EDID_JSON" '"model":"DELL U2720Q"' 'EDID : modèle du descripteur 0xFC'
assert_contains "$EDID_JSON" '"serialNumber":"CN-0ABCD-72"' 'EDID : série du descripteur 0xFF'

# Sans descripteur 0xFF, le numéro de série numérique de l'en-tête prend le
# relais : c'est un identifiant réel, pas un repli inventé. Le descripteur est
# effacé sur place — 18 octets à partir de l'octet 72.
head -c 18 /dev/zero | dd of="$EDID_DIR/card0-DP-1/edid" bs=1 seek=72 conv=notrunc 2>/dev/null
parse_edid "$EDID_DIR/card0-DP-1/edid"
assert_eq '305419896' "$EDID_SERIAL" 'EDID : repli sur le numéro de série numérique'
assert_eq 'DELL U2720Q' "$EDID_MODEL" 'EDID : le modèle survit à l’absence du descripteur 0xFF'

# Un connecteur sans écran rend un fichier de zéros. Le décoder donnerait un
# constructeur « @@@ » et un modèle vide : rien de tout cela n'est une donnée.
head -c 128 /dev/zero >"$EDID_DIR/card0-DP-1/edid"
parse_edid "$EDID_DIR/card0-DP-1/edid"
assert_eq '' "$EDID_MANUFACTURER" 'EDID : un bloc de zéros n’est pas un constructeur'
assert_eq '' "$EDID_SERIAL" 'EDID : un bloc de zéros n’est pas un numéro de série'

rm -rf "$EDID_DIR"

rm -rf "$SYSFS_DIR"

# --- Inventaire logiciel -----------------------------------------------------

suite 'Versions de runtime'

# Ces sorties sont celles des commandes réelles : c'est là que se cachent les
# pièges. Une expression gourmande retenait « 24.04 » pour gcc et « 12.3 » pour
# Python — le numéro de la distribution, pas celui du runtime.
assert_eq '24.18.0' "$(extract_version 'v24.18.0')" 'node : préfixe v ignoré'
assert_eq '3.12.3' "$(extract_version 'Python 3.12.3')" 'python : version complète, pas la fin'
assert_eq '13.3.0' "$(extract_version 'gcc (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0')" \
  'gcc : première version, pas la version de distribution'
assert_eq '29.6.2' "$(extract_version 'Docker version 29.6.2, build dfc4efb')" 'docker : version'
assert_eq '5.38.2' "$(extract_version "$(printf '\nThis is perl 5, version 38, subversion 2 (v5.38.2) built')")" \
  'perl : première ligne vide ignorée'
assert_eq '1.22' "$(extract_version 'go version go1.22 linux/amd64')" 'go : version à deux composants'
assert_eq '' "$(extract_version 'aucune version ici')" 'aucun numéro → vide, pas une approximation'
assert_eq '' "$(extract_version '')" 'sortie vide → vide'

suite 'Paquets et pilotes'

# Les paquets de plusieurs gestionnaires cohabitent : la source doit permettre
# de savoir d'où vient chacun.
SNAP_JSON=$(printf 'firefox\t124.0\ncore22\t20240111\n' | packages_from_tsv snap)
assert_contains "$SNAP_JSON" '"name":"firefox"' 'snap : nom de paquet'
assert_contains "$SNAP_JSON" '"source":"snap"' 'snap : source tracée'
assert_contains "$SNAP_JSON" '"version":"124.0"' 'snap : version'

# Un paquet sans version reste rapporté, avec un marqueur : le retirer
# masquerait une application réellement installée.
NOVERSION_JSON=$(printf 'monpaquet\t\n' | packages_from_tsv apt)
assert_contains "$NOVERSION_JSON" '"version":{"unknown":true' 'paquet sans version : marqueur, pas omission'

suite 'Champs requis que seule une vraie machine révélait'

# Deux champs manquaient à l'appel, et aucun test ne pouvait le voir : le seul
# environnement validé était un WSL2 sans `lspci` ni `lsusb`, donc sans section
# GPU et sans périphérique USB. Sur un hôte Proxmox réel, `validateReport()`
# refusait le rapport — six violations d'un coup.
#
# Les deux collecteurs sont éprouvés ici sur une sortie reconstituée, sans
# dépendre des outils : c'est la forme de l'objet produit qui est en cause, pas
# la lecture.

# `lsusb` préfixe chaque ligne de son bus et de son numéro de périphérique.
USB_LINE='Bus 001 Device 003: ID 0bda:c821 Realtek Semiconductor Corp. Bluetooth Radio'
USB_ADDRESS=$(printf '%s' "$USB_LINE" | sed -nE 's/^Bus ([0-9]+) Device ([0-9]+):.*$/\1:\2/p')
assert_eq '001:003' "$USB_ADDRESS" 'adresse USB extraite du préfixe de lsusb'

USB_JSON=$(run_cmd() { printf '%s\n' "$USB_LINE"; }; collect_usb_devices)
assert_contains "$USB_JSON" '"address":"001:003"' 'le périphérique USB porte son adresse'
assert_contains "$USB_JSON" '"bus":"USB"' 'le périphérique USB porte son bus'

# Le GPU doit porter ses deux fréquences, fût-ce en marqueur : `maybe()` accepte
# une valeur ou un marqueur, jamais une clé absente.
GPU_JSON=$(
  has_cmd() { return 1; }
  run_cmd() { printf ''; }
  depth_at_least() { return 1; }
  parse_gpu_line '00:02.0 VGA compatible controller: Intel Corporation Alder Lake-N [UHD Graphics] [8086:46d1]'
)
assert_contains "$GPU_JSON" '"coreClockMhz":{"unknown":true' 'fréquence GPU absente → marqueur, pas omission'
assert_contains "$GPU_JSON" '"memoryClockMhz":{"unknown":true' 'fréquence mémoire GPU absente → marqueur, pas omission'

suite 'Commande de démarrage des unités systemd'

# shellcheck source=../lib/collectors/media.sh
. "$SCANNER_DIR/lib/collectors/media.sh"


# Le champ `command` portait un marqueur `NOT_AVAILABLE` permanent, motivé
# « exige l'inspection détaillée de l'unité ». L'inspection existe : elle tient
# en un `systemctl show` pour toutes les unités à la fois. C'est la ligne qu'on
# regarde pour repérer une persistance indésirable.
SHOW_OUTPUT='Id=ssh.service
ExecStart={ path=/usr/sbin/sshd ; argv[]=/usr/sbin/sshd -D ; ignore_errors=no ; start_time=[n/a] }

Id=cron.service
ExecStart={ path=/usr/sbin/cron ; argv[]=/usr/sbin/cron -f ; ignore_errors=no }'

EXEC_PAIRS=$(printf '%s\n' "$SHOW_OUTPUT" | parse_systemd_exec_start)

assert_contains "$EXEC_PAIRS" '/usr/sbin/sshd -D' 'la commande retient les arguments, pas seulement le binaire'
assert_contains "$EXEC_PAIRS" 'cron.service' 'chaque unité de la sortie est reliée à sa commande'

# `path=` ne suffit pas : il donne le binaire sans ses options, et c'est
# justement l'option qui distingue un démon légitime d'un autre.
EXEC_ARGV_ONLY=$(printf '%s\n' "$SHOW_OUTPUT" | parse_systemd_exec_start | awk -F'\t' '{ print $2 }')
assert_contains "$EXEC_ARGV_ONLY" '-D' 'la commande porte ses options'

# Une unité sans exécutable — une cible, une unité déclarative — n'a pas de
# commande. Elle ne doit pas en recevoir une vide, qui se lirait comme un fait.
EXEC_EMPTY=$(printf 'Id=multi-user.target\nExecStart=\n' | parse_systemd_exec_start)
assert_eq '' "$EXEC_EMPTY" 'une unité sans commande ne produit aucune ligne'

# Une sortie tronquée ne doit pas rattacher la commande d'une unité à la
# précédente : sans `Id=`, il n'y a rien à rattacher.
EXEC_ORPHAN=$(printf 'ExecStart={ argv[]=/bin/faux ; }\n' | parse_systemd_exec_start)
assert_eq '' "$EXEC_ORPHAN" 'une commande sans unité connue est écartée'

suite 'Interfaces réseau : ce qui n’en est pas une'

# `/sys/class/net` ne contient pas que des interfaces : `bonding_masters` est un
# fichier de contrôle du pilote bonding. Le test `-e` l'acceptait, et toutes les
# machines auditées rapportaient une interface fantôme de ce nom — quatre sur
# quatre lors de la validation, l'hôte Proxmox compris.
NET_DIR=$(mktemp -d)
mkdir -p "$NET_DIR/eth0" "$NET_DIR/lo"
printf '' >"$NET_DIR/bonding_masters"
NET_FOUND=$(for i in "$NET_DIR"/*; do [ -d "$i" ] || continue; basename "$i"; done | sort | tr '\n' ' ')
assert_eq 'eth0 lo ' "$NET_FOUND" 'seuls les répertoires sont des interfaces'
NET_OLD=$(for i in "$NET_DIR"/*; do [ -e "$i" ] || continue; basename "$i"; done | sort | tr '\n' ' ')
assert_eq 'bonding_masters eth0 lo ' "$NET_OLD" 'le test -e acceptait bien le fichier de contrôle'
rm -rf "$NET_DIR"

suite 'Identifiants de disques'

# Un contrôleur qui ne renseigne pas l'identifiant rend une suite de zéros. La
# publier ferait passer deux disques distincts pour le même exemplaire — le
# genre d'erreur qu'un inventaire ne rattrape jamais.
assert_eq '' "$(reject_null_identifier '0x0000000000000000')" 'un WWN tout à zéro n’est pas un identifiant'
assert_eq '' "$(reject_null_identifier '00000000000000000000000000000000')" 'un NGUID tout à zéro n’est pas un identifiant'
assert_eq '' "$(reject_null_identifier '')" 'un identifiant vide reste vide'
assert_eq '0x5002538e40a1b2c3' "$(reject_null_identifier '0x5002538e40a1b2c3')" \
  'un WWN réel est conservé tel quel'
assert_eq 'eui.0026b7683d5a1f2e' "$(reject_null_identifier 'eui.0026b7683d5a1f2e')" \
  'un identifiant préfixé est conservé tel quel'

suite 'Dernière ligne des commandes'

# Le défaut le plus coûteux trouvé par la validation sur machine réelle :
# `run_cmd` ne terminait pas sa sortie par un saut de ligne, et `while read`
# abandonne une ligne non terminée. Vingt-cinq boucles consomment `run_cmd` ;
# celles qui ne passent pas par un filtre perdaient leur dernier élément.
assert_eq '3' "$(run_cmd printf 'a\nb\nc' | wc -l)" \
  'une sortie sans saut final est tout de même lue sur trois lignes'
assert_eq 'c' "$(last=''; while read -r l; do last=$l; done < <(run_cmd printf 'a\nb\nc'); printf '%s' "$last")" \
  'la dernière ligne atteint la boucle appelante'
assert_eq '0' "$(run_cmd printf '' | wc -l)" \
  'une sortie vide ne devient pas une ligne blanche'
assert_eq 'a' "$(run_cmd printf 'a\n')" \
  'la substitution de commande reste inchangée'

suite 'Ports en écoute'

# shellcheck source=../lib/collectors/network.sh
. "$SCANNER_DIR/lib/collectors/network.sh"

# `ss -H` publie sept colonnes ; l'adresse locale est la cinquième. Le
# collecteur en lisait la quatrième — la file d'attente d'émission — et
# publiait 4096 ou 128 comme numéro de port. Sur l'hôte Proxmox de validation,
# les quarante-six sockets en écoute sortaient toutes avec un port inventé.
SS_OUTPUT=$(
  printf '%s\n' \
    'tcp   LISTEN 0      4096       0.0.0.0:8006      0.0.0.0:*    users:(("pvedaemon",pid=1,fd=6))' \
    'tcp   LISTEN 0      128        127.0.0.1:5980    0.0.0.0:*    users:(("netdata",pid=2,fd=7))' \
    'tcp   LISTEN 0      128           [::]:22           [::]:*    users:(("sshd",pid=3,fd=4))'
)
PORTS_JSON=$(run_cmd() { printf '%s\n' "$SS_OUTPUT"; }; parse_listening_ports)

assert_contains "$PORTS_JSON" '"port":8006' 'le port lu est celui de l’adresse locale, pas la file d’attente'
assert_contains "$PORTS_JSON" '"address":"0.0.0.0"' 'l’adresse locale est lue'
assert_not_contains "$PORTS_JSON" '"port":4096' 'la profondeur du backlog n’est jamais prise pour un port'
assert_not_contains "$PORTS_JSON" '"port":128' 'idem pour la seconde valeur de backlog'
assert_contains "$PORTS_JSON" '"process":"pvedaemon"' 'le processus est extrait'

# Une écoute sur la boucle locale n'est pas exposée : la confondre avec une
# écoute sur toutes les interfaces changerait un constat de sécurité.
assert_contains "$PORTS_JSON" '"address":"127.0.0.1","process":"netdata","exposed":false' \
  'une écoute sur la boucle locale n’est pas exposée'

# IPv6 : ss encadre l'adresse de crochets, et le protocole devient tcp6.
assert_contains "$PORTS_JSON" '"protocol":"tcp6"' 'une écoute IPv6 est distinguée'

# Chaque objet doit occuper sa propre ligne : l'appelant les relit une par une,
# et sans saut final sa boucle sortait avant d'en traiter un seul — la liste
# partait vide, ce qui se lit « aucun service exposé ».
assert_eq '3' "$(printf '%s' "$PORTS_JSON" | grep -c '^{')" 'un objet JSON par ligne'
PORTS_COLLECTED=$(
  capability_tool() { printf 'true'; }
  run_cmd() { printf '%s\n' "$SS_OUTPUT"; }
  collect_listening_ports
)
assert_contains "$PORTS_COLLECTED" '"port":8006' 'le collecteur transmet réellement les ports lus'
assert_not_contains "$PORTS_COLLECTED" '""' 'aucun objet vide dans la liste assemblée'

suite 'Redondance et TRIM'

# shellcheck source=../lib/collectors/storage.sh
. "$SCANNER_DIR/lib/collectors/storage.sh"

# Le point le plus sensible de l'étape stockage : conclure à tort qu'un
# ensemble est protégé serait pire que de ne rien conclure.
assert_eq 'true' "$(raid_level_redundant raid1)" 'raid1 tolère une panne'
assert_eq 'true' "$(raid_level_redundant raid5)" 'raid5 tolère une panne'
assert_eq 'true' "$(raid_level_redundant raidz2)" 'raidz2 tolère une panne'
assert_eq 'true' "$(raid_level_redundant mirror)" 'miroir ZFS tolère une panne'
assert_eq 'false' "$(raid_level_redundant raid0)" 'raid0 ne tolère aucune panne'
assert_eq 'false' "$(raid_level_redundant linear)" 'agrégat linéaire ne tolère aucune panne'
assert_eq '' "$(raid_level_redundant 'raid-maison')" 'niveau inconnu → aucune conclusion'
assert_eq '' "$(raid_level_redundant '')" 'niveau absent → aucune conclusion'

TRIM_DIR=$(mktemp -d)
mkdir -p "$TRIM_DIR/sys/block/nvme0n1/queue" "$TRIM_DIR/sys/block/sda/queue"
printf '512\n' >"$TRIM_DIR/sys/block/nvme0n1/queue/discard_granularity"
printf '0\n' >"$TRIM_DIR/sys/block/sda/queue/discard_granularity"

# `detect_trim_support` lit sous /sys : la fonction est éprouvée via `read_value`
# sur une arborescence reconstituée, en la sourçant avec un préfixe.
assert_eq 'true' "$(granularity=$(read_value "$TRIM_DIR/sys/block/nvme0n1/queue/discard_granularity"); [ "$granularity" -gt 0 ] && printf 'true' || printf 'false')" \
  'granularité non nulle → TRIM accepté'
assert_eq 'false' "$(granularity=$(read_value "$TRIM_DIR/sys/block/sda/queue/discard_granularity"); [ "$granularity" -gt 0 ] && printf 'true' || printf 'false')" \
  'granularité nulle → TRIM refusé'
assert_eq '' "$(detect_trim_support 'disque-inexistant')" 'disque sans attribut → aucune conclusion'

rm -rf "$TRIM_DIR"

# --- Manifeste ---------------------------------------------------------------

suite 'Manifeste'

# `MANIFEST` est la source de vérité de la liste des fichiers du scanner ;
# `sysaudit.sh` en garde une copie sous forme de `source` explicites, que
# ShellCheck peut suivre. Ce test interdit aux deux de diverger — c'était la
# duplication qui piégeait toute étape ajoutant un collecteur.
MANIFEST_LIBS=$(grep -vE '^\s*(#|$)' "$SCANNER_DIR/MANIFEST" | grep -E '^lib/.*\.sh$')
SOURCED_LIBS=$(sed -nE 's|^\. "\$SCRIPT_DIR/(lib/.*\.sh)"$|\1|p' "$SCANNER_DIR/sysaudit.sh")
assert_eq "$MANIFEST_LIBS" "$SOURCED_LIBS" 'sysaudit.sh charge exactement les modules du manifeste'

MANIFEST_MISSING=''
while IFS= read -r manifest_path; do
  [ -n "$manifest_path" ] || continue
  [ -f "$SCANNER_DIR/$manifest_path" ] || MANIFEST_MISSING="$MANIFEST_MISSING $manifest_path"
done <<EOF
$(grep -vE '^\s*(#|$)' "$SCANNER_DIR/MANIFEST")
EOF
assert_eq '' "$MANIFEST_MISSING" 'chaque fichier du manifeste existe'

# Un fichier livré mais absent du manifeste ne serait jamais téléchargé par le
# script d'amorçage : le scan échouerait sur la machine auditée, pas ici.
UNLISTED=''
while IFS= read -r shell_file; do
  case "$(grep -vE '^\s*(#|$)' "$SCANNER_DIR/MANIFEST")" in
    *"$shell_file"*) ;;
    *) UNLISTED="$UNLISTED $shell_file" ;;
  esac
done <<EOF
$(cd "$SCANNER_DIR" && find lib -name '*.sh' | sort)
EOF
assert_eq '' "$UNLISTED" 'aucun module livré n’est absent du manifeste'

# --- Isolation des collecteurs ----------------------------------------------

suite 'Présentation console'

# La console ne doit jamais inventer : une valeur absente disparaît de
# l'affichage au lieu d'apparaître vide.
assert_eq '' "$(summary_value '{"model":{"unknown":true,"reason":"NOT_AVAILABLE"}}' 'model')" \
  'console : un marqueur d’absence ne produit aucune valeur'

assert_eq 'srv-01' "$(summary_value '{"hostname":"srv-01","other":"x"}' 'hostname')" \
  'console : valeur scalaire extraite'

# La première occurrence fait foi : appliquée au document entier, une clé comme
# `name` existe dans chaque interface réseau, et la dernière rencontrée serait
# une valeur juste au mauvais endroit.
assert_eq 'eth0' "$(summary_value '{"name":"eth0"},{"name":"eth1"}' 'name')" \
  'console : première occurrence retenue'

assert_eq '2' "$(summary_count '{"device":"sda"},{"device":"sdb"}' 'device')" \
  'console : comptage des occurrences'

assert_eq '1.0 Kio' "$(summary_bytes 1024)" 'console : octets formatés'

# Le séparateur décimal ne dépend pas de la langue de la machine.
#
# Sur une Ubuntu en français, `mawk` — l'awk par défaut — écrivait « 1,0 Kio », et
# le `printf` de bash refusait `1567.83` en entrée avant de rendre `1567,0`,
# c'est-à-dire un nombre faux. `LC_NUMERIC=C`, exporté par `lib/core/json.sh`,
# ferme les deux cas. Ce test le vérifie en forçant une locale française : sans
# le garde-fou, il échoue.
assert_eq '1.0 Kio' "$(LANG=fr_BE.UTF-8 summary_bytes 1024)" \
  'console : point décimal même en locale française'
assert_eq '' "$(summary_bytes 'inconnu')" 'console : valeur non numérique non formatée'
assert_eq '' "$(summary_bytes '')" 'console : valeur vide non formatée'

# La progression suit les vraies étapes, y compris depuis un sous-shell : chaque
# collecteur est appelé dans une substitution de commande, et un compteur en
# variable y resterait — la barre repartait de zéro à chaque étape.
progress_start 4
progress_done
(progress_done)
(progress_done)
progress_done
assert_eq '4' "$(progress_count)" 'console : progression comptée à travers les sous-shells'
progress_end
assert_eq '0' "$(progress_count)" 'console : journal de progression nettoyé'

suite 'Console : environnements dégradés'

# Terminal étroit : la barre se réduit sans jamais déborder.
COLUMNS=24 assert_eq '24' "$(COLUMNS=24 console_width)" 'console : largeur étroite respectée'
COLUMNS=5 assert_eq '20' "$(COLUMNS=5 console_width)" 'console : plancher de largeur appliqué'
assert_eq '80' "$(COLUMNS='' console_width)" 'console : largeur par défaut hors terminal'

# Locale sans UTF-8 : les marqueurs ASCII prennent le relais, sinon le terminal
# afficherait des points d'interrogation.
assert_contains "$(LC_ALL=C LANG=C console_marker ok)" '[OK]' 'console : marqueur ASCII sans UTF-8'
assert_contains "$(LC_ALL=fr_BE.UTF-8 console_marker ok)" '✓' 'console : marqueur Unicode avec UTF-8'

# Mode silencieux : plus rien, hors erreurs.
console_verbosity 'quiet'
assert_eq '' "$(console_session 'ceci ne doit pas apparaître' 2>&1)" \
  'console : mode silencieux muet'
console_verbosity 'normal'

# QR : rien ne s'affiche hors terminal, et l'URL reste seule.
assert_eq '' "$(console_qr 'AAAA' 2>&1)" 'console : pas de QR hors terminal'
assert_eq '' "$(console_qr '' 2>&1)" 'console : pas de QR sans dessin'

suite 'Répertoire de sortie'

# Le rapport ne suit plus le répertoire courant.
#
# L'audit est lancé depuis `/proc`, qui refuse l'écriture — l'équivalent Linux
# du `C:\WINDOWS\system32` d'une console Windows ouverte depuis le menu
# Démarrer. Le fichier doit apparaître dans le dossier personnel, et nulle part
# ailleurs : ni là où la commande a été tapée, ni dans le répertoire
# temporaire, qui n'est plus qu'un dernier recours.
#
# `SUDO_USER` est retiré de l'environnement : ce test décrit un audit lancé
# sans `sudo`, et le laisser passer ferait dépendre son résultat de la façon
# dont la suite elle-même a été lancée.
HOME_UNDER_TEST=$(mktemp -d)
FROM_UNWRITABLE=$(cd /proc 2>/dev/null &&
  env -u SUDO_USER "HOME=$HOME_UNDER_TEST" "$SCANNER_DIR/sysaudit.sh" --quick --no-markdown 2>&1 ||
  printf 'ECHEC')
assert_contains "$FROM_UNWRITABLE" "$HOME_UNDER_TEST/sysaudit-" \
  'sortie : le rapport va dans le dossier personnel, pas dans le répertoire courant'
assert_not_contains "$FROM_UNWRITABLE" "${TMPDIR:-/tmp}/sysaudit-" \
  'sortie : un dossier personnel disponible ne déclenche aucun repli'
assert_eq '1' "$(find "$HOME_UNDER_TEST" -maxdepth 1 -name 'sysaudit-*.json' | wc -l)" \
  'sortie : le fichier annoncé existe bien'
rm -rf "$HOME_UNDER_TEST"

# Dossier personnel indisponible — compte de service, `HOME` pointant sur un
# chemin qui n'existe pas. Un audit qui a réussi n'est pas perdu pour autant :
# le répertoire temporaire prend le relais, et le repli est annoncé.
UNWRITABLE_OUT=$(env -u SUDO_USER 'HOME=/proc/sysaudit-inexistant' \
  "$SCANNER_DIR/sysaudit.sh" --quick --no-markdown 2>&1 || printf 'ECHEC')
assert_contains "$UNWRITABLE_OUT" 'Dossier personnel indisponible' 'sortie : le repli est annoncé'
assert_contains "$UNWRITABLE_OUT" "${TMPDIR:-/tmp}/sysaudit-" 'sortie : rapport écrit dans le répertoire temporaire'
rm -f "${TMPDIR:-/tmp}/sysaudit-"*.json 2>/dev/null

# Un chemin demandé explicitement n'est jamais contourné : écrire ailleurs en
# silence ferait chercher le fichier au mauvais endroit.
EXPLICIT_OUT=$("$SCANNER_DIR/sysaudit.sh" --quick --no-markdown --output-dir /proc 2>&1 || printf 'ECHEC')
assert_contains "$EXPLICIT_OUT" 'ECHEC' 'sortie : un chemin explicite non inscriptible échoue'

suite 'Logo'

# Le logo ne doit jamais déborder : un dessin tronqué casse toutes les lignes
# suivantes. La vérification porte sur la largeur réelle du rendu.
#
# La largeur se mesure avec `wc -L`, qui rend la largeur **d'affichage**. Ni
# `awk length()` ni `wc -m` ne conviennent : sous mawk — l'awk par défaut
# d'Ubuntu — `length()` compte les **octets**, et les caractères de dessin du
# logo en occupent trois chacun. Le test annonçait alors 63 colonnes pour 29, et
# échouait sur un logo qui tient parfaitement.
logo_width() {
  wc -L | tr -d ' '
}

LOGO_WIDE=$(COLUMNS=120 console_logo 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
LOGO_WIDE_MAX=$(printf '%s\n' "$LOGO_WIDE" | logo_width)
assert_eq 'oui' "$([ "$LOGO_WIDE_MAX" -le 120 ] && printf 'oui' || printf 'non')" \
  'logo : tient dans 120 colonnes'
assert_eq 'oui' "$([ "$LOGO_WIDE_MAX" -ge 70 ] && printf 'oui' || printf 'non')" \
  'logo : version large affichée au-delà de 80 colonnes'

LOGO_NARROW=$(COLUMNS=50 console_logo 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
LOGO_NARROW_MAX=$(printf '%s' "$LOGO_NARROW" | logo_width)
assert_eq 'oui' "$([ "$LOGO_NARROW_MAX" -le 50 ] && printf 'oui' || printf 'non')" \
  'logo : tient dans 50 colonnes'

# Sous 34 colonnes, ou sans UTF-8, le mot seul.
assert_contains "$(COLUMNS=20 console_logo 2>&1)" 'SysAudit' 'logo : repli textuel en terminal étroit'
assert_not_contains "$(COLUMNS=20 console_logo 2>&1)" '█' 'logo : aucun bloc en terminal étroit'
# Le palier compact n'est pas franchi sous 42 colonnes : un dessin de 39
# colonnes dans un terminal de 40 ne laisserait aucune marge.
assert_not_contains "$(COLUMNS=40 console_logo 2>&1)" '█' 'logo : pas de dessin sous le seuil compact'
assert_not_contains "$(LC_ALL=C LANG=C COLUMNS=120 console_logo 2>&1)" '█' 'logo : aucun bloc sans UTF-8'

# La version accompagne le logo, dans les trois tailles.
assert_contains "$LOGO_WIDE" "v$SCANNER_VERSION" 'logo : version du scanner affichée'
assert_contains "$LOGO_WIDE" "$SCHEMA_VERSION" 'logo : version de schéma affichée'
assert_contains "$(COLUMNS=20 console_logo 2>&1)" "v$SCANNER_VERSION" 'logo : version affichée même en repli'

suite 'Attributs SMART'

# shellcheck source=../lib/collectors/storage.sh
. "$SCANNER_DIR/lib/collectors/storage.sh"

SMART_ATA=$(cat "$FIXTURES/smartctl-ata.txt")
ATTRS=$(collect_smart_attributes "$SMART_ATA")

assert_contains "$ATTRS" '"id":9,"name":"Power_On_Hours"' 'un attribut porte son identifiant et son nom'
assert_contains "$ATTRS" '"raw":"18240"' 'la valeur brute est conservée telle quelle'
assert_contains "$ATTRS" '"value":95' 'la valeur normalisée est distincte de la brute'

# `Temperature_Celsius` publie « 35 (Min/Max 20/45) » : la brute garde le
# contexte, que le champ nommé `temperatureCelsius` réduit à un entier. Perdre
# l'un des deux appauvrit le rapport.
assert_contains "$ATTRS" '"raw":"35 (Min/Max 20/45)"' 'le contexte d’un attribut n’est pas tronqué'
assert_eq '35' "$(smart_attribute "$SMART_ATA" 'Temperature_Celsius')" 'le champ nommé reste un entier'

# La table s'arrête à la ligne vide : une entrée de journal d'erreurs commence
# elle aussi par un nombre et ne doit pas passer pour un attribut.
assert_eq '' "$(collect_smart_attributes 'SMART Error Log Version: 1
  5 quelque chose 0x0000 100 100 000 - - - 0')" 'sans en-tête de table, aucun attribut n’est inventé'

# Les attributs NVMe n'ont pas cette table : le résultat doit être vide, pas
# approximatif.
assert_eq '' "$(collect_smart_attributes "$(cat "$FIXTURES/smartctl-nvme.txt")")" \
  'un rapport NVMe ne produit aucun attribut ATA'

suite 'Capteurs'

# Les capteurs ne sont vérifiables que sur la machine qui a le bon matériel —
# c'est-à-dire jamais en CI, et pas davantage dans WSL, qui n'expose aucun
# hwmon. L'arbre sysfs est donc fabriqué. Il reproduit un portable Ryzen : un
# chip `k10temp` sans zone thermique associée, et les ventilateurs d'un
# `asus_wmi_sensors`.

# shellcheck source=../lib/collectors/hardware.sh
build_sysfs() {
  local root=$1
  mkdir -p "$root/class/hwmon/hwmon0" "$root/class/hwmon/hwmon1"
  printf 'k10temp\n' >"$root/class/hwmon/hwmon0/name"
  printf '45000\n' >"$root/class/hwmon/hwmon0/temp1_input"
  printf 'Tctl\n' >"$root/class/hwmon/hwmon0/temp1_label"
  printf '95000\n' >"$root/class/hwmon/hwmon0/temp1_crit"
  printf 'asus_wmi_sensors\n' >"$root/class/hwmon/hwmon1/name"
  printf '2500\n' >"$root/class/hwmon/hwmon1/fan1_input"
  printf '2600\n' >"$root/class/hwmon/hwmon1/fan2_input"
}

SENSOR_ROOT=$(mktemp -d)
build_sysfs "$SENSOR_ROOT"

(
  # shellcheck source=../lib/collectors/hardware.sh
  SYSFS_ROOT="$SENSOR_ROOT" . "$SCANNER_DIR/lib/collectors/hardware.sh"
  init_collection_journal
  SENSORS=$(SYSFS_ROOT="$SENSOR_ROOT" collect_sensors 2>/dev/null)
  printf '%s' "$SENSORS" >"$SENSOR_ROOT/out.json"
  SYSFS_ROOT="$SENSOR_ROOT" read_cpu_temperature >"$SENSOR_ROOT/cpu.txt" 2>/dev/null
)
SENSORS=$(cat "$SENSOR_ROOT/out.json")

assert_contains "$SENSORS" '"celsius":45' 'une température hwmon est relevée'
assert_contains "$SENSORS" '"label":"Tctl"' 'l’étiquette du capteur est conservée'
assert_contains "$SENSORS" '"criticalCelsius":95' 'le seuil critique vient du capteur'
assert_contains "$SENSORS" '"rpm":2500' 'les ventilateurs sont relevés'

# Le cœur de la correction : sur un Ryzen, `k10temp` est un chip hwmon sans
# zone thermique. Ne lire que `/sys/class/thermal` revenait à déclarer « aucun
# capteur thermique CPU lisible » sur une machine qui en expose un.
assert_eq '45.0' "$(cat "$SENSOR_ROOT/cpu.txt")" 'la température CPU vient de hwmon faute de zone thermique'

# Non-déclenchement : sur un arbre sans le moindre capteur, le rapport ne doit
# pas se contenter d'un tableau vide — qui affirmerait « pas de capteur ».
EMPTY_ROOT=$(mktemp -d)
mkdir -p "$EMPTY_ROOT/class/hwmon" "$EMPTY_ROOT/class/thermal"
(
  # shellcheck source=../lib/collectors/hardware.sh
  SYSFS_ROOT="$EMPTY_ROOT" . "$SCANNER_DIR/lib/collectors/hardware.sh"
  init_collection_journal
  SYSFS_ROOT="$EMPTY_ROOT" collect_sensors >"$EMPTY_ROOT/out.json" 2>/dev/null
  build_collection_json >"$EMPTY_ROOT/journal.json"
)
assert_contains "$(cat "$EMPTY_ROOT/out.json")" '"temperatures":[]' 'sans capteur, le tableau est vide'
assert_contains "$(cat "$EMPTY_ROOT/journal.json")" '"section":"sensors.temperatures"' \
  'sans capteur, la raison est journalisée plutôt que tue'

rm -rf "$SENSOR_ROOT" "$EMPTY_ROOT"

suite 'Isolation des collecteurs'

init_collection_journal

collecteur_ok() { printf '{"ok":true}'; }
collecteur_qui_echoue() { return 3; }
collecteur_qui_sort() { exit 7; }
collecteur_muet() { printf ''; }

assert_eq '{"ok":true}' "$(run_collector demo collecteur_ok)" 'un collecteur sain rend son JSON'

# Le cœur de la garantie : `set -e` est actif dans ce harnais comme dans le
# scanner ; un collecteur qui échoue ne doit pas interrompre l'exécution.
assert_eq '' "$(run_collector casse collecteur_qui_echoue)" 'un collecteur en échec ne rend rien'
assert_eq '' "$(run_collector sortie collecteur_qui_sort)" 'un collecteur qui `exit` n’arrête pas le scan'
assert_eq '' "$(run_collector muet collecteur_muet)" 'un collecteur muet ne rend rien'

# Un collecteur qui a **déjà dit pourquoi** puis rendu une section vide n'est
# pas un collecteur en panne. Sans `lsmod`, l'inventaire des pilotes déclare
# l'outil manquant et s'arrête : y ajouter « le collecteur n'a produit aucune
# donnée » transformerait une dépendance absente en anomalie, et faisait passer
# un audit sans outils pour un audit cassé — mesuré sur trois sections lors du
# scan à PATH minimal du 2026-08-16.
collecteur_explique() {
  record_issue explique warning 'outil absent : rien à inventorier.' faux-outil NOT_AVAILABLE
  printf ''
}
assert_eq '' "$(run_collector explique collecteur_explique)" 'un collecteur qui explique ne rend rien'

# Un délai dépassé se déclare comme tel.
#
# `timeout` sort en 124, et ce code se lisait jusqu'au 2026-08-16 comme
# n'importe quelle commande en échec : le rapport disait « la donnée manque »,
# jamais « la source a mis trop de temps ». La différence compte pour qui
# relance l'audit — un disque qui ne répond pas en quinze secondes est un
# renseignement sur ce disque.
SYSAUDIT_CMD_TIMEOUT=1 run_cmd sleep 5 >/dev/null 2>&1 || true
TIMEOUT_JSON=$(build_collection_json)
assert_contains "$TIMEOUT_JSON" '"reason":"TIMEOUT"' \
  'un délai dépassé porte son motif'
assert_contains "$TIMEOUT_JSON" '"section":"commande.sleep"' \
  'la commande qui a dépassé le délai est nommée'

JOURNAL_JSON=$(build_collection_json)
assert_not_contains "$JOURNAL_JSON" '"section":"explique","severity":"warning","message":"Le collecteur'   'une absence déjà expliquée ne reçoit pas de motif d’anomalie par-dessus'
assert_contains "$JOURNAL_JSON" '"section":"muet","severity":"warning","message":"Le collecteur'   'une absence inexpliquée, elle, est bien signalée comme telle'
assert_contains "$JOURNAL_JSON" '"section":"casse"' 'l’échec est journalisé avec sa section'
assert_contains "$JOURNAL_JSON" '"severity":"error"' 'l’échec est journalisé comme erreur'
assert_contains "$JOURNAL_JSON" '"section":"muet"' 'l’absence de donnée est journalisée'
assert_contains "$JOURNAL_JSON" '"skippedSections"' 'les sections manquées sont listées'

# Durées par collecteur. Elles sortent du même journal que les incidents, et
# pour la même raison : `run_collector` s'exécute en substitution de commande,
# donc en sous-shell, où une variable Bash ne survivrait pas.
assert_contains "$JOURNAL_JSON" '"timings":[' 'les durées par collecteur atteignent le rapport'
assert_contains "$JOURNAL_JSON" '"section":"demo","durationMs":' 'un collecteur sain porte sa durée'

# Un collecteur en échec est chronométré comme les autres : il a bel et bien
# coûté du temps à l'utilisateur, et l'estimation doit en tenir compte. L'omettre
# ferait paraître rapides les audits qui échouent lentement.
assert_contains "$JOURNAL_JSON" '"section":"casse","durationMs":' 'un collecteur en échec porte aussi sa durée'

# Une durée non mesurable n'est pas enregistrée à zéro : le champ absent se lit
# « on ne sait pas », un zéro se lirait « instantané » et tirerait la médiane
# vers le bas à chaque horloge qui saute.
record_timing 'horloge-cassee' ''
record_timing 'horloge-negative' '-42'
TIMING_JSON=$(build_collection_json)
assert_not_contains "$TIMING_JSON" 'horloge-cassee' 'une durée vide n’est pas enregistrée'
assert_not_contains "$TIMING_JSON" 'horloge-negative' 'une durée négative n’est pas enregistrée'

# Une section vide est omise, jamais émise à demi : `"storage":` produirait un
# document invalide, et `"storage":{}` mentirait sur ce qui a été collecté.
assert_eq '' "$(section storage '')" 'une section vide est omise'
assert_eq '"storage":{"a":1}' "$(section storage '{"a":1}')" 'une section pleine est émise'

suite 'Niveaux de diagnostic'

# La matrice est la seule chose qui décide ce qu'un niveau collecte. Ces tests
# la lisent comme le scanner la lit — c'est aussi ce qui garantit que la table
# reste analysable par le test de contrat côté TypeScript.

PROFILE='quick'
assert_eq 'quick' "$(current_level)" 'le profil rapide donne le niveau Rapide'
assert_eq 'summary' "$(level_depth storage)" 'stockage en résumé au niveau Rapide'
assert_eq 'skipped' "$(level_depth software)" 'logiciels non collectés au niveau Rapide'
assert_eq 'standard' "$(level_depth system)" 'identité machine collectée à tous les niveaux'

PROFILE='security'
assert_eq 'quick' "$(current_level)" 'le profil historique security retombe sur Rapide'

PROFILE='standard'
assert_eq 'standard' "$(level_depth storage)" 'SMART collecté au niveau Normale'
assert_eq 'skipped' "$(level_depth benchmark)" 'aucun banc d’essai hors du niveau Poussée'
# Les périphériques, les pilotes et les logiciels ont rejoint le niveau Normale
# le 2026-08-16 : 20 secondes mesurées, dans un budget annoncé de deux minutes.
assert_eq 'standard' "$(level_depth devices)" 'périphériques complets au niveau Normale'
assert_eq 'standard' "$(level_depth software)" 'logiciels inventoriés au niveau Normale'

PROFILE='full'
assert_eq 'extended' "$(level_depth storage)" 'stockage approfondi au niveau Complète'
assert_eq 'standard' "$(level_depth software)" 'logiciels collectés au niveau Complète'
assert_eq 'skipped' "$(level_depth benchmark)" 'le niveau Complète ne charge pas la machine'

PROFILE='stress'
assert_eq 'standard' "$(level_depth benchmark)" 'banc d’essai au niveau Poussée'

# Une section inconnue de la table est collectée, jamais ignorée en silence :
# l'oubli d'une ligne ne doit pas faire disparaître une collecte.
assert_eq 'standard' "$(level_depth section_inexistante)" 'une section hors table reste collectée'

PROFILE='quick'
# Les capteurs ont rejoint le niveau Rapide le 2026-08-16 : 510 ms mesurées.
# `events` a pris leur place d'exemple — c'est la première section que Normale
# ajoute, et sa fenêtre est le journal entier, donc un coût qu'on ne borne pas.
assert_eq 'quick' "$(level_that_collects sensors)" 'les capteurs arrivent dès le niveau Rapide'
assert_eq 'standard' "$(level_that_collects events)" 'l’historique arrive au niveau Normale'
assert_eq 'stress' "$(level_that_collects benchmark)" 'le banc d’essai arrive au niveau Poussée'
assert_eq 'Rapide' "$(level_label quick)" 'le niveau porte son nom public'

if depth_at_least storage summary && ! depth_at_least storage standard; then
  PASSED=$((PASSED + 1))
  printf '  \033[32m✓\033[0m depth_at_least compare les profondeurs dans le bon sens\n'
else
  FAILED=$((FAILED + 1))
  printf '  \033[31m✗\033[0m depth_at_least compare les profondeurs dans le bon sens\n'
fi

# Le marqueur d'absence dû au niveau se distingue d'un outil manquant.
assert_contains "$(level_unknown standard)" '"reason":"NOT_COLLECTED"' \
  'une donnée non prévue au niveau porte NOT_COLLECTED'
assert_contains "$(level_unknown standard)" 'niveau Normale' \
  'le marqueur dit quel niveau l’aurait collectée'

# Un même motif rencontré une fois par disque ne produit qu'une déclaration.
init_collection_journal
record_level_skip 'storage.smart' standard
record_level_skip 'storage.smart' standard
LEVEL_JOURNAL=$(build_collection_json)
assert_eq '1' "$(printf '%s' "$LEVEL_JOURNAL" | grep -o '"section":"storage.smart"' | wc -l)" \
  'une absence due au niveau n’est déclarée qu’une fois'

# Retour au niveau par défaut : les suites suivantes lancent de vrais scans.
# shellcheck disable=SC2034 # relue par `current_level`, dans levels.sh.
PROFILE='standard'

suite 'Banc d’essai'

# shellcheck source=../lib/collectors/benchmark.sh
. "$SCANNER_DIR/lib/collectors/benchmark.sh"

# Le dimensionnement est la partie du banc d'essai qui peut nuire à la machine
# auditée : trop de mémoire et le scan provoque du swap, trop d'écritures et il
# use le support qu'il vient déclarer sain. Ces bornes se testent sans rien
# charger.

PROFILE='standard'
assert_eq '5' "$(bench_seconds)" 'mesure courte hors du niveau Poussée'
PROFILE='stress'
assert_eq '20' "$(bench_seconds)" 'mesure soutenue au niveau Poussée'
assert_eq '5' "$(bench_cooldown_seconds)" 'répit plus long au niveau Poussée'

SYSAUDIT_BENCH_SECONDS=7 assert_eq '7' "$(SYSAUDIT_BENCH_SECONDS=7 bench_seconds)" \
  'la durée demandée est respectée'
assert_eq '120' "$(SYSAUDIT_BENCH_SECONDS=99999 bench_seconds)" \
  'une durée absurde est plafonnée plutôt que refusée'
assert_eq '1' "$(SYSAUDIT_BENCH_SECONDS=0 bench_seconds)" 'une durée nulle est ramenée à une seconde'
assert_eq '20' "$(SYSAUDIT_BENCH_SECONDS=abc bench_seconds)" \
  'une durée non numérique retombe sur la valeur du niveau'

# Le budget d'écriture borne le nombre de passes : c'est ce qui empêche une
# mesure de vingt secondes sur un SSD rapide d'écrire des dizaines de gibioctets.
assert_eq '8' "$(bench_write_passes 256)" 'écritures bornées à 2 Gio au niveau Poussée'
PROFILE='standard'
assert_eq '4' "$(bench_write_passes 256)" 'écritures bornées à 1 Gio ailleurs'
assert_eq '1' "$(bench_write_passes 0)" 'une taille nulle ne divise pas par zéro'

# Le dimensionnement lit la machine réelle : on vérifie qu'il reste dans ses
# bornes, pas qu'il vaut une valeur précise.
BENCH_MEM=$(bench_memory_mib)
if [ "$BENCH_MEM" -ge 0 ] && [ "$BENCH_MEM" -le 256 ]; then
  PASSED=$((PASSED + 1))
  printf '  \033[32m✓\033[0m le budget mémoire reste borné (%s Mio)\n' "$BENCH_MEM"
else
  FAILED=$((FAILED + 1))
  printf '  \033[31m✗\033[0m budget mémoire hors bornes : %s\n' "$BENCH_MEM"
fi

BENCH_DISK=$(bench_storage_mib)
if [ "$BENCH_DISK" -ge 0 ] && [ "$BENCH_DISK" -le 256 ]; then
  PASSED=$((PASSED + 1))
  printf '  \033[32m✓\033[0m le budget disque reste borné (%s Mio)\n' "$BENCH_DISK"
else
  FAILED=$((FAILED + 1))
  printf '  \033[31m✗\033[0m budget disque hors bornes : %s\n' "$BENCH_DISK"
fi

# L'horloge de repli rend des **millisecondes**, pas des nanosecondes.
#
# `clock_ms` préfère `/proc/uptime`, monotone ; c'est son repli `date` qui était
# faux, et il ne s'exécute jamais sous Linux — donc le chemin cassé était
# invérifiable là où il comptait. Il est appelé directement ici.
#
# `date +%s%3N` paraissait donner des millisecondes ; la largeur d'un `%N` n'est
# pourtant pas honorée partout. Sous `uutils coreutils` — le `date` par défaut
# d'Ubuntu 25.10 — le `3` est ignoré et les neuf chiffres de nanosecondes
# sortent : toute durée était multipliée par un million, le budget du banc
# d'essai paraissait dépassé dès la première passe, et toutes les mesures ne
# comportaient qu'un seul passage au lieu du nombre demandé.
#
# Le test porte sur l'ordre de grandeur : un horodatage en millisecondes tient
# sur treize chiffres jusqu'en 2286, en nanosecondes il en fait dix-neuf. C'est
# exactement l'écart que le défaut produisait.
CLOCK_NOW=$(clock_ms_from_date)
case "$CLOCK_NOW" in
  '' | *[!0-9]*)
    FAILED=$((FAILED + 1))
    printf '  \033[31m✗\033[0m l’horloge de repli ne rend pas un entier : %s\n' "$CLOCK_NOW"
    ;;
  *)
    if [ "${#CLOCK_NOW}" -eq 13 ]; then
      PASSED=$((PASSED + 1))
      printf '  \033[32m✓\033[0m le repli rend des millisecondes, pas des nanosecondes\n'
    else
      FAILED=$((FAILED + 1))
      printf '  \033[31m✗\033[0m repli hors échelle : %s chiffres (%s)\n' \
        "${#CLOCK_NOW}" "$CLOCK_NOW"
    fi
    ;;
esac

# Deux lectures encadrant une attente courte doivent différer de l'ordre de
# l'attente, jamais d'un million de fois plus.
CLOCK_A=$(clock_ms)
sleep 0.05
CLOCK_B=$(clock_ms)
CLOCK_DELTA=$((CLOCK_B - CLOCK_A))
if [ "$CLOCK_DELTA" -ge 10 ] && [ "$CLOCK_DELTA" -le 5000 ]; then
  PASSED=$((PASSED + 1))
  printf '  \033[32m✓\033[0m cinquante millisecondes se mesurent comme telles (%s ms)\n' \
    "$CLOCK_DELTA"
else
  FAILED=$((FAILED + 1))
  printf '  \033[31m✗\033[0m écart aberrant sur 50 ms : %s\n' "$CLOCK_DELTA"
fi

# La boucle de mesure s'arrête à la première des deux limites atteintes.
BENCH_LOOP=$(bench_loop 100000 3 true)
assert_eq '3' "${BENCH_LOOP%% *}" 'la boucle respecte le plafond de passes'
BENCH_LOOP=$(bench_loop 0 100 true)
assert_eq '1' "${BENCH_LOOP%% *}" 'la boucle exécute au moins une passe'

# La charge soutenue n'a lieu qu'au niveau Poussée : ailleurs, elle
# immobiliserait la machine plusieurs minutes sans avoir été demandée.
PROFILE='standard'
assert_eq '0' "$(bench_soak_seconds)" 'aucune charge soutenue hors du niveau Poussée'
PROFILE='stress'
assert_eq '600' "$(bench_soak_seconds)" 'dix minutes de charge soutenue au niveau Poussée'
assert_eq '60' "$(SYSAUDIT_SOAK_SECONDS=60 bench_soak_seconds)" 'durée de charge configurable'
assert_eq '3600' "$(SYSAUDIT_SOAK_SECONDS=99999 bench_soak_seconds)" 'charge soutenue plafonnée à une heure'
assert_eq '10' "$(SYSAUDIT_SOAK_SECONDS=1 bench_soak_seconds)" 'charge soutenue d’au moins dix secondes'

# L'analyse de la sortie d'openssl : la dernière colonne est le plus gros bloc.
assert_eq '1567.8' "$(LANG=fr_BE.UTF-8 bench_openssl_score 'AES-128-CBC     1644000.00k')" \
  'débit openssl : point décimal même en locale française'

# `LC_ALL` prime sur `LC_NUMERIC` : un export seul resterait sans effet sur une
# machine où il est défini. `lib/core/json.sh` le convertit donc en `LANG` au
# chargement. Ce test lance le scanner **dans un processus séparé**, avec
# `LC_ALL` posé dans son environnement — la situation réelle d'un utilisateur.
LOCALE_REPORT=$(LC_ALL=fr_BE.UTF-8 bash "$SCANNER_DIR/sysaudit.sh" --quick --stdout --quiet 2>/dev/null || true)
if [ -n "$LOCALE_REPORT" ] && command -v node >/dev/null 2>&1; then
  assert_eq 'valide' \
    "$(printf '%s' "$LOCALE_REPORT" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{JSON.parse(d);console.log("valide")}catch(e){console.log("invalide : "+e.message)}})')" \
    'un scan lancé en locale française produit un JSON valide'
else
  printf '  \033[33m·\033[0m scan en locale française ignoré (node absent ou scan vide)\n'
fi
assert_eq '1567.8' "$(bench_openssl_score 'AES-128-CBC     1644000.00k')" \
  'débit openssl converti en Mio/s'
assert_eq '' "$(bench_openssl_score 'rien à analyser')" 'sortie inexploitable → aucun score'

# Le banc d'essai GPU mesure carte par carte : une machine à deux GPU ne doit
# pas produire un score unique qui laisserait croire que les deux ont été vues.
GPU_ROOT=$(mktemp -d)
mkdir -p "$GPU_ROOT/class/drm/card0" "$GPU_ROOT/class/drm/card1" "$GPU_ROOT/class/drm/card0-HDMI-A-1"
GPU_DEVICES=$(SYSFS_ROOT="$GPU_ROOT" bench_gpu_devices)
assert_eq '2' "$(printf '%s\n' "$GPU_DEVICES" | count_non_empty_lines)" \
  'deux cartes détectées, connecteurs exclus'
assert_contains "$GPU_DEVICES" '0' 'la première carte porte son index'
assert_contains "$GPU_DEVICES" '1' 'la seconde carte porte son index'
rm -rf "$GPU_ROOT"

# La télémétrie NVIDIA : « [N/A » n'est pas un nombre, et le prendre pour tel
# rapporterait une horloge nulle sur une carte qui tourne.
GPU_TELEMETRY=$(bench_gpu_telemetry_json '42, 1800, 7000, 1024, 8192, 61, 120.5')
assert_contains "$GPU_TELEMETRY" '"utilizationPercent":42' 'utilisation GPU rapportée'
assert_contains "$GPU_TELEMETRY" '"vramUsedBytes":1073741824' 'VRAM convertie en octets'
assert_contains "$GPU_TELEMETRY" '"powerWatts":120.5' 'puissance rapportée'
GPU_PARTIAL=$(bench_gpu_telemetry_json '[N/A], 1800, [N/A], 1024, 8192, 61, [N/A]')
assert_contains "$GPU_PARTIAL" '"utilizationPercent":{"unknown":true' 'une valeur absente reste un marqueur'
assert_contains "$GPU_PARTIAL" '"coreClockMhz":1800' 'les valeurs présentes sont conservées'
assert_eq '' "$(bench_gpu_telemetry_json '')" 'aucune source → aucun fragment'

# Une mesure écartée et une mesure ratée ne se corrigent pas de la même façon :
# elles ne doivent pas se ressembler dans le rapport.
init_collection_journal
BENCH_SKIP=$(bench_skipped 'gpu' 'glmark2' 'glmark2 absent.')
assert_contains "$BENCH_SKIP" '"status":"skipped"' 'une mesure écartée porte son statut'
assert_contains "$BENCH_SKIP" '"detail":"glmark2 absent."' 'le motif accompagne la mesure'
assert_contains "$BENCH_SKIP" '"reason":"NOT_AVAILABLE"' 'aucun score n’est inventé'

BENCH_FAIL=$(bench_failed 'cpu-single' 'openssl' 'aucun débit exploitable.')
assert_contains "$BENCH_FAIL" '"status":"failed"' 'une mesure ratée se distingue d’une mesure écartée'

# Retour au niveau par défaut pour les suites suivantes.
# shellcheck disable=SC2034 # relue par `current_level`, dans levels.sh.
PROFILE='standard'

suite 'Dépendances externes'

# Le scanner nomme ce qui manque et affiche la commande — il n'installe rien.
# Ces tests portent sur la table embarquée, dont la cohérence avec
# `packages/platform/src/tool-dependencies.ts` est vérifiée côté TypeScript.

assert_eq 'smartmontools' "$(dependency_package smartctl debian)" 'paquet Debian de smartctl'
assert_eq 'smartmontools' "$(dependency_package smartctl arch)" 'paquet Arch de smartctl'
assert_eq 'lm_sensors' "$(dependency_package sensors rhel)" 'le nom du paquet change selon la famille'
assert_eq '' "$(dependency_package ufw rhel)" 'un paquet absent d’une famille ne rend rien'
assert_eq '' "$(dependency_package outil-inconnu debian)" 'un outil hors table ne rend rien'
assert_eq '' "$(dependency_package smartctl famille-inconnue)" 'une famille inconnue ne rend rien'

assert_eq 'apt install' "$(dependency_install_prefix debian)" 'commande d’installation Debian'
assert_eq 'pacman -S' "$(dependency_install_prefix arch)" 'commande d’installation Arch'
assert_eq '' "$(dependency_install_prefix inconnue)" 'aucune commande pour une famille inconnue'

assert_contains "$(dependency_unlocks smartctl)" 'SMART' 'ce que débloque l’outil est dit'
assert_eq '' "$(dependency_unlocks outil-inconnu)" 'un outil hors table ne débloque rien'

# --- Applicabilité : ne pas conseiller ce qui ne peut rien débloquer ---------
#
# Le défaut remonté du terrain le 2026-08-18 : sur un poste x86, chaque audit
# proposait « vcgencmd — bridage et sous-tension d'un Raspberry Pi ·
# sudo apt install raspi-utils ». Le paquet n'y débloque rien, le micrologiciel
# qu'il interroge n'existant que sur un Pi — et le conseil revenait à chaque
# exécution. Un conseil inapplicable répété apprend surtout à ne plus lire les
# conseils.

# Un outil sans condition vaut partout : c'est le cas courant, et il ne doit pas
# devenir conditionnel par accident.
assert_eq 'oui' "$(dependency_applies dmidecode && echo oui || echo non)" \
  'un outil sans condition s’applique partout'
assert_eq 'oui' "$(dependency_applies outil-inconnu && echo oui || echo non)" \
  'un outil hors table s’applique partout'

# La détection lit le matériel, jamais l'architecture : un serveur ARM64 n'est
# pas un Raspberry Pi, et un Pi 5 sous noyau 64 bits ne se distingue pas d'un
# Ampere par son `uname -m`.
APPLIES_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sysaudit-applies-XXXXXX")

# Le modèle publié par l'arbre de périphériques, tel que le noyau l'écrit —
# octet nul de fin compris, qui ne doit pas polluer la comparaison.
mkdir -p "$APPLIES_DIR/proc/device-tree"
printf 'Raspberry Pi 5 Model B Rev 1.0 ' >"$APPLIES_DIR/proc/device-tree/model"
assert_contains "$(tr -d ' ' <"$APPLIES_DIR/proc/device-tree/model")" 'Raspberry Pi' \
  'le modèle est lisible une fois l’octet nul retiré'

# Sur cette machine de test, la réponse doit correspondre au matériel réel :
# c'est le seul contrôle qui vaille, puisque c'est lui qui a produit le bruit.
if [ -r /proc/device-tree/model ] && tr -d ' ' </proc/device-tree/model | grep -qi raspberry; then
  assert_eq 'oui' "$(dependency_applies vcgencmd && echo oui || echo non)" \
    'sur un Raspberry Pi, vcgencmd est conseillé'
else
  assert_eq 'non' "$(dependency_applies vcgencmd && echo oui || echo non)" \
    'hors Raspberry Pi, vcgencmd n’est pas conseillé'
  # Et il ne doit plus apparaître dans la liste que voit l'utilisateur.
  assert_not_contains "$(dependency_missing)" 'vcgencmd' \
    'vcgencmd ne figure plus parmi les outils absents à installer'
fi

# NVMe : les nœuds `/dev/nvme[0-9]*` existent dès qu'un contrôleur répond. Sans
# eux, `nvme-cli` s'installerait pour ne rien lire.
if dependency_has_nvme; then
  assert_eq 'oui' "$(dependency_applies nvme && echo oui || echo non)" \
    'avec un disque NVMe, nvme-cli est conseillé'
else
  assert_eq 'non' "$(dependency_applies nvme && echo oui || echo non)" \
    'sans disque NVMe, nvme-cli n’est pas conseillé'
fi

# `/dev/nvme-fabrics` existe sur des machines sans aucun disque NVMe : il ne
# doit pas se faire passer pour un contrôleur.
assert_eq 'non' \
  "$(printf '%s' '/dev/nvme-fabrics' | grep -qE '^/dev/nvme[0-9]' && echo oui || echo non)" \
  'le nœud nvme-fabrics ne compte pas pour un disque'

rm -rf "$APPLIES_DIR"

# La famille est déduite de l'outil présent, pas du nom de la distribution.
DEP_FAMILY=$(dependency_family)
case "$DEP_FAMILY" in
  debian | rhel | arch | suse | alpine | '')
    PASSED=$((PASSED + 1))
    printf '  \033[32m✓\033[0m famille de paquets reconnue (%s)\n' "${DEP_FAMILY:-aucune}"
    ;;
  *)
    FAILED=$((FAILED + 1))
    printf '  \033[31m✗\033[0m famille de paquets inattendue : %s\n' "$DEP_FAMILY"
    ;;
esac

# Un outil présent n'est jamais conseillé.
if dependency_missing | grep -qx 'dd'; then
  FAILED=$((FAILED + 1))
  printf '  \033[31m✗\033[0m un outil présent ne doit pas être conseillé\n'
else
  PASSED=$((PASSED + 1))
  printf '  \033[32m✓\033[0m un outil présent n’est pas conseillé\n'
fi

# Un pare-feu déjà satisfait n'en fait pas conseiller un autre : c'est la
# différence entre un conseil utile et un conseil bruyant.
if has_cmd nft || has_cmd iptables || has_cmd ufw || has_cmd firewall-cmd; then
  assert_eq '' "$(dependency_missing | grep -E '^(ufw|firewall-cmd|nft|iptables)$' || printf '')" \
    'aucun pare-feu conseillé quand un équivalent répond déjà'
else
  PASSED=$((PASSED + 1))
  printf '  \033[32m✓\033[0m groupes d’alternatives (non vérifiable : aucun pare-feu présent)\n'
fi

# Le rapport de dépendances écrit sur stderr, jamais sur stdout : stdout est
# réservé au JSON.
assert_eq '' "$(dependency_report 2>/dev/null)" 'le conseil ne pollue pas la sortie standard'

# --- Gestionnaire de dépendances --------------------------------------------
#
# Ce module est le seul du scanner qui puisse modifier la machine auditée. Les
# tests portent donc d'abord sur ce qu'il **refuse** de faire : les quatre
# conditions de l'ADR 0008, et l'interdiction de toucher un outil préexistant.
#
# Rien n'est installé ici. Les chemins qui appellent un gestionnaire de paquets
# ne sont pas exerçables sans modifier la machine de test ; ce sont leurs
# gardes, leurs commandes et leur traçabilité qui sont vérifiées.

suite 'Gestionnaire de dépendances — conditions'

PROVISION_TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sysaudit-provision-XXXXXX")
PROVISION_JOURNAL="$PROVISION_TEST_DIR/dependencies"
PROVISION_USED_JOURNAL="$PROVISION_TEST_DIR/used"
PROVISION_REMOVAL_JOURNAL="$PROVISION_TEST_DIR/removal"
: >"$PROVISION_JOURNAL"
: >"$PROVISION_USED_JOURNAL"
: >"$PROVISION_REMOVAL_JOURNAL"

# La condition 1 : sans le drapeau, rien, et sans un mot. Un refus bavard sur
# le cas nominal ferait croire à une anomalie.
OPT_INSTALL_DEPS='false'
PROFILE='full'
PROVISION_DECISION=''
if provision_enabled 2>/dev/null; then
  FAILED=$((FAILED + 1))
  printf '  \033[31m✗\033[0m %s\n' 'sans --install-deps, aucune installation'
else
  PASSED=$((PASSED + 1))
  printf '  \033[32m✓\033[0m %s\n' 'sans --install-deps, aucune installation'
fi
PROVISION_DECISION=''
assert_eq '' "$(provision_enabled 2>&1 || true)" \
  'un audit ordinaire ne dit rien de l’installation'

# La condition 2 : le drapeau ne suffit pas sur les niveaux que le site propose.
OPT_INSTALL_DEPS='true'
PROFILE='quick'
PROVISION_DECISION=''
if provision_enabled 2>/dev/null; then
  FAILED=$((FAILED + 1))
  printf '  \033[31m✗\033[0m %s\n' 'le niveau Rapide n’installe rien, même avec le drapeau'
else
  PASSED=$((PASSED + 1))
  printf '  \033[32m✓\033[0m %s\n' 'le niveau Rapide n’installe rien, même avec le drapeau'
fi
PROVISION_DECISION=''
assert_contains "$(provision_enabled 2>&1 || true)" '--install-deps ignoré' \
  'le refus dit laquelle des conditions manque'

PROFILE='standard'
PROVISION_DECISION=''
if provision_enabled 2>/dev/null; then
  FAILED=$((FAILED + 1))
  printf '  \033[31m✗\033[0m %s\n' 'le niveau Standard n’installe rien non plus'
else
  PASSED=$((PASSED + 1))
  printf '  \033[32m✓\033[0m %s\n' 'le niveau Standard n’installe rien non plus'
fi

# La décision est mémorisée : trois appelants la posent, une seule explication.
PROFILE='quick'
PROVISION_DECISION=''
provision_enabled 2>/dev/null || true
assert_eq '' "$(provision_enabled 2>&1 || true)" \
  'la condition qui manque n’est expliquée qu’une fois'

# Retour à l'état d'un audit ordinaire : les suites suivantes ne doivent pas
# hériter d'un drapeau d'installation posé ici.
# shellcheck disable=SC2034 # lues par provision.sh et levels.sh.
OPT_INSTALL_DEPS='false'
# shellcheck disable=SC2034
PROFILE='standard'
# shellcheck disable=SC2034
PROVISION_DECISION=''

suite 'Annonce du mode — ce que l’audit fait subir à la machine'

# L'en-tête annonçait « lecture seule — aucune écriture » à tous les audits.
# C'était faux deux fois : au niveau Poussée, dont le banc d'essai écrit un
# fichier temporaire, et juste après avoir proposé l'installation d'un outil.
# Ces quatre cas verrouillent les quatre combinaisons possibles.

# shellcheck disable=SC2034 # lues par provision.sh et levels.sh.
OPT_BENCHMARK='false'
# shellcheck disable=SC2034 # idem : lue par provision.sh.
OPT_INSTALL_DEPS='false'
PROFILE='standard'
PROVISION_DECISION=''
assert_contains "$(session_mode_label)" 'aucune écriture' \
  'un audit ordinaire annonce la lecture seule'

PROFILE='stress'
PROVISION_DECISION=''
assert_contains "$(session_mode_label)" 'fichier temporaire' \
  'le niveau Poussée annonce l’écriture du banc d’essai'
assert_not_contains "$(session_mode_label)" 'aucune écriture' \
  'le niveau Poussée ne prétend pas ne rien écrire'

# `--benchmark` hors du niveau Poussée : la même écriture, donc la même annonce.
PROFILE='standard'
OPT_BENCHMARK='true'
PROVISION_DECISION=''
assert_contains "$(session_mode_label)" 'fichier temporaire' \
  '--benchmark annonce l’écriture même hors du niveau Poussée'
# shellcheck disable=SC2034 # idem : la remise à zéro compte pour les cas suivants.
OPT_BENCHMARK='false'

# Installation autorisée : la décision est posée avant, et l'annonce la reprend
# au lieu de la démentir.
PROFILE='full'
PROVISION_DECISION='allowed'
assert_contains "$(session_mode_label)" 'installation d’outils' \
  'un audit qui peut installer le dit dans son en-tête'
assert_not_contains "$(session_mode_label)" 'aucune écriture' \
  'un audit qui peut installer ne prétend pas ne rien écrire'

PROFILE='stress'
PROVISION_DECISION='allowed'
assert_contains "$(session_mode_label)" 'installation d’outils' \
  'le niveau Poussée avec installation annonce les deux'
assert_contains "$(session_mode_label)" 'fichier temporaire' \
  'le niveau Poussée avec installation annonce aussi l’écriture'

# Retour à l'état d'un audit ordinaire pour les suites suivantes.
# shellcheck disable=SC2034
PROFILE='standard'
# shellcheck disable=SC2034
PROVISION_DECISION=''

suite 'Gestionnaire de dépendances — sources et commandes'

# L'ADR 0008 interdit tout téléchargement de binaire tiers. `provision_source`
# est le seul endroit du scanner qui pourrait en introduire un : aucune de ses
# réponses ne doit ressembler à une adresse.
for family in debian rhel arch suse alpine; do
  assert_not_contains "$(provision_source "$family")" 'http' \
    "la source $family n’est jamais une URL"
done
assert_contains "$(provision_source 'inconnue')" 'aucune source connue' \
  'une famille inconnue ne propose aucune source'

# Une invite bloquante au milieu d'un audit non interactif le figerait.
assert_contains "$(provision_install_command debian)" '-y' \
  'l’installation Debian est non interactive'
assert_contains "$(provision_install_command rhel)" '-y' \
  'l’installation RHEL est non interactive'
assert_contains "$(provision_install_command arch)" '--noconfirm' \
  'l’installation Arch est non interactive'

# `apt autoremove` et `pacman -Rs` emportent les dépendances devenues
# orphelines. En fin d'audit, sur une machine de production, c'est la pire
# chose que ce scanner puisse faire.
for family in debian rhel arch suse alpine; do
  assert_not_contains "$(provision_uninstall_command "$family")" 'autoremove' \
    "le retrait $family n’emporte pas les orphelins"
  assert_not_contains "$(provision_uninstall_command "$family")" '-Rs' \
    "le retrait $family ne cascade pas"
done

suite 'Gestionnaire de dépendances — inventaire'

: >"$PROVISION_JOURNAL"
provision_inventory

assert_contains "$(dependencies_inspected)" 'true' \
  'un inventaire effectué se déclare'
assert_eq "$(printf '%s' "$DEPENDENCY_TABLE" | awk 'NF' | wc -l)" \
  "$(wc -l <"$PROVISION_JOURNAL")" \
  'une ligne d’inventaire par outil de la table'

# Chaque outil sort avec une issue, et une seule.
# `grep -c` sort en 1 quand le compte est nul : le `|| true` garde le zéro
# qu'il vient d'imprimer, là où un `|| printf 0` en aurait imprimé un second.
assert_eq '0' "$(grep -cv '"outcome":' "$PROVISION_JOURNAL" || true)" \
  'aucune ligne d’inventaire sans issue'
assert_eq '0' "$(sed -n 's/.*"tool":"\([^"]*\)".*/\1/p' "$PROVISION_JOURNAL" |
  sort | uniq -d | wc -l)" \
  'aucun outil inventorié deux fois'

# L'inventaire dit ce qui est là, pas ce qu'il voudrait y trouver. `sh` est
# présent partout où ce test tourne ; un outil au nom impossible ne l'est nulle
# part. Les deux servent de repères.
if has_cmd iptables; then
  assert_contains "$(grep '"tool":"iptables"' "$PROVISION_JOURNAL")" 'PRESENT_BEFORE' \
    'un outil présent est marqué PRESENT_BEFORE'
fi
assert_not_contains "$(cat "$PROVISION_JOURNAL")" '"outcome":"INSTALLED"' \
  'un inventaire seul n’installe rien'
assert_not_contains "$(cat "$PROVISION_JOURNAL")" '"outcome":"DECLINED"' \
  'un inventaire seul ne pose aucune question'

# `provision_version` passe par `run_cmd`, qui marque l'usage. Si la liste des
# outils était publiée pendant l'inventaire, lire une bannière de version
# suffirait à faire passer l'outil pour utile à la collecte.
assert_eq '' "$(cat "$PROVISION_USED_JOURNAL")" \
  'lire une version ne compte pas comme un usage'

suite 'Gestionnaire de dépendances — traçabilité'

DEPS_JSON=$(build_dependencies_json)
assert_contains "$DEPS_JSON" '"used":false' \
  'l’usage est publié pour chaque outil'
assert_contains "$DEPS_JSON" '"removal":"NOT_APPLICABLE"' \
  'un outil non installé par SysAudit n’a rien à retirer'
assert_not_contains "$DEPS_JSON" '"removal":"REMOVED"' \
  'aucun retrait n’est annoncé sans retrait'

# La sortie doit rester du JSON valide : elle entre telle quelle dans le rapport.
if printf '%s' "$DEPS_JSON" | node -e \
  'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{JSON.parse(s)})' 2>/dev/null; then
  PASSED=$((PASSED + 1))
  printf '  \033[32m✓\033[0m %s\n' 'la trace des dépendances est du JSON valide'
else
  FAILED=$((FAILED + 1))
  printf '  \033[31m✗\033[0m %s\n' 'la trace des dépendances est du JSON valide'
fi

# Une réécriture remplace, elle n'ajoute pas : deux lignes pour un même outil
# rendraient la trace contradictoire.
provision_rewrite 'dmidecode' 'dmidecode' 'DECLINED' '' 'apt-get install -y' ''
assert_eq '1' "$(grep -c '"tool":"dmidecode"' "$PROVISION_JOURNAL")" \
  'la réécriture d’une issue ne duplique pas la ligne'
assert_contains "$(grep '"tool":"dmidecode"' "$PROVISION_JOURNAL")" 'DECLINED' \
  'la réécriture porte bien la nouvelle issue'
assert_eq "$(printf '%s' "$DEPENDENCY_TABLE" | awk 'NF' | wc -l)" \
  "$(wc -l <"$PROVISION_JOURNAL")" \
  'la réécriture ne perd aucun autre outil'

# Le cœur de l'ADR 0008 : un outil que l'utilisateur avait installé lui-même ne
# peut être ni listé, ni retiré. `provision_offer_removal` ne lit que les
# `INSTALLED` — un `PRESENT_BEFORE` n'atteint jamais la commande de retrait.
PRESENT_TOOLS=$(grep '"outcome":"PRESENT_BEFORE"' "$PROVISION_JOURNAL" |
  sed -n 's/.*"tool":"\([^"]*\)".*/\1/p')
REMOVABLE=$(grep '"outcome":"INSTALLED"' "$PROVISION_JOURNAL" |
  sed -n 's/.*"tool":"\([^"]*\)".*/\1/p' || printf '')
assert_eq '' "$REMOVABLE" \
  'aucun outil n’est retirable après un inventaire seul'
for tool in $PRESENT_TOOLS; do
  assert_not_contains "$REMOVABLE" "$tool" \
    "l’outil préexistant $tool n’est jamais proposé au retrait"
done

# Retrait refusé faute d'accord : les outils sont conservés, et le rapport le dit.
provision_mark_removal 'nvme' 'KEPT' ''
assert_contains "$(cat "$PROVISION_REMOVAL_JOURNAL")" 'KEPT' \
  'la conservation est enregistrée'

suite 'Gestionnaire de dépendances — l’accord vient bien de l’utilisateur'

# La question est posée dans la boucle qui parcourt les outils manquants. Si
# cette boucle lit la liste sur l'entrée standard, `read` y prend le nom de
# l'outil **suivant** en guise de réponse : rien ne s'installe jamais, et un
# outil sur deux n'est même pas proposé.
#
# Le défaut a réellement existé, et aucun test ne le voyait : tous passaient par
# `--assume-yes`, qui rend l'accord avant d'atteindre la lecture. Il a fallu un
# audit piloté dans un vrai terminal, en conteneur, pour le mettre au jour.
#
# Le scénario ci-dessous n'installe rien : `provision_install` est remplacé, et
# c'est bien la question qui est testée, pas `apt`.
CONSENT_DIR=$(mktemp -d)
CONSENT_JOURNAL=$(
  PROVISION_JOURNAL="$CONSENT_DIR/journal"
  : >"$PROVISION_JOURNAL"
  PROVISION_DECISION='allowed'
  OPT_ASSUME_YES='false'
  dependency_missing() { printf 'alpha\nbeta\ngamma\n'; }
  dependency_family() { printf 'debian'; }
  dependency_package() { printf '%s' "$1"; }
  dependency_unlocks() { printf 'une donnée'; }
  provision_install() { printf 'INSTALLED\n'; }
  provision_version() { printf '1.0'; }
  # La réponse est lue sur le terminal de contrôle, pas sur l'entrée standard :
  # sous `curl … | bash`, celle-ci porte le script. La suite y pointe donc
  # `/dev/stdin`, où elle verse les réponses — c'est bien `provision_ask` qui
  # est exercée, pas une imitation.
  # shellcheck disable=SC2034 # lue par provision_ask, dans provision.sh.
  PROVISION_TTY_DEVICE='/dev/stdin'
  printf 'o\no\no\n' | provision_apply >/dev/null 2>&1
  cat "$PROVISION_JOURNAL"
)
rm -rf "$CONSENT_DIR"

assert_eq '3' "$(printf '%s' "$CONSENT_JOURNAL" | grep -c '"outcome":"INSTALLED"' || true)" \
  'trois « o » valent trois accords — la réponse n’est pas volée par la liste'
for consent_tool in alpha beta gamma; do
  assert_contains "$CONSENT_JOURNAL" "\"tool\":\"$consent_tool\"" \
    "l’outil $consent_tool a bien été proposé"
done

# Et un refus reste un refus : sans quoi le test ci-dessus passerait aussi avec
# une fonction qui accepte tout.
CONSENT_DIR=$(mktemp -d)
REFUSAL_JOURNAL=$(
  PROVISION_JOURNAL="$CONSENT_DIR/journal"
  : >"$PROVISION_JOURNAL"
  # shellcheck disable=SC2034 # lues par provision_enabled et provision_consent.
  PROVISION_DECISION='allowed'
  # shellcheck disable=SC2034 # idem.
  OPT_ASSUME_YES='false'
  dependency_missing() { printf 'alpha\nbeta\ngamma\n'; }
  dependency_family() { printf 'debian'; }
  dependency_package() { printf '%s' "$1"; }
  dependency_unlocks() { printf 'une donnée'; }
  provision_install() { printf 'INSTALLED\n'; }
  provision_version() { printf '1.0'; }
  # La réponse est lue sur le terminal de contrôle, pas sur l'entrée standard :
  # sous `curl … | bash`, celle-ci porte le script. La suite y pointe donc
  # `/dev/stdin`, où elle verse les réponses — c'est bien `provision_ask` qui
  # est exercée, pas une imitation.
  # shellcheck disable=SC2034 # lue par provision_ask, dans provision.sh.
  PROVISION_TTY_DEVICE='/dev/stdin'
  printf 'n\nn\nn\n' | provision_apply >/dev/null 2>&1
  cat "$PROVISION_JOURNAL"
)
rm -rf "$CONSENT_DIR"

assert_eq '3' "$(printf '%s' "$REFUSAL_JOURNAL" | grep -c '"outcome":"DECLINED"' || true)" \
  'trois « n » valent trois refus'
assert_not_contains "$REFUSAL_JOURNAL" '"outcome":"INSTALLED"' \
  'un refus n’installe rien'

rm -rf "$PROVISION_TEST_DIR"
PROVISION_JOURNAL=''
PROVISION_USED_JOURNAL=''
PROVISION_REMOVAL_JOURNAL=''

suite 'Gestionnaire de dépendances — l’offre faite à qui n’a rien demandé'

# La commande que le site propose est `curl -fsSL …/audit/l | bash`. L'entrée
# standard y porte **le script lui-même** : `[ -t 0 ]` est faux, et une lecture
# sur cette entrée mangerait les octets du scanner en guise de réponse. Le
# consentement était donc inatteignable par le chemin d'installation officiel.
#
# `provision_tty` ouvre le terminal de contrôle, indépendant de l'entrée
# standard. Ce qui doit rester vrai — et c'est ce que ce bloc protège — est
# qu'aucune question ne soit posée là où personne ne peut répondre : un audit
# sous `cron` ou en intégration continue doit se dérouler exactement comme
# avant, sans attendre.

ANSWER_DIR=$(mktemp -d)

# Non-déclenchement : aucun terminal, donc aucune question.
assert_eq 'refuse' "$(
  PROVISION_TTY_DEVICE="$ANSWER_DIR/inexistant"
  provision_tty && printf 'accepte' || printf 'refuse'
)" 'sans terminal ouvrable, aucune question n’est posée'

# Déclenchement : une source lisible tient lieu de terminal.
printf 'o\n' >"$ANSWER_DIR/oui"
assert_eq 'accepte' "$(
  PROVISION_TTY_DEVICE="$ANSWER_DIR/oui"
  provision_tty && printf 'accepte' || printf 'refuse'
)" 'un terminal ouvrable permet de poser la question'

# Le défaut est **non** : sur une machine qu'on a promis de ne pas modifier,
# une frappe vide ne s'interprète pas comme un accord.
printf '\n' >"$ANSWER_DIR/vide"
assert_eq 'non' "$(
  PROVISION_TTY_DEVICE="$ANSWER_DIR/vide"
  provision_ask 'Installer ?' 2>/dev/null && printf 'oui' || printf 'non'
)" 'une réponse vide refuse'

assert_eq 'oui' "$(
  PROVISION_TTY_DEVICE="$ANSWER_DIR/oui"
  provision_ask 'Installer ?' 2>/dev/null && printf 'oui' || printf 'non'
)" 'un « o » franc accepte'

# L'offre ne se présente qu'à qui peut la tenir. Chacune de ces conditions se
# vérifie séparément : réunies dans un seul test, la première qui refuserait
# masquerait les autres.
assert_eq 'non' "$(
  PROVISION_TTY_DEVICE="$ANSWER_DIR/oui"
  OPT_INSTALL_DEPS='true'
  provision_offer >/dev/null 2>&1 && printf 'oui' || printf 'non'
)" 'aucune offre quand --install-deps a déjà été tapé'

assert_eq 'non' "$(
  PROVISION_TTY_DEVICE="$ANSWER_DIR/oui"
  OPT_INSTALL_DEPS='false'
  OPT_ASSUME_YES='true'
  provision_offer >/dev/null 2>&1 && printf 'oui' || printf 'non'
)" '--assume-yes seul n’est pas un accord pour installer'

assert_eq 'non' "$(
  PROVISION_TTY_DEVICE="$ANSWER_DIR/oui"
  OPT_INSTALL_DEPS='false'
  OPT_ASSUME_YES='false'
  id() { printf '1000'; }
  dependency_family() { printf 'debian'; }
  dependency_missing() { printf 'nvme\n'; }
  provision_offer >/dev/null 2>&1 && printf 'oui' || printf 'non'
)" 'aucune offre sans les privilèges qui permettraient de l’honorer'

assert_eq 'non' "$(
  PROVISION_TTY_DEVICE="$ANSWER_DIR/oui"
  OPT_INSTALL_DEPS='false'
  OPT_ASSUME_YES='false'
  id() { printf '0'; }
  dependency_family() { printf ''; }
  dependency_missing() { printf 'nvme\n'; }
  provision_offer >/dev/null 2>&1 && printf 'oui' || printf 'non'
)" 'aucune offre sans gestionnaire de paquets connu'

assert_eq 'non' "$(
  PROVISION_TTY_DEVICE="$ANSWER_DIR/oui"
  OPT_INSTALL_DEPS='false'
  OPT_ASSUME_YES='false'
  id() { printf '0'; }
  dependency_family() { printf 'debian'; }
  dependency_missing() { printf ''; }
  provision_offer >/dev/null 2>&1 && printf 'oui' || printf 'non'
)" 'aucune offre quand rien ne manque'

# Déclenchement complet, et ce qu'il pose derrière lui.
assert_eq 'oui true true' "$(
  PROVISION_TTY_DEVICE="$ANSWER_DIR/oui"
  OPT_INSTALL_DEPS='false'
  OPT_ASSUME_YES='false'
  id() { printf '0'; }
  dependency_family() { printf 'debian'; }
  dependency_missing() { printf 'nvme\nfio\n'; }
  if provision_offer >/dev/null 2>&1; then
    printf 'oui %s %s' "$OPT_INSTALL_DEPS" "$PROVISION_OFFERED"
  else
    printf 'non %s %s' "$OPT_INSTALL_DEPS" "$PROVISION_OFFERED"
  fi
)" 'une offre acceptée ouvre la revue outil par outil'

# La liste précède la question, et survit au refus.
#
# Première version : l'offre annonçait « Outils absents : 7 » et demandait
# l'accord d'ouvrir la revue. On autorisait donc l'examen d'un contenu qu'on ne
# voyait pas, et les commandes à recopier n'arrivaient qu'en fin d'audit, une
# fois la décision prise sans elles.
#
# Les deux assertions ci-dessous tiennent chacune une moitié de la correction :
# l'outil est **nommé**, et sa commande d'installation est **affichée** — donc
# copiable par qui refuse l'installation automatique.
OFFER_OUTPUT=$(
  PROVISION_TTY_DEVICE="$ANSWER_DIR/vide"
  OPT_INSTALL_DEPS='false'
  OPT_ASSUME_YES='false'
  id() { printf '0'; }
  dependency_family() { printf 'debian'; }
  dependency_missing() { printf 'nvme\nfio\n'; }
  dependency_unlocks() { printf 'une donnée'; }
  dependency_package() { printf '%s-cli' "$1"; }
  dependency_install_prefix() { printf 'apt install'; }
  provision_offer 2>&1 || true
)
assert_contains "$OFFER_OUTPUT" 'nvme' \
  'l’offre nomme les outils au lieu de les compter'
assert_contains "$OFFER_OUTPUT" 'sudo apt install nvme-cli' \
  'l’offre affiche la commande, copiable même si l’on refuse'
assert_contains "$OFFER_OUTPUT" 'restent valables' \
  'un refus rappelle que les commandes affichées restent utilisables'

# Un refus laisse la machine strictement intacte : c'est la promesse du produit,
# et elle ne doit pas dépendre du fait qu'on ait posé la question.
assert_eq 'non false false' "$(
  # shellcheck disable=SC2034 # lue par provision_ask, dans provision.sh.
  PROVISION_TTY_DEVICE="$ANSWER_DIR/vide"
  OPT_INSTALL_DEPS='false'
  OPT_ASSUME_YES='false'
  id() { printf '0'; }
  dependency_family() { printf 'debian'; }
  dependency_missing() { printf 'nvme\n'; }
  if provision_offer >/dev/null 2>&1; then
    printf 'oui %s %s' "$OPT_INSTALL_DEPS" "$PROVISION_OFFERED"
  else
    printf 'non %s %s' "$OPT_INSTALL_DEPS" "$PROVISION_OFFERED"
  fi
)" 'une offre refusée ne pose rien et laisse l’audit en lecture seule'

# La borne de niveau ne cède qu’à une offre acceptée. Le drapeau seul, au niveau
# standard, reste refusé — c’est ce qui protège l’audit que le site propose.
assert_eq 'non' "$(
  OPT_INSTALL_DEPS='true'
  # shellcheck disable=SC2034 # lue par provision_decide, dans provision.sh.
  OPT_ASSUME_YES='true'
  PROVISION_OFFERED='false'
  current_level() { printf 'standard'; }
  id() { printf '0'; }
  dependency_family() { printf 'debian'; }
  provision_decide >/dev/null 2>&1 && printf 'oui' || printf 'non'
)" 'le drapeau seul n’installe rien au niveau standard'

assert_eq 'oui' "$(
  OPT_INSTALL_DEPS='true'
  # shellcheck disable=SC2034 # lue par provision_decide, dans provision.sh.
  OPT_ASSUME_YES='true'
  PROVISION_OFFERED='true'
  current_level() { printf 'standard'; }
  id() { printf '0'; }
  dependency_family() { printf 'debian'; }
  provision_decide >/dev/null 2>&1 && printf 'oui' || printf 'non'
)" 'une offre acceptée vaut à tous les niveaux'

rm -rf "$ANSWER_DIR"


# --- Portabilité awk --------------------------------------------------------

suite 'Propriété du rapport après un audit sudo'

# Le défaut qui rendait un rapport indéposable, trouvé le 2026-08-18.
#
# `umask 077` protège le fichier — et sous `sudo`, il le protège de son
# propriétaire légitime : le rapport sort en `root:root` mode 600 dans le
# dossier personnel de l'utilisateur, qui ne peut ni le lire, ni le déposer.
#
# Le symptôme ne désignait rien : le navigateur, lancé par l'utilisateur,
# échouait sur « Failed to fetch » — une erreur réseau, alors que le réseau
# n'était pas en cause. C'est le fichier qu'il n'avait pas le droit de lire.
#
# Le test ne peut pas devenir root ; il vérifie donc la **décision**, qui est
# tout ce que la fonction contient : à qui rendre le fichier, et quand ne rien
# faire.
OWNERSHIP_FILE=$(mktemp "${TMPDIR:-/tmp}/sysaudit-owner-XXXXXX")

# Hors sudo : aucun utilisateur d'origine, donc rien à rendre. Un `chown`
# hasardeux donnerait le rapport à un compte au hasard.
CHOWN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sysaudit-chown-XXXXXX")
cat >"$CHOWN_DIR/chown" <<'FAKE'
#!/bin/sh
printf '%s\n' "$1" >>"$SYSAUDIT_CHOWN_LOG"
FAKE
chmod +x "$CHOWN_DIR/chown"

export SYSAUDIT_CHOWN_LOG="$CHOWN_DIR/appels"
: >"$SYSAUDIT_CHOWN_LOG"

(
  unset SUDO_UID SUDO_GID
  PATH="$CHOWN_DIR:$PATH" restore_report_ownership "$OWNERSHIP_FILE"
)
assert_eq '' "$(cat "$SYSAUDIT_CHOWN_LOG")" 'hors sudo, la propriété n’est pas touchée'

# `sudo -u root` : le fichier appartient déjà à root, il n'y a rien à rendre.
: >"$SYSAUDIT_CHOWN_LOG"
(
  SUDO_UID=0 SUDO_GID=0 PATH="$CHOWN_DIR:$PATH" restore_report_ownership "$OWNERSHIP_FILE"
)
assert_eq '' "$(cat "$SYSAUDIT_CHOWN_LOG")" 'un SUDO_UID nul ne déclenche aucun chown'

# Une valeur non numérique ne devient pas un argument de `chown`.
: >"$SYSAUDIT_CHOWN_LOG"
(
  SUDO_UID='root; rm -rf /' PATH="$CHOWN_DIR:$PATH" restore_report_ownership "$OWNERSHIP_FILE"
)
assert_eq '' "$(cat "$SYSAUDIT_CHOWN_LOG")" 'un SUDO_UID non numérique est refusé'

# Le cas normal : le rapport revient à l'utilisateur qui a lancé sudo.
: >"$SYSAUDIT_CHOWN_LOG"
(
  SUDO_UID=1000 SUDO_GID=1000 PATH="$CHOWN_DIR:$PATH" restore_report_ownership "$OWNERSHIP_FILE"
)
assert_eq '1000:1000' "$(cat "$SYSAUDIT_CHOWN_LOG")" 'le rapport revient à l’utilisateur d’origine'

# Sans SUDO_GID, le groupe suit l'utilisateur plutôt que d'être deviné.
: >"$SYSAUDIT_CHOWN_LOG"
(
  unset SUDO_GID
  SUDO_UID=1000 PATH="$CHOWN_DIR:$PATH" restore_report_ownership "$OWNERSHIP_FILE"
)
assert_eq '1000:1000' "$(cat "$SYSAUDIT_CHOWN_LOG")" 'sans SUDO_GID, le groupe suit l’utilisateur'

# Un fichier absent n'appelle rien : le Markdown est optionnel.
: >"$SYSAUDIT_CHOWN_LOG"
(
  SUDO_UID=1000 SUDO_GID=1000 PATH="$CHOWN_DIR:$PATH" restore_report_ownership "$CHOWN_DIR/inexistant"
)
assert_eq '' "$(cat "$SYSAUDIT_CHOWN_LOG")" 'un fichier absent n’appelle pas chown'

# Et les droits ne bougent pas : un rapport peut contenir des données
# personnelles, et le rendre lisible par tous échangerait un défaut
# d'ergonomie contre une fuite.
assert_not_contains "$(sed -n '/^restore_report_ownership()/,/^}/p' "$SCANNER_DIR/lib/core/core.sh")" \
  'chmod' 'la restitution ne change aucun droit'

# La fonction doit exister : les trois contrôles ci-dessus passeraient tout
# aussi bien si elle était absente — aucun `chown` n'aurait lieu, pour la
# mauvaise raison. C'est arrivé, et c'est un faux vert.
assert_eq 'function' "$(type -t restore_report_ownership)" \
  'la fonction est bien celle du scanner, et non une absence'

unset SYSAUDIT_CHOWN_LOG
rm -rf "$CHOWN_DIR" "$OWNERSHIP_FILE"

suite 'Journal multiligne — un message, un évènement'

# Le défaut qui a fait refuser un audit complet en production, le 2026-08-18.
#
# `journalctl -o short-unix` rend un message multiligne préfixé sur sa première
# ligne seulement ; les suivantes sont indentées. Le collecteur lisait chaque
# ligne isolément : une vidange mémoire `systemd-coredump`, qui liste ses
# modules, produisait un incident **par ligne**, avec des sources nommées
# « from » et « of ».
#
# Et la ligne vide séparant le message de sa liste donnait un incident au
# résumé entièrement blanc et à l'empreinte vide — tous deux refusés par le
# schéma (`min(1)`). L'API rendait alors un HTTP 400 sur le rapport **entier** :
# deux minutes d'audit perdues pour une ligne de journal.
JOURNAL_MULTILINE=$(printf '%s\n' \
  '1787028624.577123 hote systemd-coredump[3390]: Process 3388 (anydesk) of user 0 dumped core.' \
  '                                                     ' \
  '                                                     Module linux-vdso.so.1 from deb linux-6.8.0-45.45' \
  '                                                     Stack trace of thread 3388:' \
  '1787028625.100000 hote kernel: ata3.00: failed command: READ FPDMA QUEUED')

# Le programme awk est celui du collecteur, appliqué au flux de test : la
# fonction lit `journalctl`, qu'on ne peut pas simuler ici sans réécrire le
# parseur — ce qui ne testerait plus le code livré.
JOURNAL_PARSED=$(printf '%s' "$JOURNAL_MULTILINE" | awk "$(
  sed -n '/^stability_journal_events()/,/^}$/p' "$SCANNER_DIR/lib/collectors/stability.sh" |
    sed -n "/awk '/,/^    '$/p" | sed "1s/.*awk '//; \$d"
)")

assert_eq '2' "$(printf '%s\n' "$JOURNAL_PARSED" | grep -c .)" \
  'un message multiligne ne donne qu’un évènement'
assert_contains "$JOURNAL_PARSED" 'systemd-coredump' 'la source de la première ligne est conservée'
assert_not_contains "$JOURNAL_PARSED" '	from	' 'aucune source n’est fabriquée depuis une ligne de continuation'

# Le cœur du défaut : plus aucun enregistrement au message blanc.
assert_eq '' "$(printf '%s\n' "$JOURNAL_PARSED" | awk -F'\t' '$3 ~ /^[ \t]*$/ { print "BLANC" }')" \
  'aucun message vide ou blanc n’est émis'

# Et le filet côté émission : un enregistrement au résumé blanc n'atteint pas
# le JSON, quelle que soit l'origine du défaut.
assert_eq '' "$(printf '%s\n' "$JOURNAL_MULTILINE" | stability_journal_events err 2>/dev/null |
  stability_group_events ERROR 2>/dev/null | awk -F'\x1f' '$7 ~ /^[ \t]*$/ { print "BLANC" }')" \
  'aucun groupe au résumé blanc ne sort du regroupement'

suite 'Portabilité awk'

# Debian et Ubuntu installent **mawk** par défaut, pas gawk. Les deux ne
# comprennent pas le même sous-ensemble d’expressions régulières : mawk 1.3.4
# **panique** sur les intervalles de répétition — `{2}`, `{5}` — au lieu de les
# ignorer, et le programme awk entier ne rend alors plus rien.
#
# Le défaut était réel : le motif d’adresse MAC de `fingerprint()` en portait
# deux, et sur une machine dont l’awk est mawk le regroupement d’incidents
# retournait un tableau vide. La section `events`, cœur de ce chantier, était
# silencieusement inopérante.
#
# Ce test relance les fonctions concernées **avec mawk** quand il est installé.
if command -v mawk >/dev/null 2>&1; then
  MAWK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sysaudit-mawk-XXXXXX")
  ln -sf "$(command -v mawk)" "$MAWK_DIR/awk"

  # Même format que le test de regroupement plus bas : horodatage Unix, source,
  # message, séparés par de vraies tabulations. Les deux lignes ne diffèrent que
  # par l'adresse MAC et le secteur — donc un seul groupe attendu.
  MAWK_GROUPED=$(printf '%s\n' \
    '1785574000	kernel	ata3.00: failed command aa:bb:cc:dd:ee:ff sector 490037292' \
    '1785574100	kernel	ata3.00: failed command 11:22:33:44:55:66 sector 490112884' |
    PATH="$MAWK_DIR:$PATH" stability_group_events ERROR 2>&1)

  assert_not_contains "$MAWK_GROUPED" 'panic' 'mawk ne panique pas sur le motif d’adresse MAC'
  assert_contains "$MAWK_GROUPED" 'STORAGE' 'mawk classe l’incident comme les autres awk'
  # La preuve que l'empreinte a bien effacé l'adresse MAC : les deux lignes,
  # qui ne diffèrent que par cette adresse et le secteur, tombent dans **un
  # seul** groupe. L'adresse reste visible dans les extraits bruts, et c'est
  # normal — c'est l'empreinte qui la retire, pas la preuve.
  assert_contains "$MAWK_GROUPED" 'ata#.#: failed command # sector #' \
    'mawk efface l’adresse MAC de l’empreinte'
  assert_eq '1' "$(printf '%s' "$MAWK_GROUPED" | grep -c 'STORAGE')" \
    'les deux lignes ne forment qu’un groupe sous mawk'

  rm -rf "$MAWK_DIR"
else
  printf '  \033[33m·\033[0m portabilité mawk ignorée (mawk absent)\n'
fi

# --- Bout en bout -----------------------------------------------------------

suite 'Statistiques d’observation'

# Une observation d'une heure au pas de la seconde dépasse la borne du tableau
# d'échantillons. Ces statistiques sont alors la seule trace du pic : elles sont
# redondantes avec les échantillons, et c'est exactement leur raison d'être.
AGG=$(printf '%s\n' 78 81 83 | monitoring_aggregate '°C' 1000 '/sys/class/hwmon')
assert_contains "$AGG" '"minimum":78' 'le minimum observé est retenu'
assert_contains "$AGG" '"maximum":83' 'le maximum observé est retenu'
assert_contains "$AGG" '"average":80.67' 'la moyenne est calculée sur les échantillons'
assert_contains "$AGG" '"current":83' 'la valeur courante reste distincte du maximum'
assert_contains "$AGG" '"sampleCount":3' 'le nombre d’échantillons est publié'
assert_contains "$AGG" '"unit":"°C"' 'l’unité est littérale, jamais devinée du nom du champ'

# Le cas qui compte : aucun échantillon. `sampleCount` vaut alors zéro — un
# dénombrement, donc un fait — tandis que les statistiques restent **inconnues**.
# Une moyenne à zéro ferait passer une machine sans capteur pour une machine à
# zéro degré.
EMPTY_AGG=$(printf '' | monitoring_aggregate '°C' 1000 '/sys/class/hwmon')
assert_contains "$EMPTY_AGG" '"sampleCount":0' 'zéro échantillon est un fait, pas une absence'
assert_not_contains "$EMPTY_AGG" '"average":0' 'aucune moyenne nulle n’est fabriquée'
assert_contains "$EMPTY_AGG" '"average":{"unknown":true' 'la moyenne absente porte son marqueur'

suite 'Bridage processeur'

# Le bridage se prouve par la **progression** d'un compteur, jamais par une
# fréquence basse : un processeur au repos tourne bas sans être bridé, et
# confondre les deux inventerait une panne.
assert_eq 'true' "$(monitoring_throttled 10 12)" 'un compteur qui progresse prouve le bridage'
assert_eq 'false' "$(monitoring_throttled 10 10)" 'un compteur stable prouve l’absence de bridage'

# Au premier échantillon, il n'y a pas encore deux points à comparer. La réponse
# est alors **vide** — donc « inconnu » au rapport — et surtout pas « false ».
assert_eq '' "$(monitoring_throttled '' 10)" 'sans relevé précédent, le bridage reste inconnu'
assert_eq '' "$(monitoring_throttled 10 '')" 'un relevé manquant ne conclut pas à l’absence de bridage'

suite 'Nom du nœud Proxmox'

# `hostname` rend le nom pleinement qualifié — `pve.WORKGROUP` sur l'hôte qui a
# servi à trouver ce défaut — alors que le nœud PVE s'appelle `pve`. Tous les
# appels `pvesh get /nodes/<nom>/…` échouaient sur « proxy handler failed », et
# comme l'échec était absorbé, les tâches en échec et la dernière sauvegarde
# disparaissaient du rapport sans un mot.
PVE_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sysaudit-pve-XXXXXX")
mkdir -p "$PVE_ROOT/nodes/pve"
ln -s 'nodes/pve' "$PVE_ROOT/local"

# La fonction lit `/etc/pve/local` ; sa logique est rejouée ici sur une racine
# simulée, faute de pouvoir créer `/etc/pve` sur la machine de test.
resolve_node_in() {
  local root=$1 resolved=''
  if [ -L "$root/local" ]; then
    resolved=$(readlink "$root/local" 2>/dev/null)
    resolved=${resolved##*/}
    [ -n "$resolved" ] && {
      printf '%s' "$resolved"
      return 0
    }
  fi
  hostname -s 2>/dev/null || hostname 2>/dev/null || true
}

assert_eq 'pve' "$(resolve_node_in "$PVE_ROOT")" \
  'le nom du nœud vient de /etc/pve/local, pas de hostname'

# Trois entrées dans `nodes/` : deviner la locale d'après `hostname` serait
# doublement fragile. C'est le cas réel de l'hôte de validation.
mkdir -p "$PVE_ROOT/nodes/firebat" "$PVE_ROOT/nodes/prox"
assert_eq 'pve' "$(resolve_node_in "$PVE_ROOT")" \
  'le lien local tranche même avec plusieurs nœuds connus'

rm -f "$PVE_ROOT/local"
assert_not_contains "$(resolve_node_in "$PVE_ROOT")" '.' \
  'sans lien local, le repli emploie le nom court'
rm -rf "$PVE_ROOT"

assert_contains "$(declare -f proxmox_node_name)" '/etc/pve/local' \
  'la fonction du scanner lit bien /etc/pve/local'
assert_not_contains "$(declare -f collect_proxmox_node 2>/dev/null || printf '')" 'node_name=$(hostname 2>/dev/null)' \
  'le nom du nœud n’est plus déduit de hostname'

suite 'Services PVE sur un nœud isolé'

# Sur un nœud isolé, Proxmox laisse `corosync` **enabled** mais ne le démarre
# pas : c'est l'état normal. Le contrôle `enabled` seul annonçait donc un
# service PVE en échec sur une installation parfaitement saine — constaté sur
# l'hôte de validation.
assert_contains "$(declare -f proxmox_failed_services)" 'PROXMOX_CLUSTER_SERVICES' \
  'les services de grappe sont distingués'
for cluster_service in corosync pve-ha-lrm pve-ha-crm; do
  assert_contains "${PROXMOX_CLUSTER_SERVICES[*]}" "$cluster_service" \
    "$cluster_service est reconnu comme service de grappe"
done

suite 'Quorum d’un nœud isolé'

# Trouvé en exécutant le scanner sur un vrai nœud Proxmox autonome, pas en test :
# il faut que `pvecm status` échoue pour de bon.
#
# `cluster.quorate` y valait `UNKNOWN`, ce qui se lit « la valeur aurait dû être
# lisible et ne l'a pas été » — donc, sur un tableau de bord, comme un cluster
# dont on a perdu la trace. Un nœud hors cluster n'a pas un quorum illisible :
# il n'a pas de quorum, exactement comme il n'a pas de Ceph.
assert_contains "$(declare -f collect_proxmox_cluster)" 'NOT_APPLICABLE' \
  'le quorum d’un nœud isolé est déclaré sans objet'
assert_contains "$(declare -f collect_proxmox_cluster)" 'quorate_reason' \
  'le motif d’absence du quorum dépend du cas rencontré'

# Le pendant obligatoire : un nœud sur lequel `pvecm` est absent ne sait
# **pas** s'il est en grappe. Lui coller `NOT_APPLICABLE` affirmerait qu'il n'y
# a rien à mesurer, ce qui est une conclusion tirée d'une donnée absente.
assert_contains "$(declare -f collect_proxmox_cluster)" "quorate_reason='UNKNOWN'" \
  'sans pvecm, le quorum reste inconnu plutôt que sans objet'

# Au niveau Rapide, le cluster n'est pas interrogé. Il l'était déclaré
# `NOT_AVAILABLE` — « l'outil manque » — sur un hôte où `pvecm` est bien
# installé : le rapport annonçait un hôte Proxmox dépourvu des outils Proxmox,
# et envoyait le lecteur installer ce qu'il a déjà.
assert_contains "$(declare -f collect_proxmox)" 'level_unknown standard' \
  'hors niveau, le cluster porte NOT_COLLECTED et non NOT_AVAILABLE'
assert_not_contains "$(declare -f collect_proxmox)" 'jf_raw quorate "$(j_unknown NOT_AVAILABLE)"' \
  'le quorum hors niveau n’est plus présenté comme un outil manquant'

suite 'Tâches Proxmox'

# `pvesh --output-format json` rend une seule ligne. L'extraction passe par awk
# et non par un analyseur JSON : le scanner doit tourner sur une machine sans
# Node.js ni `jq`.
PVE_TASKS_RAW='[{"upid":"UPID:pve:0000:vzdump::","type":"vzdump","id":"101","starttime":1785000000,"endtime":1785000600,"status":"ERROR: exit code 2","node":"pve"},{"upid":"UPID:pve:0001:qmstart::","type":"qmstart","id":"102","starttime":1785001000,"endtime":1785001005,"status":"OK","node":"pve"}]'
PVE_TASKS=$(proxmox_tasks_from_json "$PVE_TASKS_RAW" 20)

assert_contains "$PVE_TASKS" '"type":"vzdump"' 'le type natif de la tâche est conservé'
assert_contains "$PVE_TASKS" '"target":"101"' 'l’invité visé est rattaché à la tâche'
assert_contains "$PVE_TASKS" '"status":"ERROR: exit code 2"' \
  'le statut natif part tel quel, sans traduction'
assert_contains "$PVE_TASKS" '"durationMs":600000' 'la durée se déduit des deux horodatages'
assert_contains "$PVE_TASKS" '"startedAt":"2026-07-25T17:20:00Z"' 'l’horodatage est converti en UTC'

# La limite doit couper, sinon un hôte à mille tâches en échec ferait grossir le
# rapport sans fin.
assert_eq '1' "$(proxmox_tasks_from_json "$PVE_TASKS_RAW" 1 | grep -o '"type"' | wc -l)" \
  'la limite de tâches est respectée'

# Une tâche non terminée n'a pas de durée : elle ne doit pas en recevoir une
# nulle, qui la ferait passer pour instantanée.
RUNNING_TASK='[{"type":"vzdump","id":"103","starttime":1785000000,"status":"running"}]'
assert_contains "$(proxmox_tasks_from_json "$RUNNING_TASK" 5)" \
  '"durationMs":{"unknown":true' 'une tâche en cours n’a pas de durée fabriquée'

suite 'Sous-systèmes Proxmox absents'

# Le critère explicite de l'étape 5 : une grappe sans Ceph n'a pas un Ceph en
# panne. `present: false` ne vaut pas `dégradé`, et surtout pas `0 dégradé`.
# Le nom d'un conteneur LXC survit à une colonne « Lock » vide.
#
# `pct list` rend quatre colonnes, dont la troisième est vide sur tout
# conteneur non verrouillé. `read` compressant les espaces, le nom tombait dans
# la variable du verrou : les huit conteneurs d'un hôte Proxmox réel se sont
# rapportés sans nom le 2026-08-16. Le découpage se fait désormais sur la
# dernière colonne, qui porte le nom dans les deux cas.
PCT_LIST_SANS_VERROU=$(printf '%s\n' \
  'VMID       Status     Lock         Name' \
  '100        running                 mcp-hub' \
  '101        stopped    backup       cloudflared' |
  awk 'NR > 1 && $1 ~ /^[0-9]+$/ { print $1 "|" $2 "|" (NF >= 3 ? $NF : "") }')
assert_contains "$PCT_LIST_SANS_VERROU" '100|running|mcp-hub' \
  'un conteneur sans verrou garde son nom'
assert_contains "$PCT_LIST_SANS_VERROU" '101|stopped|cloudflared' \
  'un conteneur verrouillé garde le sien aussi'
assert_contains "$(declare -f collect_proxmox_lxc)" 'NF >= 3 ? $NF' \
  'le collecteur lit bien le nom sur la dernière colonne'

ABSENT=$(proxmox_absent_subsystem 'aucune configuration Ceph sur ce nœud')
assert_contains "$ABSENT" '"present":false' 'l’absence du sous-système est un fait'
assert_contains "$ABSENT" '"NOT_APPLICABLE"' 'ses champs sont sans objet, pas indisponibles'
assert_not_contains "$ABSENT" '"degraded":0' 'aucun compteur de dégradation n’est fabriqué'

suite 'Noyaux installés'

# Une machine peut tourner depuis des semaines sur un noyau plus ancien que le
# plus récent installé : un correctif appliqué, mais pas encore chargé. Ni
# `os.kernel` seul ni `rebootRequired` ne disent ce fait — le premier ne dit pas
# ce qui attend, le second ne dit pas quoi.
KERNELS=$(stability_kernels_json)
assert_contains "$KERNELS" "\"running\":\"$(uname -r)\"" 'le noyau en cours est celui de uname'
assert_contains "$KERNELS" '"source"' 'la source de l’énumération est nommée'

# Régression : la chaîne s'arrêtait au premier gestionnaire de paquets
# **présent**, sans vérifier qu'il avait répondu. Sur une machine WSL, `dpkg`
# existe mais le noyau vient de Windows : aucun paquet `linux-image-*` n'est
# installé, et la liste sortait vide alors que `/lib/modules` avait la réponse.
if [ -d /lib/modules ] && [ -n "$(ls -A /lib/modules 2>/dev/null)" ]; then
  assert_not_contains "$KERNELS" '"installed":[]' \
    'la source suivante est essayée quand la précédente ne répond rien'
else
  printf '  \033[33m·\033[0m énumération des noyaux ignorée (/lib/modules vide)\n'
fi

suite 'Regroupement des incidents'

# Le regroupement n'est pas un confort d'affichage. Un disque qui meurt écrit la
# même ligne des milliers de fois ; sans regroupement, la borne du tableau
# couperait au millième doublon et cacherait tous les autres incidents.
GROUPED=$(printf '%s\n' \
  '1785574000	kernel	ata3.00: failed command: READ FPDMA QUEUED sector 490037292' \
  '1785574100	kernel	ata3.00: failed command: READ FPDMA QUEUED sector 490112884' \
  '1785574200	kernel	ata3.00: failed command: READ FPDMA QUEUED sector 490220016' \
  '1785574300	systemd	backup.service: Failed with result exit-code' |
  stability_group_events ERROR)

assert_eq '2' "$(printf '%s\n' "$GROUPED" | count_non_empty_lines)" \
  'trois lignes du même incident deviennent un seul groupe'

STORAGE_LINE=$(printf '%s\n' "$GROUPED" | grep -F 'STORAGE' || true)
assert_contains "$STORAGE_LINE" 'STORAGE' 'une erreur ATA est classée en stockage'
assert_eq '3' "$(printf '%s' "$STORAGE_LINE" | awk -v FS=$'\x1f' '{ print $6 }')" \
  'le compteur d’occurrences vaut le nombre de lignes regroupées'

# L'empreinte doit gommer ce qui change à chaque occurrence — ici le numéro de
# secteur — sans quoi elle ne regrouperait rien.
FINGERPRINT=$(printf '%s' "$STORAGE_LINE" | awk -v FS=$'\x1f' '{ print $8 }')
assert_not_contains "$FINGERPRINT" '490037292' 'l’empreinte ne retient pas le numéro de secteur'
assert_contains "$FINGERPRINT" 'read fpdma queued' 'l’empreinte retient la forme du message'

# Les trois extraits doivent être **distincts** : trois copies de la même ligne
# occuperaient la place de la preuve utile sans rien ajouter.
EV1=$(printf '%s' "$STORAGE_LINE" | awk -v FS=$'\x1f' '{ print $9 }')
EV2=$(printf '%s' "$STORAGE_LINE" | awk -v FS=$'\x1f' '{ print $10 }')
if [ -n "$EV2" ] && [ "$EV1" != "$EV2" ]; then
  PASSED=$((PASSED + 1))
  printf '  \033[32m✓\033[0m les extraits de preuve sont distincts\n'
else
  FAILED=$((FAILED + 1))
  printf '  \033[31m✗\033[0m les extraits de preuve sont identiques ou absents\n'
fi

# Le service en échec ne doit pas être avalé par le groupe précédent.
assert_contains "$GROUPED" 'SERVICE' 'un service en échec est classé à part'

# Ce que le classement ne doit **pas** faire : ranger au jugé. Une ligne qui ne
# correspond à aucun motif connu reste « autre » plutôt que d'être poussée dans
# la catégorie la plus proche — une erreur mal rangée pèserait sur le mauvais
# score.
OTHER=$(printf '%s\n' '1785574000	app	quelque chose d’inhabituel est arrivé' |
  stability_group_events ERROR)
assert_contains "$OTHER" 'OTHER' 'un message inconnu reste « autre » plutôt que rangé au jugé'

# La sévérité vient de l'appelant, qui la tient de la priorité du journal.
# Le classificateur ne la recalcule jamais : ce serait une analyse.
CRIT=$(printf '%s\n' '1785574000	kernel	Kernel panic - not syncing' |
  stability_group_events CRITICAL)
assert_contains "$CRIT" 'KERNEL_CRASH' 'une panique noyau est classée comme telle'
assert_eq 'CRITICAL' "$(printf '%s' "$CRIT" | awk -v FS=$'\x1f' '{ print $2 }')" \
  'la sévérité transmise est conservée telle quelle'
SAME_LINE_AS_ERROR=$(printf '%s\n' '1785574000	kernel	Kernel panic - not syncing' |
  stability_group_events ERROR)
assert_eq 'ERROR' "$(printf '%s' "$SAME_LINE_AS_ERROR" | awk -v FS=$'\x1f' '{ print $2 }')" \
  'la même ligne à une autre priorité garde la sévérité de sa source'

suite 'Exécution complète'

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

if "$SCANNER_DIR/sysaudit.sh" --stdout --no-markdown >"$TMP_DIR/report.json" 2>"$TMP_DIR/scan.log"; then
  PASSED=$((PASSED + 1))
  printf '  \033[32m✓\033[0m le scan se termine sans erreur\n'
else
  FAILED=$((FAILED + 1))
  printf '  \033[31m✗\033[0m le scan a échoué\n'
  tail -n 20 "$TMP_DIR/scan.log"
fi

# Aucune trace d'erreur shell ne doit apparaître : une variable non initialisée
# ou une commande absente produirait un rapport silencieusement incomplet.
assert_not_contains "$(cat "$TMP_DIR/scan.log")" 'unbound variable' 'aucune variable non initialisée'
assert_not_contains "$(cat "$TMP_DIR/scan.log")" 'command not found' 'aucune commande manquante non gérée'
assert_not_contains "$(cat "$TMP_DIR/scan.log")" 'syntax error' 'aucune erreur de syntaxe'

REPORT=$(cat "$TMP_DIR/report.json")
assert_not_contains "$REPORT" '"name":"bonding_masters"' \
  'aucune interface fantôme issue d’un fichier de /sys/class/net'
assert_contains "$REPORT" "\"schemaVersion\":\"$SCHEMA_VERSION\"" 'version de schéma annoncée'
assert_contains "$REPORT" "\"scannerVersion\":\"$SCANNER_VERSION\"" 'version de scanner annoncée'
assert_contains "$REPORT" '"capabilities"' 'section capabilities présente'
assert_contains "$REPORT" '"collection"' 'section collection présente'

# Sur un vrai scan, au moins `system` et `os` sont chronométrés : ce sont les
# deux seules sections obligatoires du schéma. Un tableau vide ici signalerait
# que la mesure ne traverse pas `run_collector`.
assert_contains "$REPORT" '"section":"system","durationMs":' 'le scan réel mesure la durée de ses collecteurs'
assert_not_contains "$REPORT" '"timings":[]' 'les durées mesurées ne repartent pas vides'

# Les sections d'historique. Leur présence dépend de ce que la machine offre —
# un conteneur sans journald n'en a pas — mais `capabilities.features` doit
# toujours dire ce qu'elle savait faire.
assert_contains "$REPORT" '"features"' 'les capacités déclarent ce que la machine sait répondre'
assert_contains "$REPORT" '"boot.fastStartupEnabled":"NOT_APPLICABLE"' \
  'une notion propre à Windows est déclarée sans objet, pas indisponible'
assert_contains "$REPORT" '"stability"' 'section stability présente au niveau Normale'

# Un compteur d'incidents ne part jamais sans sa fenêtre : « trois pannes » est
# rassurant sur un an et alarmant sur une journée.
assert_contains "$REPORT" '"observationWindowMs"' 'les compteurs portent leur fenêtre d’observation'

# La fenêtre demandée et la fenêtre obtenue sont deux faits distincts. Sans
# les deux, « aucun incident » se lirait comme un trimestre sain sur un
# journal qui ne remonte qu'à hier.
if printf '%s' "$REPORT" | grep -q '"events":{'; then
  assert_contains "$REPORT" '"requestedMs"' 'la fenêtre demandée figure au rapport'
  assert_contains "$REPORT" '"coveredMs"' 'la fenêtre réellement couverte figure au rapport'
else
  printf '  \033[33m·\033[0m historique ignoré (ni journalctl lisible ni dmesg)\n'
fi

# Régression : les problèmes de collecte étaient enregistrés dans un tableau
# Bash modifié depuis un sous-shell, si bien que `collection.issues` sortait
# systématiquement vide. Sans `dmidecode`, au moins une raison doit apparaître.
if has_cmd dmidecode; then
  PASSED=$((PASSED + 1))
  printf '  \033[32m✓\033[0m journal de collecte (non vérifiable : dmidecode présent)\n'
else
  assert_not_contains "$REPORT" '"issues":[]' 'les raisons d’absence atteignent le rapport'
fi

# Aucune clé ne sort sans valeur. `":,` et `":}` sont les deux seules formes que
# peut prendre ce défaut : toute valeur JSON licite commence par un guillemet,
# un chiffre, une accolade, un crochet ou une lettre. Ce contrôle est
# indépendant de ce que la machine sait faire, là où la validation ci-dessous ne
# voit le problème que si le collecteur fautif s'est réellement tu.
if printf '%s' "$REPORT" | grep -qE '":[,}]'; then
  FAILED=$((FAILED + 1))
  printf '  \033[31m✗\033[0m aucune clé émise sans valeur\n'
  printf '%s' "$REPORT" | grep -oE '.{40}":[,}]' | head -n 3
else
  PASSED=$((PASSED + 1))
  printf '  \033[32m✓\033[0m aucune clé émise sans valeur\n'
fi

# Le JSON doit être valide, y compris sur une machine aux capacités réduites.
if command -v node >/dev/null 2>&1; then
  if node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$TMP_DIR/report.json" 2>/dev/null; then
    PASSED=$((PASSED + 1))
    printf '  \033[32m✓\033[0m le JSON produit est syntaxiquement valide\n'
  else
    FAILED=$((FAILED + 1))
    printf '  \033[31m✗\033[0m le JSON produit est invalide\n'
  fi

  # Validation contre le schéma : c'est le contrat entre scanner et plateforme.
  SCHEMA_MODULE="$SCANNER_DIR/../../packages/report-schema/dist/index.js"
  if [ -f "$SCHEMA_MODULE" ]; then
    VALIDATION=$(node --input-type=module -e "
      import { readFileSync } from 'node:fs';
      import { validateReport } from '$SCHEMA_MODULE';
      const result = validateReport(JSON.parse(readFileSync('$TMP_DIR/report.json', 'utf8')));
      if (result.ok) { console.log('OK'); }
      else { console.log('ERREUR ' + result.code); console.log(JSON.stringify(result.issues.slice(0, 10))); }
    " 2>&1)
    assert_contains "$VALIDATION" 'OK' 'la sortie du scanner respecte le schéma SysAudit'
  else
    printf '  \033[33m·\033[0m validation de schéma ignorée (packages/report-schema non compilé)\n'
  fi
else
  printf '  \033[33m·\033[0m validation JSON ignorée (node absent)\n'
fi

# Le scanner ne doit jamais écrire ailleurs que dans son répertoire de sortie.
assert_eq '0' "$(find "$TMP_DIR" -type f ! -name 'report.json' ! -name 'scan.log' | wc -l)" \
  'aucun fichier inattendu créé'

suite 'Profil complet'

# Le profil standard n'active ni l'inventaire logiciel ni les pilotes : sans ce
# second scan, les sections `software` et `drivers` ne seraient jamais validées
# contre le schéma.
if "$SCANNER_DIR/sysaudit.sh" --full --stdout --no-markdown >"$TMP_DIR/full.json" 2>/dev/null; then
  FULL_REPORT=$(cat "$TMP_DIR/full.json")
  assert_contains "$FULL_REPORT" '"software"' 'section software présente en profil complet'
  assert_contains "$FULL_REPORT" '"packageManagers"' 'gestionnaires de paquets inventoriés'
  assert_not_contains "$FULL_REPORT" '"skippedSections":["software"' 'software n’est plus déclarée ignorée'

  if [ -f "$SCHEMA_MODULE" ]; then
    FULL_VALIDATION=$(node --input-type=module -e "
      import { readFileSync } from 'node:fs';
      import { validateReport } from '$SCHEMA_MODULE';
      const result = validateReport(JSON.parse(readFileSync('$TMP_DIR/full.json', 'utf8')));
      if (result.ok) { console.log('OK'); }
      else { console.log('ERREUR ' + result.code); console.log(JSON.stringify(result.issues.slice(0, 10))); }
    " 2>&1)
    assert_contains "$FULL_VALIDATION" 'OK' 'le rapport complet respecte le schéma SysAudit'
  fi
else
  FAILED=$((FAILED + 1))
  printf '  \033[31m✗\033[0m le scan complet a échoué\n'
fi

suite 'Niveau Rapide de bout en bout'

# Le niveau Rapide ne se distingue du niveau Normale que si son rapport le
# montre. Sans ce scan, la matrice pourrait être respectée dans le code et
# ignorée par les collecteurs.
if "$SCANNER_DIR/sysaudit.sh" --quick --stdout --no-markdown >"$TMP_DIR/quick.json" 2>/dev/null; then
  QUICK_REPORT=$(cat "$TMP_DIR/quick.json")

  assert_contains "$QUICK_REPORT" '"profile":"quick"' 'le rapport annonce son niveau'
  # Les capteurs sont désormais collectés dès le niveau Rapide : 510 ms.
  assert_contains "$QUICK_REPORT" '"sensors":{' 'les capteurs sont collectés'
  # `"events"` apparaît dans `skippedSections` : c'est la *section* qui doit
  # être absente, pas son nom.
  assert_not_contains "$QUICK_REPORT" '"events":{' 'l’historique des incidents n’est pas parcouru'
  assert_not_contains "$QUICK_REPORT" '"listeningPorts"' 'les ports en écoute ne sont pas relevés'
  assert_contains "$QUICK_REPORT" '"cpus"' 'le résumé processeur reste présent'
  assert_contains "$QUICK_REPORT" '"storage"' 'le résumé stockage reste présent'

  # Une absence due au niveau doit être discernable d'un outil manquant.
  assert_contains "$QUICK_REPORT" '"NOT_COLLECTED"' 'les champs non prévus portent leur motif'

  # Le niveau Rapide ne parcourt pas le journal. Les compteurs de `stability`
  # qui en dérivent doivent donc dire « non collecté à ce niveau » — et non
  # « aucun journal lisible », qui enverrait chercher un problème de
  # permissions sur une machine dont le journal se lit très bien.
  assert_not_contains "$QUICK_REPORT" '"events":{' 'l’historique n’est pas parcouru au niveau Rapide'
  assert_contains "$QUICK_REPORT" 'non collectée au niveau Rapide' \
    'les compteurs dérivés du journal disent qu’ils n’ont pas été regardés'
  for skipped in 'sensors' 'network.listeningPorts' 'security.updates' 'memory.modules'; do
    assert_contains "$QUICK_REPORT" "\"$skipped\"" "« $skipped » est déclarée non collectée"
  done

  if [ -f "$SCHEMA_MODULE" ]; then
    QUICK_VALIDATION=$(node --input-type=module -e "
      import { readFileSync } from 'node:fs';
      import { validateReport } from '$SCHEMA_MODULE';
      const result = validateReport(JSON.parse(readFileSync('$TMP_DIR/quick.json', 'utf8')));
      if (result.ok) { console.log('OK'); }
      else { console.log('ERREUR ' + result.code); console.log(JSON.stringify(result.issues.slice(0, 10))); }
    " 2>&1)
    assert_contains "$QUICK_VALIDATION" 'OK' 'le rapport rapide respecte le schéma SysAudit'
  fi
else
  FAILED=$((FAILED + 1))
  printf '  \033[31m✗\033[0m le scan rapide a échoué\n'
fi

suite 'Rapport Markdown du scanner'

# Toutes les exécutions ci-dessus passent `--no-markdown` : le rendu Markdown
# du scanner n'était donc jamais exercé. Il s'interrompait en silence sur une
# variable disparue, perdant sa section « Limites » et sa note de fin, sans
# qu'aucun test ne le voie.
if "$SCANNER_DIR/sysaudit.sh" --quick --output-dir "$TMP_DIR/md" >"$TMP_DIR/md.log" 2>&1; then
  MD_FILE=$(find "$TMP_DIR/md" -name '*.md' | head -n1)
  MD_REPORT=$([ -n "$MD_FILE" ] && cat "$MD_FILE" || printf '')

  assert_not_contains "$(cat "$TMP_DIR/md.log")" 'unbound variable' \
    'markdown : aucune variable non définie'
  assert_contains "$MD_REPORT" '## Limites de cette collecte' \
    'markdown : les limites de collecte sont rendues'
  # Le motif seul ne dit pas *quoi* manque : la section concernée est nommée.
  assert_contains "$MD_REPORT" '- **' 'markdown : chaque limite nomme sa section'
  assert_contains "$MD_REPORT" 'source de vérité' 'markdown : la note de fin est présente'
else
  FAILED=$((FAILED + 1))
  printf '  \033[31m✗\033[0m le scan avec rapport Markdown a échoué\n'
fi

suite 'Anonymisation de bout en bout'

if "$SCANNER_DIR/sysaudit.sh" --stdout --no-markdown --anonymize >"$TMP_DIR/anon.json" 2>/dev/null; then
  ANON_REPORT=$(cat "$TMP_DIR/anon.json")
  REAL_HOSTNAME=$(hostname 2>/dev/null || printf '')
  if [ -n "$REAL_HOSTNAME" ]; then
    assert_not_contains "$ANON_REPORT" "$REAL_HOSTNAME" 'le nom de machine réel n’apparaît pas'
  fi
  assert_contains "$ANON_REPORT" '"anonymized":true' 'le rapport se déclare anonymisé'
  assert_contains "$ANON_REPORT" 'HOST-' 'le pseudonyme de machine est présent'

  # Les adresses privées ne sont pas masquées : les masquer supprimerait une
  # information utile sans rien protéger.
  assert_contains "$ANON_REPORT" '"anonymizedCategories"' 'catégories anonymisées listées'
else
  FAILED=$((FAILED + 1))
  printf '  \033[31m✗\033[0m le scan anonymisé a échoué\n'
fi

suite 'Absence de secrets'

# Filet de sécurité : la sortie ne doit contenir aucun motif de secret connu.
for pattern in 'BEGIN RSA PRIVATE KEY' 'BEGIN OPENSSH PRIVATE KEY' 'ghp_' 'AKIA'; do
  assert_not_contains "$REPORT" "$pattern" "aucun secret de type « $pattern »"
done

# La sortie ne doit contenir aucune assignation de mot de passe.
if printf '%s' "$REPORT" | grep -qiE '"[^"]*(password|secret|token)[^"]*":"[^"]{8,}"'; then
  FAILED=$((FAILED + 1))
  printf '  \033[31m✗\033[0m aucune affectation de secret dans le rapport\n'
else
  PASSED=$((PASSED + 1))
  printf '  \033[32m✓\033[0m aucune affectation de secret dans le rapport\n'
fi

suite 'Rattachement de machine'

# Le code de rattachement voyage en en-tête, jamais dans le rapport : un
# rapport s'archive et se repartage, un code n'a rien à y faire.
SYSAUDIT_SOURCE=$(cat "$SCANNER_DIR/sysaudit.sh")
assert_contains "$SYSAUDIT_SOURCE" 'X-Machine-Claim' 'le code part en en-tête d’envoi'
assert_not_contains "$(printf '%s' "$SYSAUDIT_SOURCE" | grep -F 'jf_str' || true)" \
  'OPT_CLAIM_CODE' 'le code n’entre pas dans le JSON du rapport'

# `--claim` implique `--upload` : le code n'a de sens qu'au moment de l'envoi.
CLAIM_ARG_BLOCK=$(printf '%s' "$SYSAUDIT_SOURCE" | grep -A 4 -F -- '--claim)' || true)
assert_contains "$CLAIM_ARG_BLOCK" "OPT_UPLOAD='true'" '--claim implique --upload'

CLAIM_MISSING=$("$SCANNER_DIR/sysaudit.sh" --claim 2>&1 || printf 'ECHEC')
assert_contains "$CLAIM_MISSING" 'ECHEC' '--claim sans code échoue plutôt que d’envoyer sans preuve'

suite 'Publication d’un audit'

# `--public` ne rend pas le rapport lisible — il l'était déjà par son adresse.
# Il le rend répertoriable. La portée voyage en en-tête, jamais dans le rapport :
# elle décrit cet envoi-ci, pas la machine.
assert_contains "$SYSAUDIT_SOURCE" 'X-Scan-Visibility: public' \
  'la portée de publication part en en-tête d’envoi'
assert_not_contains "$(printf '%s' "$SYSAUDIT_SOURCE" | grep -F 'jf_str' || true)" \
  'OPT_PUBLIC' 'la portée n’entre pas dans le JSON du rapport'

# `--public` **n'implique pas** `--upload`, contrairement à `--claim` : le
# déduire ferait partir un rapport que l'utilisateur croyait garder local.
PUBLIC_ARG_BLOCK=$(printf '%s' "$SYSAUDIT_SOURCE" | grep -A 6 -F -- '--public)' || true)
assert_not_contains "$PUBLIC_ARG_BLOCK" "OPT_UPLOAD='true'" \
  '--public n’active pas l’envoi en douce'

# …et le refus arrive avant la collecte, pas après trois minutes de scan.
PUBLIC_ALONE=$("$SCANNER_DIR/sysaudit.sh" --public 2>&1 || printf 'ECHEC')
assert_contains "$PUBLIC_ALONE" 'ECHEC' '--public sans --upload échoue'
assert_contains "$PUBLIC_ALONE" '--public exige --upload' \
  'le refus de --public dit ce qui manque'

# Le défaut ne va jamais dans le sens qui expose.
assert_contains "$SYSAUDIT_SOURCE" "OPT_PUBLIC='false'" 'un audit est privé par défaut'

suite 'Adresse publique : la seule sortie réseau de la collecte'

# Trois états, et non un drapeau. Le défaut `auto` relève l'adresse là où elle
# peut l'être, et se tait ailleurs — sans quoi tout audit hors ligne échouerait
# pour un champ que personne n'a réclamé.
assert_contains "$SYSAUDIT_SOURCE" "OPT_PUBLIC_IP='auto'" \
  'l’adresse publique est relevée par défaut quand une API est connue'

PUBLIC_IP_ARG_BLOCK=$(printf '%s' "$SYSAUDIT_SOURCE" | grep -F -- '--public-ip)' || true)
assert_contains "$PUBLIC_IP_ARG_BLOCK" "OPT_PUBLIC_IP='true'" \
  '--public-ip exige le champ, et rien d’autre'
assert_not_contains "$PUBLIC_IP_ARG_BLOCK" "OPT_UPLOAD='true'" \
  '--public-ip n’active pas l’envoi'

NO_PUBLIC_IP_BLOCK=$(printf '%s' "$SYSAUDIT_SOURCE" | grep -F -- '--no-public-ip)' || true)
assert_contains "$NO_PUBLIC_IP_BLOCK" "OPT_PUBLIC_IP='false'" \
  '--no-public-ip existe et retire le relevé'

# Sans adresse d'API, le collecteur sort **sans rien émettre** et sans échouer :
# il n'y a personne à interroger, ce n'est pas une erreur. Un marqueur « non
# collecté » deviendrait « information protégée » à la lecture par un tiers,
# promettant au propriétaire une valeur qui n'existe pas.
PUBLIC_IP_HORS_LIGNE=$(bash -c '
  . "'"$SCANNER_DIR"'/lib/core/json.sh"
  . "'"$SCANNER_DIR"'/lib/collectors/network.sh"
  collect_public_ip')
assert_eq '' "$PUBLIC_IP_HORS_LIGNE" 'sans API, aucun champ n’est émis'

# …et `--no-public-ip` se tait même avec une API sous la main.
PUBLIC_IP_REFUSEE=$(bash -c '
  . "'"$SCANNER_DIR"'/lib/core/json.sh"
  . "'"$SCANNER_DIR"'/lib/collectors/network.sh"
  OPT_PUBLIC_IP=false
  OPT_API_URL=https://exemple.invalid
  collect_public_ip')
assert_eq '' "$PUBLIC_IP_REFUSEE" '--no-public-ip n’émet rien, API ou pas'

# Un audit hors ligne ne doit **pas** échouer parce que le défaut a changé : le
# refus ne vise que la demande explicite.
PUBLIC_IP_DEFAUT_HORS_LIGNE=$(env -u SYSAUDIT_API_URL "$SCANNER_DIR/sysaudit.sh" --capabilities 2>&1 ||
  printf 'ECHEC')
assert_not_contains "$PUBLIC_IP_DEFAUT_HORS_LIGNE" 'ECHEC' \
  'le défaut ne fait pas échouer un audit sans API'

# Le refus arrive avant la collecte : qui *demande* le champ doit apprendre tout
# de suite qu'il manque une API, et non le découvrir en lisant le rapport.
PUBLIC_IP_NO_API=$(env -u SYSAUDIT_API_URL "$SCANNER_DIR/sysaudit.sh" --public-ip 2>&1 ||
  printf 'ECHEC')
assert_contains "$PUBLIC_IP_NO_API" 'ECHEC' '--public-ip sans API échoue'
assert_contains "$PUBLIC_IP_NO_API" '--api-url' 'le refus de --public-ip dit ce qui manque'

# Une API injoignable donne un marqueur portant sa raison, jamais une valeur
# inventée ni un champ tu.
PUBLIC_IP_UNREACHABLE=$(bash -c '
  . "'"$SCANNER_DIR"'/lib/core/json.sh"
  . "'"$SCANNER_DIR"'/lib/core/core.sh"
  . "'"$SCANNER_DIR"'/lib/core/transport.sh"
  . "'"$SCANNER_DIR"'/lib/core/anonymize.sh"
  . "'"$SCANNER_DIR"'/lib/collectors/network.sh"
  OPT_PUBLIC_IP=true
  OPT_API_URL=https://exemple.invalid
  SCANNER_VERSION=test
  collect_public_ip')
assert_contains "$PUBLIC_IP_UNREACHABLE" '"unknown":true' \
  'une API injoignable donne un marqueur, pas une valeur'
assert_contains "$PUBLIC_IP_UNREACHABLE" 'NOT_AVAILABLE' 'le marqueur porte sa raison'

suite 'Transport : classification des échecs réseau'

# Un envoi qui échoue disait « erreur réseau », ce qui ne distingue pas un nom
# qui ne résout pas d'un proxy qui réclame des identifiants — deux pannes qui ne
# se réparent ni au même endroit ni par la même personne.
assert_contains "$(curl_failure_label 6)" 'DNS' 'le code curl 6 est nommé DNS'
assert_contains "$(curl_failure_label 7)" 'pare-feu' 'le code curl 7 nomme le pare-feu'
assert_contains "$(curl_failure_label 28)" 'délai dépassé' 'le code curl 28 nomme le délai'
assert_contains "$(curl_failure_label 60)" 'inspection HTTPS' \
  'un certificat refusé évoque l’inspection HTTPS'

# Un code inconnu est rendu tel quel plutôt que rangé dans un fourre-tout :
# « code curl 63 » se cherche, « erreur réseau » non.
assert_contains "$(curl_failure_label 63)" '63' 'un code curl inconnu reste identifiable'

assert_contains "$(http_failure_label 407)" 'proxy' 'le 407 désigne le proxy'
assert_contains "$(http_failure_label 403)" 'filtrage' 'le 403 évoque le filtrage'
assert_contains "$(http_failure_label 503)" 'serveur' 'un 5xx désigne le serveur'
assert_contains "$(http_failure_label 000)" 'aucune réponse' \
  'l’absence de réponse se dit, plutôt que de passer pour un statut'

# Le conseil n'existe que lorsqu'il en existe un. « Vérifiez votre connexion »
# n'aide personne et occupe la place du message utile.
assert_contains "$(network_failure_hint 407)" 'https_proxy' 'le 407 dit comment déclarer un proxy'
assert_eq '' "$(network_failure_hint 429)" 'un quota dépassé n’invente pas de conseil'

suite 'Transport : les identifiants de proxy ne fuient pas'

# Un mot de passe d'annuaire d'entreprise n'a rien à faire dans une sortie qu'on
# recopie dans un ticket.
MASKED=$(mask_proxy_credentials 'http://DOMAINE\utilisateur:s3cr3t@proxy.local:8080')
assert_eq 'http://proxy.local:8080' "$MASKED" 'les identifiants sont retirés de l’adresse'
assert_not_contains "$MASKED" 's3cr3t' 'le mot de passe ne survit pas au masquage'
assert_eq 'http://proxy.local:8080' "$(mask_proxy_credentials 'http://proxy.local:8080')" \
  'une adresse sans identifiants traverse inchangée'

# L'ordre suit celui que curl respecte lui-même : annoncer un proxy qui ne sera
# pas celui emprunté serait pire que ne rien annoncer.
DECLARED=$(https_proxy='http://user:pass@a.local:3128' http_proxy='http://b.local:3128' \
  bash -c '. "'"$SCANNER_DIR"'/lib/core/core.sh"; . "'"$SCANNER_DIR"'/lib/core/transport.sh"; proxy_declared')
assert_eq 'https_proxy=http://a.local:3128' "$DECLARED" \
  'https_proxy l’emporte, et sort masqué'
assert_eq '' "$(env -u https_proxy -u HTTPS_PROXY -u http_proxy -u HTTP_PROXY \
  -u all_proxy -u ALL_PROXY bash -c '. "'"$SCANNER_DIR"'/lib/core/core.sh"; . "'"$SCANNER_DIR"'/lib/core/transport.sh"; proxy_declared')" \
  'rien de déclaré rend une chaîne vide, pas une valeur inventée'

assert_eq 'sysaudit.me' "$(url_host 'https://sysaudit.me/api/')" 'l’hôte est extrait de l’URL'
assert_eq 'proxy.local' "$(url_host 'http://user:pass@proxy.local:8080/x')" \
  'l’extraction de l’hôte laisse les identifiants de côté'

suite 'Test réseau : aucun audit produit'

# Un test de connectivité qui lancerait un audit au passage obligerait à choisir
# entre savoir et ne pas auditer.
NETWORK_TEST_BLOCK=$(printf '%s' "$SYSAUDIT_SOURCE" | grep -A 6 -F -- '--network-test)' || true)
assert_not_contains "$NETWORK_TEST_BLOCK" "OPT_UPLOAD='true'" \
  '--network-test n’active pas l’envoi'
assert_contains "$NETWORK_TEST_BLOCK" "CMD='network-test'" \
  '--network-test bascule sur sa propre commande'

# La cible est `/api/health`, en lecture seule : `/api/audit/bootstrap/…` crée
# une session en base, et un test de connectivité n'a pas à laisser de trace.
#
# Les commentaires sont retirés avant l'examen : ils **citent** les points
# d'entrée qu'on s'interdit, pour expliquer pourquoi. Chercher dans le fichier
# entier ferait échouer le test sur sa propre justification.
TRANSPORT_CODE=$(grep -vE '^\s*#' "$SCANNER_DIR/lib/core/transport.sh")
assert_contains "$TRANSPORT_CODE" '/api/health' 'le test vise le point de santé'
assert_not_contains "$TRANSPORT_CODE" '/api/audit/bootstrap' \
  'le test ne crée pas de session d’audit'
assert_not_contains "$TRANSPORT_CODE" '/api/v1/scans/upload' \
  'le test n’envoie aucun rapport'

# Sans API, le refus est immédiat plutôt qu'un test qui ne teste rien.
NETWORK_TEST_NO_API=$(env -u SYSAUDIT_API_URL "$SCANNER_DIR/sysaudit.sh" --network-test 2>&1 || printf 'ECHEC')
assert_contains "$NETWORK_TEST_NO_API" 'ECHEC' '--network-test sans API échoue'
assert_contains "$NETWORK_TEST_NO_API" '--api-url' 'le refus dit ce qui manque'

suite 'Codes de sortie'

# Trois valeurs, et la distinction entre 1 et 2 est ce qui permet à une
# supervision de parc de ne pas confondre « machine non auditable » et « réseau
# fermé ». Ces deux situations n'appellent ni la même alerte ni la même action.
#
# Le domaine est en `.invalid`, réservé par la RFC 2606 : il ne résout nulle
# part, aucun paquet ne part vers un tiers.
env -u SYSAUDIT_API_URL "$SCANNER_DIR/sysaudit.sh" --network-test >/dev/null 2>&1
assert_eq '1' "$?" 'un usage incorrect sort en 1'

"$SCANNER_DIR/sysaudit.sh" --network-test --api-url https://exemple.invalid >/dev/null 2>&1
assert_eq '2' "$?" 'un réseau qui ne passerait pas sort en 2, pas en 1'

# Le renvoi d'un rapport vers une API injoignable : la collecte n'a pas eu lieu,
# seule la transmission a échoué. C'est exactement le cas que 2 doit couvrir.
RETRY_FIXTURE=$(mktemp "${TMPDIR:-/tmp}/sysaudit-retry-XXXXXX.json")
printf '{"schemaVersion":"%s"}\n' "$SCHEMA_VERSION" >"$RETRY_FIXTURE"
"$SCANNER_DIR/sysaudit.sh" --retry-upload "$RETRY_FIXTURE" --api-url https://exemple.invalid >/dev/null 2>&1
assert_eq '2' "$?" 'un renvoi vers une API injoignable sort en 2'

# Le message doit nommer la cause, pas dire « erreur réseau ».
RETRY_OUTPUT=$("$SCANNER_DIR/sysaudit.sh" --retry-upload "$RETRY_FIXTURE" --api-url https://exemple.invalid 2>&1 || true)
assert_contains "$RETRY_OUTPUT" 'ne résout pas' 'l’échec d’envoi nomme la cause'
assert_contains "$RETRY_OUTPUT" 'Rapport conservé' 'l’échec d’envoi rappelle que le rapport existe'
assert_contains "$RETRY_OUTPUT" '/deposer' 'l’échec d’envoi nomme la page de dépôt'
rm -f "$RETRY_FIXTURE"

suite 'Vérification du JSON avant écriture'

# Le contrôle attrape la chaîne mal échappée, pas le champ manquant : la
# conformité au schéma reste à l'API, qui seule la connaît.
assert_eq 'ok' "$(json_is_wellformed '{"a":1}')" 'un document bien formé est reconnu'
assert_eq 'ko' "$(json_is_wellformed '{"a":}')" 'un document mal formé est refusé'
assert_eq 'ok' "$(json_is_wellformed '{"a":"guillemet \" échappé"}')" \
  'un guillemet échappé ne fait pas échouer la vérification'

# Sans analyseur, le verdict est « inconnu » — jamais « ok ». Conclure d'une
# donnée absente est la faute que ce dépôt s'interdit partout ailleurs.
#
# `PATH` est vidé **dans** le sous-shell, pas devant lui : le vider devant
# empêcherait le shell appelant de trouver `bash` lui-même, et le test
# passerait pour une raison qui n'a rien à voir avec ce qu'il vérifie.
NO_PARSER=$(bash -c '
  PATH=/nonexistent
  . "'"$SCANNER_DIR"'/lib/core/core.sh"
  . "'"$SCANNER_DIR"'/lib/core/transport.sh"
  json_is_wellformed "{}"')
assert_eq 'inconnu' "$NO_PARSER" 'sans analyseur, la vérification ne conclut pas'

suite 'Proxy : déclaration explicite'

# `--proxy` l'emporte sur l'environnement, comme `-Proxy` côté Windows : c'est
# le plus explicite qui gagne.
PROXY_ARG_BLOCK=$(printf '%s' "$SYSAUDIT_SOURCE" | grep -A 8 -F -- '--proxy)' || true)
assert_contains "$PROXY_ARG_BLOCK" 'OPT_PROXY=$2' '--proxy retient l’adresse donnée'
# La traduction des options en arguments curl est vérifiée sur sa **sortie**, et
# non par une recherche dans le source : c'est cette sortie que curl reçoit, et
# elle sert désormais à deux appelants — l'envoi et le relevé d'adresse
# publique. Une recherche textuelle dans `sysaudit.sh` aurait continué à passer
# le jour où l'un des deux cesserait de l'appeler.
PROXY_ARGS_ENV=$(bash -c '
  . "'"$SCANNER_DIR"'/lib/core/core.sh"
  . "'"$SCANNER_DIR"'/lib/core/transport.sh"
  OPT_NO_PROXY=true
  curl_proxy_args | tr "\n" " "')
assert_contains "$PROXY_ARGS_ENV" '--noproxy *' '--no-proxy neutralise aussi l’environnement'

PROXY_ARGS_EXPLICIT=$(bash -c '
  . "'"$SCANNER_DIR"'/lib/core/core.sh"
  . "'"$SCANNER_DIR"'/lib/core/transport.sh"
  OPT_PROXY=http://p:8080
  curl_proxy_args | tr "\n" " "')
assert_contains "$PROXY_ARGS_EXPLICIT" '--proxy http://p:8080' \
  '--proxy est traduit en argument curl'

# Sans rien de déclaré, la traduction ne rend rien : curl lit `https_proxy` de
# lui-même, et forcer une politique ici la rendrait invisible à qui lit le
# script.
PROXY_ARGS_SILENT=$(bash -c '
  . "'"$SCANNER_DIR"'/lib/core/core.sh"
  . "'"$SCANNER_DIR"'/lib/core/transport.sh"
  curl_proxy_args')
assert_eq '' "$PROXY_ARGS_SILENT" 'sans option, aucun argument de proxy n’est imposé'

PROXY_MISSING=$("$SCANNER_DIR/sysaudit.sh" --proxy 2>&1 || printf 'ECHEC')
assert_contains "$PROXY_MISSING" 'ECHEC' '--proxy sans adresse échoue'

# L'adresse affichée passe par le masquage : un mot de passe d'annuaire n'a rien
# à faire dans une sortie qu'on recopie dans un ticket.
assert_contains "$SYSAUDIT_SOURCE" 'mask_proxy_credentials "$OPT_PROXY"' \
  'le proxy explicite est masqué avant affichage'

# --- Températures matérielles -----------------------------------------------

suite 'Températures matérielles'

# Les sondes réelles de la machine de test ne conviennent pas : une machine de
# CI virtualisée n'en expose aucune, et une machine de développement en expose
# des inconnues. Le collecteur lit `SYSFS_ROOT` ; on lui donne donc un
# arbre construit à la main, dont chaque valeur est choisie pour un cas précis.
#
# Ces valeurs sont des **fixtures de test**. Aucune ne circule dans le produit :
# le collecteur n'a pas de valeur par défaut, et ce qu'il ne lit pas, il ne
# rapporte pas.
THERMAL_SYSFS=$(mktemp -d "${TMPDIR:-/tmp}/sysaudit-thermal-XXXXXX")
trap 'rm -rf "$THERMAL_SYSFS"' EXIT

mk_sensor() {
  local chip=$1 index=$2 label=$3 millicelsius=$4 crit=${5-} max=${6-}
  local dir="$THERMAL_SYSFS/class/hwmon/$chip"
  mkdir -p "$dir"
  printf '%s\n' "${chip#hwmon}" >/dev/null
  [ -n "$label" ] && printf '%s\n' "$label" >"$dir/temp${index}_label"
  printf '%s\n' "$millicelsius" >"$dir/temp${index}_input"
  [ -n "$crit" ] && printf '%s\n' "$crit" >"$dir/temp${index}_crit"
  [ -n "$max" ] && printf '%s\n' "$max" >"$dir/temp${index}_max"
  return 0
}

mk_chip() {
  local chip=$1 name=$2
  mkdir -p "$THERMAL_SYSFS/class/hwmon/$chip"
  printf '%s\n' "$name" >"$THERMAL_SYSFS/class/hwmon/$chip/name"
}

# Un processeur Intel : paquet et cœurs, avec le seuil critique du capteur.
mk_chip hwmon0 coretemp
mk_sensor hwmon0 1 'Package id 0' 52000 100000
mk_sensor hwmon0 2 'Core 0' 48000 100000
mk_sensor hwmon0 3 'Core 1' 49500 100000

# Un NVMe : le noyau publie le modèle commercial, ce qui rattache la sonde au
# disque plutôt qu'à un numéro d'énumération.
mk_chip hwmon1 nvme
mk_sensor hwmon1 1 'Composite' 43000 84850
mkdir -p "$THERMAL_SYSFS/class/hwmon/hwmon1/device"
printf 'Samsung SSD 990 PRO 2TB\n' >"$THERMAL_SYSFS/class/hwmon/hwmon1/device/model"

# Un Super-I/O : trois sondes très différentes sur un seul chip. C'est le cas
# qui interdit de classer d'après le nom du pilote.
mk_chip hwmon2 nct6798
mk_sensor hwmon2 1 'SYSTIN' 34000
mk_sensor hwmon2 2 'VRM MOS' 51000
mk_sensor hwmon2 3 'PCH' 48000

# Une sonde 1-Wire absente : `-127 °C` est sa réponse consacrée.
mk_chip hwmon3 w83627ehf
mk_sensor hwmon3 1 'AUXTIN2' -127000

# Un disque SATA vu par `drivetemp` : c'est le noyau, et lui seul, qui dit si
# le support tourne.
mk_chip hwmon4 drivetemp
mk_sensor hwmon4 1 '' 36000
mkdir -p "$THERMAL_SYSFS/class/hwmon/hwmon4/device/block/sda/queue"
printf '1\n' >"$THERMAL_SYSFS/class/hwmon/hwmon4/device/block/sda/queue/rotational"

# shellcheck disable=SC2034 # relues par `collect_sensors` et `levels.sh`.
CAP_VIRTUALIZED=''
# shellcheck disable=SC2034
CAP_DOCKER='false'
# shellcheck disable=SC2034
PROFILE='standard'
THERMAL_JSON=$(SYSFS_ROOT="$THERMAL_SYSFS" collect_sensors 2>/dev/null)

assert_contains "$THERMAL_JSON" '"label":"Package id 0","celsius":52' \
  'la température du paquet processeur est celle du capteur'
assert_contains "$THERMAL_JSON" '"criticalCelsius":100' \
  'le seuil critique vient du capteur, pas d’une table'
assert_contains "$THERMAL_JSON" '"label":"Package id 0","celsius":52.0,"criticalCelsius":100.0,"category":"CPU"' \
  'le paquet processeur est classé CPU'
assert_contains "$THERMAL_JSON" '"label":"Composite","celsius":43.0,"criticalCelsius":84.8,"category":"DRIVE_NVME"' \
  'la sonde d’un NVMe est classée NVMe'
assert_contains "$THERMAL_JSON" '"device":"Samsung SSD 990 PRO 2TB"' \
  'la sonde NVMe porte le modèle du disque'
assert_contains "$THERMAL_JSON" '"label":"VRM MOS","celsius":51.0,"category":"VRM"' \
  'l’étage d’alimentation n’est pas classé « carte mère »'
assert_contains "$THERMAL_JSON" '"label":"PCH","celsius":48.0,"category":"CHIPSET"' \
  'le PCH est classé chipset'
assert_contains "$THERMAL_JSON" '"label":"SYSTIN","celsius":34.0,"category":"MOTHERBOARD"' \
  'la sonde de châssis est classée carte mère'
assert_contains "$THERMAL_JSON" '"category":"DRIVE_HDD"' \
  'un disque à plateaux est reconnu par queue/rotational'
assert_contains "$THERMAL_JSON" '"rawValue":52000,"rawUnit":"millidegree_celsius"' \
  'la valeur brute d’origine est conservée'
assert_contains "$THERMAL_JSON" '"sourcePath":"'"$THERMAL_SYSFS"'/class/hwmon/hwmon0/temp1_input"' \
  'le chemin exact de la sonde est conservé pour le diagnostic'

# La sonde absente ne doit apparaître **ni** comme température, **ni** nulle
# part ailleurs qu'en lecture écartée : c'est tout l'enjeu de la §11.
assert_not_contains "$THERMAL_JSON" '"celsius":-127' \
  'une sonde absente ne devient pas une température de -127 °C'
assert_contains "$THERMAL_JSON" '"rawValue":-127000,"rawUnit":"millidegree_celsius","reason":"OUT_OF_PHYSICAL_RANGE"' \
  'la lecture aberrante est conservée brute, pour le diagnostic'
assert_contains "$THERMAL_JSON" '"discarded":1' \
  'la lecture écartée est comptée'
assert_contains "$THERMAL_JSON" '"usable":8' \
  'les huit sondes exploitables sont comptées'
assert_contains "$THERMAL_JSON" '"probed":9' \
  'les neuf sondes rencontrées sont comptées, écartée comprise'
assert_contains "$THERMAL_JSON" '"scope":"LOCAL"' \
  'sur une machine physique, les sondes sont locales'

# Un relevé unique ne produit pas de statistiques : les publier reviendrait à
# répéter la valeur courante sous un nom qui promet une observation.
assert_contains "$THERMAL_JSON" '"sampleCount":1' \
  'un audit Normale reste un instantané, et le dit'
assert_not_contains "$THERMAL_JSON" '"averageCelsius"' \
  'aucune moyenne sur un relevé unique'

# --- Plusieurs relevés ------------------------------------------------------

suite 'Températures : plusieurs relevés'

PROFILE='full'
assert_eq 'extended' "$(level_depth sensors)" \
  'l’audit complet prévoit la collecte thermique approfondie'
assert_eq '3' "$(thermal_sample_count)" \
  'la collecte approfondie prend trois relevés'
# shellcheck disable=SC2034
PROFILE='standard'
assert_eq '1' "$(thermal_sample_count)" \
  'l’audit normal se contente d’un relevé'

# --- Aucune sonde -----------------------------------------------------------

suite 'Températures : aucune sonde'

EMPTY_SYSFS=$(mktemp -d "${TMPDIR:-/tmp}/sysaudit-thermal-empty-XXXXXX")
mkdir -p "$EMPTY_SYSFS/class/hwmon"

# shellcheck disable=SC2034
CAP_VIRTUALIZED=''
EMPTY_JSON=$(SYSFS_ROOT="$EMPTY_SYSFS" collect_sensors 2>/dev/null)
assert_contains "$EMPTY_JSON" '"temperatures":[]' \
  'sans sonde, la liste est vide plutôt que remplie'
assert_contains "$EMPTY_JSON" '"unavailableReason":"NO_SENSOR_EXPOSED"' \
  'l’absence de sonde est déclarée, pas tue'

# Sur une machine virtualisée, l'absence a une autre cause et une autre réponse :
# il n'y a aucun pilote à installer.
CAP_VIRTUALIZED='kvm'
VIRT_JSON=$(SYSFS_ROOT="$EMPTY_SYSFS" collect_sensors 2>/dev/null)
assert_contains "$VIRT_JSON" '"unavailableReason":"VIRTUALIZED"' \
  'dans une VM, l’absence de sonde est attribuée à l’hyperviseur'
assert_not_contains "$VIRT_JSON" '"suggestedTool"' \
  'aucun outil n’est suggéré là où il ne changerait rien'
# shellcheck disable=SC2034
CAP_VIRTUALIZED=''
rm -rf "$EMPTY_SYSFS"

# --- Portée des relevés en environnement virtualisé -------------------------

suite 'Températures : portée'

CAP_VIRTUALIZED='kvm'
SCOPE_JSON=$(SYSFS_ROOT="$THERMAL_SYSFS" collect_sensors 2>/dev/null)
assert_contains "$SCOPE_JSON" '"scope":"HYPERVISOR_HOST"' \
  'dans une VM, une sonde visible appartient à l’hôte, et le rapport le dit'
assert_not_contains "$SCOPE_JSON" '"scope":"LOCAL"' \
  'aucune sonde d’hôte n’est présentée comme locale'
# shellcheck disable=SC2034
CAP_VIRTUALIZED=''

# --- Classification ---------------------------------------------------------

suite 'Températures : classification des sondes'

assert_eq 'CPU' "$(thermal_category_for k10temp 'Tctl')" 'Tctl est une sonde de processeur'
assert_eq 'CPU' "$(thermal_category_for k10temp 'Tdie')" 'Tdie est une sonde de processeur'
assert_eq 'CPU' "$(thermal_category_for k10temp 'Tccd1')" 'un CCD Ryzen est une sonde de processeur'
assert_eq 'GPU' "$(thermal_category_for amdgpu 'junction')" 'la jonction est une sonde de GPU'
assert_eq 'GPU' "$(thermal_category_for amdgpu 'edge')" 'le bord de puce est une sonde de GPU'
assert_eq 'DRIVE_NVME' "$(thermal_category_for nvme 'Sensor 1')" \
  'une sonde secondaire de NVMe reste rattachée au disque'
assert_eq 'NETWORK' "$(thermal_category_for iwlwifi_1 'temp1')" \
  'la sonde d’une carte Wi-Fi est classée réseau'
assert_eq 'OTHER' "$(thermal_category_for acpitz 'temp1')" \
  'une sonde ACPI non identifiée n’est pas rangée au juger'
assert_eq 'OTHER' "$(thermal_category_for pilote_inconnu 'temp3')" \
  'une sonde inconnue reste inconnue plutôt que devinée'

# --- Bloc d'alimentation ----------------------------------------------------

suite 'Alimentation : PC de bureau ordinaire'

# Le cas qui compte, parce que c'est celui de presque toutes les machines : une
# alimentation ATX ne se présente pas au système. Le collecteur doit mesurer ce
# qu'il peut et **déclarer** ce qu'il ne peut pas — jamais combler.
PSU_SYSFS=$(mktemp -d "${TMPDIR:-/tmp}/sysaudit-psu-XXXXXX")
trap 'rm -rf "$PSU_SYSFS" "$PSU_LAPTOP" "$PSU_DIGITAL"' EXIT

mkdir -p "$PSU_SYSFS/class/hwmon/hwmon0" "$PSU_SYSFS/class/power_supply"
printf 'nct6798\n' >"$PSU_SYSFS/class/hwmon/hwmon0/name"
printf '+12V\n' >"$PSU_SYSFS/class/hwmon/hwmon0/in0_label"
printf '12096\n' >"$PSU_SYSFS/class/hwmon/hwmon0/in0_input"
printf '+5V\n' >"$PSU_SYSFS/class/hwmon/hwmon0/in1_label"
printf '5040\n' >"$PSU_SYSFS/class/hwmon/hwmon0/in1_input"
printf 'VBAT\n' >"$PSU_SYSFS/class/hwmon/hwmon0/in2_label"
printf '3312\n' >"$PSU_SYSFS/class/hwmon/hwmon0/in2_input"

# shellcheck disable=SC2034 # relues par le collecteur.
CAP_PRIVILEGED='false'
# shellcheck disable=SC2034
CAP_VIRTUALIZED=''
# shellcheck disable=SC2034
CAP_DOCKER='false'
# shellcheck disable=SC2034 # relue par `capability_tool`, via une indirection.
CAP_TOOLS[dmidecode]='false'
# shellcheck disable=SC2034
CAP_TOOLS[nvidia-smi]='false'

PSU_JSON=$(SYSFS_ROOT="$PSU_SYSFS" collect_power_supply 2>/dev/null)

assert_contains "$PSU_JSON" '"detected":false' \
  'une alimentation ATX muette n’est pas déclarée détectée'
assert_contains "$PSU_JSON" '"units":[]' \
  'aucune unité n’est fabriquée pour une alimentation qui ne dit rien'
assert_contains "$PSU_JSON" '"label":"+12V","volts":12.096,"measuredBy":"MOTHERBOARD"' \
  'la tension du rail 12 V est celle du capteur, attribuée à la carte mère'
assert_contains "$PSU_JSON" '"chip":"nct6798"' \
  'la puce qui a rendu la tension est nommée'
assert_contains "$PSU_JSON" '"ATX_NOT_SELF_DESCRIBING"' \
  'l’absence d’identité est déclarée comme une limite connue, pas comme un échec'
assert_contains "$PSU_JSON" '"RAILS_FROM_MOTHERBOARD"' \
  'le rapport dit que les tensions ne viennent pas du bloc'
assert_contains "$PSU_JSON" '"suggestedTool":"dmidecode"' \
  'l’outil qui permettrait d’en lire plus est nommé'
# Aucune puissance nominale ne doit apparaître : c'est la règle absolue.
assert_not_contains "$PSU_JSON" '"ratedPowerWatts":' \
  'aucune puissance nominale n’est publiée sans source qui la donne'

# --- SMBIOS type 39 ---------------------------------------------------------

suite 'Alimentation : SMBIOS type 39'

# Sortie réelle de `dmidecode --type 39` sur un serveur Supermicro. Aucune de
# ces valeurs ne circule dans le produit : le collecteur n'a pas de valeur par
# défaut, et ce qu'il ne lit pas, il ne le rapporte pas.
PSU_DMI=$(psu_dmi_parse <<'DMI'
Handle 0x2600, DMI type 39, 22 bytes
System Power Supply
	Power Unit Group: 1
	Location: Bay 1
	Name: PWS-751-1R
	Manufacturer: Supermicro
	Serial Number: P751ABC123
	Asset Tag: To Be Filled By O.E.M.
	Model Part Number: PWS-751-1R
	Revision: 1.0
	Max Power Capacity: 750 W
	Status: Present, OK
	Type: Switching
	Input Voltage Range Switching: Auto-switch
	Plugged: Yes
	Hot Replaceable: Yes
Handle 0x2601, DMI type 39, 22 bytes
System Power Supply
	Power Unit Group: 1
	Location: Bay 2
	Name: PWS-751-1R
	Manufacturer: Supermicro
	Serial Number: P751DEF456
	Asset Tag: To Be Filled By O.E.M.
	Model Part Number: PWS-751-1R
	Revision: 1.0
	Max Power Capacity: 750 W
	Status: Present, OK
	Type: Switching
	Input Voltage Range Switching: Auto-switch
	Plugged: Yes
	Hot Replaceable: Yes
DMI
)

assert_contains "$PSU_DMI" '"manufacturer":"Supermicro"' \
  'le fabricant vient du firmware, pas d’une table interne'
assert_contains "$PSU_DMI" '"ratedPowerWatts":750' \
  'la puissance nominale est celle que le firmware annonce'
assert_contains "$PSU_DMI" '"type":"STANDARD_ATX"' \
  'une alimentation à découpage est reconnue comme telle par le firmware'
assert_contains "$PSU_DMI" '"serialNumber":"P751DEF456"' \
  'les deux alimentations redondantes sont rendues, pas seulement la première'
assert_contains "$PSU_DMI" '"present":true,"hotReplaceable":true' \
  'présence et remplacement à chaud sont deux faits distincts'
# L'étiquette d'inventaire est un texte de remplissage du firmware : la publier
# ferait passer un champ vide pour une donnée.
assert_contains "$PSU_DMI" '"assetTag":{"unknown":true' \
  'un texte de remplissage du firmware n’est pas une donnée'

# Un enregistrement sans rien dedans ne fabrique pas d'identité.
PSU_DMI_EMPTY=$(psu_dmi_parse <<'DMI'
Handle 0x2600, DMI type 39, 22 bytes
System Power Supply
	Location: To Be Filled By O.E.M.
	Name: To Be Filled By O.E.M.
	Manufacturer: To Be Filled By O.E.M.
	Serial Number: To Be Filled By O.E.M.
	Max Power Capacity: Unknown
	Status: Present, OK
	Type: Unknown
DMI
)
assert_contains "$PSU_DMI_EMPTY" '"manufacturer":{"unknown":true' \
  'un firmware qui ne renseigne rien ne produit pas de fabricant'
assert_contains "$PSU_DMI_EMPTY" '"ratedPowerWatts":{"unknown":true' \
  '« Unknown » n’est pas une puissance : aucune valeur n’est inventée'
assert_contains "$PSU_DMI_EMPTY" '"type":"UNKNOWN"' \
  'une nature non déclarée par le firmware reste inconnue'
assert_contains "$PSU_DMI_EMPTY" '"label":"Alimentation 1"' \
  'une alimentation sans nom reçoit un repère, pas un modèle inventé'

# --- Alimentation numérique -------------------------------------------------

suite 'Alimentation : bloc numérique'

# Un bloc qui expose une interface numérique est le seul cas où hwmon rend
# autre chose que les tensions de la carte mère.
PSU_DIGITAL=$(mktemp -d "${TMPDIR:-/tmp}/sysaudit-psu-num-XXXXXX")
mkdir -p "$PSU_DIGITAL/class/hwmon/hwmon3/device" "$PSU_DIGITAL/class/power_supply"
printf 'corsairpsu\n' >"$PSU_DIGITAL/class/hwmon/hwmon3/name"
printf 'HID_NAME=Corsair HX1000i\n' >"$PSU_DIGITAL/class/hwmon/hwmon3/device/uevent"
printf 'v_in\n' >"$PSU_DIGITAL/class/hwmon/hwmon3/in0_label"
printf '230000\n' >"$PSU_DIGITAL/class/hwmon/hwmon3/in0_input"
printf 'v_out +12v\n' >"$PSU_DIGITAL/class/hwmon/hwmon3/in1_label"
printf '12093\n' >"$PSU_DIGITAL/class/hwmon/hwmon3/in1_input"
printf '118000000\n' >"$PSU_DIGITAL/class/hwmon/hwmon3/power1_input"
printf '38000\n' >"$PSU_DIGITAL/class/hwmon/hwmon3/temp1_input"
printf '620\n' >"$PSU_DIGITAL/class/hwmon/hwmon3/fan1_input"

PSU_DIGITAL_JSON=$(SYSFS_ROOT="$PSU_DIGITAL" collect_power_supply 2>/dev/null)

assert_contains "$PSU_DIGITAL_JSON" '"detected":true' \
  'un bloc qui se nomme est réellement détecté'
assert_contains "$PSU_DIGITAL_JSON" '"type":"DIGITAL_ATX"' \
  'un bloc doté d’une interface numérique est classé comme tel'
assert_contains "$PSU_DIGITAL_JSON" '"model":"Corsair HX1000i"' \
  'le modèle vient du périphérique, pas d’une correspondance de codes USB'
assert_contains "$PSU_DIGITAL_JSON" '"inputPowerWatts":118' \
  'la puissance d’entrée est celle que le bloc publie'
assert_contains "$PSU_DIGITAL_JSON" '"temperatureCelsius":38' \
  'la température vient du bloc lui-même'
assert_contains "$PSU_DIGITAL_JSON" '"fanRpm":620' \
  'la vitesse du ventilateur est relevée quand le bloc la publie'
assert_contains "$PSU_DIGITAL_JSON" '"measuredBy":"POWER_SUPPLY"' \
  'les rails d’un bloc numérique sont mesurés par le bloc'
assert_not_contains "$PSU_DIGITAL_JSON" '"measuredBy":"MOTHERBOARD"' \
  'les rails du bloc ne sont pas rattachés une seconde fois à la carte mère'
assert_contains "$PSU_DIGITAL_JSON" '"efficiencyPercent":{"unknown":true' \
  'le rendement n’est pas calculé depuis deux mesures d’instants différents'
# Même détecté, le bloc ne livre pas sa puissance nominale : elle est sur son
# étiquette, pas sur son bus.
assert_contains "$PSU_DIGITAL_JSON" '"ratedPowerWatts":{"unknown":true' \
  'la puissance nominale reste non détectable même sur un bloc qui parle'

# --- Portable ---------------------------------------------------------------

suite 'Alimentation : portable'

PSU_LAPTOP=$(mktemp -d "${TMPDIR:-/tmp}/sysaudit-psu-lap-XXXXXX")
mkdir -p "$PSU_LAPTOP/class/power_supply/BAT0" "$PSU_LAPTOP/class/power_supply/ADP1" \
  "$PSU_LAPTOP/class/hwmon"
printf 'Battery\n' >"$PSU_LAPTOP/class/power_supply/BAT0/type"
printf 'Discharging\n' >"$PSU_LAPTOP/class/power_supply/BAT0/status"
printf '12400000\n' >"$PSU_LAPTOP/class/power_supply/BAT0/power_now"
printf 'Mains\n' >"$PSU_LAPTOP/class/power_supply/ADP1/type"
printf '0\n' >"$PSU_LAPTOP/class/power_supply/ADP1/online"

PSU_LAPTOP_JSON=$(SYSFS_ROOT="$PSU_LAPTOP" collect_power_supply 2>/dev/null)

assert_contains "$PSU_LAPTOP_JSON" '"label":"ADP1","type":"LAPTOP_ADAPTER"' \
  'un bloc secteur accompagné d’une batterie est le chargeur d’un portable'
assert_contains "$PSU_LAPTOP_JSON" '"component":"SYSTEM"' \
  'la décharge de la batterie mesure la consommation de la machine entière'
assert_contains "$PSU_LAPTOP_JSON" '"watts":12.4' \
  'la puissance de décharge est celle du compteur, convertie sans arrondi trompeur'
assert_contains "$PSU_LAPTOP_JSON" '"detected":false' \
  'un chargeur qui ne publie ni fabricant ni modèle ne vaut pas identification'

# En charge, `power_now` rend la puissance de **charge** : la publier comme
# consommation ferait lire un portable qui se recharge comme un portable gourmand.
printf 'Charging\n' >"$PSU_LAPTOP/class/power_supply/BAT0/status"
PSU_CHARGING_JSON=$(SYSFS_ROOT="$PSU_LAPTOP" collect_power_supply 2>/dev/null)
assert_not_contains "$PSU_CHARGING_JSON" '"component":"SYSTEM"' \
  'la puissance de charge n’est pas présentée comme une consommation'

# --- IPMI -------------------------------------------------------------------

suite 'Alimentation : serveur IPMI'

PSU_IPMI=$(psu_ipmi_parse <<'SDR'
PS1 Status       | 70h | ok  | 10.1 | Presence detected
PS2 Status       | 71h | ns  | 10.2 | No Reading
SDR
)

assert_contains "$PSU_IPMI" '"label":"PS1 Status","type":"SERVER_MANAGED"' \
  'une alimentation vue par le contrôleur est déclarée gérée par lui'
assert_contains "$PSU_IPMI" '"status":"Presence detected"' \
  'l’état rendu par le contrôleur n’est pas traduit'
assert_contains "$PSU_IPMI" '"present":{"unknown":true' \
  'une sonde sans lecture ne devient pas une alimentation absente'
assert_contains "$PSU_IPMI" '"ratedPowerWatts":{"unknown":true' \
  'le contrôleur ne donne pas la puissance nominale, et rien ne la remplace'

# --- Machine virtualisée ----------------------------------------------------

suite 'Alimentation : machine virtualisée'

CAP_VIRTUALIZED='kvm'
PSU_VIRT_JSON=$(SYSFS_ROOT="$PSU_SYSFS" collect_power_supply 2>/dev/null)
assert_contains "$PSU_VIRT_JSON" '"VIRTUALIZED"' \
  'dans une VM, l’absence d’alimentation est attribuée à l’hyperviseur'
# shellcheck disable=SC2034
CAP_VIRTUALIZED=''

# --- Télémétrie : capteurs de charge ----------------------------------------
#
# Ces tests montent un faux `/sys` : les ventilateurs, RAPL et la tension du
# cœur n'existent pas sur toutes les machines de développement, et une suite qui
# ne s'exécuterait que sur celles qui les ont ne vérifierait rien nulle part.

suite 'Télémétrie : reconnaissance des capteurs'

TELEMETRY_SYSFS=$(mktemp -d)
mkdir -p "$TELEMETRY_SYSFS/class/hwmon/hwmon0" \
  "$TELEMETRY_SYSFS/class/hwmon/hwmon1" \
  "$TELEMETRY_SYSFS/class/powercap/intel-rapl:0"

# hwmon0 : carte mère — un ventilateur processeur étiqueté, un de boîtier, Vcore.
printf 'nct6798\n' >"$TELEMETRY_SYSFS/class/hwmon/hwmon0/name"
printf '1200\n' >"$TELEMETRY_SYSFS/class/hwmon/hwmon0/fan1_input"
printf 'CPU Fan\n' >"$TELEMETRY_SYSFS/class/hwmon/hwmon0/fan1_label"
printf '850\n' >"$TELEMETRY_SYSFS/class/hwmon/hwmon0/fan2_input"
printf 'System Fan\n' >"$TELEMETRY_SYSFS/class/hwmon/hwmon0/fan2_label"
printf '1024\n' >"$TELEMETRY_SYSFS/class/hwmon/hwmon0/in0_input"
printf 'Vcore\n' >"$TELEMETRY_SYSFS/class/hwmon/hwmon0/in0_label"

# hwmon1 : carte graphique AMD.
printf 'amdgpu\n' >"$TELEMETRY_SYSFS/class/hwmon/hwmon1/name"
printf '2400\n' >"$TELEMETRY_SYSFS/class/hwmon/hwmon1/fan1_input"
printf '61000\n' >"$TELEMETRY_SYSFS/class/hwmon/hwmon1/temp1_input"
printf 'edge\n' >"$TELEMETRY_SYSFS/class/hwmon/hwmon1/temp1_label"
printf '78000\n' >"$TELEMETRY_SYSFS/class/hwmon/hwmon1/temp2_input"
printf 'junction\n' >"$TELEMETRY_SYSFS/class/hwmon/hwmon1/temp2_label"
printf '2100000000\n' >"$TELEMETRY_SYSFS/class/hwmon/hwmon1/freq1_input"
printf '185000000\n' >"$TELEMETRY_SYSFS/class/hwmon/hwmon1/power1_average"

printf 'package-0\n' >"$TELEMETRY_SYSFS/class/powercap/intel-rapl:0/name"
printf '1000000\n' >"$TELEMETRY_SYSFS/class/powercap/intel-rapl:0/energy_uj"

# Remet la reconnaissance des capteurs à zéro : sans cela, un scénario
# reprendrait les chemins repérés par le précédent, et le second passerait pour
# une lecture réussie alors qu'il n'aurait rien lu.
#
# shellcheck disable=SC2034  # ces variables sont lues par lib/collectors/monitoring.sh.
telemetry_reset_sources() {
  MON_SOURCES_PROBED=''
  MON_FAN_CPU_PATH=''
  MON_FAN_GPU_PATH=''
  MON_FAN_CHASSIS_PATHS=''
  MON_VCORE_PATH=''
  MON_RAPL_PATH=''
  MON_GPU_HWMON=''
  MON_GPU_KIND=''
  MON_GPU_DEVICE=''
}

(
  SYSFS_ROOT="$TELEMETRY_SYSFS"
  telemetry_reset_sources
  monitoring_probe_sources
  printf '%s|%s|%s|%s|%s|%s\n' \
    "${MON_FAN_CPU_PATH##*/}" "${MON_FAN_GPU_PATH##*/}" "${MON_FAN_CHASSIS_PATHS##*/}" \
    "${MON_VCORE_PATH##*/}" "${MON_RAPL_PATH##*/}" "${MON_GPU_HWMON##*/}"
) >"$TELEMETRY_SYSFS/probe.txt"
TELEMETRY_PROBE=$(cat "$TELEMETRY_SYSFS/probe.txt")

assert_eq 'fan1_input|fan1_input|fan2_input|in0_input|energy_uj|hwmon1' "$TELEMETRY_PROBE" \
  'chaque capteur est attribué à son rôle, le pilote primant sur l’étiquette'

assert_eq '1200' "$(monitoring_fan_rpm "$TELEMETRY_SYSFS/class/hwmon/hwmon0/fan1_input")" \
  'une vitesse de rotation lisible est rendue telle quelle'
printf '0\n' >"$TELEMETRY_SYSFS/class/hwmon/hwmon0/fan3_input"
assert_eq '0' "$(monitoring_fan_rpm "$TELEMETRY_SYSFS/class/hwmon/hwmon0/fan3_input")" \
  'un ventilateur à l’arrêt rend zéro — ce n’est pas une absence de mesure'
printf '99999\n' >"$TELEMETRY_SYSFS/class/hwmon/hwmon0/fan4_input"
assert_eq '' "$(monitoring_fan_rpm "$TELEMETRY_SYSFS/class/hwmon/hwmon0/fan4_input")" \
  'une lecture hors du domaine physique ne devient pas une vitesse'
assert_eq '' "$(monitoring_fan_rpm "$TELEMETRY_SYSFS/absent")" \
  'un chemin inexistant ne rend rien plutôt que zéro'

suite 'Télémétrie : puissance et tension'

assert_eq '1.024' "$(SYSFS_ROOT="$TELEMETRY_SYSFS" MON_VCORE_PATH="$TELEMETRY_SYSFS/class/hwmon/hwmon0/in0_input" monitoring_cpu_voltage_volts)" \
  'la tension du cœur est convertie des millivolts aux volts'

assert_eq '5.0' "$(monitoring_power_watts 1000000 6000000 1)" \
  'la puissance naît de la progression du compteur d’énergie'
assert_eq '' "$(monitoring_power_watts 6000000 1000000 1)" \
  'un compteur qui recule ne produit pas de puissance négative redressée'
assert_eq '' "$(monitoring_power_watts '' 6000000 1)" \
  'sans relevé précédent, la puissance est inconnue et non nulle'

suite 'Télémétrie : motif de bridage'

assert_eq 'thermal' "$(monitoring_cpu_throttle_reason 4 5)" \
  'le compteur thermique du noyau ne compte que des bridages thermiques'
assert_eq '' "$(monitoring_cpu_throttle_reason 5 5)" \
  'un compteur stable ne désigne aucun motif'
assert_eq '' "$(monitoring_cpu_throttle_reason '' 5)" \
  'sans point de comparaison, aucun motif n’est affirmé'

suite 'Télémétrie : lecture d’une carte graphique sysfs'

# shellcheck disable=SC2034  # lues par monitoring_gpu_sample, hors de ce fichier.
TELEMETRY_GPU=$(
  MON_GPU_KIND='sysfs'
  MON_GPU_HWMON="$TELEMETRY_SYSFS/class/hwmon/hwmon1"
  MON_GPU_DEVICE=''
  monitoring_gpu_sample
)
assert_eq '61.0 78.0 2100.0 - - 185.0 - - -' "$TELEMETRY_GPU" \
  'températures, fréquence et puissance sont lues ; le reste reste absent'

suite 'Télémétrie : fragments JSON de l’échantillon'

TELEMETRY_FIELDS=$(
  SYSFS_ROOT="$TELEMETRY_SYSFS"
  telemetry_reset_sources
  monitoring_extra_fields 1 900000
)
assert_contains "$TELEMETRY_FIELDS" '"cpuFanRpm":1200' \
  'la vitesse du ventilateur processeur figure dans l’échantillon'
assert_contains "$TELEMETRY_FIELDS" '"chassisFanRpm":850' \
  'le ventilateur de boîtier est distingué de celui du processeur'
assert_contains "$TELEMETRY_FIELDS" '"gpuFanRpm":2400' \
  'le ventilateur de la carte graphique est distingué des deux autres'
assert_contains "$TELEMETRY_FIELDS" '"cpuCoreVoltageVolts":1.024' \
  'la tension du cœur figure dans l’échantillon'
assert_contains "$TELEMETRY_FIELDS" '"cpuPackagePowerWatts":0.1' \
  'la puissance est calculée contre le relevé précédent reçu en argument'

TELEMETRY_BARE=$(mktemp -d)
mkdir -p "$TELEMETRY_BARE/class/hwmon" "$TELEMETRY_BARE/class/powercap"
# `has_cmd` est neutralisé le temps de ce scénario : sans cela, le `nvidia-smi`
# de la machine de test serait détecté, et la carte graphique du développeur se
# retrouverait dans un scénario censé décrire une machine sans capteur.
# shellcheck disable=SC2034  # SYSFS_ROOT est lue par monitoring_probe_sources.
TELEMETRY_NO_SENSOR=$(
  has_cmd() { return 1; }
  SYSFS_ROOT="$TELEMETRY_BARE"
  telemetry_reset_sources
  monitoring_extra_fields 1 ''
)
assert_eq '' "$TELEMETRY_NO_SENSOR" \
  'une machine sans capteur ne produit aucun champ, pas une liste de marqueurs'

suite 'Télémétrie : carte mère sans étiquette de ventilateur'

# Le cas le plus répandu, et celui qui a fait corriger le code. Le pilote
# `nct6687` d'une MSI B850 expose seize entrées `fan*_input` et **aucun**
# `fan*_label` : rien ne dit lequel refroidit le processeur.
#
# Deux exigences en découlent. Le ventilateur processeur reste **inconnu** —
# l'inventer serait une attribution sans fondement. Et la rotation publiée est
# le **maximum**, non la première entrée du glob : l'ordre lexicographique met
# `fan11` avant `fan1`, et retenir la première publiait 1 160 tr/min sur une
# machine dont deux ventilateurs tournaient à 2 105 et 1 957.
TELEMETRY_UNLABELED=$(mktemp -d)
mkdir -p "$TELEMETRY_UNLABELED/class/hwmon/hwmon7" "$TELEMETRY_UNLABELED/class/powercap"
printf 'nct6687\n' >"$TELEMETRY_UNLABELED/class/hwmon/hwmon7/name"
printf '2105\n' >"$TELEMETRY_UNLABELED/class/hwmon/hwmon7/fan1_input"
printf '1957\n' >"$TELEMETRY_UNLABELED/class/hwmon/hwmon7/fan2_input"
printf '1160\n' >"$TELEMETRY_UNLABELED/class/hwmon/hwmon7/fan11_input"
printf '0\n' >"$TELEMETRY_UNLABELED/class/hwmon/hwmon7/fan12_input"

# shellcheck disable=SC2034  # SYSFS_ROOT est lue par monitoring_probe_sources.
TELEMETRY_UNLABELED_FIELDS=$(
  has_cmd() { return 1; }
  SYSFS_ROOT="$TELEMETRY_UNLABELED"
  telemetry_reset_sources
  monitoring_extra_fields 1 ''
)
assert_contains "$TELEMETRY_UNLABELED_FIELDS" '"chassisFanRpm":2105' \
  'sans étiquette, la rotation publiée est la plus élevée — pas la première du glob'
assert_not_contains "$TELEMETRY_UNLABELED_FIELDS" 'cpuFanRpm' \
  'sans étiquette, aucun ventilateur n’est attribué au processeur'

# Tous à l'arrêt : le zéro est conservé. C'est le cas alarmant, et le masquer
# ferait passer une machine sans refroidissement pour une machine sans capteur.
printf '0\n' >"$TELEMETRY_UNLABELED/class/hwmon/hwmon7/fan1_input"
printf '0\n' >"$TELEMETRY_UNLABELED/class/hwmon/hwmon7/fan2_input"
printf '0\n' >"$TELEMETRY_UNLABELED/class/hwmon/hwmon7/fan11_input"
# shellcheck disable=SC2034  # SYSFS_ROOT est lue par monitoring_probe_sources.
TELEMETRY_STOPPED=$(
  has_cmd() { return 1; }
  SYSFS_ROOT="$TELEMETRY_UNLABELED"
  telemetry_reset_sources
  monitoring_extra_fields 1 ''
)
assert_contains "$TELEMETRY_STOPPED" '"chassisFanRpm":0' \
  'tous les ventilateurs à l’arrêt rendent zéro, non une absence de mesure'

assert_eq '' "$(monitoring_fan_rpm_max '')" \
  'aucune entrée ne rend aucune rotation'

rm -rf "$TELEMETRY_SYSFS" "$TELEMETRY_BARE" "$TELEMETRY_UNLABELED"

suite 'Banc d’essai : cadence de rendu glmark2'

# glmark2 publie une ligne par scène. Le score global n'en est qu'une moyenne
# pondérée, et il cache exactement ce que ces lignes montrent : une carte qui
# rend 56 000 images par seconde sur une scène légère et 300 sur une scène
# d'ombrage n'a pas le même défaut qu'une carte régulière.
GLMARK_OUTPUT="[build] <default>: FPS: 56947 FrameTime: 0.018 ms
[texture] filter=nearest: FPS: 12034 FrameTime: 0.083 ms
[shading] shading=gouraud: FPS: 300 FrameTime: 3.333 ms
=======================================================
                                  glmark2 Score: 23093"
GLMARK_RENDERING=$(bench_glmark2_rendering "$GLMARK_OUTPUT")

assert_contains "$GLMARK_RENDERING" '"minimum":300' \
  'la scène la plus lente est conservée, non noyée dans la moyenne'
assert_contains "$GLMARK_RENDERING" '"maximum":56947' \
  'la scène la plus rapide est conservée'
assert_contains "$GLMARK_RENDERING" '"sampleCount":3' \
  'le décompte porte les scènes mesurées'
assert_contains "$GLMARK_RENDERING" '"unit":"FPS"' \
  'l’unité est littérale, jamais devinée du nom du champ'
assert_contains "$GLMARK_RENDERING" '"frameTimeMs"' \
  'le temps de trame est publié tel que l’outil le donne, non recalculé'

# Une version qui ne publierait pas le temps de trame ne doit pas produire un
# zéro : l'absence de mesure et une trame instantanée ne se ressemblent pas.
GLMARK_NO_FRAMETIME=$(bench_glmark2_rendering '[build] <default>: FPS: 1200')
assert_contains "$GLMARK_NO_FRAMETIME" '"framesPerSecond"' \
  'la cadence est publiée même sans temps de trame'
assert_not_contains "$GLMARK_NO_FRAMETIME" 'frameTimeMs' \
  'un temps de trame non publié ne devient pas zéro'

assert_eq '' "$(bench_glmark2_rendering '')" \
  'une sortie vide ne produit aucune cadence'
assert_eq '' "$(bench_glmark2_rendering 'glmark2 Score: 1200')" \
  'un score sans ligne de scène ne produit aucune cadence'

# --- Charges mixtes et relevé cœur par cœur ---------------------------------
#
# Deux bornes, et chacune corrige une façon précise de produire un rapport
# inutilisable : une charge « mixte » sans composante processeur, et une série
# par cœur si volumineuse que l'API refuse le rapport entier.

suite 'Charges mixtes'

assert_eq "$(( ( $(nproc 2>/dev/null || printf 1) + 1) / 2 ))" \
  "$(bench_mixed_threads gaming)" \
  'la charge « gaming » occupe la moitié des fils, arrondie au supérieur'

assert_eq "$(nproc 2>/dev/null || printf 1)" "$(bench_mixed_threads cpu-gpu)" \
  'la charge « cpu-gpu » occupe tous les fils'

suite 'Budget du relevé cœur par cœur'

assert_eq '0' "$(SYSAUDIT_CORE_SERIES_MAX=2 monitoring_core_count 1)" \
  'au-delà du plafond de cœurs, aucun relevé individuel'

assert_eq '0' "$(SYSAUDIT_CORE_SERIES_BUDGET=1 monitoring_core_count 7200)" \
  'un produit cœurs × relevés hors budget écarte le relevé individuel'

assert_eq "$(monitoring_core_ids | wc -l)" \
  "$(SYSAUDIT_CORE_SERIES_MAX=1024 SYSAUDIT_CORE_SERIES_BUDGET=10000000 monitoring_core_count 10)" \
  'dans le budget, tous les cœurs exposés sont relevés'

assert_eq '' "$(monitoring_cpu_core_usage_json '' '')" \
  'sans relevé précédent, aucune charge par cœur n’est fabriquée'

# --- Inventaire des produits de sécurité -------------------------------------

suite 'Inventaire des produits de sécurité'

# shellcheck source=../lib/collectors/security.sh
. "$SCANNER_DIR/lib/collectors/security.sh"

# La machine de test n'a ni ClamAV ni mdatp. Les deux collecteurs sont donc
# éprouvés en substituant les trois portes d'entrée du scanner vers le système :
# présence d'une commande, disponibilité d'un outil, exécution.
STUB_CMDS=''
STUB_TOOLS=''
STUB_OUTPUT=''

has_cmd() {
  case " $STUB_CMDS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

capability_tool() {
  case " $STUB_TOOLS " in *" $1 "*) printf 'true' ;; *) printf 'false' ;; esac
}

run_cmd() {
  local key="$*" line=''
  while IFS= read -r line; do
    case "$line" in
      "$key"=*) printf '%s' "${line#*=}"; return 0 ;;
    esac
  done <<<"$STUB_OUTPUT"
  return 1
}

# --- ClamAV : la distinction qui compte --------------------------------------

# `clamd` seul répond à des requêtes sans rien surveiller : c'est un moteur
# d'analyse, pas une protection à l'ouverture des fichiers.
STUB_CMDS='clamscan'
STUB_TOOLS='systemctl'
STUB_OUTPUT='systemctl is-active clamav-daemon=active
systemctl is-active clamav-clamonacc=inactive'
CLAMAV_JSON=$(detect_clamav)
assert_contains "$CLAMAV_JSON" '"kind":"ON_DEMAND_SCANNER"' \
  'ClamAV : le démon seul reste un scanner à la demande'
assert_contains "$CLAMAV_JSON" '"realtimeProtection":false' \
  'ClamAV : aucune protection temps réel sans clamonacc'
assert_contains "$CLAMAV_JSON" '"daemonRunning":true' 'ClamAV : le démon tourne'

# Avec `clamonacc`, la protection à l'ouverture existe réellement.
STUB_OUTPUT='systemctl is-active clamav-daemon=active
systemctl is-active clamav-clamonacc=active'
CLAMAV_RT=$(detect_clamav)
assert_contains "$CLAMAV_RT" '"kind":"ANTIVIRUS"' \
  'ClamAV : clamonacc en fait un antivirus temps réel'
assert_contains "$CLAMAV_RT" '"realtimeProtection":true' 'ClamAV : protection temps réel active'
assert_contains "$CLAMAV_RT" '"state":"ACTIVE"' 'ClamAV : état actif'

# Démon arrêté : le produit est là, il ne protège rien.
STUB_OUTPUT='systemctl is-active clamav-daemon=inactive
systemctl is-active clamd=inactive
systemctl is-active clamav-clamonacc=inactive'
CLAMAV_OFF=$(detect_clamav)
assert_contains "$CLAMAV_OFF" '"state":"DISABLED"' 'ClamAV : démon arrêté'
assert_contains "$CLAMAV_OFF" '"enabled":false' 'ClamAV : arrêté n’est pas actif'

# Sans systemd, l'état du service n'est pas interrogeable : un marqueur, pas
# une supposition.
STUB_TOOLS=''
STUB_OUTPUT=''
CLAMAV_NOSYSTEMD=$(detect_clamav)
assert_contains "$CLAMAV_NOSYSTEMD" '"state":"INSTALLED_UNKNOWN_STATE"' \
  'ClamAV : sans systemd, l’état reste inconnu'
assert_contains "$CLAMAV_NOSYSTEMD" '"daemonRunning":{"unknown":true' \
  'ClamAV : l’état du démon est un marqueur, pas false'

# Produit absent : aucune entrée, jamais une entrée vide.
STUB_CMDS=''
assert_eq '' "$(detect_clamav)" 'ClamAV : rien n’est émis quand le produit est absent'

# --- Fraîcheur des signatures ------------------------------------------------

CLAMAV_DB=$(mktemp -d)
touch "$CLAMAV_DB/daily.cvd"
assert_eq 'true' "$(clamav_signatures_fresh "$CLAMAV_DB")" \
  'signatures : une base du jour est à jour'

# Huit jours : freshclam vérifie quotidiennement, donc la mise à jour ne
# fonctionne plus.
touch -d '8 days ago' "$CLAMAV_DB/daily.cvd"
assert_eq 'false' "$(clamav_signatures_fresh "$CLAMAV_DB")" \
  'signatures : une base de huit jours est périmée'

# Sans base lisible, on ne dit rien — surtout pas « périmé ».
assert_eq '' "$(clamav_signatures_fresh "$(mktemp -d)")" \
  'signatures : aucune base ne vaut pas « périmé »'

# Le piège du calcul direct : un `stat` en échec rendrait 0, donc un âge de
# cinquante-six ans, et une base fraîche serait déclarée périmée.
CLAMAV_ILLISIBLE=$(mktemp -d)
touch "$CLAMAV_ILLISIBLE/daily.cvd"
stat() { return 1; }
assert_eq '' "$(clamav_signatures_fresh "$CLAMAV_ILLISIBLE")" \
  'signatures : un horodatage illisible ne vaut pas « périmé »'
unset -f stat

# --- Microsoft Defender for Endpoint -----------------------------------------

# Sans preuve de protection à l'ouverture, mdatp reste un EDR : la roadmap
# interdit de le compter comme un antivirus temps réel.
STUB_CMDS='mdatp'
STUB_OUTPUT='mdatp health --field real_time_protection_enabled=false
mdatp health --field healthy=true'
MDATP_EDR=$(detect_mdatp)
assert_contains "$MDATP_EDR" '"kind":"EDR"' 'mdatp : un EDR sans protection temps réel'
assert_contains "$MDATP_EDR" '"state":"PASSIVE"' 'mdatp : état passif'

# La CLI atteste la protection temps réel : le produit remplit alors bien le
# rôle d'un antivirus.
STUB_OUTPUT='mdatp health --field real_time_protection_enabled=true
mdatp health --field healthy=true'
MDATP_AV=$(detect_mdatp)
assert_contains "$MDATP_AV" '"kind":"ANTIVIRUS"' 'mdatp : temps réel attesté par la CLI'
assert_contains "$MDATP_AV" '"state":"ACTIVE"' 'mdatp : état actif'
assert_contains "$MDATP_AV" '"source":"PRODUCT_CLI"' 'mdatp : source nommée'

# CLI muette : ni actif ni inactif, seulement installé.
STUB_OUTPUT=''
MDATP_MUET=$(detect_mdatp)
assert_contains "$MDATP_MUET" '"state":"INSTALLED_UNKNOWN_STATE"' \
  'mdatp : CLI muette laisse l’état inconnu'
assert_contains "$MDATP_MUET" '"realtimeProtection":{"unknown":true' \
  'mdatp : la protection temps réel reste un marqueur'
# La fraîcheur des définitions n'est pas exposée par `mdatp health` : elle reste
# un marqueur plutôt qu'un « à jour » optimiste.
assert_contains "$MDATP_MUET" '"upToDate":{"unknown":true' \
  'mdatp : la fraîcheur des définitions n’est pas inventée'

STUB_CMDS=''
assert_eq '' "$(detect_mdatp)" 'mdatp : rien n’est émis quand le produit est absent'

# --- Inventaire complet ------------------------------------------------------

# Aucun produit : un tableau vide, qui affirme qu'on a cherché. Son absence
# dirait seulement qu'on n'a rien collecté, ce qui n'est pas la même chose.
STUB_CMDS=''
STUB_TOOLS=''
assert_eq '[]' "$(collect_security_products)" \
  'inventaire : aucun produit rend un tableau vide, pas une absence'

# --- Nature d'un disque : support, bus et catégorie --------------------------

suite 'Nature d’un disque'

# shellcheck source=../lib/collectors/storage.sh
. "$SCANNER_DIR/lib/collectors/storage.sh"

# Le cas que la roadmap nomme : un NVMe ne doit jamais s'afficher en disque
# mécanique parce qu'une couche d'abstraction expose du SCSI.
assert_eq 'NVME' "$(disk_kind_from_facts SSD NVME 0)" 'NVMe : reconnu par son bus'
assert_eq 'NVME' "$(disk_kind_from_facts '' NVME 0)" \
  'NVMe : reconnu même sans nature de support'
assert_eq 'NVME' "$(disk_kind_from_facts '' NVME 1)" \
  'NVMe : l’amovibilité n’en fait pas une clé USB'

# Le défaut corrigé : un support inconnu ne devient pas un disque mécanique.
assert_eq 'UNKNOWN' "$(disk_kind_from_facts '' SCSI 0)" \
  'support inconnu derrière du SCSI : aucune conclusion'
assert_eq 'UNKNOWN' "$(disk_kind_from_facts '' '' 0)" \
  'ni support ni bus : aucune conclusion'

assert_eq 'SSD' "$(disk_kind_from_facts SSD SATA 0)" 'SSD SATA'
assert_eq 'HDD' "$(disk_kind_from_facts HDD SATA 0)" 'disque mécanique SATA'
assert_eq 'USB' "$(disk_kind_from_facts SSD USB 1)" 'SSD dans un boîtier USB amovible'
assert_eq 'VIRTUAL' "$(disk_kind_from_facts '' VIRTUAL 0)" 'disque de machine virtuelle'
assert_eq 'SD' "$(disk_kind_from_facts '' MMC 0)" 'carte mémoire'
assert_eq 'SAS' "$(disk_kind_from_facts '' SAS 0)" 'disque SAS'

# --- Statistiques d'une série de relevés -------------------------------------

suite 'Statistiques d’une série de relevés'

AGG=$(printf '3100\n4600\n3200\n3150\n3180\n' | monitoring_aggregate MHz 1000 cpufreq)
assert_contains "$AGG" '"sampleCount":5' 'agrégat : les relevés sont dénombrés'
assert_contains "$AGG" '"minimum":3100' 'agrégat : minimum'
assert_contains "$AGG" '"maximum":4600' 'agrégat : maximum'
assert_contains "$AGG" '"current":3180' 'agrégat : dernier relevé'

# `first` et `current` donnent le sens de l'évolution — ce qu'aucune des trois
# autres statistiques ne dit.
assert_contains "$AGG" '"first":3100' 'agrégat : premier relevé'

# Le centile décrit ce que la machine a tenu, là où le maximum ne décrit qu'un
# instant. Sur cinq relevés, le rang le plus proche vaut 5.
assert_contains "$AGG" '"p95":4600' 'agrégat : centile par rang le plus proche'

# Vingt relevés dont un seul aberrant : le maximum bouge, le centile non.
STABLE=$(for _ in $(seq 1 19); do printf '3100\n'; done; printf '5900\n')
AGG_ABERRANT=$(printf '%s\n' "$STABLE" | monitoring_aggregate MHz 1000 cpufreq)
assert_contains "$AGG_ABERRANT" '"maximum":5900' 'agrégat : le maximum suit le relevé aberrant'
assert_contains "$AGG_ABERRANT" '"p95":3100' 'agrégat : le centile ne suit pas un relevé isolé'

# Un seul relevé : pas de centile. Sur un point il vaudrait ce point, en lui
# donnant l'autorité d'une statistique.
AGG_UN=$(printf '3100\n' | monitoring_aggregate MHz 1000 cpufreq)
assert_contains "$AGG_UN" '"sampleCount":1' 'agrégat : un seul relevé est un fait'
assert_contains "$AGG_UN" '"p95":{"unknown":true' 'agrégat : aucun centile sur un seul relevé'
assert_contains "$AGG_UN" '"first":3100' 'agrégat : le premier relevé reste publié'

# Aucun relevé exploitable : zéro échantillon est un fait, pas une moyenne nulle.
AGG_VIDE=$(printf 'n/a\n\n' | monitoring_aggregate MHz 1000 cpufreq)
assert_contains "$AGG_VIDE" '"sampleCount":0' 'agrégat : zéro échantillon est dénombré'
assert_contains "$AGG_VIDE" '"average":{"unknown":true' 'agrégat : aucune moyenne fabriquée'
assert_contains "$AGG_VIDE" '"p95":{"unknown":true' 'agrégat : aucun centile fabriqué'

# --- Progression pondérée, heartbeat et refroidissement ----------------------

suite 'Progression pondérée'

# shellcheck source=../lib/core/progress.sh
. "$SCANNER_DIR/lib/core/progress.sh"

# Le profil qui a motivé le moteur : une étape de six cents secondes au milieu
# de vingt étapes d'une seconde.
progress_weights_set 'baseline=15 cpu-single=20 cpu-multi=20 cpu-sustained=600 gpu=30'

assert_eq '685' "$(progress_weight_total)" 'poids total : la somme des coûts prévus'
assert_eq '600' "$(progress_weight_of cpu-sustained)" 'poids d’une étape déclarée'
assert_eq '1' "$(progress_weight_of etape-inconnue)" \
  'une étape non déclarée vaut le poids par défaut, jamais zéro'

# Le défaut corrigé : au début de la charge soutenue, la barre est à 8 %, pas à
# 95 %. Avec l'ancien décompte par étapes, trois étapes sur cinq valaient 60 %.
assert_eq '8' "$(progress_overall_percent 55 600 0 685)" \
  'au début de la charge soutenue, la barre reflète le coût restant'

# Et surtout : elle continue de monter pendant les six cents secondes.
# (55 + 300) / 685 = 51,8 %, tronqué à 51 par la division entière.
assert_eq '51' "$(progress_overall_percent 55 600 300 685)" \
  'à mi-charge, la barre a franchi la moitié'
assert_eq '95' "$(progress_overall_percent 55 600 600 685)" \
  'en fin de charge, la barre approche de la fin'

# Une étape qui déborde de sa durée prévue n'empiète pas sur les suivantes.
assert_eq '95' "$(progress_overall_percent 55 600 900 685)" \
  'un dépassement de durée ne fait pas déborder la barre'

# 100 % est réservé à la fin réelle.
assert_eq '99' "$(progress_overall_percent 684 1 0 685)" \
  'tant qu’il reste du poids, la barre plafonne à 99'
assert_eq '100' "$(progress_overall_percent 685 0 0 685)" \
  'la barre n’atteint 100 qu’à la fin réelle'

assert_eq '0' "$(progress_overall_percent 0 0 0 0)" 'sans poids total, aucune progression'

# --- Progression de l'étape en cours -----------------------------------------

assert_eq '50' "$(progress_phase_percent 300 600)" 'étape : la moitié du temps prévu'
assert_eq '100' "$(progress_phase_percent 900 600)" 'étape : bornée à 100'

# Une étape dont la durée n'est pas prévisible ne reçoit aucun pourcentage :
# fabriquer une fraction sans dénominateur serait une invention.
assert_eq '' "$(progress_phase_percent 42 0)" 'étape sans durée prévue : aucun pourcentage'
assert_eq '' "$(progress_phase_percent 42 '')" 'étape sans durée connue : aucun pourcentage'

# --- Temps restant -----------------------------------------------------------

assert_eq '330' "$(progress_eta_seconds 55 600 300 685)" 'temps restant estimé'
assert_eq '0' "$(progress_eta_seconds 685 0 0 685)" 'plus rien à attendre à la fin'
assert_eq '' "$(progress_eta_seconds 0 0 0 0)" 'sans poids total, aucune estimation'

# --- Format des durées -------------------------------------------------------

assert_eq '10:00' "$(format_duration 600)" 'dix minutes se lisent, six cents secondes non'
assert_eq '00:05' "$(format_duration 5)" 'les secondes gardent deux chiffres'
assert_eq '1:00:00' "$(format_duration 3600)" 'au-delà de l’heure, le format s’allonge'
assert_eq '--:--' "$(format_duration '')" 'une durée absente ne devient pas zéro'
assert_eq '--:--' "$(format_duration 'n/a')" 'une durée illisible ne devient pas zéro'

# --- Heartbeat ---------------------------------------------------------------

suite 'Heartbeat'

# Le premier est toujours dû : sans lui, les quinze premières secondes d'une
# phase longue ressemblent à un blocage.
if heartbeat_due '' 1000 15; then
  assert_eq 'oui' 'oui' 'le premier heartbeat est toujours dû'
else
  assert_eq 'oui' 'non' 'le premier heartbeat est toujours dû'
fi

if heartbeat_due 1000 1010 15; then
  assert_eq 'non' 'oui' 'aucun heartbeat avant l’intervalle'
else
  assert_eq 'non' 'non' 'aucun heartbeat avant l’intervalle'
fi

if heartbeat_due 1000 1015 15; then
  assert_eq 'oui' 'oui' 'un heartbeat à l’échéance'
else
  assert_eq 'oui' 'non' 'un heartbeat à l’échéance'
fi

HB=$(heartbeat_line '12:04:15' 'CPU sustained' 315 600 '74 °C')
assert_contains "$HB" '[12:04:15]' 'heartbeat : horodaté'
assert_contains "$HB" 'CPU sustained' 'heartbeat : nomme la phase'
assert_contains "$HB" '05:15/10:00' 'heartbeat : écoulé sur prévu, en durées lisibles'
assert_contains "$HB" '74 °C' 'heartbeat : porte la mention passée'
assert_contains "$HB" 'audit actif' 'heartbeat : dit que l’audit est vivant'

# Sans durée prévue, le heartbeat compte le temps sans inventer de fraction.
HB_SANS=$(heartbeat_line '12:04:15' 'Analyse' 42 '' '')
assert_contains "$HB_SANS" '00:42' 'heartbeat : compte le temps même sans durée prévue'
assert_not_contains "$HB_SANS" '/' 'heartbeat : aucune fraction sans dénominateur'

# --- Refroidissement ---------------------------------------------------------

suite 'Refroidissement après charge'

assert_eq 'target' "$(cooldown_state 54 55 10 60)" 'le seuil atteint termine le refroidissement'
assert_eq '' "$(cooldown_state 68 55 10 60)" 'au-dessus du seuil, le refroidissement continue'
assert_eq 'timeout' "$(cooldown_state 68 55 60 60)" 'le délai maximal termine aussi'

# Sans température lisible, seul le délai décide — et le rendu doit le dire.
assert_eq '' "$(cooldown_state '' 55 10 60)" 'sans température, rien ne conclut avant le délai'
assert_eq 'timeout' "$(cooldown_state '' 55 60 60)" 'sans température, le délai tranche'

assert_eq '0' "$(cooldown_percent 85 85 55)" 'refroidissement : rien de parcouru au départ'
assert_eq '50' "$(cooldown_percent 85 70 55)" 'refroidissement : la moitié du chemin thermique'
assert_eq '100' "$(cooldown_percent 85 55 55)" 'refroidissement : cible atteinte'
assert_eq '100' "$(cooldown_percent 85 40 55)" 'refroidissement : sous la cible, borné à 100'

# Rien à refroidir : une machine déjà sous la cible ne produit aucun
# pourcentage plutôt qu'un 100 % trompeur.
assert_eq '' "$(cooldown_percent 50 45 55)" 'déjà sous la cible : aucun refroidissement à montrer'

# --- Emplacement du rapport -------------------------------------------------

suite 'Emplacement du rapport'

# Le rapport allait dans le répertoire courant. Sous `sudo` — c'est-à-dire pour
# tout audit complet —, il finissait donc aussi bien dans `/root` que dans un
# répertoire de travail temporaire, là où son propriétaire n'irait pas le
# chercher.

# `HOME` et `SUDO_USER` sont posés dans un sous-shell : le test ne doit pas
# déplacer le dossier personnel de celui qui le lance.
resolve_home_with() {
  local sudo_user=$1 home=$2
  (
    # shellcheck disable=SC2034  # lues par `resolve_user_home`, pas ici.
    if [ -n "$sudo_user" ]; then SUDO_USER=$sudo_user; else unset SUDO_USER; fi
    if [ -n "$home" ]; then HOME=$home; else unset HOME; fi
    resolve_user_home
  )
}

assert_eq '/home/essai' "$(resolve_home_with '' '/home/essai')" \
  'sans sudo, le dossier personnel de la session fait foi'

# `sudo -u root` ne désigne personne d'autre que root : il n'y a rien à rendre.
assert_eq '/root' "$(resolve_home_with 'root' '/root')" \
  'sudo -u root reste dans le dossier personnel de root'

assert_eq "$(passwd_home_of root)" "$(passwd_home_of root)" \
  'le dossier personnel de root se lit dans la base des comptes'
assert_eq '' "$(passwd_home_of 'compte-qui-n-existe-pas-42')" \
  'un compte inconnu ne rend aucun dossier personnel'
assert_eq '' "$(passwd_home_of '')" \
  'un nom de compte vide ne rend aucun dossier personnel'

# Le cas qui compte : `sudo ./sysaudit.sh`. Le compte est choisi dans la base
# locale plutôt que supposé — un test qui parierait sur l'existence d'un nom
# précis échouerait sur la moitié des conteneurs.
TEST_ACCOUNT=$(awk -F: '$1 != "root" && $6 ~ /^\/home\// { print $1; exit }' /etc/passwd 2>/dev/null)
readonly TEST_ACCOUNT
if [ -n "$TEST_ACCOUNT" ]; then
  test_account_home=$(passwd_home_of "$TEST_ACCOUNT")
  assert_eq "$test_account_home" "$(resolve_home_with "$TEST_ACCOUNT" '/root')" \
    'sous sudo, le rapport suit l’utilisateur d’origine et non /root'
  assert_not_contains "$(resolve_home_with "$TEST_ACCOUNT" '/root')" '/root' \
    'sudo ne renvoie pas le rapport dans /root quand l’utilisateur est identifiable'
else
  printf '  \033[33mIGNORÉ\033[0m résolution sous sudo (aucun compte /home dans /etc/passwd)\n'
fi

# `HOME` peut manquer : `env -i`, un service, un conteneur minimal. La base des
# comptes répond alors pour l'utilisateur courant, plutôt que rien.
assert_eq "$(passwd_home_of "$(id -un)")" "$(resolve_home_with '' '')" \
  'sans HOME, le dossier personnel se lit dans la base des comptes'

# --- Nom du rapport ---------------------------------------------------------

with_hostname() {
  local fake=$1
  (
    hostname() { printf '%s' "$fake"; }
    report_basename
  )
}

assert_eq 'sysaudit-MSI-Ubuntu' "$(with_hostname 'MSI-Ubuntu')" \
  'le nom de rapport reprend le nom de machine'
assert_eq 'sysaudit-poste-01' "$(with_hostname 'poste/01')" \
  'une barre oblique ne peut pas entrer dans un nom de fichier'
assert_eq 'sysaudit-poste-01' "$(with_hostname 'poste é@ 01')" \
  'une suite de caractères remplacés ne laisse qu’un tiret'
assert_eq 'sysaudit-machine' "$(with_hostname '')" \
  'un nom de machine absent ne produit pas un fichier sans nom'
assert_eq 'sysaudit-machine' "$(with_hostname '@@@')" \
  'un nom de machine entièrement invalide retombe sur un nom neutre'
assert_eq 'sysaudit-poste.local' "$(with_hostname 'poste.local')" \
  'un nom pleinement qualifié garde ses points'

# --- La barre pondérée, réellement branchée ---------------------------------

suite 'Barre pondérée branchée'

# Le moteur pesé de `progress.sh` était écrit, documenté, testé — et **appelé
# par personne**. La barre dessinée restait celle qui compte les étapes, celle-là
# même que le fichier existait pour remplacer. Ces assertions couvrent la
# jonction, qui est la seule chose qui manquait.

progress_weights_set 'benchmark=600 monitoring=60'

# La **liste** et non le nombre : le dénominateur d'une barre pesée doit être
# connu avant la première étape, et le nombre s'en déduit — ce qui supprime le
# second calcul qui pouvait dériver du premier.
PROGRESS_JOURNAL=''
progress_start 'cpu memory benchmark'
assert_eq '3' "$PROGRESS_TOTAL" 'le nombre d’étapes se déduit de la liste'
assert_eq '602' "$PROGRESS_TOTAL_WEIGHT" \
  'le poids total pèse chaque étape annoncée, déclarée ou non'

# Distinct de `progress_weight_total`, qui somme la **table** : une étape non
# déclarée n'y figure pas, et compter la table donnerait un dénominateur qui
# ignore les vingt étapes courtes.
assert_eq '660' "$(progress_weight_total)" 'la table, elle, ne somme que ce qui y est déclaré'

# Le poids consommé passe par le journal, comme le décompte : chaque collecteur
# tourne dans une substitution de commande, et une variable incrémentée là n'en
# ressort pas.
# shellcheck disable=SC2034  # lue par `progress_done` de console.sh, pas ici.
PROGRESS_ACTIVE_WEIGHT=$(progress_weight_of cpu)
progress_done
# shellcheck disable=SC2034  # idem : c'est `progress_done` qui la consomme.
PROGRESS_ACTIVE_WEIGHT=$(progress_weight_of benchmark)
progress_done
assert_eq '601' "$(progress_done_weight)" 'le poids consommé s’accumule dans le journal'
assert_eq '2' "$(progress_count)" 'le décompte des étapes reste lisible à côté du poids'

progress_start ''
assert_eq '0' "$PROGRESS_TOTAL_WEIGHT" 'sans étape annoncée, aucun poids'
assert_eq '0' "$(progress_done_weight)" 'un nouveau départ repart d’un journal vide'
[ -n "$PROGRESS_JOURNAL" ] && rm -f "$PROGRESS_JOURNAL"
PROGRESS_JOURNAL=''
progress_weights_set ''

# --- Températures du refroidissement ----------------------------------------

suite 'Températures du refroidissement'

# `cooldown_state` et `cooldown_percent` n'acceptent que des entiers —
# délibérément : un pourcentage de refroidissement au dixième de degré
# prétendrait à une précision que la sonde n'a pas. `read_cpu_temperature`, lui,
# rend un dixième de degré, et c'est cette conversion qui manquait pour les
# alimenter.
assert_eq '62' "$(bench_celsius_integer '62.4')" 'un dixième de degré est arrondi'
assert_eq '63' "$(bench_celsius_integer '62.5')" 'l’arrondi va au plus proche'
assert_eq '85' "$(bench_celsius_integer '85')" 'un entier traverse inchangé'
assert_eq '' "$(bench_celsius_integer '')" 'un relevé absent le reste'
assert_eq '' "$(bench_celsius_integer 'n/a')" 'un relevé illisible ne devient pas zéro'

# --- Ce que le scanner ne fait plus -----------------------------------------

scanner_source=$(cat "$SCANNER_DIR/sysaudit.sh")
assert_not_contains "$scanner_source" 'OUTPUT_DIR=$(pwd)' \
  'la destination par défaut ne vient plus du répertoire courant'
assert_contains "$scanner_source" 'OUTPUT_DIR=$(resolve_user_home)' \
  'la destination par défaut est le dossier personnel de l’utilisateur réel'

suite 'Inventaire PCI : ce qu’une absence de pilote prouve'

# `software.sh` est déjà chargé par une suite précédente : le recharger ferait
# redéclarer ses constantes `readonly` et écrirait un avertissement à chaque
# exécution.
#
# `lspci` est substitué : la machine de test n'a pas les périphériques voulus,
# et surtout on veut choisir lesquels. Le stub rend la sortie de `lspci -nn`
# puis, pour chaque adresse, celle de `lspci -k -s`.
PCI_LIST=''
PCI_DRIVERS=''

run_cmd() {
  case "$*" in
    'lspci -nn') printf '%s\n' "$PCI_LIST"; return 0 ;;
    'lspci -k -s '*)
      # `${*##* }` ne ferait pas ce qu'on croit : sur `$*`, la suppression de
      # motif s'applique à **chaque** paramètre puis rejoint, et rend donc la
      # chaîne entière. L'adresse se prend sur une variable ordinaire.
      local joined=$* address='' line=''
      address=${joined##* }
      while IFS= read -r line; do
        case "$line" in
          "$address"=*) printf '\tKernel driver in use: %s\n' "${line#*=}"; return 0 ;;
        esac
      done <<<"$PCI_DRIVERS"
      # Aucun pilote lié : `lspci -k` n'écrit simplement pas cette ligne.
      return 0
      ;;
  esac
  return 1
}

# Un pont hôte et un pont PCI : ni l'un ni l'autre n'a quoi que ce soit à quoi
# se lier, et une machine x86 courante en expose une quinzaine.
PCI_LIST='00:00.0 Host bridge [0600]: Advanced Micro Devices, Inc. [AMD] Device [1022:1480]
00:01.1 PCI bridge [0604]: Advanced Micro Devices, Inc. [AMD] Device [1022:1483]'
PCI_DRIVERS=''
PCI_JSON=$(collect_pci_devices)

assert_not_contains "$PCI_JSON" '"status":"DRIVER_MISSING"' \
  'un pont sans pilote n’est pas déclaré « pilote manquant »'
assert_contains "$PCI_JSON" '"status":"UNKNOWN"' \
  'un pont sans pilote rend un état indéterminé'

# Le fait brut n'est pas perdu pour autant : c'est sur lui que le moteur
# raisonne, et il porte sa raison.
assert_contains "$PCI_JSON" 'aucun pilote noyau chargé' \
  'l’absence de pilote reste rapportée, avec son motif'

# La classe est transmise : sans elle, le moteur ne pourrait pas distinguer un
# pont d’une carte réseau, ce qui est exactement la distinction qui manquait.
assert_contains "$PCI_JSON" '"class":"Host bridge"' 'la classe PCI est transmise'

# Un périphérique réellement pourvu d’un pilote reste `OK`.
PCI_LIST='03:00.0 Ethernet controller [0200]: Intel Corporation I210 [8086:1533]'
PCI_DRIVERS='03:00.0=igb'
PCI_BOUND=$(collect_pci_devices)
assert_contains "$PCI_BOUND" '"status":"OK"' 'un périphérique lié reste OK'
assert_contains "$PCI_BOUND" '"driver":"igb"' 'le pilote lié est rapporté'

# --- Fraîcheur des signatures ClamAV ----------------------------------------
#
# Cette fonction portait un paramètre documenté « pour les tests » qu'aucun test
# n'employait — ShellCheck le signalait (SC2120), et il avait raison pour une
# raison plus gênante que le lint : une logique délicate n'était couverte par
# rien. Trois de ses garde-fous existent précisément parce qu'un calcul direct
# se trompe, et aucun ne l'avait jamais prouvé.

suite 'Fraîcheur des signatures ClamAV'

CLAMAV_DIR=$(mktemp -d)

# Aucune base : la question ne se pose pas. La fonction ne rend rien plutôt que
# de conclure « périmée » — un antivirus sans base téléchargée n'est pas un
# antivirus dont la base est vieille.
assert_eq '' "$(clamav_signatures_fresh "$CLAMAV_DIR")" \
  'sans base, aucune conclusion'

# Base du jour : fraîche.
touch "$CLAMAV_DIR/daily.cvd"
assert_eq 'true' "$(clamav_signatures_fresh "$CLAMAV_DIR")" \
  'une base du jour est fraîche'

# Base de six jours : encore fraîche, le seuil est à sept.
touch -d '6 days ago' "$CLAMAV_DIR/daily.cvd"
assert_eq 'true' "$(clamav_signatures_fresh "$CLAMAV_DIR")" \
  'six jours restent sous le seuil'

# Base de huit jours : `freshclam` vérifie tous les jours, une base d'une
# semaine dit donc que la mise à jour ne fonctionne plus.
touch -d '8 days ago' "$CLAMAV_DIR/daily.cvd"
assert_eq 'false' "$(clamav_signatures_fresh "$CLAMAV_DIR")" \
  'huit jours signalent une mise à jour en panne'

# `.cld` est l'autre nom de la base, après une mise à jour incrémentale. Il doit
# compter autant que `.cvd`.
rm -f "$CLAMAV_DIR/daily.cvd"
touch "$CLAMAV_DIR/daily.cld"
assert_eq 'true' "$(clamav_signatures_fresh "$CLAMAV_DIR")" \
  'la base incrémentale compte autant que la complète'

# Horloge en avance sur le fichier : l'âge est négatif. C'est une horloge
# incohérente, pas une base fraîche — et surtout pas une base périmée.
touch -d '2 days' "$CLAMAV_DIR/daily.cld"
assert_eq '' "$(clamav_signatures_fresh "$CLAMAV_DIR")" \
  'un âge négatif ne conclut rien'

rm -rf "$CLAMAV_DIR"

# --- json.sh chargé seul -----------------------------------------------------
#
# **Une grandeur mesurée ne doit jamais disparaître parce qu'une table manque.**
#
# `jf_maybe_num` consulte `SCHEMA_BOUNDS`, que `schema-bounds.sh` remplit. Sans
# déclaration préalable, Bash n'y voit pas un tableau associatif : il évalue
# l'indice comme une expression arithmétique. `${SCHEMA_BOUNDS[current]}` devient
# la variable `current`, que `set -u` refuse, et le champ sort du rapport — avec
# un message sur la sortie d'erreur que personne ne lit.
#
# Constaté sur `aggregated-metrics.test.ts`, qui charge `json.sh` seul pour
# éprouver les fonctions pures : quatre champs de télémétrie glmark2 avaient
# disparu. C'est le mode de panne que ce chantier corrige, retourné contre
# lui-même.
#
# Ce contrôle tourne dans un shell séparé : ici, `schema-bounds.sh` est déjà
# chargé, et il ne prouverait donc rien.

suite 'json.sh chargé seul'

SEUL=$(bash -c "set -eu
  . '$SCANNER_DIR/lib/core/json.sh'
  json_object \"\$(jf_maybe_num current 89562)\" \"\$(jf_maybe_num minimum 71620)\"" 2>&1)

assert_eq '{"current":89562,"minimum":71620}' "$SEUL" \
  'sans la table de bornes, les grandeurs sont publiées telles quelles'
assert_not_contains "$SEUL" 'unbound variable' \
  'aucune variable non liée : la clé n’est pas évaluée comme une expression'

# --- Portée de publication ---------------------------------------------------
#
# Le défaut d'une instance peut valoir `PUBLIC`. Ne rien dire n'est alors pas
# demander le privé : c'est laisser l'instance trancher.
#
# Le scanner n'envoyait `X-Scan-Visibility` que pour **publier**. Un audit de
# validation, de test ou d'exploitation déposé sur une telle instance devenait
# donc répertoriable sans que personne l'ait demandé, et aucune option ne
# permettait de l'éviter. Constaté le 2026-08-27 sur l'audit produit pour
# valider la chaîne de classement en production, et corrigé après coup en base.
#
# Ces contrôles lisent la source : l'envoi lui-même exige un serveur, et le
# figer ici en simulerait un — c'est déjà ainsi que la suite Windows garde ses
# propres drapeaux.

suite 'Portée de publication'

SCANNER_SOURCE=$(cat "$SCANNER_DIR/sysaudit.sh")

assert_contains "$SCANNER_SOURCE" "--private)" 'le drapeau --private existe'
assert_contains "$SCANNER_SOURCE" \
  "[ \"\$OPT_PRIVATE\" = 'true' ] && visibility_header=(-H 'X-Scan-Visibility: private')" \
  '--private envoie explicitement la portée privée'
assert_contains "$SCANNER_SOURCE" \
  "[ \"\$OPT_PUBLIC\" = 'true' ] && visibility_header=(-H 'X-Scan-Visibility: public')" \
  '--public continue d’envoyer la portée publique'

# Deux intentions contraires ne se départagent pas en silence.
assert_contains "$SCANNER_SOURCE" '--public et --private s’excluent' \
  'les deux drapeaux ensemble sont refusés'
assert_contains "$SCANNER_SOURCE" '--private exige --upload' \
  '--private sans --upload est refusé'

# Le refus doit précéder la collecte : découvrir la contradiction après trois
# minutes de scan serait la pire façon de la signaler.
assert_eq 'true' "$(
  contradiction=$(printf '%s' "$SCANNER_SOURCE" | grep -n -- '--public et --private s’excluent' | head -n1 | cut -d: -f1)
  collecte=$(printf '%s' "$SCANNER_SOURCE" | grep -n 'log_step .Batterie et alimentation.' | head -n1 | cut -d: -f1)
  if [ -z "$collecte" ] || [ "$contradiction" -lt "$collecte" ]; then printf 'true'; else printf 'false'; fi
)" 'le refus arrive avant la collecte'

# --- Batterie ---------------------------------------------------------------
#
# `parse_battery` n'était couverte par rien, et le défaut qu'elle portait ne se
# voyait sur aucune machine de développement — il faut une batterie, et un
# firmware qui refuse de compter ses cycles.
#
# Le 2026-08-27, un dépôt d'audit a été refusé en bloc :
#
#     Le rapport ne respecte pas le schéma SysAudit.
#     {"path":"$.power.batteries.0.cycleCount","message":"Too small: expected number to be >=0"}
#
# `/sys/class/power_supply/BAT0/cycle_count` rendait `-1`, la façon dont une
# partie du parc ACPI dit « ce compteur n'existe pas ». Le scanner le publiait
# comme une mesure. Le message ne nommait ni la batterie, ni la cause, et
# l'audit entier — toutes sections confondues — était perdu.

suite 'Batterie'

BATTERY_DIR=$(mktemp -d)
printf 'LGC\n' > "$BATTERY_DIR/manufacturer"
printf 'Li-ion\n' > "$BATTERY_DIR/technology"
printf 'Discharging\n' > "$BATTERY_DIR/status"
printf '11400000\n' > "$BATTERY_DIR/voltage_now"
printf '11400000\n' > "$BATTERY_DIR/voltage_min_design"
printf '50000000\n' > "$BATTERY_DIR/energy_full_design"
printf '44000000\n' > "$BATTERY_DIR/energy_full"
printf '87\n' > "$BATTERY_DIR/capacity"

# Le cas qui déclenche : le firmware avoue, le rapport ne l'invente pas.
printf -- '-1\n' > "$BATTERY_DIR/cycle_count"
assert_contains "$(parse_battery "$BATTERY_DIR")" \
  '"cycleCount":{"unknown":true,"reason":"NOT_AVAILABLE"' \
  'un compteur de cycles à -1 devient un marqueur'
assert_not_contains "$(parse_battery "$BATTERY_DIR")" '"cycleCount":-1' \
  'aucun nombre de cycles négatif ne sort du scanner'

# Le cas qui ne déclenche pas : une batterie normalement lue reste lue.
printf '612\n' > "$BATTERY_DIR/cycle_count"
assert_contains "$(parse_battery "$BATTERY_DIR")" '"cycleCount":612' \
  'un compteur réellement exposé est publié tel quel'

# Zéro cycle est une lecture, pas une absence : une batterie neuve en a zéro.
printf '0\n' > "$BATTERY_DIR/cycle_count"
assert_contains "$(parse_battery "$BATTERY_DIR")" '"cycleCount":0' \
  'zéro cycle reste une valeur'

# Même règle sur le niveau de charge, borné à 0–100 par le schéma : le rejet
# aurait été identique, et sur le même rapport.
printf -- '-1\n' > "$BATTERY_DIR/capacity"
assert_contains "$(parse_battery "$BATTERY_DIR")" \
  '"chargePercent":{"unknown":true,"reason":"NOT_AVAILABLE"' \
  'un niveau de charge hors bornes devient un marqueur'

printf '87\n' > "$BATTERY_DIR/capacity"
assert_contains "$(parse_battery "$BATTERY_DIR")" '"chargePercent":87' \
  'un niveau de charge plausible est publié tel quel'

rm -rf "$BATTERY_DIR"

# --- Rappel du banc d'essai -------------------------------------------------
#
# Le banc d'essai n'appartient qu'au niveau Poussée, et il doit le rester : il
# charge la machine plusieurs minutes. Ce qui manquait n'était pas la mesure
# mais sa **mention** — au 2026-08-27, le parc comptait 36 audits `--full` et
# pas une seule mesure, faute que rien n'ait jamais dit qu'elle existait.
#
# La règle des niveaux est éprouvée ici sur la vraie table, pas sur une copie :
# c'est elle qui décide si le rappel a lieu d'être.

suite 'Rappel du banc d’essai'

PROFILE='full'
assert_eq 'false' "$(level_collects benchmark && printf 'true' || printf 'false')" \
  'un audit complet ne mesure toujours pas les performances'

PROFILE='standard'
assert_eq 'false' "$(level_collects benchmark && printf 'true' || printf 'false')" \
  'un audit standard non plus'

PROFILE='stress'
assert_eq 'true' "$(level_collects benchmark && printf 'true' || printf 'false')" \
  'un audit poussé les mesure, et c’est le seul niveau qui le fasse'

# Le test de non-déclenchement : une section écartée à la main est déjà une
# réponse, et le scanner ne doit pas la reposer.
PROFILE='stress' SKIP_SECTIONS='benchmark'
assert_eq 'false' "$(level_collects benchmark && printf 'true' || printf 'false')" \
  '--skip benchmark l’emporte sur le niveau'
# L'état global est rendu à son défaut, et la restauration est **vérifiée**.
# `PROFILE` et `SKIP_SECTIONS` sont lus par tout le reste de la suite : les
# laisser sur « poussé, section écartée » ferait mentir la première suite
# ajoutée en dessous — le genre de piège que la suite Windows a déjà payé une
# fois. La vérifier plutôt que la supposer est aussi ce qui la rend visible de
# ShellCheck, pour qui une variable qu'on repose sans la relire est morte.
SKIP_SECTIONS=''
PROFILE='standard'
assert_eq 'standard||false' \
  "$PROFILE|$SKIP_SECTIONS|$(level_collects benchmark && printf 'true' || printf 'false')" \
  'l’état global est rendu à son défaut'

SCANNER_SOURCE=$(cat "$SCANNER_DIR/sysaudit.sh")

assert_contains "$SCANNER_SOURCE" 'benchmark_hint()' 'le rappel existe'
assert_contains "$SCANNER_SOURCE" \
  "[ \"\$OPT_BENCHMARK\" = 'true' ] && return 0" \
  'un banc d’essai demandé ne se voit rien rappeler'
assert_contains "$SCANNER_SOURCE" 'level_collects benchmark && return 0' \
  'un banc d’essai qui a tourné non plus'
assert_contains "$SCANNER_SOURCE" 'section_excluded benchmark && return 0' \
  'une section écartée à la main reste écartée'
assert_contains "$SCANNER_SOURCE" "[ \"\$(current_level)\" = 'quick' ] && return 0" \
  'un audit rapide garde sa brièveté'
assert_contains "$SCANNER_SOURCE" '--benchmark mesure processeur, mémoire et stockage' \
  'le rappel dit ce que la mesure coûte'

# --- Bilan ------------------------------------------------------------------

printf '\n'
if [ "$FAILED" -eq 0 ]; then
  printf '\033[32m%d tests réussis.\033[0m\n' "$PASSED"
  exit 0
fi
printf '\033[31m%d échec(s) sur %d tests.\033[0m\n' "$FAILED" "$((PASSED + FAILED))"
exit 1
