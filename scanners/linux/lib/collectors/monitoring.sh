#!/usr/bin/env bash
# Série temporelle : observation de la machine dans la durée.
#
# Un audit reste par défaut un **instantané**. Cette collecte est demandée
# explicitement (`--monitor <secondes>`), parce qu'elle rallonge le scan
# d'autant : personne ne doit attendre une minute sans l'avoir voulu.
#
# Tout est lu dans /proc et /sys, sans privilège ni outil.

# Relevé brut des compteurs cumulés, sur une seule ligne :
#   cpu_total cpu_idle mem_used swap_used disk_read disk_write net_rx net_tx
#
# Ces compteurs n'ont de sens que comparés à un relevé précédent : c'est de leur
# différence que naissent les taux publiés.
monitoring_raw_sample() {
  local cpu_total='' cpu_idle='' mem_used='' swap_used=''
  local disk_read='' disk_write='' net_rx='' net_tx=''

  if [ -r /proc/stat ]; then
    read -r cpu_total cpu_idle < <(
      awk '/^cpu / { print $2+$3+$4+$5+$6+$7+$8, $5; exit }' /proc/stat 2>/dev/null
    ) || true
  fi

  if [ -r /proc/meminfo ]; then
    mem_used=$(awk '
      /^MemTotal:/ { total = $2 }
      /^MemAvailable:/ { available = $2 }
      END { if (total > 0 && available != "") print (total - available) * 1024 }
    ' /proc/meminfo 2>/dev/null)
    swap_used=$(awk '
      /^SwapTotal:/ { total = $2 }
      /^SwapFree:/ { free = $2 }
      END { if (total != "" && free != "") print (total - free) * 1024 }
    ' /proc/meminfo 2>/dev/null)
  fi

  # Colonnes 6 et 10 de /proc/diskstats : secteurs lus et écrits, en secteurs de
  # 512 octets. Les périphériques virtuels (loop, ram) sont écartés : ils
  # comptabiliseraient deux fois les mêmes entrées-sorties.
  if [ -r /proc/diskstats ]; then
    read -r disk_read disk_write < <(
      awk '$3 !~ /^(loop|ram|dm-|zram)/ { r += $6; w += $10 } END { print r * 512, w * 512 }' \
        /proc/diskstats 2>/dev/null
    ) || true
  fi

  local iface=''
  net_rx=0
  net_tx=0
  for iface in /sys/class/net/*; do
    [ -d "$iface" ] || continue
    # La boucle locale ne décrit aucun trafic réel.
    [ "$(basename "$iface")" = 'lo' ] && continue
    net_rx=$((net_rx + $(cat "$iface/statistics/rx_bytes" 2>/dev/null || printf '0')))
    net_tx=$((net_tx + $(cat "$iface/statistics/tx_bytes" 2>/dev/null || printf '0')))
  done

  printf '%s %s %s %s %s %s %s %s' \
    "${cpu_total:-}" "${cpu_idle:-}" "${mem_used:-}" "${swap_used:-}" \
    "${disk_read:-}" "${disk_write:-}" "$net_rx" "$net_tx"
}

# Taux par seconde entre deux compteurs cumulés.
# Retourne une chaîne vide plutôt qu'un zéro si l'un des relevés manque, ou si
# le compteur a reculé — ce qui arrive après une remise à zéro du noyau.
monitoring_rate() {
  local before=${1-} after=${2-} seconds=${3-}
  [[ $before =~ ^[0-9]+$ ]] && [[ $after =~ ^[0-9]+$ ]] || return 0
  [ "$after" -ge "$before" ] || return 0
  awk -v d="$((after - before))" -v s="$seconds" 'BEGIN { if (s > 0) printf "%.0f", d / s }'
}

# Occupation CPU entre deux relevés de /proc/stat, en pourcentage.
monitoring_cpu_usage() {
  local total_before=${1-} idle_before=${2-} total_after=${3-} idle_after=${4-}
  [[ $total_before =~ ^[0-9]+$ ]] && [[ $total_after =~ ^[0-9]+$ ]] || return 0
  [[ $idle_before =~ ^[0-9]+$ ]] && [[ $idle_after =~ ^[0-9]+$ ]] || return 0

  awk -v tb="$total_before" -v ib="$idle_before" -v ta="$total_after" -v ia="$idle_after" 'BEGIN {
    dt = ta - tb; di = ia - ib;
    if (dt <= 0) exit;
    usage = (1 - di / dt) * 100;
    if (usage < 0) usage = 0;
    if (usage > 100) usage = 100;
    printf "%.1f", usage
  }'
}

# Fréquence effective moyenne des cœurs, en MHz.
#
# `scaling_cur_freq` est la source de premier choix : c'est ce que le noyau
# rapporte réellement. `/proc/cpuinfo` sert de repli sur les architectures qui
# n'exposent pas `cpufreq` — un conteneur, une machine virtuelle.
monitoring_cpu_frequency_mhz() {
  local sum=0 count=0 khz='' file=''
  for file in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq; do
    [ -r "$file" ] || continue
    khz=$(cat "$file" 2>/dev/null || true)
    [[ $khz =~ ^[0-9]+$ ]] || continue
    sum=$((sum + khz))
    count=$((count + 1))
  done

  if [ "$count" -gt 0 ]; then
    awk -v s="$sum" -v c="$count" 'BEGIN { printf "%.0f", s / c / 1000 }'
    return 0
  fi

  [ -r /proc/cpuinfo ] || return 0
  awk '/^cpu MHz/ { sum += $4; count++ } END { if (count > 0) printf "%.0f", sum / count }' \
    /proc/cpuinfo 2>/dev/null
}

# --- Relevés cœur par cœur ---------------------------------------------------
#
# La moyenne de `monitoring_cpu_frequency_mhz` répond « le processeur tourne à
# 3,1 GHz ». Sur une architecture hybride — cœurs performants et cœurs
# efficients —, elle ne décrit **aucun cœur réel** : deux cœurs à 4,9 GHz et
# quatorze à 2,8 GHz donnent la même moyenne que seize cœurs à 3,1, et les deux
# machines ne se comportent pas pareil.
#
# Ces relevés coûtent une lecture par cœur et par seconde. Ils ne sont donc pris
# que pendant une charge, et seulement en deçà d'un nombre de cœurs raisonnable :
# au-delà, la série pèserait plus que tout le reste du rapport, pour un
# graphique que personne ne peut lire.

# Au-delà de ce nombre de cœurs, le relevé cœur par cœur n'est pas pris.
#
# La borne du schéma est à 512 ; celle-ci est plus basse et vise le poids du
# rapport : 128 cœurs × 600 relevés × deux grandeurs font 153 600 nombres pour
# une seule charge soutenue. Un rapport qu'on ne peut plus téléverser ne
# diagnostique rien.
: "${SYSAUDIT_CORE_SERIES_MAX:=128}"

# Budget total de valeurs relevées cœur par cœur, sur toute la durée d'un banc
# d'essai.
#
# Le nombre de cœurs ne suffit pas à borner le poids : c'est le **produit**
# cœurs × relevés qui compte. Un banc d'essai peut échantillonner jusqu'à 7200
# fois ; à 128 cœurs et deux grandeurs, cela ferait près de deux millions de
# nombres — largement au-delà de la limite d'ingestion de l'API, et le rapport
# serait *refusé*, pas simplement lourd.
#
# 120 000 valeurs par grandeur pèsent environ 700 Ko de JSON, ce qui laisse la
# place au reste du rapport. Au-delà, le relevé cœur par cœur n'a pas lieu et le
# journal le dit : une série amputée en silence serait pire que son absence.
: "${SYSAUDIT_CORE_SERIES_BUDGET:=120000}"

# Identifiants des cœurs exposés par le noyau, dans l'ordre numérique.
#
# L'ordre n'est pas cosmétique : c'est la **position dans le tableau** qui
# identifie le cœur, le schéma ne publiant pas les identifiants. Un tri
# lexicographique placerait `cpu10` avant `cpu2`, et la fréquence lue sur un
# cœur serait attribuée à un autre.
monitoring_core_ids() {
  local dir='' id=''
  for dir in /sys/devices/system/cpu/cpu[0-9]*; do
    id=${dir##*/cpu}
    [[ $id =~ ^[0-9]+$ ]] || continue
    printf '%s\n' "$id"
  done | sort -n
}

# Nombre de cœurs à relever, ou 0 si le relevé cœur par cœur n'a pas lieu.
#
# `$1` porte le nombre de relevés attendus sur toute la durée de la charge, et
# il n'est pas facultatif par confort : sans lui, la borne ne porterait que sur
# le nombre de cœurs, et une charge de deux heures sur 32 cœurs passerait la
# borne tout en produisant un rapport que l'API refuse.
monitoring_core_count() {
  local expected=${1:-1}
  local count=''
  count=$(monitoring_core_ids | wc -l)
  [[ $count =~ ^[0-9]+$ ]] || count=0
  [ "$count" -gt "$SYSAUDIT_CORE_SERIES_MAX" ] && count=0
  [[ $expected =~ ^[0-9]+$ ]] && [ "$expected" -gt 0 ] || expected=1
  [ $((count * expected)) -gt "$SYSAUDIT_CORE_SERIES_BUDGET" ] && count=0
  printf '%s' "$count"
}

# Fréquences courantes, un tableau JSON dans l'ordre des cœurs.
#
# Un cœur hors ligne, ou dont `scaling_cur_freq` est illisible, porte un
# marqueur — jamais un zéro. Un cœur parqué à 0 MHz et un cœur qu'on n'a pas su
# lire produiraient sinon le même tracé, et seul le premier est une observation.
monitoring_cpu_core_clocks_json() {
  local out='' id='' khz='' file=''
  while read -r id; do
    file="/sys/devices/system/cpu/cpu$id/cpufreq/scaling_cur_freq"
    khz=''
    [ -r "$file" ] && khz=$(cat "$file" 2>/dev/null || true)
    if [[ $khz =~ ^[0-9]+$ ]]; then
      out=$(json_join "$out" "$(awk -v k="$khz" 'BEGIN { printf "%.0f", k / 1000 }')")
    else
      out=$(json_join "$out" "$(j_unknown NOT_AVAILABLE 'cpufreq n’expose pas la fréquence de ce cœur')")
    fi
  done < <(monitoring_core_ids)
  [ -n "$out" ] || return 0
  printf '[%s]' "$out"
}

# Compteurs bruts par cœur, une ligne « id total idle » chacun.
#
# Même lecture que `monitoring_raw_sample`, mais ligne à ligne : `/proc/stat`
# publie `cpu0`, `cpu1`… avant les totaux, et c'est le **delta** entre deux
# lectures qui donne une charge. Une lecture unique ne dit rien : elle décrit la
# machine depuis son démarrage.
monitoring_core_stats() {
  [ -r /proc/stat ] || return 0
  LC_ALL=C awk '
    /^cpu[0-9]+ / {
      id = substr($1, 4)
      total = 0
      for (i = 2; i <= NF; i++) total += $i
      print id, total, $5
    }' /proc/stat 2>/dev/null | sort -n
}

# Charges par cœur, un tableau JSON, à partir de deux relevés de compteurs.
#
# `$1` porte le relevé précédent, `$2` le courant, tels que `monitoring_core_stats`
# les écrit. Un cœur absent de l'un des deux relevés — cœur mis hors ligne
# pendant l'observation — porte un marqueur : la position doit rester celle du
# cœur, et décaler le tableau attribuerait chaque charge au voisin.
monitoring_cpu_core_usage_json() {
  local previous=${1-} current=${2-}
  [ -n "$previous" ] && [ -n "$current" ] || return 0

  local out=''
  out=$(LC_ALL=C awk -v prev="$previous" '
    BEGIN {
      n = split(prev, lines, "\n")
      for (i = 1; i <= n; i++) {
        if (split(lines[i], f, " ") == 3) { pt[f[1]] = f[2]; pi[f[1]] = f[3] }
      }
    }
    {
      id = $1
      if (!(id in pt)) { print "-"; next }
      dt = $2 - pt[id]
      di = $3 - pi[id]
      if (dt <= 0 || di < 0) { print "-"; next }
      usage = (dt - di) * 100 / dt
      if (usage < 0) usage = 0
      if (usage > 100) usage = 100
      printf "%.1f\n", usage
    }' <<<"$current")

  local fields='' value=''
  while IFS= read -r value; do
    if [ "$value" = '-' ] || [ -z "$value" ]; then
      fields=$(json_join "$fields" "$(j_unknown NOT_AVAILABLE 'aucun relevé précédent pour ce cœur')")
    else
      fields=$(json_join "$fields" "$(j_num "$value")")
    fi
  done <<<"$out"
  [ -n "$fields" ] || return 0
  printf '[%s]' "$fields"
}

# Compteur cumulé de bridages thermiques, toutes sources confondues.
#
# La valeur seule ne dit rien : un compteur non nul peut dater de la semaine
# dernière. C'est sa **progression** pendant l'observation qui prouve un bridage
# en cours.
monitoring_throttle_counter() {
  local total=0 value='' file='' found='false'
  for file in /sys/devices/system/cpu/cpu[0-9]*/thermal_throttle/core_throttle_count; do
    [ -r "$file" ] || continue
    value=$(cat "$file" 2>/dev/null || true)
    [[ $value =~ ^[0-9]+$ ]] || continue
    total=$((total + value))
    found='true'
  done
  [ "$found" = 'true' ] && printf '%s' "$total"
  return 0
}

# Bridage rapporté par le micrologiciel d'un Raspberry Pi.
#
# `vcgencmd get_throttled` rend un masque de bits : le bit 2 signale un bridage
# **en cours**, le bit 0 une sous-tension en cours. C'est la seule source qui
# distingue un bridage d'une simple baisse de fréquence — un processeur au repos
# tourne bas sans être bridé, et confondre les deux inventerait une panne.
monitoring_rpi_throttled() {
  has_cmd vcgencmd || return 0
  local raw=''
  raw=$(run_cmd vcgencmd get_throttled 2>/dev/null) || return 0
  local mask=${raw#*=}
  [[ $mask =~ ^0x[0-9a-fA-F]+$ ]] || return 0
  # Bit 0 : sous-tension en cours. Bit 2 : bridage en cours.
  if (((mask & 0x1) != 0 || (mask & 0x4) != 0)); then
    printf 'true'
  else
    printf 'false'
  fi
}

# Bridage constaté entre deux relevés.
#
# Sans relevé précédent — au premier échantillon — la réponse est **vide**, non
# « false ». Un premier échantillon ne prouve pas l'absence de bridage : il
# prouve seulement qu'on n'a pas encore eu deux points à comparer.
monitoring_throttled() {
  local before=${1-} after=${2-}
  local rpi=''
  rpi=$(monitoring_rpi_throttled)
  if [ -n "$rpi" ]; then
    printf '%s' "$rpi"
    return 0
  fi
  [[ $before =~ ^[0-9]+$ ]] && [[ $after =~ ^[0-9]+$ ]] || return 0
  if [ "$after" -gt "$before" ]; then printf 'true'; else printf 'false'; fi
}

# Statistiques d'une grandeur, calculées sur les valeurs lues sur stdin.
#
# `sampleCount` n'est pas un `maybe` : c'est un dénombrement, et zéro échantillon
# est un fait. C'est ce qui permet de lire une moyenne absente sans conclure
# « moyenne nulle » — il n'y a simplement rien eu à moyenner.
monitoring_aggregate() {
  local unit=$1 interval_ms=$2 source=$3

  # Les relevés sont bufferisés parce qu'ils servent deux fois : une passe awk
  # pour les statistiques d'ordre un, et un `sort -n` pour le centile. Trier
  # dans awk demanderait `asort`, qui est une extension gawk — absente de mawk,
  # l'awk par défaut de Debian et d'Ubuntu. La suite serait passée ici et aurait
  # cassé sur la moitié du parc.
  local samples=''
  samples=$(cat)

  local stats=''
  stats=$(printf '%s\n' "$samples" | LC_ALL=C awk '
    /^-?[0-9.]+$/ {
      if (count == 0 || $1 < min) min = $1
      if (count == 0 || $1 > max) max = $1
      if (count == 0) first = $1
      sum += $1
      last = $1
      count++
    }
    END {
      if (count == 0) { print "0"; exit }
      printf "%d %s %s %s %.2f %s", count, last, min, max, sum / count, first
    }')

  local count='' current='' min='' max='' average='' first=''
  read -r count current min max average first <<<"$stats"
  [ -n "$count" ] || count=0

  # Centile par rang le plus proche. Le maximum est fragile : un seul relevé
  # aberrant — une lecture prise pendant un changement de fréquence, une sonde
  # qui hoquette — suffit à le déplacer, et le rapport annonce alors une pointe
  # que la machine n'a jamais tenue.
  #
  # En dessous de deux relevés, aucun centile : sur un point il vaudrait ce
  # point, en lui donnant l'autorité d'une statistique.
  local p95=''
  if [ "$count" -ge 2 ]; then
    local rank=''
    rank=$(LC_ALL=C awk -v n="$count" 'BEGIN { r = int(0.95 * n + 0.999999); if (r < 1) r = 1; if (r > n) r = n; print r }')
    # `LC_ALL=C` sur les deux : mawk formate `%.2f` avec la virgule décimale de
    # la locale, et `sort -n` lit les nombres avec celle de la locale aussi.
    # `j_num` ramène bien la virgule au point en aval, mais un tri qui se
    # trompe d'ordre, lui, ne se rattrape nulle part.
    p95=$(printf '%s\n' "$samples" | grep -E '^-?[0-9.]+$' | LC_ALL=C sort -n | sed -n "${rank}p")
  fi

  local duration=''
  [ "$count" -gt 0 ] && duration=$((count * interval_ms))

  json_object \
    "$(jf_maybe_num current "$current" NOT_AVAILABLE 'aucun échantillon exploitable')" \
    "$(jf_maybe_num minimum "$min" NOT_AVAILABLE 'aucun échantillon exploitable')" \
    "$(jf_maybe_num maximum "$max" NOT_AVAILABLE 'aucun échantillon exploitable')" \
    "$(jf_maybe_num average "$average" NOT_AVAILABLE 'aucun échantillon exploitable')" \
    "$(jf_maybe_num first "$first" NOT_AVAILABLE 'aucun échantillon exploitable')" \
    "$(jf_maybe_num p95 "$p95" NOT_AVAILABLE 'moins de deux relevés')" \
    "$(jf_maybe_str unit "$unit")" \
    "$(jf_raw sampleCount "$count")" \
    "$(jf_maybe_num sampleIntervalMs "$interval_ms")" \
    "$(jf_maybe_num sampleDurationMs "$duration" NOT_AVAILABLE 'aucun échantillon exploitable')" \
    "$(jf_maybe_str source "$source")"
}

# collect_monitoring <durée en secondes> [intervalle en secondes]
collect_monitoring() {
  local duration=${1:-0} interval=${2:-1}
  [ "$duration" -gt 0 ] 2>/dev/null || return 0

  log_step "Observation sur ${duration} s"

  local started_at=''
  started_at=$(iso_now)

  local samples='' elapsed=0
  # Mémoire et swap sont instantanés : seuls les compteurs cumulés ont besoin
  # d'un point de comparaison.
  local prev_total='' prev_idle='' prev_read='' prev_write='' prev_rx='' prev_tx=''
  read -r prev_total prev_idle _ _ prev_read prev_write prev_rx prev_tx \
    < <(monitoring_raw_sample)
  local prev_throttle='' prev_energy=''
  prev_throttle=$(monitoring_throttle_counter)
  # Les sources sont repérées une fois, dans cette portée : les substitutions de
  # commande de la boucle en héritent, alors que rien de ce qu'elles y
  # affecteraient ne remonterait ici.
  monitoring_probe_sources
  prev_energy=$(monitoring_rapl_uj)

  # Séries brutes, gardées pour les statistiques. Elles sont **redondantes avec
  # `samples` et c'est voulu** : au-delà de la borne du tableau, les échantillons
  # sont tronqués et ce résumé devient la seule trace du pic.
  local series_usage='' series_temp='' series_freq=''

  while [ "$elapsed" -lt "$duration" ]; do
    sleep "$interval"
    elapsed=$((elapsed + interval))

    local total='' idle='' mem='' swap='' read_bytes='' write_bytes='' rx='' tx=''
    read -r total idle mem swap read_bytes write_bytes rx tx < <(monitoring_raw_sample)

    local usage='' temperature='' frequency='' throttle='' throttled='' reason=''
    usage=$(monitoring_cpu_usage "$prev_total" "$prev_idle" "$total" "$idle")
    temperature=$(read_cpu_temperature)
    frequency=$(monitoring_cpu_frequency_mhz)
    throttle=$(monitoring_throttle_counter)
    throttled=$(monitoring_throttled "$prev_throttle" "$throttle")
    reason=$(monitoring_cpu_throttle_reason "$prev_throttle" "$throttle")

    [ -n "$usage" ] && series_usage="${series_usage}${usage}"$'\n'
    [ -n "$temperature" ] && series_temp="${series_temp}${temperature}"$'\n'
    [ -n "$frequency" ] && series_freq="${series_freq}${frequency}"$'\n'

    samples=$(json_join "$samples" "$(json_object \
      "$(jf_str at "$(iso_now)")" \
      "$(jf_maybe_num cpuUsagePercent "$usage" NOT_AVAILABLE '/proc/stat illisible')" \
      "$(jf_maybe_num cpuTemperatureCelsius "$temperature" NOT_AVAILABLE 'aucun capteur thermique CPU lisible')" \
      "$(jf_maybe_num memoryUsedBytes "$mem")" \
      "$(jf_maybe_num swapUsedBytes "$swap")" \
      "$(jf_maybe_num diskReadBytesPerSecond "$(monitoring_rate "$prev_read" "$read_bytes" "$interval")" NOT_AVAILABLE '/proc/diskstats illisible')" \
      "$(jf_maybe_num diskWriteBytesPerSecond "$(monitoring_rate "$prev_write" "$write_bytes" "$interval")" NOT_AVAILABLE '/proc/diskstats illisible')" \
      "$(jf_maybe_num networkRxBytesPerSecond "$(monitoring_rate "$prev_rx" "$rx" "$interval")")" \
      "$(jf_maybe_num networkTxBytesPerSecond "$(monitoring_rate "$prev_tx" "$tx" "$interval")")" \
      "$(jf_maybe_num cpuFrequencyMhz "$frequency" NOT_AVAILABLE 'ni cpufreq ni /proc/cpuinfo n’expose la fréquence')" \
      "$(jf_maybe_bool cpuThrottled "$throttled" NOT_AVAILABLE 'aucun compteur de bridage : une fréquence basse ne suffit pas à le conclure')" \
      "$(if [ -n "$reason" ]; then jf_str cpuThrottleReason "$reason"; fi)" \
      "$(monitoring_extra_fields "$interval" "$prev_energy")")")

    prev_total=$total; prev_idle=$idle
    prev_read=$read_bytes; prev_write=$write_bytes; prev_rx=$rx; prev_tx=$tx
    prev_throttle=$throttle
    prev_energy=$(monitoring_rapl_uj)
  done

  local interval_ms=$((interval * 1000))
  local aggregates=''
  aggregates=$(json_join \
    "$(jf_raw cpuUsagePercent "$(printf '%s' "$series_usage" | monitoring_aggregate '%' "$interval_ms" '/proc/stat')")" \
    "$(jf_raw cpuTemperatureCelsius "$(printf '%s' "$series_temp" | monitoring_aggregate '°C' "$interval_ms" '/sys/class/hwmon')")" \
    "$(jf_raw cpuFrequencyMhz "$(printf '%s' "$series_freq" | monitoring_aggregate 'MHz' "$interval_ms" '/sys/devices/system/cpu')")")

  json_object \
    "$(jf_str startedAt "$started_at")" \
    "$(jf_raw intervalMs "$interval_ms")" \
    "$(jf_raw durationMs "$((elapsed * 1000))")" \
    "$(jf_raw samples "[$samples]")" \
    "$(jf_raw aggregates "{$aggregates}")"
}

# --- Capteurs de charge ------------------------------------------------------
#
# Ces lectures complètent l'échantillon : ventilateurs, puissance, tension,
# télémétrie graphique et motif de bridage. Elles servent deux appelants —
# l'observation `--monitor` et l'échantillonneur du banc d'essai — et vivent ici
# pour que les deux produisent exactement la même forme d'échantillon.
#
# Deux principes gouvernent tout ce bloc :
#
# 1. **Les sources sont repérées une fois**, au premier relevé. Chercher les
#    ventilateurs dans `/sys/class/hwmon` à chaque seconde d'une charge de dix
#    minutes coûterait six cents parcours de répertoire pour un résultat qui ne
#    change pas.
# 2. **Un capteur inexistant ne produit pas de champ.** Répéter « GPU inconnu »
#    six cents fois sur une machine sans carte graphique gonflerait le rapport
#    sans rien apprendre : l'absence se lit à ce que la série ne contient pas.
#    Un capteur repéré mais muet à l'instant du relevé, lui, produit bien un
#    marqueur — c'est un incident, pas une caractéristique de la machine.

: "${SYSFS_ROOT:=/sys}"

# Sources repérées : chemins vides tant que la reconnaissance n'a pas eu lieu.
MON_SOURCES_PROBED=''
MON_FAN_CPU_PATH=''
MON_FAN_GPU_PATH=''
MON_FAN_CHASSIS_PATHS=''
MON_VCORE_PATH=''
MON_RAPL_PATH=''
MON_GPU_KIND=''
MON_GPU_HWMON=''
MON_GPU_DEVICE=''

# Étiquette d'une entrée hwmon (`fan1_input` → `fan1_label`), en minuscules.
monitoring_hwmon_label() {
  local input=$1
  local label="${input%_input}_label"
  [ -r "$label" ] || return 0
  tr '[:upper:]' '[:lower:]' <"$label" 2>/dev/null | tr -d '\n'
}

# Repère les capteurs disponibles. Idempotent : le second appel ne fait rien.
#
# L'attribution d'un ventilateur à un rôle est le point délicat. hwmon ne
# normalise rien : selon la carte mère, `fan1_input` désigne le ventilateur
# processeur, celui du boîtier, ou une entrée morte à zéro. Deux indices sont
# donc croisés — le pilote, puis l'étiquette publiée — et **rien n'est attribué
# par défaut** : un ventilateur qu'aucun des deux ne rattache à un rôle reste
# compté comme ventilateur de boîtier, ce qui est la lecture la moins
# affirmative, jamais comme ventilateur processeur.
monitoring_probe_sources() {
  [ -z "$MON_SOURCES_PROBED" ] || return 0
  MON_SOURCES_PROBED='done'

  local chip='' name='' input='' label=''
  for chip in "$SYSFS_ROOT"/class/hwmon/hwmon*; do
    [ -d "$chip" ] || continue
    name=$(cat "$chip/name" 2>/dev/null) || name=''

    case "$name" in
      amdgpu | nouveau | i915 | xe)
        [ -n "$MON_GPU_HWMON" ] || MON_GPU_HWMON=$chip
        ;;
    esac

    for input in "$chip"/fan[0-9]*_input; do
      [ -r "$input" ] || continue
      label=$(monitoring_hwmon_label "$input")
      case "$name" in
        # Un pilote graphique ne pilote que le ventilateur de sa propre carte :
        # l'indice est plus sûr que n'importe quelle étiquette.
        amdgpu | nouveau)
          [ -n "$MON_FAN_GPU_PATH" ] || MON_FAN_GPU_PATH=$input
          continue
          ;;
      esac
      case "$label" in
        *cpu* | *processor*)
          [ -n "$MON_FAN_CPU_PATH" ] || MON_FAN_CPU_PATH=$input
          ;;
        *gpu* | *graphics*)
          [ -n "$MON_FAN_GPU_PATH" ] || MON_FAN_GPU_PATH=$input
          ;;
        *)
          # Aucun indice ne rattache celui-ci à un rôle : il rejoint la liste des
          # rotations non attribuées, dont la section publie le maximum.
          MON_FAN_CHASSIS_PATHS="${MON_FAN_CHASSIS_PATHS:+$MON_FAN_CHASSIS_PATHS }$input"
          ;;
      esac
    done

    # Tension du cœur : seule l'étiquette `vcore` la désigne sans ambiguïté.
    # Les autres entrées `in*` sont des rails d'alimentation quelconques, et
    # prendre la première pour une tension de cœur serait une invention.
    for input in "$chip"/in[0-9]*_input; do
      [ -r "$input" ] || continue
      [ -n "$MON_VCORE_PATH" ] && break
      label=$(monitoring_hwmon_label "$input")
      case "$label" in
        *vcore* | *'cpu core'*) MON_VCORE_PATH=$input ;;
      esac
    done
  done

  # RAPL : compteur d'énergie du paquet processeur. C'est un cumul en
  # microjoules, pas une puissance — la puissance naît de sa progression.
  local zone='' zone_name=''
  for zone in "$SYSFS_ROOT"/class/powercap/intel-rapl:[0-9]*; do
    [ -r "$zone/energy_uj" ] || continue
    zone_name=$(cat "$zone/name" 2>/dev/null) || zone_name=''
    case "$zone_name" in
      package-*)
        MON_RAPL_PATH="$zone/energy_uj"
        break
        ;;
    esac
  done

  if has_cmd nvidia-smi; then
    MON_GPU_KIND='nvidia'
  elif [ -n "$MON_GPU_HWMON" ]; then
    MON_GPU_KIND='sysfs'
    # Le répertoire du périphérique porte l'occupation et la VRAM ; le chip
    # hwmon porte les températures, la puissance et les fréquences.
    if [ -d "$MON_GPU_HWMON/device" ]; then MON_GPU_DEVICE="$MON_GPU_HWMON/device"; fi
  fi
  return 0
}

# La rotation la plus élevée parmi plusieurs entrées, en tours par minute.
#
# Elle existe parce que la plupart des cartes mères **n'étiquettent pas leurs
# ventilateurs**. Le pilote `nct6687` d'une MSI B850, par exemple, expose seize
# entrées `fan*_input` et **aucun** `fan*_label` : rien ne dit lequel refroidit
# le processeur.
#
# Retenir la première entrée du glob serait pire qu'inutile — l'ordre
# lexicographique met `fan11` avant `fan1`, et la machine de validation
# publiait ainsi 1 160 tr/min en ignorant les deux ventilateurs à 2 105 et
# 1 957. Le maximum, lui, répond à la question qu'on se pose devant une machine
# chaude : **est-ce que quelque chose tourne, et à quelle vitesse ?**
#
# Un maximum de zéro est conservé : tous les ventilateurs à l'arrêt sur une
# machine chaude est précisément ce qu'on cherche à voir.
monitoring_fan_rpm_max() {
  local paths=${1-} path='' rpm='' best=''
  [ -n "$paths" ] || return 0
  for path in $paths; do
    rpm=$(monitoring_fan_rpm "$path")
    [ -n "$rpm" ] || continue
    if [ -z "$best" ] || [ "$rpm" -gt "$best" ]; then best=$rpm; fi
  done
  [ -n "$best" ] && printf '%s' "$best"
  return 0
}

# Vitesse de rotation lue sur un chemin hwmon, en tours par minute.
#
# Zéro est **conservé** : un ventilateur à l'arrêt sur une machine chaude est
# précisément ce qu'on cherche à voir. Une lecture illisible, elle, ne rend rien.
monitoring_fan_rpm() {
  local path=${1-}
  [ -n "$path" ] && [ -r "$path" ] || return 0
  local rpm=''
  rpm=$(cat "$path" 2>/dev/null) || return 0
  [[ $rpm =~ ^[0-9]+$ ]] || return 0
  # Au-delà de 30 000 tr/min, la lecture décrit un capteur qui déraille, pas un
  # ventilateur : aucun ventilateur d'ordinateur n'atteint ce régime.
  [ "$rpm" -le 30000 ] || return 0
  printf '%s' "$rpm"
}

# Tension du cœur processeur, en volts. hwmon la publie en millivolts.
monitoring_cpu_voltage_volts() {
  [ -n "$MON_VCORE_PATH" ] && [ -r "$MON_VCORE_PATH" ] || return 0
  local mv=''
  mv=$(cat "$MON_VCORE_PATH" 2>/dev/null) || return 0
  [[ $mv =~ ^[0-9]+$ ]] || return 0
  LC_ALL=C awk -v m="$mv" 'BEGIN { v = m / 1000; if (v > 0 && v < 10) printf "%.3f", v }'
}

# Compteur d'énergie du paquet processeur, en microjoules.
monitoring_rapl_uj() {
  [ -n "$MON_RAPL_PATH" ] && [ -r "$MON_RAPL_PATH" ] || return 0
  local uj=''
  uj=$(cat "$MON_RAPL_PATH" 2>/dev/null) || return 0
  [[ $uj =~ ^[0-9]+$ ]] || return 0
  printf '%s' "$uj"
}

# Puissance moyenne entre deux relevés RAPL, en watts.
#
# Le compteur repasse à zéro quand il déborde — toutes les quelques minutes sur
# certaines plateformes. Un débordement produirait une puissance négative : le
# relevé est alors abandonné plutôt que redressé, parce que l'ampleur du
# débordement dépend du domaine et n'est pas publiée.
monitoring_power_watts() {
  local before=${1-} after=${2-} seconds=${3-}
  [[ $before =~ ^[0-9]+$ ]] && [[ $after =~ ^[0-9]+$ ]] || return 0
  [ "$after" -ge "$before" ] || return 0
  LC_ALL=C awk -v d="$((after - before))" -v s="$seconds" 'BEGIN {
    if (s <= 0) exit;
    w = d / 1000000 / s;
    if (w >= 0 && w < 10000) printf "%.1f", w
  }'
}

# Motif du bridage processeur, tel que le matériel le publie.
#
# Trois sources, et **aucune déduction** : une fréquence basse n'entre pas dans
# ce calcul. Le compteur `thermal_throttle` du noyau ne compte que les bridages
# thermiques — c'est son nom et sa définition — donc sa progression désigne un
# motif, pas seulement un fait. Le micrologiciel du Raspberry Pi, lui, distingue
# la sous-tension du plafond de température.
#
# Un bridage constaté sans motif publié ne rend rien : `cpuThrottled` reste vrai
# et la raison reste absente, ce qui est exactement ce qui est connu.
monitoring_cpu_throttle_reason() {
  local before=${1-} after=${2-}

  if has_cmd vcgencmd; then
    local raw=''
    raw=$(run_cmd vcgencmd get_throttled 2>/dev/null) || raw=''
    local mask=${raw#*=}
    if [[ $mask =~ ^0x[0-9a-fA-F]+$ ]]; then
      # Bit 0 : sous-tension en cours. Bit 3 : plafond de température logiciel
      # atteint. Le bit 2 signale un bridage sans en publier le motif — il ne
      # produit donc pas de raison.
      if (((mask & 0x1) != 0)); then
        printf 'under-voltage'
        return 0
      fi
      if (((mask & 0x8) != 0)); then
        printf 'thermal'
        return 0
      fi
      return 0
    fi
  fi

  [[ $before =~ ^[0-9]+$ ]] && [[ $after =~ ^[0-9]+$ ]] || return 0
  [ "$after" -gt "$before" ] && printf 'thermal'
  return 0
}

# Télémétrie de la première carte graphique.
#
# Écrit neuf champs séparés par des espaces, un tiret pour ce qui manque :
#   température point_chaud horloge horloge_mémoire tension puissance
#   utilisation vram_utilisée motif_de_bridage
#
# Une seule carte est suivie : la série décrit une machine sous charge, et
# `benchmark.results[].device` porte déjà le détail carte par carte. Suivre
# quatre cartes multiplierait la série par quatre pour une information que la
# section des résultats donne déjà.
monitoring_gpu_sample() {
  case "$MON_GPU_KIND" in
    nvidia) monitoring_gpu_sample_nvidia ;;
    sysfs) monitoring_gpu_sample_sysfs ;;
    *) return 0 ;;
  esac
}

# `nvidia-smi` rend « [N/A] » pour ce qu'une carte n'expose pas. Le prendre pour
# un nombre produirait une horloge nulle sur une carte qui tourne.
monitoring_gpu_sample_nvidia() {
  local raw=''
  raw=$(run_cmd nvidia-smi \
    --query-gpu=temperature.gpu,clocks.current.graphics,clocks.current.memory,power.draw,utilization.gpu,memory.used \
    --format=csv,noheader,nounits -i 0 2>/dev/null | head -n1) || return 0
  [ -n "$raw" ] || return 0

  local temp='' core='' mem_clock='' power='' usage='' vram=''
  IFS=',' read -r temp core mem_clock power usage vram <<<"$(printf '%s' "$raw" | tr -d ' ')"

  local field='' value=''
  for field in temp core mem_clock power usage vram; do
    value=${!field}
    [[ $value =~ ^[0-9]+([.][0-9]+)?$ ]] || printf -v "$field" '%s' ''
  done
  [ -n "$vram" ] && vram=$((${vram%.*} * 1048576))

  # Le point chaud et la tension ne sont pas exposés par NVML ; le motif de
  # bridage l'est par une requête distincte, que toutes les versions du pilote
  # n'acceptent pas. Les demander à chaque seconde coûterait un processus de
  # plus par relevé pour un champ souvent absent : ils restent hors de la série.
  printf '%s %s %s %s %s %s %s %s %s' \
    "${temp:--}" '-' "${core:--}" "${mem_clock:--}" '-' \
    "${power:--}" "${usage:--}" "${vram:--}" '-'
}

# Cartes AMD et Intel : tout est dans sysfs, sans processus à lancer.
monitoring_gpu_sample_sysfs() {
  local chip=$MON_GPU_HWMON device=$MON_GPU_DEVICE
  [ -n "$chip" ] || return 0

  local temp='' hotspot='' core='' mem_clock='' volt='' power='' usage='' vram=''

  temp=$(monitoring_hwmon_temp "$chip" 'edge')
  hotspot=$(monitoring_hwmon_temp "$chip" 'junction')
  # Sans étiquette, `temp1_input` est la température de bord sur amdgpu.
  [ -n "$temp" ] || temp=$(monitoring_sysfs_millis "$chip/temp1_input" 1000 200)

  core=$(monitoring_sysfs_millis "$chip/freq1_input" 1000000 100000)
  mem_clock=$(monitoring_sysfs_millis "$chip/freq2_input" 1000000 100000)
  volt=$(monitoring_sysfs_millis "$chip/in0_input" 1000 10)
  # `power1_average` est en microwatts.
  power=$(monitoring_sysfs_millis "$chip/power1_average" 1000000 10000)

  if [ -n "$device" ]; then
    usage=$(cat "$device/gpu_busy_percent" 2>/dev/null) || usage=''
    [[ $usage =~ ^[0-9]+$ ]] && [ "$usage" -le 100 ] || usage=''
    vram=$(cat "$device/mem_info_vram_used" 2>/dev/null) || vram=''
    [[ $vram =~ ^[0-9]+$ ]] || vram=''
  fi

  printf '%s %s %s %s %s %s %s %s %s' \
    "${temp:--}" "${hotspot:--}" "${core:--}" "${mem_clock:--}" "${volt:--}" \
    "${power:--}" "${usage:--}" "${vram:--}" '-'
}

# Température hwmon désignée par son étiquette (`edge`, `junction`, `mem`).
monitoring_hwmon_temp() {
  local chip=$1 wanted=$2 input='' label=''
  for input in "$chip"/temp[0-9]*_input; do
    [ -r "$input" ] || continue
    label=$(monitoring_hwmon_label "$input")
    [ "$label" = "$wanted" ] || continue
    monitoring_sysfs_millis "$input" 1000 200
    return 0
  done
  return 0
}

# Lecture sysfs entière divisée par un facteur, bornée par un maximum.
#
# La borne n'est pas décorative : une entrée hwmon absente ou parasite rend
# couramment des valeurs sans rapport avec la grandeur, et une horloge à
# 4 000 000 MHz dans un graphique en écrase toutes les autres.
monitoring_sysfs_millis() {
  local path=$1 divisor=$2 max=$3 raw=''
  [ -r "$path" ] || return 0
  raw=$(cat "$path" 2>/dev/null) || return 0
  [[ $raw =~ ^[0-9]+$ ]] || return 0
  LC_ALL=C awk -v r="$raw" -v d="$divisor" -v m="$max" 'BEGIN {
    v = r / d;
    if (v > 0 && v <= m) printf "%.1f", v
  }'
}

# Fragments JSON des capteurs additionnels, pour un relevé.
#
# Émis par les deux appelants — l'observation `--monitor` et l'échantillonneur
# du banc d'essai — pour que la série ait la même forme dans les deux cas. Un
# champ dont aucune source n'a été repérée est **omis** : sur une machine sans
# carte graphique, répéter « GPU inconnu » à chaque seconde ferait grossir le
# rapport sans rien apprendre que son absence ne dise déjà.
#
# Le compteur d'énergie précédent arrive en **argument**, et n'est pas gardé
# dans une variable de module : cette fonction est appelée depuis une
# substitution de commande, donc depuis un sous-shell, et tout ce qu'elle y
# affecterait serait perdu au retour. Une puissance calculée contre une
# référence perpétuellement vide serait toujours inconnue — ce qui, sur une
# machine dont RAPL fonctionne, serait faux.
monitoring_extra_fields() {
  local interval=${1:-1} previous_energy=${2-}
  monitoring_probe_sources

  local fields=''

  local voltage=''
  voltage=$(monitoring_cpu_voltage_volts)
  [ -n "$MON_VCORE_PATH" ] && fields=$(json_join "$fields" \
    "$(jf_maybe_num cpuCoreVoltageVolts "$voltage" NOT_AVAILABLE 'capteur Vcore muet à ce relevé')")

  if [ -n "$MON_RAPL_PATH" ]; then
    local power=''
    power=$(monitoring_power_watts "$previous_energy" "$(monitoring_rapl_uj)" "$interval")
    # Le premier relevé n'a pas de prédécesseur : sa puissance est inconnue, pas
    # nulle. Le motif le dit plutôt que de laisser lire une machine à l'arrêt.
    fields=$(json_join "$fields" \
      "$(jf_maybe_num cpuPackagePowerWatts "$power" NOT_AVAILABLE 'aucun relevé RAPL précédent à comparer')")
  fi

  local fan=''
  if [ -n "$MON_FAN_CPU_PATH" ]; then
    fan=$(monitoring_fan_rpm "$MON_FAN_CPU_PATH")
    fields=$(json_join "$fields" \
      "$(jf_maybe_num cpuFanRpm "$fan" NOT_AVAILABLE 'capteur de rotation muet à ce relevé')")
  fi
  if [ -n "$MON_FAN_GPU_PATH" ]; then
    fan=$(monitoring_fan_rpm "$MON_FAN_GPU_PATH")
    fields=$(json_join "$fields" \
      "$(jf_maybe_num gpuFanRpm "$fan" NOT_AVAILABLE 'capteur de rotation muet à ce relevé')")
  fi
  if [ -n "$MON_FAN_CHASSIS_PATHS" ]; then
    fan=$(monitoring_fan_rpm_max "$MON_FAN_CHASSIS_PATHS")
    fields=$(json_join "$fields" \
      "$(jf_maybe_num chassisFanRpm "$fan" NOT_AVAILABLE 'aucune des entrées de rotation n’a répondu à ce relevé')")
  fi

  if [ -n "$MON_GPU_KIND" ]; then
    local temp='' hotspot='' core='' mem_clock='' volt='' power='' usage='' vram='' reason=''
    read -r temp hotspot core mem_clock volt power usage vram reason \
      < <(monitoring_gpu_sample) || true
    # Un tiret marque ce que la source n'a pas rendu : il ne doit jamais
    # ressortir comme valeur.
    local field='' value=''
    for field in temp hotspot core mem_clock volt power usage vram reason; do
      value=${!field}
      [ "$value" = '-' ] && printf -v "$field" '%s' ''
    done

    local absent='pilote graphique muet sur cette grandeur'
    fields=$(json_join "$fields" \
      "$(jf_maybe_num gpuTemperatureCelsius "$temp" NOT_AVAILABLE "$absent")" \
      "$(jf_maybe_num gpuCoreClockMhz "$core" NOT_AVAILABLE "$absent")" \
      "$(jf_maybe_num gpuMemoryClockMhz "$mem_clock" NOT_AVAILABLE "$absent")" \
      "$(jf_maybe_num gpuBoardPowerWatts "$power" NOT_AVAILABLE "$absent")" \
      "$(jf_maybe_num gpuUsagePercent "$usage" NOT_AVAILABLE "$absent")" \
      "$(jf_maybe_num gpuVramUsedBytes "$vram" NOT_AVAILABLE "$absent")")
    # Point chaud, tension et motif de bridage n'existent que sur une partie des
    # cartes : les publier en marqueur sur toutes les autres laisserait croire
    # à un capteur défaillant là où il n'y a simplement pas de capteur.
    [ -n "$hotspot" ] && fields=$(json_join "$fields" "$(jf_maybe_num gpuHotspotCelsius "$hotspot")")
    [ -n "$volt" ] && fields=$(json_join "$fields" "$(jf_maybe_num gpuCoreVoltageVolts "$volt")")
    [ -n "$reason" ] && fields=$(json_join "$fields" "$(jf_maybe_str gpuThrottleReason "$reason")")
  fi

  printf '%s' "$fields"
}
