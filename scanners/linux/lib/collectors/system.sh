#!/usr/bin/env bash
# Identité de la machine et système d'exploitation.

# Raison à donner quand une information SMBIOS manque : distinguer « outil
# absent » de « privilèges insuffisants » permet à l'utilisateur de savoir quoi
# faire pour obtenir un rapport complet.
dmi_reason() {
  if [ "$(capability_tool dmidecode)" != 'true' ]; then
    printf 'NOT_AVAILABLE'
  elif [ "$CAP_PRIVILEGED" != 'true' ]; then
    printf 'PERMISSION_DENIED'
  else
    printf 'UNKNOWN'
  fi
}

dmi_detail() {
  if [ "$(capability_tool dmidecode)" != 'true' ]; then
    printf 'dmidecode absent'
  elif [ "$CAP_PRIVILEGED" != 'true' ]; then
    printf 'lecture SMBIOS réservée à root'
  fi
}

# Le même embranchement, rendu en motif lisible par la plateforme.
#
# Il suit `dmi_detail` ligne pour ligne, et c'est voulu : la phrase lue par un
# humain et le motif lu par une machine doivent dire la même chose. Les écrire
# au même endroit est ce qui empêche l'un de démentir l'autre.
dmi_reason() {
  if [ "$(capability_tool dmidecode)" != 'true' ]; then
    printf 'NOT_AVAILABLE'
  elif [ "$CAP_PRIVILEGED" != 'true' ]; then
    printf 'PERMISSION_DENIED'
  fi
}

# Lit une valeur DMI via /sys (accessible sans privilège pour certains champs)
# puis via dmidecode en repli.
dmi_value() {
  local sys_path=$1 dmi_string=$2 value=''

  if [ -r "$sys_path" ]; then
    value=$(clean_dmi_value "$(cat "$sys_path" 2>/dev/null)")
  fi

  if [ -z "$value" ] && [ "$(capability_tool dmidecode)" = 'true' ] && [ "$CAP_PRIVILEGED" = 'true' ]; then
    value=$(clean_dmi_value "$(run_cmd dmidecode -s "$dmi_string" | head -n 1)")
  fi

  printf '%s' "$value"
}

collect_system() {
  log_step 'Système'

  local hostname='' manufacturer='' model='' chassis='' uuid='' serial='' uptime='' timezone='' localtime=''
  local fqdn='' domain='' asset=''
  hostname=$(hostname 2>/dev/null || cat /proc/sys/kernel/hostname 2>/dev/null || printf '')
  fqdn=$(detect_fqdn)
  domain=$(detect_domain "$fqdn")
  manufacturer=$(dmi_value /sys/class/dmi/id/sys_vendor system-manufacturer)
  model=$(dmi_value /sys/class/dmi/id/product_name system-product-name)
  uuid=$(dmi_value /sys/class/dmi/id/product_uuid system-uuid)
  serial=$(dmi_value /sys/class/dmi/id/product_serial system-serial-number)
  asset=$(dmi_value /sys/class/dmi/id/chassis_asset_tag chassis-asset-tag)
  chassis=$(detect_chassis)
  uptime=$(awk '{printf "%d", $1}' /proc/uptime 2>/dev/null || printf '')
  timezone=$(detect_timezone)
  localtime=$(date +%Y-%m-%dT%H:%M:%S%:z 2>/dev/null || printf '')

  [ -z "$manufacturer" ] && record_issue 'system' 'warning' \
    "Identité matérielle non collectée ($(dmi_detail))." 'dmidecode' "$(dmi_reason)"

  json_object \
    "$(jf_maybe_str hostname "$(anon hostname "$hostname")")" \
    "$(jf_maybe_str fqdn "$(anon hostname "$fqdn")" NOT_AVAILABLE 'le résolveur local ne rend aucun nom qualifié')" \
    "$(jf_maybe_str domain "$(anon domain "$domain")" NOT_AVAILABLE 'machine sans domaine de rattachement')" \
    "$(jf_raw workgroup "$(j_unknown UNSUPPORTED 'notion propre à Windows')")" \
    "$(jf_maybe_str manufacturer "$manufacturer" "$(dmi_reason)" "$(dmi_detail)")" \
    "$(jf_maybe_str model "$model" "$(dmi_reason)" "$(dmi_detail)")" \
    "$(jf_maybe_str chassisType "$chassis" "$(dmi_reason)" "$(dmi_detail)")" \
    "$(jf_maybe_str uuid "$(anon uuid "$uuid")" "$(dmi_reason)" "$(dmi_detail)")" \
    "$(jf_maybe_str serialNumber "$(anon serialNumber "$serial")" "$(dmi_reason)" "$(dmi_detail)")" \
    "$(jf_maybe_str assetTag "$(anon serialNumber "$asset")" "$(dmi_reason)" "$(dmi_detail)")" \
    "$(jf_raw machineGuid "$(j_unknown UNSUPPORTED 'notion propre à Windows')")" \
    "$(jf_raw machineSid "$(j_unknown UNSUPPORTED 'notion propre à Windows')")" \
    "$(jf_maybe_str architecture "$CAP_ARCHITECTURE")" \
    "$(jf_maybe_num uptimeSeconds "$uptime")" \
    "$(jf_maybe_str timezone "$timezone")" \
    "$(jf_maybe_str localTime "$localtime")"
}

# Nom pleinement qualifié.
#
# `hostname -f` interroge le résolveur, ce qui peut durer si le DNS ne répond
# pas : l'appel passe par `run_cmd`, seul chemin du scanner qui porte un délai
# de garde. Un résultat sans point n'est pas un FQDN — c'est le nom court que la
# commande rend à défaut de mieux, et le republier ici en ferait un domaine de
# rattachement qui n'existe pas.
detect_fqdn() {
  local value=''
  value=$(run_cmd hostname -f | head -n1 | trim) || value=''
  case "$value" in
    *.*) ;;
    *) return 0 ;;
  esac
  # `localhost.localdomain` est le nom de repli d'une machine sans identité
  # réseau, pas son nom qualifié.
  case "$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')" in
    localhost | localhost.localdomain) return 0 ;;
  esac
  printf '%s' "$value"
}

# Domaine de rattachement. Lu du résolveur, ou à défaut retiré du nom qualifié
# qu'il vient de rendre : les deux viennent de la même source, il n'y a rien
# d'inventé à prendre la seconde quand la première se tait.
detect_domain() {
  local fqdn=${1-} value=''
  value=$(run_cmd hostname -d | head -n1 | trim) || value=''
  if [ -z "$value" ] && [ -n "$fqdn" ]; then
    value=${fqdn#*.}
    [ "$value" = "$fqdn" ] && value=''
  fi
  case "$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')" in
    localdomain | '(none)') value='' ;;
  esac
  printf '%s' "$value"
}

# Le type de châssis SMBIOS est un code numérique ; seuls les codes sans
# ambiguïté sont traduits, les autres restant inconnus plutôt que devinés.
detect_chassis() {
  local code=''
  code=$(read_value /sys/class/dmi/id/chassis_type 2>/dev/null || printf '')
  case "$code" in
    3 | 4 | 6 | 7) printf 'desktop' ;;
    8 | 9 | 10 | 14) printf 'laptop' ;;
    11 | 12) printf 'handheld' ;;
    13) printf 'all-in-one' ;;
    17 | 23 | 28) printf 'server' ;;
    30 | 31 | 32) printf 'tablet' ;;
    35) printf 'mini-pc' ;;
    *) printf '' ;;
  esac
}

detect_timezone() {
  if has_cmd timedatectl; then
    run_cmd timedatectl show -p Timezone --value && return 0
  fi
  if [ -L /etc/localtime ]; then
    readlink -f /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||'
    return 0
  fi
  read_value /etc/timezone 2>/dev/null || printf ''
}

collect_os() {
  log_step "Système d'exploitation"

  local name='' version='' distribution='' kernel='' install_date='' locale='' timezone=''
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    name=$(. /etc/os-release 2>/dev/null && printf '%s' "${NAME-}")
    # shellcheck disable=SC1091
    version=$(. /etc/os-release 2>/dev/null && printf '%s' "${VERSION_ID:-${VERSION-}}")
    # shellcheck disable=SC1091
    distribution=$(. /etc/os-release 2>/dev/null && printf '%s' "${ID-}")
  fi

  kernel=$(uname -r 2>/dev/null || printf '')
  install_date=$(detect_install_date)
  locale=${LANG-}
  timezone=$(detect_timezone)

  json_object \
    "$(jf_str family linux)" \
    "$(jf_maybe_str name "$name")" \
    "$(jf_raw edition "$(j_unknown UNSUPPORTED 'notion sans objet sous Linux')")" \
    "$(jf_maybe_str distribution "$distribution")" \
    "$(jf_maybe_str version "$version")" \
    "$(jf_raw build "$(j_unknown UNSUPPORTED 'notion sans objet sous Linux')")" \
    "$(jf_maybe_str kernel "$kernel")" \
    "$(jf_maybe_str architecture "$CAP_ARCHITECTURE")" \
    "$(jf_maybe_str installDate "$install_date" NOT_AVAILABLE 'date d’installation non déterminable de façon fiable')" \
    "$(jf_maybe_str locale "$locale")" \
    "$(jf_maybe_str timezone "$timezone")"
}

# La date d'installation n'est pas exposée directement par Linux. Celle du
# système de fichiers racine en est la meilleure approximation disponible ;
# elle n'est retenue que si `tune2fs` la fournit explicitement, sinon le champ
# reste inconnu plutôt qu'estimé.
detect_install_date() {
  local root_dev='' created=''
  has_cmd tune2fs || return 0
  [ "$CAP_PRIVILEGED" = 'true' ] || return 0

  root_dev=$(findmnt -no SOURCE / 2>/dev/null) || return 0
  [ -n "$root_dev" ] || return 0

  created=$(run_cmd tune2fs -l "$root_dev" | sed -nE 's/^Filesystem created:[[:space:]]+(.*)$/\1/p')
  [ -n "$created" ] || return 0

  date -d "$created" +%Y-%m-%d 2>/dev/null || printf ''
}
