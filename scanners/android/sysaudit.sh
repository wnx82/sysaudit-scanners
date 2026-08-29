#!/bin/sh
#
#                      Android — EXPERIMENTAL / UNVALIDATED
#
# ┌────────────────────────────────────────────────────────────────────────────┐
# │  CE SCANNER N'A JAMAIS ÉTÉ EXÉCUTÉ SUR UN APPAREIL ANDROID.                │
# │                                                                            │
# │  Il est écrit d'après la documentation d'Android et les pages de manuel de │
# │  `getprop` et `dumpsys`. Aucune de ses sorties n'a été confrontée à un      │
# │  téléphone. Tant que ce bandeau est là :                                    │
# │                                                                            │
# │    - aucune de ses collectes ne justifie une case ✅ dans la matrice de    │
# │      compatibilité ;                                                        │
# │    - un rapport qu'il produit se lit comme une hypothèse ;                  │
# │    - `notes` porte les mentions EXPERIMENTAL et UNVALIDATED.                │
# └────────────────────────────────────────────────────────────────────────────┘
#
# ## Android n'est pas un Linux comme les autres
#
# Le noyau est le même ; tout le reste diffère, et trois différences gouvernent
# ce fichier.
#
# **Le modèle de permissions.** Sur un appareil non rooté, le shell ne peut lire
# ni `/proc/<pid>` des autres applications, ni la plupart des services
# `dumpsys`, ni `logcat` sans le rôle approprié. Un champ vide n'y signifie donc
# pas « pas de donnée » mais presque toujours « pas le droit », et le scanner
# rapporte `PERMISSION_DENIED` plutôt que `NOT_AVAILABLE` chaque fois qu'il peut
# faire la différence. Les confondre inviterait à chercher une panne là où il n'y
# a qu'une politique.
#
# **Le mode de collecte change ce qui est lisible.** Lancé depuis l'appareil —
# Termux, ou une future application — le scanner a les droits de son processus.
# Lancé par `adb shell`, il a ceux du shell ADB, qui sont différents et souvent
# plus larges. Le rapport publie donc le mode dans ses notes : sans lui, deux
# rapports du même téléphone paraîtraient contradictoires.
#
# **Aucune donnée d'application n'est collectée.** Ni la liste des paquets
# installés, ni leurs données, ni le journal. C'est une décision de portée, pas
# une limite technique : l'inventaire applicatif d'un téléphone personnel est la
# donnée la plus intime qu'un audit puisse produire, et ce scanner n'a pas de
# raison de la porter.
#
# Usage :
#   ./sysaudit.sh                    audit, rapport dans le répertoire courant
#   ./sysaudit.sh --output-dir /tmp  choisit le répertoire de sortie
#   ./sysaudit.sh --stdout           écrit le JSON sur la sortie standard
#   ./sysaudit.sh --capabilities     montre ce qui serait collecté, sans scanner
#   ./sysaudit.sh --quiet
#   ./sysaudit.sh --version
#
# Depuis un poste, via ADB :
#   adb push sysaudit.sh lib /data/local/tmp/sysaudit/
#   adb shell sh /data/local/tmp/sysaudit/sysaudit.sh --stdout > rapport.json
#
# Read-only par construction : `getprop` lit, `setprop` n'apparaît nulle part,
# `settings get` lit, `settings put` n'apparaît nulle part.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
readonly SCRIPT_DIR

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
      printf 'sysaudit-android %s (EXPERIMENTAL, schéma %s)\n' "$SCANNER_VERSION" "$SCHEMA_VERSION"
      exit 0
      ;;
    -h | --help)
      sed -n '43,57p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "Option inconnue : $1" ;;
  esac
done

# --- Refus explicite --------------------------------------------------------
#
# `uname -s` rend « Linux » sur Android comme sur une Debian : il ne distingue
# rien. La marque d'Android est `getprop`, ou à défaut le répertoire
# `/system/build.prop`. Sans l'un des deux, ce scanner tournerait sur une Debian
# et produirait un rapport entièrement composé de marqueurs qu'on lirait comme
# « Android ne sait pas répondre ».
IS_ANDROID=0
have getprop && IS_ANDROID=1
[ -f /system/build.prop ] && IS_ANDROID=1

if [ "$IS_ANDROID" = '0' ] && [ "${SYSAUDIT_ALLOW_FOREIGN_HOST:-0}" != '1' ]; then
  die 'Ce scanner cible Android ; ni getprop ni /system/build.prop sur cet hôte. `uname -s` rend « Linux » ici comme sur une Debian et ne distingue rien : sans l’un de ces deux marqueurs, le rapport se lirait comme un Android incapable de répondre.'
fi

init_journal

note 'EXPERIMENTAL — scanner Android jamais exécuté sur un appareil réel. Ce rapport est une hypothèse, pas une mesure.'
note 'UNVALIDATED — aucune de ces collectes ne justifie une case validée dans la matrice de compatibilité.'
note 'Aucune donnée d’application n’est collectée : ni la liste des paquets installés, ni leurs données, ni le journal. C’est une décision de portée, pas une limite technique.'

TOOLS='getprop dumpsys settings uname cat df free top logcat pm cmd id'

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

# --- Mode de collecte -------------------------------------------------------
#
# Deux modes, et ils ne lisent pas les mêmes choses. Le déclarer n'est pas une
# coquetterie : sans lui, deux rapports du même téléphone paraîtraient
# contradictoires, et on chercherait la panne dans l'appareil.
#
# La marque du shell ADB est son utilisateur : `shell`, uid 2000. Une
# application ou Termux tournent sous un uid d'application (10000 et au-delà).

detect_mode() {
  _uid=$(id -u 2>/dev/null || printf '')
  case "$_uid" in
    0) printf 'root' ;;
    2000) printf 'adb' ;;
    '') printf 'inconnu' ;;
    *) printf 'application' ;;
  esac
}

MODE=$(detect_mode)

if [ "$CAPABILITIES_ONLY" = '1' ]; then
  printf 'sysaudit-android %s — EXPERIMENTAL, jamais exécuté sur un appareil réel.\n\n' "$SCANNER_VERSION"
  printf 'Mode de collecte : %s\n\n' "$MODE"
  printf 'Outils détectés :\n'
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

prop() {
  have getprop || return 0
  getprop "$1" 2>/dev/null | first_line
}

# Raison d'absence adaptée au mode.
#
# Sur un appareil non rooté, un `dumpsys` muet est presque toujours un refus, pas
# une absence. Les confondre inviterait à chercher une panne là où il n'y a
# qu'une politique de permissions — et c'est la confusion la plus coûteuse de
# tout ce fichier.
denial_reason() {
  if [ "$MODE" = 'root' ]; then
    printf 'NOT_AVAILABLE'
  else
    printf 'PERMISSION_DENIED'
  fi
}

DENIAL=$(denial_reason)

# Racine de `/proc`, pour que les tests puissent la simuler.
#
# C'est une **couture de test**, et la seule de ce fichier. Sans elle, l'analyse
# de `/proc/meminfo` et de `/proc/cpuinfo` — la partie la plus facile à écrire
# de travers — ne serait vérifiable que sur un appareil Android, c'est-à-dire
# jamais. Elle ne change rien en exploitation : la valeur par défaut est `/proc`,
# et rien dans le produit ne définit cette variable.
PROC="${SYSAUDIT_PROC_ROOT:-/proc}"

# --- Système ----------------------------------------------------------------

collect_system() {
  _manufacturer=$(prop ro.product.manufacturer)
  _model=$(prop ro.product.model)
  _device=$(prop ro.product.device)
  _serial=$(prop ro.serialno)

  # `ro.serialno` est vide sur Android 10 et suivants pour toute application
  # sans privilège : la lecture du numéro de série y est réservée au système.
  # Ce n'est donc pas une absence de donnée mais un refus, et le dire évite de
  # faire chercher un appareil défectueux.
  if [ -z "$_serial" ] && [ "$MODE" != 'root' ]; then
    feature 'system.serialNumber' 'PERMISSION_DENIED' 'ro.serialno est réservé au système depuis Android 10'
  fi

  _uptime=''
  if [ -r "$PROC/uptime" ]; then
    _uptime=$(awk '{ printf "%d", $1 }' "$PROC/uptime" 2>/dev/null)
  fi

  if [ -n "$_model" ]; then
    feature 'system' 'AVAILABLE'
  else
    feature 'system' "$DENIAL" 'getprop absent ou ro.product.model muet'
  fi

  json_object \
    "$(jf_maybe_str hostname "$_device" "$DENIAL" 'ro.product.device muet — Android n’a pas de nom d’hôte au sens habituel')" \
    "$(jf_maybe_str manufacturer "$_manufacturer" "$DENIAL" 'ro.product.manufacturer muet')" \
    "$(jf_maybe_str model "$_model" "$DENIAL" 'ro.product.model muet')" \
    "$(jf_maybe_str chassisType '' NOT_COLLECTED 'téléphone, tablette ou téléviseur se déduirait de ro.build.characteristics, ce qui reste une interprétation')" \
    "$(jf_maybe_str uuid '' NOT_APPLICABLE 'Android n’expose pas d’UUID SMBIOS ; l’identifiant Android est propre à l’application et n’a pas sa place ici')" \
    "$(jf_maybe_str serialNumber "$_serial" PERMISSION_DENIED 'ro.serialno est réservé au système depuis Android 10')" \
    "$(jf_maybe_str architecture "$(prop ro.product.cpu.abi)" "$DENIAL" 'ro.product.cpu.abi muet')" \
    "$(jf_maybe_num uptimeSeconds "$_uptime" "$DENIAL" "$PROC/uptime illisible")" \
    "$(jf_maybe_str timezone "$(prop persist.sys.timezone)" "$DENIAL" 'persist.sys.timezone muet')" \
    "$(jf_maybe_str localTime "$(now_iso)" NOT_AVAILABLE 'date indisponible')"
}

collect_os() {
  _release=$(prop ro.build.version.release)
  _sdk=$(prop ro.build.version.sdk)
  _patch=$(prop ro.build.version.security_patch)
  _build=$(prop ro.build.display.id)

  if [ -n "$_release" ]; then
    feature 'os' 'AVAILABLE'
  else
    feature 'os' "$DENIAL" 'ro.build.version.release muet'
  fi

  # Le niveau de correctif de sécurité est **la** donnée d'un audit Android :
  # c'est elle qui dit si l'appareil reçoit encore des correctifs. Elle porte sa
  # propre note pour être lisible sans dérouler le rapport.
  if [ -n "$_patch" ]; then
    note "Niveau de correctif de sécurité : $_patch"
    feature 'os.securityPatch' 'AVAILABLE'
  else
    feature 'os.securityPatch' "$DENIAL" 'ro.build.version.security_patch muet'
  fi

  # `family` vaut `linux` : Android **est** un Linux, et l'énumération du schéma
  # n'a pas de valeur `android`. La distinguer se fait par
  # `capabilities.platform`, qui vaut bien `android` — deux champs, deux
  # questions.
  json_object \
    "$(jf_str family 'linux')" \
    "$(jf_maybe_str name 'Android' NOT_AVAILABLE '')" \
    "$(jf_maybe_str edition '' NOT_APPLICABLE 'Android n’a pas d’édition')" \
    "$(jf_maybe_str distribution "$(prop ro.build.flavor)" "$DENIAL" 'ro.build.flavor muet')" \
    "$(jf_maybe_str version "$_release" "$DENIAL" 'ro.build.version.release muet')" \
    "$(jf_maybe_str build "$_build" "$DENIAL" 'ro.build.display.id muet')" \
    "$(jf_maybe_str kernel "$(uname -r 2>/dev/null | first_line)" NOT_AVAILABLE 'uname -r muet')" \
    "$(jf_maybe_str architecture "$(prop ro.product.cpu.abi)" "$DENIAL" 'ro.product.cpu.abi muet')" \
    "$(jf_maybe_str installDate '' NOT_COLLECTED 'ro.build.date donne la date de compilation du système, pas celle de son installation sur cet appareil')" \
    "$(jf_maybe_str locale "$(prop persist.sys.locale)" "$DENIAL" 'persist.sys.locale muet')" \
    "$(jf_maybe_str timezone '' NOT_COLLECTED 'lu dans system, pas dupliqué ici')" \
    "$(if [ -n "$_sdk" ]; then jf_raw support "$(json_object \
      "$(jf_str status 'UNKNOWN')" \
      "$(jf_str confidence 'LOW')" \
      "$(jf_str note "Niveau d’API $_sdk. La fin de support d’un appareil Android dépend du constructeur, pas de la version d’Android : la déduire de l’API serait une supposition.")")"; fi)"
}

collect_cpus() {
  _cores=''
  if [ -r "$PROC/cpuinfo" ]; then
    _cores=$(grep -c '^processor' "$PROC/cpuinfo" 2>/dev/null)
  fi
  _hardware=''
  if [ -r "$PROC/cpuinfo" ]; then
    _hardware=$(awk -F': *' '/^Hardware/ { print $2; exit }' "$PROC/cpuinfo" 2>/dev/null)
  fi
  [ -n "$_hardware" ] || _hardware=$(prop ro.board.platform)

  if [ -z "$_cores" ] && [ -z "$_hardware" ]; then
    feature 'cpus' "$DENIAL" "$PROC/cpuinfo illisible et ro.board.platform muet"
    return 0
  fi
  feature 'cpus' 'AVAILABLE'

  json_array "$(json_object \
    "$(jf_maybe_str manufacturer '' NOT_COLLECTED 'le fondeur se déduirait de la plateforme, ce qui serait une interprétation')" \
    "$(jf_maybe_str model "$_hardware" "$DENIAL" 'ni /proc/cpuinfo ni ro.board.platform n’ont nommé la puce')" \
    "$(jf_maybe_str family '' NOT_COLLECTED 'non publiée')" \
    "$(jf_maybe_str generation '' NOT_COLLECTED 'la génération commerciale se déduirait du modèle, ce qui serait une interprétation')" \
    "$(jf_maybe_str socket '' NOT_APPLICABLE 'un système sur puce est soudé ; il n’y a pas de socket à rapporter')" \
    "$(jf_maybe_num physicalCores '' NOT_COLLECTED 'les cœurs physiques d’un big.LITTLE ne se déduisent pas du nombre de lignes « processor », qui compte les cœurs logiques de tous les clusters')" \
    "$(jf_maybe_num logicalCores "$_cores" "$DENIAL" "$PROC/cpuinfo illisible")" \
    "$(jf_maybe_num baseFrequencyMhz '' NOT_COLLECTED 'un système sur puce a plusieurs clusters à fréquences distinctes ; une fréquence de base unique serait fausse')" \
    "$(jf_maybe_num maxFrequencyMhz '' NOT_COLLECTED 'idem')" \
    "$(jf_maybe_num currentFrequencyMhz '' NOT_COLLECTED 'idem')" \
    "$(jf_raw virtualization "$(j_unknown NOT_APPLICABLE 'notion sans objet sur un téléphone')")" \
    "$(jf_maybe_num temperatureCelsius '' "$DENIAL" 'les zones thermiques de /sys/class/thermal ne sont pas lisibles sans privilège sur la plupart des appareils')" \
    "$(jf_maybe_num usagePercent '' NOT_COLLECTED 'la charge instantanée n’est pas échantillonnée par ce scanner')")"
}

collect_memory() {
  _total=''
  _available=''
  if [ -r "$PROC/meminfo" ]; then
    _total=$(awk '/^MemTotal:/ { print $2 * 1024; exit }' "$PROC/meminfo" 2>/dev/null)
    _available=$(awk '/^MemAvailable:/ { print $2 * 1024; exit }' "$PROC/meminfo" 2>/dev/null)
    _swap_total=$(awk '/^SwapTotal:/ { print $2 * 1024; exit }' "$PROC/meminfo" 2>/dev/null)
    _swap_free=$(awk '/^SwapFree:/ { print $2 * 1024; exit }' "$PROC/meminfo" 2>/dev/null)
    feature 'memory' 'AVAILABLE'
  else
    _swap_total=''
    _swap_free=''
    feature 'memory' "$DENIAL" "$PROC/meminfo illisible"
  fi

  _swap_used=''
  if [ -n "$_swap_total" ] && [ -n "$_swap_free" ]; then
    _swap_used=$((_swap_total - _swap_free))
  fi

  json_object \
    "$(jf_maybe_num installedBytes "$_total" "$DENIAL" "$PROC/meminfo illisible")" \
    "$(jf_maybe_num availableBytes "$_available" "$DENIAL" "$PROC/meminfo illisible")" \
    "$(jf_maybe_num swapUsedBytes "$_swap_used" "$DENIAL" "$PROC/meminfo illisible")" \
    "$(jf_maybe_num swapTotalBytes "$_swap_total" "$DENIAL" "$PROC/meminfo illisible")" \
    "$(jf_maybe_num maxCapacityBytes '' NOT_APPLICABLE 'la mémoire d’un système sur puce n’est pas extensible')" \
    "$(jf_raw modules '[]')" \
    "$(jf_maybe_num slotsTotal '' NOT_APPLICABLE 'aucun emplacement mémoire sur un système sur puce')" \
    "$(jf_maybe_num slotsUsed '' NOT_APPLICABLE 'idem')"
}

# --- Stockage ---------------------------------------------------------------

collect_storage() {
  have df || {
    feature 'storage' "$DENIAL" 'df absent'
    return 0
  }

  # Seuls `/data` et `/` sont retenus. Lister tous les points de montage d'un
  # Android en produirait plusieurs dizaines — `/apex/*`, montages par
  # application, espaces de travail — dont aucun ne renseigne sur l'espace
  # réellement disponible pour l'utilisateur.
  _tmp="${TMPDIR:-/tmp}/sysaudit-android-parts.$$"
  df -k 2>/dev/null | awk '($NF == "/data" || $NF == "/" || $NF == "/storage/emulated") && NF >= 6 {
      pct = $(NF - 1); gsub(/%/, "", pct);
      printf "%s\t%s\t%s\t%s\t%s\t%s\n", $1, $NF, $2 * 1024, $3 * 1024, $4 * 1024, pct
    }' >"$_tmp"

  if [ ! -s "$_tmp" ]; then
    rm -f "$_tmp"
    feature 'storage' "$DENIAL" 'df n’a listé ni /data ni /'
    return 0
  fi
  feature 'storage' 'AVAILABLE'

  _rows=''
  while IFS="$(printf '\t')" read -r _dev _mount _total _used _free _pct; do
    [ -n "$_dev" ] || continue
    if [ -n "$_rows" ]; then _rows="$_rows,"; fi
    _rows="$_rows$(json_object \
      "$(jf_str name "$_dev")" \
      "$(jf_maybe_str mountPoint "$_mount" NOT_AVAILABLE 'point de montage illisible')" \
      "$(jf_maybe_str filesystem '' NOT_COLLECTED 'le type exigerait /proc/mounts, dont la lecture varie selon les appareils')" \
      "$(jf_maybe_num sizeBytes "$_total" NOT_AVAILABLE 'df muet')" \
      "$(jf_maybe_num usedBytes "$_used" NOT_AVAILABLE 'df muet')" \
      "$(jf_maybe_num freeBytes "$_free" NOT_AVAILABLE 'df muet')" \
      "$(jf_maybe_num usagePercent "$_pct" NOT_AVAILABLE 'df muet')" \
      "$(jf_maybe_bool encrypted '' NOT_COLLECTED 'le chiffrement est rapporté au niveau du système, pas par volume — voir la section sécurité')" \
      "$(jf_maybe_str encryptionType '' NOT_COLLECTED 'idem')")"
  done <"$_tmp"
  rm -f "$_tmp"

  skipped 'storage.disks'
  json_object \
    "$(jf_raw disks "[$(json_object \
      "$(jf_str device 'mémoire interne')" \
      "$(jf_str kind 'UNKNOWN')" \
      "$(jf_maybe_str manufacturer '' NOT_COLLECTED 'la mémoire UFS ou eMMC n’est pas inventoriée : ses attributs sont réservés au système')" \
      "$(jf_maybe_str model '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_str serialNumber '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_str firmware '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_num sizeBytes '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_str interface '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_num rotationRpm '' NOT_APPLICABLE 'aucune pièce mobile dans une mémoire flash')" \
      "$(jf_maybe_str partitionTable '' NOT_COLLECTED 'la table de partitions d’un Android n’est pas lisible sans privilège')" \
      "$(jf_maybe_bool removable '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_bool trimSupported '' NOT_COLLECTED 'idem')" \
      "$(jf_raw partitions "[$_rows]")")]")" \
    "$(jf_raw pools '[]')" \
    "$(jf_maybe_num totalBytes '' NOT_COLLECTED 'le total exigerait l’inventaire de la mémoire physique')" \
    "$(jf_maybe_num usedBytes '' NOT_COLLECTED 'idem')" \
    "$(jf_maybe_bool trimScheduled '' NOT_COLLECTED 'Android planifie le rejet de blocs sans l’exposer au shell')"
}

# --- Sécurité ---------------------------------------------------------------
#
# Trois faits, et ce sont les plus importants d'un audit Android : le niveau de
# correctif, l'état du chargeur d'amorçage, et le mode de Verified Boot.

collect_security() {
  _verified=$(prop ro.boot.verifiedbootstate)
  _bootloader=$(prop ro.boot.flash.locked)
  _crypto=$(prop ro.crypto.state)

  if [ -z "$_verified$_bootloader$_crypto" ]; then
    feature 'security' "$DENIAL" 'aucune propriété ro.boot.* ni ro.crypto.state lisible'
  else
    feature 'security' 'AVAILABLE'
  fi

  # `ro.boot.verifiedbootstate` vaut `green`, `yellow`, `orange` ou `red`. Seul
  # `green` signifie « chaîne de démarrage intacte et signée par le
  # constructeur ». Traiter `yellow` — signé par une clé tierce — comme `green`
  # ferait passer un appareil modifié pour un appareil d'origine.
  _boot_state=''
  case "$_verified" in
    green) _boot_state='ENABLED' ;;
    yellow | orange) _boot_state='PARTIAL' ;;
    red) _boot_state='DISABLED' ;;
  esac

  case "$_verified" in
    green) note 'Verified Boot : vert — chaîne de démarrage intacte et signée par le constructeur.' ;;
    yellow) note 'Verified Boot : jaune — démarrage signé par une clé tierce, pas par le constructeur.' ;;
    orange) note 'Verified Boot : orange — chargeur d’amorçage déverrouillé, aucune vérification.' ;;
    red) note 'Verified Boot : rouge — vérification échouée.' ;;
    '') note 'Verified Boot : non lu.' ;;
    *) note "Verified Boot : état natif « $_verified », non interprété." ;;
  esac

  # `ro.boot.flash.locked` vaut « 1 » verrouillé, « 0 » déverrouillé. La
  # propriété est absente sur beaucoup d'appareils : son absence n'est **pas**
  # un déverrouillage.
  case "$_bootloader" in
    1) note 'Chargeur d’amorçage : verrouillé.' ;;
    0) note 'Chargeur d’amorçage : déverrouillé.' ;;
    *) note 'Chargeur d’amorçage : non lu — ro.boot.flash.locked est absente sur beaucoup d’appareils, et son absence n’est pas un déverrouillage.' ;;
  esac

  _encrypted=''
  case "$_crypto" in
    encrypted) _encrypted='true' ;;
    unencrypted) _encrypted='false' ;;
  esac

  json_object \
    "$(jf_raw firewall "$(json_object \
      "$(jf_maybe_str engine '' NOT_APPLICABLE 'Android n’expose pas de pare-feu configurable au shell ; le filtrage est fait par le système, par application')" \
      "$(jf_maybe_str state '' NOT_APPLICABLE 'idem')" \
      "$(jf_maybe_str defaultInputPolicy '' NOT_APPLICABLE 'idem')" \
      "$(jf_maybe_num ruleCount '' NOT_APPLICABLE 'idem')")")" \
    "$(jf_maybe_str secureBoot "$_boot_state" "$DENIAL" 'ro.boot.verifiedbootstate muette')" \
    "$(jf_raw accounts '[]')" \
    "$(jf_raw obsoleteProtocols '[]')" \
    "$(jf_raw linux "$(json_object \
      "$(jf_maybe_str apparmor '' NOT_APPLICABLE 'Android emploie SELinux, jamais AppArmor')" \
      "$(jf_maybe_num sudoUsers '' NOT_APPLICABLE 'Android n’a pas de sudo ; l’élévation passe par le gestionnaire de root, hors de portée d’un scanner read-only')" \
      "$(jf_maybe_num passwordlessAccounts '' NOT_APPLICABLE 'Android n’a pas de comptes Unix au sens habituel : chaque application est un utilisateur')" \
      "$(jf_raw luks "$(json_object \
        "$(jf_raw present "$(if [ "$_encrypted" = 'true' ]; then printf 'true'; else printf 'false'; fi)")" \
        "$(jf_raw devices '[]')")")" \
      "$(jf_maybe_str selinux "$(case "$(if have getenforce; then getenforce 2>/dev/null | first_line; fi)" in
      Enforcing) printf 'ENFORCING' ;;
      Permissive) printf 'PERMISSIVE' ;;
      Disabled) printf 'DISABLED' ;;
    esac)" "$DENIAL" 'getenforce absent ou muet')")")"
}

# --- Alimentation -----------------------------------------------------------

collect_power() {
  # `dumpsys battery` est le seul chemin fiable, et il n'exige aucun privilège
  # particulier : c'est l'une des rares surfaces `dumpsys` ouvertes au shell.
  _dump=''
  if have dumpsys; then
    _dump=$(dumpsys battery 2>/dev/null)
  fi

  if [ -z "$_dump" ]; then
    feature 'power' "$DENIAL" 'dumpsys battery absent ou refusé'
    return 0
  fi
  feature 'power' 'AVAILABLE'

  _level=$(printf '%s' "$_dump" | awk -F': *' '/^ *level:/ { print $2; exit }')
  _status=$(printf '%s' "$_dump" | awk -F': *' '/^ *status:/ { print $2; exit }')
  _ac=$(printf '%s' "$_dump" | awk -F': *' '/^ *AC powered:/ { print $2; exit }')
  _usb=$(printf '%s' "$_dump" | awk -F': *' '/^ *USB powered:/ { print $2; exit }')
  _tech=$(printf '%s' "$_dump" | awk -F': *' '/^ *technology:/ { print $2; exit }')
  _temp=$(printf '%s' "$_dump" | awk -F': *' '/^ *temperature:/ { print $2; exit }')

  # `dumpsys battery` rend la température en **dixièmes de degré**. La publier
  # telle quelle donnerait 350 °C sur une batterie à 35 °C.
  _temp_c=''
  if [ -n "$_temp" ]; then
    _temp_c=$(awk -v t="$_temp" 'BEGIN { printf "%.1f", t / 10 }')
  fi

  _connected=''
  if [ "$_ac" = 'true' ] || [ "$_usb" = 'true' ]; then
    _connected='true'
  elif [ -n "$_ac" ] && [ -n "$_usb" ]; then
    _connected='false'
  fi

  # `status` est un **entier** : 2 en charge, 3 en décharge, 4 non chargée,
  # 5 pleine. Le publier tel quel dans un champ énuméré serait faux.
  _status_label=''
  case "$_status" in
    2) _status_label='CHARGING' ;;
    3) _status_label='DISCHARGING' ;;
    4) _status_label='NOT_CHARGING' ;;
    5) _status_label='FULL' ;;
    1) _status_label='UNKNOWN' ;;
  esac

  [ -n "$_temp_c" ] && note "Température de la batterie : $_temp_c °C (dumpsys battery, en dixièmes de degré à la source)."

  json_object \
    "$(jf_raw batteries "[$(json_object \
      "$(jf_maybe_str name 'battery' NOT_AVAILABLE '')" \
      "$(jf_maybe_str manufacturer '' NOT_COLLECTED 'non publié par dumpsys battery')" \
      "$(jf_maybe_str model '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_str serialNumber '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_str technology "$_tech" NOT_AVAILABLE 'dumpsys battery muet sur la technologie')" \
      "$(jf_maybe_num chargePercent "$_level" NOT_AVAILABLE 'niveau illisible')" \
      "$(jf_maybe_str status "$_status_label" NOT_AVAILABLE 'code de statut inconnu ou absent')" \
      "$(jf_maybe_num designCapacityWh '' NOT_COLLECTED 'la capacité de conception n’est pas publiée par dumpsys battery ; l’usure d’une batterie Android n’est donc pas calculable ici')" \
      "$(jf_maybe_num fullChargeCapacityWh '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_num cycleCount '' NOT_COLLECTED 'le compteur de cycles exige Android 14 et une permission système')" \
      "$(jf_maybe_num voltageVolts '' NOT_COLLECTED 'dumpsys rend des millivolts ; la conversion est triviale mais le champ n’est pas extrait par ce scanner expérimental')")]")" \
    "$(jf_maybe_bool acConnected "$_connected" NOT_AVAILABLE 'ni « AC powered » ni « USB powered » lisibles')" \
    "$(jf_maybe_str activePlan '' NOT_COLLECTED 'le mode économiseur exige settings get global low_power, non lu')" \
    "$(jf_maybe_str cpuGovernor '' "$DENIAL" '/sys/devices/system/cpu/*/cpufreq n’est pas lisible sans privilège sur la plupart des appareils')"
}

# --- Historique -------------------------------------------------------------

collect_stability() {
  _uptime=''
  if [ -r "$PROC/uptime" ]; then
    _uptime=$(awk '{ printf "%d", $1 }' "$PROC/uptime" 2>/dev/null)
    feature 'stability' 'AVAILABLE'
  else
    feature 'stability' "$DENIAL" "$PROC/uptime illisible"
  fi

  _booted=''
  if [ -n "$_uptime" ]; then
    _now=$(date -u '+%s' 2>/dev/null || printf '')
    [ -n "$_now" ] && _booted=$(epoch_to_iso $((_now - _uptime)))
  fi

  # `ro.boot.bootreason` dit **pourquoi** le dernier démarrage a eu lieu. C'est
  # la seule trace d'arrêt anormal accessible sans privilège, et sa valeur est
  # native : `reboot,userrequested`, `kernel_panic`, `watchdog`, `shutdown,thermal`…
  # Elle est rapportée telle quelle, jamais traduite ni interprétée : la
  # classer appartient au moteur d'analyse.
  _reason=$(prop ro.boot.bootreason)
  [ -n "$_reason" ] || _reason=$(prop sys.boot.reason)
  [ -n "$_reason" ] && note "Motif du dernier démarrage, tel que rapporté : $_reason"

  json_object \
    "$(jf_maybe_num uptimeSeconds "$_uptime" "$DENIAL" "$PROC/uptime illisible")" \
    "$(jf_maybe_str bootedAt "$_booted" "$DENIAL" "$PROC/uptime illisible")" \
    "$(jf_raw applicationCrashes "$(json_object \
      "$(jf_raw count "$(j_unknown PERMISSION_DENIED 'les crashs applicatifs exigeraient logcat, et ce scanner ne collecte aucune donnée d’application')")" \
      "$(jf_raw observationWindowMs "$(j_unknown NOT_COLLECTED '')")" \
      "$(jf_raw lastAt "$(j_unknown NOT_COLLECTED '')")" \
      "$(jf_raw source "$(j_unknown NOT_COLLECTED '')")")")" \
    "$(jf_raw failedUnits '[]')" \
    "$(jf_raw coredumps '[]')" \
    "$(jf_raw kernelTainted "$(j_unknown "$DENIAL" '/proc/sys/kernel/tainted n’est pas lisible sans privilège sur la plupart des appareils')")" \
    "$(jf_raw meta "$(json_object \
      "$(jf_str source 'getprop, /proc')" \
      "$(jf_str method 'commande shell')" \
      "$(jf_str collectedAt "$(now_iso)")")")"
}

collect_boot() {
  feature 'boot' 'NOT_AVAILABLE' 'Android ne publie aucune durée de démarrage décomposée accessible au shell'

  json_object \
    "$(jf_raw phases '[]')" \
    "$(jf_raw totalMs "$(j_unknown NOT_AVAILABLE 'ro.boottime.* n’est pas exposé uniformément ; les valeurs varient d’un constructeur à l’autre et ne se composent pas')")" \
    "$(jf_maybe_str measuredAt "$(now_iso)" NOT_AVAILABLE '')" \
    "$(jf_raw slowestItems '[]')" \
    "$(jf_raw failedAtBoot '[]')" \
    "$(jf_maybe_str firmwareMode '' NOT_APPLICABLE 'un Android démarre par son chargeur d’amorçage, qui n’est ni l’UEFI ni le BIOS hérité que ce champ oppose')" \
    "$(jf_raw fastStartupEnabled "$(j_unknown NOT_APPLICABLE 'notion propre à Windows')")"
}

collect_events() {
  # `logcat` contient les journaux de **toutes** les applications, y compris ce
  # qu'elles y écrivent d'intime. Ce scanner ne le lit pas : c'est une décision
  # de portée, écrite en tête de ce fichier, et non une limite technique.
  feature 'events' 'NOT_COLLECTED' 'logcat n’est pas lu : il contient les journaux de toutes les applications, et ce scanner ne collecte aucune donnée d’application'
  skipped 'events.entries'

  json_object \
    "$(jf_raw window "$(json_object \
      "$(jf_raw requestedMs "$(j_unknown NOT_COLLECTED 'aucune fenêtre demandée : le journal n’est pas lu')")" \
      "$(jf_raw coveredMs "$(j_unknown NOT_COLLECTED 'aucune lecture, donc aucune couverture')")" \
      "$(jf_raw since "$(j_unknown NOT_COLLECTED '')")" \
      "$(jf_raw until "$(j_unknown NOT_COLLECTED '')")" \
      "$(jf_raw persistent false)")")" \
    "$(jf_raw examined "$(j_unknown NOT_COLLECTED '')")" \
    "$(jf_raw truncated "$(j_unknown NOT_COLLECTED '')")" \
    "$(jf_raw entries '[]')"
}

# --- Assemblage -------------------------------------------------------------

log_info "SysAudit Android $SCANNER_VERSION — EXPERIMENTAL, jamais exécuté sur un appareil réel"
log_step "mode de collecte : $MODE"
note "Mode de collecte : $MODE. Il change ce qui est lisible : le shell ADB et une application n’ont pas les mêmes droits, et deux rapports du même appareil peuvent donc différer sans que l’appareil ait changé."

SYSTEM=$(collect_system)
OS=$(collect_os)
log_step 'processeur et mémoire'
CPUS=$(collect_cpus)
MEMORY=$(collect_memory)
log_step 'stockage'
STORAGE=$(collect_storage)
log_step 'sécurité'
SECURITY=$(collect_security)
log_step 'batterie'
POWER=$(collect_power)
log_step 'historique'
STABILITY=$(collect_stability)
BOOT=$(collect_boot)
EVENTS=$(collect_events)

PRIVILEGED=false
[ "$MODE" = 'root' ] && PRIVILEGED=true

CAPABILITIES=$(json_object \
  "$(jf_str platform 'android')" \
  "$(jf_str architecture "$(uname -m 2>/dev/null | first_line)")" \
  "$(jf_raw privileged "$PRIVILEGED")" \
  "$(jf_raw proxmox false)" \
  "$(jf_raw docker false)" \
  "$(jf_raw tools "$(tools_json)")" \
  "$(section features "$(features_json)")")

# `collectionMode` vaut toujours `offline` ici, et ce n'est pas un raccourci :
# ce scanner n'a ni `--upload`, ni `--api-url`. Il écrit un fichier, un point.
# Le rapport se dépose ensuite sur la page « Déposer un rapport ».
REPORT=$(json_object \
  "$(jf_str schemaVersion "$SCHEMA_VERSION")" \
  "$(jf_str scannerVersion "$SCANNER_VERSION")" \
  "$(jf_raw report "$(json_object \
    "$(jf_str generatedAt "$(now_iso)")" \
    "$(jf_str scannerKind 'android')" \
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
  "$(section security "$SECURITY")" \
  "$(section power "$POWER")" \
  "$(section stability "$STABILITY")" \
  "$(section boot "$BOOT")" \
  "$(section events "$EVENTS")" \
  "$(jf_raw notes "$(notes_json)")" \
  "$(jf_raw collection "$(json_object \
    "$(jf_raw issues "$(issues_json)")" \
    "$(jf_raw skippedSections "$(skipped_json)")")")")

if [ "$TO_STDOUT" = '1' ]; then
  printf '%s\n' "$REPORT"
  exit 0
fi

mkdir -p "$OUTPUT_DIR" 2>/dev/null || die "Répertoire de sortie inaccessible : $OUTPUT_DIR"
TARGET="$OUTPUT_DIR/sysaudit-android-$(date -u '+%Y%m%d-%H%M%S').json"
printf '%s\n' "$REPORT" >"$TARGET" || die "Écriture impossible : $TARGET"
log_info "Rapport écrit : $TARGET"
log_warn 'Scanner EXPERIMENTAL : ce rapport n’a valeur ni de validation ni de mesure de référence.'
