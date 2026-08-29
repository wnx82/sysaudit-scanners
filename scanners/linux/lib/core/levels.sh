#!/usr/bin/env bash
# Niveaux de diagnostic : quelle section, à quelle profondeur.
#
# Cette table est la copie embarquée de `packages/platform/src/diagnostic-levels.ts`.
# Elle est recopiée et non lue : le scanner doit tourner sur une machine sans
# Node.js. `packages/platform/src/diagnostic-levels-contract.test.ts` échoue si
# les deux divergent — c'est ce qui empêche le site de promettre une collecte
# que le scanner ne fait pas.
#
# Colonnes : section, puis la profondeur pour quick, standard, full et stress.
# Profondeurs, de la plus faible à la plus forte :
#
#   skipped   la section n'est pas collectée du tout ;
#   summary   collecte essentielle, sans sonde coûteuse ;
#              standard collecte complète ;
#   extended  collecte approfondie (sondes supplémentaires).
#
# `monitoring` et `firmware` n'y figurent pas : la première dépend de
# `--monitor`, la seconde n'est produite par aucun scanner.

# shellcheck disable=SC2034 # lue par level_depth, via awk.
readonly LEVEL_MATRIX='
system         standard standard standard standard
os             standard standard standard standard
motherboard    standard standard standard standard
bios           standard standard standard standard
cpus           summary  standard standard standard
memory         summary  standard standard standard
gpus           summary  standard standard standard
audio          summary  summary  summary  summary
sensors        standard standard extended extended
power          standard standard standard standard
storage        summary  standard extended extended
network        summary  standard standard standard
devices        skipped  standard standard standard
drivers        skipped  standard standard standard
software       skipped  standard standard standard
startup        skipped  summary  summary  summary
security       summary  standard standard standard
virtualization summary  standard standard standard
stability      summary  standard standard standard
boot           standard standard standard standard
shutdown       standard standard standard standard
events         skipped  standard standard standard
benchmark      skipped  skipped  skipped  standard
'

# Niveau effectif du scan, alias historiques résolus.
#
# `security` a été un profil à part entière ; il ne collectait rien de plus que
# `quick`. Le résoudre ici évite d'avoir à le tester partout ailleurs.
current_level() {
  case "${PROFILE:-standard}" in
    quick | security) printf 'quick' ;;
    full) printf 'full' ;;
    stress) printf 'stress' ;;
    *) printf 'standard' ;;
  esac
}

# Colonne de la table correspondant à un niveau.
level_column() {
  case "${1-}" in
    quick) printf '2' ;;
    full) printf '4' ;;
    stress) printf '5' ;;
    *) printf '3' ;;
  esac
}

# level_depth <section> [niveau]
#
# Profondeur prévue pour cette section. Une section absente de la table rend
# `standard` : une section non déclarée est collectée, jamais silencieusement
# ignorée.
level_depth() {
  local section=$1 level=${2:-}
  [ -n "$level" ] || level=$(current_level)

  local column=''
  column=$(level_column "$level")

  local depth=''
  depth=$(printf '%s' "$LEVEL_MATRIX" |
    awk -v s="$section" -v c="$column" '$1 == s { print $c; exit }')
  printf '%s' "${depth:-standard}"
}

# Sections écartées à la demande, séparées par des espaces.
#
# Elles se comportent exactement comme une section absente du niveau : rien
# n'est collecté, et l'absence est **déclarée** dans `collection.skippedSections`
# plutôt que tue. C'est la différence entre « nous n'avons pas regardé » et
# « il n'y avait rien » — le produit n'a jamais le droit de confondre les deux.
SKIP_SECTIONS="${SKIP_SECTIONS:-}"

# La section est-elle écartée à la demande ?
section_excluded() {
  case " ${SKIP_SECTIONS} " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# Cette section existe-t-elle dans la table ? Sert à refuser une exclusion
# portant sur un nom qui n'existe pas : une faute de frappe doit coûter un
# message d'erreur, pas une section silencieusement collectée quand même.
section_exists() {
  printf '%s' "$LEVEL_MATRIX" | awk -v s="$1" 'NF && $1 == s { found = 1 } END { exit !found }'
}

# Toutes les sections de la table, pour l'aide et la validation.
all_sections() {
  printf '%s' "$LEVEL_MATRIX" | awk 'NF { print $1 }'
}

# La section est-elle collectée à ce niveau ?
level_collects() {
  section_excluded "$1" && return 1
  [ "$(level_depth "$1")" != 'skipped' ]
}

# La profondeur courante atteint-elle au moins celle demandée ?
#
#   depth_at_least storage extended  →  vrai en profil complet et poussé
depth_at_least() {
  local section=$1 wanted=$2
  local have=''
  have=$(level_depth "$section")
  [ "$(depth_rank "$have")" -ge "$(depth_rank "$wanted")" ]
}

depth_rank() {
  case "${1-}" in
    skipped) printf '0' ;;
    summary) printf '1' ;;
    standard) printf '2' ;;
    extended) printf '3' ;;
    *) printf '0' ;;
  esac
}

# Sections collectées à ce niveau, dans l'ordre de la table.
sections_for_level() {
  local column=''
  column=$(level_column "$(current_level)")
  printf '%s' "$LEVEL_MATRIX" |
    awk -v c="$column" -v skip=" ${SKIP_SECTIONS} " \
      'NF && $c != "skipped" && index(skip, " " $1 " ") == 0 { print $1 }'
}

# Premier niveau qui collecte cette section, pour le dire à l'utilisateur.
# Rend une chaîne vide si aucun niveau ne la collecte.
level_that_collects() {
  local section=$1 level=''
  for level in quick standard full stress; do
    [ "$(level_depth "$section" "$level")" = 'skipped' ] && continue
    printf '%s' "$level"
    return 0
  done
}

# Nom public d'un niveau, tel qu'il est affiché à l'utilisateur.
level_label() {
  case "${1-}" in
    quick) printf 'Rapide' ;;
    standard) printf 'Normale' ;;
    full) printf 'Complète' ;;
    stress) printf 'Poussée' ;;
    *) printf '%s' "${1-}" ;;
  esac
}

# Déclare une donnée non collectée **à cause du niveau choisi**, avec le niveau
# qui l'aurait collectée.
#
# C'est une absence d'une autre nature qu'un outil manquant ou un accès refusé :
# la source existe peut-être très bien sur cette machine. Le rapport doit
# permettre de faire la différence, faute de quoi un audit Rapide se lit comme
# un audit dont la moitié des collectes a échoué.
record_level_skip() {
  local section=$1 needed=${2-}

  # Le même motif se rencontre une fois par disque ou par carte : `storage.smart`
  # sur une machine à quatre disques ne doit pas produire quatre lignes
  # identiques. Le journal est un fichier, donc lisible depuis le sous-shell
  # d'un collecteur.
  if [ -n "$SKIPPED_JOURNAL" ] && grep -qxF "$section" "$SKIPPED_JOURNAL" 2>/dev/null; then
    return 0
  fi

  # Une section écartée à la demande n'a pas la même raison d'être absente
  # qu'une section hors niveau. Lui coller « relancer au niveau Complète »
  # enverrait l'utilisateur refaire un audit plus long pour obtenir une donnée
  # que lui seul a décidé de ne pas collecter — et laisserait croire que le
  # niveau est en cause.
  if section_excluded "${section%%.*}"; then
    record_skipped "$section"
    record_issue "$section" 'warning' \
      'Écartée par --skip : le collecteur n’a pas été exécuté.' '' 'NOT_REQUESTED'
    return 0
  fi

  [ -n "$needed" ] || needed=$(level_that_collects "${section%%.*}")

  record_skipped "$section"
  if [ -n "$needed" ]; then
    record_issue "$section" 'warning' \
      "Non collecté au niveau $(level_label "$(current_level)") : relancer au niveau $(level_label "$needed")." \
      '' 'NOT_COLLECTED'
  else
    record_issue "$section" 'warning' \
      "Non collecté au niveau $(level_label "$(current_level)")." '' 'NOT_COLLECTED'
  fi
  return 0
}

# level_section <section> <collecteur> [arguments…]
#
# Exécute un collecteur si le niveau courant prévoit sa section, et rend le
# fragment JSON prêt à être assemblé. Sinon, ne l'exécute pas et déclare
# l'absence avec son motif.
#
# Passer par ce point unique est ce qui garantit qu'aucune section ne puisse
# être ignorée sans trace : le branchement et la déclaration ne peuvent plus
# être écrits séparément, donc plus diverger.
level_section() {
  local name=$1
  shift

  if ! level_collects "$name"; then
    record_level_skip "$name"
    return 0
  fi

  section "$name" "$(run_collector "$name" "$@")"
}

# Fragment JSON d'un champ non collecté à ce niveau, à passer à `jf_raw`.
level_unknown() {
  local needed=${1-}
  local detail=''
  if [ -n "$needed" ]; then
    detail="collecté au niveau $(level_label "$needed")"
  else
    detail="non prévu au niveau $(level_label "$(current_level)")"
  fi
  j_unknown NOT_COLLECTED "$detail"
}
