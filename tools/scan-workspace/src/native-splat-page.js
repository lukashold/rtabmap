import { SplatViewer } from './splat-viewer.js';
import { decodeNativeSplatMessage } from './native-splat-data.js';
import { decodeSplat, syntheticSplatDemo } from './splat-data.js';
import { dictionaries, resolveLanguage } from './i18n.js';
import { uxDictionaries } from './ux-i18n.js';

const $ = id => document.getElementById(id);
let viewer, sequence = 0, language = resolveLanguage(navigator.language), loading = false;
const t = key => uxDictionaries[language]?.[key] || dictionaries[language]?.[key] || key;
function notify(message) { globalThis.webkit?.messageHandlers?.kanturaSplat?.postMessage(message); }
function translate() {
  document.documentElement.lang = language; document.documentElement.dir = language === 'ar' ? 'rtl' : 'ltr';
  $('title').textContent = t('splatTitle'); $('help').textContent = t('splatHelp'); $('navigation').textContent = t('mobileNavigateHint');
  $('fit').textContent = t('fit'); $('demo').textContent = t('splatDemo');
  $('stage').setAttribute('aria-label', t('splatTitle')); $('demo').disabled = loading; $('fit').disabled = loading || !viewer;
}
function reportError(error, rendering = false) {
  const code = error?.code === 'splatLimit' ? 'splatLimit' : rendering ? 'viewerUnavailable' : 'splatInvalid';
  const message = t(code).replace('200', '32'); $('status').textContent = message;
  notify({ type: 'error', code, message });
}
async function loadData(data) {
  const attempt = ++sequence; loading = true; translate();
  $('status').textContent = t('working'); notify({ type: 'status', state: 'loading', name: data.name, message: t('working') });
  let instance;
  try {
    const old = viewer; viewer = undefined; await old?.dispose(); if (attempt !== sequence) return false;
    $('stage').replaceChildren();
    instance = new SplatViewer($('stage'), error => { if (attempt === sequence) reportError(error, true); }); viewer = instance;
    instance.renderer.domElement.setAttribute('aria-label', t('splatTitle'));
    await instance.load(data); if (attempt !== sequence) return false;
    $('status').textContent = data.name; notify({ type: 'status', state: 'ready', name: data.name, count: data.count, message: data.name }); return true;
  } catch (error) {
    if (attempt === sequence) { reportError(error, true); if (viewer === instance) viewer = undefined; await instance?.dispose(); }
    return false;
  } finally { if (attempt === sequence) { loading = false; translate(); } }
}
window.configureKanturaSplat = options => {
  if (typeof options?.language === 'string') language = resolveLanguage(options.language);
  translate();
  return true;
};
window.loadKanturaSplat = async message => {
  if (typeof message?.language === 'string') language = resolveLanguage(message.language);
  translate();
  // Invalid replacements do not discard the currently displayed scene.
  let data;
  try { data = decodeNativeSplatMessage(message); } catch (error) { reportError(error); return false; }
  return loadData(data);
};
$('fit').onclick = () => viewer?.fit();
$('demo').onclick = () => loadData(decodeSplat(syntheticSplatDemo(), 'kantura-synthetic-demo.splat'));
window.addEventListener('pagehide', () => { ++sequence; const old = viewer; viewer = undefined; old?.dispose(); });
translate(); notify({ type: 'ready' });
