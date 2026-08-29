#!/usr/bin/env bash
# Rapport Markdown local.
#
# Volontairement simple : le rapport riche (scores, recommandations, historique)
# est produit à partir du JSON par la plateforme. Ce fichier sert à lire
# l'essentiel immédiatement, sans navigateur ni serveur.

md_bytes() {
  local bytes=${1-}
  [[ $bytes =~ ^[0-9]+$ ]] || { printf 'inconnu'; return 0; }
  awk -v b="$bytes" 'BEGIN {
    split("o Kio Mio Gio Tio Pio", u, " ");
    i = 1;
    while (b >= 1024 && i < 6) { b /= 1024; i++ }
    if (i == 1) printf "%d %s", b, u[i]; else printf "%.1f %s", b, u[i]
  }'
}

md_value() {
  local value=${1-}
  if [ -z "$value" ]; then printf 'inconnu'; else printf '%s' "$value"; fi
}

write_markdown_report() {
  local output=$1

  {
    printf '# Rapport SysAudit — %s\n\n' "$(md_value "$(anon hostname "$(hostname 2>/dev/null)")")"
    # Le niveau et son effet, plutôt qu'un « audit en lecture seule » qui
    # coiffait aussi les rapports du niveau Poussée — celui qui écrit.
    printf '> Audit %s (%s) généré le %s par SysAudit scanner %s (schéma %s).\n\n' \
      "$(level_label "$(current_level)")" "$(session_mode_label)" \
      "$(date '+%d/%m/%Y à %H:%M')" "$SCANNER_VERSION" "$SCHEMA_VERSION"

    if [ "$ANONYMIZE" = 'true' ]; then
      printf '> **Rapport anonymisé** : nom de machine, utilisateurs, IP publiques, MAC,\n'
      printf '> numéros de série, UUID et SSID ont été remplacés par des pseudonymes.\n\n'
    fi

    printf '## Système\n\n'
    printf '| Élément | Valeur |\n|---|---|\n'
    printf '| Machine | %s %s |\n' \
      "$(md_value "$(dmi_value /sys/class/dmi/id/sys_vendor system-manufacturer)")" \
      "$(md_value "$(dmi_value /sys/class/dmi/id/product_name system-product-name)")"
    printf '| Système | %s |\n' "$(md_value "$(detect_distribution)")"
    printf '| Noyau | %s |\n' "$(md_value "$(uname -r 2>/dev/null)")"
    printf '| Architecture | %s |\n' "$(md_value "$CAP_ARCHITECTURE")"
    printf '| Uptime | %s |\n' "$(md_uptime)"
    printf '| Privilèges | %s |\n' "$([ "$CAP_PRIVILEGED" = 'true' ] && printf 'root' || printf 'utilisateur standard')"
    printf '\n'

    md_section_cpu
    md_section_memory
    md_section_storage
    md_section_network
    md_section_security
    [ "$CAP_PROXMOX" = 'true' ] && md_section_proxmox
    md_section_collection

    printf '\n---\n\n'
    printf 'Le fichier JSON produit à côté de ce rapport est la source de vérité :\n'
    printf 'il contient l’intégralité des données collectées et peut être analysé\n'
    printf 'par la plateforme SysAudit (scores, recommandations, historique).\n'
  } >"$output"
}

md_uptime() {
  local seconds=''
  seconds=$(awk '{printf "%d", $1}' /proc/uptime 2>/dev/null) || { printf 'inconnu'; return 0; }
  printf '%d jours, %d heures' $((seconds / 86400)) $(((seconds % 86400) / 3600))
}

md_section_cpu() {
  printf '## Processeur\n\n'
  if [ -r /proc/cpuinfo ]; then
    printf -- '- **Modèle** : %s\n' \
      "$(md_value "$(sed -nE 's/^model name[[:space:]]*:[[:space:]]*(.*)$/\1/p' /proc/cpuinfo | head -n1)")"
    printf -- '- **Threads** : %s\n' "$(grep -c '^processor' /proc/cpuinfo 2>/dev/null || printf 'inconnu')"
  else
    printf -- '- Informations processeur non lisibles.\n'
  fi
  local temp=''
  temp=$(read_cpu_temperature)
  [ -n "$temp" ] && printf -- '- **Température** : %s °C\n' "$temp"
  printf '\n'
}

md_section_memory() {
  printf '## Mémoire\n\n'
  if [ -r /proc/meminfo ]; then
    printf -- '- **Installée** : %s\n' "$(md_bytes "$(awk '/^MemTotal:/ { print $2 * 1024 }' /proc/meminfo)")"
    printf -- '- **Disponible** : %s\n' "$(md_bytes "$(awk '/^MemAvailable:/ { print $2 * 1024 }' /proc/meminfo)")"
  fi
  local slots='' used=''
  slots=$(count_memory_slots)
  used=$(run_cmd dmidecode -t 17 2>/dev/null | grep -cE '^[[:space:]]*Size:[[:space:]]+[0-9]' || printf '')
  if [ -n "$slots" ] && [ -n "$used" ]; then
    printf -- '- **Slots** : %s occupés sur %s\n' "$used" "$slots"
  else
    printf -- '- **Slots** : inconnu (%s)\n' "$(md_value "$(dmi_detail)")"
  fi
  printf '\n'
}

md_section_storage() {
  printf '## Stockage\n\n'
  if [ "$(capability_tool lsblk)" != 'true' ]; then
    printf 'lsblk absent : disques non inventoriés.\n\n'
    return 0
  fi

  printf '| Disque | Modèle | Capacité | Type | Santé |\n|---|---|---|---|---|\n'
  local name='' size='' model='' kind='' health=''
  while read -r name; do
    [ -z "$name" ] && continue
    size=$(read_value "/sys/block/$name/size" || printf '')
    [ -n "$size" ] && size=$((size * 512))
    model=$(read_value "/sys/block/$name/device/model" || printf '')

    case "$name" in
      nvme*) kind='NVMe' ;;
      *) [ "$(read_value "/sys/block/$name/queue/rotational")" = '1' ] && kind='HDD' || kind='SSD' ;;
    esac

    health='non mesurée'
    if [ "$(capability_tool smartctl)" = 'true' ] && [ "$CAP_PRIVILEGED" = 'true' ]; then
      case "$(timeout -k 2 10 smartctl -H "/dev/$name" 2>/dev/null || true)" in
        *PASSED* | *'Status: OK'*) health='OK' ;;
        *FAILED*) health='**DÉFAILLANT**' ;;
      esac
    fi

    printf '| /dev/%s | %s | %s | %s | %s |\n' \
      "$name" "$(md_value "$model")" "$(md_bytes "$size")" "$kind" "$health"
  done < <(run_cmd lsblk -dn -o NAME,TYPE | awk '$2 == "disk" { print $1 }')

  printf '\n### Systèmes de fichiers\n\n'
  printf '| Point de montage | Taille | Utilisé | %% |\n|---|---|---|---|\n'
  df -B1 --output=target,size,used,pcent --local -x tmpfs -x devtmpfs -x overlay -x squashfs 2>/dev/null |
    awk 'NR>1 && $2 > 0 { printf "| %s | %s | %s | %s |\n", $1, $2, $3, $4 }' |
    while IFS='|' read -r _ target size used pct _; do
      printf '| %s | %s | %s | %s |\n' \
        "$(printf '%s' "$target" | trim)" \
        "$(md_bytes "$(printf '%s' "$size" | trim)")" \
        "$(md_bytes "$(printf '%s' "$used" | trim)")" \
        "$(printf '%s' "$pct" | trim)"
    done
  printf '\n'
}

md_section_network() {
  printf '## Réseau\n\n'
  printf '| Interface | Type | État | Adresse |\n|---|---|---|---|\n'

  local iface='' name='' state='' type='' addr=''
  for iface in /sys/class/net/*; do
    # Même règle que dans le collecteur réseau : une interface est un
    # répertoire. `bonding_masters` est un fichier, et l'interroger avec `ip`
    # était la dernière commande du scan — son échec devenait le code de sortie.
    [ -d "$iface" ] || continue
    name=$(basename "$iface")
    [ "$name" = 'lo' ] && continue

    state=$(read_value "$iface/operstate" 2>/dev/null || printf 'inconnu')
    type=$(detect_interface_type "$name" "$iface")
    addr=''
    if [ "$(capability_tool ip)" = 'true' ]; then
      addr=$(run_cmd ip -4 -o addr show dev "$name" | awk '{print $4}' | head -n1)
      if [ -n "$addr" ] && ! is_private_ipv4 "${addr%%/*}"; then
        addr=$(anon publicIp "${addr%%/*}")
      fi
    fi

    printf '| %s | %s | %s | %s |\n' "$name" "$type" "$state" "$(md_value "$addr")"
  done
  printf '\n'
}

md_section_security() {
  printf '## Sécurité\n\n'

  local firewall_state=''
  firewall_state=$(printf '%s' "$(collect_firewall)" | sed -nE 's/.*"state":"([A-Z]+)".*/\1/p')
  printf -- '- **Pare-feu** : %s\n' "$(md_value "$firewall_state")"
  printf -- '- **Secure Boot** : %s\n' "$(md_value "$(detect_secure_boot)")"

  if [ -r /etc/ssh/sshd_config ]; then
    printf -- '- **SSH — connexion root** : %s\n' "$(md_value "$(sshd_directive PermitRootLogin)")"
    printf -- '- **SSH — mot de passe** : %s\n' "$(md_value "$(sshd_directive PasswordAuthentication)")"
  fi

  local exposed=''
  exposed=$(run_cmd ss -Hlnt 2>/dev/null | awk '{print $4}' | count_matching_lines '^(0\.0\.0\.0|\[?::\]?):')
  printf -- '- **Ports TCP exposés sur toutes les interfaces** : %s\n' "$exposed"
  printf '\n'
}

md_section_proxmox() {
  printf '## Proxmox VE\n\n'
  printf -- '- **Version** : %s\n' "$(md_value "$(run_cmd pveversion | head -n1)")"
  has_cmd qm && printf -- '- **VM** : %s\n' "$(run_cmd qm list | awk 'NR>1' | count_non_empty_lines)"
  has_cmd pct && printf -- '- **Conteneurs LXC** : %s\n' "$(run_cmd pct list | awk 'NR>1' | count_non_empty_lines)"
  printf '\n'
}

# Limites de la collecte, lues dans le **journal** — un fichier, un
# enregistrement par ligne.
#
# Cette section lisait encore un tableau `COLLECTION_ISSUES`, disparu quand le
# journal est devenu un fichier (voir `core.sh`). Sous `set -u`, la référence
# faisait échouer la fonction : le Markdown du scanner s'arrêtait à la section
# précédente, perdant à la fois ses limites et sa note de fin. Aucun test ne
# l'avait vu, tous appelant le scanner avec `--no-markdown`.
md_section_collection() {
  [ -n "$COLLECTION_JOURNAL" ] && [ -s "$COLLECTION_JOURNAL" ] || return 0

  printf '## Limites de cette collecte\n\n'
  printf 'Les éléments suivants n’ont pas pu être collectés. Ils apparaissent dans le\n'
  printf 'JSON avec la raison exacte, et ne sont **pas** remplacés par des valeurs\n'
  printf 'approximatives.\n\n'

  # La section est nommée avant le motif : vingt lignes « Non collecté au
  # niveau Rapide » ne disent pas *ce* qui manque, donc rien d'actionnable.
  local issue='' section='' message=''
  while IFS= read -r issue; do
    [ -n "$issue" ] || continue
    section=$(printf '%s' "$issue" | sed -nE 's/.*"section":"([^"]*)".*/\1/p')
    message=$(printf '%s' "$issue" | sed -nE 's/.*"message":"([^"]*)".*/\1/p')
    if [ -n "$section" ]; then
      printf -- '- **%s** : %s\n' "$section" "$message"
    else
      printf -- '- %s\n' "$message"
    fi
  done <"$COLLECTION_JOURNAL"
  printf '\n'
}
