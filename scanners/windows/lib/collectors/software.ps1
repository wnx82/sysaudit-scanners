# SysAudit Windows — inventaire logiciel : paquets, gestionnaires, runtimes,
# services.
#
# Windows n'a pas de gestionnaire de paquets unique dont on pourrait lire la
# base, comme `dpkg` ou `rpm` sous Linux. Trois sources coexistent, et aucune ne
# contient les deux autres :
#
#   - la **base de desinstallation** du registre, alimentee par les
#     installateurs MSI et par la plupart des installateurs autonomes. C'est la
#     seule source exhaustive pour les logiciels de bureau ;
#   - les **applications empaquetees** (`Appx`), qui n'y figurent pas ;
#   - **winget**, qui ne stocke rien : il interroge les deux precedentes et ses
#     propres sources distantes.
#
# Le collecteur lit les deux premieres et se contente de **constater** winget.
# Il ne l'interroge pas : `winget list` produit un tableau destine a l'oeil,
# aligne par espaces, tronque a la largeur de la console et traduit dans la
# langue du systeme. En tirer un inventaire donnerait des noms coupes en deux
# sur une console etroite, ce qui vaut moins que pas d'inventaire du tout.
#
# Le scanner n'installe jamais rien et n'interroge aucune source distante : il
# constate ce qui est la.

<#
.SYNOPSIS
  Convertit une date d'installation du registre en date ISO.

.DESCRIPTION
  Fonction pure, testable hors Windows.

  Le registre publie `InstallDate` en `yyyyMMdd`, sans separateur ni fuseau.
  Certains installateurs y ecrivent n'importe quoi — une date vide, un
  horodatage Unix, ou la chaine `20200000` dont le mois vaut zero. Une valeur
  non convertible rend `$null` : le champ sera simplement absent, plutot que de
  faire croire a une installation le 1er janvier.
#>
function Convert-RegistryInstallDate {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
  $digits = $Value.Trim()
  if ($digits -notmatch '^\d{8}$') { return $null }

  $parsed = [datetime]::MinValue
  $styles = [System.Globalization.DateTimeStyles]::None
  $culture = [System.Globalization.CultureInfo]::InvariantCulture
  if (-not [datetime]::TryParseExact($digits, 'yyyyMMdd', $culture, $styles, [ref]$parsed)) {
    return $null
  }

  return $parsed.ToString('yyyy-MM-dd')
}

<#
.SYNOPSIS
  Cette entree de desinstallation decrit-elle un logiciel installe ?

.DESCRIPTION
  Fonction pure, testable hors Windows : elle ne juge qu'un objet deja lu.

  La base de desinstallation contient bien plus que des logiciels. Trois
  familles en sont ecartees, et l'ordre des controles importe peu :

    - les entrees **sans nom affiche**, qui ne sont que des cles de service ;
    - les **composants systeme** (`SystemComponent = 1`), que Windows lui-meme
      masque dans « Applications installees » ;
    - les **correctifs et mises a jour** (`ParentKeyName` renseigne, ou type
      `Update`), qui gonfleraient l'inventaire de plusieurs centaines d'entrees
      decrivant le meme logiciel.

  Sans ce tri, un poste ordinaire rapportait plus de six cents « paquets » dont
  la majorite etaient des mises a jour d'Office.
#>
function Test-UninstallEntryIsPackage {
  param($Entry)

  if ($null -eq $Entry) { return $false }
  if ([string]::IsNullOrWhiteSpace([string]$Entry.DisplayName)) { return $false }
  if ($null -ne $Entry.SystemComponent -and [int]$Entry.SystemComponent -eq 1) { return $false }
  if (-not [string]::IsNullOrWhiteSpace([string]$Entry.ParentKeyName)) { return $false }
  if ([string]$Entry.ReleaseType -in @('Update', 'Security Update', 'Hotfix')) { return $false }

  return $true
}

<#
.SYNOPSIS
  Etat d'un service Windows, dans le vocabulaire du schema.

.DESCRIPTION
  Fonction pure. `Win32_Service` publie un etat de transition (`Start Pending`,
  `Stop Pending`) qui n'est ni demarre ni arrete : il devient `UNKNOWN` plutot
  que d'etre range arbitrairement d'un cote.
#>
function Get-ServiceStateName {
  param([string]$State)

  switch ($State) {
    'Running' { return 'RUNNING' }
    'Stopped' { return 'STOPPED' }
    default { return 'UNKNOWN' }
  }
}

<#
.SYNOPSIS
  Mode de demarrage d'un service, dans le vocabulaire du schema.

.DESCRIPTION
  Fonction pure. `Auto` et `Automatic` designent la meme chose selon la source
  interrogee ; `Boot` et `System` sont des pilotes demarres par le noyau, donc
  actives.
#>
function Get-ServiceStartupName {
  param([string]$StartMode)

  switch ($StartMode) {
    'Auto' { return 'ENABLED' }
    'Automatic' { return 'ENABLED' }
    'Boot' { return 'ENABLED' }
    'System' { return 'ENABLED' }
    'Disabled' { return 'DISABLED' }
    'Manual' { return 'MANUAL' }
    default { return 'UNKNOWN' }
  }
}

<#
.SYNOPSIS
  Premier numero de version reconnaissable dans la sortie d'une commande.

.DESCRIPTION
  Fonction pure, jumelle de `extract_version` cote Linux, et pour la meme
  raison : `go version` affiche « go version go1.22.5 windows/amd64 », ou une
  expression gourmande retiendrait « 22.5 » ou l'architecture.

  Rend une chaine vide plutot qu'une approximation quand rien n'est
  reconnaissable.
#>
function Get-VersionFromOutput {
  param([string]$Output)

  if ([string]::IsNullOrWhiteSpace($Output)) { return '' }

  foreach ($line in ($Output -split "`n")) {
    $trimmed = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
    $match = [regex]::Match($trimmed, '\d+\.\d+(\.\d+)*')
    if ($match.Success) { return $match.Value }
  }

  return ''
}

# Runtimes sondes, avec l'option qui publie leur version.
#
# La liste est **fermee et ecrite en dur** : le scanner n'execute jamais une
# commande construite a partir d'une donnee du systeme audite.
#
# `java -version` ecrit sur la sortie d'erreur, y compris en cas de succes.
# Elle est donc redirigee, faute de quoi la version resterait inconnue sur
# toutes les machines dotees d'un JDK.
$script:RuntimeProbes = @(
  @{ Name = 'node'; Argument = '--version' },
  @{ Name = 'python'; Argument = '--version' },
  @{ Name = 'java'; Argument = '-version' },
  @{ Name = 'go'; Argument = 'version' },
  @{ Name = 'php'; Argument = '--version' },
  @{ Name = 'ruby'; Argument = '--version' },
  @{ Name = 'perl'; Argument = '--version' },
  @{ Name = 'dotnet'; Argument = '--version' },
  @{ Name = 'rustc'; Argument = '--version' },
  @{ Name = 'docker'; Argument = '--version' },
  @{ Name = 'podman'; Argument = '--version' },
  @{ Name = 'pwsh'; Argument = '--version' }
)

<#
.SYNOPSIS
  Runtimes installes, version lue en executant la commande.

.DESCRIPTION
  Rien n'est deduit de la presence d'un fichier ni d'un nom de paquet : une
  version qui n'a pas ete lue reste un marqueur.
#>
function Get-RuntimeList {
  $runtimes = @()

  foreach ($probe in $script:RuntimeProbes) {
    $command = Get-Command $probe.Name -CommandType Application -ErrorAction SilentlyContinue |
      Select-Object -First 1
    if ($null -eq $command) { continue }

    $output = ''
    try {
      # `2>&1` capture la sortie d'erreur : plusieurs runtimes y publient leur
      # version en cas de succes.
      $output = (& $command.Source $probe.Argument 2>&1 | Out-String)
    } catch {
      $output = ''
    }

    $version = Get-VersionFromOutput -Output $output
    $runtimes += @{
      name = $probe.Name
      version = if ([string]::IsNullOrWhiteSpace($version)) {
        New-Unknown -Reason 'UNKNOWN' -Detail 'numero de version non reconnu dans la sortie'
      } else { $version }
      path = Get-StringOrUnknown -Value $command.Source -Reason 'UNKNOWN'
    }
  }

  # PowerShell deballe volontiers un tableau d'un seul element lorsqu'il sort
  # d'une fonction. Le schema attend pourtant toujours `software.runtimes` sous
  # forme de tableau JSON, meme lorsqu'une seule commande est presente.
  return @($runtimes)
}

<#
.SYNOPSIS
  Entrees de la base de desinstallation du registre.

.DESCRIPTION
  Les trois emplacements sont lus : 64 bits, 32 bits sur systeme 64 bits, et
  utilisateur courant. Un logiciel installe pour l'utilisateur n'apparait dans
  aucun des deux premiers, et l'omettre ferait disparaitre de l'inventaire tout
  ce qui s'installe sans elevation — dont la majorite des navigateurs.
#>
function Get-UninstallEntryList {
  $roots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )

  $entries = @()
  foreach ($root in $roots) {
    try {
      $entries += @(Get-ItemProperty -Path $root -ErrorAction Stop)
    } catch {
      # Une racine absente n'est pas une erreur : `WOW6432Node` n'existe pas sur
      # un Windows 32 bits, et `HKCU` peut etre vide.
      continue
    }
  }

  return $entries
}

<#
.SYNOPSIS
  Section `software` du rapport.
#>
function Get-SoftwareInventory {
  $packages = @()
  $seen = @{}

  foreach ($entry in (Get-UninstallEntryList)) {
    if (-not (Test-UninstallEntryIsPackage -Entry $entry)) { continue }

    $name = ([string]$entry.DisplayName).Trim()
    $version = [string]$entry.DisplayVersion
    # Une meme application installee pour la machine et pour l'utilisateur
    # figure dans deux racines. Le couple nom-version dedoublonne sans masquer
    # deux versions reellement coexistantes.
    $key = $name + '@' + $version
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true

    $package = @{
      name = $name
      version = Get-StringOrUnknown -Value $version -Reason 'UNKNOWN'
      source = 'registry'
      vendor = Get-StringOrUnknown -Value $entry.Publisher -Reason 'UNKNOWN'
    }

    $installDate = Convert-RegistryInstallDate -Value ([string]$entry.InstallDate)
    if ($null -ne $installDate) { $package.installDate = $installDate }

    $packages += $package
  }

  $registryCount = $packages.Count

  # Applications empaquetees. `Get-AppxPackage` n'existe pas sur Windows Server
  # Core ni sur les editions sans Store : son absence laisse la source vide,
  # elle n'invalide pas l'inventaire.
  $appxCount = 0
  if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
    try {
      foreach ($appx in @(Get-AppxPackage -ErrorAction Stop)) {
        $name = [string]$appx.Name
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        $appxCount += 1
        $packages += @{
          name = $name
          version = Get-StringOrUnknown -Value $appx.Version -Reason 'UNKNOWN'
          source = 'appx'
          vendor = Get-StringOrUnknown -Value $appx.Publisher -Reason 'UNKNOWN'
        }
      }
    } catch {
      Add-CollectionIssue -Section 'software.packages' -Severity 'warning' `
        -Message ('Applications empaquetees non enumerees : ' + $_.Exception.Message) `
        -Source 'Get-AppxPackage' -Reason 'NOT_AVAILABLE'
    }
  }

  $packageCount = $packages.Count

  # Le schema borne l'inventaire a 5000 entrees. Au-dela, seul le decompte est
  # conserve, et la troncature est **declaree** : un inventaire silencieusement
  # coupe se lirait comme un inventaire complet.
  $truncated = $false
  if ($packages.Count -gt 5000) {
    $packages = @($packages | Select-Object -First 5000)
    $truncated = $true
  }

  $managers = @()
  if ($registryCount -gt 0) {
    $managers += @{
      name = 'registry'
      # `UNSUPPORTED` et non `NOT_AVAILABLE` : la base de desinstallation n'est
      # pas un programme dont on pourrait lire la version, la notion elle-meme
      # n'a pas de sens ici. `NOT_APPLICABLE` aurait mieux dit les choses, mais
      # ce motif n'existe pas dans `UNKNOWN_REASONS` — l'y ecrire faisait
      # refuser tout rapport de niveau Complete par le schema.
      version = New-Unknown -Reason 'UNSUPPORTED' -Detail 'la base de desinstallation n''est pas un programme versionne'
      packageCount = $registryCount
    }
  }
  if ($appxCount -gt 0) {
    $managers += @{
      name = 'appx'
      version = New-Unknown -Reason 'NOT_AVAILABLE'
      packageCount = $appxCount
    }
  }

  $winget = Get-Command winget -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -ne $winget) {
    $wingetVersion = ''
    try {
      $wingetVersion = Get-VersionFromOutput -Output ((& $winget.Source '--version' 2>&1) | Out-String)
    } catch {
      $wingetVersion = ''
    }
    $managers += @{
      name = 'winget'
      version = if ([string]::IsNullOrWhiteSpace($wingetVersion)) { New-Unknown -Reason 'UNKNOWN' } else { $wingetVersion }
      # Volontairement non compte : `winget list` ne publie qu'un tableau
      # destine a l'oeil, tronque a la largeur de la console. Un decompte tire
      # de la ne vaudrait pas sa precision apparente.
      packageCount = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'winget ne publie pas d''inventaire exploitable'
    }
  }

  $services = @()
  try {
    foreach ($service in @(Get-CimInstance -ClassName 'Win32_Service' -ErrorAction Stop)) {
      $name = [string]$service.Name
      if ([string]::IsNullOrWhiteSpace($name)) { continue }
      $services += @{
        name = $name
        displayName = Get-StringOrUnknown -Value $service.DisplayName -Reason 'UNKNOWN'
        state = Get-ServiceStateName -State ([string]$service.State)
        startup = Get-ServiceStartupName -StartMode ([string]$service.StartMode)
      }
    }
    Add-CollectionProvenance -Path 'software.services' -Source 'Win32_Service' -Method 'CIM'
  } catch {
    Add-CollectionIssue -Section 'software.services' -Severity 'warning' `
      -Message ('Services non enumeres : ' + $_.Exception.Message) -Source 'Win32_Service' -Reason 'NOT_AVAILABLE'
  }

  Add-CollectionProvenance -Path 'software.packages' -Source 'registre de desinstallation' -Method 'registre'

  return @{
    packages = $packages
    packageCount = $packageCount
    packagesTruncated = $truncated
    packageManagers = $managers
    runtimes = @(Get-RuntimeList)
    services = $services
  }
}
