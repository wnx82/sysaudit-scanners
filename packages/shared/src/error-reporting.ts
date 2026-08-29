// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { SECRET_PATTERNS } from './secrets.js';

/**
 * Remontée d'erreurs vers un collecteur compatible Sentry (GlitchTip).
 *
 * **Aucune dépendance, et aucune importation de `node:`** — ce module tourne
 * aussi dans le navigateur. C'est pourquoi il est exporté par un chemin dédié
 * (`@sysaudit/shared/error-reporting`) plutôt que par l'index du paquet, qui
 * tire `node:crypto` et ferait échouer le paquet du navigateur.
 *
 * Le protocole d'enveloppe Sentry tient en une trentaine de lignes ; le SDK
 * officiel apporterait quelques dizaines de dépendances transitives et la
 * surface d'audit qui va avec — celle-là même qu'on vient de ramener à zéro.
 *
 * Quatre décisions gouvernent ce fichier, et elles portent toutes sur ce qui
 * **ne** part **pas**.
 *
 * **Aucune donnée d'audit ne quitte le serveur.** Un rapport SysAudit décrit une
 * machine réelle : nom d'hôte, numéros de série, disques, réseau. Rien de tout
 * cela n'a sa place dans un collecteur d'erreurs, fût-il auto-hébergé. Ne
 * partent que le type de l'erreur, son message, sa pile, et des étiquettes
 * courtes et déclarées.
 *
 * **Le gabarit de route, jamais l'URL.** `/api/v1/reports/:id` et non
 * `/api/v1/reports/a1b2c3` : un identifiant public de rapport désigne une
 * machine, et le faire figurer dans un outil tiers reviendrait à y signaler son
 * existence.
 *
 * **Tout texte sortant passe par la détection de secrets** déjà utilisée à
 * l'ingestion. Un message d'erreur qui contient une chaîne de connexion est un
 * cas banal, et c'est exactement ce qu'on ne veut pas archiver.
 *
 * **Un envoi qui échoue ne fait échouer personne.** Une panne du collecteur ne
 * doit pas transformer une erreur en deux.
 */

/** Adresse d'ingestion dérivée d'un DSN. */
export interface Dsn {
  /** Origine du collecteur — utile à la politique de sécurité du contenu. */
  readonly origin: string;
  /** Adresse complète de l'enveloppe, paramètres d'authentification compris. */
  readonly endpoint: string;
  readonly projectId: string;
}

/**
 * Analyse un DSN `protocole://cle@hote[:port]/projet`.
 *
 * Rend `null` plutôt que de lever : un DSN absent est le cas normal — la
 * remontée d'erreurs est facultative — et un DSN mal formé ne doit pas empêcher
 * l'application de démarrer.
 */
export function parseDsn(dsn: string | undefined | null): Dsn | null {
  if (dsn === undefined || dsn === null || dsn.trim() === '') return null;

  try {
    const parsed = new URL(dsn.trim());
    const publicKey = parsed.username;
    const projectId = parsed.pathname.replace(/^\/+/, '');
    if (publicKey === '' || projectId === '' || !/^\d+$/.test(projectId)) return null;

    const origin = `${parsed.protocol}//${parsed.host}`;
    const parameters = new URLSearchParams({
      sentry_key: publicKey,
      sentry_version: '7',
      sentry_client: 'sysaudit/1',
    });

    return {
      origin,
      projectId,
      endpoint: `${origin}/api/${projectId}/envelope/?${parameters.toString()}`,
    };
  } catch {
    return null;
  }
}

/** Longueur au-delà de laquelle un texte sortant est tronqué. */
const MAX_TEXT = 2000;
/** Nombre de cadres de pile conservés. Au-delà, on n'apprend plus rien. */
const MAX_FRAMES = 40;

/**
 * Masque ce qui ressemble à un secret, et tronque.
 *
 * Les motifs sont ceux de l'ingestion : ce qui est refusé à l'entrée d'un
 * rapport n'a pas davantage sa place dans un collecteur d'erreurs.
 */
export function redactOutgoingText(value: string): string {
  let redacted = value;
  for (const { pattern } of SECRET_PATTERNS) {
    // Les motifs du dépôt ne portent pas le drapeau global : on le rajoute pour
    // masquer toutes les occurrences, et non seulement la première.
    redacted = redacted.replace(new RegExp(pattern.source, `${pattern.flags}g`), '[secret masqué]');
  }

  // Aucune règle supplémentaire ici, et c'est délibéré : `SECRET_PATTERNS` est
  // la seule définition de ce qui compte comme un secret dans ce dépôt, et
  // couvre déjà les chaînes de connexion. En ajouter une seconde définition
  // ferait diverger les deux — l'ingestion refuserait ce que la remontée
  // laisserait passer, ou l'inverse.
  //
  // Le masquage emporte l'hôte en même temps que les identifiants
  // (`postgresql://…@10.0.0.1:5432/base` disparaît entièrement). C'est une perte
  // de diagnosticabilité assumée : mieux vaut une erreur qu'on doit corréler aux
  // journaux qu'un mot de passe archivé dans un collecteur.
  return redacted.length > MAX_TEXT ? `${redacted.slice(0, MAX_TEXT)}…` : redacted;
}

export type ErrorLevel = 'fatal' | 'error' | 'warning';

export interface ErrorReport {
  readonly error: unknown;
  /**
   * Gabarit de route, jamais l'URL concrète : `/api/v1/reports/:id`.
   */
  readonly transaction?: string | undefined;
  readonly level?: ErrorLevel | undefined;
  /**
   * Étiquettes courtes. Valeurs masquées et tronquées comme le reste — mais le
   * bon réflexe reste de n'y mettre que des valeurs closes (`GET`, `500`), pas
   * des données venues d'une requête.
   */
  readonly tags?: Readonly<Record<string, string>> | undefined;
}

export type CaptureOutcome = 'sent' | 'skipped' | 'failed';

export interface ErrorReporter {
  /** Faux lorsque aucun DSN n'est configuré : c'est le défaut. */
  readonly enabled: boolean;
  /** Origine du collecteur, ou `null`. La CSP en a besoin. */
  readonly origin: string | null;
  capture(report: ErrorReport): Promise<CaptureOutcome>;
}

interface StackFrame {
  readonly filename: string;
  readonly function: string;
  readonly lineno?: number;
  readonly colno?: number;
}

/**
 * Découpe une pile d'appels.
 *
 * Volontairement tolérant : les formats varient entre V8, les navigateurs et
 * les sources compilées. Une ligne non reconnue est conservée telle quelle
 * plutôt que perdue — une pile approximative vaut mieux qu'une pile absente.
 */
export function parseStack(stack: string | undefined): StackFrame[] {
  if (stack === undefined) return [];

  const frames: StackFrame[] = [];
  for (const line of stack.split('\n').slice(1)) {
    const trimmed = line.trim();
    if (trimmed === '') continue;

    const match = /^at\s+(?:(.+?)\s+\()?(.+?):(\d+):(\d+)\)?$/.exec(trimmed);
    if (match === null) {
      frames.push({ filename: redactOutgoingText(trimmed), function: '?' });
      continue;
    }
    frames.push({
      filename: redactOutgoingText(match[2]!),
      function: match[1] ?? '?',
      lineno: Number.parseInt(match[3]!, 10),
      colno: Number.parseInt(match[4]!, 10),
    });
  }

  // Sentry attend les cadres du plus ancien au plus récent.
  return frames.slice(0, MAX_FRAMES).reverse();
}

/** Ce qu'on sait dire d'une valeur levée qui n'est pas une `Error`. */
function describe(error: unknown): { type: string; value: string; stack: string | undefined } {
  if (error instanceof Error) {
    return { type: error.name || 'Error', value: error.message, stack: error.stack };
  }
  if (typeof error === 'string') return { type: 'Error', value: error, stack: undefined };
  return {
    type: 'Error',
    value: `Valeur levée non exploitable : ${typeof error}`,
    stack: undefined,
  };
}

export interface ReporterOptions {
  readonly dsn?: string | undefined;
  readonly environment: string;
  /** `sysaudit@0.50.0` — permet de rattacher une erreur à une version. */
  readonly release: string;
  readonly platform: 'node' | 'javascript';
  /** Distingue l'API du site dans le collecteur. */
  readonly serverName?: string | undefined;
  readonly fetchImpl?: typeof globalThis.fetch | undefined;
  readonly now?: (() => Date) | undefined;
  readonly eventId?: (() => string) | undefined;
  /** Prévenu quand un envoi échoue. Ne doit pas lever. */
  readonly onFailure?: ((reason: string) => void) | undefined;
  /** Au-delà, l'envoi est abandonné : un collecteur lent ne retarde rien. */
  readonly timeoutMs?: number | undefined;
  /** Échecs consécutifs au-delà desquels la remontée se met en veille. */
  readonly suspendAfter?: number | undefined;
  /** Durée de la veille, en millisecondes. */
  readonly suspendForMs?: number | undefined;
}

/**
 * Échecs consécutifs avant la mise en veille.
 *
 * Trois, et non un : un collecteur qui redémarre, une résolution DNS lente ou un
 * envoi perdu ne doivent pas éteindre la remontée pour cinq minutes.
 */
const DEFAULT_SUSPEND_AFTER = 3;

/** Durée de veille par défaut. */
const DEFAULT_SUSPEND_FOR_MS = 5 * 60 * 1000;

/** Identifiant d'événement : 32 caractères hexadécimaux, sans tiret. */
function defaultEventId(): string {
  return globalThis.crypto.randomUUID().replace(/-/g, '');
}

export function createErrorReporter(options: ReporterOptions): ErrorReporter {
  const dsn = parseDsn(options.dsn);
  if (dsn === null) {
    return {
      enabled: false,
      origin: null,
      capture: async (): Promise<CaptureOutcome> => 'skipped',
    };
  }

  const fetchImpl = options.fetchImpl ?? globalThis.fetch;
  const now = options.now ?? ((): Date => new Date());
  const eventId = options.eventId ?? defaultEventId;
  const timeoutMs = options.timeoutMs ?? 4000;
  const suspendAfter = options.suspendAfter ?? DEFAULT_SUSPEND_AFTER;
  const suspendForMs = options.suspendForMs ?? DEFAULT_SUSPEND_FOR_MS;

  /**
   * Mise en veille après une série d'échecs.
   *
   * Un collecteur injoignable ne coûtait pas un envoi perdu mais une attente de
   * `timeoutMs` **et** une ligne d'avertissement **par erreur**. Une panne du
   * site — celle-là même qu'on veut lire dans les journaux — les noyait donc
   * sous ses propres échecs de remontée, à raison de deux lignes par erreur.
   *
   * Le compteur ne mesure que des échecs **consécutifs** : un envoi réussi le
   * remet à zéro, et la remontée reprend d'elle-même à la fin de la veille sans
   * qu'on ait à redémarrer quoi que ce soit.
   */
  let consecutiveFailures = 0;
  let suspendedUntil = 0;

  /** Compte un échec, prévient, et met en veille quand la série est trop longue. */
  const fail = (reason: string, instant: Date): CaptureOutcome => {
    consecutiveFailures += 1;

    if (consecutiveFailures >= suspendAfter) {
      suspendedUntil = instant.getTime() + suspendForMs;
      consecutiveFailures = 0;
      // Dit une fois, et dit pour combien de temps : sans ce second membre de
      // phrase, un silence de cinq minutes se lit comme une remontée qui marche.
      options.onFailure?.(
        `${reason} — remontée suspendue ${Math.round(suspendForMs / 1000)} s après ${suspendAfter} échecs`,
      );
      return 'failed';
    }

    options.onFailure?.(reason);
    return 'failed';
  };

  return {
    enabled: true,
    origin: dsn.origin,

    async capture(report: ErrorReport): Promise<CaptureOutcome> {
      const instant = now();

      // En veille : ni envoi, ni attente, ni avertissement. `skipped` — comme
      // l'absence de DSN — parce que rien n'a été tenté.
      if (instant.getTime() < suspendedUntil) return 'skipped';

      const described = describe(report.error);
      const id = eventId();

      const event = {
        event_id: id,
        timestamp: instant.getTime() / 1000,
        platform: options.platform,
        level: report.level ?? 'error',
        environment: options.environment,
        release: options.release,
        // Un nom déclaré, jamais `os.hostname()` : le nom d'une machine est une
        // donnée, et celle-ci n'apprendrait rien qu'on ne sache déjà.
        ...(options.serverName === undefined ? {} : { server_name: options.serverName }),
        ...(report.transaction === undefined ? {} : { transaction: report.transaction }),
        exception: {
          values: [
            {
              type: redactOutgoingText(described.type),
              value: redactOutgoingText(described.value),
              stacktrace: { frames: parseStack(described.stack) },
            },
          ],
        },
        tags: Object.fromEntries(
          Object.entries(report.tags ?? {}).map(([key, value]) => [
            key,
            redactOutgoingText(String(value)).slice(0, 200),
          ]),
        ),
      };

      const envelope = [
        JSON.stringify({ event_id: id, sent_at: instant.toISOString() }),
        JSON.stringify({ type: 'event' }),
        JSON.stringify(event),
      ].join('\n');

      try {
        const response = await fetchImpl(dsn.endpoint, {
          method: 'POST',
          headers: { 'content-type': 'application/x-sentry-envelope' },
          body: envelope,
          signal: AbortSignal.timeout(timeoutMs),
          // Le collecteur n'a rien à faire des témoins de session.
          credentials: 'omit',
          keepalive: true,
        });

        if (!response.ok) return fail(`le collecteur a répondu ${response.status}`, instant);

        consecutiveFailures = 0;
        return 'sent';
      } catch (error) {
        // Une panne du collecteur ne doit pas transformer une erreur en deux.
        return fail(error instanceof Error ? error.message : 'cause inconnue', instant);
      }
    },
  };
}
