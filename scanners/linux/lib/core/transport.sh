#!/usr/bin/env bash
# Transport : nommer ce qui empêche l'envoi, et le vérifier sans auditer.
#
# ## Pourquoi ce module existe
#
# Un envoi qui échoue disait « erreur réseau », ce qui ne distingue pas un nom
# de domaine qui ne résout pas d'un proxy qui réclame des identifiants. Les deux
# ne se réparent pourtant ni au même endroit ni par la même personne : le
# premier est un problème de résolveur, le second une ligne à ajouter dans une
# politique de pare-feu. Un message qui les confond fait chercher au mauvais
# endroit — mesuré sur un poste d'entreprise derrière un FortiGate.
#
# ## Ce qu'il ne fait pas
#
# **Il ne conclut jamais d'une donnée absente.** Sans outil de résolution
# installé et sans réponse exploitable de curl, le verdict DNS est « non
# vérifié », pas « OK ». Un diagnostic qui invente un succès est pire que pas de
# diagnostic : il fait clore l'incident.
#
# Il ne devine pas non plus l'inspection HTTPS. Un certificat refusé par la
# chaîne de confiance système **et** accepté sans vérification est un indice
# sérieux, jamais une preuve — un certificat simplement expiré donne le même
# signal. Le mot « probable » est dans le message, et il y reste.

# --- Masquage des identifiants ----------------------------------------------

# Rend une adresse de proxy débarrassée de ses identifiants.
#
# `http://domaine\user:motdepasse@proxy:8080` devient `http://proxy:8080`. Cette
# fonction est le seul chemin par lequel une adresse de proxy atteint l'écran ou
# un journal : un mot de passe d'annuaire d'entreprise n'a rien à faire dans une
# sortie qu'on recopie dans un ticket.
mask_proxy_credentials() {
  local url=$1
  # Tout ce qui précède la dernière `@` de la partie autorité est un identifiant.
  printf '%s' "$url" | sed -E 's#^([a-zA-Z][a-zA-Z0-9+.-]*://)[^/@]*@#\1#'
}

# Nomme le proxy déclaré par l'environnement, et par quelle variable.
#
# L'ordre suit celui que respecte curl lui-même — `https_proxy` l'emporte sur
# `http_proxy` pour une cible HTTPS, et les formes minuscules l'emportent sur
# les majuscules. Le reproduire ici évite d'annoncer un proxy qui ne sera pas
# celui emprunté.
#
# Rend une chaîne vide si rien n'est déclaré. **Ce n'est pas « pas de proxy »** :
# un proxy transparent ou une configuration PAC ne passent par aucune variable.
proxy_declared() {
  local name='' value=''
  for name in https_proxy HTTPS_PROXY http_proxy HTTP_PROXY all_proxy ALL_PROXY; do
    value=$(printenv "$name" 2>/dev/null || printf '')
    if [ -n "$value" ]; then
      printf '%s=%s' "$name" "$(mask_proxy_credentials "$value")"
      return 0
    fi
  done
  printf ''
}

# Traduit `--proxy` et `--no-proxy` en arguments curl, un par ligne.
#
# Ne journalise rien : c'est une traduction, pas une décision. Les appelants qui
# doivent dire à l'utilisateur par où ils passent le disent chez eux — l'envoi le
# fait avant sa première requête, le relevé d'adresse publique n'a personne à
# prévenir.
#
# Une sortie vide signifie « laisser curl faire » : il lit `https_proxy` de
# lui-même, et le neutraliser ici imposerait une politique que personne n'a
# demandée.
curl_proxy_args() {
  if [ "${OPT_NO_PROXY:-false}" = 'true' ]; then
    # `--noproxy '*'` neutralise aussi les variables d'environnement, ce que ne
    # ferait pas un simple `--proxy ''`.
    printf '%s\n' '--noproxy' '*'
  elif [ -n "${OPT_PROXY:-}" ]; then
    printf '%s\n' '--proxy' "$OPT_PROXY"
  fi
}

# --- Codes de sortie ---------------------------------------------------------
#
# Trois valeurs, et pas une de plus.
#
#   0  l'audit a été produit, et transmis s'il devait l'être ;
#   1  l'audit n'a pas pu être produit — usage incorrect, ou collecte impossible ;
#   2  l'audit a été produit, la transmission a échoué. **Le rapport est sur le
#      disque**, et rien n'est perdu.
#
# ## Pourquoi 2 existe
#
# `die` et un envoi refusé sortaient tous deux en 1. Un ordonnanceur ne pouvait
# donc pas distinguer « la machine n'a pas pu être auditée » de « la machine a
# été auditée, le pare-feu a refusé l'envoi » — deux situations qui n'appellent
# ni la même alerte ni la même action. Sur un parc derrière proxy, la seconde
# est la normale et la première l'incident ; les confondre rend la supervision
# inutilisable.
#
# ## Pourquoi pas un code par cause
#
# Un code par cause réseau — 11 DNS, 12 TLS, 13 proxy… — se serait figé en API
# le jour où quelqu'un l'aurait mis dans un script, et aurait dû grandir à
# chaque nouvelle cause distinguée. La **cause** est déjà nommée en clair sur la
# sortie d'erreur et par `--network-test` ; le code de sortie, lui, répond à la
# seule question qu'un ordonnanceur pose : faut-il réveiller quelqu'un ?
# shellcheck disable=SC2034 # lues par sysaudit.sh et core.sh, pas ici.
readonly EXIT_OK=0
# shellcheck disable=SC2034
readonly EXIT_AUDIT_FAILED=1
readonly EXIT_TRANSPORT_FAILED=2

# --- Mode de collecte --------------------------------------------------------

# `online` si cette collecte s'inscrivait dans une session qui prévoyait de
# transmettre, `offline` sinon.
#
# Le champ décrit **l'intention au moment de la collecte**, pas son issue : un
# envoi demandé puis refusé par un pare-feu reste `online`, et c'est
# volontaire. Le rapport est alors « collecté en ligne, transporté à la main » —
# deux faits distincts, que confondre en un seul rendrait le champ inutilisable.
#
# Il est écrit avant toute tentative réseau, parce que le JSON l'est aussi : le
# faire dépendre du résultat de l'envoi exigerait de réécrire le fichier après
# coup, donc de changer son empreinte après qu'elle a servi.
collection_mode() {
  [ "${OPT_UPLOAD:-false}" = 'true' ] && printf 'online' || printf 'offline'
}

# --- Vérification du document avant écriture ---------------------------------

# Le document produit est-il du JSON bien formé ?
#
# Rend `ok`, `ko`, ou `inconnu` quand aucun analyseur n'est disponible.
#
# ## Ce que cette vérification attrape
#
# Une chaîne mal échappée ou une virgule en trop — le genre de défaut qu'un
# collecteur peut introduire sur une machine dont la sortie d'outil est
# inhabituelle. Sans elle, le fichier partait sur le disque, l'utilisateur
# repartait avec, et le refus n'arrivait qu'au dépôt, des heures plus tard, sur
# un poste qui n'est plus celui de la machine auditée.
#
# ## Ce qu'elle n'attrape pas
#
# **La conformité au schéma.** Le scanner ne peut pas la vérifier : le schéma
# vit dans un paquet TypeScript, et le scanner doit tourner sur une machine sans
# Node.js. C'est l'API qui tient cette validation, et c'est très bien ainsi —
# un second contrôle serait une seconde politique à garder en cohérence.
#
# ## Pourquoi « inconnu » plutôt que « ok »
#
# Une image minimale n'a ni `python3`, ni `jq`, ni `node`. Conclure « bien
# formé » de l'absence d'analyseur reviendrait à conclure d'une donnée absente —
# la faute que ce dépôt s'interdit partout ailleurs.
json_is_wellformed() {
  local document=$1

  if has_cmd python3; then
    printf '%s' "$document" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null &&
      printf 'ok' || printf 'ko'
  elif has_cmd jq; then
    printf '%s' "$document" | jq -e . >/dev/null 2>&1 && printf 'ok' || printf 'ko'
  elif has_cmd node; then
    printf '%s' "$document" |
      node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>JSON.parse(d))' 2>/dev/null &&
      printf 'ok' || printf 'ko'
  else
    printf 'inconnu'
  fi
}

# --- Classification des échecs ----------------------------------------------

# Traduit un code de sortie de curl en cause lisible.
#
# Ces codes sont stables depuis très longtemps et documentés dans `man 1 curl` ;
# ils sont la seule information de cause dont on dispose quand aucune réponse
# HTTP n'est revenue. Un code inconnu est rendu tel quel plutôt que rangé dans
# une catégorie fourre-tout : « code curl 63 » se cherche, « erreur réseau » non.
# Les libellés sont des **causes**, sans préfixe de catégorie : ils sont
# recopiés tels quels dans des phrases qui portent déjà la leur (« TLS : non
# atteint — … »), et un « DNS — DNS ne résout pas » y serait illisible.
curl_failure_label() {
  case "$1" in
    5) printf 'le nom du proxy déclaré ne résout pas' ;;
    6) printf 'le nom de l’API ne résout pas (DNS)' ;;
    7) printf 'connexion refusée ou impossible — pare-feu ou port fermé' ;;
    28) printf 'délai dépassé — filtrage silencieux probable' ;;
    35) printf 'erreur TLS pendant la poignée de main' ;;
    47) printf 'trop de redirections — portail captif probable' ;;
    52) printf 'réponse vide du serveur' ;;
    56) printf 'connexion interrompue en cours de réception' ;;
    60) printf 'certificat non reconnu — inspection HTTPS probable' ;;
    *) printf 'échec réseau (code curl %s)' "$1" ;;
  esac
}

# Traduit un statut HTTP en cause lisible.
#
# Seuls les statuts qui appellent une action différente sont nommés. Un 403 et
# un 407 se réparent tous deux dans l'équipement réseau, mais pas au même
# endroit — et le 407 est le seul que l'utilisateur puisse parfois lever seul,
# en déclarant le proxy.
http_failure_label() {
  case "$1" in
    401) printf 'HTTP 401 — authentification exigée par l’API' ;;
    403) printf 'HTTP 403 — refus : filtrage web ou contrôle applicatif probable' ;;
    407) printf 'HTTP 407 — le proxy exige une authentification' ;;
    413) printf 'HTTP 413 — rapport refusé pour sa taille' ;;
    429) printf 'HTTP 429 — quota d’envoi atteint' ;;
    5??) printf 'HTTP %s — erreur du serveur SysAudit' "$1" ;;
    000) printf 'aucune réponse HTTP reçue' ;;
    *) printf 'HTTP %s' "$1" ;;
  esac
}

# Conseil associé à une cause, quand il en existe un qui ne soit pas une
# banalité. Rend une chaîne vide sinon : « vérifiez votre connexion » n'aide
# personne et occupe la place du message utile.
network_failure_hint() {
  case "$1" in
    407 | proxy)
      printf 'Déclarez le proxy : export https_proxy=http://utilisateur@proxy:8080'
      ;;
    403)
      printf 'Un filtrage web bloque la destination. Voir docs/proxy/README.md.'
      ;;
    60 | 35)
      printf 'Une inspection TLS remplace le certificat. Voir docs/proxy/README.md.'
      ;;
    6)
      printf 'Le résolveur ne connaît pas ce nom, ou un filtrage DNS le refuse.'
      ;;
    *) printf '' ;;
  esac
}

# --- Test réseau (`--network-test`) -----------------------------------------
#
# Diagnostic **indépendant de l'audit** : rien n'est collecté, rien n'est écrit,
# aucun rapport n'est produit. La cible est `GET /api/health`, choisie parce
# qu'elle est en lecture seule — `/api/audit/bootstrap/…` crée une session en
# base, et un test de connectivité n'a pas à laisser de trace.

# Aligne un libellé sur une largeur fixe, à la manière d'un sommaire.
network_test_line() {
  local label=$1 verdict=$2
  local pad='..................'
  printf '  %s%s %s\n' "$label" "${pad:${#label}}" "$verdict" >&2
}

# Vérifie qu'un nom résout, avec l'outil qui se trouve là.
#
# Rend `ok`, `ko`, ou `inconnu` quand aucun outil n'est disponible — cas réel
# sur une image minimale, où ni `getent`, ni `host`, ni `dig` n'existent.
resolve_host() {
  local host=$1
  if has_cmd getent; then
    getent ahosts "$host" >/dev/null 2>&1 && printf 'ok' || printf 'ko'
  elif has_cmd host; then
    host "$host" >/dev/null 2>&1 && printf 'ok' || printf 'ko'
  elif has_cmd dig; then
    [ -n "$(dig +short "$host" 2>/dev/null)" ] && printf 'ok' || printf 'ko'
  elif has_cmd nslookup; then
    nslookup "$host" >/dev/null 2>&1 && printf 'ok' || printf 'ko'
  else
    printf 'inconnu'
  fi
}

# Extrait l'hôte d'une URL, sans identifiants ni port.
url_host() {
  printf '%s' "$1" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##; s#^[^/@]*@##; s#[/:?].*$##'
}

network_test() {
  local api_url=$1

  [ -n "$api_url" ] ||
    die '--network-test attend une API : --api-url https://… (ou SYSAUDIT_API_URL).'
  has_cmd curl || die 'curl est requis pour le test réseau.'

  local base="${api_url%/}"
  local host=''
  host=$(url_host "$base")
  [ -n "$host" ] || die "URL d’API illisible : $api_url"

  printf '\n' >&2
  log_info 'Test réseau SysAudit — aucun audit n’est produit.'
  printf '\n' >&2
  network_test_line 'Cible' "$base"

  # 1. Proxy. Lecture d'environnement : aucun paquet n'est émis, et le verdict
  #    est « déclaré » ou « non déclaré », jamais « absent » — un proxy
  #    transparent ne se déclare nulle part et intercepte quand même.
  local proxy=''
  proxy=$(proxy_declared)
  if [ -n "$proxy" ]; then
    network_test_line 'Proxy' "déclaré ($proxy)"
  else
    network_test_line 'Proxy' 'non déclaré (un proxy transparent resterait invisible)'
  fi

  # 2. DNS.
  local dns=''
  dns=$(resolve_host "$host")
  case "$dns" in
    ok) network_test_line 'DNS' "OK ($host)" ;;
    ko) network_test_line 'DNS' "ÉCHEC — $host ne résout pas" ;;
    *) network_test_line 'DNS' 'non vérifié — aucun outil de résolution installé' ;;
  esac

  # 3. TLS. La poignée de main seule, sans requête applicative : `--head` suffit
  #    à l'établir, et un refus ici sépare un problème de certificat d'un refus
  #    applicatif qui viendrait après.
  local tls_code=0
  curl -sS --head --max-time 15 -o /dev/null "$base/api/health" >/dev/null 2>&1 || tls_code=$?

  if [ "$tls_code" -eq 0 ]; then
    network_test_line 'TLS' 'OK'
  elif [ "$tls_code" -eq 60 ] || [ "$tls_code" -eq 35 ]; then
    # Le même appel sans vérification. S'il passe, la chaîne de confiance est le
    # seul obstacle : c'est la signature d'une inspection HTTPS, sans en être la
    # preuve — un certificat expiré donnerait exactement le même résultat.
    if curl -sS --head --insecure --max-time 15 -o /dev/null "$base/api/health" >/dev/null 2>&1; then
      network_test_line 'TLS' 'ÉCHEC — certificat non reconnu, inspection HTTPS probable'
    else
      network_test_line 'TLS' "ÉCHEC — $(curl_failure_label "$tls_code")"
    fi
  else
    network_test_line 'TLS' "non atteint — $(curl_failure_label "$tls_code")"
  fi

  # 4. L'API elle-même. `-o /dev/null -w '%{http_code}'` sans `-f` : on veut le
  #    statut, y compris quand il vaut 407 — que `-f` masquerait derrière un
  #    code de sortie 22.
  local http_code='' curl_code=0
  http_code=$(curl -sS --max-time 20 -o /dev/null -w '%{http_code}' \
    -H "User-Agent: SysAudit-Scanner/$SCANNER_VERSION" \
    "$base/api/health" 2>/dev/null) || curl_code=$?

  if [ "$curl_code" -ne 0 ]; then
    network_test_line 'API SysAudit' "INJOIGNABLE — $(curl_failure_label "$curl_code")"
    network_test_line 'HTTP' 'aucune réponse'
    printf '\n' >&2
    local hint=''
    hint=$(network_failure_hint "$curl_code")
    [ -n "$hint" ] && log_warn "$hint"
    log_info 'L’audit reste possible : sans --upload, le rapport est écrit localement,'
    log_info 'puis se dépose sur la page « Déposer un rapport » depuis un poste connecté.'
    return "$EXIT_TRANSPORT_FAILED"
  fi

  case "$http_code" in
    200)
      network_test_line 'API SysAudit' 'OK'
      network_test_line 'HTTP' "$http_code"
      printf '\n' >&2
      log_ok 'L’envoi direct devrait fonctionner depuis cette machine.'
      return "$EXIT_OK"
      ;;
    *)
      network_test_line 'API SysAudit' 'BLOQUÉE'
      network_test_line 'HTTP' "$(http_failure_label "$http_code")"
      printf '\n' >&2
      local hint=''
      hint=$(network_failure_hint "$http_code")
      [ -n "$hint" ] && log_warn "$hint"
      log_info 'L’audit reste possible : sans --upload, le rapport est écrit localement,'
      log_info 'puis se dépose sur la page « Déposer un rapport » depuis un poste connecté.'
      return "$EXIT_TRANSPORT_FAILED"
      ;;
  esac
}
