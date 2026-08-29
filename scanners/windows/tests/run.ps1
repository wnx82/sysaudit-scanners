<#
.SYNOPSIS
  Tests du scanner Windows.

.DESCRIPTION
  Deux plans, sur le modele de `scanners/linux/tests/run.sh` :

   1. les fonctions pures — marqueurs d'absence, conversions, isolation des
      collecteurs, resume Markdown. Elles tournent partout ou PowerShell tourne,
      y compris sur un agent Linux ;
   2. une execution de bout en bout dont la sortie est validee contre le schema
      JSON. Elle exige Windows : les collecteurs interrogent CIM, et un agent
      Linux ne peut pas y repondre. Sur un autre systeme, ce plan est ignore
      explicitement plutot qu'echoue — un test silencieusement absent en CI ne
      prouverait rien, un test annonce comme ignore, si.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$scannerRoot = Split-Path -Parent $PSScriptRoot

# L'ordre reproduit celui de `sysaudit.ps1`. `console.ps1` en fait partie :
# `Invoke-Collector` fait avancer la barre de progression, donc tester le
# collecteur sans la console teste un scanner qui n'existe pas.
. (Join-Path $scannerRoot 'lib/core/json.ps1')
. (Join-Path $scannerRoot 'lib/core/core.ps1')
. (Join-Path $scannerRoot 'lib/core/transport.ps1')
. (Join-Path $scannerRoot 'lib/core/legacy.ps1')
. (Join-Path $scannerRoot 'lib/core/paths.ps1')
. (Join-Path $scannerRoot 'lib/core/levels.ps1')
. (Join-Path $scannerRoot 'lib/core/provision.ps1')
# Le banc d'essai n'est charge que pour ses fabriques de resultats : rien n'y
# est execute sans WinSAT, donc rien ne charge la machine de test.
. (Join-Path $scannerRoot 'lib/collectors/hardware.ps1')
. (Join-Path $scannerRoot 'lib/collectors/benchmark.ps1')
. (Join-Path $scannerRoot 'lib/collectors/media.ps1')
. (Join-Path $scannerRoot 'lib/collectors/power.ps1')
# `devices.ps1` n'est charge que pour ses fonctions pures : traduction d'un code
# d'erreur du gestionnaire de peripheriques, lecture d'un identifiant materiel,
# conversion d'une date de pilote. Le collecteur lui-meme interroge CIM, mais ce
# sont ces fonctions-la qui decident si un peripherique passe pour sain.
. (Join-Path $scannerRoot 'lib/collectors/devices.ps1')
. (Join-Path $scannerRoot 'lib/collectors/security.ps1')
. (Join-Path $scannerRoot 'lib/collectors/storage.ps1')
# `system.ps1` est charge pour `Get-DomainIdentity`, qui ne lit rien du systeme :
# elle tranche entre domaine et groupe de travail a partir d'un objet CIM qu'on
# peut lui donner, et c'est la que se joue une confusion couteuse.
. (Join-Path $scannerRoot 'lib/collectors/system.ps1')
# `network.ps1` n'est charge que pour `Group-NetIPAddressRecord`, une fonction
# pure : le collecteur lui-meme interroge des cmdlets Windows, mais le rangement
# des adresses par interface se teste partout, et c'est justement lui qui avait
# lache en production.
. (Join-Path $scannerRoot 'lib/collectors/network.ps1')
# `software.ps1`, `virtualization.ps1` et `monitoring.ps1` sont charges pour
# leurs fonctions pures : conversion de date du registre, tri des entrees de
# desinstallation, lecture d'une correspondance de port Docker, calcul d'un taux
# entre deux compteurs. Aucune n'interroge le systeme, et ce sont elles qui
# portent les regles faciles a casser sans s'en apercevoir.
. (Join-Path $scannerRoot 'lib/collectors/software.ps1')
. (Join-Path $scannerRoot 'lib/collectors/events.ps1')
. (Join-Path $scannerRoot 'lib/collectors/virtualization.ps1')
. (Join-Path $scannerRoot 'lib/collectors/monitoring.ps1')
. (Join-Path $scannerRoot 'lib/output/console.ps1')
. (Join-Path $scannerRoot 'lib/output/markdown.ps1')

$script:Passed = 0
$script:Failed = 0

function Write-Suite {
  param([string]$Name)
  Write-Host ''
  Write-Host $Name -ForegroundColor White
}

function Assert-Equal {
  param($Expected, $Actual, [string]$Label)

  if ([string]$Expected -eq [string]$Actual) {
    $script:Passed++
    Write-Host ('  OK   ' + $Label) -ForegroundColor Green
  } else {
    $script:Failed++
    Write-Host ('  ECHEC ' + $Label) -ForegroundColor Red
    Write-Host ('      attendu : ' + [string]$Expected)
    Write-Host ('      obtenu  : ' + [string]$Actual)
  }
}

function Assert-True {
  param([bool]$Condition, [string]$Label)
  Assert-Equal -Expected 'True' -Actual ([string]$Condition) -Label $Label
}

# --- Marqueurs d'absence ----------------------------------------------------

Write-Suite 'Marqueurs d''absence'

$unknown = New-Unknown -Reason 'PERMISSION_DENIED'
Assert-True ($unknown.unknown -eq $true) 'New-Unknown porte le drapeau unknown'
Assert-Equal 'PERMISSION_DENIED' $unknown.reason 'New-Unknown conserve la raison'
Assert-True (-not $unknown.ContainsKey('detail')) 'aucun detail vide n''est ajoute'

$detailed = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'smartctl absent'
Assert-Equal 'smartctl absent' $detailed.detail 'le detail est conserve quand il existe'

# Une chaine vide n'est pas une valeur : elle se lirait comme un nom vide.
$empty = Get-StringOrUnknown -Value '   ' -Reason 'UNKNOWN'
Assert-True ($empty.unknown -eq $true) 'une chaine vide devient un marqueur'

Assert-Equal 'srv-01' (Get-StringOrUnknown -Value '  srv-01  ') 'les espaces de bord sont retires'
Assert-Equal 256 ((Get-StringOrUnknown -Value ('a' * 400)).Length) 'les chaines sont bornees a 256'

# --- Valeurs d'usine --------------------------------------------------------
#
# Regression `QJVJVFA6` : les deux barrettes portent `Unknown` comme fabricant
# et `00000000` comme numero de serie, le chassis porte `To be filled by
# O.E.M.`. Ce sont des collectes reussies sur des champs jamais programmes, et
# non des echecs de collecte -- l'interface les affichait telles quelles.
$usine = Get-MeaningfulStringOrUnknown -Value 'Unknown' -Reason 'UNKNOWN'
Assert-True ($usine.unknown -eq $true) 'un texte de gabarit devient un marqueur'
Assert-Equal 'placeholder constructeur non significatif' $usine.detail `
  'le marqueur dit que le firmware n''a pas rempli le champ'

$serie = Get-MeaningfulStringOrUnknown -Value '00000000' -Reason 'UNKNOWN'
Assert-True ($serie.unknown -eq $true) 'huit zeros ne sont pas un numero de serie'

$oem = Get-MeaningfulStringOrUnknown -Value 'To be filled by O.E.M.' -Reason 'UNKNOWN'
Assert-True ($oem.unknown -eq $true) 'le texte de gabarit SMBIOS devient un marqueur'

# Rien du tout garde le motif de l'appelant : une absence de collecte n'est pas
# un champ non programme, et les deux appellent deux messages differents.
$rien = Get-MeaningfulStringOrUnknown -Value $null -Reason 'NOT_AVAILABLE'
Assert-Equal 'NOT_AVAILABLE' $rien.reason 'une absence garde le motif de l''appelant'
Assert-True (-not $rien.ContainsKey('detail')) 'une absence ne porte pas le detail d''usine'

Assert-Equal 'Corsair' (Get-MeaningfulStringOrUnknown -Value '  Corsair  ') `
  'une vraie valeur passe, debarrassee de ses bords'

$zero = Get-PositiveIntOrUnknown -Value 0
Assert-Equal '0' ([string]$zero) 'zero est une mesure, pas une absence'

$negative = Get-PositiveIntOrUnknown -Value -3
Assert-True ($negative.unknown -eq $true) 'une valeur negative devient un marqueur'

$notANumber = Get-NumberOrUnknown -Value 'abc'
Assert-True ($notANumber.unknown -eq $true) 'une valeur non numerique devient un marqueur'

# --- Conversion numerique sure ----------------------------------------------
#
# `[int64]$valeur` ecrit en dur leve des que la valeur n'est pas convertible, et
# l'exception ne remonte pas au champ fautif : elle remonte au collecteur, qui
# abandonne tout ce qu'il n'avait pas encore ecrit. WMI et les applets Storage
# rendent `Unknown`, `N/A` ou une chaine vide la ou le schema attend un
# compteur — un seul disque bavard emportait l'inventaire des autres.
Write-Suite 'Conversion numerique sure'

Assert-Equal 7200 (ConvertTo-SafeInt64 -Value 7200) 'un entier passe tel quel'
Assert-Equal 7200 (ConvertTo-SafeInt64 -Value '7200') 'une chaine numerique est convertie'
Assert-Equal 7200 (ConvertTo-SafeInt64 -Value '  7200  ') 'les espaces de bord sont ignores'
Assert-Equal -3 (ConvertTo-SafeInt64 -Value '-3') 'un entier negatif reste negatif ici'
Assert-Equal 8 (ConvertTo-SafeInt64 -Value 7.6) 'un flottant est arrondi'

foreach ($illisible in @('Unknown', 'N/A', 'n/a', '', '   ', 'abc', $null)) {
  Assert-True ($null -eq (ConvertTo-SafeInt64 -Value $illisible)) `
    ('« ' + [string]$illisible + ' » ne devient pas un nombre')
}

# Une virgule decimale francaise ne doit pas faire passer « 1,5 » pour quinze :
# la culture invariante est imposee, quelle que soit celle de la machine.
Assert-True ($null -eq (ConvertTo-SafeInt64 -Value '1,5')) `
  'une virgule decimale n''est pas un separateur de milliers'

Assert-True ($null -eq (ConvertTo-SafeInt64 -Value ([double]::NaN))) 'NaN n''est pas une mesure'
Assert-True ($null -eq (ConvertTo-SafeInt64 -Value ([double]::PositiveInfinity))) `
  'l''infini n''est pas une mesure'

# Valeurs extremes mais valides : elles doivent passer, sans quoi le durcissement
# aurait remplace une exception par une perte de donnee.
Assert-Equal ([int64]::MaxValue) (ConvertTo-SafeInt64 -Value ([int64]::MaxValue)) `
  'la plus grande valeur representable passe'
Assert-Equal 4294967295 (ConvertTo-SafeInt64 -Value 4294967295) `
  'la sentinelle 0xFFFFFFFF de Get-PhysicalDisk passe, et sera ecartee plus haut'
Assert-Equal 0 (ConvertTo-SafeInt64 -Value 0) 'zero est une mesure'

# `[uint64]` au-dela de la borne signee : sentinelle, pas mesure.
Assert-True ($null -eq (ConvertTo-SafeInt64 -Value ([uint64]::MaxValue))) `
  'une sentinelle non signee hors bornes n''est pas une mesure'

# Le chemin qui compte : le marqueur, et pas l'exception.
$smartUnknown = Get-PositiveIntOrUnknown -Value 'Unknown' -Reason 'UNKNOWN'
Assert-True ($smartUnknown.unknown -eq $true) 'un compteur SMART « Unknown » devient un marqueur'
Assert-Equal 'UNKNOWN' $smartUnknown.reason 'et non un compteur nul'

# --- Dates CIM --------------------------------------------------------------
#
# `Get-CimInstance` rend deja un `DateTime` la ou `Get-WmiObject` rendait la
# chaine `CIM_DATETIME`. Le convertisseur declarait `[string]`, PowerShell
# reserialisait donc l'objet selon la culture courante — « jeudi 19 mars 2026
# 01:00:00 » sur un poste francophone — et `bios.releaseDate` sortait en
# « date WMI invalide » sur une machine ou la date etait parfaitement lisible.
Write-Suite 'Dates CIM'

$fromCim = Convert-WmiDateOrUnknown -Value ([DateTime]::new(2026, 3, 19, 1, 0, 0))
Assert-Equal '2026-03-19' $fromCim 'un DateTime rendu par Get-CimInstance est accepte'

$fromWmi = Convert-WmiDateOrUnknown -Value '20260319000000.000000+000'
Assert-Equal '2026-03-19' $fromWmi 'la chaine CIM_DATETIME reste acceptee'

$fromIso = Convert-WmiDateOrUnknown -Value '2026-03-19'
Assert-Equal '2026-03-19' $fromIso 'une date ISO est acceptee'

$badDate = Convert-WmiDateOrUnknown -Value 'pas une date'
Assert-True ($badDate.unknown -eq $true) 'une date illisible reste un marqueur'
Assert-Equal 'UNKNOWN' $badDate.reason 'une date illisible ne devient pas une date par defaut'

$noDate = Convert-WmiDateOrUnknown -Value $null
Assert-True ($noDate.unknown -eq $true) 'une date absente reste un marqueur'

$stampFromCim = Convert-WmiDateTimeOrUnknown -Value ([DateTime]::new(2026, 3, 19, 1, 0, 0, [DateTimeKind]::Utc))
Assert-True ($stampFromCim -is [string] -and $stampFromCim.StartsWith('2026-03-19T01:00:00')) `
  'un horodatage CIM est rendu en ISO 8601'

# --- Duree d'audit ----------------------------------------------------------

Write-Suite 'Duree d''audit'

Assert-Equal 8420 (Get-AuditDurationMs -ElapsedMs 8420.7) 'duree normale, tronquee a la milliseconde'
Assert-Equal 0 (Get-AuditDurationMs -ElapsedMs 0) 'duree nulle : une valeur, pas une absence'

# Le cas qui supprimait le rapport entier : au-dela de 24,8 jours, la conversion
# `[int]` levait une exception au lieu de renoncer a un champ facultatif.
Assert-True ($null -eq (Get-AuditDurationMs -ElapsedMs 2147483648)) `
  'au-dela de la capacite d''un entier 32 bits, le champ est omis sans lever'
Assert-True ($null -eq (Get-AuditDurationMs -ElapsedMs 86400001)) `
  'au-dela d''une journee, la valeur ne mesure plus un audit'
Assert-Equal 86400000 (Get-AuditDurationMs -ElapsedMs 86400000) 'la borne d''une journee reste acceptee'
Assert-True ($null -eq (Get-AuditDurationMs -ElapsedMs -1)) 'une duree negative est omise, pas ramenee a zero'
Assert-True ($null -eq (Get-AuditDurationMs)) 'une mesure absente est omise'
Assert-True ($null -eq (Get-AuditDurationMs -ElapsedMs ([double]::NaN))) 'une mesure indefinie est omise'
Assert-True ($null -eq (Get-AuditDurationMs -ElapsedMs ([double]::PositiveInfinity))) `
  'une mesure infinie est omise'

# Le chronometre est monotone : c'est ce qui distingue cette mesure d'une
# difference de `Get-Date`, que le recalage de l'horloge fait sauter.
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
Start-Sleep -Milliseconds 20
$stopwatch.Stop()
$measured = Get-AuditDurationMs -ElapsedMs $stopwatch.Elapsed.TotalMilliseconds
Assert-True ($null -ne $measured -and $measured -ge 15) 'le chronometre mesure une duree exploitable'

# --- Services Windows -------------------------------------------------------

Write-Suite 'Services Windows'

$normalStopped = [pscustomobject]@{
  Name = 'DemandService'
  DisplayName = 'Demand Service'
  State = 'Stopped'
  StartMode = 'Manual'
  ExitCode = 0
  ServiceSpecificExitCode = 0
}
$serviceUnits = Get-WindowsServiceStabilityUnits -Services @($normalStopped) -Events @{ entries = @() }
Assert-Equal 0 $serviceUnits.failedUnits.Count 'Stopped + ExitCode 0 ne produit pas d''echec'

$runningService = [pscustomobject]@{
  Name = 'HealthyService'
  DisplayName = 'Healthy Service'
  State = 'Running'
  StartMode = 'Auto'
  ExitCode = 0
  ServiceSpecificExitCode = 0
}
$serviceUnits = Get-WindowsServiceStabilityUnits -Services @($runningService) -Events @{ entries = @() }
Assert-Equal 0 $serviceUnits.failedUnits.Count 'un service Running est sain'
Assert-Equal 0 $serviceUnits.stoppedUnits.Count 'un service Running n''est pas liste comme arrete'

$exitCodeFailure = [pscustomobject]@{
  Name = 'BrokenService'
  DisplayName = 'Broken Service'
  State = 'Stopped'
  StartMode = 'Auto'
  ExitCode = 1066
  ServiceSpecificExitCode = 0
}
$serviceUnits = Get-WindowsServiceStabilityUnits -Services @($exitCodeFailure) -Events @{ entries = @() }
Assert-Equal 1 $serviceUnits.failedUnits.Count 'Stopped + ExitCode non nul produit une anomalie'
Assert-Equal 'ExitCode=1066' $serviceUnits.failedUnits[0].reason 'le code de sortie reste dans la preuve'

$scmFailure = [pscustomobject]@{
  Name = 'AppService'
  DisplayName = 'Application Service'
  State = 'Stopped'
  StartMode = 'Manual'
  ExitCode = 0
  ServiceSpecificExitCode = 0
}
$scmEvents = @{
  entries = @(
    [pscustomobject]@{
      provider = 'Service Control Manager'
      nativeId = '7031'
      summary = 'The AppService service terminated unexpectedly.'
      evidence = @()
      lastSeenAt = '2026-07-25T12:00:00.000Z'
    }
  )
}
$serviceUnits = Get-WindowsServiceStabilityUnits -Services @($scmFailure) -Events $scmEvents
Assert-Equal 1 $serviceUnits.failedUnits.Count 'Stopped + erreur SCM rattachee produit une anomalie'
Assert-Equal 'SCM 7031' $serviceUnits.failedUnits[0].reason 'l''identifiant SCM reste dans la preuve'
Assert-Equal '2026-07-25T12:00:00.000Z' $serviceUnits.failedUnits[0].since 'la date SCM sert de date de preuve'

$quietAuto = [pscustomobject]@{
  Name = 'AutoButQuiet'
  DisplayName = 'Auto But Quiet'
  State = 'Stopped'
  StartMode = 'Auto'
  ExitCode = 0
  ServiceSpecificExitCode = 0
}
$serviceUnits = Get-WindowsServiceStabilityUnits -Services @($quietAuto) -Events @{ entries = @() }
Assert-Equal 0 $serviceUnits.failedUnits.Count 'Auto arrete sans preuve ne devient pas critique'
Assert-Equal 1 $serviceUnits.stoppedUnits.Count 'Auto arrete sans preuve reste visible separement'

# --- Delai de reessai apres quota -------------------------------------------

Write-Suite 'Delai de reessai'

Assert-Equal 12 (Get-RetryAfterSeconds -Header '12') 'l''en-tete Retry-After est la premiere source'
Assert-Equal 12 (Get-RetryAfterSeconds -Body '{"retryAfterSeconds":12}') 'a defaut, le champ du corps JSON'

# Le cas reel du 2026-08-07 : l'API n'annoncait le delai que dans sa phrase.
Assert-Equal 12 (Get-RetryAfterSeconds -Body '{"error":"BAD_REQUEST","message":"Rate limit exceeded, retry in 12 seconds"}') `
  'en dernier recours, le nombre annonce dans le message'

Assert-Equal 12 (Get-RetryAfterSeconds -Header '12' -Body '{"retryAfterSeconds":99}') `
  'l''en-tete prime sur le corps'

# Sans plancher, un delai nul ferait boucler l'envoi aussi vite que le refus.
Assert-Equal 1 (Get-RetryAfterSeconds -Header '0') 'un delai nul est ramene au plancher'
Assert-Equal 1 (Get-RetryAfterSeconds) 'sans aucune source, le plancher s''applique'
Assert-Equal 1 (Get-RetryAfterSeconds -Header 'plus tard' -Body 'pas du JSON') `
  'une source illisible ne fait pas attendre indefiniment'
Assert-Equal 120 (Get-RetryAfterSeconds -Header '99999') 'un delai aberrant est plafonne'

# --- Compatibilite legacy --------------------------------------------------

Write-Suite 'Compatibilite legacy'

Assert-True (Test-LegacyCommand -Name 'Get-Date') 'une commande existante est detectee'
Assert-True (-not (Test-LegacyCommand -Name 'Commande-qui-nexiste-pas')) 'une commande absente est refusee'

$preferred = Get-LegacyCommandName -Candidates @('Commande-qui-nexiste-pas', 'Get-Date')
Assert-Equal 'Get-Date' $preferred 'le premier candidat disponible est retenu'

$modernKind = Resolve-LegacyScannerKind -Version '10.0.22631' -Caption 'Microsoft Windows 11 Pro'
Assert-Equal 'windows' $modernKind 'Windows 10 et 11 restent sur le scanner moderne'

$legacyKind = Resolve-LegacyScannerKind -Version '6.1.7601' -Caption 'Windows 7 Professionnel'
Assert-Equal 'windows-legacy' $legacyKind 'Windows 7 bascule sur le profil legacy'

$minimalKind = Resolve-LegacyScannerKind -Version '5.1.2600' -Caption 'Windows XP Professional'
Assert-Equal 'windows-minimal' $minimalKind 'Windows XP reste dans le profil minimal'

$legacyOs = Get-LegacyOsVersion -OperatingSystem ([pscustomobject]@{
    Caption = 'Windows 8.1 Professionnel'
    Version = '6.3.9600'
    BuildNumber = '9600'
    OSArchitecture = '64-bit'
    CSDVersion = ''
    ServicePackMajorVersion = 0
  })
Assert-Equal 'windows-legacy' $legacyOs.scannerKind 'la version de l''OS determine le scanner legacy'
Assert-Equal '6.3.9600' $legacyOs.version 'la version de l''OS est conservee'

$legacyMarker = New-LegacyUnsupportedMarker -Capability 'events.classic' -Reason 'NOT_AVAILABLE' -Detail 'Get-EventLog absent'
Assert-True ($legacyMarker.unknown -eq $true) 'le marqueur legacy reste un marqueur d''absence'
Assert-Equal 'events.classic' $legacyMarker.capability 'la capacite legacy absente est tracee'
Assert-True ([string]$legacyMarker.detail -like '*Get-EventLog absent*') 'le detail legacy est conserve'

$legacyCaps = Get-LegacyRuntimeCapabilities
Assert-True ($legacyCaps.ContainsKey('eventReader')) 'les capacites runtime legacy publient un lecteur d''evenements'
Assert-True ($legacyCaps.ContainsKey('inventoryReader')) 'les capacites runtime legacy publient un lecteur d''inventaire'

# --- Isolation des collecteurs ---------------------------------------------

Write-Suite 'Isolation des collecteurs'

$ok = Invoke-Collector -Section 'test' -Body { return 42 }
Assert-Equal '42' ([string]$ok) 'un collecteur qui reussit rend sa valeur'

$before = @(Get-CollectionIssueList).Count
$failed = Invoke-Collector -Section 'test.failing' -Body { throw 'panne simulee' }
$after = @(Get-CollectionIssueList).Count

Assert-True ($null -eq $failed) 'un collecteur en echec rend null'
Assert-Equal ($before + 1) $after 'un collecteur en echec rapporte un probleme'

$issue = @(Get-CollectionIssueList)[-1]
Assert-Equal 'test.failing' $issue.section 'le probleme porte la section concernee'
Assert-Equal 'error' $issue.severity 'un collecteur interrompu est une erreur'
Assert-True ([string]$issue.message -like '*panne simulee*') 'le message d''origine est conserve'

# --- Duree par collecteur ---------------------------------------------------

Write-Suite 'Duree par collecteur'

$timings = @(Get-CollectionTimings)
Assert-True ($timings.Count -ge 2) 'chaque collecteur execute laisse sa mesure'

$measured = $timings | Where-Object { $_.section -eq 'test' }
Assert-True ($null -ne $measured) 'un collecteur qui reussit porte sa duree'
Assert-True ($measured.durationMs -ge 0) 'la duree mesuree n''est jamais negative'

# Un collecteur en echec est chronometre comme les autres : il a coute du temps
# a l'utilisateur, et l'estimation affichee avant l'audit doit le refleter.
$failedTiming = $timings | Where-Object { $_.section -eq 'test.failing' }
Assert-True ($null -ne $failedTiming) 'un collecteur en echec porte aussi sa duree'

# Une mesure inexploitable est omise, jamais ramenee a zero : le champ absent se
# lit « on ne sait pas », un zero se lirait « instantane ».
$before = @(Get-CollectionTimings).Count
Add-CollectionTiming -Section 'horloge.negative' -DurationMs -42
Assert-Equal $before (@(Get-CollectionTimings).Count) 'une duree negative n''est pas enregistree'

# --- Niveaux de diagnostic --------------------------------------------------

Write-Suite 'Niveaux de diagnostic'

$script:ScanProfile = 'quick'
Assert-Equal 'quick' (Get-CurrentLevel) 'le profil rapide donne le niveau Rapide'
Assert-Equal 'summary' (Get-LevelDepth -Section 'cpus') 'processeur en resume au niveau Rapide'
# La carte mere a rejoint le niveau Rapide le 2026-08-16 : quarante
# millisecondes cote Linux, une requete CIM cote Windows. `events` a pris sa
# place d'exemple de section hors niveau Rapide.
Assert-Equal 'standard' (Get-LevelDepth -Section 'motherboard') 'carte mere collectee des le niveau Rapide'
Assert-Equal 'skipped' (Get-LevelDepth -Section 'events') 'historique non parcouru au niveau Rapide'
Assert-True (Test-LevelCollectsSection -Section 'storage') 'le resume stockage est collecte au niveau Rapide'

$script:ScanProfile = 'security'
Assert-Equal 'quick' (Get-CurrentLevel) 'le profil historique security retombe sur Rapide'

$script:ScanProfile = 'standard'
Assert-Equal 'standard' (Get-LevelDepth -Section 'cpus') 'processeur complet au niveau Normale'
Assert-True (Test-DepthAtLeast -Section 'memory' -Wanted 'standard') 'les barrettes sont lues au niveau Normale'

# Profondeurs honorees au niveau Rapide.
#
# Le scanner Windows n'appelait `Test-DepthAtLeast` qu'a un seul endroit dans
# tout le fichier : l'audit Rapide y collectait donc tout ce qu'il savait
# collecter, plus riche que la matrice ne l'annonce et plus lent que la duree
# affichee. Deux sous-collectes couteuses s'alignent desormais sur ce que le
# scanner Linux reserve deja au niveau Normale.
$script:ScanProfile = 'quick'
Assert-True (-not (Test-DepthAtLeast -Section 'storage' -Wanted 'standard')) `
  'SMART reste hors du niveau Rapide'
Assert-True (-not (Test-DepthAtLeast -Section 'gpus' -Wanted 'standard')) `
  'les sorties d''affichage restent hors du niveau Rapide'

$script:CollectionIssues = @()
$null = Get-MonitorInventory
$displaySkip = @($script:CollectionIssues | Where-Object { $_.section -eq 'gpus.displays' })
Assert-Equal 1 $displaySkip.Count 'l''absence des sorties d''affichage est declaree au niveau Rapide'

# `Get-StorageInventory` n'est pas appele ici : il atteint `Get-CimInstance`
# hors de tout try/catch, et ce cmdlet n'existe pas sous PowerShell Linux ou
# tourne cette suite. Le garde-fou lui-meme est verifie par `Test-DepthAtLeast`
# ci-dessus ; l'ecriture du motif suit exactement le meme chemin que celui des
# sorties d'affichage, verifie juste au-dessus.

# Au niveau Normale, les deux redeviennent collectables : la restriction est
# bien une restriction de niveau, pas une suppression.
$script:ScanProfile = 'standard'
Assert-True (Test-DepthAtLeast -Section 'storage' -Wanted 'standard') 'SMART revient au niveau Normale'
Assert-True (Test-DepthAtLeast -Section 'gpus' -Wanted 'standard') `
  'les sorties d''affichage reviennent au niveau Normale'

$script:CollectionIssues = @()

# Peripheriques et pilotes : collectes depuis le collecteur PnP, en resume.
# Ils etaient absents a tous les niveaux, ce qui rendait six controles du moteur
# d'analyse ineluctablement non evalues sous Windows.
$script:ScanProfile = 'stress'
foreach ($section in @('drivers', 'devices')) {
  Assert-Equal 'summary' (Get-LevelDepth -Section $section) ($section + ' est collecte en resume sous Windows')
}

# Le resume, et pas au-dela : CIM n'expose pas la largeur negociee des liens
# PCIe, et aucune version publiee de pilote n'est etablie hors ligne.
foreach ($section in @('drivers', 'devices')) {
  Assert-True (-not (Test-DepthAtLeast -Section $section -Wanted 'standard')) `
    ($section + ' ne pretend pas a la profondeur du scanner Linux')
}

# Le niveau Rapide continue de les sauter : ce sont les deux sections les plus
# lentes du scan, et le profil annonce une minute.
$script:ScanProfile = 'quick'
foreach ($section in @('drivers', 'devices')) {
  Assert-Equal 'skipped' (Get-LevelDepth -Section $section) ($section + ' reste hors du niveau Rapide')
}
$script:ScanProfile = 'stress'

# Deux plafonds declares par l'audit des niveaux du 2026-08-09 : le scanner
# Windows ne monte pas au-dela du resume sur ces sections, faute de collecteur.
# `network` n'a ni ports en ecoute, ni routes, ni proxy ; `security` n'a ni
# mises a jour en attente, ni comptes, ni protocoles obsoletes. La table le dit
# desormais, au lieu de laisser croire a une collecte complete.
foreach ($section in @('network', 'security')) {
  Assert-Equal 'summary' (Get-LevelDepth -Section $section) ($section + ' est plafonne au resume sous Windows')
  Assert-True (Test-LevelCollectsSection -Section $section) ($section + ' reste collecte a tous les niveaux')
}

# `power` a quitte cette liste : le plan d'alimentation et les batteries sont
# desormais collectes. Le plafond subsiste sur ce que Win32_Battery ne publie
# pas — le compteur de cycles — et se lit dans le rapport, champ par champ,
# plutot que par une section entiere absente.
Assert-Equal 'standard' (Get-LevelDepth -Section 'power') 'l''alimentation est collectee sous Windows'
Assert-Equal 'standard' (Get-LevelDepth -Section 'stability') 'la stabilite est collectee sous Windows'
# `standard`, et non `summary` : les deux scanners parcourent la fenetre entiere
# du journal des le niveau Normale, avec les deux severites. La matrice annonçait
# un resume moins couteux que la collecte reellement faite — corrige par l'audit
# des niveaux du 2026-08-09.
Assert-Equal 'standard' (Get-LevelDepth -Section 'events' -Level 'standard') 'l''historique couvre la fenetre entiere des le niveau Normale'
Assert-Equal 'skipped' (Get-LevelDepth -Section 'events' -Level 'quick') 'l''historique n''est pas parcouru au niveau Rapide'

# Logiciel et virtualisation ont rejoint le scanner Windows. Leur premier niveau
# est verifie ici, et pas seulement leur presence : l'inventaire logiciel coute
# une lecture complete du registre, il n'a rien a faire au niveau Rapide.
Assert-Equal 'standard' (Get-LevelDepth -Section 'software') 'l''inventaire logiciel est collecte au niveau Poussee'
Assert-Equal 'standard' (Get-FirstLevelCollecting -Section 'software') 'l''inventaire logiciel arrive au niveau Normale'
Assert-Equal 'quick' (Get-FirstLevelCollecting -Section 'virtualization') 'la virtualisation arrive des le niveau Rapide'
Assert-Equal 'summary' (Get-LevelDepth -Section 'virtualization' -Level 'quick') 'la virtualisation reste un resume au niveau Rapide'
# Les capteurs passent en collecte approfondie a partir du niveau Complete :
# c'est la que les trois releves par sonde sont pris, et les deux secondes
# qu'ils coutent n'ont rien a faire dans un audit Normale.
Assert-Equal 'extended' (Get-LevelDepth -Section 'sensors') 'les capteurs sont approfondis au niveau Poussee sous Windows'
Assert-Equal 'standard' (Get-LevelDepth -Section 'sensors' -Level 'standard') 'les capteurs restent un releve unique au niveau Normale sous Windows'
Assert-Equal 'summary' (Get-LevelDepth -Section 'startup') 'les demarrages sont plafonnes au niveau Resume sous Windows'
# `summary` a tous les niveaux : `Win32_SoundDevice` donne l'inventaire des
# peripheriques, jamais la topologie des flux, et aucun niveau n'en obtient
# davantage. Monter la case promettait une collecte que personne ne faisait.
Assert-Equal 'summary' (Get-LevelDepth -Section 'audio') 'l''audio reste un inventaire de peripheriques a tous les niveaux'
Assert-Equal 'quick' (Get-FirstLevelCollecting -Section 'sensors') 'les capteurs arrivent des le niveau Rapide sous Windows'
Assert-Equal 'quick' (Get-FirstLevelCollecting -Section 'motherboard') 'la carte mere arrive des le niveau Rapide'

# Une section inconnue de la table est collectee, jamais ignoree en silence.
Assert-Equal 'standard' (Get-LevelDepth -Section 'section-inexistante') 'une section hors table reste collectee'

# `events` sert d'exemple depuis le 2026-08-16 : les capteurs et la carte mere
# ont rejoint le niveau Rapide, l'historique des incidents est desormais la
# premiere section que Normale ajoute.
$script:ScanProfile = 'quick'
$levelIssuesBefore = @(Get-CollectionIssueList).Count
Add-LevelSkip -Section 'events'
$levelIssue = @(Get-CollectionIssueList)[-1]
Assert-Equal ($levelIssuesBefore + 1) (@(Get-CollectionIssueList).Count) 'une section hors matrice est declaree'
# Le motif n'est plus range dans `source`, qui portait tantot la commande
# fautive et tantot la raison : il a son champ, lu par la plateforme.
Assert-Equal 'NOT_COLLECTED' $levelIssue.reason 'le motif est attribue au niveau'
Assert-True ([string]$levelIssue.message -like '*relancer au niveau Normale*') `
  'une absence due au niveau dit lequel la collecterait'

# Une section qu'aucun niveau ne collecte sous Windows ne renvoie pas vers un
# niveau superieur : elle dit que le scanner ne sait pas la produire.
#
# Plus aucune section reelle n'illustre ce cas depuis le collecteur PnP : toutes
# celles de la matrice Windows sont collectees a un niveau ou a un autre. La
# regle est donc verifiee sur une matrice de test, plutot que supprimee — le
# jour ou une section repassera hors de portee, c'est ce motif-la qu'elle devra
# porter, et rien ne le prouverait sans ce test.
$matrixBefore = $script:LevelMatrix
$script:LevelMatrix = @'
firmware       skipped  skipped  skipped  skipped
'@
Add-LevelSkip -Section 'firmware'
$levelIssue = @(Get-CollectionIssueList)[-1]
Assert-Equal 'UNSUPPORTED' $levelIssue.reason 'une limite du scanner n''est pas une limite du niveau'
$script:LevelMatrix = $matrixBefore

$script:ScanProfile = 'standard'

# --- Motif d'absence des journaux -------------------------------------------
#
# Les treize compteurs de stabilite, le compteur de redemarrages et sa fenetre
# partagent un seul motif. Il valait `NOT_AVAILABLE` / « aucun journal
# d'evenements lisible » **quelle que soit la cause** : un audit Rapide, qui ne
# demande pas la section, produisait donc un rapport affirmant que le journal
# Windows etait en panne. Le lecteur cherchait une avarie que personne n'avait
# constatee, et le moteur rangeait les treize controles en « outil absent »,
# avec pour remede d'installer un outil qui n'a jamais manque.
Write-Suite 'Motif d''absence des journaux'

$script:ScanProfile = 'quick'
$absentByLevel = Get-EventsAbsenceMarker
Assert-Equal 'NOT_COLLECTED' $absentByLevel.reason `
  'au niveau Rapide, l''historique n''est pas demande — il n''est pas illisible'
Assert-True ([string]$absentByLevel.detail -like '*relancer au niveau Normale*') `
  'le motif nomme le niveau qui collecterait l''historique'

$script:ScanProfile = 'standard'
$absentByRead = Get-EventsAbsenceMarker
Assert-Equal 'NOT_AVAILABLE' $absentByRead.reason `
  'a un niveau qui demande l''historique, l''absence est bien un defaut de lecture'

# Une section ecartee a la demande n'a pas la meme reponse : relancer plus haut
# ne la ramenerait pas, seul l'utilisateur peut la redemander.
$excludedBefore = @($script:SkipSections)
Set-SkippedSectionList -Sections @('events')
$absentBySkip = Get-EventsAbsenceMarker
Assert-Equal 'NOT_COLLECTED' $absentBySkip.reason 'une section ecartee reste non collectee'
Assert-True ([string]$absentBySkip.detail -like '*-Skip*') `
  'le motif dit que l''exclusion vient de la ligne de commande'
Set-SkippedSectionList -Sections $excludedBefore

# Le compteur reprend le motif qu'on lui donne, plutot que d'en inventer un.
$counter = Get-IncidentCount -Events $null -Category 'POWER' -Absent $absentByLevel
Assert-Equal 'NOT_COLLECTED' $counter.count.reason 'le compteur porte le motif fourni'
Assert-Equal 'NOT_COLLECTED' $counter.observationWindowMs.reason 'la fenetre porte le meme motif'
Assert-Equal 'NOT_COLLECTED' $counter.lastAt.reason 'la date porte le meme motif'

# Sans motif fourni, le repli reste celui d'un journal ouvert et muet : c'est le
# seul cas ou « illisible » est la verite.
$fallback = Get-IncidentCount -Events $null -Category 'POWER'
Assert-Equal 'NOT_AVAILABLE' $fallback.count.reason 'le repli reste un defaut de lecture'

$script:ScanProfile = 'standard'

# --- Peripheriques et pilotes -----------------------------------------------

Write-Suite 'Peripheriques et pilotes'

# `ConfigManagerErrorCode` est la seule source d'etat qui vaille : `Status` vaut
# « OK » sur un peripherique dont le pilote a echoue.
Assert-Equal 'OK' (Get-DeviceStatusFromErrorCode -Code 0) 'le code 0 decrit un peripherique sain'
Assert-Equal 'DRIVER_MISSING' (Get-DeviceStatusFromErrorCode -Code 28) 'le code 28 decrit un peripherique sans pilote'
Assert-Equal 'DISABLED' (Get-DeviceStatusFromErrorCode -Code 22) 'le code 22 decrit un peripherique desactive'
Assert-Equal 'DRIVER_ERROR' (Get-DeviceStatusFromErrorCode -Code 43) 'le code 43 decrit un pilote en echec'
Assert-Equal 'UNKNOWN_DEVICE' (Get-DeviceStatusFromErrorCode -Code 1) 'le code 1 decrit un peripherique non identifie'

# Un etat non lu n'est pas un etat sain : repondre « OK » fabriquerait un
# satisfecit sur un peripherique dont on ne sait rien.
Assert-Equal 'UNKNOWN' (Get-DeviceStatusFromErrorCode -Code $null) 'un code absent ne devient pas OK'
Assert-Equal 'UNKNOWN' (Get-DeviceStatusFromErrorCode -Code 'abc') 'un code illisible ne devient pas OK'
Assert-Equal 'UNKNOWN' (Get-DeviceStatusFromErrorCode -Code 99) 'un code hors documentation reste inconnu'

Assert-Equal 'PCI' (Get-DeviceBusFromHardwareId -HardwareId 'PCI\VEN_8086&DEV_1533') 'le bus se lit dans le prefixe'
Assert-Equal 'USB' (Get-DeviceBusFromHardwareId -HardwareId 'USB\VID_046D&PID_C52B') 'le bus USB est reconnu'
Assert-Equal 'USB' (Get-DeviceBusFromHardwareId -HardwareId 'USBSTOR\DISK') 'le stockage USB reste sur le bus USB'
# Un peripherique racine ou logiciel n'a rien a faire dans un inventaire cense
# decrire du materiel enfichable.
Assert-Equal 'OTHER' (Get-DeviceBusFromHardwareId -HardwareId 'ROOT\SYSTEM\0000') 'un peripherique racine va dans OTHER'
Assert-Equal 'OTHER' (Get-DeviceBusFromHardwareId -HardwareId '') 'un identifiant vide va dans OTHER'

$ids = Get-DeviceIdentifiers -HardwareId 'PCI\VEN_8086&DEV_1533&SUBSYS_00011179'
Assert-Equal '8086' $ids.vendorId 'le constructeur PCI est extrait'
Assert-Equal '1533' $ids.deviceId 'le produit PCI est extrait'

$usbIds = Get-DeviceIdentifiers -HardwareId 'USB\VID_046D&PID_C52B'
Assert-Equal '046D' $usbIds.vendorId 'le constructeur USB est extrait'
Assert-Equal 'C52B' $usbIds.deviceId 'le produit USB est extrait'

$noIds = Get-DeviceIdentifiers -HardwareId 'ROOT\SYSTEM\0000'
Assert-Equal '' $noIds.vendorId 'un identifiant sans champ constructeur reste vide'

Assert-Equal '2024-01-15' (Convert-DriverDate -Value '20240115000000.000000+000') 'une date CIM devient une date ISO'
Assert-Equal '2024-01-15' (Convert-DriverDate -Value ([datetime]'2024-01-15')) 'un DateTime .NET devient une date ISO'
# Une date illisible rend le champ absent plutot que faux.
Assert-True ($null -eq (Convert-DriverDate -Value 'jamais')) 'une date illisible ne devient pas une date'
Assert-True ($null -eq (Convert-DriverDate -Value $null)) 'une date absente ne devient pas une date'

$entity = [pscustomobject]@{
  DeviceID = 'PCI\VEN_10DE&DEV_2504'
  PNPDeviceID = 'PCI\VEN_10DE&DEV_2504\4&1A2B3C&0&0008'
  Name = 'NVIDIA GeForce RTX 3060'
  Manufacturer = 'NVIDIA'
  PNPClass = 'Display'
  ConfigManagerErrorCode = 0
}
$record = ConvertTo-DeviceRecord -Entity $entity -DriversByDeviceId @{ 'PCI\VEN_10DE&DEV_2504' = 'nvlddmkm.sys' }
Assert-Equal 'PCI' $record.bus 'le peripherique est range sur son bus'
Assert-Equal 'OK' $record.status 'l''etat vient du code du gestionnaire'
Assert-Equal '10DE' $record.vendorId 'le constructeur est extrait de l''identifiant'
Assert-Equal 'nvlddmkm.sys' $record.driver 'le pilote associe est rattache au peripherique'

# Sans correspondance dans la table des pilotes, le champ porte un marqueur : un
# peripherique dont on ignore le pilote n'est pas un peripherique sans pilote.
$orphan = ConvertTo-DeviceRecord -Entity $entity -DriversByDeviceId @{}
Assert-True ($orphan.driver.unknown -eq $true) 'un pilote non retrouve devient un marqueur, pas une absence de pilote'
Assert-Equal 'OK' $orphan.status 'l''etat ne depend pas de la table des pilotes'

$signed = [pscustomobject]@{
  DeviceID = 'PCI\VEN_10DE&DEV_2504'
  DeviceName = 'NVIDIA GeForce RTX 3060'
  Manufacturer = 'NVIDIA'
  DriverVersion = '31.0.15.3699'
  DriverProviderName = 'NVIDIA'
  DriverDate = '20240115000000.000000+000'
  InfName = 'oem42.inf'
  IsSigned = $true
}
$driver = ConvertTo-DriverRecord -Signed $signed
Assert-Equal '31.0.15.3699' $driver.version 'la version du pilote est conservee'
Assert-Equal '2024-01-15' $driver.date 'la date du pilote est convertie'
Assert-Equal 'True' ([string]$driver.signed) 'la signature lue est conservee'
# Aucune version publiee n'est connue hors ligne : promettre une mise a jour
# sans source serait exactement l'invention que le produit s'interdit.
Assert-Equal 'CURRENT' $driver.status 'aucun pilote n''est declare a mettre a jour sans source'

$unsignedUnknown = ConvertTo-DriverRecord -Signed ([pscustomobject]@{
  DeviceID = 'PCI\VEN_1234&DEV_5678'
  DeviceName = 'Carte inconnue'
  IsSigned = $null
})
Assert-True ($unsignedUnknown.signed.unknown -eq $true) 'une signature non rapportee ne devient pas « non signe »'

# --- Collecteurs media ------------------------------------------------------

Write-Suite 'Collecteurs media'

$script:CollectionProvenance = @{}
$audio = Get-AudioSection
Assert-True ($null -ne $audio) 'la section audio est construite'
Assert-True ($audio.ContainsKey('devices')) 'la section audio expose la liste des peripheriques'
Assert-True ((Get-CollectionProvenance).ContainsKey('audio.devices')) 'la provenance audio est enregistree'

$startup = Get-StartupSection
Assert-True ($null -ne $startup) 'la section demarrage est construite'
Assert-True ($startup.ContainsKey('items')) 'la section demarrage expose la liste des elements'
Assert-True ((Get-CollectionProvenance).ContainsKey('startup.items')) 'la provenance demarrage est enregistree'

# --- Adresses reseau --------------------------------------------------------

Write-Suite 'Rangement des adresses IP'

# Le defaut constate en production : `Get-NetIPAddress` annonce l'index en
# `UInt32`, `Get-NetAdapter` le relit en `Int32`. Une table de hachage
# PowerShell compare ses cles par type autant que par valeur, la recherche
# renvoyait donc `$null` — sans erreur, sans message, et le rapport affichait
# « aucune adresse » sur neuf interfaces qui en avaient toutes.
$records = @(
  [pscustomobject]@{ InterfaceIndex = [uint32]7; IPAddress = '192.168.1.20'; PrefixLength = 24; AddressFamily = 'InterNetwork' },
  [pscustomobject]@{ InterfaceIndex = [uint32]7; IPAddress = 'fe80::21a:2bff:fe3c:4d5e%7'; PrefixLength = 64; AddressFamily = 'InterNetworkV6' },
  [pscustomobject]@{ InterfaceIndex = [uint32]12; IPAddress = '10.0.2.15'; PrefixLength = 24; AddressFamily = 'InterNetwork' }
)
$grouped = Group-NetIPAddressRecord -Records $records

$byInt32 = $grouped[[string][int]7]
Assert-True ($null -ne $byInt32) 'un index relu en Int32 retrouve ses adresses'
Assert-Equal 1 (@($byInt32.ipv4).Count) 'une adresse IPv4 est rangee dans la colonne IPv4'
Assert-Equal '192.168.1.20' (@($byInt32.ipv4)[0].address) 'l''adresse IPv4 est conservee telle quelle'
Assert-Equal 24 (@($byInt32.ipv4)[0].prefixLength) 'la longueur de prefixe suit l''adresse'
Assert-Equal 1 (@($byInt32.ipv6).Count) 'une adresse IPv6 est rangee dans la colonne IPv6'

# Le suffixe de zone est un detail Windows : le schema attend une adresse.
Assert-Equal 'fe80::21a:2bff:fe3c:4d5e' (@($byInt32.ipv6)[0].address) 'le suffixe de zone est retire'

Assert-Equal 1 (@($grouped[[string]12].ipv4).Count) 'chaque interface garde ses propres adresses'

# Sans famille annoncee, le deux-points tranche : verser une IPv6 dans la
# colonne IPv4 passerait le schema, qui accepte la chaine, et echouerait au
# format bien plus loin.
$sansFamille = Group-NetIPAddressRecord -Records @(
  [pscustomobject]@{ InterfaceIndex = 3; IPAddress = '2001:db8::1'; PrefixLength = 64; AddressFamily = $null },
  [pscustomobject]@{ InterfaceIndex = 3; IPAddress = '172.16.0.5'; PrefixLength = 16; AddressFamily = $null }
)
Assert-Equal 1 (@($sansFamille[[string]3].ipv6).Count) 'une adresse a deux-points est tenue pour IPv6'
Assert-Equal 1 (@($sansFamille[[string]3].ipv4).Count) 'une adresse pointee reste IPv4'

# Une entree vide ne cree pas d'adresse vide : le rapport n'invente pas.
$vides = Group-NetIPAddressRecord -Records @(
  $null,
  [pscustomobject]@{ InterfaceIndex = 5; IPAddress = ''; PrefixLength = 24; AddressFamily = 'InterNetwork' }
)
Assert-Equal 0 $vides.Count 'ni entree nulle ni adresse vide ne produisent d''interface'

Assert-Equal 0 (Group-NetIPAddressRecord -Records @()).Count 'aucun enregistrement donne aucun groupe'

Write-Suite 'Collecteur capteurs'

$sensorSection = Get-SensorSection
Assert-True ($null -ne $sensorSection) 'la section capteurs est construite'
Assert-True ($sensorSection.ContainsKey('temperatures')) 'la section capteurs expose les temperatures'
Assert-True ($sensorSection.ContainsKey('fans')) 'la section capteurs expose les ventilateurs'
Assert-True ($sensorSection.ContainsKey('voltages')) 'la section capteurs expose les tensions'
Assert-True ($sensorSection.ContainsKey('powers')) 'la section capteurs expose les puissances'

# --- Banc d'essai -----------------------------------------------------------

Write-Suite 'Banc d''essai'

# Les fabriques de resultats sont pures : elles se testent partout, y compris
# sur un agent Linux ou WinSAT n'existe pas.
$benchResult = New-BenchmarkResult -Target 'cpu-multi' -Score 8.4 `
  -Algorithm 'WinSAT cpuformal' -StartedAt '2026-07-29T10:00:00Z'
Assert-Equal 'completed' $benchResult.status 'une mesure aboutie porte son statut'
Assert-Equal '8.4' ([string]$benchResult.score) 'l''indice est conserve tel quel'
Assert-Equal 'indice WinSAT' $benchResult.unit 'un indice n''est pas un debit : l''unite le dit'
Assert-Equal '2026-07-29T10:00:00Z' $benchResult.startedAt 'le debut de la mesure est conserve'
Assert-True ($benchResult.finishedAt -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$') `
  'la fin de la mesure est horodatee'

$benchSkip = New-BenchmarkSkip -Target 'storage-random-read' -Tool 'winsat' `
  -Reason 'WinSAT ne publie qu''un indice composite.'
Assert-Equal 'skipped' $benchSkip.status 'une mesure ecartee porte son statut'
Assert-True ($benchSkip.score.unknown -eq $true) 'une mesure ecartee n''invente pas de score'
Assert-True ([string]$benchSkip.detail -like '*composite*') 'le motif accompagne la mesure ecartee'

$benchFail = New-BenchmarkSkip -Target 'gpu' -Tool 'winsat' -Reason 'Indice absent.' -Status 'failed'
Assert-Equal 'failed' $benchFail.status 'une mesure tentee sans resultat se distingue d''une mesure ecartee'

# Cette fonction rend trois mesures **quelle que soit** la plateforme : hors
# Windows `Win32_WinSAT` est injoignable, sous Windows il repond. Un tableau vide
# se lirait dans les deux cas comme « aucune mesure prevue ».
#
# L'assertion portait auparavant sur `completed -eq 0`, c'est-a-dire sur le fait
# de **ne pas** tourner sous Windows. Elle a echoue a la premiere execution sur
# un vrai Windows 11, ou WinSAT publie des indices valides — le scanner faisait
# exactement ce qu'on lui demande, et le test disait le contraire. Ce qui doit
# tenir partout, c'est le lien entre le statut et le contenu.
$winsatResults = @(Get-WinSatResultList -StartedAt '2026-07-29T10:00:00Z')
Assert-True ($winsatResults.Count -ge 3) 'trois mesures sont declarees, avec ou sans indices'

foreach ($result in $winsatResults) {
  if ($result.status -eq 'completed') {
    # Un indice WinSAT va de 1,0 a 9,9 : une mesure aboutie porte un nombre,
    # jamais un marqueur.
    Assert-True (($result.score -is [double]) -or ($result.score -is [int]) -or ($result.score -is [decimal])) `
      ($result.target + ' : une mesure aboutie porte un indice numerique')
    Assert-Equal 'indice WinSAT' ([string]$result.unit) `
      ($result.target + ' : l''unite dit qu''il s''agit d''un indice, pas d''un debit')
  } else {
    Assert-True ($result.score.unknown -eq $true) `
      ($result.target + ' : une mesure non aboutie n''invente pas d''indice')
  }
}

# --- Version de protocole, par couple cible + outil -------------------------

Write-Suite 'Banc d''essai — version de protocole'

# La constante unique qui regnait ici ne pouvait pas etre juste : elle etait
# censee changer quand *l'une* des mesures changeait, et elle invalidait alors
# *toutes* les autres. Ces tests verrouillent le decoupage par couple.
Assert-Equal '1.0.0' ([string](Get-BenchmarkProtocolVersion -Target 'cpu-multi' -Tool 'winsat')) `
  'l''indice processeur porte le protocole de son couple'
Assert-Equal '1.0.0' ([string](Get-BenchmarkProtocolVersion -Target 'storage-random-read' -Tool 'dotnet')) `
  'la lecture aleatoire .NET porte le protocole de son couple'
Assert-True ($null -eq (Get-BenchmarkProtocolVersion -Target 'gaming' -Tool 'winsat')) `
  'une charge mixte jamais executee ne se voit pas attribuer de protocole'
Assert-True ($null -eq (Get-BenchmarkProtocolVersion -Target 'cpu-multi' -Tool 'dotnet')) `
  'un couple qui n''existe pas n''herite pas du protocole d''un voisin'

# `tool` etait ecrase par l'appelant **apres** la construction du dictionnaire :
# la version de protocole, deja calculee, decrivait alors WinSAT pour une mesure
# venue de .NET. Le couple decide du protocole ; il ne peut pas etre connu apres.
$protoDotnet = New-BenchmarkResult -Target 'storage-sequential-read' -Score 3287.3 `
  -Algorithm 'acces sequentiel' -Tool 'dotnet'
Assert-Equal 'dotnet' ([string]$protoDotnet.tool) 'l''outil est celui qu''on a passe'
Assert-Equal '1.0.0' ([string]$protoDotnet.protocolVersion) `
  'le protocole est celui du couple, pas celui de WinSAT'

$sansProto = New-BenchmarkSkip -Target 'gaming' -Tool 'winsat' -Reason 'Charge mixte non executee.'
Assert-True (-not $sansProto.ContainsKey('protocolVersion')) `
  'aucune mesure n''a eu lieu : lui donner un protocole affirmerait une methode non employee'

$avecProto = New-BenchmarkSkip -Target 'cpu-multi' -Tool 'winsat' -Reason 'WinSAT absent.'
Assert-Equal '1.0.0' ([string]$avecProto.protocolVersion) `
  'une cible ecartee garde la methode qui etait en vigueur'

# --- Le composant que la mesure a reellement charge --------------------------

Write-Suite 'Banc d''essai — composant mesure'

$avecDevice = New-BenchmarkResult -Target 'gpu' -Score 9.9 -Algorithm 'WinSAT d3d' `
  -Device 'NVIDIA GeForce RTX 5070'
Assert-Equal 'NVIDIA GeForce RTX 5070' ([string]$avecDevice.device) `
  'la carte evaluee est nommee dans le resultat'

$sansDevice = New-BenchmarkResult -Target 'cpu-multi' -Score 9.4 -Algorithm 'WinSAT cpuformal'
Assert-True (-not $sansDevice.ContainsKey('device')) `
  'une mesure qui ne nomme aucun composant n''en invente pas'

# Les deux sondes interrogent CIM et le registre : hors Windows elles doivent
# rendre une chaine vide plutot que lever. Une chaine vide est un resultat, et
# le bon — l'analyse ecarte alors la mesure pour ambiguite.
$disqueSonde = Get-BenchmarkStorageDevice -Path ([System.IO.Path]::GetTempPath())
Assert-True ($disqueSonde -is [string]) `
  'le disque porteur se resout sans lever, meme hors Windows'
$adaptateurSonde = Get-WinSatGraphicsAdapter
Assert-True ($adaptateurSonde -is [string]) `
  'l''adaptateur evalue se lit sans lever, meme hors Windows'

# --- Mesures de stockage ----------------------------------------------------

Write-Suite 'Banc d''essai — stockage'

# Ces mesures n'utilisent que .NET : elles s'executent donc reellement ici, y
# compris sur un agent Linux. C'est la seule partie du banc d'essai Windows qui
# soit verifiable ailleurs que sous Windows, et c'est aussi celle qui ecrit sur
# le disque — donc celle qu'il faut le plus verifier.

$script:ScanProfile = 'standard'
$env:SYSAUDIT_BENCH_SECONDS = '1'
Assert-Equal '1' ([string](Get-BenchmarkDurationSecond)) 'la duree demandee est respectee'
$env:SYSAUDIT_BENCH_SECONDS = '99999'
Assert-Equal '120' ([string](Get-BenchmarkDurationSecond)) 'une duree absurde est plafonnee'
$env:SYSAUDIT_BENCH_SECONDS = ''
$script:ScanProfile = 'stress'
Assert-Equal '20' ([string](Get-BenchmarkDurationSecond)) 'mesure soutenue au niveau Poussee'
Assert-Equal '8' ([string](Get-BenchmarkWritePassCount -Mib 256)) 'ecritures bornees a 2 Gio au niveau Poussee'
$script:ScanProfile = 'standard'
Assert-Equal '4' ([string](Get-BenchmarkWritePassCount -Mib 256)) 'ecritures bornees a 1 Gio ailleurs'
Assert-Equal '1' ([string](Get-BenchmarkWritePassCount -Mib 0)) 'une taille nulle ne divise pas par zero'

# Releve des fichiers de travail deja presents : ce qui suit ne doit etre
# reproche qu'a cette suite.
$benchFilesBefore = @(Get-ChildItem ([System.IO.Path]::GetTempPath()) -File `
    -Filter 'sysaudit-bench-*.tmp' -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })

$storageMib = Get-BenchmarkStorageMib -Path ([System.IO.Path]::GetTempPath())
Assert-True (($storageMib -ge 0) -and ($storageMib -le 256)) `
  ('le budget disque reste borne (' + $storageMib + ' Mio)')

# La boucle s'arrete a la premiere des deux limites, et le fichier de travail
# disparait quoi qu'il arrive.
$env:SYSAUDIT_BENCH_SECONDS = '1'
$probe = Join-Path ([System.IO.Path]::GetTempPath()) ('sysaudit-test-' + [guid]::NewGuid().ToString('N'))
$written = Measure-DiskAccess -Path $probe -Mode 'write' -Mib 8 -BudgetMs 100000 -MaxPasses 2
Assert-Equal '2' ([string]$written.passes) 'la boucle respecte le plafond de passes'
Assert-True ($written.mibPerSecond -gt 0) 'un debit est produit'
$read = Measure-DiskAccess -Path $probe -Mode 'read' -Mib 8 -BudgetMs 300 -MaxPasses 4096
Assert-True ($read.durationMs -ge 300) 'la boucle atteint la duree visee'
$random = Measure-DiskAccess -Path $probe -Mode 'random' -Mib 8 -BudgetMs 300 -MaxPasses 4096
Assert-True ($random.mibPerSecond -gt 0) 'la lecture aleatoire produit un debit'
Remove-Item $probe -Force -ErrorAction SilentlyContinue

$absent = Measure-DiskAccess -Path (Join-Path ([System.IO.Path]::GetTempPath()) 'sysaudit-inexistant') `
  -Mode 'read' -Mib 8 -BudgetMs 100 -MaxPasses 1
Assert-True ($null -eq $absent) 'un fichier absent ne produit pas de mesure inventee'

$storageResults = @(Get-StorageBenchmarkResultList -StartedAt '2026-07-29T10:00:00Z')
Assert-Equal '3' ([string]$storageResults.Count) 'les trois modes d''acces sont rapportes'
foreach ($result in $storageResults) {
  Assert-True (@('completed', 'skipped', 'failed') -contains $result.status) `
    ($result.target + ' porte un statut connu')
  if ($result.status -eq 'completed') {
    Assert-Equal 'dotnet' ([string]$result.tool) `
      ($result.target + ' : la mesure vient de .NET, et le dit')
    Assert-Equal '1.0.0' ([string]$result.protocolVersion) `
      ($result.target + ' : le protocole est celui du couple .NET, pas celui de WinSAT')
    # Le disque porteur n'est nomme que lorsqu'il est identifiable — hors
    # Windows, il ne l'est pas, et le champ est alors absent plutot que vide.
    if ($result.ContainsKey('device')) {
      Assert-True ([string]$result.device -match '^\\\\\.\\PHYSICALDRIVE\d+$') `
        ($result.target + ' : le disque est nomme comme l''inventaire le publie')
    }
  }
}
$env:SYSAUDIT_BENCH_SECONDS = ''

# Le fichier de travail ne survit pas a la mesure.
#
# La comparaison porte sur les fichiers **apparus pendant** cette suite, pas sur
# le contenu du repertoire temporaire. La version precedente comptait tout
# `sysaudit-bench-*.tmp` present : un scan interrompu la veille — ou le scan qui
# venait d'echouer sur une erreur de syntaxe — faisait echouer un test qui
# n'avait rien mesure de neuf. Un test doit rapporter ce qu'il a provoque, pas
# ce qu'il a trouve.
$leftovers = @(Get-ChildItem ([System.IO.Path]::GetTempPath()) -File -Filter 'sysaudit-bench-*.tmp' -ErrorAction SilentlyContinue)
$newLeftovers = @($leftovers | Where-Object { $benchFilesBefore -notcontains $_.FullName })
Assert-Equal '0' ([string]$newLeftovers.Count) 'aucun fichier de travail laisse derriere par cette suite'

if ($leftovers.Count -gt $newLeftovers.Count) {
  Write-Host ('  NOTE ' + ($leftovers.Count - $newLeftovers.Count) +
    ' fichier(s) de travail plus ancien(s) dans ' + [System.IO.Path]::GetTempPath() +
    ' — laisses par une execution precedente, pas par celle-ci.') -ForegroundColor DarkGray
}

# Le nettoyage doit aussi **dire** qu'il a echoue plutot que se taire : un
# fichier de 256 Mio laisse en silence serait pire que l'echec lui-meme.
$missing = Join-Path ([System.IO.Path]::GetTempPath()) ('sysaudit-bench-absent-' + [guid]::NewGuid().ToString('N') + '.tmp')
Assert-True (Remove-BenchmarkWorkFile -Path $missing) `
  'un fichier deja absent est un nettoyage reussi, pas un echec'

$survivor = Join-Path ([System.IO.Path]::GetTempPath()) ('sysaudit-bench-' + [guid]::NewGuid().ToString('N') + '.tmp')
Set-Content -LiteralPath $survivor -Value 'x' -NoNewline
Assert-True (Remove-BenchmarkWorkFile -Path $survivor) 'un fichier accessible est supprime'
Assert-True (-not (Test-Path -LiteralPath $survivor)) 'le fichier a bien disparu'

# --- Adresses d'interface : toujours un tableau -----------------------------

Write-Suite 'Adresses d''interface'

# Deuxieme defaut de production sur ce champ precis. PowerShell deballe un
# tableau d'un seul element : `ipv4` sortait en objet des qu'une carte portait
# une seule adresse — c'est-a-dire le cas normal — et **tout rapport Windows
# etait refuse** par le schema. Le controle porte donc sur le JSON produit, pas
# sur le type de la variable : c'est la serialisation qui a lache.
$uneAdresse = @{ ipv4 = @(@{ address = '192.168.1.33'; prefixLength = 24 }); ipv6 = @() }
$deuxAdresses = @{ ipv4 = @(@{ address = 'a'; prefixLength = 24 }, @{ address = 'b'; prefixLength = 24 }); ipv6 = @() }

$jsonUne = @{ ipv4 = (Get-InterfaceAddressList -Addresses $uneAdresse -Family 'ipv4') } |
  ConvertTo-Json -Depth 6 -Compress
Assert-True ($jsonUne -like '*"ipv4":[[]*') 'une seule adresse reste un tableau en JSON'
Assert-True ($jsonUne -like '*192.168.1.33*') 'l''adresse unique n''est pas perdue'

$jsonDeux = @{ ipv4 = (Get-InterfaceAddressList -Addresses $deuxAdresses -Family 'ipv4') } |
  ConvertTo-Json -Depth 6 -Compress
Assert-True ($jsonDeux -like '*"ipv4":[[]*') 'deux adresses restent un tableau'

# Aucune adresse doit donner `[]`, jamais `null` : le schema refuse les deux
# autres, et `null` se lirait comme une lecture ratee plutot que comme une
# interface sans adresse.
$jsonVide = @{ ipv4 = (Get-InterfaceAddressList -Addresses @{ ipv4 = @(); ipv6 = @() } -Family 'ipv4') } |
  ConvertTo-Json -Depth 6 -Compress
Assert-Equal '{"ipv4":[]}' $jsonVide 'aucune adresse donne un tableau vide, pas null'

$jsonAbsent = @{ ipv4 = (Get-InterfaceAddressList -Addresses $null -Family 'ipv4') } |
  ConvertTo-Json -Depth 6 -Compress
Assert-Equal '{"ipv4":[]}' $jsonAbsent 'une interface sans entree donne un tableau vide'

# --- Ports en ecoute : ce qui sort de la machine -----------------------------

Write-Suite 'Ports en ecoute'

# `SEC-008` — « Service expose sur toutes les interfaces » — rendait un feu vert
# sur un poste dont OpenSSH ecoutait sur le port 22 : le scanner Windows ne
# collectait aucun port, et la liste vide se lisait « aucun service n'ecoute ».
# Elle est desormais collectee, et c'est ce tri-la qui decide du verdict.
#
# `Get-NetTCPConnection` n'existe pas hors de Windows ; ce tri, si, et il se
# verifie donc partout — y compris sur l'agent Linux qui fait tourner la suite.

foreach ($locale in @('127.0.0.1', '127.0.0.53', '127.255.255.254', '::1', '0:0:0:0:0:0:0:1')) {
  Assert-True (-not (Test-ListeningPortExposed -Address $locale)) `
    ('« ' + $locale +' » ne sort pas de la machine')
}

foreach ($ouverte in @('0.0.0.0', '::', '192.168.1.33', 'fe80::1', '10.0.0.7')) {
  Assert-True (Test-ListeningPortExposed -Address $ouverte) `
    ('« ' + $ouverte + ' » est joignable depuis le reseau')
}

# Le suffixe de zone nomme l'interface, pas l'adresse : `::1%1` reste la boucle.
Assert-True (-not (Test-ListeningPortExposed -Address '::1%1')) `
  'un suffixe de zone ne rend pas la boucle exposee'
Assert-True (Test-ListeningPortExposed -Address 'fe80::1%12') `
  'un suffixe de zone ne rend pas une adresse de lien locale a la machine'

# Le doute va vers le signalement : sans adresse lisible, rien ne prouve que
# l'ecoute reste locale, et `SEC-008` existe pour reperer une ecoute ouverte.
foreach ($illisible in @('', '   ', 'pas-une-adresse', $null)) {
  Assert-True (Test-ListeningPortExposed -Address $illisible) `
    ('une adresse illisible n''est pas declaree locale : « ' + [string]$illisible + ' »')
}

# --- Batteries : toujours un tableau ----------------------------------------

Write-Suite 'Batteries'

# Meme piege que pour `network.interfaces[].ipv4` : un portable Windows 11 avec
# une seule batterie produisait `{...}` au lieu de `[{...}]`, et l'API rejetait
# le rapport entier sur `$.power.batteries`.
$jsonBatterieUnique = @{ batteries = (Get-BatteryReportList -Batteries @(
      @{
        name = 'BAT0'
        manufacturer = 'OEM'
        model = 'BAT0'
        serialNumber = (New-Unknown -Reason 'NOT_AVAILABLE')
        technology = 'Li-ion'
        chargePercent = 87
        status = 'DISCHARGING'
        designCapacityWh = 57
        fullChargeCapacityWh = 43.12
        cycleCount = (New-Unknown -Reason 'NOT_AVAILABLE')
        voltageVolts = 11.52
      }
    )) } | ConvertTo-Json -Depth 6 -Compress
Assert-True ($jsonBatterieUnique -like '*"batteries":[[]*') 'une seule batterie reste un tableau en JSON'
Assert-True ($jsonBatterieUnique -like '*"name":"BAT0"*') 'la batterie unique n''est pas perdue'

$jsonBatteriesVides = @{ batteries = (Get-BatteryReportList -Batteries @()) } | ConvertTo-Json -Depth 6 -Compress
Assert-Equal '{"batteries":[]}' $jsonBatteriesVides 'aucune batterie donne un tableau vide'

# --- Runtimes logiciels : toujours un tableau -------------------------------

Write-Suite 'Runtimes logiciels'

# Meme classe de defaut que pour `ipv4` et `power.batteries` : avec un seul
# runtime trouve, PowerShell pouvait emettre `{...}` au lieu de `[{...}]`, ce
# qui faisait rejeter tout le rapport sur `$.software.runtimes`.
$jsonRuntimeUnique = @{ runtimes = @(Get-RuntimeList) } | ConvertTo-Json -Depth 6 -Compress
if ($jsonRuntimeUnique -ne '{"runtimes":[]}') {
  Assert-True ($jsonRuntimeUnique -like '*"runtimes":[[]*') 'un seul runtime reste un tableau en JSON'
}

$jsonRuntimesForces = @{
  runtimes = @(
    @{
      name = 'node'
      version = 'v22.0.0'
      path = 'C:\Program Files\nodejs\node.exe'
    }
  )
} | ConvertTo-Json -Depth 6 -Compress
Assert-True ($jsonRuntimesForces -like '*"runtimes":[[]*') 'un runtime force reste un tableau'
Assert-True ($jsonRuntimesForces -like '*"name":"node"*') 'le runtime unique n''est pas perdu'

$jsonRuntimesVides = @{ runtimes = @() } | ConvertTo-Json -Depth 6 -Compress
Assert-Equal '{"runtimes":[]}' $jsonRuntimesVides 'aucun runtime donne un tableau vide'

# --- VRAM GPU : memoire dediee reelle ---------------------------------------

Write-Suite 'VRAM GPU'

Assert-True ($null -eq (Convert-DxDiagMemoryToBytes -Value '')) `
  'une valeur dxdiag vide ne produit pas de taille'
Assert-Equal 12718178304 (Convert-DxDiagMemoryToBytes -Value '12129 MB') `
  'la memoire dediee dxdiag en Mo devient des octets'
Assert-Equal 12718178304 (Convert-DxDiagMemoryToBytes -Value '12 129 Mo') `
  'la memoire dediee dxdiag en francais devient des octets'
Assert-Equal 12884901888 (Convert-RegistryMemoryToBytes -Value ([byte[]](0,0,0,0,3,0,0,0))) `
  'une taille de VRAM en binaire little-endian est lue depuis le registre'
Assert-Equal 12884901888 (Convert-RegistryMemoryToBytes -Value 12884901888) `
  'une taille de VRAM numerique du registre est conservee'

$dxdiagSample = @'
---------------
Display Devices
---------------
           Card name: Parsec Virtual Display Adapter
        Device Key: Enum\ROOT\DISPLAY\0000
     Display Memory: 4095 MB
   Dedicated Memory: 4095 MB
      Shared Memory: 0 MB

           Card name: NVIDIA GeForce RTX 5070
        Device Key: Enum\PCI\VEN_10DE&DEV_2782&SUBSYS_00000000&REV_A1
     Display Memory: 20290 MB
   Dedicated Memory: 12129 MB
      Shared Memory: 8161 MB
'@

$dxdiagDevices = @(Get-DxDiagDisplayDeviceListFromText -Text $dxdiagSample)
Assert-Equal 2 $dxdiagDevices.Count 'deux GPU sont parses depuis la sortie dxdiag'
Assert-Equal 'PARSEC VIRTUAL DISPLAY ADAPTER' $dxdiagDevices[0].cardName.ToUpperInvariant() `
  'le nom de la premiere carte est conserve'
Assert-Equal 'PCI\VEN_10DE&DEV_2782&SUBSYS_00000000&REV_A1' $dxdiagDevices[1].deviceKey `
  'la clef de peripherique dxdiag est normalisee'
Assert-Equal 12718178304 $dxdiagDevices[1].dedicatedMemoryBytes `
  'la VRAM dediee parsee est conservee'

$gpuByPnp = [pscustomobject]@{
  Name = 'NVIDIA GeForce RTX 5070'
  PNPDeviceID = 'PCI\VEN_10DE&DEV_2782&SUBSYS_00000000&REV_A1\69D52DCC1E2DB04800'
}
Assert-Equal 12718178304 (Get-GpuDedicatedMemoryBytes -Gpu $gpuByPnp -DxDiagDevices $dxdiagDevices) `
  'la correspondance par PNPDeviceID retrouve la VRAM dediee meme avec un suffixe d''instance'

$gpuByName = [pscustomobject]@{
  Name = 'NVIDIA GeForce RTX 5070'
  PNPDeviceID = ''
}
Assert-Equal 12718178304 (Get-GpuDedicatedMemoryBytes -Gpu $gpuByName -DxDiagDevices $dxdiagDevices) `
  'la correspondance par nom sert de repli si la clef PnP manque'

$gpuUnknown = [pscustomobject]@{
  Name = 'Carte inconnue'
  PNPDeviceID = 'PCI\VEN_FFFF&DEV_FFFF'
}
Assert-True ($null -eq (Get-GpuDedicatedMemoryBytes -Gpu $gpuUnknown -DxDiagDevices $dxdiagDevices)) `
  'un GPU absent de dxdiag ne remonte pas une valeur inventee'

$gpuParsec = [pscustomobject]@{
  Name = 'Parsec Virtual Display Adapter'
  AdapterCompatibility = 'Parsec Cloud, Inc.'
  PNPDeviceID = 'ROOT\DISPLAY\0001'
}
Assert-True ($null -eq (Get-GpuDedicatedMemoryBytes -Gpu $gpuParsec -DxDiagDevices @(
      @{
        cardName = 'Parsec Virtual Display Adapter'
        deviceKey = 'ROOT\DISPLAY\0001'
        dedicatedMemoryBytes = 12718178304
      }
    ))) 'un adaptateur virtuel ne recupere pas la VRAM dxdiag'

$registryAdapters = @(Get-GpuRegistryAdapterListFromItems -Items @(
    [pscustomobject]@{
      MatchingDeviceId = 'PCI\VEN_10DE&DEV_2F04&SUBSYS_53221462'
      'HardwareInformation.AdapterString' = 'NVIDIA GeForce RTX 5070'
      'HardwareInformation.qwMemorySize' = 12884901888
    },
    [pscustomobject]@{
      MatchingDeviceId = 'ROOT\DISPLAY'
      'HardwareInformation.AdapterString' = 'Parsec Virtual Display Adapter'
      'HardwareInformation.qwMemorySize' = 12884901888
    }
  ))
Assert-Equal 2 $registryAdapters.Count 'les adaptateurs GPU du registre sont prepares'
Assert-Equal 12884901888 (Get-GpuRegistryMemoryBytes -Gpu ([pscustomobject]@{
      Name = 'NVIDIA GeForce RTX 5070'
      AdapterCompatibility = 'NVIDIA'
      PNPDeviceID = 'PCI\VEN_10DE&DEV_2F04&SUBSYS_53221462&REV_A1\69D52DCC1E2DB04800'
    }) -RegistryAdapters $registryAdapters) `
  'la VRAM du registre est associee au GPU physique'
Assert-True ($null -eq (Get-GpuRegistryMemoryBytes -Gpu $gpuParsec -RegistryAdapters $registryAdapters)) `
  'un adaptateur virtuel ne recupere pas la VRAM du registre'

$dxdiagSampleFr = @'
---------------
Périphériques d’affichage
---------------
           Nom de la carte: NVIDIA GeForce RTX 5070
     Clé du périphérique: Enum\PCI\VEN_10DE&DEV_2F04&SUBSYS_53221462&REV_A1
     Mémoire d’affichage: 20290 Mo
       Mémoire dédiée: 12129 Mo
          Mémoire partagée: 8161 Mo
'@

$dxdiagDevicesFr = @(Get-DxDiagDisplayDeviceListFromText -Text $dxdiagSampleFr)
Assert-Equal 1 $dxdiagDevicesFr.Count 'la sortie dxdiag localisee en francais est analysee'
Assert-Equal 'PCI\VEN_10DE&DEV_2F04&SUBSYS_53221462&REV_A1' $dxdiagDevicesFr[0].deviceKey `
  'la clef dxdiag francaise est normalisee'
Assert-Equal 12718178304 $dxdiagDevicesFr[0].dedicatedMemoryBytes `
  'la VRAM dediee localisee en francais est lue'

# --- Nature d'un disque ------------------------------------------------------

Write-Suite 'Nature d''un disque'

# Le cas reel, que l'ancien test manquait : `Win32_DiskDrive` presente les NVMe
# derriere la pile de stockage, avec `InterfaceType = SCSI` et
# `MediaType = Fixed hard disk media`. L'ancienne heuristique lisait cette
# derniere phrase comme « mecanique » et affichait « HDD - SCSI » sur un SSD.
# Les faits viennent desormais de `Get-PhysicalDisk`, qui connait les deux.
Assert-Equal 'NVME' (Get-DiskKindFromFacts -MediaType 'SSD' -BusType 'NVME' `
    -Model 'Samsung SSD 990 PRO 1TB') 'un SSD NVMe reste un NVMe'

Assert-Equal 'NVME' (Get-DiskKindFromFacts -MediaType '' -BusType 'NVME' `
    -Model 'Samsung SSD 990 PRO 1TB') 'le bus suffit a reconnaitre un NVMe'

# Le defaut corrige : sans nature de support, aucune conclusion. Une lacune
# visible vaut mieux qu'une erreur invisible.
Assert-Equal 'UNKNOWN' (Get-DiskKindFromFacts -MediaType '' -BusType 'SCSI' `
    -Model 'Samsung SSD 990 PRO 1TB') 'un support inconnu derriere du SCSI ne devient pas HDD'

Assert-Equal 'UNKNOWN' (Get-DiskKindFromFacts -MediaType '' -BusType '' -Model '') `
  'ni support ni bus : aucune conclusion'

Assert-Equal 'SSD' (Get-DiskKindFromFacts -MediaType 'SSD' -BusType 'SATA' -Model 'Crucial MX500') `
  'un SSD SATA'
Assert-Equal 'HDD' (Get-DiskKindFromFacts -MediaType 'HDD' -BusType 'SATA' -Model 'WDC WD10EZEX') `
  'un disque mecanique SATA'
Assert-Equal 'USB' (Get-DiskKindFromFacts -MediaType '' -BusType 'USB' -Model 'Generic Flash Disk') `
  'une cle USB sans support declare'
Assert-Equal 'VIRTUAL' (Get-DiskKindFromFacts -MediaType '' -BusType '' -Model 'VMware Virtual disk') `
  'un disque virtuel s''annonce dans son modele'

# --- Etat de Microsoft Defender ----------------------------------------------

Write-Suite 'Etat de Microsoft Defender'

# Le cas qui manquait : quand un antivirus tiers prend la main, Defender ne
# s'arrete pas, il cede la protection temps reel. Sans `AMRunningMode`, cet
# etat se lisait comme un utilisateur ayant coupe sa protection -- et chaque
# poste correctement protege aurait ete signale.
Assert-Equal 'PASSIVE' (Get-DefenderState -Status ([pscustomobject]@{
      AMRunningMode = 'Passive Mode'
      RealTimeProtectionEnabled = $false
      AMServiceEnabled = $true
    })) 'Defender passif derriere un antivirus tiers'

Assert-Equal 'PASSIVE' (Get-DefenderState -Status ([pscustomobject]@{
      AMRunningMode = 'SxS Passive Mode'
      RealTimeProtectionEnabled = $false
      AMServiceEnabled = $true
    })) 'le mode passif cote a cote est aussi un mode passif'

Assert-Equal 'PASSIVE' (Get-DefenderState -Status ([pscustomobject]@{
      AMRunningMode = 'EDR Block Mode'
      RealTimeProtectionEnabled = $false
      AMServiceEnabled = $true
    })) 'le mode blocage EDR ne protege pas a l''ouverture'

Assert-Equal 'ACTIVE' (Get-DefenderState -Status ([pscustomobject]@{
      AMRunningMode = 'Normal'
      RealTimeProtectionEnabled = $true
      AMServiceEnabled = $true
    })) 'Defender seul et actif'

# Mode normal mais protection coupee : c'est l'anomalie, et elle doit rester
# distincte du mode passif.
Assert-Equal 'DISABLED' (Get-DefenderState -Status ([pscustomobject]@{
      AMRunningMode = 'Normal'
      RealTimeProtectionEnabled = $false
      AMServiceEnabled = $true
    })) 'mode normal sans temps reel : une anomalie, pas un mode passif'

Assert-Equal 'DISABLED' (Get-DefenderState -Status ([pscustomobject]@{
      AMRunningMode = 'Not running'
      RealTimeProtectionEnabled = $false
      AMServiceEnabled = $false
    })) 'Defender arrete'

# Mode inconnu : on ne fabrique jamais `PASSIVE`, qui demande de savoir qu'un
# autre produit a la main.
Assert-Equal 'ACTIVE' (Get-DefenderState -Status ([pscustomobject]@{
      AMRunningMode = 'Mode Inedit'
      RealTimeProtectionEnabled = $true
      AMServiceEnabled = $true
    })) 'un mode non reconnu retombe sur les booleens'

Assert-Equal 'DISABLED' (Get-DefenderState -Status ([pscustomobject]@{
      AMRunningMode = ''
      RealTimeProtectionEnabled = $true
      AMServiceEnabled = $false
    })) 'service arrete : aucun mode ne le rend actif'

# --- Fraicheur des definitions -----------------------------------------------

Assert-Equal $true (Get-DefenderSignaturesFresh -Status ([pscustomobject]@{
      AntivirusSignatureAge = 0
      AntispywareSignatureAge = 0
    })) 'definitions du jour'

# Une machine eteinte le week-end rend legitimement deux ou trois jours : crier
# au loup dessus decredibiliserait le controle.
Assert-Equal $true (Get-DefenderSignaturesFresh -Status ([pscustomobject]@{
      AntivirusSignatureAge = 3
      AntispywareSignatureAge = 2
    })) 'trois jours restent acceptables'

Assert-Equal $false (Get-DefenderSignaturesFresh -Status ([pscustomobject]@{
      AntivirusSignatureAge = 12
      AntispywareSignatureAge = 0
    })) 'la plus ancienne des deux bases decide'

$signaturesInconnues = Get-DefenderSignaturesFresh -Status ([pscustomobject]@{
    AntivirusSignatureAge = $null
    AntispywareSignatureAge = $null
  })
Assert-Equal $true ($signaturesInconnues -is [hashtable] -and $signaturesInconnues.unknown) `
  'un age non publie laisse un marqueur, pas un verdict'

# --- Etat d'un produit tiers -------------------------------------------------

Assert-Equal 'ACTIVE' (Get-SecurityCenterState -Decoded @{
    enabled = $true; realtimeProtection = $true
  }) 'produit tiers actif'

Assert-Equal 'DISABLED' (Get-SecurityCenterState -Decoded @{
    enabled = $false; realtimeProtection = $false
  }) 'produit tiers desactive'

# Le Centre de securite ne publie pas de mode d'execution : `PASSIVE` ne peut
# pas s'en deduire, et le fabriquer serait affirmer ce que la source ne dit pas.
Assert-Equal 'DISABLED' (Get-SecurityCenterState -Decoded @{
    enabled = $true; realtimeProtection = $false
  }) 'actif sans temps reel : le pire des deux cas, jamais PASSIVE'

$etatIllisible = Get-SecurityCenterState -Decoded @{
  enabled = (New-Unknown -Reason 'UNKNOWN'); realtimeProtection = (New-Unknown -Reason 'UNKNOWN')
}
Assert-Equal 'UNAVAILABLE' $etatIllisible 'etat illisible : le scanner n''a pas su'

# --- Identite reseau de la machine ------------------------------------------

Write-Suite 'Domaine et groupe de travail'

# `Win32_ComputerSystem.Domain` porte le domaine **ou** le groupe de travail :
# seul `PartOfDomain` dit lequel. Recopier ce champ sans le lire ferait passer
# tout un parc en groupe de travail pour un parc joint a un annuaire.
$joined = Get-DomainIdentity -ComputerSystem ([pscustomobject]@{
    PartOfDomain = $true
    Domain = 'cabinet.lan'
    DNSHostName = 'poste-014'
  })

Assert-Equal 'poste-014.cabinet.lan' ([string]$joined.fqdn) 'le nom qualifie joint le nom court au domaine'
Assert-Equal 'cabinet.lan' ([string]$joined.domain) 'le domaine est repris tel quel'
Assert-True ($joined.workgroup -is [hashtable]) 'une machine jointe n''a pas de groupe de travail'

$standalone = Get-DomainIdentity -ComputerSystem ([pscustomobject]@{
    PartOfDomain = $false
    Domain = 'WORKGROUP'
    Workgroup = 'WORKGROUP'
    DNSHostName = 'poste-014'
  })

Assert-Equal 'WORKGROUP' ([string]$standalone.workgroup) 'hors domaine, la valeur devient le groupe de travail'
Assert-True ($standalone.domain -is [hashtable]) 'un groupe de travail n''est pas publie comme un domaine'
# Hors domaine, il n'y a pas de nom qualifie : rendre le nom court en ferait un.
Assert-True ($standalone.fqdn -is [hashtable]) 'hors domaine, aucun nom qualifie n''est fabrique'

# --- Valeurs de remplissage du firmware -------------------------------------

Write-Suite 'Textes de fabrique SMBIOS'

Assert-Equal '' (Get-MeaningfulSmbiosValue -Value 'To Be Filled By O.E.M.') `
  'un texte de gabarit n''est pas une etiquette d''inventaire'
Assert-Equal '' (Get-MeaningfulSmbiosValue -Value 'Default string') 'un gabarit alternatif est ecarte'
Assert-Equal '' (Get-MeaningfulSmbiosValue -Value $null) 'une valeur absente reste vide'
Assert-Equal 'POSTE-COMPTA-014' (Get-MeaningfulSmbiosValue -Value ' POSTE-COMPTA-014 ') `
  'une etiquette reelle est conservee, sans ses espaces'

# --- Ecrans relies ----------------------------------------------------------

Write-Suite 'Ecrans relies'

Assert-Equal 'DELL U2720Q' (Convert-MonitorCodeUnitsToText -Value @(68,69,76,76,32,85,50,55,50,48,81,0,0)) `
  'les identifiants EDID WMI sont convertis en texte lisible'
Assert-Equal 'DISPLAY\DEL4098\5&10A58F0E&0&UID4357' `
  (ConvertTo-MonitorInstanceKey -Value 'DISPLAY\DEL4098\5&10a58f0e&0&UID4357_0') `
  'la clef d''instance d''ecran est normalisee'
Assert-Equal 'HDMI' (Get-MonitorConnectionLabel -Value 6) 'le code de connexion HDMI est reconnu'
Assert-Equal '' (Get-MonitorConnectionLabel -Value 42) 'un code de connexion inconnu ne produit pas de faux libelle'

$monitorDisplays = @(Get-MonitorInventoryFromSources `
    -MonitorIds @(
      [pscustomobject]@{
        Active = $true
        InstanceName = 'DISPLAY\DEL4098\5&10a58f0e&0&UID4357_0'
        UserFriendlyName = @(68,69,76,76,32,85,50,55,50,48,81,0)
        ManufacturerName = @(68,69,76,0)
      }
    ) `
    -Connections @(
      [pscustomobject]@{
        InstanceName = 'DISPLAY\DEL4098\5&10a58f0e&0&UID4357_0'
        VideoOutputTechnology = 6
      }
    ) `
    -DesktopMonitors @(
      [pscustomobject]@{
        PNPDeviceID = 'DISPLAY\DEL4098\5&10A58F0E&0&UID4357'
        Name = 'DELL U2720Q'
        ScreenWidth = 3840
        ScreenHeight = 2160
        ScreenRefreshRate = 60
      }
    ))

Assert-Equal 1 $monitorDisplays.Count 'un ecran actif est collecte depuis WMI'
Assert-Equal 'DELL U2720Q' ([string]$monitorDisplays[0].name) 'le nom de l''ecran est conserve'
Assert-Equal '3840x2160' ([string]$monitorDisplays[0].resolution) 'la resolution du moniteur est renseignee'
Assert-Equal '60' ([string]$monitorDisplays[0].refreshRateHz) 'la frequence du moniteur est conservee'
Assert-Equal 'HDMI' ([string]$monitorDisplays[0].connection) 'le type de connexion du moniteur est conserve'

$monitorWithSerial = @(Get-MonitorInventoryFromSources `
    -MonitorIds @(
      [pscustomobject]@{
        Active = $true
        InstanceName = 'DISPLAY\DEL4098\5&10a58f0e&0&UID4357_0'
        UserFriendlyName = @(68,69,76,76,32,85,50,55,50,48,81,0)
        ManufacturerName = @(68,69,76,0)
        SerialNumberID = @(67,78,45,48,65,66,67,68,45,55,50,0)
      }
    ) `
    -Connections @() `
    -DesktopMonitors @())

Assert-Equal 'DELL U2720Q' ([string]$monitorWithSerial[0].model) `
  'le modele publie par l''ecran est repris tel quel'
Assert-Equal 'CN-0ABCD-72' ([string]$monitorWithSerial[0].serialNumber) `
  'le numero de serie EDID est collecte'

# Un ecran qui ne publie pas son numero de serie -- la majorite -- porte un
# marqueur d'absence, jamais une chaine vide qui se lirait comme une donnee.
$monitorWithoutSerial = @(Get-MonitorInventoryFromSources `
    -MonitorIds @(
      [pscustomobject]@{
        Active = $true
        InstanceName = 'DISPLAY\DEL4098\5&10a58f0e&0&UID4357_0'
        UserFriendlyName = @(68,69,76,76,32,85,50,55,50,48,81,0)
        ManufacturerName = @(68,69,76,0)
      }
    ) `
    -Connections @() `
    -DesktopMonitors @())

Assert-True ($monitorWithoutSerial[0].serialNumber -is [hashtable]) `
  'un ecran sans numero de serie EDID porte un marqueur'

$desktopFallbackDisplays = @(Get-MonitorInventoryFromSources `
    -MonitorIds @() `
    -Connections @() `
    -DesktopMonitors @(
      [pscustomobject]@{
        PNPDeviceID = 'DISPLAY\ACI27F8\4&1A2B3C4D&0&UID256'
        Name = 'ASUS PA278QV'
        ScreenWidth = 2560
        ScreenHeight = 1440
        ScreenRefreshRate = 75
      }
    ))

Assert-Equal 1 $desktopFallbackDisplays.Count 'un ecran desktop reste visible meme sans WmiMonitorID'
Assert-Equal 'ASUS PA278QV' ([string]$desktopFallbackDisplays[0].name) 'le repli Win32_DesktopMonitor garde le nom'
Assert-Equal '2560x1440' ([string]$desktopFallbackDisplays[0].resolution) 'le repli Win32_DesktopMonitor garde la resolution'

# --- Antivirus tiers --------------------------------------------------------

Write-Suite 'Antivirus tiers'

$enabledState = ConvertFrom-AntivirusProductState -Value 266240
Assert-Equal 'True' ([string]$enabledState.enabled) 'un antivirus actif est marque comme actif'
Assert-Equal 'True' ([string]$enabledState.upToDate) 'un antivirus a jour est marque comme a jour'
Assert-Equal 'True' ([string]$enabledState.realtimeProtection) 'la protection temps reel est detectee'

$outdatedState = ConvertFrom-AntivirusProductState -Value 266256
Assert-Equal 'False' ([string]$outdatedState.upToDate) 'une signature obsolete est detectee'

$thirdPartyAntivirus = @(Get-ThirdPartyAntivirusListFromProducts -Products @(
    [pscustomobject]@{
      displayName = 'Avast Free Antivirus'
      productState = 266240
      timestamp = $null
    },
    [pscustomobject]@{
      displayName = 'Microsoft Defender'
      productState = 266240
      timestamp = $null
    }
  ))

Assert-Equal 1 $thirdPartyAntivirus.Count 'Defender n''est pas duplique parmi les antivirus tiers'
Assert-Equal 'Avast Free Antivirus' ([string]$thirdPartyAntivirus[0].name) 'Avast est remonte par SecurityCenter2'
Assert-Equal 'True' ([string]$thirdPartyAntivirus[0].realtimeProtection) 'la protection temps reel Avast est preservee'

# --- Inventaire logiciel ----------------------------------------------------

Write-Suite 'Inventaire logiciel'

Assert-Equal '2024-03-17' (Convert-RegistryInstallDate -Value '20240317') `
  'une date du registre devient une date ISO'
Assert-True ($null -eq (Convert-RegistryInstallDate -Value '')) `
  'une date vide ne produit aucune date'
Assert-True ($null -eq (Convert-RegistryInstallDate -Value '20200000')) `
  'un mois nul ne devient pas le 1er janvier'
Assert-True ($null -eq (Convert-RegistryInstallDate -Value '1710633600')) `
  'un horodatage Unix n''est pas lu comme une date du registre'

# Le tri des entrees de desinstallation : c'est lui qui evite de rapporter six
# cents « paquets » dont la plupart sont des mises a jour du meme logiciel.
Assert-True (Test-UninstallEntryIsPackage -Entry ([pscustomobject]@{ DisplayName = 'Firefox' })) `
  'un logiciel nomme est un paquet'
Assert-True (-not (Test-UninstallEntryIsPackage -Entry ([pscustomobject]@{ DisplayName = '' }))) `
  'une entree sans nom affiche est ecartee'
Assert-True (-not (Test-UninstallEntryIsPackage -Entry ([pscustomobject]@{ DisplayName = 'Pilote'; SystemComponent = 1 }))) `
  'un composant systeme est ecarte'
Assert-True (-not (Test-UninstallEntryIsPackage -Entry ([pscustomobject]@{ DisplayName = 'KB5001234'; ParentKeyName = 'Office' }))) `
  'un correctif rattache a un parent est ecarte'
Assert-True (-not (Test-UninstallEntryIsPackage -Entry ([pscustomobject]@{ DisplayName = 'MaJ'; ReleaseType = 'Security Update' }))) `
  'une mise a jour de securite est ecartee'
Assert-True (-not (Test-UninstallEntryIsPackage -Entry $null)) `
  'une entree nulle est ecartee sans lever'

Assert-Equal 'RUNNING' (Get-ServiceStateName -State 'Running') 'un service demarre est RUNNING'
Assert-Equal 'STOPPED' (Get-ServiceStateName -State 'Stopped') 'un service arrete est STOPPED'
Assert-Equal 'UNKNOWN' (Get-ServiceStateName -State 'Start Pending') `
  'un etat de transition n''est range ni d''un cote ni de l''autre'
Assert-Equal 'ENABLED' (Get-ServiceStartupName -StartMode 'Auto') 'Auto vaut ENABLED'
Assert-Equal 'ENABLED' (Get-ServiceStartupName -StartMode 'Boot') 'un pilote demarre par le noyau est actif'
Assert-Equal 'DISABLED' (Get-ServiceStartupName -StartMode 'Disabled') 'Disabled vaut DISABLED'
Assert-Equal 'MANUAL' (Get-ServiceStartupName -StartMode 'Manual') 'Manual vaut MANUAL'
Assert-Equal 'UNKNOWN' (Get-ServiceStartupName -StartMode '') 'un mode absent reste inconnu'

# `go version` affiche « go version go1.22.5 windows/amd64 » : une expression
# gourmande y trouverait l'architecture ou un fragment du numero.
Assert-Equal '1.22.5' (Get-VersionFromOutput -Output 'go version go1.22.5 windows/amd64') `
  'le premier numero complet est retenu'
Assert-Equal '20.11.0' (Get-VersionFromOutput -Output "`nv20.11.0`n") `
  'une ligne vide en tete n''empeche pas la lecture'
Assert-Equal '' (Get-VersionFromOutput -Output 'commande introuvable') `
  'aucune version n''est inventee quand rien n''est reconnaissable'
Assert-Equal '' (Get-VersionFromOutput -Output '') 'une sortie vide ne produit pas de version'

# --- Virtualisation ---------------------------------------------------------

Write-Suite 'Virtualisation'

Assert-Equal 'vmware' (Get-RunningUnderHypervisor -Model 'VMware Virtual Platform' -Manufacturer 'VMware, Inc.') `
  'VMware est reconnu'
Assert-Equal 'virtualbox' (Get-RunningUnderHypervisor -Model 'VirtualBox' -Manufacturer 'innotek GmbH') `
  'VirtualBox est reconnu'
Assert-Equal 'kvm' (Get-RunningUnderHypervisor -Model 'Standard PC (Q35 + ICH9)' -Manufacturer 'QEMU') `
  'QEMU est reconnu'
Assert-Equal 'hyperv' (Get-RunningUnderHypervisor -Model 'Virtual Machine' -Manufacturer 'Microsoft Corporation') `
  'Hyper-V est reconnu'
# L'ordre des tests compte : « VMware Virtual Platform » contient « Virtual ».
Assert-Equal 'vmware' (Get-RunningUnderHypervisor -Model 'VMware Virtual Platform' -Manufacturer '') `
  'un modele VMware n''est pas pris pour du Hyper-V'
Assert-Equal '' (Get-RunningUnderHypervisor -Model 'OptiPlex 7090' -Manufacturer 'Dell Inc.') `
  'un poste physique ne se voit attribuer aucun hyperviseur'
Assert-Equal '' (Get-RunningUnderHypervisor -Model '' -Manufacturer '') `
  'une signature vide ne conclut a rien'

$port = ConvertFrom-DockerPortLine -Line '80/tcp -> 0.0.0.0:8080'
Assert-Equal '8080' ([string]$port.hostPort) 'le port hote est lu'
Assert-Equal '80' ([string]$port.containerPort) 'le port du conteneur est lu'
Assert-Equal 'tcp' ([string]$port.protocol) 'le protocole est lu'
Assert-Equal '0.0.0.0' ([string]$port.hostAddress) 'l''adresse d''ecoute est lue'

# Une adresse IPv6 contient des deux-points : decouper sur le premier donnerait
# « [ » comme adresse et le reste comme port.
$port6 = ConvertFrom-DockerPortLine -Line '443/tcp -> [::]:8443'
Assert-Equal '8443' ([string]$port6.hostPort) 'un port derriere une adresse IPv6 est lu'
Assert-Equal '[::]' ([string]$port6.hostAddress) 'l''adresse IPv6 reste entiere'

Assert-True ($null -eq (ConvertFrom-DockerPortLine -Line '')) 'une ligne vide ne produit pas de port'
Assert-True ($null -eq (ConvertFrom-DockerPortLine -Line '80/tcp')) 'une ligne sans correspondance est ignoree'
Assert-True ($null -eq (ConvertFrom-DockerPortLine -Line '80/tcp -> 0.0.0.0:99999')) `
  'un port hors bornes est refuse plutot que tronque'

Assert-True (Test-SensitiveMount -Source '/var/run/docker.sock') 'le socket Docker est signale'
Assert-True (Test-SensitiveMount -Source 'C:\Windows') 'le repertoire Windows est signale'
Assert-True (Test-SensitiveMount -Source 'c:\windows') 'la casse n''empeche pas le signalement'
Assert-True (-not (Test-SensitiveMount -Source '/srv/donnees')) 'un montage ordinaire n''est pas signale'
Assert-True (-not (Test-SensitiveMount -Source '')) 'un montage vide n''est pas signale'

Assert-Equal 'running' (Get-HyperVGuestState -State 'Running') 'l''etat Hyper-V est normalise en minuscules'
Assert-Equal '' (Get-HyperVGuestState -State '') 'un etat absent ne devient pas une chaine arbitraire'

# --- Observation dans la duree ----------------------------------------------

Write-Suite 'Observation dans la duree'

Assert-Equal '1024' ([string](Get-MonitoringRate -Before 0 -After 2048 -Seconds 2)) `
  'un taux se calcule entre deux compteurs cumules'
Assert-True ($null -eq (Get-MonitoringRate -Before 5000 -After 100 -Seconds 1)) `
  'un compteur qui recule ne produit pas un taux nul'
Assert-True ($null -eq (Get-MonitoringRate -Before $null -After 2048 -Seconds 1)) `
  'un releve manquant ne produit pas un taux nul'
Assert-True ($null -eq (Get-MonitoringRate -Before 0 -After 2048 -Seconds 0)) `
  'un intervalle nul ne divise pas par zero'

# `PercentIdleTime` de l'instance `_Total` est la somme de tous les coeurs :
# sans division par leur nombre, une machine au repos paraitrait chargee.
Assert-Equal '50' ([string](Get-MonitoringCpuUsage -IdleBefore 0 -IdleAfter 1000 -TimestampBefore 0 -TimestampAfter 2000 -CoreCount 1)) `
  'une inactivite de moitie donne 50 % d''occupation'
Assert-Equal '0' ([string](Get-MonitoringCpuUsage -IdleBefore 0 -IdleAfter 8000 -TimestampBefore 0 -TimestampAfter 2000 -CoreCount 4)) `
  'quatre coeurs inactifs donnent 0 %, pas une valeur negative'
Assert-Equal '100' ([string](Get-MonitoringCpuUsage -IdleBefore 0 -IdleAfter 0 -TimestampBefore 0 -TimestampAfter 2000 -CoreCount 4)) `
  'aucune inactivite donne 100 %'
Assert-True ($null -eq (Get-MonitoringCpuUsage -IdleBefore 0 -IdleAfter 1000 -TimestampBefore 0 -TimestampAfter 0 -CoreCount 1)) `
  'un horodatage immobile ne produit pas d''occupation'
Assert-True ($null -eq (Get-MonitoringCpuUsage -IdleBefore 0 -IdleAfter 1000 -TimestampBefore 0 -TimestampAfter 2000 -CoreCount 0)) `
  'un nombre de coeurs nul ne divise pas par zero'

# Au-dela de 64 processeurs logiques, Windows publie un total par groupe en plus
# du total global : tout nom contenant `_Total` doit etre ecarte du decompte.
$instances = @(
  [pscustomobject]@{ Name = '0' },
  [pscustomobject]@{ Name = '1' },
  [pscustomobject]@{ Name = '0,_Total' },
  [pscustomobject]@{ Name = '_Total' }
)
Assert-Equal '2' ([string](Get-MonitoringCoreCount -Instances $instances)) `
  'les totaux par groupe ne sont pas comptes comme des coeurs'

$sensorGpu = [pscustomobject]@{ SensorType = 'Temperature'; Name = 'GPU Hotspot'; Value = 81.2; Hardware = '/gpu/nvidia'; Identifier = '/gpu/temp/0'; Parent = '' }
$sensorCpu = [pscustomobject]@{ SensorType = 'Temperature'; Name = 'Tctl'; Value = 67.4; Hardware = '/amdcpu/0'; Identifier = '/amdcpu/0/temperature/0'; Parent = '' }
$sensorBoard = [pscustomobject]@{ SensorType = 'Temperature'; Name = 'SYSTIN'; Value = 34.1; Hardware = '/lpc/nct6798d'; Identifier = '/lpc/temp/0'; Parent = '' }
$sensorVoltage = [pscustomobject]@{ SensorType = 'Voltage'; Name = 'CPU VCore'; Value = 1.247; Hardware = '/amdcpu/0'; Identifier = '/amdcpu/0/voltage/0'; Parent = '' }
$sensorPower = [pscustomobject]@{ SensorType = 'Power'; Name = 'CPU Package'; Value = 62.4; Hardware = '/amdcpu/0'; Identifier = '/amdcpu/0/power/0'; Parent = '' }
$sensorGpuTemp = [pscustomobject]@{ SensorType = 'Temperature'; Name = 'GPU Temperature'; Value = 77.1; Hardware = '/gpu/nvidia'; Identifier = '/gpu/temperature/0'; Parent = '' }
$sensorGpuHotspot = [pscustomobject]@{ SensorType = 'Temperature'; Name = 'GPU Hotspot'; Value = 90.4; Hardware = '/gpu/nvidia'; Identifier = '/gpu/temperature/1'; Parent = '' }
$sensorGpuCoreClock = [pscustomobject]@{ SensorType = 'Clock'; Name = 'Graphics Clock'; Value = 1334.6; Hardware = '/gpu/nvidia'; Identifier = '/gpu/clock/0'; Parent = '' }
$sensorGpuMemoryClock = [pscustomobject]@{ SensorType = 'Clock'; Name = 'Memory Clock'; Value = 1750.2; Hardware = '/gpu/nvidia'; Identifier = '/gpu/clock/1'; Parent = '' }
$sensorGpuVoltage = [pscustomobject]@{ SensorType = 'Voltage'; Name = 'GPU Core Voltage'; Value = 1.102; Hardware = '/gpu/nvidia'; Identifier = '/gpu/voltage/0'; Parent = '' }
$sensorGpuPower = [pscustomobject]@{ SensorType = 'Power'; Name = 'Board Power Draw'; Value = 171.3; Hardware = '/gpu/nvidia'; Identifier = '/gpu/power/0'; Parent = '' }

Assert-True ((Get-MonitoringCpuSensorScore -Sensor $sensorCpu) -gt (Get-MonitoringCpuSensorScore -Sensor $sensorGpu)) `
  'un capteur CPU est prioritaire sur un capteur GPU'
Assert-Equal '67.4' ([string](Select-MonitoringCpuTemperatureFromSensors -Sensors @($sensorGpu, $sensorBoard, $sensorCpu))) `
  'la meilleure temperature CPU est choisie parmi les capteurs disponibles'
Assert-Equal '1.247' ([string](Select-MonitoringCpuVoltageFromSensors -Sensors @($sensorBoard, $sensorVoltage))) `
  'la meilleure tension CPU est choisie parmi les capteurs disponibles'
Assert-Equal '62.4' ([string](Select-MonitoringCpuPowerFromSensors -Sensors @($sensorGpu, $sensorPower))) `
  'la meilleure puissance CPU est choisie parmi les capteurs disponibles'
Assert-Equal '77.1' ([string](Select-MonitoringGpuTemperatureFromSensors -Sensors @($sensorCpu, $sensorGpuTemp, $sensorGpuHotspot))) `
  'la temperature GPU retient le capteur de coeur plutot que le hotspot'
Assert-Equal '90.4' ([string](Select-MonitoringGpuHotspotFromSensors -Sensors @($sensorGpuTemp, $sensorGpuHotspot))) `
  'le hotspot GPU est choisi parmi les capteurs disponibles'
Assert-Equal '1335' ([string](Select-MonitoringGpuCoreClockFromSensors -Sensors @($sensorGpuMemoryClock, $sensorGpuCoreClock))) `
  'la frequence coeur GPU est choisie parmi les capteurs disponibles'
Assert-Equal '1750' ([string](Select-MonitoringGpuMemoryClockFromSensors -Sensors @($sensorGpuCoreClock, $sensorGpuMemoryClock))) `
  'la frequence memoire GPU est choisie parmi les capteurs disponibles'
Assert-Equal '1.102' ([string](Select-MonitoringGpuVoltageFromSensors -Sensors @($sensorVoltage, $sensorGpuVoltage))) `
  'la tension GPU est choisie parmi les capteurs disponibles'
Assert-Equal '171.3' ([string](Select-MonitoringGpuPowerFromSensors -Sensors @($sensorPower, $sensorGpuPower))) `
  'la puissance GPU est choisie parmi les capteurs disponibles'

# --- Ventilateurs, charge et memoire graphiques -----------------------------
#
# hwmon comme LibreHardwareMonitor ne normalisent pas les noms de ventilateurs.
# Le point verifie ici est donc moins la lecture que le **refus de deviner** :
# un ventilateur qu'aucun indice ne rattache a un role ne doit pas etre pris
# pour celui du processeur.
$sensorCpuFan = [pscustomobject]@{ SensorType = 'Fan'; Name = 'CPU Fan'; Value = 1240; Hardware = '/lpc/nct6798d'; Identifier = '/lpc/fan/0'; Parent = '' }
$sensorGpuFan = [pscustomobject]@{ SensorType = 'Fan'; Name = 'GPU Fan'; Value = 2380; Hardware = '/gpu/nvidia'; Identifier = '/gpu/fan/0'; Parent = '' }
$sensorChassisFan = [pscustomobject]@{ SensorType = 'Fan'; Name = 'System Fan #2'; Value = 860; Hardware = '/lpc/nct6798d'; Identifier = '/lpc/fan/2'; Parent = '' }
$sensorUnnamedFan = [pscustomobject]@{ SensorType = 'Fan'; Name = 'Fan #5'; Value = 1500; Hardware = '/lpc/nct6798d'; Identifier = '/lpc/fan/5'; Parent = '' }
$sensorStoppedFan = [pscustomobject]@{ SensorType = 'Fan'; Name = 'CPU Fan'; Value = 0; Hardware = '/lpc/nct6798d'; Identifier = '/lpc/fan/0'; Parent = '' }
$sensorGpuLoad = [pscustomobject]@{ SensorType = 'Load'; Name = 'GPU Core'; Value = 87.5; Hardware = '/gpu/nvidia'; Identifier = '/gpu/load/0'; Parent = '' }
$sensorGpuMemoryLoad = [pscustomobject]@{ SensorType = 'Load'; Name = 'GPU Memory'; Value = 41.2; Hardware = '/gpu/nvidia'; Identifier = '/gpu/load/3'; Parent = '' }
$sensorGpuVram = [pscustomobject]@{ SensorType = 'SmallData'; Name = 'GPU Memory Used'; Value = 4096; Hardware = '/gpu/nvidia'; Identifier = '/gpu/smalldata/1'; Parent = '' }

$allFans = @($sensorChassisFan, $sensorGpuFan, $sensorCpuFan, $sensorUnnamedFan)
Assert-Equal '1240' ([string](Select-MonitoringFanFromSensors -Sensors $allFans -Role 'cpu')) `
  'le ventilateur processeur est reconnu par son etiquette'
Assert-Equal '2380' ([string](Select-MonitoringFanFromSensors -Sensors $allFans -Role 'gpu')) `
  'le ventilateur graphique est distingue de celui du processeur'
Assert-Equal '860' ([string](Select-MonitoringFanFromSensors -Sensors $allFans -Role 'chassis')) `
  'le ventilateur de boitier est distingue des deux autres'
Assert-Equal '' ([string](Select-MonitoringFanFromSensors -Sensors @($sensorUnnamedFan) -Role 'cpu')) `
  'un ventilateur sans indice n''est pas attribue au processeur par defaut'
Assert-Equal '0' ([string](Select-MonitoringFanFromSensors -Sensors @($sensorStoppedFan) -Role 'cpu')) `
  'un ventilateur a l''arret rend zero — ce n''est pas une absence de mesure'

Assert-Equal '87.5' ([string](Select-MonitoringGpuUsageFromSensors -Sensors @($sensorGpuMemoryLoad, $sensorGpuLoad))) `
  'la charge GPU retient la puce, pas sa memoire'
Assert-Equal '4294967296' ([string](Select-MonitoringGpuVramFromSensors -Sensors @($sensorGpuVram))) `
  'la memoire graphique est convertie en octets'
Assert-Equal '' ([string](Select-MonitoringGpuUsageFromSensors -Sensors @($sensorCpuFan))) `
  'sans capteur de charge GPU, rien n''est rendu'

# L'echantillon traduit chaque `$null` en marqueur portant sa raison — jamais en
# zero. C'est la regle qui separe « machine au repos » de « compteur non lu ».
$previous = @{ cpuIdle = 0; cpuTimestamp = 0; coreCount = 1; memoryUsed = 100; swapUsed = 0; diskRead = 0; diskWrite = 0; networkRx = 0; networkTx = 0 }
$current = @{ cpuIdle = 1000; cpuTimestamp = 2000; coreCount = 1; memoryUsed = 4096; swapUsed = 512; diskRead = 2048; diskWrite = $null; networkRx = 1024; networkTx = 0 }
$sample = New-MonitoringSample -Previous $previous -Current $current -IntervalSeconds 2 -At '2026-07-31T12:00:00Z'

Assert-Equal '2026-07-31T12:00:00Z' ([string]$sample.at) 'l''horodatage fourni est conserve'
Assert-Equal '50' ([string]$sample.cpuUsagePercent) 'l''occupation processeur est calculee'
Assert-Equal '4096' ([string]$sample.memoryUsedBytes) 'la memoire occupee est instantanee'
Assert-Equal '512' ([string]$sample.swapUsedBytes) 'le fichier d''echange est instantane'
Assert-Equal '1024' ([string]$sample.diskReadBytesPerSecond) 'le debit de lecture est un taux'
Assert-True ($sample.diskWriteBytesPerSecond.unknown -eq $true) `
  'un compteur d''ecriture non lu devient un marqueur, pas un zero'
Assert-Equal 'NOT_AVAILABLE' ([string]$sample.diskWriteBytesPerSecond.reason) `
  'le marqueur porte sa raison'
Assert-True ($sample.cpuTemperatureCelsius.unknown -eq $true) `
  'une temperature non relevee reste un marqueur'
Assert-True ($sample.cpuCoreVoltageVolts.unknown -eq $true) `
  'une tension CPU non relevee reste un marqueur'
Assert-True ($sample.cpuPackagePowerWatts.unknown -eq $true) `
  'une puissance CPU non relevee reste un marqueur'
Assert-True ($sample.gpuTemperatureCelsius.unknown -eq $true) `
  'une temperature GPU non relevee reste un marqueur'
Assert-True ($sample.gpuHotspotCelsius.unknown -eq $true) `
  'un hotspot GPU non releve reste un marqueur'
Assert-True ($sample.gpuBoardPowerWatts.unknown -eq $true) `
  'une puissance GPU non relevee reste un marqueur'
Assert-True ($sample.cpuFanRpm.unknown -eq $true) `
  'un ventilateur processeur non releve reste un marqueur, jamais un zero'
Assert-True ($sample.gpuFanRpm.unknown -eq $true) `
  'un ventilateur graphique non releve reste un marqueur'
Assert-True ($sample.chassisFanRpm.unknown -eq $true) `
  'un ventilateur de boitier non releve reste un marqueur'
Assert-True ($sample.gpuUsagePercent.unknown -eq $true) `
  'une charge GPU non relevee reste un marqueur'
Assert-True ($sample.gpuVramUsedBytes.unknown -eq $true) `
  'une memoire graphique non relevee reste un marqueur'

# La frequence est **instantanee** : elle vient du releve courant, pas d'une
# difference. Le bridage, lui, reste inconnu — Windows ne publie aucun compteur
# comparable a `thermal_throttle`, et le deduire d'une frequence basse
# inventerait une panne : un processeur au repos tourne bas sans etre bride.
$previousFreq = @{ cpuIdle = 0; cpuTimestamp = 0; coreCount = 1; memoryUsed = 100; swapUsed = 0; diskRead = 0; diskWrite = 0; networkRx = 0; networkTx = 0; cpuFrequency = 3800 }
$currentFreq = @{ cpuIdle = 1000; cpuTimestamp = 2000; coreCount = 1; memoryUsed = 4096; swapUsed = 512; diskRead = 2048; diskWrite = 4096; networkRx = 1024; networkTx = 0; cpuFrequency = 1200 }
$freqSample = New-MonitoringSample -Previous $previousFreq -Current $currentFreq -IntervalSeconds 2

Assert-Equal '1200' ([string]$freqSample.cpuFrequencyMhz) `
  'la frequence est celle du releve courant, pas une difference'
Assert-True ($freqSample.cpuThrottled.unknown -eq $true) `
  'le bridage reste inconnu, jamais deduit d''une frequence basse'
Assert-True ([string]$freqSample.cpuThrottled.detail -like '*inventerait une panne*') `
  'le motif du bridage inconnu est ecrit'

$noFreq = @{ cpuIdle = 1000; cpuTimestamp = 2000; coreCount = 1; memoryUsed = 4096; swapUsed = 512; diskRead = 2048; diskWrite = 4096; networkRx = 1024; networkTx = 0; cpuFrequency = $null }
$noFreqSample = New-MonitoringSample -Previous $previousFreq -Current $noFreq -IntervalSeconds 2
Assert-True ($noFreqSample.cpuFrequencyMhz.unknown -eq $true) `
  'une frequence non lue devient un marqueur, pas un zero'

# --- Statistiques d'observation ---------------------------------------------

Write-Suite 'Statistiques d''observation'

# Une observation d'une heure au pas de la seconde depasse la borne du tableau
# d'echantillons. Ces statistiques sont alors la seule trace du pic : elles sont
# redondantes avec les echantillons, et c'est exactement leur raison d'etre.
$aggregate = New-MonitoringAggregate -Values @(78, 81, 83) -Unit 'degC' -IntervalMs 1000 -Source '/thermal'

Assert-Equal '78' ([string]$aggregate.minimum) 'le minimum observe est retenu'
Assert-Equal '83' ([string]$aggregate.maximum) 'le maximum observe est retenu'
Assert-Equal '80.67' ([string]$aggregate.average) 'la moyenne est calculee sur les echantillons'
# `current` reste distinct de `maximum` : sur un instantane pris en fin de
# fenetre, les confondre ferait passer un pic transitoire pour l'etat courant.
Assert-Equal '83' ([string]$aggregate.current) 'la valeur courante est la derniere, pas le maximum'
Assert-Equal '3' ([string]$aggregate.sampleCount) 'le nombre d''echantillons est publie'
Assert-Equal 'degC' ([string]$aggregate.unit) 'l''unite est litterale, jamais devinee du nom du champ'
Assert-Equal '3000' ([string]$aggregate.sampleDurationMs) 'la duree couverte se deduit du pas et du compte'

# Le cas qui compte : aucun echantillon. `sampleCount` vaut alors zero — un
# denombrement, donc un fait — tandis que les statistiques restent inconnues.
# Une moyenne a zero ferait passer une machine sans capteur pour une machine a
# zero degre.
$empty = New-MonitoringAggregate -Values @() -Unit 'degC' -IntervalMs 1000 -Source '/thermal'
Assert-Equal '0' ([string]$empty.sampleCount) 'zero echantillon est un fait, pas une absence'
Assert-True ($empty.average.unknown -eq $true) 'la moyenne absente porte son marqueur'
Assert-True ($empty.minimum.unknown -eq $true) 'le minimum absent porte son marqueur'

# Les marqueurs sont ecartes avant le calcul. Les moyenner reviendrait a compter
# « je n'ai pas pu lire » comme un zero — la faute que ce produit interdit.
$mixed = @(
  @{ cpuUsagePercent = 10 },
  @{ cpuUsagePercent = (New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'compteur illisible') },
  @{ cpuUsagePercent = 30 }
)
$values = Select-MonitoringValue -Samples $mixed -Field 'cpuUsagePercent'
Assert-Equal '2' ([string]$values.Count) 'un marqueur n''entre pas dans les statistiques'
Assert-Equal '20' ([string](New-MonitoringAggregate -Values $values -Unit '%' -IntervalMs 1000).average) `
  'la moyenne porte sur les seules valeurs mesurees'
Assert-Equal '512' ([string]$sample.networkRxBytesPerSecond) 'le debit reseau entrant est un taux'
Assert-Equal '0' ([string]$sample.networkTxBytesPerSecond) `
  'un compteur reellement immobile vaut zero, et non un marqueur'

# Une duree nulle ne produit aucune section : l'observation se demande.
Assert-True ($null -eq (Get-MonitoringSection -DurationSeconds 0)) `
  'sans duree demandee, aucune serie temporelle n''est produite'

# --- Resume Markdown --------------------------------------------------------

Write-Suite 'Resume Markdown'

$sample = @{
  schemaVersion = '1.8.0'
  scannerVersion = '0.4.0'
  report = @{ generatedAt = '2026-07-28T12:00:00Z'; profile = 'quick' }
  capabilities = @{ privileged = $false }
  system = @{
    hostname = 'poste-01'
    manufacturer = New-Unknown -Reason 'PERMISSION_DENIED'
    model = 'OptiPlex'
    architecture = '64-bit'
  }
  os = @{ name = 'Windows 11'; version = '10.0.22631'; kernel = '10.0.22631' }
  collection = @{ issues = @(); skippedSections = @('software') }
}

$markdown = Get-ReportMarkdown -Report $sample
Assert-True ($markdown -like '*poste-01*') 'le nom de machine figure dans le resume'
# Une donnee non lue affiche sa raison : un tiret laisserait croire a une absence
# de composant plutot qu'a une absence de mesure.
Assert-True ($markdown -like '*acces refuse*') 'un marqueur affiche la raison de l''absence'
Assert-True ($markdown -like '*Sections non collectees*') 'les sections ignorees sont annoncees'
Assert-True ($markdown -like '*Aucun probleme rencontre*') 'l''absence de probleme est dite'

# --- Destination du rapport -------------------------------------------------

Write-Suite 'Destination du rapport'

# Le defaut que ces tests gardent ferme s'ecrivait
# `C:\WINDOWS\system32\sysaudit-LAPTOP-WNX.json` : la destination suivait le
# repertoire courant, et une console ouverte depuis le menu Demarrer a
# `System32` pour repertoire courant.

Assert-Equal 'sysaudit-LAPTOP-WNX.json' (Get-SysAuditReportFileName -MachineName 'LAPTOP-WNX') `
  'le nom de rapport reprend le nom de machine'
Assert-Equal 'sysaudit-POSTE-01-bureau.json' (Get-SysAuditReportFileName -MachineName 'POSTE:01\bureau') `
  'les caracteres interdits dans un nom de fichier Windows sont remplaces'
Assert-Equal 'sysaudit-POSTE-01.json' (Get-SysAuditReportFileName -MachineName 'POSTE<<>>01') `
  'une suite de caracteres remplaces ne laisse qu''un tiret'
Assert-Equal 'sysaudit-machine.json' (Get-SysAuditReportFileName -MachineName '') `
  'un nom de machine absent ne produit pas un fichier sans nom'
Assert-Equal 'sysaudit-machine.json' (Get-SysAuditReportFileName -MachineName '***') `
  'un nom de machine entierement invalide retombe sur un nom neutre'

# Repertoires systeme. Ce sont eux qu'aucun repli n'a le droit de retenir.
$systemRoots = @('C:\Windows', 'C:\Program Files', 'C:\Program Files (x86)')

Assert-True (Test-SysAuditSystemDirectory -Path 'C:\WINDOWS\system32' -Roots $systemRoots) `
  'System32 est reconnu comme repertoire systeme, quelle que soit la casse'
Assert-True (Test-SysAuditSystemDirectory -Path 'C:\Windows' -Roots $systemRoots) `
  'le repertoire Windows lui-meme est ecarte'
Assert-True (Test-SysAuditSystemDirectory `
    -Path 'C:\Windows\System32\config\systemprofile\AppData\Local\SysAudit\Reports' -Roots $systemRoots) `
  'le profil du compte SYSTEME est ecarte : il vit sous System32'
Assert-True (Test-SysAuditSystemDirectory -Path 'c:/windows/temp' -Roots $systemRoots) `
  'un chemin ecrit avec des barres obliques est reconnu'
Assert-True (Test-SysAuditSystemDirectory -Path 'C:\Program Files\SysAudit' -Roots $systemRoots) `
  'Program Files est ecarte'
Assert-True (Test-SysAuditSystemDirectory -Path 'D:\' -Roots $systemRoots) `
  'la racine d''un volume n''est pas une destination'
Assert-True (-not (Test-SysAuditSystemDirectory -Path 'C:\Users\Christophe\Downloads' -Roots $systemRoots)) `
  'le dossier Telechargements d''un utilisateur n''est pas un repertoire systeme'
Assert-True (-not (Test-SysAuditSystemDirectory -Path 'C:\Windows Company\Rapports' -Roots $systemRoots)) `
  'un repertoire dont le nom commence comme Windows n''est pas confondu avec lui'
Assert-True (-not (Test-SysAuditSystemDirectory -Path '\\serveur\profils\wnx\Downloads' -Roots $systemRoots)) `
  'un dossier Telechargements sur un partage reste acceptable'

# Developpement des variables : la valeur du registre est `%USERPROFILE%\...`,
# et c'est le profil VISE qu'il faut y mettre — pas le notre.
Assert-Equal 'C:\Users\Christophe\Downloads' `
  (Expand-SysAuditUserPath -Value '%USERPROFILE%\Downloads' -UserProfile 'C:\Users\Christophe') `
  'le profil vise remplace %USERPROFILE%, pas celui du processus'
Assert-Equal 'C:\Users\Christophe\Downloads' `
  (Expand-SysAuditUserPath -Value '%userprofile%\Downloads' -UserProfile 'C:\Users\Christophe\') `
  'la casse de la variable et une barre finale ne changent rien'
Assert-Equal '' (Expand-SysAuditUserPath -Value '%VARIABLE_INEXISTANTE%\Downloads' -UserProfile 'C:\Users\x') `
  'une variable non developpee ne devient pas un nom de repertoire'
Assert-Equal 'D:\Downloads' (Expand-SysAuditUserPath -Value 'D:\Downloads' -UserProfile 'C:\Users\x') `
  'un chemin sans variable traverse inchange'

Assert-True (Test-SysAuditServiceSid -Sid 'S-1-5-18') 'le compte SYSTEME est reconnu'
Assert-True (Test-SysAuditServiceSid -Sid 's-1-5-19') 'LOCAL SERVICE est reconnu, casse comprise'
Assert-True (-not (Test-SysAuditServiceSid -Sid 'S-1-5-21-1-2-3-1001')) `
  'un utilisateur ordinaire n''est pas un compte de service'

# Ordre des candidats. Il est verifie ici parce que c'est lui, et rien d'autre,
# qui decide ou atterrit un rapport.
$candidates = Get-SysAuditReportDirectoryCandidates `
  -Downloads 'D:\Downloads' `
  -UserProfile 'C:\Users\Christophe' `
  -LocalAppData 'C:\Users\Christophe\AppData\Local' `
  -TempPath 'C:\Users\Christophe\AppData\Local\Temp' `
  -ProgramData 'C:\ProgramData'

Assert-Equal 5 (@($candidates).Count) 'cinq destinations sont envisagees'
Assert-Equal 'd:\downloads' (Get-SysAuditComparablePath -Path $candidates[0].Path) `
  'le dossier Telechargements declare par Windows passe en premier'
Assert-Equal 'c:\users\christophe\downloads' (Get-SysAuditComparablePath -Path $candidates[1].Path) `
  '%USERPROFILE%\Downloads n''est qu''un repli'
Assert-Equal 'c:\users\christophe\appdata\local\sysaudit\reports' `
  (Get-SysAuditComparablePath -Path $candidates[2].Path) 'puis les donnees locales de l''application'
Assert-Equal 'c:\users\christophe\appdata\local\temp\sysaudit' `
  (Get-SysAuditComparablePath -Path $candidates[3].Path) 'puis le repertoire temporaire'
Assert-Equal 'c:\programdata\sysaudit\reports' (Get-SysAuditComparablePath -Path $candidates[4].Path) `
  'les donnees communes ne servent qu''en dernier recours'

# Un dossier Telechargements absent ne se cree pas : sa redirection pointe
# ailleurs, et le recreer y planterait un dossier vide.
Assert-True (-not $candidates[0].Create) 'le dossier Telechargements n''est jamais cree'
Assert-True (-not $candidates[1].Create) 'le Telechargements du profil n''est jamais cree non plus'
Assert-True ($candidates[2].Create) 'un repertoire de secours, lui, est cree'

$sansTelechargements = Get-SysAuditReportDirectoryCandidates `
  -Downloads '' -UserProfile 'C:\Users\Christophe' -LocalAppData 'C:\Users\Christophe\AppData\Local' `
  -TempPath 'C:\Temp' -ProgramData 'C:\ProgramData'
Assert-Equal 4 (@($sansTelechargements).Count) `
  'un dossier Telechargements introuvable retire un candidat, il n''en ajoute pas un vide'

# --- Chaine de replis, cas par cas ------------------------------------------
#
# La sonde est injectee : la chaine se verifie sans disque, donc partout, et
# les cas rares — Telechargements redirige, compte SYSTEME — se rejouent sans
# avoir a les fabriquer sur une vraie machine.

function New-DirectoryProbe {
  param([string[]]$Writable)

  $allowed = @($Writable | ForEach-Object { Get-SysAuditComparablePath -Path $_ })
  return {
    param($Path, $Create)
    # La sonde declare ce qui est utilisable, sans distinguer ce qui existait
    # deja de ce qu'il aurait fallu creer : `$Create` appartient au contrat,
    # cette implantation-la n'en a pas besoin.
    $null = $Create
    return ($allowed -contains (Get-SysAuditComparablePath -Path $Path))
  }.GetNewClosure()
}

$foyer = @{
  Downloads = 'C:\Users\Christophe\Downloads'
  UserProfile = 'C:\Users\Christophe'
  LocalAppData = 'C:\Users\Christophe\AppData\Local'
  TempPath = 'C:\Users\Christophe\AppData\Local\Temp'
  ProgramData = 'C:\ProgramData'
}

# Cas 1 et 2 : peu importe d'ou la commande a ete tapee — `C:\WINDOWS\system32`
# ou le Bureau —, la destination est la meme. Le repertoire courant n'est pas
# une entree de cette fonction : il ne peut donc pas la changer.
$normal = Select-SysAuditReportDirectory `
  -Candidates (Get-SysAuditReportDirectoryCandidates @foyer) `
  -SystemRoots $systemRoots `
  -Probe (New-DirectoryProbe -Writable @('C:\Users\Christophe\Downloads'))

Assert-Equal 'c:\users\christophe\downloads' (Get-SysAuditComparablePath -Path $normal.Path) `
  'le rapport va dans le dossier Telechargements de l''utilisateur'
Assert-Equal 0 (@($normal.Rejections).Count) 'aucun repli n''a ete necessaire'
Assert-True ((Get-SysAuditComparablePath -Path $normal.Path) -notlike '*system32*') `
  'la destination ne passe jamais par System32'

# Cas 4 : Telechargements redirige vers un autre volume. C'est la valeur du
# dossier connu qui l'emporte, pas `%USERPROFILE%\Downloads`.
$redirige = Select-SysAuditReportDirectory `
  -Candidates (Get-SysAuditReportDirectoryCandidates `
    -Downloads 'D:\Downloads' -UserProfile 'C:\Users\Christophe' `
    -LocalAppData 'C:\Users\Christophe\AppData\Local' -TempPath 'C:\Temp' -ProgramData 'C:\ProgramData') `
  -SystemRoots $systemRoots `
  -Probe (New-DirectoryProbe -Writable @('D:\Downloads', 'C:\Users\Christophe\Downloads'))

Assert-Equal 'd:\downloads' (Get-SysAuditComparablePath -Path $redirige.Path) `
  'un dossier Telechargements redirige est suivi jusqu''a son volume'

# Cas 5 : Telechargements indisponible — dossier sur un disque amovible absent,
# ou redirige vers un partage hors ligne. Le repli est annonce, pas subi.
$repli = Select-SysAuditReportDirectory `
  -Candidates (Get-SysAuditReportDirectoryCandidates @foyer) `
  -SystemRoots $systemRoots `
  -Probe (New-DirectoryProbe -Writable @('C:\Users\Christophe\AppData\Local\SysAudit\Reports'))

Assert-Equal 'c:\users\christophe\appdata\local\sysaudit\reports' `
  (Get-SysAuditComparablePath -Path $repli.Path) `
  'sans dossier Telechargements, le rapport va dans les donnees locales'
Assert-Equal 2 (@($repli.Rejections).Count) 'les deux candidats ecartes sont journalises'
Assert-True (@($repli.Rejections)[0].Label -like '*Telechargements*') `
  'le journal nomme le dossier Telechargements ecarte'
Assert-True (-not [string]::IsNullOrWhiteSpace(@($repli.Rejections)[0].Reason)) `
  'chaque rejet porte sa raison'

# Cas 3 : elevation. Une elevation UAC ordinaire garde le compte de
# l'utilisateur — c'est le cas ci-dessus. Le cas dur est celui ou le compte
# change : `runas`, service, tache planifiee sous LE SYSTEME. Tout ce que le
# processus connait pointe alors sous System32.
$systeme = Select-SysAuditReportDirectory `
  -Candidates (Get-SysAuditReportDirectoryCandidates `
    -Downloads '' `
    -UserProfile 'C:\Windows\System32\config\systemprofile' `
    -LocalAppData 'C:\Windows\System32\config\systemprofile\AppData\Local' `
    -TempPath 'C:\Windows\Temp' `
    -ProgramData 'C:\ProgramData') `
  -SystemRoots $systemRoots `
  -Probe (New-DirectoryProbe -Writable @(
      'C:\Windows\System32\config\systemprofile\AppData\Local\SysAudit\Reports',
      'C:\Windows\Temp\SysAudit',
      'C:\ProgramData\SysAudit\Reports'))

Assert-Equal 'c:\programdata\sysaudit\reports' (Get-SysAuditComparablePath -Path $systeme.Path) `
  'un audit sans utilisateur ecrit dans les donnees communes'
Assert-True ((Get-SysAuditComparablePath -Path $systeme.Path) -notlike '*system32*') `
  'meme inscriptible, un repertoire systeme n''est jamais retenu'
Assert-True ((@($systeme.Rejections) | Where-Object { $_.Reason -eq 'repertoire systeme' }).Count -ge 2) `
  'les repertoires systeme ecartes sont dits comme tels'

# Rien ne tient : la fonction rend une destination vide plutot que d'en
# inventer une. C'est l'appelant qui le dira, et il s'arretera.
$aucune = Select-SysAuditReportDirectory `
  -Candidates (Get-SysAuditReportDirectoryCandidates @foyer) `
  -SystemRoots $systemRoots `
  -Probe (New-DirectoryProbe -Writable @())

Assert-Equal '' ([string]$aucune.Path) 'aucune destination inscriptible ne rend aucune destination'
Assert-Equal 5 (@($aucune.Rejections).Count) 'les cinq tentatives sont journalisees'

# --- Cas 6 : un chemin explicite passe devant tout --------------------------

$explicite = Resolve-SysAuditReportPath -Requested 'D:\Audits\rapport.json' -FileName 'sysaudit-poste.json'
Assert-Equal 'D:\Audits\rapport.json' ([string]$explicite.Path) `
  'un -OutputPath absolu est repris tel quel'
Assert-True ($explicite.Explicit) 'le chemin demande est marque comme explicite'

$relatif = Resolve-SysAuditReportPath -Requested 'audit.json' -FileName 'sysaudit-poste.json' `
  -WorkingDirectory 'C:\Users\Christophe\Bureau'
Assert-Equal 'c:\users\christophe\bureau\audit.json' (Get-SysAuditComparablePath -Path $relatif.Path) `
  'un -OutputPath relatif est resolu depuis le repertoire courant, comme demande'

$defaut = Resolve-SysAuditReportPath -FileName 'sysaudit-poste.json' -Directory 'C:\Users\Christophe\Downloads'
Assert-Equal 'c:\users\christophe\downloads\sysaudit-poste.json' (Get-SysAuditComparablePath -Path $defaut.Path) `
  'sans demande, le fichier prend son nom dans le repertoire retenu'
Assert-True (-not $defaut.Explicit) 'la destination par defaut n''est pas un chemin demande'

Assert-True (Test-SysAuditRootedPath -Path 'D:\Audits') 'un chemin de volume est absolu'
Assert-True (Test-SysAuditRootedPath -Path '\\serveur\partage') 'un chemin UNC est absolu'
Assert-True (-not (Test-SysAuditRootedPath -Path 'audit.json')) 'un nom de fichier seul est relatif'
Assert-True (-not (Test-SysAuditRootedPath -Path '.\audit.json')) 'un chemin en .\ est relatif'

# --- Ce que le scanner ne fait plus -----------------------------------------
#
# Ces controles portent sur la source : ils gardent fermee la porte par
# laquelle le defaut est entre, et qu'aucun test de fonction ne surveille.

$windowsScannerSource = Get-Content (Join-Path $scannerRoot 'sysaudit.ps1') -Raw
$outputSection = $windowsScannerSource.Substring($windowsScannerSource.IndexOf('# --- Sorties'))

Assert-True ($outputSection -notmatch '\$PWD') `
  'la section des sorties n''interroge pas $PWD'
Assert-Equal 1 ([regex]::Matches($outputSection, 'Get-Location')).Count `
  'le repertoire courant n''est lu qu''une fois'
Assert-True ($outputSection -match '(?s)OutputPath.*?Get-Location') `
  'et cette seule lecture sert a resoudre un -OutputPath relatif'
# `System32` n'apparait plus que dans les commentaires, pour raconter le defaut
# corrige. Une seule ligne de code qui le nommerait ferait echouer ce test.
$system32InCode = @($outputSection -split "`n" |
    Where-Object { $_ -match '(?i)system32' -and $_.TrimStart() -notmatch '^#' })
Assert-Equal 0 (@($system32InCode).Count) `
  'aucun repertoire systeme n''est ecrit en dur comme destination'
Assert-True ($outputSection -match 'Resolve-SysAuditReportDirectory') `
  'la destination par defaut vient de la resolution des dossiers connus'

# --- Bout en bout -----------------------------------------------------------

Write-Suite 'Execution complete'

$onWindows = $env:OS -eq 'Windows_NT'
if (-not $onWindows) {
  Write-Host '  IGNORE  execution complete (collecteurs CIM : Windows requis)' -ForegroundColor Yellow
} else {
  $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('sysaudit-tests-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

  try {
    $reportPath = Join-Path $tempDir 'report.json'
    & (Join-Path $scannerRoot 'sysaudit.ps1') -Profile quick -OutputPath $reportPath -NoMarkdown | Out-Null

    Assert-True (Test-Path $reportPath) 'un rapport est produit'

    $raw = Get-Content $reportPath -Raw
    $report = $raw | ConvertFrom-Json
    Assert-Equal 'windows' $report.report.scannerKind 'le rapport se declare Windows'
    Assert-Equal 'quick' $report.report.profile 'le profil demande est rapporte'
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$report.schemaVersion)) 'la version de schema est annoncee'

    # Le contrat entre scanner et plateforme : la sortie doit passer le schema.
    $schemaModule = Join-Path $scannerRoot '../../packages/report-schema/dist/index.js'
    if (Test-Path $schemaModule) {
      # Une base `file:///` explicite : un chemin Unix n'est pas une URI absolue
      # pour .NET, `.AbsoluteUri` ne rend alors rien, et PowerShell avale
      # l'erreur. Le defaut ne se voit pas ici — ce plan ne tourne que sur
      # Windows — mais un import vide se lirait comme un rapport non conforme.
      $moduleUrl = [System.Uri]::new([System.Uri]::new('file:///'), (Resolve-Path $schemaModule).Path).AbsoluteUri
      $validationScript = @"
import { readFileSync } from 'node:fs';
import { validateReport } from '$moduleUrl';
const result = validateReport(JSON.parse(readFileSync(process.argv[1], 'utf8')));
if (result.ok) { console.log('OK'); }
else { console.log('ERREUR ' + result.code); console.log(JSON.stringify(result.issues.slice(0, 10))); }
"@
      $validation = (node --input-type=module -e $validationScript $reportPath) -join "`n"
      Assert-True ($validation -like '*OK*') "la sortie du scanner respecte le schema SysAudit ($validation)"
    } else {
      Write-Host '  IGNORE  validation de schema (packages/report-schema non compile)' -ForegroundColor Yellow
    }

    # Cas 1 et 2 du defaut corrige, joues pour de vrai : le scanner est lance
    # SANS -OutputPath, depuis un repertoire de travail quelconque. Le rapport
    # ne doit pas y apparaitre — c'est cette dependance au repertoire courant
    # qui produisait `C:\WINDOWS\system32\sysaudit-LAPTOP-WNX.json`.
    $workDir = Join-Path $tempDir 'depuis-ailleurs'
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null

    $expectedDirectory = [string](Resolve-SysAuditReportDirectory).Path
    $expectedReport = Join-Path $expectedDirectory (Get-SysAuditReportFileName -MachineName $env:COMPUTERNAME)

    Push-Location $workDir
    try {
      & (Join-Path $scannerRoot 'sysaudit.ps1') -Profile quick -NoMarkdown | Out-Null
    } finally {
      Pop-Location
    }

    try {
      Assert-Equal 0 (@(Get-ChildItem -Path $workDir -Filter 'sysaudit-*' -ErrorAction SilentlyContinue).Count) `
        'aucun rapport n''est ecrit dans le repertoire d''ou la commande est lancee'
      Assert-True (Test-Path -LiteralPath $expectedReport) `
        ('le rapport est ecrit dans le repertoire resolu (' + $expectedReport + ')')
      Assert-True ((Get-SysAuditComparablePath -Path $expectedDirectory) -notlike '*windows\system32*') `
        'le repertoire resolu n''est pas un repertoire systeme'
    } finally {
      Remove-Item -LiteralPath $expectedReport -Force -ErrorAction SilentlyContinue
    }
  } finally {
    Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
  }
}

# --- Temperatures materielles -----------------------------------------------

Write-Suite 'Temperatures materielles'

# Les providers materiels ne repondent pas sur une machine de test : ce qui est
# verifie ici est la seule partie qui decide de ce que le rapport affichera —
# la famille de composant attribuee a chaque sonde, dont depend le seuil.

Assert-Equal 'CPU' (Get-ThermalCategory -HardwareType 'Cpu' -SensorName 'CPU Package') `
  'le paquet processeur est classe CPU'
Assert-Equal 'CPU' (Get-ThermalCategory -HardwareType 'Cpu' -SensorName 'Core #0') `
  'un coeur reste une sonde de processeur'
Assert-Equal 'CPU' (Get-ThermalCategory -HardwareType 'Cpu' -SensorName 'CCD1 (Tdie)') `
  'un CCD Ryzen reste une sonde de processeur'
Assert-Equal 'GPU' (Get-ThermalCategory -HardwareType 'GpuNvidia' -SensorName 'GPU Core') `
  'une sonde NVIDIA est classee GPU'
Assert-Equal 'GPU' (Get-ThermalCategory -HardwareType 'GpuAmd' -SensorName 'GPU Hot Spot') `
  'le point chaud est classe GPU'
Assert-Equal 'DRIVE_SSD' (Get-ThermalCategory -HardwareType 'Storage' -SensorName 'Temperature') `
  'une sonde de disque est rattachee au stockage'
Assert-Equal 'NETWORK' (Get-ThermalCategory -HardwareType 'Network' -SensorName 'Temperature') `
  'une sonde de carte reseau est classee reseau'

# Le cas qui justifie que le nom prime sur le materiel : un seul Super-I/O porte
# trois sondes dont les seuils vont du simple au double.
Assert-Equal 'VRM' (Get-ThermalCategory -HardwareType 'SuperIO' -SensorName 'VRM MOS') `
  'l''etage d''alimentation n''est pas classe carte mere'
Assert-Equal 'CHIPSET' (Get-ThermalCategory -HardwareType 'SuperIO' -SensorName 'PCH') `
  'le PCH est classe chipset'
Assert-Equal 'MOTHERBOARD' (Get-ThermalCategory -HardwareType 'Motherboard' -SensorName 'System') `
  'la sonde de chassis est classee carte mere'

# Une sonde de carte mere dont on ignore ce qu'elle mesure n'est pas rangee au
# juger : elle sera affichee sans verdict thermique.
Assert-Equal 'OTHER' (Get-ThermalCategory -HardwareType 'SuperIO' -SensorName 'Temperature #3') `
  'une sonde non identifiee reste non identifiee'
Assert-Equal 'OTHER' (Get-ThermalCategory -HardwareType '' -SensorName '') `
  'sans materiel ni nom, aucune famille n''est supposee'

# Le nombre de releves suit le niveau : les deux secondes qu'ils coutent n'ont
# rien a faire dans un audit Normale.
$script:ScanProfile = 'standard'
Assert-Equal 1 (Get-ThermalSampleCount) 'l''audit normal se contente d''un releve'
$script:ScanProfile = 'full'
Assert-Equal 3 (Get-ThermalSampleCount) 'la collecte approfondie prend trois releves'
$script:ScanProfile = 'stress'

Write-Suite 'Temperature du processeur'

# `Win32_Processor` ne porte aucune temperature : le champ rendait donc
# `NOT_AVAILABLE` en dur sur toutes les machines Windows. Ce qui est verifie ici
# est la selection du capteur, c'est-a-dire la seule partie qui decide de ce que
# le rapport affichera.

function New-TestSensor {
  param([string]$Type = 'Temperature', [string]$Name = '', [string]$Hardware = '', [double]$Value = 50)
  return [pscustomobject]@{
    SensorType = $Type
    Name = $Name
    Hardware = $Hardware
    Identifier = ''
    Parent = ''
    Value = $Value
  }
}

# « CPU Package » l'emporte sur un coeur : c'est la temperature du boitier
# entier, celle qu'un constructeur publie et celle qu'un seuil vise.
Assert-True (
  (Get-CpuTemperatureSensorScore -Sensor (New-TestSensor -Name 'CPU Package')) -gt
  (Get-CpuTemperatureSensorScore -Sensor (New-TestSensor -Name 'CPU Core #3'))
) 'le paquet processeur passe avant un coeur'

Assert-True ((Get-CpuTemperatureSensorScore -Sensor (New-TestSensor -Name 'Core (Tctl/Tdie)')) -gt 0) `
  'la sonde Tctl d''un Ryzen est reconnue'

# Une frequence nommee « CPU Core » entrerait comme un degre si le type n'etait
# pas verifie d'abord.
Assert-Equal -1 (Get-CpuTemperatureSensorScore -Sensor (New-TestSensor -Type 'Clock' -Name 'CPU Core')) `
  'une frequence n''est pas une temperature'

# Tout ce qui designe un autre composant disqualifie avant meme de compter.
Assert-Equal -1 (Get-CpuTemperatureSensorScore -Sensor (New-TestSensor -Name 'GPU Core')) `
  'une sonde graphique ne devient pas une temperature de processeur'
Assert-Equal -1 (Get-CpuTemperatureSensorScore -Sensor (New-TestSensor -Name 'Composite' -Hardware 'NVMe')) `
  'une sonde de disque ne devient pas une temperature de processeur'

<#
  Le refus qui justifie toute cette selection.

  Une sonde nommee `Temperature` a 51 degres ne designe aucun materiel en
  particulier. L'attribuer au processeur produirait un constat de surchauffe sur
  une machine froide, ou l'inverse. C'est exactement ce que le collecteur Linux
  refuse deja, en toutes lettres.
#>
Assert-Equal -1 (Get-CpuTemperatureSensorScore -Sensor (New-TestSensor -Name 'Temperature')) `
  'une zone thermique generique ne devient jamais une temperature de processeur'

Assert-Equal 62.5 (Get-CpuTemperatureFromSensors -Sensors @(
    (New-TestSensor -Name 'Temperature' -Value 51),
    (New-TestSensor -Name 'CPU Package' -Value 62.5)
  )) 'la sonde processeur est preferee a la zone generique'

Assert-True ($null -eq (Get-CpuTemperatureFromSensors -Sensors @((New-TestSensor -Name 'Temperature' -Value 51)))) `
  'sans capteur rattache au processeur, aucune valeur n''est rendue'

Assert-True ($null -eq (Get-CpuTemperatureFromSensors -Sensors @())) `
  'sans provider materiel, aucune valeur n''est rendue'

# Hors du domaine physique, ce n'est pas une temperature : c'est la reponse
# d'une sonde absente ou d'un registre non initialise.
Assert-True ($null -eq (Get-CpuTemperatureFromSensors -Sensors @((New-TestSensor -Name 'CPU Package' -Value 999)))) `
  'une valeur hors domaine physique est ecartee, pas publiee'

# --- Inventaire des dependances ---------------------------------------------
#
# Sous Windows, ce module ne peut rien installer : aucun collecteur ne depend
# d'un outil tiers. Les tests portent donc sur ce qu'il dit du rapport, et sur
# ce qu'il se garde de dire.

Write-Suite 'Inventaire des dependances'

$inventaire = Get-DependencyInventory -Tools @{
  powershell = $true
  winget     = $false
  defender   = $true
}

Assert-Equal 3 $inventaire.Count 'une entree par outil de la table de capacites'

$parOutil = @{}
foreach ($entree in $inventaire) { $parOutil[$entree.tool] = $entree }

Assert-Equal 'PRESENT_BEFORE' $parOutil['powershell'].outcome 'un outil present appartient au systeme'
Assert-Equal 'NOT_OFFERED' $parOutil['winget'].outcome 'un outil absent n a pas ete propose'

# `DECLINED` signifierait que la question a ete posee et refusee. Elle ne l a
# jamais ete sous Windows : confondre les deux ferait passer un audit ordinaire
# pour un audit ou l utilisateur aurait tout refuse.
$refuses = @($inventaire | Where-Object { $_.outcome -eq 'DECLINED' })
Assert-Equal 0 $refuses.Count 'aucun refus n est invente'

$installes = @($inventaire | Where-Object { $_.outcome -eq 'INSTALLED' })
Assert-Equal 0 $installes.Count 'rien n est jamais marque installe par SysAudit'

# Le coeur de l ADR 0008 : rien de ce que le systeme fournit ne peut etre
# retire. Sous Windows, aucune entree ne doit donc porter autre chose que
# NOT_APPLICABLE.
$retraits = @($inventaire | Where-Object { $_.removal -ne 'NOT_APPLICABLE' })
Assert-Equal 0 $retraits.Count 'aucun outil du systeme n est propose au retrait'

# `used` n est pas connu sous Windows : les cmdlets sont appelees directement
# depuis chaque collecteur, sans point de passage unique. L emettre a `false`
# ferait passer pour inutile un outil dont on ignore s il a servi.
$avecUsage = @($inventaire | Where-Object { $_.ContainsKey('used') })
Assert-Equal 0 $avecUsage.Count 'l usage non determinable est omis, jamais suppose faux'

Assert-Equal 0 @(Get-DependencyInventory -Tools @{}).Count 'une table vide ne fabrique aucune entree'

# Meme classe de defaut que pour `ipv4` et `power.batteries`, mais dans l'autre
# sens : la fonction renvoyait `, $records`, et `sysaudit.ps1` entourait l'appel
# d'un `@()`. Les deux protections cumulees produisaient un tableau **contenant
# le tableau**, et l'API refusait tout le rapport sur
# `$.collection.dependencies.0` : « expected object, received array ».
#
# Le controle porte donc sur l'expression telle qu'elle est ecrite au point
# d'appel, et sur le JSON produit — pas sur le type de la variable, qui etait
# correct dans les tests precisement parce qu'ils omettaient le `@()`.
$jsonDeps = @{ dependencies = @(Get-DependencyInventory -Tools @{ powershell = $true }) } |
  ConvertTo-Json -Depth 6 -Compress
Assert-True ($jsonDeps -like '*"dependencies":[[]{*') 'un outil unique donne un tableau d''objets, pas un tableau de tableaux'
Assert-True ($jsonDeps -like '*"tool":"powershell"*') 'l''outil unique n''est pas perdu'

$jsonDepsTrois = @{ dependencies = @(Get-DependencyInventory -Tools @{
      powershell = $true
      winget     = $false
      defender   = $true
    }) } | ConvertTo-Json -Depth 6 -Compress
Assert-True ($jsonDepsTrois -like '*"dependencies":[[]{*') 'plusieurs outils donnent un tableau d''objets'

$jsonDepsVide = @{ dependencies = @(Get-DependencyInventory -Tools @{}) } |
  ConvertTo-Json -Depth 6 -Compress
Assert-Equal '{"dependencies":[]}' $jsonDepsVide 'aucun outil donne un tableau vide, pas null'

# --- Bloc d'alimentation ----------------------------------------------------

Write-Suite 'Alimentation : table SMBIOS type 39'

<#
  Fabrique une structure SMBIOS type 39, telle que la specification la decrit.

  Aucune machine de CI ne possede de firmware qui en publie une : la table est
  donc construite octet par octet, ce qui teste exactement ce que le collecteur
  lira sur un serveur — et rien d'autre.
#>
function New-Type39Table {
  param(
    [int]$Capacity = 750,
    [int]$Characteristics = 0x1183,
    [string[]]$Strings = @('Bay 1', 'PWS-751-1R', 'Supermicro', 'P751ABC123', 'To Be Filled By O.E.M.', 'PWS-751-1R', '1.0')
  )

  $bytes = New-Object System.Collections.Generic.List[byte]
  foreach ($b in @(39, 0x16, 0x00, 0x26, 1, 1, 2, 3, 4, 5, 6, 7)) { $bytes.Add([byte]$b) }
  $bytes.Add([byte]($Capacity -band 0xFF))
  $bytes.Add([byte](($Capacity -shr 8) -band 0xFF))
  $bytes.Add([byte]($Characteristics -band 0xFF))
  $bytes.Add([byte](($Characteristics -shr 8) -band 0xFF))
  1..6 | ForEach-Object { $bytes.Add([byte]0) }
  foreach ($text in $Strings) {
    foreach ($char in $text.ToCharArray()) { $bytes.Add([byte][char]$char) }
    $bytes.Add([byte]0)
  }
  $bytes.Add([byte]0)
  return $bytes.ToArray()
}

$psuUnits = @(ConvertFrom-SmbiosPowerSupplyTable -Data (New-Type39Table))
Assert-Equal 1 $psuUnits.Count 'une structure type 39 donne une alimentation'
Assert-Equal 'Supermicro' $psuUnits[0].manufacturer 'le fabricant vient du firmware'
Assert-Equal 750 $psuUnits[0].ratedPowerWatts 'la puissance nominale est celle que le firmware annonce'
Assert-Equal 'STANDARD_ATX' $psuUnits[0].type 'une alimentation a decoupage est reconnue par le firmware'
Assert-Equal 'OK' $psuUnits[0].status 'l''etat est decode depuis le mot de caracteristiques'
Assert-True ($psuUnits[0].present -eq $true) 'la presence est un fait distinct de l''etat'
Assert-True ($psuUnits[0].hotReplaceable -eq $true) 'le remplacement a chaud est lu sur son propre bit'
Assert-True ($psuUnits[0].assetTag -is [hashtable]) 'un texte de remplissage du firmware n''est pas une donnee'
Assert-True (Test-PowerSupplyDetected -Units $psuUnits) 'une alimentation identifiee est declaree detectee'

# 0x8000 est le code « inconnu » de la specification : le prendre pour une
# puissance annoncerait une alimentation de 32 768 W.
$psuUnknown = @(ConvertFrom-SmbiosPowerSupplyTable -Data (New-Type39Table -Capacity 0x8000 -Characteristics 0x0102))
Assert-True ($psuUnknown[0].ratedPowerWatts -is [hashtable]) `
  'le code « inconnu » ne devient pas une puissance de 32 768 W'
Assert-Equal 'UNKNOWN' $psuUnknown[0].type 'une nature non declaree reste inconnue'

# Une machine sans structure type 39 — la quasi-totalite du parc grand public.
$psuNone = @(ConvertFrom-SmbiosPowerSupplyTable -Data ([byte[]]@(1, 0x1B, 0x00, 0x01, 0, 0)))
Assert-Equal 0 $psuNone.Count 'une table sans type 39 ne fabrique aucune alimentation'
Assert-True (-not (Test-PowerSupplyDetected -Units $psuNone)) `
  'sans structure, rien n''est declare detecte'

# Une table tronquee ne doit ni boucler ni produire de donnee.
$psuTruncated = @(ConvertFrom-SmbiosPowerSupplyTable -Data ([byte[]]@(39, 0x16, 0x00, 0x26)))
Assert-Equal 0 $psuTruncated.Count 'une table tronquee est abandonnee, pas devinee'

Write-Suite 'Alimentation : rails et consommation'

# Un capteur de tension appartient au bloc seulement si le moniteur le rattache
# a un materiel de type PSU. Tous les autres sont ceux de la carte mere.
$railMotherboard = ConvertTo-PowerRail -Sensor ([pscustomobject]@{ Name = '+12V'; Value = 12.096 }) `
  -HardwareType 'Mainboard' -Source 'HARDWARE_MONITOR'
Assert-Equal 'MOTHERBOARD' $railMotherboard.measuredBy `
  'une tension lue sur la carte mere n''est pas presentee comme venant du bloc'
Assert-Equal 12.096 $railMotherboard.volts 'la tension est celle du capteur'

$railPsu = ConvertTo-PowerRail -Sensor ([pscustomobject]@{ Name = '+12V'; Value = 12.02 }) `
  -HardwareType 'Psu' -Source 'HARDWARE_MONITOR'
Assert-Equal 'POWER_SUPPLY' $railPsu.measuredBy 'un bloc numerique mesure ses propres rails'

Assert-Equal 'CPU' (Get-ComponentPowerKind -HardwareType 'Cpu' -SensorName 'CPU Package') `
  'la puissance du paquet processeur est rattachee au processeur'
Assert-Equal 'GPU' (Get-ComponentPowerKind -HardwareType 'GpuNvidia' -SensorName 'GPU Power') `
  'la puissance de la carte graphique lui est rattachee'
Assert-Equal '' (Get-ComponentPowerKind -HardwareType 'Mainboard' -SensorName 'Power 3') `
  'un capteur de puissance non identifie n''est attribue a aucun composant'

Assert-Equal 'DIGITAL_ATX' (Get-OverallPowerSupplyType -Units @(
    @{ type = 'UNKNOWN' }, @{ type = 'DIGITAL_ATX' }, @{ type = 'STANDARD_ATX' })) `
  'un bloc qui parle prime sur un bloc que le firmware decrit'
Assert-Equal 'UNKNOWN' (Get-OverallPowerSupplyType -Units @()) `
  'sans unite, la nature reste inconnue'

# Une unite dont tous les champs d'identite sont des marqueurs d'absence n'est
# pas une alimentation detectee : c'est une ligne de firmware vide.
Assert-True (-not (Test-PowerSupplyDetected -Units @(@{
        label = 'Alimentation'
        manufacturer = (New-Unknown -Reason 'NOT_AVAILABLE')
        ratedPowerWatts = (New-Unknown -Reason 'NOT_AVAILABLE')
      }))) 'une unite sans identite ne vaut pas detection'

Write-Suite 'Motif d''absence des champs non implementes'

# Trouve en auditant un vrai poste Windows 11, pas en test.
#
# `NOT_AVAILABLE` affirme que la source est absente du systeme. Windows Update
# existe toujours sur Windows : le rapport annoncait un poste sans service de
# mise a jour, et envoyait le lecteur chercher ce qu'il a deja. Ce qui manque
# est le collecteur, pas la source — c'est ce que `UNSUPPORTED` veut dire.
#
# La fonction est appelee, pas relue : un test qui cherche une chaine dans le
# source passe encore le jour ou l'appelant cesse de s'en servir.
$updateUnknown = New-UpdateUnknown
Assert-Equal 'UNSUPPORTED' $updateUnknown.reason `
  'un champ de mise a jour non implemente porte UNSUPPORTED'
Assert-True ($updateUnknown.unknown -eq $true) `
  'le marqueur reste un marqueur d''absence'
Assert-True ($updateUnknown.detail -like '*pas encore implementee*') `
  'le detail dit que le collecteur manque, pas la source'

Write-Suite 'Proxy d''entreprise'

# Le defaut repare : sur un poste d'entreprise, PowerShell 5.1 ne lit ni
# HTTPS_PROXY ni HTTP_PROXY, et ne presente aucun identifiant au proxy systeme.
# La collecte reussissait, l'envoi echouait — le pire ordre possible.

Assert-Equal 'http://explicite:3128' `
  (Resolve-SysAuditProxyUrl -Explicit 'http://explicite:3128' -SysAuditProxy 'http://sysaudit:1' -HttpsProxy 'http://https:2' -HttpProxy 'http://http:3') `
  '-Proxy l''emporte sur toutes les variables'

Assert-Equal 'http://sysaudit:1' `
  (Resolve-SysAuditProxyUrl -SysAuditProxy 'http://sysaudit:1' -HttpsProxy 'http://https:2') `
  'SYSAUDIT_PROXY passe avant HTTPS_PROXY'

Assert-Equal 'http://https:2' `
  (Resolve-SysAuditProxyUrl -HttpsProxy 'http://https:2' -HttpProxy 'http://http:3') `
  'HTTPS_PROXY passe avant HTTP_PROXY'

Assert-Equal 'http://http:3' (Resolve-SysAuditProxyUrl -HttpProxy 'http://http:3') `
  'HTTP_PROXY sert de dernier recours'

# Une variable posee a vide est une variable absente, pas un proxy vide.
Assert-Equal '' (Resolve-SysAuditProxyUrl -Explicit '   ' -HttpsProxy '') `
  'une valeur blanche ne designe aucun proxy'

Assert-Equal 'http://espaces:8080' (Resolve-SysAuditProxyUrl -Explicit '  http://espaces:8080  ') `
  'les espaces autour de l''adresse sont retires'

# --- Application ------------------------------------------------------------
#
# `Set-SysAuditProxy` modifie l'etat du processus : l'ancien proxy est remis en
# place a la fin, faute de quoi les tests suivants passeraient par un proxy
# imaginaire.
$previousProxy = [System.Net.WebRequest]::DefaultWebProxy

try {
  Assert-Equal 'proxy.exemple.local:8080' (Set-SysAuditProxy -ProxyUrl 'http://proxy.exemple.local:8080') `
    'l''adresse appliquee est rendue, hote et port'

  $applied = [System.Net.WebRequest]::DefaultWebProxy
  Assert-Equal 'proxy.exemple.local' $applied.Address.Host `
    'DefaultWebProxy vise bien l''hote demande — donc WebClient aussi'
  Assert-Equal '8080' ([string]$applied.Address.Port) 'le port est conserve'
  Assert-True ($null -ne $applied.Credentials) `
    'des identifiants sont presentes : un proxy NTLM repondait 407 sans eux'

  # Sans schema, la forme la plus souvent tapee.
  Assert-Equal 'nu.exemple.local:3128' (Set-SysAuditProxy -ProxyUrl 'nu.exemple.local:3128') `
    'une adresse sans schema est prefixee plutot que refusee'

  # Identifiants dans l'URL : ils doivent devenir des identifiants, jamais
  # rester dans l'adresse — celle-ci s'affiche et se journalise.
  $rendered = Set-SysAuditProxy -ProxyUrl 'http://domaine%5Cutilisateur:s%40cret@auth.exemple.local:8080'
  Assert-Equal 'auth.exemple.local:8080' $rendered `
    'l''adresse rendue ne porte aucun identifiant'
  $credential = [System.Net.WebRequest]::DefaultWebProxy.Credentials.GetCredential(
    [Uri]'http://auth.exemple.local:8080', 'Basic')
  Assert-Equal 'domaine\utilisateur' $credential.UserName `
    'l''utilisateur est decode depuis l''URL'
  Assert-Equal 's@cret' $credential.Password `
    'le mot de passe est decode : un `@` ne peut voyager autrement'

  # Rien de declare : le proxy systeme reste en place, on ne lui ajoute que de
  # quoi s'authentifier. Retourner une adresse ici ferait croire a un proxy
  # impose par le scanner.
  Assert-Equal '' (Set-SysAuditProxy -ProxyUrl '') `
    'sans declaration, aucune adresse n''est imposee'
} finally {
  [System.Net.WebRequest]::DefaultWebProxy = $previousProxy
}

# --- Transport : classification des echecs ----------------------------------

Write-Suite 'Transport : classification des echecs reseau'

# Un envoi refuse remontait le corps brut de la reponse, ou une exception .NET
# dont le message ne distingue pas un nom qui ne resout pas d'un proxy qui
# reclame des identifiants.
Assert-True ((Get-SysAuditTransportFailure -Status 'NameResolutionFailure') -like '*DNS*') `
  'NameResolutionFailure est nomme DNS'
Assert-True ((Get-SysAuditTransportFailure -Status 'ConnectFailure') -like '*pare-feu*') `
  'ConnectFailure nomme le pare-feu'
Assert-True ((Get-SysAuditTransportFailure -Status 'Timeout') -like '*delai depasse*') `
  'Timeout nomme le delai'
Assert-True ((Get-SysAuditTransportFailure -Status 'TrustFailure') -like '*inspection HTTPS*') `
  'un certificat refuse evoque l''inspection HTTPS'

# Un statut non prevu est rendu tel quel plutot que range dans un fourre-tout :
# « SendFailure » se cherche, « erreur reseau » non.
Assert-True ((Get-SysAuditTransportFailure -Status 'KeepAliveFailure') -like '*KeepAliveFailure*') `
  'un statut inconnu reste identifiable'
Assert-True ((Get-SysAuditTransportFailure -Status '') -like '*inconnue*') `
  'une cause absente se dit inconnue, plutot que de s''inventer'

Assert-True ((Get-SysAuditHttpFailure -StatusCode 407) -like '*proxy*') 'le 407 designe le proxy'
Assert-True ((Get-SysAuditHttpFailure -StatusCode 403) -like '*filtrage*') 'le 403 evoque le filtrage'
Assert-True ((Get-SysAuditHttpFailure -StatusCode 503) -like '*serveur SysAudit*') `
  'un 5xx designe le serveur'
Assert-True ((Get-SysAuditHttpFailure -StatusCode 0) -like '*aucune reponse*') `
  'l''absence de reponse se dit, plutot que de passer pour un statut'

# Le conseil n'existe que lorsqu'il en existe un : « verifiez votre connexion »
# n'aide personne et occupe la place du message utile.
Assert-True ((Get-SysAuditNetworkHint -Cause (Get-SysAuditHttpFailure -StatusCode 407)) -like '*-Proxy*') `
  'le 407 dit comment declarer un proxy'
Assert-Equal '' (Get-SysAuditNetworkHint -Cause (Get-SysAuditHttpFailure -StatusCode 429)) `
  'un quota depasse n''invente pas de conseil'

# --- Transport : les identifiants de proxy ne fuient pas --------------------

Write-Suite 'Transport : les identifiants de proxy ne fuient pas'

$display = Get-SysAuditProxyDisplay -ProxyUrl 'http://domaine%5Cutilisateur:s%40cret@proxy.local:8080'
Assert-Equal 'proxy.local:8080' $display 'les identifiants sont retires de l''adresse affichee'
Assert-True ($display -notlike '*cret*') 'le mot de passe ne survit pas au masquage'
Assert-Equal '' (Get-SysAuditProxyDisplay -ProxyUrl '') 'rien de declare ne rend rien'

# L'ordre reproduit celui de `Resolve-SysAuditProxyUrl` : annoncer une variable
# qui ne sera pas celle retenue serait pire que ne rien annoncer.
Assert-Equal 'HTTPS_PROXY=a.local:3128' (Get-SysAuditDeclaredProxy `
    -HttpsProxy 'http://user:pass@a.local:3128' -HttpProxy 'http://b.local:3128') `
  'HTTPS_PROXY l''emporte sur HTTP_PROXY, et sort masque'
Assert-Equal '-Proxy=c.local:8080' (Get-SysAuditDeclaredProxy `
    -Explicit 'http://c.local:8080' -HttpsProxy 'http://a.local:3128') `
  '-Proxy l''emporte sur l''environnement'
Assert-Equal '' (Get-SysAuditDeclaredProxy) `
  'rien de declare rend une chaine vide, pas une valeur inventee'

# --- Test reseau : aucun audit produit --------------------------------------

Write-Suite 'Test reseau : aucun audit produit'

# La cible est `/api/health`, en lecture seule : `/api/audit/bootstrap/…` cree
# une session en base, et un test de connectivite n'a pas a laisser de trace.
#
# Les commentaires sont retires avant l'examen : ils **citent** les points
# d'entree qu'on s'interdit, pour expliquer pourquoi.
$transportCode = (Get-Content (Join-Path $scannerRoot 'lib/core/transport.ps1')) |
  Where-Object { $_ -notmatch '^\s*#' }
$transportCode = $transportCode -join "`n"

Assert-True ($transportCode -like '*/api/health*') 'le test vise le point de sante'
Assert-True ($transportCode -notlike '*/api/audit/bootstrap*') `
  'le test ne cree pas de session d''audit'
Assert-True ($transportCode -notlike '*/api/v1/scans/upload*') `
  'le test n''envoie aucun rapport'

# -NetworkTest sort avant toute collecte, et n'implique pas -Upload : un test de
# connectivite qui lancerait un audit obligerait a choisir entre savoir et ne
# pas auditer.
$scannerSource = Get-Content (Join-Path $scannerRoot 'sysaudit.ps1') -Raw
$transportSource = Get-Content (Join-Path $scannerRoot 'lib/core/transport.ps1') -Raw
Assert-True ($scannerSource -match '(?s)if \(\$NetworkTest\).*?Invoke-SysAuditNetworkTest') `
  '-NetworkTest delegue au test reseau'
Assert-True ($scannerSource -match '(?s)if \(\$NetworkTest\).*?exit \$script:EXIT_TRANSPORT_FAILED') `
  '-NetworkTest rend un code de sortie exploitable'

# La validation du certificat est retablie apres un essai non verifie. Sans
# cela, un scanner ayant teste le reseau enverrait ensuite son rapport sans
# verifier aucun certificat — exactement ce contre quoi le test previent.
Assert-True ($transportCode -match '(?s)ServerCertificateValidationCallback = \$previousCallback') `
  'la validation du certificat est retablie apres un essai non verifie'

# --- Ouverture du rapport ---------------------------------------------------

Write-Suite 'Ouverture du rapport'

# Ces cas sont tous des REFUS : le chemin nominal lancerait un navigateur, ce
# qu'une suite de tests n'a pas a faire. Ce sont de toute facon les seuls cas
# interessants — l'adresse vient de l'API, et `Start-Process` lance aussi
# volontiers un executable qu'une page web.
Assert-Equal $false (Open-ReportInBrowser -Url '') 'aucune adresse : rien n''est lance'
Assert-Equal $false (Open-ReportInBrowser -Url 'sysaudit-MSI.json') `
  'une adresse relative n''est pas ouverte'
Assert-Equal $false (Open-ReportInBrowser -Url 'file:///C:/Windows/System32/calc.exe') `
  'un fichier local n''est pas ouvert'
Assert-Equal $false (Open-ReportInBrowser -Url 'C:\Windows\System32\calc.exe') `
  'un chemin Windows n''est pas ouvert'
Assert-Equal $false (Open-ReportInBrowser -Url 'javascript:alert(1)') `
  'un schema non HTTP n''est pas ouvert'

# L'ouverture n'a lieu qu'apres un envoi reussi, et se refuse. Un audit local
# n'a pas de page a ouvrir, et une execution automatisee n'attend pas de
# fenetre.
Assert-True ($scannerSource -match '(?s)Rapport disponible.*?if \(-not \$NoOpen -and -not \$Quiet\)') `
  'le navigateur ne s''ouvre qu''apres l''adresse du rapport'
Assert-True ($scannerSource -match '\[switch\]\$NoOpen') '-NoOpen existe'

# Un navigateur lance depuis une console administrateur heriterait de ces
# droits. `explorer.exe` tourne sous la session ouverte.
Assert-True ($scannerSource -match 'Open-ReportInBrowser -Url \$reportUrl -Elevated:\(Test-IsAdministrator\)') `
  'l''elevation est transmise a l''ouverture'

# --- Envoi : aucune attente muette ------------------------------------------

Write-Suite 'Envoi'

# La condition de boucle porte sur `$response` : une reponse acceptee mais
# illisible la laissait a $null et relancait l'envoi indefiniment, sans rien
# afficher. Le scanner paraissait s'arreter apres « Rapport ecrit ».
Assert-True ($scannerSource -match '(?s)Envoi accepte par le serveur, mais reponse illisible.*?exit \$script:EXIT_TRANSPORT_FAILED') `
  'une reponse illisible sort en 2 au lieu de reessayer sans fin'

# L'envoi est le seul appel bloquant du scanner : il s'annonce avant d'etre
# tente, faute de quoi une attente ne se distingue pas d'une fin d'execution.
Assert-True ($scannerSource -match '(?s)Envoi du rapport a.*?Invoke-SysAuditUpload') `
  'l''envoi est annonce avant d''etre tente'

# `WebClient` n'expose aucun delai. Un serveur qui accepte la connexion sans
# jamais repondre figeait la console sur « Envoi du rapport a … », sans message
# ni code de sortie — et tout le catalogue de causes, « delai depasse » compris,
# devenait inatteignable faute d'exception a attraper.
Assert-True ($scannerSource -notmatch 'System\.Net\.WebClient') `
  'le televersement ne passe plus par WebClient'
Assert-True ($scannerSource -match 'TimeoutSeconds \$script:UPLOAD_TIMEOUT_SECONDS') `
  'le televersement porte un delai maximal'
Assert-True ($script:UPLOAD_TIMEOUT_SECONDS -gt 0) `
  'le delai de televersement est fini'

# Les deux delais de `HttpWebRequest` sont distincts et les deux comptent :
# `Timeout` borne l'attente des en-tetes, `ReadWriteTimeout` borne l'ecriture du
# corps et sa relecture. Ne poser que le premier laisse bloquer dans le flux.
Assert-True ($transportSource -match '\$request\.Timeout = \$TimeoutSeconds \* 1000') `
  'le delai d''attente des en-tetes est pose'
Assert-True ($transportSource -match '\$request\.ReadWriteTimeout = \$TimeoutSeconds \* 1000') `
  'le delai de lecture et d''ecriture est pose'

# `Expect: 100-continue` fait attendre l'aval du serveur avant d'envoyer le
# corps. Un equipement intermediaire qui ne le renvoie jamais transforme cette
# politesse en attente pure.
Assert-True ($transportSource -match 'Expect100Continue = \$false') `
  'l''envoi ne demande pas la permission avant de transmettre'

# --- Adresse publique -------------------------------------------------------

Write-Suite 'Portee de publication : demander le prive doit etre possible'

# Le defaut d'une instance peut valoir PUBLIC. Ne rien dire n'est alors pas
# demander le prive : c'est laisser l'instance trancher. Le scanner n'envoyait
# l'en-tete que pour publier, si bien qu'un audit de validation devenait
# repertoriable sans que personne l'ait demande — constate le 2026-08-27 en
# production, et corrige apres coup en base.
Assert-True ($scannerSource -match '\[switch\]\$Private') '-Private existe'
Assert-True ($scannerSource -match "elseif \(\`$Private\) \{\s*\r?\n?\s*\`$uploadHeaders\['X-Scan-Visibility'\] = 'private'") `
  '-Private envoie explicitement la portee privee'
Assert-True ($scannerSource -match "if \(\`$Public\) \{\s*\r?\n?\s*\`$uploadHeaders\['X-Scan-Visibility'\] = 'public'") `
  '-Public continue d''envoyer la portee publique'

# Deux intentions contraires ne se departagent pas en silence.
Assert-True ($scannerSource -match "(?s)if \(\`$Public -and \`$Private\).*?throw '-Public et -Private s''excluent") `
  '-Public et -Private ensemble sont refuses'
Assert-True ($scannerSource -match "(?s)if \(-not \`$Upload -and \`$Private\).*?throw '-Private exige -Upload") `
  '-Private sans -Upload est refuse'

# **La position, et pas seulement l'existence.**
#
# Ces trois refus ont vecu cinq cents lignes plus bas, au moment de l'envoi. Le
# test precedent passait quand meme : il prouvait que le refus existe, pas qu'il
# arrive a temps. Mesure sur le vrai hote Windows le 2026-08-27, le scan complet
# se deroulait d'abord — plusieurs minutes — et l'erreur tombait apres, pour une
# contradiction lisible sur la ligne de commande.
#
# Un test qui ne regarde que l'existence d'un garde-fou ne dit rien de ce qu'il
# garde.
$premiereCollecte = $scannerSource.IndexOf("Invoke-Collector -Section 'system'")
Assert-True ($premiereCollecte -gt 0) 'la premiere collecte est reperable'
foreach ($refus in @(
    '-Public exige -Upload',
    '-Private exige -Upload',
    "-Public et -Private s''excluent",
    '-Claim exige -Upload')) {
  $position = $scannerSource.IndexOf($refus)
  Assert-True ($position -gt 0) ("le refus « $refus » existe")
  Assert-True ($position -lt $premiereCollecte) `
    ("le refus « $refus » precede la collecte")
}

Write-Suite 'Adresse publique : la seule sortie reseau de la collecte'

$networkSource = Get-Content (Join-Path $scannerRoot 'lib/collectors/network.ps1') -Raw

# Le collecteur ne sort du reseau que si on lui donne une adresse d'API. Elle
# lui est donnee des qu'une API est connue et que -NoPublicIp n'est pas pose :
# ce test fige les deux conditions, et rien d'autre ne doit s'y ajouter.
Assert-True ($scannerSource -match '\[switch\]\$PublicIp') '-PublicIp existe'
Assert-True ($scannerSource -match '\[switch\]\$NoPublicIp') '-NoPublicIp existe'
Assert-True ($scannerSource -match "(?s)\`$script:CollectPublicIp =\s*\r?\n?\s*\(-not \`$NoPublicIp\) -and \(-not \[string\]::IsNullOrWhiteSpace\(\`$ApiUrl\)\)") `
  'l''adresse est relevee des qu''une API est connue, sauf -NoPublicIp'
Assert-True ($scannerSource -match "if \(\`$script:CollectPublicIp\) \{ \`$ApiUrl \} else \{ '' \}") `
  'le collecteur ne recoit une API que dans ce cas'
Assert-True ($networkSource.Contains("[string]`$PublicIpApiUrl = ''")) `
  'le collecteur n''interroge personne sans qu''on le lui demande'

# Le refus ne vise QUE la demande explicite : un audit hors ligne ne doit pas
# echouer parce que le defaut a change.
Assert-True ($scannerSource -match "(?s)if \(\`$PublicIp -and \[string\]::IsNullOrWhiteSpace\(\`$ApiUrl\)\).*?throw '-PublicIp exige -ApiUrl") `
  '-PublicIp sans -ApiUrl est refuse'
Assert-True ($scannerSource.IndexOf('-PublicIp exige -ApiUrl') -lt $scannerSource.IndexOf("Invoke-Collector -Section 'network'")) `
  'le refus precede la collecte, et ne la gaspille pas'

# Sans API a interroger, le champ doit rester ABSENT du rapport. Un marqueur
# « non collecte » deviendrait « information protegee » a la lecture par un
# tiers : une promesse de valeur qui n'existe pas.
$sansPublicIp = Get-NetworkInventory -PublicIpApiUrl ''
Assert-True (-not $sansPublicIp.ContainsKey('publicIp')) `
  'sans API, aucun champ publicIp n''est emis'

# Une API injoignable donne un marqueur portant sa raison, jamais une valeur
# inventee ni un champ tu.
$injoignable = Get-SysAuditPublicIp -ApiUrl 'https://exemple.invalid' -TimeoutSeconds 2
Assert-True ($injoignable.unknown -eq $true) `
  'une API injoignable donne un marqueur, pas une valeur'
Assert-Equal 'NOT_AVAILABLE' $injoignable.reason 'le marqueur porte sa raison'

# TLS 1.2 est pose avant la collecte, et pas seulement avant l'envoi : celui-ci
# arrive bien plus bas, apres l'ecriture du rapport. Sans ce reglage, un hote
# qui refuse TLS 1.1 et anterieur coupe la connexion, et le champ porterait
# « l'API n'a pas repondu » pour une raison etrangere a l'API.
Assert-True ($scannerSource -match "(?s)if \(\`$script:CollectPublicIp\) \{.*?SecurityProtocol.*?Set-SysAuditProxy") `
  'TLS et proxy sont regles avant la collecte quand l''adresse sera relevee'

# --- Codes de sortie --------------------------------------------------------

Write-Suite 'Codes de sortie'

# Trois valeurs, identiques a celles du scanner Linux : un ordonnanceur qui
# pilote un parc mixte ne doit pas avoir deux tables a tenir. La distinction
# entre 1 et 2 est ce qui permet de ne pas confondre « machine non auditable »
# et « reseau ferme ».
Assert-Equal 0 $script:EXIT_OK 'le succes vaut 0'
Assert-Equal 1 $script:EXIT_AUDIT_FAILED 'un audit impossible vaut 1'
Assert-Equal 2 $script:EXIT_TRANSPORT_FAILED 'une transmission echouee vaut 2'

# Un echec d'envoi ne doit plus passer par `throw`, qui sortait en 1 : le
# rapport existe, seule sa remise a manque.
Assert-True ($scannerSource -notmatch "throw \('Upload refuse par l''API") `
  'un envoi refuse ne releve plus une exception'
Assert-True ($scannerSource -match '(?s)Envoi refuse — .*?exit \$script:EXIT_TRANSPORT_FAILED') `
  'un envoi refuse sort en 2'

# Le domaine est en `.invalid`, reserve par la RFC 2606 : il ne resout nulle
# part, aucun paquet ne part vers un tiers.
$scannerPath = Join-Path $scannerRoot 'sysaudit.ps1'
$pwshPath = (Get-Process -Id $PID).Path

& $pwshPath -NoProfile -File $scannerPath -NetworkTest -ApiUrl 'https://exemple.invalid' *> $null
Assert-Equal 2 $LASTEXITCODE 'un reseau qui ne passerait pas sort en 2, pas en 1'

# Ici le scanner **refuse**, et il l'ecrit sur la sortie d'erreur — c'est
# exactement ce que ce cas verifie. Or `*> $null` ne suffit pas sous Windows
# PowerShell 5.1 : chaque ligne ecrite par un executable natif sur cette sortie
# y devient un ErrorRecord, que le `$ErrorActionPreference = 'Stop'` de la
# ligne 21 transforme en erreur terminante. La suite s'arretait donc ici, apres
# 656 assertions vertes, au premier endroit ou elle verifie un refus.
#
# Sous `pwsh` 7 — celui que `scripts/run-powershell.mjs` prefere, et le seul
# present sur les agents de la CI — la promotion n'a pas lieu : le defaut ne se
# voit que sur une machine sans PowerShell 7. Constate le 2026-08-28, et
# reproduit a l'identique en CRLF comme en LF.
#
# La preference est abaissee pour la duree du seul appel, puis restauree. Rien
# n'est masque : la sortie d'erreur part toujours dans `$null` comme avant, le
# code de sortie reste celui du scanner, et l'assertion ne bouge pas.
$preferencePrecedente = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
  & $pwshPath -NoProfile -File $scannerPath -NetworkTest *> $null
} finally {
  $ErrorActionPreference = $preferencePrecedente
}
Assert-Equal 1 $LASTEXITCODE 'un usage incorrect sort en 1'

# --- Identite verifiable (-Verify) ------------------------------------------

Write-Suite 'Identite verifiable'

# `-Verify` repond a « qu'est-ce que je m'apprete a executer ? ». Elle se pose
# quand un antivirus signale le scanner, et elle n'avait aucune reponse dans le
# produit.
$verifyOutput = & $pwshPath -NoProfile -File $scannerPath -Verify 2>&1 | Out-String
Assert-Equal 0 $LASTEXITCODE '-Verify sort en 0'

Assert-True ($verifyOutput -match 'Version\s+:') '-Verify affiche la version'
Assert-True ($verifyOutput -match 'Chemin\s+:') '-Verify affiche le chemin execute'
Assert-True ($verifyOutput -match '[0-9a-f]{64}\s+sysaudit\.ps1') `
  '-Verify affiche l''empreinte SHA-256 de chaque fichier'
Assert-True ($verifyOutput -match 'Signature Authenticode') `
  '-Verify rend compte de la signature, meme absente'

# La phrase compte autant que les empreintes : une empreinte identique prouve
# que le fichier est CELUI-LA, pas qu'il est sain. Les confondre est
# exactement ce qu'un document de reponse a un faux positif ne doit pas faire.
Assert-True ($verifyOutput -match 'ne prouve pas qu') `
  '-Verify ne presente pas une empreinte comme une preuve d''innocuite'

# Purement informatif. Ces quatre interdits sont le coeur du contrat : un outil
# qui repond a un antivirus en le desarmant a change de metier.
Assert-True (-not ($scannerSource -match 'Add-MpPreference')) `
  'le scanner n''ajoute aucune exclusion antivirus'
Assert-True (-not ($scannerSource -match 'Set-MpPreference')) `
  'le scanner ne modifie aucun reglage antivirus'
Assert-True (-not ($scannerSource -match 'AmsiUtils|amsiInitFailed')) `
  'le scanner ne touche pas a AMSI'
Assert-True (-not ($scannerSource -match 'Invoke-Expression|EncodedCommand|FromBase64String')) `
  'le scanner n''execute aucune chaine construite ni encodee'

# --- Barre de progression ---------------------------------------------------

Write-Suite 'Barre de progression'

# Une etape de plus que prevu donnait un pourcentage superieur a 100, donc une
# partie vide de barre de longueur negative, donc une ArgumentOutOfRangeException
# levee depuis `Invoke-Collector` : l'audit entier tombait au dernier collecteur,
# apres toute la collecte. Un decompte faux doit rester un affichage faux.
Start-ConsoleProgress -Total 3
$script:ProgressLabel = 'Etape'
$script:ProgressDone = 4

$line = $null
try {
  $line = Get-ConsoleProgressLine
} catch {
  Write-Host ('      levee : ' + $_.Exception.Message)
}

Assert-True ($null -ne $line) 'une etape de trop ne fait pas echouer la barre'
Assert-True ([string]$line -match '100%') 'le pourcentage est borne a 100'
Assert-True ($null -ne $line -and [string]$line -notmatch '\.') `
  'la barre est pleine, sans portion vide negative'

# Un total nul — verbosite ou hote sans barre — ne divise rien.
Start-ConsoleProgress -Total 0
Assert-True ((Get-ConsoleProgressLine) -match '0%') 'un total nul reste a 0 %'

# --- Repli console sans VT --------------------------------------------------

Write-Suite 'Repli console sans VT'

# Une console Windows 7 n'interprete pas les sequences VT : elle les imprime.
# Le QR Code renvoye par l'API arrive deja encode en ANSI, et sans ce repli
# l'ecran se remplissait de `<-[48;5;231m` sur toute la surface du dessin.
#
# Le rendu final demande un Windows 7, que ce poste n'a pas. La **regle** qui
# choisit le repli, elle, est une fonction pure : c'est elle qu'on eprouve ici,
# et c'est ce qui rend la ligne verifiable ailleurs que sur la machine cible.

Assert-True (-not (Resolve-ConsoleVirtualTerminalSupport -OsVersion ([version]'6.1.7601'))) `
  'Windows 7 n''a pas de traitement VT'
Assert-True (-not (Resolve-ConsoleVirtualTerminalSupport -OsVersion ([version]'6.3.9600'))) `
  'Windows 8.1 non plus'

# Le traitement VT arrive avec la build 10586 (Windows 10 1511) : la 10240, qui
# est aussi un « Windows 10 », ne l'a pas. Tester la seule version majeure
# aurait donc envoye des sequences a une console qui les imprime.
Assert-True (-not (Resolve-ConsoleVirtualTerminalSupport -OsVersion ([version]'10.0.10240'))) `
  'Windows 10 1507 est en deca de la build qui apporte le VT'
Assert-True (Resolve-ConsoleVirtualTerminalSupport -OsVersion ([version]'10.0.10586')) `
  'Windows 10 1511 l''apporte'
Assert-True (Resolve-ConsoleVirtualTerminalSupport -OsVersion ([version]'10.0.22000')) `
  'Windows 11 l''a'

# Le doute conclut a l'absence : perdre la couleur coute un dessin en noir et
# blanc, l'inverse remplit l'ecran de sequences imprimees.
Assert-True (-not (Resolve-ConsoleVirtualTerminalSupport -OsVersion 'pas une version')) `
  'une version illisible fait conclure a l''absence de VT'
Assert-True (-not (Resolve-ConsoleVirtualTerminalSupport -OsVersion $null)) `
  'une version absente fait conclure a l''absence de VT'

# ANSICON installe justement le traitement manquant sur une console ancienne :
# un Windows 7 qui l'annonce sait lire les sequences.
Assert-True (Resolve-ConsoleVirtualTerminalSupport -OsVersion ([version]'6.1.7601') `
    -Environment @{ ANSICON = '121x1000 (121x30)' }) `
  'ANSICON rend le VT disponible sur Windows 7'
Assert-True (Resolve-ConsoleVirtualTerminalSupport -OsVersion ([version]'6.1.7601') `
    -Environment @{ WT_SESSION = '0a1b2c3d' }) `
  'Windows Terminal est cru sur parole'

# `ConEmuANSI` est present dans les deux cas : sa valeur dit laquelle. Lire la
# seule presence de la variable aurait conclu l'inverse de ce qu'elle annonce.
Assert-True (Resolve-ConsoleVirtualTerminalSupport -OsVersion ([version]'6.1.7601') `
    -Environment @{ ConEmuANSI = 'ON' }) `
  'ConEmu avec traitement actif annonce le VT'
Assert-True (-not (Resolve-ConsoleVirtualTerminalSupport -OsVersion ([version]'6.1.7601') `
      -Environment @{ ConEmuANSI = 'OFF' })) `
  'ConEmu avec traitement desactive ne l''annonce pas'

# Une variable vide n'annonce rien.
Assert-True (-not (Resolve-ConsoleVirtualTerminalSupport -OsVersion ([version]'6.1.7601') `
      -Environment @{ WT_SESSION = '  ' })) `
  'une variable vide n''annonce aucun support'

Assert-True (Resolve-ConsoleVirtualTerminalSupport -OnWindows $false) `
  'un hote non-Windows a toujours eu le VT'

# --- Jeu de caracteres de la console ----------------------------------------

Write-Suite 'Jeu de caracteres de la console'

$cp437 = [Text.Encoding]::GetEncoding(437)
$cp850 = [Text.Encoding]::GetEncoding(850)
$cp1252 = [Text.Encoding]::GetEncoding(1252)
$cp932 = [Text.Encoding]::GetEncoding(932)
$utf8 = [Text.Encoding]::UTF8

# L'encodeur par defaut de .NET applique un *best-fit* : sur CP1252 il change
# `▄▀█` en `_¯¦`. Trois caracteres bien reels, aucun `?`, et un logo qui se lit
# `___¯¯¯¦¦¦`. Chercher des `?` dans un aller-retour aurait declare ce cas
# lisible ; l'encodeur strict le refuse.
Assert-True (-not (Test-EncodingRendersText -Encoding $cp1252 -Text '▄▀█')) `
  'le best-fit de CP1252 ne fait pas passer les blocs pour lisibles'
Assert-Equal '_¯¦' ($cp1252.GetString($cp1252.GetBytes('▄▀█'))) `
  'le best-fit substitue bien trois caracteres sans jamais produire de ?'

# CP437 et CP850 — les pages d'une console Windows 7 occidentale — connaissent
# les trois blocs du grand logo, et pas les quadrants du petit. Les rejeter
# ensemble aurait prive Windows 7 d'un logo qu'il sait dessiner.
Assert-True (Test-EncodingRendersText -Encoding $cp437 -Text '▄▀█') `
  'CP437 sait ecrire les blocs du grand logo'
Assert-True (-not (Test-EncodingRendersText -Encoding $cp437 -Text '▗▛▟')) `
  'CP437 ne sait pas ecrire les quadrants du petit logo'
Assert-True (Test-EncodingRendersText -Encoding $cp850 -Text '▄▀█') `
  'CP850 sait ecrire les blocs du grand logo'
Assert-True (Test-EncodingRendersText -Encoding $utf8 -Text '▄▀█▗▛▟·') `
  'UTF-8 ecrit tout le repertoire du logo'

# Le point median de la ligne de version survit aux pages occidentales et
# manque aux pages a double octet.
Assert-True (Test-EncodingRendersText -Encoding $cp437 -Text '·') `
  'CP437 ecrit le point median de la ligne de version'
Assert-True (-not (Test-EncodingRendersText -Encoding $cp932 -Text '·')) `
  'une page a double octet ne l''ecrit pas'

Assert-True (-not (Test-EncodingRendersText -Encoding $null -Text 'x')) `
  'un encodage absent fait conclure a l''absence'
Assert-True (Test-EncodingRendersText -Encoding $utf8 -Text '') `
  'un texte vide est toujours ecrivable'

# Un `?` deja present dans le texte ne doit pas se prendre pour un caractere
# perdu — c'est le piege que l'ancienne heuristique portait.
Assert-True (Test-EncodingRendersText -Encoding $cp437 -Text 'Quoi ?') `
  'un point d''interrogation d''origine reste lisible'

# --- Choix du logo ----------------------------------------------------------

Write-Suite 'Choix du logo'

# L'epreuve est derivee du dessin lui-meme : une retouche du logo change ce qui
# est teste, au lieu de laisser un echantillon recopie a la main se desynchroniser.
$largeText = ''
foreach ($line in $script:LogoLarge) { foreach ($half in $line) { $largeText += [string]$half } }
$smallText = ''
foreach ($line in $script:LogoSmall) { foreach ($half in $line) { $smallText += [string]$half } }

Assert-True (Test-EncodingRendersText -Encoding $cp437 -Text $largeText) `
  'le grand logo tient entier dans CP437'
Assert-True (-not (Test-EncodingRendersText -Encoding $cp437 -Text $smallText)) `
  'le petit logo n''y tient pas'
Assert-True (Test-EncodingRendersText -Encoding $utf8 -Text ($largeText + $smallText)) `
  'les deux logos tiennent dans UTF-8'

Assert-True (-not (Test-ConsoleArt -Art $null)) `
  'un dessin absent n''est pas declare dessinable'

# Le cablage se verifie sans supposer l'encodage de l'agent — il vaut UTF-8
# ici et une page OEM sur une console Windows classique, et un test qui aurait
# parie sur l'un des deux aurait echoue sur l'autre. Ce qui doit tenir partout,
# c'est que `Test-ConsoleArt` pose exactement la question de son dessin : elle
# doit lire les deux moities de chaque ligne, et non la seule premiere.
$consoleEncoding = [Console]::OutputEncoding
Assert-Equal (Test-EncodingRendersText -Encoding $consoleEncoding -Text $largeText) `
  (Test-ConsoleArt -Art $script:LogoLarge) `
  'Test-ConsoleArt eprouve le grand logo entier'
Assert-Equal (Test-EncodingRendersText -Encoding $consoleEncoding -Text $smallText) `
  (Test-ConsoleArt -Art $script:LogoSmall) `
  'Test-ConsoleArt eprouve le petit logo entier'

# La seconde moitie de chaque ligne porte le mot « Audit ». Un dessin dont
# seule la premiere moitie serait lue passerait le test precedent par accident :
# celui-ci le refuse, en n'ecrivant un caractere impossible que dans la seconde.
$halfBlind = @(@('AB', '▟'))
Assert-True (-not (Test-EncodingRendersText -Encoding $cp437 -Text '▟')) `
  'le caractere temoin est bien hors de CP437'
Assert-True ((Test-ConsoleArt -Art $halfBlind) -eq (Test-EncodingRendersText -Encoding $consoleEncoding -Text 'AB▟')) `
  'la seconde moitie de chaque ligne compte dans l''epreuve'

# --- Cablage du repli console -----------------------------------------------

Write-Suite 'Cablage du repli console'

# Les trois decisions ci-dessus ne valent que si le rendu les consulte. Or
# aucune ne peut se verifier a l'execution depuis cet agent : `Write-ConsoleLogo`
# et `Write-ConsoleQrCode` sortent des l'entree quand la sortie est redirigee,
# et elle l'est forcement dans une suite de tests. Un test d'affichage aurait
# donc passe au vert sans jamais atteindre la ligne qu'il pretend couvrir.
#
# La garde se lit alors dans le source, comme le decompte des collecteurs plus
# bas. Ce n'est pas un pis-aller : ce qui doit tenir est precisement qu'une
# retouche du rendu ne retire pas la garde sans que rien ne le dise.

$consoleSource = Get-Content (Join-Path $scannerRoot 'lib/output/console.ps1') -Raw

# Le QR `ansi` arrive du serveur avec ses sequences deja ecrites. La couleur ne
# suffit pas a le rendre : `Write-Host -ForegroundColor` passe par l'hote et
# marche sur Windows 7, les sequences non.
Assert-True ($consoleSource -match [regex]::Escape('(Test-ConsoleColor) -and (Test-ConsoleVirtualTerminal) -and $Qr.ansi')) `
  'le QR ANSI est garde par le traitement VT, pas par la seule couleur'

# Le dessin choisi est eprouve avec ses propres caracteres — les deux tailles
# n'ont pas le meme repertoire, et une garde commune aurait prive Windows 7 du
# grand logo qu'il sait dessiner.
Assert-True ($consoleSource -match [regex]::Escape('Test-ConsoleArt -Art $script:LogoLarge')) `
  'le grand logo est eprouve avant d''etre dessine'
Assert-True ($consoleSource -match [regex]::Escape('Test-ConsoleArt -Art $script:LogoSmall')) `
  'le petit logo aussi'

# La ligne de version n'a plus de point median en dur.
Assert-True ($consoleSource -notmatch [regex]::Escape("'  scanner Windows v{0} · schema {1}'")) `
  'la ligne de version ne porte plus de separateur non-ASCII en dur'
Assert-True ($consoleSource -match [regex]::Escape("Test-ConsoleRendersText -Text '·'")) `
  'le separateur de la ligne de version est eprouve'

# --- Decompte des collecteurs -----------------------------------------------

Write-Suite 'Decompte des collecteurs'

# `$plannedCollectors` est tenu a la main, a cote du branchement qu'il decrit :
# `devices` y manquait, et la barre depassait donc 100 % a chaque audit qui
# collecte les peripheriques. Le decompte se verifie ici faute de pouvoir se
# deduire — les deux listes vivent dans le meme fichier, et ce test les compare.
$plannedBase = 0
if ($scannerSource -match '(?m)^\$plannedCollectors = (\d+)') {
  $plannedBase = [int]$Matches[1]
}
$plannedIncrements = ([regex]::Matches($scannerSource, '\$plannedCollectors \+= 1')).Count
$collectorCalls = ([regex]::Matches($scannerSource, 'Invoke-Collector -Section')).Count

Assert-True ($collectorCalls -gt 0) 'les appels de collecteurs sont bien reperes'
Assert-Equal $collectorCalls ($plannedBase + $plannedIncrements) `
  'le nombre annonce a la barre est celui des collecteurs appeles'

# --- Banc d'essai hors profil poussee ---------------------------------------
#
# Le scanner Linux offre `--benchmark` depuis longtemps ; celui-ci n'avait rien
# d'equivalent, et reclamer une mesure obligeait a basculer tout l'audit en
# profil poussee. L'ecart se lisait dans le parc au 2026-08-27 : 9 % d'adoption
# cote Windows contre 23 % cote Linux.
#
# La regle des niveaux est eprouvee sur la vraie table, pas sur une copie : elle
# decide a la fois si la mesure a lieu et si son rappel s'affiche.

Write-Suite 'Banc d''essai hors profil poussee'

Assert-Equal 'skipped' (Get-LevelDepth -Section 'benchmark' -Level 'full') `
  'un audit complet ne mesure toujours pas les performances'
Assert-Equal 'skipped' (Get-LevelDepth -Section 'benchmark' -Level 'standard') `
  'un audit standard non plus'
Assert-Equal 'skipped' (Get-LevelDepth -Section 'benchmark' -Level 'quick') `
  'un audit rapide non plus'
Assert-True ((Get-LevelDepth -Section 'benchmark' -Level 'stress') -ne 'skipped') `
  'un audit pousse les mesure, et c''est le seul niveau qui le fasse'

Assert-True ($scannerSource -match '\[switch\]\$Benchmark') `
  'le commutateur -Benchmark existe'
Assert-True ($scannerSource -match
  "\`$collectStress = \(Test-LevelCollectsSection -Section 'benchmark'\) -or \`$Benchmark\.IsPresent") `
  '-Benchmark ajoute la section sans changer de profil'

# L'en-tete annonce si la machine va etre chargee. Il doit lire la MEME valeur
# que la collecte : deux lectures separees de la regle finiraient par diverger,
# et la premiere a diverger serait celle qui l'annonce.
Assert-Equal 1 ([regex]::Matches($scannerSource, '\$collectStress = ')).Count `
  'la decision du banc d''essai n''est prise qu''une fois'
Assert-True ($scannerSource -match "(?s)\`$collectStress = .*?Mode         : ") `
  'et elle precede l''en-tete qui l''annonce'

# Le rappel, et les trois situations qui valent un silence.
Assert-True ($scannerSource -match 'Aucune mesure de performances dans cet audit') `
  'un audit sans mesure le dit'
Assert-True ($scannerSource -match
  "-not \`$collectStress -and \`$level -ne 'quick' -and \`$Skip -notcontains 'benchmark'") `
  'un banc d''essai qui a tourne, un audit rapide et une section ecartee n''ont rien a se voir rappeler'

# Les variables PowerShell sont insensibles a la casse : `$benchmark` designe le
# parametre `-Benchmark`. Lui affecter la table de la section faisait echouer le
# script sur « Impossible de convertir Hashtable en SwitchParameter », APRES la
# collecte — donc apres avoir charge la machine pour rien.
#
# Le defaut n'est sorti qu'a l'execution reelle contre le vrai Windows. Ce
# controle garde la porte fermee : aucune affectation ne doit plus viser un nom
# que le bloc `param()` a deja pris.
$switchNames = [regex]::Matches($scannerSource, '\[switch\]\$(?<nom>\w+)') |
  ForEach-Object { $_.Groups['nom'].Value }
$assignedNames = [regex]::Matches($scannerSource, '(?m)^\$(?<nom>\w+) = ') |
  ForEach-Object { $_.Groups['nom'].Value }
$collisions = @($assignedNames | Where-Object { $switchNames -contains $_ })

Assert-True ($switchNames.Count -gt 0) 'les commutateurs du bloc param() sont bien reperes'
Assert-Equal 0 $collisions.Count `
  'aucune variable du script ne porte le nom d''un commutateur'

# --- Bilan ------------------------------------------------------------------
#
# Ce bloc doit rester **le dernier du fichier**, et c'est une lecon payee : il
# etait la fin de la premiere version de cette suite, et chaque section ajoutee
# depuis s'est ecrite en dessous de lui. Quatre cent quatre-vingts lignes de
# tests se sont ainsi retrouvees apres le seul endroit qui compte les echecs :
# elles s'executaient, affichaient leurs ECHEC en rouge, et le script sortait
# malgre tout en 0 sur un « tests reussis » — la barre de progression, les
# codes de sortie, le transport et le decompte des collecteurs compris.
#
# Un test ajoute apres cette ligne ne fait donc pas echouer la suite. Il n'y a
# rien a ajouter ici : les nouvelles sections vont au-dessus.

Write-Host ''
if ($script:Failed -gt 0) {
  Write-Host ([string]$script:Failed + ' test(s) en echec, ' + [string]$script:Passed + ' reussi(s).') -ForegroundColor Red
  exit 1
}

Write-Host ([string]$script:Passed + ' tests reussis.') -ForegroundColor Green
