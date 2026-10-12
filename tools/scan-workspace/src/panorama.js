import { inspectPanoramaFile, decodePanoramaFile, syntheticPanoramaFile, MAX_PANORAMA_VIEWS } from './panorama-data.js';
import { PanoramaViewer } from './panorama-viewer.js';
import { panoramaText } from './panorama-i18n.js';

const css = `:host{color:#142f36;background:#fff;font:16px/1.5 system-ui,sans-serif}*{box-sizing:border-box}.content{padding:20px;display:grid;gap:12px}h2,p{margin:0}h2{font-size:1.5rem}.heading,.actions{display:flex;gap:10px;align-items:center;flex-wrap:wrap}.heading{justify-content:space-between}button,select{font:inherit;min-height:44px;border:1px solid #6b8388;border-radius:9px;padding:9px 13px;background:#f4f8f8;color:#142f36;max-width:100%}button{cursor:pointer}button:hover{background:#e1eeeb}button:focus-visible,select:focus-visible{outline:3px solid #087569;outline-offset:2px}button:disabled{opacity:.5;cursor:default}.primary{background:#125c50;color:#fff}.primary:hover{background:#0e493f}.hint{font-size:.9rem;color:#35545a}.limits{background:#fff3d9;border-inline-start:4px solid #88610f;padding:10px}.stage{height:clamp(220px,49vh,500px);min-width:0;position:relative;overflow:hidden;border-radius:12px;background:#10252d}.status{min-height:24px;overflow-wrap:anywhere}.error{color:#a12121;font-weight:600}.views{display:grid;gap:6px}.views select{width:100%}.small{font-size:.85rem}input[type=file]{display:none}@media(max-width:540px){.content{padding:12px}.actions>button{flex:1 1 42%}.stage{height:38vh;min-height:200px}.heading h2{font-size:1.25rem}}`;

/** Independent local-image view. No globals, network, project mutation or storage.
 * Returns {element, ready, load(file), demo(), dispose()}. `ready` resolves null
 * after an initial load error; subsequent load() calls reject with `.code`.
 */
export function openPanorama({ file, language = 'en', onClose = () => {}, onError = () => {} } = {}) {
  const words = panoramaText(language), focusReturn = document.activeElement;
  const dialog = document.createElement('dialog');
  dialog.setAttribute('aria-label', words.title); dialog.lang = language; dialog.dir = language === 'ar' ? 'rtl' : 'ltr';
  dialog.style.cssText = 'width:min(980px,96vw);max-width:96vw;max-height:94dvh;padding:0;border:1px solid #7a9196;border-radius:16px;overflow:auto;background:#fff;';
  const shell = document.createElement('div'); dialog.append(shell);
  const root = shell.attachShadow({ mode: 'open' }), style = document.createElement('style'); style.textContent = css; root.append(style);
  const element = (tag, text, className) => { const node = document.createElement(tag); if (text) node.textContent = text; if (className) node.className = className; return node; };
  const content = element('section', '', 'content'); root.append(content);
  const heading = element('div', '', 'heading'), title = element('h2', words.title), close = element('button', words.close); close.type = 'button'; heading.append(title, close); content.append(heading);
  content.append(element('p', words.help, 'limits'));
  const actions = element('div', '', 'actions'), choose = element('button', words.choose, 'primary'), demoButton = element('button', words.demo), reset = element('button', words.reset), zoomIn = element('button', words.zoomIn), zoomOut = element('button', words.zoomOut), download = element('button', words.download);
  for (const button of [choose, demoButton, reset, zoomIn, zoomOut, download]) { button.type = 'button'; actions.append(button); }
  const input = element('input'); input.type = 'file'; input.accept = '.jpg,.jpeg,.png,image/jpeg,image/png'; input.multiple = true; actions.append(input); content.append(actions);
  const views = element('label', '', 'views'), viewLabel = element('span', words.views), selector = element('select'); views.append(viewLabel, selector); views.hidden = true; content.append(views);
  const viewHelp = element('p', words.viewHelp, 'hint'); viewHelp.hidden = true; content.append(viewHelp);
  const stage = element('div', '', 'stage'); stage.dir = 'ltr'; content.append(stage);
  const status = element('p', words.empty, 'status'); status.setAttribute('role', 'status'); status.setAttribute('aria-live', 'polite'); content.append(status);
  content.append(element('p', words.controls, 'hint'), element('p', words.privacy, 'hint small'));
  let closed = false, viewer, aborter, selected = -1, generation = 0, renderError;
  const entries = [], downloadUrls = new Set();
  const enable = value => { for (const button of [reset, zoomIn, zoomOut, download]) button.disabled = !value; };
  enable(false);
  const report = error => { if (closed || error?.code === 'cancelled') return; status.textContent = words[error?.code] || words.decode; status.className = 'status error'; onError(error); };
  const refresh = () => {
    selector.replaceChildren(...entries.map((item, index) => { const option = element('option', item.name); option.value = String(index); return option; }));
    selector.value = String(selected); views.hidden = entries.length < 2; viewHelp.hidden = entries.length < 2;
  };
  async function display(index) {
    if (closed) throw Object.assign(new Error('cancelled'), { code: 'cancelled' });
    aborter?.abort(); aborter = new AbortController(); const revision = ++generation;
    status.textContent = words.loading; status.className = 'status'; enable(false);
    try {
      const decoded = await decodePanoramaFile(entries[index], { signal: aborter.signal });
      if (closed || revision !== generation) { decoded.dispose(); throw Object.assign(new Error('cancelled'), { code: 'cancelled' }); }
      if (!viewer) {
        try { viewer = new PanoramaViewer(stage, { label: words.controls, onError(error) { renderError = error; enable(false); report(error); } }); }
        catch (error) { decoded.dispose(); throw Object.assign(error, { code: 'webgl' }); }
      }
      renderError = undefined; viewer.load(decoded);
      if (renderError) throw renderError;
      selected = index; refresh(); enable(true);
      status.textContent = `${words.loaded}: ${entries[index].name} · ${decoded.metadata.width}×${decoded.metadata.height}`;
      return decoded.metadata;
    } catch (error) { if (revision === generation) { refresh(); report(error); } throw error; }
  }
  async function load(next) {
    if (closed) throw Object.assign(new Error('cancelled'), { code: 'cancelled' });
    await inspectPanoramaFile(next);
    if (closed) throw Object.assign(new Error('cancelled'), { code: 'cancelled' });
    let index = entries.indexOf(next);
    if (index < 0) { if (entries.length >= MAX_PANORAMA_VIEWS) throw Object.assign(new Error('tooMany'), { code: 'tooMany' }); index = entries.push(next) - 1; }
    return display(index);
  }
  async function demo() { return load(await syntheticPanoramaFile(words.synthetic)); }
  function dispose() {
    if (closed) return; closed = true; generation++; aborter?.abort(); viewer?.dispose();
    entries.length = 0; downloadUrls.forEach(url => URL.revokeObjectURL(url)); downloadUrls.clear();
    dialog.close(); dialog.remove(); if (focusReturn?.isConnected) focusReturn.focus({ preventScroll: true }); onClose();
  }
  close.addEventListener('click', dispose); dialog.addEventListener('cancel', event => { event.preventDefault(); dispose(); });
  choose.addEventListener('click', () => input.click());
  input.addEventListener('change', async () => {
    const files = [...input.files]; input.value = ''; if (!files.length) return;
    try {
      if (entries.length + files.length > MAX_PANORAMA_VIEWS) throw Object.assign(new Error('tooMany'), { code: 'tooMany' });
      await Promise.all(files.map(inspectPanoramaFile)); if (closed) return;
      const index = entries.length; entries.push(...files); await display(index);
    } catch (error) { report(error); }
  });
  demoButton.addEventListener('click', () => { demo().catch(report); });
  selector.addEventListener('change', () => { display(Number(selector.value)).catch(report); });
  reset.addEventListener('click', () => viewer?.reset()); zoomIn.addEventListener('click', () => viewer?.zoom(-5)); zoomOut.addEventListener('click', () => viewer?.zoom(5));
  download.addEventListener('click', () => {
    if (closed || selected < 0) return;
    const original = entries[selected], url = URL.createObjectURL(original), link = element('a'); downloadUrls.add(url);
    link.href = url; link.download = original.name; link.click();
    setTimeout(() => { URL.revokeObjectURL(url); downloadUrls.delete(url); }, 1000);
  });
  document.body.append(dialog); dialog.showModal(); choose.focus();
  const ready = file ? load(file).catch(error => { report(error); return null; }) : Promise.resolve(null);
  return { element: dialog, ready, load, demo, dispose };
}
