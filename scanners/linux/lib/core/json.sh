#!/usr/bin/env bash
# Construction de JSON valide en Bash.
#
# Générer du JSON à la main est la principale source d'erreurs d'un scanner
# shell : une valeur contenant un guillemet, une tabulation ou un octet de
# contrôle produit un document illisible. Tout passe donc par ces quelques
# fonctions, testées isolément, plutôt que par des `printf` dispersés.
#
# Convention : les fonctions `jf_*` produisent un fragment `"clé":valeur`, les
# fonctions `j_*` produisent une valeur JSON seule.

# --- Séparateur décimal ------------------------------------------------------
#
# `LC_NUMERIC=C` force le point décimal, quelle que soit la langue de la machine.
#
# Sans lui, sur une machine en français — `LANG=fr_BE.UTF-8`, ce qui est le
# réglage courant ici — deux outils changent de comportement :
#
#   - **mawk**, l'awk par défaut d'Ubuntu, écrit `1,0` là où gawk écrit `1.0` :
#     son `printf` passe par la bibliothèque C, qui suit `LC_NUMERIC` ;
#   - **le `printf` de bash refuse `1567.83` en entrée** — « invalid number » —
#     puis rend `1567,0`, c'est-à-dire un nombre faux, pas seulement mal écrit.
#
# `j_num` reconvertit la virgule en point, et le JSON produit reste donc valide.
# Mais cette protection est une seconde ligne : le résumé de fin d'audit, lui,
# affichait « 1,0 Kio » et le débit du banc d'essai sortait à `1567,0` avant même
# d'atteindre `j_num`.
#
# `LC_NUMERIC` seul, et non `LC_ALL` : les messages restent traduits et
# `console_supports_unicode` continue de lire le jeu de caractères de la locale
# pour choisir entre `✓` et `[OK]`. Forcer `LC_ALL=C` dégraderait l'affichage de
# toutes les machines pour corriger un point décimal.
#
# `LC_ALL` doit cependant être neutralisé d'abord : il **prime sur toutes** les
# catégories, `LC_NUMERIC` compris, et un `export LC_NUMERIC=C` seul resterait
# sans effet sur une machine où `LC_ALL` est défini. Le convertir en `LANG`
# conserve la langue et le jeu de caractères choisis, et rend la main aux
# catégories que l'on veut fixer.
if [ -n "${LC_ALL-}" ]; then
  LANG=$LC_ALL
  export LANG
  unset LC_ALL
fi
export LC_NUMERIC=C

# Échappe une chaîne pour insertion dans du JSON (sans les guillemets).
json_escape() {
  local s=${1-}
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\t'/\\t}
  s=${s//$'\r'/\\r}
  s=${s//$'\n'/\\n}
  # Les octets de contrôle restants sont retirés : ils sont illégaux en JSON et
  # apparaissent régulièrement dans les sorties de `dmidecode` sur du matériel
  # dont le SMBIOS est mal rempli.
  printf '%s' "$s" | LC_ALL=C tr -d '\000-\010\013\014\016-\037\177'
}

# Chaîne JSON complète, guillemets inclus.
j_str() {
  printf '"%s"' "$(json_escape "${1-}")"
}

# Nombre JSON. Retourne `null` si l'entrée n'est pas un nombre : mieux vaut une
# valeur nulle explicite qu'un document invalide.
j_num() {
  local v=${1-}
  v=${v//,/.}
  if [[ $v =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
    printf '%s' "$v"
  else
    printf 'null'
  fi
}

j_bool() {
  case "${1-}" in
    true | 1 | yes | y | on | enabled) printf 'true' ;;
    *) printf 'false' ;;
  esac
}

# Marqueur d'information non collectée.
# $1 = raison (UNKNOWN|NOT_AVAILABLE|UNSUPPORTED|PERMISSION_DENIED), $2 = détail
j_unknown() {
  local reason=${1:-UNKNOWN} detail=${2-}
  if [ -n "$detail" ]; then
    printf '{"unknown":true,"reason":"%s","detail":%s}' "$reason" "$(j_str "$detail")"
  else
    printf '{"unknown":true,"reason":"%s"}' "$reason"
  fi
}

# --- Fragments "clé":valeur -------------------------------------------------

jf_raw() { printf '"%s":%s' "$1" "$2"; }
jf_str() { printf '"%s":%s' "$1" "$(j_str "${2-}")"; }
jf_bool() { printf '"%s":%s' "$1" "$(j_bool "${2-}")"; }

# Champ **facultatif** : une valeur vide n'émet rien du tout.
#
# À ne pas confondre avec `jf_maybe_str`, qui émet un marqueur « inconnu ». Les
# deux disent des choses différentes : un marqueur affirme qu'une valeur existe
# et n'a pas pu être lue, une absence dit que la notion ne s'applique pas ici.
# Publier un marqueur là où le champ n'a pas lieu d'être créerait un trou dans
# le rapport à l'endroit exact où il n'y en a pas.
# $1 clé, $2 valeur
jf_optional_str() {
  [ -n "${2-}" ] || return 0
  jf_str "$1" "$2"
}

# Champ pouvant être inconnu : si la valeur est vide, émet un marqueur.
# $1 clé, $2 valeur, $3 raison si absente, $4 détail si absent
jf_maybe_str() {
  if [ -n "${2-}" ]; then
    jf_str "$1" "$2"
  else
    jf_raw "$1" "$(j_unknown "${3:-UNKNOWN}" "${4-}")"
  fi
}

# La table des bornes, déclarée ici pour qu'elle **existe toujours**.
#
# `schema-bounds.sh` la remplit et se charge avant ce fichier ; `declare -A` sur
# un tableau associatif déjà rempli n'en perd pas le contenu. Cette ligne ne sert
# donc que dans l'autre cas : `json.sh` chargé seul.
#
# ## Pourquoi ce n'est pas une précaution théorique
#
# Sans déclaration, Bash ne voit pas un tableau associatif : il évalue l'indice
# comme une **expression arithmétique**. `${SCHEMA_BOUNDS[current]}` devient donc
# la variable `current`, que `set -u` refuse — et le champ disparaît du rapport,
# avec un message sur la sortie d'erreur que personne ne lit.
#
# C'est exactement le mode de panne que ce chantier corrige, retourné contre
# lui-même : une grandeur parfaitement mesurée, effacée en silence parce qu'une
# table de bornes n'était pas chargée. Les suites qui éprouvent les fonctions
# pures chargent `json.sh` seul, et c'est ce qui l'a fait voir.
declare -A SCHEMA_BOUNDS

# Idem pour un nombre. Une valeur non numérique est traitée comme absente
# plutôt que convertie en 0 — un compteur SMART non lu n'est pas un compteur nul.
#
# ## Les bornes du schéma s'appliquent ici, et nulle part ailleurs
#
# Quand le champ figure dans `SCHEMA_BOUNDS`, une valeur hors du domaine que le
# schéma accepte devient un marqueur au lieu d'être publiée.
#
# Ce n'est pas une prudence supplémentaire, c'est la **seule** façon de tenir la
# règle : une valeur hors bornes ne franchira jamais la validation, et la publier
# ne fait pas passer l'information — elle fait refuser le rapport entier. Le
# 2026-08-27, `cycle_count = -1` sur une batterie a coûté un audit complet.
#
# Les gardes écrites à la main dans les fonctions de lecture restent en place et
# restent justes : elles bornent au plus près de la source, souvent plus finement
# que le schéma. Celle-ci est le filet en dessous, pas leur remplacement.
jf_maybe_num() {
  local v='' bornes=''
  v=$(j_num "${2-}")
  if [ "$v" != "null" ] && [ -n "${2-}" ]; then
    bornes=${SCHEMA_BOUNDS[$1]-}
    if [ -n "$bornes" ]; then
      jf_maybe_num_in "$1" "${2-}" "${bornes% *}" "${bornes#* }" "${3-}" "${4-}"
    else
      jf_raw "$1" "$v"
    fi
  else
    jf_raw "$1" "$(j_unknown "${3:-UNKNOWN}" "${4-}")"
  fi
}

# Champ numérique **facultatif** : une valeur illisible n'émet rien du tout.
#
# Le pendant de `jf_optional_str`, et il manquait. `jf_maybe_num` publie un
# marqueur, ce qui suppose que le schéma en accepte un ; tous les champs
# numériques ne sont pas dans ce cas. `network.interfaces[].ipv4[].prefixLength`
# est déclaré `optional()` et non `maybe()` : sur une interface point à point,
# où `ip -o addr` rend une adresse sans préfixe, le marqueur émis était refusé
# par la validation aussi sûrement que l'aurait été une valeur fausse.
#
# Émettre un marqueur là où le contrat n'en prévoit pas, c'est perdre l'audit
# pour avoir voulu dire « je ne sais pas ».
jf_optional_num() {
  local v=''
  v=$(j_num "${2-}")
  [ "$v" != "null" ] && [ -n "${2-}" ] || return 0
  jf_raw "$1" "$v"
}

# Idem, **borné** : une valeur hors des bornes physiques du champ est traitée
# comme absente, et non publiée.
#
# ## Le défaut que cette fonction ferme
#
# Une partie du parc ACPI rend `-1` dans `/sys/class/power_supply/BAT0/cycle_count`
# pour dire « ce compteur n'existe pas ». Ce n'est pas une mesure, c'est un aveu.
# `jf_maybe_num` le publiait tel quel, avec deux conséquences :
#
#  1. le rapport affirmait un nombre de cycles **négatif** — une valeur inventée,
#     exactement ce que le marqueur « inconnu » existe pour ne pas faire ;
#  2. le schéma borne ce champ à zéro, donc **l'audit entier était refusé** au
#     dépôt : « Le rapport ne respecte pas le schéma SysAudit ». Un aveu du
#     firmware faisait perdre un audit complet, et le message ne désignait ni la
#     batterie, ni la cause.
#
# Les bornes sont celles du schéma, pas des seuils inventés ici. Une borne vide
# ne contraint pas ce côté-là : `cycleCount` n'a pas de maximum, et lui en
# donner un ferait rejeter une batterie très ancienne mais parfaitement lue.
#
# $1 clé, $2 valeur, $3 borne basse (vide = aucune), $4 borne haute (vide =
# aucune), $5 raison si écartée, $6 détail
jf_maybe_num_in() {
  local v='' lo=${3-} hi=${4-}
  v=$(j_num "${2-}")
  if [ "$v" != "null" ] && [ -n "${2-}" ] &&
    { [ -z "$lo" ] || awk -v x="$v" -v b="$lo" 'BEGIN { exit !(x >= b) }'; } &&
    { [ -z "$hi" ] || awk -v x="$v" -v b="$hi" 'BEGIN { exit !(x <= b) }'; }; then
    jf_raw "$1" "$v"
  else
    jf_raw "$1" "$(j_unknown "${5:-UNKNOWN}" "${6-}")"
  fi
}

jf_maybe_bool() {
  case "${2-}" in
    true | false) jf_raw "$1" "$2" ;;
    *) jf_raw "$1" "$(j_unknown "${3:-UNKNOWN}" "${4-}")" ;;
  esac
}

# --- Assemblage -------------------------------------------------------------

# Joint des fragments par des virgules. Les fragments vides sont ignorés, ce qui
# évite les virgules orphelines quand un collecteur ne produit rien.
json_join() {
  local out='' item=''
  for item in "$@"; do
    [ -z "$item" ] && continue
    if [ -z "$out" ]; then out=$item; else out="$out,$item"; fi
  done
  printf '%s' "$out"
}

json_object() {
  printf '{%s}' "$(json_join "$@")"
}

# Fragment d'une section optionnelle du rapport.
#
# Une section qui n'a rien produit est **omise**, jamais émise vide : le schéma
# distingue « section absente » (collecte non tentée ou échouée) de « champ
# inconnu » (collecte tentée sans succès). Émettre `"storage":` produirait de
# surcroît un document invalide.
section() {
  [ -n "${2-}" ] || return 0
  jf_raw "$1" "$2"
}

json_array() {
  printf '[%s]' "$(json_join "$@")"
}

# Tableau de chaînes construit à partir de lignes lues sur stdin.
json_array_from_lines() {
  local out='' line=''
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if [ -z "$out" ]; then out=$(j_str "$line"); else out="$out,$(j_str "$line")"; fi
  done
  printf '[%s]' "$out"
}
