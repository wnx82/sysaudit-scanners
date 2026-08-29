# SysAudit Windows — transport : nommer ce qui empeche l'envoi, et le verifier
# sans auditer.
#
# ## Pourquoi ce fichier existe
#
# Un envoi refuse remontait le corps brut de la reponse, ou une exception .NET
# dont le message ne distingue pas un nom qui ne resout pas d'un proxy qui
# reclame des identifiants. Les deux ne se reparent ni au meme endroit ni par la
# meme personne. `WebException` porte pourtant la reponse dans `Status`, une
# enumeration precise : il suffisait de la lire.
#
# ## Ce qu'il ne fait pas
#
# **Il ne conclut jamais d'une donnee absente.** Sans reponse exploitable, le
# verdict est « non verifie », jamais « OK » : un diagnostic qui invente un
# succes fait clore l'incident, ce qui est pire que pas de diagnostic.
#
# Il ne prouve pas l'inspection HTTPS non plus. Un certificat refuse par la
# chaine de confiance **et** accepte sans verification est un indice serieux —
# un certificat simplement expire donne exactement le meme signal. Le mot
# « probable » est dans le message, et il y reste.

# --- Codes de sortie ---------------------------------------------------------
#
# Trois valeurs, et pas une de plus. Identiques a celles du scanner Linux : un
# ordonnanceur qui pilote un parc mixte ne doit pas avoir deux tables a tenir.
#
#   0  l'audit a ete produit, et transmis s'il devait l'etre ;
#   1  l'audit n'a pas pu etre produit — usage incorrect, ou collecte impossible ;
#   2  l'audit a ete produit, la transmission a echoue. **Le rapport est sur le
#      disque**, et rien n'est perdu.
#
# ## Pourquoi 2 existe
#
# `throw` sortait en 1, comme une collecte impossible. Un ordonnanceur ne
# pouvait donc pas distinguer « la machine n'a pas pu etre auditee » de « la
# machine a ete auditee, le pare-feu a refuse l'envoi » — deux situations qui
# n'appellent ni la meme alerte ni la meme action. Sur un parc derriere proxy,
# la seconde est la normale et la premiere l'incident.
#
# ## Pourquoi pas un code par cause
#
# Un code par cause reseau se serait fige en API le jour ou quelqu'un l'aurait
# mis dans un script. La **cause** est deja nommee en clair sur la sortie et par
# -NetworkTest ; le code repond a la seule question qu'un ordonnanceur pose :
# faut-il reveiller quelqu'un ?
$script:EXIT_OK = 0
$script:EXIT_AUDIT_FAILED = 1
$script:EXIT_TRANSPORT_FAILED = 2

# Delai maximal d'un televersement, en secondes.
#
# Large, mais fini — c'est tout ce qui compte. Un rapport pese quelques centaines
# de kilo-octets et une API en bonne sante repond en moins d'une seconde : deux
# minutes couvrent une liaison lente ou un serveur charge sans qu'un utilisateur
# assis devant la machine ait a se demander si le scanner travaille encore.
#
# La valeur precedente etait « aucun » : `WebClient` n'expose pas de delai, et
# l'attente pouvait ne jamais finir.
$script:UPLOAD_TIMEOUT_SECONDS = 120

<#
.SYNOPSIS
  Adresse de proxy debarrassee de ses identifiants.

.DESCRIPTION
  `http://domaine\user:motdepasse@proxy:8080` devient `proxy:8080`. C'est le
  seul chemin par lequel une adresse declaree atteint l'ecran : un mot de passe
  d'annuaire d'entreprise n'a rien a faire dans une sortie qu'on recopie dans un
  ticket.

  Une valeur illisible est rendue sous la forme `(adresse illisible)` plutot que
  telle quelle : une chaine qu'on n'a pas su analyser peut encore contenir le
  mot de passe qu'on croyait retirer.
#>
function Get-SysAuditProxyDisplay {
  param([string]$ProxyUrl = '')

  if ([string]::IsNullOrWhiteSpace($ProxyUrl)) { return '' }

  $normalized = $ProxyUrl.Trim()
  if ($normalized -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') { $normalized = 'http://' + $normalized }

  try {
    $uri = [Uri]$normalized
    return ($uri.Host + ':' + $uri.Port)
  } catch {
    return '(adresse illisible)'
  }
}

<#
.SYNOPSIS
  Nomme le proxy declare par l'environnement, et par quelle variable.

.DESCRIPTION
  Rend une chaine vide si rien n'est declare. **Ce n'est pas « pas de proxy »** :
  le proxy systeme de Windows, une configuration PAC ou une interception
  transparente ne passent par aucune variable et resteraient invisibles ici.

  L'ordre reproduit celui de `Resolve-SysAuditProxyUrl` : annoncer une variable
  qui ne sera pas celle retenue serait pire que ne rien annoncer.
#>
function Get-SysAuditDeclaredProxy {
  param(
    [string]$Explicit = '',
    [string]$SysAuditProxy = '',
    [string]$HttpsProxy = '',
    [string]$HttpProxy = ''
  )

  $candidates = @(
    @{ name = '-Proxy'; value = $Explicit },
    @{ name = 'SYSAUDIT_PROXY'; value = $SysAuditProxy },
    @{ name = 'HTTPS_PROXY'; value = $HttpsProxy },
    @{ name = 'HTTP_PROXY'; value = $HttpProxy }
  )

  foreach ($candidate in $candidates) {
    if (-not [string]::IsNullOrWhiteSpace($candidate.value)) {
      return ($candidate.name + '=' + (Get-SysAuditProxyDisplay -ProxyUrl $candidate.value))
    }
  }

  return ''
}

<#
.SYNOPSIS
  Traduit un `WebExceptionStatus` en cause lisible.

.DESCRIPTION
  Ces valeurs sont l'unique information de cause quand aucune reponse HTTP n'est
  revenue. Un statut non prevu est rendu tel quel plutot que range dans une
  categorie fourre-tout : « SendFailure » se cherche, « erreur reseau » non.

  Les libelles sont des **causes**, sans prefixe de categorie : ils sont
  recopies dans des phrases qui portent deja la leur.
#>
function Get-SysAuditTransportFailure {
  param([string]$Status = '')

  switch ($Status) {
    'NameResolutionFailure' { return 'le nom de l''API ne resout pas (DNS)' }
    'ProxyNameResolutionFailure' { return 'le nom du proxy declare ne resout pas' }
    'ConnectFailure' { return 'connexion refusee ou impossible — pare-feu ou port ferme' }
    'Timeout' { return 'delai depasse — filtrage silencieux probable' }
    'TrustFailure' { return 'certificat non reconnu — inspection HTTPS probable' }
    'SecureChannelFailure' { return 'echec TLS — protocole ou chiffrement refuse' }
    'ConnectionClosed' { return 'connexion fermee par le pair en cours d''echange' }
    'ReceiveFailure' { return 'connexion interrompue en cours de reception' }
    'SendFailure' { return 'connexion interrompue pendant l''envoi' }
    'ServerProtocolViolation' { return 'reponse non conforme a HTTP — equipement intermediaire probable' }
    'ProtocolError' { return 'l''API a repondu par une erreur' }
    default {
      if ([string]::IsNullOrWhiteSpace($Status)) { return 'echec reseau de cause inconnue' }
      return ('echec reseau (' + $Status + ')')
    }
  }
}

<#
.SYNOPSIS
  Traduit un statut HTTP en cause lisible.

.DESCRIPTION
  Seuls les statuts qui appellent une action differente sont nommes. Un 403 et
  un 407 se reparent tous deux dans l'equipement reseau, mais pas au meme
  endroit — et le 407 est le seul que l'utilisateur puisse parfois lever seul,
  en declarant le proxy.
#>
function Get-SysAuditHttpFailure {
  param([int]$StatusCode = 0)

  switch ($StatusCode) {
    401 { return 'HTTP 401 — authentification exigee par l''API' }
    403 { return 'HTTP 403 — refus : filtrage web ou controle applicatif probable' }
    407 { return 'HTTP 407 — le proxy exige une authentification' }
    413 { return 'HTTP 413 — rapport refuse pour sa taille' }
    429 { return 'HTTP 429 — quota d''envoi atteint' }
    0 { return 'aucune reponse HTTP recue' }
    default {
      if ($StatusCode -ge 500 -and $StatusCode -le 599) {
        return ('HTTP ' + $StatusCode + ' — erreur du serveur SysAudit')
      }
      return ('HTTP ' + $StatusCode)
    }
  }
}

<#
.SYNOPSIS
  Conseil associe a une cause, ou une chaine vide s'il n'en existe pas.

.DESCRIPTION
  « Verifiez votre connexion » n'aide personne et occupe la place du message
  utile : mieux vaut ne rien dire.
#>
function Get-SysAuditNetworkHint {
  param([string]$Cause = '')

  switch -Wildcard ($Cause) {
    '*407*' { return 'Declarez le proxy : .\sysaudit.ps1 -Proxy http://proxy:8080' }
    '*proxy*resout pas*' { return 'Verifiez SYSAUDIT_PROXY, HTTPS_PROXY et HTTP_PROXY.' }
    '*403*' { return 'Un filtrage web bloque la destination. Voir docs/proxy/README.md.' }
    '*inspection HTTPS*' { return 'Une inspection TLS remplace le certificat. Voir docs/proxy/README.md.' }
    '*DNS*' { return 'Le resolveur ne connait pas ce nom, ou un filtrage DNS le refuse.' }
    default { return '' }
  }
}

# --- Test reseau (`-NetworkTest`) -------------------------------------------
#
# Diagnostic **independant de l'audit** : rien n'est collecte, rien n'est ecrit,
# aucun rapport n'est produit. La cible est `GET /api/health`, choisie parce
# qu'elle est en lecture seule — `/api/audit/bootstrap/…` cree une session en
# base, et un test de connectivite n'a pas a laisser de trace.

# Aligne un libelle sur une largeur fixe, a la maniere d'un sommaire.
function Write-SysAuditTestLine {
  param([string]$Label, [string]$Verdict)

  $pad = '..................'
  $filled = if ($Label.Length -lt $pad.Length) { $pad.Substring($Label.Length) } else { '' }
  Write-Host ('  ' + $Label + $filled + ' ' + $Verdict)
}

<#
.SYNOPSIS
  Une requete HEAD, et ce qu'elle a rencontre.

.DESCRIPTION
  Rend un objet portant `ok`, `statusCode` et `cause`. L'appelant decide quoi en
  dire : cette fonction ne rend aucun verdict, elle rapporte.

  `IgnoreCertificate` desactive la validation **pour ce seul appel**, en
  restaurant le rappel precedent dans un `finally`. Sans cette restauration, un
  scanner qui aurait teste le reseau enverrait ensuite son rapport sans verifier
  aucun certificat — exactement ce contre quoi le test cherchait a prevenir.
#>
function Invoke-SysAuditProbe {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [int]$TimeoutSeconds = 15,
    [switch]$IgnoreCertificate
  )

  $previousCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback

  try {
    if ($IgnoreCertificate) {
      [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    }

    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.Method = 'HEAD'
    $request.Timeout = $TimeoutSeconds * 1000
    $request.UserAgent = 'SysAudit-Windows-Scanner/' + $script:SCANNER_VERSION

    $response = $request.GetResponse()
    try {
      return [pscustomobject]@{
        ok = $true
        statusCode = [int]$response.StatusCode
        cause = ''
      }
    } finally {
      $response.Dispose()
    }
  } catch [System.Net.WebException] {
    $status = [string]$_.Exception.Status
    $code = 0
    if ($_.Exception.Response -is [System.Net.HttpWebResponse]) {
      $code = [int]$_.Exception.Response.StatusCode
    }

    # Une reponse HTTP d'erreur n'est pas un echec de transport : le reseau a
    # fonctionne, c'est l'autre bout qui refuse. La distinction porte tout le
    # diagnostic — un 407 prouve que le proxy est joignable.
    $cause = if ($code -gt 0) {
      Get-SysAuditHttpFailure -StatusCode $code
    } else {
      Get-SysAuditTransportFailure -Status $status
    }

    return [pscustomobject]@{ ok = $false; statusCode = $code; cause = $cause }
  } catch {
    return [pscustomobject]@{
      ok = $false
      statusCode = 0
      cause = ('echec reseau : ' + $_.Exception.Message)
    }
  } finally {
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $previousCallback
  }
}

<#
.SYNOPSIS
  Test reseau SysAudit. Ne produit aucun audit.

.DESCRIPTION
  Rend `$true` si l'envoi direct devrait fonctionner, `$false` sinon. L'appelant
  en fait un code de sortie : un ordonnanceur doit pouvoir lire le verdict sans
  analyser le texte affiche.
#>
function Invoke-SysAuditNetworkTest {
  param(
    [Parameter(Mandatory = $true)][string]$ApiUrl,
    [string]$DeclaredProxy = ''
  )

  $base = $ApiUrl.TrimEnd('/')
  $target = $base + '/api/health'

  $uri = $null
  try {
    $uri = [Uri]$base
  } catch {
    throw ('URL d''API illisible : ' + $ApiUrl)
  }

  Write-Host ''
  Write-Host 'Test reseau SysAudit — aucun audit n''est produit.'
  Write-Host ''
  Write-SysAuditTestLine -Label 'Cible' -Verdict $base

  # 1. Proxy. Lecture de configuration : aucun paquet n'est emis.
  if ([string]::IsNullOrWhiteSpace($DeclaredProxy)) {
    Write-SysAuditTestLine -Label 'Proxy' -Verdict 'non declare (le proxy systeme reste en vigueur)'
  } else {
    Write-SysAuditTestLine -Label 'Proxy' -Verdict ('declare (' + $DeclaredProxy + ')')
  }

  # 2. DNS.
  try {
    $null = [System.Net.Dns]::GetHostEntry($uri.Host)
    Write-SysAuditTestLine -Label 'DNS' -Verdict ('OK (' + $uri.Host + ')')
  } catch {
    Write-SysAuditTestLine -Label 'DNS' -Verdict ('ECHEC — ' + $uri.Host + ' ne resout pas')
  }

  # 3. TLS, puis l'API. Une seule requete sert les deux verdicts : la separer en
  #    deux appels doublerait la charge sans rien apprendre de plus.
  $probe = Invoke-SysAuditProbe -Url $target

  if ($probe.ok -or $probe.statusCode -gt 0) {
    # Une reponse HTTP, quelle qu'elle soit, prouve que TLS a abouti.
    Write-SysAuditTestLine -Label 'TLS' -Verdict 'OK'
  } elseif ($probe.cause -like '*certificat non reconnu*' -or $probe.cause -like '*TLS*') {
    $insecure = Invoke-SysAuditProbe -Url $target -IgnoreCertificate
    if ($insecure.ok -or $insecure.statusCode -gt 0) {
      Write-SysAuditTestLine -Label 'TLS' -Verdict 'ECHEC — certificat non reconnu, inspection HTTPS probable'
    } else {
      Write-SysAuditTestLine -Label 'TLS' -Verdict ('ECHEC — ' + $probe.cause)
    }
  } else {
    Write-SysAuditTestLine -Label 'TLS' -Verdict ('non atteint — ' + $probe.cause)
  }

  if ($probe.ok -and $probe.statusCode -eq 200) {
    Write-SysAuditTestLine -Label 'API SysAudit' -Verdict 'OK'
    Write-SysAuditTestLine -Label 'HTTP' -Verdict '200'
    Write-Host ''
    Write-Host 'L''envoi direct devrait fonctionner depuis cette machine.'
    return $true
  }

  if ($probe.statusCode -gt 0) {
    Write-SysAuditTestLine -Label 'API SysAudit' -Verdict 'BLOQUEE'
    Write-SysAuditTestLine -Label 'HTTP' -Verdict $probe.cause
  } else {
    Write-SysAuditTestLine -Label 'API SysAudit' -Verdict ('INJOIGNABLE — ' + $probe.cause)
    Write-SysAuditTestLine -Label 'HTTP' -Verdict 'aucune reponse'
  }

  Write-Host ''
  $hint = Get-SysAuditNetworkHint -Cause $probe.cause
  if (-not [string]::IsNullOrWhiteSpace($hint)) { Write-Host $hint }
  Write-Host 'L''audit reste possible : sans -Upload, le rapport est ecrit localement,'
  Write-Host 'puis se depose sur la page « Deposer un rapport » depuis un poste connecte.'
  return $false
}

# --- Televersement borne dans le temps --------------------------------------

<#
.SYNOPSIS
  Envoie le rapport, avec un delai maximal, et rend le corps de la reponse.

.DESCRIPTION
  Remplace `System.Net.WebClient`, qui **n'expose aucun delai**.

  C'etait le defaut le plus couteux du scanner : un serveur qui accepte la
  connexion puis ne repond jamais laissait la console figee sur « Envoi du
  rapport a … », sans message, sans code de sortie, indefiniment. Tout le
  catalogue de causes de `Get-SysAuditTransportFailure` etait ecrit — « delai
  depasse — filtrage silencieux probable » compris — mais aucune de ces lignes
  ne pouvait etre atteinte, faute d'exception a attraper. L'utilisateur voyait
  un scanner arrete apres l'ecriture du fichier, et concluait que l'audit avait
  echoue alors qu'il etait sur le disque.

  `HttpWebRequest` porte deux delais **distincts**, et les deux comptent :

  - `Timeout` borne l'etablissement de la connexion et l'attente des en-tetes
    de reponse ;
  - `ReadWriteTimeout` borne l'ecriture du corps et sa relecture. Sans lui, un
    serveur qui accepte la requete puis cesse d'emettre bloque dans la lecture
    du flux, la ou `Timeout` a deja fini son office.

  `Expect: 100-continue` est **desactive**. .NET l'envoie par defaut sur toute
  requete POST portant un corps : le client transmet ses en-tetes puis attend
  l'aval du serveur avant d'envoyer le rapport. Les equipements intermediaires
  qui ne renvoient jamais ce `100 Continue` — relais inverses, inspection
  applicative — transforment cette politesse en attente pure. Le rapport tient
  dans quelques centaines de kilo-octets : rien ne justifie de demander la
  permission avant de l'envoyer.

  Les echecs sortent en `System.Net.WebException`, comme avec `WebClient` :
  l'appelant distingue toujours « aucune reponse » de « reponse d'erreur » par
  la presence de `.Response`.
#>
function Invoke-SysAuditUpload {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][byte[]]$Body,
    [hashtable]$Headers = @{},
    [string]$UserAgent = '',
    [int]$TimeoutSeconds = 120
  )

  $request = [System.Net.HttpWebRequest]::Create($Url)
  $request.Method = 'POST'
  $request.ContentType = 'application/json; charset=utf-8'
  $request.Timeout = $TimeoutSeconds * 1000
  $request.ReadWriteTimeout = $TimeoutSeconds * 1000
  $request.ContentLength = $Body.Length
  # `ServicePoint` porte le reglage par hote : le desactiver ici ne touche pas
  # les autres appels du processus.
  $request.ServicePoint.Expect100Continue = $false
  if (-not [string]::IsNullOrWhiteSpace($UserAgent)) { $request.UserAgent = $UserAgent }

  foreach ($name in $Headers.Keys) {
    $value = [string]$Headers[$name]
    if (-not [string]::IsNullOrWhiteSpace($value)) { $request.Headers[[string]$name] = $value }
  }

  $stream = $request.GetRequestStream()
  try {
    $stream.Write($Body, 0, $Body.Length)
  } finally {
    $stream.Dispose()
  }

  $response = $request.GetResponse()
  try {
    $reader = New-Object System.IO.StreamReader(
      $response.GetResponseStream(), (New-Object System.Text.UTF8Encoding($false)))
    try {
      return $reader.ReadToEnd()
    } finally {
      $reader.Dispose()
    }
  } finally {
    $response.Dispose()
  }
}
