#!/bin/sh
# Socle commun aux scanners expérimentaux : détection d'outils, journal de
# collecte, table des capacités.
#
# ATTENTION — fichier partagé, à l'octet près, entre les trois scanners
# expérimentaux (`scanners/macos`, `scanners/bsd`, `scanners/android`). Un test
# de parité (`scanners/experimental-parity.test.ts`) échoue si les copies
# divergent.
#
# ## Le principe qui gouverne tout ce fichier
#
# Un scanner expérimental tourne sur un système que personne n'a encore essayé.
# Il n'a donc **aucun droit de supposer** qu'une commande existe, qu'elle
# répond, ou qu'elle répond dans le format attendu. Trois fonctions encadrent
# cela, et rien ne doit s'en écarter :
#
#   have <cmd>        la commande existe-t-elle ?
#   try  <cmd...>     l'exécuter en capturant l'échec, sans jamais interrompre
#   feature <clé> <état> [motif]   déclarer ce qu'on a pu répondre
#
# Un collecteur qui appellerait une commande sans passer par `have` produirait,
# sur un système où elle manque, soit un champ vide — indiscernable d'une valeur
# mesurée — soit un arrêt du scanner. Les deux sont interdits.

# Statut du scanner, lu par les tests de parité et repris dans `notes`.
# shellcheck disable=SC2034 # consommée par les scanners qui sourcent ce fichier.
SYSAUDIT_STATUS='EXPERIMENTAL'

# --- Séparateur décimal ------------------------------------------------------
#
# `LC_NUMERIC=C` force le point décimal, quelle que soit la langue de la machine.
# Sans lui, `mawk` — l'awk par défaut d'Ubuntu — écrit `1,0` là où gawk écrit
# `1.0`, et le `printf` de bash refuse `1567.83` en entrée sur une machine en
# français. Le JSON produit deviendrait invalide.
#
# `LC_NUMERIC` seul, et non `LC_ALL` : les messages restent traduits. Mais
# `LC_ALL` prime sur toutes les catégories : il faut le convertir en `LANG`
# d'abord, sans quoi l'export ci-dessous resterait sans effet.
if [ -n "${LC_ALL-}" ]; then
  LANG=$LC_ALL
  export LANG
  unset LC_ALL
fi
export LC_NUMERIC=C

# --- Journalisation ---------------------------------------------------------
#
# Tout part sur stderr : stdout est réservé au JSON, pour que
# `sysaudit.sh --stdout | jq` fonctionne.

log_info() { [ "${QUIET:-0}" = '1' ] || printf '[SysAudit] %s\n' "$*" >&2; }
log_step() { [ "${QUIET:-0}" = '1' ] || printf '  → %s\n' "$*" >&2; }
log_warn() { printf '  ! %s\n' "$*" >&2; }
log_error() { printf '[erreur] %s\n' "$*" >&2; }

die() {
  log_error "$*"
  exit 1
}

# --- Détection d'outils -----------------------------------------------------

# La commande est-elle lançable ?
#
# `command -v` et non `which` : `which` n'est pas dans POSIX, n'existe pas sur
# certaines images Android, et rend un code de sortie nul sur des systèmes où il
# n'a pourtant rien trouvé.
have() {
  command -v "$1" >/dev/null 2>&1
}

# Exécute une commande en absorbant son échec.
#
# Rend la sortie standard si la commande réussit, **rien** sinon — et surtout
# jamais le message d'erreur, qui finirait dans un champ du rapport en se
# faisant passer pour une valeur. Le code de sortie est propagé, ce qui permet
# à l'appelant de distinguer « vide » de « échec ».
try() {
  if ! have "$1"; then
    return 127
  fi
  "$@" 2>/dev/null
}

# Première ligne non vide d'une sortie. Beaucoup d'outils système émettent un
# en-tête ou une ligne vide en tête, et prendre `head -1` aveuglément rendrait
# une chaîne vide qui se lirait comme une absence de mesure.
first_line() {
  awk 'NF { print; exit }'
}

# --- Journal de collecte ----------------------------------------------------
#
# Le journal est un **fichier**, pas une variable : les collecteurs sont appelés
# par substitution de commande, donc dans un sous-shell, où toute variable
# modifiée disparaît au retour. C'est le défaut qui avait vidé
# `collection.issues` du scanner Linux pendant plusieurs versions.

ISSUES_FILE=''
SKIPPED_FILE=''
FEATURES_FILE=''
NOTES_FILE=''

init_journal() {
  _dir=$(mktemp -d "${TMPDIR:-/tmp}/sysaudit-XXXXXX" 2>/dev/null) || {
    log_warn 'Journal de collecte indisponible : les raisons d’absence ne seront pas rapportées.'
    return 0
  }
  chmod 700 "$_dir" 2>/dev/null || true
  ISSUES_FILE="$_dir/issues"
  SKIPPED_FILE="$_dir/skipped"
  FEATURES_FILE="$_dir/features"
  NOTES_FILE="$_dir/notes"
  : >"$ISSUES_FILE"
  : >"$SKIPPED_FILE"
  : >"$FEATURES_FILE"
  : >"$NOTES_FILE"
  # Le rapport peut contenir des données personnelles : le journal disparaît
  # quoi qu'il arrive, y compris sur interruption.
  trap 'rm -rf "'"$_dir"'" 2>/dev/null || true' EXIT INT TERM
}

# issue <section> <warning|error> <message> [source]
issue() {
  [ -n "$ISSUES_FILE" ] || return 0
  json_object \
    "$(jf_str section "$1")" \
    "$(jf_str severity "$2")" \
    "$(jf_str message "$3")" \
    "$(if [ -n "${4-}" ]; then jf_str source "$4"; fi)" >>"$ISSUES_FILE"
  printf '\n' >>"$ISSUES_FILE"
}

skipped() {
  [ -n "$SKIPPED_FILE" ] || return 0
  printf '%s\n' "$1" >>"$SKIPPED_FILE"
}

# Note libre du scanner, publiée telle quelle dans `report.notes`.
#
# Elle sert à publier un fait que le schéma n'a pas encore de place pour
# accueillir. Un scanner expérimental en rencontre forcément : le schéma a été
# écrit pour des plateformes validées. Écrire le fait ici vaut mieux que de le
# perdre, et infiniment mieux que d'inventer un champ.
#
# Fichier et non variable, pour la raison donnée plus haut : les collecteurs
# tournent dans un sous-shell.
note() {
  [ -n "$NOTES_FILE" ] || return 0
  printf '%s\n' "$1" >>"$NOTES_FILE"
}

# feature <clé> <AVAILABLE|NOT_AVAILABLE|UNSUPPORTED|PERMISSION_DENIED|NOT_COLLECTED|NOT_APPLICABLE> [motif]
#
# Déclare ce que **cette machine** a su répondre. C'est la production la plus
# importante d'un scanner expérimental : sans cette table, un lecteur ne peut
# pas distinguer « SysAudit ne sait pas encore faire ça ici » de « cette machine
# va mal ». Le motif est enregistré comme problème de collecte, afin qu'il
# apparaisse aussi dans `collection.issues`.
feature() {
  [ -n "$FEATURES_FILE" ] || return 0
  printf '%s %s\n' "$1" "$2" >>"$FEATURES_FILE"
  if [ "$2" != 'AVAILABLE' ] && [ -n "${3-}" ]; then
    issue "$1" 'warning' "$3"
  fi
}

# Table `capabilities.features`, prête à insérer.
features_json() {
  [ -n "$FEATURES_FILE" ] || return 0
  [ -s "$FEATURES_FILE" ] || return 0
  _out=''
  while read -r _key _state; do
    [ -n "$_key" ] || continue
    if [ -z "$_out" ]; then _out=''; else _out="$_out,"; fi
    _out="$_out$(jf_str "$_key" "$_state")"
  done <"$FEATURES_FILE"
  printf '{%s}' "$_out"
}

issues_json() {
  [ -n "$ISSUES_FILE" ] || {
    printf '[]'
    return 0
  }
  _out=''
  while IFS= read -r _line; do
    [ -n "$_line" ] || continue
    if [ -n "$_out" ]; then _out="$_out,"; fi
    _out="$_out$_line"
  done <"$ISSUES_FILE"
  printf '[%s]' "$_out"
}

notes_json() {
  _out=''
  if [ -n "$NOTES_FILE" ] && [ -s "$NOTES_FILE" ]; then
    while IFS= read -r _line; do
      [ -n "$_line" ] || continue
      if [ -n "$_out" ]; then _out="$_out,"; fi
      _out="$_out$(j_str "$_line")"
    done <"$NOTES_FILE"
  fi
  printf '[%s]' "$_out"
}

skipped_json() {
  [ -n "$SKIPPED_FILE" ] || {
    printf '[]'
    return 0
  }
  _out=''
  while IFS= read -r _line; do
    [ -n "$_line" ] || continue
    if [ -n "$_out" ]; then _out="$_out,"; fi
    _out="$_out$(j_str "$_line")"
  done <"$SKIPPED_FILE"
  printf '[%s]' "$_out"
}

# --- Horodatage -------------------------------------------------------------

# Instant courant en ISO 8601 UTC.
#
# `date -u +%Y-%m-%dT%H:%M:%SZ` est portable ; `date --iso-8601` ne l'est pas —
# BSD et macOS ne connaissent pas cette option, et l'appeler produirait une
# chaîne d'erreur là où le schéma attend un horodatage.
now_iso() {
  date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf '1970-01-01T00:00:00Z'
}

# Convertit un instant Unix en ISO 8601 UTC.
#
# GNU et BSD ne partagent aucune syntaxe pour cela : `date -d @…` d'un côté,
# `date -r …` de l'autre. Les deux sont tentées, et l'échec des deux rend une
# chaîne vide — donc un marqueur au rapport, jamais une date inventée.
epoch_to_iso() {
  [ -n "${1-}" ] || return 0
  case "$1" in
    '' | *[!0-9]*) return 0 ;;
  esac
  date -u -r "$1" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null ||
    date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null ||
    true
}
