import { defineConfig } from 'vite';
import basicSsl from '@vitejs/plugin-basic-ssl';
import { viteStaticCopy } from 'vite-plugin-static-copy';

export default defineConfig({
  plugins: [
    basicSsl(),
    viteStaticCopy({
      targets: [
        { src: 'assets', dest: '.' },
        { src: 'manifest.json', dest: '.' },
        { src: 'sw.js', dest: '.' },
      ],
    }),
  ],
  server: {
    host: true,
    port: 3000,
  },
  build: {
    outDir: 'dist',
  },
  publicDir: false,
});
