# SysAudit Windows — alimentation, batterie et plan d'energie.
#
# Le plan d'alimentation explique des mesures qui sembleraient sinon
# contradictoires : un processeur bride a la moitie de sa frequence sous un
# profil « economie d'energie » n'a rien d'anormal, et l'attribuer a un defaut
# materiel serait un faux diagnostic. Le scanner rapporte le nom natif sans le
# traduire ni le juger.

<#
.SYNOPSIS
  Plan d'alimentation actif.

.DESCRIPTION
  `Win32_PowerPlan` vit dans `root\cimv2\power`, un espace de noms distinct.
  Il est absent de certaines editions Server et des images minimales : son
  absence est declaree, jamais devinee.

  `powercfg /getactivescheme` donnerait la meme information, mais lancer un
  processus externe la ou une requete CIM suffit ajoute un cout et une
  dependance a la langue de sortie.
#>
function Get-ActivePowerPlan {
  try {
    $plan = Get-CimInstance -Namespace 'root\cimv2\power' -ClassName 'Win32_PowerPlan' `
      -Filter 'IsActive = True' -ErrorAction Stop | Select-Object -First 1
    if ($null -ne $plan) {
      return (Get-StringOrUnknown -Value $plan.ElementName -Reason 'UNKNOWN')
    }
  } catch {
    return (New-Unknown -Reason 'NOT_AVAILABLE' `
        -Detail 'espace de noms root\cimv2\power absent de cette edition')
  }
  return (New-Unknown -Reason 'UNKNOWN' -Detail 'aucun plan actif rapporte')
}

<#
.SYNOPSIS
  Batteries, telles que Windows les expose.

.DESCRIPTION
  `Win32_Battery` publie la capacite de conception mais **pas** la capacite
  reelle a pleine charge : celle-ci vit dans `BatteryFullChargedCapacity`, une
  classe de `root\wmi` qui n'est pas toujours implementee par le micrologiciel.

  Sans elle, l'usure n'est pas calculable — et le rapport le dit plutot que de
  la deduire de la charge courante, qui ne la donne pas.
#>
function Get-BatteryReportList {
  param([object[]]$Batteries)

  if ($null -eq $Batteries) { return , @() }

  # PowerShell deballe un tableau d'un seul element a la sortie d'une
  # fonction. Sans la virgule de tete, `power.batteries` devient un objet des
  # qu'une machine n'annonce qu'une seule batterie — soit le cas le plus
  # frequent — et le schema refuse alors tout le rapport.
  return , @($Batteries)
}

function Get-BatteryList {
  $batteries = @()

  try {
    $devices = @(Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop)
  } catch {
    return @()
  }

  # Capacites a pleine charge, indexees par nom d'instance quand la classe
  # existe. Une machine de bureau n'en a aucune, ce qui est normal.
  $fullCharge = @{}
  try {
    foreach ($entry in @(Get-CimInstance -Namespace 'root\wmi' `
          -ClassName 'BatteryFullChargedCapacity' -ErrorAction Stop)) {
      $fullCharge[[string]$entry.InstanceName] = [int64]$entry.FullChargedCapacity
    }
  } catch {
    # Micrologiciel qui n'implemente pas la classe : l'usure restera inconnue.
    Write-Debug ('BatteryFullChargedCapacity absente : ' + $_.Exception.Message)
  }

  foreach ($device in $devices) {
    $designWh = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'capacite de conception non exposee'
    if ($device.DesignCapacity) {
      # `Win32_Battery` publie des milliwattheures ; le schema attend des
      # wattheures.
      $designWh = [Math]::Round([double]$device.DesignCapacity / 1000, 2)
    }

    $fullWh = New-Unknown -Reason 'NOT_AVAILABLE' `
      -Detail 'BatteryFullChargedCapacity non implementee par ce micrologiciel'
    foreach ($key in $fullCharge.Keys) {
      $fullWh = [Math]::Round([double]$fullCharge[$key] / 1000, 2)
      break
    }

    $status = switch ([int]$device.BatteryStatus) {
      1 { 'DISCHARGING' }
      2 { 'NOT_CHARGING' }
      3 { 'FULL' }
      6 { 'CHARGING' }
      default { 'UNKNOWN' }
    }

    $batteries += @{
      name = Get-StringOrUnknown -Value $device.Name -Reason 'UNKNOWN'
      manufacturer = Get-StringOrUnknown -Value $device.Manufacturer -Reason 'UNKNOWN'
      model = Get-StringOrUnknown -Value $device.DeviceID -Reason 'UNKNOWN'
      serialNumber = New-Unknown -Reason 'NOT_AVAILABLE' `
        -Detail 'Win32_Battery ne publie pas de numero de serie'
      technology = Get-StringOrUnknown -Value $device.Chemistry -Reason 'UNKNOWN'
      chargePercent = Get-NumberOrUnknown -Value $device.EstimatedChargeRemaining -Reason 'UNKNOWN'
      status = $status
      designCapacityWh = $designWh
      fullChargeCapacityWh = $fullWh
      cycleCount = New-Unknown -Reason 'NOT_AVAILABLE' `
        -Detail 'compteur de cycles non expose par Win32_Battery'
      voltageVolts = if ($device.DesignVoltage) {
        [Math]::Round([double]$device.DesignVoltage / 1000, 3)
      } else {
        New-Unknown -Reason 'NOT_AVAILABLE'
      }
    }
  }

  Get-BatteryReportList -Batteries $batteries
}

function Get-PowerSection {
  $batteries = Get-BatteryList

  # Secteur branche. `Win32_Battery` absent signifie machine de bureau : elle
  # est alimentee par definition, mais l'affirmer serait une deduction. La
  # classe `BatteryStatus` de `root\wmi` repond directement quand elle existe.
  $acConnected = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'aucune source d''alimentation interrogeable'
  try {
    $status = Get-CimInstance -Namespace 'root\wmi' -ClassName 'BatteryStatus' -ErrorAction Stop |
      Select-Object -First 1
    if ($null -ne $status) { $acConnected = [bool]$status.PowerOnline }
  } catch {
    if ($batteries.Count -eq 0) {
      $acConnected = New-Unknown -Reason 'NOT_APPLICABLE' `
        -Detail 'machine sans batterie : la notion de secteur branche n''a pas d''objet'
    }
  }

  Add-CollectionProvenance -Path 'power.activePlan' -Source 'Win32_PowerPlan' -Method 'CIM'

  return @{
    batteries = $batteries
    acConnected = $acConnected
    activePlan = Get-ActivePowerPlan
    cpuGovernor = New-Unknown -Reason 'NOT_APPLICABLE' `
      -Detail 'notion propre a cpufreq, sous Linux'
    powerSupply = Get-PowerSupplySection
  }
}

# --- Bloc d'alimentation -----------------------------------------------------
#
# Windows ne sait presque rien de l'alimentation d'un PC, et ce collecteur
# existe surtout pour le dire honnetement.
#
# `Win32_PowerSupply` est la classe que tout le monde essaie en premier : elle
# est vide sur la quasi-totalite des machines, et quand elle rend quelque chose
# c'est une entree generique issue du firmware, jamais le modele reel du bloc.
# Elle n'est donc retenue que si elle porte une identite exploitable.
#
# La table SMBIOS brute, elle, contient la structure type 39 lorsque le firmware
# la publie — c'est le cas des serveurs et de quelques stations. Elle se lit par
# `MSSmBios_RawSMBiosTables`, en octets, ce que Windows n'expose sous aucune
# forme structuree.

<#
.SYNOPSIS
  Nature du bloc, telle que le champ Characteristics du SMBIOS la code.

.DESCRIPTION
  Bits 13 a 10 du mot de caracteristiques, selon la specification DMTF. Seule
  une alimentation a decoupage conclut a `STANDARD_ATX` : c'est le firmware qui
  le dit, pas la forme du boitier.
#>
function ConvertTo-PowerSupplyType {
  param([int]$Characteristics)

  switch (($Characteristics -shr 10) -band 0x0F) {
    4 { return 'STANDARD_ATX' }
    6 { return 'UPS' }
    default { return 'UNKNOWN' }
  }
}

<#
.SYNOPSIS
  Etat du bloc, code sur les bits 9 a 7 du meme mot.
#>
function ConvertTo-PowerSupplyStatus {
  param([int]$Characteristics)

  switch (($Characteristics -shr 7) -band 0x07) {
    1 { return 'Other' }
    3 { return 'OK' }
    4 { return 'Non-critical' }
    5 { return 'Critical' }
    default { return '' }
  }
}

<#
.SYNOPSIS
  Chaines d'une structure SMBIOS, indexees a partir de 1.

.DESCRIPTION
  Le format est celui de la specification : les chaines suivent la zone
  formatee, separees par un octet nul, et la table se termine par deux nuls
  consecutifs. L'index 0 signifie « pas de chaine » — et non « chaine vide ».
#>
function Get-SmbiosStringTable {
  param(
    [byte[]]$Data,
    [int]$Start
  )

  $strings = @()
  $current = New-Object System.Text.StringBuilder
  $offset = $Start

  while ($offset -lt $Data.Length) {
    $byte = $Data[$offset]
    if ($byte -eq 0) {
      if ($current.Length -eq 0) { break }
      $strings += $current.ToString()
      $current = New-Object System.Text.StringBuilder
    } else {
      [void]$current.Append([char]$byte)
    }
    $offset++
  }

  return , @($strings)
}

<#
.SYNOPSIS
  Valeur d'un champ chaine d'une structure SMBIOS.

.DESCRIPTION
  Les valeurs de remplissage des firmwares (« To Be Filled By O.E.M. ») ne sont
  pas des donnees : les rapporter telles quelles ferait passer un champ vide
  pour un fabricant.
#>
function Get-SmbiosString {
  param(
    [string[]]$Strings,
    [int]$Index
  )

  if ($Index -le 0 -or $Index -gt $Strings.Count) { return '' }
  return (Get-MeaningfulSmbiosValue -Value $Strings[$Index - 1])
}

<#
.SYNOPSIS
  Blocs d'alimentation decrits par la table SMBIOS brute.

.DESCRIPTION
  Parcourt les structures, retient celles de type 39 et en lit les champs aux
  decalages fixes par la specification (SMBIOS 2.3.1, §7.40).

  Prend les octets en parametre plutot que d'interroger CIM : c'est ce qui rend
  l'analyse testable sur une table synthetique, faute de serveur en CI.
#>
function ConvertFrom-SmbiosPowerSupplyTable {
  param([byte[]]$Data)

  $units = @()
  # Pas de virgule de tete ici, contrairement a `Get-BatteryReportList` : ces
  # unites sont assemblees par l'appelant, qui les enveloppe lui-meme dans
  # `@(...)`. Empecher le deballage produirait un tableau dans un tableau, et
  # une machine sans alimentation decrite compterait une unite fantome.
  if ($null -eq $Data -or $Data.Length -lt 4) { return $units }

  $offset = 0
  $index = 0
  while ($offset + 4 -le $Data.Length) {
    $type = $Data[$offset]
    $length = $Data[$offset + 1]
    # Une longueur nulle ferait boucler indefiniment sur une table tronquee.
    if ($length -lt 4) { break }
    if ($offset + $length -gt $Data.Length) { break }

    $strings = Get-SmbiosStringTable -Data $Data -Start ($offset + $length)

    if ($type -eq 39 -and $length -ge 0x10) {
      $index++
      $characteristics = [int]$Data[$offset + 0x0E] + ([int]$Data[$offset + 0x0F] -shl 8)
      $capacity = [int]$Data[$offset + 0x0C] + ([int]$Data[$offset + 0x0D] -shl 8)

      $location = Get-SmbiosString -Strings $strings -Index $Data[$offset + 0x05]
      $name = Get-SmbiosString -Strings $strings -Index $Data[$offset + 0x06]
      $manufacturer = Get-SmbiosString -Strings $strings -Index $Data[$offset + 0x07]
      $serial = Get-SmbiosString -Strings $strings -Index $Data[$offset + 0x08]
      $asset = Get-SmbiosString -Strings $strings -Index $Data[$offset + 0x09]
      $part = Get-SmbiosString -Strings $strings -Index $Data[$offset + 0x0A]
      $revision = Get-SmbiosString -Strings $strings -Index $Data[$offset + 0x0B]

      $label = $name
      if ([string]::IsNullOrWhiteSpace($label)) { $label = $location }
      if ([string]::IsNullOrWhiteSpace($label)) { $label = "Alimentation $index" }

      # 0x8000 est le code « inconnu » de la specification. Le prendre pour une
      # puissance annoncerait une alimentation de 32 768 W.
      $rated = if ($capacity -eq 0x8000 -or $capacity -eq 0) {
        New-Unknown -Reason 'NOT_AVAILABLE' `
          -Detail 'puissance nominale non renseignee par le firmware — elle ne se deduit pas de la consommation'
      } else {
        [double]$capacity
      }

      $status = ConvertTo-PowerSupplyStatus -Characteristics $characteristics

      $units += @{
        label = $label
        type = ConvertTo-PowerSupplyType -Characteristics $characteristics
        location = Get-StringOrUnknown -Value $location -Reason 'NOT_AVAILABLE' `
          -Detail 'emplacement non renseigne par le firmware'
        manufacturer = Get-StringOrUnknown -Value $manufacturer -Reason 'NOT_AVAILABLE' `
          -Detail 'fabricant non renseigne par le firmware'
        model = Get-StringOrUnknown -Value $name -Reason 'NOT_AVAILABLE' `
          -Detail 'modele non renseigne par le firmware'
        serialNumber = Get-StringOrUnknown -Value $serial -Reason 'NOT_AVAILABLE' `
          -Detail 'numero de serie non renseigne par le firmware'
        assetTag = Get-StringOrUnknown -Value $asset -Reason 'NOT_AVAILABLE' `
          -Detail 'etiquette d''inventaire non renseignee'
        partNumber = Get-StringOrUnknown -Value $part -Reason 'NOT_AVAILABLE' `
          -Detail 'reference non renseignee par le firmware'
        revision = Get-StringOrUnknown -Value $revision -Reason 'NOT_AVAILABLE' `
          -Detail 'revision non renseignee par le firmware'
        ratedPowerWatts = $rated
        status = Get-StringOrUnknown -Value $status -Reason 'NOT_AVAILABLE' `
          -Detail 'etat non renseigne par le firmware'
        present = [bool]($characteristics -band 0x02)
        hotReplaceable = [bool]($characteristics -band 0x01)
        source = 'SMBIOS'
        confidence = 'MEDIUM'
      }
    }

    # Fin de la structure : zone formatee, puis table de chaines terminee par
    # deux nuls. Une structure sans chaine porte quand meme ces deux octets.
    $offset += $length
    while ($offset + 1 -lt $Data.Length -and -not ($Data[$offset] -eq 0 -and $Data[$offset + 1] -eq 0)) {
      $offset++
    }
    $offset += 2
  }

  return $units
}

function Get-SmbiosPowerSupplyUnits {
  try {
    $table = Get-CimInstance -Namespace 'root\wmi' -ClassName 'MSSmBios_RawSMBiosTables' `
      -ErrorAction Stop | Select-Object -First 1
    if ($null -eq $table -or $null -eq $table.SMBiosData) { return @() }
    return @(ConvertFrom-SmbiosPowerSupplyTable -Data ([byte[]]$table.SMBiosData))
  } catch {
    # Espace de noms absent ou lecture refusee : l'absence sera declaree par une
    # limitation, jamais comblee.
    Write-Debug ('MSSmBios_RawSMBiosTables illisible : ' + $_.Exception.Message)
    return @()
  }
}

<#
.SYNOPSIS
  Ce que `Win32_PowerSupply` rend, quand elle rend quelque chose d'exploitable.

.DESCRIPTION
  La classe est presque toujours vide. Quand elle repond, c'est le plus souvent
  une entree generique du firmware — « System Power Supply », sans fabricant ni
  puissance. Publier cette coquille comme un modele detecte serait exactement le
  faux resultat que la feuille de route interdit : elle n'est donc retenue que
  si elle porte au moins un fabricant ou une puissance.
#>
function Get-CimPowerSupplyUnits {
  $units = @()
  try {
    $devices = @(Get-CimInstance -ClassName 'Win32_PowerSupply' -ErrorAction Stop)
  } catch {
    return $units
  }

  foreach ($device in $devices) {
    $manufacturer = [string]$device.Manufacturer
    $capacity = $device.TotalOutputPower
    if ([string]::IsNullOrWhiteSpace($manufacturer) -and $null -eq $capacity) { continue }

    $label = [string]$device.Name
    if ([string]::IsNullOrWhiteSpace($label)) { $label = 'Alimentation' }

    $units += @{
      label = $label
      type = 'UNKNOWN'
      manufacturer = Get-StringOrUnknown -Value $manufacturer -Reason 'NOT_AVAILABLE' `
        -Detail 'fabricant non publie par Win32_PowerSupply'
      model = Get-StringOrUnknown -Value $device.Description -Reason 'NOT_AVAILABLE' `
        -Detail 'modele non publie par Win32_PowerSupply'
      ratedPowerWatts = Get-NumberOrUnknown -Value $capacity -Reason 'NOT_AVAILABLE' `
        -Detail 'puissance nominale non publiee — elle ne se deduit pas de la consommation'
      status = Get-StringOrUnknown -Value $device.Status -Reason 'NOT_AVAILABLE'
      source = 'CIM_POWER_SUPPLY'
      confidence = 'LOW'
    }
  }

  return $units
}

<#
.SYNOPSIS
  Rail de tension identifie a partir d'un capteur d'un moniteur materiel.

.DESCRIPTION
  Un capteur de tension appartient au bloc **seulement** si le moniteur le
  rattache a un materiel de type PSU. Tous les autres sont ceux de la carte
  mere : ils mesurent ce qui lui parvient, a travers un diviseur resistif, et
  les presenter comme des tensions d'alimentation serait le contresens le plus
  facile a commettre de toute cette section.
#>
function ConvertTo-PowerRail {
  param(
    $Sensor,
    [string]$HardwareType,
    [string]$Source
  )

  $label = [string]$Sensor.Name
  if ([string]::IsNullOrWhiteSpace($label)) { return $null }

  $measuredBy = if ($HardwareType -match 'Psu') { 'POWER_SUPPLY' } else { 'MOTHERBOARD' }

  return @{
    label = $label
    volts = [Math]::Round([double]$Sensor.Value, 3)
    measuredBy = $measuredBy
    source = $Source
  }
}

<#
.SYNOPSIS
  Composant auquel un capteur de puissance se rapporte.

.DESCRIPTION
  Rend une chaine vide quand le materiel porteur ne permet pas de conclure :
  une consommation attribuee au mauvais composant est pire qu'une consommation
  absente, parce qu'elle se lit comme une mesure.
#>
function Get-ComponentPowerKind {
  param(
    [string]$HardwareType,
    [string]$SensorName
  )

  $haystack = ("$HardwareType $SensorName").ToLowerInvariant()
  if ($haystack -match 'gpu') { return 'GPU' }
  if ($haystack -match 'cpu|processor') { return 'CPU' }
  if ($haystack -match 'psu') { return 'SYSTEM' }
  return ''
}

<#
.SYNOPSIS
  Alimentation, rails et consommation vus par un moniteur materiel.

.DESCRIPTION
  LibreHardwareMonitor et OpenHardwareMonitor sont des outils libres, optionnels
  et jamais installes par SysAudit. Leur absence est le cas ordinaire : elle est
  declaree, pas comblee.
#>
function Get-HardwareMonitorPowerSupply {
  $result = @{ units = @(); rails = @(); componentPower = @(); source = '' }

  $providers = @(
    @{ Namespace = 'root/LibreHardwareMonitor'; Tool = 'LibreHardwareMonitor' },
    @{ Namespace = 'root/OpenHardwareMonitor'; Tool = 'OpenHardwareMonitor' }
  )

  foreach ($provider in $providers) {
    $sensors = @()
    try {
      $sensors = @(Get-CimInstance -Namespace $provider.Namespace -ClassName 'Sensor' -ErrorAction Stop)
    } catch {
      continue
    }
    if ($sensors.Count -eq 0) { continue }

    $hardware = Get-HardwareIndex -Namespace $provider.Namespace
    $psuTelemetry = @{}

    foreach ($sensor in $sensors) {
      if ($null -eq $sensor.Value) { continue }
      $parent = [string]$sensor.Parent
      $carrier = if ($hardware.ContainsKey($parent)) { $hardware[$parent] } else { $null }
      $hardwareType = if ($null -ne $carrier) { [string]$carrier.Type } else { '' }
      $carrierName = if ($null -ne $carrier) { [string]$carrier.Name } else { '' }

      switch ([string]$sensor.SensorType) {
        'Voltage' {
          $rail = ConvertTo-PowerRail -Sensor $sensor -HardwareType $hardwareType -Source 'HARDWARE_MONITOR'
          if ($null -ne $rail) { $result.rails += $rail }
        }
        'Power' {
          $kind = Get-ComponentPowerKind -HardwareType $hardwareType -SensorName ([string]$sensor.Name)
          if ($kind -eq '') { break }
          if ($hardwareType -match 'Psu') {
            # Le bloc mesure sa propre consommation : c'est de la telemetrie,
            # pas la consommation d'un composant.
            $psuTelemetry[$carrierName] = [Math]::Round([double]$sensor.Value, 2)
            break
          }
          $entry = @{
            label = [string]$sensor.Name
            component = $kind
            watts = [Math]::Round([double]$sensor.Value, 2)
            source = 'HARDWARE_MONITOR'
          }
          if (-not [string]::IsNullOrWhiteSpace($carrierName)) { $entry.device = $carrierName }
          $result.componentPower += $entry
        }
      }
    }

    foreach ($identifier in $hardware.Keys) {
      $carrier = $hardware[$identifier]
      if ([string]$carrier.Type -notmatch 'Psu') { continue }

      $name = [string]$carrier.Name
      $watts = if ($psuTelemetry.ContainsKey($name)) { $psuTelemetry[$name] } else {
        New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'puissance non publiee par le bloc'
      }

      $result.units += @{
        label = if ([string]::IsNullOrWhiteSpace($name)) { 'Alimentation' } else { $name }
        type = 'DIGITAL_ATX'
        model = Get-StringOrUnknown -Value $name -Reason 'NOT_AVAILABLE' `
          -Detail 'modele non publie par le moniteur materiel'
        ratedPowerWatts = New-Unknown -Reason 'NOT_AVAILABLE' `
          -Detail 'puissance nominale non publiee par le bloc — elle ne se deduit pas de la consommation'
        telemetry = @{
          available = $true
          inputPowerWatts = $watts
          efficiencyPercent = New-Unknown -Reason 'NOT_AVAILABLE' `
            -Detail 'rendement non publie — il ne se calcule pas honnetement depuis deux mesures d''instants differents'
          source = 'HARDWARE_MONITOR'
        }
        source = 'HARDWARE_MONITOR'
        confidence = 'HIGH'
      }
    }

    $result.source = $provider.Tool
    break
  }

  return $result
}

<#
.SYNOPSIS
  Nature retenue pour l'ensemble, quand plusieurs unites coexistent.

.DESCRIPTION
  L'ordre n'est pas arbitraire : un bloc qui parle prime sur un bloc que le
  firmware se contente de decrire.
#>
function Get-OverallPowerSupplyType {
  param([object[]]$Units = @())

  foreach ($candidate in @('SERVER_MANAGED', 'DIGITAL_ATX', 'STANDARD_ATX', 'UPS', 'LAPTOP_ADAPTER', 'USB_PD')) {
    foreach ($unit in $Units) {
      if ([string]$unit.type -eq $candidate) { return $candidate }
    }
  }
  return 'UNKNOWN'
}

<#
.SYNOPSIS
  Une alimentation s'est-elle reellement identifiee ?

.DESCRIPTION
  Connaitre la presence d'un bloc n'apprend rien a personne. La detection exige
  une identite : fabricant, modele, reference ou puissance nominale reellement
  lus. Sans cette distinction, le rendu annoncerait une decouverte la ou il n'y
  a qu'une ligne de firmware vide.
#>
function Test-PowerSupplyDetected {
  param([object[]]$Units = @())

  foreach ($unit in $Units) {
    foreach ($field in @('manufacturer', 'model', 'partNumber', 'ratedPowerWatts')) {
      if (-not $unit.ContainsKey($field)) { continue }
      $value = $unit[$field]
      if ($null -eq $value) { continue }
      if ($value -is [hashtable]) { continue }
      if ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) { continue }
      return $true
    }
  }
  return $false
}

function Get-PowerSupplySection {
  $units = @()
  $sources = @()

  $smbios = @(Get-SmbiosPowerSupplyUnits)
  if ($smbios.Count -gt 0) {
    $units += $smbios
    $sources += 'SMBIOS'
    Add-CollectionProvenance -Path 'power.powerSupply' -Source 'MSSmBios_RawSMBiosTables' -Method 'CIM'
  }

  $cim = @(Get-CimPowerSupplyUnits)
  if ($cim.Count -gt 0) {
    $units += $cim
    $sources += 'CIM_POWER_SUPPLY'
  }

  $monitor = Get-HardwareMonitorPowerSupply
  $units += @($monitor.units)
  $rails = @($monitor.rails)
  $componentPower = @($monitor.componentPower)
  if ($monitor.source -ne '') { $sources += 'HARDWARE_MONITOR' }

  $detected = Test-PowerSupplyDetected -Units $units

  # Ce que la collecte n'a pas pu faire. L'ordre est celui de la lecture : la
  # cause la plus englobante d'abord.
  $limitations = @()
  if (Get-RunningUnderHypervisor) { $limitations += 'VIRTUALIZED' }
  if ($smbios.Count -eq 0) { $limitations += 'SMBIOS_TYPE_39_ABSENT' }
  if (@($monitor.units).Count -eq 0) { $limitations += 'NO_DIGITAL_INTERFACE' }
  if (-not $detected) { $limitations += 'ATX_NOT_SELF_DESCRIBING' }
  if (@($rails | Where-Object { $_.measuredBy -eq 'MOTHERBOARD' }).Count -gt 0) {
    $limitations += 'RAILS_FROM_MOTHERBOARD'
  }

  $section = @{
    detected = $detected
    type = Get-OverallPowerSupplyType -Units $units
    units = @($units)
    rails = @($rails)
    componentPower = @($componentPower)
    sources = @($sources)
    limitations = @($limitations)
  }

  # Sans moniteur materiel, Windows ne rend ni tension ni consommation : le dire
  # et nommer l'outil vaut mieux qu'une section vide dont personne ne sait quoi
  # faire. L'outil est suggere, jamais installe.
  if ($monitor.source -eq '') {
    $section.limitations = @($section.limitations + 'TOOL_MISSING')
    $section.suggestedTool = 'LibreHardwareMonitor'
  }

  return $section
}
