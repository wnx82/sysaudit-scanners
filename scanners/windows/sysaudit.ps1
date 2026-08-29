<#
.SYNOPSIS
  Scanner SysAudit pour Windows — audit read-only.

.DESCRIPTION
  Produit un rapport JSON conforme au schema SysAudit versionne.

  Trois regles gouvernent ce scanner, comme son homologue Linux :

  - il ne modifie rien. Aucune ecriture systeme, aucun service touche, aucune
    configuration changee. Seul le profil `stress` sollicite volontairement la
    machine, et il faut le demander ;
  - il n'invente rien. Une donnee non collectee porte un marqueur avec sa
    raison. Un compteur non lu n'est pas un compteur a zero ;
  - l'echec d'un collecteur n'interrompt pas l'audit. Il devient un probleme
    rapporte dans `collection.issues` et une section absente.

  Il ne depend d'aucun paquet Node.js : il doit tourner sur une machine qui n'en
  a pas.

.PARAMETER ScanProfile
  quick, standard, full, stress ou security. S'ecrit `-Profile` en ligne de
  commande : c'est un alias, `$Profile` etant deja une variable automatique.

.PARAMETER ApiUrl
  Racine de l'API SysAudit, requise avec -Upload.

.PARAMETER Upload
  Envoie le rapport a l'API. Sans ce commutateur, rien ne quitte la machine.

.PARAMETER Public
  Publie l'audit dans la vitrine de l'instance. Il ne le rend pas lisible — il
  l'etait deja par son adresse des l'envoi — il le rend repertoriable, donc
  susceptible d'apparaitre dans la liste des diagnostics recents. Exige -Upload.

.PARAMETER Private
  Exige que l'audit reste prive, quel que soit le defaut de l'instance. Utile
  pour un audit de validation, de test ou d'exploitation depose sur une
  instance qui publie par defaut : sans en-tete, c'est ce defaut qui tranche, et
  ne rien dire n'est donc pas demander le prive. Exige -Upload, et s'exclut
  de -Public.

.PARAMETER OutputPath
  Fichier JSON a ecrire. Un chemin relatif est resolu depuis le repertoire
  courant : c'est ce que veut dire `-OutputPath .\audit.json`.

  Par defaut, `sysaudit-<machine>.json` dans le dossier Telechargements de
  l'utilisateur — celui que Windows declare, pas `%USERPROFILE%\Downloads`, qui
  est faux des qu'il a ete deplace, redirige ou repris par OneDrive. La
  destination ne depend JAMAIS du repertoire courant : une console ouverte
  depuis le menu Demarrer ecrivait sinon dans `C:\WINDOWS\system32`. Voir
  `lib/core/paths.ps1` pour la chaine de replis.

.PARAMETER SessionId
  Identifiant de session d'audit, fourni par le script d'amorcage.

.PARAMETER UploadToken
  Jeton d'upload a usage unique, fourni par le script d'amorcage.

.PARAMETER Skip
  Sections a ecarter de la collecte. L'absence est declaree dans
  `collection.skippedSections` avec son motif, jamais tue : un rapport qui
  tairait ce qu'on n'a pas regarde se lirait comme un rapport ou il n'y avait
  rien. Un nom inconnu est refuse plutot qu'ignore.

.PARAMETER Proxy
  Proxy a emprunter pour l'envoi, par exemple `http://proxy.exemple.local:8080`.
  Sans lui, SYSAUDIT_PROXY, HTTPS_PROXY et HTTP_PROXY sont lues dans cet ordre,
  puis le proxy systeme de Windows. Les identifiants de la session ouverte sont
  presentes au proxy lorsqu'il en demande — un proxy NTLM ou Kerberos repondait
  sinon 407, apres une collecte pourtant reussie. NO_PROXY n'est pas lue.

.PARAMETER Monitor
  Observe la machine pendant ce nombre de secondes et joint la serie temporelle
  au rapport. Un audit reste par defaut un instantane : l'observation rallonge
  le scan d'autant, donc elle se demande. Plafonnee a 3600 secondes, comme cote
  Linux.

.PARAMETER Benchmark
  Mesure les performances de la machine, quel que soit le profil demande.

  Le banc d'essai n'appartient qu'au profil `stress` (lib/core/levels.ps1), et
  jusqu'ici c'etait le SEUL moyen de l'obtenir sous Windows — la ou le scanner
  Linux offre `--benchmark` depuis longtemps. L'ecart se lisait dans le parc au
  2026-08-27 : 9 % des audits Windows portaient une mesure, contre 23 % des
  audits Linux, et les 36 audits `full` du parc n'en portaient aucune.

  Reclamer la mesure ne devrait pas obliger a basculer tout l'audit en profil
  poussee, qui collecte par ailleurs bien davantage et dure bien plus longtemps.
  Ce commutateur ajoute la seule section demandee, et rien d'autre.

  Il CHARGE la machine et ecrit un fichier temporaire, supprime apres la mesure :
  c'est pourquoi il se demande, ici comme sous Linux, et n'arrive jamais par
  defaut.

.PARAMETER NetworkTest
  Teste le reseau et sort, **sans rien collecter ni ecrire**. Verifie le DNS, la
  poignee de main TLS et la joignabilite de l'API, et nomme ce qui bloque quand
  quelque chose bloque. Exige -ApiUrl. Sort en **2** si l'envoi direct ne
  passerait pas : un ordonnanceur doit pouvoir lire le verdict sans analyser le
  texte. Voir « Codes de sortie » ci-dessous.

  La cible est `/api/health`, en lecture seule. `/api/audit/bootstrap/…` creerait
  une session en base, et un test de connectivite n'a pas a laisser de trace.

.NOTES
  Codes de sortie, identiques a ceux du scanner Linux :

    0  l'audit a ete produit, et transmis s'il devait l'etre ;
    1  l'audit n'a pas pu etre produit — usage incorrect, collecte impossible ;
    2  l'audit a ete produit, la transmission a echoue. Le rapport est sur le
       disque, et se depose a la main ou se renvoie plus tard.

  La distinction entre 1 et 2 est ce qui permet a une supervision de parc de ne
  pas confondre « machine non auditable » et « reseau ferme ».

.PARAMETER PublicIp
  **Exige** l'adresse publique (WAN) de la machine dans le rapport.

  Le releve a deja lieu par defaut des qu'une API est connue. Ce commutateur ne
  sert donc qu'a en faire une condition : sans -ApiUrl, le scanner refuse de
  demarrer au lieu de produire un rapport ou le champ manque.

  C'est la **seule** collecte qui emette un paquet vers l'exterieur : une
  adresse WAN n'existe nulle part sur le poste, seul un correspondant distant
  l'observe. Le correspondant est l'API du produit, jamais un service d'echo
  tiers.

  L'adresse est reservee au proprietaire de la machine a la lecture : un
  visiteur anonyme, un lien de partage public ou un export voient « information
  protegee », jamais la valeur.

.PARAMETER NoPublicIp
  Ne releve pas l'adresse publique, meme avec une -ApiUrl sous la main. Aucun
  paquet ne sort alors de la collecte.

.PARAMETER NoMarkdown
  N'ecrit pas le resume Markdown a cote du JSON.

.PARAMETER NoOpen
  N'ouvre pas le rapport dans le navigateur apres un envoi reussi.

  L'ouverture n'a lieu qu'apres un envoi **reussi**, et jamais sans -Upload :
  il n'y a alors aucune page a ouvrir. Une machine sans session graphique — un
  serveur, une tache planifiee — n'a rien a ouvrir non plus, et ce commutateur
  le dit une fois pour toutes.

.PARAMETER Quiet
  N'affiche que les erreurs. `-Verbose`, fourni par PowerShell, detaille chaque
  etape et desactive la barre de progression.
#>

[CmdletBinding()]
param(
  # `$Profile` est une variable automatique de PowerShell — le chemin du profil
  # de l'hote. Un parametre du meme nom l'ecrase le temps du script. L'alias
  # garde `-Profile` en ligne de commande, qui est l'interface documentee.
  [Alias('Profile')]
  [ValidateSet('quick', 'standard', 'full', 'stress', 'security')]
  [string]$ScanProfile = 'standard',
  [string]$ApiUrl = '',
  [switch]$Upload,
  [switch]$Public,
  [switch]$Private,
  [string]$OutputPath = '',
  [string]$SessionId = '',
  [string]$UploadToken = '',
  # Code de rattachement d'une machine a un compte. Il ne vaut qu'une fois, pour
  # une machine, pendant vingt-quatre heures, et n'entre jamais dans le rapport :
  # un rapport s'archive et se repartage, un code n'a rien a y faire.
  [string]$Claim = '',
  [string[]]$Skip = @(),
  # Proxy a emprunter pour l'envoi. Voir `Resolve-SysAuditProxyUrl` pour l'ordre
  # de decision : ce parametre l'emporte sur SYSAUDIT_PROXY, HTTPS_PROXY et
  # HTTP_PROXY, et son absence laisse le proxy systeme decider.
  [string]$Proxy = '',
  [ValidateRange(0, 3600)]
  [int]$Monitor = 0,
  # Banc d'essai hors profil poussee, symetrique de `--benchmark` sous Linux.
  # Voir le bloc d'aide : il charge la machine, donc il se demande.
  [switch]$Benchmark,
  # Diagnostic seul : il n'implique **pas** -Upload, et ne collecte rien. Un test
  # de connectivite qui lancerait un audit au passage obligerait a choisir entre
  # savoir et ne pas auditer.
  [switch]$NetworkTest,
  # Releve l'adresse publique (WAN) de la machine aupres de l'API.
  #
  # Le releve a lieu DES QU'UNE API EST CONNUE : un champ de diagnostic reseau
  # qu'il faut penser a reclamer manque le jour ou il servirait. -PublicIp
  # l'EXIGE — le scanner refuse alors de demarrer sans -ApiUrl, plutot que de
  # laisser decouvrir l'absence en lisant le rapport. -NoPublicIp le retire.
  #
  # Sans -ApiUrl, il n'y a personne a interroger et rien ne sort : une adresse
  # WAN n'existe nulle part sur le poste, seul un correspondant distant
  # l'observe. Un audit hors ligne reste donc hors ligne, sans reglage — et
  # surtout sans echouer pour un champ que personne n'a reclame.
  #
  # L'adresse relevee est reservee au proprietaire a la lecture du rapport.
  [switch]$PublicIp,
  [switch]$NoPublicIp,
  [switch]$NoMarkdown,
  [switch]$NoOpen,
  # Identite verifiable du scanner : version, chemin, empreinte de chaque
  # fichier, etat de signature. Purement informatif — voir plus bas.
  [switch]$Verify,
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

# Version du format de rapport. Elle existe **a six endroits** — ici, dans les
# quatre autres scanners et dans `packages/report-schema` — et un test de contrat
# echoue si l'un d'eux diverge.
$script:SCHEMA_VERSION = '1.33.0'

$scannerRoot = $PSScriptRoot
$script:SCANNER_VERSION = (Get-Content (Join-Path $scannerRoot 'VERSION') -Raw).Trim()

# Ordre de chargement identique a celui du MANIFEST : un test verifie que les
# deux listes coincident, faute de quoi l'amorcage telechargerait un fichier que
# le scanner ne charge pas — ou l'inverse.
. (Join-Path $scannerRoot 'lib/core/json.ps1')
. (Join-Path $scannerRoot 'lib/core/core.ps1')
. (Join-Path $scannerRoot 'lib/core/transport.ps1')
. (Join-Path $scannerRoot 'lib/core/legacy.ps1')
. (Join-Path $scannerRoot 'lib/core/paths.ps1')
. (Join-Path $scannerRoot 'lib/core/levels.ps1')
. (Join-Path $scannerRoot 'lib/core/provision.ps1')
. (Join-Path $scannerRoot 'lib/collectors/system.ps1')
. (Join-Path $scannerRoot 'lib/collectors/hardware.ps1')
. (Join-Path $scannerRoot 'lib/collectors/media.ps1')
. (Join-Path $scannerRoot 'lib/collectors/power.ps1')
. (Join-Path $scannerRoot 'lib/collectors/storage.ps1')
. (Join-Path $scannerRoot 'lib/collectors/network.ps1')
. (Join-Path $scannerRoot 'lib/collectors/security.ps1')
. (Join-Path $scannerRoot 'lib/collectors/devices.ps1')
. (Join-Path $scannerRoot 'lib/collectors/software.ps1')
. (Join-Path $scannerRoot 'lib/collectors/virtualization.ps1')
. (Join-Path $scannerRoot 'lib/collectors/events.ps1')
. (Join-Path $scannerRoot 'lib/collectors/benchmark.ps1')
. (Join-Path $scannerRoot 'lib/collectors/monitoring.ps1')
. (Join-Path $scannerRoot 'lib/output/console.ps1')
. (Join-Path $scannerRoot 'lib/output/markdown.ps1')

# --- Identite verifiable -----------------------------------------------------
#
# `-Verify` repond a une seule question : « qu'est-ce que je m'apprete a
# executer, exactement ? »
#
# Elle se pose quand un antivirus signale le scanner — Avast le classe
# regulierement IDP.Generic, une heuristique comportementale — et elle n'avait
# aucune reponse dans le produit. L'utilisateur devait relever les empreintes a
# la main, fichier par fichier.
#
# Ce que cette option NE fait pas, et ne fera jamais :
#
#   - elle ne touche a aucun antivirus ;
#   - elle n'ajoute aucune exclusion ;
#   - elle ne desactive aucune protection ;
#   - elle ne masque aucune execution.
#
# Elle affiche, et c'est tout. Une empreinte affichee ne prouve pas qu'un
# fichier est sain : elle prouve qu'il est *celui-la*, et permet de le comparer
# a ce que le depot publie. C'est la seule chose qu'un programme puisse dire de
# lui-meme sans se porter garant.
#
# Elle sort du script : rien n'est collecte, rien n'est envoye.
if ($Verify) {
  Write-Host ''
  Write-Host 'SysAudit — identite du scanner' -ForegroundColor Cyan
  Write-Host '------------------------------'
  Write-Host ('Scanner        : SysAudit Windows')
  Write-Host ('Version        : ' + $script:SCANNER_VERSION)
  Write-Host ('Format rapport : ' + $script:SCHEMA_VERSION)
  Write-Host ('Chemin         : ' + $scannerRoot)
  Write-Host ('PowerShell     : ' + $PSVersionTable.PSVersion + ' (' + $PSVersionTable.PSEdition + ')')
  Write-Host ''

  Write-Host 'Empreintes SHA-256' -ForegroundColor Cyan
  $manifestPath = Join-Path $scannerRoot 'MANIFEST'
  if (-not (Test-Path $manifestPath)) {
    # Le MANIFEST absent n'est pas un detail : sans lui, on ne sait pas quels
    # fichiers *devraient* etre la, et une empreinte calculee sur ce qui se
    # trouve dans le dossier ne prouverait rien.
    Write-Host '  MANIFEST introuvable : la liste des fichiers attendus est inconnue.' -ForegroundColor Yellow
  } else {
    foreach ($entry in (Get-Content $manifestPath)) {
      $relative = $entry.Trim()
      if ([string]::IsNullOrWhiteSpace($relative) -or $relative.StartsWith('#')) { continue }
      $file = Join-Path $scannerRoot $relative
      if (Test-Path $file) {
        $hash = (Get-FileHash -Path $file -Algorithm SHA256).Hash.ToLowerInvariant()
        Write-Host ('  ' + $hash + '  ' + $relative)
      } else {
        Write-Host ('  MANQUANT' + (' ' * 57) + $relative) -ForegroundColor Yellow
      }
    }
  }

  Write-Host ''
  Write-Host 'Signature Authenticode' -ForegroundColor Cyan
  # $PSCommandPath plutot qu'un chemin recompose : c'est le fichier reellement
  # en cours d'execution, et non celui qu'on suppose l'etre. Un chemin
  # reconstruit depuis $scannerRoot serait de plus lu par le test de contrat
  # comme un module charge par le scanner, ce qu'il n'est pas.
  try {
    $signature = Get-AuthenticodeSignature -FilePath $PSCommandPath -ErrorAction Stop
    Write-Host ('  Etat    : ' + $signature.Status)
    if ($null -ne $signature.SignerCertificate) {
      Write-Host ('  Signe par : ' + $signature.SignerCertificate.Subject)
      Write-Host ('  Empreinte : ' + $signature.SignerCertificate.Thumbprint)
    } else {
      # Dit en toutes lettres, sans le presenter comme un defaut : SysAudit ne
      # dispose pas de certificat de signature de code, et pretendre le
      # contraire serait exactement le genre d'affirmation qu'on refuse.
      Write-Host '  Non signe. SysAudit ne dispose pas de certificat de signature de code.'
      Write-Host '  Les empreintes ci-dessus sont donc la seule verification disponible.'
    }
  } catch {
    Write-Host ('  Non verifiable : ' + $_.Exception.Message) -ForegroundColor Yellow
  }

  Write-Host ''
  Write-Host 'Comparez ces empreintes a celles publiees par le depot :' -ForegroundColor Cyan
  Write-Host '  https://github.com/wnx82/sysaudit-scanners'
  Write-Host ''
  Write-Host 'Une empreinte identique prouve que ce fichier est celui du depot.'
  Write-Host 'Elle ne prouve pas qu il est sain : c est une question distincte.'
  Write-Host ''
  exit 0
}

# --- Test reseau -------------------------------------------------------------
#
# Traite **avant** toute collecte, et avant le controle d'elevation : diagnostiquer
# un pare-feu ne demande aucun privilege, et exiger une console administrateur
# pour repondre « le DNS ne resout pas » ferait renoncer ceux qui n'en ont pas.
#
# Il sort du script : rien n'est collecte, rien n'est ecrit, aucun rapport n'est
# produit.
if ($NetworkTest) {
  if ([string]::IsNullOrWhiteSpace($ApiUrl)) {
    throw '-NetworkTest exige -ApiUrl.'
  }

  # Meme reglage TLS que l'envoi, et pour la meme raison : sans lui, un hote qui
  # refuse TLS 1.1 et anterieur coupe la connexion avant toute reponse, et le
  # test conclurait « API injoignable » la ou l'envoi echouait sur le protocole.
  # Un diagnostic qui ne reproduit pas les conditions de l'envoi ne diagnostique
  # pas l'envoi.
  if ([int][Net.ServicePointManager]::SecurityProtocol -ne 0) {
    [Net.ServicePointManager]::SecurityProtocol =
      [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  }

  $testProxyUrl = Resolve-SysAuditProxyUrl `
    -Explicit $Proxy `
    -SysAuditProxy $env:SYSAUDIT_PROXY `
    -HttpsProxy $env:HTTPS_PROXY `
    -HttpProxy $env:HTTP_PROXY
  $null = Set-SysAuditProxy -ProxyUrl $testProxyUrl

  $declaredProxy = Get-SysAuditDeclaredProxy `
    -Explicit $Proxy `
    -SysAuditProxy $env:SYSAUDIT_PROXY `
    -HttpsProxy $env:HTTPS_PROXY `
    -HttpProxy $env:HTTP_PROXY

  if (Invoke-SysAuditNetworkTest -ApiUrl $ApiUrl -DeclaredProxy $declaredProxy) {
    exit $script:EXIT_OK
  }
  exit $script:EXIT_TRANSPORT_FAILED
}

# L'adresse publique se releve aupres de l'API : sans adresse, il n'y a personne
# a interroger. Le refus arrive ici, AVANT la collecte, et non au moment de
# sortir — decouvrir apres plusieurs minutes de scan que le champ manque
# obligerait a tout relancer. C'est aussi le raisonnement des trois controles de
# portee, juste en dessous.
#
# Il ne vise QUE la demande explicite. Le defaut, lui, se contente de ne rien
# relever : faire echouer un audit hors ligne pour un champ que personne n'a
# reclame serait refuser de faire le travail qu'on sait faire.
if ($PublicIp -and [string]::IsNullOrWhiteSpace($ApiUrl)) {
  throw '-PublicIp exige -ApiUrl : l''adresse publique se releve aupres de l''API.'
}

# --- Portee de publication : refusee ici, AVANT la collecte ------------------
#
# Ces trois controles vivaient cinq cents lignes plus bas, au moment de l'envoi,
# au motif qu'ils « n'ont rien a collecter ». C'etait vrai et sans consequence
# tant qu'on regardait le code ; mesure sur le vrai hote Windows le 2026-08-27,
# le scan complet se deroulait d'abord, et le refus tombait apres. Sous Linux,
# les memes contradictions sont refusees avant la premiere seconde de collecte.
#
# Deux scanners qui refusent le meme argument a deux moments differents, c'est
# une asymetrie que personne ne peut deviner depuis la ligne de commande.
if (-not $Upload -and $Public) {
  throw '-Public exige -Upload : on ne publie pas un rapport qu''on n''envoie pas.'
}

# Meme raison pour le prive : une portee decrit un envoi, pas un fichier local.
if (-not $Upload -and $Private) {
  throw '-Private exige -Upload : la portee decrit un envoi, pas un fichier local.'
}

# Les deux ensemble ne veulent rien dire, et en choisir un silencieusement
# serait choisir a la place de quelqu'un qui vient d'exprimer deux intentions
# contraires. Sur une portee de publication, ce n'est pas un risque a prendre.
if ($Public -and $Private) {
  throw '-Public et -Private s''excluent : choisissez la portee de cet envoi.'
}

# Un code de rattachement n'a de sens qu'avec un envoi : c'est l'envoi qui le
# presente a l'API. Il partageait le sort des trois controles ci-dessus — refuse
# apres le scan complet — et pour la meme raison apparente : il n'a rien a
# collecter. Ce n'est pas ce que coute un refus tardif : ce n'est pas la
# verification qui est chere, c'est le scan qu'on laisse tourner avant elle.
if (-not $Upload -and -not [string]::IsNullOrWhiteSpace($Claim)) {
  throw '-Claim exige -Upload : le code se presente au moment de l''envoi.'
}

# Trois etats, et non un drapeau : exige, refuse, ou « si on peut ».
$script:CollectPublicIp =
  (-not $NoPublicIp) -and (-not [string]::IsNullOrWhiteSpace($ApiUrl))

# TLS et proxy sont regles ICI quand l'adresse sera relevee, et non a l'envoi.
#
# L'envoi les regle bien plus bas, apres l'ecriture du rapport ; la collecte,
# elle, tourne avant. Un poste dont l'hote refuse TLS 1.1 et anterieur — une
# bonne part du parc sous Windows PowerShell 5.1 — verrait sa connexion coupee
# avant toute reponse HTTP, et le champ porterait « l'API n'a pas repondu » pour
# une raison qui n'a rien a voir avec l'API. Les deux reglages sont idempotents :
# l'envoi les repose sans dommage.
if ($script:CollectPublicIp) {
  if ([int][Net.ServicePointManager]::SecurityProtocol -ne 0) {
    [Net.ServicePointManager]::SecurityProtocol =
      [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  }
  $null = Set-SysAuditProxy -ProxyUrl (Resolve-SysAuditProxyUrl `
      -Explicit $Proxy `
      -SysAuditProxy $env:SYSAUDIT_PROXY `
      -HttpsProxy $env:HTTPS_PROXY `
      -HttpProxy $env:HTTP_PROXY)
}

# Chronometre monotone plutot qu'une difference de `Get-Date` : l'horloge murale
# peut sauter en cours d'audit, celui-ci non. Voir `Get-AuditDurationMs`.
$scanStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Niveau effectif du scan. `levels.ps1` le lit dans `$script:ScanProfile` : les
# fonctions de niveau sont ainsi utilisables depuis n'importe quel collecteur,
# sans passer le profil de main en main.
$script:ScanProfile = $ScanProfile
$level = Get-CurrentLevel

# Sections ecartees a la demande. Un nom inconnu est refuse plutot qu'ignore :
# accepter `-Skip storag` sans rien dire collecterait le stockage tout en
# laissant croire le contraire — la faute la plus couteuse que cette option
# puisse faire.
foreach ($requested in $Skip) {
  if (-not (Test-KnownSection -Section $requested)) {
    throw ('Section inconnue : ' + $requested + '. Sections valides : ' + ((Get-SectionList) -join ' '))
  }
}
Set-SkippedSectionList -Sections $Skip

# Le niveau Rapide se contente de ce qu'un utilisateur standard peut lire. Les
# autres exigent l'elevation pour ne pas produire un rapport majoritairement
# vide, ce qui se lirait comme une machine sans materiel.
$lightProfile = ($level -eq 'quick')

if (-not $lightProfile -and -not (Test-IsAdministrator)) {
  throw 'Ce profil demande des droits administrateur. Relancez PowerShell en tant qu''administrateur, ou utilisez -Profile quick.'
}

# `-Verbose` n'est pas declare : `[CmdletBinding()]` le fournit deja comme
# parametre commun, et le redeclarer ferait echouer la liaison des parametres.
# Sa presence se lit donc dans `$VerbosePreference`.
if ($Quiet) { Set-ConsoleVerbosity -Level 'quiet' }
elseif ($VerbosePreference -ne 'SilentlyContinue') { Set-ConsoleVerbosity -Level 'verbose' }

Write-ConsoleLogo
Write-ConsoleSession ('Niveau       : ' + (Get-LevelLabel -Level $level) + ' (' + $level + ')')
Write-ConsoleSession ('Privileges   : ' + $(if (Test-IsAdministrator) { 'administrateur' } else { 'utilisateur' }))
# Le banc d'essai vient du niveau, ou de -Benchmark qui le demande a lui seul.
#
# Decide ICI, avant l'en-tete, et pas seulement au moment de collecter : c'est
# cette valeur qui dit a l'utilisateur si sa machine va etre chargee. Deux
# lectures separees de la meme regle finiraient par diverger, et la premiere a
# diverger serait celle qui l'annonce.
$collectStress = (Test-LevelCollectsSection -Section 'benchmark') -or $Benchmark.IsPresent
# Le mode dependait du niveau et n'en tenait pas compte : l'en-tete annonçait
# « aucune ecriture » y compris au niveau Poussee, dont le banc d'essai ecrit un
# fichier temporaire pour mesurer le debit du stockage. Rien ne s'installe en
# revanche jamais sous Windows — aucun collecteur ne depend d'un outil tiers
# (lib/core/provision.ps1) — d'ou deux cas seulement, contre quatre sous Linux.
Write-ConsoleSession ('Mode         : ' + $(
    if ($collectStress) {
      'lecture seule, sauf le fichier temporaire du banc d''essai, supprime apres la mesure'
    } else {
      'lecture seule - aucune ecriture sur cette machine'
    }
  ))
Write-Host ''

if ($lightProfile -and -not (Test-IsAdministrator)) {
  Write-ConsoleState -Kind warn -Message 'Mode leger sans elevation : certaines donnees resteront non collectees.'
}

# Ce que ce niveau collecte est decide par la matrice de `lib/core/levels.ps1`,
# et par elle seule. Le scanner Windows regroupe plusieurs sections par
# collecteur : `hardware` produit cpus, memory et gpus, d'ou ces deux
# indicateurs plutot qu'un par section.
$collectHardware = Test-LevelCollectsSection -Section 'cpus'
$collectSensors = Test-LevelCollectsSection -Section 'sensors'
$collectStorage = Test-LevelCollectsSection -Section 'storage'
$collectAudio = Test-LevelCollectsSection -Section 'audio'
$collectStartup = Test-LevelCollectsSection -Section 'startup'
$collectSoftware = Test-LevelCollectsSection -Section 'software'
# `devices` et `drivers` sortent du meme collecteur : la table des pilotes signes
# sert a nommer le pilote de chaque peripherique, et l'interroger deux fois
# doublerait le cout de la section la plus lente du scan.
$collectDevices = Test-LevelCollectsSection -Section 'devices'
$collectVirtualization = Test-LevelCollectsSection -Section 'virtualization'
# `$collectStress` est decide plus haut, avec l'en-tete qui l'annonce.
$collectPower = Test-LevelCollectsSection -Section 'power'
$collectEvents = Test-LevelCollectsSection -Section 'events'
$collectStability = Test-LevelCollectsSection -Section 'stability'
$collectBoot = Test-LevelCollectsSection -Section 'boot'
$collectShutdown = Test-LevelCollectsSection -Section 'shutdown'

# L'observation dans la duree ne depend d'aucun niveau : elle se demande. Elle
# ne figure donc pas dans la matrice des niveaux, exactement comme cote Linux.
$collectMonitoring = ($Monitor -gt 0)

# Nombre de collecteurs reellement executes, deduit du meme branchement.
$plannedCollectors = 3 # system, security, network
if ($collectHardware) { $plannedCollectors += 1 }
if ($collectSensors) { $plannedCollectors += 1 }
if ($collectAudio) { $plannedCollectors += 1 }
if ($collectStorage) { $plannedCollectors += 1 }
if ($collectStartup) { $plannedCollectors += 1 }
if ($collectSoftware) { $plannedCollectors += 1 }
if ($collectDevices) { $plannedCollectors += 1 }
if ($collectVirtualization) { $plannedCollectors += 1 }
if ($collectStress) { $plannedCollectors += 1 }
if ($collectPower) { $plannedCollectors += 1 }
if ($collectEvents) { $plannedCollectors += 1 }
if ($collectStability) { $plannedCollectors += 1 }
if ($collectBoot) { $plannedCollectors += 1 }
if ($collectShutdown) { $plannedCollectors += 1 }
if ($collectMonitoring) { $plannedCollectors += 1 }
Start-ConsoleProgress -Total $plannedCollectors

# --- Collecte ---------------------------------------------------------------
#
# Chaque appel passe par Invoke-Collector : un collecteur qui echoue laisse une
# section absente et un probleme rapporte, jamais un audit interrompu.

$inventory = Invoke-Collector -Section 'system' -Label 'Systeme' -Body { Get-SystemInventory }
if ($null -eq $inventory) {
  # Sans identite de machine, le rapport ne serait rattachable a rien.
  throw 'La collecte systeme a echoue : aucun rapport exploitable ne peut etre produit.'
}

$security = Invoke-Collector -Section 'security' -Label 'Securite' -Body { Get-SecuritySection }
$hardware = $null
$audio = $null
$sensors = $null
$storage = $null
$startup = $null
if ($collectHardware) {
  $hardware = Invoke-Collector -Section 'hardware' -Label 'Processeur / memoire / GPU' -Body { Get-HardwareInventory }
}
if ($collectAudio) {
  $audio = Invoke-Collector -Section 'audio' -Label 'Audio' -Body { Get-AudioSection }
}
if ($collectStorage) {
  $storage = Invoke-Collector -Section 'storage' -Label 'Stockage' -Body { Get-StorageInventory }
}
# `sensors` passe **apres** `storage`, et cet ordre est un contrat.
#
# Le stockage releve la temperature de chaque disque en meme temps que ses
# compteurs de fiabilite, et la depose dans le journal thermique que ce
# collecteur ramasse. Remonter cette ligne ne casserait rien de visible : les
# temperatures de disques disparaitraient de la section capteurs, ce qui se
# lirait comme une machine qui ne les expose pas. L'ordre du rapport, lui, est
# fixe a l'assemblage.
if ($collectSensors) {
  $sensors = Invoke-Collector -Section 'sensors' -Label 'Capteurs' -Body { Get-SensorSection }
}
$network = Invoke-Collector -Section 'network' -Label 'Reseau' -Body {
  # Vide quand l'adresse ne doit pas etre relevee — sous -NoPublicIp, ou faute
  # d'API a interroger. Le collecteur n'emet alors aucun paquet.
  $publicIpApi = if ($script:CollectPublicIp) { $ApiUrl } else { '' }
  Get-NetworkInventory -PublicIpApiUrl $publicIpApi `
    -UserAgent ('SysAudit-Scanner/' + $script:SCANNER_VERSION)
}
if ($collectStartup) {
  $startup = Invoke-Collector -Section 'startup' -Label 'Demarrage' -Body { Get-StartupSection }
}

$software = $null
if ($collectSoftware) {
  $software = Invoke-Collector -Section 'software' -Label 'Logiciels' -Body { Get-SoftwareInventory }
}

$deviceInventory = $null
if ($collectDevices) {
  $deviceInventory = Invoke-Collector -Section 'devices' -Label 'Peripheriques' -Body { Get-DeviceInventory }
}

$virtualization = $null
if ($collectVirtualization) {
  $virtualization = Invoke-Collector -Section 'virtualization' -Label 'Virtualisation' -Body { Get-VirtualizationSection }
}

# `events` passe **avant** `stability` : le journal n'est parcouru qu'une fois,
# et les compteurs par categorie de `stability` relisent ce parcours. Inverser
# les deux lignes ne casserait rien de visible — les compteurs deviendraient
# simplement tous inconnus, ce qui se lirait comme une machine au journal
# illisible plutot que comme le bug que c'est.
$power = $null
if ($collectPower) {
  $power = Invoke-Collector -Section 'power' -Label 'Alimentation' -Body { Get-PowerSection }
}

$events = $null
if ($collectEvents) {
  $events = Invoke-Collector -Section 'events' -Label 'Historique des incidents' -Body { Get-EventsSection }
}

$stability = $null
if ($collectStability) {
  $stability = Invoke-Collector -Section 'stability' -Label 'Stabilite observee' -Body { Get-StabilitySection -Events $events }
}

$boot = $null
if ($collectBoot) {
  $boot = Invoke-Collector -Section 'boot' -Label 'Sequence de demarrage' -Body { Get-BootSection }
}

$shutdown = $null
if ($collectShutdown) {
  $shutdown = Invoke-Collector -Section 'shutdown' -Label 'Sequence d''arret' -Body { Get-ShutdownSection }
}

# `$benchmarkSection`, et surtout PAS `$benchmark` : les variables PowerShell
# sont insensibles a la casse, si bien que `$benchmark` designe exactement le
# parametre `-Benchmark`. Lui affecter la table de la section faisait echouer le
# script sur « Impossible de convertir Hashtable en SwitchParameter » — apres la
# collecte, donc apres avoir charge la machine pour rien.
#
# Le defaut n'est apparu qu'a l'execution reelle : la suite de tests lit la
# source, et aucune lecture de source ne rapproche `$benchmark` de `$Benchmark`.
$benchmarkSection = $null
if ($collectStress) {
  $benchmarkSection = Invoke-Collector -Section 'benchmark' -Label 'Banc d''essai' -Body { Invoke-StressProfile }
}

# L'observation vient en dernier : elle dure ce que l'utilisateur a demande, et
# la placer avant retarderait d'autant tout le reste de la collecte.
$monitoring = $null
if ($collectMonitoring) {
  $monitoring = Invoke-Collector -Section 'monitoring' -Label ('Observation sur ' + $Monitor + ' s') -Body {
    Get-MonitoringSection -DurationSeconds $Monitor
  }
}

# --- Assemblage -------------------------------------------------------------

Stop-ConsoleProgress

$os = $inventory.os
$bios = $inventory.bios
$cs = $inventory.computerSystem
$baseBoard = $inventory.baseBoard

# Sections absentes de ce rapport, et pourquoi. Elles sont deduites de la
# matrice plutot qu'enumerees a la main : une liste tenue separement du
# branchement finit toujours par en differer, et c'est le lecteur du rapport
# qui en paie le prix.
#
# `firmware` s'y ajoute : elle exigerait une source constructeur qu'aucun
# scanner n'interroge, donc elle ne figure dans aucune matrice.
$skippedSections = @('firmware')
# Declarer la section sans dire pourquoi la faisait apparaitre au rapport sous
# « motif non precise », a cote de sections dont le motif est connu : le lecteur
# ne pouvait pas distinguer une absence expliquee d'un oubli du scanner.
Add-CollectionIssue -Section 'firmware' -Severity 'warning' `
  -Message 'Aucun scanner ne collecte cette section : elle exige une source constructeur que SysAudit n''interroge pas.' -Reason 'UNSUPPORTED'
foreach ($section in @('motherboard', 'bios', 'cpus', 'memory', 'gpus', 'sensors', 'power',
    'audio', 'storage', 'network', 'devices', 'drivers', 'software', 'startup', 'security', 'virtualization',
    'benchmark')) {
  if (Test-LevelCollectsSection -Section $section) { continue }
  $skippedSections += $section
  Add-LevelSkip -Section $section
}

# Un collecteur qui echoue laisse ses sections absentes, pour une raison qui
# n'a rien a voir avec le niveau : `Invoke-Collector` l'a deja rapportee.
if ($collectHardware -and $null -eq $hardware) {
  $skippedSections += @('motherboard', 'bios', 'cpus', 'memory', 'gpus')
}
if ($collectAudio -and $null -eq $audio) { $skippedSections += 'audio' }
if ($collectSensors -and $null -eq $sensors) { $skippedSections += 'sensors' }
if ($collectStorage -and $null -eq $storage) { $skippedSections += 'storage' }
if ($collectStartup -and $null -eq $startup) { $skippedSections += 'startup' }
if ($collectSoftware -and $null -eq $software) { $skippedSections += 'software' }
if ($collectDevices -and $null -eq $deviceInventory) { $skippedSections += @('devices', 'drivers') }
if ($collectVirtualization -and $null -eq $virtualization) { $skippedSections += 'virtualization' }
if ($collectStress -and $null -eq $benchmarkSection) { $skippedSections += 'benchmark' }
if ($collectPower -and $null -eq $power) { $skippedSections += 'power' }
if ($collectEvents -and $null -eq $events) { $skippedSections += 'events' }
if ($collectStability -and $null -eq $stability) { $skippedSections += 'stability' }
if ($collectBoot -and $null -eq $boot) { $skippedSections += 'boot' }
if ($collectShutdown -and $null -eq $shutdown) { $skippedSections += 'shutdown' }

# L'observation n'appartient a aucun niveau : son absence tient a ce qui a ete
# demande, pas au profil. La declarer evite qu'un rapport sans serie temporelle
# se lise comme une machine dont on aurait observe l'inactivite.
if ($null -eq $monitoring) {
  $skippedSections += 'monitoring'
  Add-CollectionIssue -Section 'monitoring' -Severity 'warning' `
    -Message 'Observation dans la duree non demandee : relancer avec -Monitor <secondes>.' -Reason 'NOT_REQUESTED'
}
if ($null -eq $security) { $skippedSections += 'security' }
if ($null -eq $network) { $skippedSections += 'network' }

$durationMs = Get-AuditDurationMs -ElapsedMs $scanStopwatch.Elapsed.TotalMilliseconds
if ($null -eq $durationMs) {
  Add-CollectionIssue -Section 'report.durationMs' -Severity 'warning' `
    -Message 'Duree d''audit non mesurable : la mesure ecoulee est hors de toute plage plausible.' -Reason 'NOT_AVAILABLE'
}

# Outils disponibles, calcules une seule fois.
#
# `capabilities.tools` et `collection.dependencies` decrivent la meme realite
# sous deux angles : la premiere dit ce qui repond, la seconde ce qu'il en est
# advenu pendant l'audit. Les derivant du meme objet, elles ne peuvent pas se
# contredire — deux tables tenues separement l'auraient fait tot ou tard.
$toolAvailability = @{
  powershell = $true
  cim = (Test-LegacyCommand -Name 'Get-CimInstance')
  wmi = (Test-LegacyCommand -Name 'Get-WmiObject')
  winEvent = (Test-LegacyCommand -Name 'Get-WinEvent')
  eventLog = (Test-LegacyCommand -Name 'Get-EventLog')
  getComputerInfo = (Test-LegacyCommand -Name 'Get-ComputerInfo')
  netFirewall = [bool](Get-Command Get-NetFirewallProfile -ErrorAction SilentlyContinue)
  netAdapter = [bool](Get-Command Get-NetAdapter -ErrorAction SilentlyContinue)
  bitlocker = [bool](Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)
  defender = [bool](Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue)
  tpm = [bool](Get-Command Get-Tpm -ErrorAction SilentlyContinue)
  winsat = [bool](Get-Command winsat -ErrorAction SilentlyContinue)
  hyperv = [bool](Get-Command Get-VM -ErrorAction SilentlyContinue)
  appx = [bool](Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)
  winget = [bool](Get-Command winget -CommandType Application -ErrorAction SilentlyContinue)
  docker = [bool](Get-Command docker -CommandType Application -ErrorAction SilentlyContinue)
}

$report = @{
  schemaVersion = $script:SCHEMA_VERSION
  scannerVersion = $script:SCANNER_VERSION
  report = @{
    localId = 'scan-' + [guid]::NewGuid().ToString()
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    scannerKind = (Get-LegacyOsVersion -OperatingSystem $os).scannerKind
    profile = $ScanProfile
    anonymized = $false
    anonymizedCategories = @()
    # Intention au moment de la collecte, pas issue de l'envoi : un envoi demande
    # puis refuse par un pare-feu reste `online`. Le rapport est alors « collecte
    # en ligne, transporte a la main » — deux faits distincts, que confondre en un
    # seul rendrait le champ inutilisable. Le transport est retenu cote API.
    collectionMode = if ($Upload) { 'online' } else { 'offline' }
  }
  capabilities = @{
    platform = 'windows'
    distribution = Get-StringOrUnknown -Value $os.Caption -Reason 'UNKNOWN'
    architecture = Get-StringOrUnknown -Value $os.OSArchitecture -Reason 'UNKNOWN'
    privileged = (Test-IsAdministrator)
    proxmox = $false
    docker = [bool](Get-Command docker -CommandType Application -ErrorAction SilentlyContinue)
    tools = $toolAvailability
  }
  system = Get-SystemSection -Inventory $inventory
  os = Get-OsSection -Inventory $inventory
  collection = @{
    issues = @(Get-CollectionIssueList)
    skippedSections = @($skippedSections | Select-Object -Unique)
    timings = @(Get-CollectionTimings)
    # Inventaire des outils, avant toute chose. Sous Windows il ne peut rien
    # devenir d'autre : aucun collecteur ne depend d'un outil tiers, donc rien
    # ne s'installe et rien ne se retire. Voir lib/core/provision.ps1.
    dependencies = @(Get-DependencyInventory -Tools $toolAvailability)
    dependenciesInspected = $true
    # Ce que le niveau prevoyait, et ce que ce scanner sait faire : les deux
    # denominateurs de toute mesure de couverture. Ils sont recopies de la
    # matrice, sans calcul — un denominateur recalcule ailleurs finit par ne
    # plus correspondre a son numerateur. `monitoring` s'ajoute au plan quand
    # elle a ete demandee : elle ne depend pas du niveau, mais elle etait bien
    # prevue pour cet audit-ci.
    plannedSections = @(Get-SectionsForLevel) + @(if ($Monitor -gt 0) { 'monitoring' })
    knownSections = @(Get-SectionList)
  }
}

# Champ facultatif : une duree non mesurable est omise, jamais remplacee par un
# nombre de convenance. Sa raison figure dans `collection.issues`.
if ($null -ne $durationMs) { $report.report.durationMs = $durationMs }

$provenance = Get-CollectionProvenance
if ($provenance.Count -gt 0) {
  $report.collection.provenance = $provenance
}

if ($null -ne $security) { $report.security = $security }

if ($null -ne $power) { $report.power = $power }
if ($null -ne $stability) { $report.stability = $stability }
if ($null -ne $boot) { $report.boot = $boot }
if ($null -ne $shutdown) { $report.shutdown = $shutdown }
if ($null -ne $events) { $report.events = $events }

if ($null -ne $benchmarkSection) { $report.benchmark = $benchmarkSection }
if ($null -ne $monitoring) { $report.monitoring = $monitoring }
if ($null -ne $audio) { $report.audio = $audio }
if ($null -ne $sensors) { $report.sensors = $sensors }
if ($null -ne $startup) { $report.startup = $startup }
if ($null -ne $software) { $report.software = $software }

if ($null -ne $deviceInventory) {
  $report.devices = $deviceInventory.devices
  $report.drivers = $deviceInventory.drivers
}

if ($null -ne $virtualization) {
  $report.virtualization = $virtualization

  # L'hyperviseur hote est un fait sur *cette* machine : il appartient donc
  # aussi aux capacites, ou les regles d'analyse le cherchent, et pas seulement
  # a la section qui inventorie ce que la machine heberge.
  if ($virtualization.ContainsKey('runningUnder')) {
    $report.capabilities.virtualized = $virtualization.runningUnder
  }
}

if ($null -ne $network) {
  # Ces deux listes partent vides parce que **personne ne les a remplies**, et
  # non parce que la machine n'aurait ni suffixe de recherche ni port en ecoute.
  # Le schema leur impose un tableau : impossible d'y poser un marqueur
  # d'inconnu. La seule façon de ne pas affirmer une absence est donc de la
  # declarer dans `collection.issues`, comme le scanner Linux le fait pour les
  # sections hors niveau. Sans ces deux lignes, un poste Windows se lisait
  # « aucun service en ecoute » — la conclusion tiree d'une donnee absente que
  # ce projet s'interdit partout ailleurs. Constate par l'audit des niveaux du
  # 2026-08-09 ; le plafond correspondant est declare dans
  # `SCANNER_SECTION_CAPS.windows.network`.
  Add-CollectionIssue -Section 'network.searchDomains' -Severity 'warning' `
    -Message 'Suffixes de recherche DNS non collectes par le scanner Windows, quel que soit le niveau.' -Reason 'UNSUPPORTED'
  $report.network = @{
    interfaces = $network.interfaces
    dnsServers = $network.dnsServers
    searchDomains = @()
    listeningPorts = @()
  }

  # Les ports en ecoute sont desormais collectes. La liste ne reste vide — et
  # declaree telle — que si les deux applets de commande ont refuse : `SEC-008`
  # sort alors en non evalue au lieu de conclure « aucun service en ecoute ».
  if ($null -ne $network.listeningPorts) {
    $report.network.listeningPorts = @($network.listeningPorts)
  } else {
    Add-CollectionIssue -Section 'network.listeningPorts' -Severity 'warning' `
      -Message 'Ports en ecoute non lus : la liste vide ne signifie pas qu''aucun service n''ecoute.' -Reason 'NOT_AVAILABLE'
  }

  # La table de routage n'est jointe que si elle a ete lue. Un tableau vide
  # affirmerait « aucune route », ce qu'aucune machine en reseau ne verifie ;
  # la cle absente laisse `NET-006` sortir en non evalue, avec le motif que
  # `Get-NetRouteTable` a laisse dans `collection.issues`.
  if ($null -ne $network.routes) { $report.network.routes = $network.routes }
}

if ($null -ne $hardware) {
  $slotsTotal = $hardware.slotsTotal

  if (Test-LevelCollectsSection -Section 'motherboard') {
    $report.motherboard = @{
      manufacturer = if ($baseBoard) { Get-StringOrUnknown -Value $baseBoard.Manufacturer -Reason 'UNKNOWN' } else { New-Unknown -Reason 'NOT_AVAILABLE' }
      model = if ($baseBoard) { Get-StringOrUnknown -Value $baseBoard.Product -Reason 'UNKNOWN' } else { New-Unknown -Reason 'NOT_AVAILABLE' }
      revision = if ($baseBoard) { Get-StringOrUnknown -Value $baseBoard.Version -Reason 'UNKNOWN' } else { New-Unknown -Reason 'NOT_AVAILABLE' }
      serialNumber = if ($baseBoard) { Get-MeaningfulStringOrUnknown -Value $baseBoard.SerialNumber -Reason 'UNKNOWN' } else { New-Unknown -Reason 'NOT_AVAILABLE' }
      chipset = New-Unknown -Reason 'NOT_AVAILABLE'
      socket = New-Unknown -Reason 'NOT_AVAILABLE'
      memorySlots = if ($null -ne $slotsTotal) { [int]$slotsTotal } else { New-Unknown -Reason 'UNKNOWN' }
    }
  }

  if (Test-LevelCollectsSection -Section 'bios') {
    $report.bios = @{
      manufacturer = Get-StringOrUnknown -Value $bios.Manufacturer -Reason 'UNKNOWN'
      version = Get-StringOrUnknown -Value $bios.SMBIOSBIOSVersion -Reason 'UNKNOWN'
      releaseDate = Convert-WmiDateOrUnknown -Value $bios.ReleaseDate
      mode = if ((Get-SecureBootState) -eq 'UNSUPPORTED') { 'LEGACY' } else { 'UEFI' }
      secureBoot = Get-SecureBootState
      smbiosVersion = Get-StringOrUnknown -Value $bios.SMBIOSMajorVersion -Reason 'UNKNOWN'
    }
  }

  $report.cpus = $hardware.cpus
  $report.gpus = $hardware.gpus
  $report.memory = @{
    modules = $hardware.memoryModules
    installedBytes = Get-PositiveIntOrUnknown -Value $cs.TotalPhysicalMemory -Reason 'UNKNOWN'
    availableBytes = Get-PositiveIntOrUnknown -Value ($os.FreePhysicalMemory * 1024) -Reason 'UNKNOWN'
    slotsTotal = if ($null -ne $slotsTotal) { [int]$slotsTotal } else { New-Unknown -Reason 'UNKNOWN' }
    slotsUsed = @($hardware.memoryModules).Count
    # `MaxCapacityEx` est en **kilo-octets**, comme `FreePhysicalMemory` et
    # `SizeStoredInPagingFiles` ci-dessous -- Microsoft le documente ainsi, et
    # la propriete `MaxCapacity` qu'elle remplace est depreciee. Le facteur
    # manquant faisait annoncer 128 **mebi**-octets de capacite maximale sur une
    # carte mere AM5 qui en accepte 128 gibioctets, soit moins que les 32 Gio
    # deja installes. `memoryMaxCapacityBytes` refuse desormais de publier une
    # telle valeur ; c'est ici qu'elle cesse d'etre produite.
    maxCapacityBytes = if ($hardware.memoryArrays) { Get-PositiveIntOrUnknown -Value (($hardware.memoryArrays | Measure-Object -Property MaxCapacityEx -Sum).Sum * 1024) -Reason 'UNKNOWN' } else { New-Unknown -Reason 'NOT_AVAILABLE' }
    # `SizeStoredInPagingFiles` est en **kilo-octets**, comme `FreePhysicalMemory`
    # juste au-dessus — pas en mebioctets. Le facteur de trop faisait annoncer
    # 34 **tera**-octets de fichier d'echange pour 34 gigaoctets, et rendait
    # `PRF-001` inoffensive : le taux d'occupation, divise par mille, restait
    # sous tous les seuils quelle que soit la charge reelle.
    swapTotalBytes = Get-PositiveIntOrUnknown -Value ($os.SizeStoredInPagingFiles * 1024) -Reason 'UNKNOWN'
    swapUsedBytes = Get-PageFileUsedBytes -OperatingSystem $os
  }
}

if ($null -ne $storage) {
  $report.storage = @{
    disks = $storage.disks
    totalBytes = $storage.totalBytes
    usedBytes = $storage.usedBytes
    trimScheduled = $storage.trimScheduled
  }

  # `pools = @()` etait pose ici sans que rien n'ait ete sonde : DIA-014 et
  # DIA-017 lisaient un tableau vide et concluaient « aucun ensemble sur cette
  # machine » — une affirmation batie sur une valeur par defaut.
  if ($null -ne $storage.pools) { $report.storage.pools = @($storage.pools) }
}

# --- Sorties ----------------------------------------------------------------

# Les problemes de collecte sont releves **ici**, et non a la construction du
# rapport.
#
# `collection.issues` etait fige au moment ou la table etait ecrite, une
# soixantaine de lignes avant l'assemblage des sections. Toute issue posee
# ensuite disparaissait sans bruit — dont les deux qui declarent les ports en
# ecoute et les suffixes de recherche DNS non collectes sous Windows.
#
# Ces deux lignes-la existaient precisement pour empecher `SEC-008` de conclure
# « aucun service en ecoute » sur une liste vide par defaut. Elles n'arrivaient
# jamais au rapport : un poste dont le serveur OpenSSH ecoutait sur le port 22
# recevait un feu vert sur un controle de securite. Constate le 2026-08-24 sur
# un poste reel, sshd en cours d'execution.
#
# Le releve tardif vaut pour toutes les issues a venir, sans qu'aucun futur
# collecteur ait a connaitre cet ordre.
$report.collection.issues = @(Get-CollectionIssueList)

$payload = $report | ConvertTo-Json -Depth 16 -Compress

$reportName = Get-SysAuditReportFileName -MachineName $env:COMPUTERNAME

# Ou poser le fichier.
#
# La destination ne depend PAS du repertoire courant. Elle l'a longtemps fait,
# et le defaut se lisait dans le nom du rapport :
# `C:\WINDOWS\system32\sysaudit-LAPTOP-WNX.json` — parce qu'une console ouverte
# depuis le menu Demarrer, un clic droit « Executer en tant qu'administrateur »
# ou un `powershell` lance depuis CMD ont tous ce repertoire-la pour repertoire
# courant. Le fichier etait alors introuvable pour qui devait le deposer, quand
# il n'etait pas simplement refuse.
#
# `lib/core/paths.ps1` porte la decision : dossier Telechargements de
# l'utilisateur reel, puis une chaine de replis dont aucun maillon n'est un
# repertoire systeme.
$reportLabel = ''
$resolvedTarget = $null

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $destination = Resolve-SysAuditReportDirectory

  # Chaque repli est dit, avec ce qui l'a impose : un rapport qui n'est pas la
  # ou l'utilisateur l'attend doit s'expliquer plutot que se laisser chercher.
  foreach ($rejected in $destination.Rejections) {
    Write-ConsoleState -Kind warn -Message (
      $rejected.Label + ' indisponible (' + $rejected.Path + ' : ' + $rejected.Reason + ').')
  }

  if ([string]::IsNullOrWhiteSpace([string]$destination.Path)) {
    # Aucun repli n'a tenu. Le dire et sortir, plutot que d'ecrire dans le
    # premier repertoire venu : c'est ainsi qu'on se retrouve a semer des
    # rapports dans `System32`.
    Write-ConsoleState -Kind error -Message 'Aucune destination inscriptible pour le rapport.'
    Write-ConsoleState -Kind warn -Message 'Indiquez-en une : .\sysaudit.ps1 -OutputPath D:\audits\rapport.json'
    exit $script:EXIT_AUDIT_FAILED
  }

  if (@($destination.Rejections).Count -gt 0) {
    Write-ConsoleState -Kind warn -Message ('Utilisation du repertoire de secours : ' + $destination.Path)
  }

  $reportLabel = [string]$destination.Label
  $resolvedTarget = Resolve-SysAuditReportPath -FileName $reportName -Directory $destination.Path
} else {
  # Seul cas ou le repertoire courant intervient, et il est demande : un
  # `-OutputPath .\audit.json` tape dans une console designe cette console-la.
  $resolvedTarget = Resolve-SysAuditReportPath -Requested $OutputPath -FileName $reportName `
    -WorkingDirectory (Get-Location).Path
}

$target = [string]$resolvedTarget.Path

# Le repertoire d'un chemin demande explicitement peut ne pas exister encore.
# Le creer vaut mieux que refuser : c'est ce que fait deja le scanner Linux
# pour `--output-dir`.
$targetDirectory = ''
try {
  $targetDirectory = [string][System.IO.Path]::GetDirectoryName($target)
} catch {
  Write-Verbose ('Repertoire du chemin demande illisible : ' + $_.Exception.Message)
}
if (-not [string]::IsNullOrWhiteSpace($targetDirectory) -and -not (Test-Path -LiteralPath $targetDirectory)) {
  try {
    New-Item -ItemType Directory -Path $targetDirectory -Force -ErrorAction Stop | Out-Null
  } catch {
    Write-ConsoleState -Kind error -Message (
      'Repertoire de destination inaccessible (' + $targetDirectory + ') : ' + $_.Exception.Message)
    exit $script:EXIT_AUDIT_FAILED
  }
}

# Un rapport peut contenir des donnees personnelles : il est ecrit sans BOM et
# reste un fichier local tant que -Upload n'est pas demande.
$utf8 = [System.Text.UTF8Encoding]::new($false)

# L'ecriture est gardee : un dossier protege par une ACL, un disque plein ou un
# antivirus qui verrouille le fichier levaient une exception .NET brute, et
# l'audit se terminait sur une trace d'appels au lieu d'une phrase.
try {
  [System.IO.File]::WriteAllText($target, $payload, $utf8)
} catch {
  Write-ConsoleState -Kind error -Message ('Ecriture du rapport impossible : ' + $_.Exception.Message)
  Write-ConsoleState -Kind warn -Message ('Destination refusee : ' + $target)
  Write-ConsoleState -Kind warn -Message 'Indiquez-en une autre : .\sysaudit.ps1 -OutputPath D:\audits\rapport.json'
  exit $script:EXIT_AUDIT_FAILED
}

Write-ConsoleSummary -Report $report
Write-ConsoleState -Kind ok -Message ('Rapport ecrit : ' + $target)

# Dire que la mesure de performances existe, a qui vient de terminer un audit
# sans elle. Meme raisonnement que `benchmark_hint` cote Linux, meme retenue :
# le scanner nomme ce qui manque et s'arrete la.
#
# Le silence avait un cout mesurable — au 2026-08-27, le parc comptait 36 audits
# `full` sans une seule mesure, et 9 % d'adoption cote Windows contre 23 % cote
# Linux. Les auteurs de ces audits avaient demande « complet » ; rien ne leur a
# jamais dit que la mesure n'en faisait pas partie.
#
# Trois situations valent un silence : un audit rapide, dont la brievete est
# tout l'objet ; une section ecartee a la main, qui est deja une reponse ; et un
# banc d'essai qui a tourne, qui n'a rien a reclamer.
if (-not $collectStress -and $level -ne 'quick' -and $Skip -notcontains 'benchmark') {
  Write-ConsoleSession 'Aucune mesure de performances dans cet audit.'
  Write-ConsoleSession (
    '-Benchmark mesure processeur, memoire et stockage - la machine est chargee pendant la mesure.')
}

# Phrase unique pour les trois issues d'un envoi manque, plus bas. Elle nomme le
# dossier quand il a un nom : « votre dossier Telechargements » se retrouve,
# alors qu'un chemin seul se relit mal dans une console.
$reportKeptMessage = if ([string]::IsNullOrWhiteSpace($reportLabel)) {
  'Le rapport est conserve : ' + $target
} else {
  'Le rapport est conserve dans votre ' + $reportLabel + ' : ' + $target
}

if (-not $NoMarkdown) {
  $markdownTarget = [System.IO.Path]::ChangeExtension($target, '.md')
  # Le resume Markdown est un supplement : son echec ne coute pas l'audit, qui
  # est deja sur le disque et peut deja partir.
  try {
    [System.IO.File]::WriteAllText($markdownTarget, (Get-ReportMarkdown -Report $report), $utf8)
    Write-ConsoleState -Kind ok -Message ('Resume ecrit  : ' + $markdownTarget)
  } catch {
    Write-ConsoleState -Kind warn -Message (
      'Resume Markdown non ecrit (' + $markdownTarget + ') : ' + $_.Exception.Message)
  }
}

if (-not $Upload) { return }

if ([string]::IsNullOrWhiteSpace($ApiUrl)) {
  throw '-Upload exige -ApiUrl.'
}

$apiBaseUrl = $ApiUrl.TrimEnd('/')
$payloadBytes = $utf8.GetBytes($payload)

# TLS 1.2, faute de quoi l'envoi echoue sur un hote qui refuse TLS 1.1 et
# anterieur : Windows PowerShell 5.1 propose encore « SSL 3.0, TLS 1.0 » sur une
# bonne part du parc, et la connexion est alors coupee avant toute reponse HTTP
# — « Impossible de se connecter au serveur distant », qui ne dit pas pourquoi.
#
# Repete ici alors que l'amorcage le fait deja : le scanner tourne dans un
# PROCESSUS DISTINCT, lance par `-File`, et n'herite d'aucun reglage de celui
# qui l'appelle. Il doit aussi fonctionner lance seul, sans amorcage.
#
# `SystemDefault` (0) vaut « laisser Windows choisir » : y toucher interdirait
# TLS 1.3 la ou il existe. Seules les valeurs explicites sont completees, et
# TLS 1.2 est AJOUTE a la liste, jamais substitue.
if ([int][Net.ServicePointManager]::SecurityProtocol -ne 0) {
  [Net.ServicePointManager]::SecurityProtocol =
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}

# Proxy, s'il en faut un. Sans declaration, le proxy systeme reste en vigueur et
# recoit seulement ce qui lui manquait : de quoi s'authentifier. Voir
# `Set-SysAuditProxy`.
$proxyUrl = Resolve-SysAuditProxyUrl `
  -Explicit $Proxy `
  -SysAuditProxy $env:SYSAUDIT_PROXY `
  -HttpsProxy $env:HTTPS_PROXY `
  -HttpProxy $env:HTTP_PROXY
$proxyApplied = Set-SysAuditProxy -ProxyUrl $proxyUrl
if (-not $Quiet -and -not [string]::IsNullOrWhiteSpace($proxyApplied)) {
  # L'hote et le port seulement : `Set-SysAuditProxy` ne rend jamais les
  # identifiants, et rien ici ne doit les faire apparaitre.
  Write-Host ('Proxy: ' + $proxyApplied)
}

# L'envoi est annonce AVANT d'etre tente.
#
# Il est le seul appel bloquant du scanner, et le seul qui depende d'un tiers.
# Sans cette ligne, une console restee sur « Rapport ecrit » ne distingue pas un
# scanner termine d'un scanner qui attend un reseau qui ne repondra pas — et
# l'utilisateur conclut que le scanner s'arrete la.
Write-ConsoleState -Kind run -Message ('Envoi du rapport a ' + $apiBaseUrl + ' ...')

# Un quota depasse n'est pas un refus definitif : l'API annonce le delai a
# respecter, et l'amorcage vient justement de consommer le quota en telechargeant
# la vingtaine de fichiers du scanner. Abandonner l'envoi pour douze secondes
# d'attente obligeait l'utilisateur a tout relancer — collecte comprise.
$response = $null
$attempt = 0
$maxAttempts = 3

while ($null -eq $response) {
  $attempt++
  try {
    $uploadHeaders = @{}
    if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
      $uploadHeaders['X-Audit-Session-Id'] = $SessionId
    }
    if (-not [string]::IsNullOrWhiteSpace($UploadToken)) {
      $uploadHeaders['X-Audit-Upload-Token'] = $UploadToken
    }
    if (-not [string]::IsNullOrWhiteSpace($Claim)) {
      $uploadHeaders['X-Machine-Claim'] = $Claim
    }
    # La portee de publication voyage en en-tete, jamais dans le rapport : elle
    # decrit ce qu'on fait de cet envoi-ci, pas la machine. Un rapport archive puis
    # renvoye plus tard ne doit pas rejouer un choix pris un autre jour.
    #
    # `-Private` est envoye **explicitement**, et ce n'est pas une redondance :
    # sans en-tete, c'est le defaut de l'instance qui tranche, et il peut valoir
    # PUBLIC. Ne rien dire n'est donc pas demander le prive.
    if ($Public) {
      $uploadHeaders['X-Scan-Visibility'] = 'public'
    }
    elseif ($Private) {
      $uploadHeaders['X-Scan-Visibility'] = 'private'
    }

    # `Invoke-SysAuditUpload` et non `WebClient` : ce dernier n'expose aucun
    # delai, et un serveur qui accepte la connexion sans jamais repondre figeait
    # la console sur la ligne ci-dessus, sans message ni code de sortie.
    $responseBody = Invoke-SysAuditUpload `
      -Url ($apiBaseUrl + '/api/v1/scans/upload') `
      -Body $payloadBytes `
      -Headers $uploadHeaders `
      -UserAgent ('SysAudit-Windows-Scanner/' + $script:SCANNER_VERSION) `
      -TimeoutSeconds $script:UPLOAD_TIMEOUT_SECONDS

    # Une reponse acceptee mais illisible n'est PAS une raison de reessayer.
    #
    # La condition de boucle porte sur `$response` : un corps vide, ou du JSON
    # que `ConvertFrom-Json` rend a `$null`, relancait l'envoi **indefiniment**,
    # sans rien afficher. Le scanner paraissait alors s'etre arrete apres
    # « Rapport ecrit », alors qu'il televersait le rapport en boucle.
    #
    # L'audit est deja sur le disque : on nomme la cause et on sort, comme pour
    # tout autre echec de remise.
    $response = $null
    if (-not [string]::IsNullOrWhiteSpace($responseBody)) {
      try {
        $response = ($responseBody | ConvertFrom-Json)
      } catch {
        # Le corps est conserve dans le message ci-dessous : le detail de
        # l'exception n'apprendrait rien de plus a qui lit la console.
        Write-Verbose ('Reponse non convertible en JSON : ' + $_.Exception.Message)
      }
    }

    if ($null -eq $response) {
      Write-ConsoleState -Kind error -Message (
        'Envoi accepte par le serveur, mais reponse illisible : ' +
        'un equipement intermediaire a probablement remplace la reponse de l''API.')
      if (-not [string]::IsNullOrWhiteSpace($responseBody)) {
        Write-ConsoleState -Kind warn -Message ('Reponse : ' + $responseBody)
      }
      Write-ConsoleState -Kind warn -Message $reportKeptMessage
      Write-Host 'Pour savoir ce qui bloque : .\sysaudit.ps1 -NetworkTest -ApiUrl <url>'
      exit $script:EXIT_TRANSPORT_FAILED
    }
  } catch [System.Net.WebException] {
    $errorResponse = $_.Exception.Response

    # Aucune reponse du tout : le transport a echoue avant HTTP. `Status` porte
    # la cause exacte — nom qui ne resout pas, certificat refuse, delai depasse —
    # et c'est la seule qu'on aura.
    #
    # Cette branche relevait l'exception .NET telle quelle, sans dire que le
    # rapport etait conserve : l'utilisateur voyait « Impossible de se connecter
    # au serveur distant » et croyait la collecte perdue. Elle ne l'a jamais ete.
    if ($null -eq $errorResponse) {
      $cause = Get-SysAuditTransportFailure -Status ([string]$_.Exception.Status)
      Write-ConsoleState -Kind error -Message ('Envoi impossible : ' + $cause)
      Write-ConsoleState -Kind warn -Message $reportKeptMessage
      $hint = Get-SysAuditNetworkHint -Cause $cause
      if (-not [string]::IsNullOrWhiteSpace($hint)) {
        Write-ConsoleState -Kind warn -Message $hint
      }
      Write-Host 'Pour savoir ce qui bloque : .\sysaudit.ps1 -NetworkTest -ApiUrl <url>'
      Write-Host 'Si ce reseau n''ouvrira pas, deposez le fichier depuis un poste connecte :'
      Write-Host '  page « Deposer un rapport » (/deposer) du site SysAudit'
      # `exit` et non `throw` : l'audit a reussi, seule sa remise a manque, et
      # le code de sortie doit le dire. `throw` sortait en 1, comme une collecte
      # impossible — un ordonnanceur ne pouvait pas faire la difference.
      exit $script:EXIT_TRANSPORT_FAILED
    }

    $errorReader = New-Object System.IO.StreamReader($errorResponse.GetResponseStream(), $utf8)
    try {
      $errorBody = $errorReader.ReadToEnd()
    } finally {
      $errorReader.Dispose()
    }

    $status = 0
    if ($errorResponse -is [System.Net.HttpWebResponse]) {
      $status = [int]$errorResponse.StatusCode
    }

    if ($status -eq 429 -and $attempt -lt $maxAttempts) {
      $wait = Get-RetryAfterSeconds -Header ([string]$errorResponse.Headers['Retry-After']) -Body $errorBody
      Write-ConsoleState -Kind warn -Message (
        'Quota d''envoi atteint. Nouvel essai dans ' + $wait + ' s (' +
        $attempt + '/' + ($maxAttempts - 1) + ').')
      Start-Sleep -Seconds $wait
      continue
    }

    # Echec definitif. Le rapport est deja sur le disque : le dire vaut mieux que
    # de laisser croire que la collecte est a refaire.
    #
    # Le statut est nomme avant d'etre detaille : « HTTP 407 » ne dit pas a qui
    # s'adresser, « le proxy exige une authentification » le dit.
    $cause = Get-SysAuditHttpFailure -StatusCode $status
    Write-ConsoleState -Kind error -Message ('Envoi refuse — ' + $cause)
    if (-not [string]::IsNullOrWhiteSpace($errorBody)) {
      Write-ConsoleState -Kind warn -Message ('Reponse : ' + $errorBody)
    }
    Write-ConsoleState -Kind warn -Message $reportKeptMessage
    $hint = Get-SysAuditNetworkHint -Cause $cause
    if (-not [string]::IsNullOrWhiteSpace($hint)) {
      Write-ConsoleState -Kind warn -Message $hint
    }
    Write-Host 'Si ce reseau n''ouvrira pas, deposez le fichier depuis un poste connecte :'
    Write-Host '  page « Deposer un rapport » (/deposer) du site SysAudit'
    exit $script:EXIT_TRANSPORT_FAILED
  }
}

$reportUrl = if ($response.absoluteUrl) {
  [string]$response.absoluteUrl
} elseif ($response.url) {
  $apiBaseUrl + [string]$response.url
} else {
  $apiBaseUrl + '/id/' + [string]$response.reportId
}

Write-Host ''
Write-ConsoleState -Kind ok -Message ('Rapport disponible : ' + $reportUrl)
Write-ConsoleQrCode -Qr $response.qr

# L'ouverture vient en dernier, apres l'adresse et le QR.
#
# Elle ne les remplace pas : un navigateur qui ne se lance pas — session non
# graphique, execution a distance, navigateur par defaut absent — laisse une
# console ou tout ce qu'il faut est deja ecrit. C'est aussi pourquoi son echec
# ne change pas le code de sortie : l'audit a ete produit et transmis.
#
# `-Quiet` s'en abstient sans avoir a poser `-NoOpen` : une execution qui ne veut
# que les erreurs est une execution automatisee, et rien n'y attend une fenetre.
if (-not $NoOpen -and -not $Quiet) {
  if (-not (Open-ReportInBrowser -Url $reportUrl -Elevated:(Test-IsAdministrator))) {
    Write-ConsoleState -Kind warn -Message 'Navigateur non ouvert : suivez l''adresse ci-dessus.'
  }
}
