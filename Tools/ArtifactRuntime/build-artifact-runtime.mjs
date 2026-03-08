import { build } from 'esbuild'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const scriptDir = path.dirname(fileURLToPath(import.meta.url))
const rootDir = path.resolve(scriptDir, '..', '..')
const entryPath = path.join(scriptDir, 'artifact-runtime-entry.mjs')
const outputPath = path.join(rootDir, 'Sources', 'Resources', 'artifact-runtime.js')

await build({
  entryPoints: [entryPath],
  outfile: outputPath,
  bundle: true,
  minify: true,
  sourcemap: false,
  target: ['safari17'],
  format: 'iife',
  platform: 'browser',
  logLevel: 'info'
})

console.log(`Wrote ${outputPath}`)
