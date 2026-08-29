#!/bin/sh
#
#            FreeBSD · pfSense · OPNsense — EXPERIMENTAL / UNVALIDATED
#
# ┌────────────────────────────────────────────────────────────────────────────┐
# │  CE SCANNER N'A JAMAIS ÉTÉ EXÉCUTÉ SUR UN FREEBSD, UN PFSENSE NI UN        │
# │  OPNSENSE.                                                                 │
# │                                                                            │
# │  Il est écrit d'après les pages de manuel de FreeBSD et la documentation   │
# │  des deux appliances. Aucune de ses sorties n'a été confrontée à une       │
# │  machine réelle. Tant que ce bandeau est là :                              │
# │                                                                            │
# │    - aucune de ses collectes ne justifie une case ✅ dans la matrice de    │
# │      compatibilité ;                                                       │
# │    - un rapport qu'il produit se lit comme une hypothèse, pas comme une    │
# │      mesure ;                                                              │
# │    - `notes` porte les mentions EXPERIMENTAL et UNVALIDATED, que           │
# │      l'interface affiche.                                                  │
# └────────────────────────────────────────────────────────────────────────────┘
#
# ## Une appliance n'est pas un serveur
#
# pfSense et OPNsense sont des FreeBSD, et ce scanner les traite comme tels
# pour tout ce qui vient du système. Mais deux différences changent la manière
# de lire un rapport, et le scanner les publie plutôt que de les gommer :
#
#   - **l'appliance est le pare-feu**. Sur un serveur, un pare-feu inactif est
#     un défaut ; sur un routeur de bordure, `pf` est la fonction même de la
#     machine, et son état est le fait le plus important du rapport ;
#   - **la version de l'appliance n'est pas celle de FreeBSD**. pfSense 2.7 et
#     OPNsense 24.7 tournent sur des bases différentes, et confondre les deux
#     versions ferait conclure à une fin de support qui n'existe pas.
#
# Usage :
#   ./sysaudit.sh                    audit, rapport dans le répertoire courant
#   ./sysaudit.sh --output-dir /tmp  choisit le répertoire de sortie
#   ./sysaudit.sh --stdout           écrit le JSON sur la sortie standard
#   ./sysaudit.sh --capabilities     montre ce qui serait collecté, sans scanner
#   ./sysaudit.sh --quiet
#   ./sysaudit.sh --version
#
# Read-only par construction : `pfctl -s` lit, `pfctl -f` n'apparaît nulle part,
# et aucune commande de ce fichier n'écrit dans la configuration du système.

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
      printf 'sysaudit-bsd %s (EXPERIMENTAL, schéma %s)\n' "$SCANNER_VERSION" "$SCHEMA_VERSION"
      exit 0
      ;;
    -h | --help)
      sed -n '33,42p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "Option inconnue : $1" ;;
  esac
done

UNAME_S=$(uname -s 2>/dev/null || printf 'unknown')
if [ "$UNAME_S" != 'FreeBSD' ] && [ "${SYSAUDIT_ALLOW_FOREIGN_HOST:-0}" != '1' ]; then
  die "Ce scanner cible FreeBSD et ses dérivés ; l’hôte annonce « $UNAME_S ». Les collectes échoueraient toutes, et le rapport se lirait comme un FreeBSD incapable de répondre."
fi

init_journal

note 'EXPERIMENTAL — scanner FreeBSD/pfSense/OPNsense jamais exécuté sur une machine réelle. Ce rapport est une hypothèse, pas une mesure.'
note 'UNVALIDATED — aucune de ces collectes ne justifie une case validée dans la matrice de compatibilité.'

TOOLS='sysctl uname hostname freebsd-version df ifconfig pfctl service smartctl
zpool dmesg swapinfo pkg netstat kldstat sockstat'

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

# --- Distribution : FreeBSD, pfSense ou OPNsense ----------------------------
#
# La détection se fait sur des **fichiers de version**, jamais sur la présence
# d'un paquet ni sur le nom d'hôte. Un FreeBSD sur lequel quelqu'un a installé
# `pfSense-something` resterait un FreeBSD, et le déclarer appliance ferait lire
# tout le reste du rapport de travers.

detect_flavor() {
  if [ -f /usr/local/opnsense/version/core ]; then
    printf 'OPNsense'
    return 0
  fi
  # pfSense écrit sa version dans `/etc/version`. FreeBSD n'a pas ce fichier ;
  # sa version se lit dans `freebsd-version`.
  if [ -f /etc/version ] && [ -d /cf/conf ]; then
    printf 'pfSense'
    return 0
  fi
  printf 'FreeBSD'
}

flavor_version() {
  case "$1" in
    OPNsense) cat /usr/local/opnsense/version/core 2>/dev/null | first_line ;;
    pfSense) cat /etc/version 2>/dev/null | first_line ;;
    *) return 0 ;;
  esac
}

FLAVOR=$(detect_flavor)
FLAVOR_VERSION=$(flavor_version "$FLAVOR")

if [ "$CAPABILITIES_ONLY" = '1' ]; then
  printf 'sysaudit-bsd %s — EXPERIMENTAL, jamais exécuté sur une machine réelle.\n\n' "$SCANNER_VERSION"
  printf 'Système détecté : %s' "$FLAVOR"
  [ -n "$FLAVOR_VERSION" ] && printf ' %s' "$FLAVOR_VERSION"
  printf '\n\nOutils détectés :\n'
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

sysctl_value() {
  have sysctl || return 0
  sysctl -n "$1" 2>/dev/null | first_line
}

# Secondes de `kern.boottime`, qui rend `{ sec = 1785000000, usec = 0 } …`.
#
# Une expression régulière `.*sec *= *\([0-9]*\)` **ne marche pas** : le `.*`
# glouton atteint « usec », et l'uptime devenait l'instant Unix tout entier —
# soit cinquante-six ans, ce que le schéma refuse. Chercher le champ « sec »
# exact ne peut pas se tromper. Le test l'a trouvé ; aucune relecture ne l'avait
# vu.
boot_epoch() {
  sysctl_value kern.boottime |
    awk '{ for (i = 1; i <= NF; i++) if ($i == "sec") { gsub(/[^0-9]/, "", $(i + 2)); print $(i + 2); exit } }'
}

uptime_seconds() {
  _b=$(boot_epoch)
  [ -n "$_b" ] || return 0
  _n=$(date -u '+%s' 2>/dev/null) || return 0
  _u=$((_n - _b))
  [ "$_u" -lt 0 ] && return 0
  printf '%s' "$_u"
}

# --- Système ----------------------------------------------------------------

collect_system() {
  _hostname=$(hostname 2>/dev/null | first_line)
  _model=$(sysctl_value hw.model)
  _arch=$(uname -m 2>/dev/null | first_line)
  _uptime=$(uptime_seconds)

  if [ -n "$_model" ] || [ -n "$_hostname" ]; then
    feature 'system' 'AVAILABLE'
  else
    feature 'system' 'NOT_AVAILABLE' 'ni hostname ni sysctl hw.model n’ont répondu'
  fi

  # `hw.model` sur FreeBSD nomme le **processeur**, pas la machine — c'est
  # l'inverse de macOS, où `hw.model` nomme la machine. Le recopier dans
  # `system.model` produirait une machine « Intel(R) Xeon(R) », ce qui est faux
  # deux fois : ce n'est ni le modèle, ni le fabricant.
  _sys_model=''
  if have kenv; then
    _sys_model=$(kenv smbios.system.product 2>/dev/null | first_line)
  fi
  _vendor=''
  if have kenv; then
    _vendor=$(kenv smbios.system.maker 2>/dev/null | first_line)
  fi

  json_object \
    "$(jf_maybe_str hostname "$_hostname" NOT_AVAILABLE 'hostname muet')" \
    "$(jf_maybe_str manufacturer "$_vendor" NOT_AVAILABLE 'kenv absent ou smbios.system.maker non renseigné')" \
    "$(jf_maybe_str model "$_sys_model" NOT_AVAILABLE 'kenv absent ou smbios.system.product non renseigné ; hw.model nomme le processeur, pas la machine')" \
    "$(jf_maybe_str chassisType '' NOT_COLLECTED 'le châssis se déduirait du modèle, ce qui serait une interprétation')" \
    "$(jf_maybe_str uuid "$(if have kenv; then kenv smbios.system.uuid 2>/dev/null | first_line; fi)" NOT_AVAILABLE 'kenv absent ou UUID non renseigné')" \
    "$(jf_maybe_str serialNumber "$(if have kenv; then kenv smbios.system.serial 2>/dev/null | first_line; fi)" NOT_AVAILABLE 'kenv absent ou numéro de série non renseigné')" \
    "$(jf_maybe_str architecture "$_arch" NOT_AVAILABLE 'uname -m muet')" \
    "$(jf_maybe_num uptimeSeconds "$_uptime" NOT_AVAILABLE 'kern.boottime illisible')" \
    "$(jf_maybe_str timezone "$(readlink /etc/localtime 2>/dev/null | sed 's#.*/zoneinfo/##')" NOT_AVAILABLE '/etc/localtime non résolu')" \
    "$(jf_maybe_str localTime "$(now_iso)" NOT_AVAILABLE 'date indisponible')"
}

collect_os() {
  _base=''
  if have freebsd-version; then
    _base=$(freebsd-version 2>/dev/null | first_line)
  fi
  [ -n "$_base" ] || _base=$(uname -r 2>/dev/null | first_line)

  if [ -n "$_base" ]; then
    feature 'os' 'AVAILABLE'
  else
    feature 'os' 'NOT_AVAILABLE' 'ni freebsd-version ni uname -r n’ont répondu'
  fi

  # La version de l'appliance et celle de la base FreeBSD sont **deux champs
  # distincts**. Les confondre ferait conclure à une fin de support qui
  # n'existe pas : OPNsense 24.7 tourne sur une base FreeBSD 13 encore
  # supportée, et lire « 13.2 » comme la version du produit serait faux.
  if [ "$FLAVOR" != 'FreeBSD' ]; then
    if [ -n "$FLAVOR_VERSION" ]; then
      note "$FLAVOR $FLAVOR_VERSION sur base FreeBSD $_base — deux versions distinctes, à ne pas confondre."
      feature 'os.appliance' 'AVAILABLE'
    else
      feature 'os.appliance' 'NOT_AVAILABLE' "$FLAVOR détecté, mais son fichier de version est illisible"
    fi
  fi

  json_object \
    "$(jf_str family 'freebsd')" \
    "$(jf_maybe_str name "$FLAVOR" NOT_AVAILABLE '')" \
    "$(jf_maybe_str edition '' NOT_APPLICABLE 'ni FreeBSD ni ses dérivés n’ont d’édition')" \
    "$(jf_maybe_str distribution "$FLAVOR" NOT_AVAILABLE '')" \
    "$(jf_maybe_str version "$(if [ -n "$FLAVOR_VERSION" ]; then printf '%s' "$FLAVOR_VERSION"; else printf '%s' "$_base"; fi)" NOT_AVAILABLE 'aucune version lisible')" \
    "$(jf_maybe_str build "$_base" NOT_AVAILABLE 'freebsd-version muet')" \
    "$(jf_maybe_str kernel "$(uname -r 2>/dev/null | first_line)" NOT_AVAILABLE 'uname -r muet')" \
    "$(jf_maybe_str architecture "$(uname -m 2>/dev/null | first_line)" NOT_AVAILABLE 'uname -m muet')" \
    "$(jf_maybe_str installDate '' NOT_COLLECTED 'la date d’installation se déduirait d’un horodatage de fichier, ce qui n’est pas la même chose')" \
    "$(jf_maybe_str locale "${LANG-}" NOT_AVAILABLE 'LANG non défini')" \
    "$(jf_maybe_str timezone '' NOT_COLLECTED 'lu dans system, pas dupliqué ici')"
}

collect_cpus() {
  _brand=$(sysctl_value hw.model)
  _ncpu=$(sysctl_value hw.ncpu)

  if [ -z "$_brand" ] && [ -z "$_ncpu" ]; then
    feature 'cpus' 'NOT_AVAILABLE' 'sysctl n’a rendu ni hw.model ni hw.ncpu'
    return 0
  fi
  feature 'cpus' 'AVAILABLE'

  # `hw.ncpu` compte les processeurs **logiques**. Le nombre de cœurs physiques
  # exigerait `kern.sched.topology_spec`, un document XML : il reste inconnu
  # plutôt que déduit d'une division par deux, qui serait fausse sur tout
  # processeur sans SMT.
  json_array "$(json_object \
    "$(jf_maybe_str manufacturer '' NOT_COLLECTED 'le fabricant se déduirait de la marque, ce qui serait une interprétation')" \
    "$(jf_maybe_str model "$_brand" NOT_AVAILABLE 'sysctl hw.model muet')" \
    "$(jf_maybe_str family '' NOT_COLLECTED 'non extraite par ce scanner expérimental')" \
    "$(jf_maybe_str generation '' NOT_COLLECTED 'la génération commerciale se déduirait du modèle, ce qui serait une interprétation')" \
    "$(jf_maybe_str socket '' NOT_COLLECTED 'exigerait dmidecode, absent des installations par défaut')" \
    "$(jf_maybe_num physicalCores '' NOT_COLLECTED 'hw.ncpu compte les processeurs logiques ; les cœurs physiques exigeraient d’analyser kern.sched.topology_spec, un document XML')" \
    "$(jf_maybe_num logicalCores "$_ncpu" NOT_AVAILABLE 'hw.ncpu muet')" \
    "$(jf_maybe_num baseFrequencyMhz '' NOT_COLLECTED 'dev.cpu.0.freq donne la fréquence courante, pas la fréquence de base')" \
    "$(jf_maybe_num maxFrequencyMhz '' NOT_COLLECTED 'non publiée par sysctl')" \
    "$(jf_maybe_num currentFrequencyMhz "$(sysctl_value dev.cpu.0.freq)" NOT_AVAILABLE 'dev.cpu.0.freq absent — normal sans pilote de gestion de fréquence')" \
    "$(jf_raw virtualization "$(j_unknown NOT_COLLECTED 'la virtualisation matérielle n’est pas interrogée par ce scanner expérimental')")" \
    "$(jf_maybe_num temperatureCelsius '' NOT_COLLECTED 'dev.cpu.0.temperature exige le module coretemp ou amdtemp, dont le chargement n’est pas tenté')" \
    "$(jf_maybe_num usagePercent '' NOT_COLLECTED 'la charge instantanée n’est pas échantillonnée par ce scanner')")"
}

collect_memory() {
  _total=$(sysctl_value hw.physmem)
  # `vm.stats.vm.v_free_count` est en **pages** ; la taille de page se lit dans
  # `hw.pagesize`. La supposer à 4096 serait faux sur les architectures à
  # grandes pages.
  _pagesize=$(sysctl_value hw.pagesize)
  _free_pages=$(sysctl_value vm.stats.vm.v_free_count)
  _available=''
  if [ -n "$_pagesize" ] && [ -n "$_free_pages" ]; then
    _available=$((_free_pages * _pagesize))
  fi

  _swap_used=''
  _swap_total=''
  if have swapinfo; then
    _swap_line=$(swapinfo -k 2>/dev/null | awk '$1 == "Total" { print $2, $3 }')
    if [ -n "$_swap_line" ]; then
      _swap_total=$(printf '%s' "$_swap_line" | awk '{ print $1 * 1024 }')
      _swap_used=$(printf '%s' "$_swap_line" | awk '{ print $2 * 1024 }')
    fi
  fi

  if [ -n "$_total" ]; then
    feature 'memory' 'AVAILABLE'
  else
    feature 'memory' 'NOT_AVAILABLE' 'hw.physmem muet'
  fi

  json_object \
    "$(jf_maybe_num installedBytes "$_total" NOT_AVAILABLE 'hw.physmem muet')" \
    "$(jf_maybe_num availableBytes "$_available" NOT_AVAILABLE 'vm.stats.vm.v_free_count ou hw.pagesize illisible')" \
    "$(jf_maybe_num swapUsedBytes "$_swap_used" NOT_AVAILABLE 'swapinfo absent ou muet')" \
    "$(jf_maybe_num swapTotalBytes "$_swap_total" NOT_AVAILABLE 'swapinfo absent ou muet')" \
    "$(jf_maybe_num maxCapacityBytes '' NOT_COLLECTED 'exigerait dmidecode, absent des installations par défaut')" \
    "$(jf_raw modules '[]')" \
    "$(jf_maybe_num slotsTotal '' NOT_COLLECTED 'idem')" \
    "$(jf_maybe_num slotsUsed '' NOT_COLLECTED 'idem')"
}

# --- Stockage ---------------------------------------------------------------

collect_storage() {
  have df || {
    feature 'storage' 'NOT_AVAILABLE' 'df absent'
    return 0
  }

  _tmp="${TMPDIR:-/tmp}/sysaudit-bsd-parts.$$"
  df -k -P 2>/dev/null | awk 'NR > 1 && $1 ~ /^\/dev\// {
      pct = $5; gsub(/%/, "", pct);
      printf "%s\t%s\t%s\t%s\t%s\t%s\n", $1, $6, $2 * 1024, $3 * 1024, $4 * 1024, pct
    }' >"$_tmp"

  if [ ! -s "$_tmp" ]; then
    rm -f "$_tmp"
    feature 'storage' 'NOT_AVAILABLE' 'df n’a listé aucun système de fichiers sur périphérique'
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
      "$(jf_maybe_str filesystem '' NOT_COLLECTED 'le type exigerait mount -p, non analysé')" \
      "$(jf_maybe_num sizeBytes "$_total" NOT_AVAILABLE 'df muet')" \
      "$(jf_maybe_num usedBytes "$_used" NOT_AVAILABLE 'df muet')" \
      "$(jf_maybe_num freeBytes "$_free" NOT_AVAILABLE 'df muet')" \
      "$(jf_maybe_num usagePercent "$_pct" NOT_AVAILABLE 'df muet')" \
      "$(jf_maybe_bool encrypted '' NOT_COLLECTED 'GELI exigerait geli status, qui demande l’élévation')" \
      "$(jf_maybe_str encryptionType '' NOT_COLLECTED 'idem')")"
  done <"$_tmp"
  rm -f "$_tmp"

  # Les pools ZFS, en revanche, se lisent proprement : `zpool list -H` a un
  # format tabulé stable. Un pool dégradé est le fait le plus important qu'un
  # rapport de stockage puisse porter, et il ne coûte qu'une commande.
  _pools=''
  if have zpool; then
    _ptmp="${TMPDIR:-/tmp}/sysaudit-bsd-pools.$$"
    zpool list -H -o name,size,alloc,health 2>/dev/null >"$_ptmp"
    while IFS="$(printf '\t')" read -r _pname _psize _palloc _phealth; do
      [ -n "$_pname" ] || continue
      if [ -n "$_pools" ]; then _pools="$_pools,"; fi
      _pools="$_pools$(json_object \
        "$(jf_str name "$_pname")" \
        "$(jf_str type 'zfs')" \
        "$(jf_maybe_str state "$_phealth" NOT_AVAILABLE 'zpool muet')" \
        "$(jf_maybe_num sizeBytes '' NOT_COLLECTED 'zpool rend une taille lisible par un humain (« 1.81T ») ; la convertir en octets par une table d’unités écrite à la main introduirait une erreur d’arrondi silencieuse')" \
        "$(jf_maybe_num usedBytes '' NOT_COLLECTED 'idem')" \
        "$(jf_raw members '[]')")"
    done <"$_ptmp"
    rm -f "$_ptmp"
    [ -n "$_pools" ] && feature 'storage.pools' 'AVAILABLE'
  else
    feature 'storage.pools' 'NOT_AVAILABLE' 'zpool absent — normal sur une installation UFS'
  fi

  skipped 'storage.disks'
  json_object \
    "$(jf_raw disks "[$(json_object \
      "$(jf_str device 'systèmes de fichiers montés')" \
      "$(jf_str kind 'UNKNOWN')" \
      "$(jf_maybe_str manufacturer '' NOT_COLLECTED 'l’inventaire des disques physiques exigerait camcontrol devlist et geom disk list, non analysés')" \
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
    "$(jf_raw pools "[$_pools]")" \
    "$(jf_maybe_num totalBytes '' NOT_COLLECTED 'le total exigerait l’inventaire des disques physiques')" \
    "$(jf_maybe_num usedBytes '' NOT_COLLECTED 'idem')" \
    "$(jf_maybe_bool trimScheduled '' NOT_COLLECTED 'exigerait de lire /etc/periodic.conf, non analysé')"
}

# --- Réseau -----------------------------------------------------------------

collect_network() {
  have ifconfig || {
    feature 'network' 'NOT_AVAILABLE' 'ifconfig absent'
    return 0
  }
  feature 'network' 'AVAILABLE'

  _tmp="${TMPDIR:-/tmp}/sysaudit-bsd-if.$$"
  ifconfig -a 2>/dev/null | awk '
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
  ' >"$_tmp"

  _rows=''
  while IFS="$(printf '\t')" read -r _name _state _mac _ip; do
    [ -n "$_name" ] || continue
    # `-` est le marqueur de champ vide pose par awk ci-dessus, jamais une
    # valeur relevee : aucune adresse ni aucun etat ne vaut un tiret seul.
    [ "$_state" = '-' ] && _state=''
    [ "$_mac" = '-' ] && _mac=''
    [ "$_ip" = '-' ] && _ip=''
    if [ -n "$_rows" ]; then _rows="$_rows,"; fi
    _ipv4='[]'
    [ -n "$_ip" ] && _ipv4="[$(json_object "$(jf_str address "$_ip")")]"
    _rows="$_rows$(json_object \
      "$(jf_str name "$_name")" \
      "$(jf_maybe_str manufacturer '' NOT_COLLECTED 'non exposé par ifconfig')" \
      "$(jf_maybe_str model '' NOT_COLLECTED 'non exposé par ifconfig')" \
      "$(jf_maybe_str mac "$_mac" NOT_AVAILABLE 'aucune adresse ether sur cette interface')" \
      "$(jf_maybe_str type '' NOT_COLLECTED 'le type se déduirait du préfixe du nom (em, igb, lagg), ce qui serait une convention supposée')" \
      "$(jf_str status "$_state")" \
      "$(jf_maybe_num speedMbps '' NOT_COLLECTED 'le débit négocié se lit dans la ligne « media », non analysée')" \
      "$(jf_maybe_str duplex '' NOT_COLLECTED 'idem')" \
      "$(jf_maybe_num mtu '' NOT_COLLECTED 'non extrait par ce scanner expérimental')" \
      "$(jf_maybe_str driver '' NOT_COLLECTED 'le pilote est le préfixe du nom d’interface ; l’en extraire serait une convention supposée')" \
      "$(jf_maybe_bool dhcp '' NOT_COLLECTED 'exigerait de lire /var/db/dhclient.leases.*')" \
      "$(jf_raw ipv4 "$_ipv4")" \
      "$(jf_raw ipv6 '[]')" \
      "$(jf_maybe_str gateway '' NOT_COLLECTED 'exigerait netstat -rn, non analysé')")"
  done <"$_tmp"
  rm -f "$_tmp"

  [ -n "$_rows" ] || return 0
  json_object \
    "$(jf_raw interfaces "[$_rows]")" \
    "$(jf_raw dnsServers '[]')" \
    "$(jf_raw searchDomains '[]')" \
    "$(jf_raw listeningPorts '[]')"
}

# --- Sécurité : le pare-feu est la fonction de la machine -------------------

collect_security() {
  # `pfctl -s info` exige root. Sans élévation il échoue, et l'échec doit se
  # lire `PERMISSION_DENIED` — pas `NOT_AVAILABLE` : sur une appliance, dire
  # « pare-feu non disponible » alors qu'il tourne serait le pire contresens
  # que ce rapport puisse commettre.
  _state=''
  _rules=''
  # La raison portée par le champ lui-même, et pas seulement par
  # `capabilities.features` : c'est le champ que quelqu'un lira.
  _reason='NOT_AVAILABLE'
  _detail='pfctl absent — inattendu sur un FreeBSD, impossible sur une appliance'
  if have pfctl; then
    if [ "$(id -u 2>/dev/null || printf 1)" != '0' ]; then
      _reason='PERMISSION_DENIED'
      _detail='pfctl exige les droits root ; l’état de pf n’a pas pu être lu'
      feature 'security.firewall' 'PERMISSION_DENIED' "$_detail"
    else
      _info=$(pfctl -s info 2>/dev/null)
      case "$_info" in
        *'Status: Enabled'*) _state='ENABLED' ;;
        *'Status: Disabled'*) _state='DISABLED' ;;
      esac
      _rules=$(pfctl -s rules 2>/dev/null | grep -c . 2>/dev/null)
      if [ -n "$_state" ]; then
        feature 'security.firewall' 'AVAILABLE'
      else
        _detail='pfctl a répondu sans annoncer d’état'
        feature 'security.firewall' 'NOT_AVAILABLE' "$_detail"
      fi
    fi
  else
    feature 'security.firewall' 'NOT_AVAILABLE' "$_detail"
  fi

  if [ "$FLAVOR" != 'FreeBSD' ]; then
    note "Cette machine est une appliance $FLAVOR : le pare-feu n’y est pas une protection parmi d’autres, c’est sa fonction. Un pf désactivé y est un incident majeur, pas un durcissement manquant."
  fi

  json_object \
    "$(jf_maybe_str engine 'pf' NOT_AVAILABLE '')" \
    "$(jf_maybe_str state "$_state" "$_reason" "$_detail")" \
    "$(jf_maybe_str defaultInputPolicy '' NOT_COLLECTED 'la politique par défaut se lit dans le jeu de règles, non analysé — une règle peut révéler la topologie')" \
    "$(jf_maybe_num ruleCount "$_rules" "$_reason" "$_detail")"
}

# --- Historique -------------------------------------------------------------

collect_stability() {
  _boot=$(boot_epoch)
  _uptime=$(uptime_seconds)

  # `dmesg` ne couvre que le **démarrage courant**, et son tampon est circulaire :
  # sur une machine chargée, les lignes du démarrage ont pu être écrasées.
  # C'est pourquoi la fenêtre annoncée est l'uptime, jamais une durée choisie.
  _dmesg_errors=''
  if have dmesg; then
    _dmesg_errors=$(dmesg 2>/dev/null | grep -c -i -E 'error|fail|panic' 2>/dev/null)
    feature 'stability' 'AVAILABLE'
  else
    feature 'stability' 'NOT_AVAILABLE' 'dmesg absent'
  fi

  _window=''
  [ -n "$_uptime" ] && _window=$((_uptime * 1000))

  json_object \
    "$(jf_maybe_num uptimeSeconds "$_uptime" NOT_AVAILABLE 'kern.boottime illisible')" \
    "$(jf_maybe_str bootedAt "$(epoch_to_iso "$_boot")" NOT_AVAILABLE 'kern.boottime illisible')" \
    "$(jf_raw hardwareErrors "$(json_object \
      "$(jf_maybe_num count "$_dmesg_errors" NOT_AVAILABLE 'dmesg absent')" \
      "$(jf_maybe_num observationWindowMs "$_window" NOT_AVAILABLE 'sans uptime, la fenêtre couverte par dmesg est inconnue')" \
      "$(jf_raw lastAt "$(j_unknown NOT_COLLECTED 'dmesg n’horodate pas ses lignes par défaut sur FreeBSD')")" \
      "$(jf_maybe_str source 'dmesg' NOT_AVAILABLE '')")")" \
    "$(jf_raw failedUnits '[]')" \
    "$(jf_raw coredumps '[]')" \
    "$(jf_raw kernelTainted "$(j_unknown NOT_APPLICABLE 'notion propre au noyau Linux')")" \
    "$(jf_raw meta "$(json_object \
      "$(jf_str source 'sysctl, dmesg')" \
      "$(jf_str method 'commande shell')" \
      "$(jf_str collectedAt "$(now_iso)")" \
      "$(if [ -n "$_window" ]; then jf_raw observationWindowMs "$_window"; fi)")")"
}

collect_boot() {
  feature 'boot' 'NOT_AVAILABLE' 'FreeBSD ne publie aucune durée de démarrage décomposée'

  json_object \
    "$(jf_raw phases '[]')" \
    "$(jf_raw totalMs "$(j_unknown NOT_AVAILABLE 'FreeBSD ne publie pas de durée de démarrage')")" \
    "$(jf_maybe_str measuredAt "$(now_iso)" NOT_AVAILABLE '')" \
    "$(jf_raw slowestItems '[]')" \
    "$(jf_raw failedAtBoot '[]')" \
    "$(jf_maybe_str firmwareMode "$(if [ -d /dev/efi ] || [ -n "$(sysctl_value machdep.bootmethod)" ]; then
      case "$(sysctl_value machdep.bootmethod)" in
        UEFI) printf 'UEFI' ;;
        BIOS) printf 'LEGACY_BIOS' ;;
      esac
    fi)" NOT_AVAILABLE 'machdep.bootmethod absent')" \
    "$(jf_raw fastStartupEnabled "$(j_unknown NOT_APPLICABLE 'notion propre à Windows')")"
}

collect_events() {
  # `dmesg` est lu pour son **décompte** dans `stability`, pas normalisé en
  # incidents ici : la normalisation exige de classer chaque ligne, et classer
  # sans avoir jamais vu une sortie réelle produirait un classement qui range
  # tout en OTHER. Un OTHER généralisé pèserait sur le mauvais score.
  feature 'events' 'NOT_COLLECTED' 'les lignes de dmesg ne sont pas normalisées : les classer sans avoir observé de sortie réelle rangerait tout en OTHER'
  skipped 'events.entries'

  _uptime=$(uptime_seconds)
  _window=''
  [ -n "$_uptime" ] && _window=$((_uptime * 1000))

  json_object \
    "$(jf_raw window "$(json_object \
      "$(jf_raw requestedMs "$(j_unknown NOT_COLLECTED 'aucune fenêtre demandée : le journal n’est pas normalisé')")" \
      "$(jf_maybe_num coveredMs "$_window" NOT_AVAILABLE 'sans uptime, la fenêtre couverte par dmesg est inconnue')" \
      "$(jf_raw since "$(j_unknown NOT_COLLECTED '')")" \
      "$(jf_raw until "$(j_unknown NOT_COLLECTED '')")" \
      "$(jf_raw persistent false)")")" \
    "$(jf_raw examined "$(j_unknown NOT_COLLECTED '')")" \
    "$(jf_raw truncated "$(j_unknown NOT_COLLECTED '')")" \
    "$(jf_raw entries '[]')"
}

# --- Assemblage -------------------------------------------------------------

log_info "SysAudit BSD $SCANNER_VERSION — EXPERIMENTAL, jamais exécuté sur une machine réelle"
log_step "système détecté : $FLAVOR"
SYSTEM=$(collect_system)
OS=$(collect_os)
log_step 'processeur et mémoire'
CPUS=$(collect_cpus)
MEMORY=$(collect_memory)
log_step 'stockage'
STORAGE=$(collect_storage)
log_step 'réseau'
NETWORK=$(collect_network)
log_step 'pare-feu'
FIREWALL=$(collect_security)
log_step 'historique'
STABILITY=$(collect_stability)
BOOT=$(collect_boot)
EVENTS=$(collect_events)

PRIVILEGED=false
[ "$(id -u 2>/dev/null || printf 1)" = '0' ] && PRIVILEGED=true

CAPABILITIES=$(json_object \
  "$(jf_str platform 'freebsd')" \
  "$(jf_str distribution "$FLAVOR")" \
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
    "$(jf_str scannerKind 'freebsd')" \
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
  "$(jf_raw security "$(json_object \
    "$(jf_raw firewall "$FIREWALL")" \
    "$(jf_raw accounts '[]')" \
    "$(jf_raw obsoleteProtocols '[]')")")" \
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
TARGET="$OUTPUT_DIR/sysaudit-bsd-$(date -u '+%Y%m%d-%H%M%S').json"
printf '%s\n' "$REPORT" >"$TARGET" || die "Écriture impossible : $TARGET"
log_info "Rapport écrit : $TARGET"
log_warn 'Scanner EXPERIMENTAL : ce rapport n’a valeur ni de validation ni de mesure de référence.'
