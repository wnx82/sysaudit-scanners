#!/usr/bin/env bash
# Audio local et éléments exécutés automatiquement au démarrage.

collect_audio() {
  log_step 'Audio'

  local devices='' count=0
  local cards='/proc/asound/cards'

  if [ ! -e "$cards" ]; then
    record_issue 'audio' 'warning' 'Sous-système ALSA absent : audio non inventorié.' '/proc/asound/cards' 'NOT_AVAILABLE'
    record_provenance 'audio.devices' '/proc/asound/cards' 'lecture fichier' 'machine'
    printf '{"devices":[]}'
    return 0
  fi

  record_provenance 'audio.devices' '/proc/asound/cards' 'lecture fichier' 'carte'

  while IFS= read -r line; do
    [[ $line =~ ^[[:space:]]*([0-9]+)[[:space:]]+\[([^]]+)\]:[[:space:]]+([^[:space:]]+)[[:space:]]+-[[:space:]]+(.+)$ ]] || continue
    [ "$count" -ge 128 ] && break
    count=$((count + 1))
    devices=$(json_join "$devices" "$(json_object \
      "$(jf_str name "$(printf '%s' "${BASH_REMATCH[4]}" | trim)")" \
      "$(jf_raw vendor "$(j_unknown NOT_AVAILABLE 'constructeur non exposé par ALSA')")" \
      "$(jf_raw driver "$(j_unknown NOT_AVAILABLE 'pilote audio non exposé par ALSA')")" \
      "$(jf_str stack 'alsa')" \
      "$(jf_str kind PLAYBACK_CAPTURE)" \
      "$(jf_str state ENABLED)" \
      "$(jf_raw default "$(j_unknown UNKNOWN 'périphérique par défaut non exposé par cette lecture')")")")
  done <"$cards"

  json_object "$(jf_raw devices "[$devices]")"
}

# Extrait « unité<TAB>commande » d'une sortie `systemctl show -p Id -p ExecStart`.
#
# Le format de `ExecStart` est un enregistrement, pas une chaîne :
#
#   ExecStart={ path=/usr/sbin/sshd ; argv[]=/usr/sbin/sshd -D ; ignore_errors=no ; … }
#
# C'est `argv[]` qui porte la ligne réellement exécutée, options comprises —
# `path` ne donne que le binaire. Une unité sans exécutable (`.target`, une
# unité `oneshot` purement déclarative) rend un `ExecStart=` vide : elle
# n'apparaît pas dans la sortie, et gardera son marqueur.
parse_systemd_exec_start() {
  local id='' line='' raw=''
  while IFS= read -r line; do
    case "$line" in
      Id=*) id=${line#Id=} ;;
      ExecStart=*)
        [ -n "$id" ] || continue
        raw=${line#ExecStart=}
        case "$raw" in
          *'argv[]='*)
            raw=${raw#*'argv[]='}
            raw=${raw%% ; *}
            [ -n "$raw" ] && printf '%s\t%s\n' "$id" "$raw"
            ;;
        esac
        ;;
    esac
  done
}

collect_startup() {
  log_step 'Démarrage'

  if [ "$(capability_tool systemctl)" != 'true' ]; then
    record_issue 'startup' 'warning' 'systemctl absent : éléments au démarrage non inventoriés.' 'systemctl' 'NOT_AVAILABLE'
    record_provenance 'startup.items' 'systemctl' 'commande shell' 'service'
    printf '{"items":[]}'
    return 0
  fi

  record_provenance 'startup.items' 'systemctl list-unit-files' 'commande shell' 'service'

  local units='' states='' unit='' state='' count=0
  while read -r unit state _; do
    [ -n "$unit" ] || continue
    case "$state" in
      enabled | enabled-runtime | disabled | static | indirect | generated | transient) ;;
      *) continue ;;
    esac
    [ "$count" -ge 500 ] && break
    count=$((count + 1))
    units="$units$unit"$'\n'
    states="$states$unit $state"$'\n'
  done < <(run_cmd systemctl list-unit-files --type=service --no-legend --no-pager --plain || true)

  # Les commandes de démarrage, en **un seul** appel.
  #
  # `systemctl show` accepte toutes les unités d'un coup. Une invocation par
  # unité coûterait cinq cents processus sur un serveur ordinaire, ce qui ferait
  # de cette section la plus lente de l'audit — pour une donnée d'appoint. C'est
  # cette dépense-là, et non l'intérêt de la donnée, qui avait fait laisser un
  # marqueur « exige l'inspection détaillée de l'unité ».
  #
  # La ligne de commande d'une unité au démarrage est exactement ce qu'on
  # regarde pour repérer une persistance indésirable : elle a une valeur de
  # sécurité, et le domaine Sécurité du moteur pourra l'exploiter.
  local commands=''
  if [ -n "$units" ]; then
    commands=$(
      # shellcheck disable=SC2046
      # Découpage voulu : `systemctl show` prend les unités en arguments séparés.
      run_cmd systemctl show --no-pager --property=Id --property=ExecStart -- $(printf '%s' "$units") 2>/dev/null |
        parse_systemd_exec_start || true
    )
    record_provenance 'startup.items[].command' 'systemctl show -p ExecStart' 'commande shell' 'unité'
  fi

  local items='' command='' escaped=''
  while read -r unit state _; do
    [ -n "$unit" ] || continue

    # `printf %s` plutôt qu'un `grep -F` sur toute la sortie : le nom d'unité est
    # une donnée non fiable, et il entrerait sinon dans un motif.
    command=$(printf '%s\n' "$commands" | awk -F'\t' -v want="$unit" '$1 == want { print $2; exit }')

    if [ -n "$command" ]; then
      escaped=$(jf_str command "$command")
    else
      escaped=$(jf_raw command "$(j_unknown NOT_AVAILABLE 'unité sans commande de démarrage lisible')")
    fi

    items=$(json_join "$items" "$(json_object \
      "$(jf_str name "${unit%.service}")" \
      "$(jf_str kind SERVICE)" \
      "$(jf_str scope SYSTEM)" \
      "$(jf_bool enabled "$([ "$state" = 'disabled' ] && printf 'false' || printf 'true')")" \
      "$escaped" \
      "$(jf_str location 'systemd')")")
  done < <(printf '%s' "$states")

  json_object "$(jf_raw items "[$items]")"
}
