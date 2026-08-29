// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

/**
 * Pourquoi une mesure venue d'un service tiers manque — **le vocabulaire**.
 *
 * ## Pourquoi ici plutôt que dans l'API
 *
 * L'API nomme la cause ; l'écran l'écrit. Tant que la liste des états vivait
 * dans `apps/api`, l'écran en tenait une copie manuscrite — et une copie
 * manuscrite d'une union de chaînes ne diverge pas bruyamment : elle laisse
 * simplement un état non traité tomber dans le `else`, qui affichait « le
 * service n'a rien rendu » pour un quota dépassé.
 *
 * Ce module est pur : ni requête, ni environnement, ni horloge. Il ne connaît
 * aucun fournisseur en particulier — la traduction d'une erreur Google ou d'un
 * statut HTTP reste dans l'API, qui est la seule à les voir.
 *
 * ## La règle qu'il sert
 *
 * Aucun de ces états ne vaut `0`. Une panne, une absence de configuration et
 * zéro visite sont trois réponses différentes. `unknown_error` est l'aveu, pas
 * le fourre-tout : y ranger une cause qu'on n'a pas voulu regarder ferait
 * exactement ce que le reste du produit refuse.
 */

/** Les états qu'une source de mesure peut rendre, du plus banal au plus obscur. */
export const PROVIDER_STATUSES = [
  /** Mesure lue, et elle porte des chiffres. */
  'ok',
  /** Aucune variable posée : le service n'est pas branché sur cette instance. */
  'not_configured',
  /** Service joignable, période vide. Ce n'est pas une panne. */
  'no_data',
  /** Jeton refusé, ou compte sans droit sur la ressource. */
  'auth_error',
  /** API non activée dans le projet du fournisseur. */
  'api_disabled',
  /** Rien n'a répondu : coupure, DNS, délai dépassé. */
  'network_error',
  /** Quota ou cadence dépassés. La mesure reviendra d'elle-même. */
  'quota_exceeded',
  /** Le service a répondu, mais mal : erreur serveur ou format inattendu. */
  'provider_error',
  /** Cause non comprise. Jamais rangée ailleurs par commodité. */
  'unknown_error',
] as const;

export type ProviderStatus = (typeof PROVIDER_STATUSES)[number];

/** Un état, et la phrase française qui l'accompagne à l'écran. */
export interface ProviderDiagnostic {
  readonly status: ProviderStatus;
  /** Ne porte jamais de secret : ni jeton, ni clé, ni adresse privée. */
  readonly detail: string;
}

/** Ramène une valeur reçue à un état connu. L'inconnu s'avoue. */
export function normalizeProviderStatus(value: unknown): ProviderStatus {
  return typeof value === 'string' && (PROVIDER_STATUSES as readonly string[]).includes(value)
    ? (value as ProviderStatus)
    : 'unknown_error';
}

/**
 * La source a-t-elle échoué ?
 *
 * `no_data` et `not_configured` répondent **non** : ce sont des états normaux.
 * Les peindre comme des pannes enverrait chercher un incident là où il n'y en a
 * pas — une propriété neuve reste vide plusieurs jours, et une instance qui n'a
 * pas branché GA4 n'a rien de cassé.
 */
export function isProviderFailure(status: ProviderStatus): boolean {
  return status !== 'ok' && status !== 'no_data' && status !== 'not_configured';
}

/** Intitulé court de l'état, pour un lecteur français. */
export const PROVIDER_STATUS_LABELS: Readonly<Record<ProviderStatus, string>> = {
  ok: 'Mesure disponible',
  not_configured: 'Service non configuré',
  no_data: 'Aucune donnée sur la période',
  auth_error: 'Authentification refusée',
  api_disabled: 'API non activée chez le fournisseur',
  network_error: 'Service injoignable',
  quota_exceeded: 'Quota ou cadence dépassés',
  provider_error: 'Le fournisseur a répondu en erreur',
  unknown_error: 'Cause non déterminée',
};

/**
 * Ce que l'exploitant peut faire, état par état.
 *
 * Une phrase par cause, et un geste par phrase. « Vérifiez la configuration »
 * ne dit rien : la valeur de cet écran tient précisément à ce qu'il envoie au
 * bon endroit du premier coup.
 */
export const PROVIDER_STATUS_GUIDANCE: Readonly<Record<ProviderStatus, string>> = {
  ok: 'Rien à faire.',
  not_configured:
    'Poser les variables nommées ci-dessous dans l’environnement de l’API, puis redémarrer.',
  no_data:
    'Rien à réparer : le service répond et n’a rien compté sur cette fenêtre. Élargir la période, ou attendre.',
  auth_error:
    'Régénérer le jeton, ou vérifier que le compte de service est bien autorisé sur la ressource. Le réseau n’est pas en cause : le service a répondu.',
  api_disabled:
    'Activer l’API dans la console du fournisseur, puis attendre quelques minutes. Ce n’est pas une autorisation à donner sur la ressource.',
  network_error:
    'Vérifier que l’API atteint le service : DNS, pare-feu sortant, adresse de l’instance.',
  quota_exceeded:
    'Attendre : la mesure reviendra d’elle-même. Si le cas se répète, allonger le cache de la source.',
  provider_error:
    'Le service a répondu autre chose que ce qui était attendu. Vérifier sa version d’API, puis relire le détail ci-dessous.',
  unknown_error:
    'La cause n’a pas pu être nommée. Le détail brut est rendu tel quel plutôt que rangé dans la case la plus probable.',
};

/**
 * Le ton d'affichage d'un état.
 *
 * Trois seulement, parce qu'un écran qui distingue neuf nuances de gravité ne
 * distingue plus rien. `info` couvre les états normaux, `warning` ce qui se
 * rétablira, `error` ce qui demande une intervention.
 */
export type ProviderTone = 'info' | 'warning' | 'error';

export function providerTone(status: ProviderStatus): ProviderTone {
  if (status === 'ok' || status === 'no_data' || status === 'not_configured') return 'info';
  if (status === 'quota_exceeded' || status === 'network_error') return 'warning';
  return 'error';
}
