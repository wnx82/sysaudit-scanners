import { defineConfig } from 'vitest/config';

/**
 * Une seule suite, et c'est ce que la surface publiée permet.
 *
 * Le dépôt privé sépare quatre projets — unité, composant, intégration, bout en
 * bout — parce qu'il porte une base PostgreSQL et un navigateur. Rien de tout
 * cela n'est publié : les paquets publics sont purs, les tests des scanners
 * lisent des fixtures sur disque, et il n'y a donc plus rien à séquencer.
 */
export default defineConfig({
  test: {
    environment: 'node',
    include: [
      'packages/*/src/**/*.test.ts',
      'packages/*/tests/**/*.test.ts',
      'scanners/*/tests/**/*.test.ts',
      'scripts/**/*.test.mjs',
    ],
    exclude: ['**/node_modules/**', '**/dist/**'],
    coverage: {
      provider: 'v8',
      reportsDirectory: './coverage',
      reporter: ['text', 'lcov'],
      include: ['packages/*/src/**/*.ts'],
      exclude: ['**/*.test.ts', '**/index.ts', '**/*.d.ts'],
    },
  },
});
