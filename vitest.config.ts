import { defineConfig, configDefaults } from 'vitest/config';
import react from '@vitejs/plugin-react';
import path from 'node:path';
import ReveIntegrationSequencer from './tests/vitest-sequencer';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./tests/setup.ts'],
    globalSetup: './tests/global-setup.ts',
    exclude: [...configDefaults.exclude, 'e2e/**'],
    fileParallelism: false,
    sequence: {
      sequencer: ReveIntegrationSequencer,
    },
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, '.'),
    },
  },
});
