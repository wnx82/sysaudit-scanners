# SysAudit Windows — identite de la machine et systeme d'exploitation.

function Get-SystemInventory {
  $cs = Get-CimInstance Win32_ComputerSystem
  $bios = Get-CimInstance Win32_BIOS
  $os = Get-CimInstance Win32_OperatingSystem
  $product = Get-CimInstance Win32_ComputerSystemProduct
  $baseBoard = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
  $enclosure = Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue

  return @{
    computerSystem = $cs
    bios = $bios
    os = $os
    product = $product
    baseBoard = $baseBoard
    enclosure = $enclosure
  }
}

function Get-SystemSection {
  param([Parameter(Mandatory = $true)]$Inventory)

  $cs = $Inventory.computerSystem
  $bios = $Inventory.bios
  $os = $Inventory.os
  $product = $Inventory.product
  $enclosure = $Inventory.enclosure

  $identity = Get-DomainIdentity -ComputerSystem $cs

  return @{
    hostname = Get-StringOrUnknown -Value $env:COMPUTERNAME -Reason 'UNKNOWN'
    fqdn = $identity.fqdn
    domain = $identity.domain
    workgroup = $identity.workgroup
    manufacturer = Get-StringOrUnknown -Value $cs.Manufacturer -Reason 'UNKNOWN'
    model = Get-StringOrUnknown -Value $cs.Model -Reason 'UNKNOWN'
    chassisType = if ($enclosure -and $enclosure.ChassisTypes) { Get-StringOrUnknown -Value ($enclosure.ChassisTypes -join ',') -Reason 'UNKNOWN' } else { New-Unknown -Reason 'NOT_AVAILABLE' }
    uuid = Get-StringOrUnknown -Value $product.UUID -Reason 'UNKNOWN'
    # `To be filled by O.E.M.` n'est pas un numero de serie : s'en servir pour
    # identifier une machine ferait passer tous les assemblages d'un meme
    # integrateur pour la meme.
    serialNumber = Get-MeaningfulStringOrUnknown -Value $bios.SerialNumber -Reason 'UNKNOWN'
    assetTag = if ($null -ne $enclosure) {
      Get-StringOrUnknown -Value (Get-MeaningfulSmbiosValue -Value $enclosure.SMBIOSAssetTag) `
        -Reason 'NOT_AVAILABLE' -Detail 'etiquette d''inventaire non renseignee'
    } else {
      New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'Win32_SystemEnclosure illisible'
    }
    machineGuid = Get-MachineGuid
    machineSid = Get-MachineSid
    architecture = Get-StringOrUnknown -Value $os.OSArchitecture -Reason 'UNKNOWN'
    uptimeSeconds = [int][Math]::Max(0, ((Get-Date) - $os.LastBootUpTime).TotalSeconds)
    timezone = Get-StringOrUnknown -Value (Get-TimeZone).Id -Reason 'UNKNOWN'
    localTime = (Get-Date).ToString('o')
  }
}

<#
.SYNOPSIS
  Nom qualifie, domaine et groupe de travail.

.DESCRIPTION
  `Win32_ComputerSystem.Domain` porte **soit** le domaine Active Directory
  **soit** le groupe de travail, et seul `PartOfDomain` dit lequel. Recopier ce
  champ dans `domain` sans le lire ferait passer tout un parc en groupe de
  travail pour un parc joint a un annuaire -- une difference qui change ce qu'un
  technicien ira verifier en premier.

  Le nom qualifie est compose de `DNSHostName` et du domaine, ce qui est sa
  definition sous Windows et non une reconstitution : les deux morceaux
  viennent de la meme classe CIM, remplis par le meme composant du systeme.
  Hors domaine, il n'y a pas de nom qualifie -- et le champ le dit plutot que
  de rendre le nom court.

  Aucune resolution DNS n'est declenchee ici. `[System.Net.Dns]` interrogerait
  le reseau, ce qu'un scanner read-only n'a pas a faire pour se nommer, et ce
  qui bloquerait l'audit sur une machine dont le resolveur ne repond pas.
#>
function Get-DomainIdentity {
  param($ComputerSystem)

  $partOfDomain = $false
  if ($null -ne $ComputerSystem -and $null -ne $ComputerSystem.PartOfDomain) {
    $partOfDomain = [bool]$ComputerSystem.PartOfDomain
  }

  $domainValue = if ($null -ne $ComputerSystem) { ([string]$ComputerSystem.Domain).Trim() } else { '' }
  $shortName = if ($null -ne $ComputerSystem) { ([string]$ComputerSystem.DNSHostName).Trim() } else { '' }
  if ([string]::IsNullOrWhiteSpace($shortName)) { $shortName = [string]$env:COMPUTERNAME }

  if (-not $partOfDomain) {
    $workgroup = $domainValue
    if ($null -ne $ComputerSystem -and -not [string]::IsNullOrWhiteSpace([string]$ComputerSystem.Workgroup)) {
      $workgroup = ([string]$ComputerSystem.Workgroup).Trim()
    }

    return @{
      fqdn = New-Unknown -Reason 'NOT_APPLICABLE' -Detail 'machine hors domaine : pas de nom qualifie'
      domain = New-Unknown -Reason 'NOT_APPLICABLE' -Detail 'machine en groupe de travail'
      workgroup = Get-StringOrUnknown -Value $workgroup -Reason 'UNKNOWN'
    }
  }

  $fqdn = if (-not [string]::IsNullOrWhiteSpace($domainValue) -and -not [string]::IsNullOrWhiteSpace($shortName)) {
    $shortName + '.' + $domainValue
  } else {
    $null
  }

  return @{
    fqdn = Get-StringOrUnknown -Value $fqdn -Reason 'UNKNOWN'
    domain = Get-StringOrUnknown -Value $domainValue -Reason 'UNKNOWN'
    workgroup = New-Unknown -Reason 'NOT_APPLICABLE' -Detail 'machine jointe a un domaine'
  }
}

<#
.SYNOPSIS
  Identifiant de l'installation Windows (`MachineGuid`).

.DESCRIPTION
  Ecrit une fois pour toutes a l'installation, sous
  `HKLM\SOFTWARE\Microsoft\Cryptography`. Il ne decrit aucun materiel : il
  survit a un changement de carte mere et suit un disque clone. C'est ce qui en
  fait le bon identifiant pour reconnaitre un poste re-deploye -- et une donnee
  reservee a son proprietaire, puisqu'elle rapproche deux audits a elle seule.

  La lecture reste en lecture seule et sans elevation : cette cle est lisible
  par tout utilisateur.
#>
function Get-MachineGuid {
  try {
    $entry = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name 'MachineGuid' -ErrorAction Stop
    return (Get-StringOrUnknown -Value $entry.MachineGuid -Reason 'UNKNOWN')
  } catch {
    return (New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'cle Cryptography\MachineGuid illisible')
  }
}

<#
.SYNOPSIS
  SID de la machine.

.DESCRIPTION
  Windows ne publie pas le SID machine tel quel : il se lit sur un compte local
  integre, dont le SID est celui de la machine suivi d'un identifiant relatif
  connu (`-500` pour l'Administrateur integre). Retirer ce suffixe n'est pas une
  deduction : c'est la structure meme d'un SID de compte local.

  Le filtre `LocalAccount=True` n'est pas un confort : sans lui, l'enumeration
  interroge l'annuaire sur une machine jointe a un domaine, et peut y passer
  plusieurs minutes.
#>
function Get-MachineSid {
  try {
    $account = Get-CimInstance Win32_UserAccount -Filter "LocalAccount=True AND SID LIKE 'S-1-5-21-%-500'" -ErrorAction Stop |
      Select-Object -First 1
    if ($null -eq $account) {
      return (New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'aucun compte local integre trouve')
    }

    $sid = [string]$account.SID
    $cut = $sid.LastIndexOf('-')
    if ($cut -le 0) {
      return (New-Unknown -Reason 'UNKNOWN' -Detail 'SID de compte local de forme inattendue')
    }

    return (Get-StringOrUnknown -Value $sid.Substring(0, $cut) -Reason 'UNKNOWN')
  } catch {
    return (New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'Win32_UserAccount illisible')
  }
}

function Get-OsSection {
  param([Parameter(Mandatory = $true)]$Inventory)

  $os = $Inventory.os

  return @{
    family = 'windows'
    name = Get-StringOrUnknown -Value $os.Caption -Reason 'UNKNOWN'
    edition = Get-StringOrUnknown -Value $os.Caption -Reason 'UNKNOWN'
    distribution = 'Windows'
    version = Get-StringOrUnknown -Value $os.Version -Reason 'UNKNOWN'
    build = Get-StringOrUnknown -Value $os.BuildNumber -Reason 'UNKNOWN'
    kernel = Get-StringOrUnknown -Value $os.Version -Reason 'UNKNOWN'
    architecture = Get-StringOrUnknown -Value $os.OSArchitecture -Reason 'UNKNOWN'
    installDate = $(if ($os.InstallDate) { (Get-Date $os.InstallDate).ToString('yyyy-MM-dd') } else { New-Unknown -Reason 'UNKNOWN' })
    locale = Get-StringOrUnknown -Value (Get-Culture).Name -Reason 'UNKNOWN'
    timezone = Get-StringOrUnknown -Value (Get-TimeZone).Id -Reason 'UNKNOWN'
  }
}
