import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { basename, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

/**
 * Contrôle qu'aucun secret n'est **suivi par Git**.
 *
 * Le 2026-08-19, `google-ga4.json` — un compte de service Google, clé privée
 * PEM comprise — a été versionné et poussé. Rien ne l'a dit : `.gitignore`
 * couvrait déjà `*.pem`, `*.key`, `credentials.json` et `secrets.json`, mais
 * pas ce nom-là, et aucun contrôle ne regardait le **contenu** des fichiers
 * suivis. Le fichier n'était même lu par aucun code : il est entré dans
 * l'historique sans avoir jamais servi.
 *
 * Un motif d'exclusion protège du fichier qu'on a prévu. Ce test protège du
 * suivant, parce qu'il regarde ce qui est réellement dans l'index plutôt que
 * ce qu'on a pensé à exclure.
 *
 * ## Pourquoi ici et pas dans un crochet Git
 *
 * Le crochet `pre-push` du dépôt a été retiré à la demande de l'exploitant
 * (`chore/desactiver-le-crochet-pre-push`). Un contrôle qu'on désactive
 * localement ne protège pas la CI, et c'est justement quand on est pressé
 * qu'un secret part. La suite de tests, elle, tourne dans `npm run verify` et
 * dans `ci:local`.
 *
 * ## Ce que ce test n'est pas
 *
 * Ce n'est pas un antivirus à secrets. Il ne cherche ni entropie, ni jetons de
 * fournisseurs particuliers : ces heuristiques rougissent sur des fixtures
 * légitimes, et un garde-fou qui crie faux finit désactivé. Il attrape les
 * trois formes qui ont réellement coûté quelque chose ici, et rien d'autre.
 *
 * ## Pourquoi il ne réutilise pas `packages/shared/src/secrets.ts`
 *
 * Ce module détecte l'**en-tête** `-----BEGIN … PRIVATE KEY-----`, ce qui est
 * exactement ce qu'il faut pour caviarder un journal : mieux vaut y masquer une
 * mention inoffensive qu'y laisser passer une clé. Ici l'arbitrage est inverse.
 * Quatre fichiers légitimes du dépôt portent cet en-tête — le module lui-même,
 * ses tests, et `docs/exploitation/TELEMETRY.md` qui documente une variable — et les
 * signaler apprendrait à ignorer ce test.
 *
 * Le motif retenu exige donc un bloc **complet** : en-tête, corps encodé, et
 * marqueur de fin. Une clé tronquée en documentation ne le remplit pas ; une
 * clé réelle, si.
 */

const ROOT = resolve(import.meta.dirname, '..');

/** Les fichiers **suivis par Git** : ni `node_modules`, ni artefacts de build. */
function trackedFiles() {
  return execFileSync('git', ['ls-files', '-z'], { cwd: ROOT, encoding: 'utf8' })
    .split('\0')
    .filter((path) => path !== '');
}

/**
 * Noms de fichiers qui annoncent un identifiant de service.
 *
 * Ils décrivent ce qu'une console de fournisseur propose au téléchargement :
 * c'est le geste — « télécharger la clé », puis `git add .` — qui produit
 * l'incident, pas une intention de commettre un secret.
 */
const CREDENTIAL_NAMES = [
  /^google-.*\.json$/,
  /^service-account.*\.json$/,
  /-credentials\.json$/,
  /^credentials\.json$/,
  /^secrets\.json$/,
];

/**
 * Gabarits d'environnement, seuls fichiers `.env*` légitimement suivis.
 *
 * `env-example.test.ts` vérifie déjà qu'ils ne portent aucune valeur ; ce test
 * vérifie qu'aucun **autre** `.env` ne les a rejoints.
 */
const ENV_TEMPLATES = new Set(['.env.example', '.env.production.example']);

/**
 * Bloc de clé privée **complet**, et non son seul en-tête.
 *
 * Le corps encodé est exigé — au moins une centaine de caractères base64 — puis
 * le marqueur de fin. C'est ce qui sépare une clé réellement versionnée d'une
 * clé citée : `docs/exploitation/TELEMETRY.md` montre `-----BEGIN PRIVATE KEY-----\n…`, et
 * `packages/shared/src/secrets.ts` porte le motif qui sert à la caviarder.
 */
const PRIVATE_KEY_BLOCK =
  /-----BEGIN(?: [A-Z]+)* PRIVATE KEY(?: BLOCK)?-----[\s\S]{100,}?-----END(?: [A-Z]+)* PRIVATE KEY(?: BLOCK)?-----/;

/** Extensions dont le contenu ne se lit pas comme du texte. */
const BINARY = /\.(png|jpe?g|gif|webp|avif|ico|pdf|woff2?|ttf|otf|zip|gz|tgz)$/i;

const tracked = trackedFiles();

describe('aucun secret suivi par Git', () => {
  it('ne suit aucun fichier au nom d’identifiant de service', () => {
    const offenders = tracked.filter((path) =>
      CREDENTIAL_NAMES.some((pattern) => pattern.test(basename(path))),
    );
    expect(
      offenders,
      `identifiants de service versionnés : ${offenders.join(', ')} — ` +
        'révoquer la clé côté fournisseur *avant* de la retirer de l’index',
    ).toEqual([]);
  });

  it('ne suit aucun `.env` autre que les deux gabarits', () => {
    const offenders = tracked.filter(
      (path) => basename(path).startsWith('.env') && !ENV_TEMPLATES.has(basename(path)),
    );
    expect(offenders, `fichiers d’environnement versionnés : ${offenders.join(', ')}`).toEqual([]);
  });

  /*
   * Ce contrôle lit **chaque fichier suivi**, et son coût grandit avec le
   * dépôt. Il frôlait le délai par défaut de 5 s, et une poignée de fichiers
   * ajoutés l'a fait basculer — sans qu'aucun secret n'ait été versionné.
   *
   * Un délai explicite plutôt qu'un contrôle allégé : ce que ce test cherche —
   * une clé privée dans l'index — se révoque, il ne se retire pas. L'échantillonner
   * pour tenir dans cinq secondes reviendrait à accepter d'en manquer une.
   */
  it('ne suit aucun fichier contenant une clé privée', { timeout: 30_000 }, () => {
    const offenders = tracked.filter((path) => {
      if (BINARY.test(path)) return false;
      // Ce fichier-ci décrit le motif qu'il cherche ; s'auto-signaler serait
      // le seul échec que ce test produirait à coup sûr.
      if (path === 'scripts/tracked-secrets.test.mjs') return false;
      let source;
      try {
        source = readFileSync(resolve(ROOT, path), 'utf8');
      } catch {
        // Fichier suivi mais absent du disque — index en cours de bascule.
        // Ce n'est pas un secret, et lever ici masquerait le vrai résultat.
        return false;
      }
      return PRIVATE_KEY_BLOCK.test(source);
    });
    expect(
      offenders,
      `clés privées versionnées : ${offenders.join(', ')} — ` +
        'à révoquer, pas seulement à retirer',
    ).toEqual([]);
  });
});
