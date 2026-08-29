#!/usr/bin/env bash
# Docker et Proxmox VE.
#
# Les variables d'environnement des conteneurs ne sont jamais exportées : elles
# contiennent presque toujours des secrets. Seuls des indicateurs de
# configuration à risque sont collectés (SECURITY.md, §29).

# Chemins dont le montage dans un conteneur mérite d'être signalé.
SENSITIVE_MOUNT_PATTERNS=(
  '/var/run/docker.sock' '/run/docker.sock'
  '/etc' '/root' '/home' '/boot' '/dev' '/proc' '/sys' '/'
)

collect_virtualization() {
  local docker_json='' podman_json='' libvirt_json='' proxmox_json='' running_under=''

  [ -n "$CAP_VIRTUALIZED" ] && running_under=$(jf_str runningUnder "$CAP_VIRTUALIZED")

  if [ "$CAP_DOCKER" = 'true' ]; then
    docker_json=$(jf_raw docker "$(collect_docker)")
  fi

  podman_json=$(section podman "$(collect_podman)")
  libvirt_json=$(section libvirt "$(collect_libvirt)")

  if [ "$CAP_PROXMOX" = 'true' ]; then
    proxmox_json=$(jf_raw proxmox "$(collect_proxmox)")
  fi

  [ -z "$running_under$docker_json$podman_json$libvirt_json$proxmox_json" ] && return 0
  json_object "$running_under" "$docker_json" "$podman_json" "$libvirt_json" "$proxmox_json"
}

# Podman, dont l'interface est compatible avec celle de Docker.
#
# Seul le mode **rootless** est interrogé sans privilège : un podman système
# hébergeant des conteneurs root ne répondra pas à un utilisateur standard, et
# la section restera absente plutôt que faussement vide.
collect_podman() {
  has_cmd podman || return 0
  log_step 'Podman'

  local version='' containers='' name='' image='' state=''
  version=$(run_cmd podman version --format '{{.Client.Version}}' | head -n1)

  # `podman ps` échoue proprement quand le service n'est pas joignable :
  # l'absence de réponse ne doit pas produire une liste vide trompeuse.
  local ps_out=''
  ps_out=$(run_cmd podman ps -a --format '{{.Names}}\t{{.Image}}\t{{.State}}') || {
    record_issue 'virtualization.podman' 'warning' \
      'Podman présent mais son service n’a pas répondu : conteneurs non inventoriés.' 'podman' 'NOT_AVAILABLE'
    return 0
  }

  while IFS=$'\t' read -r name image state; do
    [ -z "$name" ] && continue
    containers=$(json_join "$containers" "$(json_object \
      "$(jf_str name "$name")" \
      "$(jf_maybe_str image "$image")" \
      "$(jf_maybe_str state "$state")" \
      "$(jf_raw privileged "$(j_unknown NOT_AVAILABLE 'inspection détaillée non effectuée')")" \
      "$(jf_raw networkMode "$(j_unknown NOT_AVAILABLE)")" \
      "$(jf_raw publishedPorts '[]')" \
      "$(jf_raw sensitiveMounts '[]')" \
      "$(jf_raw dockerSocketMounted "$(j_unknown UNSUPPORTED 'notion propre à Docker')")")")
  done <<<"$ps_out"

  json_object \
    "$(jf_maybe_str version "$version" NOT_AVAILABLE 'version non exposée')" \
    "$(jf_raw containers "[$containers]")" \
    "$(jf_raw networks '[]')"
}

# Invités libvirt / KVM / QEMU hébergés par cette machine.
#
# À ne pas confondre avec `runningUnder`, qui dit sur quel hyperviseur cette
# machine elle-même tourne.
collect_libvirt() {
  has_cmd virsh || return 0
  log_step 'libvirt'

  local version='' guests='' name='' state=''
  version=$(run_cmd virsh --version | head -n1)

  local list_out=''
  list_out=$(run_cmd virsh list --all --name) || {
    record_issue 'virtualization.libvirt' 'warning' \
      'virsh présent mais le démon n’a pas répondu : invités non inventoriés.' 'virsh' 'NOT_AVAILABLE'
    return 0
  }

  while IFS= read -r name; do
    [ -z "$name" ] && continue
    state=$(run_cmd virsh domstate "$name" | head -n1 | trim)
    guests=$(json_join "$guests" "$(json_object \
      "$(jf_str name "$name")" \
      "$(jf_maybe_str state "$state")" \
      "$(jf_maybe_num vcpus "$(run_cmd virsh dominfo "$name" | sed -nE 's/^CPU\(s\):[[:space:]]+([0-9]+)$/\1/p' | head -n1)")" \
      "$(jf_maybe_num memoryBytes "$(libvirt_memory_bytes "$name")")" \
      "$(jf_maybe_bool autostart "$(libvirt_autostart "$name")")")")
  done <<<"$list_out"

  json_object \
    "$(jf_maybe_str version "$version" NOT_AVAILABLE 'version non exposée')" \
    "$(jf_raw guests "[$guests]")"
}

# `virsh dominfo` rapporte la mémoire maximale en kibioctets.
libvirt_memory_bytes() {
  local kib=''
  kib=$(run_cmd virsh dominfo "${1-}" | sed -nE 's/^Max memory:[[:space:]]+([0-9]+) KiB$/\1/p' | head -n1)
  [[ $kib =~ ^[0-9]+$ ]] && printf '%s' $((kib * 1024))
  return 0
}

libvirt_autostart() {
  case "$(run_cmd virsh dominfo "${1-}" | sed -nE 's/^Autostart:[[:space:]]+(.*)$/\1/p' | head -n1)" in
    enable) printf 'true' ;;
    disable) printf 'false' ;;
  esac
  return 0
}

collect_docker() {
  log_step 'Docker'

  local version='' containers='' networks='' volumes=''
  version=$(run_cmd docker info --format '{{.ServerVersion}}')

  local id=''
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    containers=$(json_join "$containers" "$(collect_container "$id")")
  done < <(run_cmd docker ps -aq | head -n 200)

  local net_name='' net_driver=''
  while IFS=$'\t' read -r net_name net_driver; do
    [ -z "$net_name" ] && continue
    networks=$(json_join "$networks" "$(json_object \
      "$(jf_str name "$net_name")" \
      "$(jf_maybe_str driver "$net_driver")")")
  done < <(run_cmd docker network ls --format '{{.Name}}\t{{.Driver}}')

  volumes=$(run_cmd docker volume ls -q | grep -c . || printf '')

  json_object \
    "$(jf_maybe_str version "$version")" \
    "$(jf_raw containers "[$containers]")" \
    "$(jf_raw networks "[$networks]")" \
    "$(jf_maybe_num volumeCount "$volumes")"
}

collect_container() {
  local id=$1 name='' image='' state='' privileged='' network_mode=''

  # Un seul `docker inspect` par conteneur, avec un gabarit qui n'extrait que
  # des métadonnées : ni `.Config.Env`, ni `.Config.Cmd`, qui exposeraient des
  # secrets et des lignes de commande complètes.
  local info=''
  info=$(run_cmd docker inspect "$id" \
    --format '{{.Name}}|{{.Config.Image}}|{{.State.Status}}|{{.HostConfig.Privileged}}|{{.HostConfig.NetworkMode}}') || return 0

  IFS='|' read -r name image state privileged network_mode <<<"$info"
  name=${name#/}

  local mounts='' socket_mounted='false' source=''
  while IFS= read -r source; do
    [ -z "$source" ] && continue
    case "$source" in
      /var/run/docker.sock | /run/docker.sock) socket_mounted='true' ;;
    esac
    if is_sensitive_mount "$source"; then
      mounts=$(json_join "$mounts" "$(j_str "$source")")
    fi
  done < <(run_cmd docker inspect "$id" --format '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}')

  local ports=''
  local port_line=''
  while IFS= read -r port_line; do
    [ -z "$port_line" ] && continue
    ports=$(json_join "$ports" "$port_line")
  done < <(parse_container_ports "$id")

  json_object \
    "$(jf_str name "$name")" \
    "$(jf_maybe_str image "$image")" \
    "$(jf_maybe_str state "$state")" \
    "$(jf_maybe_bool privileged "$privileged")" \
    "$(jf_maybe_str networkMode "$network_mode")" \
    "$(jf_raw publishedPorts "[$ports]")" \
    "$(jf_raw sensitiveMounts "[$mounts]")" \
    "$(jf_maybe_bool dockerSocketMounted "$socket_mounted")"
}

is_sensitive_mount() {
  local source=$1 pattern=''
  for pattern in "${SENSITIVE_MOUNT_PATTERNS[@]}"; do
    [ "$source" = "$pattern" ] && return 0
  done
  return 1
}

parse_container_ports() {
  local id=$1 line='' host_addr='' host_port='' container_port='' protocol=''
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    # Format : 0.0.0.0:8080->80/tcp
    host_addr=${line%%:*}
    host_port=${line#*:}
    host_port=${host_port%%-*}
    container_port=${line##*>}
    protocol=${container_port#*/}
    container_port=${container_port%%/*}

    [[ $host_port =~ ^[0-9]+$ ]] || continue
    [[ $container_port =~ ^[0-9]+$ ]] || continue

    json_object \
      "$(jf_raw hostPort "$host_port")" \
      "$(jf_raw containerPort "$container_port")" \
      "$(jf_maybe_str protocol "$protocol")" \
      "$(jf_maybe_str hostAddress "$host_addr")"
  done < <(run_cmd docker port "$id" | sed -E 's/^([0-9]+)\/([a-z]+) -> (.*)$/\3->\1\/\2/')
}

collect_proxmox() {
  log_step 'Proxmox VE'

  local version='' node_name='' kernel='' uptime='' cores='' mem_total='' mem_used=''

  version=$(run_cmd pveversion | head -n1)
  node_name=$(proxmox_node_name)
  kernel=$(uname -r 2>/dev/null)
  uptime=$(awk '{printf "%d", $1}' /proc/uptime 2>/dev/null || printf '')
  cores=$(nproc 2>/dev/null || printf '')
  if [ -r /proc/meminfo ]; then
    mem_total=$(awk '/^MemTotal:/ { print $2 * 1024 }' /proc/meminfo)
    local mem_available=''
    mem_available=$(awk '/^MemAvailable:/ { print $2 * 1024 }' /proc/meminfo)
    [ -n "$mem_total" ] && [ -n "$mem_available" ] && mem_used=$((mem_total - mem_available))
  fi

  local node_json=''
  node_json=$(json_object \
    "$(jf_maybe_str name "$(anon hostname "$node_name")")" \
    "$(jf_maybe_str kernel "$kernel")" \
    "$(jf_maybe_num uptimeSeconds "$uptime")" \
    "$(jf_maybe_num cpuCores "$cores")" \
    "$(jf_maybe_num memoryTotalBytes "$mem_total")" \
    "$(jf_maybe_num memoryUsedBytes "$mem_used")")

  if ! depth_at_least virtualization standard; then
    # `NOT_AVAILABLE` disait « l'outil manque sur cette machine ». C'était faux :
    # `pvecm` est là, on ne l'a simplement pas interrogé parce que le niveau
    # Rapide ne le prévoit pas. Le rapport annonçait donc un hôte Proxmox
    # dépourvu des outils Proxmox, et envoyait le lecteur installer ce qu'il a
    # déjà. `NOT_COLLECTED` porte le bon motif **et** le niveau qui l'aurait
    # collecté. Constaté sur un vrai nœud, en audit Rapide.
    json_object \
      "$(jf_maybe_str version "$version")" \
      "$(jf_raw node "$node_json")" \
      "$(jf_raw cluster "$(json_object \
        "$(jf_str mode UNKNOWN)" \
        "$(jf_raw nodeCount "$(level_unknown standard)")" \
        "$(jf_raw quorate "$(level_unknown standard)")")")" \
      "$(jf_raw vms '[]')" \
      "$(jf_raw containers '[]')" \
      "$(jf_raw storages '[]')"
    return 0
  fi

  local tasks_json='' last_backup='' task_window=''
  # `pvesh get /nodes/<nom>/tasks` est une lecture pure de l'API locale. Le nom
  # du nœud vient de `hostname`, jamais d'une donnée du rapport : le scanner ne
  # construit aucun argument à partir d'une valeur non fiable (SECURITY.md).
  tasks_json=$(proxmox_failed_tasks "$node_name")
  last_backup=$(proxmox_last_backup "$node_name")
  # Sept jours, comme la liste demandée à l'API. Le compte de tâches en échec
  # n'a de sens que rapporté à cette durée.
  task_window=$((7 * 86400 * 1000))

  # `vms`, `containers` et `storages` passent par `section` : `qm`, `pct` et
  # `pvesm` peuvent manquer sur un nœud partiel, et leurs collecteurs ne rendent
  # alors rien du tout — une clé sans valeur invaliderait le rapport entier.
  json_object \
    "$(jf_maybe_str version "$version")" \
    "$(jf_raw node "$node_json")" \
    "$(jf_raw cluster "$(collect_proxmox_cluster)")" \
    "$(section vms "$(collect_proxmox_vms)")" \
    "$(section containers "$(collect_proxmox_lxc)")" \
    "$(section storages "$(collect_proxmox_storages)")" \
    "$(jf_raw failedServices "[$(proxmox_failed_services)]")" \
    "$(if [ -n "$tasks_json" ]; then jf_raw failedTasks "[$tasks_json]"; fi)" \
    "$(if [ -n "$last_backup" ]; then jf_raw lastBackup "$last_backup"; fi)" \
    "$(jf_maybe_num taskWindowMs "$task_window")" \
    "$(jf_raw ceph "$(proxmox_ceph)")" \
    "$(jf_raw replication "$(proxmox_replication)")" \
    "$(jf_raw highAvailability "$(proxmox_ha)")"
}

# Services propres à Proxmox actuellement en échec.
#
# Ils sont nommés à part des unités systemd générales : un `pvestatd` arrêté
# rend toute l'interface aveugle sans qu'aucun invité ne s'arrête, et le noyer
# parmi deux cents unités le rendrait invisible.
PROXMOX_SERVICES=(
  pve-cluster pvedaemon pveproxy pvestatd pvescheduler corosync
  pve-firewall pve-ha-lrm pve-ha-crm
)

# Services qui n'ont de sens qu'en grappe.
#
# Sur un nœud isolé, Proxmox les laisse `enabled` mais ne les démarre pas : c'est
# l'état **normal**, pas une panne. Le contrôle `enabled` seul ne suffisait donc
# pas — sur l'hôte qui a servi à trouver ce défaut, `corosync` était
# `enabled` et `inactive`, et le rapport annonçait un service PVE en échec sur
# une installation parfaitement saine.
PROXMOX_CLUSTER_SERVICES=(corosync pve-ha-lrm pve-ha-crm)

proxmox_failed_services() {
  has_cmd systemctl || return 0

  # Le mode de grappe décide de ce qui est attendu. Il est lu une fois, ici :
  # `pvecm status` échoue sur un nœud isolé, et cet échec **est** la réponse.
  local standalone='false'
  if has_cmd pvecm; then
    run_cmd pvecm status >/dev/null 2>&1 || standalone='true'
  else
    standalone='true'
  fi

  local failed='' service='' state='' cluster_only=''
  for service in "${PROXMOX_SERVICES[@]}"; do
    if [ "$standalone" = 'true' ]; then
      cluster_only='false'
      for candidate in "${PROXMOX_CLUSTER_SERVICES[@]}"; do
        [ "$candidate" = "$service" ] && cluster_only='true'
      done
      [ "$cluster_only" = 'true' ] && continue
    fi
    # `is-enabled` d'abord : un service non installé n'est pas un service en
    # échec. `pve-ha-lrm` n'existe que sur une grappe, et le compter comme
    # défaillant sur un nœud isolé inventerait une panne.
    run_cmd systemctl list-unit-files "$service.service" 2>/dev/null |
      grep -q "^$service.service" || continue
    state=$(run_cmd systemctl is-active "$service" 2>/dev/null || true)
    case "$state" in
      active | activating) ;;
      # `inactive` sur un service désactivé volontairement n'est pas un échec.
      inactive)
        [ "$(run_cmd systemctl is-enabled "$service" 2>/dev/null || true)" = 'enabled' ] &&
          failed=$(json_join "$failed" "$(j_str "$service")")
        ;;
      *) failed=$(json_join "$failed" "$(j_str "$service")") ;;
    esac
  done
  printf '%s' "$failed"
}

# Tâches terminées en erreur sur les sept derniers jours.
#
# Une sauvegarde qui échoue toutes les nuits depuis trois semaines est le genre
# de fait qu'aucun inventaire ne montre : l'hôte va bien, les invités tournent,
# et il n'y a pourtant plus de sauvegarde exploitable.
# Nom du nœud **tel que Proxmox le connaît**.
#
# `hostname` ne convient pas : il rend le nom pleinement qualifié — `pve.WORKGROUP`
# sur l'hôte qui a servi à trouver ce défaut — alors que le nœud PVE s'appelle
# `pve`. Tous les appels `pvesh get /nodes/<nom>/…` échouaient alors sur
# « proxy handler failed », et comme l'échec était absorbé, les tâches en échec
# et la dernière sauvegarde disparaissaient du rapport **sans un mot**.
#
# `/etc/pve/local` est un lien symbolique vers `nodes/<nom>` maintenu par PVE
# lui-même : c'est la seule source qui ne se trompe pas. Sur cet hôte,
# `/etc/pve/nodes/` contenait d'ailleurs trois entrées — deviner laquelle est la
# locale à partir de `hostname` était doublement fragile.
proxmox_node_name() {
  local resolved=''
  if [ -L /etc/pve/local ]; then
    resolved=$(readlink /etc/pve/local 2>/dev/null)
    resolved=${resolved##*/}
    [ -n "$resolved" ] && {
      printf '%s' "$resolved"
      return 0
    }
  fi
  # Repli : le nom court. Il est juste dans la très grande majorité des cas, et
  # `hostname` tout court ne l'est que si la machine n'a pas de domaine.
  hostname -s 2>/dev/null || hostname 2>/dev/null || true
}

proxmox_failed_tasks() {
  local node=$1
  has_cmd pvesh || return 0
  [ -n "$node" ] || return 0

  local raw=''
  if ! raw=$(run_cmd pvesh get "/nodes/$node/tasks" --errors 1 --limit 100 \
    --output-format json 2>/dev/null); then
    # L'absorber ferait disparaître les tâches en échec du rapport sans que rien
    # ne le signale — et « aucune tâche en échec » se lirait comme un hôte sain.
    record_issue 'virtualization.proxmox.failedTasks' 'warning' \
      "L’API PVE n’a pas répondu pour le nœud « $node » : tâches en échec non collectées." \
      'pvesh' 'NOT_AVAILABLE'
    return 0
  fi
  [ -n "$raw" ] || return 0

  proxmox_tasks_from_json "$raw" 20
}

# Dernière sauvegarde observée, réussie **ou non**.
#
# Sa réussite est un fait, sa date en est un autre. Une sauvegarde réussie il y
# a six semaines n'est pas une sauvegarde : ne rapporter que les échecs
# masquerait exactement ce cas.
proxmox_last_backup() {
  local node=$1
  has_cmd pvesh || return 0
  [ -n "$node" ] || return 0

  local raw=''
  if ! raw=$(run_cmd pvesh get "/nodes/$node/tasks" --typefilter vzdump --limit 1 \
    --output-format json 2>/dev/null); then
    record_issue 'virtualization.proxmox.lastBackup' 'warning' \
      "L’API PVE n’a pas répondu pour le nœud « $node » : dernière sauvegarde non collectée." \
      'pvesh' 'NOT_AVAILABLE'
    return 0
  fi
  [ -n "$raw" ] || return 0

  local one=''
  one=$(proxmox_tasks_from_json "$raw" 1)
  printf '%s' "$one"
}

# Convertit la liste JSON de l'API Proxmox en objets du schéma.
#
# `pvesh --output-format json` rend une seule ligne : l'extraction passe par awk
# plutôt que par un analyseur JSON, que le scanner n'a pas le droit d'exiger —
# il doit tourner sur une machine sans Node.js ni `jq`.
proxmox_tasks_from_json() {
  local raw=$1 limit=$2
  local out='' count=0
  local type target started status duration

  while IFS=$'\x1f' read -r type target started status duration; do
    [ -n "$type" ] || continue
    [ "$count" -ge "$limit" ] && break
    count=$((count + 1))

    local started_iso=''
    [[ $started =~ ^[0-9]+$ ]] &&
      started_iso=$(date -u -d "@$started" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)

    out=$(json_join "$out" "$(json_object \
      "$(jf_str type "$type")" \
      "$(jf_maybe_str target "$target" NOT_APPLICABLE 'tâche sans invité cible')" \
      "$(jf_maybe_str startedAt "$started_iso" UNKNOWN 'horodatage illisible')" \
      "$(jf_maybe_str status "$status" UNKNOWN 'statut non publié par l’API')" \
      "$(jf_maybe_num durationMs "$duration" NOT_AVAILABLE 'tâche non terminée ou durée non publiée')")")
  done < <(
    printf '%s' "$raw" | awk -v OFS=$'\x1f' '
      {
        # Découpe la liste en objets, sans analyseur JSON complet : chaque tâche
        # est un objet plat, et ses clés sont connues.
        n = split($0, parts, /\{/)
        for (i = 2; i <= n; i++) {
          rec = parts[i]
          sub(/\}.*$/, "", rec)
          type = value(rec, "type")
          target = value(rec, "id")
          start = value(rec, "starttime")
          end = value(rec, "endtime")
          status = value(rec, "status")
          if (type == "") continue
          ms = ""
          if (start ~ /^[0-9]+$/ && end ~ /^[0-9]+$/ && end >= start) ms = (end - start) * 1000
          print type, target, start, substr(status, 1, 400), ms
        }
      }
      function value(rec, key,   m, v) {
        m = rec
        if (m !~ "\"" key "\"") return ""
        sub(".*\"" key "\"[: ]*", "", m)
        if (substr(m, 1, 1) == "\"") {
          sub(/^"/, "", m)
          sub(/".*$/, "", m)
        } else {
          sub(/[,}].*$/, "", m)
          gsub(/[ \t]/, "", m)
        }
        return m
      }
    '
  )
  printf '%s' "$out"
}

# Sous-système facultatif : Ceph.
#
# `present: false` ne vaut pas `dégradé`. Une grappe sans Ceph n'a pas un Ceph
# en panne — elle n'a pas de Ceph, et les autres champs portent alors
# `NOT_APPLICABLE`.
proxmox_ceph() {
  if ! has_cmd ceph || [ ! -f /etc/pve/ceph.conf ]; then
    proxmox_absent_subsystem 'aucune configuration Ceph sur ce nœud'
    return 0
  fi

  local health='' detail=''
  health=$(run_cmd ceph health 2>/dev/null | awk '{ print $1 }' | head -n1)
  detail=$(run_cmd ceph health 2>/dev/null | head -n1 | cut -c1-400)

  json_object \
    "$(jf_raw present true)" \
    "$(jf_maybe_str health "$health" PERMISSION_DENIED 'ceph health sans réponse : privilèges ou grappe injoignable')" \
    "$(jf_maybe_str detail "$detail" UNKNOWN)" \
    "$(jf_maybe_num degraded '' NOT_AVAILABLE 'le compte d’objets dégradés exige ceph status, non interrogé en lecture rapide')"
}

proxmox_replication() {
  # La réplication n'existe qu'avec un stockage ZFS local et une grappe.
  if [ ! -f /etc/pve/replication.cfg ]; then
    proxmox_absent_subsystem 'aucune réplication configurée sur ce nœud'
    return 0
  fi

  local failures=''
  if has_cmd pvesr; then
    failures=$(run_cmd pvesr status 2>/dev/null |
      awk 'NR > 1 && $0 ~ /[Ee]rror|[Ff]ail/ { count++ } END { print count + 0 }')
  fi

  json_object \
    "$(jf_raw present true)" \
    "$(jf_maybe_str health "$(if [ "${failures:-0}" -gt 0 ] 2>/dev/null; then printf 'ERROR'; elif [ -n "$failures" ]; then printf 'OK'; fi)" NOT_AVAILABLE 'pvesr absent')" \
    "$(jf_maybe_str detail '' NOT_AVAILABLE 'le détail par tâche exige pvesr status, tronqué ici')" \
    "$(jf_maybe_num degraded "$failures" NOT_AVAILABLE 'pvesr absent')"
}

proxmox_ha() {
  # `ha-manager` existe sur tout nœud PVE ; c'est la *configuration* HA qui dit
  # si la haute disponibilité est réellement en service.
  if [ ! -f /etc/pve/ha/resources.cfg ]; then
    proxmox_absent_subsystem 'aucune ressource en haute disponibilité déclarée'
    return 0
  fi

  local status=''
  has_cmd ha-manager && status=$(run_cmd ha-manager status 2>/dev/null | head -n1 | cut -c1-400)

  json_object \
    "$(jf_raw present true)" \
    "$(jf_maybe_str health "$(printf '%s' "$status" | awk '{ print $NF }')" NOT_AVAILABLE 'ha-manager absent ou muet')" \
    "$(jf_maybe_str detail "$status" NOT_AVAILABLE 'ha-manager absent ou muet')" \
    "$(jf_maybe_num degraded '' NOT_AVAILABLE 'le compte de ressources en défaut exige ha-manager status détaillé')"
}

# Sous-système absent : tout est `NOT_APPLICABLE`, jamais zéro ni `dégradé`.
proxmox_absent_subsystem() {
  local reason=$1
  json_object \
    "$(jf_raw present false)" \
    "$(jf_raw health "$(j_unknown NOT_APPLICABLE "$reason")")" \
    "$(jf_raw detail "$(j_unknown NOT_APPLICABLE "$reason")")" \
    "$(jf_raw degraded "$(j_unknown NOT_APPLICABLE "$reason")")"
}

collect_proxmox_cluster() {
  local mode='UNKNOWN' name='' nodes='' quorate=''
  # Motif d'absence du quorum, distinct selon la raison. `UNKNOWN` par défaut :
  # sans `pvecm`, on ne sait effectivement pas.
  local quorate_reason='UNKNOWN' quorate_detail=''

  if has_cmd pvecm; then
    local status=''
    status=$(LC_ALL=C run_cmd pvecm status) || status=''
    if [ -n "$status" ]; then
      mode='CLUSTER'
      name=$(printf '%s' "$status" | sed -nE 's/^Name:[[:space:]]+(.*)$/\1/p' | head -n1)
      nodes=$(printf '%s' "$status" | sed -nE 's/^Nodes:[[:space:]]+([0-9]+)$/\1/p' | head -n1)
      case "$(printf '%s' "$status" | sed -nE 's/^Quorate:[[:space:]]+(.*)$/\1/p' | head -n1)" in
        Yes) quorate='true' ;;
        No) quorate='false' ;;
      esac
    else
      # `pvecm status` échoue sur un nœud isolé : c'est le cas standalone.
      #
      # Le quorum y valait `UNKNOWN`, ce qui se lit « la valeur aurait dû être
      # lisible et ne l'a pas été » — donc, sur un tableau de bord, comme un
      # cluster dont on a perdu la trace. Un nœud hors cluster n'a pas un quorum
      # illisible : il n'a pas de quorum, exactement comme il n'a pas de Ceph.
      # Le défaut ne se voyait pas en test : il faut un vrai nœud autonome pour
      # que `pvecm status` échoue de cette façon.
      mode='STANDALONE'
      nodes='1'
      quorate_reason='NOT_APPLICABLE'
      quorate_detail='nœud hors cluster : il n’y a pas de quorum à mesurer'
    fi
  fi

  json_object \
    "$(jf_str mode "$mode")" \
    "$(if [ -n "$name" ]; then jf_str name "$name"; fi)" \
    "$(jf_maybe_num nodeCount "$nodes" NOT_AVAILABLE)" \
    "$(jf_maybe_bool quorate "$quorate" "$quorate_reason" "$quorate_detail")"
}

collect_proxmox_vms() {
  has_cmd qm || return 0

  local vms='' vmid='' name='' status='' mem='' cores=''
  while read -r vmid name status mem _; do
    [[ $vmid =~ ^[0-9]+$ ]] || continue

    # La configuration détaillée n'est lisible que par root.
    local config='' bios='' machine='' autostart='' disks='' nets='' tags=''
    if [ "$CAP_PRIVILEGED" = 'true' ] && depth_at_least virtualization standard; then
      config=$(run_cmd qm config "$vmid") || config=''
      cores=$(printf '%s' "$config" | sed -nE 's/^cores:[[:space:]]*([0-9]+)$/\1/p' | head -n1)
      bios=$(printf '%s' "$config" | sed -nE 's/^bios:[[:space:]]*(.*)$/\1/p' | head -n1)
      machine=$(printf '%s' "$config" | sed -nE 's/^machine:[[:space:]]*(.*)$/\1/p' | head -n1)
      case "$(printf '%s' "$config" | sed -nE 's/^onboot:[[:space:]]*([01])$/\1/p' | head -n1)" in
        1) autostart='true' ;;
        0) autostart='false' ;;
      esac
      tags=$(proxmox_tags "$config")
      disks=$(proxmox_vm_disks "$config")
      nets=$(proxmox_vm_networks "$config")
    fi

    # `qm list` rapporte la mémoire en mébioctets.
    local mem_bytes=''
    [[ $mem =~ ^[0-9]+$ ]] && mem_bytes=$((mem * 1024 * 1024))

    vms=$(json_join "$vms" "$(json_object \
      "$(jf_raw vmid "$vmid")" \
      "$(jf_maybe_str name "$name")" \
      "$(jf_maybe_str status "$status")" \
      "$(jf_maybe_num cpuCores "$cores" PERMISSION_DENIED 'qm config réservé à root')" \
      "$(jf_maybe_num memoryBytes "$mem_bytes")" \
      "$(jf_maybe_bool autostart "$autostart" PERMISSION_DENIED 'qm config réservé à root')" \
      "$(jf_raw tags "[$tags]")" \
      "$(jf_raw networkInterfaces "[$nets]")" \
      "$(jf_raw disks "[$disks]")" \
      "$(jf_maybe_str machineType "$machine" PERMISSION_DENIED)" \
      "$(jf_maybe_str bios "$bios" PERMISSION_DENIED)")")
  done < <(run_cmd qm list | awk 'NR>1')

  printf '[%s]' "$vms"
}

proxmox_tags() {
  local config=$1 out='' tag=''
  local raw=''
  raw=$(printf '%s' "$config" | sed -nE 's/^tags:[[:space:]]*(.*)$/\1/p' | head -n1)
  [ -z "$raw" ] && return 0
  while IFS= read -r tag; do
    [ -z "$tag" ] && continue
    out=$(json_join "$out" "$(j_str "$tag")")
  done < <(printf '%s' "$raw" | tr ';,' '\n\n')
  printf '%s' "$out"
}

proxmox_vm_disks() {
  local config=$1 out='' line='' key='' value='' storage='' size=''
  while IFS= read -r line; do
    key=${line%%:*}
    value=${line#*: }
    storage=${value%%:*}
    size=$(printf '%s' "$value" | sed -nE 's/.*size=([0-9]+[KMGT]?).*/\1/p')

    out=$(json_join "$out" "$(json_object \
      "$(jf_str name "$key")" \
      "$(jf_maybe_str storage "$storage")" \
      "$(jf_maybe_num sizeBytes "$(to_bytes "$size")")")")
  done < <(printf '%s' "$config" | grep -E '^(scsi|virtio|sata|ide)[0-9]+:' || true)
  printf '%s' "$out"
}

proxmox_vm_networks() {
  local config=$1 out='' line='' key='' value='' bridge='' model=''
  while IFS= read -r line; do
    key=${line%%:*}
    value=${line#*: }
    bridge=$(printf '%s' "$value" | sed -nE 's/.*bridge=([^,]+).*/\1/p')
    model=$(printf '%s' "$value" | sed -nE 's/^([a-z0-9]+)=.*/\1/p')

    out=$(json_join "$out" "$(json_object \
      "$(jf_str name "$key")" \
      "$(jf_maybe_str bridge "$bridge")" \
      "$(jf_maybe_str model "$model")")")
  done < <(printf '%s' "$config" | grep -E '^net[0-9]+:' || true)
  printf '%s' "$out"
}

collect_proxmox_lxc() {
  has_cmd pct || return 0

  local containers='' ctid='' status='' name=''
  # `pct list` rend quatre colonnes — VMID, Status, **Lock**, Name — et la
  # troisième est vide sur tout conteneur non verrouillé, c'est-à-dire sur la
  # quasi-totalité d'entre eux. `read` compresse les espaces : le nom tombait
  # alors dans la variable jetable prévue pour le verrou, et `name` restait
  # vide. Tous les conteneurs d'un hôte Proxmox sain se rapportaient donc sans
  # nom, marqués « lecture en échec » — constaté sur un hôte réel le
  # 2026-08-16, où les huit conteneurs étaient anonymes.
  #
  # Le nom est la dernière colonne, verrou ou pas : `$NF` le retrouve dans les
  # deux cas. La garde sur `NF` évite de prendre le statut pour un nom si la
  # sortie change encore de forme.
  while IFS='|' read -r ctid status name; do
    [[ $ctid =~ ^[0-9]+$ ]] || continue

    local config='' cores='' mem='' rootfs='' storage='' unprivileged='' autostart='' tags='' nets=''
    if [ "$CAP_PRIVILEGED" = 'true' ] && depth_at_least virtualization standard; then
      config=$(run_cmd pct config "$ctid") || config=''
      cores=$(printf '%s' "$config" | sed -nE 's/^cores:[[:space:]]*([0-9]+)$/\1/p' | head -n1)
      mem=$(printf '%s' "$config" | sed -nE 's/^memory:[[:space:]]*([0-9]+)$/\1/p' | head -n1)
      [ -n "$mem" ] && mem=$((mem * 1024 * 1024))

      local rootfs_line=''
      rootfs_line=$(printf '%s' "$config" | sed -nE 's/^rootfs:[[:space:]]*(.*)$/\1/p' | head -n1)
      storage=${rootfs_line%%:*}
      rootfs=$(to_bytes "$(printf '%s' "$rootfs_line" | sed -nE 's/.*size=([0-9]+[KMGT]?).*/\1/p')")

      case "$(printf '%s' "$config" | sed -nE 's/^unprivileged:[[:space:]]*([01])$/\1/p' | head -n1)" in
        1) unprivileged='true' ;;
        0) unprivileged='false' ;;
      esac
      case "$(printf '%s' "$config" | sed -nE 's/^onboot:[[:space:]]*([01])$/\1/p' | head -n1)" in
        1) autostart='true' ;;
        0) autostart='false' ;;
      esac
      tags=$(proxmox_tags "$config")
      nets=$(proxmox_lxc_networks "$config")
    fi

    containers=$(json_join "$containers" "$(json_object \
      "$(jf_raw ctid "$ctid")" \
      "$(jf_maybe_str name "$name")" \
      "$(jf_maybe_str status "$status")" \
      "$(jf_maybe_num cpuCores "$cores" PERMISSION_DENIED 'pct config réservé à root')" \
      "$(jf_maybe_num memoryBytes "$mem" PERMISSION_DENIED 'pct config réservé à root')" \
      "$(jf_maybe_bool autostart "$autostart" PERMISSION_DENIED)" \
      "$(jf_raw tags "[$tags]")" \
      "$(jf_raw networkInterfaces "[$nets]")" \
      "$(jf_maybe_num rootfsBytes "$rootfs" PERMISSION_DENIED)" \
      "$(jf_maybe_str storage "$storage" PERMISSION_DENIED)" \
      "$(jf_maybe_bool unprivileged "$unprivileged" PERMISSION_DENIED)")")
  done < <(run_cmd pct list |
    awk 'NR > 1 && $1 ~ /^[0-9]+$/ { print $1 "|" $2 "|" (NF >= 3 ? $NF : "") }')

  printf '[%s]' "$containers"
}

proxmox_lxc_networks() {
  local config=$1 out='' line='' key='' value='' bridge=''
  while IFS= read -r line; do
    key=${line%%:*}
    value=${line#*: }
    bridge=$(printf '%s' "$value" | sed -nE 's/.*bridge=([^,]+).*/\1/p')
    out=$(json_join "$out" "$(json_object \
      "$(jf_str name "$key")" \
      "$(jf_maybe_str bridge "$bridge")" \
      "$(jf_str model veth)")")
  done < <(printf '%s' "$config" | grep -E '^net[0-9]+:' || true)
  printf '%s' "$out"
}

collect_proxmox_storages() {
  has_cmd pvesm || return 0

  local storages='' name='' type='' status='' total='' used='' available=''
  while read -r name type status total used available _; do
    [ -z "$name" ] || [ "$name" = 'Name' ] && continue

    if ! depth_at_least virtualization standard; then
      storages=$(json_join "$storages" "$(json_object \
        "$(jf_str name "$name")" \
        "$(jf_str type "$type")" \
        "$(jf_maybe_str status "$status")" \
        "$(jf_raw shared "$(j_unknown NOT_AVAILABLE)")" \
        "$(jf_raw content '[]')")")
      continue
    fi

    # `pvesm status` rapporte les tailles en kibioctets.
    local total_b='' used_b='' avail_b='' pct=''
    [[ $total =~ ^[0-9]+$ ]] && total_b=$((total * 1024))
    [[ $used =~ ^[0-9]+$ ]] && used_b=$((used * 1024))
    [[ $available =~ ^[0-9]+$ ]] && avail_b=$((available * 1024))
    if [ -n "$total_b" ] && [ -n "$used_b" ] && [ "$total_b" -gt 0 ]; then
      pct=$(awk -v u="$used_b" -v t="$total_b" 'BEGIN { printf "%.1f", (u / t) * 100 }')
    fi

    storages=$(json_join "$storages" "$(json_object \
      "$(jf_str name "$name")" \
      "$(jf_str type "$type")" \
      "$(jf_maybe_str status "$status")" \
      "$(jf_maybe_num totalBytes "$total_b")" \
      "$(jf_maybe_num usedBytes "$used_b")" \
      "$(jf_maybe_num availableBytes "$avail_b")" \
      "$(jf_maybe_num usagePercent "$pct")" \
      "$(jf_raw shared "$(j_unknown NOT_AVAILABLE)")" \
      "$(jf_raw content '[]')")")
  done < <(run_cmd pvesm status | awk 'NR>1')

  printf '[%s]' "$storages"
}
