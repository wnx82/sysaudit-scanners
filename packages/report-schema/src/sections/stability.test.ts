// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { unknown } from '@sysaudit/shared';
import { describe, expect, it } from 'vitest';
import { fullReport, minimalReport } from '../fixtures.js';
import { validateReport } from '../validate.js';
import { bootSchema, incidentCountSchema, stabilitySchema } from './stability.js';
import { eventsSchema, normalizedEventSchema } from './events.js';
import { monitoringSchema } from './monitoring.js';
import { capabilitiesSchema } from './meta.js';

/**
 * Le chantier « Cross-Platform Insight » ajoute quatre sections d'historique.
 * Ces tests fixent les deux promesses qui les rendent utilisables : un ancien
 * rapport reste lisible, et une donnée absente ne devient jamais un zéro.
 */

describe('compatibilité avec les rapports antérieurs', () => {
  it('accepte un rapport sans aucune des nouvelles sections', () => {
    const legacy = minimalReport();
    expect(legacy.stability).toBeUndefined();
    expect(legacy.boot).toBeUndefined();
    expect(legacy.shutdown).toBeUndefined();
    expect(legacy.events).toBeUndefined();

    const result = validateReport(legacy);
    expect(result.ok, result.ok ? '' : JSON.stringify(result.issues)).toBe(true);
  });

  it('accepte un échantillon d’observation produit avant l’ajout de la fréquence', () => {
    const legacySample = {
      startedAt: '2026-07-25T16:41:00Z',
      intervalMs: 1000,
      durationMs: 3000,
      samples: [
        {
          at: '2026-07-25T16:41:01Z',
          cpuUsagePercent: 12,
          cpuTemperatureCelsius: 44,
          memoryUsedBytes: 1024,
          swapUsedBytes: 0,
          diskReadBytesPerSecond: 0,
          diskWriteBytesPerSecond: 0,
          networkRxBytesPerSecond: 0,
          networkTxBytesPerSecond: 0,
        },
      ],
    };
    expect(monitoringSchema.safeParse(legacySample).success).toBe(true);
  });

  it('accepte un rapport dont les capacités ne déclarent aucune fonctionnalité', () => {
    const legacyCapabilities = {
      platform: 'linux',
      architecture: 'x86_64',
      privileged: false,
      proxmox: false,
      docker: false,
      tools: {},
    };
    const parsed = capabilitiesSchema.safeParse(legacyCapabilities);
    expect(parsed.success).toBe(true);
    expect(parsed.success && parsed.data.features).toBeUndefined();
  });

  it('valide le rapport complet, nouvelles sections comprises', () => {
    const result = validateReport(fullReport());
    expect(result.ok, result.ok ? '' : JSON.stringify(result.issues)).toBe(true);
    expect(result.ok && result.report.events?.entries).toHaveLength(2);
  });
});

describe('compteur d’incidents', () => {
  it('distingue « aucun incident » de « pas pu regarder »', () => {
    const observed = incidentCountSchema.parse({
      count: 0,
      observationWindowMs: 86_400_000,
      lastAt: unknown('NOT_APPLICABLE'),
      source: 'journalctl',
    });
    const blind = incidentCountSchema.parse({
      count: unknown('PERMISSION_DENIED'),
      observationWindowMs: unknown('PERMISSION_DENIED'),
      lastAt: unknown('PERMISSION_DENIED'),
      source: 'journalctl',
    });

    expect(observed.count).toBe(0);
    expect(blind.count).not.toBe(0);
    expect(blind.count).toEqual({ unknown: true, reason: 'PERMISSION_DENIED' });
  });

  it('refuse un compteur négatif', () => {
    expect(incidentCountSchema.safeParse({ count: -1 }).success).toBe(false);
  });
});

describe('stabilité', () => {
  /**
   * Une section présente doit **dire** ce qu'elle n'a pas mesuré. Omettre le
   * champ rendrait « pas tenté » et « tenté sans succès » indiscernables — la
   * confusion exacte que le marqueur existe pour éviter.
   */
  it('refuse une section qui tait ce qu’elle n’a pas mesuré', () => {
    expect(stabilitySchema.safeParse({}).success).toBe(false);
  });

  it('accepte une section qui déclare chacune de ses absences', () => {
    const parsed = stabilitySchema.safeParse({
      uptimeSeconds: 3600,
      bootedAt: unknown('UNKNOWN'),
      kernelTainted: unknown('NOT_APPLICABLE', 'notion propre au noyau Linux'),
    });
    expect(parsed.success, JSON.stringify(parsed.success ? null : parsed.error.issues)).toBe(true);
    // Les compteurs non tentés restent absents ; le parsing n'en fabrique aucun.
    expect(parsed.success && parsed.data.kernelCrashes).toBeUndefined();
    expect(parsed.success && parsed.data.failedUnits).toEqual([]);
  });

  it('conserve la valeur brute de `tainted` sans la décomposer', () => {
    const parsed = stabilitySchema.parse({
      uptimeSeconds: unknown('UNKNOWN'),
      bootedAt: unknown('UNKNOWN'),
      kernelTainted: 512,
    });
    expect(parsed.kernelTainted).toBe(512);
  });
});

describe('démarrage', () => {
  const absentBoot = {
    totalMs: unknown('UNSUPPORTED', 'systemd-analyze absent'),
    measuredAt: unknown('UNSUPPORTED'),
    firmwareMode: unknown('UNKNOWN'),
    fastStartupEnabled: unknown('NOT_APPLICABLE', 'notion sans objet hors Windows'),
  };

  it('accepte un découpage natif partiel', () => {
    const parsed = bootSchema.parse({
      ...absentBoot,
      phases: [{ name: 'kernel', durationMs: 2940 }],
    });
    expect(parsed.phases).toHaveLength(1);
    expect(parsed.totalMs).toEqual({
      unknown: true,
      reason: 'UNSUPPORTED',
      detail: 'systemd-analyze absent',
    });
  });

  it('refuse une durée de démarrage aberrante', () => {
    expect(bootSchema.safeParse({ ...absentBoot, totalMs: -1 }).success).toBe(false);
  });
});

describe('événements normalisés', () => {
  it('refuse un incident à zéro occurrence : un incident compté a eu lieu', () => {
    const base = {
      category: 'STORAGE',
      severity: 'ERROR',
      provider: 'kernel',
      nativeId: unknown('NOT_AVAILABLE'),
      firstSeenAt: unknown('UNKNOWN'),
      lastSeenAt: unknown('UNKNOWN'),
      occurrences: 0,
      summary: 'ata3.00: failed command',
      fingerprint: 'ata-failed',
      source: 'journalctl',
    };
    expect(normalizedEventSchema.safeParse(base).success).toBe(false);
    expect(normalizedEventSchema.safeParse({ ...base, occurrences: 1 }).success).toBe(true);
  });

  it('borne la preuve brute à trois extraits', () => {
    const withEvidence = (count: number) =>
      normalizedEventSchema.safeParse({
        category: 'STORAGE',
        severity: 'ERROR',
        provider: 'kernel',
        nativeId: unknown('NOT_AVAILABLE'),
        firstSeenAt: unknown('UNKNOWN'),
        lastSeenAt: unknown('UNKNOWN'),
        occurrences: 1,
        summary: 'erreur',
        fingerprint: 'f',
        source: 'journalctl',
        evidence: Array.from({ length: count }, (_, index) => `ligne ${index}`),
      });
    expect(withEvidence(3).success).toBe(true);
    expect(withEvidence(4).success).toBe(false);
  });

  it('sépare la fenêtre demandée de la fenêtre réellement couverte', () => {
    const parsed = eventsSchema.parse({
      window: {
        requestedMs: 7_776_000_000,
        coveredMs: 172_800_000,
        since: unknown('UNKNOWN'),
        until: unknown('UNKNOWN'),
        persistent: false,
      },
      examined: unknown('NOT_AVAILABLE'),
      truncated: false,
      entries: [],
    });
    expect(parsed.window.requestedMs).not.toBe(parsed.window.coveredMs);
    expect(parsed.window.persistent).toBe(false);
  });
});
