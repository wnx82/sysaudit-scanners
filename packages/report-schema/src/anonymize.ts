// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import {
  ANONYMIZED_CATEGORIES,
  createAnonymizer,
  isPrivateIpv4,
  isPrivateIpv6,
  isUnknown,
  type AnonymizedCategory,
  type Anonymizer,
  type Maybe,
} from '@sysaudit/shared';
import type { Report } from './report.js';

/**
 * Anonymisation d'un rapport **déjà collecté**.
 *
 * Le scanner sait déjà anonymiser à la source, et c'est la meilleure option :
 * la donnée identifiante ne quitte jamais la machine. Mais un rapport stocké en
 * clair peut avoir à être montré — lien de partage public, capture d'écran,
 * ticket chez un fournisseur — et il n'est alors plus question de relancer le
 * scan. D'où cette seconde anonymisation, appliquée à la lecture.
 *
 * Trois règles la gouvernent.
 *
 * **Un marqueur d'absence n'est jamais masqué.** `unknown` n'est pas une donnée
 * identifiante ; le remplacer par un pseudonyme transformerait « non collecté »
 * en « collecté puis masqué », soit une information fausse.
 *
 * **Les adresses privées restent lisibles.** `192.168.1.10` ne désigne personne,
 * et c'est précisément la valeur qui sert à comprendre un plan d'adressage. Ce
 * sont les adresses routables qui sont masquées, comme le fait le scanner.
 *
 * **Le rapport dit ce qui a été masqué.** `report.anonymizedCategories` ne
 * liste que les catégories réellement transformées : annoncer une catégorie
 * qu'aucun champ ne portait laisserait croire à une protection appliquée.
 */

export interface AnonymizeOptions {
  /**
   * Sel des pseudonymes. Le même sel redonne les mêmes pseudonymes, ce qui
   * permet de partager deux rapports d'une même machine en gardant leur
   * correspondance. Par défaut, un sel aléatoire empêche toute corrélation.
   */
  readonly salt?: string;
}

export function anonymizeReport(report: Report, options: AnonymizeOptions = {}): Report {
  // Un rapport anonymisé par le scanner ne porte plus de valeur d'origine :
  // le repasser masquerait des pseudonymes en pseudonymes.
  if (report.report.anonymized) return report;

  const anonymizer = createAnonymizer(options.salt);
  const applied = new Set<AnonymizedCategory>();
  const copy = structuredClone(report);

  const mask = <T extends Maybe<string> | undefined>(category: AnonymizedCategory, value: T): T => {
    if (value === undefined || isUnknown(value)) return value;
    applied.add(category);
    return anonymizer.mask(category, value) as T;
  };

  copy.system.hostname = mask('hostname', copy.system.hostname);
  copy.system.uuid = mask('uuid', copy.system.uuid);
  copy.system.serialNumber = mask('serialNumber', copy.system.serialNumber);

  /*
   * Le nom qualifié **contient** le nom de machine : masquer `hostname` en
   * laissant `fqdn` en clair republierait mot pour mot ce qu'on vient de
   * retirer. Le domaine et le groupe de travail nomment l'organisation, comme
   * les domaines de recherche plus bas.
   */
  copy.system.fqdn = mask('hostname', copy.system.fqdn);
  copy.system.domain = mask('domain', copy.system.domain);
  copy.system.workgroup = mask('domain', copy.system.workgroup);
  copy.system.assetTag = mask('serialNumber', copy.system.assetTag);
  copy.system.machineGuid = mask('uuid', copy.system.machineGuid);
  copy.system.machineSid = mask('uuid', copy.system.machineSid);

  if (copy.motherboard !== undefined) {
    copy.motherboard.serialNumber = mask('serialNumber', copy.motherboard.serialNumber);
  }

  for (const module of copy.memory?.modules ?? []) {
    module.serialNumber = mask('serialNumber', module.serialNumber);
  }

  for (const disk of copy.storage?.disks ?? []) {
    disk.serialNumber = mask('serialNumber', disk.serialNumber);
    // WWN, NGUID et EUI-64 identifient l'exemplaire aussi bien que le numéro de
    // série — et mieux : ils se lisent sans privilège, donc ils sont souvent
    // les seuls présents. Les laisser en clair rendrait le masquage du numéro
    // de série décoratif.
    disk.wwn = mask('serialNumber', disk.wwn);
    disk.nguid = mask('serialNumber', disk.nguid);
    disk.eui64 = mask('serialNumber', disk.eui64);

    for (const partition of disk.partitions) {
      partition.uuid = mask('uuid', partition.uuid);
      partition.partitionUuid = mask('uuid', partition.partitionUuid);
    }
  }

  for (const gpu of copy.gpus ?? []) {
    for (const display of gpu.displays ?? []) {
      display.serialNumber = mask('serialNumber', display.serialNumber);
    }
  }

  for (const battery of copy.power?.batteries ?? []) {
    battery.serialNumber = mask('serialNumber', battery.serialNumber);
  }

  // Un bloc d'alimentation qui s'identifie donne son numéro de série comme le
  // ferait un disque. Il n'y en a que sur les machines où l'alimentation parle —
  // serveurs et blocs numériques —, ce qui est précisément le parc où un
  // exemplaire se retrouve dans un inventaire.
  for (const unit of copy.power?.powerSupply?.units ?? []) {
    unit.serialNumber = mask('serialNumber', unit.serialNumber);
    unit.assetTag = mask('serialNumber', unit.assetTag);
  }

  anonymizeNetwork(copy, mask, anonymizer, applied);

  // Le nom du nœud Proxmox est le nom de la machine, écrit une seconde fois :
  // le laisser en clair annulerait le masquage de `system.hostname`. Le nom du
  // cluster désigne l'installation, pas la machine, mais il la situe tout autant.
  const proxmox = copy.virtualization?.proxmox;
  if (proxmox !== undefined) {
    proxmox.node.name = mask('hostname', proxmox.node.name);
    proxmox.cluster.name = mask('domain', proxmox.cluster.name);
  }

  copy.report.anonymized = true;
  copy.report.anonymizedCategories = ANONYMIZED_CATEGORIES.filter((category) =>
    applied.has(category),
  );

  return copy;
}

type Mask = <T extends Maybe<string> | undefined>(category: AnonymizedCategory, value: T) => T;

function anonymizeNetwork(
  copy: Report,
  mask: Mask,
  anonymizer: Anonymizer,
  applied: Set<AnonymizedCategory>,
): void {
  const network = copy.network;
  if (network === undefined) return;

  for (const iface of network.interfaces) {
    iface.mac = mask('macAddress', iface.mac);
    if (iface.wifi !== undefined) iface.wifi.ssid = mask('wifiSsid', iface.wifi.ssid);

    for (const address of iface.ipv4) {
      if (isPrivateIpv4(address.address)) continue;
      address.address = anonymizer.mask('publicIp', address.address);
      applied.add('publicIp');
    }
    for (const address of iface.ipv6) {
      if (isPrivateIpv6(address.address)) continue;
      address.address = anonymizer.mask('publicIp', address.address);
      applied.add('publicIp');
    }
  }

  network.searchDomains = network.searchDomains.map((domain) => {
    applied.add('domain');
    return anonymizer.mask('domain', domain);
  });

  network.publicIp = mask('publicIp', network.publicIp);

  if (network.proxy !== undefined) {
    network.proxy.http = mask('domain', network.proxy.http);
    network.proxy.https = mask('domain', network.proxy.https);
    network.proxy.noProxy = mask('domain', network.proxy.noProxy);
  }
}
