import { build } from 'esbuild'
import fs from 'node:fs/promises'
import path from 'node:path'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'

const require = createRequire(import.meta.url)
const scriptDir = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(scriptDir, '..', '..')
const resourcesDir = path.join(repoRoot, 'Sources', 'Resources')
const runtimeFileName = 'markdown-prism-runtime.js'
const manifestFileName = 'markdown-prism-manifest.json'
const runtimeFilePath = path.join(resourcesDir, runtimeFileName)
const manifestFilePath = path.join(resourcesDir, manifestFileName)

const prismPackageVersion = require('prismjs/package.json').version
const prismComponents = require('prismjs/components.json')
const getPrismLoader = require('prismjs/dependencies')
const prismLanguageEntries = prismComponents.languages
const officialPrismLanguageIDs = Object.keys(prismLanguageEntries)
  .filter((id) => id !== 'meta')
  .sort()

// Project-level canonical IDs which should preserve labels/logos or map
// unsupported fence names to the closest Prism grammar.
const CUSTOM_CANONICAL_TO_PRISM = {
  txt: '',
  html: 'markup',
  xml: 'markup',
  svg: 'markup',
  shellscript: 'bash',
  shellsession: 'shell-session',
  coffee: 'coffeescript',
  dockerfile: 'docker',
  'objective-c': 'objectivec',
  'common-lisp': 'lisp',
  'emacs-lisp': 'lisp',
  fennel: 'lisp',
  janet: 'lisp',
  'fortran-fixed-form': 'fortran',
  'fortran-free-form': 'fortran',
  gdresource: 'ini',
  jsonc: 'json5',
  jsonl: 'json',
  jsonnet: 'javascript',
  bat: 'batch',
  make: 'makefile',
  proto: 'protobuf',
  pgsql: 'sql',
  postcss: 'css',
  'angular-html': 'markup',
  'angular-ts': 'typescript',
  vue: 'markup',
  'vue-html': 'markup',
  svelte: 'markup',
  astro: 'markup',
  blade: 'php',
  terraform: 'hcl',
  'ssh-config': 'ini',
  mdx: 'markdown',
  rst: 'markdown',
  tex: 'latex',
  typst: 'latex',
  'system-verilog': 'verilog',
  reasonml: 'reason',
  fish: 'bash',
  nushell: 'bash',
  hack: 'php',
  raku: 'perl',
  starlark: 'python',
  asm: 'nasm',
  mipsasm: 'nasm',
  lean: 'haskell',
  motoko: 'rust',
  viml: 'vim'
}

const customAliases = {
  plain: 'txt',
  plaintext: 'txt',
  text: 'txt',
  shell: 'shellscript',
  zsh: 'shellscript',
  console: 'shellsession',
  terminal: 'shellsession',
  'sh-session': 'shellsession',
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
  assembly: 'asm',
  x86: 'asm',
  x86asm: 'asm',
  'assembly-x86': 'asm',
  mermaidsvg: 'mermaid',
  'mermaid-svg': 'mermaid',
  elisp: 'emacs-lisp',
  wat: 'wasm',
  nu: 'nushell',
  vim: 'viml',
  vimscript: 'viml',
  perl6: 'raku',
  bazel: 'starlark',
  delphi: 'pascal'
}

const customLabels = {
  txt: 'txt',
  shellscript: 'bash',
  shellsession: 'console',
  'common-lisp': 'common-lisp',
  'emacs-lisp': 'emacs-lisp',
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
  jsonnet: 'jsonnet',
  'angular-html': 'angular',
  'angular-ts': 'angular',
  vue: 'vue',
  'vue-html': 'vue',
  svelte: 'svelte',
  astro: 'astro',
  coffee: 'coffeescript',
  erb: 'ruby',
  blade: 'php',
  liquid: 'ruby',
  hcl: 'terraform',
  terraform: 'terraform',
  mdx: 'markdown',
  rst: 'markdown',
  asciidoc: 'markdown',
  tex: 'latex',
  typst: 'latex',
  'system-verilog': 'verilog',
  vhdl: 'verilog',
  glsl: 'wgsl',
  hlsl: 'wgsl',
  postcss: 'css',
  pgsql: 'sql',
  proto: 'protobuf',
  nushell: 'nushell',
  fish: 'fish',
  hack: 'hack',
  raku: 'raku',
  reasonml: 'reasonml',
  starlark: 'starlark',
  viml: 'vim'
}

function normalizeArray(value) {
  if (Array.isArray(value)) return value
  if (value == null) return []
  return [value]
}

function objectLiteralEntries(values) {
  return Object.entries(values)
    .sort(([lhs], [rhs]) => lhs.localeCompare(rhs))
    .map(([key, value]) => `  ${JSON.stringify(key)}: ${JSON.stringify(value)}`)
    .join(',\n')
}

function buildCanonicalToPrism() {
  const canonicalToPrism = Object.create(null)

  for (const id of officialPrismLanguageIDs) {
    canonicalToPrism[id] = id
  }

  for (const [canonical, prismLanguage] of Object.entries(CUSTOM_CANONICAL_TO_PRISM)) {
    canonicalToPrism[canonical] = prismLanguage
  }

  return canonicalToPrism
}

function buildOfficialAliasToCanonical() {
  const aliasToCanonical = Object.create(null)

  for (const id of officialPrismLanguageIDs) {
    aliasToCanonical[id] = id

    const entry = prismLanguageEntries[id]
    if (typeof entry === 'string') continue

    for (const alias of normalizeArray(entry.alias)) {
      aliasToCanonical[alias] = id
    }
  }

  return aliasToCanonical
}

function buildLanguageMetadata() {
  const canonicalToPrism = buildCanonicalToPrism()
  const allCanonicalIDs = new Set(Object.keys(canonicalToPrism))
  const aliasToCanonical = Object.create(null)

  for (const id of allCanonicalIDs) {
    aliasToCanonical[id] = id
  }

  for (const [alias, canonical] of Object.entries(buildOfficialAliasToCanonical())) {
    if (!(alias in aliasToCanonical)) {
      aliasToCanonical[alias] = canonical
    }
  }

  for (const [alias, canonical] of Object.entries(customAliases)) {
    aliasToCanonical[alias] = canonical
  }

  for (const canonical of Object.values(aliasToCanonical)) {
    allCanonicalIDs.add(canonical)
  }

  for (const canonical of allCanonicalIDs) {
    if (!(canonical in canonicalToPrism)) {
      throw new Error(`Alias target ${canonical} is missing from canonical language mappings`)
    }
  }

  const aliasesByCanonical = Object.create(null)
  for (const canonical of allCanonicalIDs) {
    aliasesByCanonical[canonical] = []
  }

  for (const [alias, canonical] of Object.entries(aliasToCanonical)) {
    if (alias !== canonical) {
      aliasesByCanonical[canonical].push(alias)
    }
  }

  const canonicalLanguages = [...allCanonicalIDs]
    .sort()
    .map((id) => ({
      id,
      name: id,
      aliases: aliasesByCanonical[id].sort()
    }))

  return { canonicalLanguages, aliasToCanonical, canonicalToPrism }
}

function buildHeaderLabelByCanonical(canonicalToPrism) {
  const headerLabelByCanonical = Object.create(null)

  for (const id of Object.keys(canonicalToPrism)) {
    headerLabelByCanonical[id] = customLabels[id] || id
  }

  return headerLabelByCanonical
}

function buildLogoKeyByCanonical(canonicalToPrism) {
  const logoKeyByCanonical = Object.create(null)

  for (const id of Object.keys(canonicalToPrism)) {
    logoKeyByCanonical[id] = customLogoKeys[id] || id
  }

  return logoKeyByCanonical
}

function getPrismLanguageLoadOrder() {
  const loader = getPrismLoader(prismComponents, officialPrismLanguageIDs, [])
  return loader.getIds()
}

function buildRuntimeSource() {
  const { aliasToCanonical, canonicalToPrism } = buildLanguageMetadata()
  const headerLabelByCanonical = buildHeaderLabelByCanonical(canonicalToPrism)
  const logoKeyByCanonical = buildLogoKeyByCanonical(canonicalToPrism)
  const prismLoadOrder = getPrismLanguageLoadOrder()

  for (const prismLanguage of Object.values(canonicalToPrism)) {
    if (!prismLanguage) continue
    if (!officialPrismLanguageIDs.includes(prismLanguage)) {
      throw new Error(`Unknown Prism language mapping target: ${prismLanguage}`)
    }
  }

  const languageRequires = prismLoadOrder
    .map((id) => `require('prismjs/components/prism-${id}')`)
    .join('\n')

  return `const Prism = require('prismjs/components/prism-core')
if (typeof globalThis !== 'undefined') {
  globalThis.Prism = Prism
}
if (typeof window !== 'undefined') {
  window.Prism = Prism
}
${languageRequires}

const LANGUAGE_ALIAS_TO_CANONICAL = {
${objectLiteralEntries(aliasToCanonical)}
}
const CANONICAL_TO_PRISM = {
${objectLiteralEntries(canonicalToPrism)}
}
const LANGUAGE_HEADER_LABELS = {
${objectLiteralEntries(headerLabelByCanonical)}
}
const LANGUAGE_LOGO_KEYS = {
${objectLiteralEntries(logoKeyByCanonical)}
}
const ALL_KNOWN_LANGUAGE_IDS = new Set(${JSON.stringify(Object.keys(canonicalToPrism).sort())})

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
  var prismLanguage = canonical ? CANONICAL_TO_PRISM[canonical] : ''
  if (!prismLanguage) return ''

  var grammar = Prism.languages[prismLanguage]
  if (!grammar) return ''

  try {
    return Prism.highlight(String(code || ''), grammar, prismLanguage) || ''
  } catch (e) {
    return ''
  }
}

window.JinPrism = {
  highlightCode: highlightCode,
  normalizeLanguage: normalizeLanguage,
  languageLabel: languageLabel,
  languageLogoKey: languageLogoKey
}

window.JinCodeHighlighter = window.JinPrism
`
}

async function writeManifest(canonicalLanguages) {
  const manifest = {
    generator: 'Tools/MarkdownRuntime/build-prism-runtime.mjs',
    prismVersion: prismPackageVersion,
    canonicalLanguages,
    customCanonicalToPrism: CUSTOM_CANONICAL_TO_PRISM,
    customAliases,
    customLabels,
    customLogoKeys
  }

  await fs.writeFile(manifestFilePath, `${JSON.stringify(manifest, null, 2)}\n`, 'utf8')
}

async function cleanOutput() {
  const stalePaths = [
    runtimeFilePath,
    manifestFilePath,
    path.join(resourcesDir, 'markdown-hljs-runtime.js'),
    path.join(resourcesDir, 'markdown-hljs-manifest.json'),
    path.join(resourcesDir, 'markdown-shiki-runtime.js'),
    path.join(resourcesDir, 'markdown-shiki-manifest.json'),
    path.join(resourcesDir, 'markdown-shiki-runtime-chunks')
  ]

  for (const stalePath of stalePaths) {
    await fs.rm(stalePath, { recursive: true, force: true })
  }
}

async function main() {
  const { canonicalLanguages } = buildLanguageMetadata()
  const runtimeSource = buildRuntimeSource()
  const temporaryEntryPath = path.join(scriptDir, '.__markdown-prism-runtime-entry.cjs')

  await cleanOutput()
  await fs.writeFile(temporaryEntryPath, runtimeSource, 'utf8')

  try {
    await build({
      entryPoints: [temporaryEntryPath],
      bundle: true,
      format: 'iife',
      globalName: 'JinPrismRuntimeBundle',
      platform: 'browser',
      target: ['es2020'],
      minify: true,
      legalComments: 'none',
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
