import { build } from 'esbuild'
import fs from 'node:fs/promises'
import path from 'node:path'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'

const require = createRequire(import.meta.url)
const scriptDir = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(scriptDir, '..', '..')
const resourcesDir = path.join(repoRoot, 'Sources', 'Resources')
const runtimeFileName = 'markdown-hljs-runtime.js'
const manifestFileName = 'markdown-hljs-manifest.json'
const runtimeFilePath = path.join(resourcesDir, runtimeFileName)
const manifestFilePath = path.join(resourcesDir, manifestFileName)

// Map from our canonical language IDs to highlight.js module names.
// Languages not listed here will fall back to plain text.
const HLJS_LANGUAGE_MAP = {
  // Common languages
  'markdown': 'markdown',
  'shellscript': 'bash',
  'json': 'json',
  'yaml': 'yaml',
  'javascript': 'javascript',
  'typescript': 'typescript',
  'swift': 'swift',
  'python': 'python',
  'go': 'go',
  'java': 'java',
  'html': 'xml',
  'css': 'css',
  'xml': 'xml',
  'sql': 'sql',

  // C family
  'c': 'c',
  'cpp': 'cpp',
  'csharp': 'csharp',
  'objective-c': 'objectivec',

  // Modern systems
  'rust': 'rust',
  'nim': 'nim',
  'crystal': 'crystal',
  'v': 'go',
  'odin': 'go',

  // JVM
  'kotlin': 'kotlin',
  'scala': 'scala',
  'groovy': 'groovy',

  // Scripting
  'ruby': 'ruby',
  'php': 'php',
  'perl': 'perl',
  'lua': 'lua',
  'r': 'r',

  // Functional
  'haskell': 'haskell',
  'elixir': 'elixir',
  'erlang': 'erlang',
  'clojure': 'clojure',
  'ocaml': 'ocaml',
  'fsharp': 'fsharp',
  'julia': 'julia',
  'common-lisp': 'lisp',
  'scheme': 'scheme',
  'racket': 'scheme',
  'purescript': 'haskell',
  'elm': 'elm',
  'sml': 'sml',
  'reasonml': 'reasonml',
  'emacs-lisp': 'lisp',
  'fennel': 'lisp',
  'janet': 'lisp',
  'idris': 'haskell',
  'lean': 'haskell',
  'dhall': 'haskell',
  'coq': 'coq',

  // Mobile
  'dart': 'dart',

  // Web
  'jsx': 'javascript',
  'tsx': 'typescript',
  'vue': 'xml',
  'vue-html': 'xml',
  'svelte': 'xml',
  'astro': 'xml',
  'angular-html': 'xml',
  'angular-ts': 'typescript',
  'scss': 'scss',
  'sass': 'scss',
  'less': 'less',
  'stylus': 'stylus',
  'postcss': 'css',
  'handlebars': 'handlebars',
  'twig': 'twig',
  'erb': 'erb',
  'pug': 'xml',
  'blade': 'php',
  'liquid': 'xml',
  'haml': 'haml',

  // Shell variants
  'shellsession': 'shell',
  'powershell': 'powershell',
  'bat': 'dos',
  'fish': 'bash',
  'nushell': 'bash',

  // Config & DevOps
  'dockerfile': 'dockerfile',
  'docker': 'dockerfile',
  'toml': 'ini',
  'ini': 'ini',
  'nginx': 'nginx',
  'terraform': 'ini',
  'hcl': 'ini',
  'cmake': 'cmake',
  'make': 'makefile',
  'nix': 'nix',
  'dotenv': 'ini',
  'ssh-config': 'ini',

  // Data formats
  'jsonc': 'json',
  'json5': 'json',
  'jsonl': 'json',
  'jsonnet': 'json',
  'graphql': 'graphql',
  'proto': 'protobuf',
  'csv': 'plaintext',

  // Markup & Documentation
  'latex': 'latex',
  'tex': 'latex',
  'asciidoc': 'asciidoc',
  'mdx': 'markdown',
  'rst': 'markdown',
  'typst': 'latex',

  // Diff & Utilities
  'diff': 'diff',
  'http': 'http',
  'llvm': 'llvm',

  // Editor & game dev
  'viml': 'vim',
  'gdscript': 'python',
  'gdresource': 'ini',

  // Low-level & GPU
  'wasm': 'wasm',
  'asm': 'x86asm',
  'mipsasm': 'mipsasm',
  'glsl': 'glsl',
  'hlsl': 'glsl',
  'wgsl': 'glsl',

  // Hardware description
  'verilog': 'verilog',
  'system-verilog': 'verilog',
  'vhdl': 'vhdl',

  // Other notable
  'applescript': 'applescript',
  'coffee': 'coffeescript',
  'fortran-free-form': 'fortran',
  'fortran-fixed-form': 'fortran',
  'prolog': 'prolog',
  'matlab': 'matlab',
  'tcl': 'tcl',
  'ada': 'ada',
  'wolfram': 'mathematica',
  'pascal': 'delphi',
  'cobol': 'plaintext',
  'pgsql': 'pgsql',
  'qml': 'qml',
  'd': 'd',
  'puppet': 'puppet',
  'smalltalk': 'smalltalk',
  'stata': 'stata',
  'sas': 'sas',
  'vala': 'vala',
  'vbnet': 'vbnet',
  'awk': 'awk',
  'raku': 'perl',
  'hack': 'php',
  'motoko': 'rust',
  'solidity': 'javascript',
  'starlark': 'python',
  'bicep': 'json',
  'cue': 'yaml',
  'processing': 'processing',
}

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
  'mermaid-svg': 'mermaid',
  elisp: 'emacs-lisp',
  wat: 'wasm',
  nu: 'nushell',
  vim: 'viml',
  vimscript: 'viml',
  'perl6': 'raku',
  bazel: 'starlark',
  delphi: 'pascal',
  'objective-cpp': 'cpp',
  hlsl: 'hlsl',
  wgsl: 'wgsl',
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
  'emacs-lisp': 'elisp',
  fennel: 'fennel',
  janet: 'janet',
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

const hljsPackageVersion = require('highlight.js/package.json').version

// Collect all unique highlight.js module names we need to import.
function getUniqueHljsModules() {
  const modules = new Set()
  for (const hljsName of Object.values(HLJS_LANGUAGE_MAP)) {
    if (hljsName !== 'plaintext') {
      modules.add(hljsName)
    }
  }
  return [...modules].sort()
}

// Build the alias-to-canonical mapping.
// We keep all canonical language IDs from highlight.js + our custom aliases.
function buildLanguageMetadata() {
  const allCanonicalIDs = new Set(Object.keys(HLJS_LANGUAGE_MAP))

  // Also include IDs that only appear in customAliases targets
  for (const canonical of Object.values(customAliases)) {
    allCanonicalIDs.add(canonical)
  }

  const aliasToCanonical = Object.create(null)
  for (const id of allCanonicalIDs) {
    aliasToCanonical[id] = id
  }
  for (const [alias, canonical] of Object.entries(customAliases)) {
    aliasToCanonical[alias] = canonical
  }

  const canonicalLanguages = [...allCanonicalIDs]
    .sort()
    .map((id) => ({ id, name: id, aliases: [] }))

  return { canonicalLanguages, aliasToCanonical }
}

function objectLiteralEntries(values) {
  return Object.entries(values)
    .sort(([lhs], [rhs]) => lhs.localeCompare(rhs))
    .map(([key, value]) => `  ${JSON.stringify(key)}: ${JSON.stringify(value)}`)
    .join(',\n')
}

function buildRuntimeSource() {
  const hljsModules = getUniqueHljsModules()
  const { aliasToCanonical } = buildLanguageMetadata()

  const languageImports = hljsModules
    .map((mod, i) => `import lang_${i} from 'highlight.js/lib/languages/${mod}'`)
    .join('\n')

  const languageRegistrations = hljsModules
    .map((mod, i) => `hljs.registerLanguage(${JSON.stringify(mod)}, lang_${i})`)
    .join('\n')

  // Build a map from our canonical IDs to the hljs language name for highlighting.
  const canonicalToHljsEntries = Object.entries(HLJS_LANGUAGE_MAP)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([canonical, hljsName]) => `  ${JSON.stringify(canonical)}: ${JSON.stringify(hljsName)}`)
    .join(',\n')

  const headerLabelByCanonical = {}
  for (const id of Object.keys(HLJS_LANGUAGE_MAP)) {
    headerLabelByCanonical[id] = customLabels[id] || id
  }
  // Include aliases targets that aren't in HLJS_LANGUAGE_MAP
  for (const canonical of Object.values(customAliases)) {
    if (!(canonical in headerLabelByCanonical)) {
      headerLabelByCanonical[canonical] = customLabels[canonical] || canonical
    }
  }

  const logoKeyByCanonical = {}
  for (const id of Object.keys(HLJS_LANGUAGE_MAP)) {
    logoKeyByCanonical[id] = customLogoKeys[id] || id
  }
  for (const canonical of Object.values(customAliases)) {
    if (!(canonical in logoKeyByCanonical)) {
      logoKeyByCanonical[canonical] = customLogoKeys[canonical] || canonical
    }
  }

  return `import hljs from 'highlight.js/lib/core'
${languageImports}

${languageRegistrations}

const LANGUAGE_ALIAS_TO_CANONICAL = {
${objectLiteralEntries(aliasToCanonical)}
}
const CANONICAL_TO_HLJS = {
${canonicalToHljsEntries}
}
const LANGUAGE_HEADER_LABELS = {
${objectLiteralEntries(headerLabelByCanonical)}
}
const LANGUAGE_LOGO_KEYS = {
${objectLiteralEntries(logoKeyByCanonical)}
}
const ALL_KNOWN_LANGUAGE_IDS = new Set(${JSON.stringify(Object.keys(HLJS_LANGUAGE_MAP).sort())})

function toRawLanguageName(language) {
  return String(language || '').trim().toLowerCase()
}

function resolveCanonicalLanguage(language) {
  var raw = toRawLanguageName(language)
  if (!raw) return ''
  var canonical = LANGUAGE_ALIAS_TO_CANONICAL[raw] || raw
  return ALL_KNOWN_LANGUAGE_IDS.has(canonical) ? canonical : ''
}

function normalizeLanguage(language) {
  return resolveCanonicalLanguage(language) || 'txt'
}

function languageLabel(language) {
  var raw = toRawLanguageName(language)
  if (!raw) return 'txt'
  var canonical = resolveCanonicalLanguage(raw)
  if (!canonical) return raw
  return LANGUAGE_HEADER_LABELS[canonical] || canonical
}

function languageLogoKey(language) {
  var raw = toRawLanguageName(language)
  if (!raw) return 'txt'
  var canonical = resolveCanonicalLanguage(raw)
  if (!canonical) return raw
  return LANGUAGE_LOGO_KEYS[canonical] || canonical
}

function highlightCode(code, language) {
  var canonical = resolveCanonicalLanguage(language)
  var hljsLang = canonical ? CANONICAL_TO_HLJS[canonical] : ''
  if (!hljsLang || hljsLang === 'plaintext') return ''

  try {
    var result = hljs.highlight(String(code || ''), { language: hljsLang, ignoreIllegals: true })
    return result.value || ''
  } catch (e) {
    return ''
  }
}

window.JinHljs = {
  highlightCode: highlightCode,
  normalizeLanguage: normalizeLanguage,
  languageLabel: languageLabel,
  languageLogoKey: languageLogoKey
}
`
}

async function writeManifest(canonicalLanguages) {
  const manifest = {
    generator: 'Tools/MarkdownRuntime/build-hljs-runtime.mjs',
    hljsVersion: hljsPackageVersion,
    canonicalLanguages,
    customAliases,
    customLabels,
    customLogoKeys
  }

  await fs.writeFile(manifestFilePath, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8')
}

async function cleanOutput() {
  await fs.rm(runtimeFilePath, { force: true })
  await fs.rm(manifestFilePath, { force: true })
  // Also remove old Shiki files if present
  const oldShikiRuntime = path.join(resourcesDir, 'markdown-shiki-runtime.js')
  const oldShikiManifest = path.join(resourcesDir, 'markdown-shiki-manifest.json')
  const oldShikiChunks = path.join(resourcesDir, 'markdown-shiki-runtime-chunks')
  await fs.rm(oldShikiRuntime, { force: true })
  await fs.rm(oldShikiManifest, { force: true })
  await fs.rm(oldShikiChunks, { recursive: true, force: true })
}

async function main() {
  const { canonicalLanguages } = buildLanguageMetadata()
  const runtimeSource = buildRuntimeSource()
  const temporaryEntryPath = path.join(scriptDir, '.__markdown-hljs-runtime-entry.mjs')

  await cleanOutput()
  await fs.writeFile(temporaryEntryPath, runtimeSource, 'utf8')

  try {
    await build({
      entryPoints: [temporaryEntryPath],
      bundle: true,
      format: 'iife',
      globalName: 'JinHljsRuntimeBundle',
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
