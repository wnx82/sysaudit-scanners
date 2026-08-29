#!/usr/bin/env bash
# Audit de sécurité Linux.
#
# Seuls des indicateurs de politique sont collectés : aucune clé, aucun hash,
# aucun contenu de fichier de configuration (SECURITY.md).

collect_security() {
  log_step 'Sécurité'

  # Le résumé garde ce qui se lit sans interroger le gestionnaire de paquets ni
  # parcourir les comptes : pare-feu et démarrage sécurisé. Le reste — mises à
  # jour en attente, comptes, durcissement, protocoles obsolètes — est le
  # travail du niveau Normale, et il prend du temps.
  local updates_json='' accounts_json='' linux_json='' obsolete_json=''
  if depth_at_least security standard; then
    updates_json=$(jf_raw updates "$(collect_updates)")
    # `section`, et non `jf_raw` : `collect_accounts` ne rend rien quand
    # /etc/passwd n'est pas lisible, et une clé sans valeur invalide le rapport.
    accounts_json=$(section accounts "$(collect_accounts)")
    linux_json=$(jf_raw linux "$(collect_linux_security)")
    obsolete_json=$(jf_raw obsoleteProtocols "$(collect_obsolete_protocols)")
  else
    record_level_skip 'security.updates' standard
    record_level_skip 'security.accounts' standard
    record_level_skip 'security.linux' standard
    record_level_skip 'security.obsoleteProtocols' standard
  fi

  json_object \
    "$(jf_raw firewall "$(collect_firewall)")" \
    "$updates_json" \
    "$(jf_maybe_str secureBoot "$(detect_secure_boot)" NOT_AVAILABLE)" \
    "$accounts_json" \
    "$linux_json" \
    "$obsolete_json"
}

collect_firewall() {
  local engine='' state='' policy='' rules=''

  if [ "$(capability_tool ufw)" = 'true' ] && [ "$CAP_PRIVILEGED" = 'true' ]; then
    engine='ufw'
    local out=''
    out=$(LC_ALL=C run_cmd ufw status verbose) || out=''
    case "$out" in
      *'Status: active'*) state='ENABLED' ;;
      *'Status: inactive'*) state='DISABLED' ;;
    esac
    policy=$(printf '%s' "$out" | sed -nE 's/^Default:[[:space:]]+([a-z]+) \(incoming\).*$/\1/p' | head -n1)
    rules=$(printf '%s' "$out" | grep -cE '^\[' || printf '')
  elif [ "$(capability_tool firewall-cmd)" = 'true' ]; then
    engine='firewalld'
    if run_cmd firewall-cmd --state >/dev/null 2>&1; then state='ENABLED'; else state='DISABLED'; fi
  elif [ "$(capability_tool nft)" = 'true' ] && [ "$CAP_PRIVILEGED" = 'true' ]; then
    engine='nftables'
    local ruleset=''
    ruleset=$(run_cmd nft list ruleset) || ruleset=''
    rules=$(printf '%s' "$ruleset" | count_matching_lines '^[[:space:]]+(ip|ip6|inet|tcp|udp|ct|meta)')
    if [ "${rules:-0}" -gt 0 ]; then state='ENABLED'; else state='DISABLED'; fi
    policy=$(printf '%s' "$ruleset" | sed -nE 's/.*type filter hook input priority [^;]*; policy ([a-z]+);.*/\1/p' | head -n1)
  elif [ "$(capability_tool iptables)" = 'true' ] && [ "$CAP_PRIVILEGED" = 'true' ]; then
    engine='iptables'
    local out=''
    out=$(run_cmd iptables -S) || out=''
    rules=$(printf '%s' "$out" | count_matching_lines '^-A')
    policy=$(printf '%s' "$out" | sed -nE 's/^-P INPUT ([A-Z]+)$/\1/p' | head -n1 | tr '[:upper:]' '[:lower:]')
    if [ "${rules:-0}" -gt 0 ] || [ "$policy" = 'drop' ]; then state='ENABLED'; else state='DISABLED'; fi
  fi

  # Les apostrophes accolées concaténaient trois fragments : le motif publié
  # devenait « aucun moteur= de= pare-feu détecté ». Un marqueur sert à faire
  # comprendre pourquoi une donnée manque ; illisible, il ne sert plus à rien.
  local reason='NOT_AVAILABLE' detail='aucun moteur de pare-feu détecté'
  if [ -n "$engine" ] && [ "$CAP_PRIVILEGED" != 'true' ]; then
    reason='PERMISSION_DENIED'
    detail='inspection du pare-feu réservée à root'
  fi

  json_object \
    "$(jf_maybe_str engine "$engine" "$reason" "$detail")" \
    "$(jf_maybe_str state "$state" "$reason" "$detail")" \
    "$(jf_maybe_str defaultInputPolicy "$policy" "$reason" "$detail")" \
    "$(jf_maybe_num ruleCount "$rules" "$reason" "$detail")"
}

collect_updates() {
  local pending='' security='' reboot='' last_update=''

  if [ "$(capability_tool apt)" = 'true' ]; then
    # `apt list --upgradable` lit le cache local : aucune requête réseau n'est
    # émise, le scanner ne devant jamais initier de trafic sortant.
    local out=''
    out=$(LC_ALL=C run_cmd apt-get -s -o Debug::NoLocking=1 upgrade) || out=''
    pending=$(printf '%s' "$out" | count_matching_lines '^Inst ')
    security=$(printf '%s' "$out" | awk 'BEGIN { count = 0 } /^Inst / && tolower($0) ~ /security/ { count++ } END { print count + 0 }')
  elif [ "$(capability_tool dnf)" = 'true' ]; then
    local out=''
    out=$(run_cmd dnf -C --quiet check-update) || true
    pending=$(printf '%s' "$out" | count_matching_lines '^[a-zA-Z0-9]')
  elif [ "$(capability_tool pacman)" = 'true' ]; then
    pending=$(run_cmd pacman -Qu | count_non_empty_lines)
  fi

  if [ -f /var/run/reboot-required ] || [ -f /run/reboot-required ]; then
    reboot='true'
  elif [ -d /var/run ]; then
    reboot='false'
  fi

  if [ -r /var/log/apt/history.log ]; then
    last_update=$(sed -nE 's/^Start-Date:[[:space:]]+([0-9-]+)[[:space:]]+([0-9:]+)$/\1T\2Z/p' \
      /var/log/apt/history.log | tail -n1)
  fi

  local auto=''
  if [ -r /etc/apt/apt.conf.d/20auto-upgrades ]; then
    if grep -qE 'Unattended-Upgrade"?[[:space:]]+"1"' /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null; then
      auto='ENABLED'
    else
      auto='DISABLED'
    fi
  fi

  json_object \
    "$(jf_maybe_num pending "$pending" NOT_AVAILABLE 'aucun gestionnaire de paquets reconnu')" \
    "$(jf_maybe_num securityPending "$security" NOT_AVAILABLE 'origine de sécurité non distinguable sur cette distribution')" \
    "$(jf_maybe_bool rebootRequired "$reboot")" \
    "$(jf_raw lastCheck "$(j_unknown NOT_AVAILABLE)")" \
    "$(jf_maybe_str lastUpdate "$last_update" NOT_AVAILABLE)" \
    "$(jf_maybe_str automaticUpdates "$auto" NOT_AVAILABLE)"
}

# Comptes système. Aucun hash n'est lu : /etc/shadow n'est jamais ouvert, seul
# `passwd -S` (ou l'absence d'information) est utilisé.
collect_accounts() {
  [ -r /etc/passwd ] || return 0

  local accounts='' name='' uid='' shell=''
  while IFS=: read -r name _ uid _ _ _ shell; do
    # Seuls les comptes humains sont rapportés : les comptes système ne portent
    # pas d'information de sécurité exploitable et gonfleraient le rapport.
    [ "${uid:-0}" -ge 1000 ] 2>/dev/null || [ "$name" = 'root' ] || continue
    [ "${uid:-0}" -ge 65534 ] 2>/dev/null && continue

    local admin='false'
    if [ "$name" = 'root' ]; then
      admin='true'
    elif id -nG "$name" 2>/dev/null | tr ' ' '\n' | grep -qxE 'sudo|wheel|admin'; then
      admin='true'
    fi

    local enabled='' passwordless=''
    case "$shell" in
      */nologin | */false) enabled='false' ;;
      *) enabled='true' ;;
    esac

    if [ "$CAP_PRIVILEGED" = 'true' ] && has_cmd passwd; then
      case "$(run_cmd passwd -S "$name" | awk '{print $2}')" in
        NP) passwordless='true' ;;
        P) passwordless='false' ;;
        L) passwordless='false'; enabled='false' ;;
      esac
    fi

    accounts=$(json_join "$accounts" "$(json_object \
      "$(jf_str name "$(anon username "$name")")" \
      "$(jf_raw admin "$admin")" \
      "$(jf_maybe_bool enabled "$enabled")" \
      "$(jf_maybe_bool passwordless "$passwordless" PERMISSION_DENIED 'état du mot de passe réservé à root')")")
  done </etc/passwd

  printf '[%s]' "$accounts"
}

collect_linux_security() {
  json_object \
    "$(jf_raw ssh "$(collect_ssh)")" \
    "$(jf_maybe_str apparmor "$(detect_apparmor)" NOT_AVAILABLE)" \
    "$(jf_maybe_str selinux "$(detect_selinux)")" \
    "$(jf_raw luks "$(detect_luks)")" \
    "$(section intrusionPrevention "$(collect_intrusion_prevention)")" \
    "$(section securityProducts "$(collect_security_products)")" \
    "$(jf_maybe_num sudoUsers "$(count_sudo_users)" NOT_AVAILABLE)" \
    "$(jf_maybe_num passwordlessAccounts "$(count_passwordless)" PERMISSION_DENIED 'nécessite root')"
}

# Configuration SSH : uniquement des indicateurs de politique. Le fichier n'est
# lu que pour ces quelques directives, jamais recopié dans le rapport.
collect_ssh() {
  local installed='false' running='' port='' root_login='' password_auth='' pubkey=''

  if [ -f /etc/ssh/sshd_config ] || [ "$(capability_tool sshd)" = 'true' ]; then
    installed='true'
  fi

  if [ "$installed" = 'true' ] && has_cmd systemctl; then
    if run_cmd systemctl is-active ssh >/dev/null 2>&1 ||
      run_cmd systemctl is-active sshd >/dev/null 2>&1; then
      running='true'
    else
      running='false'
    fi
  fi

  if [ -r /etc/ssh/sshd_config ]; then
    port=$(sshd_directive Port)
    root_login=$(sshd_directive PermitRootLogin)
    password_auth=$(sshd_bool_directive PasswordAuthentication)
    pubkey=$(sshd_bool_directive PubkeyAuthentication)

    # Valeurs par défaut d'OpenSSH quand la directive est absente : elles sont
    # documentées et stables, il ne s'agit donc pas d'une supposition.
    [ -z "$port" ] && port='22'
    [ -z "$root_login" ] && root_login='prohibit-password'
    [ -z "$password_auth" ] && password_auth='true'
    [ -z "$pubkey" ] && pubkey='true'
  fi

  json_object \
    "$(jf_raw installed "$installed")" \
    "$(jf_maybe_bool running "$running")" \
    "$(jf_maybe_num port "$port" PERMISSION_DENIED 'sshd_config non lisible')" \
    "$(jf_maybe_str permitRootLogin "$root_login" PERMISSION_DENIED 'sshd_config non lisible')" \
    "$(jf_maybe_bool passwordAuthentication "$password_auth" PERMISSION_DENIED 'sshd_config non lisible')" \
    "$(jf_maybe_bool pubkeyAuthentication "$pubkey" PERMISSION_DENIED 'sshd_config non lisible')" \
    "$(jf_str protocolVersion '2')"
}

sshd_directive() {
  grep -iE "^[[:space:]]*$1[[:space:]]+" /etc/ssh/sshd_config 2>/dev/null |
    tail -n1 | awk '{print $2}' | trim
}

sshd_bool_directive() {
  case "$(sshd_directive "$1" | tr '[:upper:]' '[:lower:]')" in
    yes) printf 'true' ;;
    no) printf 'false' ;;
    *) printf '' ;;
  esac
}

# Protections contre les tentatives d'intrusion répétées.
#
# « Installé » et « actif » sont rapportés séparément : un fail2ban installé
# mais arrêté ne protège rien, et l'utilisateur qui le croit actif est plus
# exposé que celui qui sait ne rien avoir.
collect_intrusion_prevention() {
  local tools='' name='' installed='' running='' jails=''

  for name in fail2ban crowdsec; do
    installed='false'
    running=''
    jails=''

    # Le paquet peut être installé sans que son client soit dans le PATH :
    # l'unité systemd fait donc autorité sur la présence.
    if has_cmd "${name}-client" || has_cmd cscli || [ -d "/etc/$name" ]; then
      installed='true'
    fi

    if [ "$(capability_tool systemctl)" = 'true' ]; then
      case "$(run_cmd systemctl is-active "$name" || printf '')" in
        active) installed='true'; running='true' ;;
        inactive | failed) running='false' ;;
      esac
    fi

    [ "$installed" = 'true' ] || continue

    if [ "$name" = 'fail2ban' ] && has_cmd fail2ban-client && [ "$CAP_PRIVILEGED" = 'true' ]; then
      jails=$(run_cmd fail2ban-client status |
        sed -nE 's/^.*Jail list:[[:space:]]*(.*)$/\1/p' | tr ',' '\n' | count_non_empty_lines)
    fi
    if [ "$name" = 'crowdsec' ] && has_cmd cscli && [ "$CAP_PRIVILEGED" = 'true' ]; then
      jails=$(run_cmd cscli scenarios list -o raw | tail -n +2 | count_non_empty_lines)
    fi

    tools=$(json_join "$tools" "$(json_object \
      "$(jf_str name "$name")" \
      "$(jf_raw installed "$installed")" \
      "$(jf_maybe_bool running "$running" NOT_AVAILABLE 'état du service non interrogeable')" \
      "$(jf_maybe_num activeJails "$jails" PERMISSION_DENIED 'décompte réservé à root')")")
  done

  [ -n "$tools" ] || return 0
  printf '[%s]' "$tools"
}

# Inventaire des produits de sécurité.
#
# Linux n'a pas d'équivalent du Centre de sécurité Windows : aucun registre ne
# tient la liste de ce qui protège la machine. L'inventaire se reconstitue
# source par source, et chaque entrée dit laquelle l'a établie — un paquet
# installé ne prouve pas qu'un démon tourne.
#
# La distinction qui compte est `kind`. ClamAV livre deux choses très
# différentes sous un seul nom : `clamscan`, qui analyse à la demande, et
# `clamd`, qui protège à l'ouverture des fichiers via l'extension `clamonacc`.
# Les confondre donnerait une fausse assurance sur une machine qui n'a qu'un
# outil manuel.
collect_security_products() {
  local products=''

  products=$(json_join "$products" "$(detect_clamav)")
  products=$(json_join "$products" "$(detect_mdatp)")

  # Un tableau vide est émis délibérément : il affirme qu'on a cherché, là où
  # son absence dirait seulement qu'on n'a rien collecté.
  printf '[%s]' "$products"
}

# ClamAV. Le démon et le scanner sont deux produits pour le lecteur du rapport.
detect_clamav() {
  local installed='false' daemon_running='' realtime='false' up_to_date='' kind='' state='' source=''

  if has_cmd clamscan || has_cmd clamdscan || [ -d /etc/clamav ]; then
    installed='true'
    source='PACKAGE_MANAGER'
  fi
  [ "$installed" = 'true' ] || return 0

  if [ "$(capability_tool systemctl)" = 'true' ]; then
    source='SERVICE_MANAGER'
    case "$(run_cmd systemctl is-active clamav-daemon || printf '')" in
      active) daemon_running='true' ;;
      inactive | failed) daemon_running='false' ;;
    esac
    if [ "$daemon_running" != 'true' ]; then
      case "$(run_cmd systemctl is-active clamd || printf '')" in
        active) daemon_running='true' ;;
        inactive | failed) [ -z "$daemon_running" ] && daemon_running='false' ;;
      esac
    fi
    # `clamonacc` est ce qui transforme le démon en protection à l'ouverture.
    # Sans lui, `clamd` répond à des requêtes sans surveiller quoi que ce soit.
    case "$(run_cmd systemctl is-active clamav-clamonacc || printf '')" in
      active) realtime='true' ;;
    esac
  fi

  if [ "$realtime" = 'true' ]; then
    kind='ANTIVIRUS'
    state='ACTIVE'
  elif [ "$daemon_running" = 'true' ]; then
    # Le démon tourne sans surveillance à l'ouverture : c'est un moteur
    # d'analyse disponible, pas une protection.
    kind='ON_DEMAND_SCANNER'
    state='ACTIVE'
  elif [ "$daemon_running" = 'false' ]; then
    kind='ON_DEMAND_SCANNER'
    state='DISABLED'
  else
    kind='ON_DEMAND_SCANNER'
    state='INSTALLED_UNKNOWN_STATE'
  fi

  up_to_date=$(clamav_signatures_fresh)

  json_object \
    "$(jf_str name 'ClamAV')" \
    "$(jf_str vendor 'Cisco')" \
    "$(jf_raw enabled "$([ "$state" = 'DISABLED' ] && printf 'false' || printf 'true')")" \
    "$(jf_maybe_bool upToDate "$up_to_date" NOT_AVAILABLE 'base de signatures non lisible')" \
    "$(jf_raw realtimeProtection "$realtime")" \
    "$(jf_maybe_bool daemonRunning "$daemon_running" NOT_AVAILABLE 'état du service non interrogeable')" \
    "$(jf_str kind "$kind")" \
    "$(jf_str state "$state")" \
    "$(jf_str source "$source")"
}

# Fraîcheur des signatures ClamAV : la base est considérée à jour si elle a
# moins de sept jours. Le seuil est celui de `freshclam`, dont la valeur par
# défaut est une vérification quotidienne — une base d'une semaine signale donc
# que la mise à jour ne fonctionne plus.
# $1 répertoire de la base, employé par `tests/run.sh` — six cas, dont l'âge
# négatif et la base incrémentale. ShellCheck analyse chaque fichier isolément
# et ne voit donc pas cet appelant : la directive dit ce que le lint ne peut pas
# déduire, elle ne masque rien.
# shellcheck disable=SC2120
clamav_signatures_fresh() {
  local dir="${1:-/var/lib/clamav}" db='' newest='' age='' mtime=''

  for db in "$dir/daily.cvd" "$dir/daily.cld"; do
    [ -r "$db" ] || continue
    newest=$db
    break
  done
  [ -n "$newest" ] || return 0

  # Un horodatage illisible ne vaut pas « périmé » : sans date, on ne dit rien.
  # C'est le piège du calcul direct — `stat` en échec rendrait 0, donc un âge
  # de cinquante-six ans, et une base parfaitement fraîche serait déclarée
  # périmée.
  mtime=$(stat -c %Y "$newest" 2>/dev/null) || return 0
  case "$mtime" in
    '' | *[!0-9]* | 0) return 0 ;;
  esac

  age=$(( $(date +%s) - mtime ))
  # Un âge négatif signale une horloge incohérente, pas une base fraîche.
  [ "$age" -ge 0 ] || return 0

  if [ "$age" -lt 604800 ]; then printf 'true'; else printf 'false'; fi
}

# Microsoft Defender for Endpoint. C'est un EDR, et la roadmap interdit
# nommément de le compter comme un antivirus temps réel sans preuve : seul
# `real_time_protection_enabled`, rendu par la CLI du produit, l'établit.
detect_mdatp() {
  local installed='false' realtime='' healthy='' state='' source='' kind='EDR'

  if has_cmd mdatp || [ -d /opt/microsoft/mdatp ]; then
    installed='true'
    source='PACKAGE_MANAGER'
  fi
  [ "$installed" = 'true' ] || return 0

  if has_cmd mdatp; then
    source='PRODUCT_CLI'
    case "$(run_cmd mdatp health --field real_time_protection_enabled | tr -d '"' | tr '[:upper:]' '[:lower:]')" in
      true) realtime='true' ;;
      false) realtime='false' ;;
    esac
    case "$(run_cmd mdatp health --field healthy | tr -d '"' | tr '[:upper:]' '[:lower:]')" in
      true) healthy='true' ;;
      false) healthy='false' ;;
    esac
  fi

  if [ "$realtime" = 'true' ]; then
    # La protection à l'ouverture est active et vérifiée : le produit remplit
    # bien le rôle d'un antivirus temps réel.
    kind='ANTIVIRUS'
    state='ACTIVE'
  elif [ "$realtime" = 'false' ]; then
    state='PASSIVE'
  elif [ "$healthy" = 'false' ]; then
    state='DISABLED'
  else
    state='INSTALLED_UNKNOWN_STATE'
  fi

  json_object \
    "$(jf_str name 'Microsoft Defender for Endpoint')" \
    "$(jf_str vendor 'Microsoft')" \
    "$(jf_maybe_bool enabled "$healthy" NOT_AVAILABLE 'CLI mdatp non interrogeable')" \
    "$(jf_raw upToDate "$(j_unknown NOT_AVAILABLE 'fraîcheur des définitions non exposée par mdatp health')")" \
    "$(jf_maybe_bool realtimeProtection "$realtime" NOT_AVAILABLE 'CLI mdatp non interrogeable')" \
    "$(jf_str kind "$kind")" \
    "$(jf_str state "$state")" \
    "$(jf_str source "$source")"
}

detect_apparmor() {
  [ -d /sys/kernel/security/apparmor ] || return 0
  if has_cmd aa-status && [ "$CAP_PRIVILEGED" = 'true' ]; then
    if run_cmd aa-status --enabled; then printf 'ENABLED'; else printf 'DISABLED'; fi
    return 0
  fi
  printf 'ENABLED'
}

detect_selinux() {
  [ -d /sys/fs/selinux ] || { printf 'UNSUPPORTED'; return 0; }
  case "$(run_cmd getenforce | tr '[:upper:]' '[:lower:]')" in
    enforcing) printf 'ENFORCING' ;;
    permissive) printf 'PERMISSIVE' ;;
    disabled) printf 'DISABLED' ;;
    *) printf '' ;;
  esac
}

detect_luks() {
  local devices='' present='false' name=''
  if [ "$(capability_tool lsblk)" = 'true' ]; then
    while IFS= read -r name; do
      [ -z "$name" ] && continue
      present='true'
      devices=$(json_join "$devices" "$(j_str "$name")")
    done < <(run_cmd lsblk -nrp -o NAME,FSTYPE | awk '$2 == "crypto_LUKS" { print $1 }')
  fi
  json_object "$(jf_raw present "$present")" "$(jf_raw devices "[$devices]")"
}

count_sudo_users() {
  getent group sudo wheel 2>/dev/null |
    awk -F: '{ print $4 }' | tr ',' '\n' | count_non_empty_lines
}

count_passwordless() {
  [ "$CAP_PRIVILEGED" = 'true' ] || return 0
  has_cmd passwd || return 0
  # `passwd -Sa` liste l'état des mots de passe sans exposer aucun hash.
  run_cmd passwd -Sa | awk '$2 == "NP"' | count_non_empty_lines
}

collect_obsolete_protocols() {
  local protocols=''

  # Telnet en écoute : protocole en clair, toujours à signaler.
  if has_cmd ss && run_cmd ss -Hlnt | awk '{print $4}' | grep -qE ':23$'; then
    protocols=$(json_join "$protocols" "$(json_object \
      "$(jf_str name 'Telnet')" \
      "$(jf_raw enabled true)" \
      "$(jf_str note 'Un service écoute sur le port 23 : le trafic Telnet circule en clair.')")")
  fi

  # FTP en clair.
  if has_cmd ss && run_cmd ss -Hlnt | awk '{print $4}' | grep -qE ':21$'; then
    protocols=$(json_join "$protocols" "$(json_object \
      "$(jf_str name 'FTP')" \
      "$(jf_raw enabled true)" \
      "$(jf_str note 'Un service écoute sur le port 21 : privilégier SFTP ou FTPS.')")")
  fi

  # SMBv1 côté Samba.
  if [ -r /etc/samba/smb.conf ] &&
    grep -qiE '^[[:space:]]*(min protocol|server min protocol)[[:space:]]*=[[:space:]]*NT1' /etc/samba/smb.conf 2>/dev/null; then
    protocols=$(json_join "$protocols" "$(json_object \
      "$(jf_str name 'SMBv1')" \
      "$(jf_raw enabled true)" \
      "$(jf_str note 'Samba est configuré pour accepter SMBv1 (NT1).')")")
  fi

  printf '[%s]' "$protocols"
}
