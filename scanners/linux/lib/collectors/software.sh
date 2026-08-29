#!/usr/bin/env bash
# Inventaire logiciel : paquets installés, services et périphériques PCI/USB.

# Au-delà de cette limite, seul le décompte est conservé : un rapport de
# plusieurs mégaoctets serait inexploitable côté navigateur (§80).
readonly MAX_PACKAGES=800

collect_software() {
  log_step 'Logiciels'

  local packages='' count=0 truncated='false' manager=''

  if [ "$(capability_tool dpkg)" = 'true' ]; then
    manager='apt'
    count=$(run_cmd dpkg-query -f '.\n' -W | count_non_empty_lines)
    packages=$(run_cmd dpkg-query -f '${Package}\t${Version}\n' -W | head -n "$MAX_PACKAGES" |
      packages_from_tsv "$manager")
  elif [ "$(capability_tool rpm)" = 'true' ]; then
    manager='rpm'
    count=$(run_cmd rpm -qa | count_non_empty_lines)
    packages=$(run_cmd rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\n' | head -n "$MAX_PACKAGES" |
      packages_from_tsv "$manager")
  elif [ "$(capability_tool pacman)" = 'true' ]; then
    manager='pacman'
    count=$(run_cmd pacman -Q | count_non_empty_lines)
    packages=$(run_cmd pacman -Q | head -n "$MAX_PACKAGES" | tr ' ' '\t' | packages_from_tsv "$manager")
  else
    record_issue 'software' 'warning' 'Aucun gestionnaire de paquets reconnu.' '' 'NOT_AVAILABLE'
  fi

  # Les paquets Snap et Flatpak s'ajoutent à ceux du gestionnaire système : une
  # application peut n'exister que là, et n'apparaîtrait sinon nulle part.
  local extra='' extra_count=0
  extra=$(collect_snap_packages)
  [ -n "$extra" ] && {
    packages=$(json_join "$packages" "$extra")
    extra_count=$((extra_count + $(snap_package_count)))
  }
  extra=$(collect_flatpak_packages)
  [ -n "$extra" ] && {
    packages=$(json_join "$packages" "$extra")
    extra_count=$((extra_count + $(flatpak_package_count)))
  }
  count=$((${count:-0} + extra_count))

  [ "${count:-0}" -gt "$MAX_PACKAGES" ] && truncated='true'

  json_object \
    "$(jf_raw packages "[$packages]")" \
    "$(jf_maybe_num packageCount "$count" NOT_AVAILABLE)" \
    "$(jf_raw packagesTruncated "$truncated")" \
    "$(section packageManagers "$(collect_package_managers)")" \
    "$(section runtimes "$(collect_runtimes)")" \
    "$(section services "$(collect_services)")"
}

# --- Snap et Flatpak ---------------------------------------------------------

snap_package_count() {
  has_cmd snap || { printf '0'; return 0; }
  run_cmd snap list | tail -n +2 | count_non_empty_lines || printf '0'
}

collect_snap_packages() {
  has_cmd snap || return 0
  # La première ligne est l'en-tête ; les colonnes sont séparées par des espaces.
  run_cmd snap list | tail -n +2 | awk 'NF { printf "%s\t%s\n", $1, $2 }' |
    head -n "$MAX_PACKAGES" | packages_from_tsv snap
}

flatpak_package_count() {
  has_cmd flatpak || { printf '0'; return 0; }
  run_cmd flatpak list --app --columns=application | count_non_empty_lines || printf '0'
}

collect_flatpak_packages() {
  has_cmd flatpak || return 0
  run_cmd flatpak list --app --columns=application,version |
    head -n "$MAX_PACKAGES" | packages_from_tsv flatpak
}

# --- Gestionnaires de paquets ------------------------------------------------

# Inventaire des gestionnaires présents, avec le nombre de paquets qu'ils gèrent.
#
# Le scanner **n'installe jamais** un gestionnaire absent : il constate. Un
# gestionnaire présent mais sans paquet est une information à part entière, et
# se distingue d'un gestionnaire qui n'a pas répondu — dont le compteur reste
# inconnu plutôt que nul.
collect_package_managers() {
  local managers='' name=''

  for name in apt dpkg rpm dnf pacman snap flatpak; do
    has_cmd "$name" || continue
    managers=$(json_join "$managers" "$(json_object \
      "$(jf_str name "$name")" \
      "$(jf_maybe_str version "$(package_manager_version "$name")" NOT_AVAILABLE 'version non exposée')" \
      "$(jf_maybe_num packageCount "$(package_manager_count "$name")" UNKNOWN 'le gestionnaire n’a pas répondu')")")
  done

  [ -n "$managers" ] || return 0
  printf '[%s]' "$managers"
}

package_manager_version() {
  case "$1" in
    apt) run_cmd apt-get --version | head -n1 | awk '{print $2}' ;;
    dpkg) run_cmd dpkg --version | head -n1 | sed -nE 's/.* ([0-9][^ ]*).*/\1/p' ;;
    rpm) run_cmd rpm --version | awk '{print $NF}' ;;
    dnf) run_cmd dnf --version | head -n1 ;;
    pacman) run_cmd pacman --version | sed -nE 's/.*Pacman v([^ ]+).*/\1/p' | head -n1 ;;
    snap) run_cmd snap version | awk '/^snap /{print $2}' ;;
    flatpak) run_cmd flatpak --version | awk '{print $NF}' ;;
  esac
}

package_manager_count() {
  case "$1" in
    apt | dpkg) run_cmd dpkg-query -f '.\n' -W | count_non_empty_lines ;;
    rpm | dnf) run_cmd rpm -qa | count_non_empty_lines ;;
    pacman) run_cmd pacman -Q | count_non_empty_lines ;;
    snap) snap_package_count ;;
    flatpak) flatpak_package_count ;;
  esac
}

# --- Environnements d'exécution ----------------------------------------------

# Runtimes recherchés, avec l'option qui donne leur version.
#
# La liste est **fermée et écrite en dur** : le scanner n'exécute jamais une
# commande construite à partir d'une donnée du système audité (SECURITY.md).
#
# `java --version` n'existe qu'à partir du JDK 9 ; le JDK 8 n'expose sa version
# que sur stderr, que `run_cmd` ne capture pas. Sur un JDK 8, la version reste
# donc inconnue avec sa raison — plutôt que devinée depuis un nom de paquet.
RUNTIME_PROBES=(
  'node|--version'
  'python3|--version'
  'java|--version'
  'go|version'
  'php|--version'
  'ruby|--version'
  'perl|--version'
  'dotnet|--version'
  'rustc|--version'
  'gcc|--version'
  'docker|--version'
  'podman|--version'
)

collect_runtimes() {
  local runtimes='' probe='' name='' flag='' output='' version=''

  for probe in "${RUNTIME_PROBES[@]}"; do
    name=${probe%%|*}
    flag=${probe#*|}
    has_cmd "$name" || continue

    output=$(run_cmd "$name" "$flag" || printf '')
    version=$(extract_version "$output")

    runtimes=$(json_join "$runtimes" "$(json_object \
      "$(jf_str name "$name")" \
      "$(jf_maybe_str version "$version" UNKNOWN 'numéro de version non reconnu dans la sortie')" \
      "$(jf_maybe_str path "$(command -v "$name" 2>/dev/null || printf '')")")")
  done

  [ -n "$runtimes" ] || return 0
  printf '[%s]' "$runtimes"
}

# Extrait le **premier** numéro de version d'une sortie de commande.
#
# Le premier, et non le dernier : `gcc --version` affiche « gcc (Ubuntu
# 13.3.0-6ubuntu2~24.04) 13.3.0 », et une expression gourmande y trouvait
# « 24.04 ». Les lignes vides sont ignorées — `perl --version` en commence une.
#
# Retourne une chaîne vide plutôt qu'une approximation lorsqu'aucun numéro n'est
# reconnaissable.
extract_version() {
  printf '%s' "${1-}" | awk 'NF { print; exit }' |
    grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1
}

packages_from_tsv() {
  local source=$1 out='' name='' version=''
  while IFS=$'\t' read -r name version; do
    [ -z "$name" ] && continue
    out=$(json_join "$out" "$(json_object \
      "$(jf_str name "$name")" \
      "$(jf_maybe_str version "$version")" \
      "$(jf_str source "$source")")")
  done
  printf '%s' "$out"
}

# --- Pilotes -----------------------------------------------------------------

# Sous Linux, un pilote **est** un module noyau : la section `drivers` était
# déclarée non collectée alors que `lsmod` la renseigne sans privilège.
#
# Le statut reste `UNKNOWN` : établir qu'un module est à jour exigerait de
# connaître la version publiée en amont, ce que le scanner n'interroge pas. Un
# module chargé n'est pas pour autant « à jour ».
collect_drivers() {
  has_cmd lsmod || {
    record_issue 'drivers' 'warning' 'lsmod absent : modules noyau non inventoriés.' 'lsmod' 'NOT_AVAILABLE'
    return 0
  }

  local drivers='' name='' used_by='' version='' count=0
  while read -r name _ _ used_by; do
    [ -z "$name" ] && continue
    [ "$name" = 'Module' ] && continue
    [ "$count" -ge 500 ] && break
    count=$((count + 1))

    version=$(read_value "/sys/module/$name/version" 2>/dev/null || printf '')

    drivers=$(json_join "$drivers" "$(json_object \
      "$(jf_maybe_str device "$(printf '%s' "$used_by" | tr -d ' ')" NOT_AVAILABLE 'module non rattaché à un périphérique')" \
      "$(jf_raw hardwareId "$(j_unknown NOT_AVAILABLE 'lsmod ne rattache pas le module à un identifiant matériel')")" \
      "$(jf_raw vendor "$(j_unknown NOT_AVAILABLE)")" \
      "$(jf_str name "$name")" \
      "$(jf_maybe_str version "$version" NOT_AVAILABLE 'module sans version déclarée')" \
      "$(jf_raw date "$(j_unknown NOT_AVAILABLE)")" \
      "$(jf_str provider 'noyau Linux')" \
      "$(jf_raw signed "$(j_unknown NOT_AVAILABLE 'signature du module non lisible sans privilège')")" \
      "$(jf_str infName "$name")" \
      "$(jf_str status UNKNOWN)")")
  done < <(run_cmd lsmod || true)

  [ -n "$drivers" ] || return 0
  printf '[%s]' "$drivers"
}

collect_services() {
  # Sans systemd, cette fonction ne rend **rien** — pas un tableau vide. Son
  # appelant doit donc passer par `section`, qui omet la clé : `jf_raw` émettait
  # `"services":` suivi du vide, et le rapport entier cessait d'être du JSON.
  # Le cas ne se voit pas sur une machine de développement, qui a systemd ; il
  # est apparu au premier audit lancé dans un conteneur.
  [ "$(capability_tool systemctl)" = 'true' ] || return 0

  # `list-units` donne l'état courant, `list-unit-files` l'activation au
  # démarrage : les deux sont nécessaires et sont fusionnés ici plutôt que
  # d'appeler `systemctl is-enabled` une fois par service.
  declare -A startup_by_unit=()
  local unit='' value=''
  while read -r unit value _; do
    [ -z "$unit" ] && continue
    startup_by_unit[$unit]=$value
  done < <(run_cmd systemctl list-unit-files --type=service --no-legend --no-pager --plain || true)

  local services='' name='' state='' startup='' count=0
  while read -r unit _ state _; do
    [ -z "$unit" ] && continue
    [ "$count" -ge 500 ] && break
    count=$((count + 1))

    name=${unit%.service}
    case "$state" in
      active) state='RUNNING' ;;
      inactive) state='STOPPED' ;;
      failed) state='FAILED' ;;
      *) state='UNKNOWN' ;;
    esac

    case "${startup_by_unit[$unit]-}" in
      enabled | enabled-runtime) startup='ENABLED' ;;
      disabled) startup='DISABLED' ;;
      static | indirect | generated | transient) startup='MANUAL' ;;
      *) startup='UNKNOWN' ;;
    esac

    services=$(json_join "$services" "$(json_object \
      "$(jf_str name "$name")" \
      "$(jf_str state "$state")" \
      "$(jf_str startup "$startup")")")
  done < <(run_cmd systemctl list-units --type=service --all --no-legend --no-pager --plain || true)

  printf '[%s]' "$services"
}

collect_devices() {
  log_step 'Périphériques'

  local pci='' usb=''

  if [ "$(capability_tool lspci)" = 'true' ]; then
    pci=$(collect_pci_devices)
  else
    record_issue 'devices.pci' 'warning' 'lspci absent : périphériques PCI non inventoriés.' 'lspci' 'NOT_AVAILABLE'
  fi

  # Le bus USB est le plus volumineux et le moins déterminant pour un
  # diagnostic matériel : il est réservé à la collecte complète.
  if ! depth_at_least devices standard; then
    record_level_skip 'devices.usb' full
  elif [ "$(capability_tool lsusb)" = 'true' ]; then
    usb=$(collect_usb_devices)
  else
    record_issue 'devices.usb' 'warning' 'lsusb absent : périphériques USB non inventoriés.' 'lsusb' 'NOT_AVAILABLE'
  fi

  json_object \
    "$(jf_raw pci "[$pci]")" \
    "$(jf_raw usb "[$usb]")" \
    "$(jf_raw other '[]')"
}

collect_pci_devices() {
  local devices='' line='' address='' class='' name='' vendor_id='' device_id='' driver='' status=''
  while IFS= read -r line; do
    [ -z "$line" ] && continue

    address=$(printf '%s' "$line" | awk '{print $1}')
    class=$(printf '%s' "$line" | sed -nE 's/^[^ ]+ ([^:]+) \[[0-9a-f]{4}\]:.*$/\1/p')
    vendor_id=$(printf '%s' "$line" | sed -nE 's/.*\[([0-9a-f]{4}):([0-9a-f]{4})\].*$/\1/p' | tail -n1)
    device_id=$(printf '%s' "$line" | sed -nE 's/.*\[([0-9a-f]{4}):([0-9a-f]{4})\].*$/\2/p' | tail -n1)
    name=$(printf '%s' "$line" | sed -E 's/^[^ ]+ [^:]+: //; s/ \[[0-9a-f]{4}:[0-9a-f]{4}\].*$//')

    driver=$(run_cmd lspci -k -s "$address" |
      sed -nE 's/^[[:space:]]*Kernel driver in use:[[:space:]]+(.*)$/\1/p' | head -n1)

    # `UNKNOWN`, et non `DRIVER_MISSING`.
    #
    # Le commentaire qui tenait ici disait déjà l'essentiel — « n'est pas
    # nécessairement en erreur : de nombreux contrôleurs n'en requièrent pas » —
    # et le code affirmait le contraire. `DRIVER_MISSING` est un verdict ; ce
    # qu'on observe est l'absence d'un lien symbolique dans
    # /sys/bus/pci/devices/$ADDR/driver, ce qui n'est pas la même chose.
    #
    # La documentation du noyau décrit le binding comme l'association d'un objet
    # device à un pilote compatible. Elle n'autorise pas la réciproque : un pont
    # hôte, un pont PCI, un contrôleur système ou le Data Fabric n'ont rien à
    # quoi se lier, et une machine x86 courante en expose une quinzaine.
    #
    # Le fait brut n'est pas perdu pour autant : le champ `driver` porte son
    # marqueur d'absence avec sa raison, et c'est sur lui que le moteur
    # raisonne. Windows continue de rendre `DRIVER_MISSING` — là, c'est le
    # Gestionnaire de périphériques qui le déclare, avec son code de problème.
    if [ -n "$driver" ]; then status='OK'; else status='UNKNOWN'; fi

    devices=$(json_join "$devices" "$(json_object \
      "$(jf_str bus PCI)" \
      "$(jf_maybe_str hardwareId "$(if [ -n "$vendor_id" ]; then printf '%s:%s' "$vendor_id" "$device_id"; fi)")" \
      "$(jf_maybe_str vendorId "$vendor_id")" \
      "$(jf_maybe_str deviceId "$device_id")" \
      "$(jf_raw vendor "$(j_unknown NOT_AVAILABLE 'nom du constructeur non séparé par lspci')")" \
      "$(jf_maybe_str name "$name")" \
      "$(jf_maybe_str class "$class")" \
      "$(jf_maybe_str driver "$driver" NOT_AVAILABLE 'aucun pilote noyau chargé')" \
      "$(jf_str status "$status")" \
      "$(jf_maybe_str address "$address")" \
      "$(section link "$(pcie_link_json "$address")")")")
  done < <(run_cmd lspci -nn || true)

  printf '%s' "$devices"
}

# Lien PCI Express négocié, lu dans /sys. Rien n'est rapporté pour un
# périphérique qui n'expose pas ces attributs : les cartes PCI classiques et de
# nombreux contrôleurs intégrés n'ont pas de lien PCIe à décrire.
pcie_link_json() {
  local address=${1-}
  [ -n "$address" ] || return 0

  # `lspci` abrège l'adresse quand le domaine vaut 0000 ; /sys ne l'abrège pas.
  local dir="/sys/bus/pci/devices/$address"
  [ -d "$dir" ] || dir="/sys/bus/pci/devices/0000:$address"
  [ -d "$dir" ] || return 0

  pcie_link_from_dir "$dir"
}

# Séparée de la résolution du chemin pour être testable sur une arborescence
# /sys reconstituée : la machine de CI n'a pas de périphérique PCIe.
pcie_link_from_dir() {
  local dir=${1-}
  [ -d "$dir" ] || return 0

  local cur_speed='' max_speed='' cur_width='' max_width=''
  cur_speed=$(read_value "$dir/current_link_speed" 2>/dev/null || printf '')
  max_speed=$(read_value "$dir/max_link_speed" 2>/dev/null || printf '')
  cur_width=$(read_value "$dir/current_link_width" 2>/dev/null || printf '')
  max_width=$(read_value "$dir/max_link_width" 2>/dev/null || printf '')

  # Un lien inconnu de bout en bout n'est pas une information : mieux vaut ne
  # pas émettre la clé que d'émettre quatre marqueurs d'absence.
  [ -n "$cur_speed$max_speed$cur_width$max_width" ] || return 0

  # Le noyau écrit « Unknown » quand le lien n'est pas entraîné.
  case "$cur_speed" in Unknown) cur_speed='' ;; esac
  case "$max_speed" in Unknown) max_speed='' ;; esac

  json_object \
    "$(jf_maybe_str currentSpeed "$cur_speed")" \
    "$(jf_maybe_str maxSpeed "$max_speed")" \
    "$(jf_maybe_num currentWidth "$cur_width")" \
    "$(jf_maybe_num maxWidth "$max_width")"
}

collect_usb_devices() {
  local devices='' line='' vendor_id='' device_id='' name='' address=''
  while IFS= read -r line; do
    [ -z "$line" ] && continue

    # `lsusb` préfixe chaque ligne de « Bus 001 Device 003: ». Ces deux nombres
    # sont l'adresse du périphérique, celle que `lsusb -s 001:003` accepte. Le
    # schéma la réclame, et le collecteur PCI la fournit déjà : l'omettre ici
    # rendait tout rapport contenant un périphérique USB invalide — invisible
    # sur une machine sans `lsusb`, ce qui était le cas du seul environnement
    # validé jusqu'ici.
    address=$(printf '%s' "$line" | sed -nE 's/^Bus ([0-9]+) Device ([0-9]+):.*$/\1:\2/p')
    vendor_id=$(printf '%s' "$line" | sed -nE 's/.*ID ([0-9a-f]{4}):([0-9a-f]{4}).*$/\1/p')
    device_id=$(printf '%s' "$line" | sed -nE 's/.*ID ([0-9a-f]{4}):([0-9a-f]{4}).*$/\2/p')
    name=$(printf '%s' "$line" | sed -E 's/^.*ID [0-9a-f]{4}:[0-9a-f]{4} ?//')

    # Les hubs racine ne sont pas des périphériques utiles à l'inventaire.
    case "$name" in
      *'root hub'*) continue ;;
    esac

    devices=$(json_join "$devices" "$(json_object \
      "$(jf_str bus USB)" \
      "$(jf_maybe_str hardwareId "$(if [ -n "$vendor_id" ]; then printf '%s:%s' "$vendor_id" "$device_id"; fi)")" \
      "$(jf_maybe_str vendorId "$vendor_id")" \
      "$(jf_maybe_str deviceId "$device_id")" \
      "$(jf_raw vendor "$(j_unknown NOT_AVAILABLE)")" \
      "$(jf_maybe_str name "$name")" \
      "$(jf_raw class "$(j_unknown NOT_AVAILABLE)")" \
      "$(jf_raw driver "$(j_unknown NOT_AVAILABLE 'pilote USB non exposé par lsusb')")" \
      "$(jf_str status UNKNOWN)" \
      "$(jf_maybe_str address "$address")")")
  done < <(run_cmd lsusb || true)

  printf '%s' "$devices"
}
