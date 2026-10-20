import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { viteSingleFile } from 'vite-plugin-singlefile'

// Um so ficheiro HTML (JS e CSS embutidos): o hub.ps1 serve-o tal como esta, sem Node no PC.
// npm run dev: a API vem do hub a correr (HUB=https://hub.kvnterm.com npm run dev).
export default defineConfig({
  plugins: [react(), viteSingleFile()],
  build: { outDir: 'dist', assetsInlineLimit: 100000000, cssCodeSplit: false },
  server: { proxy: { '/api': { target: process.env.HUB ?? 'https://hub.kvnterm.com', changeOrigin: true, secure: true } } },
})
