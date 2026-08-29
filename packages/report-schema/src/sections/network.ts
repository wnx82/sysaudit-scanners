// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { z } from 'zod';
import {
  anonymizableText,
  ipv4,
  ipv6,
  macAddress,
  maybe,
  positiveInt,
  shortText,
} from '../primitives.js';

export const ipv4AddressSchema = z.object({
  address: ipv4,
  prefixLength: z.number().int().min(0).max(32).optional(),
});

export const ipv6AddressSchema = z.object({
  address: ipv6,
  prefixLength: z.number().int().min(0).max(128).optional(),
});

/**
 * Informations Wi-Fi. Le SSID peut être collecté et anonymisé ; la clé (PSK)
 * ne l'est **jamais**, en aucune circonstance (§21).
 */
export const wifiSchema = z.object({
  ssid: maybe(anonymizableText),
  signalPercent: maybe(z.number().min(0).max(100)),
  signalDbm: maybe(z.number().min(-120).max(0)),
  frequencyMhz: maybe(positiveInt),
  channel: maybe(positiveInt),
  standard: maybe(shortText),
  linkSpeedMbps: maybe(positiveInt),
});

export const networkInterfaceSchema = z.object({
  name: shortText,
  manufacturer: maybe(shortText),
  model: maybe(shortText),
  mac: maybe(macAddress),
  type: maybe(
    z.enum(['ethernet', 'wifi', 'bridge', 'bond', 'vlan', 'vpn', 'loopback', 'virtual', 'other']),
  ),
  status: maybe(z.enum(['UP', 'DOWN', 'UNKNOWN'])),
  speedMbps: maybe(positiveInt),
  /** Mode de transmission négocié. Sans objet sur une interface virtuelle. */
  duplex: maybe(z.enum(['FULL', 'HALF'])),
  /** Identifiant VLAN, uniquement sur une interface qui en porte un. */
  vlanId: maybe(z.number().int().min(0).max(4094)).optional(),
  mtu: maybe(positiveInt),
  driver: maybe(shortText),
  dhcp: maybe(z.boolean()),
  ipv4: z.array(ipv4AddressSchema).max(32).default([]),
  ipv6: z.array(ipv6AddressSchema).max(32).default([]),
  gateway: maybe(shortText),
  wifi: wifiSchema.optional(),
});

/** Port en écoute. L'adresse d'écoute détermine l'exposition réelle du service. */
export const listeningPortSchema = z.object({
  protocol: z.enum(['tcp', 'tcp6', 'udp', 'udp6']),
  port: z.number().int().min(0).max(65535),
  /**
   * `0.0.0.0` ou `::` signalent une exposition à toutes les interfaces.
   *
   * Facultatif depuis la 1.22.0, non parce qu'un scanner pourrait ne pas la
   * lire — il la lit toujours — mais parce qu'un service lié à une adresse
   * précise y écrit l'adresse LAN de la machine. Le champ est donc réservé au
   * propriétaire, et un champ réservé doit pouvoir porter le marqueur qui dit
   * qu'il est retenu. Ce que la valeur apportait à un tiers, `exposed` le dit
   * déjà sans nommer aucune adresse.
   */
  address: maybe(shortText),
  process: maybe(shortText),
  /** Vrai uniquement si l'écoute n'est pas limitée à la boucle locale. */
  exposed: z.boolean(),
});

/**
 * Route du système. Le tableau reste borné : sur un routeur, la table complète
 * ferait plusieurs milliers d'entrées sans rien apprendre sur la machine.
 */
export const routeSchema = z.object({
  /** `default` ou un préfixe CIDR. */
  destination: shortText,
  gateway: maybe(shortText),
  interface: maybe(shortText),
  metric: maybe(positiveInt),
});

/**
 * Proxy configuré pour les outils en ligne de commande.
 *
 * Lu dans l'environnement du scan. Les URL sont anonymisables : elles portent
 * parfois un nom d'hôte interne, et peuvent contenir des identifiants — auquel
 * cas la partie sensible est retirée avant écriture, jamais rapportée.
 */
export const proxySchema = z.object({
  http: maybe(anonymizableText),
  https: maybe(anonymizableText),
  noProxy: maybe(anonymizableText),
});

export const networkSchema = z.object({
  interfaces: z.array(networkInterfaceSchema).max(128).default([]),
  dnsServers: z.array(shortText).max(32).default([]),
  /** Domaine de recherche — anonymisable. */
  searchDomains: z.array(anonymizableText).max(32).default([]),
  /**
   * Adresse publique (WAN) de la machine, telle que le serveur la voit.
   *
   * Absente par défaut : la déterminer demande un appel réseau sortant, que le
   * scanner ne fait jamais de lui-même. Elle n'apparaît qu'avec `--public-ip`
   * (`-PublicIp` sous Windows), une option qui n'existe que pour rendre ce
   * choix explicite — le champ manquant se lit « non demandé », jamais
   * « indisponible ».
   *
   * Réservée au propriétaire à la lecture, et anonymisable à la collecte : ces
   * deux protections répondent à deux questions différentes et se cumulent.
   */
  publicIp: maybe(anonymizableText).optional(),
  listeningPorts: z.array(listeningPortSchema).max(2048).default([]),
  routes: z.array(routeSchema).max(256).optional(),
  proxy: proxySchema.optional(),
});

export type NetworkInterface = z.infer<typeof networkInterfaceSchema>;
export type Route = z.infer<typeof routeSchema>;
export type Proxy = z.infer<typeof proxySchema>;
export type ListeningPort = z.infer<typeof listeningPortSchema>;
export type Network = z.infer<typeof networkSchema>;
