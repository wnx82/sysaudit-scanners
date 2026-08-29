#!/usr/bin/env bash
# Carte mère, BIOS, CPU, mémoire, GPU et capteurs.

# Racine sysfs. Constante en production ; les tests la déplacent vers un arbre
# de fixtures, faute de quoi la collecte des capteurs ne serait vérifiable que
# sur la machine qui a le bon matériel — c'est-à-dire jamais en CI.
: "${SYSFS_ROOT:=/sys}"

collect_motherboard() {
  log_step 'Carte mère'

  local manufacturer='' model='' revision='' serial='' slots=''
  manufacturer=$(dmi_value /sys/class/dmi/id/board_vendor baseboard-manufacturer)
  model=$(dmi_value /sys/class/dmi/id/board_name baseboard-product-name)
  revision=$(dmi_value /sys/class/dmi/id/board_version baseboard-version)
  serial=$(dmi_value /sys/class/dmi/id/board_serial baseboard-serial-number)
  slots=$(count_memory_slots)

  json_object \
    "$(jf_maybe_str manufacturer "$manufacturer" "$(dmi_reason)" "$(dmi_detail)")" \
    "$(jf_maybe_str model "$model" "$(dmi_reason)" "$(dmi_detail)")" \
    "$(jf_maybe_str revision "$revision" "$(dmi_reason)" "$(dmi_detail)")" \
    "$(jf_maybe_str serialNumber "$(anon serialNumber "$serial")" "$(dmi_reason)" "$(dmi_detail)")" \
    "$(jf_raw chipset "$(j_unknown NOT_AVAILABLE 'le chipset n’est pas exposé de façon fiable sous Linux')")" \
    "$(jf_maybe_str socket "$(detect_cpu_socket)" "$(dmi_reason)" "$(dmi_detail)")" \
    "$(jf_maybe_num memorySlots "$slots" "$(dmi_reason)" "$(dmi_detail)")"
}

count_memory_slots() {
  [ "$(capability_tool dmidecode)" = 'true' ] || return 0
  [ "$CAP_PRIVILEGED" = 'true' ] || return 0
  run_cmd dmidecode -t 17 | grep -c '^Memory Device$' || printf ''
}

detect_cpu_socket() {
  [ "$(capability_tool dmidecode)" = 'true' ] || return 0
  [ "$CAP_PRIVILEGED" = 'true' ] || return 0
  clean_dmi_value "$(run_cmd dmidecode -t 4 | sed -nE 's/^[[:space:]]*Upgrade:[[:space:]]+(.*)$/\1/p' | head -n1)"
}

collect_bios() {
  log_step 'BIOS / UEFI'

  local vendor='' version='' release_date='' mode='' secure_boot='' smbios=''
  vendor=$(dmi_value /sys/class/dmi/id/bios_vendor bios-vendor)
  version=$(dmi_value /sys/class/dmi/id/bios_version bios-version)
  release_date=$(to_iso_date "$(dmi_value /sys/class/dmi/id/bios_date bios-release-date)")

  if [ -d /sys/firmware/efi ]; then mode='UEFI'; else mode='LEGACY'; fi
  secure_boot=$(detect_secure_boot)

  if [ "$(capability_tool dmidecode)" = 'true' ] && [ "$CAP_PRIVILEGED" = 'true' ]; then
    smbios=$(run_cmd dmidecode -t 0 | sed -nE 's/^SMBIOS ([0-9.]+) present.*$/\1/p' | head -n1)
    [ -z "$smbios" ] && smbios=$(run_cmd dmidecode | sed -nE 's/^SMBIOS ([0-9.]+) present.*$/\1/p' | head -n1)
  fi

  json_object \
    "$(jf_maybe_str manufacturer "$vendor" "$(dmi_reason)" "$(dmi_detail)")" \
    "$(jf_maybe_str version "$version" "$(dmi_reason)" "$(dmi_detail)")" \
    "$(jf_maybe_str releaseDate "$release_date" "$(dmi_reason)" "$(dmi_detail)")" \
    "$(jf_maybe_str mode "$mode")" \
    "$(jf_maybe_str secureBoot "$secure_boot" NOT_AVAILABLE 'état Secure Boot non lisible')" \
    "$(jf_maybe_str smbiosVersion "$smbios" "$(dmi_reason)" "$(dmi_detail)")"
}

# L'état Secure Boot est exposé par une variable EFI dont le dernier octet vaut
# 1 (activé) ou 0 (désactivé). Sans EFI, la notion n'existe pas.
detect_secure_boot() {
  [ -d /sys/firmware/efi ] || { printf 'UNSUPPORTED'; return 0; }

  local var=''
  var=$(find /sys/firmware/efi/efivars -maxdepth 1 -name 'SecureBoot-*' 2>/dev/null | head -n1)
  [ -n "$var" ] && [ -r "$var" ] || return 0

  local last=''
  last=$(od -An -t u1 "$var" 2>/dev/null | tr -s ' ' '\n' | grep -v '^$' | tail -n1)
  case "$last" in
    1) printf 'ENABLED' ;;
    0) printf 'DISABLED' ;;
    *) printf '' ;;
  esac
}

collect_cpus() {
  log_step 'Processeur'

  local model='' vendor='' cores='' threads='' sockets='' base_mhz='' max_mhz='' cur_mhz='' flags=''
  local l1='' l2='' l3='' virt_supported='' virt_tech='' temp='' usage=''

  if [ "$(capability_tool lscpu)" = 'true' ]; then
    local lscpu_out=''
    lscpu_out=$(LC_ALL=C run_cmd lscpu)
    model=$(printf '%s' "$lscpu_out" | sed -nE 's/^Model name:[[:space:]]+(.*)$/\1/p' | head -n1)
    vendor=$(printf '%s' "$lscpu_out" | sed -nE 's/^Vendor ID:[[:space:]]+(.*)$/\1/p' | head -n1)
    sockets=$(printf '%s' "$lscpu_out" | sed -nE 's/^Socket\(s\):[[:space:]]+([0-9]+)$/\1/p' | head -n1)
    local cores_per_socket=''
    cores_per_socket=$(printf '%s' "$lscpu_out" | sed -nE 's/^Core\(s\) per socket:[[:space:]]+([0-9]+)$/\1/p' | head -n1)
    threads=$(printf '%s' "$lscpu_out" | sed -nE 's/^CPU\(s\):[[:space:]]+([0-9]+)$/\1/p' | head -n1)
    max_mhz=$(printf '%s' "$lscpu_out" | sed -nE 's/^CPU max MHz:[[:space:]]+([0-9.]+)$/\1/p' | head -n1)
    cur_mhz=$(printf '%s' "$lscpu_out" | sed -nE 's/^CPU MHz:[[:space:]]+([0-9.]+)$/\1/p' | head -n1)
    flags=$(printf '%s' "$lscpu_out" | sed -nE 's/^Flags:[[:space:]]+(.*)$/\1/p' | head -n1)
    l1=$(to_bytes "$(printf '%s' "$lscpu_out" | sed -nE 's/^L1d cache:[[:space:]]+([0-9.]+ ?[KMG]?i?B).*$/\1/p' | head -n1)")
    l2=$(to_bytes "$(printf '%s' "$lscpu_out" | sed -nE 's/^L2 cache:[[:space:]]+([0-9.]+ ?[KMG]?i?B).*$/\1/p' | head -n1)")
    l3=$(to_bytes "$(printf '%s' "$lscpu_out" | sed -nE 's/^L3 cache:[[:space:]]+([0-9.]+ ?[KMG]?i?B).*$/\1/p' | head -n1)")

    if [ -n "$sockets" ] && [ -n "$cores_per_socket" ]; then
      cores=$((sockets * cores_per_socket))
    fi
  fi

  # Repli sur /proc/cpuinfo, toujours présent même sans util-linux.
  if [ -z "$model" ] && [ -r /proc/cpuinfo ]; then
    model=$(sed -nE 's/^model name[[:space:]]*:[[:space:]]*(.*)$/\1/p' /proc/cpuinfo | head -n1)
    vendor=$(sed -nE 's/^vendor_id[[:space:]]*:[[:space:]]*(.*)$/\1/p' /proc/cpuinfo | head -n1)
    threads=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || printf '')
    flags=$(sed -nE 's/^flags[[:space:]]*:[[:space:]]*(.*)$/\1/p' /proc/cpuinfo | head -n1)
  fi

  base_mhz=$(read_value /sys/devices/system/cpu/cpu0/cpufreq/base_frequency 2>/dev/null || printf '')
  [ -n "$base_mhz" ] && base_mhz=$((base_mhz / 1000))

  # La virtualisation matérielle se lit dans les drapeaux CPU ; son activation
  # dans le BIOS n'est pas lisible directement, elle reste donc inconnue.
  virt_supported='false'
  case " $flags " in
    *' vmx '*) virt_supported='true'; virt_tech='Intel VT-x' ;;
    *' svm '*) virt_supported='true'; virt_tech='AMD-V' ;;
  esac

  # La température se lit dans sysfs : elle est gratuite et reste collectée à
  # tous les niveaux. L'occupation, elle, se mesure sur un intervalle — le
  # résumé ne fait pas patienter l'utilisateur pour une valeur instantanée.
  temp=$(read_cpu_temperature)
  local socket_json=''
  if depth_at_least cpus standard; then
    usage=$(read_cpu_usage)
    socket_json=$(jf_maybe_str socket "$(detect_cpu_socket)" "$(dmi_reason)" "$(dmi_detail)")
  else
    record_level_skip 'cpus.usagePercent' standard
    record_level_skip 'cpus.socket' standard
    socket_json=$(jf_raw socket "$(level_unknown standard)")
  fi

  local instruction_sets='' flag=''
  for flag in sse4_2 avx avx2 avx512f aes sha_ni rdrand; do
    case " $flags " in
      *" $flag "*) instruction_sets=$(json_join "$instruction_sets" "$(j_str "$flag")") ;;
    esac
  done

  local virt_json=''
  if [ "$virt_supported" = 'true' ]; then
    virt_json=$(json_object \
      "$(jf_raw supported true)" \
      "$(jf_raw enabled "$(j_unknown UNKNOWN 'activation BIOS non lisible depuis le système')")" \
      "$(jf_str technology "$virt_tech")")
  else
    virt_json=$(json_object \
      "$(jf_raw supported false)" \
      "$(jf_raw enabled false)" \
      "$(jf_raw technology "$(j_unknown UNSUPPORTED)")")
  fi

  json_array "$(json_object \
    "$(jf_maybe_str manufacturer "$vendor")" \
    "$(jf_maybe_str model "$model")" \
    "$(jf_raw family "$(j_unknown NOT_AVAILABLE 'famille commerciale non exposée par le système')")" \
    "$(jf_raw generation "$(j_unknown UNKNOWN 'génération commerciale non déterminable de façon fiable')")" \
    "$socket_json" \
    "$(jf_maybe_num physicalCores "$cores")" \
    "$(jf_maybe_num logicalCores "$threads")" \
    "$(jf_maybe_num baseFrequencyMhz "$base_mhz" NOT_AVAILABLE 'fréquence de base non exposée par cpufreq')" \
    "$(jf_maybe_num maxFrequencyMhz "${max_mhz%%.*}")" \
    "$(jf_maybe_num currentFrequencyMhz "${cur_mhz%%.*}")" \
    "$(jf_raw cacheBytes "$(json_object \
      "$(jf_maybe_num l1 "$l1" NOT_AVAILABLE)" \
      "$(jf_maybe_num l2 "$l2" NOT_AVAILABLE)" \
      "$(jf_maybe_num l3 "$l3" NOT_AVAILABLE)")")" \
    "$(jf_raw instructionSets "[$instruction_sets]")" \
    "$(jf_raw virtualization "$virt_json")" \
    "$(jf_maybe_num temperatureCelsius "$temp" NOT_AVAILABLE 'aucun capteur thermique CPU lisible')" \
    "$(if depth_at_least cpus standard; then
      jf_maybe_num usagePercent "$usage"
    else
      jf_raw usagePercent "$(level_unknown standard)"
    fi)")"
}

# Température du processeur.
#
# Deux sources, dans cet ordre. Les zones thermiques ACPI d'abord, parce
# qu'elles portent un type explicite. Puis hwmon — et ce second passage n'est
# pas un luxe : sur les Ryzen, `k10temp` est un chip hwmon **sans** zone
# thermique associée. S'arrêter aux zones revenait à déclarer « aucun capteur
# thermique CPU lisible » sur toute une génération de processeurs AMD qui en
# exposent un.
read_cpu_temperature() {
  local zone='' type='' temp=''
  for zone in "$SYSFS_ROOT"/class/thermal/thermal_zone*; do
    [ -r "$zone/type" ] || continue
    type=$(cat "$zone/type" 2>/dev/null)
    case "$type" in
      *x86_pkg_temp* | *cpu* | *CPU* | *k10temp* | *coretemp*)
        temp=$(cat "$zone/temp" 2>/dev/null) || continue
        [[ $temp =~ ^-?[0-9]+$ ]] || continue
        millicelsius_to_celsius "$temp" && return 0
        ;;
    esac
  done

  local chip='' name=''
  for chip in "$SYSFS_ROOT"/class/hwmon/hwmon*; do
    [ -r "$chip/name" ] || continue
    name=$(cat "$chip/name" 2>/dev/null)
    case "$name" in
      k10temp | coretemp | zenpower | cpu_thermal)
        # `temp1_input` est le paquet sur ces trois pilotes. Les cœurs
        # individuels suivent en temp2, temp3… et n'ont pas leur place ici :
        # c'est une température de processeur, pas une liste.
        temp=$(cat "$chip/temp1_input" 2>/dev/null) || continue
        [[ $temp =~ ^-?[0-9]+$ ]] || continue
        millicelsius_to_celsius "$temp" && return 0
        ;;
    esac
  done
  return 0
}

# Convertit une lecture sysfs en degrés, ou échoue si elle est hors du domaine
# physique. `LC_ALL=C` n'est pas décoratif : une implémentation d'awk qui
# respecte `LC_NUMERIC` produirait « 45,0 », c'est-à-dire un JSON invalide.
millicelsius_to_celsius() {
  local millicelsius=$1 celsius=''
  celsius=$(LC_ALL=C awk -v t="$millicelsius" 'BEGIN { printf "%.1f", t / 1000 }')
  LC_ALL=C awk -v c="$celsius" 'BEGIN { exit !(c > -100 && c < 200) }' || return 1
  printf '%s' "$celsius"
}

# Utilisation CPU instantanée, mesurée sur un court intervalle depuis /proc/stat.
read_cpu_usage() {
  [ -r /proc/stat ] || return 0
  local a='' b=''
  a=$(awk '/^cpu / { print $2+$3+$4+$5+$6+$7+$8, $5 }' /proc/stat 2>/dev/null) || return 0
  sleep 0.3
  b=$(awk '/^cpu / { print $2+$3+$4+$5+$6+$7+$8, $5 }' /proc/stat 2>/dev/null) || return 0
  awk -v a="$a" -v b="$b" 'BEGIN {
    split(a, x, " "); split(b, y, " ");
    dt = y[1] - x[1]; di = y[2] - x[2];
    if (dt <= 0) exit;
    printf "%.1f", (1 - di / dt) * 100
  }'
}

# Motif d'absence des données mémoire issues du SMBIOS.
#
# Deux causes bien distinctes se ressemblent dans le rapport : `dmidecode` peut
# manquer, ou le niveau choisi peut ne pas prévoir cette lecture. Les confondre
# ferait chercher un paquet manquant là où il suffit de relancer au niveau
# Normale.
memory_dmi_reason() {
  if depth_at_least memory standard; then dmi_reason; else printf 'NOT_COLLECTED'; fi
}

memory_dmi_detail() {
  if depth_at_least memory standard; then
    dmi_detail
  else
    printf 'collecté au niveau Normale'
  fi
}

collect_memory() {
  log_step 'Mémoire'

  local total='' available='' swap_total='' swap_free=''
  if [ -r /proc/meminfo ]; then
    total=$(awk '/^MemTotal:/ { print $2 * 1024 }' /proc/meminfo)
    available=$(awk '/^MemAvailable:/ { print $2 * 1024 }' /proc/meminfo)
    swap_total=$(awk '/^SwapTotal:/ { print $2 * 1024 }' /proc/meminfo)
    swap_free=$(awk '/^SwapFree:/ { print $2 * 1024 }' /proc/meminfo)
  fi

  local swap_used=''
  if [ -n "$swap_total" ] && [ -n "$swap_free" ]; then
    swap_used=$((swap_total - swap_free))
  fi

  local modules='' slots_total='' slots_used='' max_capacity=''
  # Le détail des modules exige `dmidecode` et un enregistrement SMBIOS par
  # barrette : c'est la partie coûteuse de cette collecte, et le résumé s'en
  # passe. Les totaux, eux, viennent de /proc/meminfo à tous les niveaux.
  if ! depth_at_least memory standard; then
    record_level_skip 'memory.modules' standard
  elif [ "$(capability_tool dmidecode)" = 'true' ] && [ "$CAP_PRIVILEGED" = 'true' ]; then
    modules=$(collect_memory_modules)
    slots_total=$(count_memory_slots)
    slots_used=$(run_cmd dmidecode -t 17 | grep -cE '^[[:space:]]*Size:[[:space:]]+[0-9]' || printf '')
    # La capacité maximale provient du type SMBIOS 16 : c'est une donnée
    # rapportée par la machine, pas une estimation.
    max_capacity=$(to_bytes "$(run_cmd dmidecode -t 16 | sed -nE 's/^[[:space:]]*Maximum Capacity:[[:space:]]+(.*)$/\1/p' | head -n1)")
  else
    record_issue 'memory' 'warning' \
      "Détail des modules mémoire non collecté ($(dmi_detail))." 'dmidecode' "$(dmi_reason)"
  fi

  json_object \
    "$(jf_raw modules "[$modules]")" \
    "$(jf_maybe_num installedBytes "$total")" \
    "$(jf_maybe_num availableBytes "$available")" \
    "$(jf_maybe_num slotsTotal "$slots_total" "$(memory_dmi_reason)" "$(memory_dmi_detail)")" \
    "$(jf_maybe_num slotsUsed "$slots_used" "$(memory_dmi_reason)" "$(memory_dmi_detail)")" \
    "$(jf_maybe_num maxCapacityBytes "$max_capacity" "$(memory_dmi_reason)" "$(memory_dmi_detail)")" \
    "$(jf_maybe_num swapTotalBytes "$swap_total")" \
    "$(jf_maybe_num swapUsedBytes "$swap_used")"
}

# Analyse la sortie `dmidecode -t 17`, un enregistrement par module.
collect_memory_modules() {
  local out='' modules='' record=''
  out=$(LC_ALL=C run_cmd dmidecode -t 17) || return 0

  local line=''
  while IFS= read -r line; do
    if [[ $line == 'Memory Device' ]]; then
      [ -n "$record" ] && modules=$(json_join "$modules" "$(parse_memory_module "$record")")
      record=''
      continue
    fi
    record+="$line"$'\n'
  done <<<"$out"
  [ -n "$record" ] && modules=$(json_join "$modules" "$(parse_memory_module "$record")")

  printf '%s' "$modules"
}

parse_memory_module() {
  local record=$1
  local slot='' size='' manufacturer='' part='' serial='' type='' rated='' configured='' voltage='' form=''
  slot=$(printf '%s' "$record" | sed -nE 's/^[[:space:]]*Locator:[[:space:]]+(.*)$/\1/p' | head -n1)
  size=$(printf '%s' "$record" | sed -nE 's/^[[:space:]]*Size:[[:space:]]+(.*)$/\1/p' | head -n1)
  manufacturer=$(clean_dmi_value "$(printf '%s' "$record" | sed -nE 's/^[[:space:]]*Manufacturer:[[:space:]]+(.*)$/\1/p' | head -n1)")
  part=$(clean_dmi_value "$(printf '%s' "$record" | sed -nE 's/^[[:space:]]*Part Number:[[:space:]]+(.*)$/\1/p' | head -n1)")
  serial=$(clean_dmi_value "$(printf '%s' "$record" | sed -nE 's/^[[:space:]]*Serial Number:[[:space:]]+(.*)$/\1/p' | head -n1)")
  type=$(clean_dmi_value "$(printf '%s' "$record" | sed -nE 's/^[[:space:]]*Type:[[:space:]]+(.*)$/\1/p' | head -n1)")
  rated=$(printf '%s' "$record" | sed -nE 's/^[[:space:]]*Speed:[[:space:]]+([0-9]+).*$/\1/p' | head -n1)
  configured=$(printf '%s' "$record" | sed -nE 's/^[[:space:]]*Configured Memory Speed:[[:space:]]+([0-9]+).*$/\1/p' | head -n1)
  voltage=$(printf '%s' "$record" | sed -nE 's/^[[:space:]]*Configured Voltage:[[:space:]]+([0-9.]+).*$/\1/p' | head -n1)
  form=$(clean_dmi_value "$(printf '%s' "$record" | sed -nE 's/^[[:space:]]*Form Factor:[[:space:]]+(.*)$/\1/p' | head -n1)")

  # Un slot vide est rapporté : c'est une information d'upgrade essentielle.
  local size_bytes=''
  case "$size" in
    'No Module Installed' | 'Not Installed' | '') size_bytes='' ;;
    *) size_bytes=$(to_bytes "$size") ;;
  esac

  local ecc=''
  case "$(printf '%s' "$record" | sed -nE 's/^[[:space:]]*Total Width:[[:space:]]+([0-9]+).*$/\1/p' | head -n1)" in
    72 | 80) ecc='true' ;;
    64 | 32 | 16) ecc='false' ;;
  esac

  json_object \
    "$(jf_maybe_str slot "$slot")" \
    "$(jf_maybe_num sizeBytes "$size_bytes" UNSUPPORTED 'slot vide')" \
    "$(jf_maybe_str manufacturer "$manufacturer")" \
    "$(jf_maybe_str partNumber "$part")" \
    "$(jf_maybe_str serialNumber "$(anon serialNumber "$serial")")" \
    "$(jf_maybe_str type "$type")" \
    "$(jf_maybe_num ratedSpeedMts "$rated")" \
    "$(jf_maybe_num configuredSpeedMts "$configured")" \
    "$(jf_raw performanceProfile "$(json_object \
      "$(jf_raw technology "$(j_unknown UNKNOWN 'profil XMP/EXPO non exposé par SMBIOS')")" \
      "$(jf_raw active "$(j_unknown UNKNOWN 'profil XMP/EXPO non exposé par SMBIOS')")" \
      "$(jf_raw profileName "$(j_unknown NOT_AVAILABLE 'nom de profil non exposé par SMBIOS')")")")" \
    "$(jf_maybe_num voltage "$voltage")" \
    "$(jf_maybe_bool ecc "$ecc")" \
    "$(jf_maybe_str formFactor "$form")"
}

collect_gpus() {
  log_step 'Carte graphique'
  [ "$(capability_tool lspci)" = 'true' ] || {
    record_issue 'gpus' 'warning' 'lspci absent : GPU non inventoriés.' 'lspci' 'NOT_AVAILABLE'
    printf '[]'
    return 0
  }

  # Les sorties d'affichage connectées se lisent connecteur par connecteur dans
  # /sys/class/drm : utile pour un diagnostic d'écran, superflu pour un résumé.
  depth_at_least gpus standard || record_level_skip 'gpus.displays' standard

  local gpus='' line=''
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    gpus=$(json_join "$gpus" "$(parse_gpu_line "$line")")
  done < <(run_cmd lspci -nn | grep -iE 'VGA compatible controller|3D controller|Display controller' || true)

  printf '[%s]' "$gpus"
}

parse_gpu_line() {
  local line=$1 pci_id='' vendor='' model='' driver='' driver_version='' address='' temp=''
  local core_clock='' memory_clock=''

  address=$(printf '%s' "$line" | awk '{print $1}')
  pci_id=$(printf '%s' "$line" | sed -nE 's/.*\[([0-9a-f]{4}):([0-9a-f]{4})\].*$/\1:\2/p' | tail -n1)
  model=$(printf '%s' "$line" | sed -E 's/^[^ ]+ [^:]+: //; s/ \[[0-9a-f]{4}:[0-9a-f]{4}\].*$//')
  vendor=$(printf '%s' "$model" | awk '{print $1}')

  if [ -n "$address" ]; then
    driver=$(run_cmd lspci -k -s "$address" | sed -nE 's/^[[:space:]]*Kernel driver in use:[[:space:]]+(.*)$/\1/p' | head -n1)
  fi

  # Les métriques temps réel exigent l'outil du constructeur ; sans lui elles
  # restent inconnues plutôt qu'estimées.
  if has_cmd nvidia-smi && [ "$driver" = 'nvidia' ]; then
    driver_version=$(run_cmd nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -n1)
    temp=$(run_cmd nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader | head -n1)
    core_clock=$(run_cmd nvidia-smi --query-gpu=clocks.current.graphics \
      --format=csv,noheader,nounits | head -n1 | tr -cd '0-9')
    memory_clock=$(run_cmd nvidia-smi --query-gpu=clocks.current.memory \
      --format=csv,noheader,nounits | head -n1 | tr -cd '0-9')
  fi

  local vram=''
  vram=$(read_gpu_vram "$address")

  # La sonde d'une carte NVIDIA n'existe nulle part ailleurs : le pilote
  # propriétaire ne publie pas de chip hwmon. Sans ce dépôt, la section capteurs
  # afficherait toutes les températures de la machine **sauf** celle du GPU.
  if [ -n "$temp" ]; then
    record_thermal_reading 'GPU' "$temp" 'GPU' "${model:-GPU}" 'nvidia-smi'
  fi

  json_object \
    "$(jf_maybe_str vendor "$vendor")" \
    "$(jf_maybe_str model "$model")" \
    "$(jf_maybe_str pciId "$pci_id")" \
    "$(jf_maybe_num vramBytes "$vram" NOT_AVAILABLE 'VRAM non exposée par ce pilote')" \
    "$(jf_maybe_str driver "$driver" NOT_AVAILABLE 'aucun pilote noyau en cours d’utilisation')" \
    "$(jf_maybe_str driverVersion "$driver_version" NOT_AVAILABLE 'outil constructeur absent')" \
    "$(jf_raw driverDate "$(j_unknown NOT_AVAILABLE)")" \
    "$(jf_maybe_num temperatureCelsius "$temp" NOT_AVAILABLE 'outil constructeur absent')" \
    "$(jf_raw usagePercent "$(j_unknown NOT_AVAILABLE)")" \
    "$(jf_maybe_num coreClockMhz "$core_clock" NOT_AVAILABLE 'fréquence non exposée par ce pilote')" \
    "$(jf_maybe_num memoryClockMhz "$memory_clock" NOT_AVAILABLE 'fréquence mémoire non exposée par ce pilote')" \
    "$(if depth_at_least gpus standard; then section displays "$(collect_displays "$address")"; fi)"
}

# VRAM totale, quand le pilote l'expose.
#
# `amdgpu` publie `mem_info_vram_total` en octets. Les pilotes NVIDIA propriétaires
# ne l'exposent pas dans /sys : `nvidia-smi` est alors la seule source. Aucune
# déduction depuis le modèle commercial — deux cartes de même nom peuvent avoir
# des quantités de mémoire différentes.
read_gpu_vram() {
  local address=${1-}
  [ -n "$address" ] || return 0

  local dir="/sys/bus/pci/devices/$address"
  [ -d "$dir" ] || dir="/sys/bus/pci/devices/0000:$address"

  local value=''
  value=$(read_value "$dir/mem_info_vram_total" 2>/dev/null || printf '')
  if [ -z "$value" ] && has_cmd nvidia-smi; then
    value=$(run_cmd nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1)
    [[ $value =~ ^[0-9]+$ ]] && value=$((value * 1048576))
  fi

  [[ $value =~ ^[0-9]+$ ]] && printf '%s' "$value"
  return 0
}

# Écrans connectés, lus dans /sys/class/drm.
#
# Un connecteur `disconnected` n'est pas rapporté : une prise HDMI libre n'est
# pas un écran. La résolution retenue est le mode actif, ou à défaut le premier
# mode annoncé par l'écran, qui est son mode préféré.
collect_displays() {
  local address=${1-}
  [ -d /sys/class/drm ] || return 0

  local displays='' connector='' status='' name='' resolution='' modes=''
  for connector in /sys/class/drm/card*-*; do
    [ -d "$connector" ] || continue

    status=$(read_value "$connector/status" 2>/dev/null || printf '')
    [ "$status" = 'connected' ] || continue

    # Rattache l'écran à sa carte : sans cela, un poste bi-GPU listerait tous
    # les écrans sous chaque carte.
    if [ -n "$address" ] && ! drm_belongs_to "$connector" "$address"; then
      continue
    fi

    displays=$(json_join "$displays" "$(parse_display_connector "$connector")")
  done

  [ -n "$displays" ] || return 0
  printf '[%s]' "$displays"
}

# Séparée du parcours de /sys pour être testable sur une arborescence
# reconstituée : la machine de CI n'a aucun écran branché.
parse_display_connector() {
  local connector=${1-}
  local name='' resolution='' modes=''

  name=$(basename "$connector")
  # `card0-HDMI-A-1` → `HDMI-A-1`.
  name=${name#card*-}

  if [ -r "$connector/modes" ]; then
    modes=$(head -n1 "$connector/modes" 2>/dev/null || printf '')
    [[ $modes =~ ^[0-9]+x[0-9]+ ]] && resolution=${BASH_REMATCH[0]}
  fi

  parse_edid "$connector/edid"

  json_object \
    "$(jf_maybe_str name "$name")" \
    "$(jf_maybe_str manufacturer "$EDID_MANUFACTURER" NOT_AVAILABLE 'aucun EDID lisible sur ce connecteur')" \
    "$(jf_maybe_str model "$EDID_MODEL" NOT_AVAILABLE 'écran ne publiant pas son nom de modèle dans l’EDID')" \
    "$(jf_maybe_str serialNumber "$(anon serialNumber "$EDID_SERIAL")" NOT_AVAILABLE 'écran ne publiant aucun numéro de série dans l’EDID')" \
    "$(jf_maybe_str resolution "$resolution" NOT_AVAILABLE 'aucun mode annoncé par l’écran')" \
    "$(jf_raw refreshRateHz "$(j_unknown NOT_AVAILABLE 'fréquence non exposée par /sys/class/drm')")" \
    "$(jf_maybe_str connection "$(printf '%s' "$name" | sed -E 's/-[0-9]+$//')")"
}

# Identité d'un écran, lue dans le bloc EDID que le noyau expose en binaire.
#
# ## Pourquoi lire ce fichier plutôt qu'appeler un outil
#
# `/sys/class/drm/*/edid` est lisible sans privilège et sans paquet à installer.
# Les outils qui savent le décoder — `edid-decode`, `read-edid`, `xrandr
# --verbose` — sont absents de presque toutes les machines auditées, et `xrandr`
# suppose en plus une session graphique ouverte, ce qu'un scan lancé par SSH n'a
# pas. Décoder 128 octets ici évite de rendre l'écran invisible partout ailleurs.
#
# ## Ce qui est publié, et ce qui ne l'est pas
#
# Le constructeur est l'identifiant PNP à trois lettres tel que l'écran le
# déclare (`DEL`, `SAM`, `AUO`). Il n'est **pas** traduit en nom commercial :
# cette table est un annuaire externe, et l'écrire de mémoire produirait un nom
# faux sur les fabricants rares — précisément ceux qu'on ne reconnaît pas.
#
# Le modèle vient du descripteur `0xFC`, facultatif : un écran qui ne le publie
# pas laisse le champ inconnu plutôt que de recevoir le code produit numérique,
# qui ne nomme rien.
#
# Le numéro de série vient du descripteur `0xFF`, et à défaut du champ numérique
# de l'en-tête lorsqu'il n'est pas nul. Beaucoup de dalles laissent les deux
# vides ; c'est un fait sur le matériel, pas un échec de lecture.
#
# Renseigne trois variables plutôt que d'imprimer : un appelant en shell ne peut
# pas récupérer trois chaînes d'une substitution de commande sans choisir un
# séparateur — qu'un nom de modèle finirait par contenir.
parse_edid() {
  local file=${1-}
  EDID_MANUFACTURER=''
  EDID_MODEL=''
  EDID_SERIAL=''

  [ -r "$file" ] && [ -s "$file" ] || return 0
  has_cmd od || return 0

  local -a b=()
  mapfile -t b < <(od -An -v -tx1 -N 128 "$file" 2>/dev/null | tr -s ' ' '\n' | grep -v '^$')
  [ "${#b[@]}" -ge 128 ] || return 0

  # En-tête fixe de tout bloc EDID. Un connecteur sans écran rend parfois un
  # fichier de zéros : le décoder donnerait un constructeur « @@@ ».
  [ "${b[0]}" = '00' ] && [ "${b[7]}" = '00' ] || return 0
  local i=0
  for i in 1 2 3 4 5 6; do
    [ "${b[$i]}" = 'ff' ] || return 0
  done

  EDID_MANUFACTURER=$(edid_manufacturer "${b[8]}" "${b[9]}")
  EDID_MODEL=$(edid_descriptor fc "${b[@]}")
  EDID_SERIAL=$(edid_descriptor ff "${b[@]}")

  if [ -z "$EDID_SERIAL" ]; then
    EDID_SERIAL=$(edid_numeric_serial "${b[12]}" "${b[13]}" "${b[14]}" "${b[15]}")
  fi
}

# Identifiant PNP : trois lettres codées sur cinq bits chacune, `A` valant 1.
edid_manufacturer() {
  local high=$((16#${1-0})) low=$((16#${2-0}))
  local id=$(((high << 8) | low))
  local first=$(((id >> 10) & 31)) second=$(((id >> 5) & 31)) third=$((id & 31))

  # Zéro ne code aucune lettre : l'EDID est illisible ou absent.
  [ "$first" -ge 1 ] && [ "$second" -ge 1 ] && [ "$third" -ge 1 ] || return 0
  [ "$first" -le 26 ] && [ "$second" -le 26 ] && [ "$third" -le 26 ] || return 0

  printf '%b%b%b' \
    "$(printf '\\x%02x' $((first + 64)))" \
    "$(printf '\\x%02x' $((second + 64)))" \
    "$(printf '\\x%02x' $((third + 64)))"
}

# Texte d'un descripteur EDID (`fc` = modèle, `ff` = numéro de série).
#
# Les quatre descripteurs occupent 18 octets à partir de l'octet 54. Un
# descripteur de texte commence par `00 00 00 <type>`; le texte suit à l'octet 5,
# se termine par un saut de ligne et se complète d'espaces.
edid_descriptor() {
  local want=${1-}
  shift
  local -a b=("$@")
  local offset='' i='' byte='' value='' text=''

  for offset in 54 72 90 108; do
    [ "${b[$offset]}" = '00' ] || continue
    [ "${b[$((offset + 1))]}" = '00' ] || continue
    [ "${b[$((offset + 2))]}" = '00' ] || continue
    [ "${b[$((offset + 3))]}" = "$want" ] || continue

    text=''
    for ((i = offset + 5; i <= offset + 17; i++)); do
      byte=${b[$i]}
      value=$((16#$byte))
      [ "$value" -eq 10 ] && break
      # Hors ASCII imprimable, l'octet n'est pas du texte : le convertir
      # produirait un caractère de contrôle dans le rapport JSON.
      if [ "$value" -lt 32 ] || [ "$value" -gt 126 ]; then continue; fi
      text="$text$(printf '\\x%02x' "$value")"
    done

    printf '%b' "$text" | trim
    return 0
  done
}

# Numéro de série numérique de l'en-tête, sur 32 bits en petit-boutiste.
# Zéro n'est pas un numéro de série : c'est le champ laissé vide.
edid_numeric_serial() {
  local serial=0
  serial=$(((16#${4-0} << 24) | (16#${3-0} << 16) | (16#${2-0} << 8) | 16#${1-0}))
  [ "$serial" -ne 0 ] || return 0
  printf '%u' "$serial"
}

# Vrai si le connecteur DRM appartient au périphérique PCI donné.
drm_belongs_to() {
  local connector=$1 address=$2 card='' link=''
  card=$(basename "$connector")
  card=${card%%-*}
  link=$(readlink -f "/sys/class/drm/$card/device" 2>/dev/null || printf '')
  case "$link" in
    *"$address") return 0 ;;
    *) return 1 ;;
  esac
}

# Famille de composant d'une sonde, déduite de son étiquette puis de son pilote.
#
# L'étiquette prime sur le pilote, et c'est délibéré : un chip Super-I/O
# `nct6798` porte à lui seul le processeur, le châssis et les étages
# d'alimentation, et le classer entier d'après son nom rangerait la sonde du VRM
# sous « carte mère », c'est-à-dire sous un seuil quarante degrés trop bas.
#
# Ce qui n'est identifié ni par l'un ni par l'autre ressort `OTHER`. C'est le
# seul verdict honnête pour une sonde nommée `temp3` : le rapport l'affiche, avec
# sa valeur réelle, et s'abstient de la juger. Deviner ici reviendrait à inventer
# une alerte — ou à en taire une.
thermal_category_for() {
  local chip=$1 label=$2
  local haystack=''
  haystack=$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')

  case "$haystack" in
    *package* | *tctl* | *tdie* | *core* | *ccd* | *cputin* | cpu | cpu*) printf 'CPU'; return 0 ;;
    *junction* | *hotspot* | *edge* | *gpu*) printf 'GPU'; return 0 ;;
    *vrm* | *mos*) printf 'VRM'; return 0 ;;
    *pch* | *chipset* | *southbridge*) printf 'CHIPSET'; return 0 ;;
    *systin* | *motherboard* | *mainboard* | *system*) printf 'MOTHERBOARD'; return 0 ;;
    *ambient*) printf 'AMBIENT'; return 0 ;;
    *composite* | *nvme*) printf 'DRIVE_NVME'; return 0 ;;
    *dimm* | *spd*) printf 'MEMORY'; return 0 ;;
    *battery*) printf 'BATTERY'; return 0 ;;
  esac

  case "$chip" in
    coretemp | k10temp | k8temp | zenpower | cpu_thermal | soc_thermal) printf 'CPU' ;;
    amdgpu | radeon | nouveau | i915 | xe) printf 'GPU' ;;
    nvme) printf 'DRIVE_NVME' ;;
    # `drivetemp` couvre indifféremment plateaux et SSD SATA : la famille reste
    # à résoudre auprès du noyau, seul à savoir lequel des deux tourne.
    drivetemp) printf 'DRIVE_UNRESOLVED' ;;
    pch_*) printf 'CHIPSET' ;;
    spd5118) printf 'MEMORY' ;;
    iwlwifi_* | mt79* | ath1*) printf 'NETWORK' ;;
    *) printf 'OTHER' ;;
  esac
}

# Le support d'un disque exposé par `drivetemp` tourne-t-il ?
#
# `queue/rotational` est la réponse du noyau, pas une déduction sur le modèle :
# un « SSD » dans le nom commercial ne prouve rien, et des plateaux se vendent
# sous des références qui n'annoncent pas leur nature.
thermal_drive_category() {
  local chip_dir=$1 block='' rotational=''
  for block in "$chip_dir"/device/block/*; do
    [ -d "$block" ] || continue
    rotational=$(cat "$block/queue/rotational" 2>/dev/null) || continue
    case "$rotational" in
      1) printf 'DRIVE_HDD'; return 0 ;;
      0) printf 'DRIVE_SSD'; return 0 ;;
    esac
  done
  # Sans réponse du noyau, la famille reste indéterminée : aucun seuil vaut mieux
  # qu'un seuil tiré au sort entre cinquante et soixante-dix degrés.
  printf 'OTHER'
}

# Matériel porteur de la sonde, quand sysfs sait le nommer.
#
# Un NVMe et un disque SATA publient leur modèle commercial ; les chips Super-I/O
# ne publient rien. Aucun nom n'est fabriqué : sans modèle lisible, le champ reste
# vide et le rapport affiche la sonde seule, ce qui est exact.
thermal_device_for() {
  local chip_dir=$1 chip=$2 candidate='' model=''

  for candidate in "$chip_dir/device/model" "$chip_dir/device/device/model"; do
    [ -r "$candidate" ] || continue
    model=$(sed -n '1p' "$candidate" 2>/dev/null | trim) || model=''
    [ -n "$model" ] && {
      printf '%s' "$model"
      return 0
    }
  done

  case "$chip" in
    coretemp | k10temp | k8temp | zenpower | cpu_thermal | soc_thermal)
      # Le processeur porte déjà un nom ailleurs dans le rapport. Reprendre le
      # même évite que la section capteurs désigne un matériel que le lecteur ne
      # retrouve nulle part.
      model=$(awk -F': ' '/^model name/ { print $2; exit }' /proc/cpuinfo 2>/dev/null)
      [ -n "$model" ] && printf '%s' "$(printf '%s' "$model" | trim)"
      ;;
  esac
  return 0
}

# Nombre de relevés thermiques pris par sonde.
#
# Une lecture unique attrape ce qui passe : un cœur qui vient de terminer une
# tâche de fond rend dix degrés de plus que la seconde d'après, et le rapport
# annonce alors un pic là où il devrait décrire un état. Trois relevés espacés
# d'une seconde donnent un minimum, une moyenne et un maximum — des statistiques
# sur des mesures réelles, jamais une interpolation d'un trou.
#
# Ils coûtent deux secondes, et ces deux secondes ne sont prises qu'en collecte
# approfondie : un audit rapide reste un instantané, et le dit par `sampleCount`.
thermal_sample_count() {
  if depth_at_least sensors extended; then printf '3'; else printf '1'; fi
}

collect_sensors() {
  log_step 'Capteurs'

  local temps='' fans='' voltages='' discarded='' sources=''
  local hwmon='' label='' value='' celsius_value=''
  local chips_seen=0 temp_inputs_seen=0 unreadable=0 discarded_count=0 usable=0

  # Portée des relevés : dans une VM ou un conteneur, les sondes visibles sont
  # celles de l'hôte, quand l'hyperviseur les laisse passer. Les rapporter sans
  # le dire ferait chercher un ventilateur à une machine qui n'en a pas.
  local scope='LOCAL'
  if [ -n "${CAP_VIRTUALIZED:-}" ] || [ "${CAP_DOCKER:-false}" = 'true' ]; then
    scope='HYPERVISOR_HOST'
  fi

  for hwmon in "$SYSFS_ROOT"/class/hwmon/hwmon*; do
    [ -d "$hwmon" ] || continue
    chips_seen=$((chips_seen + 1))
  done

  # Première passe : recenser les sondes et leurs métadonnées, une seule fois.
  # Les relire à chaque relevé multiplierait les `readlink` par le nombre de
  # passes, pour des valeurs qui ne bougent pas d'une seconde à l'autre.
  local -a paths=() labels=() categories=() devices=() srcs=()
  local input=''
  for input in "$SYSFS_ROOT"/class/hwmon/hwmon*/temp*_input \
    "$SYSFS_ROOT"/class/hwmon/hwmon*/device/temp*_input; do
    [ -e "$input" ] || continue
    temp_inputs_seen=$((temp_inputs_seen + 1))
    if ! [ -r "$input" ]; then
      unreadable=$((unreadable + 1))
      continue
    fi

    local chip_dir='' chip_name='' category=''
    chip_dir=$(dirname "$input")
    chip_name=$(cat "$chip_dir/name" 2>/dev/null || printf '')

    label=''
    [ -r "${input%_input}_label" ] && label=$(cat "${input%_input}_label" 2>/dev/null)
    [ -n "$label" ] || label="${chip_name:-temp}/$(basename "${input%_input}")"

    category=$(thermal_category_for "$chip_name" "$label")
    [ "$category" = 'DRIVE_UNRESOLVED' ] && category=$(thermal_drive_category "$chip_dir")

    paths+=("$input")
    labels+=("$label")
    categories+=("$category")
    devices+=("$(thermal_device_for "$chip_dir" "$chip_name")")
    srcs+=('hwmon')
  done

  # Zones thermiques ACPI : elles doublonnent souvent hwmon, mais sur les
  # machines qui n'exposent aucun chip hwmon elles sont la seule source.
  if [ ${#paths[@]} -eq 0 ]; then
    local zone='' type=''
    for zone in "$SYSFS_ROOT"/class/thermal/thermal_zone*; do
      [ -r "$zone/temp" ] || continue
      temp_inputs_seen=$((temp_inputs_seen + 1))
      type=$(cat "$zone/type" 2>/dev/null || basename "$zone")
      paths+=("$zone/temp")
      labels+=("$type")
      categories+=("$(thermal_category_for "$type" "$type")")
      devices+=('')
      srcs+=('thermal_zone')
    done
  fi

  # Deuxième passe : les relevés. La boucle extérieure est la passe et non la
  # sonde — l'inverse imposerait une seconde d'attente **par capteur**, soit une
  # demi-minute sur une machine qui en expose une vingtaine.
  local passes=0 pass=0 index=0
  passes=$(thermal_sample_count)
  local -a sums=() mins=() maxs=() counts=() lasts=() raws=()
  for ((index = 0; index < ${#paths[@]}; index++)); do
    sums[index]=''
    mins[index]=''
    maxs[index]=''
    counts[index]=0
    lasts[index]=''
    raws[index]=''
  done

  for ((pass = 0; pass < passes; pass++)); do
    [ "$pass" -gt 0 ] && sleep 1
    for ((index = 0; index < ${#paths[@]}; index++)); do
      value=$(cat "${paths[index]}" 2>/dev/null) || continue
      [[ $value =~ ^-?[0-9]+$ ]] || continue
      if ! celsius_value=$(millicelsius_to_celsius "$value"); then
        # Hors domaine physique : ce n'est pas une température. Elle est retenue
        # brute, une seule fois, pour que le diagnostic voie la sonde en panne
        # plutôt que de la voir disparaître.
        if [ "$pass" -eq 0 ]; then
          discarded_count=$((discarded_count + 1))
          if [ "$discarded_count" -le 64 ]; then
            discarded=$(json_join "$discarded" "$(json_object \
              "$(jf_str label "${labels[index]}")" \
              "$(jf_str source "${srcs[index]}")" \
              "$(jf_str sourcePath "${paths[index]}")" \
              "$(jf_raw rawValue "$(j_num "$value")")" \
              "$(jf_str rawUnit 'millidegree_celsius')" \
              "$(jf_str reason 'OUT_OF_PHYSICAL_RANGE')")")
          fi
        fi
        continue
      fi
      lasts[index]="$celsius_value"
      raws[index]="$value"
      counts[index]=$((counts[index] + 1))
      if [ -z "${mins[index]}" ]; then
        mins[index]="$celsius_value"
        maxs[index]="$celsius_value"
        sums[index]="$celsius_value"
      else
        mins[index]=$(LC_ALL=C awk -v a="${mins[index]}" -v b="$celsius_value" \
          'BEGIN { printf "%.1f", (b < a ? b : a) }')
        maxs[index]=$(LC_ALL=C awk -v a="${maxs[index]}" -v b="$celsius_value" \
          'BEGIN { printf "%.1f", (b > a ? b : a) }')
        sums[index]=$(LC_ALL=C awk -v a="${sums[index]}" -v b="$celsius_value" \
          'BEGIN { printf "%.3f", a + b }')
      fi
    done
  done

  # Troisième passe : mise en forme. Les seuils du capteur sont relus ici, une
  # seule fois — ils ne bougent pas entre deux relevés.
  local base='' critical='' critical_celsius='' high='' high_celsius='' average=''
  for ((index = 0; index < ${#paths[@]}; index++)); do
    [ "${counts[index]}" -gt 0 ] || continue
    usable=$((usable + 1))

    base="${paths[index]%_input}"
    critical='' critical_celsius='' high='' high_celsius='' average=''
    if [ -r "${base}_crit" ]; then
      critical=$(cat "${base}_crit" 2>/dev/null)
      [[ $critical =~ ^-?[0-9]+$ ]] && critical_celsius=$(millicelsius_to_celsius "$critical")
    fi
    if [ -r "${base}_max" ]; then
      high=$(cat "${base}_max" 2>/dev/null)
      [[ $high =~ ^-?[0-9]+$ ]] && high_celsius=$(millicelsius_to_celsius "$high")
    fi

    # La moyenne n'existe qu'à partir de deux relevés. Sur un relevé unique, la
    # publier reviendrait à répéter la valeur courante sous un nom qui promet
    # une observation dans la durée.
    if [ "${counts[index]}" -gt 1 ]; then
      average=$(LC_ALL=C awk -v s="${sums[index]}" -v n="${counts[index]}" \
        'BEGIN { printf "%.1f", s / n }')
    fi

    temps=$(json_join "$temps" "$(json_object \
      "$(jf_str label "${labels[index]}")" \
      "$(jf_raw celsius "$(j_num "${lasts[index]}")")" \
      "$(if [ -n "$critical_celsius" ]; then jf_raw criticalCelsius "$(j_num "$critical_celsius")"; fi)" \
      "$(if [ -n "$high_celsius" ]; then jf_raw highCelsius "$(j_num "$high_celsius")"; fi)" \
      "$(jf_str category "${categories[index]}")" \
      "$(if [ -n "${devices[index]}" ]; then jf_str device "${devices[index]}"; fi)" \
      "$(jf_str source "${srcs[index]}")" \
      "$(jf_str sourcePath "${paths[index]}")" \
      "$(jf_str scope "$scope")" \
      "$(jf_str quality 'MEASURED')" \
      "$(if [ -n "$average" ]; then jf_raw minCelsius "$(j_num "${mins[index]}")"; fi)" \
      "$(if [ -n "$average" ]; then jf_raw averageCelsius "$(j_num "$average")"; fi)" \
      "$(if [ -n "$average" ]; then jf_raw maxCelsius "$(j_num "${maxs[index]}")"; fi)" \
      "$(jf_raw sampleCount "$(j_num "${counts[index]}")")" \
      "$(jf_raw rawValue "$(j_num "${raws[index]}")")" \
      "$(jf_str rawUnit 'millidegree_celsius')")")

    case "$sources" in
      *"\"${srcs[index]}\""*) : ;;
      *) sources=$(json_join "$sources" "$(j_str "${srcs[index]}")") ;;
    esac
  done

  # Ce que le stockage et les cartes graphiques ont déposé pendant leur propre
  # collecte : sondes SMART/NVMe et sondes NVIDIA, invisibles depuis hwmon.
  # Elles arrivent déjà formées — les reconstruire ici demanderait de rappeler
  # `smartctl`, et rendrait potentiellement deux valeurs pour un même capteur.
  local journal_line='' journal_source=''
  if [ -n "${THERMAL_JOURNAL:-}" ] && [ -r "${THERMAL_JOURNAL:-}" ]; then
    while IFS= read -r journal_line; do
      [ -n "$journal_line" ] || continue
      temps=$(json_join "$temps" "$journal_line")
      usable=$((usable + 1))
      temp_inputs_seen=$((temp_inputs_seen + 1))
      journal_source=$(printf '%s' "$journal_line" |
        sed -nE 's/.*"source":"([^"]*)".*/\1/p')
      [ -n "$journal_source" ] || continue
      case "$sources" in
        *"\"$journal_source\""*) : ;;
        *) sources=$(json_join "$sources" "$(j_str "$journal_source")") ;;
      esac
    done <"$THERMAL_JOURNAL"
  fi

  for input in "$SYSFS_ROOT"/class/hwmon/hwmon*/fan*_input; do
    [ -r "$input" ] || continue
    value=$(cat "$input" 2>/dev/null) || continue
    [[ $value =~ ^[0-9]+$ ]] || continue
    label=''
    [ -r "${input%_input}_label" ] && label=$(cat "${input%_input}_label" 2>/dev/null)
    [ -n "$label" ] || label=$(basename "${input%_input}")
    fans=$(json_join "$fans" "$(json_object \
      "$(jf_str label "$label")" \
      "$(jf_raw rpm "$(j_num "$value")")")")
  done

  for input in "$SYSFS_ROOT"/class/hwmon/hwmon*/in*_input \
    "$SYSFS_ROOT"/class/hwmon/hwmon*/device/in*_input; do
    [ -r "$input" ] || continue
    value=$(cat "$input" 2>/dev/null) || continue
    [[ $value =~ ^-?[0-9]+$ ]] || continue
    label=''
    [ -r "${input%_input}_label" ] && label=$(cat "${input%_input}_label" 2>/dev/null)
    if [ -z "$label" ]; then
      local chip_name=''
      chip_name=$(cat "$(dirname "$input")/name" 2>/dev/null || printf 'voltage')
      label="$chip_name/$(basename "${input%_input}")"
    fi
    local volts=''
    volts=$(LC_ALL=C awk -v mv="$value" 'BEGIN { printf "%.3f", mv / 1000 }')
    voltages=$(json_join "$voltages" "$(json_object \
      "$(jf_str label "$label")" \
      "$(jf_raw volts "$(j_num "$volts")")")")
  done

  # Un tableau vide se lit « cette machine n'a pas de capteur », ce qui est une
  # affirmation. Quand rien n'a été lu, dire ce qui a été sondé — la différence
  # entre un portable sans capteur exposé et un capteur présent mais illisible
  # est précisément ce qu'un rapport doit trancher.
  local unavailable_reason='' suggested_tool=''
  if [ -z "$temps" ]; then
    if [ "$unreadable" -gt 0 ]; then
      unavailable_reason='SENSORS_UNREADABLE'
      record_issue 'sensors.temperatures' 'warning' \
        "$temp_inputs_seen capteur(s) thermique(s) présents, $unreadable illisibles (droits insuffisants ?)." \
        'hwmon' 'PERMISSION_DENIED'
    elif [ "$chips_seen" -eq 0 ]; then
      # La virtualisation explique cette absence sans qu'il y ait rien à
      # réparer : un hyperviseur ne transmet pas ses sondes, et le dire évite
      # d'envoyer l'utilisateur chercher un pilote qui n'existe pas.
      if [ -n "${CAP_VIRTUALIZED:-}" ] || [ "${CAP_DOCKER:-false}" = 'true' ]; then
        unavailable_reason='VIRTUALIZED'
      else
        unavailable_reason='NO_SENSOR_EXPOSED'
        # `lm-sensors` charge les pilotes des chips Super-I/O que le noyau ne
        # sonde pas seul. Suggéré, jamais requis : un audit se fait sans lui.
        has_cmd sensors || suggested_tool='lm-sensors'
      fi
      record_issue 'sensors.temperatures' 'warning' \
        'Aucun chip hwmon ni zone thermique : machine virtualisée, conteneur ou noyau sans pilote de capteur.' \
        'hwmon' 'NOT_AVAILABLE'
    else
      unavailable_reason='NO_SENSOR_EXPOSED'
      has_cmd sensors || suggested_tool='lm-sensors'
      record_issue 'sensors.temperatures' 'warning' \
        "$chips_seen chip(s) hwmon présents, aucun n'expose de température exploitable." \
        'hwmon' 'NOT_AVAILABLE'
    fi
  fi

  json_object \
    "$(jf_raw temperatures "[$temps]")" \
    "$(jf_raw temperatureCollection "$(json_object \
      "$(jf_raw probed "$(j_num "$temp_inputs_seen")")" \
      "$(jf_raw usable "$(j_num "$usable")")" \
      "$(jf_raw discarded "$(j_num "$discarded_count")")" \
      "$(jf_raw sources "[$sources]")" \
      "$(jf_raw sampleCount "$(j_num "$passes")")" \
      "$(if [ "$passes" -gt 1 ]; then jf_raw sampleIntervalMs "$(j_num 1000)"; fi)" \
      "$(if [ -n "$unavailable_reason" ]; then jf_str unavailableReason "$unavailable_reason"; fi)" \
      "$(if [ -n "$suggested_tool" ]; then jf_str suggestedTool "$suggested_tool"; fi)" \
      "$(if [ -n "$discarded" ]; then jf_raw discardedReadings "[$discarded]"; fi)")")" \
    "$(jf_raw fans "[$fans]")" \
    "$(jf_raw voltages "[$voltages]")"
}
