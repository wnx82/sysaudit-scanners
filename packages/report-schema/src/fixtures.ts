// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { unknown } from '@sysaudit/shared';
import type { Report } from './report.js';
import { SCHEMA_VERSION } from './version.js';

/**
 * Rapports de référence utilisés par les tests du schéma, du rendu, des moteurs
 * de règles et de l'API.
 *
 * Ils sont volontairement exportés par le package : disposer d'un rapport
 * valide partagé évite que chaque consommateur en réinvente un légèrement
 * différent, ce qui masquerait des régressions de compatibilité.
 */

/**
 * Sections que le scanner Linux sait collecter, tous niveaux confondus.
 *
 * Recopiée de la matrice de `@sysaudit/platform` — que ce package ne peut pas
 * importer, les dépendances allant dans l'autre sens. Elle sert de dénominateur
 * aux fixtures ; un test de couverture qui la verrait vide conclurait « non
 * mesurable » là où l'on veut précisément mesurer.
 */
const KNOWN_SECTIONS = [
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
];

/** Le plus petit rapport valide possible : un scanner sans aucun privilège ni outil. */
export function minimalReport(): Report {
  return {
    schemaVersion: SCHEMA_VERSION,
    scannerVersion: '0.1.0',
    report: {
      generatedAt: '2026-07-25T16:42:00Z',
      scannerKind: 'linux',
      profile: 'standard',
      anonymized: false,
      anonymizedCategories: [],
    },
    capabilities: {
      platform: 'linux',
      architecture: 'x86_64',
      privileged: false,
      proxmox: false,
      docker: false,
      tools: { dmidecode: false, smartctl: false, lspci: false, sensors: false },
    },
    system: {
      hostname: 'pc-grenier',
      manufacturer: unknown('NOT_AVAILABLE', 'dmidecode absent'),
      model: unknown('NOT_AVAILABLE', 'dmidecode absent'),
      chassisType: unknown('NOT_AVAILABLE'),
      uuid: unknown('PERMISSION_DENIED'),
      serialNumber: unknown('PERMISSION_DENIED'),
      architecture: 'x86_64',
      uptimeSeconds: 3600,
      timezone: 'Europe/Brussels',
      localTime: '2026-07-25T18:42:00+02:00',
    },
    os: {
      family: 'linux',
      name: 'Debian GNU/Linux',
      edition: unknown('UNSUPPORTED', 'notion sans objet sous Linux'),
      distribution: 'Debian',
      version: '13',
      build: unknown('NOT_AVAILABLE'),
      kernel: '6.12.0-amd64',
      architecture: 'x86_64',
      installDate: unknown('NOT_AVAILABLE'),
      locale: 'fr_BE.UTF-8',
      timezone: 'Europe/Brussels',
    },
    collection: {
      issues: [
        {
          section: 'motherboard',
          severity: 'warning',
          message: 'dmidecode absent : identité matérielle non collectée.',
          source: 'dmidecode',
          // Une collecte attendue et manquée pour une cause remédiable : c'est
          // ce motif-là, et lui seul, qui rend cet audit `partial`.
          reason: 'NOT_AVAILABLE',
        },
      ],
      skippedSections: ['drivers', 'firmware'],
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
        'startup',
        'security',
        'virtualization',
        'stability',
        'boot',
        'shutdown',
        'events',
      ],
      knownSections: KNOWN_SECTIONS,
      // Le stockage domine, et de loin : `smartctl` interroge chaque disque et
      // attend sa réponse. C'est le profil réel d'un audit, et il justifie à lui
      // seul la granularité par collecteur — une durée totale ne dirait pas où
      // partent les trois quarts du temps.
      timings: [
        { section: 'system', durationMs: 41 },
        { section: 'os', durationMs: 96 },
        { section: 'storage', durationMs: 4820 },
        { section: 'network', durationMs: 612 },
        { section: 'security', durationMs: 288 },
      ],
      // Le cas nominal d'un audit qui n'installe rien : l'inventaire a eu lieu,
      // `dmidecode` manque, et personne ne s'est vu proposer de l'installer.
      // C'est cette combinaison — `NOT_OFFERED` sur un audit inspecté — qui
      // décrit la quasi-totalité des rapports.
      dependencies: [
        {
          tool: 'smartctl',
          package: 'smartmontools',
          outcome: 'PRESENT_BEFORE',
          version: 'smartctl 7.4 2023-08-01 r5530',
          unlocks: 'santé SMART et usure des disques',
          used: true,
          removal: 'NOT_APPLICABLE',
        },
        {
          tool: 'dmidecode',
          package: 'dmidecode',
          outcome: 'NOT_OFFERED',
          unlocks: 'carte mère, BIOS et barrettes mémoire',
          used: false,
          removal: 'NOT_APPLICABLE',
        },
      ],
      dependenciesInspected: true,
      provenance: {
        system: {
          source: '/etc/os-release',
          method: 'lecture fichier',
          precision: 'instantané',
          collectedAt: '2026-07-25T16:42:00Z',
        },
      },
    },
  };
}

/**
 * Les neuf relevés de la charge soutenue du rapport de référence.
 *
 * Générés plutôt qu'écrits à la main : neuf blocs de treize champs occuperaient
 * cent trente lignes pour une progression que quatre tableaux disent mieux. Ce
 * qui compte se lit d'un coup — la fréquence retombe, la température monte, le
 * ventilateur accélère, et le bridage thermique apparaît quand le seuil est
 * atteint.
 */
const SOAK_TELEMETRY = [
  { frequency: 5_000, temperature: 61, watts: 142.0, fan: 1_180, throttled: false },
  { frequency: 4_880, temperature: 68, watts: 141.2, fan: 1_340, throttled: false },
  { frequency: 4_610, temperature: 76, watts: 139.8, fan: 1_520, throttled: false },
  { frequency: 4_120, temperature: 84, watts: 132.4, fan: 1_760, throttled: false },
  { frequency: 3_540, temperature: 89, watts: 121.0, fan: 1_910, throttled: true },
  { frequency: 3_180, temperature: 91, watts: 112.6, fan: 1_980, throttled: true },
  { frequency: 3_090, temperature: 91, watts: 110.2, fan: 1_990, throttled: true },
  { frequency: 3_120, temperature: 90, watts: 111.4, fan: 1_985, throttled: true },
  { frequency: 3_090, temperature: 91, watts: 110.8, fan: 1_990, throttled: true },
].map((entry, index) => ({
  at: `2026-07-25T16:40:${String(35 + index).padStart(2, '0')}Z`,
  phase: 'cpu-soak' as const,
  cpuUsagePercent: 99.4,
  cpuTemperatureCelsius: entry.temperature,
  cpuFrequencyMhz: entry.frequency,
  cpuPackagePowerWatts: entry.watts,
  cpuFanRpm: entry.fan,
  cpuThrottled: entry.throttled,
  // Le motif n'accompagne que le bridage constaté : sans indicateur matériel,
  // une fréquence basse ne désigne aucune cause.
  ...(entry.throttled ? { cpuThrottleReason: 'thermal' as const } : {}),
  memoryUsedBytes: 12_884_901_888,
  swapUsedBytes: 1_073_741_824,
  diskReadBytesPerSecond: 0,
  diskWriteBytesPerSecond: 65_536,
  networkRxBytesPerSecond: 12_288,
  networkTxBytesPerSecond: 6_144,
}));

/**
 * La charge mixte, huit relevés.
 *
 * Elle raconte ce qu'aucune mesure isolée ne montre : la carte tient son rendu
 * tant que le processeur travaille peu, puis la cadence s'effondre à mesure que
 * le budget de puissance se partage. C'est exactement la situation que les
 * mesures `gpu` et `cpu-multi` séparées ne peuvent pas décrire.
 *
 * Les relevés portent le détail cœur par cœur, sur quatre cœurs seulement — la
 * fixture doit rester lisible, et quatre suffisent à montrer ce qui compte :
 * deux cœurs tenus haut, deux qui décrochent. Le troisième relevé porte un cœur
 * illisible, marqué comme tel plutôt que rendu à zéro : c'est le cas que le
 * rendu doit traverser sans tracer une chute qui n'a pas eu lieu.
 */
const GAMING_TELEMETRY = [
  { fps: 118, frame: 8.47, gpuTemp: 62, gpuClock: 2_610, cores: [4_900, 4_880, 3_100, 3_050] },
  { fps: 116, frame: 8.62, gpuTemp: 66, gpuClock: 2_595, cores: [4_890, 4_870, 3_090, 3_040] },
  { fps: 109, frame: 9.17, gpuTemp: 71, gpuClock: 2_540, cores: [4_860, null, 3_070, 3_020] },
  { fps: 98, frame: 10.2, gpuTemp: 75, gpuClock: 2_430, cores: [4_700, 4_690, 3_010, 2_980] },
  { fps: 91, frame: 10.99, gpuTemp: 78, gpuClock: 2_310, cores: [4_540, 4_520, 2_950, 2_930] },
  { fps: 84, frame: 11.9, gpuTemp: 80, gpuClock: 2_190, cores: [4_380, 4_360, 2_900, 2_880] },
  { fps: 81, frame: 12.35, gpuTemp: 81, gpuClock: 2_140, cores: [4_310, 4_300, 2_880, 2_860] },
  { fps: 80, frame: 12.5, gpuTemp: 81, gpuClock: 2_130, cores: [4_300, 4_290, 2_875, 2_855] },
].map((entry, index) => ({
  at: `2026-07-25T16:52:${String(10 + index).padStart(2, '0')}Z`,
  phase: 'gaming' as const,
  cpuUsagePercent: 52.4,
  cpuTemperatureCelsius: 72 + index,
  cpuFrequencyMhz: Math.round(
    entry.cores.reduce((sum: number, value) => sum + (value ?? 0), 0) /
      entry.cores.filter((value) => value !== null).length,
  ),
  cpuPackagePowerWatts: 96.5,
  cpuFanRpm: 1_450 + index * 30,
  memoryUsedBytes: 17_179_869_184,
  swapUsedBytes: 1_073_741_824,
  diskReadBytesPerSecond: 0,
  diskWriteBytesPerSecond: 32_768,
  networkRxBytesPerSecond: 4_096,
  networkTxBytesPerSecond: 2_048,
  // Un cœur illisible porte son marqueur. Le rendre à zéro tracerait une chute
  // brutale au milieu d'une courbe stable — une panne inventée.
  cpuCoreClocksMhz: entry.cores.map((value) =>
    value === null
      ? unknown('NOT_AVAILABLE', 'cpufreq n’expose pas la fréquence de ce cœur')
      : value,
  ),
  cpuCoreUsagePercent: [99.1, 98.7, 12.4, 11.8],
  gpuIndex: 0,
  gpuTemperatureCelsius: entry.gpuTemp,
  gpuHotspotCelsius: entry.gpuTemp + 11,
  gpuCoreClockMhz: entry.gpuClock,
  gpuMemoryClockMhz: 10_501,
  gpuBoardPowerWatts: 184.2,
  gpuUsagePercent: 99,
  gpuFanRpm: 1_800 + index * 60,
  gpuAuxiliaryFanRpm: [1_790 + index * 60, 1_810 + index * 60],
  framesPerSecond: entry.fps,
  frameTimeMs: entry.frame,
}));

/** Rapport riche : Proxmox privilégié, matériel complet, SMART dégradé, Docker. */
export function fullReport(): Report {
  return {
    schemaVersion: SCHEMA_VERSION,
    scannerVersion: '0.1.0',
    platformVersion: '0.1.0',
    report: {
      localId: 'scan-2026-07-25-164200',
      generatedAt: '2026-07-25T16:42:00Z',
      durationMs: 8420,
      scannerKind: 'proxmox',
      profile: 'full',
      anonymized: false,
      anonymizedCategories: [],
    },
    capabilities: {
      platform: 'linux',
      distribution: 'Debian',
      architecture: 'x86_64',
      privileged: true,
      proxmox: true,
      docker: true,
      tools: {
        dmidecode: true,
        smartctl: true,
        lspci: true,
        lsusb: true,
        sensors: true,
        nvme: true,
        ip: true,
        pvesh: true,
        docker: true,
      },
      // Ce que la machine sait répondre, question par question. `tools` dit que
      // `journalctl` est là ; ceci dit que l'historique matériel n'a malgré tout
      // pas de source ici — deux faits que rien ne permet de déduire l'un de
      // l'autre.
      features: {
        events: 'AVAILABLE',
        boot: 'AVAILABLE',
        shutdown: 'AVAILABLE',
        'stability.hardwareErrors': 'NOT_AVAILABLE',
        'boot.fastStartupEnabled': 'NOT_APPLICABLE',
        'monitoring.aggregates': 'AVAILABLE',
      },
    },
    system: {
      hostname: 'pve-lab',
      fqdn: 'pve-lab.cabinet.lan',
      domain: 'cabinet.lan',
      workgroup: unknown('UNSUPPORTED', 'notion propre à Windows'),
      manufacturer: 'ASUSTeK COMPUTER INC.',
      model: 'PRIME B550-PLUS',
      chassisType: 'desktop',
      uuid: '4c4c4544-0037-5810-8055-b7c04f594d32',
      serialNumber: 'MB1234567890',
      assetTag: 'POSTE-COMPTA-014',
      machineGuid: unknown('UNSUPPORTED', 'notion propre à Windows'),
      machineSid: unknown('UNSUPPORTED', 'notion propre à Windows'),
      architecture: 'x86_64',
      uptimeSeconds: 1_209_600,
      timezone: 'Europe/Brussels',
      localTime: '2026-07-25T18:42:00+02:00',
    },
    os: {
      family: 'linux',
      name: 'Debian GNU/Linux',
      edition: unknown('UNSUPPORTED'),
      distribution: 'Debian',
      version: '12',
      build: unknown('NOT_AVAILABLE'),
      kernel: '6.8.12-4-pve',
      architecture: 'x86_64',
      installDate: '2024-03-14',
      locale: 'fr_BE.UTF-8',
      timezone: 'Europe/Brussels',
      support: {
        status: 'SUPPORTED',
        endOfLife: '2028-06-30',
        confidence: 'HIGH',
        source: {
          name: 'Debian Security Team',
          title: 'Debian Long Term Support',
          url: 'https://wiki.debian.org/LTS',
          checkedAt: '2026-07-25T16:42:00Z',
        },
      },
    },
    motherboard: {
      manufacturer: 'ASUSTeK COMPUTER INC.',
      model: 'PRIME B550-PLUS',
      revision: 'Rev X.0x',
      serialNumber: 'MB1234567890',
      chipset: 'AMD B550',
      socket: 'AM4',
      memorySlots: 4,
    },
    bios: {
      manufacturer: 'American Megatrends Inc.',
      version: '2803',
      releaseDate: '2024-11-08',
      mode: 'UEFI',
      secureBoot: 'DISABLED',
      smbiosVersion: '3.3',
    },
    cpus: [
      {
        manufacturer: 'AMD',
        model: 'AMD Ryzen 7 5700X 8-Core Processor',
        family: 'Zen 3',
        generation: unknown('UNKNOWN', 'génération commerciale non déterminable de façon fiable'),
        socket: 'AM4',
        physicalCores: 8,
        logicalCores: 16,
        baseFrequencyMhz: 3400,
        maxFrequencyMhz: 4600,
        currentFrequencyMhz: 2200,
        cacheBytes: { l1: 524_288, l2: 4_194_304, l3: 33_554_432 },
        instructionSets: ['sse4_2', 'avx', 'avx2', 'aes'],
        virtualization: { supported: true, enabled: true, technology: 'AMD-V' },
        temperatureCelsius: 42.5,
        usagePercent: 12.4,
      },
    ],
    memory: {
      modules: [
        {
          slot: 'DIMM_A2',
          sizeBytes: 17_179_869_184,
          manufacturer: 'Kingston',
          partNumber: 'KF3200C16D4/16GX',
          serialNumber: 'A1B2C3D4',
          type: 'DDR4',
          ratedSpeedMts: 3200,
          configuredSpeedMts: 3200,
          voltage: 1.2,
          ecc: false,
          formFactor: 'DIMM',
        },
        {
          // Le cas qui a motivé la résolution de références : le SMBIOS ne
          // programme pas le fabricant, mais la référence est bien là.
          slot: 'DIMM_B2',
          sizeBytes: 17_179_869_184,
          manufacturer: unknown('NOT_AVAILABLE', 'champ SMBIOS non programmé'),
          partNumber: 'CT16G4SFRA32A.M16FRS',
          serialNumber: 'A1B2C3D5',
          type: 'DDR4',
          ratedSpeedMts: 3200,
          configuredSpeedMts: 3200,
          voltage: 1.2,
          ecc: false,
          formFactor: 'DIMM',
        },
      ],
      installedBytes: 34_359_738_368,
      availableBytes: 12_884_901_888,
      slotsTotal: 4,
      slotsUsed: 2,
      maxCapacityBytes: 137_438_953_472,
      swapTotalBytes: 8_589_934_592,
      swapUsedBytes: 0,
    },
    gpus: [
      {
        vendor: 'NVIDIA',
        model: 'GeForce RTX 2060',
        pciId: '10de:1f08',
        vramBytes: 6_442_450_944,
        driver: 'nvidia',
        driverVersion: '550.127.05',
        driverDate: unknown('NOT_AVAILABLE'),
        temperatureCelsius: 38,
        usagePercent: 0,
        coreClockMhz: 300,
        memoryClockMhz: 405,
        displays: [
          {
            name: 'DP-1',
            manufacturer: 'DEL',
            model: 'DELL U2720Q',
            serialNumber: 'CN-0ABCD-72',
            resolution: '3840x2160',
            refreshRateHz: 60,
            connection: 'DP',
          },
        ],
      },
    ],
    audio: {
      devices: [
        {
          name: 'HDA Intel PCH',
          vendor: unknown('NOT_AVAILABLE'),
          driver: unknown('NOT_AVAILABLE'),
          stack: 'alsa',
          kind: 'PLAYBACK_CAPTURE',
          state: 'ENABLED',
          default: unknown('UNKNOWN'),
        },
      ],
    },
    sensors: {
      temperatures: [
        {
          label: 'Tctl',
          celsius: 42.5,
          criticalCelsius: 95,
          category: 'CPU',
          device: 'AMD Ryzen 7 5800X',
          source: 'hwmon',
          sourcePath: '/sys/class/hwmon/hwmon2/temp1_input',
          scope: 'LOCAL',
          quality: 'MEASURED',
          minCelsius: 41.8,
          averageCelsius: 42.2,
          maxCelsius: 42.5,
          sampleCount: 3,
          rawValue: 42500,
          rawUnit: 'millidegree_celsius',
        },
        {
          label: 'Composite',
          celsius: 51,
          category: 'DRIVE_NVME',
          device: 'Samsung SSD 990 PRO 2TB',
          source: 'NVMe SMART',
          quality: 'MEASURED',
        },
      ],
      temperatureCollection: {
        probed: 14,
        usable: 2,
        discarded: 1,
        sources: ['hwmon', 'NVMe SMART'],
        sampleCount: 3,
        sampleIntervalMs: 1000,
        discardedReadings: [
          {
            label: 'temp3',
            source: 'hwmon',
            sourcePath: '/sys/class/hwmon/hwmon0/temp3_input',
            rawValue: -127000,
            rawUnit: 'millidegree_celsius',
            celsius: -127,
            reason: 'OUT_OF_PHYSICAL_RANGE',
          },
        ],
      },
      fans: [{ label: 'fan1', rpm: 980 }],
      voltages: [{ label: '+12V', volts: 12.096 }],
      powers: [],
    },
    power: {
      batteries: [
        {
          name: 'BAT0',
          manufacturer: 'LGC',
          model: '5B10W13930',
          serialNumber: unknown('NOT_AVAILABLE'),
          technology: 'Li-poly',
          chargePercent: 87,
          status: 'DISCHARGING',
          designCapacityWh: 57,
          fullChargeCapacityWh: 43.12,
          cycleCount: 412,
          voltageVolts: 11.52,
        },
      ],
      acConnected: false,
      /*
       * Le cas ordinaire, et celui qui compte : la machine est mesurée, son bloc
       * d'alimentation reste anonyme. `detected: false` avec des rails et une
       * consommation renseignés n'est pas une collecte ratée — c'est ce qu'un PC
       * de bureau permet de savoir, ni plus ni moins.
       */
      powerSupply: {
        detected: false,
        type: 'UNKNOWN',
        units: [],
        rails: [
          {
            label: '+12V',
            volts: 12.096,
            measuredBy: 'MOTHERBOARD',
            source: 'HWMON',
            chip: 'nct6798',
            sourcePath: '/sys/class/hwmon/hwmon1/in0_input',
          },
          {
            label: '+5V',
            volts: 5.04,
            measuredBy: 'MOTHERBOARD',
            source: 'HWMON',
            chip: 'nct6798',
            sourcePath: '/sys/class/hwmon/hwmon1/in1_input',
          },
          {
            label: '+3.3V',
            volts: 3.312,
            measuredBy: 'MOTHERBOARD',
            source: 'HWMON',
            chip: 'nct6798',
            sourcePath: '/sys/class/hwmon/hwmon1/in2_input',
          },
        ],
        componentPower: [
          {
            label: 'package-0',
            component: 'CPU',
            watts: 31.4,
            source: 'RAPL',
            device: 'AMD Ryzen 7 5800X',
            windowMs: 300,
            sourcePath: '/sys/class/powercap/intel-rapl:0/energy_uj',
          },
          {
            label: 'GPU',
            component: 'GPU',
            watts: 52,
            source: 'HWMON',
            device: 'AMD Radeon RX 6700 XT',
          },
        ],
        sources: ['SYSFS_POWER_SUPPLY', 'HWMON', 'RAPL'],
        limitations: ['SMBIOS_TYPE_39_ABSENT', 'ATX_NOT_SELF_DESCRIBING', 'RAILS_FROM_MOTHERBOARD'],
      },
    },
    storage: {
      disks: [
        {
          device: '/dev/nvme0n1',
          manufacturer: 'Samsung',
          model: 'Samsung SSD 980 PRO 1TB',
          serialNumber: 'S5GXNX0T123456',
          wwn: '0x5002538e40a1b2c3',
          nguid: '00000000000000000026b7683d5a1f2e',
          eui64: '0026b7683d5a1f2e',
          firmware: '5B2QGXA7',
          sizeBytes: 1_000_204_886_016,
          kind: 'NVME',
          mediaType: 'SSD',
          busType: 'NVME',
          protocol: 'NVMe',
          interface: 'nvme',
          rotationRpm: unknown('UNSUPPORTED', 'sans objet pour un SSD'),
          partitionTable: 'GPT',
          removable: false,
          trimSupported: true,
          link: {
            currentSpeed: '16.0 GT/s PCIe',
            maxSpeed: '16.0 GT/s PCIe',
            currentWidth: 4,
            maxWidth: 4,
          },
          smart: {
            status: 'PASSED',
            temperatureCelsius: 51,
            powerOnHours: 18_240,
            powerCycles: 412,
            reallocatedSectors: unknown('UNSUPPORTED', 'attribut ATA sans équivalent NVMe'),
            pendingSectors: unknown('UNSUPPORTED'),
            uncorrectableErrors: 0,
            wearPercent: unknown('NOT_AVAILABLE'),
            nvmePercentageUsed: 87,
            availableSparePercent: 32,
            availableSpareThresholdPercent: 10,
            mediaErrors: 0,
            unsafeShutdowns: 3,
            dataUnitsRead: 286_114_552,
            dataUnitsWritten: 412_884_221,
          },
          partitions: [
            {
              name: '/dev/nvme0n1p2',
              uuid: 'b3e1f0a2-5c7d-4e8b-9a10-2f4c6d8e0b13',
              partitionUuid: '7c9e6679-7425-40de-944b-e07fc1f90ae7',
              mountPoint: '/',
              filesystem: 'ext4',
              sizeBytes: 100_000_000_000,
              usedBytes: 93_000_000_000,
              freeBytes: 7_000_000_000,
              usagePercent: 93,
              encrypted: false,
              encryptionType: unknown('UNSUPPORTED'),
            },
          ],
        },
      ],
      trimScheduled: false,
      pools: [
        {
          name: 'rpool',
          type: 'zfs',
          state: 'ONLINE',
          sizeBytes: 2_000_398_934_016,
          usedBytes: 812_000_000_000,
          members: ['/dev/sda', '/dev/sdb'],
          raidLevel: 'mirror',
          redundant: true,
        },
        {
          // Deux disques agrégés sans protection : la panne de l'un fait
          // perdre l'ensemble.
          name: 'md0',
          type: 'md',
          state: 'active',
          sizeBytes: 4_000_797_868_032,
          usedBytes: unknown('UNSUPPORTED'),
          members: ['/dev/sdc', '/dev/sdd'],
          raidLevel: 'raid0',
          redundant: false,
        },
      ],
      totalBytes: 3_000_603_820_032,
      usedBytes: 905_000_000_000,
    },
    network: {
      interfaces: [
        {
          name: 'enp4s0',
          manufacturer: 'Realtek Semiconductor Co., Ltd.',
          model: 'RTL8125 2.5GbE Controller',
          mac: '00:1a:2b:3c:4d:5e',
          type: 'ethernet',
          status: 'UP',
          speedMbps: 2500,
          duplex: 'FULL',
          mtu: 1500,
          driver: 'r8169',
          dhcp: false,
          ipv4: [{ address: '192.168.1.20', prefixLength: 24 }],
          ipv6: [{ address: 'fe80::21a:2bff:fe3c:4d5e', prefixLength: 64 }],
          gateway: '192.168.1.1',
        },
      ],
      dnsServers: ['192.168.1.1'],
      searchDomains: ['lan'],
      // Adresse de documentation (RFC 5737, TEST-NET-2) : une fixture ne porte
      // jamais une valeur réelle, fût-elle expurgée ensuite.
      publicIp: '198.51.100.7',
      // Deux interfaces portent une route par défaut : configuration légitime
      // en bascule, accidentelle la plupart du temps.
      routes: [
        { destination: 'default', gateway: '192.168.1.1', interface: 'enp4s0', metric: 100 },
        { destination: 'default', gateway: '192.168.2.1', interface: 'wlp3s0', metric: 600 },
        {
          destination: '192.168.1.0/24',
          gateway: unknown('UNSUPPORTED'),
          interface: 'enp4s0',
          metric: unknown('NOT_AVAILABLE'),
        },
      ],
      listeningPorts: [
        { protocol: 'tcp', port: 22, address: '0.0.0.0', process: 'sshd', exposed: true },
        { protocol: 'tcp', port: 8006, address: '0.0.0.0', process: 'pveproxy', exposed: true },
        { protocol: 'tcp', port: 5432, address: '127.0.0.1', process: 'postgres', exposed: false },
        // Lié à une interface précise : c'est ce cas-là, et non `0.0.0.0`, qui
        // réinscrit l'adresse LAN de la machine dans la liste des ports.
        //
        // Le port est choisi hors des valeurs que les tests de comparaison
        // ajoutent pour simuler un service nouvellement exposé : réutiliser
        // l'une d'elles ferait passer leur ajout pour un port déjà présent, et
        // le test échouerait pour une raison sans rapport avec ce qu'il vérifie.
        {
          protocol: 'tcp',
          port: 9100,
          address: '192.168.1.20',
          process: 'node_exporter',
          exposed: true,
        },
      ],
    },
    devices: {
      pci: [
        {
          bus: 'PCI',
          hardwareId: '10de:1f08',
          vendorId: '10de',
          deviceId: '1f08',
          vendor: 'NVIDIA Corporation',
          name: 'TU106 [GeForce RTX 2060 Rev. A]',
          class: 'VGA compatible controller',
          driver: 'nvidia',
          status: 'OK',
          address: '01:00.0',
          link: {
            currentSpeed: '2.5 GT/s PCIe',
            maxSpeed: '16.0 GT/s PCIe',
            currentWidth: 4,
            maxWidth: 16,
          },
        },
      ],
      usb: [],
      other: [],
    },
    software: {
      packages: [
        { name: 'openssh-server', version: '1:9.2p1-2', source: 'apt' },
        { name: 'pve-manager', version: '8.3.2', source: 'apt' },
      ],
      packageCount: 1284,
      packagesTruncated: true,
      packageManagers: [
        { name: 'apt', version: '2.6.1', packageCount: 1282 },
        { name: 'flatpak', version: '1.14.4', packageCount: 2 },
      ],
      runtimes: [
        { name: 'node', version: '22.11.0', path: '/usr/bin/node' },
        { name: 'python3', version: '3.11.2', path: '/usr/bin/python3' },
        // Un JDK 8 n'expose pas sa version sur stdout : elle reste inconnue.
        { name: 'java', version: unknown('UNKNOWN'), path: '/usr/bin/java' },
      ],
      services: [
        { name: 'ssh', state: 'RUNNING', startup: 'ENABLED' },
        { name: 'pveproxy', state: 'RUNNING', startup: 'ENABLED' },
        { name: 'smartmontools', state: 'FAILED', startup: 'ENABLED' },
      ],
    },
    startup: {
      items: [
        {
          name: 'ssh',
          kind: 'SERVICE',
          scope: 'SYSTEM',
          enabled: true,
          command: unknown('NOT_AVAILABLE'),
          location: 'systemd',
        },
        {
          name: 'pveproxy',
          kind: 'SERVICE',
          scope: 'SYSTEM',
          enabled: true,
          command: unknown('NOT_AVAILABLE'),
          location: 'systemd',
        },
      ],
    },
    drivers: [
      {
        device: unknown('NOT_AVAILABLE'),
        hardwareId: unknown('NOT_AVAILABLE'),
        vendor: unknown('NOT_AVAILABLE'),
        name: 'nvidia',
        version: '550.54.14',
        date: unknown('NOT_AVAILABLE'),
        provider: 'noyau Linux',
        signed: unknown('NOT_AVAILABLE'),
        infName: 'nvidia',
        // Établir qu'un module est à jour exigerait la version publiée en
        // amont, que le scanner n'interroge pas.
        status: 'UNKNOWN',
      },
    ],
    security: {
      firewall: {
        engine: 'nftables',
        state: 'DISABLED',
        defaultInputPolicy: 'accept',
        ruleCount: 0,
      },
      updates: {
        pending: 34,
        securityPending: 6,
        rebootRequired: true,
        lastCheck: '2026-07-25T04:00:00Z',
        lastUpdate: '2026-06-02T04:12:00Z',
        automaticUpdates: 'DISABLED',
      },
      secureBoot: 'DISABLED',
      accounts: [
        { name: 'root', admin: true, enabled: true, passwordless: false },
        { name: 'wnx', admin: true, enabled: true, passwordless: false },
      ],
      linux: {
        ssh: {
          installed: true,
          running: true,
          port: 22,
          permitRootLogin: 'yes',
          passwordAuthentication: true,
          pubkeyAuthentication: true,
          protocolVersion: '2',
        },
        // fail2ban installé mais arrêté : le cas que SEC-016 doit voir.
        intrusionPrevention: [
          { name: 'fail2ban', installed: true, running: false, activeJails: unknown('UNKNOWN') },
        ],
        apparmor: 'ENABLED',
        selinux: 'UNSUPPORTED',
        luks: { present: false, devices: [] },
        sudoUsers: 1,
        passwordlessAccounts: 0,
      },
      obsoleteProtocols: [],
    },
    virtualization: {
      podman: {
        version: '4.9.3',
        containers: [
          {
            name: 'registre',
            image: 'docker.io/library/registry:2',
            state: 'running',
            privileged: unknown('NOT_AVAILABLE'),
            networkMode: unknown('NOT_AVAILABLE'),
            publishedPorts: [],
            sensitiveMounts: [],
            dockerSocketMounted: unknown('UNSUPPORTED'),
          },
        ],
        networks: [],
      },
      libvirt: {
        version: '10.0.0',
        guests: [
          {
            name: 'vm-test',
            state: 'running',
            vcpus: 2,
            memoryBytes: 4_294_967_296,
            autostart: true,
          },
        ],
      },
      docker: {
        version: '27.3.1',
        containers: [
          {
            name: 'homeassistant',
            image: 'ghcr.io/home-assistant/home-assistant:stable',
            state: 'running',
            privileged: true,
            networkMode: 'host',
            publishedPorts: [],
            sensitiveMounts: ['/run/dbus'],
            dockerSocketMounted: false,
          },
        ],
        networks: [{ name: 'bridge', driver: 'bridge' }],
        volumeCount: 4,
      },
      proxmox: {
        version: 'pve-manager/8.3.2/1d1c4e1e',
        node: {
          name: 'pve-lab',
          kernel: '6.8.12-4-pve',
          uptimeSeconds: 1_209_600,
          cpuCores: 16,
          memoryTotalBytes: 34_359_738_368,
          memoryUsedBytes: 21_474_836_480,
        },
        cluster: { mode: 'STANDALONE', nodeCount: 1 },
        vms: [
          {
            vmid: 100,
            name: 'win11-test',
            status: 'stopped',
            cpuCores: 4,
            memoryBytes: 8_589_934_592,
            autostart: false,
            tags: ['lab'],
            networkInterfaces: [{ name: 'net0', bridge: 'vmbr0', model: 'virtio' }],
            disks: [{ name: 'scsi0', storage: 'local-lvm', sizeBytes: 68_719_476_736 }],
            machineType: 'q35',
            bios: 'ovmf',
          },
        ],
        containers: [
          {
            ctid: 200,
            name: 'nginx-proxy',
            status: 'running',
            cpuCores: 2,
            memoryBytes: 1_073_741_824,
            autostart: true,
            tags: ['prod'],
            networkInterfaces: [{ name: 'eth0', bridge: 'vmbr0', model: 'veth' }],
            rootfsBytes: 8_589_934_592,
            storage: 'local-lvm',
            unprivileged: true,
          },
        ],
        storages: [
          {
            name: 'local-lvm',
            type: 'lvmthin',
            status: 'active',
            totalBytes: 800_000_000_000,
            usedBytes: 412_000_000_000,
            availableBytes: 388_000_000_000,
            usagePercent: 51.5,
            shared: false,
            content: ['images', 'rootdir'],
          },
        ],
      },
    },
    monitoring: {
      startedAt: '2026-07-25T16:41:00Z',
      intervalMs: 1000,
      durationMs: 3000,
      // Charge soutenue sur toute la fenêtre : le cas que PRF-007 doit voir, et
      // qu'aucune règle fondée sur un instantané ne pourrait établir.
      samples: [
        {
          at: '2026-07-25T16:41:01Z',
          cpuUsagePercent: 92.4,
          cpuTemperatureCelsius: 78,
          memoryUsedBytes: 12_884_901_888,
          swapUsedBytes: 1_073_741_824,
          diskReadBytesPerSecond: 4_194_304,
          diskWriteBytesPerSecond: 12_582_912,
          networkRxBytesPerSecond: 131_072,
          networkTxBytesPerSecond: 65_536,
        },
        {
          at: '2026-07-25T16:41:02Z',
          cpuUsagePercent: 88.1,
          cpuTemperatureCelsius: 81,
          memoryUsedBytes: 12_952_010_752,
          swapUsedBytes: 1_073_741_824,
          diskReadBytesPerSecond: 2_097_152,
          diskWriteBytesPerSecond: 8_388_608,
          networkRxBytesPerSecond: 98_304,
          networkTxBytesPerSecond: 49_152,
        },
        {
          at: '2026-07-25T16:41:03Z',
          cpuUsagePercent: 95.7,
          cpuTemperatureCelsius: 83,
          memoryUsedBytes: 13_019_119_616,
          swapUsedBytes: 1_073_741_824,
          diskReadBytesPerSecond: 1_048_576,
          diskWriteBytesPerSecond: 16_777_216,
          networkRxBytesPerSecond: 143_360,
          networkTxBytesPerSecond: 71_680,
          cpuFrequencyMhz: 3_190,
          cpuThrottled: true,
        },
      ],
      // Les mêmes trois échantillons, résumés. Sur une observation longue les
      // échantillons sont tronqués et ce résumé devient la seule trace du pic.
      aggregates: {
        cpuUsagePercent: {
          current: 95.7,
          minimum: 88.1,
          maximum: 95.7,
          average: 92.07,
          unit: '%',
          sampleCount: 3,
          sampleIntervalMs: 1000,
          sampleDurationMs: 3000,
          source: '/proc/stat',
        },
        cpuTemperatureCelsius: {
          current: 83,
          minimum: 78,
          maximum: 83,
          average: 80.67,
          unit: '°C',
          sampleCount: 3,
          sampleIntervalMs: 1000,
          sampleDurationMs: 3000,
          source: '/sys/class/hwmon',
        },
        // Un seul relevé de fréquence : la statistique existe, mais elle ne
        // porte qu'un point — et le dit, plutôt que d'afficher une moyenne qui
        // aurait l'air d'en résumer trois.
        cpuFrequencyMhz: {
          current: 3_190,
          minimum: 3_190,
          maximum: 3_190,
          average: 3_190,
          unit: 'MHz',
          sampleCount: 1,
          sampleIntervalMs: 1000,
          sampleDurationMs: unknown('UNKNOWN', 'un seul relevé exploitable'),
          source: '/sys/devices/system/cpu',
        },
      },
    },
    benchmark: {
      startedAt: '2026-07-25T16:40:00Z',
      finishedAt: '2026-07-25T16:41:01Z',
      durationMs: 61_000,
      secondsPerTargetPlanned: 20,
      // La série relevée pendant les mesures, étiquetée par phase.
      //
      // Elle raconte la même machine que les résultats ci-dessous, et c'est
      // voulu : trois relevés au repos qui donnent la référence, puis une charge
      // soutenue où la fréquence retombe de 5 000 à 3 100 MHz pendant que la
      // température monte et que le noyau signale un bridage thermique. Le
      // score seul ne dirait rien de tout cela.
      telemetry: {
        intervalMs: 1000,
        samples: [
          {
            at: '2026-07-25T16:39:57Z',
            phase: 'idle',
            cpuUsagePercent: 3.1,
            cpuTemperatureCelsius: 41,
            cpuFrequencyMhz: 1_400,
            cpuPackagePowerWatts: 14.2,
            cpuFanRpm: 720,
            memoryUsedBytes: 8_589_934_592,
            swapUsedBytes: 1_073_741_824,
            diskReadBytesPerSecond: 0,
            diskWriteBytesPerSecond: 131_072,
            networkRxBytesPerSecond: 8_192,
            networkTxBytesPerSecond: 4_096,
          },
          {
            at: '2026-07-25T16:39:58Z',
            phase: 'idle',
            cpuUsagePercent: 2.4,
            cpuTemperatureCelsius: 42,
            cpuFrequencyMhz: 1_380,
            cpuPackagePowerWatts: 13.8,
            cpuFanRpm: 715,
            memoryUsedBytes: 8_590_000_000,
            swapUsedBytes: 1_073_741_824,
            diskReadBytesPerSecond: 0,
            diskWriteBytesPerSecond: 65_536,
            networkRxBytesPerSecond: 6_144,
            networkTxBytesPerSecond: 3_072,
          },
          {
            at: '2026-07-25T16:39:59Z',
            phase: 'idle',
            cpuUsagePercent: 4.0,
            cpuTemperatureCelsius: 42,
            cpuFrequencyMhz: 1_420,
            cpuPackagePowerWatts: 14.6,
            cpuFanRpm: 730,
            memoryUsedBytes: 8_591_000_000,
            swapUsedBytes: 1_073_741_824,
            diskReadBytesPerSecond: 0,
            diskWriteBytesPerSecond: 98_304,
            networkRxBytesPerSecond: 7_168,
            networkTxBytesPerSecond: 3_584,
          },
          ...SOAK_TELEMETRY,
          ...GAMING_TELEMETRY,
        ],
      },
      results: [
        {
          target: 'cpu-single',
          status: 'completed',
          startedAt: '2026-07-25T16:40:00Z',
          finishedAt: '2026-07-25T16:40:30Z',
          tool: 'openssl',
          protocolVersion: '1.0.0',
          toolVersion: '3.0.13',
          algorithm: 'AES-128-CBC',
          parameters: '-evp aes-128-cbc -seconds 20 -bytes 16384',
          durationMs: 30_400,
          score: 1738,
          unit: 'MiB/s',
          temperatureCelsius: 79,
          // Départ à froid, pic au milieu de la mesure : les trois valeurs
          // racontent une machine qui chauffe, ce que la seule valeur de fin
          // ne dirait pas.
          temperatureBeforeCelsius: 42,
          temperatureMaxCelsius: 84,
          // Bridage observé pendant la mesure : PRF-008 doit le voir.
          throttled: true,
        },
        {
          target: 'cpu-soak',
          status: 'completed',
          startedAt: '2026-07-25T16:40:35Z',
          finishedAt: '2026-07-25T16:50:35Z',
          tool: 'openssl',
          protocolVersion: '1.0.0',
          toolVersion: '3.0.13',
          algorithm: 'AES-128-CBC soutenu, 20 segment(s) de 30 s',
          parameters: '-evp aes-128-cbc -seconds 30 -bytes 16384 -multi 16',
          durationMs: 600_000,
          score: 1512,
          unit: 'MiB/s',
          temperatureCelsius: 88,
          temperatureBeforeCelsius: 45,
          temperatureMaxCelsius: 91,
          throttled: true,
        },
        {
          // Une carte mesurée, avec sa cadence scène par scène : c'est ce que
          // le score global cache. 300 images par seconde sur la scène
          // d'ombrage et 56 947 sur la scène de géométrie décrivent une carte
          // dont un usage précis s'effondre — la moyenne, elle, ne dit rien.
          target: 'gpu',
          status: 'completed',
          device: 'NVIDIA GeForce RTX 4070',
          startedAt: '2026-07-25T16:50:40Z',
          finishedAt: '2026-07-25T16:51:00Z',
          tool: 'glmark2',
          protocolVersion: '1.0.0',
          toolVersion: '2023.01',
          algorithm: 'rendu synthétique hors écran',
          parameters: '--off-screen',
          durationMs: 20_000,
          score: 23_093,
          unit: 'points',
          temperatureCelsius: 74,
          throttled: false,
          framesPerSecond: {
            current: 300,
            minimum: 300,
            maximum: 56_947,
            average: 23_093.7,
            unit: 'FPS',
            sampleCount: 3,
            sampleIntervalMs: unknown('NOT_APPLICABLE', 'une mesure par scène, non par intervalle'),
            sampleDurationMs: unknown('NOT_APPLICABLE', 'une mesure par scène, non par intervalle'),
            source: 'glmark2 --off-screen',
          },
          frameTimeMs: {
            current: 3.333,
            minimum: 0.018,
            maximum: 3.333,
            average: 1.145,
            unit: 'ms',
            sampleCount: 3,
            sampleIntervalMs: unknown('NOT_APPLICABLE', 'une mesure par scène, non par intervalle'),
            sampleDurationMs: unknown('NOT_APPLICABLE', 'une mesure par scène, non par intervalle'),
            source: 'glmark2 --off-screen',
          },
        },
        {
          target: 'gpu',
          status: 'skipped',
          detail: 'glmark2 absent : mesure GPU indisponible.',
          tool: 'glmark2',
          protocolVersion: '1.0.0',
          toolVersion: unknown('NOT_AVAILABLE'),
          algorithm: unknown('NOT_AVAILABLE'),
          parameters: unknown('NOT_AVAILABLE'),
          durationMs: unknown('NOT_AVAILABLE'),
          score: unknown('NOT_AVAILABLE', 'glmark2 absent : mesure GPU indisponible.'),
          unit: unknown('NOT_AVAILABLE'),
          temperatureCelsius: unknown('NOT_AVAILABLE'),
          throttled: unknown('NOT_AVAILABLE'),
        },
        {
          // Seconde carte : sans l'étiquette `device`, cette mesure passerait
          // pour un doublon de la première.
          target: 'gpu',
          status: 'completed',
          device: 'NVIDIA GeForce RTX 4070',
          startedAt: '2026-07-25T16:50:40Z',
          finishedAt: '2026-07-25T16:51:00Z',
          tool: 'glmark2',
          protocolVersion: '1.0.0',
          toolVersion: '2023.01',
          algorithm: 'rendu synthétique hors écran',
          parameters: '--off-screen DRI_PRIME=1',
          durationMs: 20_000,
          score: 4820,
          unit: 'points',
          temperatureCelsius: unknown('NOT_AVAILABLE'),
          throttled: unknown('NOT_AVAILABLE'),
          gpu: {
            utilizationPercent: 98,
            coreClockMhz: 2610,
            memoryClockMhz: 10_501,
            vramUsedBytes: 1_073_741_824,
            vramTotalBytes: 12_884_901_888,
            temperatureCelsius: 67,
            powerWatts: 185.4,
          },
        },
        {
          // La charge mixte : la carte et le processeur ensemble. Le score est
          // très en deçà de celui de la mesure `gpu` seule, et c'est
          // l'information — la machine ne tient pas les deux à la fois.
          target: 'gaming',
          status: 'completed',
          device: 'NVIDIA GeForce RTX 4070',
          startedAt: '2026-07-25T16:52:10Z',
          finishedAt: '2026-07-25T16:52:18Z',
          tool: 'glmark2 + openssl',
          protocolVersion: '1.0.0',
          toolVersion: '2023.01',
          algorithm: 'rendu synthétique hors écran sous charge AES-128-CBC',
          parameters:
            'glmark2 --off-screen -b build -b texture -b shading -b bump ; openssl speed -evp aes-128-cbc -multi 8',
          durationMs: 8_000,
          score: 14_820,
          unit: 'points',
          temperatureCelsius: 79,
          temperatureBeforeCelsius: 51,
          temperatureMaxCelsius: 81,
          throttled: false,
          // Les centiles bas viennent d'une mesure par trame, que seul un
          // collecteur capable de les compter peut produire. Ils décrivent une
          // machine dont la moyenne est correcte et dont le pire centième ne
          // l'est pas — la lecture que la moyenne efface.
          frameStability: {
            frameCount: 812,
            onePercentLowFps: 61,
            zeroPointOnePercentLowFps: 44,
            stutterCount: 7,
            stutterThresholdMs: 21.4,
            stutterRule: 'trame au-delà de 2× la médiane du rendu (10,7 ms)',
          },
        },
        {
          // La charge la plus exigeante n'a pas eu lieu : le banc d'essai s'est
          // arrêté avant. Elle reste publiée avec son motif — une mesure absente
          // et une mesure ratée ne se ressemblent que dans un rapport qui ne dit
          // ni l'une ni l'autre.
          target: 'cpu-gpu',
          status: 'skipped',
          detail:
            'arrêt de sécurité : 91 °C atteints pendant la charge précédente, au-delà du seuil publié par le capteur.',
          tool: 'glmark2 + openssl',
          protocolVersion: '1.0.0',
          toolVersion: unknown('NOT_AVAILABLE'),
          algorithm: unknown('NOT_AVAILABLE'),
          parameters: unknown('NOT_AVAILABLE'),
          durationMs: unknown('NOT_AVAILABLE'),
          score: unknown('NOT_AVAILABLE', 'charge non exécutée : arrêt de sécurité.'),
          unit: unknown('NOT_AVAILABLE'),
          temperatureCelsius: unknown('NOT_AVAILABLE'),
          throttled: unknown('NOT_AVAILABLE'),
        },
      ],
    },
    // Une machine qui tient debout mais pas sans grincer : un disque qui jette
    // des erreurs depuis trois semaines, un service qui boucle, une coupure
    // secteur. Chaque compteur porte sa fenêtre — sans elle, « 47 » ne veut
    // rien dire.
    stability: {
      uptimeSeconds: 3600,
      bootedAt: '2026-07-25T15:42:00Z',
      reboots: {
        count: 4,
        observationWindowMs: 2_592_000_000,
        lastAt: '2026-07-25T15:42:00Z',
        source: 'last reboot',
      },
      unexpectedShutdowns: {
        count: 1,
        observationWindowMs: 2_592_000_000,
        lastAt: '2026-07-12T03:17:44Z',
        source: 'journalctl --list-boots',
      },
      kernelCrashes: {
        count: 0,
        observationWindowMs: 2_592_000_000,
        lastAt: unknown('NOT_APPLICABLE', 'aucune panique sur la fenêtre'),
        source: 'journalctl -k -p emerg',
      },
      storageErrors: {
        count: 47,
        observationWindowMs: 1_814_400_000,
        lastAt: '2026-07-25T04:12:09Z',
        source: 'journalctl -k -p err',
      },
      serviceFailures: {
        count: 2,
        observationWindowMs: 2_592_000_000,
        lastAt: '2026-07-24T22:05:00Z',
        source: 'journalctl -u',
      },
      hardwareErrors: {
        count: unknown('NOT_AVAILABLE', 'ni rasdaemon ni EDAC sur cette machine'),
        observationWindowMs: unknown('NOT_AVAILABLE'),
        lastAt: unknown('NOT_AVAILABLE'),
        source: unknown('NOT_AVAILABLE'),
      },
      // Les compteurs ci-dessous valent **zéro**, et zéro est une mesure : le
      // collecteur Linux les produit tous depuis le journal normalisé
      // (`stability_incident_count`). Les omettre de la fixture faisait passer
      // pour non collectées des données que le scanner remonte, et privait de
      // test tout le chemin « compteur lu et sain ».
      filesystemErrors: {
        count: 0,
        observationWindowMs: 1_814_400_000,
        lastAt: unknown('NOT_APPLICABLE', 'aucune erreur sur la fenêtre'),
        source: 'journalctl -k -p err',
      },
      memoryPressureEvents: {
        count: 0,
        observationWindowMs: 1_814_400_000,
        lastAt: unknown('NOT_APPLICABLE', 'aucun manque de mémoire sur la fenêtre'),
        source: 'journalctl -k',
      },
      networkErrors: {
        count: 3,
        observationWindowMs: 1_814_400_000,
        lastAt: '2026-07-20T11:02:41Z',
        source: 'journalctl -k -p warning',
      },
      driverErrors: {
        count: 0,
        observationWindowMs: 1_814_400_000,
        lastAt: unknown('NOT_APPLICABLE', 'aucune erreur de module sur la fenêtre'),
        source: 'journalctl -k -p err',
      },
      applicationCrashes: {
        count: 2,
        observationWindowMs: 2_592_000_000,
        lastAt: '2026-07-23T19:44:12Z',
        source: 'coredumpctl list',
      },
      thermalEvents: {
        count: 0,
        observationWindowMs: 1_814_400_000,
        lastAt: unknown('NOT_APPLICABLE', 'aucun incident thermique sur la fenêtre'),
        source: 'journalctl -k',
      },
      failedUpdates: {
        count: 0,
        observationWindowMs: 2_592_000_000,
        lastAt: unknown('NOT_APPLICABLE', 'aucune mise à jour en échec sur la fenêtre'),
        source: 'journalctl -u apt-daily',
      },
      failedUnits: [
        {
          name: 'backup-nightly.service',
          state: 'failed',
          result: 'exit-code',
          since: '2026-07-24T22:05:00Z',
          restarts: 3,
        },
      ],
      stoppedUnits: [],
      coredumps: [
        {
          executable: 'firefox',
          signal: 'SIGSEGV',
          at: '2026-07-23T19:44:12Z',
          count: 2,
          present: false,
        },
      ],
      kernelTainted: 512,
      meta: {
        source: 'journalctl',
        method: 'commande shell',
        collectedAt: '2026-07-25T16:42:00Z',
        observationWindowMs: 2_592_000_000,
      },
    },
    boot: {
      phases: [
        { name: 'firmware', durationMs: 4_820_000 },
        { name: 'loader', durationMs: 3_100 },
        { name: 'kernel', durationMs: 2_940 },
        { name: 'initrd', durationMs: 1_780 },
        { name: 'userspace', durationMs: 18_400 },
      ],
      totalMs: 4_846_220,
      measuredAt: '2026-07-25T16:42:00Z',
      slowestItems: [
        { name: 'NetworkManager-wait-online.service', durationMs: 12_100, kind: 'unit' },
        { name: 'docker.service', durationMs: 4_300, kind: 'unit' },
      ],
      failedAtBoot: [
        {
          name: 'backup-nightly.service',
          state: 'failed',
          result: 'exit-code',
          since: '2026-07-25T15:42:31Z',
          restarts: unknown('UNKNOWN'),
        },
      ],
      firmwareMode: 'UEFI',
      // Notion propre à Windows : sous Linux, il n'y a rien à mesurer.
      fastStartupEnabled: unknown('NOT_APPLICABLE', 'notion sans objet sous Linux'),
      history: [
        { at: '2026-07-25T15:42:00Z', totalMs: 4_846_220 },
        { at: '2026-07-18T08:03:00Z', totalMs: 4_612_900 },
        { at: '2026-07-11T07:58:00Z', totalMs: 4_701_300 },
      ],
      // Le collecteur Linux énumère les noyaux installés et désigne le plus
      // récent selon le gestionnaire de paquets. Sans ces champs, la fixture
      // laissait `BOO-004` non évaluable alors que le scanner sait répondre.
      kernels: {
        running: '6.8.12-4-pve',
        installed: ['6.8.12-4-pve', '6.8.12-2-pve'],
        newestInstalled: '6.8.12-4-pve',
        source: 'dpkg-query',
      },
      meta: {
        source: 'systemd-analyze',
        method: 'commande shell',
        collectedAt: '2026-07-25T16:42:00Z',
      },
    },
    shutdown: {
      lastShutdownAt: '2026-07-25T15:41:12Z',
      lastShutdownWasClean: true,
      lastShutdownReason: 'systemd-shutdown: powering off',
      lastShutdownDurationMs: 9_400,
      slowestItems: [{ name: 'docker.service', durationMs: 6_200, kind: 'unit' }],
      meta: {
        source: 'journalctl --list-boots',
        method: 'commande shell',
        collectedAt: '2026-07-25T16:42:00Z',
      },
    },
    events: {
      window: {
        requestedMs: 7_776_000_000,
        // Demandé quatre-vingt-dix jours, obtenu vingt-et-un : le journal ne
        // remonte pas plus loin. Sans les deux valeurs, « rien avant » se
        // lirait comme « rien ».
        coveredMs: 1_814_400_000,
        since: '2026-07-04T16:42:00Z',
        until: '2026-07-25T16:42:00Z',
        persistent: true,
      },
      examined: 18_432,
      truncated: false,
      entries: [
        {
          category: 'STORAGE',
          severity: 'ERROR',
          provider: 'kernel',
          nativeId: 'ata3.00',
          firstSeenAt: '2026-07-04T22:31:07Z',
          lastSeenAt: '2026-07-25T04:12:09Z',
          occurrences: 47,
          summary: 'ata3.00: failed command: READ FPDMA QUEUED',
          fingerprint: 'ata-failed-command-read-fpdma',
          source: 'journalctl -k -p err',
          // Les lignes brutes, et non une copie du résumé : c'est là que le
          // journal met le nom du périphérique, le secteur et le contexte —
          // donc ce que la rédaction doit pouvoir retirer. Un extrait
          // identique au résumé ne protégerait rien une fois masqué.
          evidence: [
            'ata3.00: exception Emask 0x0 SAct 0x400000 SErr 0x0 action 0x0',
            'ata3.00: cmd 60/08:00:28:1f:b1/00:00:1d:00:00/40 tag 22 ncq dma 4096 in',
            'blk_update_request: I/O error, dev sda, sector 490037292 op 0x0:(READ)',
          ],
        },
        {
          category: 'POWER',
          severity: 'CRITICAL',
          provider: 'systemd-logind',
          nativeId: unknown('NOT_AVAILABLE', 'journald ne numérote pas les entrées'),
          firstSeenAt: '2026-07-12T03:17:44Z',
          lastSeenAt: '2026-07-12T03:17:44Z',
          occurrences: 1,
          summary: 'arrêt non propre détecté au démarrage suivant',
          fingerprint: 'unclean-shutdown',
          source: 'journalctl --list-boots',
        },
      ],
      meta: {
        source: 'journalctl',
        method: 'commande shell',
        collectedAt: '2026-07-25T16:42:00Z',
        observationWindowMs: 1_814_400_000,
      },
    },
    collection: {
      issues: [],
      skippedSections: ['drivers', 'firmware'],
      plannedSections: KNOWN_SECTIONS.filter((section) => section !== 'drivers'),
      knownSections: KNOWN_SECTIONS,
      // Un audit Poussée : le banc d'essai pèse plus que tout le reste réuni.
      // C'est attendu — il charge la machine volontairement — et c'est
      // précisément ce qu'une estimation par niveau doit savoir.
      timings: [
        { section: 'system', durationMs: 38 },
        { section: 'os', durationMs: 91 },
        { section: 'storage', durationMs: 5104 },
        { section: 'network', durationMs: 588 },
        { section: 'security', durationMs: 301 },
        { section: 'benchmark', durationMs: 182_450 },
      ],
      // Le rapport complet couvre l'autre bout : un audit `--install-deps` où
      // un outil a été installé et conservé, un autre refusé, et un troisième
      // dont l'installation a échoué. Les trois issues doivent traverser le
      // rendu sans qu'aucune ne se lise comme un problème de la machine.
      dependencies: [
        {
          tool: 'smartctl',
          package: 'smartmontools',
          outcome: 'PRESENT_BEFORE',
          version: 'smartctl 7.4 2023-08-01 r5530',
          unlocks: 'santé SMART et usure des disques',
          used: true,
          removal: 'NOT_APPLICABLE',
        },
        {
          tool: 'nvme',
          package: 'nvme-cli',
          outcome: 'INSTALLED',
          version: 'nvme version 2.8',
          method: 'apt-get install -y --no-install-recommends',
          unlocks: 'journal SMART NVMe étendu',
          used: true,
          removal: 'KEPT',
        },
        {
          tool: 'glmark2',
          package: 'glmark2',
          outcome: 'DECLINED',
          unlocks: 'mesure GPU du banc d’essai',
          used: false,
          removal: 'NOT_APPLICABLE',
        },
        {
          tool: 'sensors',
          package: 'lm-sensors',
          outcome: 'INSTALL_FAILED',
          method: 'apt-get install -y --no-install-recommends',
          unlocks: 'capteurs complémentaires',
          used: false,
          removal: 'NOT_APPLICABLE',
          error: 'E: Unable to locate package lm-sensors',
        },
      ],
      dependenciesInspected: true,
      provenance: {
        'audio.devices': {
          source: '/proc/asound/cards',
          method: 'lecture fichier',
          precision: 'carte',
          collectedAt: '2026-07-25T16:42:00Z',
        },
        'startup.items': {
          source: 'systemctl list-unit-files',
          method: 'commande shell',
          precision: 'service',
          collectedAt: '2026-07-25T16:42:00Z',
        },
      },
    },
  };
}
