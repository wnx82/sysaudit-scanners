# SysAudit Windows — peripheriques et pilotes.
#
# Cette section manquait entierement au scanner Windows. Consequence mesurable :
# six controles du moteur d'analyse — peripherique sans pilote, peripherique en
# erreur, peripherique desactive, pilote non signe, mise a jour de pilote, lien
# PCIe negocie sous sa capacite — sortaient « non evalues » sur **toute** machine
# Windows, sans qu'aucun rapport ne dise pourquoi. Le scanner Linux les remplit
# depuis `lspci`/`lsusb` ; l'equivalent Windows est CIM, et il repond aussi bien.
#
# Deux sources, et une seule question chacune :
#
#   - `Win32_PnPEntity` : ce qui est branche, et dans quel etat le gestionnaire
#     de peripheriques le declare. C'est `ConfigManagerErrorCode` qui porte
#     l'etat, pas `Status` — ce dernier vaut « OK » sur un peripherique dont le
#     pilote a echoue ;
#   - `Win32_PnPSignedDriver` : quel pilote sert quel peripherique, sa version,
#     sa date, son fichier INF et sa signature.
#
# Ce qui n'est **pas** fait ici, et pourquoi :
#
#   - aucune version « disponible » n'est renseignee. L'etablir exigerait
#     d'interroger le constructeur, ce qu'un scanner hors ligne ne fait pas. Le
#     statut reste donc `CURRENT` ou `UNKNOWN`, jamais `UPDATE_AVAILABLE` : la
#     regle `DRV-005` refuse de recommander une mise a jour sans source, et lui
#     en fabriquer une serait exactement l'invention que le produit s'interdit ;
#   - la largeur des liens PCIe n'est pas rapportee. Windows ne l'expose pas par
#     CIM, et la deduire du modele de carte serait une supposition. La section
#     `link` reste donc absente sous Windows, et `PRF-005` le dit.

<#
.SYNOPSIS
  Etat d'un peripherique, deduit du code d'erreur du gestionnaire.

.DESCRIPTION
  Fonction pure, testable hors Windows.

  `ConfigManagerErrorCode` est la seule source fiable : `Status` vaut « OK » sur
  un peripherique dont le pilote a echoue, et `Present` ne dit rien de son
  fonctionnement. Les codes retenus sont ceux documentes par Microsoft, et seuls
  ceux-la sont traduits — un code inconnu devient `UNKNOWN` plutot que d'etre
  range au jugé dans la categorie la plus proche.

  Un code absent rend `UNKNOWN` et non `OK` : sur un peripherique dont l'etat
  n'a pas pu etre lu, repondre « OK » fabriquerait un satisfecit.
#>
function Get-DeviceStatusFromErrorCode {
  param($Code)

  if ($null -eq $Code -or ([string]$Code) -eq '') { return 'UNKNOWN' }

  $value = 0
  if (-not [int]::TryParse([string]$Code, [ref]$value)) { return 'UNKNOWN' }

  switch ($value) {
    0 { return 'OK' }
    # 22 : desactive par l'utilisateur. 28 : aucun pilote installe.
    22 { return 'DISABLED' }
    28 { return 'DRIVER_MISSING' }
    # 1 : peripherique mal configure — Windows n'a pas su l'identifier.
    1 { return 'UNKNOWN_DEVICE' }
    # 10, 19, 31, 37, 39, 43 : le pilote est la et l'initialisation a echoue.
    10 { return 'DRIVER_ERROR' }
    19 { return 'DRIVER_ERROR' }
    31 { return 'DRIVER_ERROR' }
    37 { return 'DRIVER_ERROR' }
    39 { return 'DRIVER_ERROR' }
    43 { return 'DRIVER_ERROR' }
    default { return 'UNKNOWN' }
  }
}

<#
.SYNOPSIS
  Bus d'un peripherique, deduit de son identifiant materiel.

.DESCRIPTION
  Fonction pure, testable hors Windows.

  L'identifiant Windows porte son bus en prefixe (`PCI\VEN_8086&DEV_1533`,
  `USB\VID_046D&PID_C52B`). Tout le reste — peripheriques racine, logiciels,
  HID derives — va dans `OTHER` : les ranger dans PCI gonflerait un inventaire
  cense decrire du materiel enfichable.
#>
function Get-DeviceBusFromHardwareId {
  param([string]$HardwareId)

  if ([string]::IsNullOrWhiteSpace($HardwareId)) { return 'OTHER' }

  $prefix = ($HardwareId.Trim() -split '\\')[0]
  switch ($prefix.ToUpperInvariant()) {
    'PCI' { return 'PCI' }
    'PCIE' { return 'PCIE' }
    'USB' { return 'USB' }
    'USBSTOR' { return 'USB' }
    default { return 'OTHER' }
  }
}

<#
.SYNOPSIS
  Identifiants constructeur et produit extraits d'un identifiant materiel.

.DESCRIPTION
  Fonction pure, testable hors Windows.

  Rend une table a deux clefs, `vendorId` et `deviceId`, vides quand
  l'identifiant ne suit pas la forme attendue. Elles servent a chercher un
  pilote : c'est la seule base fiable, un nom commercial approximatif ne suffit
  pas.
#>
function Get-DeviceIdentifiers {
  param([string]$HardwareId)

  $result = @{ vendorId = ''; deviceId = '' }
  if ([string]::IsNullOrWhiteSpace($HardwareId)) { return $result }

  $text = $HardwareId.ToUpperInvariant()
  if ($text -match 'VEN_([0-9A-F]{4})') { $result.vendorId = $Matches[1] }
  elseif ($text -match 'VID_([0-9A-F]{4})') { $result.vendorId = $Matches[1] }

  if ($text -match 'DEV_([0-9A-F]{4})') { $result.deviceId = $Matches[1] }
  elseif ($text -match 'PID_([0-9A-F]{4})') { $result.deviceId = $Matches[1] }

  return $result
}

<#
.SYNOPSIS
  Date de pilote convertie en date ISO.

.DESCRIPTION
  Fonction pure, testable hors Windows.

  CIM rend soit un `DateTime` .NET, soit une chaine CIM (`20240115000000.000000+000`).
  Les deux sont acceptees ; tout le reste rend `$null`, pour que le champ soit
  absent plutot que faux.
#>
function Convert-DriverDate {
  param($Value)

  if ($null -eq $Value) { return $null }
  if ($Value -is [datetime]) { return $Value.ToString('yyyy-MM-dd') }

  $text = ([string]$Value).Trim()
  if ($text -match '^(\d{4})(\d{2})(\d{2})') {
    $candidate = $Matches[1] + '-' + $Matches[2] + '-' + $Matches[3]
    $parsed = [datetime]::MinValue
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $styles = [System.Globalization.DateTimeStyles]::None
    if ([datetime]::TryParseExact($candidate, 'yyyy-MM-dd', $culture, $styles, [ref]$parsed)) {
      return $candidate
    }
  }

  return $null
}

<#
.SYNOPSIS
  Un enregistrement CIM de peripherique converti au format du rapport.

.DESCRIPTION
  Fonction pure, testable hors Windows : elle ne juge qu'un objet deja lu.

  Le nom du pilote vient de la table des pilotes signes, passee en second
  argument et indexee par identifiant de peripherique. Sans correspondance, le
  champ porte un marqueur d'absence : un peripherique dont on ignore le pilote
  n'est pas un peripherique sans pilote — c'est `ConfigManagerErrorCode` qui le
  dit, et lui seul.
#>
function ConvertTo-DeviceRecord {
  param(
    $Entity,
    [hashtable]$DriversByDeviceId = @{}
  )

  if ($null -eq $Entity) { return $null }

  $hardwareId = ''
  if ($null -ne $Entity.DeviceID) { $hardwareId = ([string]$Entity.DeviceID).Trim() }

  $identifiers = Get-DeviceIdentifiers -HardwareId $hardwareId
  $driverName = ''
  if ($hardwareId -ne '' -and $DriversByDeviceId.ContainsKey($hardwareId)) {
    $driverName = [string]$DriversByDeviceId[$hardwareId]
  }

  return @{
    bus = Get-DeviceBusFromHardwareId -HardwareId $hardwareId
    hardwareId = Get-StringOrUnknown -Value $hardwareId -Reason 'UNKNOWN' -Detail 'identifiant materiel non rapporte'
    vendorId = Get-StringOrUnknown -Value $identifiers.vendorId -Reason 'NOT_APPLICABLE' -Detail 'identifiant sans champ constructeur'
    deviceId = Get-StringOrUnknown -Value $identifiers.deviceId -Reason 'NOT_APPLICABLE' -Detail 'identifiant sans champ produit'
    vendor = Get-StringOrUnknown -Value $Entity.Manufacturer -Reason 'UNKNOWN' -Detail 'constructeur non rapporte'
    name = Get-StringOrUnknown -Value $Entity.Name -Reason 'UNKNOWN' -Detail 'nom non rapporte'
    class = Get-StringOrUnknown -Value $Entity.PNPClass -Reason 'UNKNOWN' -Detail 'classe non rapportee'
    driver = Get-StringOrUnknown -Value $driverName -Reason 'NOT_AVAILABLE' -Detail 'aucun pilote signe associe a ce peripherique'
    status = Get-DeviceStatusFromErrorCode -Code $Entity.ConfigManagerErrorCode
    address = Get-StringOrUnknown -Value $Entity.PNPDeviceID -Reason 'UNKNOWN' -Detail 'emplacement non rapporte'
  }
}

<#
.SYNOPSIS
  Un enregistrement CIM de pilote converti au format du rapport.

.DESCRIPTION
  Fonction pure, testable hors Windows.

  Le statut ne vaut jamais `UPDATE_AVAILABLE` : l'affirmer exigerait une version
  publiee par le constructeur, qu'aucun scanner hors ligne ne connait. Un pilote
  correctement installe est `CURRENT` — ce qui dit « il fonctionne », pas « il
  est le plus recent ».
#>
function ConvertTo-DriverRecord {
  param($Signed)

  if ($null -eq $Signed) { return $null }

  $date = Convert-DriverDate -Value $Signed.DriverDate

  # Une signature non rapportee n'est pas une signature absente : le marqueur
  # laisse `DRV-004` se taire au lieu de signaler un pilote non signe.
  #
  # La valeur est calculee **avant** la table, et non par un `if` place dans
  # l'initialiseur : Windows PowerShell 5.1 ne sait pas assigner depuis une
  # instruction `if`, et une bonne part du parc Windows tourne encore dessus.
  # Le scanner y serait mort au chargement du fichier, sans qu'aucun test sous
  # PowerShell 7 ne le voie.
  $signedValue = New-Unknown -Reason 'UNKNOWN' -Detail 'etat de signature non rapporte'
  if ($null -ne $Signed.IsSigned) { $signedValue = [bool]$Signed.IsSigned }

  $record = @{
    device = Get-StringOrUnknown -Value $Signed.DeviceName -Reason 'UNKNOWN' -Detail 'peripherique non nomme'
    hardwareId = Get-StringOrUnknown -Value $Signed.DeviceID -Reason 'UNKNOWN' -Detail 'identifiant materiel non rapporte'
    vendor = Get-StringOrUnknown -Value $Signed.Manufacturer -Reason 'UNKNOWN' -Detail 'constructeur non rapporte'
    name = Get-StringOrUnknown -Value $Signed.DeviceName -Reason 'UNKNOWN' -Detail 'nom non rapporte'
    version = Get-StringOrUnknown -Value $Signed.DriverVersion -Reason 'UNKNOWN' -Detail 'version non rapportee'
    provider = Get-StringOrUnknown -Value $Signed.DriverProviderName -Reason 'UNKNOWN' -Detail 'editeur non rapporte'
    infName = Get-StringOrUnknown -Value $Signed.InfName -Reason 'UNKNOWN' -Detail 'fichier INF non rapporte'
    signed = $signedValue
    status = 'CURRENT'
  }

  if ($null -eq $date) {
    $record.date = New-Unknown -Reason 'UNKNOWN' -Detail 'date de pilote illisible'
  } else {
    $record.date = $date
  }

  return $record
}

<#
.SYNOPSIS
  Inventaire des peripheriques et des pilotes.

.DESCRIPTION
  Interroge CIM. Rend une table a deux clefs, `devices` et `drivers`, prete a
  etre posee sur le rapport.

  Les listes sont bornees : le schema plafonne a 512 peripheriques par bus et le
  scanner s'y tient, plutot que de produire un document que le serveur refusera.
  Une machine qui depasse laisse une issue de collecte disant ce qui a ete
  tronque — un tableau tronque presente comme complet se lirait comme un
  inventaire.
#>
<#
.SYNOPSIS
  Delai accorde a l'inventaire des pilotes, en secondes.

.DESCRIPTION
  Genereux, parce que la lenteur de `Win32_PnPSignedDriver` est normale et non
  pathologique : couper a trente secondes priverait d'inventaire la majorite des
  machines. Le delai n'est pas la pour accelerer quoi que ce soit, mais pour
  garantir qu'un WMI reellement bloque ne coute pas le rapport.

  `SYSAUDIT_DRIVER_TIMEOUT` permet de le reduire, notamment pour les tests.
#>
function Get-DriverInventoryTimeoutSeconds {
  $requested = [Environment]::GetEnvironmentVariable('SYSAUDIT_DRIVER_TIMEOUT')
  $value = 300
  if (-not [string]::IsNullOrWhiteSpace($requested)) {
    $parsed = 0
    if ([int]::TryParse($requested, [ref]$parsed) -and $parsed -ge 5 -and $parsed -le 1800) {
      $value = $parsed
    }
  }
  return $value
}

<#
.SYNOPSIS
  Enumere les pilotes signes, sans pouvoir bloquer indefiniment.

.DESCRIPTION
  `-OperationTimeoutSec` borne l'operation WMI elle-meme : c'est le mecanisme
  prevu pour cela, et il evite d'ouvrir un `Job` — donc un second processus
  PowerShell — pour surveiller une lecture.

  Rend `$null` quand la lecture echoue, et non un tableau vide : une liste vide
  se lirait comme « cette machine n'a aucun pilote », ce qui n'arrive jamais. Le
  motif est distingue — depassement de delai ou erreur — parce qu'ils
  n'appellent pas la meme suite : le premier se retente sur une machine moins
  chargee, le second demande a regarder WMI.
#>
function Get-SignedDriversBounded {
  param(
    [Parameter(Mandatory = $true)][string[]]$Properties,
    [Parameter(Mandatory = $true)][int]$TimeoutSeconds
  )

  try {
    return @(Get-CimInstance -ClassName 'Win32_PnPSignedDriver' -Property $Properties `
        -OperationTimeoutSec $TimeoutSeconds -ErrorAction Stop)
  } catch {
    $message = [string]$_.Exception.Message
    $reason = if ($message -match 'timeout|delai|expir') { 'TIMEOUT' } else { 'COLLECTOR_ERROR' }
    Add-CollectionIssue -Section 'drivers' -Severity 'warning' `
      -Message ('Inventaire des pilotes signes indisponible : ' + $message) `
      -Source 'Win32_PnPSignedDriver' -Reason $reason
    return $null
  }
}

function Get-DeviceInventory {
  $devices = @{ pci = @(); usb = @(); other = @() }
  $drivers = @()
  $driversByDeviceId = @{}

  # `Win32_PnPSignedDriver` est la classe la plus lente de tout le scanner, et de
  # loin : l'enumerer fait parcourir le magasin de pilotes entier, ce qui prend
  # une a plusieurs **minutes** sur une installation ordinaire. C'est ce qui
  # faisait paraitre l'audit bloque a 53 % sur l'etape « Peripheriques ».
  #
  # Trois precautions, et aucune ne consiste a renoncer a l'inventaire :
  #
  # 1. **L'attente est annoncee.** Une etape qui dure trois minutes sans rien
  #    dire est indiscernable d'un plantage.
  # 2. **Seules les proprietes utilisees sont demandees.** Sans `-Property`, WMI
  #    materialise aussi `HardWareID`, `Signer` et `ClassGuid` pour chaque
  #    pilote, qu'aucune ligne de ce fichier ne lit.
  # 3. **La lecture est bornee.** Au-dela du delai, la section des pilotes est
  #    declaree non collectee **avec sa raison**, et l'audit continue : un
  #    inventaire de pilotes ne vaut pas de perdre le rapport entier.
  Write-ConsoleStep -Message 'Inventaire des pilotes signes — cette lecture prend souvent plusieurs minutes.'

  $driverProperties = @(
    'DeviceID', 'DeviceName', 'DriverVersion', 'DriverProviderName',
    'DriverName', 'InfName', 'DriverDate', 'IsSigned', 'Manufacturer'
  )
  $signedDrivers = Get-SignedDriversBounded -Properties $driverProperties `
    -TimeoutSeconds (Get-DriverInventoryTimeoutSeconds)

  # `$null` signale une lecture qui n'a pas abouti ; la raison est deja
  # consignee par `Get-SignedDriversBounded`. L'audit continue sans inventaire de
  # pilotes plutot que de perdre le rapport entier.
  if ($null -ne $signedDrivers) {
    foreach ($signed in $signedDrivers) {
      $record = ConvertTo-DriverRecord -Signed $signed
      if ($null -eq $record) { continue }
      $drivers += $record

      if ($null -ne $signed.DeviceID -and $null -ne $signed.DriverName) {
        $driversByDeviceId[([string]$signed.DeviceID).Trim()] = [string]$signed.DriverName
      } elseif ($null -ne $signed.DeviceID -and $null -ne $signed.InfName) {
        $driversByDeviceId[([string]$signed.DeviceID).Trim()] = [string]$signed.InfName
      }
    }
  }

  try {
    foreach ($entity in @(Get-CimInstance -ClassName 'Win32_PnPEntity' -ErrorAction Stop)) {
      $record = ConvertTo-DeviceRecord -Entity $entity -DriversByDeviceId $driversByDeviceId
      if ($null -eq $record) { continue }

      switch ($record.bus) {
        'PCI' { if ($devices.pci.Count -lt 512) { $devices.pci += $record } }
        'PCIE' { if ($devices.pci.Count -lt 512) { $devices.pci += $record } }
        'USB' { if ($devices.usb.Count -lt 512) { $devices.usb += $record } }
        default { if ($devices.other.Count -lt 512) { $devices.other += $record } }
      }
    }
  } catch {
    Add-CollectionIssue -Section 'devices' -Severity 'warning' `
      -Message ('Inventaire des peripheriques illisible : ' + $_.Exception.Message) `
      -Source 'Win32_PnPEntity' -Reason 'COLLECTOR_ERROR'
    return $null
  }

  # Le plafond du schema atteint : le dire, plutot que de laisser croire que la
  # machine n'a que 512 peripheriques sur ce bus.
  foreach ($bus in @('pci', 'usb', 'other')) {
    if ($devices[$bus].Count -ge 512) {
      Add-CollectionIssue -Section 'devices' -Severity 'warning' `
        -Message ('Inventaire ' + $bus + ' tronque a 512 entrees, plafond du schema.') `
        -Source 'Win32_PnPEntity' -Reason 'COLLECTOR_ERROR'
    }
  }

  if ($drivers.Count -gt 512) { $drivers = $drivers[0..511] }

  return @{ devices = $devices; drivers = $drivers }
}
