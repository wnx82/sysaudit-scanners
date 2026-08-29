// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { unknown } from '@sysaudit/shared';
import { fullReport } from './fixtures.js';
import type { Report } from './report.js';

/**
 * Rapports de référence par **forme de machine**, et non par système.
 *
 * ## Ce que `fixtures-os.ts` ne couvre pas
 *
 * Les onze fixtures OS décrivent onze systèmes sur une seule machine : une tour
 * complète, avec capteurs, batterie, une carte graphique et un disque. C'est le
 * cas le plus favorable, et c'est le seul que la plupart des tests voient.
 *
 * Or les défauts que ce dépôt existe pour empêcher n'arrivent pas là. Ils
 * arrivent sur la machine **à laquelle il manque quelque chose** : un serveur
 * sans capteur thermique, une tour sans batterie, une machine virtuelle sans
 * matériel du tout. C'est là qu'un moteur d'analyse conclut d'une donnée
 * absente, et c'est là qu'aucune fixture ne l'attendait.
 *
 * ## Le principe de chaque forme
 *
 * Retirer, jamais ajouter. Chaque fixture part du rapport de référence et
 * **enlève** ce qu'une machine de cette forme n'a pas — en laissant le motif
 * d'absence quand le champ existe, et en supprimant la section quand elle
 * n'existe pas. Les deux cas ne se lisent pas pareil, et c'est précisément la
 * distinction que `read()` ramène au même cas côté moteur.
 */

export const SHAPE_FIXTURE_KEYS = [
  'sans-capteur',
  'sans-batterie',
  'portable',
  'tour',
  'machine-virtuelle',
  'multi-gpu',
  'valeurs-usine',
] as const;

export type ShapeFixtureKey = (typeof SHAPE_FIXTURE_KEYS)[number];

interface ShapeProfile {
  readonly label: string;
  /** Ce que cette forme éprouve, en une phrase. Sert aux messages de test. */
  readonly proves: string;
  readonly build: () => Report;
}

const PROFILES: Record<ShapeFixtureKey, ShapeProfile> = {
  /**
   * Un serveur en baie, dont le noyau n'expose aucune sonde.
   *
   * `sensors` **disparaît**, elle n'est pas vidée : une section absente et une
   * section vide ne disent pas la même chose. La première dit « rien n'a été
   * lu », la seconde « rien n'existe » — et un tableau de capteurs vide se lit
   * « cette machine n'a pas de sonde », ce qui est faux d'un serveur.
   */
  'sans-capteur': {
    label: 'Machine sans capteur thermique',
    proves: 'aucune température n’est déduite d’une section absente',
    build: () => {
      const report = fullReport();
      const { sensors: _sensors, ...rest } = report;
      return {
        ...rest,
        cpus: (report.cpus ?? []).map((cpu) => ({
          ...cpu,
          temperatureCelsius: unknown('NOT_AVAILABLE', 'aucune sonde exposée par le noyau'),
        })),
        gpus: (report.gpus ?? []).map((gpu) => ({
          ...gpu,
          temperatureCelsius: unknown('NOT_AVAILABLE', 'aucune sonde exposée par le pilote'),
        })),
      } as Report;
    },
  },

  /**
   * Une tour de bureau, qui n'a pas de batterie et n'en aura jamais.
   *
   * `NOT_APPLICABLE` et non `NOT_AVAILABLE` : ce n'est pas une lecture qui a
   * échoué, c'est une question qui ne se pose pas. Un score de santé batterie
   * calculé ici serait un défaut inventé sur une machine parfaite.
   */
  'sans-batterie': {
    label: 'Tour sans batterie',
    proves: 'aucune santé de batterie n’est calculée sur une machine qui n’en a pas',
    build: () => {
      const report = fullReport();
      return {
        ...report,
        system: { ...report.system, chassisType: 'Desktop' },
        power: {
          ...report.power,
          batteries: [],
          acConnected: true,
        },
      } as Report;
    },
  },

  /**
   * Un portable, avec ce qu'il a de particulier : une batterie usée, un châssis
   * mobile, un bloc secteur qui se déclare.
   *
   * La batterie est à 71 % de santé — au-dessus du seuil d'alerte et en dessous
   * du neuf. C'est la zone où un arrondi malheureux fait basculer un verdict.
   */
  portable: {
    label: 'Portable, batterie usée',
    proves: 'la santé batterie se calcule sans jamais dépasser 100 %',
    build: () => {
      const report = fullReport();
      const battery = report.power?.batteries?.[0];
      return {
        ...report,
        system: { ...report.system, chassisType: 'Notebook' },
        power: {
          ...report.power,
          batteries: [
            {
              ...battery,
              designCapacityWh: 56,
              fullChargeCapacityWh: 39.8,
              cycleCount: 612,
              chargePercent: 84,
            },
          ],
        },
      } as Report;
    },
  },

  /**
   * Une tour d'assemblage, dont le SMBIOS ne nomme ni constructeur ni modèle.
   *
   * C'est le cas le plus fréquent du parc de bureau, et celui où la résolution
   * visuelle doit refuser de conclure : il n'y a pas de modèle constructeur à
   * retrouver, seulement une carte mère.
   */
  tour: {
    label: 'Tour assemblée, sans modèle constructeur',
    proves: 'aucun visuel exact n’est attribué à une machine assemblée',
    build: () => {
      const report = fullReport();
      return {
        ...report,
        system: {
          ...report.system,
          chassisType: 'Tower',
          manufacturer: unknown('NOT_AVAILABLE', 'machine assemblée, SMBIOS non renseigné'),
          model: unknown('NOT_AVAILABLE', 'machine assemblée, SMBIOS non renseigné'),
        },
      } as Report;
    },
  },

  /**
   * Une machine virtuelle : pas de sonde, pas de batterie, pas de SMART, un
   * disque virtuel et une carte graphique émulée.
   *
   * Elle éprouve le cas où **presque tout** est légitimement absent. Un moteur
   * qui note cette machine sur ce qu'elle n'a pas la déclarerait en panne alors
   * qu'elle est conforme à ce qu'elle est.
   */
  'machine-virtuelle': {
    label: 'Machine virtuelle',
    proves: 'une machine sans matériel réel n’est pas notée sur ce qu’elle n’a pas',
    build: () => {
      const report = fullReport();
      const { sensors: _sensors, power: _power, ...rest } = report;
      const disk = report.storage?.disks?.[0];
      return {
        ...rest,
        system: {
          ...report.system,
          chassisType: 'Other',
          manufacturer: 'QEMU',
          model: 'Standard PC',
        },
        virtualization: { ...report.virtualization, runningUnder: 'kvm' },
        gpus: [
          {
            vendor: 'Red Hat',
            model: 'Virtio GPU',
            pciId: '1af4:1050',
            vramBytes: unknown('NOT_APPLICABLE', 'carte graphique émulée'),
            driver: 'virtio_gpu',
            driverVersion: unknown('NOT_AVAILABLE'),
            driverDate: unknown('NOT_AVAILABLE'),
            temperatureCelsius: unknown('NOT_APPLICABLE', 'carte graphique émulée'),
            usagePercent: unknown('NOT_AVAILABLE'),
            coreClockMhz: unknown('NOT_APPLICABLE', 'carte graphique émulée'),
            memoryClockMhz: unknown('NOT_APPLICABLE', 'carte graphique émulée'),
            displays: [],
          },
        ],
        storage: {
          ...report.storage,
          disks: [
            {
              ...disk,
              manufacturer: unknown('NOT_AVAILABLE'),
              model: 'QEMU HARDDISK',
              // Un disque virtuel n'a pas de SMART : la section disparaît, elle
              // n'est pas remplie de zéros.
              smart: undefined,
            },
          ],
        },
      } as Report;
    },
  },

  /**
   * Deux cartes graphiques, dont une intégrée.
   *
   * Le cas que le résumé système ne rendait pas : il n'affichait que la
   * première, avec un visuel unique, sous un titre qui ne disait pas laquelle.
   */
  'multi-gpu': {
    label: 'Deux cartes graphiques',
    proves: 'chaque carte a sa fiche et son visuel, aucune n’est écrasée',
    build: () => {
      const report = fullReport();
      const first = report.gpus?.[0];
      return {
        ...report,
        gpus: [
          {
            ...first,
            vendor: 'Intel',
            model: 'UHD Graphics 770',
            pciId: '8086:4680',
            vramBytes: unknown('NOT_APPLICABLE', 'mémoire partagée avec le système'),
            displays: [],
          },
          {
            ...first,
            vendor: 'NVIDIA',
            model: 'GeForce RTX 4070',
            pciId: 'PCI\\VEN_10DE&DEV_2786&SUBSYS_403B1458&REV_A1',
          },
        ],
      } as Report;
    },
  },

  /**
   * Les valeurs d'usine que les cartes mères publient telles quelles.
   *
   * `To Be Filled By O.E.M.`, `Default string`, `System manufacturer`,
   * `123456789`. Elles **ressemblent** à des mesures et n'en sont pas. Un
   * rapport qui les affiche fait chercher un fabricant nommé « Default
   * string » ; un catalogue qui les indexe crée une marque qui n'existe pas.
   */
  'valeurs-usine': {
    label: 'Valeurs d’usine non renseignées',
    proves: 'une valeur d’usine ne devient jamais une marque ni un modèle',
    build: () => {
      const report = fullReport();
      const module = report.memory?.modules?.[0];
      return {
        ...report,
        system: {
          ...report.system,
          manufacturer: 'System manufacturer',
          model: 'System Product Name',
          serialNumber: 'To Be Filled By O.E.M.',
        },
        motherboard: {
          ...report.motherboard,
          manufacturer: 'ASUSTeK COMPUTER INC.',
          model: 'PRIME B550M-A',
          serialNumber: 'Default string',
        },
        memory: {
          ...report.memory,
          modules: [
            {
              ...module,
              manufacturer: 'Unknown',
              partNumber: 'Default string',
              serialNumber: '00000000',
            },
          ],
        },
      } as Report;
    },
  },
};

export function shapeFixtureLabel(key: ShapeFixtureKey): string {
  return PROFILES[key].label;
}

/** Ce que cette forme éprouve, en une phrase. */
export function shapeFixtureProves(key: ShapeFixtureKey): string {
  return PROFILES[key].proves;
}

/**
 * Rapport de référence pour une forme de machine.
 *
 * Chaque forme reçoit une identité distincte, pour la même raison que les
 * fixtures OS : deux rapports partageant une identité seraient fusionnés par
 * l'empreinte machine, et les tests d'historique deviendraient faux.
 */
export function shapeFixture(key: ShapeFixtureKey): Report {
  const report = PROFILES[key].build();
  return {
    ...report,
    system: {
      ...report.system,
      hostname: `forme-${key}`,
      uuid: `00000000-0000-4000-9000-${key
        .replace(/[^a-z0-9]/g, '')
        .slice(0, 12)
        .padEnd(12, '0')}`,
      serialNumber: `SN-${key.toUpperCase()}`,
    },
  } as Report;
}

/** Toutes les formes, dans l'ordre déclaré. */
export function shapeFixtures(): {
  key: ShapeFixtureKey;
  label: string;
  proves: string;
  report: Report;
}[] {
  return SHAPE_FIXTURE_KEYS.map((key) => ({
    key,
    label: shapeFixtureLabel(key),
    proves: shapeFixtureProves(key),
    report: shapeFixture(key),
  }));
}
