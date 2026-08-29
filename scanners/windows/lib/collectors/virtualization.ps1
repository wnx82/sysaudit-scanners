# SysAudit Windows — virtualisation : hyperviseur hote, Hyper-V, Docker Desktop.
#
# Les variables d'environnement des conteneurs ne sont jamais exportees : elles
# contiennent presque toujours des secrets. Seuls des indicateurs de
# configuration a risque sont collectes, comme cote Linux.
#
# Deux notions voisines ne doivent jamais etre confondues, et Windows rend la
# confusion particulierement facile :
#
#   - `runningUnder` dit sur quel hyperviseur **cette** machine s'execute ;
#   - `hyperv.guests` dit quelles machines **elle heberge**.
#
# `Win32_ComputerSystem.HypervisorPresent` ne repond a aucune des deux. Il vaut
# `$true` sur un invite, mais aussi sur tout hote Hyper-V — et depuis Windows
# 10, sur toute machine ou l'integrite du code protegee par l'hyperviseur, le
# sous-systeme Linux ou la plateforme de machine virtuelle sont actifs, ce qui
# est le cas par defaut sur du materiel recent. S'en servir pour conclure « cette
# machine est virtualisee » ferait passer la majorite des postes physiques
# modernes pour des machines virtuelles.

# Chemins dont le montage dans un conteneur merite d'etre signale.
#
# Les chemins Windows s'y ajoutent aux chemins Unix : Docker Desktop monte les
# lecteurs de l'hote sous leur lettre, et un conteneur Linux peut monter le
# socket du demon aussi bien sous sa forme Unix que via le tube nomme Windows.
$script:SensitiveMountPatterns = @(
  '/var/run/docker.sock', '/run/docker.sock', '//./pipe/docker_engine',
  '/etc', '/root', '/home', '/boot', '/dev', '/proc', '/sys', '/',
  'C:\', 'C:\Windows', 'C:\Users'
)

<#
.SYNOPSIS
  Ce montage merite-t-il d'etre signale ?
.DESCRIPTION
  Fonction pure, testable hors Windows. La comparaison est exacte et
  insensible a la casse : les chemins Windows ne le sont pas, et signaler
  `c:\windows` mais pas `C:\Windows` serait une faille de lecture.
#>
function Test-SensitiveMount {
  param([string]$Source)

  if ([string]::IsNullOrWhiteSpace($Source)) { return $false }
  foreach ($pattern in $script:SensitiveMountPatterns) {
    if ($Source.TrimEnd('/') -eq $pattern.TrimEnd('/')) { return $true }
    if ($Source -eq $pattern) { return $true }
    if ([string]::Equals($Source, $pattern, [StringComparison]::OrdinalIgnoreCase)) { return $true }
  }
  return $false
}

<#
.SYNOPSIS
  Hyperviseur sur lequel cette machine s'execute, ou chaine vide.

.DESCRIPTION
  Fonction pure : elle ne lit rien, elle interprete un modele et un fabricant
  deja obtenus de `Win32_ComputerSystem`.

  Elle conclut sur la **signature du materiel virtuel**, jamais sur la presence
  d'un hyperviseur. Un materiel virtualise se declare : « Virtual Machine » chez
  Microsoft, « VMware Virtual Platform » chez VMware, « VirtualBox » chez Oracle,
  « KVM » ou « Bochs » chez QEMU.

  Rend une chaine vide quand rien ne signe une machine virtuelle. Ce n'est pas
  « machine physique » : c'est « aucun indice de virtualisation parmi ceux
  testes », et l'appelant le traduit en marqueur plutot qu'en negation.
#>
function Get-RunningUnderHypervisor {
  param([string]$Model, [string]$Manufacturer)

  $haystack = ($Model + ' ' + $Manufacturer).Trim()
  if ([string]::IsNullOrWhiteSpace($haystack)) { return '' }

  if ($haystack -match 'VMware') { return 'vmware' }
  if ($haystack -match 'VirtualBox') { return 'virtualbox' }
  if ($haystack -match 'KVM|QEMU|Bochs') { return 'kvm' }
  if ($haystack -match 'Xen') { return 'xen' }
  if ($haystack -match 'Parallels') { return 'parallels' }
  # « Virtual Machine » chez Microsoft signe Hyper-V. Le test vient en dernier :
  # « VMware Virtual Platform » contient aussi « Virtual ».
  if ($haystack -match 'Virtual Machine' -or $haystack -match 'Hyper-V') { return 'hyperv' }

  return ''
}

<#
.SYNOPSIS
  Analyse une correspondance de port publiee par `docker port`.

.DESCRIPTION
  Fonction pure, jumelle de `parse_container_ports` cote Linux.

  Format attendu : `80/tcp -> 0.0.0.0:8080`. L'adresse d'hote peut etre une
  adresse IPv6 entre crochets (`[::]:8080`), auquel cas decouper sur le premier
  deux-points donnerait `[` comme adresse et le reste comme port. Le port se lit
  donc **apres le dernier** deux-points.

  Rend `$null` quand la ligne n'est pas exploitable, plutot qu'un port zero.
#>
function ConvertFrom-DockerPortLine {
  param([string]$Line)

  if ([string]::IsNullOrWhiteSpace($Line)) { return $null }

  $parts = $Line -split '->'
  if ($parts.Count -lt 2) { return $null }

  $containerSide = $parts[0].Trim()
  $hostSide = $parts[1].Trim()

  $containerParts = $containerSide -split '/'
  $containerPort = $containerParts[0].Trim()
  $protocol = if ($containerParts.Count -gt 1) { $containerParts[1].Trim() } else { '' }

  $separator = $hostSide.LastIndexOf(':')
  if ($separator -lt 0) { return $null }
  $hostAddress = $hostSide.Substring(0, $separator).Trim()
  $hostPort = $hostSide.Substring($separator + 1).Trim()

  if ($containerPort -notmatch '^\d+$' -or $hostPort -notmatch '^\d+$') { return $null }
  $containerNumber = [int]$containerPort
  $hostNumber = [int]$hostPort
  if ($containerNumber -gt 65535 -or $hostNumber -gt 65535) { return $null }

  return @{
    hostPort = $hostNumber
    containerPort = $containerNumber
    protocol = if ([string]::IsNullOrWhiteSpace($protocol)) { New-Unknown -Reason 'UNKNOWN' } else { $protocol }
    hostAddress = if ([string]::IsNullOrWhiteSpace($hostAddress)) { New-Unknown -Reason 'UNKNOWN' } else { $hostAddress }
  }
}

<#
.SYNOPSIS
  Etat d'une machine virtuelle Hyper-V, en minuscules.
.DESCRIPTION
  Fonction pure. `Get-VM` publie une enumeration (`Running`, `Off`,
  `Paused`, `Saved`) : elle est normalisee en minuscules pour ressembler aux
  etats Docker et libvirt, que le rapport affiche cote a cote.
#>
function Get-HyperVGuestState {
  param([string]$State)

  if ([string]::IsNullOrWhiteSpace($State)) { return '' }
  return $State.Trim().ToLowerInvariant()
}

<#
.SYNOPSIS
  Machines virtuelles Hyper-V hebergees par cette machine, ou `$null`.

.DESCRIPTION
  Le module Hyper-V n'est present que sur un hote ou le role est installe. Son
  absence n'est pas un echec : c'est le cas de la quasi-totalite des postes.

  `Get-VM` exige l'elevation. Sans elle, il echoue plutot que de rendre une
  liste vide, et la section reste absente avec son motif — une liste vide
  ferait croire a un hote sans machine virtuelle.
#>
function Get-HyperVSection {
  if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) { return $null }

  $guests = @()
  try {
    foreach ($vm in @(Get-VM -ErrorAction Stop)) {
      $state = Get-HyperVGuestState -State ([string]$vm.State)
      $guests += @{
        name = Get-StringOrUnknown -Value $vm.Name -Reason 'UNKNOWN'
        state = if ([string]::IsNullOrWhiteSpace($state)) { New-Unknown -Reason 'UNKNOWN' } else { $state }
        vcpus = Get-PositiveIntOrUnknown -Value $vm.ProcessorCount -Reason 'UNKNOWN'
        memoryBytes = Get-PositiveIntOrUnknown -Value $vm.MemoryAssigned -Reason 'UNKNOWN'
        autostart = if ([string]$vm.AutomaticStartAction -eq 'Nothing') { $false }
        elseif ([string]::IsNullOrWhiteSpace([string]$vm.AutomaticStartAction)) { New-Unknown -Reason 'UNKNOWN' }
        else { $true }
      }
    }
  } catch {
    Add-CollectionIssue -Section 'virtualization.hyperv' -Severity 'warning' `
      -Message ('Role Hyper-V present mais ses machines virtuelles n''ont pas repondu : ' + $_.Exception.Message) `
      -Source 'Get-VM' -Reason 'NOT_AVAILABLE'
    return $null
  }

  $version = New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'Hyper-V ne publie pas de version distincte de celle de Windows'
  try {
    $service = Get-CimInstance -ClassName 'Win32_Service' -Filter "Name='vmms'" -ErrorAction Stop |
      Select-Object -First 1
    if ($null -ne $service -and -not [string]::IsNullOrWhiteSpace([string]$service.PathName)) {
      $version = Get-StringOrUnknown -Value ([System.Environment]::OSVersion.Version.ToString()) -Reason 'UNKNOWN'
    }
  } catch {
    Add-CollectionIssueOnce -Section 'virtualization.hyperv' -Severity 'warning' `
      -Message ('Version du service Hyper-V non lue : ' + $_.Exception.Message) -Source 'Win32_Service' -Reason 'NOT_AVAILABLE'
  }

  Add-CollectionProvenance -Path 'virtualization.hyperv.guests' -Source 'Get-VM' -Method 'PowerShell'

  return @{
    version = $version
    guests = $guests
  }
}

<#
.SYNOPSIS
  Un conteneur Docker, metadonnees uniquement.
.DESCRIPTION
  Un seul `docker inspect` par conteneur, avec un gabarit qui n'extrait que des
  metadonnees : ni `.Config.Env`, ni `.Config.Cmd`, qui exposeraient des secrets
  et des lignes de commande completes.
#>
function Get-DockerContainer {
  param([string]$DockerPath, [string]$Id)

  $format = '{{.Name}}|{{.Config.Image}}|{{.State.Status}}|{{.HostConfig.Privileged}}|{{.HostConfig.NetworkMode}}'
  $info = ''
  try {
    $info = (& $DockerPath 'inspect' $Id '--format' $format 2>$null | Out-String).Trim()
  } catch {
    return $null
  }
  if ([string]::IsNullOrWhiteSpace($info)) { return $null }

  $fields = $info -split '\|'
  if ($fields.Count -lt 5) { return $null }

  $name = $fields[0].Trim().TrimStart('/')
  if ([string]::IsNullOrWhiteSpace($name)) { return $null }

  $mounts = @()
  $socketMounted = $false
  try {
    $mountOutput = (& $DockerPath 'inspect' $Id '--format' '{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' 2>$null | Out-String)
    foreach ($line in ($mountOutput -split "`n")) {
      $source = $line.Trim()
      if ([string]::IsNullOrWhiteSpace($source)) { continue }
      if ($source -in @('/var/run/docker.sock', '/run/docker.sock', '//./pipe/docker_engine')) {
        $socketMounted = $true
      }
      if (Test-SensitiveMount -Source $source) { $mounts += $source }
    }
  } catch {
    Add-CollectionIssueOnce -Section 'virtualization.docker' -Severity 'warning' `
      -Message ('Montages des conteneurs non inspectes : ' + $_.Exception.Message) -Source 'docker inspect' -Reason 'NOT_AVAILABLE'
  }

  $ports = @()
  try {
    $portOutput = (& $DockerPath 'port' $Id 2>$null | Out-String)
    foreach ($line in ($portOutput -split "`n")) {
      $parsed = ConvertFrom-DockerPortLine -Line $line
      if ($null -ne $parsed) { $ports += $parsed }
    }
  } catch {
    Add-CollectionIssueOnce -Section 'virtualization.docker' -Severity 'warning' `
      -Message ('Ports publies non lus : ' + $_.Exception.Message) -Source 'docker port' -Reason 'NOT_AVAILABLE'
  }

  $privileged = [string]$fields[3].Trim()
  $networkMode = [string]$fields[4].Trim()

  return @{
    name = $name
    image = Get-StringOrUnknown -Value $fields[1] -Reason 'UNKNOWN'
    state = Get-StringOrUnknown -Value $fields[2] -Reason 'UNKNOWN'
    privileged = if ($privileged -eq 'true') { $true } elseif ($privileged -eq 'false') { $false } else { New-Unknown -Reason 'UNKNOWN' }
    networkMode = if ([string]::IsNullOrWhiteSpace($networkMode)) { New-Unknown -Reason 'UNKNOWN' } else { $networkMode }
    publishedPorts = $ports
    sensitiveMounts = $mounts
    dockerSocketMounted = $socketMounted
  }
}

<#
.SYNOPSIS
  Docker Desktop, ou `$null` si le client est absent.
.DESCRIPTION
  Un client present dont le demon ne repond pas laisse la section absente avec
  son motif, jamais une liste vide : Docker Desktop est arrete la plupart du
  temps sur un poste ordinaire, et « aucun conteneur » se lirait comme un fait.
#>
function Get-DockerSection {
  $docker = Get-Command docker -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -eq $docker) { return $null }

  $version = ''
  try {
    $version = (& $docker.Source 'info' '--format' '{{.ServerVersion}}' 2>$null | Out-String).Trim()
  } catch {
    $version = ''
  }

  if ([string]::IsNullOrWhiteSpace($version)) {
    <#
      Un demon arrete n'est pas une donnee manquante.

      Docker Desktop passe l'essentiel de son temps eteint sur un poste
      ordinaire, et c'est un etat voulu, pas une panne : demon arrete signifie
      aucun conteneur en execution — la question a donc une reponse. La classer
      « source indisponible » revenait a exiger de l'utilisateur qu'il demarre
      Docker pour obtenir un audit propre, c'est-a-dire a fabriquer le `partial`
      que ce produit s'interdit ailleurs. Constate le 2026-08-16 : un poste
      Windows 11 sortait `partial` aux trois niveaux pour cette seule raison.

      Le demon **actif** qui ne repond pas reste, lui, un vrai manque : la
      source existe, elle devrait parler, et il y a quelque chose a corriger.
    #>
    $service = Get-Service -Name 'com.docker.service' -ErrorAction SilentlyContinue
    $backend = @(Get-Process -Name 'com.docker.backend' -ErrorAction SilentlyContinue)
    $active = ($null -ne $service -and $service.Status -eq 'Running') -or $backend.Count -gt 0

    if ($active) {
      Add-CollectionIssue -Section 'virtualization.docker' -Severity 'warning' `
        -Message 'Demon Docker actif mais sans reponse : conteneurs non inventories.' `
        -Source 'docker' -Reason 'NOT_AVAILABLE'
    } else {
      Add-CollectionIssue -Section 'virtualization.docker' -Severity 'warning' `
        -Message 'Docker installe et arrete : aucun conteneur en execution, rien a inventorier.' `
        -Source 'docker' -Reason 'NOT_APPLICABLE'
    }
    return $null
  }

  $containers = @()
  try {
    $ids = @((& $docker.Source 'ps' '-aq' 2>$null | Out-String) -split "`n" |
        ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    # Meme plafond que cote Linux : au-dela, l'inspection un-par-un couterait
    # plus que ce qu'elle apprend.
    foreach ($id in ($ids | Select-Object -First 200)) {
      $container = Get-DockerContainer -DockerPath $docker.Source -Id $id
      if ($null -ne $container) { $containers += $container }
    }
  } catch {
    Add-CollectionIssue -Section 'virtualization.docker' -Severity 'warning' `
      -Message ('Conteneurs non enumeres : ' + $_.Exception.Message) -Source 'docker' -Reason 'NOT_AVAILABLE'
  }

  $networks = @()
  try {
    $networkOutput = (& $docker.Source 'network' 'ls' '--format' '{{.Name}}|{{.Driver}}' 2>$null | Out-String)
    foreach ($line in ($networkOutput -split "`n")) {
      $trimmed = $line.Trim()
      if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
      $fields = $trimmed -split '\|'
      if ([string]::IsNullOrWhiteSpace($fields[0])) { continue }
      $networks += @{
        name = $fields[0].Trim()
        driver = if ($fields.Count -gt 1) { Get-StringOrUnknown -Value $fields[1] -Reason 'UNKNOWN' } else { New-Unknown -Reason 'UNKNOWN' }
      }
    }
  } catch {
    Add-CollectionIssueOnce -Section 'virtualization.docker' -Severity 'warning' `
      -Message ('Reseaux Docker non enumeres : ' + $_.Exception.Message) -Source 'docker network ls' -Reason 'NOT_AVAILABLE'
  }

  $volumeCount = New-Unknown -Reason 'NOT_AVAILABLE'
  try {
    $volumes = @((& $docker.Source 'volume' 'ls' '-q' 2>$null | Out-String) -split "`n" |
        ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $volumeCount = [int]$volumes.Count
  } catch {
    Add-CollectionIssueOnce -Section 'virtualization.docker' -Severity 'warning' `
      -Message ('Volumes Docker non comptes : ' + $_.Exception.Message) -Source 'docker volume ls' -Reason 'NOT_AVAILABLE'
  }

  Add-CollectionProvenance -Path 'virtualization.docker' -Source 'docker' -Method 'CLI'

  return @{
    version = $version
    containers = $containers
    networks = $networks
    volumeCount = $volumeCount
  }
}

<#
.SYNOPSIS
  Section `virtualization` du rapport, ou `$null` si rien n'a ete trouve.
.DESCRIPTION
  Une section absente vaut mieux qu'une section vide : sur un poste sans
  Hyper-V, sans Docker et non virtualise, il n'y a rien a dire, et le dire
  quand meme donnerait a lire trois listes vides sans signification.
#>
function Get-VirtualizationSection {
  $section = @{}

  try {
    $computerSystem = Get-CimInstance -ClassName 'Win32_ComputerSystem' -ErrorAction Stop
    $runningUnder = Get-RunningUnderHypervisor -Model ([string]$computerSystem.Model) `
      -Manufacturer ([string]$computerSystem.Manufacturer)
    if (-not [string]::IsNullOrWhiteSpace($runningUnder)) {
      $section.runningUnder = $runningUnder
      Add-CollectionProvenance -Path 'virtualization.runningUnder' -Source 'Win32_ComputerSystem' -Method 'CIM'
    }
  } catch {
    Add-CollectionIssue -Section 'virtualization' -Severity 'warning' `
      -Message ('Signature materielle non lue : ' + $_.Exception.Message) -Source 'Win32_ComputerSystem' -Reason 'NOT_AVAILABLE'
  }

  $hyperv = Get-HyperVSection
  if ($null -ne $hyperv) { $section.hyperv = $hyperv }

  $docker = Get-DockerSection
  if ($null -ne $docker) { $section.docker = $docker }

  if ($section.Count -eq 0) { return $null }
  return $section
}
