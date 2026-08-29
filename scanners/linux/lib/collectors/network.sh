#!/usr/bin/env bash
# Réseau : interfaces, adressage, DNS, Wi-Fi et ports en écoute.
#
# Aucune clé Wi-Fi n'est jamais lue : seul le SSID est collecté, et il est
# anonymisable (SECURITY.md).

collect_network() {
  log_step 'Réseau'

  local interfaces='' dns='' domains='' ports=''

  interfaces=$(collect_interfaces)
  dns=$(collect_dns_servers)
  domains=$(collect_search_domains)

  # Ports en écoute, routes et proxy sont trois sondes distinctes du niveau
  # Normale. Un tableau de ports vide se lirait « aucun service exposé », ce
  # qui est une affirmation : à ce niveau, la liste est déclarée non collectée
  # plutôt que rendue vide.
  local ports_json='' routes_json='' proxy_json=''
  if depth_at_least network standard; then
    ports=$(collect_listening_ports)
    ports_json=$(jf_raw listeningPorts "[$ports]")
    routes_json=$(section routes "$(collect_routes)")
    proxy_json=$(section proxy "$(collect_proxy)")
  else
    record_level_skip 'network.listeningPorts' standard
    record_level_skip 'network.routes' standard
    record_level_skip 'network.proxy' standard
  fi

  json_object \
    "$(jf_raw interfaces "[$interfaces]")" \
    "$(jf_raw dnsServers "[$dns]")" \
    "$(jf_raw searchDomains "[$domains]")" \
    "$(collect_public_ip)" \
    "$ports_json" \
    "$routes_json" \
    "$proxy_json"
}

# Adresse publique (WAN), **sur demande explicite uniquement**.
#
# ## Pourquoi elle ne peut pas se lire localement
#
# Une machine derrière un routeur ne connaît pas son adresse publique : aucune
# interface ne la porte, aucun fichier ne l'écrit. Seul un correspondant distant
# l'observe. La relever suppose donc d'émettre un paquet vers l'extérieur — la
# seule collecte de ce scanner qui le fasse, et la raison pour laquelle elle se
# demande plutôt qu'elle ne s'exécute.
#
# ## Pourquoi l'API du produit, et non un service d'écho
#
# Envoyer l'empreinte réseau des machines auditées à un tiers pour *protéger*
# leur adresse serait l'exact contraire du but. L'API interrogée est celle vers
# laquelle le rapport partira de toute façon : elle n'apprend rien qu'elle
# n'aurait su.
#
# ## Ce que la fonction ne fait pas
#
# Elle n'invente aucune valeur. Une réponse absente, illisible ou qui n'a pas la
# forme d'une adresse donne un marqueur portant sa raison — jamais une chaîne
# reprise telle quelle, qui ferait entrer dans le rapport ce qu'un intermédiaire
# aura bien voulu y mettre.
#
# Sous `--no-public-ip`, ou faute d'API à interroger, elle n'émet **rien** : le
# champ absent se lit « pas de correspondant ». Un marqueur « non collecté »
# serait à peine moins faux, et il deviendrait « information protégée » à la
# lecture par un tiers — une phrase qui promettrait au propriétaire une valeur
# qui n'existe pas.
collect_public_ip() {
  # `auto` est le défaut : on relève si on peut, on se tait sinon. `true` est une
  # exigence, mais le scanner a déjà refusé de démarrer sans API dans ce cas :
  # le test d'URL ne peut donc échouer qu'en `auto`.
  [ "${OPT_PUBLIC_IP:-auto}" = 'false' ] && return 0
  [ -n "${OPT_API_URL:-}" ] || return 0

  if ! has_cmd curl; then
    jf_maybe_str publicIp '' NOT_AVAILABLE 'curl est requis pour interroger l’API'
    return 0
  fi

  local proxy_args=()
  mapfile -t proxy_args < <(curl_proxy_args)

  local body='' code=0
  body=$(curl -sS --max-time 15 \
    "${proxy_args[@]}" \
    -H "User-Agent: SysAudit-Scanner/$SCANNER_VERSION" \
    "${OPT_API_URL%/}/api/v1/public-ip" 2>/dev/null) || code=$?

  if [ "$code" -ne 0 ]; then
    jf_maybe_str publicIp '' NOT_AVAILABLE "l’API n’a pas répondu ($(curl_failure_label "$code"))"
    return 0
  fi

  local ip=''
  ip=$(printf '%s' "$body" | sed -nE 's/.*"ip"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p')

  # Une réponse qui n'a pas la forme d'une adresse n'est pas une adresse. Le
  # filtre est volontairement grossier — il laisse passer des chaînes qui ne
  # sont pas des adresses valides — parce que c'est l'API, à l'ingestion, qui
  # valide le format. Son travail ici est d'écarter tout ce qui pourrait n'être
  # pas une adresse du tout : page d'erreur d'un portail captif, HTML d'un proxy.
  case "$ip" in
    '' | *[!0-9a-fA-F.:]*)
      jf_maybe_str publicIp '' NOT_AVAILABLE 'réponse illisible — portail captif ou proxy interposé ?'
      return 0
      ;;
  esac

  jf_str publicIp "$(anon publicIp "$ip")"
}

# Table de routage IPv4 et IPv6, bornée : sur un routeur, la table complète
# ferait des milliers d'entrées sans rien apprendre sur la machine elle-même.
collect_routes() {
  [ "$(capability_tool ip)" = 'true' ] || return 0

  local routes='' line='' dest='' gw='' dev='' metric='' count=0
  local family=''
  for family in -4 -6; do
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      [ "$count" -ge 128 ] && break
      count=$((count + 1))

      dest=$(printf '%s' "$line" | awk '{print $1}')
      gw=$(printf '%s' "$line" | sed -nE 's/.*\bvia ([^ ]+).*/\1/p')
      dev=$(printf '%s' "$line" | sed -nE 's/.*\bdev ([^ ]+).*/\1/p')
      metric=$(printf '%s' "$line" | sed -nE 's/.*\bmetric ([0-9]+).*/\1/p')

      routes=$(json_join "$routes" "$(json_object \
        "$(jf_str destination "$dest")" \
        "$(jf_maybe_str gateway "$gw" UNSUPPORTED 'route directe, sans passerelle')" \
        "$(jf_maybe_str interface "$dev")" \
        "$(jf_maybe_num metric "$metric" NOT_AVAILABLE 'aucune métrique explicite')")")
    done < <(run_cmd ip "$family" route show || true)
  done

  [ -n "$routes" ] || return 0
  printf '[%s]' "$routes"
}

# Proxy configuré dans l'environnement.
#
# Une URL de proxy peut contenir des identifiants (`http://user:pass@proxy`) :
# la partie sensible est **retirée** avant écriture. Un secret n'est jamais
# rapporté, même masqué.
collect_proxy() {
  local http='' https='' no_proxy=''
  http=$(strip_proxy_credentials "${http_proxy:-${HTTP_PROXY:-}}")
  https=$(strip_proxy_credentials "${https_proxy:-${HTTPS_PROXY:-}}")
  no_proxy="${no_proxy:-${NO_PROXY:-}}"

  [ -n "$http$https$no_proxy" ] || return 0

  json_object \
    "$(jf_maybe_str http "$(anon domain "$http")" NOT_AVAILABLE 'aucun proxy HTTP configuré')" \
    "$(jf_maybe_str https "$(anon domain "$https")" NOT_AVAILABLE 'aucun proxy HTTPS configuré')" \
    "$(jf_maybe_str noProxy "$(anon domain "$no_proxy")" NOT_AVAILABLE 'aucune exclusion de proxy')"
}

# Retire `user:motdepasse@` d'une URL de proxy.
strip_proxy_credentials() {
  printf '%s' "${1-}" | sed -E 's#^([a-zA-Z][a-zA-Z0-9+.-]*://)[^/@]*@#\1#'
}

collect_interfaces() {
  local interfaces='' iface=''
  for iface in /sys/class/net/*; do
    # Une interface est un **répertoire**. `/sys/class/net` contient aussi
    # `bonding_masters`, un fichier de contrôle du pilote bonding : le test
    # `-e` l'acceptait, et toutes les machines rapportaient une interface
    # fantôme de ce nom, sans adresse ni état. Son interrogation par `ip` était
    # de plus la dernière commande du scan, et son échec devenait le code de
    # sortie du script : un audit réussi se terminait sur un code 1.
    [ -d "$iface" ] || continue
    interfaces=$(json_join "$interfaces" "$(collect_interface "$(basename "$iface")")")
  done
  printf '%s' "$interfaces"
}

collect_interface() {
  local name=$1 base="/sys/class/net/$1"
  local mac='' speed='' mtu='' state='' type='' driver='' ipv4='' ipv6='' gateway='' wifi_json=''

  mac=$(read_value "$base/address" || printf '')
  # Une MAC entièrement nulle est un placeholder, pas une adresse.
  [ "$mac" = '00:00:00:00:00:00' ] && mac=''
  mtu=$(read_value "$base/mtu" || printf '')
  speed=$(read_value "$base/speed" 2>/dev/null || printf '')
  # Le noyau rapporte -1 pour une interface sans lien : ce n'est pas une vitesse.
  [ "$speed" = '-1' ] && speed=''

  local duplex='' vlan_id=''
  case "$(read_value "$base/duplex" 2>/dev/null || printf '')" in
    full) duplex='FULL' ;;
    half) duplex='HALF' ;;
  esac
  # L'identifiant VLAN n'existe que sur une interface qui en porte un.
  [ -r /proc/net/vlan/config ] &&
    vlan_id=$(awk -v n="$name" '$1 == n { print $3 }' /proc/net/vlan/config 2>/dev/null | head -n1)

  case "$(read_value "$base/operstate" 2>/dev/null)" in
    up) state='UP' ;;
    down) state='DOWN' ;;
    *) state='UNKNOWN' ;;
  esac

  type=$(detect_interface_type "$name" "$base")

  if [ -L "$base/device/driver" ]; then
    driver=$(basename "$(readlink -f "$base/device/driver" 2>/dev/null)" 2>/dev/null)
  fi

  if [ "$(capability_tool ip)" = 'true' ]; then
    ipv4=$(collect_addresses "$name" -4)
    ipv6=$(collect_addresses "$name" -6)
    gateway=$(run_cmd ip -4 route show default dev "$name" | awk '{print $3}' | head -n1)
  fi

  if [ "$type" = 'wifi' ]; then
    wifi_json=$(collect_wifi "$name")
    [ -n "$wifi_json" ] && wifi_json=$(jf_raw wifi "$wifi_json")
  fi

  json_object \
    "$(jf_str name "$name")" \
    "$(jf_raw manufacturer "$(j_unknown NOT_AVAILABLE 'constructeur non exposé par le pilote')")" \
    "$(jf_raw model "$(j_unknown NOT_AVAILABLE)")" \
    "$(jf_maybe_str mac "$(anon macAddress "$mac")" NOT_AVAILABLE 'interface sans adresse matérielle')" \
    "$(jf_maybe_str type "$type")" \
    "$(jf_str status "$state")" \
    "$(jf_maybe_num speedMbps "$speed" NOT_AVAILABLE 'vitesse non rapportée (lien inactif ou interface virtuelle)')" \
    "$(jf_maybe_str duplex "$duplex" UNSUPPORTED 'notion sans objet sur cette interface')" \
    "$(section vlanId "$(j_num "$vlan_id" | grep -v '^null$' || true)")" \
    "$(jf_maybe_num mtu "$mtu")" \
    "$(jf_maybe_str driver "$driver" NOT_AVAILABLE)" \
    "$(jf_raw dhcp "$(j_unknown NOT_AVAILABLE 'mode d’attribution non déterminable de façon fiable')")" \
    "$(jf_raw ipv4 "[$ipv4]")" \
    "$(jf_raw ipv6 "[$ipv6]")" \
    "$(jf_maybe_str gateway "$gateway" NOT_AVAILABLE 'aucune route par défaut sur cette interface')" \
    "$wifi_json"
}

detect_interface_type() {
  local name=$1 base=$2
  [ "$name" = 'lo' ] && { printf 'loopback'; return 0; }
  [ -d "$base/wireless" ] && { printf 'wifi'; return 0; }
  [ -d "$base/bridge" ] && { printf 'bridge'; return 0; }
  [ -d "$base/bonding" ] && { printf 'bond'; return 0; }
  [ -f "$base/uevent" ] && grep -q 'DEVTYPE=vlan' "$base/uevent" 2>/dev/null && { printf 'vlan'; return 0; }
  # Les interfaces de tunnel portent des noms stables selon la technologie.
  case "$name" in
    tun* | tap* | wg* | ppp* | ipsec* | zt* | tailscale*) printf 'vpn'; return 0 ;;
  esac
  # Une interface sans périphérique physique associé est virtuelle (veth, tap…).
  [ -e "$base/device" ] || { printf 'virtual'; return 0; }
  printf 'ethernet'
}

collect_addresses() {
  local name=$1 family=$2 out='' line='' addr='' prefix=''
  while IFS= read -r line; do
    addr=${line%%/*}
    prefix=${line##*/}
    [ -z "$addr" ] && continue

    # Seules les adresses publiques sont anonymisées : masquer une IP privée
    # supprimerait une information utile sans protéger quoi que ce soit.
    if [ "$family" = '-4' ] && ! is_private_ipv4 "$addr"; then
      addr=$(anon publicIp "$addr")
    fi

    out=$(json_join "$out" "$(json_object \
      "$(jf_str address "$addr")" \
      "$(jf_optional_num prefixLength "$prefix")")")
  done < <(run_cmd ip "$family" -o addr show dev "$name" | awk '{print $4}')
  printf '%s' "$out"
}

is_private_ipv4() {
  case "$1" in
    10.* | 127.* | 169.254.* | 192.168.*) return 0 ;;
    172.1[6-9].* | 172.2[0-9].* | 172.3[01].*) return 0 ;;
    100.6[4-9].* | 100.[7-9][0-9].* | 100.1[01][0-9].* | 100.12[0-7].*) return 0 ;;
  esac
  return 1
}

wifi_channel_from_freq() {
  local freq=${1-}
  case "$freq" in
    2412) printf '1' ;;
    2417) printf '2' ;;
    2422) printf '3' ;;
    2427) printf '4' ;;
    2432) printf '5' ;;
    2437) printf '6' ;;
    2442) printf '7' ;;
    2447) printf '8' ;;
    2452) printf '9' ;;
    2457) printf '10' ;;
    2462) printf '11' ;;
    2467) printf '12' ;;
    2472) printf '13' ;;
    2484) printf '14' ;;
    *)
      if [[ $freq =~ ^[0-9]+$ ]]; then
        if [ "$freq" -ge 5000 ] && [ "$freq" -le 5895 ]; then
          printf '%s' $(( (freq - 5000) / 5 ))
        elif [ "$freq" -ge 5955 ] && [ "$freq" -le 7115 ]; then
          printf '%s' $(( (freq - 5950) / 5 ))
        fi
      fi
      ;;
  esac
}

wifi_signal_percent_from_dbm() {
  local signal=${1-}
  if [[ $signal =~ ^-?[0-9]+$ ]]; then
    if [ "$signal" -le -100 ]; then
      printf '0'
    elif [ "$signal" -ge -50 ]; then
      printf '100'
    else
      printf '%s' $(( (signal + 100) * 2 ))
    fi
  fi
}

collect_wifi() {
  local name=$1 ssid='' signal='' freq='' rate='' channel='' standard='' signal_percent='' info=''

  if has_cmd iw; then
    local out=''
    out=$(LC_ALL=C run_cmd iw dev "$name" link) || return 0
    ssid=$(printf '%s' "$out" | sed -nE 's/^[[:space:]]*SSID:[[:space:]]+(.*)$/\1/p' | head -n1)
    signal=$(printf '%s' "$out" | sed -nE 's/^[[:space:]]*signal:[[:space:]]+(-?[0-9]+) dBm.*$/\1/p' | head -n1)
    freq=$(printf '%s' "$out" | sed -nE 's/^[[:space:]]*freq:[[:space:]]+([0-9]+).*$/\1/p' | head -n1)
    rate=$(printf '%s' "$out" | sed -nE 's/^[[:space:]]*rx bitrate:[[:space:]]+([0-9]+).*$/\1/p' | head -n1)

    info=$(LC_ALL=C run_cmd iw dev "$name" info || printf '')
    standard=$(printf '%s' "$info" | sed -nE 's/^[[:space:]]*channel[[:space:]]+[0-9]+[[:space:]]+\(([0-9]+) MHz\),[[:space:]]+width:[[:space:]]+([^,]+).*/\2/p' | head -n1)
  fi

  channel=$(wifi_channel_from_freq "$freq")
  signal_percent=$(wifi_signal_percent_from_dbm "$signal")

  json_object \
    "$(jf_maybe_str ssid "$(anon wifiSsid "$ssid")" NOT_AVAILABLE 'iw absent ou interface non associée')" \
    "$(jf_maybe_num signalPercent "$signal_percent" NOT_AVAILABLE 'signal Wi-Fi non convertible en pourcentage')" \
    "$(jf_maybe_num signalDbm "$signal" NOT_AVAILABLE)" \
    "$(jf_maybe_num frequencyMhz "$freq" NOT_AVAILABLE)" \
    "$(jf_maybe_num channel "$channel" NOT_AVAILABLE 'canal Wi-Fi non déductible de la fréquence')" \
    "$(jf_maybe_str standard "$standard" NOT_AVAILABLE 'standard Wi-Fi non exposé par iw')" \
    "$(jf_maybe_num linkSpeedMbps "$rate" NOT_AVAILABLE)"
}

collect_dns_servers() {
  local out=''
  if has_cmd resolvectl; then
    while IFS= read -r server; do
      [ -z "$server" ] && continue
      out=$(json_join "$out" "$(j_str "$server")")
    done < <(run_cmd resolvectl dns | tr ' ' '\n' | grep -E '^[0-9a-fA-F:.]+$' | sort -u)
  fi
  if [ -z "$out" ] && [ -r /etc/resolv.conf ]; then
    while IFS= read -r server; do
      [ -z "$server" ] && continue
      out=$(json_join "$out" "$(j_str "$server")")
    done < <(sed -nE 's/^nameserver[[:space:]]+([^[:space:]]+).*$/\1/p' /etc/resolv.conf)
  fi
  printf '%s' "$out"
}

collect_search_domains() {
  local out=''
  [ -r /etc/resolv.conf ] || return 0
  while IFS= read -r domain; do
    [ -z "$domain" ] && continue
    out=$(json_join "$out" "$(j_str "$(anon domain "$domain")")")
  done < <(sed -nE 's/^(search|domain)[[:space:]]+(.*)$/\2/p' /etc/resolv.conf | tr ' ' '\n')
  printf '%s' "$out"
}

# Ports en écoute. `exposed` distingue une écoute limitée à la boucle locale
# d'une écoute sur toutes les interfaces : c'est ce qui détermine le risque réel.
collect_listening_ports() {
  [ "$(capability_tool ss)" = 'true' ] || {
    record_issue 'network.ports' 'warning' 'ss absent : ports en écoute non inventoriés.' 'ss' 'NOT_AVAILABLE'
    return 0
  }

  local ports='' line=''
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    ports=$(json_join "$ports" "$line")
  done < <(parse_listening_ports)

  printf '%s' "$ports"
}

parse_listening_ports() {
  local proto='' local_addr='' process='' addr='' port='' exposed=''
  # -H omet l'en-tête, -n évite toute résolution DNS (le scanner ne fait aucun
  # appel réseau sortant), -p n'est renseigné qu'avec les privilèges suffisants.
  #
  # `ss -H` publie sept colonnes : Netid, State, Recv-Q, Send-Q, adresse locale,
  # adresse distante, puis le processus. L'adresse locale est la **cinquième**.
  # Un `_` manquait, et `local_addr` recevait la file d'attente d'émission : le
  # rapport annonçait des ports 4096, 128 ou 0 — la profondeur du backlog prise
  # pour un numéro de port. Rien ne pouvait le voir sur un WSL2 sans service en
  # écoute, seul environnement validé jusqu'ici.
  while read -r proto _ _ _ local_addr _ process; do
    [ -z "$local_addr" ] && continue

    port=${local_addr##*:}
    addr=${local_addr%:*}
    [[ $port =~ ^[0-9]+$ ]] || continue
    # Une adresse sans deux-points n'est pas une adresse : `${x%:*}` rend alors
    # la chaîne entière, et port comme adresse porteraient la même valeur.
    [ "$addr" = "$local_addr" ] && continue

    # ss encadre les adresses IPv6 de crochets.
    addr=${addr#[}
    addr=${addr%]}
    [ -z "$addr" ] && addr='*'

    case "$addr" in
      '127.0.0.1' | '::1' | 'localhost') exposed='false' ;;
      '0.0.0.0' | '::' | '*') exposed='true' ;;
      *) exposed='true' ;;
    esac

    local proc_name=''
    proc_name=$(printf '%s' "$process" | sed -nE 's/.*users:\(\("([^"]+)".*/\1/p')

    case "$proto" in
      tcp | udp) : ;;
      *) continue ;;
    esac
    case "$addr" in
      *:*) proto="${proto}6" ;;
    esac

    # `json_object` n'ajoute pas de fin de ligne : sans ce `printf`, les objets
    # se collaient en une seule ligne sans saut final, et la boucle `read` de
    # l'appelant sortait avant d'en traiter un seul. La liste partait vide, donc
    # « aucun port en écoute » — sur un hyperviseur qui en avait quarante-six.
    printf '%s\n' "$(json_object \
      "$(jf_str protocol "$proto")" \
      "$(jf_raw port "$port")" \
      "$(jf_str address "$addr")" \
      "$(jf_maybe_str process "$proc_name" PERMISSION_DENIED 'nom du processus réservé à root')" \
      "$(jf_raw exposed "$exposed")")"
  done < <(run_cmd ss -Hlntup 2>/dev/null || run_cmd ss -Hlntu)
}
