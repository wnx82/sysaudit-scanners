#!/usr/bin/env bash
# Stockage : disques, partitions, santé SMART / NVMe et pools ZFS.

collect_storage() {
  log_step 'Stockage'

  local disks='' pools='' total='' used=''

  if [ "$(capability_tool lsblk)" = 'true' ]; then
    disks=$(collect_disks)
  else
    # `warning`, et non `error`, depuis le 2026-08-16 : la sévérité `error`
    # fait passer l'audit entier en « dégradé », un mot qui doit rester réservé
    # à ce qui s'est mal passé. Un paquet absent n'est pas une anomalie — c'est
    # une collecte attendue et manquée, pour une cause connue et remédiable en
    # une commande. Le rapport le dit, le motif le classe, et le statut devient
    # « partiel » : « il manque un outil » plutôt que « quelque chose a cassé ».
    record_issue 'storage' 'warning' 'lsblk absent : disques non inventoriés.' 'lsblk' 'NOT_AVAILABLE'
  fi

  # Trois technologies d'ensemble coexistent couramment sur une même machine :
  # elles sont collectées indépendamment et concaténées. `zpool` et `vgs`
  # interrogent des sous-systèmes qui peuvent mettre plusieurs secondes à
  # répondre : le résumé ne les sollicite pas.
  if depth_at_least storage standard; then
    pools=$(json_join "$(collect_zfs_pools)" "$(collect_md_arrays)")
    pools=$(json_join "$pools" "$(collect_lvm_groups)")
  else
    record_level_skip 'storage.pools' standard
  fi

  # Totaux calculés sur les systèmes de fichiers montés : ils reflètent l'espace
  # réellement utilisable, pas la capacité brute.
  if has_cmd df; then
    local df_out=''
    df_out=$(run_cmd df -B1 --output=size,used --local -x tmpfs -x devtmpfs -x overlay -x squashfs) || df_out=''
    if [ -n "$df_out" ]; then
      total=$(printf '%s' "$df_out" | awk 'NR>1 { s += $1 } END { printf "%d", s }')
      used=$(printf '%s' "$df_out" | awk 'NR>1 { s += $2 } END { printf "%d", s }')
    fi
  fi

  json_object \
    "$(jf_raw disks "[$disks]")" \
    "$(jf_raw pools "[$pools]")" \
    "$(jf_maybe_num totalBytes "$total")" \
    "$(jf_maybe_num usedBytes "$used")" \
    "$(jf_maybe_bool trimScheduled "$(detect_trim_scheduled)" NOT_AVAILABLE 'aucun gestionnaire de services interrogeable')"
}

# --- TRIM --------------------------------------------------------------------

# Le périphérique accepte-t-il les commandes de rejet de blocs ?
#
# La réponse est lue dans `queue/discard_granularity` : une granularité nulle
# signifie que le noyau ne relaiera aucun TRIM. Elle n'est **jamais** déduite du
# type de disque — un SSD derrière un contrôleur RAID peut ne rien exposer.
detect_trim_support() {
  local name=${1-} granularity=''
  granularity=$(read_value "/sys/block/$name/queue/discard_granularity" 2>/dev/null || printf '')
  [[ $granularity =~ ^[0-9]+$ ]] || return 0
  [ "$granularity" -gt 0 ] && printf 'true' || printf 'false'
}

# Un `fstrim` périodique est-il planifié ? La notion est globale : c'est un
# timer systemd, pas une propriété du matériel.
detect_trim_scheduled() {
  [ "$(capability_tool systemctl)" = 'true' ] || return 0
  case "$(run_cmd systemctl is-enabled fstrim.timer || printf '')" in
    enabled | enabled-runtime | static) printf 'true' ;;
    disabled | masked) printf 'false' ;;
    *) : ;;
  esac
}

# --- RAID logiciel -----------------------------------------------------------

# Ensembles md (RAID logiciel Linux), lus dans /proc/mdstat.
#
# `/proc/mdstat` est lisible sans privilège et sans `mdadm` installé, ce qui en
# fait la source la plus largement disponible.
collect_md_arrays() {
  [ -r /proc/mdstat ] || return 0

  local arrays='' line='' name='' level='' state='' members='' size=''
  while IFS= read -r line; do
    case "$line" in
      md[0-9]*)
        name=$(printf '%s' "$line" | awk -F' : ' '{print $1}')
        state=$(printf '%s' "$line" | awk -F' : ' '{print $2}' | awk '{print $1}')
        level=$(printf '%s' "$line" | grep -oE 'raid[0-9]+|linear|multipath|faulty' | head -n1)

        members=''
        local member=''
        for member in $(printf '%s' "$line" | grep -oE '[a-z]+[0-9]*\[[0-9]+\]' | sed 's/\[[0-9]*\]//'); do
          members=$(json_join "$members" "$(j_str "/dev/$member")")
        done

        size=$(read_value "/sys/block/$name/size" 2>/dev/null || printf '')
        [[ $size =~ ^[0-9]+$ ]] && size=$((size * 512)) || size=''

        arrays=$(json_join "$arrays" "$(json_object \
          "$(jf_str name "$name")" \
          "$(jf_str type 'md')" \
          "$(jf_maybe_str state "$state")" \
          "$(jf_maybe_num sizeBytes "$size")" \
          "$(jf_raw usedBytes "$(j_unknown UNSUPPORTED 'un ensemble md ne rapporte pas d’occupation')")" \
          "$(jf_raw members "[$members]")" \
          "$(jf_maybe_str raidLevel "$level")" \
          "$(jf_maybe_bool redundant "$(raid_level_redundant "$level")" UNKNOWN 'niveau RAID non reconnu')")")
        ;;
    esac
  done </proc/mdstat

  printf '%s' "$arrays"
}

# Un niveau RAID tolère-t-il la perte d'un membre ?
#
# Uniquement sur un niveau **reconnu**. Un niveau inconnu ne donne rien : mieux
# vaut ne rien dire que d'affirmer à tort qu'un ensemble est protégé.
raid_level_redundant() {
  case "${1-}" in
    raid1 | raid4 | raid5 | raid6 | raid10 | mirror | raidz | raidz1 | raidz2 | raidz3)
      printf 'true'
      ;;
    raid0 | linear | stripe | faulty) printf 'false' ;;
    *) : ;;
  esac
}

# --- LVM ---------------------------------------------------------------------

# Groupes de volumes LVM. `vgs` exige des privilèges : sans eux, la section
# reste absente avec sa raison plutôt que vide.
collect_lvm_groups() {
  has_cmd vgs || return 0
  if [ "$CAP_PRIVILEGED" != 'true' ]; then
    record_issue 'storage.lvm' 'warning' \
      'Groupes LVM non collectés : lecture réservée à root.' 'vgs' 'PERMISSION_DENIED'
    return 0
  fi

  local groups='' name='' size='' free='' used='' members=''
  while IFS=$'\t' read -r name size free; do
    [ -z "$name" ] && continue

    used=''
    if [[ $size =~ ^[0-9]+$ ]] && [[ $free =~ ^[0-9]+$ ]]; then
      used=$((size - free))
    fi

    members=''
    local pv=''
    while IFS= read -r pv; do
      [ -z "$pv" ] && continue
      members=$(json_join "$members" "$(j_str "$pv")")
    done < <(run_cmd pvs --noheadings -o pv_name --select "vg_name=$name" | awk '{print $1}')

    groups=$(json_join "$groups" "$(json_object \
      "$(jf_str name "$name")" \
      "$(jf_str type 'lvm')" \
      "$(jf_raw state "$(j_unknown UNSUPPORTED 'LVM ne rapporte pas d’état de santé')")" \
      "$(jf_maybe_num sizeBytes "$size")" \
      "$(jf_maybe_num usedBytes "$used")" \
      "$(jf_raw members "[$members]")" \
      "$(jf_raw redundant "$(j_unknown UNSUPPORTED 'LVM ne porte pas de niveau RAID par lui-même')")")")
  done < <(run_cmd vgs --noheadings --units b --nosuffix -o vg_name,vg_size,vg_free |
    awk '{ printf "%s\t%s\t%s\n", $1, $2, $3 }')

  printf '%s' "$groups"
}

collect_disks() {
  local disks='' name=''
  # -d : disques uniquement (les partitions sont récupérées séparément).
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    disks=$(json_join "$disks" "$(collect_disk "$name")")
  done < <(run_cmd lsblk -dn -o NAME,TYPE | awk '$2 == "disk" { print $1 }')

  printf '%s' "$disks"
}

collect_disk() {
  local name=$1 device="/dev/$1"
  local model='' serial='' size='' rotational='' removable='' kind='' interface='' firmware='' ptable='' vendor=''
  local media_type='' bus_type='' protocol=''

  model=$(read_value "/sys/block/$name/device/model" || printf '')
  vendor=$(read_value "/sys/block/$name/device/vendor" || printf '')
  size=$(read_value "/sys/block/$name/size" || printf '')
  # /sys/block/*/size est exprimé en secteurs de 512 octets par convention.
  [ -n "$size" ] && size=$((size * 512))
  rotational=$(read_value "/sys/block/$name/queue/rotational" || printf '')
  removable=$(read_value "/sys/block/$name/removable" || printf '')

  # Nature du support : `queue/rotational` est la seule source qui la connaisse,
  # et un fichier illisible ne vaut pas « à mémoire flash ». L'ancien code
  # concluait `SSD` dès que la lecture échouait — conclure d'une donnée absente,
  # ce que ce dépôt s'interdit.
  case "$rotational" in
    1) media_type='HDD' ;;
    0) media_type='SSD' ;;
    *) media_type='' ;;
  esac

  case "$name" in
    nvme*)
      bus_type='NVME'
      interface='nvme'
      # Seul cas où le jeu de commandes est certain sans interroger le
      # périphérique : le nom du nœud le nomme.
      protocol='NVMe'
      ;;
    sd*)
      interface=$(detect_disk_interface "$name")
      case "$interface" in
        usb) bus_type='USB' ;;
        sata) bus_type='SATA' ;;
        scsi) bus_type='SCSI' ;;
        nvme) bus_type='NVME' ;;
        *) bus_type='' ;;
      esac
      ;;
    vd* | xvd*) bus_type='VIRTUAL'; interface='virtio' ;;
    mmcblk*) bus_type='MMC'; interface='mmc' ;;
    *) bus_type='' ;;
  esac

  kind=$(disk_kind_from_facts "$media_type" "$bus_type" "$removable")

  local removable_json='false'
  [ "$removable" = '1' ] && removable_json='true'

  ptable=$(run_cmd lsblk -dn -o PTTYPE "$device" | trim)
  case "$(printf '%s' "$ptable" | tr '[:lower:]' '[:upper:]')" in
    GPT) ptable='GPT' ;;
    DOS | MBR) ptable='MBR' ;;
    *) ptable='UNKNOWN' ;;
  esac

  local smart_json=''
  smart_json=$(collect_smart "$device" "$kind" "$model")
  [ -n "$smart_json" ] && smart_json=$(jf_raw smart "$smart_json")
  local link_json=''
  link_json=$(storage_link_for_disk "$name")
  [ -n "$link_json" ] && link_json=$(jf_raw link "$link_json")

  # Le firmware et le numéro de série ne sont lisibles qu'avec smartctl et des
  # privilèges ; sans eux ils restent inconnus.
  if depth_at_least storage standard &&
    [ "$(capability_tool smartctl)" = 'true' ] && [ "$CAP_PRIVILEGED" = 'true' ]; then
    local info=''
    info=$(LC_ALL=C run_cmd smartctl -i "$device") || info=''
    firmware=$(printf '%s' "$info" | sed -nE 's/^Firmware Version:[[:space:]]+(.*)$/\1/p' | head -n1)
    serial=$(printf '%s' "$info" | sed -nE 's/^Serial [Nn]umber:[[:space:]]+(.*)$/\1/p' | head -n1)
  fi

  json_object \
    "$(jf_str device "$device")" \
    "$(jf_maybe_str manufacturer "$vendor" NOT_AVAILABLE 'constructeur non exposé par le contrôleur')" \
    "$(jf_maybe_str model "$model")" \
    "$(jf_maybe_str serialNumber "$(anon serialNumber "$serial")" "$(smart_reason)" "$(smart_detail)")" \
    "$(jf_maybe_str wwn "$(anon serialNumber "$(disk_wwn "$name")")" NOT_AVAILABLE 'aucun WWN publié par le contrôleur')" \
    "$(jf_maybe_str nguid "$(anon serialNumber "$(disk_namespace_id "$name" nguid)")" NOT_AVAILABLE 'sans objet hors NVMe')" \
    "$(jf_maybe_str eui64 "$(anon serialNumber "$(disk_namespace_id "$name" eui)")" NOT_AVAILABLE 'sans objet hors NVMe')" \
    "$(jf_maybe_str firmware "$firmware" "$(smart_reason)" "$(smart_detail)")" \
    "$(jf_maybe_num sizeBytes "$size")" \
    "$(jf_str kind "$kind")" \
    "$(jf_maybe_str mediaType "$media_type" NOT_AVAILABLE 'queue/rotational non lisible')" \
    "$(jf_maybe_str busType "$bus_type" NOT_AVAILABLE 'bus non déductible du chemin sysfs')" \
    "$(jf_maybe_str protocol "$protocol" NOT_AVAILABLE 'jeu de commandes non interrogé')" \
    "$(jf_maybe_str interface "$interface")" \
    "$(jf_maybe_num rotationRpm '' UNSUPPORTED 'vitesse de rotation non exposée')" \
    "$(jf_str partitionTable "$ptable")" \
    "$(jf_raw removable "$removable_json")" \
    "$(jf_maybe_bool trimSupported "$(detect_trim_support "$name")" NOT_AVAILABLE 'granularité de rejet non exposée par le noyau')" \
    "$link_json" \
    "$smart_json" \
    "$(jf_raw partitions "$(collect_partitions "$name")")"
}

# World Wide Name du support.
#
# Contrairement au numéro de série, il ne demande ni `smartctl` ni privilège :
# le noyau le publie dès qu'il l'a lu du contrôleur. Sur une machine auditée
# sans root — le cas courant —, c'est donc le seul identifiant de disque que le
# rapport puisse porter.
disk_wwn() {
  local name=${1-} value=''
  value=$(run_cmd lsblk -dn -o WWN "/dev/$name" | head -n1 | trim) || value=''
  [ -n "$value" ] || value=$(read_value "/sys/block/$name/wwid" 2>/dev/null || printf '')
  reject_null_identifier "$value"
}

# Identifiant d'espace de noms NVMe (`nguid` ou `eui`).
#
# Le fichier existe aussi sur les contrôleurs qui ne renseignent pas le champ :
# il rend alors une suite de zéros, qui n'est pas un identifiant.
disk_namespace_id() {
  local name=${1-} kind=${2-} value=''
  value=$(read_value "/sys/block/$name/$kind" 2>/dev/null || printf '')
  reject_null_identifier "$value"
}

# Un identifiant tout à zéro est un champ laissé vide par le firmware. Le
# publier ferait passer deux disques distincts pour le même exemplaire.
reject_null_identifier() {
  local value=${1-}
  [ -n "$value" ] || return 0
  # Le tiret reste en dernier : place ailleurs, `tr` lit « :- » comme un
  # intervalle de caractères et refuse la liste.
  case "$(printf '%s' "$value" | tr -d '0x.: -')" in
    '') return 0 ;;
  esac
  printf '%s' "$value"
}

# Catégorie historique d'un disque, dérivée des faits séparés.
#
# `kind` mélange support, bus et protocole dans un seul champ. Il est conservé
# parce que tout le rendu s'y appuie, mais il n'est plus deviné : il se déduit
# de `media_type` et `bus_type`, qui viennent chacun de leur source.
#
# Un disque dont le bus est connu mais le support inconnu ne devient jamais
# `HDD` : il reste `UNKNOWN`. Une lacune visible vaut mieux qu'une erreur
# invisible.
#
# $1 support, $2 bus, $3 indicateur amovible
disk_kind_from_facts() {
  local media=${1-} bus=${2-} removable=${3-}

  # Un NVMe est d'abord un NVMe : ils sont tous à mémoire flash, et c'est ce
  # que le lecteur cherche en premier. L'amovibilité ne le change pas.
  [ "$bus" = 'NVME' ] && { printf 'NVME'; return 0; }
  [ "$bus" = 'VIRTUAL' ] && { printf 'VIRTUAL'; return 0; }
  [ "$removable" = '1' ] && [ "$bus" = 'USB' ] && { printf 'USB'; return 0; }
  [ "$media" = 'SSD' ] && { printf 'SSD'; return 0; }
  [ "$media" = 'HDD' ] && { printf 'HDD'; return 0; }
  [ "$bus" = 'USB' ] && { printf 'USB'; return 0; }
  case "$bus" in
    SD | MMC) printf 'SD'; return 0 ;;
    SAS) printf 'SAS'; return 0 ;;
  esac
  printf 'UNKNOWN'
}

detect_disk_interface() {
  local name=$1 path=''
  path=$(readlink -f "/sys/block/$name" 2>/dev/null) || return 0
  case "$path" in
    *usb*) printf 'usb' ;;
    *ata*) printf 'sata' ;;
    *nvme*) printf 'nvme' ;;
    *scsi*) printf 'scsi' ;;
    *) printf '' ;;
  esac
}

storage_link_for_disk() {
  local name=${1-}
  local dir="/sys/block/$name/device"
  [ -d "$dir" ] || return 0
  pcie_link_from_dir "$dir"
}

smart_reason() {
  if ! depth_at_least storage standard; then
    printf 'NOT_COLLECTED'
  elif [ "$(capability_tool smartctl)" != 'true' ]; then
    printf 'NOT_AVAILABLE'
  elif [ "$CAP_PRIVILEGED" != 'true' ]; then
    printf 'PERMISSION_DENIED'
  else
    printf 'UNKNOWN'
  fi
}

smart_detail() {
  if ! depth_at_least storage standard; then
    printf 'collecté au niveau Normale'
  elif [ "$(capability_tool smartctl)" != 'true' ]; then
    printf 'smartctl absent (paquet smartmontools)'
  elif [ "$CAP_PRIVILEGED" != 'true' ]; then
    printf 'lecture SMART réservée à root'
  fi
}

# Le même embranchement, rendu en motif lisible par la plateforme. Voir
# `dmi_reason` dans system.sh : la phrase et le motif se décident ensemble.
smart_reason() {
  if ! depth_at_least storage standard; then
    printf 'NOT_COLLECTED'
  elif [ "$(capability_tool smartctl)" != 'true' ]; then
    printf 'NOT_AVAILABLE'
  elif [ "$CAP_PRIVILEGED" != 'true' ]; then
    printf 'PERMISSION_DENIED'
  fi
}

collect_partitions() {
  local disk=$1 parts=''
  while IFS='|' read -r name mount fstype size used avail; do
    [ -z "$name" ] && continue
    local pct=''
    if [ -n "$size" ] && [ -n "$used" ] && [ "$size" -gt 0 ] 2>/dev/null; then
      pct=$(awk -v u="$used" -v s="$size" 'BEGIN { printf "%.1f", (u / s) * 100 }')
    fi

    local encrypted='false'
    [ -n "$(run_cmd lsblk -no FSTYPE "/dev/$name" | grep -i crypto_LUKS)" ] && encrypted='true'

    # Les deux identifiants sont demandés séparément : en une seule interrogation,
    # une colonne vide disparaîtrait de la ligne et décalerait la suivante.
    local fs_uuid='' part_uuid=''
    fs_uuid=$(run_cmd lsblk -dno UUID "/dev/$name" | head -n1 | trim) || fs_uuid=''
    part_uuid=$(run_cmd lsblk -dno PARTUUID "/dev/$name" | head -n1 | trim) || part_uuid=''

    parts=$(json_join "$parts" "$(json_object \
      "$(jf_str name "/dev/$name")" \
      "$(jf_maybe_str uuid "$(anon uuid "$fs_uuid")" NOT_AVAILABLE 'partition sans système de fichiers identifié')" \
      "$(jf_maybe_str partitionUuid "$(anon uuid "$part_uuid")" NOT_AVAILABLE 'table de partitions sans identifiants (MBR)')" \
      "$(jf_maybe_str mountPoint "$mount" NOT_AVAILABLE 'partition non montée')" \
      "$(jf_maybe_str filesystem "$fstype")" \
      "$(jf_maybe_num sizeBytes "$size")" \
      "$(jf_maybe_num usedBytes "$used" NOT_AVAILABLE 'partition non montée')" \
      "$(jf_maybe_num freeBytes "$avail" NOT_AVAILABLE 'partition non montée')" \
      "$(jf_maybe_num usagePercent "$pct" NOT_AVAILABLE 'partition non montée')" \
      "$(jf_raw encrypted "$encrypted")" \
      "$(jf_raw encryptionType "$([ "$encrypted" = 'true' ] && j_str 'LUKS' || j_unknown UNSUPPORTED)")")")
  done < <(run_cmd lsblk -bnrp -o NAME,MOUNTPOINT,FSTYPE,FSSIZE,FSUSED,FSAVAIL "/dev/$disk" |
    awk 'NR>1 { printf "%s|%s|%s|%s|%s|%s\n", substr($1,6), $2, $3, $4, $5, $6 }')

  printf '[%s]' "$parts"
}

# Santé SMART / NVMe. Chaque compteur non lu reste inconnu : le remplacer par 0
# ferait passer un disque non mesuré pour un disque sain.
collect_smart() {
  local device=$1 kind=$2 model=${3-}

  # Interroger SMART coûte un aller-retour par disque, plusieurs secondes sur
  # un disque en veille : le niveau Rapide s'en abstient. Le dire explicitement
  # évite de lire « santé inconnue » comme un disque qui refuse de répondre.
  if ! depth_at_least storage standard; then
    record_level_skip 'storage.smart' standard
    return 0
  fi

  if [ "$(capability_tool smartctl)" != 'true' ] || [ "$CAP_PRIVILEGED" != 'true' ]; then
    record_issue 'storage.smart' 'warning' \
      "Santé de $device non collectée ($(smart_detail))." 'smartctl' "$(smart_reason)"
    return 0
  fi

  local out=''
  # smartctl retourne un code non nul dès qu'un bit d'état est levé (disque en
  # échec), ce qui est précisément le cas qui nous intéresse : on ignore donc le
  # code de retour et on analyse la sortie.
  out=$(LC_ALL=C timeout -k 2 "${SYSAUDIT_CMD_TIMEOUT:-15}" smartctl -A -H "$device" 2>/dev/null || true)
  [ -z "$out" ] && return 0

  local status='' temp='' hours='' cycles='' realloc='' pending='' uncorrect=''
  local nvme_used='' spare='' spare_threshold='' media_errors='' unsafe_shutdowns='' read_units='' written='' wear=''

  case "$out" in
    *'SMART overall-health self-assessment test result: PASSED'*) status='PASSED' ;;
    *'SMART overall-health self-assessment test result: FAILED'*) status='FAILED' ;;
    *'SMART Health Status: OK'*) status='PASSED' ;;
    *'SMART/Health Information'*) status='PASSED' ;;
  esac

  if [ "$kind" = 'NVME' ]; then
    temp=$(printf '%s' "$out" | sed -nE 's/^Temperature:[[:space:]]+([0-9]+) Celsius.*$/\1/p' | head -n1)
    hours=$(printf '%s' "$out" | sed -nE 's/^Power On Hours:[[:space:]]+([0-9,]+).*$/\1/p' | head -n1 | tr -d ',')
    cycles=$(printf '%s' "$out" | sed -nE 's/^Power Cycles:[[:space:]]+([0-9,]+).*$/\1/p' | head -n1 | tr -d ',')
    nvme_used=$(printf '%s' "$out" | sed -nE 's/^Percentage Used:[[:space:]]+([0-9]+)%.*$/\1/p' | head -n1)
    spare=$(printf '%s' "$out" | sed -nE 's/^Available Spare:[[:space:]]+([0-9]+)%.*$/\1/p' | head -n1)
    spare_threshold=$(printf '%s' "$out" | sed -nE 's/^Available Spare Threshold:[[:space:]]+([0-9]+)%.*$/\1/p' | head -n1)
    media_errors=$(printf '%s' "$out" | sed -nE 's/^Media and Data Integrity Errors:[[:space:]]+([0-9,]+).*$/\1/p' | head -n1 | tr -d ',')
    unsafe_shutdowns=$(printf '%s' "$out" | sed -nE 's/^Unsafe Shutdowns:[[:space:]]+([0-9,]+).*$/\1/p' | head -n1 | tr -d ',')
    read_units=$(printf '%s' "$out" | sed -nE 's/^Data Units Read:[[:space:]]+([0-9,]+).*$/\1/p' | head -n1 | tr -d ',')
    written=$(printf '%s' "$out" | sed -nE 's/^Data Units Written:[[:space:]]+([0-9,]+).*$/\1/p' | head -n1 | tr -d ',')
  else
    temp=$(smart_attribute "$out" 'Temperature_Celsius')
    [ -z "$temp" ] && temp=$(smart_attribute "$out" 'Airflow_Temperature_Cel')
    hours=$(smart_attribute "$out" 'Power_On_Hours')
    cycles=$(smart_attribute "$out" 'Power_Cycle_Count')
    realloc=$(smart_attribute "$out" 'Reallocated_Sector_Ct')
    pending=$(smart_attribute "$out" 'Current_Pending_Sector')
    uncorrect=$(smart_attribute "$out" 'Offline_Uncorrectable')
    # L'usure d'un SSD ATA se lit dans un attribut normalisé qui compte à
    # rebours depuis 100. La consommée est donc le complément — pas une
    # estimation, une soustraction sur une valeur publiée par le disque.
    local remaining=''
    remaining=$(smart_attribute_value "$out" 'Media_Wearout_Indicator')
    [ -z "$remaining" ] && remaining=$(smart_attribute_value "$out" 'SSD_Life_Left')
    [ -z "$remaining" ] && remaining=$(smart_attribute_value "$out" 'Percent_Lifetime_Remain')
    if [ -n "$remaining" ] && [ "$remaining" -ge 0 ] 2>/dev/null && [ "$remaining" -le 100 ]; then
      wear=$((100 - remaining))
    fi
  fi

  # La température part aussi vers la section capteurs, où elle rejoint le
  # processeur et la carte mère sous un même toit.
  #
  # Elle n'est pas relue là-bas : rappeler `smartctl` sur chaque disque coûterait
  # plusieurs secondes et pourrait rendre une seconde valeur, différente de
  # celle-ci, pour un même capteur. La catégorie vient du type réel du disque,
  # jamais d'une supposition sur le modèle — c'est elle qui décide du seuil, et
  # cinquante degrés ne se lisent pas pareil sur un plateau et sur un NVMe.
  if [ -n "$temp" ]; then
    local thermal_category=''
    case "$kind" in
      NVME) thermal_category='DRIVE_NVME' ;;
      SSD) thermal_category='DRIVE_SSD' ;;
      HDD) thermal_category='DRIVE_HDD' ;;
      # USB, SD, VIRTUAL, UNKNOWN : le support réel est inconnu derrière ces
      # interfaces. Aucun seuil ne leur est appliqué plutôt qu'un seuil au juger.
      *) thermal_category='OTHER' ;;
    esac
    record_thermal_reading \
      "$([ "$kind" = 'NVME' ] && printf 'Composite' || printf 'Température du disque')" \
      "$temp" "$thermal_category" "${model:-$device}" \
      "$([ "$kind" = 'NVME' ] && printf 'NVMe SMART' || printf 'smartctl')"
  fi

  # La table brute des attributs est volumineuse — une trentaine de lignes par
  # disque — et n'a d'intérêt que pour comparer deux audits dans le détail :
  # elle est réservée à la collecte approfondie.
  local attributes=''
  if depth_at_least storage extended; then
    attributes=$(collect_smart_attributes "$out")
  else
    record_level_skip 'storage.smart.attributes' full
  fi

  json_object \
    "$(jf_maybe_str status "$status" UNKNOWN 'verdict SMART non exposé')" \
    "$(jf_maybe_num temperatureCelsius "$temp" NOT_AVAILABLE)" \
    "$(jf_maybe_num powerOnHours "$hours" NOT_AVAILABLE)" \
    "$(jf_maybe_num powerCycles "$cycles" NOT_AVAILABLE)" \
    "$(jf_maybe_num reallocatedSectors "$realloc" "$([ "$kind" = 'NVME' ] && printf UNSUPPORTED || printf NOT_AVAILABLE)" "$([ "$kind" = 'NVME' ] && printf 'attribut ATA sans équivalent NVMe')")" \
    "$(jf_maybe_num pendingSectors "$pending" "$([ "$kind" = 'NVME' ] && printf UNSUPPORTED || printf NOT_AVAILABLE)")" \
    "$(jf_maybe_num uncorrectableErrors "$uncorrect" "$([ "$kind" = 'NVME' ] && printf UNSUPPORTED || printf NOT_AVAILABLE)")" \
    "$(jf_maybe_num wearPercent "$wear" NOT_AVAILABLE 'usure non exposée par ce disque')" \
    "$(jf_maybe_num nvmePercentageUsed "$nvme_used" "$([ "$kind" = 'NVME' ] && printf NOT_AVAILABLE || printf UNSUPPORTED)")" \
    "$(jf_maybe_num availableSparePercent "$spare" "$([ "$kind" = 'NVME' ] && printf NOT_AVAILABLE || printf UNSUPPORTED)")" \
    "$(jf_maybe_num availableSpareThresholdPercent "$spare_threshold" "$([ "$kind" = 'NVME' ] && printf NOT_AVAILABLE || printf UNSUPPORTED)")" \
    "$(jf_maybe_num mediaErrors "$media_errors" "$([ "$kind" = 'NVME' ] && printf NOT_AVAILABLE || printf UNSUPPORTED)")" \
    "$(jf_maybe_num unsafeShutdowns "$unsafe_shutdowns" "$([ "$kind" = 'NVME' ] && printf NOT_AVAILABLE || printf UNSUPPORTED)")" \
    "$(jf_maybe_num dataUnitsRead "$read_units" "$([ "$kind" = 'NVME' ] && printf NOT_AVAILABLE || printf UNSUPPORTED)")" \
    "$(jf_maybe_num dataUnitsWritten "$written" "$([ "$kind" = 'NVME' ] && printf NOT_AVAILABLE || printf UNSUPPORTED)")" \
    "$(if [ -n "$attributes" ]; then jf_raw attributes "[$attributes]"; fi)"
}

# Table SMART complète, conservée telle que le disque la publie.
#
# Les sept compteurs promus en champs nommés ne couvrent qu'une partie de ce
# qu'un disque expose : le reste — CRC UDMA, secteurs relogés en attente,
# heures de tête chargée — n'a pas de champ dédié et disparaissait. Le garder
# brut permet de comparer deux audits de la même machine sur des attributs que
# le schéma n'a pas anticipés.
#
# Rien n'est interprété ici : `value` est la colonne normalisée du disque,
# `raw` sa valeur brute, telles quelles.
collect_smart_attributes() {
  local out=$1
  printf '%s' "$out" | awk '
    # La table ATA commence après cet en-tête et se termine à la première ligne
    # vide. S’en tenir à ce bloc évite de prendre pour un attribut une ligne de
    # journal d’erreurs qui commencerait, elle aussi, par un nombre.
    /^ID# +ATTRIBUTE_NAME/ { inside = 1; next }
    inside && /^[[:space:]]*$/ { inside = 0 }
    inside && $1 ~ /^[0-9]+$/ && $2 != "" {
      raw = ""
      for (i = 10; i <= NF; i++) raw = raw (raw == "" ? "" : " ") $i
      gsub(/"/, "", raw)
      gsub(/\\/, "", raw)
      printf "%s{\"id\":%d,\"name\":\"%s\",\"value\":%d,\"raw\":\"%s\"}",
        (count++ ? "," : ""), $1, $2, $4, raw
    }
  '
}

# Valeur normalisée (colonne VALUE) d'un attribut SMART ATA, par opposition à
# sa valeur brute. Les indicateurs d'usure ne sont lisibles que là : leur RAW
# porte souvent un compteur de blocs sans rapport avec un pourcentage.
smart_attribute_value() {
  local out=$1 name=$2
  printf '%s' "$out" | awk -v n="$name" '$2 == n { print $4 + 0 }' | head -n1
}

# Extrait la valeur brute (RAW_VALUE) d'un attribut SMART ATA.
smart_attribute() {
  local out=$1 name=$2 raw=''
  raw=$(printf '%s' "$out" | awk -v n="$name" '$2 == n { print $10 }' | head -n1)
  # Certains attributs rapportent « 35 (Min/Max 20/45) » : seul l'entier initial
  # est retenu, le reste étant du contexte non normalisé.
  printf '%s' "$raw" | sed -nE 's/^([0-9]+).*$/\1/p'
}

collect_zfs_pools() {
  has_cmd zpool || return 0
  [ "$CAP_PRIVILEGED" = 'true' ] || return 0

  local pools=''
  while IFS=$'\t' read -r name size alloc health; do
    [ -z "$name" ] && continue
    pools=$(json_join "$pools" "$(json_object \
      "$(jf_str name "$name")" \
      "$(jf_str type zfs)" \
      "$(jf_maybe_str state "$health")" \
      "$(jf_maybe_num sizeBytes "$size")" \
      "$(jf_maybe_num usedBytes "$alloc")" \
      "$(jf_raw members '[]')" \
      "$(jf_maybe_str raidLevel "$(zfs_pool_level "$name")" UNKNOWN 'topologie du pool non lisible')" \
      "$(jf_maybe_bool redundant "$(raid_level_redundant "$(zfs_pool_level "$name")")" UNKNOWN 'topologie du pool non lisible')")")
  done < <(run_cmd zpool list -Hp -o name,size,alloc,health || true)

  printf '%s' "$pools"
}

# Topologie d'un pool ZFS, lue dans sa configuration : `mirror`, `raidz`,
# `raidz2`… Un pool sans ligne de topologie est un simple agrégat de disques,
# donc sans redondance — mais cela se lit, ne se suppose pas.
zfs_pool_level() {
  local name=${1-} status=''
  status=$(run_cmd zpool status "$name") || return 0
  printf '%s' "$status" | grep -oE '^[[:space:]]+(mirror|raidz[0-9]?)' | head -n1 | trim
}
