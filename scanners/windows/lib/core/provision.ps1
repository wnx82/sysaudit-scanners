<#
.SYNOPSIS
  Inventaire des outils de collecte. Sous Windows, il n'installe rien.

.DESCRIPTION
  Pendant Windows de `lib/core/provision.sh`, moins le gestionnaire de paquets —
  et ce n'est pas un manque, c'est le constat.

  **Aucun collecteur Windows ne depend d'un outil tiers.** Les seize entrees de
  `capabilities.tools` sont des commandes PowerShell, des modules livres avec le
  systeme ou des interfaces CIM/WMI : `Get-StorageReliabilityCounter` pour la
  sante disque, `Get-MpComputerStatus` pour l'antivirus, `Get-BitLockerVolume`
  pour le chiffrement, `winsat` pour les mesures. Aucune n'a de paquet dans
  `packages/platform/src/tool-dependencies.ts`, parce qu'aucune ne s'installe :
  elle est la, ou la fonctionnalite Windows correspondante est absente de cette
  edition — ce qu'aucun `winget install` ne corrige.

  L'ADR 0008 autorise WinGet ; il ne l'impose pas. Ecrire ici un chemin
  d'installation qui n'aurait jamais rien a installer produirait du code mort
  sur le chemin le plus sensible du scanner, celui qui modifie la machine.

  Ce module se limite donc a ce qui apporte quelque chose : dire, dans le
  rapport, quels outils etaient presents avant l'audit. La question de
  l'installation recoit `NOT_OFFERED` — elle n'a pas ete posee, et sous Windows
  elle n'a pas lieu d'etre.

  `used` n'est **pas** emis. Le scanner Linux le deduit parce que toutes ses
  commandes externes passent par un point unique ; PowerShell appelle ses
  cmdlets directement, depuis chaque collecteur. Emettre `used = false` ferait
  passer pour inutile un outil dont on ignore simplement s'il a servi.
#>

<#
.SYNOPSIS
  Inventaire des outils, a partir de la table de capacites deja calculee.

.DESCRIPTION
  Prend `capabilities.tools` telle quelle plutot que de tenir une seconde
  liste : deux listes finiraient par diverger, et la divergence se lirait comme
  une contradiction du rapport.

.PARAMETER Tools
  Table de hachage `nom -> present`, celle de `capabilities.tools`.
#>
function Get-DependencyInventory {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable] $Tools
  )

  $records = @()
  foreach ($name in ($Tools.Keys | Sort-Object)) {
    # `PRESENT_BEFORE` est exact et porte sa consequence : ces outils
    # appartiennent au systeme, donc rien ne peut les retirer. `NOT_OFFERED`
    # dit qu'aucune installation n'a ete proposee — et non qu'elle a ete
    # refusee, ce que `DECLINED` signifierait.
    $outcome = if ($Tools[$name]) { 'PRESENT_BEFORE' } else { 'NOT_OFFERED' }
    $records += @{
      tool    = [string]$name
      outcome = $outcome
      removal = 'NOT_APPLICABLE'
    }
  }

  # Les enregistrements partent tels quels, deroules par le pipeline : c'est
  # l'appelant qui les remet en tableau avec `@()`, comme il le fait deja pour
  # `collection.issues`. La virgule unaire, ici, faisait l'inverse de ce qu'elle
  # promet : entourer d'un `@()` une fonction qui renvoie `, $liste` rend un
  # tableau **contenant** la liste. L'API refusait alors le rapport entier sur
  # `$.collection.dependencies.0` — « expected object, received array ».
  #
  # `Get-InterfaceAddressList` et `Get-BatteryReportList` gardent la virgule
  # parce que leurs appelants, eux, n'ecrivent pas `@()`. Les deux conventions
  # sont valides ; c'est de les cumuler que le tableau se dedouble.
  return $records
}
