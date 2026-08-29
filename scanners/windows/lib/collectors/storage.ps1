# SysAudit Windows — disques et volumes.

<#
.SYNOPSIS
  Support, bus et protocole d'un disque, lus separement.

.DESCRIPTION
  `Win32_DiskDrive` ne sait pas repondre a ces questions, et c'est la cause du
  defaut que cette fonction remplace. La classe presente les disques derriere
  la pile de stockage : un NVMe y porte `InterfaceType = SCSI`, et
  `MediaType = Fixed hard disk media` -- une phrase qui dit « fixe », pas
  « mecanique ». L'ancienne heuristique en concluait `HDD`, puis affichait
  « HDD - SCSI » sur un SSD NVMe. Faux deux fois, avec l'aplomb d'une mesure.

  `Get-PhysicalDisk` (MSFT_PhysicalDisk) repond, lui, aux bonnes questions :
  `MediaType` vaut `SSD`, `HDD` ou `Unspecified`, et `BusType` nomme le bus
  reel, NVMe compris. C'est donc la source, et l'appariement se fait par numero
  de disque -- seule cle commune avec `Win32_DiskDrive.Index`.

  Sans cette applet -- Windows 7, ou service de stockage arrete -- rien n'est
  devine : le support reste `UNKNOWN`. Un disque non identifie est une lacune
  visible ; un disque mal identifie est une erreur invisible.
#>
function Get-PhysicalDiskFactsByNumber {
  $byNumber = @{}
  if (-not (Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue)) { return $byNumber }

  try {
    foreach ($physical in @(Get-PhysicalDisk -ErrorAction Stop)) {
      $number = [string]$physical.DeviceId
      if ([string]::IsNullOrWhiteSpace($number)) { continue }

      $byNumber[$number] = @{
        mediaType = switch ([string]$physical.MediaType) {
          'SSD' { 'SSD' }
          'HDD' { 'HDD' }
          # `Unspecified` est la reponse d'un disque virtuel ou d'un
          # controleur qui ne publie rien : elle ne vaut pas `HDD`.
          default { '' }
        }
        busType = switch -Regex ([string]$physical.BusType) {
          '^NVMe$' { 'NVME' }
          '^SATA$' { 'SATA' }
          '^SAS$' { 'SAS' }
          '^SCSI$' { 'SCSI' }
          '^ATA$' { 'ATA' }
          '^USB$' { 'USB' }
          '^RAID$' { 'RAID' }
          '^SD$' { 'SD' }
          '^MMC$' { 'MMC' }
          '^Fibre Channel$' { 'FIBRE_CHANNEL' }
          '^iSCSI$' { 'ISCSI' }
          '^(Virtual|File Backed Virtual|Storage Spaces)$' { 'VIRTUAL' }
          default { '' }
        }
        spindleSpeed = $physical.SpindleSpeed
      }
    }
  } catch {
    Add-CollectionIssue -Section 'storage.disks' -Severity 'info' `
      -Message ('Nature des supports non lue : ' + $_.Exception.Message) `
      -Source 'Get-PhysicalDisk' -Reason 'NOT_AVAILABLE'
  }

  return $byNumber
}

<#
.SYNOPSIS
  Categorie historique d'un disque, derivee des faits separes.

.DESCRIPTION
  `kind` melange support, bus et protocole dans un seul champ. Il est conserve
  parce que tout le rendu s'y appuie, mais il n'est plus **devine** : il se
  deduit de `mediaType` et `busType`, qui viennent chacun de leur source.

  L'ordre suit ce que le lecteur cherche en premier. Un NVMe est d'abord un
  NVMe, quel que soit son support -- ils sont tous a memoire flash. Un disque
  dont le bus est connu mais le support inconnu ne devient jamais `HDD` : il
  reste `UNKNOWN`, et le rapport le dit.
#>
function Get-DiskKindFromFacts {
  param([string]$MediaType, [string]$BusType, [string]$Model)

  if ($BusType -eq 'NVME') { return 'NVME' }
  if ($BusType -eq 'VIRTUAL') { return 'VIRTUAL' }
  if ($MediaType -eq 'SSD') { return 'SSD' }
  if ($MediaType -eq 'HDD') { return 'HDD' }
  if ($BusType -eq 'USB') { return 'USB' }
  if ($BusType -eq 'SD' -or $BusType -eq 'MMC') { return 'SD' }
  if ($BusType -eq 'SAS') { return 'SAS' }
  # Le nom du modele est la derniere ressource, et seulement pour ce qu'il
  # nomme explicitement : un disque de machine virtuelle s'annonce.
  if ($Model -match 'Virtual|VBOX|VMware|QEMU') { return 'VIRTUAL' }
  return 'UNKNOWN'
}

<#
.SYNOPSIS
  Une optimisation periodique des disques est-elle planifiee ?

.DESCRIPTION
  La notion est **globale**, comme dans le schema : c'est une tache planifiee,
  pas une propriete du materiel. Sous Windows, « Optimiser les lecteurs »
  (`ScheduledDefrag`) declenche le retrim des disques a memoire flash.

  Une tache absente ou illisible laisse un marqueur : « non planifiee » et
  « impossible a verifier » ne disent pas la meme chose.
#>
function Get-TrimScheduled {
  if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) {
    return (New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'Get-ScheduledTask indisponible')
  }

  try {
    $task = Get-ScheduledTask -TaskPath '\Microsoft\Windows\Defrag\' -TaskName 'ScheduledDefrag' -ErrorAction Stop
    return ([string]$task.State -ne 'Disabled')
  } catch {
    return (New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'tache d''optimisation introuvable')
  }
}

<#
.SYNOPSIS
  Identifiant de volume par lettre de lecteur.

.DESCRIPTION
  `Win32_Volume.DeviceID` rend le GUID de volume (`\\?\Volume{...}\`), qui est
  l'equivalent Windows de l'UUID de systeme de fichiers sous Linux : il designe
  le contenu, et suit le disque d'une machine a l'autre.

  L'indexation se fait par lettre de lecteur, seule cle commune avec
  `Win32_LogicalDisk` d'ou viennent les volumes du rapport. Un volume monte sans
  lettre n'apparait donc pas ici -- il n'apparait pas non plus dans le rapport.
#>
<#
.SYNOPSIS
  Etat BitLocker par lettre de lecteur.

.DESCRIPTION
  `encrypted` et `encryptionType` partaient en `NOT_AVAILABLE` sur toute
  partition Windows, ce qui rendait `SEC-014` — « Aucun chiffrement de disque
  detecte » — non evaluable la ou la question se pose le plus : un portable.

  `Get-BitLockerVolume` **exige l'elevation** et repond « Acces refuse » sans
  elle. C'est un motif exact, et actionnable : `PERMISSION_DENIED` affiche
  « relancer l'audit en administrateur », la ou « donnee absente » n'apprend
  rien. Le distinguer d'un volume reellement non chiffre est tout l'objet de
  cette fonction : les deux se ressemblent, et l'un est une lacune de lecture
  quand l'autre est un defaut de la machine.

  Rend une table lettre -> etat, ou `$null` si rien n'a pu etre lu, auquel cas
  l'appelant pose le marqueur qui convient.
#>
function Get-BitLockerStateByLetter {
  $volumes = @()
  try {
    $volumes = @(Get-BitLockerVolume -ErrorAction Stop)
  } catch {
    # `Get-BitLockerVolume` n'existe pas sur les editions Familiales et refuse
    # sans elevation. Les deux se lisent sur le message, faute d'un type
    # d'exception distinct.
    $message = [string]$_.Exception.Message
    $denied = $message -match 'refus|denied|Access is denied'
    Add-CollectionIssueOnce -Section 'storage.partitions' -Severity 'warning' `
      -Message ('Etat BitLocker non lu : ' + $message) -Source 'Get-BitLockerVolume' `
      -Reason $(if ($denied) { 'PERMISSION_DENIED' } else { 'NOT_AVAILABLE' })
    return $null
  }

  $byLetter = @{}
  foreach ($volume in $volumes) {
    $mount = [string]$volume.MountPoint
    if ([string]::IsNullOrWhiteSpace($mount)) { continue }
    $letter = $mount.TrimEnd('\')

    # `VolumeStatus` dit l'etat du chiffrement, `ProtectionStatus` celui de la
    # protection. Un volume « FullyEncrypted » dont la protection est suspendue
    # reste chiffre : c'est bien la premiere qui repond a la question posee.
    $status = [string]$volume.VolumeStatus
    $encrypted = ($status -eq 'FullyEncrypted' -or $status -eq 'EncryptionInProgress')

    $byLetter[$letter] = @{
      encrypted = [bool]$encrypted
      type = if ($encrypted) { 'BitLocker' } else { $null }
      status = $status
    }
  }

  Add-CollectionProvenance -Path 'storage.disks[].partitions[].encrypted' `
    -Source 'Get-BitLockerVolume' -Method 'applet de commande' -Precision 'volume'

  return $byLetter
}

function Get-VolumeIdentifiersByLetter {
  $byLetter = @{}

  try {
    foreach ($volume in @(Get-CimInstance Win32_Volume -ErrorAction Stop)) {
      $letter = ([string]$volume.DriveLetter).Trim()
      if ([string]::IsNullOrWhiteSpace($letter)) { continue }
      if ($byLetter.ContainsKey($letter)) { continue }
      $byLetter[$letter] = [string]$volume.DeviceID
    }
  } catch {
    Add-CollectionIssue -Section 'storage.partitions' -Severity 'info' `
      -Message ('Identifiants de volumes non lus : ' + $_.Exception.Message) `
      -Source 'Win32_Volume' -Reason 'NOT_AVAILABLE'
  }

  return $byLetter
}

<#
.SYNOPSIS
  GUID de partition GPT par lettre de lecteur.

.DESCRIPTION
  Distinct du GUID de volume : reformater une partition change le second sans
  toucher au premier. Une table MBR n'en a aucun, et `Get-Partition` rend alors
  une chaine vide -- ce n'est pas une lecture ratee, c'est une table qui ne
  porte pas cette notion.
#>
function Get-PartitionIdentifiersByLetter {
  $byLetter = @{}
  if (-not (Get-Command Get-Partition -ErrorAction SilentlyContinue)) { return $byLetter }

  try {
    foreach ($partition in @(Get-Partition -ErrorAction Stop)) {
      $letter = ([string]$partition.DriveLetter).Trim()
      if ([string]::IsNullOrWhiteSpace($letter)) { continue }
      $guid = ([string]$partition.Guid).Trim()
      if ([string]::IsNullOrWhiteSpace($guid)) { continue }
      $key = $letter + ':'
      if ($byLetter.ContainsKey($key)) { continue }
      $byLetter[$key] = $guid
    }
  } catch {
    Add-CollectionIssue -Section 'storage.partitions' -Severity 'info' `
      -Message ('Identifiants de partitions non lus : ' + $_.Exception.Message) `
      -Source 'Get-Partition' -Reason 'NOT_AVAILABLE'
  }

  return $byLetter
}

<#
.SYNOPSIS
  World Wide Name par index de disque physique.

.DESCRIPTION
  `Get-Disk` publie un identifiant unique et **le format qui le decrit**.
  Seuls `EUI64` et `FCPHName` sont des WWN ; `VendorSpecific` est une chaine
  propre au constructeur, souvent le numero de serie recopie, et l'annoncer
  comme un WWN donnerait un identifiant normalise a une valeur qui ne l'est pas.

  La cle est le numero de disque, seul lien fiable avec `Win32_DiskDrive.Index`.
#>
function Get-DiskWwnByIndex {
  $byIndex = @{}
  if (-not (Get-Command Get-Disk -ErrorAction SilentlyContinue)) { return $byIndex }

  try {
    foreach ($disk in @(Get-Disk -ErrorAction Stop)) {
      $format = ([string]$disk.UniqueIdFormat).Trim()
      if ($format -ne 'EUI64' -and $format -ne 'FCPHName') { continue }
      $uniqueId = ([string]$disk.UniqueId).Trim()
      if ([string]::IsNullOrWhiteSpace($uniqueId)) { continue }
      $byIndex[[string]$disk.Number] = $uniqueId
    }
  } catch {
    Add-CollectionIssue -Section 'storage.disks' -Severity 'info' `
      -Message ('Identifiants mondiaux de disques non lus : ' + $_.Exception.Message) `
      -Source 'Get-Disk' -Reason 'NOT_AVAILABLE'
  }

  return $byIndex
}

<#
.SYNOPSIS
  Redondance deduite d'un mode de resilience Storage Spaces.

.DESCRIPTION
  Fonction pure, separee pour etre testable ailleurs que sur une machine
  equipee d'un espace de stockage — c'est-a-dire a peu pres partout.

  Rend `$true`, `$false` ou `$null`. `$null` n'est pas « non redondant » : c'est
  « je ne sais pas ». Le schema est explicite sur ce point — mieux vaut ne rien
  dire que d'affirmer a tort qu'un ensemble est protege.

  `Simple` repartit sans copie : la perte d'un disque perd l'ensemble.
  `Mirror` et `Parity` tolerent la perte d'un membre. Un mode inconnu — un
  futur mode, ou un nom localise — ne se devine pas.
#>
function Get-ResiliencyRedundancy {
  param([string]$Resiliency)

  switch ($Resiliency.Trim().ToLowerInvariant()) {
    'simple' { return $false }
    'mirror' { return $true }
    'parity' { return $true }
    default { return $null }
  }
}

<#
.SYNOPSIS
  Ensembles Storage Spaces, ou `$null` si la fonctionnalite n'a pas pu etre sondee.

.DESCRIPTION
  `storage.pools` partait a `@()` sans que rien n'ait ete regarde. Un tableau
  vide **affirme** l'absence : `DIA-014` et `DIA-017` concluaient « aucun
  ensemble sur cette machine » sur la seule foi d'une valeur par defaut. C'est
  la meme ambiguite que celle des ports en ecoute, et elle se resout de la meme
  facon — sonder, puis distinguer le vide constate du vide suppose.

  Le pool **primordial** est ecarte. Windows en declare toujours un : il
  represente les disques non enrolles, pas un ensemble. Le publier ferait
  apparaitre un « ensemble de stockage » sur toute machine Windows, y compris
  celles qui n'ont jamais configure d'espace de stockage.

  `$null` en retour signifie « non sonde » — les applets de commande Storage
  n'existent pas, ou ont refuse. L'appelant omet alors la cle, et les deux
  regles sortent en non evalue avec le motif exact plutot qu'en « sans objet ».
#>
function Get-StoragePoolInventory {
  $pools = @()
  try {
    $pools = @(Get-StoragePool -ErrorAction Stop | Where-Object { -not $_.IsPrimordial })
  } catch {
    Add-CollectionIssue -Section 'storage.pools' -Severity 'warning' `
      -Message ('Espaces de stockage non enumeres : ' + $_.Exception.Message) `
      -Source 'Get-StoragePool' -Reason 'NOT_AVAILABLE'
    return $null
  }

  Add-CollectionProvenance -Path 'storage.pools' -Source 'Get-StoragePool' `
    -Method 'applet de commande' -Precision 'ensemble'

  # Aucun espace configure : le tableau vide est cette fois un **constat**, et
  # les deux regles ont raison d'en conclure « sans objet ».
  #
  # `,@()` et non `@()` : PowerShell deroule un tableau rendu par une fonction, et
  # un tableau **vide** se deroule en **rien** — l'appelant recevait `$null`,
  # concluait « ensembles non sondes » et omettait la cle. DIA-014 et DIA-017
  # sortaient donc en « donnee absente » sur une machine ou le sondage avait
  # parfaitement abouti. L'operateur virgule emballe le tableau et empeche le
  # deroulement.
  if ($pools.Count -eq 0) { return ,@() }

  $inventory = @()
  foreach ($pool in $pools) {
    $members = @()
    try {
      $members = @(Get-PhysicalDisk -StoragePool $pool -ErrorAction Stop |
          ForEach-Object { [string]$_.FriendlyName } |
          Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    } catch {
      Add-CollectionIssue -Section 'storage.pools' -Severity 'warning' `
        -Message ('Membres de l''ensemble ' + $pool.FriendlyName + ' non enumeres : ' + $_.Exception.Message) `
        -Source 'Get-PhysicalDisk' -Reason 'NOT_AVAILABLE'
    }

    # Le niveau vient des disques virtuels de l'ensemble, et **seulement s'ils
    # s'accordent** : un ensemble qui heberge un miroir et un volume simple n'a
    # pas de niveau unique, et lui en attribuer un declarerait protege ce qui ne
    # l'est qu'a moitie.
    $resiliencies = @()
    try {
      $resiliencies = @(Get-VirtualDisk -StoragePool $pool -ErrorAction Stop |
          ForEach-Object { [string]$_.ResiliencySettingName } |
          Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
          Select-Object -Unique)
    } catch {
      Write-Debug ('Disques virtuels de ' + $pool.FriendlyName + ' non lus : ' + $_.Exception.Message)
    }

    $raidLevel = New-Unknown -Reason 'UNKNOWN' -Detail 'aucun mode de resilience unique sur cet ensemble'
    $redundant = New-Unknown -Reason 'UNKNOWN' -Detail 'mode de resilience non determine'
    if ($resiliencies.Count -eq 1) {
      $raidLevel = $resiliencies[0]
      $known = Get-ResiliencyRedundancy -Resiliency $resiliencies[0]
      if ($null -ne $known) { $redundant = [bool]$known }
    }

    $inventory += @{
      name = Get-StringOrUnknown -Value $pool.FriendlyName -Reason 'UNKNOWN'
      type = 'Storage Spaces'
      state = Get-StringOrUnknown -Value $pool.HealthStatus -Reason 'UNKNOWN'
      sizeBytes = Get-PositiveIntOrUnknown -Value $pool.Size -Reason 'UNKNOWN'
      usedBytes = Get-PositiveIntOrUnknown -Value $pool.AllocatedSize -Reason 'UNKNOWN'
      members = $members
      raidLevel = $raidLevel
      redundant = $redundant
    }
  }

  return $inventory
}

function Get-StorageInventory {
  $reliabilityByDisk = @{}
  # SMART n'est pas lu au niveau Rapide.
  #
  # C'est une requete `Get-StorageReliabilityCounter` **par disque**, la partie
  # couteuse de cette collecte -- exactement ce que le scanner Linux reserve
  # deja au niveau Normale. Le scanner Windows, lui, appelait
  # `Test-DepthAtLeast` a un seul endroit dans tout le fichier, si bien que
  # l'audit Rapide y collectait tout ce qu'il savait collecter : plus riche que
  # la matrice ne l'annonce, et plus lent que la duree affichee.
  #
  # L'absence est declaree, jamais silencieuse : `Add-LevelSkip` dit quel niveau
  # l'aurait collectee.
  if (-not (Test-DepthAtLeast -Section 'storage' -Wanted 'standard')) {
    Add-LevelSkip -Section 'storage.disks[].smart' -Needed 'standard'
  } elseif ((Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue) -and
    (Get-Command Get-StorageReliabilityCounter -ErrorAction SilentlyContinue)) {
    try {
      foreach ($physicalDisk in @(Get-PhysicalDisk -ErrorAction Stop)) {
        try {
          $counter = Get-StorageReliabilityCounter -PhysicalDisk $physicalDisk -ErrorAction Stop
          $reliabilityByDisk[[string]$physicalDisk.FriendlyName] = $counter
        } catch {
          continue
        }
      }
      if ($reliabilityByDisk.Count -gt 0) {
        Add-CollectionProvenance -Path 'storage.disks[].smart' -Source 'Get-StorageReliabilityCounter' -Method 'PowerShell' -Precision 'disque'
      }
    } catch {
      Add-CollectionIssue -Section 'storage.smart' -Severity 'warning' `
        -Message ('Compteurs de fiabilite Windows non lisibles : ' + $_.Exception.Message) `
        -Source 'Get-StorageReliabilityCounter' -Reason 'NOT_AVAILABLE'
    }
  }

  $volumeIds = Get-VolumeIdentifiersByLetter
  $partitionIds = Get-PartitionIdentifiersByLetter
  $wwnByIndex = Get-DiskWwnByIndex
  # Une seule interrogation de BitLocker pour toutes les partitions : elle est
  # couteuse et son resultat est le meme pour chacune.
  $bitlocker = Get-BitLockerStateByLetter
  $physicalByNumber = Get-PhysicalDiskFactsByNumber

  $logicalDisks = @{}
  Get-CimInstance Win32_LogicalDisk -ErrorAction SilentlyContinue | ForEach-Object {
    # `$null` a gauche : compare a droite, PowerShell filtre les collections au
    # lieu de tester, et un tableau vide passerait pour une valeur presente.
    # `ConvertTo-SafeInt64` et non `[int64]` : la taille d'un volume arrive
    # parfois en chaine, et `[int64]'Unknown'` leve — l'exception emportait
    # alors l'inventaire des volumes suivants, pas seulement celui-ci.
    $size = ConvertTo-SafeInt64 -Value $_.Size
    $free = ConvertTo-SafeInt64 -Value $_.FreeSpace
    $used = if ($null -ne $size -and $null -ne $free) { $size - $free } else { $null }
    $usage = if ($null -ne $size -and $size -gt 0 -and $null -ne $used) {
      [int][Math]::Round(($used * 100.0) / $size)
    } else { $null }
    $letter = [string]$_.DeviceID
    $logicalDisks[$_.DeviceID] = @{
      name = [string]$_.DeviceID
      uuid = if ($volumeIds.ContainsKey($letter)) {
        Get-StringOrUnknown -Value $volumeIds[$letter] -Reason 'UNKNOWN'
      } else {
        New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'volume sans identifiant publie par Win32_Volume'
      }
      partitionUuid = if ($partitionIds.ContainsKey($letter)) {
        Get-StringOrUnknown -Value $partitionIds[$letter] -Reason 'UNKNOWN'
      } else {
        New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'table de partitions sans identifiants (MBR)'
      }
      mountPoint = [string]$_.DeviceID
      filesystem = Get-StringOrUnknown -Value $_.FileSystem -Reason 'UNKNOWN'
      sizeBytes = Get-PositiveIntOrUnknown -Value $_.Size -Reason 'UNKNOWN'
      usedBytes = if ($null -ne $used) { $used } else { New-Unknown -Reason 'UNKNOWN' }
      freeBytes = Get-PositiveIntOrUnknown -Value $_.FreeSpace -Reason 'UNKNOWN'
      usagePercent = if ($null -ne $usage) { [int]$usage } else { New-Unknown -Reason 'UNKNOWN' }
      encrypted = if ($null -eq $bitlocker) {
        New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'etat BitLocker non lu'
      } elseif ($bitlocker.ContainsKey($letter)) {
        $bitlocker[$letter].encrypted
      } else {
        # BitLocker a repondu, et ne connait pas ce volume : il n'est pas
        # chiffre. C'est un constat, pas un repli.
        $false
      }
      encryptionType = if ($null -eq $bitlocker) {
        New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'etat BitLocker non lu'
      } elseif ($bitlocker.ContainsKey($letter) -and $null -ne $bitlocker[$letter].type) {
        $bitlocker[$letter].type
      } else {
        New-Unknown -Reason 'NOT_APPLICABLE' -Detail 'volume non chiffre'
      }
    }
  }

  $disks = @()
  Get-CimInstance Win32_DiskDrive -ErrorAction SilentlyContinue | ForEach-Object {
    $device = [string]$_.DeviceID
    # Chaque disque dans son propre `try`.
    #
    # Un inventaire de disques est la collecte la plus exposee du scanner : elle
    # traverse Win32_DiskDrive, les compteurs de fiabilite, les associations de
    # partitions et BitLocker, dont aucun ne garantit le type de ce qu'il rend.
    # Sans cette isolation, une seule valeur inattendue sur le troisieme disque
    # emportait les trois — et le rapport ne montrait aucun disque du tout, sans
    # dire lequel avait fauté.
    #
    # L'issue nomme le disque : « un disque manque » se corrige, « le stockage a
    # echoue » ne se corrige pas.
    try {
      $reliability = $null
      foreach ($key in $reliabilityByDisk.Keys) {
        if ([string]$_.Model -like "*$key*" -or $key -like "*$($_.Model)*") {
          $reliability = $reliabilityByDisk[$key]
          break
        }
      }
      $partitions = @()
      try {
        # Le chemin part **tel quel**, sans doubler ses antislashs.
        #
        # `Get-CimInstance -Query` n'attend pas d'echappement ici : `\\.\PHYSICALDRIVE2`
        # trouve ses partitions, `\\\\.\\PHYSICALDRIVE2` echoue sur « Non trouve ».
        # Le doublement venait de WQL passe a `wmic`, ou il etait juste ; ici il
        # faisait manquer **toutes** les partitions de **tous** les disques, sur
        # toutes les machines Windows. Constate le 2026-08-16 sur un poste reel :
        # trois disques, trois avertissements, aucun volume rattache.
        $query = "ASSOCIATORS OF {Win32_DiskDrive.DeviceID='$device'} WHERE AssocClass = Win32_DiskDriveToDiskPartition"
        $linkedPartitions = Get-CimInstance -Query $query -ErrorAction Stop
        foreach ($partition in $linkedPartitions) {
          try {
            # Meme raison qu'au-dessus. Le DeviceID d'une partition — « Disque #2,
            # Partition #0 » — ne porte pas d'antislash, le doublement y etait
            # sans effet ; le retirer garde les deux requetes identiques, faute de
            # quoi la prochaine lecture croira que l'une des deux formes est la
            # bonne.
            $logicalQuery = "ASSOCIATORS OF {Win32_DiskPartition.DeviceID='$($partition.DeviceID)'} WHERE AssocClass = Win32_LogicalDiskToPartition"
            $linkedLogicalDisks = Get-CimInstance -Query $logicalQuery -ErrorAction Stop
            foreach ($logical in $linkedLogicalDisks) {
              if ($logicalDisks.ContainsKey($logical.DeviceID)) { $partitions += $logicalDisks[$logical.DeviceID] }
            }
          } catch {
            Add-CollectionIssue -Section 'storage.partitions' -Severity 'warning' `
              -Message ('Volumes de la partition ' + $partition.DeviceID + ' non associes : ' + $_.Exception.Message) `
              -Source 'Win32_LogicalDiskToPartition' -Reason 'NOT_AVAILABLE'
          }
        }
      } catch {
        Add-CollectionIssue -Section 'storage.partitions' -Severity 'warning' `
          -Message ('Partitions de ' + $device + ' non enumerees : ' + $_.Exception.Message) `
          -Source 'Win32_DiskDriveToDiskPartition' -Reason 'NOT_AVAILABLE'
      }

      $physicalFacts = $null
      if ($physicalByNumber.ContainsKey([string]$_.Index)) {
        $physicalFacts = $physicalByNumber[[string]$_.Index]
      }
      # Converties une fois, en amont du champ qui les emploie : c'est ici que le
      # `Unknown` de `Get-PhysicalDisk` et de `Get-StorageReliabilityCounter`
      # arrivait jusqu'a un `[int64]` ecrit en dur.
      $spindleSpeed = if ($null -ne $physicalFacts) { ConvertTo-SafeInt64 -Value $physicalFacts.spindleSpeed } else { $null }
      $wear = if ($null -ne $reliability) { ConvertTo-SafeInt64 -Value $reliability.Wear } else { $null }
      $diskMediaType = if ($null -ne $physicalFacts) { [string]$physicalFacts.mediaType } else { '' }
      $diskBusType = if ($null -ne $physicalFacts) { [string]$physicalFacts.busType } else { '' }
      $diskKind = Get-DiskKindFromFacts -MediaType $diskMediaType -BusType $diskBusType -Model ([string]$_.Model)

      # La temperature du disque part aussi vers la section capteurs, ou elle
      # rejoint le processeur et la carte mere. La categorie vient du type reel du
      # support : cinquante degres ne se lisent pas pareil sur un plateau et sur un
      # NVMe, et c'est elle qui decide du seuil applique a l'affichage.
      if ($null -ne $reliability -and $null -ne $reliability.Temperature) {
        $diskTemperature = [double]$reliability.Temperature
        # `Get-StorageReliabilityCounter` rend 0 quand le disque ne publie pas de
        # sonde. Zero degre n'est pas une temperature de disque en marche : le
        # rapporter ferait apparaitre une sonde la ou il n'y en a pas.
        if ($diskTemperature -gt 0 -and $diskTemperature -lt 150) {
          $diskCategory = switch ($diskKind) {
            'NVME' { 'DRIVE_NVME' }
            'SSD' { 'DRIVE_SSD' }
            'HDD' { 'DRIVE_HDD' }
            # USB, VIRTUAL, UNKNOWN : le support reel est inconnu derriere ces
            # interfaces. Aucun seuil ne leur est applique, plutot qu'un seuil au
            # juger.
            default { 'OTHER' }
          }
          $diskModel = [string]$_.Model
          if ([string]::IsNullOrWhiteSpace($diskModel)) { $diskModel = $device }
          Add-ThermalReading -Label 'Temperature du disque' -Celsius $diskTemperature `
            -Category $diskCategory -Device $diskModel -Source 'Get-StorageReliabilityCounter'
        }
      }

      $disks += @{
        device = $device
        manufacturer = Get-StringOrUnknown -Value $_.Manufacturer -Reason 'UNKNOWN'
        model = Get-StringOrUnknown -Value $_.Model -Reason 'UNKNOWN'
        serialNumber = Get-StringOrUnknown -Value $_.SerialNumber -Reason 'UNKNOWN'
        wwn = if ($wwnByIndex.ContainsKey([string]$_.Index)) {
          Get-StringOrUnknown -Value $wwnByIndex[[string]$_.Index] -Reason 'UNKNOWN'
        } else {
          New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'aucun identifiant normalise publie par le controleur'
        }
        # Les identifiants d'espace de noms NVMe ne remontent par aucune classe
        # CIM ni applet de commande : ils demandent une commande d'administration
        # NVMe passee au pilote, ce qu'un scanner en lecture seule ne fait pas.
        nguid = New-Unknown -Reason 'UNSUPPORTED' -Detail 'non expose par Windows'
        eui64 = New-Unknown -Reason 'UNSUPPORTED' -Detail 'non expose par Windows'
        firmware = Get-StringOrUnknown -Value $_.FirmwareRevision -Reason 'UNKNOWN'
        sizeBytes = Get-PositiveIntOrUnknown -Value $_.Size -Reason 'UNKNOWN'
        kind = $diskKind
        # Les trois faits que `kind` melangeait, chacun de sa source.
        # `Win32_DiskDrive.InterfaceType` reste publie tel quel dans `interface` :
        # c'est bien ce que la pile de stockage rend, et le corriger reviendrait a
        # masquer la couche d'abstraction au lieu de la nommer.
        mediaType = if ($diskMediaType) { $diskMediaType } else {
          New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'nature du support non publiee par Get-PhysicalDisk'
        }
        busType = if ($diskBusType) { $diskBusType } else {
          New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'bus non publie par Get-PhysicalDisk'
        }
        # Le jeu de commandes ne se lit nulle part sous Windows. Le deduire du bus
        # serait juste dans la majorite des cas et faux sur un NVMe en boitier
        # USB, qui est precisement le cas ou la question se pose.
        protocol = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'jeu de commandes non expose par Windows'
        interface = Get-StringOrUnknown -Value $_.InterfaceType -Reason 'UNKNOWN'
        rotationRpm = if ($null -ne $spindleSpeed -and $spindleSpeed -gt 0 -and $spindleSpeed -lt 4294967295) {
          $spindleSpeed
        } else {
          # `Get-PhysicalDisk` rend 0 sur un SSD et 0xFFFFFFFF quand la valeur est
          # inconnue. Ni l'un ni l'autre n'est une vitesse de rotation.
          New-Unknown -Reason 'NOT_AVAILABLE'
        }
        # Windows n'expose le rejet de blocs qu'au niveau du systeme
        # (`fsutil behavior query DisableDeleteNotify`), jamais par disque.
        # Recopier le reglage global sur chaque disque en ferait une propriete
        # du materiel qu'il n'est pas.
        trimSupported = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'non expose par disque sous Windows'
        partitionTable = New-Unknown -Reason 'NOT_AVAILABLE'
        removable = [bool]$_.MediaLoaded -and ([string]$_.InterfaceType -eq 'USB')
        smart = @{
          status = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'verdict SMART global non expose par Win32_DiskDrive'
          temperatureCelsius = if ($null -ne $reliability) { Get-NumberOrUnknown -Value $reliability.Temperature -Reason 'UNKNOWN' } else { New-Unknown -Reason 'NOT_AVAILABLE' }
          powerOnHours = if ($null -ne $reliability) { Get-PositiveIntOrUnknown -Value $reliability.PowerOnHours -Reason 'UNKNOWN' } else { New-Unknown -Reason 'NOT_AVAILABLE' }
          powerCycles = if ($null -ne $reliability) { Get-PositiveIntOrUnknown -Value $reliability.StartStopCycleCount -Reason 'UNKNOWN' } else { New-Unknown -Reason 'NOT_AVAILABLE' }
          reallocatedSectors = New-Unknown -Reason 'NOT_AVAILABLE'
          pendingSectors = New-Unknown -Reason 'NOT_AVAILABLE'
          uncorrectableErrors = if ($null -ne $reliability) { Get-PositiveIntOrUnknown -Value $reliability.WriteErrorsTotal -Reason 'UNKNOWN' } else { New-Unknown -Reason 'NOT_AVAILABLE' }
          wearPercent = if ($null -ne $wear) { [Math]::Max(0, [Math]::Min(100, $wear)) } else { New-Unknown -Reason 'NOT_AVAILABLE' }
          nvmePercentageUsed = New-Unknown -Reason 'NOT_AVAILABLE'
          availableSparePercent = New-Unknown -Reason 'NOT_AVAILABLE'
          availableSpareThresholdPercent = New-Unknown -Reason 'NOT_AVAILABLE'
          mediaErrors = if ($null -ne $reliability) { Get-PositiveIntOrUnknown -Value $reliability.ReadErrorsTotal -Reason 'UNKNOWN' } else { New-Unknown -Reason 'NOT_AVAILABLE' }
          unsafeShutdowns = if ($null -ne $reliability) { Get-PositiveIntOrUnknown -Value $reliability.UnsafeShutdownCount -Reason 'UNKNOWN' } else { New-Unknown -Reason 'NOT_AVAILABLE' }
          dataUnitsRead = New-Unknown -Reason 'NOT_AVAILABLE'
          dataUnitsWritten = New-Unknown -Reason 'NOT_AVAILABLE'
        }
        partitions = $partitions
      }
    } catch {
      Add-CollectionIssue -Section 'storage.disks' -Severity 'warning' `
        -Message ('Disque ' + $device + ' non inventorie : ' + $_.Exception.Message) `
        -Source 'Win32_DiskDrive' -Reason 'COLLECTOR_ERROR'
    }
  }

  $storageTotal = 0
  $storageUsed = 0
  foreach ($entry in $logicalDisks.Values) {
    $entrySize = if ($entry.sizeBytes -is [ValueType]) { ConvertTo-SafeInt64 -Value $entry.sizeBytes } else { $null }
    $entryUsed = if ($entry.usedBytes -is [ValueType]) { ConvertTo-SafeInt64 -Value $entry.usedBytes } else { $null }
    if ($null -ne $entrySize) { $storageTotal += $entrySize }
    if ($null -ne $entryUsed) { $storageUsed += $entryUsed }
  }

  $inventory = @{
    disks = $disks
    totalBytes = $storageTotal
    usedBytes = $storageUsed
    trimScheduled = Get-TrimScheduled
  }

  # La cle n'est posee que si les ensembles ont ete sondes. Absente, elle laisse
  # DIA-014 et DIA-017 sortir en non evalue avec le motif que le sondage a
  # laisse dans `collection.issues` — jamais en « sans objet », qui affirmerait
  # une absence que personne n'a constatee.
  $pools = Get-StoragePoolInventory
  if ($null -ne $pools) { $inventory['pools'] = @($pools) }

  return $inventory
}
