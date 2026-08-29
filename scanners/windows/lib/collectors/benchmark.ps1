# SysAudit Windows — profil de charge et mesures.
#
# Seul collecteur a solliciter volontairement la machine. Il n'est execute que
# sur demande explicite du niveau Poussee.
#
# WinSAT etait lance puis oublie : le scanner chargeait la machine pendant
# plusieurs minutes sans rien rapporter de ce qu'il avait mesure. Ses indices
# sont desormais relus depuis `Win32_WinSAT` et projetes dans la section
# `benchmark`, avec leur unite — un indice WinSAT n'est pas un debit, et les
# confondre rendrait deux machines incomparables.
#
# Aucun outil tiers n'est telecharge ni redistribue : WinSAT fait partie de
# Windows.

<#
.SYNOPSIS
  Horodatage ISO 8601 UTC, format attendu par le schema.
#>
function Get-IsoNow {
  return (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}

# Version du **protocole de mesure**, distincte de la version de l'outil.
#
# `toolVersion` dit quel binaire a tourne ; celle-ci dit comment il a ete
# employe. Deux indices WinSAT produits par des evaluations differentes ne sont
# pas comparables, et rien ne le disait.
#
# **Une version par couple cible + outil, et non une par scanner.**
#
# La constante unique qui regnait ici ne pouvait pas etre juste : elle etait
# censee changer quand *l'une* des mesures changeait, et elle invalidait alors
# *toutes* les autres. Changer la taille de bloc du disque aurait casse la
# comparabilite des indices WinSAT, qui n'avaient pas bouge — si bien que
# personne ne la changeait, et qu'elle ne distinguait plus rien.
#
# A incrementer des que la methode d'une ligne change, meme si l'outil ne bouge
# pas. `docs/format-rapport/PROTOCOLE-BANC-ESSAI.md` dit ce que chaque version
# recouvre, et un test de contrat refuse qu'un couple d'ici publie une version
# que l'analyse ne sait pas lire.
$script:BenchmarkProtocols = @{
  'cpu-multi|winsat' = '1.0.0'
  'memory-copy|winsat' = '1.0.0'
  'gpu|winsat' = '1.0.0'
  'storage-sequential-read|dotnet' = '1.0.0'
  'storage-sequential-write|dotnet' = '1.0.0'
  'storage-random-read|dotnet' = '1.0.0'
}

<#
.SYNOPSIS
  Version du protocole d'un couple cible + outil, ou `$null` s'il n'en a pas.
.DESCRIPTION
  `$null` n'est pas un trou dans la table : les charges mixtes sont publiees
  avec le seul motif qui les ecarte, et aucune mesure n'a eu lieu. Leur donner
  un numero de protocole affirmerait une methode qui n'a pas ete employee.
#>
function Get-BenchmarkProtocolVersion {
  param(
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string]$Tool
  )

  $key = $Target + '|' + $Tool
  if ($script:BenchmarkProtocols.ContainsKey($key)) { return $script:BenchmarkProtocols[$key] }
  return $null
}

<#
.SYNOPSIS
  Une mesure non produite, avec son motif.
.DESCRIPTION
  Une mesure absente et une mesure ratee ne se ressemblent que dans un rapport
  qui ne dit ni l'une ni l'autre.
#>
function New-BenchmarkSkip {
  param(
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string]$Tool,
    [Parameter(Mandatory = $true)][string]$Reason,
    [ValidateSet('skipped', 'failed')][string]$Status = 'skipped'
  )

  Add-CollectionIssue -Section ('benchmark.' + $Target) -Severity 'warning' `
    -Message $Reason -Source $Tool

  $result = @{
    target = $Target
    status = $Status
    detail = $Reason
    tool = $Tool
    toolVersion = New-Unknown -Reason 'NOT_AVAILABLE'
    algorithm = New-Unknown -Reason 'NOT_AVAILABLE'
    parameters = New-Unknown -Reason 'NOT_AVAILABLE'
    durationMs = New-Unknown -Reason 'NOT_AVAILABLE'
    score = New-Unknown -Reason 'NOT_AVAILABLE' -Detail $Reason
    unit = New-Unknown -Reason 'NOT_AVAILABLE'
    temperatureCelsius = New-Unknown -Reason 'NOT_AVAILABLE'
    throttled = New-Unknown -Reason 'NOT_AVAILABLE'
  }

  $protocol = Get-BenchmarkProtocolVersion -Target $Target -Tool $Tool
  if ($null -ne $protocol) { $result.protocolVersion = $protocol }
  return $result
}

<#
.SYNOPSIS
  Une mesure aboutie.
.DESCRIPTION
  L'indice WinSAT va de 1,0 a 9,9 et n'a de sens que compare a un autre indice
  WinSAT : l'unite le dit, et l'algorithme nomme l'evaluation d'origine.
#>
function New-BenchmarkResult {
  param(
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][double]$Score,
    [Parameter(Mandatory = $true)][string]$Algorithm,
    [string]$StartedAt = '',
    [string]$Parameters = '',
    # L'outil doit etre connu **ici**, et non recolle par l'appelant apres coup.
    #
    # Les mesures de stockage ecrasaient `tool` une fois le dictionnaire rendu ;
    # la version de protocole, elle, etait deja calculee — et decrivait donc
    # WinSAT alors que la mesure venait de .NET. Le couple cible + outil decide
    # du protocole : il ne peut pas etre connu apres lui.
    [string]$Tool = 'winsat',
    [string]$Device = ''
  )

  $result = @{
    target = $Target
    status = 'completed'
    startedAt = if ([string]::IsNullOrWhiteSpace($StartedAt)) { Get-IsoNow } else { $StartedAt }
    finishedAt = Get-IsoNow
    tool = $Tool
    toolVersion = Get-StringOrUnknown -Value ([System.Environment]::OSVersion.Version.ToString()) -Reason 'UNKNOWN'
    algorithm = $Algorithm
    parameters = if ([string]::IsNullOrWhiteSpace($Parameters)) { New-Unknown -Reason 'NOT_AVAILABLE' } else { $Parameters }
    durationMs = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'WinSAT ne publie pas la duree de chaque sous-test'
    score = $Score
    unit = 'indice WinSAT'
    # Aucune source thermique fiable sous Windows sans composant tiers : le
    # rapport le dit plutot que de laisser croire a une mesure a froid.
    temperatureCelsius = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'aucun capteur thermique lisible sous Windows'
    throttled = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'frequence sous charge non relevee'
  }

  $protocol = Get-BenchmarkProtocolVersion -Target $Target -Tool $Tool
  if ($null -ne $protocol) { $result.protocolVersion = $protocol }
  if (-not [string]::IsNullOrWhiteSpace($Device)) { $result.device = $Device }
  return $result
}

<#
.SYNOPSIS
  Execute les evaluations WinSAT puis relit leurs indices.
.DESCRIPTION
  Retourne la section `benchmark` du rapport, ou `$null` si WinSAT est absent —
  cas courant sur Windows Server, ou la fonctionnalite n'est pas installee.
#>
function Invoke-StressProfile {
  $startedAt = Get-IsoNow
  $started = Get-Date

  Write-Host '[stress] CPU / RAM / disque / GPU'

  # WinSAT n'est pas installe partout — Windows Server, notamment. Son absence
  # prive des indices processeur, memoire et Direct3D, pas des debits disque :
  # rendre `$null` ici supprimerait des mesures parfaitement realisables.
  $hasWinSat = [bool](Get-Command winsat -ErrorAction SilentlyContinue)
  if (-not $hasWinSat) {
    Add-CollectionIssue -Section 'benchmark' -Severity 'warning' `
      -Message 'WinSAT absent : indices processeur, memoire et Direct3D non mesures.' -Source 'winsat' -Reason 'NOT_AVAILABLE'
  }

  $tests = @(
    @{ label = 'CPU'; args = @('cpuformal') ; section = 'benchmark.cpu-multi' },
    @{ label = 'Memoire'; args = @('memformal') ; section = 'benchmark.memory-copy' },
    @{ label = 'Disque'; args = @('diskformal') ; section = 'benchmark.storage-sequential-read' },
    @{ label = 'GPU'; args = @('d3d') ; section = 'benchmark.gpu' }
  )

  foreach ($test in $tests) {
    if (-not $hasWinSat) { break }
    Write-Host ('  -> ' + $test.label)
    try {
      $process = Start-Process winsat -ArgumentList $test.args -Wait -PassThru -WindowStyle Hidden
      if ($process.ExitCode -ne 0) {
        Add-CollectionIssue -Section $test.section -Severity 'warning' `
          -Message ('WinSAT a retourne un code non nul pendant le test ' + $test.label + '.') -Source 'winsat' -Reason 'NOT_AVAILABLE'
      }
    } catch {
      Add-CollectionIssue -Section $test.section -Severity 'warning' `
        -Message ('Le test ' + $test.label + ' n''a pas pu etre execute.') -Source 'winsat' -Reason 'NOT_AVAILABLE'
    }
  }

  # Les indices WinSAT couvrent le processeur, la memoire et Direct3D. Le
  # stockage n'y figure que sous forme d'indice composite, d'ou aucun debit
  # n'est deductible : il est mesure separement, en .NET.
  $results = @(Get-WinSatResultList -StartedAt $startedAt)
  $results += @(Get-StorageBenchmarkResultList -StartedAt $startedAt)
  $results += @(Get-MixedLoadSkipList)

  return @{
    startedAt = $startedAt
    finishedAt = Get-IsoNow
    durationMs = [int][Math]::Max(0, ((Get-Date) - $started).TotalMilliseconds)
    results = @($results)
  }
}

<#
.SYNOPSIS
  Les charges mixtes, declarees non exploitees sous Windows.
.DESCRIPTION
  Le format prevoit deux charges menant de front un rendu graphique et un
  travail processeur : `gaming` et `cpu-gpu`. Elles repondent a une question
  qu'aucune mesure isolee ne repond — une machine dont chaque composant tient
  seul peut s'effondrer quand les deux travaillent ensemble.

  Windows ne les execute pas, et ce n'est pas un oubli. WinSAT est un evaluateur
  a passe unique : il note un sous-systeme a la fois et n'accepte aucune charge
  concurrente. Composer la charge demanderait un moteur de rendu tiers, donc un
  binaire redistribue ou telecharge a l'execution — ce que le scanner s'interdit
  partout ailleurs pour la meme raison que le stockage n'utilise pas `diskspd`.

  Les cibles sont donc publiees **avec leur motif** plutot qu'omises. Une cible
  absente se lit comme une version de scanner trop ancienne ; une cible
  `skipped` dit exactement ce qui s'est passe, et le rapport le montre a cote
  des charges qui, elles, ont tourne.
#>
function Get-MixedLoadSkipList {
  $reason = 'Charge mixte non executee sous Windows : WinSAT evalue un sous-systeme a la fois et n''accepte aucune charge concurrente. La composer demanderait un moteur de rendu tiers, que ce scanner ne redistribue ni ne telecharge.'

  return @(
    (New-BenchmarkSkip -Target 'gaming' -Tool 'winsat' -Reason $reason),
    (New-BenchmarkSkip -Target 'cpu-gpu' -Tool 'winsat' -Reason $reason)
  )
}

<#
.SYNOPSIS
  Relit les indices publies par la derniere evaluation WinSAT.
.DESCRIPTION
  `Win32_WinSAT` expose un indice par sous-systeme, et l'etat de l'evaluation.
  Un etat autre que « valide » signifie que les indices decrivent une autre
  configuration materielle que celle-ci : ils sont alors ecartes plutot que
  rapportes, un indice perime etant pire qu'une absence.

  Le disque n'y figure que sous forme d'indice composite, qui melange acces
  sequentiel et acces aleatoire. Le projeter sur une cible « lecture
  sequentielle » decrirait autre chose que ce qui a ete mesure : les cibles de
  stockage sont donc declarees non exploitees, avec ce motif.
#>
function Get-WinSatResultList {
  param([string]$StartedAt = '')

  if (-not (Get-Command winsat -ErrorAction SilentlyContinue)) {
    $absent = 'WinSAT absent de cette installation de Windows.'
    return @(
      (New-BenchmarkSkip -Target 'cpu-multi' -Tool 'winsat' -Reason $absent),
      (New-BenchmarkSkip -Target 'memory-copy' -Tool 'winsat' -Reason $absent),
      (New-BenchmarkSkip -Target 'gpu' -Tool 'winsat' -Reason $absent)
    )
  }

  $winsat = $null
  try {
    $winsat = Get-CimInstance Win32_WinSAT -ErrorAction Stop
  } catch {
    $winsat = $null
  }

  if ($null -eq $winsat) {
    return @(
      (New-BenchmarkSkip -Target 'cpu-multi' -Tool 'winsat' -Reason 'Win32_WinSAT illisible : indices non recuperes.' -Status 'failed'),
      (New-BenchmarkSkip -Target 'memory-copy' -Tool 'winsat' -Reason 'Win32_WinSAT illisible : indices non recuperes.' -Status 'failed'),
      (New-BenchmarkSkip -Target 'gpu' -Tool 'winsat' -Reason 'Win32_WinSAT illisible : indices non recuperes.' -Status 'failed')
    )
  }

  # 1 = evaluation valide. Toute autre valeur signale des indices qui ne
  # correspondent plus au materiel present.
  if ($winsat.WinSATAssessmentState -ne 1) {
    $reason = 'Indices WinSAT declares non valides pour ce materiel (etat ' + [string]$winsat.WinSATAssessmentState + ').'
    return @(
      (New-BenchmarkSkip -Target 'cpu-multi' -Tool 'winsat' -Reason $reason),
      (New-BenchmarkSkip -Target 'memory-copy' -Tool 'winsat' -Reason $reason),
      (New-BenchmarkSkip -Target 'gpu' -Tool 'winsat' -Reason $reason)
    )
  }

  $results = @()

  # Seul l'indice Direct3D nomme un composant.
  #
  # Le processeur et la memoire n'en nomment pas, et ce n'est pas une omission :
  # `cpuformal` charge tous les coeurs du seul processeur, `memformal` mesure la
  # configuration memoire dans son ensemble. Nommer une barrette la reviendrait
  # a lui attribuer un debit que la plateforme entiere a produit.
  $adapter = Get-WinSatGraphicsAdapter

  $scores = @(
    @{ target = 'cpu-multi'; value = $winsat.CPUScore; algorithm = 'WinSAT cpuformal (compression et chiffrement, multi-thread)'; device = '' },
    @{ target = 'memory-copy'; value = $winsat.MemoryScore; algorithm = 'WinSAT memformal (bande passante memoire)'; device = '' },
    @{ target = 'gpu'; value = $winsat.D3DScore; algorithm = 'WinSAT d3d (rendu Direct3D)'; device = $adapter }
  )

  foreach ($score in $scores) {
    $value = $score.value
    # WinSAT rend 255 pour « non evalue » ; le prendre pour un indice ferait de
    # la machine la plus rapide jamais mesuree.
    if ($null -eq $value -or $value -le 0 -or $value -ge 255) {
      $results += New-BenchmarkSkip -Target $score.target -Tool 'winsat' `
        -Reason 'WinSAT n''a publie aucun indice exploitable pour ce sous-systeme.' -Status 'failed'
      continue
    }
    $results += New-BenchmarkResult -Target $score.target -Score ([double]$value) `
      -Algorithm $score.algorithm -StartedAt $StartedAt -Parameters 'evaluation formelle Windows' `
      -Device $score.device
  }

  return $results
}

<#
.SYNOPSIS
  Debits disque mesures, sans outil tiers.
.DESCRIPTION
  WinSAT ne publie qu'un indice de stockage composite, d'ou aucun debit n'est
  deductible. `diskspd` le ferait, mais c'est un binaire tiers : le
  redistribuer demanderait une analyse de licence et de provenance, et le
  telecharger a l'execution reviendrait a executer du code non verifie sur la
  machine auditee.

  Les trois mesures ci-dessous n'utilisent que .NET, present partout ou
  PowerShell tourne. Elles suivent les memes regles que leurs equivalents
  Linux : duree visee atteinte en repetant l'acces, volume ecrit borne
  independamment de la duree, fichier de travail supprime quoi qu'il arrive.
#>

<#
.SYNOPSIS
  Duree visee par mesure, en secondes.
#>
function Get-BenchmarkDurationSecond {
  $requested = $env:SYSAUDIT_BENCH_SECONDS
  $value = if ((Get-CurrentLevel) -eq 'stress') { 20 } else { 5 }
  if ($requested -match '^\d+$') { $value = [int]$requested }
  if ($value -lt 1) { $value = 1 }
  if ($value -gt 120) { $value = 120 }
  return $value
}

<#
.SYNOPSIS
  Taille du fichier de travail, en mebioctets, ou 0 si la place manque.
.DESCRIPTION
  Un dixieme de la place libre, plafonne a 256 Mio. En dessous de 64 Mio, la
  mesure est ecartee : elle decrirait le cache d'ecriture, pas le disque — et
  remplir un disque presque plein pour mesurer un debit serait une facon
  couteuse de provoquer la panne qu'on cherche a prevenir.
#>
function Get-BenchmarkStorageMib {
  param([string]$Path)

  try {
    $root = [System.IO.Path]::GetPathRoot((Resolve-Path $Path).Path)
    $drive = Get-PSDrive -PSProvider FileSystem | Where-Object {
      $_.Root -eq $root
    } | Select-Object -First 1
    if ($null -eq $drive -or $null -eq $drive.Free) { return 0 }

    $freeMib = [int]([double]$drive.Free / 1MB)
    $budget = [int]($freeMib / 10)
    if ($budget -gt 256) { $budget = 256 }
    if ($budget -lt 64) { return 0 }
    return $budget
  } catch {
    return 0
  }
}

<#
.SYNOPSIS
  Le disque physique qui porte un chemin, ou une chaine vide si c'est ambigu.
.DESCRIPTION
  **Sans lui, aucune machine a plusieurs disques ne peut etre classee.**

  Le banc d'essai ecrit dans le repertoire temporaire, donc sur un seul disque —
  celui du systeme, en general. Le resultat ne portait pourtant aucun nom de
  disque. L'analyse recevait un debit sans savoir a quoi l'attribuer : sur une
  machine a quatre disques elle refusait de classer, et elle avait raison —
  crediter les trois autres d'un debit qu'ils n'ont pas rendu aurait invente un
  merite. Le prix de ce refus etait qu'aucun disque n'obtenait jamais de rang.

  L'identifiant rendu est celui de `Win32_DiskDrive.DeviceID`
  (`\\.\PHYSICALDRIVE0`), **exactement** la forme que l'inventaire publie sous
  `storage.disks[].device` : c'est ce qui permet de relier la mesure au disque
  sans supposer quoi que ce soit.

  Une chaine vide est un resultat, et le bon. Un volume reparti sur plusieurs
  disques — agregat, miroir logiciel — n'a pas de disque unique a nommer, et en
  choisir un serait une invention. L'analyse retombe alors sur l'unicite, et
  ecarte la mesure si la machine porte plusieurs disques.
#>
function Get-BenchmarkStorageDevice {
  param([Parameter(Mandatory = $true)][string]$Path)

  try {
    $root = [System.IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $Path).Path)
    $letter = ($root -replace '\\$', '')
    if ($letter -notmatch '^[A-Za-z]:$') { return '' }

    # Les deux associations CIM plutot que le module Storage : elles existent
    # depuis Windows XP, la ou `Get-Partition` demande Windows 8 et un service
    # qui n'est pas toujours demarre sur les editions Serveur.
    $partitions = @(Get-CimInstance Win32_LogicalDiskToPartition -ErrorAction Stop |
        Where-Object { $_.Dependent.DeviceID -eq $letter } |
        ForEach-Object { $_.Antecedent.DeviceID })
    if ($partitions.Count -eq 0) { return '' }

    $drives = @(Get-CimInstance Win32_DiskDriveToDiskPartition -ErrorAction Stop |
        Where-Object { $partitions -contains $_.Dependent.DeviceID } |
        ForEach-Object { [string]$_.Antecedent.DeviceID } |
        Sort-Object -Unique)

    # Un seul disque, ou rien : deux disques derriere un meme volume signifient
    # un agregat, et le debit mesure les deux ensemble.
    if ($drives.Count -ne 1) { return '' }
    return $drives[0]
  } catch {
    return ''
  }
}

<#
.SYNOPSIS
  La carte graphique que WinSAT a reellement evaluee, ou une chaine vide.
.DESCRIPTION
  **WinSAT n'evalue qu'un adaptateur : le principal.** Publier son indice sans
  dire lequel laissait l'analyse devant un choix impossible sur une machine a
  plusieurs cartes — et le classement d'une carte dediee pouvait echoir a un
  adaptateur d'affichage virtuel qui n'a jamais rendu une image.

  WinSAT ecrit lui-meme le nom de l'adaptateur evalue sous
  `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WinSAT`. C'est sa
  reponse, pas une deduction : aucune heuristique ne vient decider a sa place
  quelle carte etait « la principale ».

  Chaine vide si la cle est absente : l'analyse ecarte alors la mesure pour
  ambiguite plutot que de la crediter au hasard.
#>
function Get-WinSatGraphicsAdapter {
  try {
    $key = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\WinSAT' -ErrorAction Stop
    $name = [string]$key.PrimaryAdapterString
    if ([string]::IsNullOrWhiteSpace($name)) { return '' }
    return $name.Trim()
  } catch {
    return ''
  }
}

<#
.SYNOPSIS
  Nombre de passes d'ecriture tolerees.
.DESCRIPTION
  Les lectures se repetent librement — elles n'usent rien. Les ecritures sont
  bornees : mesurer un debit ne doit pas couter plusieurs gibioctets de cycles
  d'ecriture a un SSD dont on cherche precisement a preserver la sante.
#>
function Get-BenchmarkWritePassCount {
  param([int]$Mib)

  if ($Mib -le 0) { return 1 }
  $budgetMib = if ((Get-CurrentLevel) -eq 'stress') { 2048 } else { 1024 }
  $passes = [int]($budgetMib / $Mib)
  if ($passes -lt 1) { $passes = 1 }
  return $passes
}

<#
.SYNOPSIS
  Mesure un acces disque, en repetant jusqu'a la duree visee.
.DESCRIPTION
  `WriteThrough` demande au systeme de ne pas differer l'ecriture : sans lui,
  la mesure decrirait le cache du systeme, pas le disque. Le mode `random`
  parcourt le fichier par blocs de 4 Kio a des positions tirees d'une suite
  deterministe — pas d'aleatoire non reproductible dans une mesure.

  Retourne un dictionnaire { mibPerSecond, passes, durationMs }, ou `$null` si
  la mesure n'a rien produit.
#>
function Measure-DiskAccess {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][ValidateSet('write', 'read', 'random')][string]$Mode,
    [Parameter(Mandatory = $true)][int]$Mib,
    [Parameter(Mandatory = $true)][int]$BudgetMs,
    [Parameter(Mandatory = $true)][int]$MaxPasses,
    [System.IO.FileOptions]$ReadOptions = [System.IO.FileOptions]::SequentialScan
  )

  $blockSize = 1MB
  $buffer = New-Object byte[] $blockSize
  $randomBlock = 4096
  $randomBuffer = New-Object byte[] $randomBlock

  $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
  $passes = 0
  $bytes = [long]0
  # Suite deterministe : deux executions parcourent les memes positions, ce qui
  # rend la mesure comparable a elle-meme.
  $position = [long]0

  try {
    while ($true) {
      switch ($Mode) {
        'write' {
          $stream = [System.IO.FileStream]::new(
            $Path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None, $blockSize, [System.IO.FileOptions]::WriteThrough)
          try {
            for ($i = 0; $i -lt $Mib; $i++) { $stream.Write($buffer, 0, $blockSize) }
            $stream.Flush($true)
          } finally { $stream.Dispose() }
          $bytes += [long]$Mib * $blockSize
        }
        'read' {
          $stream = [System.IO.FileStream]::new(
            $Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read, $blockSize, $ReadOptions)
          try {
            while ($stream.Read($buffer, 0, $blockSize) -gt 0) { $bytes += $blockSize }
          } finally { $stream.Dispose() }
        }
        'random' {
          $stream = [System.IO.FileStream]::new(
            $Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read, $randomBlock, [System.IO.FileOptions]::RandomAccess)
          try {
            $blocks = [long]$Mib * $blockSize / $randomBlock
            for ($i = 0; $i -lt $blocks; $i++) {
              # Pas de 1 048 573 blocs : un nombre premier, donc une suite qui
              # parcourt tout le fichier sans repasser deux fois au meme endroit.
              $position = ($position + 1048573) % $blocks
              $stream.Seek($position * $randomBlock, [System.IO.SeekOrigin]::Begin) | Out-Null
              $read = $stream.Read($randomBuffer, 0, $randomBlock)
              if ($read -le 0) { break }
              $bytes += $read
              if ($stopwatch.ElapsedMilliseconds -ge $BudgetMs) { break }
            }
          } finally { $stream.Dispose() }
        }
      }

      $passes++
      if ($stopwatch.ElapsedMilliseconds -ge $BudgetMs) { break }
      if ($passes -ge $MaxPasses) { break }
    }
  } catch {
    return $null
  }

  $stopwatch.Stop()
  $elapsed = [int]$stopwatch.ElapsedMilliseconds
  if ($elapsed -le 0 -or $bytes -le 0) { return $null }

  return @{
    mibPerSecond = [Math]::Round(($bytes / 1MB) / ($elapsed / 1000.0), 1)
    passes = $passes
    durationMs = $elapsed
  }
}

<#
.SYNOPSIS
  L'acces non tamponne est-il utilisable sur ce fichier ?
.DESCRIPTION
  Teste en lisant reellement : l'option s'accepte a l'ouverture mais echoue a
  la lecture quand l'alignement ne convient pas, et cette difference ne se lit
  dans aucune metadonnee. La sonde emprunte exactement le chemin de la mesure,
  ce qui est la seule facon de savoir qu'il tiendra.
#>
function Test-UnbufferedRead {
  param([string]$Path, [int]$BlockSize)

  $options = [System.IO.FileOptions]0x20000000
  try {
    $stream = [System.IO.FileStream]::new(
      $Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
      [System.IO.FileShare]::Read, $BlockSize, $options)
    try {
      $probe = New-Object byte[] $BlockSize
      return ($stream.Read($probe, 0, $BlockSize) -gt 0)
    } finally { $stream.Dispose() }
  } catch {
    return $false
  }
}

<#
.SYNOPSIS
  Supprime le fichier de travail du banc d'essai, et le dit s'il n'y arrive pas.

.DESCRIPTION
  Le nettoyage etait un `Remove-Item -ErrorAction SilentlyContinue` : un echec y
  passait sans un mot. Or ce fichier pese jusqu'a 256 Mio, et le laisser dans le
  repertoire temporaire sans le signaler est exactement le genre de silence que
  ce produit refuse ailleurs.

  Sous Windows, un antivirus ou le service d'indexation peut retenir la
  poignee quelques centaines de millisecondes apres la fermeture du flux. Trois
  tentatives espacees suffisent en pratique ; au-dela, l'echec est **rapporte**
  plutot que tu, avec le chemin, pour que quelqu'un puisse le supprimer.

  Rend `$true` si le fichier n'est plus la.
#>
function Remove-BenchmarkWorkFile {
  param([Parameter(Mandatory = $true)][string]$Path)

  for ($attempt = 1; $attempt -le 3; $attempt++) {
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    try {
      Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
      return $true
    } catch {
      if ($attempt -lt 3) { Start-Sleep -Milliseconds (100 * $attempt) }
    }
  }

  if (-not (Test-Path -LiteralPath $Path)) { return $true }

  Add-CollectionIssue -Section 'benchmark.storage' -Severity 'warning' `
    -Message ('Fichier de travail du banc d''essai non supprime : ' + $Path +
    '. Il occupe jusqu''a 256 Mio et peut etre efface a la main.') `
    -Source 'dotnet'
  return $false
}

<#
.SYNOPSIS
  Les trois mesures de stockage, fichier de travail compris.
.DESCRIPTION
  Le fichier de travail est cree dans le repertoire temporaire et supprime quoi
  qu'il arrive, y compris quand la mesure echoue. Si la suppression echoue
  malgre les tentatives, elle est **rapportee** dans `collection.issues` : un
  fichier de 256 Mio laisse en silence serait pire que l'echec lui-meme.
#>
function Get-StorageBenchmarkResultList {
  param([string]$StartedAt = '')

  $directory = [System.IO.Path]::GetTempPath()
  $mib = Get-BenchmarkStorageMib -Path $directory
  $Device = Get-BenchmarkStorageDevice -Path $directory
  $targets = @('storage-sequential-write', 'storage-sequential-read', 'storage-random-read')

  if ($mib -le 0) {
    $reason = 'Place libre insuffisante dans le repertoire temporaire : mesures ecartees pour ne pas remplir le disque.'
    return @($targets | ForEach-Object { New-BenchmarkSkip -Target $_ -Tool 'dotnet' -Reason $reason })
  }

  $path = Join-Path $directory ('sysaudit-bench-' + [guid]::NewGuid().ToString('N') + '.tmp')
  $seconds = Get-BenchmarkDurationSecond
  $budgetMs = $seconds * 1000
  $results = @()

  try {
    foreach ($target in $targets) {
      $mode = switch ($target) {
        'storage-sequential-write' { 'write' }
        'storage-sequential-read' { 'read' }
        default { 'random' }
      }

      # Les mesures de lecture ont besoin d'un fichier deja ecrit : il l'est
      # hors chronometre, faute de quoi elles mesureraient l'ecriture.
      if ($mode -ne 'write' -and -not (Test-Path $path)) {
        $seed = Measure-DiskAccess -Path $path -Mode 'write' -Mib $mib -BudgetMs 1 -MaxPasses 1
        if ($null -eq $seed) {
          $results += New-BenchmarkSkip -Target $target -Tool 'dotnet' `
            -Reason 'Creation du fichier de travail impossible.' -Status 'failed'
          continue
        }
      }

      $maxPasses = if ($mode -eq 'write') { Get-BenchmarkWritePassCount -Mib $mib } else { 4096 }

      $readOptions = [System.IO.FileOptions]::SequentialScan
      if ($mode -eq 'read') {
        if (Test-UnbufferedRead -Path $path -BlockSize 1MB) {
          $readOptions = [System.IO.FileOptions]0x20000000
        } else {
          Add-CollectionIssue -Section ('benchmark.' + $target) -Severity 'warning' `
            -Message 'Acces non tamponne refuse par le systeme de fichiers : la mesure inclut le cache du systeme.' `
            -Source 'dotnet'
        }
      }

      $measured = Measure-DiskAccess -Path $path -Mode $mode -Mib $mib `
        -BudgetMs $budgetMs -MaxPasses $maxPasses -ReadOptions $readOptions

      if ($null -eq $measured) {
        $results += New-BenchmarkSkip -Target $target -Tool 'dotnet' `
          -Reason 'La mesure n''a produit aucun debit exploitable.' -Status 'failed'
        continue
      }

      $algorithm = if ($mode -eq 'random') { 'lecture aleatoire 4 Kio' } else { 'acces sequentiel' }
      # Les parametres disent si le cache du systeme a ete contourne : deux
      # mesures qui ne l'ont pas fait de la meme facon ne sont pas comparables.
      $cache = if ($mode -eq 'write') {
        'ecriture non differee'
      } elseif ($readOptions -eq [System.IO.FileOptions]0x20000000) {
        'acces non tamponne'
      } else {
        'cache systeme inclus'
      }
      $result = New-BenchmarkResult -Target $target -Score $measured.mibPerSecond `
        -Algorithm $algorithm -StartedAt $StartedAt -Tool 'dotnet' -Device $Device `
        -Parameters ("bloc 1 Mio, fichier $mib Mio, $($measured.passes) passe(s), $cache")
      $result.unit = 'MiB/s'
      $result.durationMs = $measured.durationMs
      $result.toolVersion = [System.Environment]::Version.ToString()
      $results += $result
    }
  } finally {
    # `| Out-Null` n'est pas decoratif : en PowerShell, toute expression non
    # capturee — y compris dans un `finally` — entre dans le flux de sortie de
    # la fonction. Sans lui, le booleen de nettoyage venait s'ajouter aux trois
    # mesures, et l'appelant recevait quatre resultats dont un `$true`.
    Remove-BenchmarkWorkFile -Path $path | Out-Null
  }

  return $results
}
