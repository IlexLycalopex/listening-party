// @ts-check
import { defineConfig } from 'astro/config';

// https://astro.build/config
export default defineConfig({
  site: 'https://ilexlycalopex.github.io',
  base: '/listening-party',             // ← must match your GitHub repo name
  output: 'static',
});
