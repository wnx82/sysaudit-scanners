# SysAudit Windows — processeurs, memoire et cartes graphiques.

function ConvertTo-GpuDeviceKey {
  param($Value)

  if ($null -eq $Value) { return '' }
  $text = [string]$Value
  if ([string]::IsNullOrWhiteSpace($text)) { return '' }
  return ($text.Trim() -replace '^Enum\\', '').ToUpperInvariant()
}

function ConvertTo-GpuName {
  param($Value)

  if ($null -eq $Value) { return '' }
  $text = [string]$Value
  if ([string]::IsNullOrWhiteSpace($text)) { return '' }
  return (($text.Trim() -replace '\s+', ' ').ToUpperInvariant())
}

function Test-VirtualDisplayAdapter {
  param(
    $Model,
    $Vendor
  )

  $text = "$(ConvertTo-GpuName -Value $Model) $(ConvertTo-GpuName -Value $Vendor)"
  return (
    $text.Contains('PARSEC VIRTUAL DISPLAY ADAPTER') -or
    $text.Contains('VIRTUAL DISPLAY ADAPTER') -or
    $text.Contains('INDIRECT DISPLAY ADAPTER')
  )
}

function ConvertTo-GpuHardwareId {
  param($Value)

  $deviceKey = ConvertTo-GpuDeviceKey -Value $Value
  if ($deviceKey -eq '') { return '' }

  $parts = $deviceKey -split '\\'
  if ($parts.Length -ge 2) {
    return ($parts[0] + '\' + $parts[1])
  }

  return $deviceKey
}

<#
.SYNOPSIS
  Octets reellement occupes dans les fichiers d'echange, ou un marqueur.

.DESCRIPTION
  `memory.swapUsedBytes` sortait en `NOT_AVAILABLE` sur toute machine Windows,
  et `PRF-001` — « Fichier d'echange fortement sollicite » — avec lui, alors que
  `Win32_PageFileUsage` publie la valeur sans elevation. Le collecteur de
  telemetrie la lisait deja pour ses echantillons ; seule la section `memory` ne
  la recevait pas.

  Trois situations, trois reponses distinctes :

  - des fichiers d'echange existent et sont lus : la somme de leur occupation ;
  - `SizeStoredInPagingFiles` vaut zero : la machine n'en a pas, et zero octet
    occupe est alors un **fait**, pas un repli. C'est ce qui permet a `PRF-001`
    de conclure « aucun fichier d'echange configure » au lieu de rester muette ;
  - la classe ne repond pas alors qu'un fichier est declare : marqueur. Publier
    zero ferait passer une machine qui echange beaucoup pour une machine au
    repos — exactement l'inverse du constat.

  `CurrentUsage` est en mebioctets, comme `AllocatedBaseSize`.
#>
function Get-PageFileUsedBytes {
  param($OperatingSystem)

  # `SizeStoredInPagingFiles` est en kilo-octets. Seul son signe compte ici —
  # « un fichier d'echange est-il declare ? » —, mais le nommer d'apres son
  # unite reelle evite qu'un lecteur ne le recopie ailleurs avec le mauvais
  # facteur, ce qui est exactement ce qui etait arrive a `swapTotalBytes`.
  $declaredKib = 0
  if ($null -ne $OperatingSystem -and $null -ne $OperatingSystem.SizeStoredInPagingFiles) {
    $declaredKib = [int64]$OperatingSystem.SizeStoredInPagingFiles
  }

  $usage = @()
  try {
    $usage = @(Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction Stop)
  } catch {
    if ($declaredKib -le 0) { return [int64]0 }
    Add-CollectionIssue -Section 'memory.swapUsedBytes' -Severity 'warning' `
      -Message ('Occupation du fichier d''echange non lue : ' + $_.Exception.Message) `
      -Source 'Win32_PageFileUsage' -Reason 'NOT_AVAILABLE'
    return (New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'Win32_PageFileUsage illisible')
  }

  if ($usage.Count -eq 0) {
    # Aucun fichier d'echange declare non plus : l'absence est coherente, et
    # zero octet occupe est la mesure juste.
    if ($declaredKib -le 0) { return [int64]0 }
    return (New-Unknown -Reason 'UNKNOWN' `
        -Detail 'un fichier d''echange est declare, mais Win32_PageFileUsage n''en publie aucun')
  }

  $usedMib = 0
  foreach ($file in $usage) {
    if ($null -eq $file.CurrentUsage) { continue }
    $usedMib += [int64]$file.CurrentUsage
  }

  Add-CollectionProvenance -Path 'memory.swapUsedBytes' -Source 'Win32_PageFileUsage' `
    -Method 'CIM' -Precision 'mebioctet'

  return [int64]($usedMib * 1MB)
}

function Convert-RegistryMemoryToBytes {
  param($Value)

  if ($null -eq $Value) { return $null }
  if ($Value -is [byte[]]) {
    if ($Value.Length -lt 8) { return $null }
    return [BitConverter]::ToInt64($Value, 0)
  }

  if ($Value -is [int64] -or $Value -is [uint64] -or $Value -is [int32] -or $Value -is [uint32]) {
    return [int64]$Value
  }

  if ($Value -is [string] -and $Value -match '^\d+$') {
    return [int64]$Value
  }

  return $null
}

function Convert-DxDiagMemoryToBytes {
  param([string]$Value)

  if ([string]::IsNullOrWhiteSpace($Value)) { return $null }

  if ($Value -match '([0-9][0-9\s,\.]*)\s*(KB|MB|GB|KO|MO|GO)\b') {
    $number = ($Matches[1] -replace '[\s,]', '')
    $unit = $Matches[2].ToUpperInvariant()
    if ($number -match '^\d+(?:\.\d+)?$') {
      $parsedNumber = [double]::Parse($number, [System.Globalization.CultureInfo]::InvariantCulture)
      $multiplier = switch ($unit) {
        'KB' { 1024.0 }
        'KO' { 1024.0 }
        'MB' { 1048576.0 }
        'MO' { 1048576.0 }
        'GB' { 1073741824.0 }
        'GO' { 1073741824.0 }
        default { $null }
      }
      if ($null -ne $multiplier) {
        return [int64]([Math]::Round($parsedNumber * $multiplier))
      }
    }
  }

  return $null
}

function Convert-MonitorCodeUnitsToText {
  param($Value)

  if ($null -eq $Value) { return '' }

  $chars = @()
  foreach ($item in @($Value)) {
    if ($null -eq $item) { continue }
    $code = [int]$item
    if ($code -le 0) { continue }
    $chars += [char]$code
  }

  if ($chars.Count -eq 0) { return '' }
  return (($chars -join '').Trim() -replace '\s+', ' ')
}

function ConvertTo-MonitorInstanceKey {
  param($Value)

  if ($null -eq $Value) { return '' }
  $text = [string]$Value
  if ([string]::IsNullOrWhiteSpace($text)) { return '' }

  return (($text.Trim().ToUpperInvariant()) -replace '_\d+$', '')
}

function Get-MonitorConnectionLabel {
  param($Value)

  if ($null -eq $Value) { return '' }

  $code = [int64]$Value
  switch ($code) {
    0 { return 'Autre' }
    1 { return 'VGA' }
    2 { return 'S-Video' }
    3 { return 'Composite' }
    4 { return 'Component' }
    5 { return 'DVI' }
    6 { return 'HDMI' }
    8 { return 'LVDS' }
    11 { return 'DisplayPort' }
    12 { return 'eDP' }
    2147483648 { return 'Interne' }
    default { return '' }
  }
}

function Get-MonitorInventoryFromSources {
  param(
    [object[]]$MonitorIds,
    [object[]]$Connections,
    [object[]]$DesktopMonitors
  )

  $connectionsByKey = @{}
  foreach ($connection in @($Connections)) {
    if ($null -eq $connection) { continue }
    $key = ConvertTo-MonitorInstanceKey -Value $connection.InstanceName
    if ($key -eq '' -or $connectionsByKey.ContainsKey($key)) { continue }
    $connectionsByKey[$key] = $connection
  }

  $desktopByKey = @{}
  foreach ($desktop in @($DesktopMonitors)) {
    if ($null -eq $desktop) { continue }
    $key = ConvertTo-MonitorInstanceKey -Value $desktop.PNPDeviceID
    if ($key -eq '' -or $desktopByKey.ContainsKey($key)) { continue }
    $desktopByKey[$key] = $desktop
  }

  $displays = @()
  foreach ($monitor in @($MonitorIds)) {
    if ($null -eq $monitor) { continue }
    if ($null -ne $monitor.PSObject.Properties['Active'] -and -not [bool]$monitor.Active) { continue }

    $key = ConvertTo-MonitorInstanceKey -Value $monitor.InstanceName
    $desktop = if ($key -ne '' -and $desktopByKey.ContainsKey($key)) { $desktopByKey[$key] } else { $null }
    $connection = if ($key -ne '' -and $connectionsByKey.ContainsKey($key)) { $connectionsByKey[$key] } else { $null }

    $name = Convert-MonitorCodeUnitsToText -Value $monitor.UserFriendlyName
    if ([string]::IsNullOrWhiteSpace($name) -and $null -ne $desktop) {
      $name = [string]$desktop.Name
    }

    $manufacturer = Convert-MonitorCodeUnitsToText -Value $monitor.ManufacturerName
    $resolution = $null
    if ($null -ne $desktop -and $desktop.ScreenWidth -and $desktop.ScreenHeight) {
      $resolution = ([string]$desktop.ScreenWidth + 'x' + [string]$desktop.ScreenHeight)
    }

    $refreshRate = $null
    if ($null -ne $desktop -and $desktop.ScreenRefreshRate) {
      $refreshRate = $desktop.ScreenRefreshRate
    }

    # `UserFriendlyName` est le nom que l'ecran publie dans son EDID : c'est le
    # modele, et le champ `name` le portait deja faute d'avoir ou le mettre.
    # Les deux restent renseignes -- `name` designe l'ecran dans la liste,
    # `model` dit ce qu'il est.
    $model = Convert-MonitorCodeUnitsToText -Value $monitor.UserFriendlyName
    $serial = Convert-MonitorCodeUnitsToText -Value $monitor.SerialNumberID

    $displays += @{
      name = Get-StringOrUnknown -Value $name -Reason 'UNKNOWN'
      manufacturer = Get-StringOrUnknown -Value $manufacturer -Reason 'UNKNOWN'
      model = Get-StringOrUnknown -Value $model -Reason 'NOT_AVAILABLE' -Detail 'ecran ne publiant pas son nom de modele dans l''EDID'
      serialNumber = Get-StringOrUnknown -Value $serial -Reason 'NOT_AVAILABLE' -Detail 'ecran ne publiant aucun numero de serie dans l''EDID'
      resolution = Get-StringOrUnknown -Value $resolution -Reason 'NOT_AVAILABLE'
      refreshRateHz = Get-PositiveIntOrUnknown -Value $refreshRate -Reason 'NOT_AVAILABLE'
      connection = Get-StringOrUnknown -Value (Get-MonitorConnectionLabel -Value $connection.VideoOutputTechnology) -Reason 'NOT_AVAILABLE'
    }
  }

  if ($displays.Count -gt 0) { return $displays }

  foreach ($desktop in @($DesktopMonitors)) {
    if ($null -eq $desktop) { continue }
    $resolution = $null
    if ($desktop.ScreenWidth -and $desktop.ScreenHeight) {
      $resolution = ([string]$desktop.ScreenWidth + 'x' + [string]$desktop.ScreenHeight)
    }

    # Ce repli ne dispose que de `Win32_DesktopMonitor`, qui ne porte aucune
    # donnee d'EDID : modele et numero de serie y sont absents, non illisibles.
    $displays += @{
      name = Get-StringOrUnknown -Value $desktop.Name -Reason 'UNKNOWN'
      manufacturer = New-Unknown -Reason 'NOT_AVAILABLE'
      model = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'EDID non expose par Win32_DesktopMonitor'
      serialNumber = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'EDID non expose par Win32_DesktopMonitor'
      resolution = Get-StringOrUnknown -Value $resolution -Reason 'NOT_AVAILABLE'
      refreshRateHz = Get-PositiveIntOrUnknown -Value $desktop.ScreenRefreshRate -Reason 'NOT_AVAILABLE'
      connection = New-Unknown -Reason 'NOT_AVAILABLE'
    }
  }

  return $displays
}

function Get-MonitorInventory {
  $monitorIds = @()
  $connections = @()
  $desktopMonitors = @()

  # Les sorties d'affichage ne sont pas enumerees au niveau Rapide.
  #
  # Trois requetes CIM, dont deux dans `root\wmi` -- l'espace de noms le plus
  # lent de la collecte. Le scanner Linux reserve deja les sorties d'affichage
  # au niveau Normale (`hardware.sh`) : aligner Windows dessus rend la matrice
  # vraie sur les deux scanners, et rend l'audit Rapide reellement rapide.
  if (-not (Test-DepthAtLeast -Section 'gpus' -Wanted 'standard')) {
    Add-LevelSkip -Section 'gpus.displays' -Needed 'standard'
    return @()
  }

  try {
    $monitorIds = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop)
  } catch {
    $monitorIds = @()
  }

  try {
    $connections = @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams -ErrorAction Stop)
  } catch {
    $connections = @()
  }

  try {
    $desktopMonitors = @(Get-CimInstance Win32_DesktopMonitor -ErrorAction Stop)
  } catch {
    $desktopMonitors = @()
  }

  return @(Get-MonitorInventoryFromSources -MonitorIds $monitorIds -Connections $connections -DesktopMonitors $desktopMonitors)
}

function Get-GpuRegistryAdapterListFromItems {
  param([object[]]$Items)

  $adapters = @()
  foreach ($item in @($Items)) {
    if ($null -eq $item) { continue }
    $memorySizeBytes = Convert-RegistryMemoryToBytes -Value $item.'HardwareInformation.qwMemorySize'
    if ($null -eq $memorySizeBytes) { continue }

    $adapters += @{
      adapterString = [string]$item.'HardwareInformation.AdapterString'
      matchingDeviceId = ConvertTo-GpuHardwareId -Value $item.MatchingDeviceId
      memorySizeBytes = [int64]$memorySizeBytes
    }
  }

  return $adapters
}

function Get-GpuRegistryAdapterList {
  if ($null -ne $script:GpuRegistryAdapters) { return $script:GpuRegistryAdapters }

  $script:GpuRegistryAdapters = @()
  $root = 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Video'

  try {
    $items = Get-ChildItem -Path $root -ErrorAction Stop |
      ForEach-Object {
        Get-ItemProperty -LiteralPath (Join-Path $_.PSPath '0000') -ErrorAction SilentlyContinue
      }
    $script:GpuRegistryAdapters = @(Get-GpuRegistryAdapterListFromItems -Items $items)
    return $script:GpuRegistryAdapters
  } catch {
    return $script:GpuRegistryAdapters
  }
}

function Get-DxDiagDisplayDeviceListFromText {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) { return @() }

  $devices = @()
  $current = $null

  foreach ($line in ($Text -split "`r?`n")) {
    if ($line -match '^\s*(?:Card name|Nom de la carte)\s*:\s*(.+?)\s*$') {
      if ($null -ne $current) { $devices += $current }
      $current = @{
        cardName = $Matches[1].Trim()
        deviceKey = ''
        dedicatedMemoryBytes = $null
      }
      continue
    }

    if ($null -eq $current) { continue }

    if ($line -match '^\s*(?:Device Key|Clé du périphérique|Cle du peripherique)\s*:\s*(.+?)\s*$') {
      $current.deviceKey = ConvertTo-GpuDeviceKey -Value $Matches[1]
      continue
    }

    if ($line -match '^\s*(?:Dedicated Memory|Mémoire dédiée|Memoire dediee)\s*:\s*(.+?)\s*$') {
      $current.dedicatedMemoryBytes = Convert-DxDiagMemoryToBytes -Value $Matches[1]
      continue
    }
  }

  if ($null -ne $current) { $devices += $current }
  return $devices
}

function Get-DxDiagDisplayDeviceList {
  if ($null -ne $script:DxDiagDisplayDevices) { return $script:DxDiagDisplayDevices }

  $script:DxDiagDisplayDevices = @()
  $temp = Join-Path ([System.IO.Path]::GetTempPath()) ('sysaudit-dxdiag-' + [guid]::NewGuid().ToString('N') + '.txt')

  try {
    $process = Start-Process dxdiag `
      -ArgumentList @('/whql:off', '/t', $temp) `
      -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
    if ($null -eq $process -or $process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $temp)) {
      return $script:DxDiagDisplayDevices
    }

    $content = Get-Content -LiteralPath $temp -Raw -ErrorAction Stop
    $script:DxDiagDisplayDevices = @(Get-DxDiagDisplayDeviceListFromText -Text $content)
    return $script:DxDiagDisplayDevices
  } catch {
    return $script:DxDiagDisplayDevices
  } finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
  }
}

function Get-GpuDedicatedMemoryBytes {
  param(
    $Gpu,
    [object[]]$DxDiagDevices
  )

  if (Test-VirtualDisplayAdapter -Model $Gpu.Name -Vendor $Gpu.AdapterCompatibility) {
    return $null
  }

  $deviceKey = ConvertTo-GpuDeviceKey -Value $Gpu.PNPDeviceID
  $cardName = ConvertTo-GpuName -Value $Gpu.Name

  foreach ($entry in @($DxDiagDevices)) {
    if ($null -eq $entry) { continue }
    if (
      $deviceKey -ne '' -and
      $entry.deviceKey -ne '' -and
      ($deviceKey.StartsWith($entry.deviceKey) -or $entry.deviceKey.StartsWith($deviceKey)) -and
      $null -ne $entry.dedicatedMemoryBytes
    ) {
      return $entry.dedicatedMemoryBytes
    }
  }

  foreach ($entry in @($DxDiagDevices)) {
    if ($null -eq $entry) { continue }
    if (
      $cardName -ne '' -and
      (ConvertTo-GpuName -Value $entry.cardName) -eq $cardName -and
      $null -ne $entry.dedicatedMemoryBytes
    ) {
      return $entry.dedicatedMemoryBytes
    }
  }

  return $null
}

function Get-GpuRegistryMemoryBytes {
  param(
    $Gpu,
    [object[]]$RegistryAdapters
  )

  if (Test-VirtualDisplayAdapter -Model $Gpu.Name -Vendor $Gpu.AdapterCompatibility) {
    return $null
  }

  $hardwareId = ConvertTo-GpuHardwareId -Value $Gpu.PNPDeviceID
  $cardName = ConvertTo-GpuName -Value $Gpu.Name

  foreach ($entry in @($RegistryAdapters)) {
    if ($null -eq $entry) { continue }
    if (
      $hardwareId -ne '' -and
      $entry.matchingDeviceId -ne '' -and
      ($hardwareId.StartsWith($entry.matchingDeviceId) -or $entry.matchingDeviceId.StartsWith($hardwareId)) -and
      $null -ne $entry.memorySizeBytes
    ) {
      return $entry.memorySizeBytes
    }
  }

  foreach ($entry in @($RegistryAdapters)) {
    if ($null -eq $entry) { continue }
    if (
      $cardName -ne '' -and
      (ConvertTo-GpuName -Value $entry.adapterString) -eq $cardName -and
      $null -ne $entry.memorySizeBytes
    ) {
      return $entry.memorySizeBytes
    }
  }

  return $null
}

function Get-HardwareSensorSnapshot {
  $providers = @(
    @{ Namespace = 'root/LibreHardwareMonitor' },
    @{ Namespace = 'root/OpenHardwareMonitor' }
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

function Get-GpuTelemetrySensorScore {
  param(
    $Sensor,
    [string]$Metric
  )

  if ($null -eq $Sensor) { return -1 }

  $expectedType = switch ($Metric) {
    'temperature' { 'Temperature' }
    'coreClock' { 'Clock' }
    'memoryClock' { 'Clock' }
    default { '' }
  }
  if ([string]$Sensor.SensorType -ne $expectedType) { return -1 }

  $parts = @([string]$Sensor.Name, [string]$Sensor.Hardware, [string]$Sensor.Identifier, [string]$Sensor.Parent) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  if ($parts.Count -eq 0) { return -1 }

  $haystack = ($parts -join ' ').ToLowerInvariant()
  $score = 0

  switch ($Metric) {
    'temperature' {
      if ($haystack -match 'gpu temperature') { $score += 130 }
      if ($haystack -match 'gpu core') { $score += 120 }
      if ($haystack -match '\bedge\b') { $score += 100 }
      if ($haystack -match '\bgpu\b') { $score += 80 }
      if ($haystack -match 'hot\s?spot|junction') { $score -= 120 }
    }
    'coreClock' {
      if ($haystack -match 'graphics clock') { $score += 150 }
      if ($haystack -match 'gpu core') { $score += 140 }
      if ($haystack -match 'gpu clock') { $score += 130 }
      if ($haystack -match '\bgpu\b') { $score += 70 }
      if ($haystack -match 'memory') { $score -= 120 }
    }
    'memoryClock' {
      if ($haystack -match 'memory clock') { $score += 150 }
      if ($haystack -match 'mem clock') { $score += 140 }
      if ($haystack -match 'gpu memory') { $score += 130 }
      if ($haystack -match '\bgpu\b') { $score += 60 }
    }
  }

  if ($haystack -match 'cpu|ram|dram|nvme|ssd|chipset|motherboard') { $score -= 200 }
  return $score
}

function Select-GpuTelemetrySensorValue {
  param(
    [object[]]$Sensors = @(),
    [string]$Metric,
    [switch]$RoundInt
  )

  $bestSensor = $null
  $bestScore = -1
  foreach ($sensor in $Sensors) {
    $score = Get-GpuTelemetrySensorScore -Sensor $sensor -Metric $Metric
    if ($score -lt 0) { continue }
    if ($score -le $bestScore) { continue }
    $bestScore = $score
    $bestSensor = $sensor
  }

  if ($null -eq $bestSensor) { return $null }

  try {
    $value = [double]$bestSensor.Value
    if ($RoundInt) { return [int][Math]::Round($value) }
    return [Math]::Round($value, 1)
  } catch {
    return $null
  }
}

function Get-GpuLiveTelemetryFromSensors {
  param([object[]]$Sensors = @())

  return @{
    temperatureCelsius = Select-GpuTelemetrySensorValue -Sensors $Sensors -Metric 'temperature'
    coreClockMhz = Select-GpuTelemetrySensorValue -Sensors $Sensors -Metric 'coreClock' -RoundInt
    memoryClockMhz = Select-GpuTelemetrySensorValue -Sensors $Sensors -Metric 'memoryClock' -RoundInt
  }
}

<#
.SYNOPSIS
  Note un capteur comme temperature de **processeur**.

.DESCRIPTION
  Meme mecanique que la selection GPU, et pour la meme raison : plusieurs sondes
  portent des noms voisins, et prendre la premiere revient a tirer au sort.

  Trois principes gouvernent cette note, et le troisieme est le seul qui compte
  vraiment.

  1. Le capteur doit etre de type `Temperature`. Sans cela, une frequence
     nommee « CPU Core » entrerait comme un degre.
  2. « CPU Package » l'emporte sur « CPU Core #3 » : c'est la temperature du
     boitier entier, celle qu'un constructeur publie et celle qu'un seuil vise.
  3. **Une zone thermique generique ne peut jamais gagner.** C'est la regle que
     le collecteur Linux applique deja en toutes lettres — refuser de convertir
     une `thermal_zone` anonyme en « CPU » — et la raison en est concrete : une
     sonde nommee `Temperature` a 51 degres ne designe aucun materiel en
     particulier, et l'attribuer au processeur produirait un constat de
     surchauffe sur une machine froide, ou l'inverse.

  Une note negative signifie « ce capteur ne dit rien du processeur », et
  l'appelant n'en tire alors aucune valeur.
#>
function Get-CpuTemperatureSensorScore {
  param($Sensor)

  if ($null -eq $Sensor) { return -1 }
  if ([string]$Sensor.SensorType -ne 'Temperature') { return -1 }

  $parts = @([string]$Sensor.Name, [string]$Sensor.Hardware, [string]$Sensor.Identifier, [string]$Sensor.Parent) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  if ($parts.Count -eq 0) { return -1 }

  $haystack = ($parts -join ' ').ToLowerInvariant()

  # Tout ce qui designe un autre composant disqualifie, avant meme de compter.
  # Une carte graphique publie « GPU Core », un NVMe « Composite » : les deux
  # sont des temperatures, aucune n'est celle du processeur.
  if ($haystack -match '\bgpu\b|\bvram\b|\bnvme\b|\bssd\b|\bhdd\b|\bdrive\b|chipset|motherboard|\bvrm\b|\bdimm\b|\bdram\b|ambient') {
    return -1
  }

  $score = 0
  if ($haystack -match 'cpu package|package temperature') { $score += 150 }
  if ($haystack -match 'core \(tctl') { $score += 140 }
  if ($haystack -match '\btdie\b') { $score += 130 }
  if ($haystack -match 'cpu core') { $score += 110 }
  if ($haystack -match '\bcpu\b') { $score += 90 }
  if ($haystack -match 'core average') { $score += 60 }
  if ($haystack -match 'core max') { $score += 50 }

  # Rien dans le nom ne rattache ce capteur au processeur : c'est le cas de la
  # zone thermique ACPI generique, et il ne doit jamais gagner.
  if ($score -eq 0) { return -1 }
  return $score
}

<#
.SYNOPSIS
  Temperature du processeur, quand une source materielle la publie.

.DESCRIPTION
  `Win32_Processor` ne porte aucune temperature — c'est pourquoi ce champ
  rendait `NOT_AVAILABLE` en dur. Un provider materiel, lui, en publie une
  quand il tourne.

  Rend `$null` quand aucun capteur ne se rattache explicitement au processeur.
  L'appelant conserve alors son marqueur d'absence, ce qui est exact : la
  machine n'a rien dit, et la zone thermique ACPI qu'elle expose peut-etre ne
  parle pas du processeur.
#>
function Get-CpuTemperatureFromSensors {
  param([object[]]$Sensors = @())

  $bestSensor = $null
  $bestScore = -1
  foreach ($sensor in $Sensors) {
    $score = Get-CpuTemperatureSensorScore -Sensor $sensor
    if ($score -lt 0) { continue }
    if ($score -le $bestScore) { continue }
    $bestScore = $score
    $bestSensor = $sensor
  }

  if ($null -eq $bestSensor) { return $null }

  try {
    $value = [double]$bestSensor.Value
  } catch {
    return $null
  }

  # Hors du domaine physique, ce n'est pas une temperature : c'est la reponse
  # d'une sonde absente ou d'un registre non initialise.
  if ($value -le -40 -or $value -ge 150) { return $null }
  return [Math]::Round($value, 1)
}

function Get-HardwareInventory {
  $cpus = @()
  $physicalProcessors = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue
  # Les capteurs sont lus **une fois** pour toute la section : ils servent au
  # processeur ici, et aux cartes graphiques plus bas. Deux interrogations du
  # provider rendraient deux instants differents sous un meme rapport.
  $cpuSensors = @(Get-HardwareSensorSnapshot)
  $cpuTemperature = Get-CpuTemperatureFromSensors -Sensors $cpuSensors
  if ($null -ne $cpuTemperature) {
    Add-CollectionProvenance -Path 'cpus[].temperatureCelsius' -Source 'LibreHardwareMonitor' -Method 'CIM' -Precision 'capteur'
  }
  foreach ($cpu in $physicalProcessors) {
    $cpus += @{
      manufacturer = Get-StringOrUnknown -Value $cpu.Manufacturer -Reason 'UNKNOWN'
      model = Get-StringOrUnknown -Value $cpu.Name -Reason 'UNKNOWN'
      family = Get-StringOrUnknown -Value $cpu.Description -Reason 'UNKNOWN'
      generation = New-Unknown -Reason 'UNKNOWN'
      socket = Get-StringOrUnknown -Value $cpu.SocketDesignation -Reason 'UNKNOWN'
      physicalCores = Get-PositiveIntOrUnknown -Value $cpu.NumberOfCores -Reason 'UNKNOWN'
      logicalCores = Get-PositiveIntOrUnknown -Value $cpu.NumberOfLogicalProcessors -Reason 'UNKNOWN'
      baseFrequencyMhz = Get-PositiveIntOrUnknown -Value $cpu.MaxClockSpeed -Reason 'UNKNOWN'
      maxFrequencyMhz = Get-PositiveIntOrUnknown -Value $cpu.MaxClockSpeed -Reason 'UNKNOWN'
      currentFrequencyMhz = Get-PositiveIntOrUnknown -Value $cpu.CurrentClockSpeed -Reason 'UNKNOWN'
      virtualization = @{
        supported = [bool]$cpu.VirtualizationFirmwareEnabled -or [bool]$cpu.VMMonitorModeExtensions
        enabled = [bool]$cpu.VirtualizationFirmwareEnabled
        technology = 'VT-x/AMD-V'
      }
      <#
        `Win32_Processor` ne porte aucune temperature : ce champ rendait donc
        `NOT_AVAILABLE` en dur, sur toutes les machines Windows.

        Une source materielle dediee, quand elle tourne, en publie une. A
        defaut, le marqueur d'absence est **conserve** plutot que rempli par la
        zone thermique ACPI que la machine expose peut-etre : une sonde nommee
        `Temperature` a 51 degres ne designe aucun materiel en particulier, et
        l'attribuer au processeur produirait un constat de surchauffe sur une
        machine froide. C'est exactement le refus que le collecteur Linux
        applique deja, et il vaut ici pour la meme raison.
      #>
      temperatureCelsius = if ($null -ne $cpuTemperature) { $cpuTemperature } else { New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'aucun capteur rattache au processeur' }
      usagePercent = Get-NumberOrUnknown -Value $cpu.LoadPercentage -Reason 'UNKNOWN'
    }
  }

  # Le detail des barrettes vient de `Win32_PhysicalMemory`, une requete par
  # module : c'est la partie couteuse de cette collecte, et le resume s'en
  # passe. Les totaux, eux, sont lus a tous les niveaux.
  $memoryModules = @()
  $physicalMemory = @()
  if (Test-DepthAtLeast -Section 'memory' -Wanted 'standard') {
    $physicalMemory = Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue
  } else {
    Add-LevelSkip -Section 'memory.modules' -Needed 'standard'
  }
  foreach ($module in $physicalMemory) {
    $memoryModules += @{
      slot = Get-StringOrUnknown -Value $module.DeviceLocator -Reason 'UNKNOWN'
      sizeBytes = Get-PositiveIntOrUnknown -Value $module.Capacity -Reason 'UNKNOWN'
      # Trois champs SMBIOS facultatifs, et trois textes de gabarit rencontres
      # sur le parc : `Unknown`, `00000000`, la chaine vide. Voir
      # `Get-MeaningfulStringOrUnknown`.
      manufacturer = Get-MeaningfulStringOrUnknown -Value $module.Manufacturer -Reason 'UNKNOWN'
      partNumber = Get-MeaningfulStringOrUnknown -Value $module.PartNumber -Reason 'UNKNOWN'
      serialNumber = Get-MeaningfulStringOrUnknown -Value $module.SerialNumber -Reason 'UNKNOWN'
      type = Get-StringOrUnknown -Value $module.SMBIOSMemoryType -Reason 'UNKNOWN'
      ratedSpeedMts = Get-PositiveIntOrUnknown -Value $module.Speed -Reason 'UNKNOWN'
      configuredSpeedMts = Get-PositiveIntOrUnknown -Value $module.ConfiguredClockSpeed -Reason 'UNKNOWN'
      performanceProfile = @{
        technology = New-Unknown -Reason 'UNKNOWN' -Detail 'profil XMP/EXPO non expose par WMI'
        active = New-Unknown -Reason 'UNKNOWN' -Detail 'profil XMP/EXPO non expose par WMI'
        profileName = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'nom de profil non expose par WMI'
      }
      voltage = if ($module.ConfiguredVoltage) { [Math]::Round(([double]$module.ConfiguredVoltage / 1000), 3) } else { New-Unknown -Reason 'UNKNOWN' }
      ecc = if ($null -ne $module.TotalWidth -and $null -ne $module.DataWidth) { [bool]([int]$module.TotalWidth -gt [int]$module.DataWidth) } else { New-Unknown -Reason 'UNKNOWN' }
      formFactor = Get-StringOrUnknown -Value $module.FormFactor -Reason 'UNKNOWN'
    }
  }

  $memoryArrays = Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue
  $slotsTotal = if ($memoryArrays) { ($memoryArrays | Measure-Object -Property MemoryDevices -Sum).Sum } else { $null }

  $gpus = @()
  $registryGpuAdapters = @(Get-GpuRegistryAdapterList)
  $dxdiagDevices = @(Get-DxDiagDisplayDeviceList)
  $videoControllers = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
  # Deja prise en tete de section, pour le processeur : la relire ici rendrait
  # deux instants differents sous un meme rapport.
  $gpuSensors = $cpuSensors
  $physicalGpuCount = @($videoControllers | Where-Object {
      -not (Test-VirtualDisplayAdapter -Model $_.Name -Vendor $_.AdapterCompatibility)
    }).Count
  $singleGpuTelemetry = if ($physicalGpuCount -eq 1) { Get-GpuLiveTelemetryFromSensors -Sensors $gpuSensors } else { $null }
  foreach ($gpu in $videoControllers) {
    $dedicatedMemoryBytes = Get-GpuRegistryMemoryBytes -Gpu $gpu -RegistryAdapters $registryGpuAdapters
    if ($null -eq $dedicatedMemoryBytes) {
      $dedicatedMemoryBytes = Get-GpuDedicatedMemoryBytes -Gpu $gpu -DxDiagDevices $dxdiagDevices
    }
    $applyTelemetry = $null -ne $singleGpuTelemetry -and -not (Test-VirtualDisplayAdapter -Model $gpu.Name -Vendor $gpu.AdapterCompatibility)
    $gpus += @{
      vendor = Get-StringOrUnknown -Value $gpu.AdapterCompatibility -Reason 'UNKNOWN'
      model = Get-StringOrUnknown -Value $gpu.Name -Reason 'UNKNOWN'
      pciId = Get-StringOrUnknown -Value $gpu.PNPDeviceID -Reason 'UNKNOWN'
      vramBytes = if ($null -ne $dedicatedMemoryBytes) {
        [int64]$dedicatedMemoryBytes
      } else {
        Get-PositiveIntOrUnknown -Value $gpu.AdapterRAM -Reason 'UNKNOWN'
      }
      driver = Get-StringOrUnknown -Value ($gpu.InstalledDisplayDrivers -join ', ') -Reason 'UNKNOWN'
      driverVersion = Get-StringOrUnknown -Value $gpu.DriverVersion -Reason 'UNKNOWN'
      driverDate = Convert-WmiDateOrUnknown -Value $gpu.DriverDate
      temperatureCelsius = if ($applyTelemetry -and $null -ne $singleGpuTelemetry.temperatureCelsius) { $singleGpuTelemetry.temperatureCelsius } else { New-Unknown -Reason 'NOT_AVAILABLE' }
      usagePercent = New-Unknown -Reason 'NOT_AVAILABLE'
      coreClockMhz = if ($applyTelemetry -and $null -ne $singleGpuTelemetry.coreClockMhz) { $singleGpuTelemetry.coreClockMhz } else { New-Unknown -Reason 'NOT_AVAILABLE' }
      memoryClockMhz = if ($applyTelemetry -and $null -ne $singleGpuTelemetry.memoryClockMhz) { $singleGpuTelemetry.memoryClockMhz } else { New-Unknown -Reason 'NOT_AVAILABLE' }
      displays = @()
    }
  }

  $displays = @(Get-MonitorInventory)
  if ($gpus.Count -gt 0 -and $displays.Count -gt 0) {
    $targetGpu = $gpus | Where-Object {
      -not (Test-VirtualDisplayAdapter -Model $_.model -Vendor $_.vendor)
    } | Select-Object -First 1
    if ($null -eq $targetGpu) {
      $targetGpu = $gpus[0]
    }
    $targetGpu.displays = @($displays)
    Add-CollectionProvenance -Path 'gpus[].displays' -Source 'CIM WmiMonitorID/WmiMonitorConnectionParams' -Method 'CIM' -Precision 'ecran actif'
  }

  return @{
    cpus = $cpus
    memoryModules = $memoryModules
    memoryArrays = $memoryArrays
    slotsTotal = $slotsTotal
    gpus = $gpus
  }
}

<#
.SYNOPSIS
  Famille de composant d'une sonde, deduite du materiel qui la porte.

.DESCRIPTION
  LibreHardwareMonitor rattache chaque capteur a un materiel type
  (`HardwareType`) : c'est une information de premiere main, bien plus sure
  qu'une lecture du nom du capteur. Elle sert donc d'abord.

  Le nom departage ensuite ce qu'un seul materiel porte de differents : une carte
  mere expose sous un meme `Mainboard`/`SuperIO` la sonde du chipset, celle du
  chassis et celle des etages d'alimentation, dont les seuils vont du simple au
  double. Les classer toutes « carte mere » rangerait le VRM quarante degres
  trop bas.

  Ce que ni l'un ni l'autre n'identifie ressort `OTHER` : le rapport affiche la
  valeur, exacte, et s'abstient de la juger.
#>
function Get-ThermalCategory {
  param([string]$HardwareType = '', [string]$SensorName = '')

  $name = $SensorName.ToLowerInvariant()

  switch -Regex ($name) {
    'vrm|mos' { return 'VRM' }
    'pch|chipset' { return 'CHIPSET' }
    'ambient' { return 'AMBIENT' }
    'package|tctl|tdie|ccd|core #|cpu core|cpu package' { return 'CPU' }
  }

  switch -Regex ($HardwareType) {
    'GpuNvidia|GpuAmd|GpuIntel' { return 'GPU' }
    'Cpu' { return 'CPU' }
    'Memory' { return 'MEMORY' }
    'Storage' { return 'DRIVE_SSD' }
    'Network' { return 'NETWORK' }
    'Battery' { return 'BATTERY' }
    'Motherboard|Mainboard|SuperIO|EmbeddedController' {
      switch -Regex ($name) {
        'system|motherboard|mainboard' { return 'MOTHERBOARD' }
        default { return 'OTHER' }
      }
    }
  }

  return 'OTHER'
}

<#
.SYNOPSIS
  Materiels declares par le provider, indexes par identifiant.

.DESCRIPTION
  La classe `Sensor` ne porte que l'identifiant de son parent. Sans cette table,
  une temperature « Temperature » a 51 degres ne designe aucun materiel en
  particulier — et trois disques rendraient trois lignes identiques.
#>
function Get-HardwareIndex {
  param([string]$Namespace)

  $index = @{}
  try {
    foreach ($hardware in @(Get-CimInstance -Namespace $Namespace -ClassName 'Hardware' -ErrorAction Stop)) {
      $identifier = [string]$hardware.Identifier
      if ([string]::IsNullOrWhiteSpace($identifier)) { continue }
      $index[$identifier] = @{
        Name = [string]$hardware.Name
        Type = [string]$hardware.HardwareType
      }
    }
  } catch {
    # Un provider qui expose `Sensor` sans `Hardware` reste exploitable : les
    # relevés perdent leur materiel porteur, pas leur valeur.
    return $index
  }
  return $index
}

<#
.SYNOPSIS
  Nombre de releves thermiques pris par sonde.

.DESCRIPTION
  Une lecture unique attrape ce qui passe : un cœur qui vient de terminer une
  tache de fond rend dix degres de plus que la seconde d'apres. Trois releves
  espaces d'une seconde donnent un minimum, une moyenne et un maximum — des
  statistiques sur des mesures reelles, jamais une interpolation.

  Ils coutent deux secondes, prises seulement en collecte approfondie.
#>
function Get-ThermalSampleCount {
  if (Test-DepthAtLeast -Section 'sensors' -Wanted 'extended') { return 3 }
  return 1
}

<#
.SYNOPSIS
  Zones thermiques ACPI, quand aucun provider materiel n'a repondu.

.DESCRIPTION
  `MSAcpi_ThermalZoneTemperature` publie des dixiemes de kelvin. C'est une vraie
  sonde, mais son instance ne dit pas toujours ce qu'elle mesure : elle est donc
  rapportee sous sa propre source, sans etre presentee comme une temperature de
  processeur (§17 de la feuille de route). Une valeur hors du domaine physique
  est ecartee plutot que convertie.
#>
function Get-AcpiThermalReadings {
  param([string]$Scope = 'LOCAL', [int]$Passes = 1)

  $readings = @()
  $discarded = @()
  try {
    $zones = @(Get-CimInstance -Namespace 'root/wmi' -ClassName 'MSAcpi_ThermalZoneTemperature' -ErrorAction Stop)
  } catch {
    return @{ readings = $readings; discarded = $discarded; probed = 0 }
  }

  <#
    Les releves supplementaires de la collecte approfondie.

    Cette source les ignorait : elle rendait `sampleCount = 1` en dur, quelle
    que soit la profondeur demandee. Or elle est le **deuxieme rideau**, celui
    qui sert quand aucun provider materiel n'a repondu — c'est-a-dire sur la
    quasi-totalite des postes Windows, ou LibreHardwareMonitor n'est pas
    installe. Le niveau Complete y promettait donc une collecte approfondie des
    capteurs qu'il ne faisait pas, et n'apportait en pratique rien de plus que
    le niveau Normale. Constate le 2026-08-16 sur un poste Windows 11.

    Les statistiques ne sont publiees qu'a partir de deux releves, comme dans la
    branche des providers materiels : sur un releve unique, elles repeteraient
    la valeur courante sous un nom qui promet une observation dans la duree.
  #>
  $extra = @{}
  for ($pass = 1; $pass -lt $Passes; $pass++) {
    Start-Sleep -Seconds 1
    try {
      foreach ($again in @(Get-CimInstance -Namespace 'root/wmi' -ClassName 'MSAcpi_ThermalZoneTemperature' -ErrorAction Stop)) {
        if ($null -eq $again.CurrentTemperature) { continue }
        $key = [string]$again.InstanceName
        if (-not $extra.ContainsKey($key)) { $extra[$key] = @() }
        $extra[$key] += (([double]$again.CurrentTemperature / 10) - 273.15)
      }
    } catch {
      break
    }
  }

  foreach ($zone in $zones) {
    if ($null -eq $zone.CurrentTemperature) { continue }
    $raw = [double]$zone.CurrentTemperature
    $celsius = ($raw / 10) - 273.15
    $label = [string]$zone.InstanceName
    if ([string]::IsNullOrWhiteSpace($label)) { $label = 'Zone thermique ACPI' }

    if ($celsius -le -40 -or $celsius -ge 150) {
      $discarded += @{
        label = $label
        source = 'MSAcpi_ThermalZoneTemperature'
        rawValue = $raw
        rawUnit = 'decikelvin'
        celsius = [Math]::Round($celsius, 1)
        reason = 'OUT_OF_PHYSICAL_RANGE'
      }
      continue
    }

    $values = @($celsius)
    $key = [string]$zone.InstanceName
    if ($extra.ContainsKey($key)) { $values += $extra[$key] }

    $reading = @{
      label = $label
      celsius = [Math]::Round($celsius, 1)
      category = 'OTHER'
      source = 'MSAcpi_ThermalZoneTemperature'
      scope = $Scope
      quality = 'MEASURED'
      sampleCount = $values.Count
      rawValue = $raw
      rawUnit = 'decikelvin'
    }

    if ($values.Count -gt 1) {
      $measured = $values | Measure-Object -Minimum -Maximum -Average
      $reading.minCelsius = [Math]::Round($measured.Minimum, 1)
      $reading.maxCelsius = [Math]::Round($measured.Maximum, 1)
      $reading.averageCelsius = [Math]::Round($measured.Average, 1)
    }

    $readings += $reading
  }

  return @{ readings = $readings; discarded = $discarded; probed = @($zones).Count }
}

function Get-SensorSection {
  $temperatures = @()
  $fans = @()
  $voltages = @()
  $powers = @()
  $discarded = @()
  $sources = @()
  $probed = 0

  # Dans une machine virtuelle, une sonde visible appartient a l'hote quand
  # l'hyperviseur la laisse passer. Les rapporter sans le dire ferait chercher un
  # ventilateur a une machine qui n'en a pas.
  $scope = if (Get-RunningUnderHypervisor) { 'HYPERVISOR_HOST' } else { 'LOCAL' }

  # Ordre de repli (§5) : provider materiel d'abord, ACPI ensuite, puis ce que
  # le stockage a depose. Chaque niveau nomme sa source, parce qu'un « CPU
  # Package » venant de LibreHardwareMonitor et le meme venant d'une zone ACPI
  # n'ont pas la meme valeur de preuve.
  $providers = @(
    @{ Namespace = 'root/LibreHardwareMonitor'; Source = 'LibreHardwareMonitor' },
    @{ Namespace = 'root/OpenHardwareMonitor'; Source = 'OpenHardwareMonitor' }
  )

  $passes = Get-ThermalSampleCount

  foreach ($provider in $providers) {
    $sensors = @()
    try {
      $sensors = @(Get-CimInstance -Namespace $provider.Namespace -ClassName Sensor -ErrorAction Stop)
    } catch {
      continue
    }
    if ($sensors.Count -eq 0) { continue }

    Add-CollectionProvenance -Path 'sensors.temperatures' -Source $provider.Source -Method 'CIM' -Precision 'capteur'
    Add-CollectionProvenance -Path 'sensors.fans' -Source $provider.Source -Method 'CIM' -Precision 'capteur'
    Add-CollectionProvenance -Path 'sensors.voltages' -Source $provider.Source -Method 'CIM' -Precision 'capteur'
    Add-CollectionProvenance -Path 'sensors.powers' -Source $provider.Source -Method 'CIM' -Precision 'capteur'

    $hardware = Get-HardwareIndex -Namespace $provider.Namespace
    $samples = @{}

    for ($pass = 0; $pass -lt $passes; $pass++) {
      if ($pass -gt 0) {
        Start-Sleep -Seconds 1
        try {
          $sensors = @(Get-CimInstance -Namespace $provider.Namespace -ClassName Sensor -ErrorAction Stop)
        } catch {
          break
        }
      }

      foreach ($sensor in $sensors) {
        if ([string]$sensor.SensorType -ne 'Temperature') { continue }
        if ($null -eq $sensor.Value) { continue }
        $identifier = [string]$sensor.Identifier
        if ([string]::IsNullOrWhiteSpace($identifier)) { $identifier = [string]$sensor.Name }
        $value = [double]$sensor.Value

        if (-not $samples.ContainsKey($identifier)) {
          if ($pass -eq 0) { $probed++ }
          $parent = [string]$sensor.Parent
          $carrier = if ($hardware.ContainsKey($parent)) { $hardware[$parent] } else { $null }
          $samples[$identifier] = @{
            Label = [string]$sensor.Name
            HardwareType = if ($null -ne $carrier) { $carrier.Type } else { '' }
            Device = if ($null -ne $carrier) { $carrier.Name } else { '' }
            Values = @()
          }
        }

        # Hors du domaine physique, ce n'est pas une temperature : c'est la
        # reponse d'une sonde absente ou d'un registre non initialise. Elle est
        # conservee brute, une seule fois, plutot que d'etre effacee — une sonde
        # en panne est en soi une information.
        if ($value -le -40 -or $value -ge 150) {
          if ($pass -eq 0) {
            $discarded += @{
              label = $samples[$identifier].Label
              source = $provider.Source
              rawValue = $value
              rawUnit = 'celsius'
              celsius = [Math]::Round($value, 1)
              reason = 'OUT_OF_PHYSICAL_RANGE'
            }
          }
          continue
        }

        $samples[$identifier].Values += $value
      }
    }

    foreach ($identifier in $samples.Keys) {
      $entry = $samples[$identifier]
      $values = @($entry.Values)
      if ($values.Count -eq 0) { continue }

      $reading = @{
        label = if ([string]::IsNullOrWhiteSpace($entry.Label)) { 'Temperature' } else { $entry.Label }
        celsius = [Math]::Round($values[$values.Count - 1], 1)
        criticalCelsius = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'seuil constructeur non expose par le provider'
        category = Get-ThermalCategory -HardwareType $entry.HardwareType -SensorName $entry.Label
        source = $provider.Source
        scope = $scope
        quality = 'MEASURED'
        sampleCount = $values.Count
      }
      if (-not [string]::IsNullOrWhiteSpace($entry.Device)) { $reading.device = $entry.Device }

      # Les statistiques n'existent qu'a partir de deux releves : sur un releve
      # unique, les publier reviendrait a repeter la valeur courante sous un nom
      # qui promet une observation dans la duree.
      if ($values.Count -gt 1) {
        $measured = $values | Measure-Object -Minimum -Maximum -Average
        $reading.minCelsius = [Math]::Round($measured.Minimum, 1)
        $reading.maxCelsius = [Math]::Round($measured.Maximum, 1)
        $reading.averageCelsius = [Math]::Round($measured.Average, 1)
      }

      $temperatures += $reading
    }

    foreach ($sensor in $sensors) {
      $name = Get-StringOrUnknown -Value $sensor.Name -Reason 'UNKNOWN'
      switch ([string]$sensor.SensorType) {
        'Fan' {
          $fans += @{
            label = $name
            rpm = Get-PositiveIntOrUnknown -Value $sensor.Value -Reason 'UNKNOWN'
          }
        }
        'Voltage' {
          $voltages += @{
            label = $name
            volts = [Math]::Round([double]$sensor.Value, 3)
          }
        }
        'Power' {
          $powers += @{
            label = $name
            watts = [Math]::Round([double]$sensor.Value, 2)
          }
        }
      }
    }

    if ($temperatures.Count -gt 0) { $sources += $provider.Source }
    break
  }

  # Deuxieme rideau : les zones ACPI. Elles ne sont interrogees que si aucun
  # provider materiel n'a rendu de temperature — les doubler produirait deux
  # lignes pour une meme sonde, sans moyen de savoir laquelle croire.
  if ($temperatures.Count -eq 0) {
    $acpi = Get-AcpiThermalReadings -Scope $scope -Passes $passes
    $probed += $acpi.probed
    $temperatures += $acpi.readings
    $discarded += $acpi.discarded
    if (@($acpi.readings).Count -gt 0) { $sources += 'MSAcpi_ThermalZoneTemperature' }
  }

  # Ce que le stockage a depose pendant sa propre collecte : sondes SMART/NVMe,
  # invisibles depuis les providers materiels quand ceux-ci sont absents.
  foreach ($reading in @(Get-ThermalReadingList)) {
    $temperatures += $reading
    $probed++
    if ($reading.ContainsKey('source') -and $sources -notcontains $reading.source) {
      $sources += $reading.source
    }
  }

  $unavailableReason = $null
  $suggestedTool = $null
  if ($temperatures.Count -eq 0) {
    if ($scope -eq 'HYPERVISOR_HOST') {
      $unavailableReason = 'VIRTUALIZED'
    } else {
      $unavailableReason = 'TOOL_MISSING'
      $suggestedTool = 'LibreHardwareMonitor'
    }
    Add-CollectionIssue -Section 'sensors' -Severity 'warning' `
      -Message 'Aucun provider LibreHardwareMonitor/OpenHardwareMonitor accessible : capteurs Windows non releves.' `
      -Source 'capteurs' -Reason 'NOT_AVAILABLE'
  }

  $collection = @{
    probed = $probed
    usable = $temperatures.Count
    discarded = @($discarded).Count
    sources = @($sources)
    sampleCount = $passes
  }
  if ($passes -gt 1) { $collection.sampleIntervalMs = 1000 }
  if (@($discarded).Count -gt 0) { $collection.discardedReadings = @($discarded) }
  if ($null -ne $unavailableReason) { $collection.unavailableReason = $unavailableReason }
  if ($null -ne $suggestedTool) { $collection.suggestedTool = $suggestedTool }

  return @{
    temperatures = $temperatures
    temperatureCollection = $collection
    fans = $fans
    voltages = $voltages
    powers = $powers
  }
}
