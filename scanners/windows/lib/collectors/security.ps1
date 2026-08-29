# SysAudit Windows — pare-feu, chiffrement, TPM, UAC, demarrage securise.
#
# Chaque lecture est independante : un module absent — Defender desactive, TPM
# non expose par une machine virtuelle — laisse un marqueur, jamais une valeur
# inventee.

function Get-SecureBootState {
  try {
    if (Confirm-SecureBootUEFI) { return 'ENABLED' }
    return 'DISABLED'
  } catch {
    return 'UNSUPPORTED'
  }
}

function Get-UacState {
  try {
    $enabled = Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA
    if ([int]$enabled -eq 1) { return 'ENABLED' }
    return 'DISABLED'
  } catch {
    return (New-Unknown -Reason 'NOT_AVAILABLE')
  }
}

function Get-FirewallState {
  param($Profiles)
  if ($Profiles.Count -eq 0) { return (New-Unknown -Reason 'NOT_AVAILABLE') }
  if (($Profiles | Where-Object { $_.state -eq 'ENABLED' }).Count -gt 0) { return 'ENABLED' }
  return 'DISABLED'
}

<#
.SYNOPSIS
  Securite fondee sur la virtualisation : VBS, HVCI, Credential Guard.

.DESCRIPTION
  `Win32_DeviceGuard` publie trois choses distinctes, et les confondre serait
  faux :

  - `AvailableSecurityProperties` — ce que le **materiel** permet ;
  - `SecurityServicesConfigured` — ce que la **politique** demande ;
  - `SecurityServicesRunning` — ce qui **tourne reellement**.

  Seule la troisieme dit si la protection est active. Une machine ou Credential
  Guard est configure mais ne demarre pas — faute de UEFI verrouille, par
  exemple — n'est pas protegee, et la lire comme protegee serait la pire des
  erreurs de ce rapport.

  Le service `SecurityServicesRunning` vaut 1 pour Credential Guard et 2 pour
  l'integrite du code protegee par l'hyperviseur (HVCI).
#>
# Motif d'absence des champs de mise a jour Windows.
#
# Un seul point de definition : six champs portaient la meme valeur recopiee,
# donc six occasions d'en corriger cinq.
function New-UpdateUnknown {
  New-Unknown -Reason 'UNSUPPORTED' `
    -Detail 'l''interrogation de Windows Update n''est pas encore implementee par ce scanner'
}

<#
.SYNOPSIS
  Un redemarrage est-il en attente ?

.DESCRIPTION
  Deux marqueurs font foi, et deux seulement :

  - `Component Based Servicing\RebootPending`, pose par la pile de servicing ;
  - `WindowsUpdate\Auto Update\RebootRequired`, pose par Windows Update.

  `PendingFileRenameOperations` n'en fait **pas** partie, bien qu'il soit le
  plus souvent cite. N'importe quel programme d'installation l'ecrit, et la
  valeur survit longtemps a ce qui l'a posee : sur la machine d'essai, elle est
  presente alors que les deux marqueurs qui font foi sont absents et qu'aucun
  redemarrage n'est requis. S'en servir pour conclure fabriquerait un
  redemarrage en attente sur une bonne part des machines saines.

  Les deux cles vivent sous HKLM et se lisent sans elevation.
#>
function Get-RebootPendingState {
  $keys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
  )

  foreach ($key in $keys) {
    try {
      if (Test-Path -LiteralPath $key) { return $true }
    } catch {
      Add-CollectionIssue -Section 'security.updates' -Severity 'warning' `
        -Message ('Marqueur de redemarrage non lu (' + $key + ') : ' + $_.Exception.Message) `
        -Source 'Registre' -Reason 'PERMISSION_DENIED'
      return (New-Unknown -Reason 'PERMISSION_DENIED' -Detail 'marqueur de redemarrage illisible')
    }
  }

  # Aucun des deux marqueurs : c'est un constat, pas un repli. Les deux cles
  # existent ou n'existent pas, il n'y a pas de troisieme etat.
  return $false
}

<#
.SYNOPSIS
  Etat des mises a jour automatiques, dans l'ordre d'autorite des sources.

.DESCRIPTION
  La strategie d'entreprise prime sur le reglage local, qui prime sur le
  comportement par defaut. Chaque niveau est lu ; aucun n'est suppose.

  `AUOptions` vaut 1 (jamais), 2 (notifier avant de telecharger), 3 (telecharger
  puis notifier), 4 (installer selon un calendrier) ou 5 (choix local). Seul 1
  coupe les mises a jour ; 2 et 3 les laissent a la main de l'utilisateur, ce
  que `PARTIAL` decrit mieux qu'un booleen.

  Un service `wuauserv` **desactive** coupe tout, quelle que soit la strategie.
  `Manual` ne coupe rien : c'est le reglage par defaut de Windows 10 et 11, ou
  le service demarre sur declencheur. Les confondre annoncerait des mises a jour
  desactivees sur la quasi-totalite du parc.

  Sans strategie ni reglage local, et avec un service qui peut demarrer, la
  reponse est `ENABLED` : c'est le comportement documente de Windows non
  configure, pas une deduction tiree d'une cle absente. Le sens de la
  precaution compte ici — `SEC-013` ne se declenche que sur `DISABLED`, et
  aucune des sources lues ne dit « desactive ».
#>
function Get-AutomaticUpdatesState {
  $policy = $null
  $local = $null
  try {
    $policy = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -ErrorAction Stop
  } catch {
    Write-Debug ('Aucune strategie Windows Update : ' + $_.Exception.Message)
  }
  try {
    $local = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update' -ErrorAction Stop
  } catch {
    Write-Debug ('Aucun reglage local Windows Update : ' + $_.Exception.Message)
  }

  foreach ($source in @($policy, $local)) {
    if ($null -eq $source) { continue }
    if ($null -ne $source.NoAutoUpdate -and [int]$source.NoAutoUpdate -eq 1) { return 'DISABLED' }
    if ($null -ne $source.AUOptions) {
      switch ([int]$source.AUOptions) {
        1 { return 'DISABLED' }
        2 { return 'PARTIAL' }
        3 { return 'PARTIAL' }
        4 { return 'ENABLED' }
        5 { return 'ENABLED' }
        default { }
      }
    }
  }

  try {
    $service = Get-Service -Name 'wuauserv' -ErrorAction Stop
    if ([string]$service.StartType -eq 'Disabled') { return 'DISABLED' }
  } catch {
    return (New-Unknown -Reason 'UNKNOWN' -Detail 'service Windows Update non interroge')
  }

  return 'ENABLED'
}

<#
.SYNOPSIS
  Date du dernier succes d'une etape de Windows Update, ou un marqueur.
#>
function Get-WindowsUpdateResultTime {
  param([string]$Step)

  $path = 'HKLM:\SOFTWARE\Microsoft\Windows\WindowsUpdate\Auto Update\Results\' + $Step
  try {
    $value = (Get-ItemProperty -LiteralPath $path -Name 'LastSuccessTime' -ErrorAction Stop).LastSuccessTime
    $parsed = ConvertTo-CimDateTime -Value $value
    if ($null -ne $parsed) { return $parsed.ToUniversalTime().ToString('o') }
  } catch {
    Write-Debug ('Aucun resultat Windows Update pour ' + $Step + ' : ' + $_.Exception.Message)
  }

  return (New-Unknown -Reason 'UNKNOWN' `
      -Detail ('aucun ' + $Step.ToLowerInvariant() + ' Windows Update date sur cette machine'))
}

<#
.SYNOPSIS
  Mises a jour en attente, comptees **hors ligne** et seulement si le catalogue
  local a une date.

.DESCRIPTION
  L'agent Windows Update expose un moteur de recherche par COM. Interroge avec
  `Online = $false`, il ne consulte que le cache local : aucun paquet ne sort de
  la machine, ce qui est la regle de ce scanner — seule l'adresse WAN, demandee
  explicitement, autorise un echange avec l'exterieur.

  Un cache non date ne se compte pas. Sur la machine d'essai, la recherche hors
  ligne rend 44 « mises a jour en attente » qui sont toutes des pilotes d'un
  catalogue de 2019, et zero mise a jour de securite. Publier ces deux nombres
  annoncerait 44 correctifs en retard et, plus grave, un feu vert sur les
  correctifs de securite — un chiffre faux dans les deux sens, tire d'un cache
  que rien ne date.

  La detection datee est donc une condition, pas un ornement : sans elle, les
  deux compteurs restent inconnus, avec le motif exact.
#>
function Get-PendingUpdateCounts {
  param($LastCheck)

  if ($LastCheck -isnot [string]) {
    $unknown = New-Unknown -Reason 'UNKNOWN' `
      -Detail 'aucune detection Windows Update datee : le catalogue local n''a jamais ete confronte au service'
    return @{ pending = $unknown; securityPending = $unknown }
  }

  try {
    $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
    $searcher.Online = $false
    $result = $searcher.Search('IsInstalled=0 and IsHidden=0')
  } catch {
    Add-CollectionIssue -Section 'security.updates' -Severity 'warning' `
      -Message ('Catalogue Windows Update non interroge : ' + $_.Exception.Message) `
      -Source 'Microsoft.Update.Session' -Reason 'NOT_AVAILABLE'
    $unknown = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'agent Windows Update non interrogeable'
    return @{ pending = $unknown; securityPending = $unknown }
  }

  $pending = 0
  $security = 0
  foreach ($update in $result.Updates) {
    $pending += 1
    foreach ($category in $update.Categories) {
      # Le nom de categorie est traduit ; le `CategoryID` ne l'est pas.
      # « Security Updates » porte toujours cet identifiant, quelle que soit la
      # langue de Windows.
      if ([string]$category.CategoryID -eq '0FA1201D-4330-4FA8-8AE9-B877473B6441') {
        $security += 1
        break
      }
    }
  }

  Add-CollectionProvenance -Path 'security.updates.pending' -Source 'Microsoft.Update.Session' `
    -Method 'recherche hors ligne' -Precision 'mise a jour'

  return @{ pending = [int64]$pending; securityPending = [int64]$security }
}

<#
.SYNOPSIS
  Section `security.updates` pour Windows.
#>
function Get-WindowsUpdateState {
  $lastCheck = Get-WindowsUpdateResultTime -Step 'Detect'
  $counts = Get-PendingUpdateCounts -LastCheck $lastCheck

  return @{
    pending = $counts.pending
    securityPending = $counts.securityPending
    rebootRequired = Get-RebootPendingState
    lastCheck = $lastCheck
    lastUpdate = Get-WindowsUpdateResultTime -Step 'Install'
    automaticUpdates = Get-AutomaticUpdatesState
  }
}

function Get-DeviceGuardState {
  try {
    $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' `
      -ClassName 'Win32_DeviceGuard' -ErrorAction Stop
  } catch {
    $unknown = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'espace de noms DeviceGuard absent'
    return @{ vbs = $unknown; hvci = $unknown; credentialGuard = $unknown; dmaProtection = $unknown }
  }

  # 0 = desactive, 1 = active mais pas en cours, 2 = active et en cours.
  $vbs = switch ([int]$dg.VirtualizationBasedSecurityStatus) {
    0 { 'DISABLED' }
    1 { 'PARTIAL' }
    2 { 'ENABLED' }
    default { New-Unknown -Reason 'UNKNOWN' }
  }

  $running = @()
  if ($dg.SecurityServicesRunning) { $running = @($dg.SecurityServicesRunning) }
  $configured = @()
  if ($dg.SecurityServicesConfigured) { $configured = @($dg.SecurityServicesConfigured) }

  # Configure mais pas en cours : `PARTIAL`. La distinction est le coeur de
  # cette lecture — annoncer `ENABLED` sur une protection qui ne demarre pas
  # serait une fausse assurance.
  $credentialGuard = if ($running -contains 1) { 'ENABLED' } elseif ($configured -contains 1) { 'PARTIAL' } else { 'DISABLED' }
  $hvci = if ($running -contains 2) { 'ENABLED' } elseif ($configured -contains 2) { 'PARTIAL' } else { 'DISABLED' }

  # Propriete 6 : protection DMA du noyau. `AvailableSecurityProperties` dit ce
  # que le materiel **permet**, pas ce qui est actif : le champ le declare donc
  # comme une disponibilite, jamais comme un etat.
  $available = @()
  if ($dg.AvailableSecurityProperties) { $available = @($dg.AvailableSecurityProperties) }
  $dma = if ($available -contains 6) {
    'PARTIAL'
  } else {
    New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'protection DMA non annoncee par le materiel'
  }

  return @{ vbs = $vbs; hvci = $hvci; credentialGuard = $credentialGuard; dmaProtection = $dma }
}

<#
.SYNOPSIS
  Smart App Control, introduit avec Windows 11 22H2.

.DESCRIPTION
  Trois etats : 0 desactive, 1 actif, 2 evaluation. L'evaluation n'est pas une
  protection — Windows observe l'usage avant de decider — et la compter comme
  active surestimerait la posture de securite de la machine.

  La cle est absente sur Windows 10 et sur Server : c'est `NOT_APPLICABLE`, la
  fonctionnalite n'existant pas, et non `NOT_AVAILABLE`.
#>
function Get-SmartAppControlState {
  try {
    $value = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' `
      -Name 'VerifiedAndReputablePolicyState' -ErrorAction Stop
    switch ([int]$value) {
      0 { return 'DISABLED' }
      1 { return 'ENABLED' }
      2 { return 'PARTIAL' }
      default { return (New-Unknown -Reason 'UNKNOWN') }
    }
  } catch {
    return (New-Unknown -Reason 'NOT_APPLICABLE' `
        -Detail 'Smart App Control n''existe pas sur cette edition de Windows')
  }
}

function Get-RdpState {
  try {
    $denied = Get-ItemPropertyValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' `
      -Name 'fDenyTSConnections' -ErrorAction Stop
    $enabled = ([int]$denied -eq 0)

    $nla = New-Unknown -Reason 'NOT_AVAILABLE'
    try {
      $nlaValue = Get-ItemPropertyValue `
        -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
        -Name 'UserAuthentication' -ErrorAction Stop
      $nla = ([int]$nlaValue -eq 1)
    } catch {
      # Poste sans pile RDP installee : la sous-cle n'existe pas.
      Write-Debug ('UserAuthentication illisible : ' + $_.Exception.Message)
    }

    return @{ enabled = $enabled; networkLevelAuthentication = $nla }
  } catch {
    return (New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'cle Terminal Server illisible')
  }
}

function Get-SmbState {
  $v1 = New-Unknown -Reason 'NOT_AVAILABLE'
  $signing = New-Unknown -Reason 'NOT_AVAILABLE'

  try {
    $config = Get-SmbServerConfiguration -ErrorAction Stop
    $v1 = [bool]$config.EnableSMB1Protocol
    $signing = [bool]$config.RequireSecuritySignature
  } catch {
    # `Get-SmbServerConfiguration` exige des privileges et le role Serveur SMB.
    # Son absence n'est pas une absence de SMB.
    Write-Debug ('Configuration SMB non lue : ' + $_.Exception.Message)
  }

  return @{ v1Enabled = $v1; signingRequired = $signing }
}

<#
.SYNOPSIS
  Etat consolide de Microsoft Defender, mode d'execution compris.

.DESCRIPTION
  `AMRunningMode` est le champ qui manquait, et il porte la distinction la plus
  utile du tableau : quand un antivirus tiers prend la main, Defender **ne
  s'arrete pas**. Il passe en mode passif, continue de se mettre a jour, et
  n'analyse plus aucun fichier a l'ouverture.

  Sans ce champ, cet etat se lisait `enabled = true` et
  `realtimeProtection = false` -- exactement comme un utilisateur qui aurait
  coupe sa protection, qui est une anomalie. Le distinguer evite de signaler
  chaque poste correctement protege par un tiers.

  Les valeurs publiees par Defender sont des chaines en anglais, quelle que soit
  la langue du systeme : la comparaison est donc sure. Une valeur inconnue de
  cette liste ne devient pas `ACTIVE` par defaut -- elle laisse l'etat se
  deduire des booleens, ce qui est plus prudent que de parier sur un mode qu'on
  ne connait pas.
#>
function Get-DefenderState {
  param($Status)

  $runningMode = ([string]$Status.AMRunningMode).Trim()
  $realtime = [bool]$Status.RealTimeProtectionEnabled

  switch -Regex ($runningMode) {
    '^Normal$' { return $(if ($realtime) { 'ACTIVE' } else { 'DISABLED' }) }
    # Les trois modes ou Defender tourne sans proteger a l'ouverture.
    '^(SxS )?Passive Mode$' { return 'PASSIVE' }
    '^EDR Block Mode$' { return 'PASSIVE' }
    '^Not running$' { return 'DISABLED' }
  }

  # Mode absent ou non reconnu : on retombe sur ce que les booleens disent, et
  # on ne fabrique jamais `PASSIVE`, qui demande de savoir qu'un autre produit
  # a la main.
  if (-not [bool]$Status.AMServiceEnabled) { return 'DISABLED' }
  if ($realtime) { return 'ACTIVE' }
  return 'DISABLED'
}

<#
.SYNOPSIS
  Les signatures de Defender sont-elles a jour ?

.DESCRIPTION
  Defender publie l'age des definitions en jours. Le seuil est de sept jours,
  et non de zero : Defender met a jour plusieurs fois par jour, mais une
  machine eteinte le week-end rend legitimement un age de deux ou trois jours
  sans que rien ne soit casse. Signaler cet age reviendrait a crier au loup sur
  la moitie d'un parc.

  L'ancienne ecriture -- `[bool]$mp.AntispywareSignatureAge -eq 0` -- rendait le
  bon resultat par accident de precedence : PowerShell evaluait
  `([bool]$age) -eq 0`, ou un age non nul devient `$true`, lui-meme different de
  `0`. Le resultat etait juste et la lecture ne l'etait pas.

  Un age absent laisse un marqueur : « pas de definitions » et « age non
  publie » ne se lisent pas pareil.
#>
function Get-DefenderSignaturesFresh {
  param($Status)

  $ages = @()
  foreach ($age in @($Status.AntivirusSignatureAge, $Status.AntispywareSignatureAge)) {
    if ($null -eq $age) { continue }
    $parsed = 0
    if ([int]::TryParse([string]$age, [ref]$parsed) -and $parsed -ge 0) { $ages += $parsed }
  }
  if ($ages.Count -eq 0) {
    return (New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'age des definitions non publie')
  }

  # La plus ancienne des deux bases decide : une seule base perimee suffit a
  # laisser passer ce qu'elle ne connait pas.
  return (($ages | Measure-Object -Maximum).Maximum -lt 7)
}

function ConvertFrom-AntivirusProductState {
  param($Value)

  if ($null -eq $Value) {
    return @{
      enabled = New-Unknown -Reason 'UNKNOWN'
      upToDate = New-Unknown -Reason 'UNKNOWN'
      realtimeProtection = New-Unknown -Reason 'UNKNOWN'
    }
  }

  $state = [int64]$Value
  $statusByte = ($state -band 0xFF00) -shr 8
  $signatureByte = $state -band 0xFF

  $enabled = switch ($statusByte) {
    0x10 { $true }
    0x11 { $true }
    0x01 { $false }
    0x00 { $false }
    default { New-Unknown -Reason 'UNKNOWN' }
  }

  $realtime = switch ($statusByte) {
    0x10 { $true }
    0x11 { $false }
    0x01 { $false }
    0x00 { $false }
    default { New-Unknown -Reason 'UNKNOWN' }
  }

  $upToDate = switch ($signatureByte) {
    0x00 { $true }
    0x10 { $false }
    default { New-Unknown -Reason 'UNKNOWN' }
  }

  return @{
    enabled = $enabled
    upToDate = $upToDate
    realtimeProtection = $realtime
  }
}

<#
.SYNOPSIS
  Etat d'un produit declare au Centre de securite, depuis ses trois booleens.

.DESCRIPTION
  Le Centre de securite ne publie pas de mode d'execution : il encode l'etat
  dans un entier dont `ConvertFrom-AntivirusProductState` tire trois booleens.
  On ne peut donc pas y distinguer `PASSIVE`, qui demande de savoir qu'un autre
  produit a la main -- et fabriquer cet etat serait affirmer une chose que la
  source ne dit pas.

  La reconstruction est donc volontairement prudente, et prefere le pire des
  deux cas au plus flatteur : un produit actif sans protection temps reel est
  lu `DISABLED`. Si un autre produit protege reellement la machine, la regle le
  verra dans **son** etat a lui, et ne signalera rien.
#>
function Get-SecurityCenterState {
  param($Decoded)

  $enabled = $Decoded.enabled
  $realtime = $Decoded.realtimeProtection

  # Ni l'un ni l'autre lisible : c'est le scanner qui n'a pas su, pas la
  # machine qui est nue.
  if ($enabled -isnot [bool] -and $realtime -isnot [bool]) { return 'UNAVAILABLE' }
  if ($enabled -is [bool] -and -not $enabled) { return 'DISABLED' }
  if ($realtime -is [bool]) { return $(if ($realtime) { 'ACTIVE' } else { 'DISABLED' }) }
  return 'INSTALLED_UNKNOWN_STATE'
}

function Get-ThirdPartyAntivirusListFromProducts {
  param([object[]]$Products)

  $entries = @()
  foreach ($product in @($Products)) {
    if ($null -eq $product) { continue }
    $name = [string]$product.displayName
    if ([string]::IsNullOrWhiteSpace($name)) { continue }
    if ($name -match 'Defender') { continue }

    $decoded = ConvertFrom-AntivirusProductState -Value $product.productState
    $entry = @{
      name = $name.Trim()
      enabled = $decoded.enabled
      upToDate = $decoded.upToDate
      realtimeProtection = $decoded.realtimeProtection
      state = Get-SecurityCenterState -Decoded $decoded
      # Le Centre de securite ne recense **que** les produits declares comme
      # antivirus : c'est la definition de la classe interrogee. Un EDR qui ne
      # s'y declare pas n'apparait pas ici, et un qui s'y declare y prend bien
      # ce role.
      kind = 'ANTIVIRUS'
      source = 'WINDOWS_SECURITY_CENTER'
    }

    if ($null -ne $product.timestamp) {
      try {
        $entry.lastScan = ([DateTime]$product.timestamp).ToUniversalTime().ToString('o')
      } catch {
        # Certaines suites publient un horodatage non ISO. Ne pas mentir sur la
        # date est necessaire, mais pas suffisant : sans marqueur, « aucune
        # analyse enregistree » et « date illisible » se liraient pareil. Le
        # champ porte donc la raison, et l'incident remonte dans la collecte.
        Write-Debug ('Horodatage antivirus illisible : ' + $_.Exception.Message)
        $entry.lastScan = New-Unknown -Reason 'UNKNOWN' `
          -Detail 'horodatage publie par la suite antivirus non convertible en date'
      }
    }

    $entries += $entry
  }

  return $entries
}

function Get-ThirdPartyAntivirusList {
  try {
    $products = @(Get-CimInstance -Namespace 'root\SecurityCenter2' -ClassName 'AntiVirusProduct' -ErrorAction Stop)
    return @(Get-ThirdPartyAntivirusListFromProducts -Products $products)
  } catch {
    Add-CollectionIssue -Section 'security.windows.thirdPartyAntivirus' -Severity 'warning' `
      -Message ('Antivirus tiers non lus : ' + $_.Exception.Message) -Source 'SecurityCenter2 AntiVirusProduct' -Reason 'NOT_AVAILABLE'
    return @()
  }
}

function Get-SecuritySection {
  $firewallProfiles = @()
  try {
    $firewallProfiles = Get-NetFirewallProfile | ForEach-Object {
      @{
        name = $_.Name
        state = $(if ($_.Enabled) { 'ENABLED' } else { 'DISABLED' })
      }
    }
  } catch {
    $firewallProfiles = @()
  }

  $windowsSecurity = @{}
  try {
    $mp = Get-MpComputerStatus -ErrorAction Stop
    $defenderState = Get-DefenderState -Status $mp
    $defender = @{
      name = 'Microsoft Defender Antivirus'
      vendor = 'Microsoft'
      enabled = [bool]$mp.AntivirusEnabled
      upToDate = Get-DefenderSignaturesFresh -Status $mp
      realtimeProtection = [bool]$mp.RealTimeProtectionEnabled
      state = $defenderState
      # Defender **est** un antivirus temps reel quand il tourne en mode normal.
      # En mode passif, il reste un antivirus dont la protection est cedee : la
      # nature du produit ne change pas, seul son etat change.
      kind = 'ANTIVIRUS'
      source = 'DEFENDER_POWERSHELL'
      version = Get-StringOrUnknown -Value $mp.AMProductVersion -Reason 'UNKNOWN'
    }
    if ($mp.QuickScanEndTime) {
      $defender.lastScan = ([DateTime]$mp.QuickScanEndTime).ToUniversalTime().ToString('o')
    }
    if ($mp.AntivirusSignatureLastUpdated) {
      try {
        $defender.signatureDate = ([DateTime]$mp.AntivirusSignatureLastUpdated).ToUniversalTime().ToString('o')
      } catch {
        Write-Debug ('Date des definitions illisible : ' + $_.Exception.Message)
        $defender.signatureDate = New-Unknown -Reason 'UNKNOWN' `
          -Detail 'date des definitions non convertible'
      }
    }
    $windowsSecurity.defender = $defender
  } catch {
    Add-CollectionIssue -Section 'security.defender' -Severity 'warning' `
      -Message ('Etat de Defender non lu : ' + $_.Exception.Message) -Source 'Get-MpComputerStatus' -Reason 'NOT_AVAILABLE'
  }

  try {
    $tpm = Get-Tpm -ErrorAction Stop
    $windowsSecurity.tpm = @{
      present = [bool]$tpm.TpmPresent
      version = if ($tpm.ManufacturerVersionFull20) { [string]$tpm.ManufacturerVersionFull20 } else { Get-StringOrUnknown -Value $tpm.ManufacturerVersion -Reason 'UNKNOWN' }
      enabled = [bool]$tpm.TpmEnabled
      ready = [bool]$tpm.TpmReady
    }
  } catch {
    $windowsSecurity.tpm = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'Get-Tpm indisponible'
  }

  try {
    $bitlocker = Get-BitLockerVolume -ErrorAction Stop
    $windowsSecurity.bitlocker = @{
      state = if (($bitlocker | Where-Object { $_.ProtectionStatus -eq 'On' }).Count -gt 0) { 'ENABLED' } else { 'DISABLED' }
      protectedVolumes = @($bitlocker | Where-Object { $_.ProtectionStatus -eq 'On' } | ForEach-Object { $_.MountPoint })
    }
  } catch {
    $windowsSecurity.bitlocker = New-Unknown -Reason 'NOT_AVAILABLE'
  }

  $deviceGuard = Get-DeviceGuardState
  $thirdPartyAntivirus = @(Get-ThirdPartyAntivirusList)

  Add-CollectionIssue -Section 'security.accounts' -Severity 'warning' `
    -Message 'Comptes locaux non collectes par le scanner Windows, quel que soit le niveau : la liste vide ne signifie pas qu''aucun compte n''existe.' -Reason 'UNSUPPORTED'
  Add-CollectionIssue -Section 'security.obsoleteProtocols' -Severity 'warning' `
    -Message 'Protocoles obsoletes non recherches par le scanner Windows, quel que soit le niveau : la liste vide ne vaut pas constat.' -Reason 'UNSUPPORTED'

  $section = @{
    firewall = @{
      engine = 'windows-firewall'
      state = Get-FirewallState -Profiles $firewallProfiles
      # Le pare-feu Windows expose l'un et l'autre ; ce sont les collecteurs qui
      # manquent, pas la source.
      defaultInputPolicy = New-Unknown -Reason 'UNSUPPORTED' `
        -Detail 'la politique par defaut du pare-feu Windows n''est pas encore lue par ce scanner'
      ruleCount = New-Unknown -Reason 'UNSUPPORTED' `
        -Detail 'le decompte des regles de pare-feu n''est pas encore lu par ce scanner'
      profiles = $firewallProfiles
    }
    windows = @{
      thirdPartyAntivirus = $thirdPartyAntivirus
      tpm = if ($windowsSecurity.ContainsKey('tpm')) { $windowsSecurity.tpm } else { New-Unknown -Reason 'NOT_AVAILABLE' }
      bitlocker = if ($windowsSecurity.ContainsKey('bitlocker')) { $windowsSecurity.bitlocker } else { New-Unknown -Reason 'NOT_AVAILABLE' }
      uac = Get-UacState
      rdp = Get-RdpState
      smb = Get-SmbState
      credentialGuard = $deviceGuard.credentialGuard
      hvci = $deviceGuard.hvci
      vbs = $deviceGuard.vbs
      dmaProtection = $deviceGuard.dmaProtection
      smartAppControl = Get-SmartAppControlState
      # Meme correction que pour les mises a jour : le catalogue de signatures
      # existe sur la machine, c'est son analyse qui n'est pas ecrite.
      unsignedDrivers = New-Unknown -Reason 'UNSUPPORTED' `
        -Detail 'l''enumeration des pilotes non signes exige une analyse de catalogue non implementee'
    }
    secureBoot = Get-SecureBootState
    # Meme raison que pour `network.listeningPorts` : le schema impose un
    # tableau, un tableau vide affirme une absence, et cette absence n'a pas ete
    # constatee. Un poste Windows annonçait « aucun compte » et « aucun
    # protocole obsolete » alors que rien n'avait ete regarde.
    accounts = @()
    obsoleteProtocols = @()
    # `UNSUPPORTED` et non `NOT_AVAILABLE`.
    #
    # `NOT_AVAILABLE` affirme que la source est absente du systeme. Sur Windows,
    # Windows Update existe toujours : le rapport annoncait donc un poste sans
    # service de mise a jour, et envoyait le lecteur chercher ce qu'il a deja.
    # Ce qui manque est le collecteur, pas la source — c'est exactement ce que
    # `UNSUPPORTED` veut dire. Constate en auditant un vrai poste Windows 11.
    updates = Get-WindowsUpdateState
  }

  if ($windowsSecurity.ContainsKey('defender')) {
    $section.windows.defender = $windowsSecurity.defender
  }

  if ($thirdPartyAntivirus.Count -gt 0) {
    Add-CollectionProvenance -Path 'security.windows.thirdPartyAntivirus' `
      -Source 'SecurityCenter2 AntiVirusProduct' -Method 'CIM' -Precision 'suite de sécurité'
  }

  return $section
}
