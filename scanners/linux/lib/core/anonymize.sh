#!/usr/bin/env bash
# Anonymisation (§31).
#
# Le pseudonyme est déterministe **au sein d'un rapport** : la même valeur donne
# toujours le même pseudonyme, ce qui préserve les corrélations internes
# (l'interface `eth0` reste rattachée à sa MAC). Un sel aléatoire par exécution
# empêche en revanche de corréler deux rapports ou de retrouver une valeur par
# dictionnaire — indispensable sur des espaces réduits comme les adresses MAC.
#
# Ce comportement reproduit celui de `createAnonymizer()` dans @sysaudit/shared.

ANONYMIZE='false'
ANON_SALT=''
declare -A ANON_CACHE=()

# Catégories exposées à l'utilisateur avant tout upload.
ANON_CATEGORIES=(hostname username domain publicIp macAddress serialNumber uuid wifiSsid)

anon_init() {
  ANONYMIZE=$1
  [ "$ANONYMIZE" = 'true' ] || return 0

  if has_cmd openssl; then
    ANON_SALT=$(openssl rand -hex 32)
  elif [ -r /dev/urandom ]; then
    ANON_SALT=$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
  else
    die "Anonymisation demandée mais aucune source d'aléa disponible (openssl ou /dev/urandom)."
  fi

  has_cmd sha256sum || has_cmd shasum ||
    die 'Anonymisation demandée mais ni sha256sum ni shasum ne sont disponibles.'
}

anon_prefix() {
  case "$1" in
    hostname) printf 'HOST' ;;
    username) printf 'USER' ;;
    domain) printf 'DOMAIN' ;;
    publicIp) printf 'IP' ;;
    macAddress) printf 'MAC' ;;
    serialNumber) printf 'SN' ;;
    uuid) printf 'UUID' ;;
    wifiSsid) printf 'SSID' ;;
    *) printf 'ANON' ;;
  esac
}

# anon <catégorie> <valeur> — retourne la valeur, ou son pseudonyme si
# l'anonymisation est active. Une valeur vide reste vide.
anon() {
  local category=$1 value=${2-}

  [ "$ANONYMIZE" = 'true' ] || { printf '%s' "$value"; return 0; }
  [ -z "$value" ] && return 0

  local key=''
  key="$category:$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"

  if [ -n "${ANON_CACHE[$key]-}" ]; then
    printf '%s' "${ANON_CACHE[$key]}"
    return 0
  fi

  local digest=''
  if has_cmd sha256sum; then
    digest=$(printf '%s%s' "$ANON_SALT" "$key" | sha256sum | cut -c1-10)
  else
    digest=$(printf '%s%s' "$ANON_SALT" "$key" | shasum -a 256 | cut -c1-10)
  fi

  local masked=''
  masked="$(anon_prefix "$category")-$(printf '%s' "$digest" | tr '[:lower:]' '[:upper:]')"
  ANON_CACHE[$key]=$masked
  printf '%s' "$masked"
}

# Fragment JSON listant les catégories effectivement masquées.
anon_categories_json() {
  [ "$ANONYMIZE" = 'true' ] || { printf '[]'; return 0; }
  local out='' category=''
  for category in "${ANON_CATEGORIES[@]}"; do
    out=$(json_join "$out" "$(j_str "$category")")
  done
  printf '[%s]' "$out"
}

# Affiché avant tout upload : l'utilisateur doit voir ce qui est transformé.
anon_describe() {
  if [ "$ANONYMIZE" = 'true' ]; then
    log_info 'Anonymisation active. Sont remplacés par un pseudonyme stable :'
    log_step 'nom de machine, noms d’utilisateurs, domaines de recherche'
    log_step 'adresses IP publiques, adresses MAC, SSID Wi-Fi'
    log_step 'numéros de série et UUID matériels'
    log_step 'Les adresses IP privées sont conservées : elles n’identifient personne.'
  else
    log_warn 'Anonymisation désactivée : le rapport contient le nom de machine,'
    log_warn 'les adresses MAC et les numéros de série. Utilisez --anonymize pour les masquer.'
  fi
}
