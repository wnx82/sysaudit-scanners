// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

/**
 * Où va chaque section du rapport, une fois collectée.
 *
 * Une donnée collectée puis jamais affichée coûte le temps de collecte, la
 * place en base et la surface d'attaque, sans rien rendre. Une carte d'interface
 * alimentée par un champ qui n'existe pas coûte pire : elle affirme.
 *
 * Ce registre déclare, pour chaque section racine du schéma, ce qui la consomme
 * en aval. Il n'est pas décoratif : `traceability.test.ts` échoue si une section
 * du schéma n'y figure pas. Ajouter une section au schéma oblige donc à décider
 * de son sort — et à écrire pourquoi, quand la réponse est « rien ».
 *
 * Le registre décrit, il ne vérifie pas : que `renderer: true` soit vrai reste
 * de la responsabilité de la relecture. Ce qu'il garantit, c'est qu'aucune
 * section ne soit ajoutée sans que la question soit posée.
 */

/** Consommateurs possibles d'une section, en aval du scanner. */
export interface SectionTrace {
  /** Projetée dans les tables d'analyse (`apps/api/src/scan-facts.ts`). */
  readonly facts: boolean;
  /** Rendue par `@sysaudit/report-renderer` (Markdown, HTML autonome, PDF). */
  readonly renderer: boolean;
  /** Affichée par l'interface Web (`apps/web/src/components/report-sections.tsx`). */
  readonly web: boolean;
  /** Lue par au moins une règle de `@sysaudit/analysis-engine`. */
  readonly rules: boolean;
  /** Transmise au contexte de l'analyse IA (`apps/api/src/assistant-grounding.ts`). */
  readonly ai: boolean;
  /** Pourquoi un consommateur manque, quand l'absence est délibérée. */
  readonly note?: string;
}

/**
 * Le rapport brut est **toujours** conservé en base tel quel : `facts` ne
 * décrit que la projection interrogeable, pas la persistance.
 */
export const SECTION_TRACEABILITY: Readonly<Record<string, SectionTrace>> = {
  schemaVersion: {
    facts: true,
    renderer: true,
    web: true,
    rules: false,
    ai: false,
    note: 'Métadonnée de format : aiguillage et migration, pas un fait matériel.',
  },
  scannerVersion: {
    facts: true,
    renderer: true,
    web: true,
    rules: false,
    ai: false,
    note: 'Métadonnée de format.',
  },
  platformVersion: {
    facts: false,
    renderer: false,
    web: false,
    rules: false,
    ai: false,
    note: 'Renseignée par l’API à l’ingestion, pas par le scanner.',
  },
  report: { facts: true, renderer: true, web: true, rules: false, ai: true },
  capabilities: { facts: true, renderer: true, web: true, rules: true, ai: true },

  system: { facts: true, renderer: true, web: true, rules: true, ai: true },
  os: { facts: true, renderer: true, web: true, rules: true, ai: true },

  motherboard: { facts: false, renderer: true, web: true, rules: false, ai: true },
  bios: { facts: false, renderer: true, web: true, rules: true, ai: false },
  cpus: { facts: true, renderer: true, web: true, rules: true, ai: true },
  memory: { facts: true, renderer: true, web: true, rules: true, ai: true },
  gpus: { facts: true, renderer: true, web: true, rules: true, ai: true },
  audio: {
    facts: false,
    renderer: true,
    web: true,
    rules: false,
    ai: false,
    note: 'Inventaire utile au rapport et au diagnostic humain ; aucune règle ne s’y appuie encore.',
  },

  sensors: {
    facts: false,
    renderer: true,
    web: true,
    rules: true,
    ai: false,
    note: 'Températures et ventilateurs : à transmettre à l’IA (étape 09), qui juge aujourd’hui une machine sans savoir si elle chauffe.',
  },
  power: { facts: false, renderer: true, web: true, rules: true, ai: false },

  storage: { facts: true, renderer: true, web: true, rules: true, ai: true },
  network: { facts: false, renderer: true, web: true, rules: true, ai: false },
  devices: { facts: false, renderer: true, web: true, rules: true, ai: false },
  drivers: { facts: false, renderer: true, web: true, rules: true, ai: false },

  firmware: {
    facts: false,
    renderer: false,
    web: false,
    rules: false,
    ai: false,
    note: 'Définie au schéma, collectée par aucun scanner — la section figure dans `collection.skippedSections`. Étape 08.',
  },

  software: { facts: false, renderer: true, web: true, rules: true, ai: false },
  startup: {
    facts: false,
    renderer: true,
    web: true,
    rules: false,
    ai: false,
    note: 'Le démarrage automatique est rendu tel quel ; aucune règle ne juge encore son opportunité.',
  },
  security: { facts: false, renderer: true, web: true, rules: true, ai: false },
  virtualization: { facts: true, renderer: true, web: true, rules: true, ai: false },

  monitoring: { facts: false, renderer: true, web: true, rules: true, ai: false },
  benchmark: {
    facts: true,
    renderer: true,
    web: true,
    rules: true,
    ai: false,
    note: 'Les mesures de performance ne parviennent pas à l’IA. Étape 09.',
  },

  // Les quatre sections d'historique du chantier « Cross-Platform Insight ».
  // L'étape 11 les a raccordées à leurs consommateurs : règles de scoring,
  // trois rendus exportés, interface Web. Restent deux `false` datés.
  stability: {
    facts: false,
    renderer: true,
    web: true,
    rules: true,
    ai: false,
    note: 'Pas projetée dans les tables d’analyse : les compteurs n’ont de sens qu’avec leur fenêtre, et une colonne « 47 » sans sa période produirait exactement la comparaison que le schéma interdit. Non transmise à l’IA en attendant l’étape 09.',
  },
  boot: {
    facts: false,
    renderer: true,
    web: true,
    rules: true,
    ai: false,
    note: 'Séquence de démarrage. Même réserve que `stability` pour la projection et pour l’IA.',
  },
  shutdown: {
    facts: false,
    renderer: true,
    web: true,
    rules: true,
    ai: false,
    note: 'Séquence d’arrêt. Même réserve que `stability` pour la projection et pour l’IA.',
  },
  events: {
    facts: false,
    renderer: true,
    web: true,
    rules: true,
    ai: false,
    note: 'Journal normalisé et regroupé. Les extraits bruts ne partiront pas à l’IA sans décision explicite d’anonymisation : ce sont les seules chaînes du rapport que le scanner recopie du système.',
  },

  notes: {
    facts: false,
    renderer: false,
    web: false,
    rules: false,
    ai: false,
    note: 'Notes libres du scanner, jamais interprétées automatiquement — c’est le contrat de ce champ.',
  },
  collection: { facts: true, renderer: true, web: true, rules: true, ai: false },
};
