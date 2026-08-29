#!/usr/bin/env bash
# SysAudit — progression pondérée, heartbeat et refroidissement.
#
# ## Le défaut que ce fichier corrige
#
# La barre existante compte les collecteurs terminés sur le nombre total. Chaque
# étape y pèse donc pareil — et sur un profil de charge, une seule d'entre elles
# dure six cents secondes quand les vingt autres en durent une. La barre
# atteignait 95 % en quelques secondes, puis ne bougeait plus pendant dix
# minutes. L'utilisateur en concluait, raisonnablement, que le programme était
# planté.
#
# La correction ne consiste pas à ralentir la barre : elle consiste à **peser
# les étapes par leur coût prévu**. Une étape de six cents secondes occupe alors
# la moitié de la barre, et la remplit progressivement pendant qu'elle tourne.
#
# ## Ce qui reste honnête
#
# Une étape dont la durée n'est pas prévisible ne reçoit **aucun pourcentage**.
# Elle affiche un compteur de temps écoulé et un heartbeat, ce qui répond à la
# seule question que l'utilisateur se pose — « est-ce que ça avance ? » — sans
# fabriquer une fraction dont personne ne connaît le dénominateur.
#
# ## Pourquoi ces fonctions sont pures
#
# Elles ne lisent ni l'horloge, ni le terminal, ni aucun état global : tout
# entre par arguments. C'est ce qui les rend testables sans TTY et sans
# attendre six cents secondes — la partie qui échouait justement à être
# vérifiée jusqu'ici.

# Poids prévus des étapes, sous la forme `nom=secondes`, séparés par des espaces.
#
# Ce ne sont pas des mesures : ce sont des ordres de grandeur, et c'est
# suffisant. Une barre pondérée par des durées approximatives reste infiniment
# plus juste qu'une barre qui donne le même poids à une lecture de sysfs et à
# dix minutes de charge processeur.
PROGRESS_WEIGHTS=''

# Poids par défaut d'une étape dont le coût n'a pas été déclaré.
readonly PROGRESS_DEFAULT_WEIGHT=1

# Déclare les coûts prévus. `$1` = `baseline=15 cpu-sustained=600 …`
progress_weights_set() {
  PROGRESS_WEIGHTS=${1-}
}

# Coût prévu d'une étape, en secondes.
#
# Une étape inconnue vaut le poids par défaut plutôt que zéro : à zéro, elle
# n'avancerait jamais la barre, et le lecteur verrait une étape s'exécuter sans
# qu'il se passe rien.
progress_weight_of() {
  local name=${1-} entry=''
  for entry in $PROGRESS_WEIGHTS; do
    case "$entry" in
      "$name="*)
        local value=${entry#*=}
        case "$value" in
          '' | *[!0-9]*) printf '%s' "$PROGRESS_DEFAULT_WEIGHT" ;;
          *) printf '%s' "$value" ;;
        esac
        return 0
        ;;
    esac
  done
  printf '%s' "$PROGRESS_DEFAULT_WEIGHT"
}

# Somme des coûts prévus de toutes les étapes déclarées.
progress_weight_total() {
  local entry='' total=0 value=''
  for entry in $PROGRESS_WEIGHTS; do
    value=${entry#*=}
    case "$value" in
      '' | *[!0-9]*) value=$PROGRESS_DEFAULT_WEIGHT ;;
    esac
    total=$((total + value))
  done
  printf '%s' "$total"
}

# Pourcentage global.
#
# $1 somme des poids des étapes terminées
# $2 poids de l'étape en cours
# $3 secondes écoulées dans l'étape en cours
# $4 somme de tous les poids
#
# L'étape en cours contribue **au prorata de son temps écoulé**. C'est tout
# l'objet du fichier : pendant les six cents secondes de charge, la barre
# continue de monter.
#
# Le résultat est borné à [0, 100] et ne peut pas atteindre 100 tant qu'il reste
# du poids à consommer — une barre pleine sur un audit qui continue est le
# deuxième défaut le plus déroutant après une barre figée.
progress_overall_percent() {
  local done_weight=${1:-0} active_weight=${2:-0} elapsed=${3:-0} total=${4:-0}

  case "$total" in '' | *[!0-9]* | 0) printf '0'; return 0 ;; esac
  case "$done_weight" in '' | *[!0-9]*) done_weight=0 ;; esac
  case "$active_weight" in '' | *[!0-9]*) active_weight=0 ;; esac
  case "$elapsed" in '' | *[!0-9]*) elapsed=0 ;; esac

  # La part de l'étape en cours est plafonnée à son propre poids : une étape qui
  # dure plus longtemps que prévu ne doit pas empiéter sur les suivantes.
  local partial=$elapsed
  [ "$partial" -le "$active_weight" ] || partial=$active_weight

  local consumed=$((done_weight + partial))
  [ "$consumed" -le "$total" ] || consumed=$total

  local percent=$((consumed * 100 / total))
  [ "$percent" -ge 0 ] || percent=0
  # 100 % est réservé à la fin réelle : tant qu'il reste du poids, on plafonne à
  # 99 plutôt que d'annoncer une fin qui n'a pas eu lieu.
  if [ "$percent" -ge 100 ] && [ "$consumed" -lt "$total" ]; then percent=99; fi
  [ "$percent" -le 100 ] || percent=100

  printf '%s' "$percent"
}

# Pourcentage de l'étape en cours.
#
# Rend une chaîne **vide** lorsque la durée prévue est inconnue ou nulle : c'est
# le refus explicite de fabriquer une fraction sans dénominateur. L'appelant
# affiche alors un compteur de temps, pas une barre.
progress_phase_percent() {
  local elapsed=${1:-0} expected=${2:-0}
  case "$expected" in '' | *[!0-9]* | 0) return 0 ;; esac
  case "$elapsed" in '' | *[!0-9]*) elapsed=0 ;; esac

  local percent=$((elapsed * 100 / expected))
  [ "$percent" -ge 0 ] || percent=0
  [ "$percent" -le 100 ] || percent=100
  printf '%s' "$percent"
}

# Temps restant estimé, en secondes.
#
# Vide lorsqu'il n'est pas calculable. Une estimation absente est lisible ; une
# estimation inventée fait perdre confiance dans toutes les suivantes.
progress_eta_seconds() {
  local done_weight=${1:-0} active_weight=${2:-0} elapsed=${3:-0} total=${4:-0}
  case "$total" in '' | *[!0-9]* | 0) return 0 ;; esac
  case "$done_weight" in '' | *[!0-9]*) done_weight=0 ;; esac
  case "$active_weight" in '' | *[!0-9]*) active_weight=0 ;; esac
  case "$elapsed" in '' | *[!0-9]*) elapsed=0 ;; esac

  local partial=$elapsed
  [ "$partial" -le "$active_weight" ] || partial=$active_weight

  local remaining=$((total - done_weight - partial))
  [ "$remaining" -ge 0 ] || remaining=0
  printf '%s' "$remaining"
}

# Durée en `mm:ss`, ou `h:mm:ss` au-delà de l'heure.
#
# Le format compte : `600` ne se lit pas, `10:00` se lit. Une valeur non
# numérique rend `--:--`, qui dit « pas de durée » sans mentir sur zéro.
format_duration() {
  local seconds=${1-}
  case "$seconds" in
    '' | *[!0-9]*) printf -- '--:--'; return 0 ;;
  esac

  local hours=$((seconds / 3600))
  local minutes=$(((seconds % 3600) / 60))
  local rest=$((seconds % 60))

  if [ "$hours" -gt 0 ]; then
    printf '%d:%02d:%02d' "$hours" "$minutes" "$rest"
  else
    printf '%02d:%02d' "$minutes" "$rest"
  fi
}

# --- Heartbeat ---------------------------------------------------------------
#
# Pendant une phase longue, la barre se réécrit sur place et ne laisse aucune
# trace dans un journal redirigé. Le heartbeat existe pour ça : une ligne
# horodatée toutes les dix à quinze secondes, qui survit à la redirection et
# prouve que l'audit est vivant.

readonly HEARTBEAT_INTERVAL_DEFAULT=15

# Un heartbeat est-il dû ?
#
# $1 horodatage du dernier émis (vide si aucun), $2 horodatage courant,
# $3 intervalle en secondes.
#
# Le premier appel en émet toujours un : une phase longue doit s'annoncer dès
# son début, sinon les quinze premières secondes ressemblent à un blocage.
heartbeat_due() {
  local last=${1-} now=${2-} interval=${3:-$HEARTBEAT_INTERVAL_DEFAULT}
  case "$now" in '' | *[!0-9]*) return 1 ;; esac
  case "$interval" in '' | *[!0-9]* | 0) interval=$HEARTBEAT_INTERVAL_DEFAULT ;; esac
  case "$last" in '' | *[!0-9]*) return 0 ;; esac
  [ $((now - last)) -ge "$interval" ]
}

# Ligne de heartbeat, telle qu'elle part au journal.
#
# $1 horodatage lisible, $2 nom de la phase, $3 écoulé, $4 prévu, $5 mention
# facultative (température, débit…).
#
# Elle est en texte simple, sans code ANSI : c'est la version qui doit rester
# lisible dans un fichier, et c'est le seul endroit du rendu console qui ne
# dépend d'aucune capacité du terminal.
heartbeat_line() {
  local stamp=${1-} phase=${2-} elapsed=${3-} expected=${4-} note=${5-}
  local timing=''
  if [ -n "$expected" ] && [ "$expected" != '0' ]; then
    timing="$(format_duration "$elapsed")/$(format_duration "$expected")"
  else
    timing="$(format_duration "$elapsed")"
  fi

  if [ -n "$note" ]; then
    printf '[%s] %s — %s — %s — audit actif' "$stamp" "$phase" "$timing" "$note"
  else
    printf '[%s] %s — %s — audit actif' "$stamp" "$phase" "$timing"
  fi
}

# --- Refroidissement ---------------------------------------------------------
#
# Après une charge thermique, enchaîner immédiatement fausse la mesure suivante.
# Le refroidissement a donc deux fins possibles, et le rendu doit dire laquelle
# s'applique : le seuil atteint, ou le délai maximal écoulé.

# Le refroidissement est-il terminé ?
#
# $1 température courante, $2 cible, $3 écoulé, $4 délai maximal.
# Rend `target`, `timeout`, ou rien tant qu'il continue.
#
# Sans température lisible, seul le délai décide — et c'est écrit dans le rendu,
# faute de quoi l'utilisateur croirait la machine refroidie alors que personne
# n'a regardé.
cooldown_state() {
  local current=${1-} target=${2-} elapsed=${3:-0} timeout=${4:-60}
  case "$elapsed" in '' | *[!0-9]*) elapsed=0 ;; esac
  case "$timeout" in '' | *[!0-9]*) timeout=60 ;; esac

  # Les deux valeurs sont validées **séparément**. Les concaténer laissait
  # passer un relevé vide dès que la cible, elle, était numérique : `''` et
  # `'55'` forment `'55'`, qui est bien un nombre.
  local readable='true'
  case "$current" in '' | *[!0-9]*) readable='false' ;; esac
  case "$target" in '' | *[!0-9]*) readable='false' ;; esac
  if [ "$readable" = 'true' ] && [ "$current" -le "$target" ]; then
    printf 'target'
    return 0
  fi

  [ "$elapsed" -ge "$timeout" ] && { printf 'timeout'; return 0; }
  return 0
}

# Avancement du refroidissement, en pourcentage.
#
# $1 température de départ, $2 courante, $3 cible.
#
# Il mesure le chemin thermique parcouru, pas le temps écoulé : c'est ce que
# l'utilisateur regarde. Vide lorsque les trois valeurs ne permettent pas de le
# calculer — notamment quand le départ est déjà sous la cible, cas où il n'y a
# rien à refroidir.
cooldown_percent() {
  local start=${1-} current=${2-} target=${3-}
  case "$start" in '' | *[!0-9]*) return 0 ;; esac
  case "$current" in '' | *[!0-9]*) return 0 ;; esac
  case "$target" in '' | *[!0-9]*) return 0 ;; esac
  [ "$start" -gt "$target" ] || return 0

  local span=$((start - target))
  local moved=$((start - current))
  [ "$moved" -ge 0 ] || moved=0
  [ "$moved" -le "$span" ] || moved=$span

  printf '%s' $((moved * 100 / span))
}

# --- Émission d'un heartbeat -------------------------------------------------

# Horodatage du dernier heartbeat émis, par phase.
HEARTBEAT_LAST=''

# Ouvre une phase longue : le prochain heartbeat sera émis immédiatement.
heartbeat_phase_start() {
  HEARTBEAT_LAST=''
}

# Émet un heartbeat si l'échéance est atteinte.
#
# $1 nom de la phase, $2 secondes écoulées, $3 durée prévue (vide si inconnue),
# $4 mention facultative.
#
# Il passe par `console_emit`, donc au-dessus de la barre et jamais collé à
# elle. Hors terminal, `console_emit` écrit simplement une ligne — c'est
# exactement ce qu'un journal redirigé doit contenir, et c'est le seul témoin
# qui survit à la redirection.
heartbeat_tick() {
  local phase=${1-} elapsed=${2:-0} expected=${3-} note=${4-}
  local now=''
  now=$(date +%s 2>/dev/null || printf '')
  case "$now" in '' | *[!0-9]*) return 0 ;; esac

  heartbeat_due "$HEARTBEAT_LAST" "$now" "$HEARTBEAT_INTERVAL_DEFAULT" || return 0
  HEARTBEAT_LAST=$now

  console_emit "$(heartbeat_line "$(date +%H:%M:%S)" "$phase" "$elapsed" "$expected" "$note")"
}
