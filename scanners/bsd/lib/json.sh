#!/bin/sh
# Construction de JSON valide en shell POSIX.
#
# ATTENTION — fichier partagé, à l'octet près, entre les trois scanners
# expérimentaux (`scanners/macos`, `scanners/bsd`, `scanners/android`). Un test
# de parité (`scanners/experimental-parity.test.ts`) échoue si les copies
# divergent. Modifier ici, puis recopier — la divergence silencieuse entre
# scanners est exactement ce que ce test empêche.
#
# Pourquoi `sh` et non `bash` : FreeBSD n'installe pas bash, pfSense et OPNsense
# non plus, et l'interpréteur d'Android est `mksh`. macOS livre bash 3.2, dont
# les tableaux associatifs n'existent pas. Écrire en POSIX est donc la seule
# façon d'avoir **un** dialecte pour les trois.
#
# Convention, identique au scanner Linux : `jf_*` produit un fragment
# `"clé":valeur`, `j_*` produit une valeur JSON seule.

# Échappe une chaîne pour insertion dans du JSON, sans les guillemets.
#
# `sed` plutôt que la substitution de paramètres `${s//x/y}` : celle-ci est une
# extension bash, absente de `dash`, d'`ash` et de `mksh`.
json_escape() {
  printf '%s' "${1-}" |
    sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' |
    tr -d '\000-\010\013\014\016-\037\177' |
    awk 'BEGIN { ORS = "" } { if (NR > 1) print "\\n"; print }'
}

j_str() {
  printf '"%s"' "$(json_escape "${1-}")"
}

# Nombre JSON. Rend `null` si l'entrée n'en est pas un : mieux vaut une valeur
# nulle explicite qu'un document invalide.
j_num() {
  _v=$(printf '%s' "${1-}" | tr ',' '.')
  case "$_v" in
    '' | *[!0-9.eE+-]*) printf 'null' ;;
    *)
      if printf '%s' "$_v" | grep -Eq '^-?[0-9]+(\.[0-9]+)?$'; then
        printf '%s' "$_v"
      else
        printf 'null'
      fi
      ;;
  esac
}

j_bool() {
  case "${1-}" in
    true | 1 | yes | y | on | enabled | Enabled | YES) printf 'true' ;;
    *) printf 'false' ;;
  esac
}

# Marqueur d'information non collectée.
#
# Les six raisons du produit, et rien d'autre : `UNKNOWN`, `NOT_AVAILABLE`,
# `UNSUPPORTED`, `PERMISSION_DENIED`, `NOT_COLLECTED`, `NOT_APPLICABLE`. Un
# scanner expérimental s'en sert plus que les autres — c'est même sa principale
# production — et le détail est donc **obligatoire** en pratique : « non
# disponible » sans motif ne dit rien de plus que l'absence du champ.
j_unknown() {
  if [ -n "${2-}" ]; then
    printf '{"unknown":true,"reason":"%s","detail":%s}' "${1:-UNKNOWN}" "$(j_str "$2")"
  else
    printf '{"unknown":true,"reason":"%s"}' "${1:-UNKNOWN}"
  fi
}

# --- Fragments "clé":valeur -------------------------------------------------

jf_raw() { printf '"%s":%s' "$1" "$2"; }
jf_str() { printf '"%s":%s' "$1" "$(j_str "${2-}")"; }
jf_bool() { printf '"%s":%s' "$1" "$(j_bool "${2-}")"; }

# Champ pouvant être inconnu. Une valeur vide devient un marqueur, jamais une
# chaîne vide : le schéma refuse les chaînes vides, et une chaîne vide se lirait
# comme une valeur mesurée.
jf_maybe_str() {
  if [ -n "${2-}" ]; then
    jf_str "$1" "$2"
  else
    jf_raw "$1" "$(j_unknown "${3:-UNKNOWN}" "${4-}")"
  fi
}

# Idem pour un nombre. Une valeur non numérique est traitée comme absente plutôt
# que convertie en 0 — un compteur non lu n'est pas un compteur nul.
jf_maybe_num() {
  _n=$(j_num "${2-}")
  if [ "$_n" != 'null' ] && [ -n "${2-}" ]; then
    jf_raw "$1" "$_n"
  else
    jf_raw "$1" "$(j_unknown "${3:-UNKNOWN}" "${4-}")"
  fi
}

jf_maybe_bool() {
  case "${2-}" in
    true | false) jf_raw "$1" "$2" ;;
    *) jf_raw "$1" "$(j_unknown "${3:-UNKNOWN}" "${4-}")" ;;
  esac
}

# --- Assemblage -------------------------------------------------------------

# Joint des fragments par des virgules, en ignorant les vides. Sans cela, un
# collecteur qui ne produit rien laisserait une virgule orpheline et le document
# entier serait invalide.
json_join() {
  _out=''
  for _item in "$@"; do
    [ -z "$_item" ] && continue
    if [ -z "$_out" ]; then _out=$_item; else _out="$_out,$_item"; fi
  done
  printf '%s' "$_out"
}

json_object() {
  printf '{%s}' "$(json_join "$@")"
}

json_array() {
  printf '[%s]' "$(json_join "$@")"
}

# Fragment d'une section facultative du rapport.
#
# Une section qui n'a rien produit est **omise**, jamais émise vide : le schéma
# distingue « section absente » — collecte non tentée — de « champ inconnu » —
# collecte tentée sans succès.
section() {
  [ -n "${2-}" ] || return 0
  printf '"%s":%s' "$1" "$2"
}
