# SysAudit Windows — ou poser le rapport.
#
# Ce fichier existe a cause d'une seule ligne : le repertoire de sortie etait
# `(Get-Location).Path`. Une console ouverte depuis le menu Demarrer, un clic
# droit « Executer en tant qu'administrateur », un `powershell` lance depuis
# CMD : tous ont pour repertoire courant `C:\WINDOWS\system32`. Le rapport
# s'appelait alors `C:\WINDOWS\system32\sysaudit-LAPTOP-WNX.json` — au mieux
# introuvable pour qui doit le deposer, au pire ecrit dans un repertoire
# systeme par un processus eleve.
#
# La destination ne depend donc plus de la ou la commande a ete tapee. Elle est
# deduite de l'utilisateur, dans cet ordre :
#
#   1. son dossier Telechargements, tel que WINDOWS le declare — pas
#      `%USERPROFILE%\Downloads`, qui est faux des qu'il a ete deplace,
#      redirige ou repris par OneDrive ;
#   2. `%USERPROFILE%\Downloads`, s'il existe malgre tout ;
#   3. `%LOCALAPPDATA%\SysAudit\Reports` ;
#   4. `%TEMP%\SysAudit` ;
#   5. `%ProgramData%\SysAudit\Reports`, qui n'a de sens que pour un audit sans
#      utilisateur — une tache planifiee sous LE SYSTEME.
#
# Aucun repertoire systeme n'est jamais retenu, meme si Windows le designe :
# voir `Test-SysAuditSystemDirectory`. Un `-OutputPath` explicite, lui, passe
# devant tout ce qui precede — l'utilisateur a dit ou il voulait son fichier.

# FOLDERID_Downloads. Ce GUID est le nom de la valeur sous les deux cles
# ci-dessous : c'est lui, et non « Downloads », qui suit le dossier quand il
# demenage.
$script:SYSAUDIT_DOWNLOADS_FOLDER_ID = '{374DE290-123F-4565-9164-39C4925E467B}'

# `User Shell Folders` porte la valeur telle qu'elle a ete ecrite — souvent un
# REG_EXPAND_SZ (`%USERPROFILE%\Downloads`) ; `Shell Folders` en porte une copie
# deja developpee, que Windows rafraichit a l'ouverture de session. La premiere
# est la reference, la seconde le repli.
$script:SYSAUDIT_USER_SHELL_FOLDERS_KEY = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
$script:SYSAUDIT_SHELL_FOLDERS_KEY = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'
$script:SYSAUDIT_PROFILE_LIST_KEY = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'

# Comptes de service. Aucun n'a de bureau, donc aucun n'a de Telechargements :
# leur profil vit sous `C:\Windows\System32\config`, precisement la ou un
# rapport n'a rien a faire.
$script:SYSAUDIT_SERVICE_SIDS = @('S-1-5-18', 'S-1-5-19', 'S-1-5-20')

# --- Nom du fichier ---------------------------------------------------------

<#
.SYNOPSIS
  `sysaudit-<machine>.json`, avec un nom de machine utilisable comme nom de
  fichier.

.DESCRIPTION
  Un nom de machine peut contenir ce qu'un nom de fichier Windows refuse :
  `\ / : * ? " < > |`, et tout caractere de controle. Il est ramene a
  l'alphabet du scanner Linux — lettres, chiffres, point, tiret bas, tiret —
  pour que les deux scanners produisent le meme nom sur la meme machine.
#>
function Get-SysAuditReportFileName {
  param([string]$MachineName = '', [string]$Extension = '.json')

  # Le meme alphabet que le scanner Linux, a la lettre : les deux scanners
  # doivent produire le meme nom de fichier pour la meme machine.
  $clean = [string]$MachineName -replace '[^A-Za-z0-9._-]', '-'
  $clean = $clean -replace '-{2,}', '-'
  $clean = $clean.Trim('-')

  if ([string]::IsNullOrWhiteSpace($clean)) { $clean = 'machine' }

  return ('sysaudit-' + $clean + $Extension)
}

<#
.SYNOPSIS
  Assemble deux morceaux de chemin Windows.

.DESCRIPTION
  `Join-Path` passe par les lecteurs de PowerShell : sur l'agent Linux qui joue
  les tests, `C:\Users\wnx` n'existe pas comme lecteur et l'appel echoue. Cette
  fonction ne fait que du texte, et rend le meme resultat des deux cotes.
#>
function Join-SysAuditPath {
  param([string]$Parent = '', [string]$Child = '')

  if ([string]::IsNullOrWhiteSpace($Parent)) { return $Child }
  if ([string]::IsNullOrWhiteSpace($Child)) { return $Parent }

  return ($Parent.TrimEnd('\', '/') + '\' + $Child.TrimStart('\', '/'))
}

# --- Repertoires systeme ----------------------------------------------------

<#
.SYNOPSIS
  Forme comparable d'un chemin : separateurs uniformises, casse ecartee.

.DESCRIPTION
  Volontairement textuelle, sans `GetFullPath` : cette fonction doit rendre le
  meme verdict sur l'agent Linux qui execute les tests et sur la machine
  auditee, et `GetFullPath` ne voit pas de separateur dans un `\` sous Linux.
#>
function Get-SysAuditComparablePath {
  param([string]$Path = '')

  if ([string]::IsNullOrWhiteSpace($Path)) { return '' }

  $normalized = $Path.Trim().Replace('/', '\')

  # Le double antislash d'un chemin UNC est conserve : `\\serveur\partage` est
  # une racine, pas une redondance. Un dossier Telechargements redirige vers un
  # partage en porte un.
  $prefix = ''
  if ($normalized.StartsWith('\\')) {
    $prefix = '\\'
    $normalized = $normalized.Substring(2)
  }

  while ($normalized.Contains('\\')) { $normalized = $normalized.Replace('\\', '\') }
  $normalized = ($prefix + $normalized).TrimEnd('\')

  return $normalized.ToLowerInvariant()
}

<#
.SYNOPSIS
  Repertoires ou un rapport ne doit jamais atterrir.

.DESCRIPTION
  Lus dans l'environnement plutot qu'ecrits en dur : `C:\Windows` n'est pas
  `C:\Windows` partout, et un chemin code en clair serait faux sur une
  installation deplacee tout en donnant l'illusion de proteger.
#>
function Get-SysAuditSystemDirectoryRoots {
  # `ProgramFiles(x86)` porte des parentheses : seule la forme delimitee de
  # `$env:` les accepte, et cette forme est indiscernable d'une interpolation
  # TypeScript recopiee par erreur — ce qu'un test de syntaxe surveille dans
  # tous les fichiers du scanner. L'appel .NET dit la meme chose sans
  # l'ambiguite.
  $roots = @()
  foreach ($value in @(
      $env:SystemRoot,
      $env:windir,
      $env:ProgramFiles,
      [System.Environment]::GetEnvironmentVariable('ProgramFiles(x86)'),
      $env:ProgramW6432
    )) {
    if (-not [string]::IsNullOrWhiteSpace($value)) { $roots += $value }
  }
  return $roots
}

<#
.SYNOPSIS
  Le chemin est-il dans un repertoire systeme ?

.DESCRIPTION
  La comparaison porte sur le chemin **et ses descendants** : le defaut a
  corriger n'ecrivait pas dans `C:\Windows`, il ecrivait dans
  `C:\Windows\System32`. Le profil du compte SYSTEME
  (`...\System32\config\systemprofile`) tombe sous la meme regle, ce qui est
  voulu : une tache planifiee n'a pas a semer des rapports dans le systeme.
#>
function Test-SysAuditSystemDirectory {
  param([string]$Path = '', [string[]]$Roots = @())

  $candidate = Get-SysAuditComparablePath -Path $Path
  if ($candidate -eq '') { return $false }

  foreach ($root in $Roots) {
    $normalized = Get-SysAuditComparablePath -Path $root
    if ($normalized -eq '') { continue }
    if ($candidate -eq $normalized) { return $true }
    if ($candidate.StartsWith($normalized + '\')) { return $true }
  }

  # La racine d'un volume n'est pas un repertoire systeme au sens ci-dessus,
  # mais elle n'est pas davantage un endroit ou deposer un rapport.
  if ($candidate -match '^[a-z]:$') { return $true }

  return $false
}

# --- Ecriture possible ? ----------------------------------------------------

<#
.SYNOPSIS
  Le repertoire accepte-t-il une ecriture ?
.DESCRIPTION
  Teste en ecrivant reellement : les droits effectifs sous Windows dependent des
  ACL, de l'elevation et de la virtualisation de fichiers, qu'aucune lecture de
  metadonnees ne resume fidelement.
#>
function Test-WritableDirectory {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) { return $false }
  $probe = Join-Path $Path ('.sysaudit-' + [guid]::NewGuid().ToString('N') + '.tmp')
  try {
    [System.IO.File]::WriteAllText($probe, '')
    Remove-Item $probe -Force -ErrorAction SilentlyContinue
    return $true
  } catch {
    return $false
  }
}

<#
.SYNOPSIS
  Le repertoire est-il utilisable — quitte a le creer ?

.DESCRIPTION
  `-Create` distingue les deux familles de candidats. Un dossier
  Telechargements ABSENT ne se cree pas : son absence signifie que la
  redirection pointe ailleurs, vers un disque amovible ou un partage hors
  ligne, et le recreer y planterait un dossier vide sans rendre le rapport plus
  accessible. Un repertoire de secours, lui, n'existe que parce que SysAudit
  l'a cree.
#>
function Test-SysAuditReportDirectory {
  param([string]$Path = '', [switch]$Create)

  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

  if (-not (Test-Path -LiteralPath $Path)) {
    if (-not $Create) { return $false }
    try {
      New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
    } catch {
      return $false
    }
  }

  return (Test-WritableDirectory -Path $Path)
}

# --- Utilisateur reel -------------------------------------------------------

function Test-SysAuditServiceSid {
  param([string]$Sid = '')

  if ([string]::IsNullOrWhiteSpace($Sid)) { return $false }
  return ($script:SYSAUDIT_SERVICE_SIDS -contains $Sid.ToUpperInvariant())
}

<#
.SYNOPSIS
  SID du compte qui execute ce processus, ou une chaine vide.
#>
function Get-SysAuditCurrentUserSid {
  try {
    return [string][Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  } catch {
    # Hors Windows — les tests de fonctions pures tournent sur un agent Linux —
    # il n'y a pas d'identite Windows a lire.
    Write-Verbose ('Identite Windows illisible : ' + $_.Exception.Message)
    return ''
  }
}

<#
.SYNOPSIS
  SID du proprietaire d'un processus, ou une chaine vide.

.DESCRIPTION
  Deux formes d'objet, selon ce que la machine sait faire : une instance CIM
  n'expose pas ses methodes et passe par `Invoke-CimMethod`, un objet WMI —
  seule voie avant PowerShell 3.0 — les expose directement.
#>
function Get-SysAuditProcessOwnerSid {
  param($Process)

  if ($null -eq $Process) { return '' }

  $owner = $null
  try {
    if ($null -ne $Process.PSObject.Methods['GetOwnerSid']) {
      $owner = $Process.GetOwnerSid()
    } elseif (Test-LegacyCommand -Name 'Invoke-CimMethod') {
      $owner = Invoke-CimMethod -InputObject $Process -MethodName 'GetOwnerSid' -ErrorAction Stop
    }
  } catch {
    Write-Verbose ('Proprietaire de processus illisible : ' + $_.Exception.Message)
    return ''
  }

  if ($null -eq $owner) { return '' }
  if ($null -ne $owner.ReturnValue -and [int]$owner.ReturnValue -ne 0) { return '' }

  return [string]$owner.Sid
}

<#
.SYNOPSIS
  SID de l'utilisateur assis devant la machine, ou une chaine vide.

.DESCRIPTION
  Le processus courant ne le dit pas toujours. `runas /user:Admin`, un service,
  une tache planifiee sous LE SYSTEME : dans ces trois cas, le compte qui
  execute le scanner n'est pas celui qui a lance l'audit, et son
  `%USERPROFILE%` designe un profil que personne ne consulte — parfois
  `C:\Windows\System32\config\systemprofile`.
  (Une elevation UAC ordinaire, elle, conserve le compte : le SID est alors le
  meme des deux cotes, et cette fonction ne change rien.)

  `explorer.exe` est le repere : c'est le shell de la session interactive, il
  tourne sous l'utilisateur, et son absence signifie precisement qu'il n'y a
  personne — auquel cas on ne devine pas.

  La session est comparee a la notre en premier : sur un serveur a plusieurs
  bureaux ouverts, plusieurs `explorer.exe` coexistent, et seul celui de notre
  session repond a « qui a lance cette commande ».
#>
function Get-SysAuditInteractiveUserSid {
  $sessionId = -1
  try {
    $sessionId = [int](Get-Process -Id $PID -ErrorAction Stop).SessionId
  } catch {
    Write-Verbose ('Session du processus illisible : ' + $_.Exception.Message)
  }

  $processes = @()
  try {
    $processes = @(Get-LegacyWmiValue -AllowCim -AllowWmi `
        -Query "SELECT Handle, SessionId FROM Win32_Process WHERE Name = 'explorer.exe'")
  } catch {
    Write-Verbose ('Session interactive introuvable : ' + $_.Exception.Message)
    return ''
  }

  $ordered = @()
  $ordered += @($processes | Where-Object { $null -ne $_ -and [int]$_.SessionId -eq $sessionId })
  $ordered += @($processes | Where-Object { $null -ne $_ -and [int]$_.SessionId -ne $sessionId })

  foreach ($process in $ordered) {
    $sid = Get-SysAuditProcessOwnerSid -Process $process
    if ([string]::IsNullOrWhiteSpace($sid)) { continue }
    if (Test-SysAuditServiceSid -Sid $sid) { continue }
    return $sid
  }

  return ''
}

# --- Registre ---------------------------------------------------------------

<#
.SYNOPSIS
  Valeur brute d'une cle utilisateur, sans developper les variables.

.DESCRIPTION
  `-Sid` vide designe l'utilisateur courant (`HKCU`) ; sinon la ruche de
  l'utilisateur vise (`HKU\<sid>`), chargee tant qu'il a une session ouverte.

  Les variables ne sont **pas** developpees ici, et c'est le point : Windows
  ecrit `%USERPROFILE%\Downloads`, et developper cette variable avec notre
  environnement rendrait le profil de l'administrateur pour le dossier d'un
  autre utilisateur — l'erreur exacte que ce fichier existe pour eviter.
#>
function Get-SysAuditUserRegistryValue {
  param(
    [Parameter(Mandatory = $true)][string]$SubKey,
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Sid = ''
  )

  try {
    $root = if ([string]::IsNullOrWhiteSpace($Sid)) {
      [Microsoft.Win32.Registry]::CurrentUser
    } else {
      [Microsoft.Win32.Registry]::Users
    }
    $path = if ([string]::IsNullOrWhiteSpace($Sid)) { $SubKey } else { $Sid + '\' + $SubKey }

    $key = $root.OpenSubKey($path)
    if ($null -eq $key) { return '' }
    try {
      $value = $key.GetValue($Name, '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
      return [string]$value
    } finally {
      $key.Close()
    }
  } catch {
    Write-Verbose ('Lecture de registre impossible (' + $SubKey + '\' + $Name + ') : ' + $_.Exception.Message)
    return ''
  }
}

<#
.SYNOPSIS
  Developpe `%USERPROFILE%` avec le profil vise, puis les autres variables.

.DESCRIPTION
  L'ordre compte. `%USERPROFILE%` est traite a part parce que c'est la seule
  variable dont la valeur differe selon l'utilisateur dont on parle ; les
  autres (`%SystemDrive%`, `%OneDrive%`…) ne varient pas d'un compte a l'autre
  au point de tromper.
#>
function Expand-SysAuditUserPath {
  param([string]$Value = '', [string]$UserProfile = '')

  if ([string]::IsNullOrWhiteSpace($Value)) { return '' }

  $expanded = $Value
  if (-not [string]::IsNullOrWhiteSpace($UserProfile)) {
    $expanded = [System.Text.RegularExpressions.Regex]::Replace(
      $expanded, '%USERPROFILE%', $UserProfile.TrimEnd('\'),
      [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  }

  if ($expanded -match '%') {
    try {
      $expanded = [System.Environment]::ExpandEnvironmentVariables($expanded)
    } catch {
      Write-Verbose ('Variables non developpees dans ' + $Value + ' : ' + $_.Exception.Message)
    }
  }

  # Une variable inconnue reste telle quelle : un chemin qui contient encore un
  # `%` n'en est pas un, et le proposer comme destination reviendrait a creer un
  # repertoire nomme `%OneDrive%`.
  if ($expanded -match '%') { return '' }

  return $expanded
}

<#
.SYNOPSIS
  Chemin du profil d'un utilisateur, lu dans `ProfileList`.
#>
function Get-SysAuditUserProfilePath {
  param([string]$Sid = '')

  if ([string]::IsNullOrWhiteSpace($Sid)) { return '' }

  try {
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($script:SYSAUDIT_PROFILE_LIST_KEY + '\' + $Sid)
    if ($null -eq $key) { return '' }
    try {
      $value = [string]$key.GetValue('ProfileImagePath', '',
        [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    } finally {
      $key.Close()
    }
  } catch {
    Write-Verbose ('Profil introuvable pour ' + $Sid + ' : ' + $_.Exception.Message)
    return ''
  }

  return (Expand-SysAuditUserPath -Value $value)
}

<#
.SYNOPSIS
  Dossier Telechargements d'un utilisateur, ou une chaine vide.

.DESCRIPTION
  C'est la question a laquelle `"$env:USERPROFILE\Downloads"` repond mal : le
  dossier se deplace, se renomme, se redirige par strategie de groupe, et
  OneDrive le reprend a son compte. La valeur qui suit ces changements est
  celle du dossier connu FOLDERID_Downloads, dont ces deux cles de registre
  sont la source — celle-la meme que lit `SHGetKnownFolderPath`.
#>
function Get-SysAuditDownloadsFolder {
  param([string]$Sid = '', [string]$UserProfile = '')

  foreach ($subKey in @($script:SYSAUDIT_USER_SHELL_FOLDERS_KEY, $script:SYSAUDIT_SHELL_FOLDERS_KEY)) {
    $raw = Get-SysAuditUserRegistryValue -SubKey $subKey -Name $script:SYSAUDIT_DOWNLOADS_FOLDER_ID -Sid $Sid
    $expanded = Expand-SysAuditUserPath -Value $raw -UserProfile $UserProfile
    if (-not [string]::IsNullOrWhiteSpace($expanded)) { return $expanded }
  }

  return ''
}

# --- Choix du repertoire ----------------------------------------------------

<#
.SYNOPSIS
  Les destinations envisagees, dans l'ordre, avec leur libelle.

.DESCRIPTION
  Fonction pure : elle ne lit ni le registre ni le disque. Tout ce qu'elle sait
  de la machine lui est donne, ce qui rend l'ordre des replis verifiable sans
  Windows.
#>
function Get-SysAuditReportDirectoryCandidates {
  param(
    [string]$Downloads = '',
    [string]$UserProfile = '',
    [string]$LocalAppData = '',
    [string]$TempPath = '',
    [string]$ProgramData = ''
  )

  $candidates = @()

  if (-not [string]::IsNullOrWhiteSpace($Downloads)) {
    $candidates += @{ Path = $Downloads; Label = 'dossier Telechargements'; Create = $false }
  }
  if (-not [string]::IsNullOrWhiteSpace($UserProfile)) {
    $candidates += @{
      Path = (Join-SysAuditPath -Parent $UserProfile -Child 'Downloads')
      Label = 'dossier Telechargements du profil'
      Create = $false
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($LocalAppData)) {
    $candidates += @{
      Path = (Join-SysAuditPath -Parent $LocalAppData -Child 'SysAudit\Reports')
      Label = 'donnees locales de l''application'
      Create = $true
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($TempPath)) {
    $candidates += @{
      Path = (Join-SysAuditPath -Parent $TempPath -Child 'SysAudit')
      Label = 'repertoire temporaire'
      Create = $true
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($ProgramData)) {
    # Dernier recours, et seulement pour un audit sans utilisateur : une tache
    # planifiee sous LE SYSTEME n'a ni Telechargements ni temporaire hors du
    # systeme. Sans lui, il ne resterait que `C:\Windows\Temp`.
    $candidates += @{
      Path = (Join-SysAuditPath -Parent $ProgramData -Child 'SysAudit\Reports')
      Label = 'donnees communes de la machine'
      Create = $true
    }
  }

  return $candidates
}

<#
.SYNOPSIS
  Le premier candidat utilisable, et la raison du refus des precedents.

.DESCRIPTION
  `-Probe` est injectable pour que la chaine de replis se teste sans disque :
  il recoit le chemin et un booleen « creer si absent », et rend vrai si le
  repertoire est utilisable.

  Rend `@{ Path; Label; Rejections }`. `Path` vide signifie qu'aucune
  destination n'a ete trouvee — l'appelant doit alors le dire, pas ecrire
  ailleurs.
#>
function Select-SysAuditReportDirectory {
  param(
    [object[]]$Candidates = @(),
    [string[]]$SystemRoots = @(),
    [scriptblock]$Probe = $null
  )

  if ($null -eq $Probe) {
    $Probe = { param($Path, $Create) Test-SysAuditReportDirectory -Path $Path -Create:$Create }
  }

  $rejections = @()

  foreach ($candidate in $Candidates) {
    $path = [string]$candidate.Path
    $label = [string]$candidate.Label
    $create = [bool]$candidate.Create

    if (Test-SysAuditSystemDirectory -Path $path -Roots $SystemRoots) {
      $rejections += @{ Path = $path; Label = $label; Reason = 'repertoire systeme' }
      continue
    }

    if (& $Probe $path $create) {
      return @{ Path = $path; Label = $label; Rejections = $rejections }
    }

    $rejections += @{
      Path = $path
      Label = $label
      Reason = if ($create) { 'creation ou ecriture impossible' } else { 'absent ou non inscriptible' }
    }
  }

  return @{ Path = ''; Label = ''; Rejections = $rejections }
}

<#
.SYNOPSIS
  Le chemin est-il absolu, au sens de Windows ?

.DESCRIPTION
  Ecrite a la main plutot que confiee a `IsPathRooted` : celle-ci depend du
  systeme qui l'execute, et l'agent Linux qui joue les tests ne voit pas de
  racine dans `D:\Audits`.
#>
function Test-SysAuditRootedPath {
  param([string]$Path = '')

  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  return ($Path -match '^([A-Za-z]:[\\/]|[\\/])')
}

<#
.SYNOPSIS
  Ou ecrire le rapport, `-OutputPath` compris.

.DESCRIPTION
  Un chemin demande explicitement est respecte, y compris relatif — il est
  alors resolu depuis le repertoire courant, parce que c'est ce que veut dire
  `-OutputPath .\audit.json` tape dans une console. C'est le SEUL cas ou le
  repertoire courant intervient : sans demande explicite, la destination ne
  depend pas de la ou la commande a ete tapee.

  Rend `@{ Path; Directory; Label; Explicit; Rejections }`.
#>
function Resolve-SysAuditReportPath {
  param(
    [string]$Requested = '',
    [Parameter(Mandatory = $true)][string]$FileName,
    [string]$WorkingDirectory = '',
    [string]$Directory = ''
  )

  if (-not [string]::IsNullOrWhiteSpace($Requested)) {
    $path = $Requested
    if (-not (Test-SysAuditRootedPath -Path $Requested) -and
      -not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
      # `.\audit.json` designe le repertoire courant, que la jonction apporte
      # deja : le garder rendrait un `C:\...\.\audit.json` valide mais illisible
      # dans le message de fin.
      $relative = $Requested -replace '^\.[\\/]+', ''
      $path = Join-SysAuditPath -Parent $WorkingDirectory -Child $relative
    }
    return @{ Path = $path; Directory = ''; Label = ''; Explicit = $true; Rejections = @() }
  }

  return @{
    Path = (Join-SysAuditPath -Parent $Directory -Child $FileName)
    Directory = $Directory
    Label = ''
    Explicit = $false
    Rejections = @()
  }
}

<#
.SYNOPSIS
  Le repertoire de rapport de cette machine, pour cet utilisateur.

.DESCRIPTION
  Seul point de ce fichier qui interroge le systeme. Il assemble les trois
  questions traitees plus haut — qui est l'utilisateur reel, ou est son dossier
  Telechargements, quel repli tient — et rend `@{ Path; Label; Rejections }`.
#>
function Resolve-SysAuditReportDirectory {
  $userProfile = $env:USERPROFILE
  $localAppData = $env:LOCALAPPDATA
  $programData = $env:ProgramData

  $tempPath = ''
  try {
    $tempPath = [System.IO.Path]::GetTempPath()
  } catch {
    Write-Verbose ('Repertoire temporaire illisible : ' + $_.Exception.Message)
  }

  # L'utilisateur vise est celui de la session interactive des qu'il differe du
  # compte qui execute — `runas`, service, tache planifiee. Une elevation UAC
  # ordinaire garde le meme compte, et cette branche ne s'applique pas.
  $sid = ''
  $current = Get-SysAuditCurrentUserSid
  $interactive = Get-SysAuditInteractiveUserSid
  if (-not [string]::IsNullOrWhiteSpace($interactive) -and $interactive -ne $current) {
    $interactiveProfile = Get-SysAuditUserProfilePath -Sid $interactive
    if (-not [string]::IsNullOrWhiteSpace($interactiveProfile)) {
      $sid = $interactive
      $userProfile = $interactiveProfile
      $localAppData = Join-SysAuditPath -Parent $interactiveProfile -Child 'AppData\Local'
    }
  }

  $downloads = Get-SysAuditDownloadsFolder -Sid $sid -UserProfile $userProfile

  $candidates = Get-SysAuditReportDirectoryCandidates `
    -Downloads $downloads `
    -UserProfile $userProfile `
    -LocalAppData $localAppData `
    -TempPath $tempPath `
    -ProgramData $programData

  return (Select-SysAuditReportDirectory -Candidates $candidates -SystemRoots (Get-SysAuditSystemDirectoryRoots))
}
