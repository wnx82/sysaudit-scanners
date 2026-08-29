// SPDX-FileCopyrightText: 2026 SysAudit
// SPDX-License-Identifier: LicenseRef-SysAudit-Source-Available

/**
 * Refuse le contenu qui n'a rien à faire dans un dépôt publiable.
 *
 * Ce contrôle est **générique par construction**. Inscrire ici les noms de
 * domaines, les hostnames ou les plages d'adresses réellement utilisés
 * publierait exactement ce qu'il prétend protéger — le scanner deviendrait la
 * fuite. Il cherche donc des *formes* : un bloc de clé privée complet, un nom
 * de fichier que les consoles de fournisseurs proposent au téléchargement, une
 * adresse dans un espace privé RFC 1918.
 *
 * Ce qu'il n'est pas : un détecteur d'entropie. Ces heuristiques rougissent sur
 * des fixtures légitimes, et un garde-fou qui crie faux finit désactivé.
 *
 * Usage : node scripts/scan-forbidden-content.mjs [racine]
 * Sortie : 0 si rien, 1 sinon. Les valeurs trouvées ne sont **jamais** affichées.
 */

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const ROOT = resolve(process.argv[2] ?? '.');

/** Noms de fichiers qui annoncent un identifiant, quelle que soit leur place. */
const FORBIDDEN_NAMES = [
  { pattern: /(^|\/)\.env(\.|$)/, unless: /\.example$/, label: 'fichier .env réel' },
  { pattern: /(^|\/)google-[^/]*\.json$/, label: 'compte de service Google' },
  { pattern: /(^|\/)service-account[^/]*\.json$/, label: 'compte de service' },
  { pattern: /-credentials\.json$/, label: "fichier d'identifiants" },
  { pattern: /(^|\/)(credentials|secrets)\.json$/, label: "fichier d'identifiants" },
  { pattern: /\.(pem|key|p12|pfx)$/, unless: /\/tests?\//, label: 'clé ou certificat privé' },
  { pattern: /\.(sql\.gz|dump|sqlite3?|db)$/, label: 'dump ou base de données' },
  {
    pattern: /(^|\/)sysaudit(-[^/]*)?\.(json|html)$/,
    unless: /fixtures?\//,
    label: 'rapport SysAudit',
  },
];

/**
 * Contenus interdits.
 *
 * Le motif de clé privée exige un bloc **complet** — en-tête, corps encodé,
 * marqueur de fin. Un en-tête seul apparaît légitimement dans la documentation
 * d'une variable d'environnement et dans le module qui caviarde les journaux ;
 * les signaler apprendrait à ignorer ce contrôle.
 */
const FORBIDDEN_CONTENT = [
  {
    re: /-----BEGIN (?:RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----[\s\S]{64,}?-----END/,
    label: 'bloc de clé privée complet',
  },
  {
    re: /\b(?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis|amqp):\/\/[^\s:@/"'`]+:[^\s:@/"'`]{6,}@/,
    label: 'URL de connexion avec mot de passe',
    // Les gabarits et la documentation montrent la forme ; ils la montrent sans
    // valeur, ce que `env-example.test.ts` vérifie déjà de son côté.
    allow:
      /MOT_DE_PASSE|mot.?de.?passe|<[^>]+>|\$\{?[A-Z_]+\}?|pass(?:word)?|change.?me|secret|exemple|example|xxx+/i,
  },
];

/**
 * Fichiers dont les motifs de contenu ont déjà été relus.
 *
 * Même logique que `IP_REVIEWED` : la valeur de ce contrôle est ce qu'il dit du
 * fichier **nouveau**. Chacun de ceux-ci a été ouvert — ce sont des URL de
 * connexion vers `localhost` ou vers un hôte inventé dans des tests, et, pour
 * `tracked-secrets.test.mjs`, l'expression régulière qui cherche les clés
 * privées, que ce script-ci confond avec une clé.
 */
const CONTENT_REVIEWED = [
  /^\.github\/workflows\/ci\.yml$/,
  /^apps\/api\/tests\/test-database\.ts$/,
  /^packages\/shared\/src\/(error-reporting|secrets)\.test\.ts$/,
  /^scripts\/(test-database-url\.mjs|tracked-secrets\.test\.mjs)$/,
  /^scripts\/scan-forbidden-content\.mjs$/,
];

/** Adresses privées RFC 1918. */
const PRIVATE_IP =
  /\b(?:10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})\b/;

/**
 * Fichiers dont l'adressage privé a déjà été relu.
 *
 * Une interdiction sèche des adresses RFC 1918 n'a pas de sens ici : un projet
 * d'audit système en manipule par métier, et un contrôle qui rougit sur cent
 * fixtures légitimes finit désactivé — ce qui coûte plus cher que de ne pas
 * l'avoir écrit.
 *
 * Ce qui a de la valeur, c'est le **fichier nouveau**. Chaque entrée ci-dessous
 * a été lue : l'adresse y est un exemple générique ou une fixture synthétique,
 * jamais une adresse de l'infrastructure réelle. Un fichier absent de cette
 * liste échoue, et demande la même relecture.
 *
 * Ces chemins ne sont pas des secrets — les valeurs, elles, ne sont ni ici ni
 * affichées.
 */
const IP_REVIEWED = [
  // Fixtures et attentes des paquets privés : adresses de plan d'adressage
  // générique (192.168.1.x, 192.168.2.x) et exclusion de proxy.
  /^packages\/(analysis-engine|audit-runner|report-renderer)\/src\//,
  // Modules dont le sujet *est* l'adresse : caviardage, anonymisation, refus
  // d'une image servie depuis un réseau privé, résolution d'URL publique.
  /(redact|anonymize|anonymise|sensitive|trust-proxy|hardware-images|public-url|telemetry|test-database)/i,
  // Ce script, qui décrit les motifs qu'il cherche.
  /^scripts\/scan-forbidden-content\.mjs$/,
  // Documentation et annotations : exemples de plan d'adressage.
  /^packages\/report-schema\/src\/field-annotations\.ts$/,
  // Fixtures synthétiques du format de rapport et des scanners.
  /^packages\/report-schema\/src\/fixtures\.ts$/,
  /^packages\/shared\/src\/error-reporting\.(ts|test\.ts)$/,
  /^scanners\/[a-z]+\/tests\//,
  // Outils de développement des composants privés.
  /^scripts\/migrate-test-db\.mjs$/,
  /^apps\/api\/src\/(assistant-analysis|assistant-health)\.test\.ts$/,
  /^apps\/web\/src\/(components\/report-sections\.tsx|lib\/)/,
  /^docs\//,
  /^CHANGELOG\.md$/,
  /^\.env(\.production)?\.example$/,
];

/**
 * Motifs interdits **fournis à l'exécution**, jamais committés.
 *
 * Les vrais domaines internes, hostnames et préfixes réseau ne peuvent pas
 * figurer dans ce fichier : les y écrire publierait exactement ce qu'ils
 * servent à protéger. La CI les passe par `SYSAUDIT_FORBIDDEN_PATTERNS`, une
 * expression régulière par ligne, depuis un secret de dépôt.
 */
const EXTRA_PATTERNS = (process.env.SYSAUDIT_FORBIDDEN_PATTERNS ?? '')
  .split('\n')
  .map((line) => line.trim())
  .filter((line) => line !== '' && !line.startsWith('#'))
  .map((line) => new RegExp(line, 'i'));

function trackedFiles(root) {
  return execFileSync('git', ['ls-files', '-z'], { cwd: root, encoding: 'utf8' })
    .split('\0')
    .filter((p) => p !== '');
}

const findings = [];

for (const file of trackedFiles(ROOT)) {
  for (const { pattern, unless, label } of FORBIDDEN_NAMES) {
    if (pattern.test(file) && !(unless?.test(file) ?? false)) {
      findings.push({ file, label });
    }
  }

  let text;
  try {
    text = readFileSync(resolve(ROOT, file), 'utf8');
  } catch {
    continue; // Fichier illisible : rien à analyser ici.
  }
  // Octet nul : le fichier est binaire, les motifs texte n'y veulent rien dire.
  if (text.includes(String.fromCharCode(0))) continue;

  const contentReviewed = CONTENT_REVIEWED.some((re) => re.test(file));
  for (const { re, label, allow } of FORBIDDEN_CONTENT) {
    const hit = text.match(re);
    if (hit === null || contentReviewed) continue;
    if (!(allow?.test(hit[0]) ?? false)) findings.push({ file, label });
  }

  if (PRIVATE_IP.test(text) && !IP_REVIEWED.some((re) => re.test(file))) {
    findings.push({
      file,
      label:
        "adresse RFC 1918 dans un fichier non relu — vérifier qu'elle ne décrit " +
        'pas une infrastructure réelle, puis inscrire le chemin dans IP_REVIEWED',
    });
  }

  for (const re of EXTRA_PATTERNS) {
    if (re.test(text)) findings.push({ file, label: 'motif interdit fourni par la CI' });
  }
}

if (findings.length === 0) {
  console.log(`Aucun contenu interdit dans ${ROOT}.`);
  process.exit(0);
}

console.error(`${findings.length} détection(s) — valeurs volontairement non affichées :\n`);
for (const { file, label } of findings) console.error(`  ${file}\n    → ${label}`);
console.error('\nRetirer, caviarder, ou justifier par une exemption explicite dans ce script.');
process.exit(1);
