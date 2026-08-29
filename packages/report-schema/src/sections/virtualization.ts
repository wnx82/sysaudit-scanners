// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { z } from 'zod';
import {
  byteSize,
  durationMs,
  isoDateTime,
  maybe,
  mediumText,
  percent,
  positiveInt,
  shortText,
} from '../primitives.js';

/**
 * Conteneur Docker (§29).
 *
 * Les variables d'environnement ne sont **jamais** exportées : elles
 * contiennent presque toujours des secrets. Seuls des indicateurs de
 * configuration à risque sont collectés.
 */
export const dockerContainerSchema = z.object({
  name: shortText,
  image: maybe(shortText),
  state: maybe(shortText),
  /** Un conteneur privilégié dispose de capacités équivalentes à l'hôte. */
  privileged: maybe(z.boolean()),
  /** `network_mode: host` supprime l'isolation réseau. */
  networkMode: maybe(shortText),
  publishedPorts: z
    .array(
      z.object({
        hostPort: z.number().int().min(0).max(65535),
        containerPort: z.number().int().min(0).max(65535),
        protocol: maybe(shortText),
        /** Adresse d'écoute côté hôte : détermine l'exposition réelle. */
        hostAddress: maybe(shortText),
      }),
    )
    .max(256)
    .default([]),
  /** Montages jugés sensibles (`/`, `/etc`, `/var/run/docker.sock`). */
  sensitiveMounts: z.array(shortText).max(64).default([]),
  /** Le socket Docker est monté dans le conteneur : équivaut à un accès root hôte. */
  dockerSocketMounted: maybe(z.boolean()),
});

export const dockerSchema = z.object({
  version: maybe(shortText),
  containers: z.array(dockerContainerSchema).max(1000).default([]),
  networks: z
    .array(
      z.object({
        name: shortText,
        driver: maybe(shortText),
      }),
    )
    .max(256)
    .default([]),
  volumeCount: maybe(positiveInt).optional(),
});

const guestCommon = {
  name: maybe(shortText),
  status: maybe(shortText),
  cpuCores: maybe(positiveInt),
  memoryBytes: maybe(byteSize),
  autostart: maybe(z.boolean()),
  tags: z.array(shortText).max(64).default([]),
  networkInterfaces: z
    .array(
      z.object({
        name: shortText,
        bridge: maybe(shortText),
        model: maybe(shortText),
      }),
    )
    .max(32)
    .default([]),
};

export const proxmoxVmSchema = z.object({
  vmid: positiveInt,
  ...guestCommon,
  disks: z
    .array(
      z.object({
        name: shortText,
        storage: maybe(shortText),
        sizeBytes: maybe(byteSize),
      }),
    )
    .max(64)
    .default([]),
  machineType: maybe(shortText),
  bios: maybe(shortText),
});

export const proxmoxLxcSchema = z.object({
  ctid: positiveInt,
  ...guestCommon,
  rootfsBytes: maybe(byteSize),
  storage: maybe(shortText),
  unprivileged: maybe(z.boolean()),
});

export const proxmoxStorageSchema = z.object({
  name: shortText,
  type: shortText,
  /** `active`, `available`, `disabled` tel que rapporté par `pvesm`. */
  status: maybe(shortText),
  totalBytes: maybe(byteSize),
  usedBytes: maybe(byteSize),
  availableBytes: maybe(byteSize),
  usagePercent: maybe(percent),
  shared: maybe(z.boolean()),
  content: z.array(shortText).max(16).default([]),
});

/**
 * Tâche Proxmox terminée en erreur.
 *
 * Une sauvegarde qui échoue toutes les nuits depuis trois semaines est le
 * genre de fait qu'aucun inventaire ne montre : l'hôte va bien, les invités
 * tournent, et il n'y a pourtant plus de sauvegarde exploitable.
 */
export const proxmoxTaskSchema = z.object({
  /** `vzdump`, `qmigrate`, `replication`, `qmstart`… tel que Proxmox le nomme. */
  type: shortText,
  /** Invité concerné, quand la tâche en vise un. */
  target: maybe(shortText),
  startedAt: maybe(isoDateTime),
  /** Statut natif (`OK`, `ERROR: …`), non traduit et tronqué. */
  status: maybe(mediumText),
  durationMs: maybe(durationMs),
});

/**
 * Santé d'un sous-système facultatif de l'hôte (Ceph, réplication, HA).
 *
 * `present: false` ne vaut pas `dégradé`. Une grappe sans Ceph n'a pas un Ceph
 * en panne : elle n'a pas de Ceph, et le reste des champs porte alors
 * `NOT_APPLICABLE`. C'est le critère explicite de l'étape 5 du chantier.
 */
export const proxmoxSubsystemSchema = z.object({
  present: z.boolean(),
  /** État natif (`HEALTH_OK`, `HEALTH_WARN`, `active`), non interprété. */
  health: maybe(shortText),
  detail: maybe(mediumText),
  /** Nombre d'éléments en défaut, quand la source le donne. */
  degraded: maybe(positiveInt),
});

export const proxmoxSchema = z.object({
  version: maybe(shortText),
  node: z.object({
    name: maybe(shortText),
    kernel: maybe(shortText),
    uptimeSeconds: maybe(positiveInt),
    cpuCores: maybe(positiveInt),
    memoryTotalBytes: maybe(byteSize),
    memoryUsedBytes: maybe(byteSize),
  }),
  cluster: z.object({
    mode: z.enum(['STANDALONE', 'CLUSTER', 'UNKNOWN']),
    name: maybe(shortText).optional(),
    nodeCount: maybe(positiveInt).optional(),
    quorate: maybe(z.boolean()).optional(),
  }),
  vms: z.array(proxmoxVmSchema).max(2000).default([]),
  containers: z.array(proxmoxLxcSchema).max(2000).default([]),
  storages: z.array(proxmoxStorageSchema).max(256).default([]),

  /**
   * Services propres à Proxmox actuellement en échec (`pve-cluster`,
   * `pvestatd`, `corosync`, `pvescheduler`…).
   *
   * Ils sont nommés séparément des unités systemd générales : un `pvestatd`
   * arrêté rend toute l'interface Proxmox aveugle sans qu'aucun invité ne
   * s'arrête, et le noyer parmi deux cents unités le rendrait invisible.
   */
  failedServices: z.array(shortText).max(64).optional(),

  /** Tâches terminées en erreur, les plus récentes d'abord. */
  failedTasks: z.array(proxmoxTaskSchema).max(100).optional(),
  /** Dernière sauvegarde `vzdump` observée, réussie ou non. */
  lastBackup: proxmoxTaskSchema.optional(),
  /** Fenêtre couverte par la lecture des tâches — indissociable de leur compte. */
  taskWindowMs: maybe(durationMs).optional(),

  ceph: proxmoxSubsystemSchema.optional(),
  replication: proxmoxSubsystemSchema.optional(),
  highAvailability: proxmoxSubsystemSchema.optional(),
});

/**
 * Invité libvirt / KVM / QEMU hébergé par cette machine.
 *
 * Distinct de `runningUnder`, qui dit sur quel hyperviseur *cette* machine
 * tourne : ici, ce sont les machines qu'elle **héberge**.
 */
export const libvirtGuestSchema = z.object({
  name: shortText,
  state: maybe(shortText),
  vcpus: maybe(positiveInt),
  memoryBytes: maybe(byteSize),
  autostart: maybe(z.boolean()),
});

export const libvirtSchema = z.object({
  version: maybe(shortText),
  guests: z.array(libvirtGuestSchema).max(500).default([]),
});

/**
 * Machine virtuelle Hyper-V hébergée par cette machine.
 *
 * Même forme qu'un invité libvirt, et pour la même raison qu'entre Docker et
 * Podman : ce sont deux hyperviseurs de type 1 qui exposent les mêmes faits —
 * un nom, un état, des cœurs, de la mémoire, un démarrage automatique. La forme
 * est répétée plutôt que partagée, car les deux sources peuvent diverger : un
 * invité Hyper-V a une génération, un invité libvirt a une architecture émulée.
 */
export const hypervGuestSchema = z.object({
  name: shortText,
  state: maybe(shortText),
  vcpus: maybe(positiveInt),
  memoryBytes: maybe(byteSize),
  autostart: maybe(z.boolean()),
});

export const hypervSchema = z.object({
  /**
   * Hyper-V ne publie pas de version distincte de celle de Windows : le champ
   * porte donc la version du système, ou un marqueur.
   */
  version: maybe(shortText),
  guests: z.array(hypervGuestSchema).max(500).default([]),
});

export const virtualizationSchema = z.object({
  /** Hyperviseur sur lequel *cette* machine s'exécute, si elle est virtualisée. */
  runningUnder: maybe(shortText).optional(),
  docker: dockerSchema.optional(),
  /**
   * Podman. Son interface en ligne de commande est compatible avec celle de
   * Docker : la même forme décrit donc les deux, plutôt qu'un schéma jumeau qui
   * divergerait à la première évolution.
   */
  podman: dockerSchema.optional(),
  libvirt: libvirtSchema.optional(),
  /** Machines virtuelles hébergées par un hôte Hyper-V (scanner Windows). */
  hyperv: hypervSchema.optional(),
  proxmox: proxmoxSchema.optional(),
});

export type DockerContainer = z.infer<typeof dockerContainerSchema>;
export type Docker = z.infer<typeof dockerSchema>;
export type Proxmox = z.infer<typeof proxmoxSchema>;
export type ProxmoxVm = z.infer<typeof proxmoxVmSchema>;
export type ProxmoxLxc = z.infer<typeof proxmoxLxcSchema>;
export type ProxmoxTask = z.infer<typeof proxmoxTaskSchema>;
export type ProxmoxSubsystem = z.infer<typeof proxmoxSubsystemSchema>;
export type Virtualization = z.infer<typeof virtualizationSchema>;
export type LibvirtGuest = z.infer<typeof libvirtGuestSchema>;
export type HypervGuest = z.infer<typeof hypervGuestSchema>;
export type Hyperv = z.infer<typeof hypervSchema>;
