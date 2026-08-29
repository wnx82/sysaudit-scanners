# SysAudit Windows — presentation console.
#
# Meme grammaire visuelle que le scanner Linux : logo dimensionne au terminal,
# quatre etats, barre de progression alimentee par les vraies etapes, resume
# final et QR Code recu de l'API.
#
# Trois regles, identiques a celles du scanner Linux :
#
# - rien n'est ecrit sur la machine auditee ;
# - rien n'est invente : une valeur absente disparait du resume plutot que
#   d'etre remplacee par un tiret qui se lirait comme « aucun » ;
# - la progression suit les vraies etapes, sans temporisation decorative.

# quiet < normal < verbose
$script:Verbosity = 'normal'

function Set-ConsoleVerbosity {
  param([ValidateSet('quiet', 'normal', 'verbose')][string]$Level)
  $script:Verbosity = $Level
}

function Test-ConsoleQuiet { return $script:Verbosity -eq 'quiet' }

<#
.SYNOPSIS
  Largeur utilisable du terminal.
.DESCRIPTION
  `$Host.UI.RawUI` n'est pas disponible dans toutes les hotes — tache
  planifiee, sortie redirigee, ISE. La valeur de repli evite un calcul de barre
  fonde sur zero colonne.
#>
function Get-ConsoleWidth {
  try {
    $width = $Host.UI.RawUI.WindowSize.Width
    if ($width -ge 20) { return [int]$width }
  } catch {
    # Hote sans interface : la largeur par defaut fera l'affaire. Le detail
    # n'a d'interet qu'en diagnostic, et n'a rien a faire dans un rapport.
    Write-Verbose ('Largeur de console non lisible : ' + $_.Exception.Message)
  }
  return 80
}

function Test-ConsoleInteractive {
  # Une sortie redirigee ne doit recevoir ni barre ni retour chariot : un
  # journal rempli de `\r` est illisible.
  return -not [Console]::IsOutputRedirected
}

function Test-ConsoleColor {
  if ($env:NO_COLOR) { return $false }
  return (Test-ConsoleInteractive)
}

# --- Capacites du terminal : sequences VT et jeu de caracteres ---------------
#
# `Write-Host -ForegroundColor` passe par l'API de l'hote, pas par des
# sequences d'echappement : elle colore aussi bien la console classique de
# Windows 7 que Windows Terminal. C'est pour cela que `Test-ConsoleColor`
# suffit partout, et qu'elle n'a pas a se soucier du VT.
#
# Deux choses, elles, ne passent pas par l'hote et cassent sur une console
# ancienne :
#
# - **les sequences VT brutes.** Le QR Code renvoye par l'API arrive deja
#   encode en ANSI. Une console sans traitement VT ne les interprete pas : elle
#   les **imprime**, et l'ecran se remplit de `<-[48;5;231m` sur toute la
#   surface du dessin. Ce n'est pas une degradation, c'est du bruit.
# - **les caracteres hors du jeu de la console.** Le logo est dessine en blocs
#   Unicode. Une console reglee sur une page de codes OEM les remplace par des
#   `?`, et le logo devient une bouillie de points d'interrogation sur huit
#   lignes.
#
# Les deux decisions sont donc prises par des fonctions **pures**, alimentees
# ensuite par l'environnement reel. C'est ce qui rend le cas Windows 7
# verifiable depuis n'importe quelle machine : le rendu final demande toujours
# un Windows 7, mais la regle qui choisit le repli, elle, se teste ici.

<#
.SYNOPSIS
  La cible interprete-t-elle les sequences VT ? Fonction pure.

.DESCRIPTION
  Le traitement VT est apparu dans la console de Windows 10 1511. Sur tout ce
  qui precede — Windows 7 en tete — les sequences sont recopiees telles quelles.

  Quatre emetteurs annoncent leur support par une variable d'environnement, et
  ils sont crus : Windows Terminal (`WT_SESSION`), ConEmu (`ConEmuANSI`), un
  terminal tiers (`TERM_PROGRAM`) et ANSICON, qui installe justement le
  traitement manquant sur une console ancienne. Un hote non-Windows n'a jamais
  eu le probleme.

  **Le doute conclut a l'absence.** Une version de systeme illisible rend
  `$false` : perdre la couleur d'un QR Code sur une machine moderne coute un
  dessin en noir et blanc, alors que l'inverse remplit l'ecran de sequences
  imprimees sur la machine qu'on cherche justement a servir.
#>
function Resolve-ConsoleVirtualTerminalSupport {
  param(
    [bool]$OnWindows = $true,
    $OsVersion = $null,
    [hashtable]$Environment = @{}
  )

  if (-not $OnWindows) { return $true }

  foreach ($name in @('WT_SESSION', 'ANSICON', 'ConEmuANSI', 'TERM_PROGRAM')) {
    if (-not $Environment.ContainsKey($name)) { continue }
    $value = [string]$Environment[$name]
    if ([string]::IsNullOrWhiteSpace($value)) { continue }
    # `ConEmuANSI` vaut `OFF` quand l'utilisateur a desactive le traitement :
    # la variable est presente et dit precisement le contraire.
    if ($name -eq 'ConEmuANSI' -and $value -ne 'ON') { continue }
    return $true
  }

  $parsed = $OsVersion -as [version]
  if ($null -eq $parsed) { return $false }

  if ($parsed.Major -gt 10) { return $true }
  if ($parsed.Major -lt 10) { return $false }
  # Windows 10 : le traitement VT arrive avec la build 10586 (1511).
  return $parsed.Build -ge 10586
}

<#
.SYNOPSIS
  L'encodage de sortie sait-il rendre ce texte ? Fonction pure.

.DESCRIPTION
  La question n'est pas « la console est-elle en UTF-8 » mais « ces
  caracteres-la survivent-ils a cet encodage ». Une liste de pages de codes
  autorisees se serait trompee dans les deux sens : CP437 rend `█` et pas `▗`,
  CP932 l'inverse pour `·`.

  **La question est posee a un encodeur strict, et c'est tout l'interet de
  cette fonction.** L'encodeur par defaut de .NET applique un *best-fit* : sur
  CP1252, il change `▄▀█` en `_¯¦` — trois caracteres bien reels, aucun `?`, et
  un logo qui se lit `___¯¯¯¦¦¦`. Chercher des `?` dans un aller-retour aurait
  donc declare ce cas lisible, ce qu'il n'est pas. `ExceptionFallback` retire le
  *best-fit* : un caractere absent de la page de codes leve, au lieu d'etre
  remplace par une ressemblance.

  Le repli sur l'encodeur recu couvre le cas d'une page de codes que
  `GetEncoding` ne sait pas reconstruire. Il conclut alors a l'absence : mieux
  vaut un nom en clair qu'un logo dont on ne sait rien.
#>
function Test-EncodingRendersText {
  param(
    $Encoding,
    [string]$Text
  )

  if ($null -eq $Encoding) { return $false }
  if ([string]::IsNullOrEmpty($Text)) { return $true }

  $strict = $null
  try {
    $strict = [Text.Encoding]::GetEncoding(
      $Encoding.CodePage,
      [Text.EncoderFallback]::ExceptionFallback,
      [Text.DecoderFallback]::ExceptionFallback
    )
  } catch {
    Write-Verbose ('Page de codes non reconstructible : ' + $_.Exception.Message)
    return $false
  }

  try {
    [void]$strict.GetBytes($Text)
  } catch {
    # Le cas nominal du repli : un caractere que la console ne sait pas ecrire.
    Write-Verbose ('Caractere hors de la page de codes de la console : ' + $_.Exception.Message)
    return $false
  }

  return $true
}

<#
.SYNOPSIS
  La console de cette machine peut-elle afficher ce texte ?

.DESCRIPTION
  L'epreuve porte sur le texte **reellement destine a l'ecran**, jamais sur un
  echantillon choisi a la main : un sondage forfaitaire se serait trompe des la
  premiere retouche du dessin, et il aurait deja degrade trop. La console CP437
  de Windows 7 sait afficher `▄`, `▀` et `█` — donc le grand logo — et ignore
  les quadrants du petit. Les rejeter ensemble aurait prive Windows 7 d'un logo
  qu'il savait dessiner.
#>
function Test-ConsoleRendersText {
  param([string]$Text)

  try {
    $encoding = [Console]::OutputEncoding
  } catch {
    # Hote sans console attachee : le repli ASCII est le choix sur.
    Write-Verbose ('Encodage de sortie non lisible : ' + $_.Exception.Message)
    return $false
  }

  return (Test-EncodingRendersText -Encoding $encoding -Text $Text)
}

<#
.SYNOPSIS
  Les sequences VT sont-elles interpretables ici ?
#>
function Test-ConsoleVirtualTerminal {
  if (-not (Test-ConsoleInteractive)) { return $false }

  $environment = @{}
  foreach ($name in @('WT_SESSION', 'ANSICON', 'ConEmuANSI', 'TERM_PROGRAM')) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if (-not [string]::IsNullOrWhiteSpace($value)) { $environment[$name] = $value }
  }

  # `$IsWindows` n'existe pas en PowerShell 5.1 — donc pas sur Windows 7, ou la
  # question se pose. Son absence **est** la reponse : cet hote est Windows.
  $onWindows = $true
  $flag = Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue
  if ($null -ne $flag) { $onWindows = [bool]$flag.Value }

  $version = $null
  try {
    $version = [Environment]::OSVersion.Version
  } catch {
    Write-Verbose ('Version du systeme non lisible : ' + $_.Exception.Message)
  }

  return (Resolve-ConsoleVirtualTerminalSupport -OnWindows $onWindows -OsVersion $version -Environment $environment)
}

<#
.SYNOPSIS
  La console peut-elle dessiner ce logo ?

.DESCRIPTION
  Le texte eprouve est le dessin lui-meme, aplati. Deriver l'epreuve de la
  donnee plutot que de la recopier a la main est ce qui empeche la verification
  de mentir apres une retouche du dessin.
#>
function Test-ConsoleArt {
  param($Art)

  if ($null -eq $Art) { return $false }

  $flat = New-Object System.Text.StringBuilder
  foreach ($line in $Art) {
    foreach ($half in $line) { [void]$flat.Append([string]$half) }
  }

  return (Test-ConsoleRendersText -Text $flat.ToString())
}

# --- Logo -------------------------------------------------------------------
#
# Dessins issus des polices figlet « Mono 12 » et « Small Mono 9 », figés ici :
# le scanner ne dépend d'aucun générateur à l'exécution.
#
# Chaque ligne est coupée en deux — « Sys » puis « Audit » — pour que les deux
# moitiés reçoivent des teintes distinctes, comme dans le nom.

$script:LogoLarge = @(
    @('  ▄▄▄▄', '                           ▄▄                     ▄▄     ██'),
    @('▄█▀▀▀▀█', '                         ████                    ██     ▀▀       ██'),
    @('██▄       ▀██  ███  ▄▄█████▄', '    ████    ██    ██   ▄███▄██   ████     ███████'),
    @(' ▀████▄    ██▄ ██   ██▄▄▄▄ ▀', '   ██  ██   ██    ██  ██▀  ▀██     ██       ██'),
    @('     ▀██    ████▀    ▀▀▀▀██▄', '   ██████   ██    ██  ██    ██     ██       ██'),
    @('█▄▄▄▄▄█▀     ███    █▄▄▄▄▄██', '  ▄██  ██▄  ██▄▄▄███  ▀██▄▄███  ▄▄▄██▄▄▄    ██▄▄▄'),
    @(' ▀▀▀▀▀       ██      ▀▀▀▀▀▀', '   ▀▀    ▀▀   ▀▀▀▀ ▀▀    ▀▀▀ ▀▀  ▀▀▀▀▀▀▀▀     ▀▀▀▀'),
    @('           ███', '')
)

$script:LogoSmall = @(
    @(' ▗▄▖           ', '  ▄          ▗▖  █'),
    @('▗▛▀▜           ', ' ▐█▌         ▐▌  ▀   ▐▌'),
    @('▐▙   ▝█ █▌▗▟██▖', ' ▐█▌ ▐▌ ▐▌ ▟█▟▌ ██  ▐███'),
    @(' ▜█▙  █▖█ ▐▙▄▖▘', ' █ █ ▐▌ ▐▌▐▛ ▜▌  █   ▐▌'),
    @('   ▜▌ ▐█▛  ▀▀█▖', ' ███ ▐▌ ▐▌▐▌ ▐▌  █   ▐▌'),
    @('▐▄▄▟▘  █▌ ▐▄▄▟▌', '▗█ █▖▐▙▄█▌▝█▄█▌▗▄█▄▖ ▐▙▄'),
    @(' ▀▀▘   █   ▀▀▀ ', '▝▘ ▝▘ ▀▀▝▘ ▝▀▝▘▝▀▀▀▘  ▀▀'),
    @('      █▌', '')
)

function Write-ConsoleLogo {
  if (Test-ConsoleQuiet) { return }

  $width = Get-ConsoleWidth
  $color = Test-ConsoleColor

  # Trois tailles, choisies d'après la largeur réelle. Un logo qui déborde est
  # pire qu'une absence de logo : il casse toutes les lignes suivantes.
  #
  # Une quatrième condition s'ajoute à la largeur : la console doit savoir
  # écrire le dessin. Chaque taille est éprouvée avec **ses** caractères, et
  # une console CP437 garde donc le grand logo — `▄`, `▀` et `█` lui sont
  # connus — tout en retombant sur le nom en clair pour le petit, dont les
  # quadrants ne le sont pas.
  $art = $null
  if ($width -ge 80 -and (Test-ConsoleArt -Art $script:LogoLarge)) {
    $art = $script:LogoLarge
  } elseif ($width -ge 42 -and (Test-ConsoleArt -Art $script:LogoSmall)) {
    $art = $script:LogoSmall
  }

  Write-Host ''
  if ($null -eq $art) {
    if ($color) { Write-Host 'SysAudit' -ForegroundColor Cyan } else { Write-Host 'SysAudit' }
  } else {
    foreach ($line in $art) {
      if ($color) {
        Write-Host $line[0] -ForegroundColor Cyan -NoNewline
        Write-Host $line[1] -ForegroundColor Blue
      } else {
        Write-Host ($line[0] + $line[1])
      }
    }
  }

  # La version accompagne le logo : elle répond à « qu'est-ce qui tourne » sans
  # qu'on ait à la chercher, et c'est la première question d'un rapport de bug.
  # `·` survit à CP437, CP850 et CP1252 — il manque en revanche aux pages
  # de codes à double octet, celles d'un Windows 7 japonais ou coréen. Sans ce
  # repli la ligne s'y affichait « v1.2.3 ? schema 0.68.0 », et un point
  # d'interrogation au milieu d'une version se lit comme un doute sur la
  # version.
  $separator = if (Test-ConsoleRendersText -Text '·') { '·' } else { '-' }
  $legend = '  scanner Windows v{0} {1} schema {2}' -f $script:SCANNER_VERSION, $separator, $script:SCHEMA_VERSION
  if ($color) { Write-Host $legend -ForegroundColor DarkGray } else { Write-Host $legend }
  Write-Host ''
}

function Write-ConsoleSession {
  param([string]$Text)
  if (Test-ConsoleQuiet) { return }
  Write-Host ('  ' + $Text)
}

# --- Etats ------------------------------------------------------------------

function Write-ConsoleState {
  param(
    [ValidateSet('run', 'ok', 'warn', 'error')][string]$Kind,
    [string]$Message
  )

  if ((Test-ConsoleQuiet) -and $Kind -ne 'error') { return }

  $markers = @{ run = '[>]'; ok = '[OK]'; warn = '[!]'; error = '[ERROR]' }
  $colors = @{ run = 'Cyan'; ok = 'Green'; warn = 'Yellow'; error = 'Red' }

  if (Test-ConsoleColor) {
    Write-Host ('  ' + $markers[$Kind] + ' ') -ForegroundColor $colors[$Kind] -NoNewline
    Write-Host $Message
  } else {
    Write-Host ('  ' + $markers[$Kind] + ' ' + $Message)
  }
}

# --- Progression ------------------------------------------------------------

$script:ProgressTotal = 0
$script:ProgressDone = 0
$script:ProgressLabel = ''

function Start-ConsoleProgress {
  param([int]$Total)
  $script:ProgressTotal = $Total
  $script:ProgressDone = 0
}

function Test-ConsoleProgressBar {
  return (Test-ConsoleInteractive) -and $script:ProgressTotal -gt 0 -and $script:Verbosity -eq 'normal'
}

function Write-ConsoleProgressStep {
  param([string]$Label)
  $script:ProgressLabel = $Label
  if (Test-ConsoleQuiet) { return }

  if (Test-ConsoleProgressBar) { Write-ConsoleProgressBar } else { Write-ConsoleState -Kind run -Message $Label }
}

function Complete-ConsoleProgressStep {
  $script:ProgressDone++
  if (Test-ConsoleQuiet) { return }

  if (Test-ConsoleProgressBar) { Write-ConsoleProgressBar } else { Write-ConsoleState -Kind ok -Message $script:ProgressLabel }
}

<#
.SYNOPSIS
  Ligne de progression, rendue sans rien ecrire.

.DESCRIPTION
  Le pourcentage est **borne a 100**, comme cote Linux (`progress_render`).
  Ce n'est pas une precaution decorative : une etape de plus que prevu donnait
  une barre plus large que la barre, donc un `'.' * (-1)` que PowerShell refuse
  par une `ArgumentOutOfRangeException`. Levee depuis `Invoke-Collector`, elle
  interrompait **l'audit entier** au dernier collecteur — toute la collecte
  perdue pour une decoration. Un decompte faux doit rester un affichage faux.
#>
function Get-ConsoleProgressLine {
  $percent = 0
  if ($script:ProgressTotal -gt 0) {
    $percent = [int](($script:ProgressDone * 100) / $script:ProgressTotal)
  }
  if ($percent -gt 100) { $percent = 100 }
  if ($percent -lt 0) { $percent = 0 }

  $barWidth = [Math]::Max(10, [Math]::Min(40, (Get-ConsoleWidth) - 24))
  $filled = [Math]::Max(0, [Math]::Min($barWidth, [int](($percent * $barWidth) / 100)))
  $bar = ('#' * $filled) + ('.' * ($barWidth - $filled))

  return ('  [{0}] {1,3}%  {2}' -f $bar, $percent, $script:ProgressLabel)
}

function Write-ConsoleProgressBar {
  # Retour chariot sans saut de ligne : la barre se reecrit sur place. Cette
  # fonction n'est jamais appelee hors terminal.
  Write-Host ("`r" + (Get-ConsoleProgressLine).PadRight((Get-ConsoleWidth) - 1)) -NoNewline
}

<#
.SYNOPSIS
  Une ligne d'information, ecrite **au-dessus** de la barre de progression.

.DESCRIPTION
  Un collecteur qui prend plusieurs minutes doit pouvoir le dire. Sans cette
  fonction, son message s'accolait a la barre — celle-ci se terminant par un
  retour chariot sans saut de ligne — et l'affichage devenait illisible au
  moment precis ou il devait rassurer.

  La barre est donc effacee, le message ecrit, la barre redessinee : les
  messages defilent, la barre reste en bas.
#>
function Write-ConsoleStep {
  param([string]$Message)

  if (Test-ConsoleQuiet) { return }

  if (Test-ConsoleProgressBar) {
    Write-Host ("`r" + (' ' * ((Get-ConsoleWidth) - 1)) + "`r") -NoNewline
    Write-ConsoleState -Kind run -Message $Message
    Write-ConsoleProgressBar
    return
  }

  Write-ConsoleState -Kind run -Message $Message
}

function Stop-ConsoleProgress {
  if (Test-ConsoleQuiet) { return }
  if (Test-ConsoleProgressBar) {
    Write-Host ("`r" + (' ' * ((Get-ConsoleWidth) - 1)) + "`r") -NoNewline
  }
}

# --- Resume -----------------------------------------------------------------

function Write-SummaryLine {
  param([string]$Label, $Value)

  # Un marqueur d'absence ou une valeur vide ne produit pas de ligne : afficher
  # un tiret se lirait comme « aucun ».
  if ($null -eq $Value) { return }
  if ($Value -is [hashtable] -and $Value.ContainsKey('unknown')) { return }

  $text = [string]$Value
  if ([string]::IsNullOrWhiteSpace($text)) { return }

  Write-Host ('  {0,-14} {1}' -f $Label, $text)
}

function Format-SummaryByteSize {
  param($Bytes)

  if ($null -eq $Bytes -or $Bytes -is [hashtable]) { return $null }
  $value = [double]$Bytes
  if ($value -le 0) { return $null }

  $units = @('o', 'Kio', 'Mio', 'Gio', 'Tio')
  $index = 0
  while ($value -ge 1024 -and $index -lt 4) {
    $value = $value / 1024
    $index++
  }
  if ($index -eq 0) { return ('{0:N0} {1}' -f $value, $units[$index]) }
  return ('{0:N1} {1}' -f $value, $units[$index])
}

<#
.SYNOPSIS
  Resume de fin d'audit, lu depuis le rapport reellement assemble.
#>
function Write-ConsoleSummary {
  param([Parameter(Mandatory = $true)]$Report)

  if (Test-ConsoleQuiet) { return }

  Write-Host ''
  Write-Host '  Resume' -ForegroundColor $(if (Test-ConsoleColor) { 'Cyan' } else { 'White' })

  Write-SummaryLine -Label 'Machine' -Value $Report.system.hostname

  $vendor = if ($Report.system.manufacturer -is [hashtable]) { $null } else { [string]$Report.system.manufacturer }
  $model = if ($Report.system.model -is [hashtable]) { $null } else { [string]$Report.system.model }
  Write-SummaryLine -Label 'Materiel' -Value (($vendor, $model | Where-Object { $_ }) -join ' ')

  $osName = if ($Report.os.name -is [hashtable]) { $null } else { [string]$Report.os.name }
  $osVersion = if ($Report.os.version -is [hashtable]) { $null } else { [string]$Report.os.version }
  Write-SummaryLine -Label 'Systeme' -Value (($osName, $osVersion | Where-Object { $_ }) -join ' ')

  Write-SummaryLine -Label 'Architecture' -Value $Report.system.architecture

  if ($Report.ContainsKey('cpus') -and @($Report.cpus).Count -gt 0) {
    Write-SummaryLine -Label 'Processeur' -Value @($Report.cpus)[0].model
  }
  if ($Report.ContainsKey('memory')) {
    Write-SummaryLine -Label 'Memoire' -Value (Format-SummaryByteSize $Report.memory.installedBytes)
  }
  if ($Report.ContainsKey('storage')) {
    $disks = @($Report.storage.disks).Count
    if ($disks -gt 0) { Write-SummaryLine -Label 'Stockage' -Value ("$disks disque(s)") }
  }
  if ($Report.ContainsKey('network')) {
    $interfaces = @($Report.network.interfaces).Count
    if ($interfaces -gt 0) { Write-SummaryLine -Label 'Reseau' -Value ("$interfaces interface(s)") }
  }

  $issues = @($Report.collection.issues).Count
  if ($issues -gt 0) {
    Write-ConsoleState -Kind warn -Message ("$issues information(s) non collectee(s), motif dans le rapport.")
  }
}

# --- QR Code ----------------------------------------------------------------

<#
.SYNOPSIS
  Affiche le QR Code renvoye par l'API, ou rien.

.DESCRIPTION
  Le dessin est fabrique cote serveur : encoder un QR en PowerShell demanderait
  une arithmetique de corps de Galois qu'aucun test de ce depot ne pourrait
  verifier. Son absence n'empeche rien — l'URL reste affichee.

  La variante coloree force un fond clair, seule facon qu'un QR reste lisible
  quel que soit le theme du terminal.

  **Elle exige un traitement VT, pas seulement de la couleur.** Le dessin
  `ansi` arrive du serveur avec ses sequences d'echappement deja ecrites : une
  console qui ne les interprete pas les imprime, et le QR se change en plusieurs
  centaines de lignes de `<-[48;5;231m`. La variante `plain`, elle, est coloree
  par l'hote — `Write-Host -BackgroundColor` — et fonctionne sur une console
  Windows 7 comme sur un terminal moderne.
#>
function Write-ConsoleQrCode {
  param($Qr)

  if (Test-ConsoleQuiet) { return }
  if ($null -eq $Qr) { return }
  if (-not (Test-ConsoleInteractive)) { return }
  if ((Get-ConsoleWidth) -lt 40) { return }

  Write-Host ''
  if ((Test-ConsoleColor) -and (Test-ConsoleVirtualTerminal) -and $Qr.ansi) {
    Write-Host ([string]$Qr.ansi)
  } elseif ($Qr.plain) {
    foreach ($line in ([string]$Qr.plain -split "`n")) {
      Write-Host $line -ForegroundColor Black -BackgroundColor White
    }
  }
  Write-Host ''
}

# --- Ouverture du rapport ---------------------------------------------------

<#
.SYNOPSIS
  Ouvre le rapport dans le navigateur par defaut. Rend $true s'il a ete lance.

.DESCRIPTION
  Le QR Code s'adresse a un telephone, et l'adresse a qui veut la recopier.
  Reste le cas le plus frequent : l'utilisateur est devant la machine auditee,
  et veut simplement voir son rapport. C'est ce que fait cette fonction.

  Trois precautions, et aucune n'est decorative.

  **Le schema est verifie.** L'adresse vient de la reponse de l'API : c'est une
  donnee distante, au meme titre qu'un nom de disque lu dans un rapport.
  `Start-Process` lancerait aussi bien un executable local qu'une page web —
  seuls `http` et `https` sont ouverts.

  **L'ouverture passe par l'explorateur quand le scanner est eleve.** Un audit
  complet exige l'elevation, et `Start-Process <url>` depuis une console
  administrateur ouvre le navigateur AVEC ces droits — dans un profil qui n'est
  pas celui de l'utilisateur, et avec des privileges qu'un navigateur n'a aucune
  raison d'avoir. `explorer.exe` tourne, lui, sous la session ouverte : la page
  s'ouvre la ou l'utilisateur l'attend.

  **Un echec n'est pas une erreur d'audit.** Une machine sans session graphique
  n'a pas de navigateur a lancer ; l'adresse vient d'etre affichee, et elle reste
  le moyen d'y arriver. Rien n'est ecrit sur la machine dans un cas comme dans
  l'autre : ouvrir une page n'est pas une modification du systeme audite.
#>
function Open-ReportInBrowser {
  param([string]$Url, [switch]$Elevated)

  if ([string]::IsNullOrWhiteSpace($Url)) { return $false }

  # `-as [Uri]` rend $null sur une chaine inexploitable, et un URI **relatif**
  # sur `sysaudit-MSI.json` : interroger `.Scheme` avant `IsAbsoluteUri` levait.
  $uri = $Url -as [Uri]
  if ($null -eq $uri -or -not $uri.IsAbsoluteUri) { return $false }
  if (@('http', 'https') -notcontains $uri.Scheme) { return $false }

  try {
    if ($Elevated) {
      Start-Process 'explorer.exe' -ArgumentList $uri.AbsoluteUri
    } else {
      Start-Process $uri.AbsoluteUri
    }
    return $true
  } catch {
    # L'audit a reussi et l'adresse est affichee : l'echec d'ouverture se
    # raconte en diagnostic, pas en erreur.
    Write-Verbose ('Ouverture du navigateur impossible : ' + $_.Exception.Message)
    return $false
  }
}
