# SysAudit Windows — serie temporelle : observation de la machine dans la duree.
#
# Un audit reste par defaut un **instantane**. Cette collecte est demandee
# explicitement (`-Monitor <secondes>`), parce qu'elle rallonge le scan
# d'autant : personne ne doit attendre une minute sans l'avoir voulu.
#
# Elle reprend la semantique du collecteur Linux, pas ses sources. Deux
# precautions gouvernent le choix de ces sources.
#
# Les **classes de performance brutes** sont preferees aux classes formatees.
# Une classe brute publie un compteur cumule, dont le taux se calcule par
# difference entre deux releves — exactement comme `/proc/diskstats` sous Linux.
# Une classe formatee publie un taux deja calcule par le fournisseur, dont le
# premier appel vaut souvent zero : le scanner rapporterait une machine au repos
# la ou il n'a simplement pas encore de point de comparaison.
#
# Les **noms de classes** sont invariants, jamais les noms de compteurs. Passer
# par `Get-Counter` obligerait a nommer « \Processeur(_Total)\% temps
# processeur » sur un Windows francais et « \Processor(_Total)\% Processor
# Time » sur un Windows anglais. La collecte se ferait donc en silence sur toute
# machine dont la langue n'est pas celle du developpeur.

<#
.SYNOPSIS
  Taux par seconde entre deux compteurs cumules.

.DESCRIPTION
  Fonction pure, separee de la collecte pour etre testable ailleurs que sur
  Windows.

  Rend `$null` plutot qu'un zero dans trois cas : un releve manquant, un
  intervalle nul, et un compteur qui a **recule**. Le troisieme n'est pas
  theorique — un compteur de performance Windows repart de zero au redemarrage
  du fournisseur, et la difference devient negative. Un zero y ferait passer
  une machine chargee pour une machine inerte.
#>
function Get-MonitoringRate {
  param($Before, $After, [double]$Seconds)

  if ($null -eq $Before -or $null -eq $After) { return $null }
  if ($Seconds -le 0) { return $null }

  try {
    $from = [double]$Before
    $to = [double]$After
  } catch {
    return $null
  }

  if ($to -lt $from) { return $null }
  return [int64][Math]::Round(($to - $from) / $Seconds)
}

<#
.SYNOPSIS
  Occupation processeur entre deux releves du compteur d'inactivite.

.DESCRIPTION
  Fonction pure, sur le modele de `monitoring_cpu_usage` cote Linux.

  `PercentIdleTime` de l'instance `_Total` est la somme des ticks d'inactivite
  de **tous** les coeurs : rapporte au seul temps ecoule, il donnerait jusqu'a
  `n` fois 100 % sur une machine a `n` coeurs, et donc une occupation negative.
  Le nombre de coeurs est donc un parametre, pas une constante.

  Le resultat est borne a l'intervalle [0, 100] : un compteur legerement
  desynchronise de son horodatage produit sinon 100,4 %, que le schema refuse.
#>
function Get-MonitoringCpuUsage {
  param($IdleBefore, $IdleAfter, $TimestampBefore, $TimestampAfter, [int]$CoreCount)

  if ($null -eq $IdleBefore -or $null -eq $IdleAfter) { return $null }
  if ($null -eq $TimestampBefore -or $null -eq $TimestampAfter) { return $null }
  if ($CoreCount -le 0) { return $null }

  try {
    $idleDelta = [double]$IdleAfter - [double]$IdleBefore
    $timeDelta = [double]$TimestampAfter - [double]$TimestampBefore
  } catch {
    return $null
  }

  if ($timeDelta -le 0) { return $null }
  if ($idleDelta -lt 0) { return $null }

  $usage = (1 - ($idleDelta / ($timeDelta * $CoreCount))) * 100
  if ($usage -lt 0) { $usage = 0 }
  if ($usage -gt 100) { $usage = 100 }
  return [Math]::Round($usage, 1)
}

<#
.SYNOPSIS
  Temperature du processeur, en degres Celsius, ou `$null`.

.DESCRIPTION
  `MSAcpi_ThermalZoneTemperature` publie des dixiemes de kelvin. La classe
  n'existe que si le constructeur a expose une zone thermique ACPI : sur la
  majorite des machines de bureau, elle est absente ou refuse la lecture sans
  elevation. C'est un `$null`, jamais une valeur de repli.
#>
function Get-MonitoringHardwareSensors {
  $providers = @(
    @{ Namespace = 'root/LibreHardwareMonitor'; Source = 'LibreHardwareMonitor' },
    @{ Namespace = 'root/OpenHardwareMonitor'; Source = 'OpenHardwareMonitor' }
  )

  foreach ($provider in $providers) {
    try {
      $sensors = @(Get-CimInstance -Namespace $provider.Namespace -ClassName 'Sensor' -ErrorAction Stop)
      if ($sensors.Count -gt 0) { return $sensors }
    } catch {
      continue
    }
  }

  return @()
}

function Get-MonitoringCpuTemperatureFromSources {
  param([object[]]$Sensors = @())

  $temperature = Select-MonitoringCpuTemperatureFromSensors -Sensors $Sensors
  if ($null -ne $temperature) { return $temperature }

  try {
    $zones = @(Get-CimInstance -Namespace 'root/wmi' -ClassName 'MSAcpi_ThermalZoneTemperature' -ErrorAction Stop)
  } catch {
    return $null
  }

  foreach ($zone in $zones) {
    if ($null -eq $zone.CurrentTemperature) { continue }
    $celsius = ([double]$zone.CurrentTemperature / 10) - 273.15
    if ($celsius -lt -50 -or $celsius -gt 150) { continue }
    return [Math]::Round($celsius, 1)
  }

  return $null
}

function Get-MonitoringCpuTemperature {
  return Get-MonitoringCpuTemperatureFromSources -Sensors (Get-MonitoringHardwareSensors)
}

function Get-MonitoringCpuVoltage {
  return Select-MonitoringCpuVoltageFromSensors -Sensors (Get-MonitoringHardwareSensors)
}

function Get-MonitoringCpuPower {
  return Select-MonitoringCpuPowerFromSensors -Sensors (Get-MonitoringHardwareSensors)
}

function Get-MonitoringCpuSensorScore {
  param($Sensor)

  if ($null -eq $Sensor) { return -1 }

  $type = [string]$Sensor.SensorType
  if ($type -ne 'Temperature') { return -1 }

  try {
    $value = [double]$Sensor.Value
  } catch {
    return -1
  }

  if ($value -lt -50 -or $value -gt 150) { return -1 }

  $parts = @(
    [string]$Sensor.Name,
    [string]$Sensor.Hardware,
    [string]$Sensor.Identifier,
    [string]$Sensor.Parent
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  if ($parts.Count -eq 0) { return -1 }

  $haystack = ($parts -join ' ').ToLowerInvariant()
  $score = 0

  if ($haystack -match 'cpu package') { $score += 120 }
  if ($haystack -match 'package') { $score += 80 }
  if ($haystack -match '\btctl\b') { $score += 110 }
  if ($haystack -match '\btdie\b') { $score += 110 }
  if ($haystack -match 'cpu') { $score += 70 }
  if ($haystack -match 'core \(max\)') { $score += 45 }
  if ($haystack -match '\bcore\b') { $score += 20 }
  if ($haystack -match 'ccd') { $score += 15 }
  if ($haystack -match 'gpu|nvme|ssd|pch|chipset|motherboard|systin|auxtin|ambient') { $score -= 200 }

  return $score
}

function Select-MonitoringCpuTemperatureFromSensors {
  param([object[]]$Sensors = @())

  $bestSensor = $null
  $bestScore = -1

  foreach ($sensor in $Sensors) {
    $score = Get-MonitoringCpuSensorScore -Sensor $sensor
    if ($score -lt 0) { continue }
    if ($score -le $bestScore) { continue }
    $bestScore = $score
    $bestSensor = $sensor
  }

  if ($null -eq $bestSensor) { return $null }

  try {
    return [Math]::Round([double]$bestSensor.Value, 1)
  } catch {
    return $null
  }
}

function Get-MonitoringCpuVoltageSensorScore {
  param($Sensor)

  if ($null -eq $Sensor) { return -1 }
  if ([string]$Sensor.SensorType -ne 'Voltage') { return -1 }

  try {
    $value = [double]$Sensor.Value
  } catch {
    return -1
  }
  if ($value -lt 0 -or $value -gt 10) { return -1 }

  $parts = @(
    [string]$Sensor.Name,
    [string]$Sensor.Hardware,
    [string]$Sensor.Identifier,
    [string]$Sensor.Parent
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  if ($parts.Count -eq 0) { return -1 }

  $haystack = ($parts -join ' ').ToLowerInvariant()
  $score = 0
  if ($haystack -match '\bvcore\b') { $score += 140 }
  if ($haystack -match 'cpu core') { $score += 120 }
  if ($haystack -match '\bvid\b') { $score += 100 }
  if ($haystack -match '\bcpu\b') { $score += 70 }
  if ($haystack -match 'soc') { $score += 15 }
  if ($haystack -match 'gpu|dram|\+12v|\+5v|\+3\.3v|vin|battery') { $score -= 200 }
  return $score
}

function Select-MonitoringCpuVoltageFromSensors {
  param([object[]]$Sensors = @())

  $bestSensor = $null
  $bestScore = -1
  foreach ($sensor in $Sensors) {
    $score = Get-MonitoringCpuVoltageSensorScore -Sensor $sensor
    if ($score -lt 0) { continue }
    if ($score -le $bestScore) { continue }
    $bestScore = $score
    $bestSensor = $sensor
  }

  if ($null -eq $bestSensor) { return $null }

  try {
    return [Math]::Round([double]$bestSensor.Value, 3)
  } catch {
    return $null
  }
}

function Get-MonitoringCpuPowerSensorScore {
  param($Sensor)

  if ($null -eq $Sensor) { return -1 }
  if ([string]$Sensor.SensorType -ne 'Power') { return -1 }

  try {
    $value = [double]$Sensor.Value
  } catch {
    return -1
  }
  if ($value -lt 0 -or $value -gt 10000) { return -1 }

  $parts = @(
    [string]$Sensor.Name,
    [string]$Sensor.Hardware,
    [string]$Sensor.Identifier,
    [string]$Sensor.Parent
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  if ($parts.Count -eq 0) { return -1 }

  $haystack = ($parts -join ' ').ToLowerInvariant()
  $score = 0
  if ($haystack -match 'cpu package') { $score += 140 }
  if ($haystack -match 'package') { $score += 100 }
  if ($haystack -match '\bppt\b') { $score += 120 }
  if ($haystack -match '\bcpu\b') { $score += 70 }
  if ($haystack -match 'cores') { $score += 30 }
  if ($haystack -match 'gpu|psu|supply|motherboard|dram') { $score -= 200 }
  return $score
}

function Select-MonitoringCpuPowerFromSensors {
  param([object[]]$Sensors = @())

  $bestSensor = $null
  $bestScore = -1
  foreach ($sensor in $Sensors) {
    $score = Get-MonitoringCpuPowerSensorScore -Sensor $sensor
    if ($score -lt 0) { continue }
    if ($score -le $bestScore) { continue }
    $bestScore = $score
    $bestSensor = $sensor
  }

  if ($null -eq $bestSensor) { return $null }

  try {
    return [Math]::Round([double]$bestSensor.Value, 2)
  } catch {
    return $null
  }
}

function Get-MonitoringGpuTemperatureSensorScore {
  param($Sensor)

  if ($null -eq $Sensor) { return -1 }
  if ([string]$Sensor.SensorType -ne 'Temperature') { return -1 }

  try {
    $value = [double]$Sensor.Value
  } catch {
    return -1
  }
  if ($value -lt -50 -or $value -gt 150) { return -1 }

  $parts = @([string]$Sensor.Name, [string]$Sensor.Hardware, [string]$Sensor.Identifier, [string]$Sensor.Parent) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  if ($parts.Count -eq 0) { return -1 }

  $haystack = ($parts -join ' ').ToLowerInvariant()
  $score = 0
  if ($haystack -match 'gpu temperature') { $score += 130 }
  if ($haystack -match 'gpu core') { $score += 120 }
  if ($haystack -match '\bedge\b') { $score += 100 }
  if ($haystack -match '\bgpu\b') { $score += 80 }
  if ($haystack -match 'hot\s?spot|junction') { $score -= 120 }
  if ($haystack -match 'cpu|nvme|ssd|chipset|motherboard|systin|ambient') { $score -= 200 }
  return $score
}

function Select-MonitoringGpuTemperatureFromSensors {
  param([object[]]$Sensors = @())

  $bestSensor = $null
  $bestScore = -1
  foreach ($sensor in $Sensors) {
    $score = Get-MonitoringGpuTemperatureSensorScore -Sensor $sensor
    if ($score -lt 0) { continue }
    if ($score -le $bestScore) { continue }
    $bestScore = $score
    $bestSensor = $sensor
  }

  if ($null -eq $bestSensor) { return $null }

  try {
    return [Math]::Round([double]$bestSensor.Value, 1)
  } catch {
    return $null
  }
}

function Get-MonitoringGpuHotspotSensorScore {
  param($Sensor)

  if ($null -eq $Sensor) { return -1 }
  if ([string]$Sensor.SensorType -ne 'Temperature') { return -1 }

  try {
    $value = [double]$Sensor.Value
  } catch {
    return -1
  }
  if ($value -lt -50 -or $value -gt 150) { return -1 }

  $parts = @([string]$Sensor.Name, [string]$Sensor.Hardware, [string]$Sensor.Identifier, [string]$Sensor.Parent) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  if ($parts.Count -eq 0) { return -1 }

  $haystack = ($parts -join ' ').ToLowerInvariant()
  $score = 0
  if ($haystack -match 'hot\s?spot') { $score += 150 }
  if ($haystack -match 'junction') { $score += 140 }
  if ($haystack -match '\bgpu\b') { $score += 70 }
  if ($haystack -match 'cpu|nvme|ssd|chipset|motherboard|systin|ambient') { $score -= 200 }
  return $score
}

function Select-MonitoringGpuHotspotFromSensors {
  param([object[]]$Sensors = @())

  $bestSensor = $null
  $bestScore = -1
  foreach ($sensor in $Sensors) {
    $score = Get-MonitoringGpuHotspotSensorScore -Sensor $sensor
    if ($score -lt 0) { continue }
    if ($score -le $bestScore) { continue }
    $bestScore = $score
    $bestSensor = $sensor
  }

  if ($null -eq $bestSensor) { return $null }

  try {
    return [Math]::Round([double]$bestSensor.Value, 1)
  } catch {
    return $null
  }
}

function Get-MonitoringGpuCoreClockSensorScore {
  param($Sensor)

  if ($null -eq $Sensor) { return -1 }
  if ([string]$Sensor.SensorType -ne 'Clock') { return -1 }

  try {
    $value = [double]$Sensor.Value
  } catch {
    return -1
  }
  if ($value -lt 0 -or $value -gt 100000) { return -1 }

  $parts = @([string]$Sensor.Name, [string]$Sensor.Hardware, [string]$Sensor.Identifier, [string]$Sensor.Parent) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  if ($parts.Count -eq 0) { return -1 }

  $haystack = ($parts -join ' ').ToLowerInvariant()
  $score = 0
  if ($haystack -match 'graphics clock') { $score += 150 }
  if ($haystack -match 'gpu core') { $score += 140 }
  if ($haystack -match 'gpu clock') { $score += 130 }
  if ($haystack -match '\bgpu\b') { $score += 70 }
  if ($haystack -match 'memory') { $score -= 120 }
  if ($haystack -match 'cpu|ram|dram') { $score -= 200 }
  return $score
}

function Select-MonitoringGpuCoreClockFromSensors {
  param([object[]]$Sensors = @())

  $bestSensor = $null
  $bestScore = -1
  foreach ($sensor in $Sensors) {
    $score = Get-MonitoringGpuCoreClockSensorScore -Sensor $sensor
    if ($score -lt 0) { continue }
    if ($score -le $bestScore) { continue }
    $bestScore = $score
    $bestSensor = $sensor
  }

  if ($null -eq $bestSensor) { return $null }

  try {
    return [int][Math]::Round([double]$bestSensor.Value)
  } catch {
    return $null
  }
}

function Get-MonitoringGpuMemoryClockSensorScore {
  param($Sensor)

  if ($null -eq $Sensor) { return -1 }
  if ([string]$Sensor.SensorType -ne 'Clock') { return -1 }

  try {
    $value = [double]$Sensor.Value
  } catch {
    return -1
  }
  if ($value -lt 0 -or $value -gt 100000) { return -1 }

  $parts = @([string]$Sensor.Name, [string]$Sensor.Hardware, [string]$Sensor.Identifier, [string]$Sensor.Parent) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  if ($parts.Count -eq 0) { return -1 }

  $haystack = ($parts -join ' ').ToLowerInvariant()
  $score = 0
  if ($haystack -match 'memory clock') { $score += 150 }
  if ($haystack -match 'mem clock') { $score += 140 }
  if ($haystack -match 'gpu memory') { $score += 130 }
  if ($haystack -match '\bgpu\b') { $score += 60 }
  if ($haystack -match 'cpu|ram|dram') { $score -= 200 }
  return $score
}

function Select-MonitoringGpuMemoryClockFromSensors {
  param([object[]]$Sensors = @())

  $bestSensor = $null
  $bestScore = -1
  foreach ($sensor in $Sensors) {
    $score = Get-MonitoringGpuMemoryClockSensorScore -Sensor $sensor
    if ($score -lt 0) { continue }
    if ($score -le $bestScore) { continue }
    $bestScore = $score
    $bestSensor = $sensor
  }

  if ($null -eq $bestSensor) { return $null }

  try {
    return [int][Math]::Round([double]$bestSensor.Value)
  } catch {
    return $null
  }
}

function Get-MonitoringGpuVoltageSensorScore {
  param($Sensor)

  if ($null -eq $Sensor) { return -1 }
  if ([string]$Sensor.SensorType -ne 'Voltage') { return -1 }

  try {
    $value = [double]$Sensor.Value
  } catch {
    return -1
  }
  if ($value -lt 0 -or $value -gt 10) { return -1 }

  $parts = @([string]$Sensor.Name, [string]$Sensor.Hardware, [string]$Sensor.Identifier, [string]$Sensor.Parent) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  if ($parts.Count -eq 0) { return -1 }

  $haystack = ($parts -join ' ').ToLowerInvariant()
  $score = 0
  if ($haystack -match 'gpu core') { $score += 140 }
  if ($haystack -match 'gpu voltage') { $score += 130 }
  if ($haystack -match '\bvddc\b') { $score += 150 }
  if ($haystack -match '\bgpu\b') { $score += 70 }
  if ($haystack -match 'memory|mvdd|fbvdd') { $score -= 80 }
  if ($haystack -match 'cpu|dram|\+12v|\+5v|\+3\.3v|battery') { $score -= 200 }
  return $score
}

function Select-MonitoringGpuVoltageFromSensors {
  param([object[]]$Sensors = @())

  $bestSensor = $null
  $bestScore = -1
  foreach ($sensor in $Sensors) {
    $score = Get-MonitoringGpuVoltageSensorScore -Sensor $sensor
    if ($score -lt 0) { continue }
    if ($score -le $bestScore) { continue }
    $bestScore = $score
    $bestSensor = $sensor
  }

  if ($null -eq $bestSensor) { return $null }

  try {
    return [Math]::Round([double]$bestSensor.Value, 3)
  } catch {
    return $null
  }
}

function Get-MonitoringGpuPowerSensorScore {
  param($Sensor)

  if ($null -eq $Sensor) { return -1 }
  if ([string]$Sensor.SensorType -ne 'Power') { return -1 }

  try {
    $value = [double]$Sensor.Value
  } catch {
    return -1
  }
  if ($value -lt 0 -or $value -gt 10000) { return -1 }

  $parts = @([string]$Sensor.Name, [string]$Sensor.Hardware, [string]$Sensor.Identifier, [string]$Sensor.Parent) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  if ($parts.Count -eq 0) { return -1 }

  $haystack = ($parts -join ' ').ToLowerInvariant()
  $score = 0
  if ($haystack -match 'board power draw') { $score += 170 }
  if ($haystack -match 'total board') { $score += 160 }
  if ($haystack -match 'gpu power') { $score += 150 }
  if ($haystack -match '\bgpu\b') { $score += 70 }
  if ($haystack -match 'cpu|psu|supply|motherboard|dram') { $score -= 200 }
  return $score
}

function Select-MonitoringGpuPowerFromSensors {
  param([object[]]$Sensors = @())

  $bestSensor = $null
  $bestScore = -1
  foreach ($sensor in $Sensors) {
    $score = Get-MonitoringGpuPowerSensorScore -Sensor $sensor
    if ($score -lt 0) { continue }
    if ($score -le $bestScore) { continue }
    $bestScore = $score
    $bestSensor = $sensor
  }

  if ($null -eq $bestSensor) { return $null }

  try {
    return [Math]::Round([double]$bestSensor.Value, 2)
  } catch {
    return $null
  }
}

<#
.SYNOPSIS
  Vitesse de rotation d'un ventilateur, en tours par minute, ou `$null`.

.DESCRIPTION
  LibreHardwareMonitor expose les ventilateurs en `SensorType = 'Fan'`, sans
  convention de nommage : selon la carte mere, `Fan #1` designe le ventilateur
  processeur, celui du boitier, ou une entree morte. Le rattachement a un role
  se fait donc par notation, comme pour les autres capteurs de ce fichier — et
  **rien n'est attribue par defaut** : un ventilateur qu'aucun indice ne
  rattache reste hors du releve plutot que compte pour celui du processeur.

  Zero est conserve : un ventilateur a l'arret sur une machine chaude est
  precisement ce qu'on cherche a voir.
#>
function Get-MonitoringFanSensorScore {
  param($Sensor, [string]$Role = 'cpu')

  if ($null -eq $Sensor) { return -1 }
  if ([string]$Sensor.SensorType -ne 'Fan') { return -1 }

  try {
    $value = [double]$Sensor.Value
  } catch {
    return -1
  }
  # Au-dela de 30 000 tr/min, la lecture decrit un capteur qui deraille : aucun
  # ventilateur d'ordinateur n'atteint ce regime.
  if ($value -lt 0 -or $value -gt 30000) { return -1 }

  $parts = @([string]$Sensor.Name, [string]$Sensor.Hardware, [string]$Sensor.Identifier, [string]$Sensor.Parent) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  if ($parts.Count -eq 0) { return -1 }

  $haystack = ($parts -join ' ').ToLowerInvariant()
  $score = 0
  switch ($Role) {
    'cpu' {
      if ($haystack -match 'cpu fan|processor fan') { $score += 160 }
      if ($haystack -match '\bcpu\b') { $score += 80 }
      if ($haystack -match '\bgpu\b|graphics|chassis|system fan|pump') { $score -= 200 }
    }
    'gpu' {
      if ($haystack -match 'gpu fan|graphics fan') { $score += 160 }
      if ($haystack -match '\bgpu\b|nvidia|radeon|geforce') { $score += 80 }
      if ($haystack -match '\bcpu\b|chassis|system fan') { $score -= 200 }
    }
    'chassis' {
      if ($haystack -match 'chassis|system fan|case fan') { $score += 150 }
      if ($haystack -match '\bcpu\b|\bgpu\b|graphics') { $score -= 200 }
    }
  }
  return $score
}

function Select-MonitoringFanFromSensors {
  param([object[]]$Sensors = @(), [string]$Role = 'cpu')

  $bestSensor = $null
  $bestScore = 0
  foreach ($sensor in $Sensors) {
    $score = Get-MonitoringFanSensorScore -Sensor $sensor -Role $Role
    # Un score nul signale un ventilateur qu'aucun indice ne rattache a ce
    # role : il est ecarte, jamais retenu par defaut.
    if ($score -le $bestScore) { continue }
    $bestScore = $score
    $bestSensor = $sensor
  }

  if ($null -eq $bestSensor) { return $null }

  try {
    return [int][Math]::Round([double]$bestSensor.Value, 0)
  } catch {
    return $null
  }
}

<#
.SYNOPSIS
  Occupation du processeur graphique, en pourcentage, ou `$null`.
#>
function Select-MonitoringGpuUsageFromSensors {
  param([object[]]$Sensors = @())

  foreach ($sensor in $Sensors) {
    if ([string]$sensor.SensorType -ne 'Load') { continue }
    $parts = @([string]$sensor.Name, [string]$sensor.Hardware, [string]$sensor.Identifier) |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $haystack = ($parts -join ' ').ToLowerInvariant()
    # `gpu core` est le nom que LibreHardwareMonitor donne a la charge de la
    # puce. « gpu memory » est une autre grandeur, et les confondre ferait lire
    # une carte saturee la ou seule sa memoire l'est.
    if ($haystack -notmatch 'gpu core') { continue }
    try {
      $value = [double]$sensor.Value
    } catch {
      continue
    }
    if ($value -lt 0 -or $value -gt 100) { continue }
    return [Math]::Round($value, 1)
  }

  return $null
}

<#
.SYNOPSIS
  Memoire graphique occupee, en octets, ou `$null`.

.DESCRIPTION
  Le capteur publie des mebioctets ; le schema attend des octets. La conversion
  se fait ici, une fois, plutot que dans chaque lecteur du rapport.
#>
function Select-MonitoringGpuVramFromSensors {
  param([object[]]$Sensors = @())

  foreach ($sensor in $Sensors) {
    if ([string]$sensor.SensorType -ne 'SmallData') { continue }
    $parts = @([string]$sensor.Name, [string]$sensor.Hardware, [string]$sensor.Identifier) |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $haystack = ($parts -join ' ').ToLowerInvariant()
    if ($haystack -notmatch 'gpu memory used|memory used') { continue }
    if ($haystack -match 'free|total') { continue }
    try {
      $value = [double]$sensor.Value
    } catch {
      continue
    }
    if ($value -lt 0 -or $value -gt 262144) { continue }
    return [int64]([Math]::Round($value * 1048576, 0))
  }

  return $null
}

<#
.SYNOPSIS
  Frequence effective du processeur, en megahertz, ou `$null`.

.DESCRIPTION
  `Win32_Processor.CurrentClockSpeed` est la frequence **instantanee** rapportee
  par le firmware. Le nom de classe est invariant, comme partout ailleurs dans
  ce fichier ; passer par `Get-Counter` obligerait a nommer un compteur traduit.

  Sur une machine a plusieurs sockets, la moyenne est prise : rapporter la
  premiere ferait passer un serveur bi-socket pour un mono-socket. Une machine
  qui ne publie aucune frequence rend `$null`, jamais `MaxClockSpeed` — la
  frequence maximale n'est pas la frequence courante, et les confondre ferait
  lire une machine bridee comme une machine au maximum.
#>
function Get-MonitoringCpuFrequency {
  try {
    $processors = @(Get-CimInstance -ClassName 'Win32_Processor' -ErrorAction Stop)
  } catch {
    return $null
  }

  $sum = 0
  $count = 0
  foreach ($processor in $processors) {
    if ($null -eq $processor.CurrentClockSpeed) { continue }
    $sum += [double]$processor.CurrentClockSpeed
    $count += 1
  }

  if ($count -eq 0) { return $null }
  return [int][Math]::Round($sum / $count)
}

<#
.SYNOPSIS
  Statistiques d'une grandeur echantillonnee : minimum, maximum, moyenne.

.DESCRIPTION
  Fonction pure. Elle prend les valeurs **reellement mesurees** — les marqueurs
  d'absence sont ecartes en amont — et rend l'objet `aggregatedMetric` du schema.

  `sampleCount` n'est pas un `maybe` : c'est un denombrement, et zero echantillon
  est un fait. C'est precisement ce qui permet de lire une moyenne absente sans
  conclure « moyenne nulle » : il n'y a simplement rien eu a moyenner.

  Ces statistiques sont **redondantes avec les echantillons, et c'est voulu** :
  une observation d'une heure au pas de la seconde depasse la borne du tableau,
  et le resume doit survivre a sa troncature.
#>
function New-MonitoringAggregate {
  param(
    [double[]]$Values = @(),
    [string]$Unit = '',
    [int]$IntervalMs = 0,
    [string]$Source = ''
  )

  $unknown = { param($detail) New-Unknown -Reason 'NOT_AVAILABLE' -Detail $detail }

  if ($Values.Count -eq 0) {
    return @{
      current = & $unknown 'aucun echantillon exploitable'
      minimum = & $unknown 'aucun echantillon exploitable'
      maximum = & $unknown 'aucun echantillon exploitable'
      average = & $unknown 'aucun echantillon exploitable'
      unit = if ([string]::IsNullOrWhiteSpace($Unit)) { & $unknown 'unite non renseignee' } else { $Unit }
      sampleCount = 0
      sampleIntervalMs = if ($IntervalMs -gt 0) { $IntervalMs } else { & $unknown 'intervalle inconnu' }
      sampleDurationMs = & $unknown 'aucun echantillon exploitable'
      source = if ([string]::IsNullOrWhiteSpace($Source)) { & $unknown 'source non renseignee' } else { $Source }
    }
  }

  $minimum = $Values[0]
  $maximum = $Values[0]
  $sum = 0
  foreach ($value in $Values) {
    if ($value -lt $minimum) { $minimum = $value }
    if ($value -gt $maximum) { $maximum = $value }
    $sum += $value
  }

  return @{
    # `current` reste distinct de `maximum` : sur un instantane pris en fin de
    # fenetre, les confondre ferait passer un pic transitoire pour l'etat
    # courant de la machine.
    current = [Math]::Round($Values[$Values.Count - 1], 2)
    minimum = [Math]::Round($minimum, 2)
    maximum = [Math]::Round($maximum, 2)
    average = [Math]::Round($sum / $Values.Count, 2)
    unit = if ([string]::IsNullOrWhiteSpace($Unit)) { & $unknown 'unite non renseignee' } else { $Unit }
    sampleCount = $Values.Count
    sampleIntervalMs = if ($IntervalMs -gt 0) { $IntervalMs } else { & $unknown 'intervalle inconnu' }
    sampleDurationMs = if ($IntervalMs -gt 0) { $IntervalMs * $Values.Count } else { & $unknown 'intervalle inconnu' }
    source = if ([string]::IsNullOrWhiteSpace($Source)) { & $unknown 'source non renseignee' } else { $Source }
  }
}

<#
.SYNOPSIS
  Valeurs reellement mesurees d'un champ, a travers une serie d'echantillons.

.DESCRIPTION
  Fonction pure. Ecarte les marqueurs d'absence : les moyenner reviendrait a
  compter « je n'ai pas pu lire » comme un zero, ce qui est exactement la faute
  que ce produit interdit.
#>
# Nom au singulier, comme le veut la convention PowerShell : un verbe rend une
# collection sans que son nom ait a le dire — `Get-ChildItem` en rend plusieurs.
function Select-MonitoringValue {
  param([object[]]$Samples = @(), [string]$Field)

  $values = @()
  foreach ($sample in $Samples) {
    $value = $sample[$Field]
    if ($null -eq $value) { continue }
    # Un marqueur porte `unknown = $true`. Le distinguer d'un nombre est tout
    # l'objet de cette fonction.
    if ($value -is [hashtable] -or $value -is [System.Collections.IDictionary]) { continue }
    try {
      $values += [double]$value
    } catch {
      continue
    }
  }
  return $values
}

<#
.SYNOPSIS
  Nombre de processeurs logiques vus par les compteurs de performance.

.DESCRIPTION
  Compte les instances de `Win32_PerfRawData_PerfOS_Processor` autres que les
  totaux. Au-dela de 64 processeurs logiques, Windows publie un total par groupe
  (`0,_Total`) en plus du total global : tout nom contenant `_Total` est donc
  ecarte, pas seulement le nom exact.
#>
function Get-MonitoringCoreCount {
  param([object[]]$Instances)

  $count = 0
  foreach ($instance in $Instances) {
    $name = [string]$instance.Name
    if ($name -like '*_Total*') { continue }
    $count += 1
  }
  return $count
}

<#
.SYNOPSIS
  Releve brut des compteurs, cumules et instantanes.

.DESCRIPTION
  Rend une table dont chaque entree vaut `$null` quand sa source n'a pas
  repondu. Aucune valeur n'est inventee : c'est l'appelant qui traduira un
  `$null` en marqueur, avec sa raison.

  Memoire et fichier d'echange sont **instantanes** — ils se lisent tels quels.
  Disque et reseau sont **cumules** — ils n'ont de sens que compares au releve
  precedent.
#>
function Get-MonitoringRawSample {
  $sample = @{
    cpuIdle = $null
    cpuTimestamp = $null
    coreCount = 0
    memoryUsed = $null
    swapUsed = $null
    diskRead = $null
    diskWrite = $null
    networkRx = $null
    networkTx = $null
    cpuFrequency = $null
  }

  $sample.cpuFrequency = Get-MonitoringCpuFrequency

  try {
    $processors = @(Get-CimInstance -ClassName 'Win32_PerfRawData_PerfOS_Processor' -ErrorAction Stop)
    $total = $processors | Where-Object { [string]$_.Name -eq '_Total' } | Select-Object -First 1
    if ($null -ne $total) {
      $sample.cpuIdle = $total.PercentIdleTime
      $sample.cpuTimestamp = $total.Timestamp_Sys100NS
    }
    $sample.coreCount = Get-MonitoringCoreCount -Instances $processors
  } catch {
    Add-CollectionIssueOnce -Section 'monitoring.cpu' -Severity 'warning' `
      -Message ('Compteurs processeur illisibles : ' + $_.Exception.Message) `
      -Source 'Win32_PerfRawData_PerfOS_Processor' -Reason 'NOT_AVAILABLE'
  }

  try {
    $os = Get-CimInstance -ClassName 'Win32_OperatingSystem' -ErrorAction Stop
    if ($null -ne $os.TotalVisibleMemorySize -and $null -ne $os.FreePhysicalMemory) {
      $used = ([double]$os.TotalVisibleMemorySize - [double]$os.FreePhysicalMemory) * 1024
      if ($used -ge 0) { $sample.memoryUsed = [int64]$used }
    }
  } catch {
    Add-CollectionIssueOnce -Section 'monitoring.memory' -Severity 'warning' `
      -Message ('Occupation memoire illisible : ' + $_.Exception.Message) `
      -Source 'Win32_OperatingSystem' -Reason 'NOT_AVAILABLE'
  }

  # Un fichier d'echange occupe se lit en mega-octets. L'absence d'instance est
  # une information differente d'une requete en echec : sans fichier d'echange
  # configure, l'occupation est reellement nulle. La requete en echec, elle,
  # laisse `$null`.
  try {
    $pageFiles = @(Get-CimInstance -ClassName 'Win32_PageFileUsage' -ErrorAction Stop)
    $swapUsed = 0
    foreach ($pageFile in $pageFiles) {
      if ($null -eq $pageFile.CurrentUsage) { continue }
      $swapUsed += [int64]$pageFile.CurrentUsage * 1024 * 1024
    }
    $sample.swapUsed = [int64]$swapUsed
  } catch {
    Add-CollectionIssueOnce -Section 'monitoring.swap' -Severity 'warning' `
      -Message ('Occupation du fichier d''echange illisible : ' + $_.Exception.Message) `
      -Source 'Win32_PageFileUsage' -Reason 'NOT_AVAILABLE'
  }

  try {
    $disks = @(Get-CimInstance -ClassName 'Win32_PerfRawData_PerfDisk_PhysicalDisk' -ErrorAction Stop)
    $diskTotal = $disks | Where-Object { [string]$_.Name -eq '_Total' } | Select-Object -First 1
    if ($null -ne $diskTotal) {
      $sample.diskRead = $diskTotal.DiskReadBytesPersec
      $sample.diskWrite = $diskTotal.DiskWriteBytesPersec
    }
  } catch {
    Add-CollectionIssueOnce -Section 'monitoring.disk' -Severity 'warning' `
      -Message ('Compteurs disque illisibles : ' + $_.Exception.Message) `
      -Source 'Win32_PerfRawData_PerfDisk_PhysicalDisk' -Reason 'NOT_AVAILABLE'
  }

  # `Win32_PerfRawData_Tcpip_NetworkInterface` ne publie aucune instance de
  # bouclage, contrairement a `/sys/class/net` : il n'y a donc rien a exclure
  # ici, la ou le collecteur Linux doit ecarter `lo`.
  try {
    $interfaces = @(Get-CimInstance -ClassName 'Win32_PerfRawData_Tcpip_NetworkInterface' -ErrorAction Stop)
    if ($interfaces.Count -gt 0) {
      $rx = 0
      $tx = 0
      foreach ($interface in $interfaces) {
        if ($null -ne $interface.BytesReceivedPersec) { $rx += [int64]$interface.BytesReceivedPersec }
        if ($null -ne $interface.BytesSentPersec) { $tx += [int64]$interface.BytesSentPersec }
      }
      $sample.networkRx = [int64]$rx
      $sample.networkTx = [int64]$tx
    }
  } catch {
    Add-CollectionIssueOnce -Section 'monitoring.network' -Severity 'warning' `
      -Message ('Compteurs reseau illisibles : ' + $_.Exception.Message) `
      -Source 'Win32_PerfRawData_Tcpip_NetworkInterface' -Reason 'NOT_AVAILABLE'
  }

  return $sample
}

<#
.SYNOPSIS
  Construit un echantillon du schema a partir de deux releves bruts.

.DESCRIPTION
  Fonction pure : elle ne lit rien, elle compare. C'est elle qui traduit un
  `$null` en marqueur portant sa raison, et elle seule.
#>
function New-MonitoringSample {
  param(
    [Parameter(Mandatory = $true)]$Previous,
    [Parameter(Mandatory = $true)]$Current,
    [Parameter(Mandatory = $true)][double]$IntervalSeconds,
    [string]$At = '',
    $TemperatureCelsius = $null,
    $CpuVoltageVolts = $null,
    $CpuPackagePowerWatts = $null,
    $GpuTemperatureCelsius = $null,
    $GpuHotspotCelsius = $null,
    $GpuCoreClockMhz = $null,
    $GpuMemoryClockMhz = $null,
    $GpuVoltageVolts = $null,
    $GpuBoardPowerWatts = $null,
    $GpuUsagePercent = $null,
    $GpuVramUsedBytes = $null,
    $CpuFanRpm = $null,
    $GpuFanRpm = $null,
    $ChassisFanRpm = $null
  )

  $cpuUsage = Get-MonitoringCpuUsage -IdleBefore $Previous.cpuIdle -IdleAfter $Current.cpuIdle `
    -TimestampBefore $Previous.cpuTimestamp -TimestampAfter $Current.cpuTimestamp `
    -CoreCount $Current.coreCount

  $diskRead = Get-MonitoringRate -Before $Previous.diskRead -After $Current.diskRead -Seconds $IntervalSeconds
  $diskWrite = Get-MonitoringRate -Before $Previous.diskWrite -After $Current.diskWrite -Seconds $IntervalSeconds
  $networkRx = Get-MonitoringRate -Before $Previous.networkRx -After $Current.networkRx -Seconds $IntervalSeconds
  $networkTx = Get-MonitoringRate -Before $Previous.networkTx -After $Current.networkTx -Seconds $IntervalSeconds

  return @{
    at = if ([string]::IsNullOrWhiteSpace($At)) { Get-IsoNow } else { $At }
    cpuUsagePercent = if ($null -ne $cpuUsage) { $cpuUsage } else { New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'compteur d''inactivite processeur illisible' }
    cpuTemperatureCelsius = if ($null -ne $TemperatureCelsius) { $TemperatureCelsius } else { New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'aucun capteur CPU exploitable (LibreHardwareMonitor/OpenHardwareMonitor/ACPI)' }
    cpuCoreVoltageVolts = if ($null -ne $CpuVoltageVolts) { $CpuVoltageVolts } else { New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'aucun capteur de tension CPU exploitable' }
    cpuPackagePowerWatts = if ($null -ne $CpuPackagePowerWatts) { $CpuPackagePowerWatts } else { New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'aucun capteur de puissance CPU exploitable' }
    gpuTemperatureCelsius = if ($null -ne $GpuTemperatureCelsius) { $GpuTemperatureCelsius } else { New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'aucun capteur GPU exploitable' }
    gpuHotspotCelsius = if ($null -ne $GpuHotspotCelsius) { $GpuHotspotCelsius } else { New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'aucun capteur hotspot GPU exploitable' }
    gpuCoreClockMhz = if ($null -ne $GpuCoreClockMhz) { $GpuCoreClockMhz } else { New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'aucun capteur de frequence GPU exploitable' }
    gpuMemoryClockMhz = if ($null -ne $GpuMemoryClockMhz) { $GpuMemoryClockMhz } else { New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'aucun capteur de frequence memoire GPU exploitable' }
    gpuCoreVoltageVolts = if ($null -ne $GpuVoltageVolts) { $GpuVoltageVolts } else { New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'aucun capteur de tension GPU exploitable' }
    gpuBoardPowerWatts = if ($null -ne $GpuBoardPowerWatts) { $GpuBoardPowerWatts } else { New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'aucun capteur de puissance GPU exploitable' }
    memoryUsedBytes = if ($null -ne $Current.memoryUsed) { [int64]$Current.memoryUsed } else { New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'Win32_OperatingSystem illisible' }
    swapUsedBytes = if ($null -ne $Current.swapUsed) { [int64]$Current.swapUsed } else { New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'Win32_PageFileUsage illisible' }
    diskReadBytesPerSecond = if ($null -ne $diskRead) { $diskRead } else { New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'compteurs disque illisibles' }
    diskWriteBytesPerSecond = if ($null -ne $diskWrite) { $diskWrite } else { New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'compteurs disque illisibles' }
    networkRxBytesPerSecond = if ($null -ne $networkRx) { $networkRx } else { New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'compteurs reseau illisibles' }
    networkTxBytesPerSecond = if ($null -ne $networkTx) { $networkTx } else { New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'compteurs reseau illisibles' }
    cpuFrequencyMhz = if ($null -ne $Current.cpuFrequency) { $Current.cpuFrequency } else { New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'Win32_Processor.CurrentClockSpeed illisible' }
    # Le bridage n'est **jamais** deduit d'une frequence basse : un processeur au
    # repos tourne bas sans etre bride, et confondre les deux inventerait une
    # panne. Windows ne publie aucun compteur de bridage thermique comparable a
    # `thermal_throttle` sous Linux : le champ reste inconnu, avec ce motif.
    cpuThrottled = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'Windows ne publie aucun compteur de bridage thermique ; le deduire d''une frequence basse inventerait une panne'
    gpuUsagePercent = if ($null -ne $GpuUsagePercent) { $GpuUsagePercent } else { New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'aucun capteur de charge GPU exploitable' }
    gpuVramUsedBytes = if ($null -ne $GpuVramUsedBytes) { $GpuVramUsedBytes } else { New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'aucun capteur de memoire GPU exploitable' }
    cpuFanRpm = if ($null -ne $CpuFanRpm) { $CpuFanRpm } else { New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'aucun capteur de rotation rattache au ventilateur processeur' }
    gpuFanRpm = if ($null -ne $GpuFanRpm) { $GpuFanRpm } else { New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'aucun capteur de rotation rattache au ventilateur graphique' }
    chassisFanRpm = if ($null -ne $ChassisFanRpm) { $ChassisFanRpm } else { New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'aucun capteur de rotation rattache au ventilateur de boitier' }
  }
}

<#
.SYNOPSIS
  Observe la machine pendant la duree demandee.

.DESCRIPTION
  Rend la section `monitoring` du rapport, ou `$null` si la duree est nulle.

  Le premier releve ne produit **aucun** echantillon : sans point precedent, il
  n'y a pas de difference, et un zero ferait passer une machine chargee pour une
  machine au repos. C'est la regle ecrite dans le schema, et le collecteur Linux
  l'applique de la meme facon.
#>
function Get-MonitoringSection {
  param(
    [int]$DurationSeconds = 0,
    [int]$IntervalSeconds = 1
  )

  if ($DurationSeconds -le 0) { return $null }
  if ($IntervalSeconds -le 0) { $IntervalSeconds = 1 }

  $startedAt = Get-IsoNow
  $previous = Get-MonitoringRawSample

  $samples = @()
  $elapsed = 0
  while ($elapsed -lt $DurationSeconds) {
    Start-Sleep -Seconds $IntervalSeconds
    $elapsed += $IntervalSeconds

    $current = Get-MonitoringRawSample
    $sensors = @(Get-MonitoringHardwareSensors)
    $cpuTemperature = Get-MonitoringCpuTemperatureFromSources -Sensors $sensors
    $cpuVoltage = Select-MonitoringCpuVoltageFromSensors -Sensors $sensors
    $cpuPower = Select-MonitoringCpuPowerFromSensors -Sensors $sensors
    $gpuTemperature = Select-MonitoringGpuTemperatureFromSensors -Sensors $sensors
    $gpuHotspot = Select-MonitoringGpuHotspotFromSensors -Sensors $sensors
    $gpuCoreClock = Select-MonitoringGpuCoreClockFromSensors -Sensors $sensors
    $gpuMemoryClock = Select-MonitoringGpuMemoryClockFromSensors -Sensors $sensors
    $gpuVoltage = Select-MonitoringGpuVoltageFromSensors -Sensors $sensors
    $gpuPower = Select-MonitoringGpuPowerFromSensors -Sensors $sensors
    $gpuUsage = Select-MonitoringGpuUsageFromSensors -Sensors $sensors
    $gpuVram = Select-MonitoringGpuVramFromSensors -Sensors $sensors
    $cpuFan = Select-MonitoringFanFromSensors -Sensors $sensors -Role 'cpu'
    $gpuFan = Select-MonitoringFanFromSensors -Sensors $sensors -Role 'gpu'
    $chassisFan = Select-MonitoringFanFromSensors -Sensors $sensors -Role 'chassis'
    $samples += New-MonitoringSample -Previous $previous -Current $current `
      -IntervalSeconds $IntervalSeconds -TemperatureCelsius $cpuTemperature `
      -CpuVoltageVolts $cpuVoltage -CpuPackagePowerWatts $cpuPower `
      -GpuTemperatureCelsius $gpuTemperature -GpuHotspotCelsius $gpuHotspot `
      -GpuCoreClockMhz $gpuCoreClock -GpuMemoryClockMhz $gpuMemoryClock `
      -GpuVoltageVolts $gpuVoltage -GpuBoardPowerWatts $gpuPower `
      -GpuUsagePercent $gpuUsage -GpuVramUsedBytes $gpuVram `
      -CpuFanRpm $cpuFan -GpuFanRpm $gpuFan -ChassisFanRpm $chassisFan

    $previous = $current
  }

  Add-CollectionProvenance -Path 'monitoring.samples' -Source 'Win32_PerfRawData_*' `
    -Method 'CIM' -Precision ([string]$IntervalSeconds + ' s')

  $intervalMs = $IntervalSeconds * 1000
  $aggregates = @{}
  # Les grandeurs resumees, avec leur unite **litterale** : elle n'est jamais
  # devinee du nom du champ.
  $metrics = @(
    @{ field = 'cpuUsagePercent'; unit = '%'; source = 'Win32_PerfRawData_PerfOS_Processor' },
    @{ field = 'cpuTemperatureCelsius'; unit = 'degC'; source = 'LibreHardwareMonitor|OpenHardwareMonitor|MSAcpi_ThermalZoneTemperature' },
    @{ field = 'cpuCoreVoltageVolts'; unit = 'V'; source = 'LibreHardwareMonitor|OpenHardwareMonitor' },
    @{ field = 'cpuPackagePowerWatts'; unit = 'W'; source = 'LibreHardwareMonitor|OpenHardwareMonitor' },
    @{ field = 'gpuTemperatureCelsius'; unit = 'degC'; source = 'LibreHardwareMonitor|OpenHardwareMonitor' },
    @{ field = 'gpuHotspotCelsius'; unit = 'degC'; source = 'LibreHardwareMonitor|OpenHardwareMonitor' },
    @{ field = 'gpuCoreClockMhz'; unit = 'MHz'; source = 'LibreHardwareMonitor|OpenHardwareMonitor' },
    @{ field = 'gpuMemoryClockMhz'; unit = 'MHz'; source = 'LibreHardwareMonitor|OpenHardwareMonitor' },
    @{ field = 'gpuCoreVoltageVolts'; unit = 'V'; source = 'LibreHardwareMonitor|OpenHardwareMonitor' },
    @{ field = 'gpuBoardPowerWatts'; unit = 'W'; source = 'LibreHardwareMonitor|OpenHardwareMonitor' },
    @{ field = 'gpuUsagePercent'; unit = '%'; source = 'LibreHardwareMonitor|OpenHardwareMonitor' },
    @{ field = 'gpuVramUsedBytes'; unit = 'octets'; source = 'LibreHardwareMonitor|OpenHardwareMonitor' },
    @{ field = 'cpuFanRpm'; unit = 'tr/min'; source = 'LibreHardwareMonitor|OpenHardwareMonitor' },
    @{ field = 'gpuFanRpm'; unit = 'tr/min'; source = 'LibreHardwareMonitor|OpenHardwareMonitor' },
    @{ field = 'chassisFanRpm'; unit = 'tr/min'; source = 'LibreHardwareMonitor|OpenHardwareMonitor' },
    @{ field = 'cpuFrequencyMhz'; unit = 'MHz'; source = 'Win32_Processor' },
    @{ field = 'memoryUsedBytes'; unit = 'octets'; source = 'Win32_OperatingSystem' },
    @{ field = 'swapUsedBytes'; unit = 'octets'; source = 'Win32_PageFileUsage' },
    @{ field = 'diskReadBytesPerSecond'; unit = 'octets/s'; source = 'Win32_PerfRawData_PerfDisk_PhysicalDisk' },
    @{ field = 'diskWriteBytesPerSecond'; unit = 'octets/s'; source = 'Win32_PerfRawData_PerfDisk_PhysicalDisk' },
    @{ field = 'networkRxBytesPerSecond'; unit = 'octets/s'; source = 'Win32_PerfRawData_Tcpip_NetworkInterface' },
    @{ field = 'networkTxBytesPerSecond'; unit = 'octets/s'; source = 'Win32_PerfRawData_Tcpip_NetworkInterface' }
  )
  foreach ($metric in $metrics) {
    $values = Select-MonitoringValue -Samples $samples -Field $metric.field
    $aggregates[$metric.field] = New-MonitoringAggregate -Values $values -Unit $metric.unit `
      -IntervalMs $intervalMs -Source $metric.source
  }

  return @{
    startedAt = $startedAt
    intervalMs = $intervalMs
    durationMs = $elapsed * 1000
    samples = $samples
    aggregates = $aggregates
  }
}
