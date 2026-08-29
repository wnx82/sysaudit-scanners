# SysAudit Windows — interfaces reseau et resolution DNS.

function Get-AdapterType {
  param($Adapter)
  if ($Adapter.Name -match 'Wi-?Fi|Wireless|WLAN') { return 'wifi' }
  if ($Adapter.Name -match 'Loopback') { return 'loopback' }
  if ($Adapter.Name -match 'Bluetooth|Virtual|VPN|Hyper-V|vEthernet') { return 'virtual' }
  return 'ethernet'
}

<#
.SYNOPSIS
  Range les adresses IP par index d'interface.

.DESCRIPTION
  Fonction pure, separee du collecteur pour etre testable ailleurs que sur
  Windows : elle ne fait qu'ordonner des enregistrements deja obtenus.

  Deux precautions, chacune payee par un defaut constate en production.

  La cle est une **chaine**. Une table de hachage PowerShell compare ses cles
  par type autant que par valeur : une cle rangee en `UInt32` ne se retrouve pas
  avec un `Int32`, et la recherche renvoie `$null` sans lever la moindre erreur.
  `Get-NetIPAddress` et `Get-NetAdapter` n'annoncent pas le meme type d'index
  selon la version de Windows, et la difference ne se voit qu'a l'arrivee : des
  interfaces sans adresse, sans message.

  La famille se lit sur `AddressFamily`, avec le deux-points comme second
  recours. Une carte qui n'annonce pas sa famille verserait sinon ses adresses
  IPv6 dans la colonne IPv4, ce qu'aucun controle du schema n'attraperait :
  `ipv4` accepte la chaine, c'est le format qui la refuserait plus loin.
#>
function Group-NetIPAddressRecord {
  param([object[]]$Records)

  $byIndex = @{}
  foreach ($record in $Records) {
    if ($null -eq $record) { continue }

    $address = [string]$record.IPAddress
    if ([string]::IsNullOrWhiteSpace($address)) { continue }

    # Windows suffixe l'adresse de lien local de sa zone — « fe80::1%7 ». Le
    # schema attend une adresse, pas une adresse et son interface.
    $address = ($address -split '%')[0]

    $key = [string]$record.InterfaceIndex
    if (-not $byIndex.ContainsKey($key)) { $byIndex[$key] = @{ ipv4 = @(); ipv6 = @() } }

    $entry = @{ address = $address; prefixLength = [int]$record.PrefixLength }
    $family = [string]$record.AddressFamily
    if ($family -match 'V6' -or ($family -eq '' -and $address.Contains(':'))) {
      $byIndex[$key].ipv6 += $entry
    } else {
      $byIndex[$key].ipv4 += $entry
    }
  }

  return $byIndex
}

<#
.SYNOPSIS
  Les adresses d'une interface, **toujours** sous forme de tableau.

.DESCRIPTION
  Fonction pure, separee du collecteur pour etre testable ailleurs que sur
  Windows — et elle a besoin de l'etre : c'est la deuxieme fois que ce champ
  precis part de travers en production.

  PowerShell **deballe** un tableau d'un seul element des qu'il traverse le
  pipeline, y compris la sortie d'un `if` ou le `return` d'une fonction. Le code
  precedent, `$ipv4 = if (…) { @($addresses.ipv4) } else { @() }`, produisait
  donc trois resultats differents pour la meme intention :

    aucune adresse  -> `$null`, serialise en `null` ;
    une adresse     -> un objet, serialise en `{ … }` ;
    deux et plus    -> un tableau, serialise en `[ … ]`.

  Le schema attend un tableau dans les trois cas. Sur une machine reelle, ou
  chaque carte porte exactement une adresse IPv4, **tout rapport Windows etait
  refuse** par `validateReport()`.

  La virgule de tete est ce qui repare : `,@($liste)` emet un tableau contenant
  le tableau, le pipeline en retire une couche, et l'appelant recoit bien le
  tableau — quel que soit son nombre d'elements.
#>
function Get-InterfaceAddressList {
  param(
    $Addresses,
    [ValidateSet('ipv4', 'ipv6')][string]$Family
  )

  if ($null -eq $Addresses) { return , @() }
  $list = $Addresses.$Family
  if ($null -eq $list) { return , @() }
  return , @($list)
}

<#
.SYNOPSIS
  Releve l'adresse publique (WAN) aupres de l'API, sur demande explicite.

.DESCRIPTION
  Une machine derriere un routeur ne connait pas son adresse publique : aucune
  interface ne la porte, aucun registre ne l'ecrit. Seul un correspondant
  distant l'observe. La relever suppose donc d'emettre un paquet vers
  l'exterieur — la seule collecte de ce scanner qui le fasse, et la raison pour
  laquelle elle se demande avec `-PublicIp` plutot qu'elle ne s'execute.

  L'API interrogee est celle du produit, et non un service d'echo tiers :
  envoyer l'empreinte reseau des machines auditees a un inconnu pour *proteger*
  leur adresse serait l'exact contraire du but. Cette API recevra le rapport de
  toute facon ; elle n'apprend rien qu'elle n'aurait su.

  Rend l'adresse, ou un marqueur portant la raison de son absence. Jamais la
  chaine recue telle quelle : une page d'erreur de portail captif ferait entrer
  dans le rapport ce qu'un intermediaire aura bien voulu y mettre.
#>
function Get-SysAuditPublicIp {
  param(
    [Parameter(Mandatory = $true)][string]$ApiUrl,
    [string]$UserAgent = '',
    [int]$TimeoutSeconds = 15
  )

  $body = ''
  try {
    $request = [System.Net.HttpWebRequest]::Create($ApiUrl.TrimEnd('/') + '/api/v1/public-ip')
    $request.Method = 'GET'
    $request.Timeout = $TimeoutSeconds * 1000
    $request.ReadWriteTimeout = $TimeoutSeconds * 1000
    if (-not [string]::IsNullOrWhiteSpace($UserAgent)) { $request.UserAgent = $UserAgent }

    $response = $request.GetResponse()
    try {
      $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
      try { $body = $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $response.Dispose() }
  } catch {
    Add-CollectionIssue -Section 'network.publicIp' -Severity 'warning' `
      -Message ('Adresse publique non relevee : ' + $_.Exception.Message) -Source 'api/v1/public-ip' -Reason 'NOT_AVAILABLE'
    return (New-Unknown -Reason 'NOT_AVAILABLE' -Detail 'l''API n''a pas repondu')
  }

  # Extraction par motif plutot que par `ConvertFrom-Json` : la reponse attendue
  # tient en un champ, et un analyseur complet accepterait volontiers une page
  # HTML de portail captif contenant par hasard la bonne cle.
  $ip = ''
  if ($body -match '"ip"\s*:\s*"([^"]*)"') { $ip = $Matches[1] }

  # Le filtre est volontairement grossier — il laisse passer des chaines qui ne
  # sont pas des adresses valides — parce que c'est l'API, a l'ingestion, qui
  # valide le format. Son role ici est d'ecarter ce qui n'est pas une adresse
  # du tout.
  if ([string]::IsNullOrWhiteSpace($ip) -or $ip -notmatch '^[0-9a-fA-F.:]+$') {
    return (New-Unknown -Reason 'NOT_AVAILABLE' `
        -Detail 'reponse illisible — portail captif ou proxy interpose ?')
  }

  return $ip
}

<#
.SYNOPSIS
  Table de routage, lue d'une source structuree.

.DESCRIPTION
  `Get-NetRoute` rend des objets ; `route print` rend un tableau **traduit**,
  dont les en-tetes changent avec la langue de Windows. Le second obligerait a
  reconnaitre « Passerelle » ici et « Gateway » la, et casserait a la premiere
  machine installee dans une langue non prevue.

  Deux normalisations, sans lesquelles la regle NET-006 ne verrait rien :

  - `0.0.0.0/0` et `::/0` deviennent `default`. Le schema attend ce mot, que le
    scanner Linux ecrit tel quel puisque `ip route show` l'imprime. Sans cette
    traduction, la meme configuration se lirait « une passerelle par defaut »
    sous Linux et « aucune » sous Windows ;
  - une passerelle `0.0.0.0` ou `::` n'est pas une passerelle : c'est une route
    directe, sur le lien. Elle porte un marqueur, jamais l'adresse nulle, qui se
    lirait comme une sortie vers une machine d'adresse zero.

  La table est bornee a 128 entrees, comme cote Linux : au-dela, elle decrit la
  table du systeme et non plus la machine. Les routes par defaut passent en
  premier pour qu'un plafond ne puisse jamais les faire tomber.
#>
function Get-NetRouteTable {
  $records = @()
  try {
    $records = @(Get-NetRoute -ErrorAction Stop)
  } catch {
    Add-CollectionIssue -Section 'network.routes' -Severity 'warning' `
      -Message ('Table de routage non lue : ' + $_.Exception.Message) `
      -Source 'Get-NetRoute' -Reason 'NOT_AVAILABLE'
    return $null
  }

  # Zero enregistrement n'est pas une table vide : une machine qui parle a
  # quelque chose a des routes. C'est une lecture qui n'a rien rendu, et le
  # dire evite qu'« aucune route par defaut » ne devienne un constat.
  if ($records.Count -eq 0) {
    # `COLLECTOR_ERROR` et non `UNKNOWN` : le vocabulaire des issues de collecte
    # est ferme et distinct de celui des marqueurs de champ. Un contrat de
    # schema le verifie.
    Add-CollectionIssue -Section 'network.routes' -Severity 'warning' `
      -Message 'Table de routage vide : aucune route rendue par Get-NetRoute.' `
      -Source 'Get-NetRoute' -Reason 'COLLECTOR_ERROR'
    return $null
  }

  $routes = @()
  $ordered = @($records | Sort-Object -Property @{
      Expression = { if ($_.DestinationPrefix -eq '0.0.0.0/0' -or $_.DestinationPrefix -eq '::/0') { 0 } else { 1 } }
    }, DestinationPrefix)

  foreach ($record in $ordered) {
    if ($routes.Count -ge 128) { break }

    $destination = [string]$record.DestinationPrefix
    if ([string]::IsNullOrWhiteSpace($destination)) { continue }
    if ($destination -eq '0.0.0.0/0' -or $destination -eq '::/0') { $destination = 'default' }

    $nextHop = [string]$record.NextHop
    $gateway = if ([string]::IsNullOrWhiteSpace($nextHop) -or $nextHop -eq '0.0.0.0' -or $nextHop -eq '::') {
      New-Unknown -Reason 'NOT_APPLICABLE' -Detail 'route directe, sans passerelle'
    } else {
      $nextHop
    }

    $routes += @{
      destination = $destination
      gateway = $gateway
      interface = Get-StringOrUnknown -Value $record.InterfaceAlias -Reason 'UNKNOWN'
      metric = Get-PositiveIntOrUnknown -Value $record.RouteMetric -Reason 'UNKNOWN'
    }
  }

  Add-CollectionProvenance -Path 'network.routes' -Source 'Get-NetRoute' `
    -Method 'applet de commande' -Precision 'route'

  return $routes
}

<#
.SYNOPSIS
  Vrai si une ecoute sur cette adresse sort de la machine.

.DESCRIPTION
  Hors de `Get-ListeningPortList` pour une raison de verification : les applets
  de commande `Get-NetTCPConnection` et `Get-NetUDPEndpoint` n'existent que sous
  Windows, alors que ce tri-la est du texte pur et se verifie partout — y
  compris sur l'agent Linux qui fait tourner la suite.

  La definition est celle du schema : `exposed` est vrai des que l'ecoute n'est
  **pas** limitee a la boucle locale. La boucle, c'est tout `127.0.0.0/8` — et
  non le seul `127.0.0.1` — plus `::1` et sa forme longue. `0.0.0.0` et `::`
  ecoutent partout ; une adresse d'interface aussi, du point de vue du reseau
  local.

  Le suffixe de zone d'IPv6 — `fe80::1%12` — est retire avant comparaison : il
  nomme l'interface, pas l'adresse.
#>
function Test-ListeningPortExposed {
  param([string]$Address)

  $value = ([string]$Address -split '%')[0].Trim()
  if ([string]::IsNullOrWhiteSpace($value)) {
    # Sans adresse, rien ne prouve que l'ecoute reste locale. Le doute va vers
    # le signalement : `SEC-008` existe pour reperer une ecoute ouverte.
    return $true
  }

  # `IsLoopback` couvre `127.0.0.0/8` en entier — `127.0.0.53` est aussi locale
  # que `127.0.0.1` — ainsi que `::1` et sa forme longue. Une adresse qui ne se
  # laisse pas analyser n'est pas declaree locale pour autant.
  $parsed = [System.Net.IPAddress]::Any
  if ([System.Net.IPAddress]::TryParse($value, [ref]$parsed)) {
    if ([System.Net.IPAddress]::IsLoopback($parsed)) { return $false }
  }

  return $true
}

<#
.SYNOPSIS
  Ports en ecoute, TCP et UDP, avec le processus qui les tient.

.DESCRIPTION
  Cette liste partait vide, et le rapport declarait dans `collection.issues`
  qu'elle ne signifiait rien. C'etait honnete et couteux : `SEC-008` — « Service
  expose sur toutes les interfaces », le controle qui repere une administration
  ouverte au reseau — ne pouvait s'evaluer sur aucune machine Windows.

  `Get-NetTCPConnection` et `Get-NetUDPEndpoint` repondent **sans elevation**.
  Le nom du processus n'est pas toujours lisible : un service tenu par un compte
  systeme refuse `Get-Process` a un utilisateur ordinaire. C'est un marqueur, pas
  un blanc — savoir qu'un port 22 ecoute compte davantage que savoir qui le
  tient.

  `exposed` suit la definition du schema : vrai des que l'ecoute n'est pas
  limitee a la boucle locale. `0.0.0.0` et `::` sont les deux formes de
  « toutes les interfaces » ; `127.0.0.1` et `::1` les deux formes de la boucle.

  L'adresse elle-meme n'est **pas** publiee. Le schema la reserve au
  proprietaire depuis la 1.22.0, parce qu'un service lie a une adresse precise y
  ecrirait l'adresse LAN de la machine. `exposed` dit ce qu'un tiers a besoin de
  savoir sans nommer aucune adresse.
#>
function Get-ListeningPortList {
  $ports = @()
  $seen = @{}
  $processNames = @{}
  $read = $false

  function Resolve-OwningProcessName {
    param($ProcessId)

    if ($null -eq $ProcessId) { return $null }
    $key = [string]$ProcessId
    if ($processNames.ContainsKey($key)) { return $processNames[$key] }

    $name = $null
    try {
      $name = (Get-Process -Id ([int]$ProcessId) -ErrorAction Stop).ProcessName
    } catch {
      # Un service tenu par un compte systeme refuse la lecture a un
      # utilisateur ordinaire. L'ecoute reste un fait ; son proprietaire non.
      Write-Debug ('Processus ' + $key + ' non identifie : ' + $_.Exception.Message)
    }

    $processNames[$key] = $name
    return $name
  }

  foreach ($family in @(
      @{ cmdlet = 'Get-NetTCPConnection'; udp = $false },
      @{ cmdlet = 'Get-NetUDPEndpoint'; udp = $true }
    )) {
    $records = @()
    try {
      $records = if ($family.udp) {
        @(Get-NetUDPEndpoint -ErrorAction Stop)
      } else {
        @(Get-NetTCPConnection -State Listen -ErrorAction Stop)
      }
      $read = $true
    } catch {
      Add-CollectionIssue -Section 'network.listeningPorts' -Severity 'warning' `
        -Message ($family.cmdlet + ' n''a pas repondu : ' + $_.Exception.Message) `
        -Source $family.cmdlet -Reason 'NOT_AVAILABLE'
      continue
    }

    foreach ($record in $records) {
      if ($ports.Count -ge 2048) { break }

      $port = ConvertTo-SafeInt64 -Value $record.LocalPort
      if ($null -eq $port -or $port -lt 0 -or $port -gt 65535) { continue }

      $address = [string]$record.LocalAddress
      $isV6 = $address.Contains(':')
      $protocol = if ($family.udp) {
        if ($isV6) { 'udp6' } else { 'udp' }
      } else {
        if ($isV6) { 'tcp6' } else { 'tcp' }
      }

      # Un meme port peut apparaitre plusieurs fois — une entree par adresse
      # liee. Le rapport decrit un service en ecoute, pas une table de sockets.
      $key = $protocol + '/' + [string]$port
      if ($seen.ContainsKey($key)) {
        if (Test-ListeningPortExposed -Address $address) { $seen[$key].exposed = $true }
        continue
      }

      $processName = Resolve-OwningProcessName -ProcessId $record.OwningProcess
      $entry = @{
        protocol = $protocol
        port = [int]$port
        process = if ([string]::IsNullOrWhiteSpace([string]$processName)) {
          New-Unknown -Reason 'PERMISSION_DENIED' -Detail 'processus proprietaire non lisible sans elevation'
        } else {
          [string]$processName
        }
        exposed = (Test-ListeningPortExposed -Address $address)
        # L'adresse est reservee au proprietaire : voir le schema.
        address = New-Unknown -Reason 'NOT_APPLICABLE' -Detail 'adresse reservee au proprietaire du rapport'
      }
      $seen[$key] = $entry
      $ports += $entry
    }
  }

  if (-not $read) { return $null }

  Add-CollectionProvenance -Path 'network.listeningPorts' `
    -Source 'Get-NetTCPConnection, Get-NetUDPEndpoint' -Method 'applet de commande' -Precision 'port'

  return ,@($ports)
}

function Get-NetworkInventory {
  param(
    # Adresse de l'API a interroger pour l'adresse publique. Vide — le defaut —
    # signifie que `-PublicIp` n'a pas ete demande : aucun paquet ne sort, et le
    # champ reste **absent** du rapport. Un marqueur « non collecte » serait a
    # peine moins faux, et il deviendrait « information protegee » a la lecture
    # par un tiers : une promesse de valeur qui n'existe pas.
    [string]$PublicIpApiUrl = '',
    [string]$UserAgent = ''
  )

  <#
    Les adresses viennent de `Get-NetIPAddress`, et non plus de
    `Get-NetIPConfiguration`.

    C'est d'abord ce que le schema annonce — `network.interfaces[].ipv4` declare
    ce collecteur dans `field-annotations.ts`, et le code en employait un autre.
    C'est surtout ce qui a manque en production : sur un poste Windows 11,
    `Get-NetIPConfiguration` n'a rien renvoye du tout — ni erreur, ni objet — et
    les neuf interfaces du rapport sont parties avec `ipv4: []`, `dhcp` inconnu
    et `gateway` inconnu. Le rapport affichait « aucune » : une conclusion tiree
    d'une donnee absente, exactement ce que ce projet s'interdit.

    `Get-NetIPConfiguration` reste employe pour la passerelle et le mode DHCP,
    qu'il est seul a donner d'un bloc — mais son silence est desormais declare.
  #>
  $addressRecords = @()
  try {
    $addressRecords = @(Get-NetIPAddress -ErrorAction Stop)
  } catch {
    Add-CollectionIssue -Section 'network.interfaces' -Severity 'warning' `
      -Message ('Adresses IP non lues : ' + $_.Exception.Message) -Source 'Get-NetIPAddress' -Reason 'NOT_AVAILABLE'
  }

  # Une machine a toujours au moins une adresse de boucle locale. Zero
  # enregistrement n'est donc pas « pas d'adresse », c'est « pas de lecture » —
  # et il faut le dire, sans quoi le rapport affirme une absence qu'il n'a pas
  # constatee.
  if ($addressRecords.Count -eq 0) {
    Add-CollectionIssue -Section 'network.interfaces' -Severity 'warning' `
      -Message 'Aucune adresse IP retournee : les interfaces sont listees sans adresse.' `
      -Source 'Get-NetIPAddress' -Reason 'NOT_AVAILABLE'
  }

  $addressesByIndex = Group-NetIPAddressRecord -Records $addressRecords

  $ipConfigs = @{}
  try {
    Get-NetIPConfiguration -ErrorAction Stop | ForEach-Object {
      $ipConfigs[[string]$_.InterfaceIndex] = $_
    }
  } catch {
    Add-CollectionIssue -Section 'network.interfaces' -Severity 'warning' `
      -Message ('Configuration IP non lue : ' + $_.Exception.Message) -Source 'Get-NetIPConfiguration' -Reason 'NOT_AVAILABLE'
  }

  $interfaces = @()
  try {
    Get-NetAdapter -ErrorAction Stop | ForEach-Object {
      $cfg = $ipConfigs[[string]$_.ifIndex]
      $addresses = $addressesByIndex[[string]$_.ifIndex]
      $ipv4 = Get-InterfaceAddressList -Addresses $addresses -Family 'ipv4'
      $ipv6 = Get-InterfaceAddressList -Addresses $addresses -Family 'ipv6'

      $interfaces += @{
        name = [string]$_.Name
        manufacturer = Get-StringOrUnknown -Value $_.InterfaceDescription -Reason 'UNKNOWN'
        model = Get-StringOrUnknown -Value $_.DriverDescription -Reason 'UNKNOWN'
        mac = Get-StringOrUnknown -Value (($_.MacAddress -replace '-', ':').ToLowerInvariant()) -Reason 'UNKNOWN'
        type = Get-AdapterType -Adapter $_
        status = if ($_.Status -eq 'Up') { 'UP' } elseif ($_.Status -eq 'Disconnected') { 'DOWN' } else { 'UNKNOWN' }
        speedMbps = if ($_.LinkSpeed -match '(\d+)') { [int]$Matches[1] } else { New-Unknown -Reason 'UNKNOWN' }
        # `FullDuplex` n'est pas expose par toutes les cartes, notamment
        # virtuelles : absent, il reste un marqueur plutot qu'un mode suppose.
        duplex = if ($null -eq $_.FullDuplex) {
          New-Unknown -Reason 'NOT_AVAILABLE'
        } elseif ($_.FullDuplex) {
          'FULL'
        } else {
          'HALF'
        }
        mtu = New-Unknown -Reason 'NOT_AVAILABLE'
        driver = Get-StringOrUnknown -Value $_.DriverFileName -Reason 'UNKNOWN'
        dhcp = if ($cfg -and $cfg.NetIPv4Interface) { [bool]$cfg.NetIPv4Interface.Dhcp } else { New-Unknown -Reason 'UNKNOWN' }
        ipv4 = $ipv4
        ipv6 = $ipv6
        gateway = if ($cfg -and $cfg.IPv4DefaultGateway) { Get-StringOrUnknown -Value $cfg.IPv4DefaultGateway.NextHop -Reason 'UNKNOWN' } else { New-Unknown -Reason 'UNKNOWN' }
      }
    }
  } catch {
    Add-CollectionIssue -Section 'network.interfaces' -Severity 'warning' `
      -Message ('Interfaces reseau non enumerees : ' + $_.Exception.Message) -Source 'Get-NetAdapter' -Reason 'NOT_AVAILABLE'
  }

  $dnsServers = @()
  try {
    $dnsServers = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop | ForEach-Object { $_.ServerAddresses } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
  } catch {
    $dnsServers = @()
  }

  $inventory = @{
    interfaces = $interfaces
    dnsServers = $dnsServers
  }

  # Lue a tous les niveaux, et non a partir de Normale comme cote Linux.
  #
  # `SCANNER_SECTION_CAPS.windows.network` plafonne cette section a `summary`
  # quel que soit le niveau demande : les ports en ecoute et les suffixes de
  # recherche DNS ne sont pas ecrits pour Windows. Conditionner les routes a
  # une profondeur `standard` reviendrait donc a ne jamais les collecter.
  # `Get-NetRoute` est un appel unique et sans effet de bord : le cout tient
  # dans le plafond de `summary`.
  $routes = Get-NetRouteTable
  if ($null -ne $routes) { $inventory['routes'] = $routes }

  $listening = Get-ListeningPortList
  if ($null -ne $listening) { $inventory['listeningPorts'] = $listening }

  if (-not [string]::IsNullOrWhiteSpace($PublicIpApiUrl)) {
    $inventory['publicIp'] = Get-SysAuditPublicIp -ApiUrl $PublicIpApiUrl -UserAgent $UserAgent
  }

  return $inventory
}
