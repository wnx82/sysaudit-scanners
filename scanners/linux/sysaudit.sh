#!/usr/bin/env bash
#
# SysAudit — scanner Linux / Proxmox
#
# Audit READ ONLY d'une machine Linux : ce script ne modifie jamais la
# configuration du système audité et ne collecte aucun secret.
#
# Connexions sortantes : aucune, sauf deux, et toutes deux vers l'API désignée
# par `--api-url` — jamais vers un tiers.
#
#   1. l'envoi du rapport, qui se demande par `--upload` ;
#   2. le relevé de l'adresse publique (WAN), qui n'existe nulle part sur le
#      poste et qu'il faut donc demander à un correspondant distant.
#
# Le second a lieu **dès qu'une API est connue**, parce qu'un champ de
# diagnostic réseau qu'il faut penser à réclamer manque le jour où il servirait.
# `--no-public-ip` le retire. Sans `--api-url`, il n'y a personne à interroger
# et rien ne sort : un audit hors ligne reste hors ligne, sans réglage.
#
# Une seule exception, et elle se demande toujours : l'installation d'outils
# manquants — un par un, chacun décrit avant la question, et leur retrait proposé
# en fin d'audit. Deux chemins y mènent, jamais un défaut :
#
#   - `--install-deps`, en audit complet ou poussé ;
#   - une **offre**, quand des outils manquent et qu'un terminal peut répondre.
#     Le défaut y est non, et sans terminal — cron, conteneur, intégration
#     continue — la question n'est pas posée du tout.
#
# Décision et bornes : docs/adr/0008-installation-consentie-en-audit-administrateur.md.
#
# Usage :
#   sudo ./sysaudit.sh                     audit standard, rapport local
#   sudo ./sysaudit.sh --quick            audit rapide
#   sudo ./sysaudit.sh --full             audit complet
#   sudo ./sysaudit.sh --stress           audit poussé / stress
#   sudo ./sysaudit.sh --full --install-deps  propose d'installer les outils manquants
#   sudo ./sysaudit.sh --assume-yes        accord d'installation déjà donné (sans TTY)
#   sudo ./sysaudit.sh --benchmark         mesure les performances (charge la machine)
#   sudo ./sysaudit.sh --monitor 60        observe la machine pendant 60 s
#   sudo ./sysaudit.sh --anonymize         masque les identifiants
#   sudo ./sysaudit.sh --no-public-ip      ne relève pas l'adresse WAN
#   sudo ./sysaudit.sh --upload --public   publie l'audit dans la vitrine
#   sudo ./sysaudit.sh --upload --private  garde l'audit privé, même si
#                                          l'instance publie par défaut
#   sudo ./sysaudit.sh --skip software     écarte une section, et le déclare
#   sudo ./sysaudit.sh --output-dir /tmp   choisit le répertoire de sortie
#                                          (défaut : dossier personnel de
#                                          l'utilisateur, `sudo` compris)
#   sudo ./sysaudit.sh --stdout            écrit le JSON sur stdout
#   sudo ./sysaudit.sh --claim ABCD-EFGH   rattache cette machine à votre compte
#   sudo ./sysaudit.sh --proxy http://p:8080  emprunte ce proxy pour l'envoi
#   sudo ./sysaudit.sh --no-proxy          ignore le proxy de l'environnement
#   ./sysaudit.sh --network-test           teste le réseau, sans auditer
#   ./sysaudit.sh --capabilities           montre ce qui serait collecté
#   ./sysaudit.sh --version
#
# Codes de sortie :
#   0  audit produit, et transmis s'il devait l'être
#   1  audit impossible — usage incorrect, ou collecte en échec
#   2  audit produit, transmission échouée — le rapport est sur le disque

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR

# Version du scanner, indépendante de celle de la plateforme (docs/format-rapport/VERSIONING.md).
SCANNER_VERSION=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || printf '0.0.0')
readonly SCANNER_VERSION

# Version du format produit. Doit correspondre à SCHEMA_VERSION du package
# @sysaudit/report-schema : un test de CI vérifie cette égalité.
readonly SCHEMA_VERSION='1.33.0'

# Chargement des modules. L'ordre et la liste sont ceux de `MANIFEST`, source de
# vérité partagée avec l'API et le script d'amorçage. Les `source` restent
# explicites pour que ShellCheck puisse les suivre ; un test du scanner vérifie
# qu'ils correspondent exactement au manifeste.

# shellcheck source=lib/core/schema-bounds.sh
. "$SCRIPT_DIR/lib/core/schema-bounds.sh"
# shellcheck source=lib/core/json.sh
. "$SCRIPT_DIR/lib/core/json.sh"
# shellcheck source=lib/core/console.sh
. "$SCRIPT_DIR/lib/core/console.sh"
# shellcheck source=lib/core/progress.sh
. "$SCRIPT_DIR/lib/core/progress.sh"
# shellcheck source=lib/core/core.sh
. "$SCRIPT_DIR/lib/core/core.sh"
# shellcheck source=lib/core/transport.sh
. "$SCRIPT_DIR/lib/core/transport.sh"
# shellcheck source=lib/core/levels.sh
. "$SCRIPT_DIR/lib/core/levels.sh"
# shellcheck source=lib/core/dependencies.sh
. "$SCRIPT_DIR/lib/core/dependencies.sh"
# shellcheck source=lib/core/provision.sh
. "$SCRIPT_DIR/lib/core/provision.sh"
# shellcheck source=lib/core/anonymize.sh
. "$SCRIPT_DIR/lib/core/anonymize.sh"
# shellcheck source=lib/core/capabilities.sh
. "$SCRIPT_DIR/lib/core/capabilities.sh"
# shellcheck source=lib/collectors/system.sh
. "$SCRIPT_DIR/lib/collectors/system.sh"
# shellcheck source=lib/collectors/hardware.sh
. "$SCRIPT_DIR/lib/collectors/hardware.sh"
# shellcheck source=lib/collectors/media.sh
. "$SCRIPT_DIR/lib/collectors/media.sh"
# shellcheck source=lib/collectors/power.sh
. "$SCRIPT_DIR/lib/collectors/power.sh"
# shellcheck source=lib/collectors/storage.sh
. "$SCRIPT_DIR/lib/collectors/storage.sh"
# shellcheck source=lib/collectors/network.sh
. "$SCRIPT_DIR/lib/collectors/network.sh"
# shellcheck source=lib/collectors/security.sh
. "$SCRIPT_DIR/lib/collectors/security.sh"
# shellcheck source=lib/collectors/software.sh
. "$SCRIPT_DIR/lib/collectors/software.sh"
# shellcheck source=lib/collectors/virtualization.sh
. "$SCRIPT_DIR/lib/collectors/virtualization.sh"
# shellcheck source=lib/collectors/stability.sh
. "$SCRIPT_DIR/lib/collectors/stability.sh"
# shellcheck source=lib/collectors/monitoring.sh
. "$SCRIPT_DIR/lib/collectors/monitoring.sh"
# shellcheck source=lib/collectors/benchmark.sh
. "$SCRIPT_DIR/lib/collectors/benchmark.sh"
# shellcheck source=lib/output/markdown.sh
. "$SCRIPT_DIR/lib/output/markdown.sh"

# --- Options ----------------------------------------------------------------

# Destination par défaut du rapport : le dossier personnel de l'utilisateur qui
# a lancé l'audit — et non le répertoire courant, qui dépend de l'endroit d'où
# la commande a été tapée, ni `/root` dès que `sudo` est passé par là. Voir
# `resolve_user_home` dans `lib/core/core.sh`.
OUTPUT_DIR=$(resolve_user_home)
OPT_OUTPUT_DIR_EXPLICIT='false'
PROFILE='standard'
OPT_ANONYMIZE='false'
OPT_STDOUT='false'
OPT_NO_MARKDOWN='false'
OPT_UPLOAD='false'
# Publie l'audit dans la vitrine de l'instance.
#
# Il ne rend pas le rapport « lisible » : il l'était déjà par son adresse, dès
# l'envoi. Il le rend **répertoriable** — susceptible d'apparaître dans la liste
# des diagnostics récents. C'est la différence entre une adresse qu'on donne et
# une adresse qu'on publie, et c'est pour cela qu'elle se demande.
OPT_PUBLIC='false'
# Exige explicitement le privé, quel que soit le défaut de l'instance.
#
# ## Pourquoi ce drapeau manquait, et ce que son absence a coûté
#
# L'API traite `X-Scan-Visibility` **dans les deux sens** depuis toujours : un
# envoi qui demande `private` reste privé même sur une instance publique par
# défaut, et un test le garde. Le scanner, lui, n'envoyait l'en-tête que pour
# publier — il n'avait aucun moyen de demander le privé.
#
# Sur une instance dont `DEFAULT_SCAN_VISIBILITY` vaut `PUBLIC`, un audit de
# validation, de test ou d'exploitation devenait donc répertoriable **sans que
# personne l'ait demandé**, et sans qu'aucune option ne permette de l'éviter.
# C'est arrivé le 2026-08-27, sur l'audit produit pour valider la chaîne de
# classement en production : il a fallu le repasser en privé après coup, en
# base.
#
# La demande d'un envoi doit pouvoir être plus stricte que le défaut d'une
# instance. Sans quoi « privé » n'est pas une décision, seulement une chance.
OPT_PRIVATE='false'
# Relève l'adresse publique (WAN) de la machine. Trois états, pas deux.
#
#   auto   — le défaut : relevée **si une API est connue**, ignorée sinon.
#   true   — `--public-ip` : exigée. Sans API, le scanner refuse de démarrer.
#   false  — `--no-public-ip` : jamais relevée, même avec une API sous la main.
#
# ## Pourquoi trois états et non un simple drapeau
#
# C'est la seule collecte du scanner qui émette un paquet vers l'extérieur, et
# une adresse WAN n'existe nulle part sur le poste : seul un correspondant
# distant l'observe. Sans adresse d'API, il n'y a donc personne à interroger —
# et un défaut à `true` ferait échouer d'emblée tout audit hors ligne, pour un
# champ que l'utilisateur n'a jamais réclamé. Un défaut à `false` obligeait à
# l'inverse à penser à l'option à chaque audit.
#
# `auto` répond aux deux : l'adresse est relevée là où elle peut l'être, et
# l'absence d'API n'est pas une erreur mais une réponse — le champ reste absent
# du rapport, ce qui se lit « pas de correspondant à interroger ».
#
# Le refus explicite est conservé pour `--public-ip` : qui *demande* ce champ
# doit apprendre tout de suite qu'il manque une API, et non le découvrir en
# lisant le rapport.
#
# L'adresse relevée est réservée au propriétaire à la lecture, et pseudonymisée
# à la collecte sous `--anonymize`.
OPT_PUBLIC_IP='auto'
OPT_MONITOR_SECONDS='0'
OPT_BENCHMARK='false'
OPT_API_URL="${SYSAUDIT_API_URL:-}"
# Proxy à emprunter pour l'envoi. Vide signifie « rien de déclaré ici » — et non
# « pas de proxy » : curl lit `https_proxy` de lui-même, et un proxy transparent
# ne se déclare nulle part. `SYSAUDIT_PROXY` reprend la variable propre à cet
# outil, comme côté Windows, pour qu'un poste puisse le désigner sans toucher
# aux variables communes.
OPT_PROXY="${SYSAUDIT_PROXY:-}"
# Ignore tout proxy, y compris celui de l'environnement, pour cet envoi.
OPT_NO_PROXY='false'
# Code de rattachement d'une machine à un compte. Il n'est pas un secret de
# longue durée : il vaut une fois, pour une machine, pendant vingt-quatre
# heures. Il n'entre jamais dans le rapport — seulement dans l'en-tête d'envoi.
OPT_CLAIM_CODE=''
# Chemin d'un rapport déjà produit, à renvoyer sans relancer la collecte.
OPT_RETRY_PATH=''
# Autorise SysAudit à proposer l'installation des outils manquants. Jamais
# déduit d'autre chose : c'est la première des quatre conditions de l'ADR 0008,
# et le script d'amorçage ne le passe pas.
OPT_INSTALL_DEPS='false'
# Accord d'installation donné en amont, pour un lancement sans terminal. Ne
# vaut que pour l'installation : le retrait reste une décision non posée, donc
# les outils sont conservés.
OPT_ASSUME_YES='false'

usage() {
  sed -n '2,50p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      scan) shift ;;
      --quick) PROFILE='quick'; shift ;;
      --full) PROFILE='full'; shift ;;
      --stress) PROFILE='stress'; shift ;;
      --security) PROFILE='security'; shift ;;
      --anonymize) OPT_ANONYMIZE='true'; shift ;;
      --public-ip) OPT_PUBLIC_IP='true'; shift ;;
      --no-public-ip) OPT_PUBLIC_IP='false'; shift ;;
      --stdout) OPT_STDOUT='true'; shift ;;
      --no-markdown) OPT_NO_MARKDOWN='true'; shift ;;
      --output-dir)
        [ $# -ge 2 ] || die '--output-dir attend un chemin.'
        OUTPUT_DIR=$2; OPT_OUTPUT_DIR_EXPLICIT='true'; shift 2
        ;;
      --upload)
        OPT_UPLOAD='true'; shift
        ;;
      --public)
        # N'implique pas `--upload` : publier ce qu'on n'envoie pas n'a pas de
        # sens, et le déduire silencieusement ferait partir un rapport que
        # l'utilisateur croyait garder local. Le refus est explicite, plus bas.
        OPT_PUBLIC='true'; shift
        ;;
      --private)
        # Le symétrique, et il exige `--upload` pour la même raison : une portée
        # décrit ce qu'on fait d'un envoi, pas d'un fichier qui reste sur place.
        OPT_PRIVATE='true'; shift
        ;;
      --retry-upload)
        # Renvoie un rapport déjà produit, sans relancer la collecte. C'est la
        # sortie d'un envoi qui a échoué : le rapport existe, seule sa remise
        # a manqué. L'API déduplique, un renvoi de trop est donc sans effet.
        [ $# -ge 2 ] || die '--retry-upload attend le chemin d’un rapport JSON.'
        [ -f "$2" ] || die "Rapport introuvable : $2"
        CMD='retry-upload'; OPT_RETRY_PATH=$2; OPT_UPLOAD='true'; shift 2
        ;;
      --skip)
        # Écarte une section de la collecte. L'absence est **déclarée** dans
        # `collection.skippedSections`, jamais tue : un rapport qui tairait ce
        # qu'on n'a pas regardé se lirait comme un rapport où il n'y avait rien.
        #
        # Un nom inconnu est refusé plutôt qu'ignoré. Accepter `--skip storag`
        # sans rien dire collecterait le stockage tout en laissant croire le
        # contraire — la faute la plus coûteuse que cette option puisse faire.
        [ $# -ge 2 ] || die '--skip attend un nom de section (voir --help).'
        section_exists "$2" ||
          die "Section inconnue : $2. Sections valides : $(all_sections | paste -sd' ' -)"
        SKIP_SECTIONS="${SKIP_SECTIONS} $2"
        shift 2
        ;;
      --install-deps)
        # Ne déclenche rien à lui seul : `provision_enabled` vérifie les trois
        # autres conditions, et refuse en le disant si l'une manque.
        # shellcheck disable=SC2034 # lue par provision_decide, dans provision.sh.
        OPT_INSTALL_DEPS='true'; shift
        ;;
      --assume-yes | --yes | -y)
        # shellcheck disable=SC2034 # lue par provision_consent, dans provision.sh.
        OPT_ASSUME_YES='true'; shift
        ;;
      --benchmark) OPT_BENCHMARK='true'; shift ;;
      --quiet) console_verbosity 'quiet'; shift ;;
      --verbose) console_verbosity 'verbose'; shift ;;
      --monitor)
        [ $# -ge 2 ] || die '--monitor attend une durée en secondes.'
        [[ $2 =~ ^[0-9]+$ ]] || die '--monitor attend un nombre entier de secondes.'
        [ "$2" -le 3600 ] || die '--monitor est plafonné à 3600 secondes.'
        OPT_MONITOR_SECONDS=$2; shift 2
        ;;
      --api-url)
        [ $# -ge 2 ] || die '--api-url attend une URL.'
        OPT_API_URL=$2; shift 2
        ;;
      --proxy)
        # curl lit déjà `https_proxy` de lui-même : cette option existe pour le
        # cas où l'on ne veut pas — ou ne peut pas — toucher à l'environnement,
        # et pour rendre le choix visible dans la commande plutôt que caché
        # dans un shell. Elle l'emporte sur les variables, comme `-Proxy` côté
        # Windows : c'est le plus explicite qui gagne.
        [ $# -ge 2 ] || die '--proxy attend une adresse, par exemple http://proxy.local:8080.'
        OPT_PROXY=$2; shift 2
        ;;
      --no-proxy)
        # Ignore un proxy déclaré par l'environnement, pour cet envoi seulement.
        # Sur un poste où `https_proxy` est posé pour tout le monde alors que
        # l'API est joignable en direct, c'était la seule chose qui manquait.
        OPT_NO_PROXY='true'; shift
        ;;
      --claim)
        [ $# -ge 2 ] || die '--claim attend un code de rattachement.'
        # Le code prouve qu'on a la main sur cette machine : il n'a de sens
        # qu'avec un envoi, puisque c'est l'envoi qui le présente.
        OPT_CLAIM_CODE=$2; OPT_UPLOAD='true'; shift 2
        ;;
      --network-test)
        # Diagnostic seul : il n'implique **pas** `--upload`, et ne collecte
        # rien. Un test de connectivité qui lancerait un audit au passage
        # obligerait à choisir entre savoir et ne pas auditer.
        CMD='network-test'; shift
        ;;
      --capabilities) CMD='capabilities'; shift ;;
      --version | version)
        printf 'SysAudit scanner Linux %s (schéma %s)\n' "$SCANNER_VERSION" "$SCHEMA_VERSION"
        exit 0
        ;;
      -h | --help | help) usage; exit 0 ;;
      *) die "Option inconnue : $1 (voir --help)" ;;
    esac
  done
}

# --- Assemblage du rapport --------------------------------------------------

build_report() {
  local started_at=$1
  local system_json='' os_json='' capabilities_json=''
  local motherboard_json='' bios_json='' cpus_json='' memory_json='' gpus_json='' audio_json=''
  local sensors_json='' power_json='' storage_json='' network_json='' devices_json=''
  local software_json='' drivers_json='' startup_json='' security_json='' virtualization_json=''
  local monitoring_json='' benchmark_json=''
  local stability_json='' boot_json='' shutdown_json='' events_json=''

  console_session "Niveau       : $(level_label "$(current_level)") ($(current_level))"
  console_session "Privilèges   : $([ "$(id -u)" -eq 0 ] && printf 'root' || printf 'utilisateur')"
  console_session "Anonymisation: $([ "$ANONYMIZE" = 'true' ] && printf 'activée' || printf 'désactivée')"
  console_session "Mode         : $(session_mode_label)"
  printf '\n' >&2

  capabilities_json=$(build_capabilities_json)

  # Nombre de collecteurs réellement exécutés pour ce profil. Il est déclaré
  # ici, contre le branchement qui le détermine, et un test vérifie que la
  # barre atteint bien 100 % — une divergence se verrait donc immédiatement.
  # La barre reçoit la **liste** des étapes, pas leur nombre : c'est ce qui lui
  # permet de peser chacune par son coût prévu. Une barre qui compte les étapes
  # atteint 95 % en quelques secondes puis ne bouge plus pendant le banc
  # d'essai, et l'utilisateur en conclut, raisonnablement, qu'elle est figée.
  progress_weights_set "$(collector_weights)"
  progress_start "$(collector_sections | tr '\n' ' ')"

  # Le canal des messages du scanner, distinct de l'erreur standard des outils
  # qu'il appelle. Sans lui, `run_collector` jette les deux ensemble et un banc
  # d'essai de dix-sept minutes se déroule dans un silence complet.
  console_open_log_fd

  # Chaque section passe par `run_collector` : un collecteur qui échoue produit
  # une section absente **avec sa raison** dans `collection.issues`, et l'audit
  # se poursuit. Une carte réseau exotique ne doit pas coûter le rapport entier.
  system_json=$(run_collector system collect_system)
  os_json=$(run_collector os collect_os)

  # Sans identité système ni OS, le rapport ne serait pas valide : ce sont les
  # deux seules sections obligatoires du schéma.
  [ -n "$system_json" ] || die 'Collecte de l’identité système impossible : rapport non produit.'
  [ -n "$os_json" ] || die 'Collecte du système d’exploitation impossible : rapport non produit.'

  # L'ordre de ces lignes est celui du rapport ; ce qu'elles collectent, et à
  # quelle profondeur, est décidé par la matrice de `lib/core/levels.sh`. Une
  # section non prévue au niveau courant n'est pas silencieusement absente :
  # `level_section` la déclare, avec le niveau qui l'aurait collectée.
  motherboard_json=$(level_section motherboard collect_motherboard)
  bios_json=$(level_section bios collect_bios)
  cpus_json=$(level_section cpus collect_cpus)
  memory_json=$(level_section memory collect_memory)
  gpus_json=$(level_section gpus collect_gpus)
  audio_json=$(level_section audio collect_audio)
  power_json=$(level_section power collect_power)
  storage_json=$(level_section storage collect_storage)

  # `sensors` passe **après** `gpus` et `storage`, et cet ordre est un contrat.
  #
  # Les deux relèvent des températures que `collect_sensors` ne sait pas lire
  # autrement : la sonde d'un GPU NVIDIA n'existe que dans `nvidia-smi`, et celle
  # d'un disque derrière un contrôleur USB ou RAID n'existe que dans SMART. Elles
  # sont déposées dans le journal thermique, que ce collecteur ramasse pour
  # rendre une liste unique.
  #
  # Déplacer cette ligne plus haut ne casserait rien de visible : les
  # températures de disques et de GPU disparaîtraient simplement de la section
  # capteurs, ce qui se lirait comme une machine qui ne les expose pas.
  # L'ordre du rapport, lui, ne dépend pas d'ici : il est fixé à l'assemblage.
  sensors_json=$(level_section sensors collect_sensors)

  network_json=$(level_section network collect_network)
  devices_json=$(level_section devices collect_devices)
  drivers_json=$(level_section drivers collect_drivers)
  software_json=$(level_section software collect_software)
  startup_json=$(level_section startup collect_startup)
  security_json=$(level_section security collect_security)

  # La virtualisation ne passe pas par `run_collector` : une machine sans
  # hyperviseur ni conteneur est un cas normal, pas un collecteur en échec.
  #
  # Elle ne peut pas pour autant disparaître sans un mot. Jusqu'au 2026-08-16,
  # une machine sans conteneur produisait un rapport où la clé `virtualization`
  # n'existait pas, ne figurait pas dans `skippedSections` et n'avait aucune
  # issue : les cent quinze champs de la plus grosse section du schéma étaient
  # indistinguables d'une collecte jamais tentée. « Nous avons regardé, il n'y
  # avait rien » et « nous n'avons pas regardé » se lisaient pareil — la
  # confusion que ce produit s'interdit partout ailleurs.
  if level_collects virtualization; then
    virtualization_json=$(section virtualization "$(collect_virtualization)")
    if [ -z "$virtualization_json" ]; then
      record_skipped 'virtualization'
      record_issue 'virtualization' 'warning' \
        'Ni hyperviseur, ni conteneur, ni cluster sur cette machine : rien à inventorier.' \
        '' 'NOT_APPLICABLE'
    fi
  else
    record_level_skip 'virtualization'
  fi

  # `events` passe **avant** `stability` : le journal n'est parcouru qu'une
  # fois, et les compteurs par catégorie de `stability` relisent le résultat de
  # ce parcours. Inverser les deux lignes ne casserait rien de visible — les
  # compteurs deviendraient simplement tous inconnus, ce qui se lirait comme une
  # machine dont le journal est illisible.
  events_json=$(level_section events collect_events)
  stability_json=$(level_section stability collect_stability)
  boot_json=$(level_section boot collect_boot)
  shutdown_json=$(level_section shutdown collect_shutdown)

  # Le banc d'essai charge volontairement la machine : seul le niveau Poussée
  # le prévoit, et `--benchmark` permet de le demander explicitement ailleurs.
  if level_collects benchmark || [ "$OPT_BENCHMARK" = 'true' ]; then
    benchmark_json=$(section benchmark "$(run_collector benchmark collect_benchmark)")
  else
    record_level_skip 'benchmark'
  fi

  # L'observation dans la durée n'a lieu que si elle a été demandée : elle
  # rallonge le scan de sa propre durée.
  if [ "$OPT_MONITOR_SECONDS" -gt 0 ]; then
    monitoring_json=$(section monitoring \
      "$(run_collector monitoring collect_monitoring "$OPT_MONITOR_SECONDS")")
  else
    # Déclarer la section sans dire pourquoi la laissait apparaître au rapport
    # sous « motif non précisé », à côté de sections dont le motif est connu :
    # le lecteur ne pouvait pas distinguer une absence expliquée d'un oubli du
    # scanner. L'observation ne dépend pas du niveau, mais d'une demande.
    record_skipped 'monitoring'
    record_issue 'monitoring' 'warning' \
      'Observation dans la durée non demandée : relancer avec --monitor <secondes>.' \
      '' 'NOT_REQUESTED'
  fi

  # Le firmware disponible en amont exige une source constructeur que le scanner
  # n'interroge pas : la section est explicitement déclarée non collectée plutôt
  # qu'omise sans explication.
  record_skipped 'firmware'
  record_issue 'firmware' 'warning' \
    'Aucun scanner ne collecte cette section : elle exige une source constructeur que SysAudit n’interroge pas.' \
    '' 'UNSUPPORTED'

  # Mesurée avant le bilan console pour que le compte d'incidents affiché tienne
  # compte d'une durée non mesurable.
  local duration=''
  duration=$(audit_duration_ms "$started_at" "$(clock_ms)")
  if [ -z "$duration" ]; then
    record_issue 'report.durationMs' 'warning' \
      'Durée d’audit non mesurable : l’horloge de la machine a sauté pendant l’audit.' \
      'clock' 'NOT_AVAILABLE'
  fi

  progress_end
  console_summary "$system_json" "$os_json" "$cpus_json" "$memory_json" \
    "$storage_json" "$network_json" "$virtualization_json" "$(collection_issue_count)"

  local report_meta=''
  report_meta=$(json_object \
    "$(jf_str localId "scan-$(date -u +%Y%m%dT%H%M%SZ)")" \
    "$(jf_str generatedAt "$(iso_now)")" \
    "$(if [ -n "$duration" ]; then jf_raw durationMs "$duration"; fi)" \
    "$(jf_str scannerKind "$([ "$CAP_PROXMOX" = 'true' ] && printf 'proxmox' || printf 'linux')")" \
    "$(jf_str profile "$PROFILE")" \
    "$(jf_raw anonymized "$ANONYMIZE")" \
    "$(jf_raw anonymizedCategories "$(anon_categories_json)")" \
    "$(jf_str collectionMode "$(collection_mode)")")

  # Le retrait est proposé ici, et pas en fin de `run_scan`.
  #
  # La collecte est terminée — les outils ont servi, l'utilisateur a vu le
  # résumé — mais `collection` n'est pas encore sérialisée. C'est la seule
  # fenêtre où le sort réel de chaque outil peut entrer dans le rapport écrit.
  # Proposer le retrait après l'écriture produirait un rapport annonçant
  # `NOT_APPLICABLE` sur des outils effectivement désinstallés.
  #
  # Les invites partent sur stderr, comme tout le reste de la console : stdout
  # de cette fonction est le JSON, et il le reste.
  provision_offer_removal

  local collection=''
  collection=$(build_collection_json)

  json_object \
    "$(jf_str schemaVersion "$SCHEMA_VERSION")" \
    "$(jf_str scannerVersion "$SCANNER_VERSION")" \
    "$(jf_raw report "$report_meta")" \
    "$(jf_raw capabilities "$capabilities_json")" \
    "$(jf_raw system "$system_json")" \
    "$(jf_raw os "$os_json")" \
    "$motherboard_json" \
    "$bios_json" \
    "$cpus_json" \
    "$memory_json" \
    "$gpus_json" \
    "$audio_json" \
    "$sensors_json" \
    "$power_json" \
    "$storage_json" \
    "$network_json" \
    "$devices_json" \
    "$drivers_json" \
    "$software_json" \
    "$startup_json" \
    "$security_json" \
    "$virtualization_json" \
    "$stability_json" \
    "$boot_json" \
    "$shutdown_json" \
    "$events_json" \
    "$monitoring_json" \
    "$benchmark_json" \
    "$(section collection "$collection")"
}

# --- Sorties ----------------------------------------------------------------

show_capabilities() {
  detect_capabilities
  printf '%s\n' "$(build_capabilities_json)"
}

run_scan() {
  local started_at=''
  started_at=$(clock_ms)

  init_collection_journal

  # L'inventaire des outils passe **avant** toute autre chose : il doit décrire
  # la machine telle qu'elle était en arrivant. Fait après une installation, il
  # ne saurait plus distinguer ce qui appartenait à l'utilisateur de ce que
  # SysAudit vient d'ajouter — et c'est cette distinction qui interdit de
  # supprimer le premier.
  provision_inventory

  # L'offre passe **après** l'inventaire et **avant** la décision.
  #
  # Après, parce que l'inventaire doit décrire la machine telle qu'elle est
  # arrivée : c'est lui qui distingue ce qui appartenait à l'utilisateur de ce
  # que SysAudit ajoute, et donc ce qu'il s'interdit de retirer ensuite.
  #
  # Avant, parce qu'un outil installé une fois la collecte finie n'enrichirait
  # que le prochain audit. La question posée ici sert celui qu'on est en train
  # de faire.
  #
  # Elle ne se pose qu'à un humain devant un terminal ; sans terminal, elle
  # n'existe pas et le conseil de fin de scan reste le seul chemin.
  provision_offer || true

  if provision_enabled; then
    log_info 'Audit en lecture seule, sauf installation d’outils : chacune sera demandée.'
    provision_apply
  else
    log_info 'Audit en lecture seule — aucune écriture sur cette machine.'
  fi

  detect_capabilities
  anon_describe

  local json=''
  json=$(build_report "$started_at")

  if [ "$OPT_STDOUT" = 'true' ]; then
    printf '%s\n' "$json"
    # Le conseil part sur stderr : stdout reste du JSON pur, canalisable.
    dependency_report
    return 0
  fi

  # Un chemin demandé explicitement est respecté : si son répertoire refuse
  # l'écriture, l'erreur remonte plutôt que d'écrire ailleurs en silence.
  #
  # Sans demande, c'est le dossier personnel de l'utilisateur qui a lancé
  # l'audit — pas le répertoire courant, qui vaut `/root`, `/` ou un répertoire
  # de travail temporaire aussi souvent qu'autre chose. Un dossier personnel
  # absent ou fermé à l'écriture — compte de service, `HOME` non défini — ne
  # fait pas perdre un audit qui a réussi : le répertoire temporaire prend le
  # relais, et le chemin retenu est affiché.
  if [ -z "$OUTPUT_DIR" ] || ! mkdir -p "$OUTPUT_DIR" 2>/dev/null || [ ! -w "$OUTPUT_DIR" ]; then
    if [ "$OPT_OUTPUT_DIR_EXPLICIT" = 'true' ]; then
      die "Répertoire de sortie non inscriptible : $OUTPUT_DIR"
    fi
    log_warn "Dossier personnel indisponible (${OUTPUT_DIR:-non défini}) : rapport écrit dans ${TMPDIR:-/tmp}."
    OUTPUT_DIR="${TMPDIR:-/tmp}"
  fi

  local base='' json_path='' md_path=''
  base=$(report_basename)
  json_path="$OUTPUT_DIR/$base.json"
  md_path="$OUTPUT_DIR/$base.md"

  # Le document est-il seulement du JSON ?
  #
  # La question se pose **avant** l'écriture, pas au dépôt. Un document mal
  # formé écrit sur le disque repart avec l'utilisateur, et son refus arrive des
  # heures plus tard, sur un poste qui n'est plus celui de la machine auditée —
  # là où plus personne ne peut relancer la collecte.
  #
  # Ce contrôle ne remplace pas la validation de schéma, qui reste à l'API : il
  # attrape la chaîne mal échappée, pas le champ manquant. Sans analyseur
  # disponible, il ne conclut rien plutôt que de conclure « bien formé ».
  local wellformed=''
  wellformed=$(json_is_wellformed "$json")
  case "$wellformed" in
    ko)
      die 'Le rapport produit n’est pas du JSON valide : rien n’a été écrit. Relancez avec SYSAUDIT_DEBUG=1 et signalez le cas.'
      ;;
    inconnu)
      log_debug 'Aucun analyseur JSON disponible : le rapport n’a pas été vérifié avant écriture.'
      ;;
  esac

  # Le rapport peut contenir des données personnelles : il est créé avec des
  # droits restreints plutôt que selon l'umask de l'appelant.
  local previous_umask=''
  previous_umask=$(umask)
  umask 077
  printf '%s\n' "$json" >"$json_path"
  [ "$OPT_NO_MARKDOWN" = 'true' ] || write_markdown_report "$md_path"
  umask "$previous_umask"

  # Rendre le rapport à qui a lancé l'audit.
  #
  # `umask 077` protège le fichier, et sous `sudo` il le protège **de son
  # propriétaire légitime** : le rapport sort en `root:root` mode 600, dans le
  # dossier personnel de l'utilisateur, qui ne peut alors ni le lire, ni le
  # copier, ni le déposer.
  #
  # Le symptôme était trompeur au possible. Le scanner annonçait « Rapport
  # conservé dans : /home/…/sysaudit-poste.json », et le dépôt par le navigateur
  # échouait sur « Failed to fetch » — une erreur réseau, alors que rien
  # n'était en cause côté réseau : le navigateur, lancé par l'utilisateur,
  # n'avait tout simplement pas le droit de lire le fichier qu'on venait de lui
  # désigner.
  #
  # Le fichier revient donc à l'utilisateur d'origine, **sans** changer ses
  # droits : il reste en 600, lisible par son seul propriétaire — qui devient
  # enfin un humain plutôt que `root`.
  restore_report_ownership "$json_path"
  [ "$OPT_NO_MARKDOWN" = 'true' ] || restore_report_ownership "$md_path"

  log_info 'Rapport généré :'
  log_ok "$json_path"
  [ "$OPT_NO_MARKDOWN" = 'true' ] || log_ok "$md_path"

  local issue_count=''
  issue_count=$(collection_issue_count)
  if [ "$issue_count" -gt 0 ]; then
    log_warn "$issue_count information(s) non collectée(s) : la raison figure dans le JSON."
  fi

  # Ce qui manquait, et quoi installer pour l'obtenir. Le scanner nomme, il
  # n'installe pas : voir docs/adr/0006-dependances-externes.md.
  dependency_report

  benchmark_hint

  if [ "$OPT_UPLOAD" = 'true' ]; then
    upload_report "$json_path"
  else
    log_info 'Aucun envoi effectué. Utilisez --upload pour publier ce rapport.'
  fi

}

# Dire que la mesure de performances existe, à qui vient de terminer un audit
# sans elle.
#
# ## Pourquoi une ligne d'information, et pas une invite
#
# Le banc d'essai n'appartient qu'au niveau Poussée, et c'est une bonne règle :
# il charge la machine plusieurs minutes, et personne ne doit se le voir imposer
# par un défaut. Mais le silence a un coût, et il se mesure — au 2026-08-27, le
# parc comptait **36 audits `--full` et pas une seule mesure**. Leurs auteurs
# avaient demandé « complet » ; rien ne leur a jamais dit que la mesure ne
# faisait pas partie du complet, ni comment l'obtenir.
#
# Une invite interactive corrigerait le chiffre en déplaçant le problème :
# proposer une charge de plusieurs minutes à la fin d'un audit, c'est la faire
# accepter par lassitude. Le scanner nomme donc ce qui manque et **s'arrête
# là** — exactement ce que `dependency_report` fait des outils absents, et pour
# la même raison.
#
# ## Ce qui vaut un silence
#
# Un audit rapide, dont la brièveté est tout l'objet ; une section écartée à la
# main, qui est déjà une réponse ; et un banc d'essai qui a tourné, qui n'a rien
# à réclamer.
benchmark_hint() {
  [ "$OPT_BENCHMARK" = 'true' ] && return 0
  level_collects benchmark && return 0
  section_excluded benchmark && return 0
  [ "$(current_level)" = 'quick' ] && return 0

  log_info 'Aucune mesure de performances dans cet audit.'
  log_info '--benchmark mesure processeur, mémoire et stockage — la machine est chargée pendant la mesure.'
}

# --- Résumé de fin ----------------------------------------------------------
#
# Le scanner ne doit **jamais** annoncer qu'un audit est enregistré tant que
# l'API ne l'a pas confirmé. Ces deux résumés sont les seules formulations
# autorisées, et ils disent exactement ce qui s'est passé.

# Envoi accepté : le rapport est en base, avec son identifiant et son lien.
upload_ok_summary() {
  local report_id=$1 url=$2 duplicate=$3

  printf '\n' >&2
  log_ok 'Audit terminé'
  if [ "$duplicate" = 'true' ]; then
    log_ok 'Rapport déjà enregistré dans PostgreSQL (aucun doublon créé)'
  else
    log_ok 'Rapport enregistré dans PostgreSQL'
  fi
  [ -n "$report_id" ] && log_ok "Identifiant : $report_id"
  [ -n "$url" ] && log_ok "Lien : $url"
}

# Envoi refusé ou impossible : l'audit existe, en local, et se renvoie.
upload_failed_summary() {
  local json_path=$1 reason=$2 detail=$3

  printf '\n' >&2
  log_warn 'Audit terminé localement'
  log_error "Échec de l’envoi vers l’API ($reason)"
  [ -n "$detail" ] && log_warn "Réponse : $(printf '%s' "$detail" | head -c 300)"
  log_warn "Rapport conservé dans : $json_path"
  printf '\n' >&2
  log_info 'Pour réessayer une fois l’API disponible :'
  log_info "  ./sysaudit.sh --retry-upload '$json_path' --api-url '${OPT_API_URL%/}'"
  printf '\n' >&2
  # La seconde issue, et la seule qui marche quand le réseau ne s'ouvrira pas.
  # Elle était vraie depuis le début et n'était dite nulle part : l'utilisateur
  # qui vient de heurter un pare-feu d'entreprise n'obtiendra pas de dérogation
  # dans l'heure, et réessayer ne changera rien.
  #
  # L'adresse du site n'est pas déduite de celle de l'API : les deux peuvent
  # vivre sur des hôtes distincts, et fabriquer une URL fausse enverrait sur une
  # page inexistante quelqu'un qui a déjà un problème.
  log_info 'Si ce réseau n’ouvrira pas, déposez le fichier depuis un poste connecté :'
  log_info '  page « Déposer un rapport » (/deposer) du site SysAudit'
  log_info 'Pour savoir ce qui bloque : ./sysaudit.sh --network-test'
}

# L'upload n'a jamais lieu sans `--upload` explicite, et jamais sans que
# l'utilisateur ait vu ce qui est envoyé (§101).
upload_report() {
  local json_path=$1

  [ -n "$OPT_API_URL" ] || die '--upload requiert --api-url (ou la variable SYSAUDIT_API_URL).'
  case "$OPT_API_URL" in
    https://*) : ;;
    http://localhost* | http://127.0.0.1*) log_warn 'Envoi en clair vers une adresse locale.' ;;
    http://10.* | http://192.168.* | http://172.1[6-9].* | http://172.2[0-9].* | http://172.3[0-1].*)
      log_warn 'Envoi en clair vers une adresse privée du réseau local.'
      ;;
    *) die "L'envoi exige HTTPS (URL fournie : $OPT_API_URL)." ;;
  esac

  has_cmd curl || die 'curl est requis pour l’envoi du rapport.'

  log_info "Contenu envoyé : le fichier $json_path, tel quel."
  [ "$ANONYMIZE" = 'true' ] ||
    log_warn 'Ce rapport n’est pas anonymisé. Relancez avec --anonymize pour masquer les identifiants.'

  local bootstrap_path='linux'
  [ "${CAP_PROXMOX:-false}" = 'true' ] && bootstrap_path='proxmox'

  # Le proxy emprunté est dit avant l'essai, jamais après : quand l'envoi
  # échoue derrière un proxy authentifié, savoir lequel a été tenté est la
  # première chose qu'on cherche.
  #
  # `curl_proxy_args` traduit `--proxy` et `--no-proxy` en arguments curl ; sans
  # eux, curl lit les variables d'environnement de lui-même, et l'affichage
  # ci-dessous ne change rien à ce qu'il fait — seulement à ce qu'on en sait.
  local proxy_args=()
  mapfile -t proxy_args < <(curl_proxy_args)

  local declared_proxy=''
  if [ "$OPT_NO_PROXY" = 'true' ]; then
    log_info 'Proxy ignoré pour cet envoi (--no-proxy).'
  elif [ -n "$OPT_PROXY" ]; then
    log_info "Proxy : $(mask_proxy_credentials "$OPT_PROXY")"
  else
    declared_proxy=$(proxy_declared)
    [ -n "$declared_proxy" ] && log_info "Proxy déclaré : $declared_proxy"
  fi

  # L'amorçage est **la première requête qui sort**, donc celle qu'un proxy
  # refuse en premier. Son statut doit donc être nommé aussi précisément que
  # celui de l'envoi.
  #
  # `-f` a été retiré pour cela : il range tous les statuts d'erreur derrière le
  # code de sortie 22, et le motif exact était perdu — un 407 devenait « l'API a
  # répondu par une erreur », c'est-à-dire rien. Mesuré le 2026-08-12 par la
  # validation des scénarios, qui a trouvé exactement ce trou.
  local bootstrap='' bootstrap_body='' bootstrap_status='' bootstrap_code=0
  bootstrap_body=$(mktemp /tmp/sysaudit-bootstrap-XXXXXX.json)
  bootstrap_status=$(curl -sSL -o "$bootstrap_body" -w '%{http_code}' --max-time 30 \
    "${proxy_args[@]}" \
    -H "User-Agent: SysAudit-Scanner/$SCANNER_VERSION" \
    "${OPT_API_URL%/}/api/audit/bootstrap/$bootstrap_path") || bootstrap_code=$?

  if [ "$bootstrap_code" -ne 0 ]; then
    rm -f "$bootstrap_body"
    upload_failed_summary "$json_path" "$(curl_failure_label "$bootstrap_code")" \
      "$(network_failure_hint "$bootstrap_code")"
    return "$EXIT_TRANSPORT_FAILED"
  fi

  if [ "$bootstrap_status" != '200' ]; then
    rm -f "$bootstrap_body"
    upload_failed_summary "$json_path" "$(http_failure_label "$bootstrap_status")" \
      'refus avant l’envoi (amorçage de session)'
    local bootstrap_hint=''
    bootstrap_hint=$(network_failure_hint "$bootstrap_status")
    [ -n "$bootstrap_hint" ] && log_info "$bootstrap_hint"
    return "$EXIT_TRANSPORT_FAILED"
  fi

  bootstrap=$(cat "$bootstrap_body")
  rm -f "$bootstrap_body"

  local session_id='' upload_token=''
  session_id=$(printf '%s' "$bootstrap" | sed -nE 's/.*"sessionId"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')
  upload_token=$(printf '%s' "$bootstrap" | sed -nE 's/.*"uploadToken"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')
  [ -n "$session_id" ] || die "Réponse bootstrap invalide : $bootstrap"
  [ -n "$upload_token" ] || die "Réponse bootstrap invalide : $bootstrap"

  # Le code de rattachement voyage en en-tête, jamais dans le rapport : le
  # rapport est archivé et repartagé, un code n'a rien à y faire.
  local claim_header=()
  [ -n "$OPT_CLAIM_CODE" ] && claim_header=(-H "X-Machine-Claim: $OPT_CLAIM_CODE")

  # La portée de publication voyage elle aussi en en-tête, et jamais dans le
  # rapport : elle décrit ce qu'on fait de cet envoi-ci, pas la machine. Un
  # rapport archivé puis renvoyé plus tard ne doit pas rejouer un choix de
  # publication pris un autre jour.
  #
  # `--private` est envoyé **explicitement**, et ce n'est pas une redondance :
  # sans en-tête, c'est le défaut de l'instance qui tranche, et il peut valoir
  # `PUBLIC`. Ne rien dire n'est donc pas demander le privé.
  local visibility_header=()
  [ "$OPT_PUBLIC" = 'true' ] && visibility_header=(-H 'X-Scan-Visibility: public')
  [ "$OPT_PRIVATE" = 'true' ] && visibility_header=(-H 'X-Scan-Visibility: private')

  local response_file='' http_code='' response='' send_code=0
  response_file=$(mktemp /tmp/sysaudit-upload-response-XXXXXX.json)
  http_code=$(curl -sS -o "$response_file" -w '%{http_code}' --max-time 60 \
    "${proxy_args[@]}" \
    -H 'Content-Type: application/json' \
    -H "User-Agent: SysAudit-Scanner/$SCANNER_VERSION" \
    -H "X-Audit-Session-Id: $session_id" \
    -H "X-Audit-Upload-Token: $upload_token" \
    "${claim_header[@]}" \
    "${visibility_header[@]}" \
    --data-binary "@$json_path" \
    "${OPT_API_URL%/}/api/v1/scans/upload") || send_code=$?
  if [ "$send_code" -ne 0 ]; then
    rm -f "$response_file"
    # Aucune réponse HTTP : la cause est dans le code de sortie de curl, et lui
    # seul distingue un nom qui ne résout pas d'un certificat refusé.
    upload_failed_summary "$json_path" "$(curl_failure_label "$send_code")" \
      "$(network_failure_hint "$send_code")"
    return "$EXIT_TRANSPORT_FAILED"
  fi
  response=$(cat "$response_file")
  rm -f "$response_file"

  case "$http_code" in
    200|201) ;;
    *)
      # L'audit n'est pas perdu : le JSON est deja ecrit sur le disque. On le
      # dit, on donne la commande de renvoi, et on sort en erreur — sans jamais
      # laisser croire que le rapport est enregistre.
      #
      # Le statut est nommé plutôt que rendu brut : « HTTP 407 » ne dit pas à
      # qui s'adresser, « le proxy exige une authentification » le dit.
      upload_failed_summary "$json_path" "$(http_failure_label "$http_code")" "$response"
      local hint=''
      hint=$(network_failure_hint "$http_code")
      [ -n "$hint" ] && log_info "$hint"
      return "$EXIT_TRANSPORT_FAILED"
      ;;
  esac

  local url=''
  url=$(printf '%s' "$response" | sed -nE 's/.*"absoluteUrl"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')
  if [ -z "$url" ]; then
    url=$(printf '%s' "$response" | sed -nE 's/.*"url"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')
    case "$url" in
      /*) url="${OPT_API_URL%/}$url" ;;
    esac
  fi
  if [ -z "$url" ]; then
    log_warn "Réponse inattendue de l'API : $response"
    return 0
  fi

  # Le dessin du QR vient de l'API. Seule la variante sans séquences ANSI est
  # lue ici : extraire des échappements `\u001b` avec sed serait fragile, et
  # l'encadrement noir-sur-blanc ci-dessous donne le même rendu lisible.
  local qr='' report_id=''
  qr=$(printf '%s' "$response" | sed -nE 's/.*"plain"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p')
  report_id=$(printf '%s' "$response" | sed -nE 's/.*"reportId"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')

  local duplicate='false'
  printf '%s' "$response" | grep -q '"duplicate"[[:space:]]*:[[:space:]]*true' && duplicate='true'

  upload_ok_summary "$report_id" "$url" "$duplicate"
  console_qr "$qr"
}

# Compte les collecteurs passant par `run_collector` au niveau courant.
#
# Le compte est déduit de la matrice plutôt que tenu à la main : la barre de
# progression ne peut donc plus se désynchroniser en ajoutant une section.
# `virtualization` en est retirée — elle ne passe pas par `run_collector`, une
# machine sans hyperviseur n'étant pas un échec de collecte.
collectors_for_profile() {
  # Le compte se déduit désormais de la **liste**, et non l'inverse : deux
  # calculs parallèles du même ensemble finiraient par diverger, et c'est
  # exactement ce que la barre ne doit pas faire.
  collector_sections | wc -w | tr -d ' '
}

# Les collecteurs passant par `run_collector`, nommés.
#
# La liste sert à deux choses qui exigent la même vérité : compter les étapes,
# et connaître le **coût prévu** de chacune. C'est ce second usage qui a motivé
# de la nommer — une barre pondérée a besoin de savoir quelles étapes elle va
# traverser avant la première, faute de quoi son dénominateur change en route.
collector_sections() {
  sections_for_level | awk '$0 != "virtualization"'

  # Le banc d'essai peut être demandé hors du niveau Poussée.
  if [ "$OPT_BENCHMARK" = 'true' ] && ! level_collects benchmark; then
    printf 'benchmark\n'
  fi

  if [ "$OPT_MONITOR_SECONDS" -gt 0 ]; then
    printf 'monitoring\n'
  fi
}

# Coûts prévus des étapes longues, sous la forme `nom=secondes`.
#
# Deux étapes seulement y figurent, et c'est délibéré : ce sont les deux dont la
# durée dépasse la seconde, et les deux dont on connaît le budget **avant** de
# les lancer. Les autres gardent le poids par défaut, ce qui revient à leur
# donner le même poids qu'entre elles — ce qui est exact, elles durent toutes à
# peu près pareil.
#
# Les chiffres ne sont pas des mesures mais des budgets, ceux-là mêmes que le
# banc d'essai et le suivi s'imposent. Une barre pondérée par des ordres de
# grandeur reste infiniment plus juste qu'une barre qui donne le même poids à
# une lecture de sysfs et à dix minutes de charge processeur.
collector_weights() {
  local weights=''

  if [ "$OPT_BENCHMARK" = 'true' ] || level_collects benchmark; then
    weights="benchmark=$(bench_estimated_seconds)"
  fi

  if [ "$OPT_MONITOR_SECONDS" -gt 0 ]; then
    weights="$weights monitoring=$OPT_MONITOR_SECONDS"
  fi

  printf '%s' "$weights"
}

# --- Point d'entrée ---------------------------------------------------------

CMD='scan'

main() {
  parse_args "$@"

  # Publier sans envoyer n'a pas de sens, et le déduire silencieusement ferait
  # partir un rapport que l'utilisateur croyait garder local. Le refus arrive
  # **avant** la collecte : découvrir la contradiction après trois minutes de
  # scan serait la pire façon de la signaler.
  if [ "$OPT_PUBLIC" = 'true' ] && [ "$OPT_UPLOAD" != 'true' ]; then
    die '--public exige --upload : on ne publie pas un rapport qu’on n’envoie pas.'
  fi

  if [ "$OPT_PRIVATE" = 'true' ] && [ "$OPT_UPLOAD" != 'true' ]; then
    die '--private exige --upload : la portée décrit un envoi, pas un fichier local.'
  fi

  # Les deux ensemble ne veulent rien dire, et en choisir un silencieusement
  # serait choisir à la place de quelqu'un qui vient d'exprimer deux intentions
  # contraires. Sur une portée de publication, ce n'est pas un risque à prendre.
  if [ "$OPT_PUBLIC" = 'true' ] && [ "$OPT_PRIVATE" = 'true' ]; then
    die '--public et --private s’excluent : choisissez la portée de cet envoi.'
  fi

  # Même raisonnement pour l'adresse publique, mais **seulement si elle a été
  # demandée** : elle se relève auprès de l'API, et sans adresse d'API il n'y a
  # personne à interroger. Le refus arrive lui aussi avant la collecte —
  # découvrir après trois minutes de scan que le seul champ pour lequel on avait
  # accepté une sortie réseau manque au rapport obligerait à tout recommencer.
  #
  # Le défaut `auto` ne passe pas par ici : sans API, il se contente de ne rien
  # relever. Faire échouer un audit hors ligne pour un champ que personne n'a
  # réclamé serait refuser de faire le travail qu'on sait faire.
  if [ "$OPT_PUBLIC_IP" = 'true' ] && [ -z "$OPT_API_URL" ]; then
    die '--public-ip requiert --api-url (ou la variable SYSAUDIT_API_URL) : l’adresse publique se relève auprès de l’API.'
  fi

  console_logo
  anon_init "$OPT_ANONYMIZE"

  # Le statut est **capturé**, pas laissé à `set -e`.
  #
  # Avec `set -e` seul, un `run_scan` rendant 2 faisait bien sortir le script en
  # 2 — mais par un chemin qui ne le disait nulle part, et qu'une simple
  # réécriture du `case` aurait cassé sans qu'aucun test ne s'en aperçoive. Le
  # code de sortie est une interface : il se décide ici, en toutes lettres.
  #
  # `|| status=$?` neutralise `set -e` pour cette commande précise : sans lui,
  # le script sortirait avant d'atteindre la ligne suivante.
  local status=0
  case "$CMD" in
    capabilities) show_capabilities || status=$? ;;
    network-test) network_test "$OPT_API_URL" || status=$? ;;
    scan) run_scan || status=$? ;;
    retry-upload) upload_report "$OPT_RETRY_PATH" || status=$? ;;
    *) die "Commande inconnue : $CMD" ;;
  esac

  # Un audit mené jusqu'au bout se termine sur 0, quoi qu'ait rendu la dernière
  # sonde exécutée : les sondes facultatives sont gardées là où elles sont
  # appelées — c'est ce que fait `run_cmd` en rendant 1 sans lever.
  #
  # Les trois valeurs possibles sont décrites dans `lib/core/transport.sh`. Un
  # statut inattendu est ramené à `EXIT_AUDIT_FAILED` plutôt que propagé tel
  # quel : inventer un quatrième code au détour d'un retour non prévu ferait
  # mentir la documentation, et un appelant lit cette documentation.
  case "$status" in
    "$EXIT_OK" | "$EXIT_TRANSPORT_FAILED") return "$status" ;;
    *) return "$EXIT_AUDIT_FAILED" ;;
  esac
}

main "$@"
exit $?
