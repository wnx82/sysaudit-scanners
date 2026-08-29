#!/usr/bin/env bash
# Fonctions transverses du scanner : journalisation, exécution maîtrisée des
# commandes et suivi des problèmes de collecte.

# --- Journalisation ---------------------------------------------------------
#
# Toute la journalisation part sur stderr : stdout reste réservé au JSON afin
# que `sysaudit.sh --stdout | jq` fonctionne.

if [ -t 2 ] && [ -z "${NO_COLOR-}" ]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'
  C_YELLOW=$'\033[33m'; C_GREEN=$'\033[32m'; C_BLUE=$'\033[34m'
else
  C_RESET=''; C_DIM=''; C_RED=''; C_YELLOW=''; C_GREEN=''; C_BLUE=''
fi

log_info() { console_emit "$(printf '%s[SysAudit]%s %s' "$C_BLUE" "$C_RESET" "$*")"; }
# Les messages du scanner passent par `console_emit` : c'est lui qui les place
# au-dessus de la barre de progression, et lui qui les écrit sur le canal dédié
# — celui que `run_collector` ne jette pas, contrairement à l'erreur standard des
# outils appelés.
log_step() { console_emit "$(printf '%s  →%s %s' "$C_DIM" "$C_RESET" "$*")"; }
log_ok() { console_emit "$(printf '%s  ✓%s %s' "$C_GREEN" "$C_RESET" "$*")"; }
log_warn() { console_emit "$(printf '%s  !%s %s' "$C_YELLOW" "$C_RESET" "$*")"; }
log_error() { console_emit "$(printf '%s[erreur]%s %s' "$C_RED" "$C_RESET" "$*")"; }
log_debug() {
  [ "${SYSAUDIT_DEBUG:-0}" = "1" ] && console_emit "$(printf '%s  ·%s %s' "$C_DIM" "$C_RESET" "$*")"
  return 0
}

die() {
  log_error "$*"
  exit 1
}

# --- Problèmes de collecte --------------------------------------------------
#
# Un scan partiel doit se dire tel quel : chaque échec est enregistré et se
# retrouve dans la section `collection` du rapport.
#
# Le journal est un **fichier**, pas un tableau Bash. Les collecteurs sont
# appelés par substitution de commande (`$(collect_x)`), qui ouvre un
# sous-shell : un tableau modifié là n'existe plus au retour. Tant que le
# journal était un tableau, `collection.issues` sortait systématiquement vide et
# aucune raison d'absence n'atteignait le rapport.

COLLECTION_JOURNAL=''
SKIPPED_JOURNAL=''
PROVENANCE_JOURNAL=''
TIMING_JOURNAL=''
THERMAL_JOURNAL=''

# Ouvre les journaux. Appelé une fois, avant toute collecte.
init_collection_journal() {
  local dir=''
  dir=$(mktemp -d "${TMPDIR:-/tmp}/sysaudit-journal-XXXXXX") || {
    log_warn 'Journal de collecte indisponible : les raisons d’absence ne seront pas rapportées.'
    return 0
  }
  chmod 700 "$dir" 2>/dev/null || true
  COLLECTION_JOURNAL="$dir/issues"
  SKIPPED_JOURNAL="$dir/skipped"
  PROVENANCE_JOURNAL="$dir/provenance"
  TIMING_JOURNAL="$dir/timings"
  THERMAL_JOURNAL="$dir/thermal"
  # Journaux du gestionnaire de dépendances (`provision.sh`). Ils vivent dans le
  # même répertoire éphémère : ils portent des noms d'outils et des messages
  # d'erreur de gestionnaire de paquets, qui n'ont pas à survivre à l'audit.
  PROVISION_JOURNAL="$dir/dependencies"
  PROVISION_USED_JOURNAL="$dir/dependencies-used"
  PROVISION_REMOVAL_JOURNAL="$dir/dependencies-removal"
  : >"$COLLECTION_JOURNAL"
  : >"$SKIPPED_JOURNAL"
  : >"$PROVENANCE_JOURNAL"
  : >"$TIMING_JOURNAL"
  : >"$THERMAL_JOURNAL"
  : >"$PROVISION_JOURNAL"
  : >"$PROVISION_USED_JOURNAL"
  : >"$PROVISION_REMOVAL_JOURNAL"
  # Le rapport peut contenir des données personnelles : les journaux
  # disparaissent quoi qu'il arrive, y compris en cas d'interruption.
  trap 'rm -rf "$(dirname "$COLLECTION_JOURNAL")" 2>/dev/null || true' EXIT INT TERM
}

# record_issue <section> <severity: warning|error> <message> [source] [motif]
#
# Écrit une ligne dans le journal. Fonctionne depuis n'importe quel sous-shell,
# ce qui est indispensable : la plupart des appels viennent d'un collecteur.
#
# Le **motif** est lu par la plateforme pour décider du statut de l'audit ; le
# message, lui, s'adresse à un humain. Les valeurs admises sont celles de
# `collectionIssueReasonSchema` :
#
#   NOT_COLLECTED  NOT_REQUESTED  NOT_APPLICABLE  UNSUPPORTED
#   PERMISSION_DENIED  NOT_AVAILABLE  TIMEOUT  COLLECTOR_ERROR
#
# Il est laissé vide quand l'issue ne décrit **pas** une absence — un bridage
# thermique constaté pendant le banc d'essai est un résultat de mesure, pas une
# donnée manquante. Une issue sans motif n'est pas classable : la plateforme la
# traite comme une collecte manquée, ce qui est la lecture prudente.
record_issue() {
  local section=$1 severity=$2 message=$3 source=${4-} reason=${5-}
  local entry=''
  entry=$(json_object \
    "$(jf_str section "$section")" \
    "$(jf_str severity "$severity")" \
    "$(jf_str message "$message")" \
    "$(if [ -n "$source" ]; then jf_str source "$source"; fi)" \
    "$(if [ -n "$reason" ]; then jf_str reason "$reason"; fi)")

  # `json_object` produit toujours une ligne unique : `json_escape` échappe les
  # sauts de ligne. Un enregistrement par ligne est donc sans ambiguïté.
  [ -n "$COLLECTION_JOURNAL" ] && printf '%s\n' "$entry" >>"$COLLECTION_JOURNAL"
  log_debug "issue[$severity] $section: $message"
  return 0
}

record_skipped() {
  [ -n "$SKIPPED_JOURNAL" ] && printf '%s\n' "$1" >>"$SKIPPED_JOURNAL"
  return 0
}

# Cette section a-t-elle déjà expliqué une absence ?
#
# Le journal est un fichier, donc lisible depuis le sous-shell d'un collecteur.
# La correspondance est préfixée : une issue sur `devices.usb` répond pour
# `devices`, l'inverse étant faux — savoir que toute la section manque
# n'explique pas laquelle de ses sondes a échoué.
section_has_issue() {
  local section=$1
  [ -n "$COLLECTION_JOURNAL" ] && [ -s "$COLLECTION_JOURNAL" ] || return 1
  grep -q "\"section\":\"${section}\(\.[^\"]*\)\?\"" "$COLLECTION_JOURNAL" 2>/dev/null
}

# record_timing <section> <durée_ms>
#
# Temps passé dans un collecteur. Le rapport ne s'en sert pas pour lui-même : il
# alimente l'estimation de durée affichée avant l'audit, qui était jusqu'ici une
# constante écrite à la main.
#
# Une durée non mesurable n'est **pas** enregistrée. Le champ manquant se lit
# « on ne sait pas », là où un zéro se lirait « instantané » et tirerait la
# médiane vers le bas à chaque horloge qui saute.
record_timing() {
  local section=${1-} elapsed=${2-}
  [ -n "$section" ] || return 0
  case "$elapsed" in '' | *[!0-9]*) return 0 ;; esac
  [ -n "$TIMING_JOURNAL" ] && printf '%s\n' "$(json_object \
    "$(jf_str section "$section")" \
    "$(jf_raw durationMs "$(j_num "$elapsed")")")" >>"$TIMING_JOURNAL"
  return 0
}

# record_thermal_reading <label> <celsius> <category> <device> <source> [scope]
#
# Température relevée **hors** du collecteur de capteurs.
#
# Deux sections en produisent : le stockage, qui lit les températures SMART/NVMe
# en même temps que l'usure des disques, et les cartes graphiques, dont
# `nvidia-smi` rend la sonde avec le reste de la télémétrie. Les faire relire par
# `collect_sensors` reviendrait à rappeler `smartctl` sur chaque disque —
# plusieurs secondes, et deux valeurs pour un même capteur.
#
# Le journal résout un problème de portée, pas d'architecture : chaque collecteur
# tourne dans une substitution de commande, donc dans un sous-shell, et une
# variable globale n'en ressort pas. C'est déjà la raison d'être des journaux
# d'incidents et de provenance.
#
# `collect_sensors` est appelé **après** le stockage et les cartes graphiques
# pour cette seule raison : il ramasse ce que les deux ont laissé ici. L'ordre
# des sections dans le rapport, lui, ne change pas — il est fixé à l'assemblage.
record_thermal_reading() {
  local label=$1 celsius=$2 category=$3 device=${4-} source=${5-} scope=${6-}
  [ -n "$label" ] || return 0
  [ -n "$celsius" ] || return 0
  [ -n "$THERMAL_JOURNAL" ] || return 0

  printf '%s\n' "$(json_object \
    "$(jf_str label "$label")" \
    "$(jf_raw celsius "$(j_num "$celsius")")" \
    "$(if [ -n "$category" ]; then jf_str category "$category"; fi)" \
    "$(if [ -n "$device" ]; then jf_str device "$device"; fi)" \
    "$(if [ -n "$source" ]; then jf_str source "$source"; fi)" \
    "$(jf_str scope "${scope:-LOCAL}")" \
    "$(jf_str quality 'MEASURED')")" >>"$THERMAL_JOURNAL"
  return 0
}

# record_provenance <path> <source> [method] [precision] [collected_at]
#
# Associe un chemin du rapport à la manière dont il a été lu. Le journal est un
# fichier, comme pour les incidents : les collecteurs s'exécutent en sous-shell.
record_provenance() {
  local path=$1 source=$2 method=${3-} precision=${4-} collected_at=${5-}
  [ -n "$path" ] && [ -n "$source" ] || return 0

  [ -n "$collected_at" ] || collected_at=$(iso_now)

  local entry=''
  entry=$(json_object \
    "$(jf_str path "$path")" \
    "$(jf_str source "$source")" \
    "$(if [ -n "$method" ]; then jf_str method "$method"; fi)" \
    "$(if [ -n "$precision" ]; then jf_str precision "$precision"; fi)" \
    "$(jf_str collectedAt "$collected_at")")

  [ -n "$PROVENANCE_JOURNAL" ] && printf '%s\n' "$entry" >>"$PROVENANCE_JOURNAL"
  return 0
}

# Fragment JSON de la section `collection`, lu depuis les journaux.
build_collection_json() {
  local issues='[]' skipped='[]' provenance='' timings='[]'

  if [ -n "$COLLECTION_JOURNAL" ] && [ -s "$COLLECTION_JOURNAL" ]; then
    issues="[$(paste -sd, - <"$COLLECTION_JOURNAL")]"
  fi
  if [ -n "$SKIPPED_JOURNAL" ] && [ -s "$SKIPPED_JOURNAL" ]; then
    # Dédoublonnage en conservant l'ordre d'apparition : une section déclarée
    # une fois par disque — `storage.smart` sur une machine à quatre disques —
    # se lirait comme quatre absences différentes.
    skipped=$(awk '!seen[$0]++' <"$SKIPPED_JOURNAL" | json_array_from_lines)
  fi

  if [ -n "$TIMING_JOURNAL" ] && [ -s "$TIMING_JOURNAL" ]; then
    timings="[$(paste -sd, - <"$TIMING_JOURNAL")]"
  fi

  if [ -n "$PROVENANCE_JOURNAL" ] && [ -s "$PROVENANCE_JOURNAL" ]; then
    provenance=$(awk '
      BEGIN { first = 1; printf "{" }
      {
        line = $0
        path = line
        sub(/^.*"path":"?/, "", path)
        sub(/".*$/, "", path)
        body = line
        sub(/^.*"path":"[^"]*",?/, "", body)
        if (!first) printf ","
        printf "\"%s\":{%s", path, body
        if (body !~ /}$/) printf "}"
        first = 0
      }
      END { printf "}" }
    ' "$PROVENANCE_JOURNAL")
  fi

  # Ce que le niveau prévoyait, et ce que le scanner sait faire.
  #
  # Les deux listes sont **recopiées** de la matrice, sans calcul : ce sont les
  # dénominateurs de toute mesure de couverture, et un dénominateur recalculé
  # ailleurs finit par ne plus correspondre au numérateur. `monitoring` s'ajoute
  # au plan quand elle a été demandée — elle ne dépend pas du niveau, mais elle
  # était bel et bien prévue pour cet audit-ci.
  local planned='' known=''
  planned=$(sections_for_level | json_array_from_lines)
  known=$(all_sections | json_array_from_lines)
  if [ "${OPT_MONITOR_SECONDS:-0}" -gt 0 ]; then
    planned=$(printf '%s' "$planned" | sed 's/\]$/,"monitoring"]/')
  fi

  json_object \
    "$(jf_raw issues "$issues")" \
    "$(jf_raw skippedSections "$skipped")" \
    "$(jf_raw timings "$timings")" \
    "$(if [ -n "$provenance" ]; then jf_raw provenance "$provenance"; fi)" \
    "$(jf_raw dependencies "$(build_dependencies_json)")" \
    "$(jf_raw dependenciesInspected "$(dependencies_inspected)")" \
    "$(jf_raw plannedSections "$planned")" \
    "$(jf_raw knownSections "$known")"
}

# Nombre de problèmes enregistrés, pour le bilan affiché en fin de scan.
collection_issue_count() {
  if [ -n "$COLLECTION_JOURNAL" ] && [ -f "$COLLECTION_JOURNAL" ]; then
    count_non_empty_lines <"$COLLECTION_JOURNAL"
  else
    printf '0'
  fi
}

# --- Isolation des collecteurs ----------------------------------------------

# Exécute un collecteur en isolant sa défaillance.
#
# Deux garanties, quelle que soit la machine auditée :
#
#   1. une erreur du collecteur n'interrompt jamais l'audit. Le collecteur
#      s'exécute dans un sous-shell : ni `set -e`, ni un `exit`, ni un `return`
#      non nul ne remontent au script principal, dont le statut est traité ici ;
#   2. un échec produit une section **absente avec sa raison**, jamais une
#      section inventée ou à moitié écrite.
#
# Le temps d'exécution est borné **par commande** et non par collecteur :
# `run_cmd` applique `SYSAUDIT_CMD_TIMEOUT` à chaque commande externe, seul
# endroit où un blocage se produit réellement. Un délai supplémentaire au
# niveau du collecteur exigerait de le lancer dans un processus séparé, où les
# fonctions du scanner n'existeraient plus.
#
# Écrit le JSON du collecteur sur stdout, ou rien en cas d'échec.
run_collector() {
  local section=$1
  shift

  # Point de passage unique de tous les collecteurs : c'est donc ici, et
  # nulle part ailleurs, que la progression avance. Une barre alimentée
  # depuis l'appelant se désynchroniserait au premier collecteur ajouté.
  progress_step "$section"

  # Chronométré ici pour la même raison que la progression : c'est le seul
  # point par lequel tous les collecteurs passent. Mesurer depuis l'appelant
  # obligerait à ne pas oublier une ligne sur vingt-cinq, et l'oubli ne
  # casserait rien de visible — il ferait juste mentir la médiane.
  #
  # `clock_ms` lit /proc/uptime : la mesure est monotone, donc insensible à un
  # ajustement NTP survenant pendant la collecte.
  local began=''
  began=$(clock_ms)

  local output='' status=0
  output=$("$@" 2>/dev/null) || status=$?

  # Enregistrée même quand le collecteur échoue : un collecteur qui met vingt
  # secondes avant d'abandonner a bel et bien coûté vingt secondes à
  # l'utilisateur, et c'est cette durée-là que l'estimation doit refléter.
  record_timing "$section" "$(audit_duration_ms "$began" "$(clock_ms)")"

  progress_done

  if [ "$status" -eq 0 ] && [ -n "$output" ]; then
    printf '%s' "$output"
    return 0
  fi

  if [ "$status" -ne 0 ]; then
    record_issue "$section" 'error' \
      "Le collecteur a échoué (code $status) : section non rapportée." '' 'COLLECTOR_ERROR'
  elif section_has_issue "$section"; then
    # Le collecteur s'est arrêté proprement **après** avoir dit pourquoi : sans
    # `lsmod`, l'inventaire des pilotes déclare l'outil manquant puis rend une
    # section vide. Ajouter « le collecteur n'a produit aucune donnée » par
    # dessus transformerait une dépendance absente en anomalie, et faisait
    # passer un audit sans outils pour un audit en panne — mesuré : trois
    # sections sur un scan à PATH minimal.
    record_skipped "$section"
    return 0
  else
    record_issue "$section" 'warning' \
      'Le collecteur n’a produit aucune donnée : section non rapportée.' '' 'COLLECTOR_ERROR'
  fi
  record_skipped "$section"
  return 0
}

# --- Exécution maîtrisée ----------------------------------------------------

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

# Rend le fichier produit à l'utilisateur qui a lancé l'audit.
#
# `sudo` conserve l'identité d'origine dans `SUDO_UID` et `SUDO_GID`. Sans ce
# rattrapage, tout audit privilégié — c'est-à-dire tout audit complet — laisse
# derrière lui un fichier `root:root` en 600 dans le dossier personnel de
# quelqu'un qui ne peut pas l'ouvrir.
#
# Trois précautions, et chacune évite un dégât :
#
#   - **rien n'est fait hors `sudo`.** Un audit lancé directement en root, sans
#     `sudo`, n'a pas d'utilisateur d'origine à qui rendre quoi que ce soit :
#     `SUDO_UID` est alors absent, et deviner reviendrait à donner le rapport à
#     un compte au hasard ;
#   - **`SUDO_UID` doit être un nombre**, et non zéro. Un `sudo -u root` laisse
#     `SUDO_UID=0` : le fichier appartient déjà à root, il n'y a rien à faire ;
#   - **les droits ne changent pas.** Seul le propriétaire change ; le fichier
#     reste en 600. Le rapport peut contenir des données personnelles, et le
#     rendre lisible par tous pour régler un problème de propriétaire
#     échangerait un défaut d'ergonomie contre une fuite.
#
# Un `chown` qui échoue n'interrompt rien : le rapport existe, il est simplement
# moins commode. L'échec est dit, pas tu.
restore_report_ownership() {
  local path=$1

  [ -e "$path" ] || return 0
  # Hors `sudo`, il n'y a pas d'utilisateur d'origine connu.
  [ -n "${SUDO_UID:-}" ] || return 0
  case "$SUDO_UID" in
    '' | *[!0-9]*) return 0 ;;
    0) return 0 ;;
  esac

  has_cmd chown || {
    log_debug 'chown absent : le rapport reste la propriété de root.'
    return 0
  }

  if chown "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$path" 2>/dev/null; then
    log_debug "Rapport rendu à l’utilisateur $SUDO_UID : $path"
  else
    log_warn "Le rapport reste la propriété de root ($path) : ${SUDO_USER:-l’utilisateur} devra le lire avec sudo."
  fi
}

# Exécute une commande en lecture seule, avec timeout, et capture sa sortie.
#
# Le scanner n'exécute que des commandes écrites en dur dans son code : aucun
# argument n'est construit à partir de données non fiables (SECURITY.md).
# Retourne 0 et écrit sur stdout en cas de succès, 1 sinon.
run_cmd() {
  local timeout_s=${SYSAUDIT_CMD_TIMEOUT:-15}
  local output='' status=''

  # Un outil de la table vient-il d'être invoqué ? C'est le seul point du
  # scanner par lequel passent les commandes externes : le déduire ici est la
  # seule façon de dire honnêtement, dans le rapport, qu'un outil a **servi** —
  # plutôt que de conclure de sa présence qu'il a été utile.
  #
  # Test d'appartenance en pur shell, sans sous-processus : cette fonction est
  # appelée plusieurs centaines de fois par audit.
  case "${PROVISION_TOOLS-}" in
    *" ${1-} "*) provision_mark_used "$1" ;;
  esac

  if has_cmd timeout; then
    output=$(timeout -k 2 "$timeout_s" "$@" 2>/dev/null)
    status=$?
  else
    output=$("$@" 2>/dev/null)
    status=$?
  fi

  # Un délai dépassé n'est pas un échec comme un autre.
  #
  # `timeout` sort en 124 quand il a dû interrompre la commande — et en 137 si
  # le `-k 2` a dû aller jusqu'au signal KILL. Les deux cas se lisaient jusqu'ici
  # comme n'importe quelle commande qui échoue : le rapport disait « la donnée
  # manque », jamais « la source a mis trop de temps à répondre ». La différence
  # compte pour qui relance l'audit : un disque qui ne répond pas en quinze
  # secondes est un renseignement sur ce disque.
  #
  # La section est déduite du nom de la commande, faute de mieux : `run_cmd` ne
  # sait pas pour quelle section il travaille. C'est `run_collector` qui le
  # sait, et il enregistrera de son côté ce que le collecteur a fini par rendre.
  if [ $status -eq 124 ] || [ $status -eq 137 ]; then
    log_debug "délai dépassé (${timeout_s}s) : $*"
    record_issue "commande.${1-}" 'warning' \
      "La commande a dépassé le délai de ${timeout_s} s : la donnée qu’elle devait fournir manque." \
      "${1-}" 'TIMEOUT'
    return 1
  fi

  if [ $status -ne 0 ]; then
    log_debug "échec ($status) : $*"
    return 1
  fi

  # La sortie se termine par un saut de ligne dès qu'elle n'est pas vide.
  #
  # `$(...)` retire les sauts de ligne finaux : sans ce `\n`, la dernière ligne
  # partait sans terminateur, et toute boucle `while read < <(run_cmd …)`
  # sortait avant de la traiter. Vingt-cinq boucles consomment cette fonction ;
  # celles qui ne passent pas par un filtre intermédiaire — `awk`, `sed`, `sort`,
  # qui réémettent un saut de ligne — perdaient donc silencieusement leur
  # **dernier élément** : le dernier module noyau, le dernier service, le dernier
  # périphérique PCI ou USB, et le dernier port en écoute.
  #
  # Sur l'hôte Proxmox de validation, le port perdu était le 8006 : l'interface
  # d'administration, soit le service le plus exposé de la machine. Aucun test ne
  # pouvait le voir — un WSL2 sans service en écoute n'a pas de dernière ligne à
  # perdre.
  #
  # Le cas vide reste vide : `printf '%s\n' ''` produirait une ligne blanche là
  # où l'appelant attend l'absence de sortie.
  [ -n "$output" ] || return 0
  printf '%s\n' "$output"
}

# Lit un fichier système en gérant proprement l'absence et le refus d'accès.
# Écrit le contenu sur stdout ; retourne 1 (absent) ou 2 (accès refusé).
read_file() {
  local path=$1
  [ -e "$path" ] || return 1
  [ -r "$path" ] || return 2
  # `cat` échoue tout de même sur certains fichiers /sys selon le matériel.
  cat "$path" 2>/dev/null || return 2
}

# Lit un fichier et retourne sa première ligne nettoyée, ou une chaîne vide.
read_value() {
  local content=''
  content=$(read_file "$1") || return 1
  printf '%s' "$content" | head -n 1 | trim
}

trim() {
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# Convertit une taille rapportée par un outil système en octets.
# Retourne une chaîne vide si l'entrée n'est pas interprétable avec certitude.
to_bytes() {
  local input=${1-} value='' unit=''
  input=$(printf '%s' "$input" | trim)
  [ -z "$input" ] && return 0

  value=$(printf '%s' "$input" | sed -nE 's/^([0-9]+([.,][0-9]+)?).*$/\1/p')
  [ -z "$value" ] && return 0
  value=${value//,/.}

  unit=$(printf '%s' "$input" | sed -nE 's/^[0-9]+([.,][0-9]+)?[[:space:]]*([A-Za-z]*).*$/\2/p')
  unit=$(printf '%s' "$unit" | tr '[:upper:]' '[:lower:]')

  local multiplier=''
  case "$unit" in
    '' | b | bytes) multiplier=1 ;;
    k | kb | kib) multiplier=1024 ;;
    m | mb | mib) multiplier=1048576 ;;
    g | gb | gib) multiplier=1073741824 ;;
    t | tb | tib) multiplier=1099511627776 ;;
    p | pb | pib) multiplier=1125899906842624 ;;
    *) return 0 ;;
  esac

  awk -v v="$value" -v m="$multiplier" 'BEGIN { printf "%.0f", v * m }'
}

# Horodatage ISO 8601 UTC, format attendu par le schéma.
iso_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# Horloge de mesure de durée, en millisecondes.
#
# `/proc/uptime` est **monotone** : il ne recule jamais et ne bondit pas quand
# NTP recale l'horloge en cours d'audit. `date` n'offre pas cette garantie. Une
# machine virtuelle dont l'horloge matérielle démarre à une date absurde puis se
# synchronise pendant l'audit produisait sinon une durée de plusieurs milliers
# d'années — au-delà du plus grand entier représentable, l'API refusait alors le
# rapport entier pour ce seul champ de métadonnées.
#
# Le choix de la source ne dépend que de la lisibilité de `/proc/uptime` : les
# deux lectures qui encadrent l'audit retiennent donc la même horloge sans avoir
# à se le transmettre, ce qu'un appel en sous-shell rendrait impossible. Si le
# fichier venait malgré tout à disparaître entre les deux, la soustraction
# donnerait une valeur aberrante, que `audit_duration_ms` écarte.
clock_ms() {
  local up='' secs='' frac=''

  if read -r up _ </proc/uptime 2>/dev/null; then
    secs=${up%%.*}
    frac=${up#*.}
    [ "$frac" = "$up" ] && frac='0'
    frac="${frac}00"
    case "$secs$frac" in
      '' | *[!0-9]*) ;;
      *)
        printf '%s' "$((10#$secs * 1000 + 10#${frac:0:3}))"
        return 0
        ;;
    esac
  fi

  clock_ms_from_date
}

# Repli de `clock_ms` : l'horloge de `date`, et surtout **pas** `%s%3N`.
#
# ## Le défaut
#
# La largeur d'un `%N` n'est pas honorée partout. `uutils coreutils` — le `date`
# par défaut d'Ubuntu 25.10 — ignore le `3` et rend les neuf chiffres de
# nanosecondes : `date +%s%3N` y donne `1786976329122140886` là où GNU donne
# `1786976329122`. Toute durée en sortait multipliée par un million.
#
# Ce n'était pas cosmétique : la boucle du banc d'essai voyait son budget dépassé
# dès la première passe et **toutes** les mesures ne comportaient qu'un seul
# passage au lieu du nombre demandé — un débit mesuré sur un échantillon unique,
# annoncé comme soutenu.
#
# ## Le remède
#
# `%s%N` est demandé **sans largeur** — la forme que les deux implémentations
# rendent pareillement — puis divisé. Là où `%N` n'existe pas du tout (busybox),
# la chaîne porte un `N` littéral, donc n'est pas numérique, et la seconde
# entière prend le relais : la mesure perd en finesse, elle ne devient pas fausse.
#
# Fonction séparée pour être **atteignable par un test**. Repliée dans
# `clock_ms`, elle ne s'exécutait que sur une machine sans `/proc/uptime`, c'est-
# à-dire jamais sous Linux : le chemin cassé était invérifiable là où il comptait.
clock_ms_from_date() {
  local raw=''

  raw=$(date +%s%N 2>/dev/null) || raw=''
  case "$raw" in
    '' | *[!0-9]*) ;;
    *)
      printf '%s' "$((raw / 1000000))"
      return 0
      ;;
  esac

  raw=$(date +%s 2>/dev/null) || raw=''
  case "$raw" in
    '' | *[!0-9]*) printf '0' ;;
    *) printf '%s' "$((raw * 1000))" ;;
  esac
}

# Au-delà d'une journée, la valeur ne mesure plus un audit mais un saut
# d'horloge : même le profil `--stress` reste très en deçà.
readonly MAX_AUDIT_DURATION_MS=86400000

# audit_duration_ms <début_ms> <fin_ms>
#
# Durée de l'audit, ou **rien** si la mesure n'est pas exploitable. Le champ est
# optionnel dans le schéma : mieux vaut l'omettre, avec sa raison au journal de
# collecte, que publier un nombre faux — la règle est la même que pour un
# compteur SMART non lu.
audit_duration_ms() {
  local started=${1-} ended=${2-} duration=''

  case "$started" in '' | *[!0-9]*) return 0 ;; esac
  case "$ended" in '' | *[!0-9]*) return 0 ;; esac

  duration=$((10#$ended - 10#$started))
  [ "$duration" -lt 0 ] && return 0
  [ "$duration" -gt "$MAX_AUDIT_DURATION_MS" ] && return 0

  printf '%s' "$duration"
}

# Compte des lignes non vides sur stdin sans dépendre du code de retour de
# `grep -c`, qui renvoie 1 quand il n'y a aucune correspondance tout en
# écrivant déjà `0`. Enchaîner `|| printf '0'` produirait alors `0\n0`.
count_non_empty_lines() {
  awk 'NF { count++ } END { print count + 0 }'
}

# Compte les lignes correspondant à une expression régulière étendue.
count_matching_lines() {
  local pattern=${1-}
  # `-v` traite son argument comme une **chaîne** : awk y interprète les
  # séquences d'échappement et se plaint de `\.`, `\[` et `\]`, soit trois
  # avertissements sur la sortie d'erreur à chaque audit. Ils étaient invisibles
  # tant que l'erreur standard des collecteurs partait au néant.
  #
  # Les antislashs sont doublés ici, une fois, plutôt que dans chaque appelant :
  # une expression rationnelle correcte pour `grep` doit rester correcte pour
  # cette fonction.
  awk -v pattern="${pattern//\\/\\\\}" \
    'BEGIN { count = 0 } $0 ~ pattern { count++ } END { print count + 0 }'
}

# Normalise une date vers AAAA-MM-JJ, ou chaîne vide si elle est incertaine.
# Ne devine jamais : une date ambiguë est préférable absente.
to_iso_date() {
  local input=${1-}
  [ -z "$input" ] && return 0
  # Format déjà correct.
  if [[ $input =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    printf '%s' "$input"
    return 0
  fi
  # Format américain MM/JJ/AAAA de `dmidecode`.
  # `10#` force la base décimale : sans lui, printf interpréterait « 08 » comme
  # de l'octal invalide et produirait une date fausse.
  if [[ $input =~ ^([0-9]{1,2})/([0-9]{1,2})/([0-9]{4})$ ]]; then
    printf '%04d-%02d-%02d' \
      "$((10#${BASH_REMATCH[3]}))" "$((10#${BASH_REMATCH[1]}))" "$((10#${BASH_REMATCH[2]}))"
    return 0
  fi
  return 0
}

# Filtre les placeholders SMBIOS : les rapporter tels quels reviendrait à
# présenter « To Be Filled By O.E.M. » comme un nom de constructeur.
clean_dmi_value() {
  local value=''
  value=$(printf '%s' "${1-}" | trim)
  case "$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')" in
    '' | 'to be filled by o.e.m.' | 'to be filled by o.e.m' | 'default string' | \
      'system manufacturer' | 'system product name' | 'system serial number' | \
      'system version' | 'not specified' | 'not available' | 'unknown' | 'none' | \
      'n/a' | 'na' | 'default' | 'o.e.m.' | 'oem' | '0123456789' | 'chassis manufacture')
      return 0
      ;;
  esac
  printf '%s' "$value"
}

# --- Emplacement du rapport -------------------------------------------------
#
# Le rapport allait jusqu'ici dans le répertoire courant. C'est la même
# faiblesse que celle du scanner Windows, avec des conséquences différentes :
# sous `sudo` — c'est-à-dire pour tout audit complet —, un audit lancé depuis
# `/root`, depuis `/` ou depuis un répertoire de travail temporaire déposait le
# rapport là où son propriétaire n'irait pas le chercher. Le nom du fichier
# dépendait de l'endroit d'où la commande avait été tapée.
#
# La destination est désormais déduite de l'utilisateur, pas du terminal.

# Nom du rapport, sans extension : `sysaudit-<machine>`.
#
# Le nom de machine est ramené à un alphabet sûr — lettres, chiffres, point,
# tiret bas, tiret. Un nom peut contenir des caractères qu'un système de
# fichiers refuse, et le scanner Windows applique exactement le même filtre :
# la même machine donne le même nom de fichier des deux côtés.
#
# Vit ici, et non dans `sysaudit.sh`, pour être testable : c'est une règle de
# nommage, et une règle de nommage se vérifie.
report_basename() {
  local host=''
  host=$(anon hostname "$(hostname 2>/dev/null || printf 'machine')")
  host=$(printf '%s' "$host" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\{2,\}/-/g; s/^-//; s/-$//')
  [ -n "$host" ] || host='machine'
  printf 'sysaudit-%s' "$host"
}

# Dossier personnel de l'utilisateur qui a lancé l'audit.
#
# `sudo` est le cas qui compte. Il laisse `HOME=/root` — ou le conserve, selon
# la configuration de `env_reset` et de `always_set_home` —, et le rapport
# atterrissait alors dans le dossier personnel de root : lisible par root seul,
# introuvable pour l'humain qui vient de lancer l'audit et qui doit le déposer.
#
# `SUDO_USER` porte l'identité d'origine, et son dossier personnel se lit dans
# la base des comptes plutôt que se devine : `/home/<nom>` est faux dès qu'un
# annuaire, un `/Users` hérité ou un compte système entrent en jeu.
#
# Trois précautions :
#
#   - `SUDO_USER` valant `root` ne désigne personne d'autre que root — c'est un
#     `sudo -u root`, et il n'y a rien à rendre ;
#   - un audit lancé directement en root, sans `sudo`, n'a pas d'utilisateur
#     d'origine connu : `HOME` reste alors la seule réponse honnête ;
#   - `HOME` lui-même peut manquer — un `env -i`, un service, un conteneur
#     minimal. La base des comptes répond alors pour l'utilisateur courant.
resolve_user_home() {
  local candidate=''

  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != 'root' ]; then
    candidate=$(passwd_home_of "$SUDO_USER")
    [ -n "$candidate" ] && { printf '%s' "$candidate"; return 0; }
  fi

  if [ -n "${HOME:-}" ]; then
    printf '%s' "$HOME"
    return 0
  fi

  candidate=$(passwd_home_of "$(id -un 2>/dev/null)")
  printf '%s' "$candidate"
}

# Sixième champ de la ligne d'un compte, ou une chaîne vide.
#
# `getent` d'abord, parce qu'il interroge aussi les annuaires — LDAP, SSSD —
# que `/etc/passwd` ignore. Sa relève directe n'est pas un luxe : BusyBox ne
# fournit pas `getent`, et un conteneur minimal est exactement le genre
# d'endroit où un audit se lance.
passwd_home_of() {
  local user=${1-} line=''

  [ -n "$user" ] || return 0

  if has_cmd getent; then
    line=$(getent passwd "$user" 2>/dev/null)
  fi

  if [ -n "$line" ]; then
    printf '%s' "$line" | cut -d: -f6
    return 0
  fi

  [ -r /etc/passwd ] || return 0

  # Comparaison littérale, et non `grep "^$user:"` : un nom de compte n'a pas à
  # être relu comme une expression régulière.
  local name='' home=''
  while IFS=: read -r name _ _ _ _ home _; do
    if [ "$name" = "$user" ]; then
      printf '%s' "$home"
      return 0
    fi
  done < /etc/passwd

  return 0
}
