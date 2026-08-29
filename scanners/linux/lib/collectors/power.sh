#!/usr/bin/env bash
# Batterie, alimentation secteur et bloc d'alimentation.
#
# La batterie et le secteur viennent de `/sys/class/power_supply`, présent sans
# outil ni privilège : la collecte fonctionne donc sur un portable sans rien
# installer. Une machine fixe n'a pas de batterie — c'est un cas normal, pas une
# donnée manquante.
#
# Le bloc d'alimentation, lui, ne se laisse presque jamais lire : une
# alimentation ATX standard n'a aucun canal pour se présenter au système. Ce
# collecteur interroge tout ce qui existe — SMBIOS, sysfs, hwmon, IPMI — et,
# quand rien ne répond, **le dit** au lieu de combler. Aucune puissance nominale
# n'est déduite d'une consommation : un PC qui tire 300 W peut avoir un bloc de
# 500, 750 ou 1000 W.

# Racine sysfs, déplaçable par les tests — même raison que dans `hardware.sh` :
# sans elle, la collecte des rails ne serait vérifiable que sur la machine qui a
# le bon Super-I/O, c'est-à-dire jamais en CI.
: "${SYSFS_ROOT:=/sys}"

collect_power() {
  log_step 'Batterie et alimentation'

  local batteries='' ac='' entry='' type=''

  for entry in "$SYSFS_ROOT"/class/power_supply/*; do
    [ -d "$entry" ] || continue
    type=$(read_value "$entry/type" 2>/dev/null || printf '')

    case "$type" in
      Battery)
        batteries=$(json_join "$batteries" "$(parse_battery "$entry")")
        ;;
      Mains | USB)
        # Plusieurs alimentations peuvent coexister (secteur, USB-C) : une seule
        # branchée suffit à conclure que la machine est alimentée.
        case "$(read_value "$entry/online" 2>/dev/null || printf '')" in
          1) ac='true' ;;
          0) [ -z "$ac" ] && ac='false' ;;
        esac
        ;;
    esac
  done

  # Gouverneur de fréquence et profil de plateforme. Ils expliquent des mesures
  # qui sembleraient sinon contradictoires : un processeur bridé à la moitié de
  # sa fréquence sous `powersave` n'a rien d'anormal, et l'attribuer à un défaut
  # matériel serait un faux diagnostic.
  #
  # Le gouverneur est lu sur `cpu0` : le noyau les tient identiques sur tous les
  # cœurs d'une même politique, et publier une valeur par cœur donnerait
  # trente-deux fois la même.
  local governor='' plan=''
  [ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ] &&
    governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || true)
  [ -r /sys/firmware/acpi/platform_profile ] &&
    plan=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null || true)

  json_object \
    "$(jf_raw batteries "[$batteries]")" \
    "$(jf_maybe_bool acConnected "$ac" NOT_AVAILABLE 'aucune alimentation déclarée par le noyau')" \
    "$(jf_maybe_str activePlan "$plan" NOT_AVAILABLE 'aucun profil de plateforme ACPI exposé')" \
    "$(jf_maybe_str cpuGovernor "$governor" NOT_AVAILABLE 'cpufreq non exposé par ce noyau')" \
    "$(jf_raw powerSupply "$(collect_power_supply)")"
}

# Convertit en wattheures une valeur exposée en microwattheures.
uwh_to_wh() {
  local raw=${1-}
  [ -n "$raw" ] || return 0
  [[ $raw =~ ^[0-9]+$ ]] || return 0
  awk -v v="$raw" 'BEGIN { printf "%.2f", v / 1000000 }'
}

# Convertit un couple microampères-heures / microvolts en wattheures.
#
# Certains firmwares n'exposent que des charges (`charge_*`) et non des énergies
# (`energy_*`). Sans la tension nominale, la conversion serait une invention :
# la valeur reste alors absente.
uah_to_wh() {
  local charge=${1-} microvolts=${2-}
  [ -n "$charge" ] && [ -n "$microvolts" ] || return 0
  [[ $charge =~ ^[0-9]+$ ]] && [[ $microvolts =~ ^[0-9]+$ ]] || return 0
  [ "$microvolts" -gt 0 ] || return 0
  awk -v c="$charge" -v v="$microvolts" 'BEGIN { printf "%.2f", (c / 1000000) * (v / 1000000) }'
}

parse_battery() {
  local dir=$1
  local name='' manufacturer='' model='' serial='' technology='' capacity='' status=''
  local design_wh='' full_wh='' cycles='' voltage_uv='' voltage_v='' nominal_uv=''

  name=$(basename "$dir")
  manufacturer=$(clean_dmi_value "$(read_value "$dir/manufacturer" 2>/dev/null || printf '')")
  model=$(clean_dmi_value "$(read_value "$dir/model_name" 2>/dev/null || printf '')")
  serial=$(clean_dmi_value "$(read_value "$dir/serial_number" 2>/dev/null || printf '')")
  technology=$(clean_dmi_value "$(read_value "$dir/technology" 2>/dev/null || printf '')")
  capacity=$(read_value "$dir/capacity" 2>/dev/null || printf '')
  cycles=$(read_value "$dir/cycle_count" 2>/dev/null || printf '')
  voltage_uv=$(read_value "$dir/voltage_now" 2>/dev/null || printf '')
  nominal_uv=$(read_value "$dir/voltage_min_design" 2>/dev/null || printf '')

  # `energy_*` est en microwattheures ; `charge_*` en microampères-heures.
  design_wh=$(uwh_to_wh "$(read_value "$dir/energy_full_design" 2>/dev/null || printf '')")
  full_wh=$(uwh_to_wh "$(read_value "$dir/energy_full" 2>/dev/null || printf '')")
  if [ -z "$design_wh" ]; then
    design_wh=$(uah_to_wh "$(read_value "$dir/charge_full_design" 2>/dev/null || printf '')" "$nominal_uv")
  fi
  if [ -z "$full_wh" ]; then
    full_wh=$(uah_to_wh "$(read_value "$dir/charge_full" 2>/dev/null || printf '')" "$nominal_uv")
  fi

  [ -n "$voltage_uv" ] && [[ $voltage_uv =~ ^[0-9]+$ ]] &&
    voltage_v=$(awk -v v="$voltage_uv" 'BEGIN { printf "%.2f", v / 1000000 }')

  case "$(read_value "$dir/status" 2>/dev/null || printf '')" in
    Charging) status='CHARGING' ;;
    Discharging) status='DISCHARGING' ;;
    Full) status='FULL' ;;
    'Not charging') status='NOT_CHARGING' ;;
    Unknown) status='UNKNOWN' ;;
    *) status='' ;;
  esac

  if [ -z "$design_wh" ] || [ -z "$full_wh" ]; then
    record_issue 'power.battery' 'warning' \
      "Capacités de $name non lisibles : usure non calculable." 'sysfs' 'NOT_AVAILABLE'
  fi

  json_object \
    "$(jf_maybe_str name "$name")" \
    "$(jf_maybe_str manufacturer "$manufacturer")" \
    "$(jf_maybe_str model "$model")" \
    "$(jf_maybe_str serialNumber "$(anon serialNumber "$serial")")" \
    "$(jf_maybe_str technology "$technology")" \
    "$(jf_maybe_num chargePercent "$capacity" NOT_AVAILABLE \
      'niveau de charge hors des bornes physiques, ou non exposé')" \
    "$(jf_maybe_str status "$status" UNKNOWN 'état non rapporté par le firmware')" \
    "$(jf_maybe_num designCapacityWh "$design_wh" NOT_AVAILABLE 'capacité de conception non exposée')" \
    "$(jf_maybe_num fullChargeCapacityWh "$full_wh" NOT_AVAILABLE 'capacité à pleine charge non exposée')" \
    "$(jf_maybe_num cycleCount "$cycles" NOT_AVAILABLE \
      'compteur de cycles non exposé par le firmware')" \
    "$(jf_maybe_num voltageVolts "$voltage_v")"
}

# --- Bloc d'alimentation -----------------------------------------------------
#
# Quatre sources, interrogées dans l'ordre de ce qu'elles valent :
#
#  1. **SMBIOS type 39** — le firmware décrit le bloc. Absent de la quasi-totalité
#     des PC grand public, présent sur les serveurs et quelques stations ;
#  2. **hwmon** — un pilote d'alimentation numérique (`corsairpsu`) fait parler
#     le bloc lui-même ; les autres puces ne rendent que les tensions **de la
#     carte mère**, ce que le rapport ne confond jamais avec celles du bloc ;
#  3. **sysfs power_supply** — bloc secteur d'un portable, chargeur USB-PD,
#     onduleur ; pas l'alimentation ATX d'une machine fixe ;
#  4. **IPMI** — sur un serveur, le contrôleur de gestion sait tout ce que le
#     système d'exploitation ignore.
#
# Aucune ne rend quoi que ce soit sur un PC de bureau ordinaire, et c'est le
# résultat normal : le rapport le déclare en `limitations`.

# Puissance nominale annoncée par le SMBIOS, en watts.
#
# `Max Power Capacity: 750 W` est une donnée ; `Unknown` n'en est pas une, et
# la retenir comme zéro afficherait une alimentation de 0 W.
psu_dmi_capacity() {
  local raw=${1-}
  case "$raw" in
    *[0-9]*' W') printf '%s' "${raw%% W}" ;;
  esac
}

# Nature du bloc, telle que le SMBIOS la nomme.
#
# Seule `Switching` conclut à une alimentation ATX : c'est le firmware qui le
# dit, pas la forme du boîtier. Tout le reste ressort `UNKNOWN` — deviner
# reviendrait exactement à inventer ce que ce collecteur existe pour ne pas
# inventer.
psu_dmi_type() {
  case "${1-}" in
    Switching) printf 'STANDARD_ATX' ;;
    UPS) printf 'UPS' ;;
    *) printf 'UNKNOWN' ;;
  esac
}

# Analyse un enregistrement `dmidecode --type 39`.
parse_dmi_power_supply() {
  local record=$1 index=${2:-1}
  local name='' location='' manufacturer='' serial='' asset='' part='' revision=''
  local capacity='' status_raw='' status='' present='' hot='' type_raw=''

  psu_dmi_field() {
    printf '%s' "$record" | sed -nE "s/^[[:space:]]*$1:[[:space:]]+(.*)\$/\1/p" | head -n1
  }

  name=$(clean_dmi_value "$(psu_dmi_field 'Name')")
  location=$(clean_dmi_value "$(psu_dmi_field 'Location')")
  manufacturer=$(clean_dmi_value "$(psu_dmi_field 'Manufacturer')")
  serial=$(clean_dmi_value "$(psu_dmi_field 'Serial Number')")
  asset=$(clean_dmi_value "$(psu_dmi_field 'Asset Tag')")
  part=$(clean_dmi_value "$(psu_dmi_field 'Model Part Number')")
  revision=$(clean_dmi_value "$(psu_dmi_field 'Revision')")
  capacity=$(psu_dmi_capacity "$(psu_dmi_field 'Max Power Capacity')")
  status_raw=$(psu_dmi_field 'Status')
  type_raw=$(psu_dmi_field 'Type')

  # `Status: Present, OK` porte deux faits distincts : la présence physique du
  # bloc et son état. Les fondre en une chaîne obligerait chaque lecteur à
  # refaire cette analyse.
  case "$status_raw" in
    *'Not Present'*) present='false' ;;
    *Present*) present='true' ;;
  esac
  status=$(printf '%s' "${status_raw#*, }" | trim)
  [ "$status" = "$status_raw" ] && status=$(clean_dmi_value "$status_raw")

  case "$(psu_dmi_field 'Hot Replaceable')" in
    Yes) hot='true' ;;
    No) hot='false' ;;
  esac

  local label="$name"
  [ -n "$label" ] || label="$location"
  [ -n "$label" ] || label="Alimentation $index"

  unset -f psu_dmi_field

  json_object \
    "$(jf_str label "$label")" \
    "$(jf_str type "$(psu_dmi_type "$type_raw")")" \
    "$(jf_maybe_str location "$location" NOT_AVAILABLE 'emplacement non renseigné par le firmware')" \
    "$(jf_maybe_str manufacturer "$manufacturer" NOT_AVAILABLE 'fabricant non renseigné par le firmware')" \
    "$(jf_maybe_str model "$name" NOT_AVAILABLE 'modèle non renseigné par le firmware')" \
    "$(jf_maybe_str serialNumber "$(anon serialNumber "$serial")" NOT_AVAILABLE 'numéro de série non renseigné par le firmware')" \
    "$(jf_maybe_str partNumber "$part" NOT_AVAILABLE 'référence non renseignée par le firmware')" \
    "$(jf_maybe_str assetTag "$(anon serialNumber "$asset")" NOT_AVAILABLE 'étiquette d’inventaire non renseignée')" \
    "$(jf_maybe_str revision "$revision" NOT_AVAILABLE 'révision non renseignée par le firmware')" \
    "$(jf_maybe_num ratedPowerWatts "$capacity" NOT_AVAILABLE 'puissance nominale non renseignée par le firmware — elle ne se déduit pas de la consommation')" \
    "$(jf_maybe_str status "$status" NOT_AVAILABLE 'état non renseigné par le firmware')" \
    "$(jf_maybe_bool present "$present" NOT_AVAILABLE 'présence non renseignée par le firmware')" \
    "$(jf_maybe_bool hotReplaceable "$hot" NOT_AVAILABLE 'remplacement à chaud non renseigné par le firmware')" \
    "$(jf_str source 'SMBIOS')" \
    "$(jf_str confidence 'MEDIUM')"
}

# Découpe la sortie de `dmidecode --type 39`, un enregistrement par bloc.
#
# Lit stdin plutôt que d'appeler `dmidecode` : c'est ce qui permet de tester
# l'analyse sur des sorties réelles, y compris celles de serveurs qu'aucune
# machine de CI ne possède.
psu_dmi_parse() {
  local units='' record='' line='' index=0 seen='false'
  while IFS= read -r line; do
    if [ "$line" = 'System Power Supply' ]; then
      if [ "$seen" = 'true' ]; then
        index=$((index + 1))
        units=$(json_join "$units" "$(parse_dmi_power_supply "$record" "$index")")
      fi
      seen='true'
      record=''
      continue
    fi
    record+="$line"$'\n'
  done
  # Le dernier enregistrement n'est suivi d'aucun marqueur : sans cette reprise,
  # une machine à alimentation unique n'en rendrait aucune.
  if [ "$seen" = 'true' ]; then
    index=$((index + 1))
    units=$(json_join "$units" "$(parse_dmi_power_supply "$record" "$index")")
  fi
  printf '%s' "$units"
}

# Une alimentation identifiée par le SMBIOS, ou rien.
psu_dmi_units() {
  [ "$(capability_tool dmidecode)" = 'true' ] || return 0
  [ "$CAP_PRIVILEGED" = 'true' ] || return 0

  local out=''
  out=$(LC_ALL=C run_cmd dmidecode --type 39 2>/dev/null) || return 0
  case "$out" in
    *'System Power Supply'*) ;;
    *) return 0 ;;
  esac
  printf '%s' "$out" | psu_dmi_parse
}

# Convertit une valeur hwmon en unité du rapport, sans arrondi trompeur.
psu_scale() {
  local raw=${1-} divisor=${2-} decimals=${3:-3}
  [ -n "$raw" ] || return 0
  [[ $raw =~ ^-?[0-9]+$ ]] || return 0
  LC_ALL=C awk -v v="$raw" -v d="$divisor" -v n="$decimals" \
    'BEGIN { printf "%." n "f", v / d }'
}

# Étiquette d'un capteur hwmon : celle de la puce, ou son nom de fichier.
psu_sensor_label() {
  local input=$1 chip=$2 label=''
  [ -r "${input%_input}_label" ] && label=$(cat "${input%_input}_label" 2>/dev/null)
  [ -n "$label" ] || label="${chip:-hwmon}/$(basename "${input%_input}")"
  printf '%s' "$label"
}

# Le bloc parle-t-il de lui-même ?
#
# Un pilote d'alimentation numérique est le **seul** cas où hwmon rend autre
# chose que les tensions de la carte mère. La liste est volontairement courte :
# reconnaître un bloc sur un nom approchant reviendrait à attribuer au matériel
# des mesures qui ne viennent pas de lui.
psu_is_digital_chip() {
  case "${1-}" in
    corsairpsu | nzxt_epsu | aquacomputer_* | asus_ec_sensors_psu) return 0 ;;
    *) return 1 ;;
  esac
}

# Modèle publié par un périphérique HID, quand le noyau le nomme.
psu_hid_name() {
  local chip_dir=$1 uevent=''
  for uevent in "$chip_dir/device/uevent" "$chip_dir/device/../uevent"; do
    [ -r "$uevent" ] || continue
    local name=''
    name=$(sed -nE 's/^HID_NAME=(.*)$/\1/p' "$uevent" 2>/dev/null | head -n1)
    [ -n "$name" ] && {
      printf '%s' "$(printf '%s' "$name" | trim)"
      return 0
    }
  done
  return 0
}

# Alimentations numériques exposées par hwmon, avec leurs rails.
#
# Rend deux fragments séparés par une tabulation : les unités et les rails. Les
# rails d'un bloc numérique sont les seuls à porter `measuredBy: POWER_SUPPLY` —
# ce sont les seuls que le bloc mesure lui-même.
psu_digital_from_hwmon() {
  local units='' rails='' hwmon='' chip=''

  for hwmon in "$SYSFS_ROOT"/class/hwmon/hwmon*; do
    [ -d "$hwmon" ] || continue
    chip=$(cat "$hwmon/name" 2>/dev/null || printf '')
    psu_is_digital_chip "$chip" || continue

    local model='' input_watts='' input_volts='' temperature='' fan='' input=''
    model=$(psu_hid_name "$hwmon")

    # `power1` est la puissance totale consommée à l'entrée, `in0` la tension du
    # secteur : ce sont les deux grandeurs que le pilote documente comme telles.
    [ -r "$hwmon/power1_input" ] &&
      input_watts=$(psu_scale "$(cat "$hwmon/power1_input" 2>/dev/null)" 1000000 2)
    [ -r "$hwmon/in0_input" ] &&
      input_volts=$(psu_scale "$(cat "$hwmon/in0_input" 2>/dev/null)" 1000 3)
    [ -r "$hwmon/temp1_input" ] &&
      temperature=$(psu_scale "$(cat "$hwmon/temp1_input" 2>/dev/null)" 1000 1)
    [ -r "$hwmon/fan1_input" ] && fan=$(cat "$hwmon/fan1_input" 2>/dev/null)
    [[ $fan =~ ^[0-9]+$ ]] || fan=''

    # Les rails de sortie : tout `inN` sauf `in0`, qui est l'entrée secteur.
    for input in "$hwmon"/in[1-9]_input; do
      [ -r "$input" ] || continue
      local volts=''
      volts=$(psu_scale "$(cat "$input" 2>/dev/null)" 1000 3) || continue
      [ -n "$volts" ] || continue
      rails=$(json_join "$rails" "$(json_object \
        "$(jf_str label "$(psu_sensor_label "$input" "$chip")")" \
        "$(jf_raw volts "$(j_num "$volts")")" \
        "$(jf_str measuredBy 'POWER_SUPPLY')" \
        "$(jf_str source 'HWMON')" \
        "$(jf_str chip "$chip")" \
        "$(jf_str sourcePath "$input")")")
    done

    units=$(json_join "$units" "$(json_object \
      "$(jf_str label "${model:-$chip}")" \
      "$(jf_str type 'DIGITAL_ATX')" \
      "$(jf_maybe_str model "$model" NOT_AVAILABLE 'le pilote ne publie pas de modèle')" \
      "$(jf_raw ratedPowerWatts "$(j_unknown NOT_AVAILABLE 'puissance nominale non publiée par le bloc — elle ne se déduit pas de la consommation')")" \
      "$(jf_raw telemetry "$(json_object \
        "$(jf_bool available 'true')" \
        "$(jf_maybe_num inputPowerWatts "$input_watts" NOT_AVAILABLE 'puissance d’entrée non publiée')" \
        "$(jf_maybe_num inputVoltageVolts "$input_volts" NOT_AVAILABLE 'tension d’entrée non publiée')" \
        "$(jf_maybe_num temperatureCelsius "$temperature" NOT_AVAILABLE 'température non publiée')" \
        "$(jf_maybe_num fanRpm "$fan" NOT_AVAILABLE 'vitesse de ventilateur non publiée')" \
        "$(jf_raw efficiencyPercent "$(j_unknown NOT_AVAILABLE 'rendement non publié — il ne se calcule pas honnêtement depuis deux mesures d’instants différents')")" \
        "$(jf_str source 'HWMON')")")" \
      "$(jf_str source 'HWMON')" \
      "$(jf_str confidence 'HIGH')")")
  done

  printf '%s\t%s' "$units" "$rails"
}

# Tensions rendues par les puces de surveillance de la carte mère.
#
# Elles ne viennent **pas** du bloc d'alimentation : un Super-I/O mesure ce qui
# arrive à la carte mère, à travers un diviseur résistif. Les présenter comme
# des tensions d'alimentation serait le contresens le plus facile à commettre de
# toute cette section.
psu_motherboard_rails() {
  local rails='' input='' chip='' count=0

  for input in "$SYSFS_ROOT"/class/hwmon/hwmon*/in*_input \
    "$SYSFS_ROOT"/class/hwmon/hwmon*/device/in*_input; do
    [ -r "$input" ] || continue
    [ "$count" -ge 64 ] && break

    local chip_dir=''
    chip_dir=$(dirname "$input")
    chip=$(cat "$chip_dir/name" 2>/dev/null || printf '')
    # Un bloc numérique a déjà rendu ses rails, mesurés par lui : les reprendre
    # ici les rattacherait une seconde fois à la carte mère.
    psu_is_digital_chip "$chip" && continue

    local volts=''
    volts=$(psu_scale "$(cat "$input" 2>/dev/null)" 1000 3)
    [ -n "$volts" ] || continue

    count=$((count + 1))
    rails=$(json_join "$rails" "$(json_object \
      "$(jf_str label "$(psu_sensor_label "$input" "$chip")")" \
      "$(jf_raw volts "$(j_num "$volts")")" \
      "$(jf_str measuredBy 'MOTHERBOARD')" \
      "$(jf_str source 'HWMON')" \
      "$(if [ -n "$chip" ]; then jf_str chip "$chip"; fi)" \
      "$(jf_str sourcePath "$input")")")
  done

  printf '%s' "$rails"
}

# Sources d'alimentation exposées par le noyau : secteur, USB-PD, onduleur.
#
# Ce sous-système ne décrit **pas** l'alimentation ATX d'une machine fixe. Il
# décrit ce qui entre dans la machine, ce qui n'est pas la même chose, et la
# nature du périphérique est donc portée explicitement par `type`.
psu_sysfs_units() {
  local units='' entry='' kind='' has_battery='false'

  for entry in "$SYSFS_ROOT"/class/power_supply/*; do
    [ -d "$entry" ] || continue
    [ "$(read_value "$entry/type" 2>/dev/null || printf '')" = 'Battery' ] && has_battery='true'
  done

  for entry in "$SYSFS_ROOT"/class/power_supply/*; do
    [ -d "$entry" ] || continue
    kind=$(read_value "$entry/type" 2>/dev/null || printf '')

    local unit_type='' usb_type=''
    case "$kind" in
      Mains)
        # Un bloc secteur avec une batterie dans la même énumération est le
        # chargeur d'un portable. Sans batterie, la nature de l'entrée n'est pas
        # établie : le noyau dit « secteur », pas « alimentation interne ».
        if [ "$has_battery" = 'true' ]; then unit_type='LAPTOP_ADAPTER'; else unit_type='UNKNOWN'; fi
        ;;
      USB)
        usb_type=$(read_value "$entry/usb_type" 2>/dev/null || printf '')
        case "$usb_type" in
          *PD*) unit_type='USB_PD' ;;
          *) unit_type='UNKNOWN' ;;
        esac
        ;;
      UPS) unit_type='UPS' ;;
      *) continue ;;
    esac

    local manufacturer='' model='' serial='' volts='' amps='' watts=''
    manufacturer=$(clean_dmi_value "$(read_value "$entry/manufacturer" 2>/dev/null || printf '')")
    model=$(clean_dmi_value "$(read_value "$entry/model_name" 2>/dev/null || printf '')")
    serial=$(clean_dmi_value "$(read_value "$entry/serial_number" 2>/dev/null || printf '')")
    volts=$(psu_scale "$(read_value "$entry/voltage_now" 2>/dev/null || printf '')" 1000000 3)
    amps=$(psu_scale "$(read_value "$entry/current_now" 2>/dev/null || printf '')" 1000000 3)
    watts=$(psu_scale "$(read_value "$entry/power_now" 2>/dev/null || printf '')" 1000000 2)

    local available='false'
    [ -n "$volts$amps$watts" ] && available='true'

    units=$(json_join "$units" "$(json_object \
      "$(jf_str label "$(basename "$entry")")" \
      "$(jf_str type "$unit_type")" \
      "$(jf_maybe_str manufacturer "$manufacturer" NOT_AVAILABLE 'fabricant non publié par le pilote')" \
      "$(jf_maybe_str model "$model" NOT_AVAILABLE 'modèle non publié par le pilote')" \
      "$(jf_maybe_str serialNumber "$(anon serialNumber "$serial")" NOT_AVAILABLE 'numéro de série non publié par le pilote')" \
      "$(jf_raw ratedPowerWatts "$(j_unknown NOT_AVAILABLE 'puissance nominale non publiée — elle ne se déduit pas de la consommation')")" \
      "$(jf_raw telemetry "$(json_object \
        "$(jf_bool available "$available")" \
        "$(jf_maybe_num outputVoltageVolts "$volts" NOT_AVAILABLE 'tension non publiée par le pilote')" \
        "$(jf_maybe_num currentAmps "$amps" NOT_AVAILABLE 'courant non publié par le pilote')" \
        "$(jf_maybe_num outputPowerWatts "$watts" NOT_AVAILABLE 'puissance non publiée par le pilote')" \
        "$(jf_str source 'SYSFS_POWER_SUPPLY')")")" \
      "$(jf_str source 'SYSFS_POWER_SUPPLY')" \
      "$(jf_str confidence 'MEDIUM')")")
  done

  printf '%s' "$units"
}

# Alimentations d'un serveur, vues par son contrôleur de gestion.
#
# `ipmitool sdr type "Power Supply"` rend une ligne par bloc :
#
#   PS1 Status | 70h | ok  | 10.1 | Presence detected
#
# Lit stdin : la sortie d'un BMC ne se rejoue pas sur une machine de test.
psu_ipmi_parse() {
  local units='' line='' label='' state='' index=0
  while IFS= read -r line; do
    case "$line" in
      *'|'*) ;;
      *) continue ;;
    esac
    label=$(printf '%s' "$line" | cut -d'|' -f1 | trim)
    state=$(printf '%s' "$line" | rev | cut -d'|' -f1 | rev | trim)
    [ -n "$label" ] || continue
    index=$((index + 1))

    local present=''
    case "$state" in
      *'Presence detected'*) present='true' ;;
      *'No Reading'* | *'Disabled'*) present='' ;;
    esac

    units=$(json_join "$units" "$(json_object \
      "$(jf_str label "$label")" \
      "$(jf_str type 'SERVER_MANAGED')" \
      "$(jf_maybe_str status "$state" NOT_AVAILABLE 'état non rendu par le contrôleur')" \
      "$(jf_maybe_bool present "$present" UNKNOWN 'présence non rendue par le contrôleur')" \
      "$(jf_raw ratedPowerWatts "$(j_unknown NOT_AVAILABLE 'puissance nominale non rendue par le contrôleur')")" \
      "$(jf_str source 'IPMI')" \
      "$(jf_str confidence 'HIGH')")")
  done
  printf '%s' "$units"
}

psu_ipmi_units() {
  has_cmd ipmitool || return 0
  [ "$CAP_PRIVILEGED" = 'true' ] || return 0

  local out=''
  out=$(LC_ALL=C run_cmd ipmitool sdr type 'Power Supply' 2>/dev/null) || return 0
  [ -n "$out" ] || return 0
  printf '%s' "$out" | psu_ipmi_parse
}

# Puissance instantanée d'un serveur, rendue par DCMI.
#
#   Instantaneous power reading:  118 Watts
psu_ipmi_power() {
  has_cmd ipmitool || return 0
  [ "$CAP_PRIVILEGED" = 'true' ] || return 0

  local watts=''
  watts=$(LC_ALL=C run_cmd ipmitool dcmi power reading 2>/dev/null |
    sed -nE 's/^[[:space:]]*Instantaneous power reading:[[:space:]]+([0-9]+).*$/\1/p' | head -n1)
  [ -n "$watts" ] || return 0

  json_object \
    "$(jf_str label 'Alimentation du serveur')" \
    "$(jf_str component 'SYSTEM')" \
    "$(jf_raw watts "$(j_num "$watts")")" \
    "$(jf_str source 'IPMI')"
}

# Puissance du processeur, mesurée par ses compteurs d'énergie.
#
# RAPL ne publie pas une puissance : il publie une énergie qui s'accumule. La
# puissance est le rapport de deux lectures à la durée qui les sépare — et cette
# durée est **mesurée**, jamais supposée égale à celle demandée : un `sleep` de
# 300 ms qui en dure 480 donnerait, sinon, une puissance surestimée de moitié.
#
# Les compteurs sont réservés à root depuis la divulgation de PLATYPUS
# (CVE-2020-8694) : sans privilège, la mesure n'a pas lieu et le rapport le dit.
psu_rapl_power() {
  local zone='' entries=''
  [ -n "${EPOCHREALTIME:-}" ] || return 0

  for zone in "$SYSFS_ROOT"/class/powercap/intel-rapl:[0-9]*; do
    [ -r "$zone/energy_uj" ] || continue
    case "$zone" in
      *:*:*) continue ;; # sous-domaines (cœurs, GPU intégré) : ils font double emploi
    esac

    local name='' first='' second='' start='' stop=''
    name=$(cat "$zone/name" 2>/dev/null || basename "$zone")
    first=$(cat "$zone/energy_uj" 2>/dev/null) || continue
    start=${EPOCHREALTIME/,/.}
    sleep 0.3 2>/dev/null || sleep 1
    second=$(cat "$zone/energy_uj" 2>/dev/null) || continue
    stop=${EPOCHREALTIME/,/.}

    [[ $first =~ ^[0-9]+$ ]] && [[ $second =~ ^[0-9]+$ ]] || continue
    # Le compteur reboucle à `max_energy_range_uj`. Une différence négative n'est
    # pas une consommation négative : c'est un tour de compteur, et la seule
    # réponse honnête est de ne rien publier pour cette passe.
    [ "$second" -ge "$first" ] || continue

    local watts='' window=''
    watts=$(LC_ALL=C awk -v a="$first" -v b="$second" -v t0="$start" -v t1="$stop" \
      'BEGIN { d = t1 - t0; if (d <= 0) exit 1; printf "%.1f", (b - a) / 1000000 / d }') || continue
    window=$(LC_ALL=C awk -v t0="$start" -v t1="$stop" 'BEGIN { printf "%d", (t1 - t0) * 1000 }')

    entries=$(json_join "$entries" "$(json_object \
      "$(jf_str label "$name")" \
      "$(jf_str component 'CPU')" \
      "$(jf_raw watts "$(j_num "$watts")")" \
      "$(jf_str source 'RAPL')" \
      "$(jf_raw windowMs "$(j_num "$window")")" \
      "$(jf_str sourcePath "$zone/energy_uj")")")
  done

  printf '%s' "$entries"
}

# Puissance des cartes graphiques, quand le pilote la publie.
psu_gpu_power() {
  local entries='' hwmon='' chip=''

  for hwmon in "$SYSFS_ROOT"/class/hwmon/hwmon*; do
    [ -r "$hwmon/power1_average" ] || continue
    chip=$(cat "$hwmon/name" 2>/dev/null || printf '')
    case "$chip" in
      amdgpu | radeon | nouveau | i915 | xe) ;;
      *) continue ;;
    esac

    local watts=''
    watts=$(psu_scale "$(cat "$hwmon/power1_average" 2>/dev/null)" 1000000 1)
    [ -n "$watts" ] || continue

    entries=$(json_join "$entries" "$(json_object \
      "$(jf_str label 'GPU')" \
      "$(jf_str component 'GPU')" \
      "$(jf_raw watts "$(j_num "$watts")")" \
      "$(jf_str source 'HWMON')" \
      "$(jf_str chip "$chip")" \
      "$(jf_str sourcePath "$hwmon/power1_average")")")
  done

  if [ "$(capability_tool nvidia-smi)" = 'true' ]; then
    local line=''
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      local watts='' model=''
      watts=$(printf '%s' "$line" | cut -d',' -f1 | trim)
      model=$(printf '%s' "$line" | cut -d',' -f2- | trim)
      [[ $watts =~ ^[0-9]+([.][0-9]+)?$ ]] || continue
      entries=$(json_join "$entries" "$(json_object \
        "$(jf_str label 'GPU')" \
        "$(jf_str component 'GPU')" \
        "$(jf_raw watts "$(j_num "$watts")")" \
        "$(jf_str source 'NVIDIA_SMI')" \
        "$(if [ -n "$model" ]; then jf_str device "$model"; fi)")")
    done < <(run_cmd nvidia-smi --query-gpu=power.draw,name --format=csv,noheader,nounits 2>/dev/null)
  fi

  printf '%s' "$entries"
}

# Puissance tirée de la batterie : la consommation réelle de la machine entière.
#
# Elle n'a de sens qu'en décharge. Sur secteur, `power_now` rend la puissance de
# **charge**, qui n'est pas la consommation du système : la publier comme telle
# ferait lire un portable en train de se recharger comme un portable gourmand.
psu_battery_power() {
  local entry='' entries=''
  for entry in "$SYSFS_ROOT"/class/power_supply/*; do
    [ -d "$entry" ] || continue
    [ "$(read_value "$entry/type" 2>/dev/null || printf '')" = 'Battery' ] || continue
    [ "$(read_value "$entry/status" 2>/dev/null || printf '')" = 'Discharging' ] || continue

    local watts=''
    watts=$(psu_scale "$(read_value "$entry/power_now" 2>/dev/null || printf '')" 1000000 1)
    [ -n "$watts" ] || continue

    entries=$(json_join "$entries" "$(json_object \
      "$(jf_str label "Décharge $(basename "$entry")")" \
      "$(jf_str component 'SYSTEM')" \
      "$(jf_raw watts "$(j_num "$watts")")" \
      "$(jf_str source 'SYSFS_POWER_SUPPLY')" \
      "$(jf_str sourcePath "$entry/power_now")")")
  done
  printf '%s' "$entries"
}

# Nature retenue pour l'ensemble, quand plusieurs unités coexistent.
#
# L'ordre n'est pas arbitraire : une machine dont le BMC gère l'alimentation est
# un serveur avant d'être un porteur de chargeur USB, et un bloc qui parle prime
# sur un bloc que le firmware se contente de décrire.
psu_overall_type() {
  local units=$1 candidate=''
  for candidate in SERVER_MANAGED DIGITAL_ATX STANDARD_ATX UPS LAPTOP_ADAPTER USB_PD; do
    case "$units" in
      *"\"type\":\"$candidate\""*)
        printf '%s' "$candidate"
        return 0
        ;;
    esac
  done
  printf 'UNKNOWN'
}

collect_power_supply() {
  local units='' rails='' component='' sources='' limitations='' digital=''
  local dmi_units='' digital_units='' digital_rails=''

  # 1. Ce que le firmware décrit.
  dmi_units=$(psu_dmi_units)
  units=$(json_join "$units" "$dmi_units")
  [ -n "$dmi_units" ] && sources=$(json_join "$sources" "$(j_str 'SMBIOS')")

  # 2. Ce que le bloc dit de lui-même.
  digital=$(psu_digital_from_hwmon)
  digital_units=${digital%%$'\t'*}
  digital_rails=${digital#*$'\t'}
  units=$(json_join "$units" "$digital_units")

  # 3. Ce qui entre dans la machine.
  local sysfs_units=''
  sysfs_units=$(psu_sysfs_units)
  units=$(json_join "$units" "$sysfs_units")
  [ -n "$sysfs_units" ] && sources=$(json_join "$sources" "$(j_str 'SYSFS_POWER_SUPPLY')")

  # 4. Ce que sait le contrôleur d'un serveur.
  local ipmi_units=''
  ipmi_units=$(psu_ipmi_units)
  units=$(json_join "$units" "$ipmi_units")
  [ -n "$ipmi_units" ] && sources=$(json_join "$sources" "$(j_str 'IPMI')")

  rails=$(json_join "$digital_rails" "$(psu_motherboard_rails)")
  [ -n "$rails" ] && sources=$(json_join "$sources" "$(j_str 'HWMON')")

  local rapl='' gpu='' battery='' ipmi_power=''
  if [ "$CAP_PRIVILEGED" = 'true' ]; then rapl=$(psu_rapl_power); fi
  gpu=$(psu_gpu_power)
  battery=$(psu_battery_power)
  ipmi_power=$(psu_ipmi_power)
  component=$(json_join "$rapl" "$gpu" "$battery" "$ipmi_power")
  [ -n "$rapl" ] && sources=$(json_join "$sources" "$(j_str 'RAPL')")
  case "$gpu" in
    *'NVIDIA_SMI'*) sources=$(json_join "$sources" "$(j_str 'NVIDIA_SMI')") ;;
  esac

  # Une alimentation est « détectée » quand elle s'est **identifiée** : un bloc
  # dont on ne connaît que la présence n'apprend rien à personne. La distinction
  # est ce qui empêche le rendu d'annoncer une découverte là où il n'y a qu'une
  # ligne de firmware vide.
  local detected='false'
  case "$units" in
    *'"manufacturer":"'* | *'"model":"'* | *'"partNumber":"'* | *'"ratedPowerWatts":'[0-9]*)
      detected='true'
      ;;
  esac

  # Ce que la collecte n'a pas pu faire. L'ordre est celui de la lecture : la
  # cause la plus englobante d'abord.
  local suggested_tool=''
  if [ -n "${CAP_VIRTUALIZED:-}" ] || [ "${CAP_DOCKER:-false}" = 'true' ]; then
    limitations=$(json_join "$limitations" "$(j_str 'VIRTUALIZED')")
  fi
  if [ "$(capability_tool dmidecode)" != 'true' ]; then
    limitations=$(json_join "$limitations" "$(j_str 'TOOL_MISSING')")
    suggested_tool='dmidecode'
  elif [ "$CAP_PRIVILEGED" != 'true' ]; then
    limitations=$(json_join "$limitations" "$(j_str 'PRIVILEGE_REQUIRED')")
  elif [ -z "$dmi_units" ]; then
    limitations=$(json_join "$limitations" "$(j_str 'SMBIOS_TYPE_39_ABSENT')")
  fi
  if [ -z "$digital_units" ]; then
    limitations=$(json_join "$limitations" "$(j_str 'NO_DIGITAL_INTERFACE')")
  fi
  if [ "$detected" = 'false' ]; then
    limitations=$(json_join "$limitations" "$(j_str 'ATX_NOT_SELF_DESCRIBING')")
  fi
  case "$rails" in
    *'"measuredBy":"MOTHERBOARD"'*)
      limitations=$(json_join "$limitations" "$(j_str 'RAILS_FROM_MOTHERBOARD')")
      ;;
  esac

  json_object \
    "$(jf_bool detected "$detected")" \
    "$(jf_str type "$(psu_overall_type "$units")")" \
    "$(jf_raw units "[$units]")" \
    "$(jf_raw rails "[$rails]")" \
    "$(jf_raw componentPower "[$component]")" \
    "$(jf_raw sources "[$sources]")" \
    "$(jf_raw limitations "[$limitations]")" \
    "$(if [ -n "$suggested_tool" ]; then jf_str suggestedTool "$suggested_tool"; fi)"
}
