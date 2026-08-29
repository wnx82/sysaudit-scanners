# SysAudit Windows — historique, stabilite, demarrage et arret.
#
# L'inventaire dit qu'un disque existe ; seul l'Observateur d'evenements dit
# qu'il jette une erreur toutes les nuits depuis trois semaines. Ce collecteur
# lit ce que Windows a **deja ecrit** : il n'active aucun canal, ne change aucun
# niveau de trace, n'ecrit nulle part.
#
# Trois regles gouvernent ce fichier, les memes que cote Linux :
#
#   1. un compteur ne part jamais sans sa fenetre — « trois pannes » est
#      rassurant sur un an et alarmant sur une journee ;
#   2. la fenetre demandee n'est pas la fenetre obtenue — un journal Systeme
#      limite a 20 Mo tourne en quelques jours sur une machine bavarde ;
#   3. la severite vient du journal, jamais du scanner. Decider qu'un
#      avertissement est en realite critique est une analyse, et l'analyse se
#      recalcule sur des rapports deja collectes.

# Fenetre d'historique demandee, en jours.
$script:HistoryDays = 30

<#
.SYNOPSIS
  Categorie commune d'un evenement Windows.

.DESCRIPTION
  Le classement s'appuie d'abord sur le **fournisseur et l'identifiant**, qui
  sont stables et documentes, et seulement ensuite sur le texte. L'ordre compte :
  un `Microsoft-Windows-Kernel-Power` 41 est un arret inattendu, quel que soit
  le libelle — lequel est traduit dans la langue du systeme et ne peut donc pas
  servir de critere principal.

  C'est la difference majeure avec le collecteur Linux : sous Windows, les
  identifiants sont invariants la ou les messages sont localises.
#>
function Get-EventCategory {
  param(
    [string]$Provider,
    [int]$Id,
    [string]$Message
  )

  switch -Regex ($Provider) {
    # Ecran bleu : WER-SystemErrorReporting 1001 et BugCheck 1001.
    'WER-SystemErrorReporting|^BugCheck$' { return 'KERNEL_CRASH' }
    'WHEA-Logger' { return 'HARDWARE' }
    'Kernel-Power' {
      # 41 est l'arret sans extinction propre ; les autres identifiants de ce
      # fournisseur decrivent des transitions d'alimentation ordinaires.
      if ($Id -eq 41) { return 'POWER' }
      return 'POWER'
    }
    'EventLog' {
      # 6008 : arret inattendu, ecrit au demarrage suivant.
      if ($Id -eq 6008) { return 'POWER' }
      return 'OTHER'
    }
    '^(disk|storahci|stornvme|iaStorA|storvsc|msiscsi)$' { return 'STORAGE' }
    '^(Ntfs|volmgr|volsnap|refs)$' { return 'FILESYSTEM' }
    'Application Error|Windows Error Reporting|Application Hang' { return 'APPLICATION_CRASH' }
    'Service Control Manager' { return 'SERVICE' }
    'Microsoft-Windows-WindowsUpdateClient|Servicing' { return 'UPDATE' }
    'Microsoft-Windows-Security-Auditing|Defender' { return 'SECURITY' }
    'Microsoft-Windows-Kernel-PnP|Microsoft-Windows-DriverFrameworks' { return 'DRIVER' }
    'Microsoft-Windows-Diagnostics-Performance' { return 'BOOT' }
    'Tcpip|NDIS|Microsoft-Windows-NetworkProfile|e1[a-z]express|netwtw' { return 'NETWORK' }
    'Microsoft-Windows-Hyper-V' { return 'VIRTUALIZATION' }
  }

  # Repli sur le texte, en dernier recours seulement : il est traduit.
  if ($Message -match 'thermal|temperature|throttl') { return 'THERMAL' }
  if ($Message -match 'memory|m..moire') { return 'MEMORY' }
  return 'OTHER'
}

<#
.SYNOPSIS
  Empreinte de regroupement d'un evenement.

.DESCRIPTION
  Un disque qui meurt ecrit la meme ligne des milliers de fois. Sans
  regroupement, la borne du tableau couperait au millieme doublon et cacherait
  tous les autres incidents — c'est-a-dire exactement ceux qu'on cherche.

  Sous Windows, l'empreinte se construit sur le **couple fournisseur +
  identifiant**, invariant, plutot que sur le message, qui est localise. Deux
  machines de langues differentes produisent ainsi la meme empreinte pour le
  meme incident.
#>
function Get-EventFingerprint {
  param(
    [string]$Provider,
    [int]$Id
  )
  return ('{0}/{1}' -f $Provider, $Id)
}

<#
.SYNOPSIS
  Severite telle que le journal la rapporte.

.DESCRIPTION
  `Level` : 1 = Critical, 2 = Error, 3 = Warning, 4 = Information. Le scanner
  transpose, il ne reevalue pas.
#>
function Get-EventSeverity {
  param([int]$Level)
  switch ($Level) {
    1 { return 'CRITICAL' }
    2 { return 'ERROR' }
    3 { return 'WARNING' }
    default { return 'INFO' }
  }
}

<#
.SYNOPSIS
  Evenements d'un journal, regroupes par empreinte.

.DESCRIPTION
  `Get-WinEvent -FilterHashtable` filtre **cote service**, ce qui evite de
  rapatrier des centaines de milliers d'enregistrements pour n'en garder que
  quelques-uns. Un canal absent ou vide leve une exception, que le collecteur
  traite comme « rien a lire » et non comme un echec — un journal Application
  vide sur une machine neuve est un cas normal.
#>
function Get-WinEventGroup {
  param(
    [string]$LogName,
    [int]$Days,
    [int]$MaxEvents = 2000
  )

  $since = (Get-Date).AddDays(-$Days)
  $records = @()
  try {
    $records = @(Get-WinEvent -FilterHashtable @{
        LogName = $LogName
        Level = @(1, 2)
        StartTime = $since
      } -MaxEvents $MaxEvents -ErrorAction Stop)
  } catch {
    # « No events were found » n'est pas une erreur de lecture. Un refus
    # d'acces, si : les deux se distinguent par le type d'exception.
    $unreadable = $_.Exception
    if ($unreadable -is [System.UnauthorizedAccessException]) {
      Add-CollectionIssueOnce -Section 'events' -Severity 'warning' `
        -Message ("Journal $LogName inaccessible : privileges insuffisants.") -Source 'Get-WinEvent' -Reason 'PERMISSION_DENIED'
    }
    return @{ groups = @(); examined = 0; readable = $false }
  }

  $groups = @{}
  foreach ($record in $records) {
    $provider = [string]$record.ProviderName
    $id = [int]$record.Id
    $key = Get-EventFingerprint -Provider $provider -Id $id
    $message = ''
    if ($record.Message) { $message = ([string]$record.Message).Trim() }
    if ($message.Length -gt 400) { $message = $message.Substring(0, 400) }
    $at = $record.TimeCreated.ToUniversalTime()

    if (-not $groups.ContainsKey($key)) {
      $groups[$key] = @{
        category = Get-EventCategory -Provider $provider -Id $id -Message $message
        severity = Get-EventSeverity -Level ([int]$record.Level)
        provider = $provider
        nativeId = [string]$id
        first = $at
        last = $at
        occurrences = 0
        summary = $message
        fingerprint = $key
        source = $LogName
        evidence = @()
      }
    }

    $group = $groups[$key]
    $group.occurrences += 1
    if ($at -lt $group.first) { $group.first = $at }
    if ($at -gt $group.last) { $group.last = $at }

    # Trois extraits au plus, et **distincts** : le regroupement rassemble des
    # lignes qui ne different que par un PID ou un chemin, et trois copies
    # identiques occuperaient la place de la preuve utile sans rien ajouter.
    if ($group.evidence.Count -lt 3 -and $message -ne '' -and $group.evidence -notcontains $message) {
      $group.evidence += $message
    }
  }

  return @{ groups = @($groups.Values); examined = $records.Count; readable = $true }
}

<#
.SYNOPSIS
  Fenetre reellement couverte par un journal.

.DESCRIPTION
  Demander trente jours a un journal Systeme limite a 20 Mo n'en donne pas
  trente : sur une machine bavarde, il tourne en quelques jours. Sans cette
  lecture, « aucun incident » se lirait comme un mois sain.

  L'enregistrement le plus ancien est lu par `-Oldest`, un seul evenement : le
  cout est negligeable devant celui du filtre principal.
#>
function Get-EventLogWindow {
  param([string]$LogName)

  try {
    $oldest = Get-WinEvent -LogName $LogName -Oldest -MaxEvents 1 -ErrorAction Stop
    if ($null -ne $oldest) {
      return $oldest.TimeCreated.ToUniversalTime()
    }
  } catch {
    # Canal absent ou vide : il n'y a pas de plus ancien enregistrement, ce qui
    # n'est pas une erreur. La fenetre restera inconnue plutot que supposee.
    Write-Debug ('Fenetre du journal ' + $LogName + ' indeterminable : ' + $_.Exception.Message)
    return $null
  }
  return $null
}

function Get-EventsSection {
  param([int]$Days = 0)

  if ($Days -le 0) { $Days = $script:HistoryDays }

  $logs = @('System', 'Application')
  $allGroups = @()
  $examined = 0
  $readable = $false
  $oldest = $null

  foreach ($log in $logs) {
    $result = Get-WinEventGroup -LogName $log -Days $Days
    if ($result.readable) { $readable = $true }
    $allGroups += $result.groups
    $examined += $result.examined

    $logOldest = Get-EventLogWindow -LogName $log
    if ($null -ne $logOldest) {
      # La fenetre couverte est celle du journal qui remonte le **moins** loin :
      # annoncer la plus longue laisserait croire que tous les canaux la
      # couvrent.
      if ($null -eq $oldest -or $logOldest -gt $oldest) { $oldest = $logOldest }
    }
  }

  if (-not $readable) {
    Add-CollectionIssueOnce -Section 'events' -Severity 'warning' `
      -Message 'Aucun journal d''evenements lisible : historique non collecte.' -Source 'Get-WinEvent' -Reason 'NOT_AVAILABLE'
    return $null
  }

  $now = (Get-Date).ToUniversalTime()
  $requestedMs = [int64]$Days * 86400000

  $coveredMs = New-Unknown -Reason 'UNKNOWN' -Detail 'plus ancien enregistrement non datable'
  $since = New-Unknown -Reason 'UNKNOWN' -Detail 'plus ancien enregistrement non datable'
  if ($null -ne $oldest) {
    # Le journal peut remonter plus loin que la fenetre demandee : dans ce cas,
    # la couverture *est* la fenetre demandee, pas l'age du journal.
    $span = [int64]($now - $oldest).TotalMilliseconds
    if ($span -lt 0) { $span = 0 }
    $coveredMs = [Math]::Min($span, $requestedMs)
    $since = $oldest.ToString('o')
  }

  $entries = @()
  $truncated = $false
  foreach ($group in ($allGroups | Sort-Object -Property { $_.last } -Descending)) {
    if ($entries.Count -ge 500) { $truncated = $true; break }
    $entries += @{
      category = $group.category
      severity = $group.severity
      provider = $group.provider
      nativeId = $group.nativeId
      firstSeenAt = $group.first.ToString('o')
      lastSeenAt = $group.last.ToString('o')
      occurrences = $group.occurrences
      summary = if ([string]::IsNullOrWhiteSpace($group.summary)) { '(message non publie par le fournisseur)' } else { $group.summary }
      fingerprint = $group.fingerprint
      source = $group.source
      evidence = @($group.evidence)
    }
  }

  Add-CollectionProvenance -Path 'events.entries' -Source 'Get-WinEvent' `
    -Method 'journal Windows' -Precision 'incident regroupe'

  return @{
    window = @{
      requestedMs = $requestedMs
      coveredMs = $coveredMs
      since = $since
      until = $now.ToString('o')
      # Les journaux Windows sont ecrits sur disque et survivent au
      # redemarrage : contrairement a journald, il n'y a pas de mode volatile.
      persistent = $true
    }
    examined = $examined
    truncated = $truncated
    entries = $entries
    meta = @{
      source = 'Get-WinEvent'
      method = 'journal Windows'
      collectedAt = $now.ToString('o')
      observationWindowMs = $coveredMs
    }
  }
}

<#
.SYNOPSIS
  Pourquoi il n'y a pas de journal a lire, dit exactement.

.DESCRIPTION
  Trois situations produisent la meme absence et n'appellent pas la meme
  reponse du lecteur :

  - la section a ete ecartee a la demande (`-Skip events`) ;
  - le niveau choisi ne la prevoit pas — relancer plus haut suffit ;
  - le journal a bien ete ouvert, et n'a rien rendu d'exploitable.

  Seule la troisieme est un defaut. Les confondre envoyait chercher une panne
  du journal Windows apres un audit Rapide, qui ne l'avait pas ouvert.
#>
function Get-EventsAbsenceMarker {
  if (Test-SectionExcluded -Section 'events') {
    return (New-Unknown -Reason 'NOT_COLLECTED' -Detail 'section ecartee par -Skip')
  }

  if (-not (Test-LevelCollectsSection -Section 'events')) {
    $needed = Get-FirstLevelCollecting -Section 'events'
    if ([string]::IsNullOrWhiteSpace($needed)) {
      return (New-Unknown -Reason 'UNSUPPORTED' `
          -Detail 'historique non collecte par le scanner Windows, quel que soit le niveau')
    }
    return (New-Unknown -Reason 'NOT_COLLECTED' `
        -Detail ('historique non collecte au niveau ' + (Get-LevelLabel -Level (Get-CurrentLevel)) +
          ' : relancer au niveau ' + (Get-LevelLabel -Level $needed)))
  }

  return (New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'aucun journal d''evenements lisible')
}

<#
.SYNOPSIS
  Compteur d'incidents d'une categorie, avec sa fenetre.

.DESCRIPTION
  Zero n'est publie que si le journal a **reellement** ete parcouru. Sans cela,
  un compteur nul affirmerait « regarde, rien trouve » sans avoir regarde.
#>
function Get-IncidentCount {
  param(
    $Events,
    [string]$Category,
    $Absent
  )

  if ($null -eq $Events) {
    # Le motif vient de l'appelant, qui seul sait **pourquoi** il n'y a pas de
    # journal a lire. Sans lui, les treize compteurs affirmaient tous
    # « aucun journal d'evenements lisible » — y compris au niveau Rapide, ou
    # la section n'est simplement pas demandee. Le rapport declarait donc un
    # journal Windows en panne sur une machine ou personne ne l'avait ouvert,
    # et le lecteur cherchait une avarie inexistante.
    $unknown = if ($null -ne $Absent) { $Absent } else {
      New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'aucun journal d''evenements lisible'
    }
    return @{
      count = $unknown
      observationWindowMs = $unknown
      lastAt = $unknown
      source = $unknown
    }
  }

  $matching = @($Events.entries | Where-Object { $_.category -eq $Category })
  $total = 0
  foreach ($entry in $matching) { $total += $entry.occurrences }

  $lastAt = New-Unknown -Reason 'NOT_APPLICABLE' -Detail 'aucun incident de cette categorie sur la fenetre'
  if ($matching.Count -gt 0) {
    $lastAt = ($matching | Sort-Object -Property lastSeenAt -Descending | Select-Object -First 1).lastSeenAt
  }

  return @{
    count = $total
    observationWindowMs = $Events.window.coveredMs
    lastAt = $lastAt
    source = 'Get-WinEvent'
  }
}

$script:ServiceFailureEventIds = @(7000, 7001, 7009, 7011, 7022, 7023, 7024, 7031, 7034, 7043)

function Test-ServiceEventMentionsService {
  param(
    $ScmEvent,
    [string]$Name,
    [string]$DisplayName
  )

  $needles = @($Name, $DisplayName) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
  if ($needles.Count -eq 0) { return $false }

  $texts = @($ScmEvent.summary) + @($ScmEvent.evidence)
  foreach ($text in $texts) {
    if ([string]::IsNullOrWhiteSpace([string]$text)) { continue }
    foreach ($needle in $needles) {
      $pattern = '(^|[^A-Za-z0-9_.-])' + [regex]::Escape([string]$needle) + '([^A-Za-z0-9_.-]|$)'
      if ([string]$text -match $pattern) { return $true }
    }
  }

  return $false
}

function Get-ServiceFailureEvidence {
  param(
    $Service,
    $Events
  )

  $proofs = @()
  $exitCode = $null
  if ($null -ne $Service.ExitCode -and [int64]::TryParse([string]$Service.ExitCode, [ref]$exitCode) -and $exitCode -ne 0) {
    $proofs += ('ExitCode={0}' -f $exitCode)
  }

  $serviceSpecificExitCode = $null
  if ($null -ne $Service.ServiceSpecificExitCode -and [int64]::TryParse([string]$Service.ServiceSpecificExitCode, [ref]$serviceSpecificExitCode) -and $serviceSpecificExitCode -ne 0) {
    $proofs += ('ServiceSpecificExitCode={0}' -f $serviceSpecificExitCode)
  }

  $matchingEvents = @()
  if ($null -ne $Events -and $null -ne $Events.entries) {
    $matchingEvents = @($Events.entries | Where-Object {
        $nativeId = 0
        [string]$_.provider -eq 'Service Control Manager' -and
        [int]::TryParse([string]$_.nativeId, [ref]$nativeId) -and
        $script:ServiceFailureEventIds -contains $nativeId -and
        (Test-ServiceEventMentionsService -ScmEvent $_ -Name ([string]$Service.Name) -DisplayName ([string]$Service.DisplayName))
      } | Sort-Object -Property lastSeenAt -Descending)
  }

  if ($matchingEvents.Count -gt 0) {
    $scmEvent = $matchingEvents | Select-Object -First 1
    $proofs += ('SCM {0}' -f $scmEvent.nativeId)
  }

  return @{
    proofs = $proofs
    event = if ($matchingEvents.Count -gt 0) { $matchingEvents | Select-Object -First 1 } else { $null }
  }
}

function Convert-WindowsServiceToStabilityUnit {
  param(
    $Service,
    [string[]]$Reasons,
    $ScmEvent
  )

  $since = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'Win32_Service ne date pas le changement d''etat'
  if ($null -ne $ScmEvent -and -not [string]::IsNullOrWhiteSpace([string]$ScmEvent.lastSeenAt)) {
    $since = [string]$ScmEvent.lastSeenAt
  }

  $resultParts = @()
  if ($null -ne $Service.ExitCode) { $resultParts += ('ExitCode={0}' -f $Service.ExitCode) }
  if ($null -ne $Service.ServiceSpecificExitCode) {
    $resultParts += ('ServiceSpecificExitCode={0}' -f $Service.ServiceSpecificExitCode)
  }
  if ($resultParts.Count -eq 0) { $resultParts += 'code de sortie non publie' }

  $source = 'Win32_Service'
  if ($null -ne $ScmEvent) { $source = 'Win32_Service, Service Control Manager' }

  return @{
    name = [string]$Service.Name
    state = Get-StringOrUnknown -Value $Service.State -Reason 'UNKNOWN'
    result = ($resultParts -join '; ')
    since = $since
    restarts = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'compteur de redemarrages non expose par Win32_Service'
    startup = Get-StringOrUnknown -Value $Service.StartMode -Reason 'UNKNOWN'
    reason = if ($Reasons.Count -gt 0) { $Reasons -join '; ' } else { 'arrete sans preuve d''echec' }
    source = $source
  }
}

function Get-WindowsServiceStabilityUnits {
  param(
    $Services,
    $Events
  )

  $failedUnits = @()
  $stoppedUnits = @()

  foreach ($service in @($Services)) {
    if ([string]::IsNullOrWhiteSpace([string]$service.Name)) { continue }
    if ([string]$service.State -eq 'Running') { continue }

    $evidence = Get-ServiceFailureEvidence -Service $service -Events $Events
    if ($evidence.proofs.Count -gt 0) {
      $failedUnits += Convert-WindowsServiceToStabilityUnit -Service $service -Reasons $evidence.proofs -ScmEvent $evidence.event
      if ($failedUnits.Count -ge 200) { break }
      continue
    }

    if ([string]$service.StartMode -eq 'Auto' -and $stoppedUnits.Count -lt 200) {
      $stoppedUnits += Convert-WindowsServiceToStabilityUnit -Service $service -Reasons @() -ScmEvent $null
    }
  }

  return @{ failedUnits = $failedUnits; stoppedUnits = $stoppedUnits }
}

function Get-StabilitySection {
  param($Events)

  # Calcule une fois : les treize compteurs, le compteur de redemarrages et sa
  # fenetre partagent le meme motif d'absence, et deux motifs pour une meme
  # cause se contrediraient dans le rapport.
  $absent = Get-EventsAbsenceMarker

  $uptimeSeconds = New-Unknown -Reason 'NOT_AVAILABLE'
  $bootedAt = New-Unknown -Reason 'NOT_AVAILABLE'
  try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $boot = $os.LastBootUpTime
    if ($boot) {
      $bootUtc = ([DateTime]$boot).ToUniversalTime()
      $bootedAt = $bootUtc.ToString('o')
      $uptimeSeconds = [int64]((Get-Date).ToUniversalTime() - $bootUtc).TotalSeconds
    }
  } catch {
    Add-CollectionIssueOnce -Section 'stability' -Severity 'warning' `
      -Message ('Temps de fonctionnement non lu : ' + $_.Exception.Message) -Source 'Win32_OperatingSystem' -Reason 'NOT_AVAILABLE'
  }

  # Services actuellement en echec. `Stopped` seul n'est pas une preuve :
  # services manuels, declenches ou ponctuels peuvent etre arretes normalement.
  # On ne classe en echec que les services portes par un code de sortie non nul
  # ou un evenement SCM pertinent et rattache au service.
  $failedUnits = @()
  $stoppedUnits = @()
  try {
    $services = @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop)
    $units = Get-WindowsServiceStabilityUnits -Services $services -Events $Events
    $failedUnits = @($units.failedUnits)
    $stoppedUnits = @($units.stoppedUnits)
  } catch {
    Add-CollectionIssueOnce -Section 'stability' -Severity 'warning' `
      -Message ('Services non enumeres : ' + $_.Exception.Message) -Source 'Win32_Service' -Reason 'NOT_AVAILABLE'
  }

  # Redemarrages : le journal Systeme les date par l'evenement 6005 (« le
  # service Journal des evenements a demarre »), ecrit a chaque demarrage.
  #
  # `Get-WinEvent` leve la meme exception pour « je ne peux pas lire ce journal »
  # et pour « ce journal ne contient aucun evenement de ce genre ». Les
  # confondre coutait cher dans les deux sens : le compteur restait inconnu sur
  # une machine dont le journal est parfaitement lisible, et le rapport
  # annoncait « journal Systeme illisible » — un defaut de la machine — la ou le
  # journal avait simplement ete vide la veille.
  #
  # La lecture du plus ancien enregistrement tranche : si elle aboutit, le
  # journal est lisible, et l'absence de 6005 est un fait, pas une panne. La
  # fenetre publiee est alors celle que le journal couvre **reellement**, sans
  # quoi « zero redemarrage » se lirait sur trente jours quand il ne porte que
  # sur neuf heures.
  $reboots = @{
    count = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'journal Systeme illisible'
    observationWindowMs = $absent
    lastAt = $bootedAt
    source = 'System/EventLog 6005'
  }
  $systemOldest = Get-EventLogWindow -LogName 'System'
  $requestedMs = [int64]$script:HistoryDays * 86400000
  $coveredMs = $null
  if ($null -ne $systemOldest) {
    $span = [int64]((Get-Date).ToUniversalTime() - $systemOldest).TotalMilliseconds
    if ($span -lt 0) { $span = 0 }
    $coveredMs = [Math]::Min($span, $requestedMs)
  }

  if ($null -ne $coveredMs) {
    $boots = @()
    try {
      $boots = @(Get-WinEvent -FilterHashtable @{
          LogName = 'System'
          ProviderName = 'EventLog'
          Id = 6005
          StartTime = (Get-Date).AddDays(-$script:HistoryDays)
        } -ErrorAction Stop)
    } catch {
      # Le journal est lisible — le plus ancien enregistrement vient d'en sortir.
      # L'exception ne peut donc dire qu'une chose : aucun 6005 sur la fenetre.
      Write-Debug ('Aucun demarrage date sur la fenetre : ' + $_.Exception.Message)
    }
    $reboots.count = $boots.Count
    # La fenetre du journal des incidents quand elle existe — les deux comptent
    # alors la meme duree —, sinon celle que le journal Systeme couvre seul.
    $reboots.observationWindowMs = if ($null -ne $Events) { $Events.window.coveredMs } else { $coveredMs }
  }

  return @{
    uptimeSeconds = $uptimeSeconds
    bootedAt = $bootedAt
    reboots = $reboots
    unexpectedShutdowns = Get-IncidentCount -Events $Events -Category 'POWER' -Absent $absent
    kernelCrashes = Get-IncidentCount -Events $Events -Category 'KERNEL_CRASH' -Absent $absent
    hardwareErrors = Get-IncidentCount -Events $Events -Category 'HARDWARE' -Absent $absent
    storageErrors = Get-IncidentCount -Events $Events -Category 'STORAGE' -Absent $absent
    filesystemErrors = Get-IncidentCount -Events $Events -Category 'FILESYSTEM' -Absent $absent
    memoryPressureEvents = Get-IncidentCount -Events $Events -Category 'MEMORY' -Absent $absent
    networkErrors = Get-IncidentCount -Events $Events -Category 'NETWORK' -Absent $absent
    driverErrors = Get-IncidentCount -Events $Events -Category 'DRIVER' -Absent $absent
    serviceFailures = Get-IncidentCount -Events $Events -Category 'SERVICE' -Absent $absent
    applicationCrashes = Get-IncidentCount -Events $Events -Category 'APPLICATION_CRASH' -Absent $absent
    thermalEvents = Get-IncidentCount -Events $Events -Category 'THERMAL' -Absent $absent
    failedUpdates = Get-IncidentCount -Events $Events -Category 'UPDATE' -Absent $absent
    failedUnits = $failedUnits
    stoppedUnits = $stoppedUnits
    # `coredumpctl` n'a pas d'equivalent : Windows produit des vidanges memoire,
    # mais leur inventaire passe par Windows Error Reporting, dont le format
    # n'est pas documente de facon stable.
    coredumps = @()
    kernelTainted = New-Unknown -Reason 'NOT_APPLICABLE' -Detail 'notion propre au noyau Linux'
    meta = @{
      source = 'Get-WinEvent, Win32_Service'
      method = 'journal Windows et CIM'
      collectedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
  }
}

<#
.SYNOPSIS
  Sequence de demarrage, lue dans Diagnostics-Performance.

.DESCRIPTION
  L'evenement 100 du canal `Microsoft-Windows-Diagnostics-Performance/Operational`
  porte les durees de demarrage. Ce canal **n'existe pas sur Server Core** ni sur
  les editions Server par defaut : son absence est declaree, jamais devinee.

  Le decoupage n'est pas normalise avec celui de systemd : `systemd-analyze` et
  Diagnostics-Performance ne mesurent pas les memes bornes, et forcer une
  correspondance produirait une comparaison fausse entre un Linux et un Windows.
#>
function Get-BootSection {
  $phases = @()
  $totalMs = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'canal Diagnostics-Performance absent ou vide'
  $measuredAt = New-Unknown -Reason 'NOT_AVAILABLE'
  $slowestItems = @()
  $history = @()

  try {
    $bootEvents = @(Get-WinEvent -FilterHashtable @{
        LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'
        Id = 100
      } -MaxEvents 20 -ErrorAction Stop)

    if ($bootEvents.Count -gt 0) {
      $latest = $bootEvents[0]
      $xml = [xml]$latest.ToXml()
      $data = @{}
      foreach ($node in $xml.Event.EventData.Data) { $data[$node.Name] = $node.'#text' }

      $measuredAt = $latest.TimeCreated.ToUniversalTime().ToString('o')
      if ($data.ContainsKey('BootTime')) { $totalMs = [int64]$data['BootTime'] }
      # Les trois bornes que Windows publie separement. `MainPathBootTime` est
      # le chemin critique, `BootPostBootTime` la fin du demarrage du bureau.
      if ($data.ContainsKey('FirmwareBootTime') -and [int64]$data['FirmwareBootTime'] -gt 0) {
        $phases += @{ name = 'firmware'; durationMs = [int64]$data['FirmwareBootTime'] }
      }
      if ($data.ContainsKey('MainPathBootTime')) {
        $phases += @{ name = 'mainPath'; durationMs = [int64]$data['MainPathBootTime'] }
      }
      if ($data.ContainsKey('BootPostBootTime')) {
        $phases += @{ name = 'postBoot'; durationMs = [int64]$data['BootPostBootTime'] }
      }

      foreach ($entry in $bootEvents) {
        $entryXml = [xml]$entry.ToXml()
        $eventData = @{}
        foreach ($node in $entryXml.Event.EventData.Data) { $eventData[$node.Name] = $node.'#text' }
        $history += @{
          at = $entry.TimeCreated.ToUniversalTime().ToString('o')
          totalMs = if ($eventData.ContainsKey('BootTime')) { [int64]$eventData['BootTime'] } else { New-Unknown -Reason 'UNKNOWN' }
        }
      }
    }
  } catch {
    Add-CollectionIssueOnce -Section 'boot' -Severity 'warning' `
      -Message 'Canal Diagnostics-Performance absent : durees de demarrage non mesurees. Server Core ne le fournit pas.' `
      -Source 'Get-WinEvent' -Reason 'NOT_AVAILABLE'
  }

  # 101 : application lente au demarrage. 102 : pilote lent. 103 : service lent.
  $kinds = @{ 101 = 'application'; 102 = 'driver'; 103 = 'service' }
  foreach ($id in $kinds.Keys) {
    try {
      $slow = @(Get-WinEvent -FilterHashtable @{
          LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'
          Id = $id
        } -MaxEvents 10 -ErrorAction Stop)
      foreach ($entry in $slow) {
        if ($slowestItems.Count -ge 50) { break }
        $entryXml = [xml]$entry.ToXml()
        $eventData = @{}
        foreach ($node in $entryXml.Event.EventData.Data) { $eventData[$node.Name] = $node.'#text' }
        $name = if ($eventData.ContainsKey('Name')) { $eventData['Name'] } elseif ($eventData.ContainsKey('FileName')) { $eventData['FileName'] } else { '' }
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $slowestItems += @{
          name = [string]$name
          durationMs = if ($eventData.ContainsKey('TotalTime')) { [int64]$eventData['TotalTime'] } else { New-Unknown -Reason 'UNKNOWN' }
          kind = $kinds[$id]
        }
      }
    } catch {
      # Canal absent : deja signale par la lecture de l'evenement 100, et le
      # repeter par identifiant produirait trois fois le meme probleme.
      Write-Debug ('Evenement ' + $id + ' absent : ' + $_.Exception.Message)
    }
  }

  # Mode du micrologiciel. `$env:firmware_type` est pose par Windows lui-meme et
  # ne demande aucun privilege, contrairement a `Confirm-SecureBootUEFI`.
  $firmwareMode = 'UNKNOWN'
  if ($env:firmware_type -eq 'UEFI') { $firmwareMode = 'UEFI' }
  elseif ($env:firmware_type -eq 'Legacy') { $firmwareMode = 'LEGACY_BIOS' }

  # Demarrage rapide : il fausse tout le reste de cette section. La machine ne
  # redemarre pas vraiment, l'uptime ne repart pas de zero et les correctifs ne
  # s'appliquent pas. Le signaler evite de lire un « demarrage en huit
  # secondes » comme une performance.
  $fastStartup = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'cle HiberbootEnabled illisible'
  try {
    $value = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' `
      -Name 'HiberbootEnabled' -ErrorAction Stop
    $fastStartup = ([int]$value -eq 1)
  } catch {
    # La cle est absente sur les editions Server, ou l'hibernation ne l'est pas.
    Write-Debug ('HiberbootEnabled illisible : ' + $_.Exception.Message)
  }

  return @{
    phases = $phases
    totalMs = $totalMs
    measuredAt = $measuredAt
    slowestItems = $slowestItems
    failedAtBoot = @()
    firmwareMode = $firmwareMode
    fastStartupEnabled = $fastStartup
    history = $history
    kernels = @{
      # Les parentheses ne sont pas decoratives : en mode argument, PowerShell
      # lit `-Value [System.Environment]::…` comme le debut d'un litteral de
      # type et refuse **le fichier entier** a l'analyse. Le scanner ne
      # demarrait pas, et aucun garde-fou local ne le voyait — PSScriptAnalyzer
      # classe cela en severite `ParseError`, que le lint n'incluait pas.
      running = Get-StringOrUnknown -Value ([System.Environment]::OSVersion.Version.ToString()) -Reason 'UNKNOWN'
      installed = @()
      newestInstalled = New-Unknown -Reason 'NOT_APPLICABLE' -Detail 'Windows ne conserve pas plusieurs noyaux installes'
      source = 'System.Environment.OSVersion'
    }
    meta = @{
      source = 'Microsoft-Windows-Diagnostics-Performance/Operational'
      method = 'journal Windows'
      collectedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
  }
}

<#
.SYNOPSIS
  Dernier arret : proprete, motif et duree.

.DESCRIPTION
  Trois evenements racontent l'arret, et ils ne disent pas la meme chose :

  - `User32` 1074 — un arret **demande**, avec le processus qui l'a demande ;
  - `EventLog` 6006 — le service de journalisation s'est arrete proprement ;
  - `Kernel-Power` 41 et `EventLog` 6008 — la machine s'est arretee **sans**
    passer par la sequence d'extinction.

  `lastShutdownWasClean = $false` est une affirmation forte : elle exige une
  trace explicite. L'absence de trace d'arret propre ne suffit pas, car le
  journal a pu tourner.
#>
function Get-ShutdownSection {
  $lastAt = New-Unknown -Reason 'UNKNOWN' -Detail 'aucun evenement d''arret dans la fenetre'
  $wasClean = New-Unknown -Reason 'UNKNOWN' -Detail 'aucune trace explicite : le journal a pu tourner'
  $reason = New-Unknown -Reason 'UNKNOWN' -Detail 'aucun evenement d''arret identifie'

  $clean = $null
  $unclean = $null

  try {
    $clean = Get-WinEvent -FilterHashtable @{
      LogName = 'System'
      Id = @(1074, 6006)
      StartTime = (Get-Date).AddDays(-$script:HistoryDays)
    } -MaxEvents 1 -ErrorAction Stop
  } catch {
    # Aucun arret propre dans la fenetre : ce n'est pas une erreur de lecture.
    Write-Debug ('Aucun arret propre trouve : ' + $_.Exception.Message)
  }

  try {
    $unclean = Get-WinEvent -FilterHashtable @{
      LogName = 'System'
      Id = @(41, 6008)
      StartTime = (Get-Date).AddDays(-$script:HistoryDays)
    } -MaxEvents 1 -ErrorAction Stop
  } catch {
    # Aucun arret sale dans la fenetre.
    Write-Debug ('Aucun arret inattendu trouve : ' + $_.Exception.Message)
  }

  # Le plus recent des deux tranche : une machine qui a plante il y a un mois
  # puis s'est arretee proprement hier s'est bien arretee proprement.
  $latest = $null
  if ($null -ne $clean -and $null -ne $unclean) {
    if ($clean.TimeCreated -ge $unclean.TimeCreated) {
      $latest = $clean; $wasClean = $true
    } else {
      $latest = $unclean; $wasClean = $false
    }
  } elseif ($null -ne $clean) {
    $latest = $clean; $wasClean = $true
  } elseif ($null -ne $unclean) {
    $latest = $unclean; $wasClean = $false
  }

  if ($null -ne $latest) {
    $lastAt = $latest.TimeCreated.ToUniversalTime().ToString('o')
    $text = if ($latest.Message) { ([string]$latest.Message).Trim() } else { '' }
    if ($text.Length -gt 1024) { $text = $text.Substring(0, 1024) }
    if ($text -ne '') { $reason = $text }
  }

  return @{
    lastShutdownAt = $lastAt
    lastShutdownWasClean = $wasClean
    lastShutdownReason = $reason
    lastShutdownDurationMs = New-Unknown -Reason 'NOT_AVAILABLE' `
      -Detail 'le journal Windows ne chronometre pas l''extinction'
    slowestItems = @()
    meta = @{
      source = 'System/User32 1074, Kernel-Power 41'
      method = 'journal Windows'
      collectedAt = (Get-Date).ToUniversalTime().ToString('o')
    }
  }
}
