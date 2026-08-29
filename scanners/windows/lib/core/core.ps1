# SysAudit Windows — socle d'execution.
#
# Deux responsabilites : savoir si le scan est privilegie, et isoler chaque
# collecteur. L'isolation est la raison d'etre de ce fichier : avant
# l'extraction, `$ErrorActionPreference = 'Stop'` faisait qu'une seule requete
# CIM en echec interrompait l'audit complet, sur la machine auditee, sans
# rapport partiel ni explication.

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Problemes rencontres pendant la collecte, rapportes dans `collection.issues`.
$script:CollectionIssues = @()
$script:CollectionProvenance = @{}
$script:CollectionTimings = @()

<#
.SYNOPSIS
  Temperatures relevees hors du collecteur de capteurs.

.DESCRIPTION
  Le stockage lit la temperature de chaque disque en meme temps que ses
  compteurs de fiabilite. La relire depuis `Get-SensorSection` couterait une
  seconde requete `Get-StorageReliabilityCounter` par disque — la partie la plus
  lente de la section — et pourrait rendre deux valeurs differentes pour un
  meme capteur.

  Elles sont donc deposees ici, et `Get-SensorSection` les ramasse. C'est la
  raison pour laquelle il est appele **apres** le stockage ; l'ordre du rapport,
  lui, est fixe a l'assemblage et ne depend pas de cet appel.
#>
$script:ThermalReadings = @()

function Add-ThermalReading {
  param(
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][double]$Celsius,
    [Parameter(Mandatory = $true)][string]$Category,
    [string]$Device = '',
    [string]$Source = '',
    [string]$Scope = 'LOCAL'
  )

  $reading = @{
    label = $Label
    celsius = [Math]::Round($Celsius, 1)
    category = $Category
    scope = $Scope
    quality = 'MEASURED'
  }
  if (-not [string]::IsNullOrWhiteSpace($Device)) { $reading.device = $Device }
  if (-not [string]::IsNullOrWhiteSpace($Source)) { $reading.source = $Source }

  $script:ThermalReadings += $reading
}

function Get-ThermalReadingList {
  return $script:ThermalReadings
}

<#
.SYNOPSIS
  Declare une collecte qui n'a pas eu lieu, avec son motif.

.DESCRIPTION
  Le motif (`-Reason`) est lu par la plateforme pour decider du statut de
  l'audit ; le message, lui, s'adresse a un humain. Les valeurs admises sont
  celles de `collectionIssueReasonSchema`, cote TypeScript.

  Les quatre premieres decrivent une absence voulue ou sans objet : un audit
  qui n'en porte que de celles-la est un audit reussi. Les deux suivantes une
  collecte attendue et manquee pour une cause connue. Les deux dernieres une
  anomalie.

  Le motif est laisse vide quand l'issue ne decrit pas une absence. Une issue
  sans motif n'est pas classable : la plateforme la traite comme une collecte
  manquee, ce qui est la lecture prudente.
#>
function Add-CollectionIssue {
  param(
    [Parameter(Mandatory = $true)][string]$Section,
    [ValidateSet('warning', 'error')][string]$Severity = 'warning',
    [Parameter(Mandatory = $true)][string]$Message,
    [string]$Source = '',
    [ValidateSet('', 'NOT_COLLECTED', 'NOT_REQUESTED', 'NOT_APPLICABLE', 'UNSUPPORTED',
      'PERMISSION_DENIED', 'NOT_AVAILABLE', 'TIMEOUT', 'COLLECTOR_ERROR')]
    [string]$Reason = ''
  )

  $issue = @{
    section = $Section
    severity = $Severity
    message = $Message
  }
  if (-not [string]::IsNullOrWhiteSpace($Source)) { $issue.source = $Source }
  if (-not [string]::IsNullOrWhiteSpace($Reason)) { $issue.reason = $Reason }

  $script:CollectionIssues += $issue
}

function Get-CollectionIssueList {
  return $script:CollectionIssues
}

<#
.SYNOPSIS
  Delai d'attente avant de renvoyer un rapport refuse pour quota.

.DESCRIPTION
  Trois sources, dans cet ordre, parce qu'aucune n'est garantie :

   1. l'en-tete `Retry-After`, que pose `@fastify/rate-limit` ;
   2. le champ `retryAfterSeconds` du corps JSON ;
   3. le nombre annonce dans le message, en dernier recours — l'API dit
      « retry in 12 seconds » meme quand le reste manque.

  Le resultat est borne. Sans plancher, un `Retry-After: 0` ferait boucler
  l'envoi aussi vite que le refus arrive ; sans plafond, un en-tete aberrant
  laisserait le scanner attendre des heures sur une machine que l'utilisateur
  croit en train de travailler.
#>
function Get-RetryAfterSeconds {
  param(
    [string]$Header = '',
    [string]$Body = '',
    [int]$Minimum = 1,
    [int]$Maximum = 120
  )

  $seconds = 0

  if ($Header -match '^\s*(\d+)\s*$') { $seconds = [int]$Matches[1] }

  if ($seconds -le 0 -and $Body -match '"retryAfterSeconds"\s*:\s*(\d+)') {
    $seconds = [int]$Matches[1]
  }

  if ($seconds -le 0 -and $Body -match '(\d+)\s*second') { $seconds = [int]$Matches[1] }

  if ($seconds -le 0) { $seconds = $Minimum }
  if ($seconds -lt $Minimum) { $seconds = $Minimum }
  if ($seconds -gt $Maximum) { $seconds = $Maximum }

  return $seconds
}

<#
.SYNOPSIS
  Adresse du proxy a emprunter, ou une chaine vide pour « aucun ».

.DESCRIPTION
  Windows PowerShell 5.1 ne lit ni HTTPS_PROXY ni HTTP_PROXY, contrairement a
  PowerShell 7 : sur un poste d'entreprise ou ces variables sont la convention,
  le scanner partait en connexion directe et echouait sans dire pourquoi.

  L'ordre va du plus explicite au plus implicite, et la premiere valeur
  renseignee l'emporte :

    1. -Proxy, passe en ligne de commande ;
    2. SYSAUDIT_PROXY, qui ne vaut que pour cet outil ;
    3. HTTPS_PROXY, puis HTTP_PROXY, la convention commune.

  Une chaine vide signifie « rien de declare » — et NON « pas de proxy » : le
  proxy systeme de Windows reste alors en vigueur, c'est .NET qui le choisit.

  NO_PROXY n'est **pas** lu. Le dire vaut mieux que le lire a moitie : sa syntaxe
  (suffixes, jokers, plages) ne se traduit pas fidelement en liste d'exclusion
  .NET, qui attend des expressions regulieres. Une exclusion mal traduite
  enverrait au proxy un hote qui devait l'eviter, sans que rien ne le signale.
#>
function Resolve-SysAuditProxyUrl {
  param(
    [string]$Explicit = '',
    [string]$SysAuditProxy = '',
    [string]$HttpsProxy = '',
    [string]$HttpProxy = ''
  )

  foreach ($candidate in @($Explicit, $SysAuditProxy, $HttpsProxy, $HttpProxy)) {
    if (-not [string]::IsNullOrWhiteSpace($candidate)) { return $candidate.Trim() }
  }

  return ''
}

<#
.SYNOPSIS
  Applique le proxy a tout ce que ce processus emettra ensuite.

.DESCRIPTION
  Deux defauts sont repares ici, et ils sont independants.

  **Les identifiants.** PowerShell 5.1 emprunte bien le proxy systeme, mais ne
  lui presente jamais d'identifiants : un proxy NTLM ou Kerberos — le cas
  courant en entreprise — repond 407, et l'envoi du rapport echoue apres une
  collecte pourtant reussie. Les identifiants de la session ouverte ne quittent
  pas la machine : c'est Windows qui repond au defi du proxy.

  **L'adresse.** Voir `Resolve-SysAuditProxyUrl` pour l'ordre de decision.

  Le reglage passe par `DefaultWebProxy`, donc vaut pour `Invoke-WebRequest`
  comme pour `WebClient`, sans avoir a le repeter a chaque appel. Il ne survit
  pas au processus : rien n'est ecrit dans le registre ni dans l'environnement,
  et le scanner reste en lecture seule.

  Rend l'adresse appliquee — sans identifiants, pour qu'un appelant puisse
  l'afficher — ou une chaine vide si le proxy systeme a ete laisse tel quel.
#>
function Set-SysAuditProxy {
  param([string]$ProxyUrl = '')

  if ([string]::IsNullOrWhiteSpace($ProxyUrl)) {
    # Rien de declare : on garde le proxy systeme, en lui ajoutant seulement ce
    # qui lui manquait — de quoi s'authentifier.
    if ($null -ne [System.Net.WebRequest]::DefaultWebProxy) {
      [System.Net.WebRequest]::DefaultWebProxy.Credentials =
        [System.Net.CredentialCache]::DefaultCredentials
    }
    return ''
  }

  # Une adresse sans schema (`proxy:8080`) serait lue comme un chemin relatif :
  # on la prefixe plutot que de la refuser, c'est la forme la plus souvent tapee.
  $normalized = $ProxyUrl
  if ($normalized -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') { $normalized = 'http://' + $normalized }

  $uri = [Uri]$normalized

  # Construit depuis l'hote et le port, jamais depuis l'URL complete : un
  # `http://domaine\user:motdepasse@proxy:8080` inscrirait sinon le mot de passe
  # dans l'adresse du proxy, donc dans tout ce qui l'affiche ou la journalise.
  $proxy = New-Object System.Net.WebProxy($uri.Host, $uri.Port)
  $proxy.BypassProxyOnLocal = $true

  if ([string]::IsNullOrWhiteSpace($uri.UserInfo)) {
    $proxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
  } else {
    # `user:motdepasse`, chacun encode pour l'URL : un mot de passe contenant
    # `@` ou `/` ne peut voyager autrement.
    $pair = $uri.UserInfo.Split(':', 2)
    $user = [Uri]::UnescapeDataString($pair[0])
    $secret = if ($pair.Length -gt 1) { [Uri]::UnescapeDataString($pair[1]) } else { '' }
    $proxy.Credentials = New-Object System.Net.NetworkCredential($user, $secret)
  }

  [System.Net.WebRequest]::DefaultWebProxy = $proxy

  return ($uri.Host + ':' + $uri.Port)
}

# Au-dela d'une journee, la valeur ne mesure plus un audit mais une anomalie de
# mesure : meme le profil `stress` reste tres en deca.
$script:MaxAuditDurationMs = 86400000

<#
.SYNOPSIS
  Duree d'audit en millisecondes, ou $null si la mesure n'est pas exploitable.

.DESCRIPTION
  Le chronometre qui alimente cette fonction est monotone, contrairement a une
  difference de `Get-Date` : un recalage NTP en cours d'audit ne le fait ni
  reculer ni bondir. C'est le defaut qui, sur le scanner Linux, produisait une
  duree de plusieurs milliers d'annees sur une machine virtuelle dont l'horloge
  materielle partait d'une date aberrante.

  Reste a ecarter ce qui n'a de toute facon pas de sens. Le champ est facultatif
  dans le schema : mieux vaut l'omettre, avec sa raison au journal de collecte,
  que publier un nombre faux — la regle est la meme que pour un compteur SMART
  non lu.

  Le plafond protege aussi d'un debordement. La conversion `[int]` s'arrete a
  24,8 jours et levait une exception au-dela : le scanner perdait alors le
  rapport entier, la ou il ne devait perdre qu'un champ facultatif.
#>
function Get-AuditDurationMs {
  param([Nullable[double]]$ElapsedMs = $null)

  if ($null -eq $ElapsedMs) { return $null }

  $ms = [double]$ElapsedMs
  if ([double]::IsNaN($ms) -or [double]::IsInfinity($ms)) { return $null }
  if ($ms -lt 0 -or $ms -gt $script:MaxAuditDurationMs) { return $null }

  return [int][Math]::Floor($ms)
}

<#
.SYNOPSIS
  Rapporte un probleme au plus une fois.

.DESCRIPTION
  Certains collecteurs repassent au meme endroit un grand nombre de fois : une
  observation d'une minute releve les memes compteurs soixante fois, et une
  inspection Docker se repete par conteneur. Si la source est indisponible, elle
  l'est a chaque passage.

  Sans deduplication, `collection.issues` recevait soixante fois la meme phrase,
  et le seul probleme reellement distinct devenait introuvable au milieu. Le
  couple section-message sert de cle : deux echecs de la meme lecture sont le
  meme probleme, deux echecs de lectures differentes n'en sont pas un.
#>
function Add-CollectionIssueOnce {
  param(
    [Parameter(Mandatory = $true)][string]$Section,
    [ValidateSet('warning', 'error')][string]$Severity = 'warning',
    [Parameter(Mandatory = $true)][string]$Message,
    [string]$Source = '',
    [string]$Reason = ''
  )

  foreach ($existing in $script:CollectionIssues) {
    if ($existing.section -eq $Section -and $existing.message -eq $Message) { return }
  }

  Add-CollectionIssue -Section $Section -Severity $Severity -Message $Message -Source $Source -Reason $Reason
}

function Add-CollectionProvenance {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Source,
    [string]$Method = '',
    [string]$Precision = '',
    [string]$CollectedAt = ''
  )

  if ([string]::IsNullOrWhiteSpace($CollectedAt)) {
    $CollectedAt = (Get-Date).ToUniversalTime().ToString('o')
  }

  $entry = @{
    source = $Source
    collectedAt = $CollectedAt
  }
  if (-not [string]::IsNullOrWhiteSpace($Method)) { $entry.method = $Method }
  if (-not [string]::IsNullOrWhiteSpace($Precision)) { $entry.precision = $Precision }

  $script:CollectionProvenance[$Path] = $entry
}

function Get-CollectionProvenance {
  return $script:CollectionProvenance
}

<#
.SYNOPSIS
  Enregistre le temps passe dans un collecteur.

.DESCRIPTION
  Alimente l'estimation de duree affichee avant l'audit, jusqu'ici une constante
  ecrite a la main. Une duree negative — horloge ajustee pendant la collecte —
  n'est pas enregistree : le champ absent se lit « on ne sait pas », la ou un
  zero se lirait « instantane » et fausserait la mediane.
#>
function Add-CollectionTiming {
  param(
    [Parameter(Mandatory = $true)][string]$Section,
    [Parameter(Mandatory = $true)][long]$DurationMs
  )

  if ($DurationMs -lt 0) { return }

  $script:CollectionTimings += [pscustomobject]@{
    section = $Section
    durationMs = $DurationMs
  }
}

function Get-CollectionTimings {
  return $script:CollectionTimings
}

<#
.SYNOPSIS
  Execute un collecteur en l'empechant d'interrompre l'audit.

.DESCRIPTION
  L'echec d'un collecteur devient un probleme rapporte et une section absente,
  jamais un audit interrompu. Un rapport partiel qui dit ce qui manque vaut
  mieux qu'une absence de rapport : c'est la seule difference visible pour la
  personne qui lance le scan.
#>
function Invoke-Collector {
  param(
    [Parameter(Mandatory = $true)][string]$Section,
    [Parameter(Mandatory = $true)][scriptblock]$Body,
    [string]$Label = ''
  )

  # Point de passage unique des collecteurs : c'est donc ici, et nulle part
  # ailleurs, que la progression avance.
  $step = if ([string]::IsNullOrWhiteSpace($Label)) { $Section } else { $Label }
  Write-ConsoleProgressStep -Label $step

  # Chronometre monotone, insensible a un ajustement d'horloge survenant pendant
  # la collecte. Mesure prise ici pour la meme raison que la progression : c'est
  # le seul point par lequel tous les collecteurs passent.
  $watch = [System.Diagnostics.Stopwatch]::StartNew()

  try {
    $result = & $Body
    $watch.Stop()
    Add-CollectionTiming -Section $Section -DurationMs $watch.ElapsedMilliseconds
    return $result
  } catch {
    # Un collecteur qui echoue au bout de vingt secondes a bel et bien coute
    # vingt secondes : c'est cette duree-la que l'estimation doit refleter.
    $watch.Stop()
    Add-CollectionTiming -Section $Section -DurationMs $watch.ElapsedMilliseconds
    Add-CollectionIssue -Section $Section -Severity 'error' `
      -Message ('Collecteur interrompu : ' + $_.Exception.Message) -Source 'collector' `
      -Reason 'COLLECTOR_ERROR'
    return $null
  } finally {
    # La progression avance ici, et une seule fois. Elle etait avancee dans les
    # deux branches : un echec de l'affichage la faisait donc echouer une
    # seconde fois, hors du `catch` qui venait de la rattraper — et cette
    # deuxieme levee, elle, remontait jusqu'a interrompre l'audit.
    Complete-ConsoleProgressStep
  }
}
