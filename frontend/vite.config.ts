import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

const WEBUI_BRIDGE_PORT = 7681;

export default defineConfig(({ command }) => ({
  plugins: [
    svelte(),
    {
      name: 'webui-bridge',
      transformIndexHtml() {
        const src = command === 'serve'
          ? `http://127.0.0.1:${WEBUI_BRIDGE_PORT}/webui.js`
          : '/webui.js';

        return [{ tag: 'script', attrs: { src }, injectTo: 'head' }];
      },
    },
  ],
  server: {
    host: '127.0.0.1',
    port: 5173,
    strictPort: true,
  },
}));
