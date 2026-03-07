import { build } from 'esbuild'
import { bundledLanguagesInfo } from 'shiki'
import fs from 'node:fs/promises'
import path from 'node:path'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'

const require = createRequire(import.meta.url)
const scriptDir = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(scriptDir, '..', '..')
const resourcesDir = path.join(repoRoot, 'Sources', 'Resources')
const runtimeFileName = 'markdown-shiki-runtime.js'
const manifestFileName = 'markdown-shiki-manifest.json'
const runtimeFilePath = path.join(resourcesDir, runtimeFileName)
const manifestFilePath = path.join(resourcesDir, manifestFileName)

const starterLanguageIDs = [
  'markdown',
  'mermaid',
  'shellscript',
  'json',
  'yaml',
  'javascript',
  'typescript',
  'tsx',
  'swift',
  'python',
  'go',
  'java',
  'html',
  'css',
  'xml',
  'sql'
]

// Languages included in the bundle (available for on-demand highlighting).
// Starter languages are loaded on init; the rest load lazily when encountered.
// Non-bundled languages still get correct labels/logos but render as plain text.
const bundledLanguageIDs = [
  ...starterLanguageIDs,

  // C family
  'c', 'cpp', 'csharp', 'objective-c', 'objective-cpp',

  // Modern systems
  'rust', 'zig', 'nim', 'crystal', 'v', 'odin',

  // JVM
  'kotlin', 'scala', 'groovy',

  // Scripting
  'ruby', 'php', 'perl', 'lua', 'r',

  // Functional
  'haskell', 'elixir', 'erlang', 'clojure', 'ocaml', 'fsharp', 'julia',
  'common-lisp', 'scheme', 'racket', 'purescript',

  // Mobile
  'dart',

  // Web frameworks
  'jsx', 'vue', 'vue-html', 'svelte', 'astro', 'angular-html', 'angular-ts',

  // CSS preprocessors
  'scss', 'sass', 'less', 'stylus', 'postcss',

  // Template engines
  'pug', 'handlebars', 'twig', 'erb', 'blade', 'liquid',

  // Shell variants
  'shellsession', 'powershell', 'bat', 'fish', 'nushell',

  // Config & DevOps
  'docker', 'toml', 'ini', 'nginx', 'terraform', 'hcl',
  'cmake', 'make', 'nix', 'dotenv', 'ssh-config',

  // Data formats
  'jsonc', 'json5', 'jsonl', 'graphql', 'proto', 'prisma', 'csv',

  // Markup & Documentation
  'latex', 'tex', 'mdx', 'rst', 'asciidoc', 'typst',

  // Diff & Utilities
  'diff', 'regexp', 'log', 'http',

  // Blockchain
  'solidity',

  // Editor & Game dev
  'viml', 'gdscript', 'gdresource',

  // Low-level & GPU
  'wasm', 'asm', 'glsl', 'hlsl', 'wgsl',

  // Hardware description
  'verilog', 'system-verilog', 'vhdl',

  // Other notable
  'applescript', 'coffee', 'fortran-free-form', 'fortran-fixed-form',
  'pascal', 'prolog', 'matlab', 'tcl', 'ada', 'cobol',
  'wolfram',
]

const customAliases = {
  plain: 'txt',
  plaintext: 'txt',
  text: 'txt',
  shell: 'shellscript',
  shellscript: 'shellscript',
  zsh: 'shellscript',
  docker: 'dockerfile',
  fishshell: 'fish',
  vuejs: 'vue',
  cplusplus: 'cpp',
  objectivec: 'objective-c',
  'obj-c': 'objective-c',
  'objective-cpp': 'cpp',
  golang: 'go',
  mysql: 'sql',
  postgresql: 'sql',
  sqlite: 'sql',
  pgsql: 'sql',
  fortran: 'fortran-free-form',
  assembly: 'asm',
  x86: 'asm',
  'x86asm': 'asm',
  'assembly-x86': 'asm',
  mermaidsvg: 'mermaid',
  'mermaid-svg': 'mermaid'
}

const customLabels = {
  txt: 'txt',
  shellscript: 'bash',
  shellsession: 'console',
  'common-lisp': 'common-lisp',
  'fortran-fixed-form': 'fortran',
  'fortran-free-form': 'fortran',
  make: 'makefile'
}

const customLogoKeys = {
  shellscript: 'bash',
  shellsession: 'bash',
  'ssh-config': 'bash',
  dockerfile: 'docker',
  docker: 'docker',
  jsx: 'javascript',
  tsx: 'typescript',
  'common-lisp': 'lisp',
  'fortran-fixed-form': 'fortran',
  'fortran-free-form': 'fortran',
  make: 'make',
  json5: 'json',
  jsonc: 'json',
  jsonl: 'json',
  'angular-html': 'angular',
  'angular-ts': 'angular',
  'vue-html': 'vue',
  coffee: 'coffeescript',
  erb: 'ruby',
  blade: 'php',
  liquid: 'ruby',
  hcl: 'terraform',
  mdx: 'markdown',
  rst: 'markdown',
  asciidoc: 'markdown',
  typst: 'latex',
  'system-verilog': 'verilog',
  vhdl: 'verilog',
  glsl: 'wgsl',
  hlsl: 'wgsl'
}

const shikiPackageVersion = require('shiki/package.json').version

function buildLanguageMetadata() {
  const canonicalLanguages = bundledLanguagesInfo
    .map((info) => ({
      id: info.id,
      name: info.name,
      aliases: (info.aliases ?? []).slice().sort()
    }))
    .sort((lhs, rhs) => lhs.id.localeCompare(rhs.id))

  const aliasToCanonical = Object.create(null)
  for (const info of canonicalLanguages) {
    aliasToCanonical[info.id] = info.id
    for (const alias of info.aliases) {
      aliasToCanonical[alias] = info.id
    }
  }

  for (const [alias, canonical] of Object.entries(customAliases)) {
    aliasToCanonical[alias] = canonical
  }

  const knownCanonicalIDs = new Set(canonicalLanguages.map((info) => info.id))
  for (const starterID of starterLanguageIDs) {
    if (!knownCanonicalIDs.has(starterID)) {
      throw new Error(`Starter language '${starterID}' is not a bundled Shiki language.`)
    }
  }
  for (const bundledID of bundledLanguageIDs) {
    if (!knownCanonicalIDs.has(bundledID)) {
      throw new Error(`Bundled language '${bundledID}' is not a known Shiki language.`)
    }
  }

  return { canonicalLanguages, aliasToCanonical }
}

function objectLiteralEntries(values) {
  return Object.entries(values)
    .sort(([lhs], [rhs]) => lhs.localeCompare(rhs))
    .map(([key, value]) => `  ${JSON.stringify(key)}: ${JSON.stringify(value)}`)
    .join(',\n')
}

function buildRuntimeSource(canonicalLanguages, aliasToCanonical) {
  // Only bundle the curated language set to keep the runtime small (~4 MB instead of ~8 MB).
  // Non-bundled languages still get correct labels/logos/aliases but no syntax highlighting.
  const bundledSet = new Set(bundledLanguageIDs)
  const bundledLanguages = canonicalLanguages.filter((lang) => bundledSet.has(lang.id))

  const languageImports = bundledLanguages
    .map((language, index) => `import lang${index} from '@shikijs/langs-precompiled/${language.id}'`)
    .join('\n')

  const bundledLanguageEntries = bundledLanguages
    .map((language, index) => `  ${JSON.stringify(language.id)}: lang${index}`)
    .join(',\n')

  const headerLabelByCanonical = Object.fromEntries(
    canonicalLanguages.map((language) => [language.id, customLabels[language.id] ?? language.id])
  )

  const logoKeyByCanonical = Object.fromEntries(
    canonicalLanguages.map((language) => [language.id, customLogoKeys[language.id] ?? language.id])
  )

  return `import { createHighlighterCore } from 'shiki/core'
import { createJavaScriptRawEngine } from 'shiki/engine/javascript'
import githubLightDefault from '@shikijs/themes/github-light-default'
import githubDarkDefault from '@shikijs/themes/github-dark-default'
${languageImports}

const THEME_NAMES = { light: 'github-light-default', dark: 'github-dark-default' }
const STARTER_LANGUAGE_IDS = ${JSON.stringify(starterLanguageIDs)}
const LANGUAGE_ALIAS_TO_CANONICAL = {
${objectLiteralEntries(aliasToCanonical)}
}
const LANGUAGE_HEADER_LABELS = {
${objectLiteralEntries(headerLabelByCanonical)}
}
const LANGUAGE_LOGO_KEYS = {
${objectLiteralEntries(logoKeyByCanonical)}
}
const ALL_KNOWN_LANGUAGE_IDS = new Set(${JSON.stringify(canonicalLanguages.map((language) => language.id))})
const BUNDLED_LANGUAGE_MODULES = {
${bundledLanguageEntries}
}
const loadedLanguageIDs = new Set()

let highlighterPromise = null
let highlighter = null

function unwrapLanguageModule(moduleValue) {
  const value = moduleValue && moduleValue.default ? moduleValue.default : moduleValue
  return Array.isArray(value) ? value : [value]
}

function toRawLanguageName(language) {
  return String(language || '').trim().toLowerCase()
}

function resolveCanonicalLanguage(language) {
  const raw = toRawLanguageName(language)
  if (!raw) return ''
  const canonical = LANGUAGE_ALIAS_TO_CANONICAL[raw] || raw
  return ALL_KNOWN_LANGUAGE_IDS.has(canonical) ? canonical : ''
}

function normalizeLanguage(language) {
  return resolveCanonicalLanguage(language) || 'txt'
}

function languageLabel(language) {
  const raw = toRawLanguageName(language)
  if (!raw) return 'txt'
  const canonical = resolveCanonicalLanguage(raw)
  if (!canonical) return raw
  return LANGUAGE_HEADER_LABELS[canonical] || canonical
}

function languageLogoKey(language) {
  const raw = toRawLanguageName(language)
  if (!raw) return 'txt'
  const canonical = resolveCanonicalLanguage(raw)
  if (!canonical) return raw
  return LANGUAGE_LOGO_KEYS[canonical] || canonical
}

function languageDefinitionsFor(id) {
  const moduleValue = BUNDLED_LANGUAGE_MODULES[id]
  return moduleValue ? unwrapLanguageModule(moduleValue) : []
}

async function ensureHighlighter() {
  if (highlighter) return highlighter
  if (!highlighterPromise) {
    highlighterPromise = Promise.resolve().then(async () => {
      highlighter = await createHighlighterCore({
        engine: createJavaScriptRawEngine(),
        themes: [githubLightDefault, githubDarkDefault],
        langs: STARTER_LANGUAGE_IDS.flatMap((id) => languageDefinitionsFor(id))
      })
      STARTER_LANGUAGE_IDS.forEach((id) => loadedLanguageIDs.add(id))
      return highlighter
    })
  }
  return highlighterPromise
}

async function ensureLanguagesLoaded(languages) {
  const canonicalIDs = [...new Set(
    (languages || [])
      .map((language) => resolveCanonicalLanguage(language))
      .filter((canonical) => canonical && !loadedLanguageIDs.has(canonical))
  )]

  if (!canonicalIDs.length) return false

  const instance = await ensureHighlighter()
  const definitions = canonicalIDs.flatMap((id) => languageDefinitionsFor(id))
  if (!definitions.length) return false

  await instance.loadLanguage(...definitions)
  canonicalIDs.forEach((id) => loadedLanguageIDs.add(id))
  return true
}

function highlightCodeToHtmlIfReady(code, language) {
  if (!highlighter) return ''
  const canonical = resolveCanonicalLanguage(language) || 'txt'
  if (canonical !== 'txt' && !loadedLanguageIDs.has(canonical)) return ''

  try {
    return highlighter.codeToHtml(String(code ?? ''), {
      lang: canonical,
      themes: {
        light: THEME_NAMES.light,
        dark: THEME_NAMES.dark
      },
      defaultColor: false
    })
  } catch {
    return ''
  }
}

window.JinShiki = {
  prepareHighlighter: async () => {
    try {
      return !!(await ensureHighlighter())
    } catch (error) {
      console.warn('[JinShiki] failed to prepare highlighter', error)
      return false
    }
  },
  ensureLanguagesLoaded,
  highlightCodeToHtmlIfReady,
  normalizeLanguage,
  languageLabel,
  languageLogoKey
}
`
}

async function writeManifest(canonicalLanguages) {
  const manifest = {
    generator: 'Tools/MarkdownRuntime/build-shiki-runtime.mjs',
    shikiVersion: shikiPackageVersion,
    themeIDs: ['github-light-default', 'github-dark-default'],
    starterLanguageIDs,
    canonicalLanguages,
    customAliases,
    customLabels,
    customLogoKeys
  }

  await fs.writeFile(manifestFilePath, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8')
}

async function cleanOutput() {
  await fs.rm(runtimeFilePath, { force: true })
  await fs.rm(path.join(resourcesDir, 'markdown-shiki-runtime-chunks'), { recursive: true, force: true })
  await fs.rm(manifestFilePath, { force: true })
}

async function main() {
  const { canonicalLanguages, aliasToCanonical } = buildLanguageMetadata()
  const runtimeSource = buildRuntimeSource(canonicalLanguages, aliasToCanonical)
  const temporaryEntryPath = path.join(scriptDir, '.__markdown-shiki-runtime-entry.mjs')

  await cleanOutput()
  await fs.writeFile(temporaryEntryPath, runtimeSource, 'utf8')

  try {
    await build({
      entryPoints: [temporaryEntryPath],
      bundle: true,
      format: 'iife',
      globalName: 'JinShikiRuntimeBundle',
      platform: 'browser',
      target: ['es2020'],
      minify: true,
      entryNames: runtimeFileName.replace(/\.js$/, ''),
      outdir: resourcesDir,
      write: true,
      logLevel: 'info'
    })
  } finally {
    await fs.rm(temporaryEntryPath, { force: true })
  }

  await writeManifest(canonicalLanguages)
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
