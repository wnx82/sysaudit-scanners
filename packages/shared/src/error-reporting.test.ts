// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

import { describe, expect, it, vi } from 'vitest';
import {
  createErrorReporter,
  parseDsn,
  parseStack,
  redactOutgoingText,
} from './error-reporting.js';

const DSN = 'http://cle0123456789abcdef@collecteur.test:8000/14';

describe('parseDsn', () => {
  it('dérive l’adresse d’enveloppe et l’origine', () => {
    const dsn = parseDsn(DSN);
    expect(dsn?.origin).toBe('http://collecteur.test:8000');
    expect(dsn?.projectId).toBe('14');
    expect(dsn?.endpoint).toContain('http://collecteur.test:8000/api/14/envelope/');
    expect(dsn?.endpoint).toContain('sentry_key=cle0123456789abcdef');
    expect(dsn?.endpoint).toContain('sentry_version=7');
  });

  it('accepte un DSN en HTTPS sans port', () => {
    expect(parseDsn('https://cle@collecteur.test/2')?.origin).toBe('https://collecteur.test');
  });

  it('rend null plutôt que de lever', () => {
    // Un DSN absent est le cas normal — la remontée est facultative — et un DSN
    // mal formé ne doit pas empêcher l'application de démarrer.
    expect(parseDsn(undefined)).toBeNull();
    expect(parseDsn('')).toBeNull();
    expect(parseDsn('   ')).toBeNull();
    expect(parseDsn('pas-une-url')).toBeNull();
    // Sans clé publique.
    expect(parseDsn('http://collecteur.test/14')).toBeNull();
    // Sans projet, ou avec un projet qui n'est pas un nombre.
    expect(parseDsn('http://cle@collecteur.test/')).toBeNull();
    expect(parseDsn('http://cle@collecteur.test/projet')).toBeNull();
  });
});

describe('redactOutgoingText', () => {
  it('masque une clé privée', () => {
    const redacted = redactOutgoingText(
      'Échec de lecture : -----BEGIN PRIVATE KEY-----\nMIIEv...\n',
    );
    expect(redacted).toContain('[secret masqué]');
    expect(redacted).not.toContain('BEGIN PRIVATE KEY');
  });

  it('masque une chaîne de connexion, hôte compris', () => {
    // Le cas le plus banal : une erreur PostgreSQL qui recopie l'URL complète.
    // Le motif du dépôt emporte l'hôte avec les identifiants — perte de
    // diagnosticabilité assumée, voir le commentaire de `redactOutgoingText`.
    const redacted = redactOutgoingText(
      'connect ECONNREFUSED postgresql://sysaudit:motdepasse@10.0.0.1:5432/base',
    );
    expect(redacted).toContain('[secret masqué]');
    expect(redacted).not.toContain('motdepasse');
    expect(redacted).not.toContain('10.0.0.1');
    // Ce qui précède reste : c'est ce qui reste diagnosticable.
    expect(redacted).toContain('connect ECONNREFUSED');
  });

  it('masque toutes les occurrences, pas seulement la première', () => {
    const redacted = redactOutgoingText(
      'a=postgresql://u1:motdepasse1@h1/db b=mysql://u2:motdepasse2@h2/db',
    );
    expect(redacted).not.toContain('motdepasse1');
    expect(redacted).not.toContain('motdepasse2');
  });

  it('tronque un texte démesuré', () => {
    const redacted = redactOutgoingText('x'.repeat(10_000));
    expect(redacted.length).toBeLessThanOrEqual(2001);
    expect(redacted.endsWith('…')).toBe(true);
  });

  it('laisse intact un message ordinaire', () => {
    expect(redactOutgoingText('Rapport introuvable.')).toBe('Rapport introuvable.');
  });
});

describe('parseStack', () => {
  it('découpe les cadres V8', () => {
    const frames = parseStack(
      [
        'Error: quelque chose',
        '    at lit (/app/src/lecture.ts:12:5)',
        '    at /app/src/app.ts:340:9',
      ].join('\n'),
    );

    // Du plus ancien au plus récent, comme Sentry l'attend.
    expect(frames).toHaveLength(2);
    expect(frames[1]).toMatchObject({
      filename: '/app/src/lecture.ts',
      function: 'lit',
      lineno: 12,
    });
    expect(frames[0]).toMatchObject({ filename: '/app/src/app.ts', function: '?', lineno: 340 });
  });

  it('conserve une ligne non reconnue plutôt que de la perdre', () => {
    // Une pile approximative vaut mieux qu'une pile absente.
    const frames = parseStack('Error: x\n    quelque chose d’inattendu');
    expect(frames).toHaveLength(1);
    expect(frames[0]?.function).toBe('?');
  });

  it('rend une liste vide sans pile', () => {
    expect(parseStack(undefined)).toEqual([]);
  });
});

describe('createErrorReporter', () => {
  const BASE = {
    environment: 'test',
    release: 'sysaudit@0.50.0',
    platform: 'node' as const,
    now: () => new Date('2026-07-30T12:00:00Z'),
    eventId: () => 'a'.repeat(32),
  };

  it('est désactivé sans DSN, et ne tente aucun envoi', async () => {
    // C'est le défaut : la remontée d'erreurs ne s'active pas toute seule.
    const fetchImpl = vi.fn();
    const reporter = createErrorReporter({ ...BASE, fetchImpl: fetchImpl as never });

    expect(reporter.enabled).toBe(false);
    expect(reporter.origin).toBeNull();
    expect(await reporter.capture({ error: new Error('x') })).toBe('skipped');
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  /** Décode l'enveloppe envoyée pour en relire l'événement. */
  function eventFrom(body: string): Record<string, unknown> {
    const lines = body.split('\n');
    return JSON.parse(lines[2]!) as Record<string, unknown>;
  }

  it('envoie une enveloppe conforme', async () => {
    const calls: { url: string; body: string }[] = [];
    const fetchImpl = vi.fn(async (url: string, init: RequestInit) => {
      calls.push({ url: String(url), body: String(init.body) });
      return new Response('', { status: 200 });
    });

    const reporter = createErrorReporter({
      ...BASE,
      dsn: DSN,
      serverName: 'api',
      fetchImpl: fetchImpl as never,
    });

    const outcome = await reporter.capture({
      error: new Error('quelque chose a cassé'),
      transaction: 'GET /api/v1/reports/:id',
      tags: { method: 'GET', statusCode: '500' },
    });

    expect(outcome).toBe('sent');
    expect(calls[0]?.url).toContain('/api/14/envelope/');

    const [header, itemHeader] = calls[0]!.body.split('\n');
    expect(JSON.parse(header!)).toMatchObject({ event_id: 'a'.repeat(32) });
    expect(JSON.parse(itemHeader!)).toEqual({ type: 'event' });

    const event = eventFrom(calls[0]!.body);
    expect(event.release).toBe('sysaudit@0.50.0');
    expect(event.environment).toBe('test');
    expect(event.transaction).toBe('GET /api/v1/reports/:id');
    expect(event.server_name).toBe('api');
    expect(event.tags).toEqual({ method: 'GET', statusCode: '500' });
  });

  it('n’envoie jamais un secret présent dans le message', async () => {
    // Ce qui est refusé à l'ingestion d'un rapport n'a pas davantage sa place
    // dans un collecteur d'erreurs.
    let body = '';
    const fetchImpl = vi.fn(async (_url: string, init: RequestInit) => {
      body = String(init.body);
      return new Response('', { status: 200 });
    });

    const reporter = createErrorReporter({ ...BASE, dsn: DSN, fetchImpl: fetchImpl as never });
    await reporter.capture({
      error: new Error('échec : postgresql://sysaudit:tres-secret@10.0.0.1:5432/base'),
    });

    expect(body).not.toContain('tres-secret');
    expect(body).toContain('secret masqué');
  });

  it('masque aussi les étiquettes', async () => {
    let body = '';
    const fetchImpl = vi.fn(async (_url: string, init: RequestInit) => {
      body = String(init.body);
      return new Response('', { status: 200 });
    });

    const reporter = createErrorReporter({ ...BASE, dsn: DSN, fetchImpl: fetchImpl as never });
    await reporter.capture({
      error: new Error('x'),
      tags: { cible: 'mysql://u:motdepasse@h/db' },
    });

    expect(body).not.toContain('motdepasse');
  });

  it('rapporte un refus du collecteur sans lever', async () => {
    // Une panne du collecteur ne doit pas transformer une erreur en deux.
    const reasons: string[] = [];
    const reporter = createErrorReporter({
      ...BASE,
      dsn: DSN,
      fetchImpl: (async () => new Response('', { status: 429 })) as never,
      onFailure: (reason) => reasons.push(reason),
    });

    expect(await reporter.capture({ error: new Error('x') })).toBe('failed');
    expect(reasons[0]).toContain('429');
  });

  it('rapporte un collecteur injoignable sans lever', async () => {
    const reasons: string[] = [];
    const reporter = createErrorReporter({
      ...BASE,
      dsn: DSN,
      fetchImpl: (async () => {
        throw new Error('ECONNREFUSED');
      }) as never,
      onFailure: (reason) => reasons.push(reason),
    });

    expect(await reporter.capture({ error: new Error('x') })).toBe('failed');
    expect(reasons[0]).toContain('ECONNREFUSED');
  });

  it('se met en veille après une série d’échecs, puis reprend', async () => {
    // Un collecteur injoignable coûtait une attente **et** une ligne
    // d'avertissement par erreur : une panne du site se noyait sous ses propres
    // échecs de remontée. Passé trois échecs, on cesse d'essayer pendant un
    // moment — sans rien perdre d'autre que des envois qui échouaient déjà.
    const reasons: string[] = [];
    let instant = new Date('2026-07-30T12:00:00Z');
    const fetchImpl = vi.fn(async () => {
      throw new Error('ECONNREFUSED');
    });

    const reporter = createErrorReporter({
      ...BASE,
      dsn: DSN,
      now: () => instant,
      fetchImpl: fetchImpl as never,
      onFailure: (reason) => reasons.push(reason),
      suspendAfter: 3,
      suspendForMs: 60_000,
    });

    for (let attempt = 0; attempt < 3; attempt += 1) {
      expect(await reporter.capture({ error: new Error('x') })).toBe('failed');
    }
    expect(fetchImpl).toHaveBeenCalledTimes(3);
    // Le troisième échec dit la veille et sa durée : un silence non annoncé se
    // lirait comme une remontée qui marche.
    expect(reasons).toHaveLength(3);
    expect(reasons[2]).toContain('suspendue 60 s');

    // Pendant la veille : ni envoi, ni avertissement supplémentaire.
    instant = new Date('2026-07-30T12:00:30Z');
    expect(await reporter.capture({ error: new Error('x') })).toBe('skipped');
    expect(fetchImpl).toHaveBeenCalledTimes(3);
    expect(reasons).toHaveLength(3);

    // Passée la veille, la remontée reprend d'elle-même.
    instant = new Date('2026-07-30T12:01:01Z');
    expect(await reporter.capture({ error: new Error('x') })).toBe('failed');
    expect(fetchImpl).toHaveBeenCalledTimes(4);
  });

  it('ne compte que les échecs consécutifs', async () => {
    // Un collecteur qui redémarre ou un envoi perdu ne doivent pas éteindre la
    // remontée : un seul succès remet le compteur à zéro.
    const reasons: string[] = [];
    let succeed = false;
    const reporter = createErrorReporter({
      ...BASE,
      dsn: DSN,
      fetchImpl: (async () => new Response('', { status: succeed ? 200 : 500 })) as never,
      onFailure: (reason) => reasons.push(reason),
      suspendAfter: 3,
    });

    expect(await reporter.capture({ error: new Error('x') })).toBe('failed');
    expect(await reporter.capture({ error: new Error('x') })).toBe('failed');

    succeed = true;
    expect(await reporter.capture({ error: new Error('x') })).toBe('sent');

    succeed = false;
    expect(await reporter.capture({ error: new Error('x') })).toBe('failed');
    expect(await reporter.capture({ error: new Error('x') })).toBe('failed');

    // Quatre échecs au total, jamais trois d'affilée : aucune veille.
    expect(reasons).toHaveLength(4);
    expect(reasons.some((reason) => reason.includes('suspendue'))).toBe(false);
  });

  it('accepte une valeur levée qui n’est pas une Error', async () => {
    let body = '';
    const reporter = createErrorReporter({
      ...BASE,
      dsn: DSN,
      fetchImpl: (async (_url: string, init: RequestInit) => {
        body = String(init.body);
        return new Response('', { status: 200 });
      }) as never,
    });

    expect(await reporter.capture({ error: 'une chaîne levée' })).toBe('sent');
    expect(eventFrom(body).exception).toMatchObject({
      values: [{ value: 'une chaîne levée' }],
    });
  });
});
