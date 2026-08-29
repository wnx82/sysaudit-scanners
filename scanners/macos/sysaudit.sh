#!/bin/sh
#
#  ███████╗██╗   ██╗███████╗ █████╗ ██╗   ██╗██████╗ ██╗████████╗
#  ██╔════╝╚██╗ ██╔╝██╔════╝██╔══██╗██║   ██║██╔══██╗██║╚══██╔══╝
#  ███████╗ ╚████╔╝ ███████╗███████║██║   ██║██║  ██║██║   ██║
#  ╚════██║  ╚██╔╝  ╚════██║██╔══██║██║   ██║██║  ██║██║   ██║
#  ███████║   ██║   ███████║██║  ██║╚██████╔╝██████╔╝██║   ██║
#  ╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═╝   ╚═╝
#
#                    macOS — EXPERIMENTAL / UNVALIDATED
#
# ┌────────────────────────────────────────────────────────────────────────────┐
# │  CE SCANNER N'A JAMAIS ÉTÉ EXÉCUTÉ SUR UN MAC.                             │
# │                                                                            │
# │  Il est écrit d'après la documentation d'Apple et les pages de manuel des  │
# │  outils employés. Aucune de ses sorties n'a été confrontée à une machine   │
# │  réelle. Tant que ce bandeau est là :                                      │
# │                                                                            │
# │    - aucune de ses collectes ne justifie une case ✅ dans la matrice de    │
# │      compatibilité ;                                                       │
# │    - un rapport qu'il produit doit être lu comme une hypothèse, pas comme  │
# │      une mesure ;                                                          │
# │    - `report.profile` reste `quick` et `notes` porte la mention            │
# │      EXPERIMENTAL, que l'interface affiche.                                │
# │                                                                            │
# │  Ce qu'il garantit malgré tout, et qui se teste sans Mac : il ne suppose   │
# │  l'existence d'aucune commande, il n'invente aucune valeur, et il produit  │
# │  un rapport conforme au schéma même quand rien n'a pu être lu.             │
# └────────────────────────────────────────────────────────────────────────────┘
#
# Usage :
#   ./sysaudit.sh                    audit, rapport dans le répertoire courant
#   ./sysaudit.sh --output-dir /tmp  choisit le répertoire de sortie
#   ./sysaudit.sh --stdout           écrit le JSON sur la sortie standard
#   ./sysaudit.sh --capabilities     montre ce qui serait collecté, sans scanner
#   ./sysaudit.sh --quiet
#   ./sysaudit.sh --version
#
# Read-only par construction : aucune commande de ce fichier n'écrit dans la
# configuration du système. `defaults read` lit, `defaults write` n'apparaît
# nulle part, et aucun `sudo` n'est appelé.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
readonly SCRIPT_DIR

# Version du schéma produit. Déclarée en dur : le scanner doit tourner sur une
# machine sans Node.js. `scanner-contract.test.ts` vérifie qu'elle ne diverge
# pas de celle du paquet.
SCHEMA_VERSION='1.33.0'
readonly SCHEMA_VERSION

SCANNER_VERSION=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || printf '0.0.0')
readonly SCANNER_VERSION

# shellcheck source=lib/json.sh
. "$SCRIPT_DIR/lib/json.sh"
# shellcheck source=lib/core.sh
. "$SCRIPT_DIR/lib/core.sh"

OUTPUT_DIR='.'
TO_STDOUT=0
QUIET=0
CAPABILITIES_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --output-dir)
      [ $# -ge 2 ] || die '--output-dir attend un chemin.'
      OUTPUT_DIR=$2
      shift 2
      ;;
    --stdout)
      TO_STDOUT=1
      shift
      ;;
    --quiet)
      # shellcheck disable=SC2034 # lue par log_info/log_step, dans lib/core.sh.
      QUIET=1
      shift
      ;;
    --capabilities)
      CAPABILITIES_ONLY=1
      shift
      ;;
    --version)
      printf 'sysaudit-macos %s (EXPERIMENTAL, schéma %s)\n' "$SCANNER_VERSION" "$SCHEMA_VERSION"
      exit 0
      ;;
    -h | --help)
      sed -n '31,41p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "Option inconnue : $1" ;;
  esac
done

# --- Refus explicite --------------------------------------------------------
#
# Lancé ailleurs que sur macOS, ce scanner produirait un rapport plein de
# marqueurs qu'on lirait comme « macOS ne sait pas répondre ». Il refuse donc,
# plutôt que de fabriquer une preuve à charge contre un système qu'il n'a même
# pas rencontré.
UNAME_S=$(uname -s 2>/dev/null || printf 'unknown')
if [ "$UNAME_S" != 'Darwin' ] && [ "${SYSAUDIT_ALLOW_FOREIGN_HOST:-0}" != '1' ]; then
  die "Ce scanner cible macOS ; l’hôte annonce « $UNAME_S ». Les collectes échoueraient toutes, et le rapport se lirait comme un macOS incapable de répondre."
fi

init_journal

# Les deux mentions qui gouvernent la lecture de ce rapport, écrites avant toute
# collecte : un scan interrompu doit les porter aussi.
note 'EXPERIMENTAL — scanner macOS jamais exécuté sur une machine réelle. Ce rapport est une hypothèse, pas une mesure.'
note 'UNVALIDATED — aucune de ces collectes ne justifie une case validée dans la matrice de compatibilité.'
note 'Le schéma n’a pas de sous-section de sécurité macOS : SIP, FileVault et Gatekeeper sont donc rapportés ici, en clair.'

# --- Détection des outils ---------------------------------------------------
#
# Tous les outils employés plus bas sont détectés **ici**, une fois. Aucun
# collecteur n'appelle une commande sans que sa présence figure dans cette
# table : c'est ce qui permet de publier `capabilities.tools` et de justifier
# chaque marqueur d'absence.

TOOLS='sw_vers sysctl uname hostname scutil system_profiler diskutil df ifconfig
networksetup pmset csrutil fdesetup spctl defaults vm_stat log last uptime
softwareupdate ioreg'

tools_json() {
  _out=''
  for _tool in $TOOLS; do
    if [ -n "$_out" ]; then _out="$_out,"; fi
    if have "$_tool"; then
      _out="$_out$(jf_raw "$_tool" true)"
    else
      _out="$_out$(jf_raw "$_tool" false)"
    fi
  done
  printf '{%s}' "$_out"
}

if [ "$CAPABILITIES_ONLY" = '1' ]; then
  printf 'sysaudit-macos %s — EXPERIMENTAL, jamais exécuté sur un Mac réel.\n\n' "$SCANNER_VERSION"
  printf 'Outils détectés sur cette machine :\n'
  for _tool in $TOOLS; do
    if have "$_tool"; then
      printf '  présent  %s\n' "$_tool"
    else
      printf '  absent   %s\n' "$_tool"
    fi
  done
  printf '\nUn outil absent ne fait pas échouer le scan : le champ correspondant\n'
  printf 'porte un marqueur avec sa raison.\n'
  exit 0
fi

# --- Système ----------------------------------------------------------------

# `sysctl -n` en une ligne, ou rien. La valeur `hw.model` d'un Mac ressemble à
# `MacBookPro18,3` : c'est un identifiant produit, pas un nom commercial, et le
# scanner ne tente pas de le traduire — la table de correspondance vieillirait
# mal et une traduction fausse serait pire qu'un identifiant brut.
sysctl_value() {
  have sysctl || return 0
  sysctl -n "$1" 2>/dev/null | first_line
}

# Secondes de `kern.boottime`, qui rend `{ sec = 1785000000, usec = 0 } …`.
#
# Une expression régulière `.*sec *= *\([0-9]*\)` **ne marche pas** : le `.*`
# glouton atteint « usec », et l'uptime devenait l'instant Unix tout entier —
# soit cinquante-six ans, ce que le schéma refuse. Chercher le champ « sec »
# exact ne peut pas se tromper.
boottime_seconds() {
  awk '{ for (i = 1; i <= NF; i++) if ($i == "sec") { gsub(/[^0-9]/, "", $(i + 2)); print $(i + 2); exit } }'
}

collect_system() {
  _hostname=''
  if have scutil; then
    _hostname=$(scutil --get ComputerName 2>/dev/null | first_line)
  fi
  [ -n "$_hostname" ] && have hostname || true
  if [ -z "$_hostname" ] && have hostname; then
    _hostname=$(hostname 2>/dev/null | first_line)
  fi

  _model=$(sysctl_value hw.model)
  _arch=$(uname -m 2>/dev/null | first_line)

  # `kern.boottime` rend `{ sec = 1785000000, usec = 0 } …`. L'uptime s'en
  # déduit ; sans lui il reste inconnu, jamais nul — une machine d'uptime nul
  # n'existe pas, et zéro se lirait comme un redémarrage à l'instant.
  _boot_sec=$(sysctl_value kern.boottime | boottime_seconds)
  _uptime=''
  if [ -n "$_boot_sec" ]; then
    _now=$(date -u '+%s' 2>/dev/null || printf '')
    if [ -n "$_now" ]; then _uptime=$((_now - _boot_sec)); fi
  fi
  [ -n "$_uptime" ] && [ "$_uptime" -lt 0 ] && _uptime=''

  # Le numéro de série vient d'`ioreg`. Il n'est **pas** deviné du modèle, et
  # son absence n'est pas comblée : c'est une donnée identifiante, et en
  # inventer une serait la pire des fabrications.
  _serial=''
  if have ioreg; then
    _serial=$(ioreg -l 2>/dev/null |
      sed -n 's/.*"IOPlatformSerialNumber" = "\([^"]*\)".*/\1/p' | first_line)
  fi
  _uuid=''
  if have ioreg; then
    _uuid=$(ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null |
      sed -n 's/.*"IOPlatformUUID" = "\([^"]*\)".*/\1/p' | first_line)
  fi

  if [ -n "$_model" ]; then
    feature 'system' 'AVAILABLE'
  else
    feature 'system' 'NOT_AVAILABLE' 'sysctl hw.model n’a rien rendu'
  fi

  _tz=''
  if have systemsetup; then
    : # `systemsetup -gettimezone` exige les droits administrateur ; non tenté.
  fi
  [ -f /etc/localtime ] && _tz=$(readlink /etc/localtime 2>/dev/null | sed 's#.*/zoneinfo/##')

  json_object \
    "$(jf_maybe_str hostname "$_hostname" NOT_AVAILABLE 'ni scutil ni hostname n’ont répondu')" \
    "$(jf_maybe_str manufacturer '' NOT_COLLECTED 'non collecté : un Mac se reconnaît à son modèle, et déduire « Apple » du système serait une supposition')" \
    "$(jf_maybe_str model "$_model" NOT_AVAILABLE 'sysctl hw.model absent ou muet')" \
    "$(jf_maybe_str chassisType '' NOT_COLLECTED 'le châssis se déduirait du modèle, ce qui serait une interprétation')" \
    "$(jf_maybe_str uuid "$_uuid" NOT_AVAILABLE 'ioreg absent ou IOPlatformUUID illisible')" \
    "$(jf_maybe_str serialNumber "$_serial" NOT_AVAILABLE 'ioreg absent ou numéro de série illisible')" \
    "$(jf_maybe_str architecture "$_arch" NOT_AVAILABLE 'uname -m muet')" \
    "$(jf_maybe_num uptimeSeconds "$_uptime" NOT_AVAILABLE 'kern.boottime illisible')" \
    "$(jf_maybe_str timezone "$_tz" NOT_AVAILABLE '/etc/localtime non résolu')" \
    "$(jf_maybe_str localTime "$(now_iso)" NOT_AVAILABLE 'date indisponible')"
}

collect_os() {
  _name=''
  _version=''
  _build=''
  if have sw_vers; then
    _name=$(sw_vers -productName 2>/dev/null | first_line)
    _version=$(sw_vers -productVersion 2>/dev/null | first_line)
    _build=$(sw_vers -buildVersion 2>/dev/null | first_line)
    feature 'os' 'AVAILABLE'
  else
    feature 'os' 'NOT_AVAILABLE' 'sw_vers absent'
  fi

  _kernel=$(uname -r 2>/dev/null | first_line)

  json_object \
    "$(jf_str family 'macos')" \
    "$(jf_maybe_str name "$_name" NOT_AVAILABLE 'sw_vers absent')" \
    "$(jf_maybe_str edition '' NOT_APPLICABLE 'macOS n’a pas d’édition')" \
    "$(jf_maybe_str distribution '' NOT_APPLICABLE 'notion propre aux distributions Linux')" \
    "$(jf_maybe_str version "$_version" NOT_AVAILABLE 'sw_vers absent')" \
    "$(jf_maybe_str build "$_build" NOT_AVAILABLE 'sw_vers absent')" \
    "$(jf_maybe_str kernel "$_kernel" NOT_AVAILABLE 'uname -r muet')" \
    "$(jf_maybe_str architecture "$(uname -m 2>/dev/null | first_line)" NOT_AVAILABLE 'uname -m muet')" \
    "$(jf_maybe_str installDate '' NOT_COLLECTED 'la date d’installation se déduirait d’un horodatage de fichier, ce qui n’est pas la même chose')" \
    "$(jf_maybe_str locale "${LANG-}" NOT_AVAILABLE 'LANG non défini')" \
    "$(jf_maybe_str timezone '' NOT_COLLECTED 'lu dans system, pas dupliqué ici')"
}

# --- Processeur et mémoire --------------------------------------------------

collect_cpus() {
  _brand=$(sysctl_value machdep.cpu.brand_string)
  # Sur Apple Silicon, `machdep.cpu.brand_string` n'existe pas : la puce se lit
  # dans `hw.model` et le nom commercial n'est publié nulle part en clair. Le
  # champ reste alors inconnu plutôt que rempli avec le modèle de la machine,
  # qui n'est pas le nom du processeur.
  _physical=$(sysctl_value hw.physicalcpu)
  _logical=$(sysctl_value hw.logicalcpu)
  _freq=$(sysctl_value hw.cpufrequency)
  _mhz=''
  if [ -n "$_freq" ]; then _mhz=$((_freq / 1000000)); fi

  if [ -z "$_brand" ] && [ -z "$_physical" ]; then
    feature 'cpus' 'NOT_AVAILABLE' 'sysctl n’a rendu ni marque ni nombre de cœurs'
    return 0
  fi
  feature 'cpus' 'AVAILABLE'

  json_array "$(json_object \
    "$(jf_maybe_str manufacturer '' NOT_COLLECTED 'le fabricant se déduirait de la marque, ce qui serait une interprétation')" \
    "$(jf_maybe_str model "$_brand" NOT_AVAILABLE 'machdep.cpu.brand_string absent — attendu sur Apple Silicon')" \
    "$(jf_maybe_str family '' NOT_COLLECTED 'non publiée par sysctl sur Apple Silicon')" \
    "$(jf_maybe_str generation '' NOT_COLLECTED 'la génération commerciale se déduirait du modèle, ce qui serait une interprétation')" \
    "$(jf_maybe_str socket '' NOT_APPLICABLE 'les processeurs Apple sont soudés ; il n’y a pas de socket à rapporter')" \
    "$(jf_maybe_num physicalCores "$_physical" NOT_AVAILABLE 'hw.physicalcpu muet')" \
    "$(jf_maybe_num logicalCores "$_logical" NOT_AVAILABLE 'hw.logicalcpu muet')" \
    "$(jf_maybe_num baseFrequencyMhz "$_mhz" NOT_AVAILABLE 'hw.cpufrequency absent — attendu sur Apple Silicon')" \
    "$(jf_maybe_num maxFrequencyMhz '' NOT_AVAILABLE 'aucune fréquence maximale publiée par sysctl')" \
    "$(jf_maybe_num currentFrequencyMhz '' NOT_AVAILABLE 'macOS ne publie pas la fréquence instantanée')" \
    "$(jf_raw virtualization "$(j_unknown NOT_COLLECTED 'la virtualisation matérielle n’est pas interrogée par ce scanner expérimental')")" \
    "$(jf_maybe_num temperatureCelsius '' NOT_COLLECTED 'les capteurs thermiques exigent une interface privée d’Apple')" \
    "$(jf_maybe_num usagePercent '' NOT_COLLECTED 'la charge instantanée n’est pas échantillonnée par ce scanner')")"
}

collect_memory() {
  _total=$(sysctl_value hw.memsize)
  _available=''

  # `vm_stat` rend des pages, pas des octets, et la taille de page varie —
  # 4 Kio sur Intel, 16 Kio sur Apple Silicon. La multiplier par une constante
  # écrite en dur donnerait un chiffre faux d'un facteur quatre sur la moitié du
  # parc : la taille est donc lue, et sans elle le champ reste inconnu.
  _pagesize=$(sysctl_value hw.pagesize)
  if have vm_stat && [ -n "$_pagesize" ]; then
    _free_pages=$(vm_stat 2>/dev/null |
      awk -F: '/Pages free/ { gsub(/[^0-9]/, "", $2); free = $2 }
               /Pages inactive/ { gsub(/[^0-9]/, "", $2); inactive = $2 }
               END { if (free != "") print free + inactive }')
    if [ -n "$_free_pages" ]; then _available=$((_free_pages * _pagesize)); fi
  fi

  if [ -z "$_total" ]; then
    feature 'memory' 'NOT_AVAILABLE' 'hw.memsize muet'
  else
    feature 'memory' 'AVAILABLE'
  fi

  json_object \
    "$(jf_maybe_num installedBytes "$_total" NOT_AVAILABLE 'hw.memsize muet')" \
    "$(jf_maybe_num availableBytes "$_available" NOT_AVAILABLE 'vm_stat absent ou taille de page illisible')" \
    "$(jf_maybe_num swapUsedBytes '' NOT_COLLECTED 'sysctl vm.swapusage non analysé par ce scanner expérimental')" \
    "$(jf_maybe_num swapTotalBytes '' NOT_COLLECTED 'sysctl vm.swapusage non analysé par ce scanner expérimental')" \
    "$(jf_maybe_num maxCapacityBytes '' NOT_COLLECTED 'la capacité maximale exigerait system_profiler SPMemoryDataType')" \
    "$(jf_raw modules '[]')" \
    "$(jf_maybe_num slotsTotal '' NOT_AVAILABLE 'system_profiler SPMemoryDataType non analysé')" \
    "$(jf_maybe_num slotsUsed '' NOT_AVAILABLE 'system_profiler SPMemoryDataType non analysé')"
}

# --- Stockage ---------------------------------------------------------------
#
# Les partitions viennent de `df -k -P`, dont le format est fixé par POSIX. Les
# disques physiques exigeraient `diskutil list -plist`, donc un analyseur XML :
# hors de portée d'un scanner shell, et le simuler produirait des disques
# inventés. Le tableau `disks` reste donc **vide**, et `collection.skippedSections`
# le déclare — un tableau vide sans déclaration se lirait comme « aucun disque ».

collect_storage() {
  have df || {
    feature 'storage' 'NOT_AVAILABLE' 'df absent'
    return 0
  }

  _parts=$(df -k -P 2>/dev/null | awk 'NR > 1 && $1 ~ /^\/dev\// {
      total = $2 * 1024; used = $3 * 1024; free = $4 * 1024;
      pct = $5; gsub(/%/, "", pct);
      printf "%s\t%s\t%s\t%s\t%s\t%s\n", $1, $6, total, used, free, pct
    }')

  if [ -z "$_parts" ]; then
    feature 'storage' 'NOT_AVAILABLE' 'df n’a listé aucun système de fichiers sur périphérique'
    return 0
  fi
  feature 'storage' 'AVAILABLE'

  _rows=''
  printf '%s\n' "$_parts" >"${TMPDIR:-/tmp}/sysaudit-parts.$$"
  while IFS="$(printf '\t')" read -r _dev _mount _total _used _free _pct; do
    [ -n "$_dev" ] || continue
    if [ -n "$_rows" ]; then _rows="$_rows,"; fi
    _rows="$_rows$(json_object \
      "$(jf_str name "$_dev")" \
      "$(jf_maybe_str mountPoint "$_mount" NOT_AVAILABLE 'point de montage illisible')" \
      "$(jf_maybe_str filesystem '' NOT_COLLECTED 'le type de système de fichiers exigerait diskutil info')" \
      "$(jf_maybe_num sizeBytes "$_total" NOT_AVAILABLE 'df muet')" \
      "$(jf_maybe_num usedBytes "$_used" NOT_AVAILABLE 'df muet')" \
      "$(jf_maybe_num freeBytes "$_free" NOT_AVAILABLE 'df muet')" \
      "$(jf_maybe_num usagePercent "$_pct" NOT_AVAILABLE 'df muet')" \
      "$(jf_maybe_bool encrypted '' NOT_COLLECTED 'le chiffrement par volume exigerait diskutil apfs list')" \
      "$(jf_maybe_str encryptionType '' NOT_COLLECTED 'idem')")"
  done <"${TMPDIR:-/tmp}/sysaudit-parts.$$"
  rm -f "${TMPDIR:-/tmp}/sysaudit-parts.$$"

  # Un seul « disque » synthétique, qui porte les systèmes de fichiers. Il ne
  # prétend pas être un disque physique : son `device` le dit, ses champs
  # matériels portent tous NOT_COLLECTED, et `storage.disks` figure dans
  # `skippedSections`. Fabriquer un disque par point de montage inventerait du
  # matériel — la faute exacte que ce produit s'interdit.
  skipped 'storage.disks'
  json_object \
    "$(jf_raw disks "[$(json_object \
      "$(jf_str device 'systèmes de fichiers montés')" \
      "$(jf_str kind 'UNKNOWN')" \
      "$(jf_maybe_str manufacturer '' NOT_COLLECTED 'diskutil list -plist exigerait un analyseur XML, hors de portée d’un scanner shell')" \
      "$(jf_maybe_str model '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_str serialNumber '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_str firmware '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_num sizeBytes '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_str interface '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_num rotationRpm '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_str partitionTable '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_bool removable '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_bool trimSupported '' NOT_COLLECTED 'idem')" \
      "$(jf_raw partitions "[$_rows]")")]")" \
    "$(jf_raw pools '[]')" \
    "$(jf_maybe_num totalBytes '' NOT_COLLECTED 'le total exigerait l’inventaire des disques physiques, non collecté')" \
    "$(jf_maybe_num usedBytes '' NOT_COLLECTED 'idem')" \
    "$(jf_maybe_bool trimScheduled '' NOT_APPLICABLE 'macOS gère le rejet de blocs sans planification exposée')"
}

# --- Réseau -----------------------------------------------------------------

collect_network() {
  have ifconfig || {
    feature 'network' 'NOT_AVAILABLE' 'ifconfig absent'
    return 0
  }
  feature 'network' 'AVAILABLE'

  # `ifconfig -a` : un bloc par interface, les suivantes indentées. Le format
  # est celui de BSD, stable depuis des décennies — mais le scanner ne s'y fie
  # que pour ce qu'il sait relire, et laisse le reste inconnu.
  # Un bloc par interface : la ligne d'en-tête commence en colonne 1, les
  # suivantes sont indentées. L'interface n'est émise qu'à l'arrivée de la
  # suivante — sinon la dernière ligne lue écraserait ce qui précède, et une
  # interface à plusieurs adresses ressortirait autant de fois.
  _ifaces=$(ifconfig -a 2>/dev/null | awk '
    # Un champ vide est emis comme `-`, jamais comme rien.
    #
    # La tabulation est un caractere blanc au sens de IFS : `read` fusionne donc
    # deux tabulations consecutives en un seul delimiteur, et un champ vide
    # decale tous les suivants. Une interface sans adresse ether — un tunnel
    # WireGuard, un point-a-point — voyait ainsi son adresse IP publiee comme
    # adresse MAC : une valeur inventee, et de surcroit une adresse qui echappe
    # a lanonymisation prevue pour le champ ou elle atterrissait.
    #
    # Aucune apostrophe dans ce bloc : il vit dans un programme awk entre
    # apostrophes simples, et la moindre en fermerait la chaine.
    function cell(value) { return value == "" ? "-" : value }
    function flush() {
      if (name != "") printf "%s\t%s\t%s\t%s\n", name, cell(state), cell(mac), cell(ip)
    }
    /^[a-zA-Z]/ {
      flush()
      name = $1; sub(/:$/, "", name)
      state = ($0 ~ /[<,]UP[,>]/) ? "UP" : "DOWN"
      mac = ""; ip = ""
      next
    }
    $1 == "ether" { mac = $2 }
    $1 == "inet" && $2 != "127.0.0.1" && ip == "" { ip = $2 }
    END { flush() }
  ')

  _rows=''
  printf '%s\n' "$_ifaces" >"${TMPDIR:-/tmp}/sysaudit-ifaces.$$"
  _seen=''
  while IFS="$(printf '\t')" read -r _name _state _mac _ip; do
    [ -n "$_name" ] || continue
    # `-` est le marqueur de champ vide pose par awk ci-dessus, jamais une
    # valeur relevee : aucune adresse ni aucun etat ne vaut un tiret seul.
    [ "$_state" = '-' ] && _state=''
    [ "$_mac" = '-' ] && _mac=''
    [ "$_ip" = '-' ] && _ip=''
    case " $_seen " in *" $_name "*) continue ;; esac
    _seen="$_seen $_name"
    if [ -n "$_rows" ]; then _rows="$_rows,"; fi
    _ipv4='[]'
    [ -n "$_ip" ] && _ipv4="[$(json_object "$(jf_str address "$_ip")" "$(jf_raw prefixLength 24)")]"
    _rows="$_rows$(json_object \
      "$(jf_str name "$_name")" \
      "$(jf_maybe_str manufacturer '' NOT_COLLECTED 'non exposé par ifconfig')" \
      "$(jf_maybe_str model '' NOT_COLLECTED 'non exposé par ifconfig')" \
      "$(jf_maybe_str mac "$_mac" NOT_AVAILABLE 'aucune adresse ether sur cette interface')" \
      "$(jf_maybe_str type '' NOT_COLLECTED 'le type se déduirait du préfixe du nom (en, lo, utun), ce qui serait une convention supposée')" \
      "$(jf_str status "$_state")" \
      "$(jf_maybe_str duplex '' NOT_COLLECTED 'exigerait networksetup ou ioreg')" \
      "$(jf_maybe_num speedMbps '' NOT_COLLECTED 'le débit négocié exigerait networksetup ou ioreg')" \
      "$(jf_maybe_num mtu '' NOT_COLLECTED 'non extrait par ce scanner expérimental')" \
      "$(jf_maybe_str driver '' NOT_APPLICABLE 'macOS ne nomme pas ses pilotes réseau comme Linux')" \
      "$(jf_maybe_bool dhcp '' NOT_COLLECTED 'exigerait ipconfig getpacket, non tenté')" \
      "$(jf_raw ipv4 "$_ipv4")" \
      "$(jf_raw ipv6 '[]')" \
      "$(jf_maybe_str gateway '' NOT_COLLECTED 'exigerait netstat -rn, non analysé')")"
  done <"${TMPDIR:-/tmp}/sysaudit-ifaces.$$"
  rm -f "${TMPDIR:-/tmp}/sysaudit-ifaces.$$"

  [ -n "$_rows" ] || return 0
  json_object \
    "$(jf_raw interfaces "[$_rows]")" \
    "$(jf_raw dnsServers '[]')" \
    "$(jf_raw searchDomains '[]')" \
    "$(jf_raw listeningPorts '[]')"
}

# --- Sécurité ---------------------------------------------------------------
#
# Quatre protections, quatre outils, et **aucune déduction de l'une à l'autre**.
# SIP actif ne dit rien de FileVault, et Gatekeeper actif ne dit rien du
# pare-feu. Chaque champ est lu ou reste inconnu.

collect_security() {
  _sip=''
  if have csrutil; then
    case "$(csrutil status 2>/dev/null)" in
      *enabled*) _sip='true' ;;
      *disabled*) _sip='false' ;;
    esac
  fi

  _filevault=''
  if have fdesetup; then
    case "$(fdesetup status 2>/dev/null)" in
      *'FileVault is On'*) _filevault='true' ;;
      *'FileVault is Off'*) _filevault='false' ;;
    esac
  fi

  _gatekeeper=''
  if have spctl; then
    case "$(spctl --status 2>/dev/null)" in
      *'assessments enabled'*) _gatekeeper='true' ;;
      *'assessments disabled'*) _gatekeeper='false' ;;
    esac
  fi

  # Le pare-feu applicatif se lit dans les préférences. `defaults read` **lit**,
  # il n'écrit rien — la distinction compte, ce scanner étant read-only.
  # `globalstate` vaut 0 (inactif), 1 (actif) ou 2 (actif, mode bloquant).
  _firewall=''
  if have defaults; then
    case "$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null | first_line)" in
      1 | 2) _firewall='ENABLED' ;;
      0) _firewall='DISABLED' ;;
    esac
  fi

  # SIP, FileVault et Gatekeeper partent dans `notes`, au niveau du rapport.
  #
  # Le schéma porte une sous-section `security.windows` et une
  # `security.linux` ; il n'a **pas** d'équivalent macOS. En ajouter une serait
  # une évolution de schéma, et une évolution de schéma décidée par un scanner
  # que personne n'a jamais exécuté serait décidée à l'aveugle. Les trois faits
  # sont donc publiés en clair, dans le champ prévu pour ce que le scanner
  # constate sans que rien ne l'interprète automatiquement.
  note "SIP : $(state_label "$_sip")"
  note "FileVault : $(state_label "$_filevault")"
  note "Gatekeeper : $(state_label "$_gatekeeper")"

  if [ -z "$_sip$_filevault$_gatekeeper$_firewall" ]; then
    feature 'security' 'NOT_AVAILABLE' 'aucun des quatre outils de sécurité n’a répondu'
    return 0
  fi
  feature 'security' 'AVAILABLE'

  json_object \
    "$(jf_raw firewall "$(json_object \
      "$(jf_maybe_str engine 'com.apple.alf' NOT_AVAILABLE '')" \
      "$(jf_maybe_str state "$_firewall" NOT_AVAILABLE 'com.apple.alf illisible ou defaults absent')" \
      "$(jf_maybe_str defaultInputPolicy '' NOT_COLLECTED 'la politique par défaut du pare-feu applicatif macOS n’est pas exposée comme sur un pare-feu de paquets')" \
      "$(jf_maybe_num ruleCount '' NOT_COLLECTED 'le décompte exigerait socketfilterfw, qui demande l’élévation')")")" \
    "$(jf_maybe_str secureBoot '' NOT_COLLECTED 'la politique de démarrage sécurisé exige bputil, réservé aux Mac Apple Silicon et à l’administrateur')" \
    "$(jf_raw accounts '[]')" \
    "$(jf_raw obsoleteProtocols '[]')"
}

# Traduit un booléen éventuellement vide en mot lisible. Le cas vide rend
# « non lu » et jamais « désactivé » : ne pas avoir su lire une protection n'est
# pas la même chose que de l'avoir trouvée éteinte.
state_label() {
  case "${1-}" in
    true) printf 'actif' ;;
    false) printf 'désactivé' ;;
    *) printf 'non lu' ;;
  esac
}

# --- Alimentation -----------------------------------------------------------

collect_power() {
  have pmset || {
    feature 'power' 'NOT_AVAILABLE' 'pmset absent'
    return 0
  }

  _batt=$(pmset -g batt 2>/dev/null)
  if [ -z "$_batt" ]; then
    feature 'power' 'NOT_AVAILABLE' 'pmset -g batt muet'
    return 0
  fi

  _ac=''
  case "$_batt" in
    *"'AC Power'"*) _ac='true' ;;
    *"'Battery Power'"*) _ac='false' ;;
  esac

  _percent=$(printf '%s' "$_batt" | sed -n 's/.*[^0-9]\([0-9][0-9]*\)%.*/\1/p' | first_line)

  # Aucune batterie n'est un fait sur un Mac de bureau, et non une lecture
  # ratée : le tableau reste vide et `NOT_APPLICABLE` le dit.
  _batteries='[]'
  if [ -n "$_percent" ]; then
    feature 'power' 'AVAILABLE'
    _batteries="[$(json_object \
      "$(jf_maybe_str name 'InternalBattery' NOT_AVAILABLE '')" \
      "$(jf_maybe_str manufacturer '' NOT_COLLECTED 'exigerait ioreg -rc AppleSmartBattery, non analysé')" \
      "$(jf_maybe_str model '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_str serialNumber '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_str technology '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_num chargePercent "$_percent" NOT_AVAILABLE 'pourcentage illisible dans pmset')" \
      "$(jf_maybe_str status '' NOT_COLLECTED 'l’état natif de pmset n’est pas normalisé par ce scanner expérimental')" \
      "$(jf_maybe_num designCapacityWh '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_num fullChargeCapacityWh '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_num cycleCount '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_num voltageVolts '' NOT_COLLECTED 'idem')")]"
  else
    feature 'power' 'NOT_APPLICABLE' 'aucune batterie rapportée par pmset — attendu sur un Mac de bureau'
  fi

  json_object \
    "$(jf_raw batteries "$_batteries")" \
    "$(jf_maybe_bool acConnected "$_ac" NOT_AVAILABLE 'pmset n’a nommé aucune source d’alimentation')" \
    "$(jf_maybe_str activePlan '' NOT_APPLICABLE 'macOS n’expose pas de plan d’alimentation nommé comme Windows')" \
    "$(jf_maybe_str cpuGovernor '' NOT_APPLICABLE 'notion propre à Linux')"
}

# --- Historique -------------------------------------------------------------
#
# `log show` est l'unique journal de macOS depuis Sierra, et il est **coûteux** :
# une requête sur trente jours peut prendre plusieurs minutes et produire des
# gigaoctets. Ce scanner expérimental ne l'interroge donc pas, et le déclare :
# une section absente sans motif se lirait comme une machine sans incident.

collect_stability() {
  _boot_sec=$(sysctl_value kern.boottime | boottime_seconds)
  _uptime=''
  if [ -n "$_boot_sec" ]; then
    _now=$(date -u '+%s' 2>/dev/null || printf '')
    [ -n "$_now" ] && _uptime=$((_now - _boot_sec))
  fi

  # Les rapports de panne sont des **fichiers**, et les compter ne demande ni
  # `log show` ni privilège. C'est le seul compteur que ce scanner sait
  # produire honnêtement, et il porte sa fenêtre : celle du répertoire, que le
  # système purge lui-même.
  _crashes=''
  _crashdir="$HOME/Library/Logs/DiagnosticReports"
  if [ -d "$_crashdir" ]; then
    _crashes=$(find "$_crashdir" -name '*.ips' -o -name '*.crash' 2>/dev/null | wc -l | tr -d ' ')
    feature 'stability' 'AVAILABLE'
  else
    feature 'stability' 'NOT_AVAILABLE' 'répertoire DiagnosticReports absent ou inaccessible'
  fi

  json_object \
    "$(jf_maybe_num uptimeSeconds "$_uptime" NOT_AVAILABLE 'kern.boottime illisible')" \
    "$(jf_maybe_str bootedAt "$(epoch_to_iso "$_boot_sec")" NOT_AVAILABLE 'kern.boottime illisible')" \
    "$(jf_raw applicationCrashes "$(json_object \
      "$(jf_maybe_num count "$_crashes" NOT_AVAILABLE 'DiagnosticReports inaccessible')" \
      "$(jf_raw observationWindowMs "$(j_unknown NOT_AVAILABLE 'le répertoire est purgé par le système sans période fixe : annoncer une fenêtre serait l’inventer')")" \
      "$(jf_raw lastAt "$(j_unknown NOT_COLLECTED 'la date du dernier rapport n’est pas extraite')")" \
      "$(jf_maybe_str source 'Library/Logs/DiagnosticReports' NOT_AVAILABLE '')")")" \
    "$(jf_raw kernelCrashes "$(json_object \
      "$(jf_raw count "$(j_unknown NOT_COLLECTED 'les paniques noyau exigeraient log show, dont le coût est prohibitif')")" \
      "$(jf_raw observationWindowMs "$(j_unknown NOT_COLLECTED '')")" \
      "$(jf_raw lastAt "$(j_unknown NOT_COLLECTED '')")" \
      "$(jf_raw source "$(j_unknown NOT_COLLECTED '')")")")" \
    "$(jf_raw failedUnits '[]')" \
    "$(jf_raw coredumps '[]')" \
    "$(jf_raw kernelTainted "$(j_unknown NOT_APPLICABLE 'notion propre au noyau Linux')")" \
    "$(jf_raw meta "$(json_object \
      "$(jf_str source 'sysctl, DiagnosticReports')" \
      "$(jf_str method 'commande shell')" \
      "$(jf_str collectedAt "$(now_iso)")")")"
}

collect_boot() {
  # `sysctl kern.boottime` date le démarrage ; il ne dit **pas** combien de
  # temps il a duré. macOS ne publie aucune décomposition en phases comparable à
  # `systemd-analyze`, et en fabriquer une serait inventer.
  feature 'boot' 'NOT_AVAILABLE' 'macOS ne publie aucune durée de démarrage décomposée'

  _firmware='UEFI'
  # Les Mac Intel démarrent en EFI, les Apple Silicon en iBoot — ni l'un ni
  # l'autre n'est le « UEFI » ni le « BIOS hérité » que ce champ oppose. Le
  # déclarer UEFI serait donc à moitié faux ; il reste inconnu.
  _firmware=''

  json_object \
    "$(jf_raw phases '[]')" \
    "$(jf_raw totalMs "$(j_unknown NOT_AVAILABLE 'macOS ne publie pas de durée de démarrage')")" \
    "$(jf_maybe_str measuredAt "$(now_iso)" NOT_AVAILABLE '')" \
    "$(jf_raw slowestItems '[]')" \
    "$(jf_raw failedAtBoot '[]')" \
    "$(jf_maybe_str firmwareMode "$_firmware" NOT_APPLICABLE 'un Mac démarre en EFI ou en iBoot, dont aucun n’est l’UEFI ni le BIOS hérité que ce champ oppose')" \
    "$(jf_raw fastStartupEnabled "$(j_unknown NOT_APPLICABLE 'notion propre à Windows')")"
}

collect_events() {
  # `log show --last 30d` sur un Mac chargé produit plusieurs gigaoctets et
  # occupe la machine de longues minutes. Ce scanner ne l'appelle pas, et le
  # dit : sans cette déclaration, une section absente se lirait comme un journal
  # sans incident.
  feature 'events' 'NOT_COLLECTED' 'log show non appelé : son coût est prohibitif et ce scanner est expérimental'
  skipped 'events.entries'

  json_object \
    "$(jf_raw window "$(json_object \
      "$(jf_raw requestedMs "$(j_unknown NOT_COLLECTED 'aucune fenêtre demandée : le journal n’est pas lu')")" \
      "$(jf_raw coveredMs "$(j_unknown NOT_COLLECTED 'aucune lecture, donc aucune couverture')")" \
      "$(jf_raw since "$(j_unknown NOT_COLLECTED '')")" \
      "$(jf_raw until "$(j_unknown NOT_COLLECTED '')")" \
      "$(jf_raw persistent "$(j_unknown NOT_COLLECTED 'le journal unifié est persistant, mais l’affirmer sans l’avoir lu serait une supposition')")")")" \
    "$(jf_raw examined "$(j_unknown NOT_COLLECTED '')")" \
    "$(jf_raw truncated "$(j_unknown NOT_COLLECTED '')")" \
    "$(jf_raw entries '[]')"
}

# --- Assemblage -------------------------------------------------------------

log_info "SysAudit macOS $SCANNER_VERSION — EXPERIMENTAL, jamais exécuté sur un Mac réel"
log_step 'système'
SYSTEM=$(collect_system)
log_step 'système d’exploitation'
OS=$(collect_os)
log_step 'processeur'
CPUS=$(collect_cpus)
log_step 'mémoire'
MEMORY=$(collect_memory)
log_step 'stockage'
STORAGE=$(collect_storage)
log_step 'réseau'
NETWORK=$(collect_network)
log_step 'sécurité'
SECURITY=$(collect_security)
log_step 'alimentation'
POWER=$(collect_power)
log_step 'historique'
STABILITY=$(collect_stability)
BOOT=$(collect_boot)
EVENTS=$(collect_events)

PRIVILEGED=false
[ "$(id -u 2>/dev/null || printf 1)" = '0' ] && PRIVILEGED=true

CAPABILITIES=$(json_object \
  "$(jf_str platform 'macos')" \
  "$(jf_str architecture "$(uname -m 2>/dev/null | first_line)")" \
  "$(jf_raw privileged "$PRIVILEGED")" \
  "$(jf_raw proxmox false)" \
  "$(jf_raw docker false)" \
  "$(jf_raw tools "$(tools_json)")" \
  "$(section features "$(features_json)")")

COLLECTION=$(json_object \
  "$(jf_raw issues "$(issues_json)")" \
  "$(jf_raw skippedSections "$(skipped_json)")")

# `collectionMode` vaut toujours `offline` ici, et ce n'est pas un raccourci :
# ce scanner n'a ni `--upload`, ni `--api-url`. Il écrit un fichier, un point.
# Le rapport se dépose ensuite sur la page « Déposer un rapport ».
REPORT=$(json_object \
  "$(jf_str schemaVersion "$SCHEMA_VERSION")" \
  "$(jf_str scannerVersion "$SCANNER_VERSION")" \
  "$(jf_raw report "$(json_object \
    "$(jf_str generatedAt "$(now_iso)")" \
    "$(jf_str scannerKind 'macos')" \
    "$(jf_str profile 'quick')" \
    "$(jf_raw anonymized false)" \
    "$(jf_raw anonymizedCategories '[]')" \
    "$(jf_str collectionMode 'offline')")")" \
  "$(jf_raw capabilities "$CAPABILITIES")" \
  "$(jf_raw system "$SYSTEM")" \
  "$(jf_raw os "$OS")" \
  "$(section cpus "$CPUS")" \
  "$(section memory "$MEMORY")" \
  "$(section storage "$STORAGE")" \
  "$(section network "$NETWORK")" \
  "$(section security "$SECURITY")" \
  "$(section power "$POWER")" \
  "$(section stability "$STABILITY")" \
  "$(section boot "$BOOT")" \
  "$(section events "$EVENTS")" \
  "$(jf_raw notes "$(notes_json)")" \
  "$(jf_raw collection "$COLLECTION")")

if [ "$TO_STDOUT" = '1' ]; then
  printf '%s\n' "$REPORT"
  exit 0
fi

mkdir -p "$OUTPUT_DIR" 2>/dev/null || die "Répertoire de sortie inaccessible : $OUTPUT_DIR"
TARGET="$OUTPUT_DIR/sysaudit-macos-$(date -u '+%Y%m%d-%H%M%S').json"
printf '%s\n' "$REPORT" >"$TARGET" || die "Écriture impossible : $TARGET"
log_info "Rapport écrit : $TARGET"
log_warn 'Scanner EXPERIMENTAL : ce rapport n’a valeur ni de validation ni de mesure de référence.'
