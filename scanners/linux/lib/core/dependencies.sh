#!/usr/bin/env bash
# Ce qui manque, et quoi installer pour l'obtenir.
#
# Le scanner tourne sans aucun outil externe : il dégrade explicitement. Mais
# jusqu'ici, l'utilisateur voyait « NOT_AVAILABLE : dmidecode absent » sans
# jamais apprendre que `apt install dmidecode` lui rendrait la carte mère, le
# BIOS et ses barrettes mémoire. Ce module comble exactement cet écart.
#
# Il **n'installe rien** et n'appelle aucun gestionnaire de paquets : il nomme.
# La décision et ses raisons : docs/adr/0006-dependances-externes.md.
#
# La table est la copie embarquée de `packages/platform/src/tool-dependencies.ts`
# — le scanner doit tourner sur une machine sans Node.js. Elle est vérifiée par
# `tool-dependencies-contract.test.ts` : un nom de paquet qui divergerait
# enverrait l'utilisateur installer quelque chose qui n'existe pas.
#
# Colonnes : outil, paquet Debian/Ubuntu, RHEL/Fedora, Arch, SUSE, Alpine, puis
# ce que l'outil débloque. Un tiret signale une famille où le paquet n'existe
# pas sous ce nom.

# shellcheck disable=SC2034 # lue par dependency_hints, via awk.
readonly DEPENDENCY_TABLE='
dmidecode dmidecode dmidecode dmidecode dmidecode dmidecode carte mère, BIOS et barrettes mémoire
smartctl smartmontools smartmontools smartmontools smartmontools smartmontools santé SMART et usure des disques
lspci pciutils pciutils pciutils pciutils pciutils cartes graphiques et périphériques PCI
lsusb usbutils usbutils usbutils usbutils usbutils périphériques USB
sensors lm-sensors lm_sensors lm_sensors sensors lm-sensors capteurs complémentaires
nvme nvme-cli nvme-cli nvme-cli nvme-cli nvme-cli journal SMART NVMe étendu
zpool zfsutils-linux zfs zfs-utils zfs zfs pools ZFS
ip iproute2 iproute iproute2 iproute2 - interfaces et routes réseau
ss iproute2 iproute iproute2 iproute2 - ports en écoute
ufw ufw - ufw ufw - état du pare-feu Ubuntu
firewall-cmd firewalld firewalld - firewalld - état du pare-feu firewalld
nft nftables nftables nftables nftables - règles de filtrage nftables
iptables iptables iptables iptables iptables - règles de filtrage héritées
fio fio fio fio fio fio mesure de lecture aléatoire du banc d’essai
glmark2 glmark2 glmark2 glmark2 glmark2 - mesure GPU du banc d’essai
coredumpctl systemd-coredump systemd-udev systemd systemd-coredump systemd vidanges mémoire recensées
ceph ceph-common ceph-common ceph ceph-common ceph santé d’une grappe Ceph
vcgencmd raspi-utils raspi-utils raspberrypi-utils raspi-utils raspberrypi-utils bridage et sous-tension d’un Raspberry Pi
'

# Outils interchangeables : une machine ne fait tourner qu'un pare-feu, et
# quatre outils répondent à la même question. Conseiller d'installer `ufw` à
# quelqu'un dont `nftables` répond déjà serait un conseil activement mauvais.
#
# Une ligne par groupe : nom du groupe, puis ses membres. Le contrat vérifie que
# ces groupes sont ceux de `tool-dependencies.ts`.
# shellcheck disable=SC2034 # lue par dependency_group_satisfied, via awk.
readonly DEPENDENCY_GROUPS='
firewall ufw firewall-cmd nft iptables
'

# Outils qui n'ont de sens que sur un certain matériel.
#
# Une ligne par outil : son nom, puis la condition. Un outil absent de cette
# table vaut pour toute machine — c'est le cas courant.
#
# Le besoin est venu du terrain : `vcgencmd` était proposé à chaque audit sur un
# poste x86, avec `sudo apt install raspi-utils` à la clé. Le conseil ne pouvait
# rien apporter — le micrologiciel qu'il interroge n'existe que sur un Raspberry
# Pi — et il revenait à chaque exécution. Un conseil inapplicable répété apprend
# surtout à ne plus lire les conseils.
#
# Le contrat vérifie que ces conditions sont celles de `tool-dependencies.ts`.
# shellcheck disable=SC2034 # lue par dependency_applies, via awk.
readonly DEPENDENCY_APPLIES='
vcgencmd raspberry-pi
nvme nvme-device
'

# Cette machine est-elle un Raspberry Pi ?
#
# Le modèle publié par l'arbre de périphériques est la source la plus directe et
# la moins ambiguë : le noyau l'écrit depuis le micrologiciel. `/proc/cpuinfo`
# prend le relais sur les noyaux qui n'exposent pas `/proc/device-tree`.
#
# Aucune déduction à partir de l'architecture : un serveur ARM64 n'est pas un
# Raspberry Pi, et un Pi 5 sous un noyau 64 bits ne se distingue pas d'un
# Ampere par son `uname -m`.
dependency_is_raspberry_pi() {
  local model=''
  if [ -r /proc/device-tree/model ]; then
    # Le fichier est terminé par un octet nul : `tr` l'écarte plutôt que de le
    # laisser polluer la comparaison.
    model=$(tr -d '\0' </proc/device-tree/model 2>/dev/null)
    case "$model" in *[Rr]aspberry*) return 0 ;; esac
  fi

  if [ -r /proc/cpuinfo ]; then
    grep -qi 'raspberry pi' /proc/cpuinfo 2>/dev/null && return 0
  fi
  return 1
}

# Cette machine porte-t-elle un disque NVMe ?
#
# Les nœuds `/dev/nvme*` sont créés par le noyau dès qu'un contrôleur répond :
# leur absence signifie qu'il n'y a rien que `nvme-cli` pourrait interroger.
dependency_has_nvme() {
  local node=''
  for node in /dev/nvme[0-9]*; do
    [ -e "$node" ] && return 0
  done
  return 1
}

# dependency_applies <outil>
#
# L'outil a-t-il un sens sur cette machine ? Vrai par défaut : seule une
# condition déclarée peut l'écarter, et une condition inconnue ne l'écarte pas
# — mieux vaut un conseil de trop qu'un outil utile passé sous silence par une
# faute de frappe dans la table.
dependency_applies() {
  local tool=${1-} condition=''
  condition=$(printf '%s' "$DEPENDENCY_APPLIES" | awk -v t="$tool" '$1 == t { print $2; exit }')
  [ -n "$condition" ] || return 0

  case "$condition" in
    raspberry-pi) dependency_is_raspberry_pi ;;
    nvme-device) dependency_has_nvme ;;
    *)
      log_debug "Condition d’applicabilité inconnue pour $tool : $condition"
      return 0
      ;;
  esac
}

# Le groupe de cet outil a-t-il déjà un membre présent sur la machine ?
dependency_group_satisfied() {
  local tool=${1-} line='' member=''
  line=$(printf '%s' "$DEPENDENCY_GROUPS" | awk -v t="$tool" '{
    for (i = 2; i <= NF; i++) if ($i == t) { print $0; exit }
  }')
  [ -n "$line" ] || return 1

  for member in $(printf '%s' "$line" | cut -d' ' -f2-); do
    [ "$member" = "$tool" ] && continue
    has_cmd "$member" && return 0
  done
  return 1
}

# Famille de gestionnaire de paquets de cette machine.
#
# Déduite de l'outil réellement présent, pas du nom de la distribution : un
# dérivé inconnu qui embarque `apt` s'installe comme Debian, et c'est la seule
# chose qui compte ici.
dependency_family() {
  if has_cmd apt || has_cmd apt-get; then
    printf 'debian'
  elif has_cmd dnf || has_cmd yum; then
    printf 'rhel'
  elif has_cmd pacman; then
    printf 'arch'
  elif has_cmd zypper; then
    printf 'suse'
  elif has_cmd apk; then
    printf 'alpine'
  fi
  return 0
}

# Commande d'installation de la famille, sans le nom du paquet.
dependency_install_prefix() {
  case "${1-}" in
    debian) printf 'apt install' ;;
    rhel) printf 'dnf install' ;;
    arch) printf 'pacman -S' ;;
    suse) printf 'zypper install' ;;
    alpine) printf 'apk add' ;;
  esac
  return 0
}

# Colonne de la table correspondant à une famille.
dependency_column() {
  case "${1-}" in
    debian) printf '2' ;;
    rhel) printf '3' ;;
    arch) printf '4' ;;
    suse) printf '5' ;;
    alpine) printf '6' ;;
    *) printf '0' ;;
  esac
}

# dependency_package <outil> <famille>
#
# Nom du paquet, ou rien si l'outil n'est pas installable sous cette famille.
dependency_package() {
  local tool=$1 family=$2 column=''
  column=$(dependency_column "$family")
  [ "$column" != '0' ] || return 0

  printf '%s' "$DEPENDENCY_TABLE" |
    awk -v t="$tool" -v c="$column" '$1 == t && $c != "-" { print $c; exit }'
}

# Ce que débloque un outil, en clair.
dependency_unlocks() {
  printf '%s' "$DEPENDENCY_TABLE" | awk -v t="${1-}" '
    $1 == t {
      out = ""
      for (i = 7; i <= NF; i++) out = out (out == "" ? "" : " ") $i
      print out
      exit
    }'
}

# Outils absents qui auraient enrichi ce rapport, une ligne par outil.
#
# Seuls les outils réellement absents sont listés, et seulement ceux qui
# figurent dans la table : conseiller d'installer `util-linux` n'aurait aucun
# sens, et c'est pourquoi il n'y figure pas.
dependency_missing() {
  local tool=''
  while read -r tool; do
    [ -n "$tool" ] || continue
    has_cmd "$tool" && continue
    # Un outil dont un équivalent répond déjà n'apporterait rien.
    dependency_group_satisfied "$tool" && continue
    # Ni un outil qui ne peut rien débloquer sur ce matériel.
    dependency_applies "$tool" || continue
    printf '%s\n' "$tool"
  done < <(printf '%s' "$DEPENDENCY_TABLE" | awk 'NF { print $1 }')
  return 0
}

# Affiche, en fin de scan, ce qui aurait pu être collecté en plus.
#
# Rien n'est installé ici : la commande est affichée, l'utilisateur décide. Un
# scanner en lecture seule qui installerait des paquets ne serait plus en
# lecture seule.
#
# Ce conseil reste le **seul** chemin quand personne ne peut répondre — `cron`,
# intégration continue, conteneur sans terminal. Depuis la `v0.112.0`, un audit
# lancé devant un terminal se voit en outre **proposer** la revue des outils
# manquants avant la collecte : c'est `provision_offer`, et le défaut y est non.
# Les deux ne se recouvrent pas — l'offre sert l'audit en cours, ce conseil
# sert le prochain.
dependency_report() {
  local missing=''
  missing=$(dependency_missing)
  [ -n "$missing" ] || return 0

  log_info 'Outils absents — leur installation enrichirait le prochain audit :'
  dependency_lines "$missing"
  return 0
}

# Une ligne par outil : ce qu'il apporte, et la commande qui l'installe.
#
# Extrait de `dependency_report` parce que **deux** surfaces en ont besoin, et
# qu'elles ne disent pas la même phrase d'introduction : le conseil de fin de
# scan parle du prochain audit, l'offre faite avant la collecte parle de
# celui-ci. Ce qui doit rester identique entre les deux est la liste elle-même —
# ses noms de paquets et ses commandes. Deux boucles auraient divergé au premier
# gestionnaire de paquets ajouté, et l'une des deux aurait fini par proposer une
# commande fausse.
#
# La commande est affichée **même quand elle ne sera pas exécutée** : c'est ce
# qui permet de refuser l'installation automatique et de la faire soi-même,
# ce que beaucoup préféreront sur une machine de production.
dependency_lines() {
  local missing=${1-}
  [ -n "$missing" ] || missing=$(dependency_missing)
  [ -n "$missing" ] || return 0

  local family='' prefix=''
  family=$(dependency_family)
  prefix=$(dependency_install_prefix "$family")

  local tool='' package='' unlocks=''
  while IFS= read -r tool; do
    [ -n "$tool" ] || continue
    unlocks=$(dependency_unlocks "$tool")
    package=$(dependency_package "$tool" "$family")

    if [ -n "$package" ] && [ -n "$prefix" ]; then
      log_step "$tool — $unlocks · sudo $prefix $package"
    else
      log_step "$tool — $unlocks"
    fi
  done <<<"$missing"

  return 0
}
