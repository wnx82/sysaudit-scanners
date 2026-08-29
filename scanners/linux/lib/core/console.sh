#!/usr/bin/env bash
# Présentation console du scanner.
#
# Tout part sur stderr : stdout reste réservé au JSON, pour que
# `sysaudit.sh --stdout | jq` continue de fonctionner. Une amélioration
# visuelle qui casserait ce contrat serait une régression, pas une refonte.
#
# Trois règles gouvernent ce fichier.
#
# **Rien n'est écrit sur la machine auditée.** L'affichage ne touche ni
# fichier, ni service, ni configuration.
#
# **Rien n'est inventé.** Le résumé n'affiche que ce que le rapport contient
# réellement ; une valeur absente disparaît de l'affichage au lieu d'être
# remplacée par un tiret qui se lirait comme « aucun ».
#
# **La progression suit les vraies étapes.** Aucun `sleep` décoratif : la barre
# avance quand un collecteur se termine, et pas avant.

# --- Capacités du terminal --------------------------------------------------

# Niveaux de verbosité : quiet < normal < verbose.
SYSAUDIT_VERBOSITY="${SYSAUDIT_VERBOSITY:-normal}"

# Passe par une fonction : une affectation directe depuis `sysaudit.sh` ferait
# croire à ShellCheck, qui analyse chaque fichier isolément, que la variable
# n'est jamais lue.
console_verbosity() { SYSAUDIT_VERBOSITY=$1; }

# --- Canal des messages du scanner ------------------------------------------
#
# `run_collector` capture la sortie standard d'un collecteur et **jette son
# erreur standard** : c'est ce qui empêche les avertissements de `dmidecode`, de
# `smartctl` ou de `lspci` de se mêler au rapport.
#
# Mais les collecteurs écrivent aussi leurs *propres* messages sur l'erreur
# standard — trente-cinq appels à `log_step` répartis dans douze fichiers — et
# ceux-là étaient jetés avec le reste. Personne ne l'avait vu, parce que rien ne
# manque à l'écran quand une étape dure une seconde. Un banc d'essai au niveau
# Poussée dure dix-sept minutes, et il ne disait **rien** : la barre restait à
# 95 %, et l'audit passait pour bloqué.
#
# Les messages du scanner passent donc par un descripteur distinct, ouvert par
# `console_open_log_fd` sur le terminal. `run_collector` continue de jeter
# l'erreur standard des outils ; les messages du scanner, eux, arrivent.
#
# Par défaut le descripteur **est** l'erreur standard : hors du scanner — dans
# les tests, par exemple — rien ne change.
SYSAUDIT_LOG_FD=2

# Ouvre le canal. Appelée une fois, avant la collecte.
console_open_log_fd() {
  # Aucune redirection autour de cet `exec`, et c'est une leçon coûteuse :
  # `{ exec 3>&2; } 2>/dev/null` duplique l'erreur standard **du groupe**, donc
  # `/dev/null`, et le canal partait droit au néant. La forme sans garde est de
  # toute façon la bonne : dupliquer un descripteur ouvert n'échoue pas.
  exec 3>&2 || return 0
  SYSAUDIT_LOG_FD=3
  return 0
}

# Le canal des messages est-il un terminal ?
#
# Le test porte sur `SYSAUDIT_LOG_FD`, non sur l'erreur standard. Dans un
# collecteur, `run_collector` a déjà envoyé l'erreur standard sur `/dev/null` :
# tester `2` y répondait « pas un terminal », la barre n'était donc ni effacée ni
# redessinée, et le premier message du collecteur s'accolait à elle. Le canal,
# lui, pointe toujours sur le terminal d'origine.
console_is_tty() { [ -t "$SYSAUDIT_LOG_FD" ]; }

console_width() {
  local width=''
  if console_is_tty; then
    width=$(tput cols 2>/dev/null || true)
  fi
  [ -n "$width" ] || width="${COLUMNS:-80}"
  case "$width" in
    '' | *[!0-9]*) width=80 ;;
  esac
  [ "$width" -ge 20 ] || width=20
  printf '%s' "$width"
}

# L'Unicode n'est utilisable que si la locale l'annonce. Un terminal en C/POSIX
# afficherait des points d'interrogation à la place des blocs.
console_supports_unicode() {
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *UTF-8* | *utf8* | *UTF8*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Logo -------------------------------------------------------------------
#
# Trois tailles, choisies d'après la largeur réelle du terminal. Un logo qui
# déborde est pire qu'une absence de logo : il casse toutes les lignes.

# Teintes du logo : « Sys » et « Audit » se distinguent, comme dans le nom.
if [ -t 2 ] && [ -z "${NO_COLOR-}" ]; then
  C_LOGO_A=$'\033[38;5;45m'
  C_LOGO_B=$'\033[38;5;39m'
else
  C_LOGO_A=''
  C_LOGO_B=''
fi

console_logo() {
  [ "$SYSAUDIT_VERBOSITY" = 'quiet' ] && return 0

  local width
  width=$(console_width)

  # Trois tailles, choisies d'après la largeur réelle. Un logo qui déborde est
  # pire qu'une absence de logo : il casse toutes les lignes suivantes.
  # Les dessins viennent de la police figlet « Mono 12 » et « Small Mono 9 »,
  # et sont figés ici — le scanner ne dépend d'aucun générateur à l'exécution.
  if [ "$width" -ge 80 ] && console_supports_unicode; then
    printf '\n' >&2
    printf '%s%s%s%s%s\n' "$C_LOGO_A" '  ▄▄▄▄                       ' "$C_LOGO_B" '    ▄▄                     ▄▄     ██' "$C_RESET" >&2
    printf '%s%s%s%s%s\n' "$C_LOGO_A" '▄█▀▀▀▀█                      ' "$C_LOGO_B" '   ████                    ██     ▀▀       ██' "$C_RESET" >&2
    printf '%s%s%s%s%s\n' "$C_LOGO_A" '██▄       ▀██  ███  ▄▄█████▄ ' "$C_LOGO_B" '   ████    ██    ██   ▄███▄██   ████     ███████' "$C_RESET" >&2
    printf '%s%s%s%s%s\n' "$C_LOGO_A" ' ▀████▄    ██▄ ██   ██▄▄▄▄ ▀ ' "$C_LOGO_B" '  ██  ██   ██    ██  ██▀  ▀██     ██       ██' "$C_RESET" >&2
    printf '%s%s%s%s%s\n' "$C_LOGO_A" '     ▀██    ████▀    ▀▀▀▀██▄ ' "$C_LOGO_B" '  ██████   ██    ██  ██    ██     ██       ██' "$C_RESET" >&2
    printf '%s%s%s%s%s\n' "$C_LOGO_A" '█▄▄▄▄▄█▀     ███    █▄▄▄▄▄██ ' "$C_LOGO_B" ' ▄██  ██▄  ██▄▄▄███  ▀██▄▄███  ▄▄▄██▄▄▄    ██▄▄▄' "$C_RESET" >&2
    printf '%s%s%s%s%s\n' "$C_LOGO_A" ' ▀▀▀▀▀       ██      ▀▀▀▀▀▀  ' "$C_LOGO_B" ' ▀▀    ▀▀   ▀▀▀▀ ▀▀    ▀▀▀ ▀▀  ▀▀▀▀▀▀▀▀     ▀▀▀▀' "$C_RESET" >&2
    printf '%s%s%s%s%s\n' "$C_LOGO_A" '           ███' "$C_LOGO_B" '' "$C_RESET" >&2
  elif [ "$width" -ge 42 ] && console_supports_unicode; then
    printf '\n' >&2
    printf '%s%s%s%s%s\n' "$C_LOGO_A" ' ▗▄▖           ' "$C_LOGO_B" '  ▄          ▗▖  █' "$C_RESET" >&2
    printf '%s%s%s%s%s\n' "$C_LOGO_A" '▗▛▀▜           ' "$C_LOGO_B" ' ▐█▌         ▐▌  ▀   ▐▌' "$C_RESET" >&2
    printf '%s%s%s%s%s\n' "$C_LOGO_A" '▐▙   ▝█ █▌▗▟██▖' "$C_LOGO_B" ' ▐█▌ ▐▌ ▐▌ ▟█▟▌ ██  ▐███' "$C_RESET" >&2
    printf '%s%s%s%s%s\n' "$C_LOGO_A" ' ▜█▙  █▖█ ▐▙▄▖▘' "$C_LOGO_B" ' █ █ ▐▌ ▐▌▐▛ ▜▌  █   ▐▌' "$C_RESET" >&2
    printf '%s%s%s%s%s\n' "$C_LOGO_A" '   ▜▌ ▐█▛  ▀▀█▖' "$C_LOGO_B" ' ███ ▐▌ ▐▌▐▌ ▐▌  █   ▐▌' "$C_RESET" >&2
    printf '%s%s%s%s%s\n' "$C_LOGO_A" '▐▄▄▟▘  █▌ ▐▄▄▟▌' "$C_LOGO_B" '▗█ █▖▐▙▄█▌▝█▄█▌▗▄█▄▖ ▐▙▄' "$C_RESET" >&2
    printf '%s%s%s%s%s\n' "$C_LOGO_A" ' ▀▀▘   █   ▀▀▀ ' "$C_LOGO_B" '▝▘ ▝▘ ▀▀▝▘ ▝▀▝▘▝▀▀▀▘  ▀▀' "$C_RESET" >&2
    printf '%s%s%s%s%s\n' "$C_LOGO_A" '      █▌' "$C_LOGO_B" '' "$C_RESET" >&2
  else
    printf '\n%sSysAudit%s\n' "$C_LOGO_A" "$C_RESET" >&2
  fi

  # La version accompagne le logo : elle répond à « qu'est-ce qui tourne » sans
  # qu'on ait à la chercher, et c'est la première question d'un rapport de bug.
  printf '%s  %s v%s · schéma %s%s\n\n' \
    "$C_DIM" "$(console_logo_scope)" "$SCANNER_VERSION" "$SCHEMA_VERSION" "$C_RESET" >&2
}

# Nom du scanner, tel qu'il figure sous le logo.
console_logo_scope() {
  if [ "${CAP_PROXMOX:-false}" = 'true' ]; then printf 'scanner Proxmox'; else printf 'scanner Linux'; fi
}

# --- États ------------------------------------------------------------------
#
# Quatre états, et quatre seulement. Une sortie qui multiplie les préfixes
# devient illisible ; celle-ci se relit d'un coup d'œil.

console_marker() {
  local kind=$1
  if console_supports_unicode; then
    case "$kind" in
      run) printf '%s→%s' "$C_BLUE" "$C_RESET" ;;
      ok) printf '%s✓%s' "$C_GREEN" "$C_RESET" ;;
      warn) printf '%s!%s' "$C_YELLOW" "$C_RESET" ;;
      err) printf '%s✗%s' "$C_RED" "$C_RESET" ;;
    esac
  else
    case "$kind" in
      run) printf '%s[>]%s' "$C_BLUE" "$C_RESET" ;;
      ok) printf '%s[OK]%s' "$C_GREEN" "$C_RESET" ;;
      warn) printf '%s[!]%s' "$C_YELLOW" "$C_RESET" ;;
      err) printf '%s[ERROR]%s' "$C_RED" "$C_RESET" ;;
    esac
  fi
}

console_session() {
  [ "$SYSAUDIT_VERBOSITY" = 'quiet' ] && return 0
  console_emit "$(printf '  %s' "$*")"
}

# Écrit une ligne **au-dessus** de la barre de progression.
#
# Sans cette précaution, un message émis pendant une étape s'accolait à la barre
# — `[███] 95 % benchmark  → Banc d'essai CPU` sur une seule ligne — parce que
# la barre se termine par un retour chariot sans saut de ligne. La barre est donc
# effacée, le message écrit, la barre redessinée : les messages défilent, la
# barre reste en bas.
console_emit() {
  if console_progress_visible; then
    printf '\r\033[K' >&"$SYSAUDIT_LOG_FD"
    printf '%s\n' "$*" >&"$SYSAUDIT_LOG_FD"
    progress_render
    return 0
  fi
  printf '%s\n' "$*" >&"$SYSAUDIT_LOG_FD"
}

# La barre est-elle actuellement à l'écran ?
console_progress_visible() {
  [ "$PROGRESS_TOTAL" -gt 0 ] || return 1
  [ "$SYSAUDIT_VERBOSITY" != 'verbose' ] || return 1
  [ "$SYSAUDIT_VERBOSITY" != 'quiet' ] || return 1
  console_is_tty
}

# --- Progression ------------------------------------------------------------
#
# La barre reflète le nombre de collecteurs réellement planifiés pour le profil
# demandé. Elle n'est affichée que sur un terminal : hors TTY, chaque étape
# produit une ligne, ce qui reste lisible dans un journal.

PROGRESS_TOTAL=0
PROGRESS_ACTIVE=''
PROGRESS_JOURNAL=''

# Le décompte passe par un fichier, et non par une variable.
#
# Chaque collecteur est appelé dans une substitution de commande — donc dans un
# sous-shell — et toute variable incrémentée là y reste : la barre repartait de
# zéro à chaque étape et ne dépassait jamais le premier pourcentage. Un fichier
# est partagé par les sous-shells, comme l'est déjà le journal de collecte.
# Poids total des étapes annoncées, et poids déjà consommé.
#
# Ils viennent doubler le décompte plutôt que le remplacer : une barre pesée
# décrit le temps, une barre comptée décrit les étapes, et les deux se lisent
# — « 42 % · 7/23 ». Sans le second, une étape qui dure la moitié de l'audit
# fait paraître la barre bloquée alors qu'elle avance ; sans le premier, elle
# saute de 95 % à 95 % pendant dix minutes.
PROGRESS_TOTAL_WEIGHT=0
PROGRESS_ACTIVE_WEIGHT=0
PROGRESS_STEP_STARTED_AT=0

# `$1` = la **liste** des étapes, séparées par des espaces.
#
# Une liste et non un nombre : le poids total ne se déduit pas d'un compte, et
# une barre pesée doit connaître son dénominateur avant la première étape. Le
# nombre s'en déduit, lui, ce qui supprime le second calcul qui pouvait dériver.
progress_start() {
  local sections=${1-}
  PROGRESS_TOTAL=$(printf '%s' "$sections" | wc -w | tr -d ' ')
  PROGRESS_JOURNAL=$(mktemp "${TMPDIR:-/tmp}/sysaudit-progress-XXXXXX" 2>/dev/null || printf '')

  PROGRESS_TOTAL_WEIGHT=0
  local section=''
  for section in $sections; do
    PROGRESS_TOTAL_WEIGHT=$((PROGRESS_TOTAL_WEIGHT + $(progress_weight_of "$section")))
  done
  PROGRESS_ACTIVE_WEIGHT=0
  PROGRESS_STEP_STARTED_AT=0
}

progress_count() {
  [ -n "$PROGRESS_JOURNAL" ] && [ -f "$PROGRESS_JOURNAL" ] || { printf '0'; return 0; }
  wc -l <"$PROGRESS_JOURNAL" | tr -d ' '
}

# Poids déjà consommé, relu du journal.
#
# Comme le décompte, il passe par un fichier : chaque collecteur tourne dans une
# substitution de commande, donc dans un sous-shell, et une variable incrémentée
# là n'en ressort pas — c'est le défaut qui faisait repartir la barre de zéro à
# chaque étape.
progress_done_weight() {
  [ -n "$PROGRESS_JOURNAL" ] && [ -f "$PROGRESS_JOURNAL" ] || { printf '0'; return 0; }
  awk '{ total += $1 } END { print total + 0 }' <"$PROGRESS_JOURNAL"
}

progress_step() {
  PROGRESS_ACTIVE=$1
  PROGRESS_ACTIVE_WEIGHT=$(progress_weight_of "$1")
  PROGRESS_STEP_STARTED_AT=$(progress_now_seconds)
  [ "$SYSAUDIT_VERBOSITY" = 'quiet' ] && return 0

  if console_progress_visible; then
    progress_render
  else
    printf '  %s %s\n' "$(console_marker run)" "$1" >&"$SYSAUDIT_LOG_FD"
  fi
}

progress_done() {
  [ -n "$PROGRESS_JOURNAL" ] && printf '%s\n' "$PROGRESS_ACTIVE_WEIGHT" >>"$PROGRESS_JOURNAL"
  PROGRESS_ACTIVE_WEIGHT=0
  PROGRESS_STEP_STARTED_AT=0
  [ "$SYSAUDIT_VERBOSITY" = 'quiet' ] && return 0

  if console_progress_visible; then
    progress_render
  else
    printf '  %s %s\n' "$(console_marker ok)" "$PROGRESS_ACTIVE" >&"$SYSAUDIT_LOG_FD"
  fi
}

# L'horloge, en secondes. Isolée pour que les tests la remplacent.
progress_now_seconds() {
  date +%s 2>/dev/null || printf '0'
}

progress_render() {
  local percent=0 filled=0 width bar_width label completed
  completed=$(progress_count)

  # Deux calculs, et le pesé l'emporte quand il est disponible.
  #
  # `progress_overall_percent` fait avancer la barre **pendant** une étape, au
  # prorata de son temps écoulé : c'est ce qui empêche un banc d'essai de dix
  # minutes de ressembler à un blocage. Le décompte simple reste le repli — un
  # appelant qui n'aurait pas déclaré ses étapes obtient l'ancien comportement
  # plutôt qu'une barre à zéro.
  if [ "${PROGRESS_TOTAL_WEIGHT:-0}" -gt 0 ]; then
    local elapsed=0
    if [ "${PROGRESS_STEP_STARTED_AT:-0}" -gt 0 ]; then
      elapsed=$(($(progress_now_seconds) - PROGRESS_STEP_STARTED_AT))
      [ "$elapsed" -ge 0 ] || elapsed=0
    fi
    percent=$(progress_overall_percent \
      "$(progress_done_weight)" "${PROGRESS_ACTIVE_WEIGHT:-0}" "$elapsed" "$PROGRESS_TOTAL_WEIGHT")
  elif [ "$PROGRESS_TOTAL" -gt 0 ]; then
    percent=$((completed * 100 / PROGRESS_TOTAL))
  fi
  [ "$percent" -le 100 ] || percent=100

  width=$(console_width)
  # La barre laisse la place au pourcentage et au libellé de l'étape.
  bar_width=$((width - 24))
  [ "$bar_width" -ge 10 ] || bar_width=10
  [ "$bar_width" -le 40 ] || bar_width=40
  filled=$((percent * bar_width / 100))

  local full='' empty='' full_char='#' empty_char='.'
  if console_supports_unicode; then
    full_char='█'
    empty_char='░'
  fi

  local index=0
  while [ "$index" -lt "$filled" ]; do
    full="${full}${full_char}"
    index=$((index + 1))
  done
  index=$filled
  while [ "$index" -lt "$bar_width" ]; do
    empty="${empty}${empty_char}"
    index=$((index + 1))
  done

  # L'étape en cours, et son propre avancement quand il est connu.
  #
  # `progress_phase_percent` était calculé et jamais dessiné : la barre globale
  # dit « on en est là de l'audit », elle ne dit pas « on en est là de cette
  # étape-ci ». Sur une charge soutenue de dix minutes, c'est la seconde qui
  # répond à la question qu'on se pose.
  #
  # Il **manque volontairement** quand la durée de l'étape n'est pas
  # prévisible : une fraction sans dénominateur connu vaut moins que rien, et
  # `progress_phase_percent` rend une chaîne vide plutôt que d'en fabriquer une.
  label=$PROGRESS_ACTIVE
  local phase=''
  if [ "${PROGRESS_STEP_STARTED_AT:-0}" -gt 0 ] && [ "${PROGRESS_ACTIVE_WEIGHT:-0}" -gt 1 ]; then
    local step_elapsed=$(($(progress_now_seconds) - PROGRESS_STEP_STARTED_AT))
    [ "$step_elapsed" -ge 0 ] || step_elapsed=0
    phase=$(progress_phase_percent "$step_elapsed" "$PROGRESS_ACTIVE_WEIGHT")
    [ -z "$phase" ] || label="$label $phase%"
  fi

  # `\r` sans saut de ligne : la barre se réécrit sur place. Hors TTY, cette
  # fonction n'est jamais appelée — un journal rempli de retours chariot est
  # illisible.
  printf '\r\033[K  %s[%s%s]%s %3d%%  %s' \
    "$C_DIM" "$full" "$empty" "$C_RESET" "$percent" "$label" >&"$SYSAUDIT_LOG_FD"
}

progress_end() {
  if console_progress_visible; then
    printf '\r\033[K' >&"$SYSAUDIT_LOG_FD"
  fi

  [ -n "$PROGRESS_JOURNAL" ] && rm -f "$PROGRESS_JOURNAL"
  PROGRESS_JOURNAL=''
  return 0
}

# --- Résumé -----------------------------------------------------------------
#
# Lu depuis le JSON produit, jamais depuis les variables de collecte : le résumé
# décrit le rapport réellement écrit, et non ce que le scanner croyait avoir
# mesuré.

summary_line() {
  local label=$1 value=$2
  # Une valeur absente n'est pas affichée : une ligne vide se lirait comme
  # « aucun », ce qui serait faux.
  [ -n "$value" ] || return 0
  printf '  %s%-14s%s %s\n' "$C_DIM" "$label" "$C_RESET" "$value" >&2
}

# Première valeur scalaire portant cette clé, dans **une section** de rapport.
#
# L'extraction prend volontairement la première occurrence : appliquée au
# document entier, une clé comme `name` existerait dans chaque interface réseau
# et chaque conteneur, et le résumé afficherait la dernière rencontrée — une
# valeur juste, au mauvais endroit, donc une valeur fausse.
summary_value() {
  local json=$1 key=$2
  printf '%s' "$json" |
    grep -o "\"${key}\":\"[^\"]*\"" |
    head -n 1 |
    sed -E "s/^\"${key}\":\"//; s/\"$//"
}

# Compte les occurrences d'une clé : nombre de disques, d'interfaces…
summary_count() {
  local json=$1 key=$2 count=''
  count=$(printf '%s' "$json" | grep -o "\"${key}\":" | wc -l | tr -d ' ')
  printf '%s' "$count"
}

# Octets en unité lisible. Une valeur non numérique ne produit rien plutôt
# qu'un « 0 o » qui se lirait comme une mesure.
summary_bytes() {
  local bytes=$1
  case "$bytes" in
    '' | *[!0-9]*) return 0 ;;
  esac
  awk -v b="$bytes" 'BEGIN {
    split("o Kio Mio Gio Tio", unit, " ")
    i = 1
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    printf (i == 1 ? "%d %s" : "%.1f %s"), b, unit[i]
  }'
}

# Résumé de fin d'audit.
#
# Chaque ligne vient de la section correspondante du rapport, jamais du document
# entier : voir `summary_value`. Une section absente disparaît du résumé.
console_summary() {
  local system_json=$1 os_json=$2 cpus_json=$3 memory_json=$4
  local storage_json=$5 network_json=$6 virtualization_json=$7 issues=$8

  [ "$SYSAUDIT_VERBOSITY" = 'quiet' ] && return 0

  printf '\n  %sRésumé%s\n' "$C_BLUE" "$C_RESET" >&2

  summary_line 'Machine' "$(summary_value "$system_json" 'hostname')"

  local vendor='' model=''
  vendor=$(summary_value "$system_json" 'manufacturer')
  model=$(summary_value "$system_json" 'model')
  summary_line 'Matériel' "$(printf '%s %s' "$vendor" "$model" | sed 's/^ *//; s/ *$//')"

  local os_name='' os_version=''
  os_name=$(summary_value "$os_json" 'name')
  os_version=$(summary_value "$os_json" 'version')
  summary_line 'Système' "$(printf '%s %s' "$os_name" "$os_version" | sed 's/^ *//; s/ *$//')"

  summary_line 'Architecture' "$(summary_value "$system_json" 'architecture')"
  summary_line 'Processeur' "$(summary_value "$cpus_json" 'model')"

  local installed=''
  installed=$(printf '%s' "$memory_json" | grep -o '"installedBytes":[0-9]*' | head -n 1 | sed 's/.*://')
  summary_line 'Mémoire' "$(summary_bytes "$installed")"

  local disks=''
  disks=$(summary_count "$storage_json" 'device')
  [ "$disks" -gt 0 ] 2>/dev/null && summary_line 'Stockage' "$disks disque(s)"

  local interfaces=''
  interfaces=$(summary_count "$network_json" 'mac')
  [ "$interfaces" -gt 0 ] 2>/dev/null && summary_line 'Réseau' "$interfaces interface(s)"

  local hypervisor=''
  hypervisor=$(summary_value "$virtualization_json" 'runningUnder')
  summary_line 'Virtualisation' "$hypervisor"

  local vms=''
  vms=$(summary_count "$virtualization_json" 'vmid')
  [ "$vms" -gt 0 ] 2>/dev/null && summary_line 'Invités' "$vms VM/LXC"

  if [ "${issues:-0}" -gt 0 ] 2>/dev/null; then
    printf '  %s %s information(s) non collectée(s), motif dans le rapport.\n' \
      "$(console_marker warn)" "$issues" >&2
  fi
}

# --- QR Code ----------------------------------------------------------------
#
# Le dessin vient de l'API : encoder un QR en Bash demanderait une arithmétique
# de corps de Galois qu'aucun test de ce dépôt ne pourrait vérifier. L'absence
# de QR n'empêche rien, l'URL étant toujours affichée.

# Affiche le QR reçu de l'API, ou rien.
#
# Trois conditions doivent être réunies : un dessin, un terminal, et une locale
# UTF-8. À défaut, seule l'URL reste — c'est un raccourci, jamais le seul chemin
# vers le rapport.
console_qr() {
  local encoded=$1 line=''

  [ "$SYSAUDIT_VERBOSITY" = 'quiet' ] && return 0
  [ -n "$encoded" ] || return 0
  console_is_tty || return 0
  console_supports_unicode || return 0

  # Un terminal étroit tronquerait le dessin, donc le rendrait illisible.
  [ "$(console_width)" -ge 40 ] || return 0

  printf '\n' >&2
  # Chaque ligne est encadrée en noir sur blanc : un QR sombre sur fond sombre
  # ne se lit pas, et le thème du terminal n'est pas connu d'ici.
  printf '%b' "$encoded" | while IFS= read -r line; do
    if [ -n "${NO_COLOR-}" ]; then
      printf '%s\n' "$line" >&2
    else
      printf '\033[47;30m%s\033[0m\n' "$line" >&2
    fi
  done
  printf '\n' >&2
}
