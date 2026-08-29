<#
.SYNOPSIS
  Niveaux de diagnostic : quelle section, a quelle profondeur.

.DESCRIPTION
  Copie embarquee de `packages/platform/src/diagnostic-levels.ts`, plafonds
  Windows appliques. Elle est recopiee et non lue : le scanner doit tourner sur
  une machine sans Node.js. `diagnostic-levels-contract.test.ts` echoue si les
  deux divergent.

  Cette table est la table **Windows**, pas la table de reference : elle porte
  deja les plafonds declares dans `SCANNER_SECTION_CAPS.windows`. Un `skipped`
  ici ne signifie donc pas « ce niveau ne le prevoit pas » mais, parfois, « ce
  scanner ne sait pas encore le faire ». La difference est ecrite dans
  `docs/produit/DIAGNOSTIC-LEVELS.md`, et le rapport la dit section par section.

  Colonnes : section, puis la profondeur pour quick, standard, full et stress.
  Profondeurs : skipped < summary < standard < extended.
#>

$script:LevelMatrix = @'
system         standard standard standard standard
os             standard standard standard standard
motherboard    standard standard standard standard
bios           standard standard standard standard
cpus           summary  standard standard standard
memory         summary  standard standard standard
gpus           summary  standard standard standard
audio          summary  summary  summary  summary
sensors        standard standard extended extended
power          standard standard standard standard
storage        summary  standard standard standard
network        summary  summary  summary  summary
devices        skipped  summary  summary  summary
drivers        skipped  summary  summary  summary
software       skipped  standard standard standard
startup        skipped  summary  summary  summary
security       summary  summary  summary  summary
virtualization summary  standard standard standard
stability      summary  standard standard standard
boot           standard standard standard standard
shutdown       standard standard standard standard
events         skipped  standard standard standard
benchmark      skipped  skipped  skipped  summary
'@

$script:LevelLabels = @{
  quick = 'Rapide'
  standard = 'Normale'
  full = 'Complete'
  stress = 'Poussee'
}

$script:DepthRanks = @{
  skipped = 0
  summary = 1
  standard = 2
  extended = 3
}

<#
.SYNOPSIS
  Niveau effectif du scan, alias historiques resolus.
.DESCRIPTION
  `security` a ete un profil a part entiere ; il ne collectait rien de plus que
  `quick`. Le resoudre ici evite d'avoir a le tester partout ailleurs.
#>
function Get-CurrentLevel {
  param([string]$ScanProfile = $script:ScanProfile)

  switch ($ScanProfile) {
    'quick' { return 'quick' }
    'security' { return 'quick' }
    'full' { return 'full' }
    'stress' { return 'stress' }
    default { return 'standard' }
  }
}

function Get-LevelLabel {
  param([string]$Level)
  if ($script:LevelLabels.ContainsKey($Level)) { return $script:LevelLabels[$Level] }
  return $Level
}

<#
.SYNOPSIS
  Profondeur prevue pour une section.
.DESCRIPTION
  Une section absente de la table rend `standard` : une section non declaree
  est collectee, jamais silencieusement ignoree.
#>
function Get-LevelDepth {
  param([string]$Section, [string]$Level = '')

  if ([string]::IsNullOrWhiteSpace($Level)) { $Level = Get-CurrentLevel }

  $column = switch ($Level) {
    'quick' { 1 }
    'full' { 3 }
    'stress' { 4 }
    default { 2 }
  }

  foreach ($line in ($script:LevelMatrix -split "`n")) {
    $cells = $line.Trim() -split '\s+'
    if ($cells.Count -lt 5) { continue }
    if ($cells[0] -ne $Section) { continue }
    return $cells[$column]
  }
  return 'standard'
}

<#
.SYNOPSIS
  Sections ecartees a la demande, via -Skip.
.DESCRIPTION
  Elles se comportent exactement comme une section absente du niveau : rien
  n'est collecte, et l'absence est declaree dans `collection.skippedSections`
  plutot que tue. C'est la difference entre « nous n'avons pas regarde » et
  « il n'y avait rien » — que le produit n'a jamais le droit de confondre.
#>
$script:SkipSections = @()

function Set-SkippedSectionList {
  param([string[]]$Sections)
  $script:SkipSections = @($Sections)
}

function Test-SectionExcluded {
  param([string]$Section)
  return $script:SkipSections -contains $Section
}

<#
.SYNOPSIS
  Cette section existe-t-elle dans la table ?
.DESCRIPTION
  Sert a refuser une exclusion portant sur un nom qui n'existe pas : une faute
  de frappe doit couter un message d'erreur, pas une section silencieusement
  collectee quand meme.
#>
function Test-KnownSection {
  param([string]$Section)

  foreach ($line in ($script:LevelMatrix -split "`n")) {
    $cells = $line.Trim() -split '\s+'
    if ($cells.Count -lt 5) { continue }
    if ($cells[0] -eq $Section) { return $true }
  }
  return $false
}

function Get-SectionList {
  $sections = @()
  foreach ($line in ($script:LevelMatrix -split "`n")) {
    $cells = $line.Trim() -split '\s+'
    if ($cells.Count -lt 5) { continue }
    $sections += $cells[0]
  }
  return $sections
}

function Test-LevelCollectsSection {
  param([string]$Section)
  if (Test-SectionExcluded -Section $Section) { return $false }
  return (Get-LevelDepth -Section $Section) -ne 'skipped'
}

<#
.SYNOPSIS
  La profondeur courante atteint-elle au moins celle demandee ?
#>
function Test-DepthAtLeast {
  param([string]$Section, [string]$Wanted)

  $have = Get-LevelDepth -Section $Section
  return $script:DepthRanks[$have] -ge $script:DepthRanks[$Wanted]
}

<#
.SYNOPSIS
  Sections que ce scanner collecte au niveau courant.
#>
function Get-SectionsForLevel {
  $sections = @()
  foreach ($line in ($script:LevelMatrix -split "`n")) {
    $cells = $line.Trim() -split '\s+'
    if ($cells.Count -lt 5) { continue }
    if ((Get-LevelDepth -Section $cells[0]) -eq 'skipped') { continue }
    if (Test-SectionExcluded -Section $cells[0]) { continue }
    $sections += $cells[0]
  }
  return $sections
}

<#
.SYNOPSIS
  Premier niveau ou ce scanner collecte cette section, ou chaine vide.
#>
function Get-FirstLevelCollecting {
  param([string]$Section)

  foreach ($level in @('quick', 'standard', 'full', 'stress')) {
    if ((Get-LevelDepth -Section $Section -Level $level) -ne 'skipped') { return $level }
  }
  return ''
}

<#
.SYNOPSIS
  Declare une section non collectee, en distinguant les deux motifs possibles.
.DESCRIPTION
  Une section peut manquer parce que le niveau ne la prevoit pas — relancer a
  un niveau superieur suffit — ou parce que ce scanner ne sait pas encore la
  produire, quel que soit le niveau. Les confondre ferait relancer un audit de
  45 minutes pour obtenir une section qui n'arrivera pas.
#>
function Add-LevelSkip {
  param([string]$Section, [string]$Needed = '')

  # Une section ecartee a la demande n'a pas la meme raison d'etre absente
  # qu'une section hors niveau. Lui coller « relancer au niveau Complete »
  # enverrait l'utilisateur refaire un audit plus long pour obtenir une donnee
  # que lui seul a decide de ne pas collecter.
  # L'appelant a deja ajoute la section a `skippedSections` : ce qui se decide
  # ici est le **motif**, et lui seul.
  if (Test-SectionExcluded -Section ($Section -split '\.')[0]) {
    Add-CollectionIssue -Section $Section -Severity 'warning' `
      -Message 'Ecartee par -Skip : le collecteur n''a pas ete execute.' -Reason 'NOT_REQUESTED'
    return
  }

  if ([string]::IsNullOrWhiteSpace($Needed)) {
    $Needed = Get-FirstLevelCollecting -Section ($Section -split '\.')[0]
  }

  $current = Get-LevelLabel -Level (Get-CurrentLevel)
  if ([string]::IsNullOrWhiteSpace($Needed)) {
    Add-CollectionIssue -Section $Section -Severity 'warning' `
      -Message ('Non collectee par le scanner Windows, quel que soit le niveau.') -Reason 'UNSUPPORTED'
  } else {
    Add-CollectionIssue -Section $Section -Severity 'warning' `
      -Message ('Non collectee au niveau ' + $current + ' : relancer au niveau ' + (Get-LevelLabel -Level $Needed) + '.') -Reason 'NOT_COLLECTED'
  }
}
