#!/usr/bin/env bash
# Gestionnaire de dépendances : inventorier, informer, installer sur accord.
#
# Ce module est le **seul** endroit du scanner qui appelle un gestionnaire de
# paquets. Disperser cette logique dans les collecteurs rendrait impossible la
# seule garantie qui compte ici : qu'un outil déjà présent avant l'audit ne
# puisse jamais être supprimé.
#
# Il complète `dependencies.sh`, qui nomme, sans le remplacer : hors des quatre
# conditions de l'ADR 0008, ce module se contente d'inventorier en lecture seule
# et le conseil de `dependency_report` reste le seul chemin proposé.
#
# Les quatre conditions, telles que `provision_enabled` les applique :
#
#   1. `--install-deps` explicitement tapé — jamais déduit ;
#   2. niveau `full` ou `stress` — l'audit rapide et l'audit standard, ceux que
#      le site propose, n'installent rien ;
#   3. accord donné outil par outil, après affichage de ce qu'il est ;
#   4. terminal interactif, sauf `--assume-yes`.
#
# Décision et bornes : docs/adr/0008-installation-consentie-en-audit-administrateur.md.

# Journal des outils, une ligne JSON par outil. Rempli avant la collecte pour
# l'inventaire, complété après pour l'usage et le retrait.
PROVISION_JOURNAL=''
# Liste des outils de la table, encadrée d'espaces pour un test d'appartenance
# sans sous-processus depuis `run_cmd`.
# shellcheck disable=SC2034 # lue par run_cmd, dans core.sh.
PROVISION_TOOLS=' '
# Journal des outils réellement invoqués pendant la collecte.
PROVISION_USED_JOURNAL=''
# Journal du sort final des outils installés — retirés, conservés, ou dont le
# retrait a échoué.
PROVISION_REMOVAL_JOURNAL=''
# Décision d'installation, mémorisée : vide tant qu'elle n'a pas été posée,
# puis `allowed` ou `refused`.
PROVISION_DECISION=''
# Vrai lorsque l'accord vient d'une **offre acceptée au terminal** plutôt que du
# drapeau `--install-deps`. Il lève la borne de niveau, et lui seul : un « oui »
# tapé à la main est la volonté que cette borne cherchait à protéger.
PROVISION_OFFERED='false'

# --- Primitives, aux noms de la roadmap -------------------------------------

# isInstalled — l'outil répond-il sur cette machine ?
provision_is_installed() {
  has_cmd "${1-}"
}

# getInstalledVersion — version déclarée, ou rien.
#
# Aucun format n'est imposé aux outils : la première ligne de leur bannière est
# conservée telle quelle, tronquée. Tenter d'en extraire un numéro produirait
# une valeur fausse sur le premier outil qui n'a pas la forme attendue — et une
# version fausse est pire qu'une version absente.
provision_version() {
  local tool=${1-} raw=''
  provision_is_installed "$tool" || return 0

  case "$tool" in
    # `nvme --version` existe, mais `nvme version` est la forme documentée.
    nvme) raw=$(run_cmd "$tool" version) ;;
    # `ip -V`, `ss -V` : `--version` n'existe pas sur iproute2.
    ip | ss) raw=$(run_cmd "$tool" -V) ;;
    *) raw=$(run_cmd "$tool" --version) || raw=$(run_cmd "$tool" -V) ;;
  esac

  [ -n "$raw" ] || return 0
  printf '%s' "$raw" | head -n 1 | trim | cut -c1-120
}

# resolveSource — d'où viendrait cet outil.
#
# Toujours le dépôt de la distribution, jamais une URL : l'ADR 0008 interdit
# explicitement le téléchargement d'un binaire tiers, et cette fonction est le
# seul endroit qui pourrait en introduire un.
provision_source() {
  local family=${1-}
  case "$family" in
    debian) printf 'dépôts officiels Debian/Ubuntu (apt)' ;;
    rhel) printf 'dépôts officiels RHEL/Fedora (dnf)' ;;
    arch) printf 'dépôts officiels Arch (pacman)' ;;
    suse) printf 'dépôts officiels openSUSE/SLES (zypper)' ;;
    alpine) printf 'dépôts officiels Alpine (apk)' ;;
    *) printf 'aucune source connue pour cette distribution' ;;
  esac
}

# Commande d'installation non interactive de la famille.
#
# Séparée de `dependency_install_prefix`, qui sert à **afficher** une commande
# qu'un humain tapera : celle-ci s'exécute, et doit donc porter le drapeau qui
# évite une invite bloquante au milieu d'un audit.
provision_install_command() {
  case "${1-}" in
    debian) printf 'apt-get install -y --no-install-recommends' ;;
    rhel) printf 'dnf install -y' ;;
    arch) printf 'pacman -S --noconfirm' ;;
    suse) printf 'zypper --non-interactive install' ;;
    alpine) printf 'apk add --no-cache' ;;
  esac
  return 0
}

# Commande de retrait de la famille.
#
# Aucune ne retire les dépendances devenues orphelines : `apt autoremove` ou
# `pacman -Rs` peuvent emporter un paquet dont autre chose dépend encore, et
# le faire en fin d'audit sur une machine de production serait la pire chose
# que ce scanner puisse faire.
provision_uninstall_command() {
  case "${1-}" in
    debian) printf 'apt-get remove -y' ;;
    rhel) printf 'dnf remove -y' ;;
    arch) printf 'pacman -R --noconfirm' ;;
    suse) printf 'zypper --non-interactive remove' ;;
    alpine) printf 'apk del' ;;
  esac
  return 0
}

# --- Journal ----------------------------------------------------------------

# provision_record <outil> <paquet> <issue> <version> <méthode> <débloque> <erreur>
provision_record() {
  local tool=$1 package=${2-} outcome=$3 version=${4-} method=${5-} unlocks=${6-} error=${7-}
  [ -n "$PROVISION_JOURNAL" ] || return 0

  printf '%s\n' "$(json_object \
    "$(jf_str tool "$tool")" \
    "$(if [ -n "$package" ]; then jf_str package "$package"; fi)" \
    "$(jf_str outcome "$outcome")" \
    "$(if [ -n "$version" ]; then jf_str version "$version"; fi)" \
    "$(if [ -n "$method" ]; then jf_str method "$method"; fi)" \
    "$(if [ -n "$unlocks" ]; then jf_str unlocks "$unlocks"; fi)" \
    "$(if [ -n "$error" ]; then jf_str error "$error"; fi)")" >>"$PROVISION_JOURNAL"
  return 0
}

# Note qu'un outil de la table vient d'être invoqué.
#
# Appelée par `run_cmd`, donc sur le chemin chaud : elle n'ouvre aucun
# sous-processus et se contente d'une ligne ajoutée. Le dédoublonnage a lieu à
# la construction du JSON, pas ici.
provision_mark_used() {
  [ -n "$PROVISION_USED_JOURNAL" ] && printf '%s\n' "$1" >>"$PROVISION_USED_JOURNAL"
  return 0
}

# --- Inventaire d'avant-collecte --------------------------------------------

# detect — l'état de chaque outil de la table, avant que rien n'ait été touché.
#
# Cet inventaire tourne sur **tous** les audits, y compris ceux qui n'installent
# rien : il est en lecture seule, coûte un `command -v` par outil, et c'est lui
# qui rend la trace exploitable. Sans lui, un outil installé à la main trois
# minutes avant le scan serait indiscernable d'un outil installé par SysAudit,
# et deviendrait donc supprimable — ce que l'ADR 0008 interdit.
provision_inventory() {
  [ -n "$PROVISION_JOURNAL" ] || return 0

  local tool='' family='' package='' version='' seen=' '
  family=$(dependency_family)

  while read -r tool; do
    [ -n "$tool" ] || continue
    # La liste n'est publiée qu'à la sortie de cette boucle. `provision_version`
    # passe par `run_cmd`, qui marque l'usage : la remplir au fil de l'eau
    # ferait passer pour « utilisé par la collecte » tout outil dont on vient
    # de lire la bannière de version.
    seen="${seen}${tool} "
    package=$(dependency_package "$tool" "$family")

    if provision_is_installed "$tool"; then
      version=$(provision_version "$tool")
      provision_record "$tool" "$package" 'PRESENT_BEFORE' "$version" '' \
        "$(dependency_unlocks "$tool")" ''
    else
      # `NOT_OFFERED` est l'état par défaut de tout outil absent. Il devient
      # `INSTALLED`, `DECLINED` ou `INSTALL_FAILED` seulement si la proposition
      # a réellement eu lieu — et `provision_apply` réécrit alors la ligne.
      provision_record "$tool" "$package" 'NOT_OFFERED' '' '' \
        "$(dependency_unlocks "$tool")" ''
    fi
  done < <(printf '%s' "$DEPENDENCY_TABLE" | awk 'NF { print $1 }')

  # shellcheck disable=SC2034 # lue par run_cmd, dans core.sh.
  PROVISION_TOOLS=$seen
  return 0
}

# --- Les quatre conditions --------------------------------------------------

# L'installation est-elle permise pour cet audit ?
#
# Le refus est **silencieux et sans reproche** quand le drapeau n'a pas été
# donné : c'est le cas normal, pas une anomalie. Il est expliqué dans les
# autres cas, sans quoi l'utilisateur croirait le drapeau pris en compte.
provision_enabled() {
  # Décision mémorisée : trois appelants la posent, et une explication répétée
  # trois fois se lirait comme trois refus différents.
  case "$PROVISION_DECISION" in
    allowed) return 0 ;;
    refused) return 1 ;;
  esac

  if provision_decide; then
    PROVISION_DECISION='allowed'
    return 0
  fi
  PROVISION_DECISION='refused'
  return 1
}

# Ce que cet audit fera subir à la machine, en une ligne d'en-tête.
#
# L'en-tête annonçait « lecture seule — aucune écriture sur cette machine » à
# tous les audits, y compris juste après avoir écrit qu'une installation allait
# être proposée, et y compris au niveau Poussée dont le banc d'essai écrit un
# fichier temporaire. Deux lignes de la même console se contredisaient ; celle
# qui rassurait était la fausse.
#
# La phrase est construite ici parce que c'est ici que la décision
# d'installation est connue. Elle est appelée après `provision_enabled`, dont
# la décision est mémorisée : elle ne repose donc jamais que sur ce qui a été
# réellement décidé.
session_mode_label() {
  local writes='' installs=''

  # Le banc d'essai est la seule écriture du produit : un fichier temporaire,
  # supprimé après la mesure. `--benchmark` permet de le demander hors du
  # niveau Poussée, d'où la double condition — la même qu'au branchement.
  if level_collects benchmark || [ "${OPT_BENCHMARK:-false}" = 'true' ]; then
    writes='oui'
  fi
  provision_enabled && installs='oui'

  if [ -n "$writes" ] && [ -n "$installs" ]; then
    printf 'banc d’essai — fichier temporaire écrit puis supprimé, et installation d’outils sur accord'
  elif [ -n "$writes" ]; then
    printf 'lecture seule, sauf le fichier temporaire du banc d’essai, supprimé après la mesure'
  elif [ -n "$installs" ]; then
    printf 'lecture seule, sauf installation d’outils : chacune sera demandée'
  else
    printf 'lecture seule — aucune écriture sur cette machine'
  fi
}

provision_decide() {
  [ "${OPT_INSTALL_DEPS:-false}" = 'true' ] || return 1

  # Le niveau ne borne que le **drapeau**. Une offre acceptée devant le terminal
  # vaut à tous les niveaux : la restriction existait pour qu'un audit lancé
  # depuis le site ne modifie rien sans qu'on l'ait voulu, et un « oui » tapé à
  # la main est précisément cette volonté.
  if [ "${PROVISION_OFFERED:-false}" != 'true' ]; then
    case "$(current_level)" in
      full | stress) ;;
      *)
        log_warn '--install-deps ignoré : réservé aux niveaux Complète (--full) et Poussée (--stress).'
        return 1
        ;;
    esac
  fi

  if [ "$(id -u 2>/dev/null || printf '1')" != '0' ]; then
    log_warn '--install-deps ignoré : l’installation de paquets demande les privilèges root.'
    return 1
  fi

  if [ -z "$(dependency_family)" ]; then
    log_warn '--install-deps ignoré : aucun gestionnaire de paquets connu sur cette machine.'
    return 1
  fi

  # Le terminal de contrôle, et non l'entrée standard : sous `curl … | bash`,
  # celle-ci porte le script. La garde `[ -t 0 ]` rendait donc l'installation
  # consentie inatteignable par le chemin d'installation officiel.
  if [ "${OPT_ASSUME_YES:-false}" != 'true' ] && ! provision_tty && [ ! -t 0 ]; then
    log_warn '--install-deps ignoré : pas de terminal pour demander l’accord (voir --assume-yes).'
    return 1
  fi

  return 0
}

# L'offre faite quand rien n'a été demandé.
#
# ## Ce qu'elle change, et à quelle décision elle touche
#
# L'ADR 0008 pose quatre conditions cumulatives à toute installation. Deux
# d'entre elles rendaient l'offre invisible à qui ne connaît pas le produit : le
# drapeau `--install-deps` **tapé à la main**, et un niveau `full` ou `stress`.
# Un utilisateur qui suit la commande du site voyait donc, en fin d'audit, sept
# lignes `sudo apt install …` à recopier une par une.
#
# Cette fonction ouvre une cinquième porte, à la demande du propriétaire du
# projet : **proposer**, quand la machine peut recevoir l'installation et qu'un
# humain est là pour répondre. Les garanties qui comptent ne bougent pas :
#
# - le défaut reste **non** — une frappe vide refuse ;
# - l'accord reste donné **outil par outil** ensuite, avec paquet, provenance et
#   commande exacte : cette question-ci n'ouvre que la porte, elle n'installe
#   rien ;
# - sans terminal — `cron`, conteneur, chaîne d'intégration — **aucune question
#   n'est posée** et le comportement d'avant est intégralement conservé : on
#   nomme, on n'installe pas ;
# - sans root et sans gestionnaire de paquets connu, l'offre ne se présente pas :
#   proposer ce qu'on ne peut pas tenir est pire que se taire.
#
# Ce qui change vraiment est donc le **moment où la question est posée**, pas ce
# qu'elle engage.
provision_offer() {
  # Déjà demandé explicitement : `provision_decide` fait foi, on ne redemande pas.
  [ "${OPT_INSTALL_DEPS:-false}" != 'true' ] || return 1
  # `--assume-yes` sans `--install-deps` n'est pas un accord pour installer :
  # c'est l'absence de question, ce qui n'est pas la même chose.
  [ "${OPT_ASSUME_YES:-false}" != 'true' ] || return 1
  # Un audit qu'on ne regarde pas ne se voit pas poser de question.
  provision_tty || return 1
  [ "$(id -u 2>/dev/null || printf '1')" = '0' ] || return 1
  [ -n "$(dependency_family)" ] || return 1

  local missing='' count=0
  missing=$(dependency_missing)
  [ -n "$missing" ] || return 1
  count=$(printf '%s\n' "$missing" | grep -c '[^[:space:]]' || true)
  [ "$count" -gt 0 ] || return 1

  # La liste **avant** la question, jamais un décompte.
  #
  # Première version, corrigée après relecture par le propriétaire du projet :
  # elle annonçait « Outils absents : 7 » et demandait l'accord d'ouvrir la
  # revue. On autorisait donc l'examen d'un contenu qu'on ne voyait pas, et les
  # commandes à recopier n'arrivaient qu'en fin d'audit — plusieurs minutes plus
  # tard, une fois la décision prise sans elles.
  #
  # Les afficher ici sert les deux réponses, ce qui est le point : « oui » ouvre
  # la revue en sachant sur quoi elle portera, « non » laisse à l'écran
  # exactement ce qu'il faut copier pour le faire soi-même — ce que beaucoup
  # préféreront sur une machine de production.
  log_info ''
  log_info "Outils absents ($count) — les installer enrichirait cet audit :"
  dependency_lines "$missing"
  log_info 'Chacun sera ensuite proposé séparément : paquet, provenance, commande.'

  provision_ask "Installer maintenant ? Répondre non n’installe rien et poursuit l’audit." || {
    log_info 'Aucune installation. Les commandes ci-dessus restent valables à tout moment.'
    return 1
  }

  # shellcheck disable=SC2034 # lues par provision_decide, dans ce même fichier.
  OPT_INSTALL_DEPS='true'
  PROVISION_OFFERED='true'
  return 0
}

# --- Terminal ---------------------------------------------------------------

# Le terminal auquel poser une question, s'il en existe un.
#
# ## Le défaut que cette fonction corrige
#
# Le consentement se lisait sur l'**entrée standard**, et la garde était
# `[ -t 0 ]`. Or la commande que le site propose — la seule que la plupart des
# utilisateurs tapent — est `curl -fsSL …/audit/l | bash` : l'entrée standard y
# est le tube qui porte **le script lui-même**. Deux conséquences, et la seconde
# est pire :
#
# - `[ -t 0 ]` est faux, donc la question n'était jamais posée. L'installation
#   consentie était inatteignable par le chemin d'installation officiel, quel
#   que soit le drapeau ;
# - si la garde avait cédé, `read` aurait mangé les octets du script en guise de
#   réponse — le scanner se serait tronqué lui-même.
#
# `/dev/tty` est le terminal de contrôle du processus, indépendant de ce à quoi
# l'entrée standard est branchée. C'est la seule voie qui permette de poser une
# question depuis un script tubé, et c'est exactement le cas d'emploi du produit.
#
# Rien n'est supposé : le descripteur est réellement ouvert en lecture et en
# écriture. Sous `cron`, dans un conteneur sans terminal ou dans une chaîne
# d'intégration, l'ouverture échoue et la fonction rend faux — donc aucune
# question, donc aucun blocage.
# Le fichier où lire la réponse. Nommé plutôt qu'écrit en dur pour que la suite
# de tests exerce **cette** fonction plutôt qu'une imitation : elle y pointe
# `/dev/stdin`, où elle verse les réponses.
PROVISION_TTY_DEVICE=${PROVISION_TTY_DEVICE:-/dev/tty}

provision_tty() {
  # Ouverture réelle en lecture, et rien d'autre : sous `cron` ou dans un
  # conteneur sans terminal, `/dev/tty` **existe** et `[ -r ]` répond vrai,
  # mais l'ouverture échoue faute de terminal de contrôle. Tester la présence
  # du fichier aurait donc posé une question à personne, et attendu.
  { : <"$PROVISION_TTY_DEVICE"; } 2>/dev/null
}

# --- Consentement -----------------------------------------------------------

# Tout ce qu'il faut savoir avant de dire oui, puis la question.
#
# L'affichage précède la question et ne peut pas en être séparé : un accord
# donné sans savoir ce qu'on installe, d'où, et avec quels privilèges, ne vaut
# rien. Retourne 0 si l'utilisateur accepte.
provision_consent() {
  local tool=$1 package=$2 family=$3
  local prefix=''
  prefix=$(provision_install_command "$family")

  log_info ''
  log_info "Outil manquant : $tool"
  log_step "Paquet          $package"
  log_step "Apporte         $(dependency_unlocks "$tool")"
  log_step "Sans lui        la donnée est marquée non évaluée, jamais inventée"
  log_step "Provenance      $(provision_source "$family")"
  log_step "Commande        $prefix $package"
  log_step "Privilèges      root (déjà obtenus pour cet audit)"
  log_step "Après l’audit   retrait proposé ; refuser le conserve"

  if [ "${OPT_ASSUME_YES:-false}" = 'true' ]; then
    log_step 'Accord          --assume-yes'
    return 0
  fi

  provision_ask "Installer $package ?"
}

# La question, et la seule façon d'y répondre oui.
#
# Elle est posée **au terminal de contrôle**, pas à l'entrée standard : sous
# `curl … | bash`, celle-ci porte le script. Voir `provision_tty`.
#
# Le défaut est **non**. Une frappe vide, une fin de fichier, un terminal qui
# disparaît en cours de route : tout ce qui n'est pas un oui franc refuse. Sur
# une machine qu'on a promis de ne pas modifier, l'hésitation ne s'interprète
# pas.
provision_ask() {
  local question=$1 answer=''

  # L'invite part sur stderr — jamais sur stdout, qui porte le rapport et doit
  # rester canalisable. Seule la **lecture** vise le terminal : écrire dessus
  # aussi n'apporterait rien et casserait le cas où la question est posée
  # pendant que la sortie est redirigée vers un fichier.
  if provision_tty; then
    printf '%s [o/N] ' "$question" >&2
    IFS= read -r answer <"$PROVISION_TTY_DEVICE" || answer=''
  elif [ -t 0 ]; then
    printf '%s [o/N] ' "$question" >&2
    IFS= read -r answer || answer=''
  else
    return 1
  fi

  case "$answer" in
    o | O | y | Y | oui | OUI | yes | YES) return 0 ;;
    *) return 1 ;;
  esac
}

# --- Installation -----------------------------------------------------------

# install + verify — installe, puis vérifie que l'outil répond réellement.
#
# Un code retour nul ne prouve pas que la commande est appelable : un paquet
# peut s'installer et poser son binaire hors du `PATH` de cet audit. La
# vérification est donc une seconde question, pas une formalité.
#
# Écrit sur stdout l'issue (`INSTALLED` ou `INSTALL_FAILED`) suivie, en cas
# d'échec, de la raison sur la ligne suivante.
provision_install() {
  local tool=$1 package=$2 family=$3
  local prefix='' output='' status=0
  prefix=$(provision_install_command "$family")

  log_info "Installation de $package…"
  # `$prefix` est construit par `provision_install_command` à partir d'une
  # famille détectée, jamais d'une donnée du rapport : sa découpe en mots est
  # voulue et sûre (SECURITY.md).
  # shellcheck disable=SC2086
  output=$($prefix "$package" 2>&1) || status=$?

  if [ "$status" -ne 0 ]; then
    printf 'INSTALL_FAILED\n'
    printf '%s\n' "$(printf '%s' "$output" | tail -n 3 | tr '\n' ' ' | cut -c1-300)"
    return 1
  fi

  # Le `PATH` peut avoir été enrichi par l'installation.
  hash -r 2>/dev/null || true

  if ! provision_is_installed "$tool"; then
    printf 'INSTALL_FAILED\n'
    printf '%s\n' "paquet $package installé, mais $tool reste introuvable dans le PATH"
    return 1
  fi

  printf 'INSTALLED\n'
  return 0
}

# --- Orchestration ----------------------------------------------------------

# Le passage complet : proposer, installer, tracer. Avant la collecte.
#
# Réécrit les lignes de l'inventaire concernées plutôt que d'en ajouter :
# deux lignes pour un même outil rendraient la trace contradictoire, et c'est
# précisément la contradiction que la forme normalisée du schéma interdit.
provision_apply() {
  provision_enabled || return 0

  local missing=''
  missing=$(dependency_missing)
  if [ -z "$missing" ]; then
    log_ok 'Aucun outil manquant : rien à installer.'
    return 0
  fi

  local family='' prefix=''
  family=$(dependency_family)
  prefix=$(provision_install_command "$family")

  log_info 'Des outils absents enrichiraient cet audit. Chacun est proposé séparément.'

  local tool='' package='' outcome='' error='' version='' result=''
  # La liste des outils entre par le descripteur 3, **pas** par l'entrée
  # standard : `provision_consent` y lit la réponse de l'utilisateur, et un
  # `done 3<<<"$missing"` la lui aurait volée. Le défaut était silencieux et
  # complet — chaque question consommait le nom de l'outil suivant en guise de
  # réponse, ce qui refusait tout et n'en proposait qu'un sur deux. Il ne se
  # voyait pas avec `--assume-yes`, seul mode exercé jusqu'ici, parce que
  # l'accord y est rendu avant d'atteindre la lecture.
  while IFS= read -r tool <&3; do
    [ -n "$tool" ] || continue
    package=$(dependency_package "$tool" "$family")
    if [ -z "$package" ]; then
      log_debug "$tool : aucun paquet connu pour la famille $family"
      continue
    fi

    error=''
    version=''
    if provision_consent "$tool" "$package" "$family"; then
      result=$(provision_install "$tool" "$package" "$family") || true
      outcome=$(printf '%s' "$result" | head -n 1)
      if [ "$outcome" = 'INSTALLED' ]; then
        version=$(provision_version "$tool")
        log_ok "$tool installé${version:+ ($version)}"
      else
        error=$(printf '%s' "$result" | tail -n +2 | head -n 1)
        log_warn "$tool non installé : $error"
      fi
    else
      outcome='DECLINED'
      log_info "$tool : refusé. La donnée correspondante sera marquée non évaluée."
    fi

    provision_rewrite "$tool" "$package" "$outcome" "$version" "$prefix" "$error"
  done 3<<<"$missing"

  return 0
}

# Remplace la ligne d'inventaire d'un outil par son issue définitive.
provision_rewrite() {
  local tool=$1 package=${2-} outcome=$3 version=${4-} method=${5-} error=${6-}
  [ -n "$PROVISION_JOURNAL" ] && [ -f "$PROVISION_JOURNAL" ] || return 0

  local kept=''
  # Le nom d'outil est un identifiant de la table, jamais une donnée du
  # rapport : il ne peut pas contenir de quote.
  kept=$(grep -v "\"tool\":\"$tool\"" "$PROVISION_JOURNAL" 2>/dev/null || true)
  printf '%s' "$kept" >"$PROVISION_JOURNAL"
  [ -z "$kept" ] || printf '\n' >>"$PROVISION_JOURNAL"

  provision_record "$tool" "$package" "$outcome" "$version" "$method" \
    "$(dependency_unlocks "$tool")" "$error"
  return 0
}

# --- Retrait après audit ----------------------------------------------------

# uninstall — propose de rendre la machine à son état initial.
#
# Ne peut porter que sur les outils dont l'inventaire dit `INSTALLED` : un outil
# `PRESENT_BEFORE` n'est jamais proposé, jamais listé, et aucun chemin de ce
# module ne permet de le retirer.
provision_offer_removal() {
  provision_enabled || return 0
  [ -n "$PROVISION_JOURNAL" ] && [ -f "$PROVISION_JOURNAL" ] || return 0

  local installed=''
  installed=$(grep '"outcome":"INSTALLED"' "$PROVISION_JOURNAL" 2>/dev/null |
    sed -n 's/.*"tool":"\([^"]*\)".*/\1/p')
  [ -n "$installed" ] || return 0

  log_info ''
  log_info 'SysAudit a installé les outils suivants pour cet audit :'

  local tool=''
  while IFS= read -r tool; do
    [ -n "$tool" ] || continue
    log_step "$tool — $(dependency_unlocks "$tool")"
  done <<<"$installed"

  log_info 'Les outils déjà présents avant cet audit ne sont pas concernés.'

  if [ "${OPT_ASSUME_YES:-false}" = 'true' ]; then
    # Un `--assume-yes` donné pour installer ne vaut pas accord pour désinstaller :
    # ce sont deux décisions, et la seconde n'a pas été posée. Conserver est le
    # choix qui ne détruit rien.
    log_info 'Outils conservés (--assume-yes ne vaut pas accord de retrait).'
    provision_mark_removal "$installed" 'KEPT' ''
    return 0
  fi

  local answer=''
  printf 'Désinstaller ces outils ? [o/N] ' >&2
  IFS= read -r answer || answer=''
  case "$answer" in
    o | O | y | Y | oui | OUI | yes | YES) ;;
    *)
      log_info 'Outils conservés.'
      provision_mark_removal "$installed" 'KEPT' ''
      return 0
      ;;
  esac

  local family='' package='' prefix='' output='' status=0 error=''
  family=$(dependency_family)
  prefix=$(provision_uninstall_command "$family")
  while IFS= read -r tool; do
    [ -n "$tool" ] || continue
    package=$(dependency_package "$tool" "$family")
    [ -n "$package" ] || continue

    status=0
    # shellcheck disable=SC2086
    output=$($prefix "$package" 2>&1) || status=$?

    if [ "$status" -eq 0 ]; then
      log_ok "$package retiré."
      provision_mark_removal "$tool" 'REMOVED' ''
    else
      error=$(printf '%s' "$output" | tail -n 2 | tr '\n' ' ' | cut -c1-300)
      # Un retrait raté laisse la machine modifiée : le taire ferait croire
      # qu'elle a été rendue à son état initial.
      log_warn "$package n’a pas pu être retiré : $error"
      provision_mark_removal "$tool" 'REMOVAL_FAILED' "$error"
    fi
  done <<<"$installed"

  return 0
}

# Note le sort final d'un ou plusieurs outils, une ligne par nom.
provision_mark_removal() {
  local tools=$1 removal=$2 error=${3-}
  [ -n "$PROVISION_REMOVAL_JOURNAL" ] || return 0

  local tool=''
  while IFS= read -r tool; do
    [ -n "$tool" ] || continue
    printf '%s\t%s\t%s\n' "$tool" "$removal" "$error" >>"$PROVISION_REMOVAL_JOURNAL"
  done <<<"$tools"
  return 0
}

# --- Sortie JSON ------------------------------------------------------------

# `collection.dependencies`, une entrée par outil de la table.
#
# L'usage et le retrait sont recollés ici : les deux ne sont connus qu'après la
# collecte, alors que l'issue l'est avant. Les recoller à la source aurait
# demandé de réécrire chaque ligne deux fois de plus.
build_dependencies_json() {
  [ -n "$PROVISION_JOURNAL" ] && [ -s "$PROVISION_JOURNAL" ] || {
    printf '[]'
    return 0
  }

  local used_list='' removal_list=''
  if [ -n "$PROVISION_USED_JOURNAL" ] && [ -s "$PROVISION_USED_JOURNAL" ]; then
    used_list=$(awk '!seen[$0]++' <"$PROVISION_USED_JOURNAL" | paste -sd' ' -)
  fi
  if [ -n "$PROVISION_REMOVAL_JOURNAL" ] && [ -s "$PROVISION_REMOVAL_JOURNAL" ]; then
    removal_list=$PROVISION_REMOVAL_JOURNAL
  fi

  local out='' line='' tool='' used='false' removal='NOT_APPLICABLE' rerror=''
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    tool=$(printf '%s' "$line" | sed -n 's/.*"tool":"\([^"]*\)".*/\1/p')

    used='false'
    case " $used_list " in *" $tool "*) used='true' ;; esac

    removal='NOT_APPLICABLE'
    rerror=''
    if [ -n "$removal_list" ]; then
      local found=''
      found=$(awk -F'\t' -v t="$tool" '$1 == t { print $2 "\t" $3; exit }' "$removal_list")
      if [ -n "$found" ]; then
        removal=${found%%$'\t'*}
        rerror=${found#*$'\t'}
      fi
    fi

    # La ligne du journal est déjà un objet JSON complet : les deux champs
    # manquants sont insérés avant son accolade fermante.
    line="${line%\}}"
    line="$line,$(jf_bool used "$used"),$(jf_str removal "$removal")"
    [ -z "$rerror" ] || line="$line,$(jf_str error "$rerror")"
    line="$line}"

    if [ -z "$out" ]; then out=$line; else out="$out,$line"; fi
  done <"$PROVISION_JOURNAL"

  printf '[%s]' "$out"
}

# L'inventaire a-t-il eu lieu ? Une liste vide sans ce drapeau se lirait comme
# « aucun outil ne manquait », alors qu'elle peut vouloir dire « on n'a pas
# regardé ».
dependencies_inspected() {
  if [ -n "$PROVISION_JOURNAL" ] && [ -s "$PROVISION_JOURNAL" ]; then
    printf 'true'
  else
    printf 'false'
  fi
}
