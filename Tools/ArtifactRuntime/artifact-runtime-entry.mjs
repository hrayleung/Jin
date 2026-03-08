import * as React from 'react'
import { createRoot } from 'react-dom/client'
import * as Babel from '@babel/standalone'
import * as echarts from 'echarts'
import createDOMPurify from 'dompurify'

const rootEl = document.getElementById('artifact-root')
const statusEl = document.getElementById('artifact-status')
const titleEl = document.getElementById('artifact-title')
const subtitleEl = document.getElementById('artifact-subtitle')
const purifier = createDOMPurify(window)

let currentCleanup = null
let currentResizeObserver = null
let currentWindowResizeHandler = null

function setStatus(text) {
  if (!statusEl) return
  statusEl.textContent = text || ''
}

function setMetadata(payload) {
  if (titleEl) {
    titleEl.textContent = payload?.title || 'Artifact'
  }
  if (subtitleEl) {
    subtitleEl.textContent = payload?.contentType || ''
  }
}

function clearContainer() {
  if (typeof currentCleanup === 'function') {
    try {
      currentCleanup()
    } catch (_) {
      // Ignore cleanup failures so the next artifact still renders.
    }
  }
  if (currentResizeObserver) {
    currentResizeObserver.disconnect()
    currentResizeObserver = null
  }
  if (currentWindowResizeHandler) {
    window.removeEventListener('resize', currentWindowResizeHandler)
    currentWindowResizeHandler = null
  }
  currentCleanup = null
  if (rootEl) {
    rootEl.innerHTML = ''
  }
}

function renderError(message) {
  clearContainer()
  setStatus('Render failed')
  const pre = document.createElement('pre')
  pre.className = 'artifact-error'
  pre.textContent = message || 'Render failed.'
  rootEl?.appendChild(pre)
}

function sanitizeMarkup(markup, options = {}) {
  return purifier.sanitize(markup, {
    RETURN_TRUSTED_TYPE: false,
    ...options
  })
}

function renderHTML(content) {
  clearContainer()
  setStatus('')
  rootEl.innerHTML = sanitizeMarkup(content, {
    USE_PROFILES: { html: true }
  })
}

function renderECharts(content) {
  clearContainer()
  setStatus('')

  const option = JSON.parse(content || '{}')
  const chartEl = document.createElement('div')
  chartEl.className = 'artifact-chart'
  rootEl?.appendChild(chartEl)

  const chart = echarts.init(chartEl, null, { renderer: 'canvas' })
  chart.setOption(option, true)

  const resize = () => chart.resize()
  currentWindowResizeHandler = resize
  window.addEventListener('resize', resize)

  currentResizeObserver = new ResizeObserver(() => {
    chart.resize()
  })
  currentResizeObserver.observe(chartEl)

  currentCleanup = () => {
    chart.dispose()
  }
}

function transpileReactSource(source) {
  return Babel.transform(source, {
    filename: 'artifact.tsx',
    presets: [
      ['react', { runtime: 'classic' }],
      'typescript'
    ],
    plugins: ['transform-modules-commonjs']
  }).code
}

function createArtifactRequire() {
  const reactModule = {
    __esModule: true,
    default: React,
    ...React
  }
  const reactDOMClientModule = {
    __esModule: true,
    createRoot
  }
  const jsxRuntimeModule = {
    __esModule: true,
    Fragment: React.Fragment,
    jsx: React.createElement,
    jsxs: React.createElement
  }
  const echartsModule = {
    __esModule: true,
    default: echarts,
    ...echarts
  }

  return (specifier) => {
    switch (specifier) {
      case 'react':
        return reactModule
      case 'react-dom/client':
        return reactDOMClientModule
      case 'react/jsx-runtime':
      case 'react/jsx-dev-runtime':
        return jsxRuntimeModule
      case 'echarts':
        return echartsModule
      default:
        throw new Error(`Unsupported import: ${specifier}`)
    }
  }
}

function renderReact(content) {
  clearContainer()
  setStatus('')

  const mount = document.createElement('div')
  mount.className = 'artifact-react-root'
  rootEl?.appendChild(mount)

  const transpiled = transpileReactSource(content || '')
  const module = { exports: {} }
  const exports = module.exports
  const require = createArtifactRequire()

  const Component = new Function(
    'React',
    'require',
    'module',
    'exports',
    `const { useState, useEffect, useMemo, useRef, useReducer, useContext, useLayoutEffect, useDeferredValue, useTransition, useId } = React;
    ${transpiled}
    const candidate = typeof ArtifactApp !== 'undefined'
      ? ArtifactApp
      : (module.exports && (module.exports.default || module.exports.ArtifactApp))
        || (exports && (exports.default || exports.ArtifactApp));
    if (!candidate) {
      throw new Error('React artifacts must define a top-level ArtifactApp component.');
    }
    return candidate;
  `
  )(React, require, module, exports)

  const root = createRoot(mount)
  root.render(React.createElement(Component))
  currentCleanup = () => {
    root.unmount()
  }
}

async function renderArtifact(payload) {
  setMetadata(payload)

  try {
    switch (payload?.contentType) {
      case 'text/html':
        renderHTML(payload.content)
        break
      case 'application/vnd.jin.echarts.option+json':
        renderECharts(payload.content)
        break
      case 'application/vnd.jin.react':
        renderReact(payload.content)
        break
      default:
        throw new Error(`Unsupported artifact type: ${payload?.contentType || '(missing)'}`)
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    renderError(message)
  }
}

window.renderArtifact = renderArtifact
