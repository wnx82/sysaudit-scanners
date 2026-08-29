# SysAudit Windows — compatibilité Windows legacy.
#
# Ce fichier n'active pas encore le scanner legacy. Il fixe le vocabulaire et
# les replis dont les collecteurs auront besoin lorsqu'ils cesseront de supposer
# CIM et `Get-WinEvent`.

function Test-LegacyCommand {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [string[]]$CommandType = @('Alias', 'Function', 'Cmdlet', 'Application')
  )

  return $null -ne (Get-Command $Name -CommandType $CommandType -ErrorAction SilentlyContinue)
}

function Get-LegacyCommandName {
  param(
    [Parameter(Mandatory = $true)][string[]]$Candidates
  )

  foreach ($candidate in $Candidates) {
    if (Test-LegacyCommand -Name $candidate) { return $candidate }
  }

  return ''
}

function Resolve-LegacyScannerKind {
  param(
    [string]$Version = '',
    [string]$Caption = ''
  )

  $parsed = $null
  if (-not [string]::IsNullOrWhiteSpace($Version)) {
    try { $parsed = [version]$Version } catch { $parsed = $null }
  }

  if ($null -ne $parsed) {
    if ($parsed.Major -ge 10) { return 'windows' }
    if ($parsed.Major -eq 6 -and $parsed.Minor -ge 1) { return 'windows-legacy' }
    if (($parsed.Major -eq 6 -and $parsed.Minor -eq 0) -or $parsed.Major -le 5) {
      return 'windows-minimal'
    }
  }

  if ($Caption -match 'Windows 11|Windows 10|Windows Server') { return 'windows' }
  if ($Caption -match 'Windows 8\.1|Windows 8|Windows 7') { return 'windows-legacy' }
  if ($Caption -match 'Windows Vista|Windows XP|Windows 2000|Windows 2003') {
    return 'windows-minimal'
  }

  return 'windows'
}

function Get-LegacyOsVersion {
  param(
    $OperatingSystem
  )

  if ($null -eq $OperatingSystem) {
    return @{
      caption = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'inventaire systeme absent'
      version = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'inventaire systeme absent'
      build = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'inventaire systeme absent'
      architecture = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'inventaire systeme absent'
      servicePack = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'inventaire systeme absent'
      scannerKind = 'windows'
    }
  }

  $versionText = ''
  if ($null -ne $OperatingSystem.PSObject.Properties['Version']) {
    $versionText = [string]$OperatingSystem.Version
  }
  $caption = ''
  if ($null -ne $OperatingSystem.PSObject.Properties['Caption']) {
    $caption = [string]$OperatingSystem.Caption
  }

  $servicePack = ''
  if ($null -ne $OperatingSystem.PSObject.Properties['CSDVersion'] -and
      -not [string]::IsNullOrWhiteSpace([string]$OperatingSystem.CSDVersion)) {
    $servicePack = [string]$OperatingSystem.CSDVersion
  } elseif ($null -ne $OperatingSystem.PSObject.Properties['ServicePackMajorVersion'] -and
      [int]$OperatingSystem.ServicePackMajorVersion -gt 0) {
    $servicePack = 'SP' + [string]$OperatingSystem.ServicePackMajorVersion
  }

  return @{
    caption = Get-StringOrUnknown -Value $caption -Reason 'UNKNOWN'
    version = Get-StringOrUnknown -Value $versionText -Reason 'UNKNOWN'
    build = Get-StringOrUnknown -Value $OperatingSystem.BuildNumber -Reason 'UNKNOWN'
    architecture = Get-StringOrUnknown -Value $OperatingSystem.OSArchitecture -Reason 'UNKNOWN'
    servicePack = Get-StringOrUnknown -Value $servicePack -Reason 'NOT_AVAILABLE'
    scannerKind = Resolve-LegacyScannerKind -Version $versionText -Caption $caption
  }
}

function Get-LegacyRuntimeCapabilities {
  $eventReader = Get-LegacyCommandName -Candidates @('Get-WinEvent', 'Get-EventLog')
  $inventoryReader = Get-LegacyCommandName -Candidates @('Get-CimInstance', 'Get-WmiObject')

  return @{
    powershellMajor = $PSVersionTable.PSVersion.Major
    powershellMinor = $PSVersionTable.PSVersion.Minor
    cim = (Test-LegacyCommand -Name 'Get-CimInstance')
    wmi = (Test-LegacyCommand -Name 'Get-WmiObject')
    winEvent = (Test-LegacyCommand -Name 'Get-WinEvent')
    eventLog = (Test-LegacyCommand -Name 'Get-EventLog')
    computerInfo = (Test-LegacyCommand -Name 'Get-ComputerInfo')
    eventReader = if ([string]::IsNullOrWhiteSpace($eventReader)) { 'unsupported' } else { $eventReader }
    inventoryReader = if ([string]::IsNullOrWhiteSpace($inventoryReader)) { 'unsupported' } else { $inventoryReader }
  }
}

function New-LegacyUnsupportedMarker {
  param(
    [Parameter(Mandatory = $true)][string]$Capability,
    [Parameter(Mandatory = $true)][string]$Reason,
    [string]$Detail = ''
  )

  $message = 'Capacite legacy indisponible : ' + $Capability
  if (-not [string]::IsNullOrWhiteSpace($Detail)) {
    $message += ' (' + $Detail + ')'
  }

  $marker = New-Unknown -Reason $Reason -Detail $message
  $marker.capability = $Capability
  return $marker
}

# `Get-WmiObject` est deprecie, et PSScriptAnalyzer a raison de le signaler
# partout ailleurs. Ici il est **le sujet** : cette fonction existe pour lire
# une machine anterieure a PowerShell 3.0, ou `Get-CimInstance` n'existe pas.
# CIM reste essaye en premier ; WMI n'est atteint que s'il a echoue, et
# seulement quand l'appelant l'autorise explicitement par `-AllowWmi`.
# Remplacer ces trois appels par CIM retirerait la seule raison d'etre du
# fichier.
function Get-LegacyWmiValue {
  [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWMICmdlet', '',
    Justification = 'Repli delibere pour les systemes sans CIM ; CIM est toujours tente en premier.'
  )]
  param(
    [string]$ClassName = '',
    [string]$Namespace = '',
    [string]$Query = '',
    [switch]$AllowCim,
    [switch]$AllowWmi
  )

  if ($AllowCim -and (Test-LegacyCommand -Name 'Get-CimInstance')) {
    if (-not [string]::IsNullOrWhiteSpace($Query)) {
      return Get-CimInstance -Query $Query -ErrorAction Stop
    }
    if ([string]::IsNullOrWhiteSpace($Namespace)) {
      return Get-CimInstance -ClassName $ClassName -ErrorAction Stop
    }
    return Get-CimInstance -Namespace $Namespace -ClassName $ClassName -ErrorAction Stop
  }

  if ($AllowWmi -and (Test-LegacyCommand -Name 'Get-WmiObject')) {
    if (-not [string]::IsNullOrWhiteSpace($Query)) {
      return Get-WmiObject -Query $Query -ErrorAction Stop
    }
    if ([string]::IsNullOrWhiteSpace($Namespace)) {
      return Get-WmiObject -Class $ClassName -ErrorAction Stop
    }
    return Get-WmiObject -Namespace $Namespace -Class $ClassName -ErrorAction Stop
  }

  throw 'Ni CIM ni WMI ne sont disponibles pour cette lecture.'
}

function Get-LegacyRegistryValue {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Name
  )

  try {
    $entry = Get-ItemProperty -Path $Path -ErrorAction Stop
  } catch {
    return (New-LegacyUnsupportedMarker -Capability ('registry:' + $Path + ':' + $Name) `
      -Reason 'NOT_AVAILABLE' -Detail 'cle ou acces indisponible')
  }

  if ($null -eq $entry.PSObject.Properties[$Name]) {
    return (New-LegacyUnsupportedMarker -Capability ('registry:' + $Path + ':' + $Name) `
      -Reason 'NOT_AVAILABLE' -Detail 'valeur absente')
  }

  return $entry.$Name
}
