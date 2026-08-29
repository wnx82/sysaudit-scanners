#!/usr/bin/env bash
# Détection des capacités : que peut réellement faire ce scanner sur cette
# machine ? Exécutée avant toute collecte, elle conditionne le reste du scan et
# figure dans le rapport pour expliquer chaque donnée manquante (ADR 0003).

# Outils dont la présence change ce que le scanner peut collecter.
# Les outils du banc d'essai en font partie : leur absence explique un score
# manquant, et le rapport doit permettre de le comprendre sans relire le code.
CAPABILITY_TOOLS=(
  dmidecode lspci lsusb lsblk smartctl nvme sensors ip ss hostnamectl
  lscpu docker systemctl ufw firewall-cmd nft iptables apt dpkg rpm dnf pacman
  pveversion pvesh qm pct pvesm pvecm pvesr ceph ha-manager zpool sshd
  openssl dd fio glmark2 nvidia-smi
  journalctl systemd-analyze coredumpctl dmesg last vcgencmd
)

CAP_PLATFORM=''
CAP_DISTRIBUTION=''
CAP_ARCHITECTURE=''
CAP_PRIVILEGED='false'
CAP_VIRTUALIZED=''
CAP_PROXMOX='false'
CAP_DOCKER='false'
declare -A CAP_TOOLS

detect_capabilities() {
  log_step 'Détection des capacités'

  CAP_PLATFORM='linux'
  CAP_ARCHITECTURE=$(uname -m 2>/dev/null || printf 'unknown')

  if [ "$(id -u)" = "0" ]; then
    CAP_PRIVILEGED='true'
  else
    CAP_PRIVILEGED='false'
    log_warn "Exécution sans privilèges : les champs inaccessibles seront marqués PERMISSION_DENIED."
  fi

  local tool=''
  for tool in "${CAPABILITY_TOOLS[@]}"; do
    if has_cmd "$tool"; then CAP_TOOLS[$tool]='true'; else CAP_TOOLS[$tool]='false'; fi
  done

  CAP_DISTRIBUTION=$(detect_distribution)
  CAP_VIRTUALIZED=$(detect_hypervisor)
  detect_proxmox && CAP_PROXMOX='true'
  detect_docker && CAP_DOCKER='true'

  log_ok "Plateforme : ${CAP_DISTRIBUTION:-Linux} (${CAP_ARCHITECTURE}), privilégié : ${CAP_PRIVILEGED}"
  [ "$CAP_PROXMOX" = 'true' ] && log_ok 'Proxmox VE détecté : module dédié activé.'
  [ "$CAP_DOCKER" = 'true' ] && log_ok 'Docker détecté.'
  return 0
}

detect_distribution() {
  local id=''
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    id=$(. /etc/os-release 2>/dev/null && printf '%s' "${NAME:-${ID:-}}")
  fi
  [ -z "$id" ] && [ -r /etc/debian_version ] && id='Debian'
  [ -z "$id" ] && [ -r /etc/redhat-release ] && id=$(head -n1 /etc/redhat-release 2>/dev/null)
  printf '%s' "$id"
}

# Hyperviseur sur lequel cette machine s'exécute (et non ceux qu'elle héberge).
detect_hypervisor() {
  local result=''
  if has_cmd systemd-detect-virt; then
    result=$(systemd-detect-virt 2>/dev/null || true)
    [ "$result" = 'none' ] && result=''
  fi
  if [ -z "$result" ] && [ -r /sys/class/dmi/id/product_name ]; then
    case "$(cat /sys/class/dmi/id/product_name 2>/dev/null)" in
      *VMware*) result='vmware' ;;
      *VirtualBox*) result='oracle' ;;
      *KVM*) result='kvm' ;;
      *Hyper-V* | *"Virtual Machine"*) result='microsoft' ;;
    esac
  fi
  printf '%s' "$result"
}

# Proxmox est identifié par la présence conjointe de ses outils et de son
# répertoire de configuration : `pveversion` seul pourrait provenir d'un client.
detect_proxmox() {
  if has_cmd pveversion && { [ -d /etc/pve ] || [ -f /usr/bin/pvesh ]; }; then
    return 0
  fi
  return 1
}

detect_docker() {
  has_cmd docker || return 1
  # Docker peut être installé sans démon accessible ; on vérifie l'accès réel.
  run_cmd docker info --format '{{.ServerVersion}}' >/dev/null 2>&1
}

capability_tool() {
  printf '%s' "${CAP_TOOLS[$1]:-false}"
}

# Ce que cette machine sait répondre, domaine par domaine.
#
# `tools` dit quels **binaires** existent. Cela ne suffit pas : `journalctl`
# peut être installé et rendre un journal vide faute d'appartenance au groupe
# `systemd-journal`, et `dmesg` échouer sur `kernel.dmesg_restrict`. Seul un
# essai de lecture réel tranche.
#
# Sans cette table, un lecteur ne peut pas distinguer « SysAudit ne sait pas
# encore faire ça ici » de « cette machine va mal ».
build_features_json() {
  local features=''

  local events_status='NOT_AVAILABLE'
  if stability_journal_readable; then
    events_status='AVAILABLE'
  elif has_cmd journalctl; then
    # Installé mais muet : c'est un refus d'accès, pas une absence d'outil. Les
    # confondre enverrait l'utilisateur installer ce qu'il a déjà.
    events_status='PERMISSION_DENIED'
  elif has_cmd dmesg; then
    events_status='AVAILABLE'
  fi
  features=$(json_join "$features" "$(jf_str events "$events_status")")

  features=$(json_join "$features" \
    "$(jf_str boot "$(has_cmd systemd-analyze && printf 'AVAILABLE' || printf 'NOT_AVAILABLE')")")
  features=$(json_join "$features" \
    "$(jf_str shutdown "$(stability_journal_readable && printf 'AVAILABLE' || printf 'NOT_AVAILABLE')")")
  features=$(json_join "$features" \
    "$(jf_str 'stability.coredumps' "$(has_cmd coredumpctl && printf 'AVAILABLE' || printf 'NOT_AVAILABLE')")")
  features=$(json_join "$features" \
    "$(jf_str 'stability.reboots' "$(has_cmd last && printf 'AVAILABLE' || printf 'NOT_AVAILABLE')")")
  # Notion propre à Windows : rien à mesurer ici, ce qui n'est ni une panne ni
  # une lacune de SysAudit.
  features=$(json_join "$features" "$(jf_str 'boot.fastStartupEnabled' 'NOT_APPLICABLE')")

  # Refus SELinux. Trois situations que rien ne permet de confondre :
  #
  #   - pas de SELinux sur cette machine — il n'y a rien à mesurer ;
  #   - SELinux présent, mais aucune source d'audit lisible — on ne sait pas ;
  #   - SELinux présent et journal lisible — zéro refus veut alors dire zéro.
  #
  # C'est le critère explicite de l'étape 3 : « une absence d'auditd est
  # distinguée d'une absence d'incident ». Sans lui, une machine Fedora dont
  # `auditd` est arrêté se lirait comme une machine sans le moindre refus.
  #
  # Le test porte sur `/sys/fs/selinux/enforce` et **non** sur l'existence du
  # répertoire : le noyau WSL crée `/sys/fs/selinux` vide, sans SELinux derrière.
  # Se fier au répertoire annonçait donc « SELinux surveillé » sur une machine
  # qui n'en a pas.
  local selinux_status='NOT_APPLICABLE'
  if [ -e /sys/fs/selinux/enforce ]; then
    if stability_journal_readable || has_cmd ausearch; then
      selinux_status='AVAILABLE'
    else
      selinux_status='NOT_AVAILABLE'
    fi
  fi
  features=$(json_join "$features" "$(jf_str 'stability.selinuxDenials' "$selinux_status")")

  # Idem pour AppArmor, qui écrit ses refus dans le journal du noyau.
  #
  # `/sys/kernel/security` est en mode 0700 : un scan non privilégié n'y accède
  # pas, et conclure « pas d'AppArmor » de ce refus serait exactement l'erreur
  # que ce produit s'interdit. Le paramètre de module, lui, est lisible par
  # tous.
  local apparmor_status='NOT_APPLICABLE'
  if [ -r /sys/module/apparmor/parameters/enabled ]; then
    case "$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null)" in
      Y | y | 1)
        if stability_journal_readable || has_cmd dmesg; then
          apparmor_status='AVAILABLE'
        else
          apparmor_status='NOT_AVAILABLE'
        fi
        ;;
      # Module chargé mais désactivé : rien à surveiller, et c'est un fait lu.
      *) apparmor_status='NOT_APPLICABLE' ;;
    esac
  elif [ -d /sys/module/apparmor ] && [ "$CAP_PRIVILEGED" != 'true' ]; then
    apparmor_status='PERMISSION_DENIED'
  fi
  features=$(json_join "$features" "$(jf_str 'stability.apparmorDenials' "$apparmor_status")")

  features=$(json_join "$features" \
    "$(jf_str 'boot.kernels' "$(if has_cmd dpkg-query || has_cmd rpm || has_cmd pacman ||
      [ -d /lib/modules ]; then printf 'AVAILABLE'; else printf 'NOT_AVAILABLE'; fi)")")

  printf '{%s}' "$features"
}

# Fragment JSON de la section `capabilities`.
build_capabilities_json() {
  local tools='' name=''
  for name in "${!CAP_TOOLS[@]}"; do
    tools=$(json_join "$tools" "$(jf_bool "$name" "${CAP_TOOLS[$name]}")")
  done

  json_object \
    "$(jf_str platform "$CAP_PLATFORM")" \
    "$(if [ -n "$CAP_DISTRIBUTION" ]; then jf_str distribution "$CAP_DISTRIBUTION"; fi)" \
    "$(jf_str architecture "$CAP_ARCHITECTURE")" \
    "$(jf_raw privileged "$CAP_PRIVILEGED")" \
    "$(if [ -n "$CAP_VIRTUALIZED" ]; then jf_str virtualized "$CAP_VIRTUALIZED"; fi)" \
    "$(jf_raw proxmox "$CAP_PROXMOX")" \
    "$(jf_raw docker "$CAP_DOCKER")" \
    "$(jf_raw tools "{$tools}")" \
    "$(jf_raw features "$(build_features_json)")"
}
