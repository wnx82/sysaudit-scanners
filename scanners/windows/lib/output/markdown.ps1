# SysAudit Windows — resume Markdown.
#
# Volontairement minimal : le rendu complet — constats, scores, remediations —
# est produit par `@sysaudit/report-renderer` sur une machine qui dispose de
# Node.js. Ce fichier existe pour qu'un scan reste lisible sans rien installer.
#
# Toute valeur vient du rapport : rien n'est deduit, rien n'est complete.

function Format-ReportValue {
  param($Value)

  if ($null -eq $Value) { return 'non collecte' }

  if ($Value -is [hashtable] -and $Value.ContainsKey('unknown')) {
    $labels = @{
      UNKNOWN = 'non determine'
      NOT_AVAILABLE = 'non disponible'
      UNSUPPORTED = 'sans objet'
      PERMISSION_DENIED = 'acces refuse'
    }
    $label = if ($labels.ContainsKey([string]$Value.reason)) { $labels[[string]$Value.reason] } else { [string]$Value.reason }
    if ($Value.ContainsKey('detail') -and -not [string]::IsNullOrWhiteSpace([string]$Value.detail)) {
      return ($label + ' — ' + [string]$Value.detail)
    }
    return $label
  }

  return [string]$Value
}

function Get-ReportMarkdown {
  param([Parameter(Mandatory = $true)]$Report)

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('# Rapport SysAudit — ' + (Format-ReportValue $Report.system.hostname))
  $lines.Add('')
  $lines.Add('**' + (Format-ReportValue $Report.os.name) + ' ' + (Format-ReportValue $Report.os.version) + '**')
  $lines.Add('')
  $lines.Add('Genere le ' + [string]$Report.report.generatedAt + ' — profil ' + [string]$Report.report.profile + '.')
  $lines.Add('')
  $lines.Add('## Machine')
  $lines.Add('')
  $lines.Add('| Element | Valeur |')
  $lines.Add('| --- | --- |')
  $lines.Add('| Constructeur | ' + (Format-ReportValue $Report.system.manufacturer) + ' |')
  $lines.Add('| Modele | ' + (Format-ReportValue $Report.system.model) + ' |')
  $lines.Add('| Architecture | ' + (Format-ReportValue $Report.system.architecture) + ' |')
  $lines.Add('| Noyau | ' + (Format-ReportValue $Report.os.kernel) + ' |')
  $lines.Add('| Scan privilegie | ' + [string]$Report.capabilities.privileged + ' |')
  $lines.Add('')

  $issues = @($Report.collection.issues)
  $lines.Add('## Collecte')
  $lines.Add('')
  if ($issues.Count -eq 0) {
    $lines.Add('Aucun probleme rencontre.')
  } else {
    # Les problemes sont rapportes avant les donnees : un rapport partiel doit
    # dire ce qui lui manque, pas se presenter comme complet.
    foreach ($issue in $issues) {
      $lines.Add('- **' + [string]$issue.section + '** (' + [string]$issue.severity + ') : ' + [string]$issue.message)
    }
  }
  $lines.Add('')

  $skipped = @($Report.collection.skippedSections)
  if ($skipped.Count -gt 0) {
    $lines.Add('Sections non collectees : ' + ($skipped -join ', ') + '.')
    $lines.Add('')
  }

  $lines.Add('---')
  $lines.Add('')
  $lines.Add('Schema ' + [string]$Report.schemaVersion + ' — scanner ' + [string]$Report.scannerVersion + '.')
  $lines.Add('')
  $lines.Add('Le rapport complet — constats, scores et remediations — se produit avec')
  $lines.Add('`npx sysaudit-render <rapport>.json`.')

  return ($lines -join "`n")
}
