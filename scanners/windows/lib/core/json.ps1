# SysAudit Windows — valeurs et marqueurs d'absence.
#
# Une donnee non collectee porte un marqueur avec sa raison. Elle n'est jamais
# remplacee par une valeur nulle ou vide : un compteur non lu n'est pas un
# compteur a zero, et un champ absent ne dit pas qu'un composant l'est.

function New-Unknown {
  param(
    [string]$Reason,
    [string]$Detail
  )

  if ([string]::IsNullOrWhiteSpace($Detail)) {
    return @{ unknown = $true; reason = $Reason }
  }

  return @{ unknown = $true; reason = $Reason; detail = $Detail }
}

function Get-StringOrUnknown {
  param(
    $Value,
    [string]$Reason = 'UNKNOWN',
    [string]$Detail = ''
  )

  if ($null -eq $Value) { return (New-Unknown -Reason $Reason -Detail $Detail) }
  $Text = [string]$Value
  if ([string]::IsNullOrWhiteSpace($Text)) { return (New-Unknown -Reason $Reason -Detail $Detail) }
  $Text = $Text.Trim()
  if ($Text.Length -gt 256) { return $Text.Substring(0, 256) }
  return $Text
}

<#
.SYNOPSIS
  Valeur SMBIOS debarrassee des textes de fabrique.

.DESCRIPTION
  Les firmwares laissent des champs remplis d'un texte de gabarit -- « To Be
  Filled By O.E.M. », « Default string », « System Serial Number ». Ce ne sont
  pas des donnees : les publier ferait passer un champ jamais renseigne pour un
  numero de serie ou une etiquette d'inventaire.

  La liste est ici, et non recopiee dans chaque collecteur : le scanner Linux a
  la sienne (`clean_dmi_value`), et deux listes suffisent deja a diverger.
#>
function Get-MeaningfulSmbiosValue {
  param($Value)

  if ($null -eq $Value) { return '' }
  $text = ([string]$Value).Trim()
  $placeholders = @(
    'to be filled by o.e.m.', 'to be filled by o.e.m', 'to be filled by oem',
    'default string',
    'system manufacturer', 'system product name', 'system serial number',
    'system version', 'not specified', 'not available', 'unknown', 'none',
    'n/a', 'na', 'default', 'o.e.m.', 'oem', '0123456789', 'chassis manufacture',
    # Numeros de serie jamais programmes. Les deux barrettes de l'audit
    # `QJVJVFA6` portent `00000000` : huit zeros ne designent aucun module, et
    # deux composants qui les portent tous deux ne sont pas le meme.
    '00000000', '000000000000', 'null', 'invalid', 'not applicable', ''
  )
  if ($placeholders -contains $text.ToLowerInvariant()) { return '' }
  return $text
}

<#
.SYNOPSIS
  Chaine SMBIOS exploitable, ou un marqueur qui dit laquelle des deux causes.

.DESCRIPTION
  `Get-StringOrUnknown` ne distingue pas « le firmware n'a rien rendu » de « le
  firmware a rendu son texte de gabarit ». Les deux sortent differemment : la
  premiere est une absence de collecte, la seconde est une collecte reussie sur
  un champ que le fabricant n'a jamais rempli.

  L'audit `QJVJVFA6` illustre les deux : ses barrettes portent `Unknown` comme
  fabricant et `00000000` comme numero de serie, et l'interface les affichait
  tels quels. Un lecteur y voyait un scanner en echec, pas un firmware
  incomplet.

  Le detail est ecrit une seule fois, ici, et repris a l'identique par
  `meaningful()` cote TypeScript : deux formulations pour la meme cause
  obligeraient le lecteur a se demander si elles disent la meme chose.
#>
function Get-MeaningfulStringOrUnknown {
  param(
    $Value,
    [string]$Reason = 'UNKNOWN'
  )

  $texte = Get-MeaningfulSmbiosValue -Value $Value
  if ($texte -ne '') { return (Get-StringOrUnknown -Value $texte -Reason $Reason) }

  # Rien du tout : c'est une absence de collecte, avec le motif de l'appelant.
  if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
    return (New-Unknown -Reason $Reason)
  }

  return (New-Unknown -Reason 'UNKNOWN' -Detail 'placeholder constructeur non significatif')
}

<#
.SYNOPSIS
  Entier 64 bits tire d'une valeur quelconque, ou `$null`.

.DESCRIPTION
  Le pendant de `ConvertTo-CimDateTime` pour les nombres, et il existe pour la
  meme raison : un `[int64]$valeur` ecrit en dur **leve** des que la valeur n'est
  pas convertible, et l'exception ne remonte pas au champ fautif — elle remonte
  au collecteur, qui abandonne tout ce qu'il n'avait pas encore ecrit.

  Le cas nomme par la roadmap est `Unknown → System.Int64` : WMI et les applets
  de commande Storage rendent parfois la chaine `Unknown`, `N/A` ou une valeur
  vide la ou le schema attend un compteur. Un seul disque bavard suffisait alors
  a emporter l'inventaire des autres.

  Rend `$null` plutot que de lever : l'appelant decide du marqueur et de son
  motif. `$null` ne veut jamais dire zero.
#>
function ConvertTo-SafeInt64 {
  param($Value)

  if ($null -eq $Value) { return $null }

  # Deja un entier : rien a analyser.
  if ($Value -is [int64] -or $Value -is [int32] -or $Value -is [int16] -or $Value -is [byte]) {
    return [int64]$Value
  }
  if ($Value -is [uint64]) {
    # Au-dela de `[int64]::MaxValue`, la conversion leverait. Aucun compteur
    # materiel ne va la : la valeur est une sentinelle, pas une mesure.
    if ($Value -gt [uint64][int64]::MaxValue) { return $null }
    return [int64]$Value
  }
  if ($Value -is [uint32] -or $Value -is [uint16]) { return [int64]$Value }

  if ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]) {
    $number = [double]$Value
    if ([double]::IsNaN($number) -or [double]::IsInfinity($number)) { return $null }
    if ($number -gt [double][int64]::MaxValue -or $number -lt [double][int64]::MinValue) { return $null }
    return [int64][Math]::Round($number)
  }

  $text = ([string]$Value).Trim()
  if ([string]::IsNullOrWhiteSpace($text)) { return $null }

  # `TryParse` et non un `try { [int64]$text }` : la conversion PowerShell
  # accepte des formes qu'on ne veut pas ici — « 1e3 », « 0x10 » — et le
  # `InvariantCulture` evite qu'une virgule decimale francaise ne fasse passer
  # « 1,5 » pour quinze.
  $parsed = [int64]0
  if ([int64]::TryParse($text, [Globalization.NumberStyles]::Integer,
      [Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
    return $parsed
  }

  $asDouble = [double]0
  if ([double]::TryParse($text, [Globalization.NumberStyles]::Float,
      [Globalization.CultureInfo]::InvariantCulture, [ref]$asDouble)) {
    if ([double]::IsNaN($asDouble) -or [double]::IsInfinity($asDouble)) { return $null }
    if ($asDouble -gt [double][int64]::MaxValue -or $asDouble -lt [double][int64]::MinValue) { return $null }
    return [int64][Math]::Round($asDouble)
  }

  return $null
}

function Get-NumberOrUnknown {
  param(
    $Value,
    [string]$Reason = 'UNKNOWN',
    [string]$Detail = ''
  )

  if ($null -eq $Value) { return (New-Unknown -Reason $Reason -Detail $Detail) }
  try {
    return [double]$Value
  } catch {
    return (New-Unknown -Reason $Reason -Detail $Detail)
  }
}

function Get-PositiveIntOrUnknown {
  param(
    $Value,
    [string]$Reason = 'UNKNOWN',
    [string]$Detail = ''
  )

  if ($null -eq $Value) { return (New-Unknown -Reason $Reason -Detail $Detail) }

  $number = ConvertTo-SafeInt64 -Value $Value
  if ($null -eq $number) { return (New-Unknown -Reason $Reason -Detail $Detail) }

  # Une valeur negative n'est pas une mesure : la ramener a zero fabriquerait
  # un compteur nul la ou la lecture a echoue.
  if ($number -lt 0) {
    return (New-Unknown -Reason 'UNKNOWN' -Detail 'valeur negative rapportee par le systeme')
  }

  return $number
}

<#
.SYNOPSIS
  Date d'une propriete CIM, quelle que soit la forme sous laquelle elle arrive.

.DESCRIPTION
  Le parametre n'est **pas** type `[string]`, et c'est tout l'objet de cette
  fonction.

  `Get-CimInstance` convertit deja les proprietes `CIM_DATETIME` en `DateTime` —
  a la difference de `Get-WmiObject`, qui rendait la chaine brute
  `20260319000000.000000+000`. Un parametre `[string]` forcait donc PowerShell a
  reserialiser cet objet **selon la culture courante**, et le convertisseur
  recevait « jeudi 19 mars 2026 01:00:00 ». `ToDateTime` echouait, le repli sur
  huit chiffres aussi, et `bios.releaseDate` sortait en « date WMI invalide » sur
  toute machine ou la date etait pourtant parfaitement lisible. `DRV-006` —
  « BIOS ancien » — ne pouvait plus s'evaluer nulle part.

  Les trois formes sont donc acceptees explicitement : l'objet `DateTime` rendu
  par CIM, la chaine `CIM_DATETIME` des anciens chemins WMI, et une date ISO. Une
  quatrieme forme reste une absence — jamais une date inventee.
#>
function Convert-WmiDateOrUnknown {
  param(
    $Value
  )

  $parsed = ConvertTo-CimDateTime -Value $Value
  if ($null -eq $parsed) { return (New-Unknown -Reason 'UNKNOWN' -Detail 'date WMI invalide') }
  return $parsed.ToString('yyyy-MM-dd')
}

function Convert-WmiDateTimeOrUnknown {
  param(
    $Value
  )

  $parsed = ConvertTo-CimDateTime -Value $Value
  if ($null -eq $parsed) { return (New-Unknown -Reason 'UNKNOWN' -Detail 'datetime WMI invalide') }
  return $parsed.ToUniversalTime().ToString('o')
}

<#
.SYNOPSIS
  `DateTime` tire d'une valeur CIM, ou `$null`.

.DESCRIPTION
  Rend `$null` plutot que de lever : l'appelant decide du marqueur d'absence et
  de son libelle. Une valeur illisible ne devient jamais une date par defaut.
#>
function ConvertTo-CimDateTime {
  param(
    $Value
  )

  if ($null -eq $Value) { return $null }

  # Forme rendue par `Get-CimInstance` : la conversion a deja eu lieu.
  if ($Value -is [DateTime]) { return $Value }
  if ($Value -is [DateTimeOffset]) { return $Value.DateTime }

  $text = ([string]$Value).Trim()
  if ([string]::IsNullOrWhiteSpace($text)) { return $null }

  # Forme rendue par `Get-WmiObject` et par les chemins WMI historiques.
  try {
    return [Management.ManagementDateTimeConverter]::ToDateTime($text)
  } catch {
    Write-Debug ('Date CIM non convertie par ManagementDateTimeConverter : ' + $text)
  }

  # Repli sur les huit premiers chiffres — `20260319…` — puis sur une date ISO.
  #
  # `ParseExact` dans un `try` plutot que `TryParseExact` : PowerShell ne sait
  # pas choisir la surcharge a cinq arguments de `TryParseExact`, et echoue sur
  # « Cannot find an overload ». Le cout d'une exception est sans consequence ici,
  # le chemin nominal ne passant jamais par ce repli.
  if ($text -match '^(\d{4})(\d{2})(\d{2})') {
    try {
      return [DateTime]::ParseExact(($Matches[1] + $Matches[2] + $Matches[3]), 'yyyyMMdd',
        [Globalization.CultureInfo]::InvariantCulture)
    } catch {
      Write-Debug ('Date CIM non convertie par le repli a huit chiffres : ' + $text)
    }
  }

  try {
    return [DateTime]::Parse($text, [Globalization.CultureInfo]::InvariantCulture,
      [Globalization.DateTimeStyles]::RoundtripKind)
  } catch {
    Write-Debug ('Date CIM non convertie en ISO 8601 : ' + $text)
  }

  return $null
}
