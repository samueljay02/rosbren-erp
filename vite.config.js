import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

export default defineConfig({
  base: './',
  plugins: [react()],
  optimizeDeps: { exclude: ['@electric-sql/pglite'] },
  build: { chunkSizeWarningLimit: 2000 },
})
