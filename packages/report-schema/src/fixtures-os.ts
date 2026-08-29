// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { unknown } from '@sysaudit/shared';
import { fullReport } from './fixtures.js';
import type { Report } from './report.js';

/**
 * Rapports de référence, un par système supporté ou visé.
 *
 * Ils existent pour une raison : jusqu'ici, tout ce qui lisait un rapport était
 * testé contre **une seule** machine — un hôte Proxmox sous Debian. Un rendu, une
 * règle ou une migration pouvait donc dépendre sans le savoir d'un `scannerKind`,
 * d'un gestionnaire de paquets ou d'une architecture particuliers, et ne casser
 * que sur la machine d'un utilisateur.
 *
 * Chaque fixture est **anonymisée par construction** : les noms de machine sont
 * génériques, les numéros de série et UUID sont des valeurs de test, et aucune
 * adresse publique n'y figure. Ce ne sont pas des rapports réels expurgés, ce
 * sont des rapports fabriqués — la différence compte : un expurgement raté
 * publierait une donnée réelle.
 *
 * Elles ne remplacent pas `fullReport()`, qui reste le rapport riche servant aux
 * tests de rendu détaillé. Elles couvrent la **variété**, pas la profondeur.
 */

export const OS_FIXTURE_KEYS = [
  'ubuntu-24-04',
  'debian-12',
  'fedora-40',
  'arch',
  'raspberry-pi-os',
  'proxmox-8',
  'proxmox-9',
  'windows-11',
  'windows-10',
  'windows-7',
  'windows-server-2022',
] as const;

export type OsFixtureKey = (typeof OS_FIXTURE_KEYS)[number];

interface OsProfile {
  readonly label: string;
  readonly hostname: string;
  readonly build: (base: Report) => Report;
}

/** Base commune : un rapport complet, débarrassé de ce qui est propre à Proxmox. */
function linuxBase(): Report {
  const report = fullReport();
  const { virtualization: _virtualization, ...rest } = report;

  return {
    ...rest,
    report: { ...report.report, scannerKind: 'linux' },
    capabilities: { ...report.capabilities, proxmox: false },
  } as Report;
}

function withOs(report: Report, os: Partial<Report['os']>): Report {
  return { ...report, os: { ...report.os, ...os } };
}

function withSystem(report: Report, system: Partial<Report['system']>): Report {
  return { ...report, system: { ...report.system, ...system } };
}

function withPackageManager(report: Report, name: string, packages: number): Report {
  const software = report.software;
  if (software === undefined) return report;

  return {
    ...report,
    software: {
      ...software,
      packageManagers: [{ name, version: unknown('NOT_AVAILABLE'), packageCount: packages }],
    },
  } as Report;
}

/**
 * Rapport Windows : le scanner Windows ne collecte ni logiciels, ni pilotes, ni
 * virtualisation, et le déclare. Les fixtures doivent refléter cette réalité,
 * faute de quoi elles testeraient un rapport que ce scanner ne produit jamais.
 */
function windowsBase(): Report {
  const report = fullReport();
  const {
    virtualization: _virtualization,
    software: _software,
    firmware: _firmware,
    ...rest
  } = report;

  return {
    ...rest,
    /*
     * Périphériques et pilotes sont conservés depuis la v0.113.0 : le scanner
     * Windows les produit désormais (`Win32_PnPEntity`, `Win32_PnPSignedDriver`).
     * Les retirer ici laisserait six contrôles pilotes non évalués sur la seule
     * fixture Windows, et ferait passer pour une limite de plateforme ce qui
     * n'était qu'un trou de fixture.
     *
     * La largeur des liens PCIe, elle, est bien retirée : CIM ne l'expose pas,
     * et la laisser ferait croire `PRF-005` évaluable sous Windows.
     */
    devices: {
      pci: (report.devices?.pci ?? []).map(({ link: _link, ...device }) => device),
      usb: (report.devices?.usb ?? []).map(({ link: _link, ...device }) => device),
      other: (report.devices?.other ?? []).map(({ link: _link, ...device }) => device),
    },
    drivers: report.drivers ?? [],
    /*
     * Le démarrage rapide est un réglage Windows, et la base Linux y laissait
     * un marqueur « sans objet sous Linux » — sur une fixture Windows, ce qui
     * rendait `BOO-003` non évaluable là où il est justement pertinent.
     */
    boot: { ...report.boot, fastStartupEnabled: false },
    report: { ...report.report, scannerKind: 'windows', profile: 'standard' },
    capabilities: {
      platform: 'windows',
      distribution: 'Windows',
      architecture: '64-bit',
      privileged: true,
      proxmox: false,
      docker: false,
      tools: { powershell: true, cim: true, defender: true, tpm: true, bitlocker: true },
    },
    os: {
      family: 'windows',
      name: 'Microsoft Windows 11 Pro',
      edition: 'Pro',
      distribution: 'Windows',
      version: '10.0.26100',
      build: '26100',
      kernel: '10.0.26100',
      architecture: '64-bit',
      installDate: '2025-01-12',
      locale: 'fr-BE',
      timezone: 'Europe/Brussels',
    },
    collection: {
      issues: [],
      skippedSections: ['firmware', 'software', 'virtualization'],
      // Vide, et volontairement : ces fixtures servent à comparer des OS, pas à
      // les chronométrer. Le tableau vide dit ici « pas de mesure », ce que le
      // schéma interdit justement de confondre avec « instantané ».
      timings: [],
      dependencies: [],
      dependenciesInspected: false,
      // Le plan d'un audit Normale sur ce scanner, moins ce qu'il ne sait pas
      // faire. Sans lui, la couverture de ces fixtures serait « non mesurable »
      // — ce qui est exact pour un vieux rapport, mais pas pour un modèle.
      plannedSections: [
        'system',
        'os',
        'motherboard',
        'bios',
        'cpus',
        'memory',
        'gpus',
        'audio',
        'sensors',
        'power',
        'storage',
        'network',
        'devices',
        'drivers',
        'startup',
        'security',
        'stability',
        'boot',
        'shutdown',
        'events',
      ],
      knownSections: [
        'system',
        'os',
        'motherboard',
        'bios',
        'cpus',
        'memory',
        'gpus',
        'audio',
        'sensors',
        'power',
        'storage',
        'network',
        'devices',
        'drivers',
        'software',
        'startup',
        'security',
        'virtualization',
        'stability',
        'boot',
        'shutdown',
        'events',
        'benchmark',
      ],
    },
  } as Report;
}

const PROFILES: Readonly<Record<OsFixtureKey, OsProfile>> = {
  'ubuntu-24-04': {
    label: 'Ubuntu 24.04 LTS',
    hostname: 'poste-ubuntu',
    build: (base) =>
      withPackageManager(
        withOs(base, {
          name: 'Ubuntu',
          distribution: 'Ubuntu',
          version: '24.04',
          kernel: '6.8.0-41-generic',
          edition: unknown('UNSUPPORTED'),
        }),
        'apt',
        2143,
      ),
  },
  'debian-12': {
    label: 'Debian 12',
    hostname: 'srv-debian',
    build: (base) =>
      withPackageManager(
        withOs(base, {
          name: 'Debian GNU/Linux',
          distribution: 'Debian',
          version: '12',
          kernel: '6.1.0-23-amd64',
        }),
        'apt',
        1187,
      ),
  },
  'fedora-40': {
    label: 'Fedora 40',
    hostname: 'poste-fedora',
    build: (base) =>
      withPackageManager(
        withOs(base, {
          name: 'Fedora Linux',
          distribution: 'Fedora',
          version: '40',
          kernel: '6.9.7-200.fc40.x86_64',
        }),
        'dnf',
        1832,
      ),
  },
  arch: {
    label: 'Arch Linux',
    hostname: 'poste-arch',
    build: (base) =>
      withPackageManager(
        withOs(base, {
          name: 'Arch Linux',
          distribution: 'Arch',
          // Arch est une distribution à publication continue : `os-release`
          // n'y porte pas de `VERSION_ID`, et inventer un numéro serait une
          // valeur fabriquée.
          version: unknown('NOT_AVAILABLE', 'distribution à publication continue'),
          kernel: '6.10.2-arch1-1',
        }),
        'pacman',
        942,
      ),
  },
  'raspberry-pi-os': {
    label: 'Raspberry Pi OS',
    hostname: 'pi-atelier',
    build: (base) =>
      withPackageManager(
        withSystem(
          withOs(base, {
            name: 'Debian GNU/Linux',
            distribution: 'Raspbian',
            version: '12',
            kernel: '6.6.31+rpt-rpi-2712',
            architecture: 'aarch64',
          }),
          {
            manufacturer: 'Raspberry Pi Ltd',
            model: 'Raspberry Pi 5 Model B Rev 1.0',
            chassisType: 'embedded',
            architecture: 'aarch64',
          },
        ),
        'apt',
        764,
      ),
  },
  'proxmox-8': {
    label: 'Proxmox VE 8',
    hostname: 'pve-08',
    build: () => {
      const report = fullReport();
      return {
        ...report,
        report: { ...report.report, scannerKind: 'proxmox' },
        os: { ...report.os, version: '12', kernel: '6.8.12-4-pve' },
      } as Report;
    },
  },
  'proxmox-9': {
    label: 'Proxmox VE 9',
    hostname: 'pve-09',
    build: () => {
      const report = fullReport();
      return {
        ...report,
        report: { ...report.report, scannerKind: 'proxmox' },
        os: { ...report.os, version: '13', kernel: '6.14.0-1-pve' },
      } as Report;
    },
  },
  'windows-11': {
    label: 'Windows 11 Pro',
    hostname: 'poste-win11',
    build: () => windowsBase(),
  },
  /**
   * Windows 10, dernière version servie.
   *
   * Elle diffère de la 11 sur deux points que le moteur d'analyse regarde : sa
   * fin de support est **passée** (2025-10-14), et le socle matériel qu'elle
   * n'exige pas — TPM 2.0, Secure Boot — est présent ici, ce qui distingue
   * « la machine ne peut pas » de « le système n'exige pas ».
   */
  'windows-10': {
    label: 'Windows 10 Pro',
    hostname: 'poste-win10',
    build: () => {
      const base = windowsBase();
      return {
        ...base,
        os: {
          ...base.os,
          name: 'Microsoft Windows 10 Professionnel',
          edition: 'Professionnel',
          version: '10.0.19045',
          build: '19045',
          kernel: '10.0.19045',
          /*
           * La fixture Windows 11 ne porte **aucun** `support` : le scanner ne
           * l'établit que lorsqu'une source fiable le dit, et Windows 11 est
           * encore servi. Ici, la source existe et la date est passée — c'est
           * ce cas-là qu'aucune fixture Windows n'éprouvait.
           */
          support: {
            status: 'END_OF_LIFE',
            endOfLife: '2025-10-14',
            confidence: 'HIGH',
            source: {
              name: 'Microsoft',
              title: 'Windows 10 Home and Pro — end of support',
              url: 'https://learn.microsoft.com/lifecycle/products/windows-10-home-and-pro',
              checkedAt: '2026-08-22T00:00:00Z',
            },
          },
        },
      } as Report;
    },
  },
  /**
   * Windows 7, et ce qu'il **ne peut pas** avoir.
   *
   * C'est la fixture qui manquait le plus, et pas parce qu'elle décrit un
   * système répandu : parce qu'elle est la seule où l'absence est
   * **structurelle**. Secure Boot n'existe pas avant UEFI généralisé, le TPM 2.0
   * n'y est pas spécifié, le démarrage rapide n'y est pas.
   *
   * Un scanner qui rapporte `NOT_APPLICABLE` sur ces trois champs a raison ; un
   * moteur qui en tire un défaut de sécurité a tort. C'est exactement la
   * distinction que le dépôt tient partout — « ne jamais conclure d'une donnée
   * absente » — et aucune fixture ne l'éprouvait.
   */
  'windows-7': {
    label: 'Windows 7 Professionnel',
    hostname: 'poste-win7',
    build: () => {
      const base = windowsBase();
      const { boot, security, bios, ...rest } = base;
      return {
        ...rest,
        os: {
          ...base.os,
          name: 'Microsoft Windows 7 Professionnel',
          edition: 'Professionnel',
          version: '6.1.7601',
          build: '7601',
          kernel: '6.1.7601',
          support: {
            status: 'END_OF_LIFE',
            endOfLife: '2020-01-14',
            // Le support étendu payant s'est arrêté trois ans plus tard : les
            // deux dates existent, et les confondre daterait la fin de six ans
            // trop tôt ou trois ans trop tard selon le sens de l'erreur.
            endOfExtendedSupport: '2023-01-10',
            confidence: 'HIGH',
            source: {
              name: 'Microsoft',
              title: 'Windows 7 — end of support',
              url: 'https://learn.microsoft.com/lifecycle/products/windows-7',
              checkedAt: '2026-08-22T00:00:00Z',
            },
          },
        },
        // Un BIOS hérité : `UEFI` n'est pas une valeur qu'une machine de cette
        // génération peut publier, et `secureBoot` n'y a pas d'objet.
        bios: {
          ...bios,
          mode: 'LEGACY',
          secureBoot: unknown('NOT_APPLICABLE', 'Secure Boot exige un micrologiciel UEFI'),
        },
        security: {
          ...security,
          secureBoot: unknown('NOT_APPLICABLE', 'Secure Boot exige un micrologiciel UEFI'),
          dmaProtection: unknown('NOT_APPLICABLE', 'protection DMA introduite après cette version'),
        },
        boot: {
          ...boot,
          firmwareMode: 'LEGACY_BIOS',
          fastStartupEnabled: unknown(
            'NOT_APPLICABLE',
            'démarrage rapide introduit après cette version',
          ),
        },
      } as Report;
    },
  },
  'windows-server-2022': {
    label: 'Windows Server 2022',
    hostname: 'srv-win',
    build: () => {
      const base = windowsBase();
      return {
        ...base,
        os: {
          ...base.os,
          name: 'Microsoft Windows Server 2022 Standard',
          edition: 'Standard',
          version: '10.0.20348',
          build: '20348',
          kernel: '10.0.20348',
        },
      } as Report;
    },
  },
};

/** Libellé lisible d'une fixture, utilisé par les messages de test. */
export function osFixtureLabel(key: OsFixtureKey): string {
  return PROFILES[key].label;
}

/**
 * Rapport de référence pour un système donné.
 *
 * Le nom de machine est réécrit à chaque construction : deux fixtures ne doivent
 * pas partager d'identité, sans quoi une empreinte machine les confondrait.
 */
export function osFixture(key: OsFixtureKey): Report {
  const profile = PROFILES[key];
  const built = profile.build(key.startsWith('windows') ? fullReport() : linuxBase());

  return withSystem(built, {
    hostname: profile.hostname,
    uuid: `00000000-0000-4000-8000-${key
      .replace(/[^a-z0-9]/g, '')
      .slice(0, 12)
      .padEnd(12, '0')}`,
    serialNumber: `SN-${profile.hostname.toUpperCase()}`,
  });
}

/** Toutes les fixtures, dans l'ordre déclaré. */
export function osFixtures(): { key: OsFixtureKey; label: string; report: Report }[] {
  return OS_FIXTURE_KEYS.map((key) => ({
    key,
    label: osFixtureLabel(key),
    report: osFixture(key),
  }));
}
