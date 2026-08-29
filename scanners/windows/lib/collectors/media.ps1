# SysAudit Windows — audio local et démarrage automatique.

function Get-AudioSection {
  $devices = @()
  Add-CollectionProvenance -Path 'audio.devices' -Source 'Win32_SoundDevice' -Method 'CIM' -Precision 'peripherique'

  if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
    Add-CollectionIssue -Section 'audio' -Severity 'warning' `
      -Message 'Get-CimInstance indisponible dans cet environnement PowerShell.' -Source 'Win32_SoundDevice' -Reason 'NOT_AVAILABLE'
    return @{ devices = $devices }
  }

  $soundDevices = Get-CimInstance Win32_SoundDevice -ErrorAction SilentlyContinue

  foreach ($device in $soundDevices) {
    $devices += @{
      name = Get-StringOrUnknown -Value $device.Name -Reason 'UNKNOWN'
      vendor = Get-StringOrUnknown -Value $device.Manufacturer -Reason 'UNKNOWN'
      driver = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'pilote audio non expose par Win32_SoundDevice'
      stack = 'wdm'
      kind = 'PLAYBACK_CAPTURE'
      state = if ($device.Status -eq 'OK') { 'ENABLED' } else { 'UNKNOWN' }
      default = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'peripherique par defaut non expose par Win32_SoundDevice'
    }
  }

  return @{ devices = $devices }
}

function Get-StartupSection {
  Add-CollectionProvenance -Path 'startup.items' -Source 'Windows Run keys' -Method 'registre' -Precision 'entree'

  $items = @()
  $seen = @{}
  $sources = @(
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Scope = 'SYSTEM'; Kind = 'REGISTRY' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'; Scope = 'SYSTEM'; Kind = 'REGISTRY' },
    @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Scope = 'USER'; Kind = 'REGISTRY' },
    @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'; Scope = 'USER'; Kind = 'REGISTRY' }
  )

  foreach ($source in $sources) {
    if (-not (Get-Command Get-ItemProperty -ErrorAction SilentlyContinue)) {
      Add-CollectionIssue -Section 'startup' -Severity 'warning' `
        -Message 'Lecture du registre indisponible dans cet environnement PowerShell.' -Source $source.Path -Reason 'NOT_AVAILABLE'
      break
    }
    if (-not (Test-Path $source.Path)) { continue }

    try {
      $properties = Get-ItemProperty -Path $source.Path -ErrorAction Stop
      foreach ($property in $properties.PSObject.Properties) {
        if ($property.Name -in @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')) {
          continue
        }

        $key = $source.Path + '|' + $property.Name
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true

        $items += @{
          name = Get-StringOrUnknown -Value $property.Name -Reason 'UNKNOWN'
          kind = $source.Kind
          scope = $source.Scope
          enabled = $true
          command = Get-StringOrUnknown -Value $property.Value -Reason 'UNKNOWN'
          location = $source.Path
        }
      }
    } catch {
      Add-CollectionIssue -Section 'startup' -Severity 'warning' `
        -Message ('Lecture du registre impossible : ' + $_.Exception.Message) -Source $source.Path -Reason 'NOT_AVAILABLE'
    }
  }

  return @{ items = $items }
}
