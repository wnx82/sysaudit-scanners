#!/usr/bin/env bash
# Banc d'essai : mesures de performance reproductibles.
#
# À la différence du reste du scanner, ce module **charge volontairement la
# machine**. Il n'est donc jamais exécuté sans demande explicite.
#
# Aucun outil tiers n'est embarqué ni redistribué : le banc d'essai utilise ce
# qui est déjà installé — `dd` (coreutils), `openssl`, `glmark2`, `fio` — et
# déclare la mesure indisponible quand l'outil manque, avec son nom.

# Durée cible de chaque mesure, en secondes.
#
# Elle dépend du niveau de diagnostic : cinq secondes mesurent surtout la montée
# en fréquence du processeur, pas son débit soutenu — c'est le défaut qui faisait
# dire que « le banc d'essai se termine beaucoup trop vite ». Le niveau Poussée
# vise donc une charge soutenue, et `--benchmark` hors de ce niveau garde une
# mesure courte : l'utilisateur n'a pas demandé un audit de 45 minutes.
#
# `SYSAUDIT_BENCH_SECONDS` reste prioritaire, mais bornée : une valeur absurde
# transformerait un audit en test de vieillissement.
bench_seconds() {
  local requested="${SYSAUDIT_BENCH_SECONDS:-}"
  local default=5
  [ "$(current_level)" = 'stress' ] && default=20

  local value=$default
  [[ $requested =~ ^[0-9]+$ ]] && value=$requested
  [ "$value" -lt 1 ] && value=1
  [ "$value" -gt 120 ] && value=120
  printf '%s' "$value"
}

# Répit entre deux mesures : la suivante partirait sinon d'un processeur déjà
# chaud, et mesurerait le refroidissement de la précédente.
bench_cooldown_seconds() {
  [ "$(current_level)" = 'stress' ] && printf '5' || printf '1'
}

# Durée de la charge soutenue, en secondes.
#
# Le bridage thermique n'apparaît pas en vingt secondes : un processeur met
# plusieurs minutes à atteindre son régime stable, et c'est là que se voit un
# refroidissement insuffisant, une pâte thermique sèche ou un ventilateur
# encrassé. Cette mesure est la raison d'être du niveau Poussée ; ailleurs,
# elle n'a pas lieu.
#
# `SYSAUDIT_SOAK_SECONDS` permet de la raccourcir, notamment pour les tests.
bench_soak_seconds() {
  [ "$(current_level)" = 'stress' ] || {
    printf '0'
    return 0
  }

  local requested="${SYSAUDIT_SOAK_SECONDS:-}"
  local value=600
  [[ $requested =~ ^[0-9]+$ ]] && value=$requested
  [ "$value" -lt 10 ] && value=10
  [ "$value" -gt 3600 ] && value=3600
  printf '%s' "$value"
}

# Volume écrit par les mesures de stockage, en mébioctets.
#
# 256 Mio dépassent la plupart des caches d'écriture sans immobiliser la
# machine, mais la valeur est plafonnée par la place réellement libre : écrire
# un quart d'un disque presque plein pour mesurer un débit serait une façon
# coûteuse de provoquer la panne qu'on cherche à prévenir.
bench_storage_mib() {
  local dir="${TMPDIR:-/tmp}" free_mib=''
  free_mib=$(df -Pm "$dir" 2>/dev/null | awk 'NR==2 { print $4 }')
  [[ $free_mib =~ ^[0-9]+$ ]] || {
    printf '0'
    return 0
  }

  # Un dixième de la place libre au plus, et jamais moins de 64 Mio : en deçà,
  # la mesure décrirait le cache d'écriture, pas le disque.
  local budget=$((free_mib / 10))
  [ "$budget" -gt 256 ] && budget=256
  [ "$budget" -lt 64 ] && budget=0
  printf '%s' "$budget"
}

# Volume manipulé par les mesures mémoire.
#
# Un huitième de la mémoire *disponible* : un banc d'essai n'a pas à provoquer
# de swap, encore moins l'arrivée du tueur de processus. La mémoire libre est
# lue à chaque appel, l'état de la machine ayant pu changer entre deux mesures.
bench_memory_mib() {
  local available_kib=''
  available_kib=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo 2>/dev/null)
  [[ $available_kib =~ ^[0-9]+$ ]] || {
    printf '0'
    return 0
  }

  local budget=$((available_kib / 1024 / 8))
  [ "$budget" -gt 256 ] && budget=256
  [ "$budget" -lt 32 ] && budget=0
  printf '%s' "$budget"
}

# Exécute une commande de mesure.
#
# `run_cmd` borne chaque commande à 15 secondes, ce qui convient à une collecte
# mais **pas** à un banc d'essai : `openssl speed` répète sa mesure sur six
# tailles de bloc, soit six fois la durée demandée. Une mesure tuée en cours
# produirait un « outil indisponible » trompeur — l'outil était bien là.
# Code de retour de `bench_run` lorsque le délai a été dépassé.
#
# Distinct de l'échec ordinaire, et il fallait qu'il le soit : les deux
# produisaient `1`, et la mesure graphique rapportait « pas de contexte de rendu »
# à chaque fois qu'elle avait simplement été interrompue. Un diagnostic faux
# envoie chercher un pilote absent là où il suffit d'allonger le budget.
readonly BENCH_TIMED_OUT=124

bench_run() {
  local budget=$(($(bench_seconds) * 12 + 60))
  local output='' status=0

  if has_cmd timeout; then
    output=$(timeout -k 5 "$budget" "$@" 2>/dev/null) || status=$?
  else
    output=$("$@" 2>/dev/null) || status=$?
  fi

  # `timeout` rend 124 quand il a tué la commande, 137 quand il a dû l'achever
  # au signal KILL après le sursis de `-k`.
  if [ "$status" -eq 124 ] || [ "$status" -eq 137 ]; then
    return "$BENCH_TIMED_OUT"
  fi
  [ "$status" -eq 0 ] || return 1
  printf '%s' "$output"
}

collect_benchmark() {
  local seconds=''
  seconds=$(bench_seconds)

  log_warn 'Banc d’essai : la machine va être volontairement chargée.'
  log_info "Chaque mesure vise $seconds s, avec $(bench_cooldown_seconds) s de répit entre deux."
  log_info "Durée à prévoir : environ $(bench_estimated_label). Chaque étape est annoncée ci-dessous."

  local started_at='' start_ms='' results=''
  started_at=$(iso_now)
  start_ms=$(clock_ms)

  bench_safety_init

  # La décision de relever cœur par cœur se prend **ici, une fois**, et pas dans
  # l'échantillonneur : celui-ci tourne dans un sous-shell dont la sortie est
  # jetée, et un avertissement émis là n'arriverait nulle part. Le lecteur doit
  # savoir pourquoi une machine à 96 cœurs n'a pas de graphique par cœur.
  BENCH_CORE_SERIES=$(monitoring_core_count "$(bench_estimated_seconds)")
  if [ "$BENCH_CORE_SERIES" -eq 0 ] && [ "$(monitoring_core_count 1)" -gt 0 ]; then
    log_info 'Relevé cœur par cœur non pris : la durée du banc d’essai et le nombre de cœurs dépasseraient le budget de série (SYSAUDIT_CORE_SERIES_BUDGET).'
  fi

  bench_baseline

  # L'ordre n'est pas indifférent : les mesures processeur d'abord, sur une
  # machine encore froide, puis mémoire, stockage et GPU. Chaque mesure est
  # précédée d'un répit et suivie d'un contrôle de sécurité — un banc d'essai
  # qui refuse de s'arrêter n'est pas un diagnostic, c'est un risque.
  local phase=''
  for phase in cpu-single cpu-multi cpu-soak memory-read memory-write memory-copy \
    storage-sequential-write storage-sequential-read storage-random-read gpu gaming cpu-gpu; do

    if bench_stopped; then
      results=$(json_join "$results" \
        "$(bench_skipped "$phase" 'banc d’essai' "$(bench_stop_reason)")")
      continue
    fi

    bench_cooldown
    case "$phase" in
      cpu-single) results=$(json_join "$results" "$(bench_cpu single)") ;;
      cpu-multi) results=$(json_join "$results" "$(bench_cpu multi)") ;;
      cpu-soak) results=$(json_join "$results" "$(bench_cpu_soak)") ;;
      memory-read | memory-write | memory-copy)
        results=$(json_join "$results" "$(bench_memory "${phase#memory-}")")
        ;;
      storage-sequential-write) results=$(json_join "$results" "$(bench_storage write)") ;;
      storage-sequential-read) results=$(json_join "$results" "$(bench_storage read)") ;;
      storage-random-read) results=$(json_join "$results" "$(bench_storage random)") ;;
      gpu) results=$(json_join "$results" "$(bench_gpu)") ;;
      # Les charges mixtes viennent en dernier, et l'ordre compte : elles sont
      # le pire cas thermique de la machine, et les faire passer avant les
      # autres laisserait chaque mesure suivante démarrer sur un châssis déjà
      # saturé. Le répit qui les précède ne suffirait pas à l'effacer.
      gaming | cpu-gpu) results=$(json_join "$results" "$(bench_mixed "$phase")") ;;
    esac
    bench_safety_check
  done

  local duration='' stopped_reason=''
  duration=$(($(clock_ms) - start_ms))
  [ "$duration" -lt 0 ] && duration=0
  bench_stopped && stopped_reason=$(bench_stop_reason)
  bench_safety_cleanup

  local telemetry=''
  telemetry=$(bench_telemetry_json)

  json_object \
    "$(jf_str startedAt "$started_at")" \
    "$(jf_str finishedAt "$(iso_now)")" \
    "$(jf_raw durationMs "$duration")" \
    "$(jf_raw secondsPerTargetPlanned "$seconds")" \
    "$(if [ -n "$stopped_reason" ]; then jf_str stoppedEarlyReason "$stopped_reason"; fi)" \
    "$(jf_raw results "[$results]")" \
    "$(section telemetry "$telemetry")"
}

# Nombre d'échantillons que le schéma accepte dans la série du banc d'essai.
readonly BENCH_TELEMETRY_MAX=7200

# La série relevée pendant les mesures, en un objet JSON — ou rien.
#
# Rien, et non un objet vide : une section `telemetry` sans échantillon
# affirmerait une observation qui n'a pas eu lieu. Sur une machine où le banc
# d'essai s'arrête à la première cible, l'absence est la seule réponse exacte.
#
# La borne du schéma est atteinte après deux heures de charge continue. Au-delà,
# ce sont les **premiers** échantillons qui sont écartés : la fin de charge est
# le moment où un refroidissement insuffisant se voit, et la tronquer reviendrait
# à jeter la seule partie de la série qui explique quelque chose. La coupe est
# dite dans le journal, jamais silencieuse.
bench_telemetry_json() {
  [ -n "$BENCH_TELEMETRY_FILE" ] && [ -s "$BENCH_TELEMETRY_FILE" ] || return 0

  local count=''
  count=$(wc -l <"$BENCH_TELEMETRY_FILE" 2>/dev/null | tr -d ' ') || return 0
  [[ $count =~ ^[0-9]+$ ]] && [ "$count" -gt 0 ] || return 0

  local samples=''
  if [ "$count" -gt "$BENCH_TELEMETRY_MAX" ]; then
    log_warn "Série du banc d’essai tronquée : $count relevés pour $BENCH_TELEMETRY_MAX conservés, les plus anciens écartés."
    samples=$(tail -n "$BENCH_TELEMETRY_MAX" "$BENCH_TELEMETRY_FILE" | paste -sd, -)
  else
    samples=$(paste -sd, - <"$BENCH_TELEMETRY_FILE")
  fi
  [ -n "$samples" ] || return 0

  json_object \
    "$(jf_raw intervalMs 1000)" \
    "$(jf_raw samples "[$samples]")"
}

# Durée totale à prévoir, en secondes.
#
# Elle n'est pas décorative. Au niveau Poussée, le banc d'essai occupe la machine
# pendant un quart d'heure : sans annonce, la barre de progression reste sur la
# même étape tout ce temps et l'audit passe pour bloqué — c'est exactement ce qui
# a été signalé. Le chiffre est une somme des budgets, pas une mesure : il est
# donc présenté comme un ordre de grandeur.
bench_estimated_seconds() {
  local per_target='' cooldown='' soak='' baseline=''
  per_target=$(bench_seconds)
  cooldown=$(bench_cooldown_seconds)
  soak=$(bench_soak_seconds)
  baseline=$(bench_baseline_seconds)

  # Neuf cibles au budget nominal, plus la charge soutenue qui a le sien, plus
  # les deux charges mixtes, plus un répit avant chacune des douze, plus le
  # relevé de référence.
  #
  # Les charges mixtes ne durent pas le budget nominal : leur durée est celle du
  # rendu, que glmark2 fixe à une quarantaine de secondes pour les quatre scènes
  # retenues — la même que la mesure `gpu`. Elles sont donc comptées à cette
  # valeur-là, pas au budget d'une mesure processeur.
  local render=40
  printf '%s' "$((baseline + 12 * cooldown + 9 * per_target + soak + 2 * render))"
}

# La durée, en minutes ou en secondes selon ce qui se lit le mieux.
bench_estimated_label() {
  local total=''
  total=$(bench_estimated_seconds)
  if [ "$total" -lt 90 ]; then
    printf '%s s' "$total"
    return 0
  fi
  printf '%s min' "$(((total + 30) / 60))"
}

# --- Sécurité et thermique ---------------------------------------------------
#
# Les mesures s'exécutent dans des sous-shells (`$(bench_cpu …)`) : un drapeau
# porté par une variable y serait perdu au retour. L'état d'arrêt vit donc dans
# un fichier, comme le journal de collecte.

BENCH_STOP_FILE=''
BENCH_SAMPLE_FILE=''
BENCH_TELEMETRY_FILE=''

# Nombre de cœurs relevés individuellement, ou 0 si le relevé n'a pas lieu.
#
# Décidé une seule fois par `collect_benchmark`, avant la première mesure. Les
# mesures s'exécutent dans des substitutions de commande, donc dans des
# sous-shells qui héritent de cette variable — mais dont rien ne remonte : c'est
# pourquoi la décision, et l'avertissement qui l'accompagne, vivent en amont.
BENCH_CORE_SERIES=0

BENCH_OWN_DIR=''

bench_safety_init() {
  # Le répertoire du journal de collecte est déjà supprimé par un `trap`, y
  # compris si le scan est interrompu. S'y greffer évite d'installer un second
  # `trap` — qui remplacerait le premier — et surtout évite d'abandonner un
  # répertoire derrière soi à chaque banc d'essai.
  local dir=''
  if [ -n "$COLLECTION_JOURNAL" ]; then
    dir="$(dirname "$COLLECTION_JOURNAL")/benchmark"
    mkdir -p "$dir" 2>/dev/null || dir=''
  fi

  if [ -z "$dir" ]; then
    dir=$(mktemp -d "${TMPDIR:-/tmp}/sysaudit-bench-XXXXXX") || return 0
    BENCH_OWN_DIR=$dir
  fi

  chmod 700 "$dir" 2>/dev/null || true
  BENCH_STOP_FILE="$dir/stop"
  BENCH_SAMPLE_FILE="$dir/samples"
  BENCH_TELEMETRY_FILE="$dir/telemetry"
  : >"$BENCH_SAMPLE_FILE"
  : >"$BENCH_TELEMETRY_FILE"
}

# Supprime le répertoire créé en propre, quand le journal n'était pas
# disponible. Le cas du journal présent est couvert par son `trap`.
bench_safety_cleanup() {
  [ -n "$BENCH_OWN_DIR" ] || return 0
  rm -rf "$BENCH_OWN_DIR" 2>/dev/null || true
  BENCH_OWN_DIR=''
  return 0
}

bench_stopped() {
  [ -n "$BENCH_STOP_FILE" ] && [ -s "$BENCH_STOP_FILE" ]
}

bench_stop_reason() {
  [ -n "$BENCH_STOP_FILE" ] && [ -f "$BENCH_STOP_FILE" ] && head -n1 "$BENCH_STOP_FILE"
  return 0
}

# Seuil critique publié par le capteur processeur, en degrés.
#
# Aucune marge inventée : un seuil arbitraire arrêterait le banc d'essai sur des
# machines parfaitement saines, ou ne l'arrêterait pas sur celles qui souffrent.
# Sans seuil publié, la surveillance ne conclut rien.
bench_critical_celsius() {
  local chip='' name='' crit=''
  for chip in "$SYSFS_ROOT"/class/hwmon/hwmon*; do
    [ -r "$chip/name" ] || continue
    name=$(cat "$chip/name" 2>/dev/null)
    case "$name" in
      k10temp | coretemp | zenpower | cpu_thermal) : ;;
      *) continue ;;
    esac
    crit=$(cat "$chip/temp1_crit" 2>/dev/null) || continue
    [[ $crit =~ ^[0-9]+$ ]] || continue
    millicelsius_to_celsius "$crit" && return 0
  done
  return 0
}

# Arrête le banc d'essai si la température dépasse le seuil du constructeur.
bench_safety_check() {
  local current='' critical=''
  current=$(read_cpu_temperature)
  critical=$(bench_critical_celsius)
  [ -n "$current" ] && [ -n "$critical" ] || return 0

  # Le seuil critique est celui où le matériel se protège lui-même. Le banc
  # d'essai s'arrête avant, à 95 % : dépasser volontairement le point où le
  # processeur commence à se brider ne mesure plus rien d'utile.
  awk -v c="$current" -v k="$critical" 'BEGIN { exit !(c >= k * 0.95) }' || return 0

  local reason="Arrêt de sécurité : ${current} °C atteints pour un seuil constructeur de ${critical} °C."
  [ -n "$BENCH_STOP_FILE" ] && printf '%s\n' "$reason" >"$BENCH_STOP_FILE"
  log_warn "$reason"
  record_issue 'benchmark' 'warning' "$reason" 'thermique'
  return 0
}

# Répète un accès jusqu'à la durée visée, sans dépasser un nombre de passes.
#
# Un seul passage de 256 Mio se termine en quelques dizaines de millisecondes
# sur du matériel récent : la mesure décrivait alors surtout la résolution de
# l'horloge. Répéter jusqu'à la durée demandée donne un débit soutenu, et le
# plafond de passes est ce qui empêche une mesure d'écriture de devenir un test
# d'usure.
#
# Écrit « passes durée_ms » sur stdout. La boucle s'arrête à la première des
# deux limites atteintes.
#
# L'horloge est celle du cœur, `clock_ms`, et non un `date` appelé sur place.
# Ce collecteur s'en était fabriqué une seconde, à coups de `date +%s%3N`, et en
# a hérité les deux défauts que `clock_ms` corrige :
#
# - elle n'était **pas monotone** : un recalage NTP en cours de mesure changeait
#   la durée mesurée, exactement le défaut qui avait déjà fait refuser des
#   rapports entiers pour une durée d'audit aberrante ;
# - `%3N` n'est pas honoré partout. Sous `uutils coreutils`, le `date` par
#   défaut d'Ubuntu 25.10, la largeur est ignorée et les neuf chiffres de
#   nanosecondes sortent : le budget paraissait dépassé dès la première passe,
#   et **toutes** les mesures du banc d'essai ne comportaient qu'une seule passe
#   au lieu du nombre demandé.
bench_loop() {
  local budget_ms=$1 max_passes=$2
  shift 2

  local start='' passes=0 elapsed=0
  start=$(clock_ms)
  while :; do
    "$@" 2>/dev/null || true
    passes=$((passes + 1))
    elapsed=$(($(clock_ms) - start))
    [ "$elapsed" -ge "$budget_ms" ] && break
    [ "$passes" -ge "$max_passes" ] && break
  done

  printf '%s %s' "$passes" "$elapsed"
}

# Nombre de passes d'écriture tolérées sur un support persistant.
#
# Les lectures sont répétées librement — elles n'usent rien. Les écritures sont
# bornées : mesurer un débit ne doit pas coûter plusieurs gibioctets de cycles
# d'écriture sur un SSD dont on cherche précisément à préserver la santé.
bench_write_passes() {
  local mib=$1
  [ "$mib" -gt 0 ] || {
    printf '1'
    return 0
  }

  local budget_mib=1024
  [ "$(current_level)" = 'stress' ] && budget_mib=2048

  local passes=$((budget_mib / mib))
  [ "$passes" -lt 1 ] && passes=1
  printf '%s' "$passes"
}

# Durée de la phase de référence, en secondes.
bench_baseline_seconds() {
  case "$(current_level)" in
    stress) printf '15' ;;
    quick) printf '5' ;;
    *) printf '10' ;;
  esac
}

# Relève la machine **au repos**, avant toute charge.
#
# C'est la mesure la plus utile du banc d'essai et la seule qui ne mesure rien :
# sans elle, une température de 85 °C sous charge n'est comparable à rien. Une
# machine partie de 35 °C et une machine partie de 70 °C atteignent le même
# chiffre et ne décrivent pas le même refroidissement — mais leurs courbes de
# charge, elles, sont identiques.
#
# Elle vient avant l'échauffement de la première mesure, donc avant que quoi que
# ce soit ait chauffé la machine.
bench_baseline() {
  local seconds=''
  seconds=$(bench_baseline_seconds)
  [ "$seconds" -gt 0 ] || return 0

  log_step "Relevé de référence au repos (${seconds} s)"
  bench_sampler_start idle
  sleep "$seconds"
  bench_sampler_stop
  # La référence thermique de la série, retenue ici parce que c'est le seul
  # moment où la machine est froide. Tous les refroidissements qui suivent s'y
  # comparent : sans elle, « 62 °C » ne dit pas si la machine est revenue au
  # repos ou si elle est encore chaude.
  BENCH_BASELINE_CELSIUS=$(bench_celsius_integer "$(bench_sampled_max)")
  return 0
}

# Température de référence au repos, en degrés entiers. Vide si non lisible.
BENCH_BASELINE_CELSIUS=''

# Marge admise au-dessus du repos avant de considérer la machine refroidie.
#
# Cinq degrés, et pas zéro : un processeur ne revient jamais exactement à sa
# température de départ entre deux mesures, et exiger l'égalité ferait annoncer
# « délai écoulé » à tous les coups — c'est-à-dire ne rien annoncer du tout.
readonly BENCH_COOLDOWN_MARGIN_CELSIUS=5

# Un relevé de température ramené à l'entier.
#
# `read_cpu_temperature` rend un dixième de degré (`62.4`), et les fonctions de
# refroidissement n'acceptent que des entiers — délibérément : un pourcentage de
# refroidissement au dixième de degré prétendrait à une précision que la sonde
# n'a pas. Une valeur illisible rend une chaîne vide, que `cooldown_state` sait
# traiter comme « personne n'a regardé ».
bench_celsius_integer() {
  local value=${1-}
  case "$value" in '' | *[!0-9.]*) return 0 ;; esac
  LC_ALL=C awk -v t="$value" 'BEGIN { printf "%d", int(t + 0.5) }'
}

# Répit entre deux mesures — et **phase de référence** de la série.
#
# La machine y est au repos relatif, ventilateurs encore en action et
# température en train de redescendre. Sans ces relevés-là, une montée à 85 °C
# pendant la charge suivante ne serait comparable à rien : c'est l'écart avec le
# repos qui décrit un refroidissement, pas la valeur absolue.
bench_cooldown() {
  local seconds=''
  seconds=$(bench_cooldown_seconds)
  [ "$seconds" -gt 0 ] || return 0

  local start='' target=''
  start=$(bench_celsius_integer "$(read_cpu_temperature)")
  case "$BENCH_BASELINE_CELSIUS" in
    '' | *[!0-9]*) target='' ;;
    *) target=$((BENCH_BASELINE_CELSIUS + BENCH_COOLDOWN_MARGIN_CELSIUS)) ;;
  esac

  bench_sampler_start idle

  # La durée **ne change pas** : la boucle dort le même total qu'un `sleep`.
  #
  # C'est délibéré. Écourter le répit dès que la cible est atteinte raccourcirait
  # la phase de référence, qui est aussi une phase de mesure — c'est elle qui
  # donne l'écart au repos auquel toute la série se compare. L'allonger, à
  # l'inverse, ferait mentir l'estimation annoncée au début de l'audit.
  #
  # Ce que la boucle apporte, c'est le **compte rendu** : `cooldown_percent`
  # mesure le chemin thermique parcouru, et `cooldown_state` dit laquelle des
  # deux fins s'applique. Les deux existaient sans que rien ne les alimente, et
  # l'utilisateur regardait un répit muet.
  local elapsed=0 current='' state='' percent=''
  while [ "$elapsed" -lt "$seconds" ]; do
    sleep 1
    elapsed=$((elapsed + 1))
    current=$(bench_celsius_integer "$(read_cpu_temperature)")
    percent=$(cooldown_percent "$start" "$current" "$target")
    if [ -n "$percent" ] && [ -n "$current" ]; then
      heartbeat_tick 'refroidissement' "$elapsed" "$seconds" "${current} °C — ${percent} % du retour au repos"
    fi
  done

  bench_sampler_stop

  # Laquelle des deux fins s'applique, et elle se dit. « Sans température
  # lisible, seul le délai décide » — et l'écrire évite de laisser croire que
  # quelqu'un a vérifié que la machine était refroidie.
  state=$(cooldown_state "$current" "$target" "$elapsed" "$seconds")
  case "$state" in
    target) log_step "Machine revenue au repos (${current} °C, cible ${target} °C)" ;;
    timeout)
      if [ -n "$current" ] && [ -n "$target" ]; then
        log_step "Répit écoulé, machine encore à ${current} °C (cible ${target} °C)"
      else
        log_step 'Répit écoulé — aucune température lisible pour le confirmer'
      fi
      ;;
  esac
  return 0
}

# Échantillonne la machine pendant une mesure, en tâche de fond.
#
# Deux sorties, pour deux usages :
#
# - `BENCH_SAMPLE_FILE` ne reçoit que la température, et il est **remis à zéro à
#   chaque appel** : c'est ce qui donne le maximum *de cette mesure-là*. Le
#   maximum ne se déduit pas des températures de début et de fin, une machine
#   pouvant culminer au milieu d'une mesure puis redescendre.
# - `BENCH_TELEMETRY_FILE` **accumule** un échantillon complet par seconde, sur
#   toute la durée du banc d'essai, chacun étiqueté de la phase en cours. C'est
#   cette série qui répond à la question qu'un score ne répond pas : la fréquence
#   a-t-elle tenu, la température s'est-elle stabilisée, les ventilateurs
#   ont-ils répondu ?
#
# La phase est passée en argument plutôt que lue dans une variable globale : les
# mesures s'exécutent dans des sous-shells, et une globale posée là n'y
# survivrait pas — le même piège que celui qui a fait sortir l'état d'arrêt dans
# un fichier.
bench_sampler_start() {
  local phase=${1:-idle}
  [ -n "$BENCH_SAMPLE_FILE" ] || return 0
  : >"$BENCH_SAMPLE_FILE"
  (
    # `local` n'a pas cours hors d'une fonction ; le sous-shell tient lieu de
    # portée, et rien de ce qui suit ne remonte au processus appelant.
    sampler_total=''
    sampler_idle=''
    sampler_read=''
    sampler_write=''
    sampler_rx=''
    sampler_tx=''
    sampler_throttle=''
    sampler_energy=''
    sampler_cores=0
    sampler_core_stats=''
    read -r sampler_total sampler_idle _ _ sampler_read sampler_write sampler_rx sampler_tx \
      < <(monitoring_raw_sample)
    sampler_throttle=$(monitoring_throttle_counter)
    # Les sources sont repérées ici, une fois, et non dans chaque substitution
    # de commande : celles-ci s'exécutent dans un sous-shell d'où rien ne
    # remonte, et le repérage y recommencerait à chaque seconde.
    monitoring_probe_sources
    sampler_energy=$(monitoring_rapl_uj)
    # Le relevé cœur par cœur coûte une lecture par cœur et par seconde : il
    # n'est pris que si la machine en compte un nombre raisonnable, et cette
    # décision se prend une fois pour toute la charge.
    sampler_cores=$BENCH_CORE_SERIES
    sampler_core_stats=''
    [ "$sampler_cores" -gt 0 ] && sampler_core_stats=$(monitoring_core_stats)

    while :; do
      sleep 1

      sample=$(read_cpu_temperature)
      [ -n "$sample" ] && printf '%s\n' "$sample" >>"$BENCH_SAMPLE_FILE"
      [ -n "$BENCH_TELEMETRY_FILE" ] || continue

      total=''; idle=''; mem=''; swap=''; read_bytes=''; write_bytes=''; rx=''; tx=''
      read -r total idle mem swap read_bytes write_bytes rx tx < <(monitoring_raw_sample)

      usage=$(monitoring_cpu_usage "$sampler_total" "$sampler_idle" "$total" "$idle")
      frequency=$(monitoring_cpu_frequency_mhz)
      core_clocks=''; core_usage=''; core_stats=''
      if [ "$sampler_cores" -gt 0 ]; then
        core_clocks=$(monitoring_cpu_core_clocks_json)
        core_stats=$(monitoring_core_stats)
        core_usage=$(monitoring_cpu_core_usage_json "$sampler_core_stats" "$core_stats")
      fi
      throttle=$(monitoring_throttle_counter)
      throttled=$(monitoring_throttled "$sampler_throttle" "$throttle")
      reason=$(monitoring_cpu_throttle_reason "$sampler_throttle" "$throttle")

      # Les accolades, et le saut de ligne : `json_object` n'en émet pas, et
      # sans lui tous les relevés se concaténeraient sur une seule ligne — que
      # `wc -l` compterait pour zéro, faisant disparaître la série entière.
      {
        json_object \
        "$(jf_str at "$(iso_now)")" \
        "$(jf_str phase "$phase")" \
        "$(jf_maybe_num cpuUsagePercent "$usage" NOT_AVAILABLE '/proc/stat illisible')" \
        "$(jf_maybe_num cpuTemperatureCelsius "$sample" NOT_AVAILABLE 'aucun capteur thermique CPU lisible')" \
        "$(jf_maybe_num memoryUsedBytes "$mem")" \
        "$(jf_maybe_num swapUsedBytes "$swap")" \
        "$(jf_maybe_num diskReadBytesPerSecond "$(monitoring_rate "$sampler_read" "$read_bytes" 1)" NOT_AVAILABLE '/proc/diskstats illisible')" \
        "$(jf_maybe_num diskWriteBytesPerSecond "$(monitoring_rate "$sampler_write" "$write_bytes" 1)" NOT_AVAILABLE '/proc/diskstats illisible')" \
        "$(jf_maybe_num networkRxBytesPerSecond "$(monitoring_rate "$sampler_rx" "$rx" 1)")" \
        "$(jf_maybe_num networkTxBytesPerSecond "$(monitoring_rate "$sampler_tx" "$tx" 1)")" \
        "$(jf_maybe_num cpuFrequencyMhz "$frequency" NOT_AVAILABLE 'ni cpufreq ni /proc/cpuinfo n’expose la fréquence')" \
        "$(jf_maybe_bool cpuThrottled "$throttled" NOT_AVAILABLE 'aucun compteur de bridage : une fréquence basse ne suffit pas à le conclure')" \
        "$(if [ -n "$reason" ]; then jf_str cpuThrottleReason "$reason"; fi)" \
        "$(if [ -n "$core_clocks" ]; then jf_raw cpuCoreClocksMhz "$core_clocks"; fi)" \
        "$(if [ -n "$core_usage" ]; then jf_raw cpuCoreUsagePercent "$core_usage"; fi)" \
        "$(monitoring_extra_fields 1 "$sampler_energy")"
        printf '\n'
      } >>"$BENCH_TELEMETRY_FILE"
      sampler_energy=$(monitoring_rapl_uj)
      [ -n "$core_stats" ] && sampler_core_stats=$core_stats

      sampler_total=$total; sampler_idle=$idle
      sampler_read=$read_bytes; sampler_write=$write_bytes
      sampler_rx=$rx; sampler_tx=$tx
      sampler_throttle=$throttle
    done
    # `>/dev/null` n'est pas décoratif. Les mesures s'exécutent dans des
    # substitutions de commande — `$(bench_cpu single)` — et le sous-shell de
    # l'échantillonneur y hérite du **tube de sortie**. Tant qu'un descripteur
    # sur ce tube reste ouvert, l'appelant attend : un `nvidia-smi` bloqué,
    # petit-fils de l'échantillonneur que `kill` n'atteint pas, suffirait à
    # figer l'audit entier. L'échantillonneur n'écrit rien sur sa sortie
    # standard ; il n'a donc aucune raison de la garder.
  ) >/dev/null 2>&1 &
  BENCH_SAMPLER_PID=$!
  return 0
}

# Arrête l'échantillonneur.
#
# `kill` ne tue que le sous-shell : une commande qu'il avait lancée —
# `nvidia-smi`, `awk` — lui survit brièvement. Ce n'est pas grave, et surtout ce
# n'est **pas** à corriger en tirant sur le groupe de processus : sans contrôle
# de tâches, un sous-shell d'arrière-plan partage le groupe du script, et
# `kill -- -$pid` viserait l'audit entier. La survie d'un petit-fils est rendue
# inoffensive par le `>/dev/null` de `bench_sampler_start`, qui l'empêche de
# retenir le tube de l'appelant, et bornée par le délai de `run_cmd`.
bench_sampler_stop() {
  [ -n "${BENCH_SAMPLER_PID:-}" ] || return 0
  kill "$BENCH_SAMPLER_PID" 2>/dev/null || true
  wait "$BENCH_SAMPLER_PID" 2>/dev/null || true
  BENCH_SAMPLER_PID=''
  return 0
}

# Température maximale relevée pendant la dernière mesure.
bench_sampled_max() {
  [ -n "$BENCH_SAMPLE_FILE" ] && [ -s "$BENCH_SAMPLE_FILE" ] || return 0
  LC_ALL=C awk 'NF && (max == "" || $1 > max) { max = $1 } END { if (max != "") print max }' \
    "$BENCH_SAMPLE_FILE"
}

# Version du **protocole de mesure**, distincte de la version de l'outil.
#
# `toolVersion` dit quel binaire a tourné ; celle-ci dit comment il a été
# employé — durée, taille de bloc, nombre de passes, ordre des phases. Deux
# mesures produites par le même `openssl` mais l'une sur trois secondes et
# l'autre sur trente ne sont pas comparables, et rien ne le disait.
#
# **Une version par couple cible + outil, et non une par scanner.**
#
# La constante unique qui régnait ici jusqu'à présent ne pouvait pas être juste :
# elle était censée changer quand *l'une* des mesures changeait, et elle
# invalidait alors *toutes* les autres. Changer les scènes de glmark2 aurait
# cassé la comparabilité des débits disque, qui n'avaient pas bougé — si bien que
# personne ne la changeait jamais, et qu'elle ne distinguait plus rien.
#
# Découpée par mesure, elle redevient un contrat : modifier la charge processeur
# n'invalide que le processeur, et le classement graphique se referme
# exactement quand il doit se refermer.
#
# **À incrémenter dès qu'une de ces conditions change** pour la ligne concernée,
# même si l'outil ne bouge pas : durée, taille de bloc, nombre de passes, ordre
# des phases, algorithme demandé, ce qui décide qu'une mesure est écartée.
# `docs/format-rapport/PROTOCOLE-BANC-ESSAI.md` dit ce que chaque version
# recouvre, et un test de contrat refuse qu'un couple d'ici publie une version
# que l'analyse ne sait pas lire.
bench_protocol_version() {
  case "${1-}|${2-}" in
    'cpu-single|openssl' | 'cpu-multi|openssl' | 'cpu-soak|openssl') printf '1.0.0' ;;
    'memory-read|dd' | 'memory-write|dd' | 'memory-copy|dd') printf '1.0.0' ;;
    'storage-sequential-read|dd' | 'storage-sequential-write|dd') printf '1.0.0' ;;
    'storage-random-read|fio') printf '1.0.0' ;;
    'gpu|glmark2') printf '1.0.0' ;;
    'gaming|glmark2 + openssl' | 'cpu-gpu|glmark2 + openssl') printf '1.0.0' ;;
    # Aucun autre couple n'a de protocole, et c'est **volontaire**.
    #
    # Ces couples n'apparaissent que sur les chemins d'écart : la cible d'une
    # charge mixte annoncée avec le seul `glmark2` parce que c'est lui qui
    # manque, ou une mesure aléatoire écartée avant que `fio` n'entre en jeu.
    # Aucune mesure n'a eu lieu ; leur donner un numéro de protocole
    # affirmerait une méthode qui n'a pas été employée.
    *) return 0 ;;
  esac
}

# Un résultat complet. Le score, son unité, l'outil et les paramètres vont
# ensemble : un chiffre seul n'est comparable à rien.
bench_result() {
  bench_result_device "$1" '' "$2" "$3" "$4" "$5" "$6" "$7" "$8" "${9-}" "${10-}" ''
}

# Variante nommant le composant mesuré, et pouvant porter un fragment
# supplémentaire — la télémétrie d'une carte graphique, par exemple.
bench_result_device() {
  local target=$1 device=$2 tool=$3 version=$4 algorithm=$5 parameters=$6
  local duration=$7 score=$8 unit=$9
  local started_at=${10-} temp_before=${11-} extra=${12-}
  json_object \
    "$(jf_str target "$target")" \
    "$(jf_str status 'completed')" \
    "$(if [ -n "$device" ]; then jf_str device "$device"; fi)" \
    "$(if [ -n "$started_at" ]; then jf_str startedAt "$started_at"; fi)" \
    "$(jf_str finishedAt "$(iso_now)")" \
    "$(jf_optional_str protocolVersion "$(bench_protocol_version "$target" "$tool")")" \
    "$(jf_str tool "$tool")" \
    "$(jf_maybe_str toolVersion "$version" NOT_AVAILABLE 'version non exposée')" \
    "$(jf_maybe_str algorithm "$algorithm" UNSUPPORTED 'notion sans objet pour cette mesure')" \
    "$(jf_maybe_str parameters "$parameters")" \
    "$(jf_maybe_num durationMs "$duration")" \
    "$(jf_maybe_num score "$score" NOT_AVAILABLE 'mesure non aboutie')" \
    "$(jf_maybe_str unit "$unit" NOT_AVAILABLE)" \
    "$(jf_maybe_num temperatureCelsius "$(read_cpu_temperature)" NOT_AVAILABLE 'aucun capteur thermique CPU lisible')" \
    "$(jf_maybe_num temperatureBeforeCelsius "$temp_before" NOT_AVAILABLE 'aucun capteur thermique CPU lisible')" \
    "$(jf_maybe_num temperatureMaxCelsius "$(bench_sampled_max)" NOT_AVAILABLE 'aucune température échantillonnée pendant la mesure')" \
    "$(jf_maybe_bool throttled "$(bench_throttled)" UNKNOWN 'fréquence de base ou fréquence courante non lisible')" \
    "$extra"
}

# Mesure écartée : l'outil manque, la place manque, ou le banc d'essai s'est
# arrêté. La cible est rapportée avec sa raison plutôt qu'omise — une absence
# silencieuse laisserait croire que la mesure n'a jamais été prévue.
bench_skipped() {
  bench_not_measured "$1" '' "$2" "$3" 'skipped'
}

bench_skipped_device() {
  bench_not_measured "$1" "$2" "$3" "$4" 'skipped'
}

# Mesure tentée sans résultat exploitable : l'outil était là, il n'a rien rendu.
# C'est un défaut, pas une limite d'environnement, et les deux ne se corrigent
# pas de la même façon.
bench_failed() {
  bench_not_measured "$1" '' "$2" "$3" 'failed'
}

bench_failed_device() {
  bench_not_measured "$1" "$2" "$3" "$4" 'failed'
}

bench_not_measured() {
  local target=$1 device=$2 tool=$3 reason=$4 status=$5
  record_issue "benchmark.$target${device:+ ($device)}" 'warning' "$reason" "$tool"
  json_object \
    "$(jf_str target "$target")" \
    "$(jf_str status "$status")" \
    "$(if [ -n "$device" ]; then jf_str device "$device"; fi)" \
    "$(jf_str detail "$reason")" \
    "$(jf_optional_str protocolVersion "$(bench_protocol_version "$target" "$tool")")" \
    "$(jf_str tool "$tool")" \
    "$(jf_raw toolVersion "$(j_unknown NOT_AVAILABLE)")" \
    "$(jf_raw algorithm "$(j_unknown NOT_AVAILABLE)")" \
    "$(jf_raw parameters "$(j_unknown NOT_AVAILABLE)")" \
    "$(jf_raw durationMs "$(j_unknown NOT_AVAILABLE)")" \
    "$(jf_raw score "$(j_unknown NOT_AVAILABLE "$reason")")" \
    "$(jf_raw unit "$(j_unknown NOT_AVAILABLE)")" \
    "$(jf_raw temperatureCelsius "$(j_unknown NOT_AVAILABLE)")" \
    "$(jf_raw throttled "$(j_unknown NOT_AVAILABLE)")"
}

# Le processeur est-il bridé au moment de l'appel ?
#
# Comparaison de la fréquence courante à la fréquence de base. Les deux doivent
# être lisibles : affirmer à tort l'absence de bridage fausserait toute
# comparaison entre machines.
bench_throttled() {
  local current='' base=''
  current=$(read_value /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || printf '')
  base=$(read_value /sys/devices/system/cpu/cpu0/cpufreq/base_frequency 2>/dev/null || printf '')
  [[ $current =~ ^[0-9]+$ ]] && [[ $base =~ ^[0-9]+$ ]] || return 0
  [ "$base" -gt 0 ] || return 0

  # 85 % de la fréquence de base sous charge : le même seuil que la règle
  # PRF-002, pour que les deux disent la même chose.
  awk -v c="$current" -v b="$base" 'BEGIN { print (c < b * 0.85) ? "true" : "false" }'
}

# --- CPU ---------------------------------------------------------------------

# Débit de chiffrement AES, en mébioctets par seconde.
#
# `openssl speed` est retenu parce qu'il est présent sur presque toute
# installation, qu'il mesure une primitive normalisée, et qu'il sait lui-même
# répartir la charge sur plusieurs cœurs. Rien n'est redistribué : l'outil est
# appelé s'il est là.
bench_cpu() {
  # `local a=$1 b="$a"` ne fonctionne pas : Bash développe tous les arguments de
  # `local` avant de les affecter, et `set -u` rejette alors la seconde.
  local mode=$1
  local target="cpu-$mode"

  has_cmd openssl || {
    bench_skipped "$target" 'openssl' 'openssl absent : mesure CPU indisponible.'
    return 0
  }

  local seconds=''
  seconds=$(bench_seconds)

  # `openssl speed` répète sa mesure sur sept tailles de bloc : `-seconds 20`
  # occupe donc la machine 140 secondes, et la durée annoncée par le rapport
  # n'aurait rien à voir avec la durée réelle. `-bytes` fixe une taille unique —
  # 16 Ko, la plus représentative d'un débit soutenu — et rend `-seconds`
  # littéral. L'option n'existe qu'à partir d'OpenSSL 3 : sans elle, la mesure
  # reste valable mais dure plus longtemps, et les paramètres rapportés le
  # disent.
  local block=''
  [ "$(openssl_major)" -ge 3 ] 2>/dev/null && block='-bytes 16384'

  local threads=1 parameters=''
  if [ "$mode" = 'multi' ]; then
    threads=$(nproc 2>/dev/null || printf '1')
    parameters="-evp aes-128-cbc -seconds $seconds $block -multi $threads"
  else
    parameters="-evp aes-128-cbc -seconds $seconds $block"
  fi

  log_step "Banc d’essai CPU ($mode, $threads fil(s), $seconds s)"

  # Échauffement, hors chronomètre. Un processeur au repos démarre à sa
  # fréquence la plus basse : sans cette phase, la mesure décrit surtout la
  # vitesse à laquelle le gouverneur monte en régime, et deux exécutions
  # successives ne donnent pas le même chiffre.
  local warmup=2
  [ "$(current_level)" = 'stress' ] && warmup=5
  # shellcheck disable=SC2086  # les paramètres sont construits ici, pas reçus.
  if [ "$mode" = 'multi' ]; then
    LC_ALL=C bench_run openssl speed -evp aes-128-cbc -seconds "$warmup" $block -multi "$threads" >/dev/null 2>&1 || true
  else
    LC_ALL=C bench_run openssl speed -evp aes-128-cbc -seconds "$warmup" $block >/dev/null 2>&1 || true
  fi

  local started_at='' temp_before='' start_ms='' output='' score=''
  started_at=$(iso_now)
  temp_before=$(read_cpu_temperature)
  bench_sampler_start "$target"
  start_ms=$(clock_ms)
  # shellcheck disable=SC2086  # les paramètres sont construits ici, pas reçus.
  output=$(LC_ALL=C bench_run openssl speed $parameters) || output=''
  local duration=$(($(clock_ms) - start_ms))
  bench_sampler_stop

  score=$(bench_openssl_score "$output")

  [ -n "$score" ] || {
    bench_failed "$target" 'openssl' 'openssl n’a produit aucun débit exploitable.'
    return 0
  }

  bench_result "$target" 'openssl' "$(openssl_version)" 'AES-128-CBC' "$parameters" \
    "$duration" "$score" 'MiB/s' "$started_at" "$temp_before"
}

# Charge processeur soutenue.
#
# Elle ne cherche pas le débit de pointe — `cpu-multi` s'en charge — mais ce qui
# se passe après plusieurs minutes : la fréquence tient-elle, la température
# se stabilise-t-elle, ou le processeur se bride-t-il ?
#
# La charge est découpée en segments : c'est ce qui permet de contrôler la
# sécurité pendant la mesure plutôt qu'après, et de comparer le débit du dernier
# segment à celui du premier. Une perte de débit sous charge prolongée est le
# symptôme, pas la cause — mais elle est mesurable, contrairement à l'état de la
# pâte thermique.
bench_cpu_soak() {
  local target='cpu-soak'
  local total=''
  total=$(bench_soak_seconds)

  [ "$total" -gt 0 ] || {
    bench_skipped "$target" 'openssl' \
      'Charge soutenue réservée au niveau Poussée : elle immobilise la machine plusieurs minutes.'
    return 0
  }

  has_cmd openssl || {
    bench_skipped "$target" 'openssl' 'openssl absent : charge soutenue impossible.'
    return 0
  }

  local block=''
  [ "$(openssl_major)" -ge 3 ] 2>/dev/null && block='-bytes 16384'

  local threads=''
  threads=$(nproc 2>/dev/null || printf '1')

  # Segments de 30 secondes : assez courts pour que l'arrêt de sécurité
  # intervienne vite, assez longs pour que chacun soit une mesure et non du
  # bruit.
  local segment=30
  [ "$segment" -gt "$total" ] && segment=$total
  local segments=$((total / segment))
  [ "$segments" -lt 1 ] && segments=1

  log_step "Banc d’essai CPU (charge soutenue, $threads fil(s), $total s)"

  local started_at='' temp_before='' start_ms=''
  started_at=$(iso_now)
  temp_before=$(read_cpu_temperature)
  bench_sampler_start "$target"
  start_ms=$(clock_ms)
  # La charge soutenue est la phase pendant laquelle SysAudit paraissait planté :
  # la barre ne bougeait plus, et rien n'était écrit dans un journal redirigé.
  heartbeat_phase_start

  local index=0 first='' last='' sum=0 measured=0 output='' value=''
  while [ "$index" -lt "$segments" ]; do
    # shellcheck disable=SC2086  # les paramètres sont construits ici, pas reçus.
    output=$(LC_ALL=C bench_run openssl speed -evp aes-128-cbc -seconds "$segment" $block -multi "$threads") || output=''
    value=$(bench_openssl_score "$output")
    if [ -n "$value" ]; then
      [ -z "$first" ] && first=$value
      last=$value
      sum=$(awk -v s="$sum" -v v="$value" 'BEGIN { printf "%.1f", s + v }')
      measured=$((measured + 1))
    fi

    index=$((index + 1))
    # La sécurité est contrôlée *pendant* la charge : attendre la fin d'une
    # mesure de dix minutes pour s'apercevoir que la machine a surchauffé
    # n'aurait pas de sens.
    bench_safety_check

    # Un signe de vie à chaque segment, avec la température quand elle est
    # lisible. C'est la seule trace qui survit à une redirection du journal.
    local heartbeat_temp=''
    heartbeat_temp=$(read_cpu_temperature)
    heartbeat_tick 'Charge soutenue CPU' \
      $((index * segment)) "$total" \
      "$([ -n "$heartbeat_temp" ] && printf '%s °C' "$heartbeat_temp")"

    bench_stopped && break
  done

  local duration=$(($(clock_ms) - start_ms))
  bench_sampler_stop

  [ "$measured" -gt 0 ] || {
    bench_failed "$target" 'openssl' 'la charge soutenue n’a produit aucun débit exploitable.'
    return 0
  }

  local average=''
  average=$(awk -v s="$sum" -v n="$measured" 'BEGIN { printf "%.1f", s / n }')

  # Une perte de débit entre le premier et le dernier segment est le signe le
  # plus direct d'un bridage sous charge. Elle est rapportée telle quelle, sans
  # verdict : un portable qui bride à 85 % de son débit initial est conçu ainsi.
  if [ -n "$first" ] && [ -n "$last" ] && [ "$measured" -ge 2 ]; then
    local retained=''
    retained=$(awk -v f="$first" -v l="$last" 'BEGIN { if (f > 0) printf "%.0f", (l / f) * 100 }')
    if [ -n "$retained" ] && [ "$retained" -lt 90 ] 2>/dev/null; then
      record_issue 'benchmark.cpu-soak' 'warning' \
        "Débit tombé à $retained % de sa valeur initiale après $((duration / 1000)) s de charge : bridage sous charge prolongée." \
        'openssl'
    fi
  fi

  bench_result "$target" 'openssl' "$(openssl_version)" \
    "AES-128-CBC soutenu, $measured segment(s) de $segment s" \
    "-evp aes-128-cbc -seconds $segment $block -multi $threads" \
    "$duration" "$average" 'MiB/s' "$started_at" "$temp_before"
}

# Débit lu dans une sortie `openssl speed`, en Mio/s.
#
# La dernière colonne correspond au plus gros bloc, la plus représentative du
# débit soutenu. `openssl` l'exprime en milliers d'octets.
bench_openssl_score() {
  printf '%s' "${1-}" | awk '
    /^(AES-128-CBC|aes-128-cbc)/ { value = $NF }
    END { if (value != "") { gsub(/k$/, "", value); printf "%.1f", value * 1000 / 1048576 } }
  '
}

openssl_version() {
  run_cmd openssl version | awk '{print $2}'
}

# Numéro de version majeur d'OpenSSL, ou `0` s'il n'est pas lisible.
openssl_major() {
  local version=''
  version=$(openssl_version)
  printf '%s' "${version%%.*}" | grep -E '^[0-9]+$' || printf '0'
}

# --- Mémoire -----------------------------------------------------------------

# Débit de copie mémoire, mesuré sur un système de fichiers en RAM.
#
# Ce n'est pas la bande passante théorique des barrettes : c'est le débit
# qu'obtient réellement une copie de fichier en mémoire, avec le coût du noyau.
# L'unité et l'outil sont rapportés pour que personne ne confonde les deux.
# Débits mémoire — lecture, écriture, copie — mesurés sur un système de
# fichiers en RAM.
#
# Ce n'est pas la bande passante théorique des barrettes : c'est le débit
# qu'obtient réellement un accès en mémoire, avec le coût du noyau. L'unité et
# l'outil sont rapportés pour que personne ne confonde les deux.
#
# Les trois modes ne mesurent pas la même chose et n'ont aucune raison de donner
# le même chiffre : n'en publier qu'un — la copie — laissait croire à une
# mesure unique de « la RAM ».
bench_memory() {
  local mode=$1
  local target="memory-$mode"

  local ramdisk=''
  for ramdisk in /dev/shm /run/shm; do
    [ -d "$ramdisk" ] && [ -w "$ramdisk" ] && break
    ramdisk=''
  done

  [ -n "$ramdisk" ] || {
    bench_skipped "$target" 'dd' 'aucun système de fichiers en mémoire inscriptible.'
    return 0
  }

  local mib=''
  mib=$(bench_memory_mib)
  [ "$mib" -gt 0 ] || {
    bench_skipped "$target" 'dd' \
      'mémoire disponible insuffisante : la mesure aurait provoqué du swap.'
    return 0
  }

  # La copie manipule deux fichiers : elle exige deux fois le budget.
  [ "$mode" = 'copy' ] && mib=$((mib / 2))
  [ "$mib" -ge 16 ] || {
    bench_skipped "$target" 'dd' \
      'mémoire disponible insuffisante : la mesure aurait provoqué du swap.'
    return 0
  }

  log_step "Banc d’essai mémoire ($mode, $mib Mio)"

  local source_file='' target_file='' started_at='' temp_before=''
  local start_ms='' duration='' score=''
  source_file=$(mktemp "$ramdisk/sysaudit-bench-src-XXXXXX") || {
    bench_skipped "$target" 'dd' 'création du fichier de travail impossible.'
    return 0
  }

  # Le fichier de travail est écrit hors chronomètre pour les mesures qui le
  # lisent : seul l'accès mesuré doit compter.
  if [ "$mode" != 'write' ]; then
    dd if=/dev/zero of="$source_file" bs=1M count="$mib" status=none 2>/dev/null || true
  fi

  local seconds='' passes='' loop=''
  seconds=$(bench_seconds)
  started_at=$(iso_now)
  temp_before=$(read_cpu_temperature)
  bench_sampler_start "$target"
  case "$mode" in
    read)
      loop=$(bench_loop $((seconds * 1000)) 4096 dd if="$source_file" of=/dev/null bs=1M status=none)
      ;;
    write)
      # La RAM ne s'use pas : le plafond de passes n'a ici qu'un rôle de garde-fou.
      loop=$(bench_loop $((seconds * 1000)) 4096 \
        dd if=/dev/zero of="$source_file" bs=1M count="$mib" status=none)
      ;;
    copy)
      target_file=$(mktemp "$ramdisk/sysaudit-bench-dst-XXXXXX")
      loop=$(bench_loop $((seconds * 1000)) 4096 \
        dd if="$source_file" of="$target_file" bs=1M status=none)
      ;;
  esac
  bench_sampler_stop

  passes=${loop%% *}
  duration=${loop##* }
  rm -f "$source_file" "$target_file"

  [ "$duration" -gt 0 ] &&
    score=$(awk -v mib="$mib" -v n="$passes" -v ms="$duration" \
      'BEGIN { printf "%.1f", (mib * n) / (ms / 1000) }')

  [ -n "$score" ] || {
    bench_failed "$target" 'dd' 'accès trop rapide pour être chronométré.'
    return 0
  }

  local algorithm=''
  case "$mode" in
    read) algorithm='lecture séquentielle en RAM' ;;
    write) algorithm='écriture séquentielle en RAM' ;;
    copy) algorithm='copie séquentielle en RAM' ;;
  esac

  bench_result "$target" 'dd' "$(dd_version)" "$algorithm" \
    "bs=1M count=$mib sur $ramdisk, $passes passe(s)" \
    "$duration" "$score" 'MiB/s' "$started_at" "$temp_before"
}

dd_version() {
  run_cmd dd --version | head -n1 | awk '{print $NF}'
}

# --- Stockage ----------------------------------------------------------------

# Le disque physique qui porte un chemin, ou rien si c'est ambigu.
#
# **Sans lui, aucune machine à plusieurs disques ne peut être classée.**
#
# Le banc d'essai écrit dans un répertoire temporaire, donc sur un seul disque.
# Le résultat ne portait pourtant aucun nom de disque : l'analyse recevait un
# débit sans savoir à quoi l'attribuer, et sur une machine à quatre disques elle
# refusait de classer — à raison, créditer les trois autres d'un débit qu'ils
# n'ont pas rendu aurait inventé un mérite. Le prix de ce refus était qu'aucun
# disque n'obtenait jamais de rang.
#
# La forme rendue est `/dev/<nom>`, **exactement** celle que l'inventaire publie
# sous `storage.disks[].device` : c'est ce qui relie la mesure au disque sans
# rien supposer.
#
# Rien du tout est un résultat, et le bon. Un tmpfs ne décrit aucun disque ; un
# volume réparti sur plusieurs supports — agrégat, miroir, groupe LVM — n'a pas
# de disque unique à nommer, et en choisir un serait une invention.
bench_storage_device() {
  local path=${1-} source='' disks='' count=''
  [ -n "$path" ] || path=${TMPDIR:-/tmp}
  has_cmd df && has_cmd lsblk || return 0

  source=$(run_cmd df -P "$path" | awk 'NR == 2 { print $1 }')
  case "$source" in
    /dev/*) ;;
    *) return 0 ;;
  esac

  # `-s` remonte les dépendances au lieu de les descendre : d'une partition vers
  # son disque, d'un volume logique vers tous ses supports. `-r` désactive le
  # rendu arborescent, dont les caractères de branche pollueraient les noms.
  disks=$(run_cmd lsblk -rnso NAME,TYPE "$source" | awk '$2 == "disk" { print $1 }' | sort -u)
  count=$(printf '%s' "$disks" | grep -c . || true)
  [ "$count" = '1' ] || return 0
  printf '/dev/%s' "$disks"
}

# Débits disque, mesurés sur un fichier temporaire du répertoire de sortie.
#
# `oflag=direct` et `iflag=direct` contournent le cache du noyau : sans eux, la
# mesure décrirait la mémoire, pas le disque.
bench_storage() {
  local mode=$1 target=''
  case "$mode" in
    write) target='storage-sequential-write' ;;
    read) target='storage-sequential-read' ;;
    random) target='storage-random-read' ;;
  esac

  if [ "$mode" = 'random' ]; then
    has_cmd fio || {
      bench_skipped "$target" 'fio' 'fio absent : mesure aléatoire indisponible.'
      return 0
    }
  fi

  # La taille du fichier de travail suit la place libre : elle n'est plus une
  # constante. Sur un disque presque plein, la mesure est écartée plutôt que
  # tentée — le diagnostic ne doit pas être ce qui déclenche la panne.
  local mib=''
  mib=$(bench_storage_mib)
  [ "$mib" -gt 0 ] || {
    bench_skipped "$target" 'dd' \
      "place libre insuffisante dans ${TMPDIR:-/tmp} : mesure écartée pour ne pas remplir le disque."
    return 0
  }

  # Résolu **avant** la mesure : `df` et `lsblk` sur un disque qu'on vient de
  # remplir de 256 Mio répondent aussi bien, mais faire dépendre l'identité du
  # disque de l'état où la mesure l'a laissé n'a aucune raison d'être.
  local disk=''
  disk=$(bench_storage_device "${TMPDIR:-/tmp}")

  log_step "Banc d’essai stockage ($mode, $mib Mio)"

  local work=''
  work=$(mktemp "${TMPDIR:-/tmp}/sysaudit-bench-disk-XXXXXX") || {
    bench_skipped "$target" 'dd' 'création du fichier de travail impossible.'
    return 0
  }

  local seconds='' started_at='' temp_before=''
  seconds=$(bench_seconds)
  local start_ms='' duration='' score='' parameters=''

  # Le fichier lu doit exister avant le chronomètre : l'écrire pendant la mesure
  # de lecture reviendrait à mesurer l'écriture.
  if [ "$mode" != 'write' ]; then
    dd if=/dev/zero of="$work" bs=1M count="$mib" conv=fdatasync status=none 2>/dev/null || true
  fi

  started_at=$(iso_now)
  temp_before=$(read_cpu_temperature)
  bench_sampler_start "$target"
  # `oflag=direct` contourne le cache du noyau : sans lui, la mesure décrirait la
  # mémoire, pas le disque. Tous les systèmes de fichiers ne l'acceptent pas —
  # tmpfs et certains montages réseau le refusent — et la capacité se vérifie
  # une fois, avant la boucle, plutôt qu'à chaque passe.
  #
  # Le test porte sur un fichier **distinct** : `dd` tronque son fichier de
  # sortie, et sonder sur le fichier de travail le ramenait à un mébioctet. La
  # mesure de lecture parcourait alors 1 Mio en croyant en lire 256, et
  # rapportait un débit de plus de cent gibioctets par seconde.
  local probe='' direct='oflag=direct'
  probe=$(mktemp "${TMPDIR:-/tmp}/sysaudit-bench-probe-XXXXXX") || probe=''
  if [ -n "$probe" ]; then
    dd if=/dev/zero of="$probe" bs=1M count=1 oflag=direct status=none 2>/dev/null || direct=''
    rm -f "$probe"
  else
    direct=''
  fi
  [ -n "$direct" ] || record_issue "benchmark.$target" 'warning' \
    'Accès direct refusé par le système de fichiers : la mesure inclut le cache du noyau.' 'dd'

  local passes=1 loop=''
  case "$mode" in
    write)
      # Le nombre de passes est plafonné par le volume écrit, pas par la durée :
      # une mesure de vingt secondes à plusieurs Gio/s userait le support autant
      # qu'une journée d'utilisation normale.
      local max_passes=''
      max_passes=$(bench_write_passes "$mib")
      parameters="bs=1M count=$mib $direct conv=fdatasync, $max_passes passe(s) au plus"
      # shellcheck disable=SC2086  # `$direct` est vide ou `oflag=direct`, construit ici.
      loop=$(bench_loop $((seconds * 1000)) "$max_passes" \
        dd if=/dev/zero of="$work" bs=1M count="$mib" $direct conv=fdatasync status=none)
      passes=${loop%% *}
      duration=${loop##* }
      ;;
    read)
      parameters="bs=1M count=$mib ${direct:+iflag=direct}"
      # shellcheck disable=SC2086  # idem : forme construite localement.
      loop=$(bench_loop $((seconds * 1000)) 4096 \
        dd if="$work" of=/dev/null bs=1M ${direct:+iflag=direct} status=none)
      passes=${loop%% *}
      duration=${loop##* }
      ;;
    random)
      # Lecture seule : une mesure aléatoire en écriture userait le support pour
      # un chiffre que la lecture donne déjà à moindre coût.
      parameters="--rw=randread --bs=4k --size=${mib}M --runtime=$seconds --direct=1"
      start_ms=$(clock_ms)
      local fio_out=''
      fio_out=$(bench_run fio --name=sysaudit --filename="$work" --rw=randread --bs=4k \
        --size="${mib}M" --runtime="$seconds" --time_based --direct=1 --minimal) || fio_out=''
      duration=$(($(clock_ms) - start_ms))
      # Champ 7 de la sortie minimale de fio : débit de lecture en Kio/s.
      score=$(printf '%s' "$fio_out" | awk -F';' 'NR==1 { printf "%.1f", $7 / 1024 }')
      ;;
  esac
  bench_sampler_stop

  # Nettoyage garanti : le fichier de travail disparaît quel que soit le sort de
  # la mesure, y compris quand elle n'a rien produit.
  rm -f "$work"

  if [ "$mode" != 'random' ] && [ "$duration" -gt 0 ]; then
    score=$(awk -v mib="$mib" -v n="$passes" -v ms="$duration" \
      'BEGIN { printf "%.1f", (mib * n) / (ms / 1000) }')
  fi

  [ -n "$score" ] || {
    bench_failed "$target" "$([ "$mode" = 'random' ] && printf 'fio' || printf 'dd')" \
      'la mesure n’a produit aucun débit exploitable.'
    return 0
  }

  local tool='dd' version=''
  [ "$mode" = 'random' ] && tool='fio'
  version=$([ "$tool" = 'fio' ] && run_cmd fio --version | sed 's/^fio-//' || dd_version)

  bench_result_device "$target" "$disk" "$tool" "$version" \
    "$([ "$mode" = 'random' ] && printf 'lecture aléatoire 4 Ko' || printf 'accès séquentiel')" \
    "$parameters, $passes passe(s)" "$duration" "$score" 'MiB/s' "$started_at" "$temp_before"
}

# --- GPU ---------------------------------------------------------------------

# Le modèle d'une carte, tel que **l'inventaire** le publie.
#
# Même source et mêmes coupes que `parse_gpu_line` dans `hardware.sh` : c'est ce
# qui permet à l'analyse de relier une mesure à la carte inventoriée sans
# rapprocher deux libellés « qui se ressemblent ». Un appariement approximatif
# entre deux cartes du même fabricant est exactement l'erreur qui attribuerait
# le score d'une carte dédiée à un adaptateur d'affichage virtuel.
bench_gpu_model() {
  local address=${1-}
  [ -n "$address" ] || return 0
  [ "$(capability_tool lspci)" = 'true' ] || return 0
  run_cmd lspci -nn -s "$address" |
    sed -E 's/^[^ ]+ [^:]+: //; s/ \[[0-9a-f]{4}:[0-9a-f]{4}\].*$//' | head -n1
}

# L'adresse PCI d'un nœud DRM, ou rien.
#
# **Lue du nœud lui-même**, et non devinée par la position. La version
# précédente prenait la n-ième ligne de `lspci` pour la carte `cardN` : les deux
# énumérations n'ont aucune raison de coïncider, et sur une machine dont la
# carte intégrée est déclarée avant la carte dédiée, ce raccourci nommait la
# mauvaise. `/sys/class/drm/cardN/device` pointe sur le périphérique PCI réel ;
# c'est un fait, pas un ordre supposé.
bench_gpu_address() {
  local card=${1-} cible=''
  [ -e "$card/device" ] || return 0
  cible=$(readlink -f "$card/device" 2>/dev/null) || return 0
  cible=$(basename "$cible")
  # `0000:01:00.0` en sysfs, `01:00.0` chez lspci : le domaine par défaut n'est
  # pas écrit par lspci, et le garder ne trouverait aucune ligne.
  case "$cible" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f]:*) printf '%s' "${cible#0000:}" ;;
    *) return 0 ;;
  esac
}

# Cartes graphiques présentes, une par ligne :
# « index<TAB>modèle inventorié<TAB>étiquette d'affichage ».
#
# L'index est celui des nœuds DRM (`/dev/dri/card0`, `card1`…), le seul qui
# permette ensuite de désigner une carte à `DRI_PRIME`.
#
# **Le modèle est vide quand la carte n'a pas pu être identifiée**, et c'est
# tout l'intérêt de le séparer de l'étiquette. L'étiquette sert au journal et au
# rapport, où « carte 1 » est une information suffisante ; le modèle sert à
# rattacher un score à un composant, et une valeur approximative y produirait un
# rang faux plutôt qu'un rang absent.
bench_gpu_devices() {
  local names='' card='' index='' address='' model=''
  [ "$(capability_tool lspci)" = 'true' ] &&
    names=$(run_cmd lspci |
      grep -iE 'VGA compatible controller|3D controller|Display controller' |
      sed -E 's/^[^ ]+ [^:]+: //')

  local found=0
  for card in "$SYSFS_ROOT"/class/drm/card[0-9]*; do
    [ -d "$card" ] || continue
    # `card0-HDMI-A-1` est un connecteur, pas une carte.
    index=$(basename "$card" | sed -nE 's/^card([0-9]+)$/\1/p')
    [ -n "$index" ] || continue
    address=$(bench_gpu_address "$card")
    model=$(bench_gpu_model "$address")
    printf '%s\t%s\t%s\n' "$index" "$model" \
      "$(printf '%s' "${model:-$(printf '%s' "$names" | sed -n "$((index + 1))p")}" | cut -c1-64)"
    found=$((found + 1))
  done

  # Sans nœud DRM — machine virtuelle, conteneur — il reste éventuellement des
  # cartes vues par lspci : elles sont rapportées sans index utilisable, et sans
  # modèle : rien ne dit laquelle `glmark2` a effectivement chargée.
  if [ "$found" -eq 0 ] && [ -n "$names" ]; then
    printf '%s' "$names" | while IFS= read -r name; do
      [ -n "$name" ] && printf '\t\t%s\n' "$(printf '%s' "$name" | cut -c1-64)"
    done
  fi
  return 0
}

# Les scènes mesurées par glmark2, en une liste fixe.
#
# La suite complète — le défaut de `glmark2 --off-screen` — dure **plus de trois
# minutes** sur une machine de bureau récente. Le budget de `bench_run` est de
# 120 s hors niveau Poussée : la mesure graphique était donc tuée à chaque
# audit Rapide, Normale et Complète, et le rapport en donnait une cause fausse.
#
# Quatre scènes suffisent à décrire une carte, et elles sont choisies pour
# couvrir des usages distincts : géométrie, échantillonnage de texture,
# éclairage par pixel, et une passe de post-traitement. Elles tiennent en une
# quarantaine de secondes.
#
# **La liste est la même à tous les niveaux, et c'est essentiel.** Le score de
# glmark2 est la moyenne des scènes exécutées : deux audits qui n'auraient pas
# joué les mêmes scènes produiraient des scores incomparables, sans que rien ne
# le signale. Elle figure dans `parameters` du résultat, pour que la comparaison
# reste vérifiable.
bench_glmark2_scenes() {
  printf -- '-b build -b texture -b shading -b bump'
}

# Cadence de rendu relevée par glmark2, scène par scène.
#
# L'outil publie une ligne par scène :
#
#     [build] <default>: FPS: 56947 FrameTime: 0.018 ms
#
# Le score global n'en est qu'une moyenne pondérée, et il cache ce que ces
# lignes montrent : une carte régulière et une carte qui s'effondre sur une
# scène produisent le même chiffre.
#
# Écrit deux objets JSON agrégés — cadence puis temps de trame — ou rien si
# aucune ligne n'est exploitable. Le format d'agrégation est celui du reste du
# schéma : `sampleCount` y porte le nombre de **scènes**, non de secondes.
#
# D'où `sampleIntervalMs` et `sampleDurationMs` en `NOT_APPLICABLE` : glmark2
# publie une mesure par scène, et les scènes n'ont ni cadence d'échantillonnage
# ni durée commune. Les **omettre** n'était pas une option — le schéma les exige
# comme tout champ `maybe`, et un rapport qui les taisait partait en HTTP 400.
# Les remplir d'une durée inventée aurait été pire : une fenêtre d'observation
# fausse se serait lue comme une mesure.
# Motif d'échantillonnage de glmark2, identique pour la cadence et le temps de
# trame. Écrit une fois : deux copies divergeraient au premier ajustement.
bench_glmark2_sampling_fields() {
  local detail='une mesure par scène, non par intervalle'
  json_join \
    "$(jf_raw sampleIntervalMs "$(j_unknown NOT_APPLICABLE "$detail")")" \
    "$(jf_raw sampleDurationMs "$(j_unknown NOT_APPLICABLE "$detail")")"
}

bench_glmark2_rendering() {
  local output=${1-}
  [ -n "$output" ] || return 0

  local stats=''
  stats=$(printf '%s' "$output" | LC_ALL=C awk '
    match($0, /FPS: [0-9]+/) {
      fps = substr($0, RSTART + 5, RLENGTH - 5) + 0
      if (fps <= 0) next
      if (scenes == 0 || fps < fps_min) fps_min = fps
      if (scenes == 0 || fps > fps_max) fps_max = fps
      fps_sum += fps
      fps_last = fps

      if (match($0, /FrameTime: [0-9.]+/)) {
        ft = substr($0, RSTART + 11, RLENGTH - 11) + 0
        if (ft > 0) {
          if (frames == 0 || ft < ft_min) ft_min = ft
          if (frames == 0 || ft > ft_max) ft_max = ft
          ft_sum += ft
          ft_last = ft
          frames++
        }
      }
      scenes++
    }
    END {
      if (scenes == 0) { print "0 0"; exit }
      printf "%d %d %d %d %.1f %d %.3f %.3f %.3f %.3f",
        scenes, fps_last, fps_min, fps_max, fps_sum / scenes,
        frames, ft_last, ft_min, ft_max, (frames > 0 ? ft_sum / frames : 0)
    }')

  local scenes='' fps_last='' fps_min='' fps_max='' fps_avg=''
  local frames='' ft_last='' ft_min='' ft_max='' ft_avg=''
  read -r scenes fps_last fps_min fps_max fps_avg frames ft_last ft_min ft_max ft_avg <<<"$stats"
  [ -n "$scenes" ] && [ "$scenes" -gt 0 ] 2>/dev/null || return 0

  jf_raw framesPerSecond "$(json_object \
    "$(jf_maybe_num current "$fps_last")" \
    "$(jf_maybe_num minimum "$fps_min")" \
    "$(jf_maybe_num maximum "$fps_max")" \
    "$(jf_maybe_num average "$fps_avg")" \
    "$(jf_str unit 'FPS')" \
    "$(jf_raw sampleCount "$scenes")" \
    "$(bench_glmark2_sampling_fields)" \
    "$(jf_str source 'glmark2 --off-screen')")"

  # Le temps de trame n'est publié que si des lignes en portaient un : une
  # version de glmark2 qui ne le donnerait pas ne doit pas produire un zéro.
  [ "$frames" -gt 0 ] 2>/dev/null || return 0
  printf ','
  jf_raw frameTimeMs "$(json_object \
    "$(jf_maybe_num current "$ft_last")" \
    "$(jf_maybe_num minimum "$ft_min")" \
    "$(jf_maybe_num maximum "$ft_max")" \
    "$(jf_maybe_num average "$ft_avg")" \
    "$(jf_str unit 'ms')" \
    "$(jf_raw sampleCount "$frames")" \
    "$(bench_glmark2_sampling_fields)" \
    "$(jf_str source 'glmark2 --off-screen')")"
}

# Télémétrie d'une carte NVIDIA, via NVML (`nvidia-smi`).
#
# Écrit « utilisation,horloge,horloge mémoire,VRAM utilisée,VRAM totale,
# température,puissance » ou rien. Les unités de `nvidia-smi` sont converties
# ici : le schéma attend des octets, pas des mébioctets.
bench_gpu_telemetry() {
  local index=${1-}
  has_cmd nvidia-smi || return 0
  [ -n "$index" ] || return 0

  run_cmd nvidia-smi \
    --query-gpu=utilization.gpu,clocks.current.graphics,clocks.current.memory,memory.used,memory.total,temperature.gpu,power.draw \
    --format=csv,noheader,nounits -i "$index" 2>/dev/null | head -n1
}

# Fragment JSON de télémétrie GPU, ou rien si aucune source ne répond.
bench_gpu_telemetry_json() {
  local raw=${1-}
  [ -n "$raw" ] || return 0

  local usage='' core='' mem_clock='' used='' total='' temp='' power=''
  IFS=',' read -r usage core mem_clock used total temp power <<<"$(printf '%s' "$raw" | tr -d ' ')"

  # `nvidia-smi` rend « [N/A] » pour ce que la carte n'expose pas : le prendre
  # pour un nombre produirait une horloge nulle sur une carte qui tourne.
  local numeric='' field=''
  for field in usage core mem_clock used total temp power; do
    numeric=${!field}
    [[ $numeric =~ ^[0-9]+([.][0-9]+)?$ ]] || printf -v "$field" '%s' ''
  done

  [ -n "$used" ] && used=$((used * 1048576))
  [ -n "$total" ] && total=$((total * 1048576))

  jf_raw gpu "$(json_object \
    "$(jf_maybe_num utilizationPercent "$usage" NOT_AVAILABLE 'utilisation non exposée par le pilote')" \
    "$(jf_maybe_num coreClockMhz "$core" NOT_AVAILABLE 'fréquence non exposée par le pilote')" \
    "$(jf_maybe_num memoryClockMhz "$mem_clock" NOT_AVAILABLE 'fréquence mémoire non exposée par le pilote')" \
    "$(jf_maybe_num vramUsedBytes "$used" NOT_AVAILABLE)" \
    "$(jf_maybe_num vramTotalBytes "$total" NOT_AVAILABLE)" \
    "$(jf_maybe_num temperatureCelsius "$temp" NOT_AVAILABLE 'aucun capteur thermique GPU lisible')" \
    "$(jf_maybe_num powerWatts "$power" NOT_AVAILABLE 'puissance non exposée par le pilote')")"
}

# Banc d'essai GPU, **une mesure par carte**.
#
# glmark2 rend sur la carte par défaut ; `DRI_PRIME` en désigne une autre. Sur
# une machine à deux cartes, publier un score unique laissait croire que les
# deux avaient été mesurées — ou que la seconde n'existait pas.
bench_gpu() {
  local devices=''
  devices=$(bench_gpu_devices)

  if [ -z "$devices" ]; then
    bench_skipped 'gpu' 'glmark2' 'aucune carte graphique détectée sur cette machine.'
    return 0
  fi

  local results='' index='' model='' label=''
  while IFS=$'\t' read -r index model label; do
    [ -n "$index" ] || [ -n "$label" ] || continue
    results=$(json_join "$results" "$(bench_gpu_device "$index" "$model" "$label")")
  done <<<"$devices"

  printf '%s' "$results"
}

bench_gpu_device() {
  local index=${1-} model=${2-} label=${3-}
  local target='gpu'
  [ -n "$label" ] || label="carte $index"

  has_cmd glmark2 || {
    bench_skipped_device "$target" "$label" 'glmark2' \
      'glmark2 absent : mesure GPU indisponible (paquet glmark2).'
    return 0
  }

  log_step "Banc d’essai GPU ($label)"

  local started_at='' temp_before='' start_ms='' output='' duration='' score=''
  local telemetry_before='' telemetry_after=''
  started_at=$(iso_now)
  temp_before=$(read_cpu_temperature)
  telemetry_before=$(bench_gpu_telemetry "$index")
  bench_sampler_start 'gpu'
  start_ms=$(clock_ms)
  # `DRI_PRIME` désigne la carte pour les pilotes libres ; sans index utilisable,
  # la mesure porte sur la carte par défaut, ce que l'étiquette rappelle.
  local status=0 scenes=''
  scenes=$(bench_glmark2_scenes)
  # shellcheck disable=SC2086  # la liste de scènes est construite ici, pas reçue.
  if [ -n "$index" ]; then
    output=$(DRI_PRIME="$index" bench_run glmark2 --off-screen $scenes) || status=$?
  else
    output=$(bench_run glmark2 --off-screen $scenes) || status=$?
  fi
  [ "$status" -eq 0 ] || output=''
  duration=$(($(clock_ms) - start_ms))
  bench_sampler_stop
  # Relevée juste après la charge : une télémétrie prise à froid ne dirait rien
  # de ce que la carte fait sous charge.
  telemetry_after=$(bench_gpu_telemetry "$index")
  [ -n "$telemetry_after" ] || telemetry_after=$telemetry_before

  # Le dépassement de délai a son propre message. Le confondre avec un échec de
  # rendu envoyait chercher un pilote absent là où il n'y avait qu'une mesure
  # trop longue pour son budget.
  if [ "$status" -eq "$BENCH_TIMED_OUT" ]; then
    bench_failed_device "$target" "$label" 'glmark2' \
      "glmark2 a dépassé le budget de $(($(bench_seconds) * 12 + 60)) s et a été interrompu : aucun score."
    return 0
  fi

  # `[[:space:]]*` en tête, et ce n'est pas de la prudence décorative : glmark2
  # **indente** sa ligne de score depuis la version 2023.01, celle que livrent
  # Debian et Ubuntu actuels. L'ancrage en début de ligne ne correspondait donc
  # plus à rien, et toute mesure graphique aboutissait à « glmark2 n'a produit
  # aucun score exploitable » — un diagnostic faux, qui envoyait chercher un
  # pilote absent sur des machines dont la carte fonctionnait parfaitement.
  score=$(printf '%s' "$output" |
    sed -nE 's/^[[:space:]]*glmark2 Score:[[:space:]]+([0-9]+).*$/\1/p' | head -n1)
  [ -n "$score" ] || {
    bench_failed_device "$target" "$label" 'glmark2' \
      'glmark2 n’a produit aucun score exploitable (pas de contexte de rendu ?).'
    return 0
  }

  # Le **modèle**, et non l'étiquette : c'est lui qui rattache le score à une
  # carte inventoriée. Vide quand la carte n'a pas pu être identifiée, auquel cas
  # l'analyse écarte la mesure pour ambiguïté plutôt que de la créditer au hasard.
  bench_result_device "$target" "$model" 'glmark2' \
    "$(run_cmd glmark2 --version | awk '{print $NF}')" 'rendu synthétique hors écran' \
    "--off-screen $scenes${index:+ DRI_PRIME=$index}" "$duration" "$score" 'points' \
    "$started_at" "$temp_before" \
    "$(json_join "$(bench_gpu_telemetry_json "$telemetry_after")" "$(bench_glmark2_rendering "$output")")"
}

# --- Charges mixtes ----------------------------------------------------------
#
# Le banc d'essai mesurait le processeur seul et la carte graphique seule. Une
# machine dont chacun tient séparément peut pourtant s'effondrer quand les deux
# travaillent ensemble : alimentation insuffisante, budget thermique partagé
# dans un châssis d'ordinateur portable, plafond de puissance commun aux deux.
# Aucune des deux mesures isolées ne le montre.
#
# Deux charges, et la différence entre elles est réelle :
#
# - `gaming` occupe la carte à fond et le processeur **à moitié**, ce qui décrit
#   la répartition d'un jeu — le rendu domine, le reste du travail tient sur
#   quelques fils. Elle ne prétend pas être un jeu : la charge graphique reste
#   celle de glmark2, hors écran et synthétique, et `parameters` le dit.
# - `cpu-gpu` sature les deux. C'est le pire cas thermique et électrique de la
#   machine, celui qui révèle un plafond partagé.
#
# Ni l'une ni l'autre n'est **jamais simulée**. Sans charge graphique
# exécutable, ou sans de quoi composer la charge processeur, la mesure est
# écartée avec son motif — jamais un score obtenu sur un seul des deux
# composants et présenté comme une charge mixte.

# Nombre de fils de la composante processeur, selon la charge.
bench_mixed_threads() {
  local target=${1-} total=''
  total=$(nproc 2>/dev/null || printf '1')
  [[ $total =~ ^[0-9]+$ ]] && [ "$total" -ge 1 ] || total=1
  if [ "$target" = 'gaming' ]; then
    # La moitié, arrondie au supérieur : sur un biprocesseur, la moitié de deux
    # reste un fil, et une charge mixte sans charge processeur n'en est pas une.
    printf '%s' $(((total + 1) / 2))
  else
    printf '%s' "$total"
  fi
}

# Mesure une charge mixte sur une carte donnée.
bench_mixed_device() {
  local target=${1-} index=${2-} label=${3-}
  [ -n "$label" ] || label="carte $index"

  has_cmd glmark2 || {
    bench_skipped_device "$target" "$label" 'glmark2' \
      'glmark2 absent : la charge mixte ne peut pas être composée (paquet glmark2). Aucun score n’est publié — une charge processeur seule ne décrirait pas cette mesure.'
    return 0
  }
  has_cmd openssl || {
    bench_skipped_device "$target" "$label" 'openssl' \
      'openssl absent : la composante processeur de la charge mixte ne peut pas être composée. Le score graphique seul serait celui de la mesure `gpu`, pas de celle-ci.'
    return 0
  }

  local threads='' scenes='' seconds=''
  threads=$(bench_mixed_threads "$target")
  scenes=$(bench_glmark2_scenes)
  seconds=$(bench_seconds)

  local human='charge mixte — rendu et processeur'
  [ "$target" = 'cpu-gpu' ] && human='processeur multi-cœur + graphique'
  log_step "Banc d’essai $human ($label, $threads fil(s) processeur)"

  local block=''
  [ "$(openssl_major)" -ge 3 ] 2>/dev/null && block='-bytes 16384'

  # La composante processeur doit couvrir toute la durée du rendu, dont la fin
  # n'est pas connue à l'avance. Elle est donc lancée pour le budget entier de
  # `bench_run`, puis arrêtée dès que le rendu se termine : une charge qui
  # s'arrêterait avant lui laisserait la fin du rendu se faire au repos, et la
  # mesure ne décrirait plus une charge mixte.
  local budget=$((seconds * 12 + 60))

  local started_at='' temp_before='' start_ms='' output='' duration='' score=''
  local telemetry_before='' telemetry_after='' status=0 load_pid=''
  started_at=$(iso_now)
  temp_before=$(read_cpu_temperature)
  telemetry_before=$(bench_gpu_telemetry "$index")

  bench_sampler_start "$target"
  start_ms=$(clock_ms)

  # `>/dev/null 2>&1` n'est pas décoratif : la mesure s'exécute dans une
  # substitution de commande, et un processus d'arrière-plan qui garderait le
  # tube de sortie ouvert ferait attendre l'appelant après la fin du rendu.
  # C'est le même piège que celui de l'échantillonneur.
  # shellcheck disable=SC2086  # les paramètres sont construits ici, pas reçus.
  LC_ALL=C openssl speed -evp aes-128-cbc -seconds "$budget" $block -multi "$threads" \
    >/dev/null 2>&1 &
  load_pid=$!

  # shellcheck disable=SC2086  # la liste de scènes est construite ici, pas reçue.
  if [ -n "$index" ]; then
    output=$(DRI_PRIME="$index" bench_run glmark2 --off-screen $scenes) || status=$?
  else
    output=$(bench_run glmark2 --off-screen $scenes) || status=$?
  fi
  [ "$status" -eq 0 ] || output=''
  duration=$(($(clock_ms) - start_ms))

  # `openssl speed -multi` est un père qui a essaimé : le tuer seul laisserait
  # ses fils charger la machine pendant tout le reste du banc d'essai, et les
  # mesures suivantes décriraient cette charge résiduelle. Le groupe de
  # processus n'est pas une option — sans contrôle de tâches, il est celui du
  # script entier —, les enfants sont donc terminés nommément.
  bench_kill_tree "$load_pid"

  bench_sampler_stop
  telemetry_after=$(bench_gpu_telemetry "$index")
  [ -n "$telemetry_after" ] || telemetry_after=$telemetry_before

  if [ "$status" -eq "$BENCH_TIMED_OUT" ]; then
    bench_failed_device "$target" "$label" 'glmark2' \
      "le rendu a dépassé le budget de ${budget} s sous charge mixte et a été interrompu : aucun score."
    return 0
  fi

  score=$(printf '%s' "$output" |
    sed -nE 's/^[[:space:]]*glmark2 Score:[[:space:]]+([0-9]+).*$/\1/p' | head -n1)
  [ -n "$score" ] || {
    bench_failed_device "$target" "$label" 'glmark2' \
      'le rendu n’a produit aucun score exploitable sous charge mixte.'
    return 0
  }

  # Les scènes sont **les mêmes** que celles de la mesure `gpu`, et c'est tout
  # l'intérêt : l'écart entre les deux scores est ce que cette mesure apporte.
  # Deux listes de scènes différentes rendraient la comparaison muette.
  bench_result_device "$target" "$label" 'glmark2 + openssl' \
    "$(run_cmd glmark2 --version | awk '{print $NF}')" \
    'rendu synthétique hors écran sous charge AES-128-CBC' \
    "glmark2 --off-screen $scenes${index:+ DRI_PRIME=$index} ; openssl speed -evp aes-128-cbc -multi $threads" \
    "$duration" "$score" 'points' "$started_at" "$temp_before" \
    "$(json_join "$(bench_gpu_telemetry_json "$telemetry_after")" "$(bench_glmark2_rendering "$output")")"
}

# Termine un processus et ses enfants directs.
#
# `openssl speed -multi N` engendre N fils de calcul. Tuer le père sans eux
# laisserait la machine chargée pendant les mesures suivantes, qui décriraient
# alors cette charge résiduelle plutôt que ce qu'elles prétendent mesurer.
bench_kill_tree() {
  local pid=${1-}
  [ -n "$pid" ] || return 0
  local child=''
  for child in $(pgrep -P "$pid" 2>/dev/null || true); do
    kill "$child" 2>/dev/null || true
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  return 0
}

# Charge mixte, sur chaque carte détectée.
bench_mixed() {
  local target=${1-} devices=''
  devices=$(bench_gpu_devices)

  if [ -z "$devices" ]; then
    bench_skipped "$target" 'glmark2' \
      'aucune carte graphique détectée : une charge mixte sans composante graphique n’en est pas une.'
    return 0
  fi

  # L'étiquette suffit ici, et le modèle est délibérément ignoré : une charge
  # mixte décrit la machine, jamais un composant. Lui donner un modèle de carte
  # inviterait à la classer comme une mesure graphique, ce qu'elle n'est pas.
  local results='' index='' model='' label=''
  while IFS=$'\t' read -r index model label; do
    [ -n "$index" ] || [ -n "$label" ] || continue
    results=$(json_join "$results" "$(bench_mixed_device "$target" "$index" "$label")")
  done <<<"$devices"

  printf '%s' "$results"
}
