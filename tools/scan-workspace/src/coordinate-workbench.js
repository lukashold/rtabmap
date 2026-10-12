import { registerLandmarks } from './registration.js';
import { validateGeodeticPoint, georeferencePoint } from './georeference.js';
import { coordinateLanguage, coordinateText } from './coordinate-i18n.js';

export const COORDINATE_INPUT_LIMIT = 64 * 1024;
export const COORDINATE_POINT_LIMIT = 100;
export class CoordinateInputError extends Error {
  constructor(code) { super(code); this.name = 'CoordinateInputError'; this.code = code; }
}
const fail = code => { throw new CoordinateInputError(code); };
const record = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const copy = value => JSON.parse(JSON.stringify(value));
const unknownFrame = () => ({ kind: 'user-entered-unknown', units: 'm' });

export function parseCoordinateJSON(text) {
  if (typeof text !== 'string') fail('jsonError');
  if (text.length > COORDINATE_INPUT_LIMIT || new TextEncoder().encode(text).length > COORDINATE_INPUT_LIMIT) fail('sizeError');
  try { return JSON.parse(text); } catch { fail('jsonError'); }
}

function points(value) {
  if (!Array.isArray(value) || value.length < 3 || value.length > COORDINATE_POINT_LIMIT ||
      Array.from(value).some(point => !Array.isArray(point) || point.length !== 3 ||
        Array.from(point).some(n => !Number.isFinite(n) || Math.abs(n) > 1e9))) fail('pairsError');
  return value.map(point => [...point]);
}
function frame(value) {
  if (value === undefined || value === null) return unknownFrame();
  if (!record(value) || value.units !== 'm' || typeof value.kind !== 'string' || !value.kind || value.kind.length > 200) fail('pairsError');
  const allowed = ['kind', 'units', 'roomId', 'name', 'floor', 'modelToFrame'];
  if (Object.keys(value).some(key => !allowed.includes(key))) fail('pairsError');
  for (const key of ['roomId', 'name', 'floor']) {
    if (value[key] !== undefined && (typeof value[key] !== 'string' || value[key].length > 200)) fail('pairsError');
  }
  if (value.modelToFrame !== undefined && (!Array.isArray(value.modelToFrame) || value.modelToFrame.length !== 16 ||
      Array.from(value.modelToFrame).some(n => !Number.isFinite(n) || Math.abs(n) > 1e9) ||
      [3,7,11].some(index => value.modelToFrame[index] !== 0) || value.modelToFrame[15] !== 1)) fail('pairsError');
  return copy(value);
}
function labels(value, count) {
  if (value === undefined || value === null) return null;
  if (!Array.isArray(value) || value.length !== count || Array.from(value).some(label => typeof label !== 'string' || label.length > 200)) fail('pairsError');
  return [...value];
}

/** Accept our detached anchor export as well as an ordinary numeric point list.
 * Row order is preserved; labels never silently create/reorder correspondences. */
export function parseLandmarkField(text) {
  const value = parseCoordinateJSON(text);
  if (Array.isArray(value)) return { points: points(value), labels: null, frame: unknownFrame(), inputProvenance: 'manual-input', inputType: 'point-list' };
  if (!record(value) || value.format !== 'kantura-coordinate-anchors' || value.version !== 1 ||
      value.source !== 'manual-control-point-anchors' || value.units !== 'm' || value.metricAccuracyValidated !== false) fail('pairsError');
  const parsed = points(value.points);
  return { points: parsed, labels: labels(value.labels, parsed.length), frame: frame(value.frame),
    inputProvenance: provenance(value.inputProvenance ?? 'manual-input'), inputType: 'anchor-json' };
}
export function parseCoordinateTolerance(text) {
  if (typeof text !== 'string' || text.length > 80) fail('toleranceError');
  const value = text.trim();
  if (!value) return undefined;
  if (!/^(?:\d+(?:[.,]\d*)?|[.,]\d+)(?:e[+-]?\d+)?$/i.test(value)) fail('toleranceError');
  const number = Number(value.replace(',', '.'));
  if (!Number.isFinite(number) || number < 0 || number > 1e9) fail('toleranceError');
  return number;
}
export function parseGeodeticField(text) {
  // Unknown uncertainty stays absent; neither an omitted axis nor an omitted
  // uncertainty object is silently replaced with zero or a certified estimate.
  return validateGeodeticPoint(parseCoordinateJSON(text));
}

export function exportCoordinateAnchors({ sourcePoints, sourceFrame, sourceLabels, inputProvenance = 'manual-input' }) {
  const parsed = points(sourcePoints);
  return JSON.stringify({ format: 'kantura-coordinate-anchors', version: 1,
    source: 'manual-control-point-anchors', units: 'm', points: parsed,
    labels: labels(sourceLabels, parsed.length), frame: frame(sourceFrame),
    inputProvenance: provenance(inputProvenance), metricAccuracyValidated: false }, null, 2);
}
function provenance(value) {
  if (!['manual-input', 'provided-project-anchors', 'synthetic-example'].includes(value)) fail('pairsError');
  return value;
}
function candidate(operation, inputs, result, inputProvenance) {
  return { format: 'kantura-coordinate-candidate', version: 1, source: 'candidate', operation,
    inputProvenance: provenance(inputProvenance), metricAccuracyValidated: false,
    physicalAccuracyValidated: false, appliedToModel: false, automaticBuildingMerge: false,
    inputs: copy(inputs), result: copy(result) };
}

export function calculateRegistrationCandidate({ sourceText, targetText, toleranceText = '', sourceFrame, sourceLabels,
  inputProvenance = 'manual-input', sourceInputProvenance = inputProvenance,
  targetInputProvenance = inputProvenance === 'synthetic-example' ? 'synthetic-example' : 'manual-input' }) {
  const source = parseLandmarkField(sourceText), target = parseLandmarkField(targetText);
  if (source.points.length !== target.points.length) fail('pairsError');
  if (sourceFrame !== undefined) source.frame = frame(sourceFrame);
  if (sourceLabels !== undefined) source.labels = labels(sourceLabels, source.points.length);
  // Pasted payloads retain their declared provenance on each side. Editing a
  // raw numeric list is manual input, never evidence of survey certification.
  if (source.inputType === 'point-list') source.inputProvenance = provenance(sourceInputProvenance);
  if (target.inputType === 'point-list') target.inputProvenance = provenance(targetInputProvenance);
  const combinedProvenance = [source, target].some(side => side.inputProvenance === 'synthetic-example') ? 'synthetic-example' : inputProvenance;
  const maxResidual = parseCoordinateTolerance(toleranceText);
  const result = registerLandmarks(source.points, target.points, maxResidual === undefined ? {} : { maxResidual });
  return candidate('landmark-registration', { source, target, toleranceMeters: maxResidual ?? null }, result, combinedProvenance);
}
export function calculateGPSCandidate({ pointText, originText, inputProvenance = 'manual-input' }) {
  const point = parseGeodeticField(pointText), origin = parseGeodeticField(originText);
  return candidate('georeference-point', { point, origin }, georeferencePoint(point, origin), inputProvenance);
}

/** Never turns a reviewed fit into a survey certificate or applies a transform.
 * An edited object with nonfinite numbers is rejected rather than saved as null. */
export function exportCoordinateCandidate(value) {
  if (!record(value) || value.format !== 'kantura-coordinate-candidate' || value.version !== 1 || value.source !== 'candidate' ||
      !['landmark-registration', 'georeference-point'].includes(value.operation) || value.metricAccuracyValidated !== false ||
      value.physicalAccuracyValidated !== false || value.appliedToModel !== false || value.automaticBuildingMerge !== false) fail('geometryError');
  let encoded;
  try {
    encoded = JSON.stringify(value, (_, entry) => {
      if (typeof entry === 'number' && !Number.isFinite(entry)) fail('geometryError');
      return entry;
    }, 2);
  } catch { fail('geometryError'); }
  if (new TextEncoder().encode(encoded).length > 256 * 1024) fail('sizeError');
  return encoded;
}

const CSS = `
:host{font:16px/1.5 system-ui,sans-serif;color:#251a40;color-scheme:light}
*{box-sizing:border-box} dialog{color:#251a40;background:#fffdf9;border:1px solid #d9d1e3;border-radius:22px;padding:24px;width:min(920px,calc(100vw - 24px));max-width:none;max-height:calc(100dvh - 32px);overflow:auto;box-shadow:0 20px 70px #120b2350}
dialog::backdrop{background:#171025aa} h2{font-size:1.55rem;margin:0;line-height:1.25}p{margin:.65em 0} header{display:flex;gap:16px;align-items:start;justify-content:space-between}.muted{color:#584d69}.tabs,.actions{display:flex;gap:10px;flex-wrap:wrap;margin:18px 0}.tabs{border-bottom:1px solid #d9d1e3;padding-bottom:12px}
button{font:inherit;color:inherit;background:white;border:1px solid #9e91b0;border-radius:12px;padding:10px 15px;min-height:44px;cursor:pointer}button[aria-selected=true],button.primary{background:#70edc5;border-color:#248166;font-weight:650}button:disabled{opacity:.5;cursor:default}:focus-visible{outline:3px solid #5534a5;outline-offset:3px} [hidden]{display:none!important}
.grid{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:16px}label{display:block;font-weight:650;margin:12px 0 6px}textarea,input{width:100%;font:14px/1.5 ui-monospace,SFMono-Regular,Consolas,monospace;color:#251a40;background:#fff;border:1px solid #9e91b0;border-radius:10px;padding:10px}textarea{min-height:180px;resize:vertical}input{max-width:260px;font-size:1rem}.notice{background:#ecf8f1;border-inline-start:4px solid #278064;padding:12px;border-radius:6px}.error{color:#8e1830;font-weight:600}.summary{white-space:pre-wrap;font-weight:650}.result{min-height:240px}.small{font-size:.92rem}.review{padding:12px;border:1px solid #d9d1e3;border-radius:12px}@media(max-width:620px){dialog{padding:16px;border-radius:16px}.grid{grid-template-columns:minmax(0,1fr)}h2{font-size:1.3rem}.tabs button{flex:1}textarea{min-height:155px}}
`;

/** Advanced, ephemeral review dialog. Root integration must prohibit nonmetric
 * model contexts. This module never reads/mutates the viewer or model itself. */
export function openCoordinateWorkbench({ language = 'en', sourcePoints, sourceFrame, sourceLabels, onClose = () => {} } = {}) {
  const locale = coordinateLanguage(language), t = coordinateText(locale);
  const host = document.createElement('div'), shadow = host.attachShadow({ mode: 'open' });
  const style = document.createElement('style'); style.textContent = CSS; shadow.append(style);
  const dialog = document.createElement('dialog'); dialog.lang = locale; dialog.dir = locale === 'ar' ? 'rtl' : 'ltr';
  if (typeof dialog.showModal !== 'function') throw new Error(t.unavailable);
  dialog.setAttribute('aria-labelledby', 'coordinate-title'); dialog.setAttribute('aria-describedby', 'coordinate-privacy'); shadow.append(dialog);
  const create = (tag, text, parent, className) => {
    const node = document.createElement(tag); if (text !== undefined) node.textContent = text;
    if (className) node.className = className; parent?.append(node); return node;
  };
  const previousFocus = document.activeElement;
  let disposed = false, active = 0, current = null, registrationProvenance = sourcePoints ? 'provided-project-anchors' : 'manual-input', targetProvenance = 'manual-input', gpsProvenance = 'manual-input';
  let currentSourceFrame = sourceFrame, currentSourceLabels = sourceLabels;
  const urls = new Set();
  function dispose() {
    if (disposed) return; disposed = true;
    if (dialog.open) dialog.close();
    urls.forEach(url => URL.revokeObjectURL(url)); urls.clear(); host.remove();
    if (previousFocus?.isConnected) previousFocus.focus({ preventScroll: true });
    onClose();
  }
  const header = create('header', undefined, dialog);
  const title = create('h2', t.title, header); title.id = 'coordinate-title';
  const close = create('button', t.close, header); close.type = 'button'; close.addEventListener('click', dispose);
  const privacy = create('p', t.privacy, dialog, 'muted small'); privacy.id = 'coordinate-privacy';
  const tabs = create('div', undefined, dialog, 'tabs'); tabs.setAttribute('role', 'tablist'); tabs.setAttribute('aria-label', t.title);
  const panels = [create('section', undefined, dialog), create('section', undefined, dialog)];
  const tabButtons = [t.registrationTab, t.gpsTab].map((title, index) => {
    const button = create('button', title, tabs); button.type = 'button'; button.id = `coordinate-tab-${index}`;
    button.setAttribute('role', 'tab'); button.setAttribute('aria-controls', `coordinate-panel-${index}`);
    panels[index].id = `coordinate-panel-${index}`; panels[index].setAttribute('role', 'tabpanel'); panels[index].setAttribute('aria-labelledby', button.id);
    button.addEventListener('click', () => selectTab(index));
    return button;
  });
  create('p', t.registrationHelp, panels[0]); create('p', t.anchorHelp, panels[0], 'muted');
  const prefill = create('p', t.prefillHelp, panels[0], 'notice'); prefill.hidden = !sourcePoints;
  const registrationGrid = create('div', undefined, panels[0], 'grid');
  function field(parent, labelText, id, input = false) {
    const wrapper = create('div', undefined, parent); const label = create('label', labelText, wrapper); label.htmlFor = id;
    const control = create(input ? 'input' : 'textarea', undefined, wrapper); control.id = id; control.dir = 'ltr';
    control.spellcheck = false; control.autocomplete = 'off';
    if (!input) control.maxLength = COORDINATE_INPUT_LIMIT;
    return control;
  }
  const source = field(registrationGrid, t.sourceLabel, 'coordinate-source');
  const target = field(registrationGrid, t.targetLabel, 'coordinate-target');
  const targetHelp = create('p', t.targetUnknown, panels[0], 'small muted'); targetHelp.id = 'coordinate-target-help'; target.setAttribute('aria-describedby', targetHelp.id);
  const tolerance = field(panels[0], t.toleranceLabel, 'coordinate-tolerance', true); tolerance.inputMode = 'decimal'; tolerance.maxLength = 80;
  const toleranceHelp = create('p', t.toleranceHelp, panels[0], 'small muted'); toleranceHelp.id = 'coordinate-tolerance-help'; tolerance.setAttribute('aria-describedby', toleranceHelp.id);
  create('p', t.gpsHelp, panels[1]);
  const gpsGrid = create('div', undefined, panels[1], 'grid');
  const point = field(gpsGrid, t.pointLabel, 'coordinate-point'), origin = field(gpsGrid, t.originLabel, 'coordinate-origin');
  const exampleNotice = create('p', t.exampleNotice, dialog, 'notice'); exampleNotice.hidden = true;
  const actions = create('div', undefined, dialog, 'actions');
  const calculate = create('button', t.calculate, actions, 'primary'), example = create('button', t.loadExample, actions), anchors = create('button', t.downloadAnchors, actions);
  for (const button of [calculate, example, anchors]) button.type = 'button';
  const error = create('p', undefined, dialog, 'error'); error.setAttribute('role', 'alert');
  const summary = create('p', undefined, dialog, 'summary'); summary.setAttribute('role', 'status'); summary.setAttribute('aria-live', 'polite');
  create('p', t.resultHelp, dialog, 'review');
  const resultLabel = create('label', t.resultLabel, dialog); resultLabel.htmlFor = 'coordinate-result';
  const result = create('textarea', undefined, dialog, 'result'); result.id = 'coordinate-result'; result.readOnly = true; result.dir = 'ltr'; result.spellcheck = false;
  const download = create('button', t.download, dialog); download.type = 'button'; download.disabled = true;
  function invalidate() { current = null; result.value = ''; download.disabled = true; error.textContent = ''; summary.textContent = ''; }
  function selectTab(index) {
    active = index; invalidate();
    tabButtons.forEach((button, n) => { button.setAttribute('aria-selected', String(n === index)); button.tabIndex = n === index ? 0 : -1; panels[n].hidden = n !== index; });
    anchors.hidden = active !== 0;
    exampleNotice.hidden = active === 0 ? ![registrationProvenance, targetProvenance].includes('synthetic-example') : gpsProvenance !== 'synthetic-example';
  }
  tabs.addEventListener('keydown', event => {
    const step = (event.key === 'ArrowRight' ? 1 : event.key === 'ArrowLeft' ? -1 : 0) * (locale === 'ar' ? -1 : 1);
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? 1 : step ? (active + step + 2) % 2 : null;
    if (next !== null) { event.preventDefault(); selectTab(next); tabButtons[next].focus(); }
  });
  for (const control of [source, target, tolerance, point, origin]) control.addEventListener('input', () => {
    invalidate();
    if (control === source) { registrationProvenance = 'manual-input'; currentSourceLabels = undefined; currentSourceFrame = undefined; prefill.hidden = true; }
    if (control === target) targetProvenance = 'manual-input';
    if (control === point || control === origin) gpsProvenance = 'manual-input';
    exampleNotice.hidden = active === 0 ? ![registrationProvenance, targetProvenance].includes('synthetic-example') : gpsProvenance !== 'synthetic-example';
  });
  const showError = exception => {
    const code = exception?.code;
    const key = Object.hasOwn(t, code) ? code : ['invalidLandmarks', 'landmarkCountMismatch'].includes(code) ? 'pairsError'
      : code === 'invalidRegistrationThreshold' ? 'toleranceError'
      : ['invalidGeodetic', 'unsupportedVerticalDatum', 'invalidUncertainty', 'missingOrigin', 'invalidECEF', 'invalidENU'].includes(code) ? 'gpsError' : 'geometryError';
    error.textContent = t[key];
  };
  function save(text, filename) {
    const url = URL.createObjectURL(new Blob([text], { type: 'application/json' })); urls.add(url);
    const link = document.createElement('a'); link.href = url; link.download = filename; shadow.append(link); link.click(); link.remove();
    setTimeout(() => { URL.revokeObjectURL(url); urls.delete(url); }, 1000);
  }
  anchors.addEventListener('click', () => {
    try { const parsed = parseLandmarkField(source.value); save(exportCoordinateAnchors({ sourcePoints: parsed.points,
      sourceFrame: currentSourceFrame ?? parsed.frame, sourceLabels: currentSourceLabels ?? parsed.labels,
      inputProvenance: parsed.inputType === 'anchor-json' ? parsed.inputProvenance : registrationProvenance }), 'kantura-coordinate-anchors.json'); error.textContent = ''; }
    catch (exception) { showError(exception); }
  });
  calculate.addEventListener('click', () => {
    invalidate();
    try {
      current = active === 0 ? calculateRegistrationCandidate({ sourceText: source.value, targetText: target.value, toleranceText: tolerance.value,
        sourceFrame: currentSourceFrame, sourceLabels: currentSourceLabels, inputProvenance: registrationProvenance,
        sourceInputProvenance: registrationProvenance, targetInputProvenance: targetProvenance })
        : calculateGPSCandidate({ pointText: point.value, originText: origin.value, inputProvenance: gpsProvenance });
      result.value = exportCoordinateCandidate(current); download.disabled = false;
      exampleNotice.hidden = current.inputProvenance !== 'synthetic-example';
      if (active === 0) {
        const fit = current.result, formatter = new Intl.NumberFormat(locale, { maximumSignificantDigits: 8 });
        summary.textContent = (fit.accepted === null ? t.needsReview : fit.accepted ? t.accepted : t.rejected) +
          `\n${t.rmse}: ${formatter.format(fit.rmse)} m\n${t.maxResidual}: ${formatter.format(fit.maxResidual)} m`;
      } else summary.textContent = t.gpsResult;
    } catch (exception) { current = null; result.value = ''; download.disabled = true; showError(exception); }
  });
  example.addEventListener('click', () => {
    invalidate();
    if (active === 0) {
      source.value = JSON.stringify([[0,0,0],[2,0,0],[0,0,2],[0,2,0]], null, 2);
      target.value = JSON.stringify([[10,1,3],[12,1,3],[10,1,5],[10,3,3]], null, 2);
      tolerance.value = ''; registrationProvenance = 'synthetic-example'; targetProvenance = 'synthetic-example'; currentSourceFrame = undefined; currentSourceLabels = undefined; prefill.hidden = true;
    } else {
      const sample = { latitude: 0, longitude: 0, height: 0, verticalDatum: 'ellipsoidal', uncertainty: { horizontalMeters: 5, verticalMeters: 10 } };
      origin.value = JSON.stringify(sample, null, 2); point.value = JSON.stringify({ ...sample, longitude: 0.00001, height: 2 }, null, 2); gpsProvenance = 'synthetic-example';
    }
    exampleNotice.hidden = false;
  });
  download.addEventListener('click', () => { if (current) save(exportCoordinateCandidate(current), `kantura-${current.operation}-candidate.json`); });
  dialog.addEventListener('cancel', event => { event.preventDefault(); dispose(); });
  dialog.addEventListener('close', dispose);
  selectTab(0);
  if (sourcePoints !== undefined) {
    try { const validated = points(sourcePoints); currentSourceFrame = frame(sourceFrame); currentSourceLabels = labels(sourceLabels, validated.length); source.value = JSON.stringify(validated, null, 2); }
    catch (exception) { currentSourceFrame = undefined; currentSourceLabels = undefined; registrationProvenance = 'manual-input'; prefill.hidden = true; showError(exception); }
  }
  document.body.append(host);
  try { dialog.showModal(); tabButtons[0].focus(); } catch (exception) { host.remove(); throw exception; }
  return { element: host, dispose };
}
