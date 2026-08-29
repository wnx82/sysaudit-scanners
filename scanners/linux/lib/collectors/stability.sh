#!/usr/bin/env bash
# Historique, stabilité, démarrage et arrêt.
#
# L'inventaire dit qu'un disque existe ; seul le journal dit qu'il jette une
# erreur toutes les nuits depuis trois semaines. Ce collecteur lit ce que le
# système a déjà écrit — il n'active aucune journalisation, ne change aucun
# niveau de trace, n'écrit nulle part.
#
# Trois règles gouvernent tout ce fichier :
#
#   1. **Un compteur ne part jamais sans sa fenêtre.** « Trois pannes » est
#      rassurant sur un an et alarmant sur une journée.
#   2. **La fenêtre demandée n'est pas la fenêtre obtenue.** Un `journald` en
#      mémoire repart de zéro à chaque démarrage : sans le dire, « aucun
#      incident » se lirait comme un trimestre sain.
#   3. **La sévérité vient de la source, jamais du scanner.** Décider qu'un
#      avertissement est en réalité critique est une analyse, et l'analyse se
#      recalcule sur des rapports déjà collectés (ADR 0003).

# Fenêtre d'historique demandée, en jours. Trente couvre un cycle de mise à
# jour mensuel sans imposer à `journalctl` de parcourir une année d'archives.
STABILITY_WINDOW_DAYS="${SYSAUDIT_HISTORY_DAYS:-30}"

# Séparateur interne des enregistrements produits par awk. `\x1f` (unit
# separator) n'apparaît pas dans un journal texte, là où `|` et `;` y sont
# courants — un séparateur qu'on peut rencontrer dans la donnée découperait les
# messages au hasard.
readonly STABILITY_FS=$'\x1f'

# --- Disponibilité des sources ----------------------------------------------

# `journalctl` peut être installé et refuser de répondre : sans appartenance au
# groupe `systemd-journal` ni privilèges, il rend un journal vide plutôt qu'une
# erreur. Un test de lecture réel est donc le seul verdict fiable.
stability_journal_readable() {
  has_cmd journalctl || return 1
  run_cmd journalctl --no-pager -n 1 -q >/dev/null 2>&1
}

# Le journal survit-il au redémarrage ? `Storage=persistent` crée
# `/var/log/journal` ; en mode volatile, tout vit dans `/run/log/journal`.
stability_journal_persistent() {
  [ -d /var/log/journal ] && return 0
  return 1
}

# Instant du plus ancien enregistrement conservé, en secondes epoch.
#
# C'est ce qui distingue « rien ne s'est passé depuis trente jours » de « le
# journal ne remonte qu'à avant-hier ». Sans cette lecture, les deux se
# ressemblent exactement.
#
# `journalctl -n 1` rend la ligne la **plus récente**, pas la plus ancienne : il
# n'existe pas de `--head`. Une première version l'utilisait et annonçait des
# fenêtres de deux secondes sur des journaux vieux de plusieurs semaines. La
# lecture part donc du début de la fenêtre et `head -n 1` interrompt
# `journalctl` dès la première ligne — le positionnement par date est indexé,
# donc immédiat, et rien de plus n'est lu.
stability_journal_oldest_epoch() {
  local line='' runner=()
  has_cmd timeout && runner=(timeout -k 2 "${SYSAUDIT_CMD_TIMEOUT:-15}")
  line=$("${runner[@]}" journalctl --no-pager --quiet -o short-unix \
    --since "-${STABILITY_WINDOW_DAYS} days" 2>/dev/null | head -n 1) || true
  printf '%s' "${line%% *}" | grep -oE '^[0-9]+' || true
}

# --- Normalisation des incidents --------------------------------------------

# Programme awk commun à toutes les sources d'incidents.
#
# Il reçoit des lignes `epoch<TAB>provider<TAB>message`, les classe, les
# regroupe par empreinte et rend un enregistrement par groupe.
#
# Le regroupement n'est pas un confort d'affichage : un disque qui meurt écrit
# la même ligne des milliers de fois. Sans lui, la borne du tableau couperait au
# millième doublon et cacherait tous les autres incidents — c'est-à-dire
# exactement ceux qu'on cherche.
stability_group_events() {
  local severity=$1
  awk -v FS='\t' -v OFS="$STABILITY_FS" -v sev="$severity" '
    # Empreinte : le message débarrassé de ce qui change à chaque occurrence —
    # horodatages, PID, adresses, secteurs, identifiants hexadécimaux. Deux
    # occurrences du même incident doivent tomber sur la même empreinte, sinon
    # le regroupement ne regroupe rien.
    function fingerprint(msg,   f) {
      f = tolower(msg)
      gsub(/0x[0-9a-f]+/, "#", f)
      # Adresse MAC, écrite sans intervalle de répétition : `mawk` — l’awk par
      # défaut de Debian et d’Ubuntu — **panique** sur `{2}` et `{5}`
      # (« REcompile() - panic: values still on machine stack »), et le
      # regroupement d’incidents ne rendait alors plus rien du tout. Le motif
      # développé donne le même résultat sur mawk comme sur gawk.
      gsub(/[0-9a-f][0-9a-f](:[0-9a-f][0-9a-f])(:[0-9a-f][0-9a-f])(:[0-9a-f][0-9a-f])(:[0-9a-f][0-9a-f])(:[0-9a-f][0-9a-f])/, "#", f)
      gsub(/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/, "#", f)
      gsub(/\[[0-9]+\]/, "[#]", f)
      gsub(/[0-9]+/, "#", f)
      gsub(/[ \t]+/, " ", f)
      sub(/^ /, "", f); sub(/ $/, "", f)
      return substr(f, 1, 120)
    }

    # Catégorie : ce qui a échoué, jamais l’outil qui l’a dit. Le premier motif
    # qui correspond gagne ; l’ordre va donc du plus spécifique au plus général.
    function categorize(msg, prov,   m) {
      m = tolower(msg " " prov)
      if (m ~ /kernel panic|oops:|general protection fault|bug: unable to handle|watchdog: bug/) return "KERNEL_CRASH"
      if (m ~ /out of memory|oom-killer|oom_reaper|cannot allocate memory/) return "MEMORY"
      if (m ~ /machine check|mce:|hardware error|edac|pcie bus error|aer:|corrected error/) return "HARDWARE"
      if (m ~ /ext4-fs error|xfs.*internal error|btrfs.*(error|checksum)|remount.*read-only|filesystem.*read-only/) return "FILESYSTEM"
      if (m ~ /i\/o error|blk_update_request|failed command|medium error|serror|ata[0-9]|nvme.*(reset|error|timeout)|scsi.*(error|abort)|buffer i\/o/) return "STORAGE"
      if (m ~ /link is down|carrier lost|netdev watchdog|transmit queue.*timed out|link down/) return "NETWORK"
      if (m ~ /module verification failed|unknown symbol|failed to load firmware|firmware.*failed|taint|driver.*failed/) return "DRIVER"
      if (m ~ /segfault|dumped core|traps:|core dump/) return "APPLICATION_CRASH"
      if (m ~ /avc: *denied|apparmor=.?"?denied|authentication failure|failed password|refused connect/) return "SECURITY"
      if (m ~ /under-voltage|undervoltage|power supply|battery critical|unclean shutdown|forced shutdown/) return "POWER"
      if (m ~ /thermal|throttl|critical temperature|above threshold|overheat/) return "THERMAL"
      if (m ~ /dpkg: error|apt.*error|dnf.*error|pacman.*error|upgrade failed|update failed/) return "UPDATE"
      if (m ~ /failed with result|entered failed state|start request repeated|failed to start/) return "SERVICE"
      if (m ~ /failed to mount|dependency failed|emergency mode/) return "BOOT"
      return "OTHER"
    }

    NF < 3 { next }
    {
      epoch = $1
      provider = $2
      message = $3
      if (message == "") next

      key = fingerprint(message)
      cat = categorize(message, provider)
      id = cat STAB_SEP key

      if (!(id in count)) {
        count[id] = 0
        first[id] = epoch
        prov[id] = provider
        summary[id] = substr(message, 1, 400)
        category[id] = cat
        print_order[++n] = id
      }
      count[id]++
      last[id] = epoch
      if (epoch < first[id]) first[id] = epoch

      # Trois extraits au plus, et **distincts**. Le regroupement rassemble des
      # lignes qui ne diffèrent que par un PID ou un secteur : garder trois
      # copies identiques occuperait la place de la preuve utile sans rien
      # ajouter. Une alerte sans la ligne qui la fonde n’est pas vérifiable ;
      # trois fois la même ne l’est pas davantage.
      line = substr(message, 1, 400)
      if (evn[id] < 3 && line != ev1[id] && line != ev2[id] && line != ev3[id]) {
        evn[id]++
        if (evn[id] == 1) ev1[id] = line
        else if (evn[id] == 2) ev2[id] = line
        else ev3[id] = line
      }
    }

    END {
      for (i = 1; i <= n; i++) {
        id = print_order[i]
        k = id; sub(/^[^\x1e]*\x1e/, "", k)
        print category[id], sev, prov[id], first[id], last[id], count[id], \
              summary[id], k, ev1[id], ev2[id], ev3[id]
      }
    }
  ' STAB_SEP=$'\x1e'
}

# Incidents lus dans journald, pour une plage de priorités donnée.
#
# `journalctl` publie la priorité : la sévérité est donc **lue**, non déduite.
# Deux appels valent mieux qu'un seul suivi d'un classement maison — celui-ci
# serait une analyse déguisée en collecte.
stability_journal_events() {
  local priority=$1
  run_cmd journalctl --no-pager --quiet --since "-${STABILITY_WINDOW_DAYS} days" \
    -p "$priority" -o short-unix 2>/dev/null |
    awk '
      # Un message de journal peut tenir sur plusieurs lignes, et c’est alors
      # **un seul évènement**.
      #
      # `short-unix` rend la première ligne préfixée « epoch hôte source: » et
      # les suivantes simplement indentées. Traiter chaque ligne isolément —
      # ce que faisait ce collecteur — fabriquait un évènement par ligne de
      # continuation : une vidange mémoire `systemd-coredump`, qui liste ses
      # modules sur trente lignes, produisait trente-et-un incidents dont les
      # sources s’appelaient « from » et « of ».
      #
      # Pire, la ligne vide qui sépare le message de sa liste de modules
      # donnait un incident au résumé **entièrement blanc** et à l’empreinte
      # vide, tous deux refusés par le schéma (`min(1)`). Le dépôt entier
      # partait alors en HTTP 400 : deux minutes d’audit perdues pour une ligne
      # de journal.
      #
      # Les lignes de continuation sont donc rattachées au message courant.
      # Rien n’est inventé et rien n’est jeté : c’est la forme que journald
      # donne au champ `MESSAGE`, restituée telle qu’elle.
      function flush(   text) {
        if (epoch == "") return
        text = message
        gsub(/[ \t]+/, " ", text)
        sub(/^ +/, "", text); sub(/ +$/, "", text)
        # Un message réduit à des espaces n’est pas un incident : il ne
        # décrit rien, et le publier violerait le schéma.
        if (text == "") { epoch = ""; return }
        printf "%s\t%s\t%s\n", epoch, provider, text
        epoch = ""
      }

      # Ligne d’en-tête : elle seule commence par un horodatage Unix.
      /^[0-9]+\.[0-9]+ / {
        flush()
        epoch = $1
        sub(/\..*$/, "", epoch)
        # La source porte parfois un PID entre crochets, qui ne fait pas
        # partie de son nom.
        provider = $3
        sub(/\[[0-9]+\]:?$/, "", provider)
        sub(/:$/, "", provider)
        message = $0
        sub(/^[^ ]+ [^ ]+ [^ ]+ /, "", message)
        next
      }

      # Ligne de continuation. Sans message courant — la fenêtre commence au
      # milieu d’un message — il n’y a rien à quoi la rattacher : on ne sait
      # ni la dater ni l’attribuer, donc on ne la publie pas.
      { if (epoch != "") message = message " " $0 }

      END { flush() }
    '
}

# Repli sur l'anneau du noyau quand journald est absent ou muet.
#
# `dmesg` ne couvre que le démarrage courant et ne connaît que le noyau : la
# fenêtre réellement couverte est donc l'uptime, et c'est ce que le rapport
# annoncera. Sur beaucoup de distributions, `kernel.dmesg_restrict` le réserve
# à root — l'échec est alors un refus d'accès, pas une absence d'incident.
stability_dmesg_events() {
  local levels=$1
  # `--time-format=iso` existe depuis util-linux 2.24 ; sans lui, aucun
  # horodatage exploitable, et le collecteur préfère ne rien dater.
  run_cmd dmesg --level="$levels" --time-format=iso 2>/dev/null |
    awk '
      {
        stamp = $1
        # ISO local avec fuseau : « 2026-07-25T04:12:09,123456+0200 ».
        gsub(/,[0-9]+/, "", stamp)
        cmd = "date -d \"" stamp "\" +%s 2>/dev/null"
        epoch = ""
        cmd | getline epoch
        close(cmd)
        if (epoch == "") next
        msg = $0
        sub(/^[^ ]+ /, "", msg)
        provider = "kernel"
        if (msg ~ /^[a-zA-Z0-9_.-]+: /) {
          provider = msg
          sub(/:.*$/, "", provider)
        }
        printf "%s\t%s\t%s\n", epoch, provider, msg
      }
    '
}

# Convertit un epoch en horodatage ISO 8601 UTC, ou rien s'il est illisible.
stability_iso() {
  local epoch=${1-}
  [[ $epoch =~ ^[0-9]+$ ]] || return 0
  date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true
}

# --- Section `events` -------------------------------------------------------

# Compteurs par catégorie, écrits par `collect_events` et relus par
# `collect_stability`.
#
# Le passage se fait par **fichier** et non par variable, pour la même raison
# que le journal des incidents : `run_collector` exécute chaque collecteur dans
# un sous-shell, et une variable qu'il affecte meurt avec lui. Une version
# antérieure de ce fichier utilisait un tableau associatif ; les compteurs
# sortaient tous inconnus, ce qui se lisait comme une machine au journal
# illisible plutôt que comme le bug que c'était.
#
# Le journal est par ailleurs parcouru une seule fois : le relire pour chaque
# catégorie multiplierait par dix le coût du collecteur le plus lent.
STABILITY_JOURNAL=''

# Chemin du journal de stabilité, dans le répertoire temporaire déjà créé —
# et déjà supprimé en fin de scan, y compris en cas d'interruption.
stability_journal_path() {
  [ -n "$COLLECTION_JOURNAL" ] || return 1
  printf '%s/stability' "$(dirname "$COLLECTION_JOURNAL")"
}

collect_events() {
  log_step 'Historique des incidents'

  local records='' source='' examined=0
  local severity='' priority='' levels=''

  if stability_journal_readable; then
    source='journalctl'
    # Deux passes : `0..2` (emerg, alert, crit) et `3..3` (err). La sévérité
    # sort ainsi du journal lui-même.
    for severity in CRITICAL ERROR; do
      [ "$severity" = 'CRITICAL' ] && priority='0..2' || priority='3..3'
      local raw=''
      raw=$(stability_journal_events "$priority")
      [ -n "$raw" ] || continue
      examined=$((examined + $(printf '%s\n' "$raw" | count_non_empty_lines)))
      records=$(printf '%s\n%s' "$records" "$(printf '%s\n' "$raw" | stability_group_events "$severity")")
    done
  elif has_cmd dmesg; then
    source='dmesg'
    for severity in CRITICAL ERROR; do
      [ "$severity" = 'CRITICAL' ] && levels='emerg,alert,crit' || levels='err'
      local raw=''
      raw=$(stability_dmesg_events "$levels")
      [ -n "$raw" ] || continue
      examined=$((examined + $(printf '%s\n' "$raw" | count_non_empty_lines)))
      records=$(printf '%s\n%s' "$records" "$(printf '%s\n' "$raw" | stability_group_events "$severity")")
    done
  fi

  if [ -z "$source" ]; then
    record_issue 'events' 'warning' \
      'Ni journalctl lisible ni dmesg : aucun historique d’incidents n’a pu être lu.' \
      'journalctl' 'NOT_AVAILABLE'
    return 0
  fi

  # Fenêtre réellement couverte, et non celle demandée.
  local requested_ms=$((STABILITY_WINDOW_DAYS * 86400 * 1000))
  local covered_ms='' since='' until_ts='' persistent=''
  until_ts=$(iso_now)

  if [ "$source" = 'journalctl' ]; then
    if stability_journal_persistent; then persistent='true'; else persistent='false'; fi
    local oldest=''
    oldest=$(stability_journal_oldest_epoch)
    if [[ $oldest =~ ^[0-9]+$ ]]; then
      since=$(stability_iso "$oldest")
      covered_ms=$(( ($(date -u +%s) - oldest) * 1000 ))
      [ "$covered_ms" -lt 0 ] && covered_ms=''
    fi
  else
    # `dmesg` ne connaît que le démarrage courant : la fenêtre *est* l'uptime,
    # et l'annoncer comme trente jours serait un mensonge par omission.
    persistent='false'
    local uptime_s=''
    uptime_s=$(awk '{ printf "%d", $1 }' /proc/uptime 2>/dev/null || true)
    if [[ $uptime_s =~ ^[0-9]+$ ]]; then
      covered_ms=$((uptime_s * 1000))
      since=$(stability_iso "$(($(date -u +%s) - uptime_s))")
    fi
  fi

  # En-tête du journal de stabilité : source et fenêtre, que `collect_stability`
  # relira pour ses propres compteurs.
  STABILITY_JOURNAL=$(stability_journal_path) || STABILITY_JOURNAL=''
  if [ -n "$STABILITY_JOURNAL" ]; then
    printf 'META\t%s\t%s\n' "$source" "${covered_ms:-}" >"$STABILITY_JOURNAL"
  fi

  local entries='' kept=0 truncated='false'
  local category severity_out provider first last count summary fingerprint ev1 ev2 ev3
  while IFS="$STABILITY_FS" read -r category severity_out provider first last count summary fingerprint ev1 ev2 ev3; do
    [ -n "$category" ] || continue

    # Dernier filet avant le JSON : le schéma exige un résumé et une empreinte
    # non vides, et un incident sans l'un des deux ne décrit rien de toute
    # façon. Un seul enregistrement mal formé faisait refuser le rapport
    # **entier** en HTTP 400 — deux minutes d'audit perdues pour une ligne de
    # journal. Le rejet a lieu ici, sur l'enregistrement fautif, plutôt qu'à
    # l'autre bout du réseau sur le document complet.
    #
    # Ce n'est pas un pansement sur le parseur, qui est corrigé par ailleurs :
    # c'est la garantie qu'aucun futur défaut de lecture ne pourra plus rendre
    # un rapport indéposable.
    # Vide ou réduit à des espaces : les deux cas d'un coup. Le motif ne
    # correspond que si le résumé porte au moins un caractère non blanc.
    case "$summary" in
    *[![:space:]]*) ;;
    *) continue ;;
    esac
    [ -n "$fingerprint" ] || continue

    local last_iso=''
    last_iso=$(stability_iso "$last")
    # Compteurs par catégorie, pour la section `stability`.
    [ -n "$STABILITY_JOURNAL" ] &&
      printf 'CAT\t%s\t%s\t%s\n' "$category" "$count" "$last_iso" >>"$STABILITY_JOURNAL"

    if [ "$kept" -ge 500 ]; then
      truncated='true'
      continue
    fi
    kept=$((kept + 1))

    local evidence=''
    local line=''
    for line in "$ev1" "$ev2" "$ev3"; do
      [ -n "$line" ] || continue
      evidence=$(json_join "$evidence" "$(j_str "$(anon_message "$line")")")
    done

    entries=$(json_join "$entries" "$(json_object \
      "$(jf_str category "$category")" \
      "$(jf_str severity "$severity_out")" \
      "$(jf_str provider "${provider:-inconnu}")" \
      "$(jf_maybe_str nativeId '' NOT_AVAILABLE 'journald ne numérote pas ses entrées')" \
      "$(jf_maybe_str firstSeenAt "$(stability_iso "$first")" UNKNOWN 'horodatage illisible')" \
      "$(jf_maybe_str lastSeenAt "$last_iso" UNKNOWN 'horodatage illisible')" \
      "$(jf_raw occurrences "$count")" \
      "$(jf_str summary "$(anon_message "$summary")")" \
      "$(jf_str fingerprint "$fingerprint")" \
      "$(jf_str source "$source")" \
      "$(if [ -n "$evidence" ]; then jf_raw evidence "[$evidence]"; fi)")")
  done < <(printf '%s\n' "$records")

  record_provenance 'events.entries' "$source" 'commande shell' 'incident regroupé'

  json_object \
    "$(jf_raw window "$(json_object \
      "$(jf_raw requestedMs "$requested_ms")" \
      "$(jf_maybe_num coveredMs "$covered_ms" UNKNOWN 'plus ancienne entrée non datable')" \
      "$(jf_maybe_str since "$since" UNKNOWN 'plus ancienne entrée non datable')" \
      "$(jf_str until "$until_ts")" \
      "$(jf_maybe_bool persistent "$persistent")")")" \
    "$(jf_maybe_num examined "$examined")" \
    "$(jf_maybe_bool truncated "$truncated")" \
    "$(jf_raw entries "[$entries]")" \
    "$(jf_raw meta "$(json_object \
      "$(jf_str source "$source")" \
      "$(jf_str method 'commande shell')" \
      "$(jf_str collectedAt "$until_ts")" \
      "$(if [ -n "$covered_ms" ]; then jf_raw observationWindowMs "$covered_ms"; fi)")")"
}

# Retire d'une ligne de journal ce qui identifie une personne ou une machine,
# quand l'anonymisation est demandée.
#
# Le champ `evidence` est déjà réservé au propriétaire côté serveur ; cette
# passe traite le cas où l'utilisateur a explicitement demandé que le rapport
# ne contienne rien d'identifiant, y compris pour lui-même.
anon_message() {
  local line=${1-}
  [ "$ANONYMIZE" = 'true' ] || {
    printf '%s' "$line"
    return 0
  }
  local host=''
  host=$(hostname 2>/dev/null || true)
  [ -n "$host" ] && line=${line//$host/$(anon hostname "$host")}
  # Les adresses IPv4 littérales et les chemins personnels sont les deux autres
  # porteurs habituels d'identité dans une ligne de journal.
  line=$(printf '%s' "$line" | sed -E 's#/home/[^/ ]+#/home/USER#g; s#\b([0-9]{1,3}\.){3}[0-9]{1,3}\b#IP#g')
  printf '%s' "$line"
}

# --- Section `stability` ----------------------------------------------------

# Source et fenêtre relues dans le journal de stabilité, ou vides si
# `collect_events` n'a rien pu lire.
STABILITY_EVENTS_SOURCE=''
STABILITY_COVERED_MS=''

stability_load_journal() {
  STABILITY_JOURNAL=$(stability_journal_path) || STABILITY_JOURNAL=''
  [ -n "$STABILITY_JOURNAL" ] && [ -s "$STABILITY_JOURNAL" ] || return 0
  read -r STABILITY_EVENTS_SOURCE STABILITY_COVERED_MS < <(
    awk -v FS='\t' '$1 == "META" { print $2, $3; exit }' "$STABILITY_JOURNAL"
  )
  return 0
}

# Compteur d'incidents d'une catégorie, avec la fenêtre qu'il couvre.
#
# Aucune catégorie n'est ramenée à zéro par défaut : si le journal n'a pas pu
# être lu, le compteur reste inconnu. Zéro voudrait dire « regardé, rien
# trouvé », ce qui est une affirmation que le scanner n'a pas le droit de faire
# sans avoir regardé.
stability_incident_count() {
  local category=$1
  local count='' last=''

  if [ -n "$STABILITY_EVENTS_SOURCE" ]; then
    # Zéro est ici une mesure : le journal a été parcouru, cette catégorie n'y
    # figurait pas.
    count=$(awk -v FS='\t' -v c="$category" \
      '$1 == "CAT" && $2 == c { total += $3 } END { print total + 0 }' "$STABILITY_JOURNAL")
    last=$(awk -v FS='\t' -v c="$category" \
      '$1 == "CAT" && $2 == c && $4 != "" { print $4 }' "$STABILITY_JOURNAL" | sort | tail -n 1)
  fi

  # Ces compteurs dérivent du parcours de `events`. Quand le niveau choisi ne
  # collecte pas `events`, ils manquent parce qu'on n'a pas regardé — pas parce
  # que le journal serait illisible. Une première version disait « aucun journal
  # lisible » sur une machine dont le journal se lisait très bien : le lecteur
  # aurait cherché un problème de permissions au lieu de relancer au bon niveau.
  local reason='NOT_AVAILABLE' detail='aucun journal lisible'
  if [ -z "$STABILITY_EVENTS_SOURCE" ] && ! level_collects events; then
    reason='NOT_COLLECTED'
    detail="dérivé de la section events, non collectée au niveau $(level_label "$(current_level)")"
  fi

  # « Aucun incident de cette catégorie » ne se dit que si l'on a regardé.
  # Sinon, l'absence de date a la même raison que l'absence de compteur.
  local last_reason="$reason" last_detail="$detail"
  if [ -n "$count" ]; then
    last_reason='NOT_APPLICABLE'
    last_detail='aucun incident de cette catégorie sur la fenêtre'
  fi

  json_object \
    "$(jf_maybe_num count "$count" "$reason" "$detail")" \
    "$(jf_maybe_num observationWindowMs "$STABILITY_COVERED_MS" "$reason" "$detail")" \
    "$(jf_maybe_str lastAt "$last" "$last_reason" "$last_detail")" \
    "$(jf_maybe_str source "$STABILITY_EVENTS_SOURCE" "$reason" "$detail")"
}

# Unités du gestionnaire de services actuellement en échec.
stability_failed_units() {
  has_cmd systemctl || return 0
  local units='' name='' load='' active='' sub=''
  while read -r name load active sub _; do
    [ -n "$name" ] || continue
    case "$name" in *.service | *.socket | *.timer | *.mount | *.target) ;; *) continue ;; esac
    units=$(json_join "$units" "$(json_object \
      "$(jf_str name "$name")" \
      "$(jf_maybe_str state "$active" UNKNOWN)" \
      "$(jf_maybe_str result "$sub" UNKNOWN)" \
      "$(jf_maybe_str since '' NOT_AVAILABLE 'systemctl list-units ne date pas l’entrée en échec')" \
      "$(jf_maybe_num restarts '' NOT_AVAILABLE 'compteur de redémarrages non exposé par list-units')")")
    # `load` n'est pas rapporté : il décrit le fichier d'unité, pas l'incident.
    : "$load"
  done < <(run_cmd systemctl list-units --failed --no-legend --plain --no-pager 2>/dev/null || true)
  printf '%s' "$units"
}

# Vidanges mémoire recensées. Jamais leur contenu : il expose la mémoire du
# processus, donc potentiellement des secrets.
stability_coredumps() {
  has_cmd coredumpctl || return 0
  local dumps='' exe='' signal='' at='' present=''
  while IFS="$STABILITY_FS" read -r exe signal at present; do
    [ -n "$exe" ] || continue
    dumps=$(json_join "$dumps" "$(json_object \
      "$(jf_maybe_str executable "$(anon_message "$exe")" UNKNOWN)" \
      "$(jf_maybe_str signal "$signal" UNKNOWN)" \
      "$(jf_maybe_str at "$at" UNKNOWN)" \
      "$(jf_raw count 1)" \
      "$(jf_maybe_bool present "$present")")")
  done < <(
    run_cmd coredumpctl list --no-legend --no-pager 2>/dev/null |
      awk -v OFS=$'\x1f' '
        NF >= 8 {
          # « JJ-MM-JJ HH:MM:SS TZ PID UID GID SIG COREFILE EXE »
          cmd = "date -u -d \"" $1 " " $2 "\" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null"
          at = ""
          cmd | getline at
          close(cmd)
          present = ($(NF - 1) == "present") ? "true" : "false"
          print $NF, $(NF - 2), at, present
        }
      ' | tail -n 100
  )
  printf '%s' "$dumps"
}

collect_stability() {
  log_step 'Stabilité observée'

  stability_load_journal

  local uptime_s='' booted_at=''
  if [ -r /proc/uptime ]; then
    uptime_s=$(awk '{ printf "%d", $1 }' /proc/uptime 2>/dev/null || true)
    [[ $uptime_s =~ ^[0-9]+$ ]] && booted_at=$(stability_iso "$(($(date -u +%s) - uptime_s))")
  fi

  # `/proc/sys/kernel/tainted` non nul signale un module propriétaire, un module
  # forcé ou une erreur matérielle antérieure. La valeur brute part telle
  # quelle : décomposer ses bits est une interprétation.
  local tainted=''
  [ -r /proc/sys/kernel/tainted ] && tainted=$(cat /proc/sys/kernel/tainted 2>/dev/null || true)

  # Redémarrages : `last reboot` lit `wtmp`, dont la rotation est indépendante
  # de celle du journal. La fenêtre annoncée est donc celle du journal, faute de
  # pouvoir dater le début de `wtmp` de façon portable.
  local reboots=''
  if has_cmd last; then
    reboots=$(run_cmd last --time-format iso -F reboot 2>/dev/null |
      awk 'NF && $1 == "reboot" { count++ } END { print count + 0 }')
  fi

  local failed_units='' coredumps=''
  failed_units=$(stability_failed_units)
  coredumps=$(stability_coredumps)

  local reboot_window=''
  reboot_window=$(json_object \
    "$(jf_maybe_num count "$reboots" NOT_AVAILABLE 'commande last absente ou wtmp illisible')" \
    "$(jf_maybe_num observationWindowMs '' NOT_AVAILABLE 'la rotation de wtmp n’est pas datable de façon portable')" \
    "$(jf_maybe_str lastAt "$booted_at" UNKNOWN)" \
    "$(jf_maybe_str source 'last reboot' NOT_AVAILABLE)")

  json_object \
    "$(jf_maybe_num uptimeSeconds "$uptime_s" NOT_AVAILABLE '/proc/uptime illisible')" \
    "$(jf_maybe_str bootedAt "$booted_at" UNKNOWN)" \
    "$(jf_raw reboots "$reboot_window")" \
    "$(jf_raw unexpectedShutdowns "$(stability_incident_count POWER)")" \
    "$(jf_raw kernelCrashes "$(stability_incident_count KERNEL_CRASH)")" \
    "$(jf_raw hardwareErrors "$(stability_incident_count HARDWARE)")" \
    "$(jf_raw storageErrors "$(stability_incident_count STORAGE)")" \
    "$(jf_raw filesystemErrors "$(stability_incident_count FILESYSTEM)")" \
    "$(jf_raw memoryPressureEvents "$(stability_incident_count MEMORY)")" \
    "$(jf_raw networkErrors "$(stability_incident_count NETWORK)")" \
    "$(jf_raw driverErrors "$(stability_incident_count DRIVER)")" \
    "$(jf_raw serviceFailures "$(stability_incident_count SERVICE)")" \
    "$(jf_raw applicationCrashes "$(stability_incident_count APPLICATION_CRASH)")" \
    "$(jf_raw thermalEvents "$(stability_incident_count THERMAL)")" \
    "$(jf_raw failedUpdates "$(stability_incident_count UPDATE)")" \
    "$(jf_raw failedUnits "[$failed_units]")" \
    "$(jf_raw coredumps "[$coredumps]")" \
    "$(jf_maybe_num kernelTainted "$tainted" NOT_AVAILABLE '/proc/sys/kernel/tainted illisible')" \
    "$(jf_raw meta "$(json_object \
      "$(jf_str source "${STABILITY_EVENTS_SOURCE:-/proc}")" \
      "$(jf_str method 'commande shell')" \
      "$(jf_str collectedAt "$(iso_now)")" \
      "$(if [ -n "$STABILITY_COVERED_MS" ]; then jf_raw observationWindowMs "$STABILITY_COVERED_MS"; fi)")")"
}

# --- Noyaux installés -------------------------------------------------------

# Noyaux installés, interrogés au gestionnaire de paquets de la machine.
#
# Le gestionnaire est choisi sur sa **présence réelle**, jamais sur le nom de la
# distribution : `/etc/os-release` dit « Manjaro » sur une machine dont
# quelqu'un a installé `dnf`, et un aiguillage par nom se tromperait
# silencieusement. C'est aussi ce qui fait fonctionner ce collecteur sur les
# dérivées que personne n'a prévues.
#
# La première ligne écrite est `SOURCE<TAB><nom>` ; les suivantes sont les
# versions. Faire voyager la source par un fichier temporaire aurait ajouté une
# écriture à un scanner qui n'en fait aucune hors de son rapport.
#
# Chaque source est tentée **et son résultat vérifié** : la présence de l'outil
# ne garantit pas une réponse. Une machine WSL a `dpkg`, mais son noyau vient de
# Windows et aucun paquet `linux-image-*` n'est installé. S'arrêter au premier
# outil trouvé rendait alors une liste vide là où `/lib/modules` avait la
# réponse.
stability_installed_kernels() {
  local list=''

  if has_cmd dpkg-query; then
    list=$(run_cmd dpkg-query -W -f '${Package}\n' 'linux-image-[0-9]*' 2>/dev/null |
      sed -E 's/^linux-image-//' | sort -Vu)
    if [ -n "$list" ]; then
      printf 'SOURCE\tdpkg\n%s\n' "$list"
      return 0
    fi
  fi

  if has_cmd rpm; then
    list=$(run_cmd rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel kernel-core 2>/dev/null |
      grep -vF 'not installed' | sort -Vu)
    if [ -n "$list" ]; then
      printf 'SOURCE\trpm\n%s\n' "$list"
      return 0
    fi
  fi

  # Arch garde un répertoire de modules par version : plus fiable que le nom du
  # paquet, qui ne porte pas la version pour `linux`, `linux-lts`, `linux-zen`.
  if has_cmd pacman && [ -d /usr/lib/modules ]; then
    list=$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -Vu)
    if [ -n "$list" ]; then
      printf 'SOURCE\tpacman\n%s\n' "$list"
      return 0
    fi
  fi

  # Dernier recours, valable partout : les modules installés.
  if [ -d /lib/modules ]; then
    list=$(find /lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -Vu)
    if [ -n "$list" ]; then
      printf 'SOURCE\t/lib/modules\n%s\n' "$list"
    fi
  fi
  return 0
}

stability_kernels_json() {
  local running='' installed='' source='' newest=''
  running=$(uname -r 2>/dev/null || true)

  local entry='' tag=''
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    tag=${entry%%$'\t'*}
    if [ "$tag" = 'SOURCE' ]; then
      source=${entry#*$'\t'}
      continue
    fi
    installed=$(json_join "$installed" "$(j_str "$entry")")
    newest=$entry
  done < <(stability_installed_kernels)

  json_object \
    "$(jf_maybe_str running "$running" NOT_AVAILABLE 'uname illisible')" \
    "$(jf_raw installed "[$installed]")" \
    "$(jf_maybe_str newestInstalled "$newest" NOT_AVAILABLE 'aucun noyau énuméré')" \
    "$(jf_maybe_str source "$source" NOT_AVAILABLE 'aucun gestionnaire de paquets interrogeable')"
}

# --- Section `boot` ---------------------------------------------------------

collect_boot() {
  log_step 'Séquence de démarrage'

  local firmware_mode='UNKNOWN'
  # `/sys/firmware/efi` n'existe que si le noyau a démarré en mode EFI. Son
  # absence sur une machine capable d'UEFI signifie donc bien un démarrage en
  # mode hérité, et non une incertitude.
  if [ -d /sys/firmware/efi ]; then firmware_mode='UEFI'; else firmware_mode='LEGACY_BIOS'; fi

  local phases='' total_ms='' measured_at=''
  if has_cmd systemd-analyze; then
    local analyze=''
    analyze=$(run_cmd systemd-analyze time 2>/dev/null || true)
    if [ -n "$analyze" ]; then
      measured_at=$(iso_now)
      # « Startup finished in 4.820s (firmware) + 3.100s (loader) + … = 29.260s »
      local phase='' value=''
      while read -r value phase; do
        [ -n "$phase" ] || continue
        phases=$(json_join "$phases" "$(json_object \
          "$(jf_str name "$phase")" \
          "$(jf_maybe_num durationMs "$value")")")
      done < <(printf '%s' "$analyze" | awk '
        {
          for (i = 1; i <= NF; i++) {
            if ($i ~ /^\(.*\)$/ && $(i - 1) ~ /^[0-9.]+(ms|s|min)?$/) {
              name = $i; gsub(/[()]/, "", name)
              v = $(i - 1)
              unit = "s"
              if (v ~ /ms$/) unit = "ms"
              else if (v ~ /min$/) unit = "min"
              gsub(/[a-z]+$/, "", v)
              ms = (unit == "ms") ? v : ((unit == "min") ? v * 60000 : v * 1000)
              printf "%.0f %s\n", ms, name
            }
          }
        }')

      # `systemd-analyze` n'écrit « = <total> » que lorsqu'il a plusieurs phases
      # à additionner. Sur une machine qui n'en rapporte qu'une — un conteneur,
      # une VM sans micrologiciel mesurable — la ligne s'arrête après la phase,
      # et une première version rendait alors le total « non disponible » alors
      # qu'il était sous les yeux.
      #
      # À défaut de total publié, la somme des phases **mesurées** en tient
      # lieu. Additionner des durées lues n'invente rien ; c'est exactement ce
      # que `systemd-analyze` fait lui-même quand il en a plusieurs.
      total_ms=$(printf '%s' "$analyze" | awk '
        /= *[0-9]/ {
          v = $NF
          unit = "s"
          if (v ~ /ms$/) unit = "ms"
          else if (v ~ /min$/) unit = "min"
          gsub(/[a-z]+$/, "", v)
          if (v ~ /^[0-9.]+$/) {
            printf "%.0f", (unit == "ms") ? v : ((unit == "min") ? v * 60000 : v * 1000)
            exit
          }
        }')
      if [ -z "$total_ms" ]; then
        total_ms=$(printf '%s' "$phases" | grep -oE '"durationMs":[0-9]+' |
          awk -v FS=':' '{ sum += $2 } END { if (NR > 0) printf "%d", sum }')
      fi
    fi
  fi

  local slowest=''
  if has_cmd systemd-analyze; then
    local name='' ms=''
    while read -r ms name; do
      [ -n "$name" ] || continue
      slowest=$(json_join "$slowest" "$(json_object \
        "$(jf_str name "$name")" \
        "$(jf_maybe_num durationMs "$ms")" \
        "$(jf_str kind 'unit')")")
    done < <(
      run_cmd systemd-analyze blame --no-pager 2>/dev/null | head -n 20 | awk '
        NF >= 2 {
          v = $1
          unit = "s"
          if (v ~ /ms$/) unit = "ms"
          else if (v ~ /min$/) unit = "min"
          gsub(/[a-z]+$/, "", v)
          if (v !~ /^[0-9.]+$/) next
          ms = (unit == "ms") ? v : ((unit == "min") ? v * 60000 : v * 1000)
          printf "%.0f %s\n", ms, $NF
        }'
    )
  fi

  # Unités en échec depuis le démarrage courant : `systemctl list-units --failed`
  # décrit l'instant présent, pas le démarrage. Les deux coïncident souvent mais
  # pas toujours — un service tombé une heure après le démarrage n'a pas échoué
  # *au* démarrage, et les confondre accuserait la séquence de boot à tort.
  local failed_at_boot=''
  if stability_journal_readable; then
    local unit=''
    while read -r unit; do
      [ -n "$unit" ] || continue
      failed_at_boot=$(json_join "$failed_at_boot" "$(json_object \
        "$(jf_str name "$unit")" \
        "$(jf_maybe_str state 'failed' UNKNOWN)" \
        "$(jf_maybe_str result '' NOT_AVAILABLE 'le journal ne publie pas le code de sortie sur cette ligne')" \
        "$(jf_maybe_str since '' NOT_AVAILABLE 'ligne de journal non datée individuellement')" \
        "$(jf_maybe_num restarts '' NOT_AVAILABLE 'compteur non exposé par le journal')")")
    done < <(
      run_cmd journalctl --no-pager --quiet -b 0 -p err -o cat 2>/dev/null |
        awk '
          # Deux formulations pour le même fait, et le nom de l’unité n’est pas
          # au même endroit :
          #   « foo.service: Failed with result ʼexit-codeʼ. »
          #   « Failed to start Description longue du service. »
          # La première nomme l’unité, la seconde sa description. Seule la
          # première est exploitable telle quelle ; la seconde est conservée
          # parce quʼelle reste identifiable par un administrateur.
          /: Failed with result/ {
            unit = $0
            sub(/:.*$/, "", unit)
            if (unit != "") print unit
            next
          }
          /^Failed to start / {
            line = $0
            sub(/^Failed to start /, "", line)
            sub(/\.$/, "", line)
            if (line != "") print line
          }
        ' | sort -u | head -n 50
    )
  fi

  json_object \
    "$(jf_raw phases "[$phases]")" \
    "$(jf_maybe_num totalMs "$total_ms" NOT_AVAILABLE 'systemd-analyze absent ou muet')" \
    "$(jf_maybe_str measuredAt "$measured_at" NOT_AVAILABLE 'systemd-analyze absent')" \
    "$(jf_raw slowestItems "[$slowest]")" \
    "$(jf_raw failedAtBoot "[$failed_at_boot]")" \
    "$(jf_str firmwareMode "$firmware_mode")" \
    "$(jf_raw fastStartupEnabled "$(j_unknown NOT_APPLICABLE 'notion propre à Windows')")" \
    "$(jf_raw kernels "$(stability_kernels_json)")" \
    "$(jf_raw meta "$(json_object \
      "$(jf_str source 'systemd-analyze')" \
      "$(jf_str method 'commande shell')" \
      "$(jf_str collectedAt "$(iso_now)")")")"
}

# --- Section `shutdown` -----------------------------------------------------

collect_shutdown() {
  log_step 'Séquence d’arrêt'

  stability_journal_readable || {
    record_issue 'shutdown' 'warning' \
      'journalctl illisible : le déroulement du dernier arrêt n’a pas pu être lu.' 'journalctl' 'NOT_AVAILABLE'
    return 0
  }

  # Le démarrage précédent (`-b -1`) contient les traces de l'arrêt qui l'a
  # terminé. Sur une machine qui n'a démarré qu'une fois, il n'existe pas — et
  # c'est « rien à mesurer », pas une panne.
  local previous=''
  previous=$(run_cmd journalctl --no-pager --quiet -b -1 -n 40 -o short-unix 2>/dev/null || true)

  if [ -z "$previous" ]; then
    json_object \
      "$(jf_raw lastShutdownAt "$(j_unknown NOT_APPLICABLE 'aucun démarrage antérieur dans le journal')")" \
      "$(jf_raw lastShutdownWasClean "$(j_unknown NOT_APPLICABLE 'aucun démarrage antérieur dans le journal')")" \
      "$(jf_raw lastShutdownReason "$(j_unknown NOT_APPLICABLE 'aucun démarrage antérieur dans le journal')")" \
      "$(jf_raw lastShutdownDurationMs "$(j_unknown NOT_AVAILABLE 'le journal ne chronomètre pas l’extinction')")" \
      "$(jf_raw slowestItems '[]')" \
      "$(jf_raw meta "$(json_object \
        "$(jf_str source 'journalctl --list-boots')" \
        "$(jf_str method 'commande shell')" \
        "$(jf_str collectedAt "$(iso_now)")")")"
    return 0
  fi

  local last_epoch='' reason='' clean=''
  last_epoch=$(printf '%s' "$previous" | tail -n 1 | awk '{ sub(/\..*$/, "", $1); print $1 }')

  # Un arrêt propre laisse une trace explicite. Son **absence** ne prouve pas
  # l'inverse : le journal peut avoir été tronqué. `clean` reste donc inconnu
  # plutôt que faux, sauf trace contraire.
  if printf '%s' "$previous" | grep -qiE 'systemd-shutdown|Reached target (Shutdown|Power-Off|Reboot)|Powering off|Shutting down'; then
    clean='true'
    reason=$(printf '%s' "$previous" |
      grep -iE 'systemd-shutdown|Reached target (Shutdown|Power-Off|Reboot)|Powering off' |
      tail -n 1 | cut -c1-400)
    reason=${reason#* * }
  elif printf '%s' "$previous" | grep -qiE 'unclean shutdown|forced (reboot|shutdown)|watchdog.*reset'; then
    clean='false'
    reason=$(printf '%s' "$previous" |
      grep -iE 'unclean shutdown|forced (reboot|shutdown)|watchdog.*reset' |
      tail -n 1 | cut -c1-400)
    reason=${reason#* * }
  fi

  json_object \
    "$(jf_maybe_str lastShutdownAt "$(stability_iso "$last_epoch")" UNKNOWN 'dernière ligne du démarrage précédent non datable')" \
    "$(jf_maybe_bool lastShutdownWasClean "$clean" UNKNOWN 'aucune trace explicite d’arrêt : le journal a pu être tronqué')" \
    "$(jf_maybe_str lastShutdownReason "$(anon_message "$reason")" UNKNOWN 'aucune ligne d’arrêt identifiée')" \
    "$(jf_raw lastShutdownDurationMs "$(j_unknown NOT_AVAILABLE 'le journal ne chronomètre pas l’extinction')")" \
    "$(jf_raw slowestItems '[]')" \
    "$(jf_raw meta "$(json_object \
      "$(jf_str source 'journalctl -b -1')" \
      "$(jf_str method 'commande shell')" \
      "$(jf_str collectedAt "$(iso_now)")")")"
}
