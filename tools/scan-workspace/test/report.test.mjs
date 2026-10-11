import test from 'node:test';
import assert from 'node:assert/strict';
import { floorplanDXF, measurementReport } from '../src/report.js';

const floor = { kind: 'floor', label: 'Wohnzimmer', points: [[0, 0, 0], [4000, 0, 0], [4000, 0, 3000], [0, 0, 3000]] };
const project = { version: 1, name: 'Haus', upAxis: 'z', scale: 0.001, calibrated: false, measurements: [floor, { kind: 'distance', label: 'Tor diagonal', points: [[0, 0, 0], [3000, 12000, 4000]] }, { kind: 'surface', label: 'Torfläche', points: [[0, 0, 0], [2000, 0, 0], [2000, 3000, 0], [0, 3000, 0]] }] };
const createdAt = '2026-10-11T12:00:00.000Z';
function pairs(dxf) {
  const lines = dxf.trimEnd().split(/\r?\n/);
  assert.equal(lines.length % 2, 0, 'every DXF group code has a value');
  return Array.from({ length: lines.length / 2 }, (_, index) => { assert.match(lines[index * 2], /^\d+$/); return [Number(lines[index * 2]), lines[index * 2 + 1]]; });
}
function entities(dxf) {
  const result = [];
  let inside = false, current;
  for (const [code, value] of pairs(dxf)) {
    if (code === 2 && value === 'ENTITIES') { inside = true; continue; }
    if (!inside) continue;
    if (code === 0) { if (current) result.push(current); if (value === 'ENDSEC') break; current = { type: value, pairs: [] }; }
    else current?.pairs.push([code, value]);
  }
  return result;
}
const values = (entity, code) => entity.pairs.filter(pair => pair[0] === code).map(pair => pair[1]);

test('DXF declares AutoCAD 2000 meters and applies calibration once to floor geometry and dimensions', () => {
  const dxf = floorplanDXF(project.measurements, project.scale, project.name);
  assert.match(dxf, /9\r\n\$ACADVER\r\n1\r\nAC1015/);
  assert.match(dxf, /9\r\n\$INSUNITS\r\n70\r\n6/);
  assert.ok(dxf.endsWith('0\r\nEOF\r\n'));
  const contents = entities(dxf), contours = contents.filter(entity => entity.type === 'LWPOLYLINE');
  assert.equal(contours.length, 1, 'distance and vertical surface are not exported as floors');
  assert.deepEqual(values(contours[0], 10).map(Number), [0, 4, 4, 0]);
  assert.deepEqual(values(contours[0], 20).map(Number), [0, 0, -3, -3]);
  assert.deepEqual(values(contours[0], 70), ['1']);
  assert.deepEqual(values(contours[0], 90), ['4']);
  const labels = contents.filter(entity => entity.type === 'TEXT').flatMap(entity => values(entity, 1));
  assert.equal(labels.filter(label => label === '4.000 m').length, 2);
  assert.equal(labels.filter(label => label === '3.000 m').length, 2);
  assert.ok(labels.includes('12.000 m2 | P 14.000 m'));
  assert.equal(contents.filter(entity => entity.type === 'LINE').length, 20);
  assert.ok(labels.some(label => label.includes('does not update labels')));
});

test('DXF preserves concave polygons and computes their area rather than their bounding rectangle', () => {
  const outline = { kind: 'floor', label: 'L-Raum', points: [[0, 0, 0], [3, 0, 0], [3, 0, 1], [1, 0, 1], [1, 0, 3], [0, 0, 3]] };
  const contents = entities(floorplanDXF([outline], 1));
  assert.deepEqual(values(contents.find(entity => entity.type === 'LWPOLYLINE'), 90), ['6']);
  assert.ok(contents.filter(entity => entity.type === 'TEXT').some(entity => values(entity, 1).includes('5.000 m2 | P 12.000 m')));
  const reversed = entities(floorplanDXF([{ ...outline, points: [...outline.points].reverse() }], 1));
  assert.ok(reversed.filter(entity => entity.type === 'TEXT').some(entity => values(entity, 1).includes('5.000 m2 | P 12.000 m')));
});

test('DXF text is ASCII-safe without injectable group codes and retains Unicode escapes', () => {
  const name = 'Küche 中文\n0\nENDSEC %%d \\U+0041';
  const dxf = floorplanDXF([{ ...floor, label: name }], 0.001, name);
  assert.match(dxf, /^[\x00-\x7f]+$/);
  const contents = entities(dxf);
  assert.equal(contents.filter(entity => entity.type === 'LWPOLYLINE').length, 1);
  const labels = contents.filter(entity => entity.type === 'TEXT').flatMap(entity => values(entity, 1));
  assert.ok(labels.some(label => label.includes('K\\U+00FCche \\U+4E2D\\U+6587 0 ENDSEC')));
  assert.ok(labels.some(label => label.includes('\\U+0025\\U+0025d \\U+005CU+0041')));
  assert.equal(pairs(dxf).filter(([code, value]) => code === 0 && value === 'ENDSEC').length, 5);
  const handles = pairs(dxf).filter(([code]) => code === 5).map(([, value]) => value);
  assert.equal(handles.length, new Set(handles).size);
});

test('DXF rejects missing floors, non-planar geometry and invalid scale', () => {
  assert.throws(() => floorplanDXF([], 1), { code: 'noFloor' });
  assert.throws(() => floorplanDXF([floor], 0), { code: 'invalidScale' });
  assert.throws(() => floorplanDXF([{ ...floor, points: [[0, 0, 0], [1, 0, 0], [1, 0.1, 1]] }], 1), { code: 'notPlanar' });
});

test('report includes 3D length, horizontal distance, height, area, perimeter and a non-scale floor plan', () => {
  const html = measurementReport(project, { language: 'de', createdAt });
  for (const value of ['13,000', '5,000', '12,000', '6,000', '10,000', '14,000']) assert.ok(html.includes(value), value);
  assert.match(html, /<svg\b/);
  assert.match(html, /Maßstab noch nicht geprüft/);
  assert.match(html, /0,001 m/);
  assert.match(html, /datetime="2026-10-11T12:00:00.000Z"/);
  assert.match(html, /keinen festen Maßstab/);
  assert.match(html, /@page\{size:A4 portrait/);
  assert.match(html, /window\.print\(\)/);
  assert.doesNotMatch(html, /<(?:script|link)\b[^>]*(?:src|href)=/);
});

test('report safely escapes project and measurement text, custom translations and note content', () => {
  const evil = '</title><script>alert(1)</script><img src=x onerror=alert(2)>';
  const html = measurementReport({ ...project, name: evil, measurements: [{ ...floor, label: evil }] }, { createdAt, dictionary: { report: evil } });
  assert.ok(html.includes('&lt;script&gt;alert(1)&lt;/script&gt;'));
  assert.doesNotMatch(html, /<script>alert/);
  assert.doesNotMatch(html, /<img src=x/);
  assert.equal((html.match(/<script>/g) || []).length, 1, 'only the static print script is executable');
});

test('report has five localized variants and supports distance-only projects without fabricating a plan', () => {
  const titles = { de: 'Messbericht', fr: 'Rapport de mesures', es: 'Informe de medidas', it: 'Rapporto di misura', 'zh-Hans': '测量报告' };
  for (const [language, title] of Object.entries(titles)) {
    const html = measurementReport({ ...project, calibrated: true, measurements: [project.measurements[1]] }, { language, createdAt });
    assert.ok(html.includes(title));
    assert.ok(html.includes(`<html lang="${language}">`));
    assert.doesNotMatch(html, /<svg\b/);
  }
  assert.match(measurementReport(project, { language: 'zh-CN', createdAt }), /<html lang="zh-Hans">/);
  assert.match(measurementReport(project, { language: 'en', createdAt }), /<html lang="de">/);
});

test('report shows current reference deviations after calibration without claiming accuracy', () => {
  const calibrated = { ...project, scale: 1.01, calibrated: true, measurements: [], checks: [
    { id: '123e4567-e89b-42d3-a456-426614174001', label: 'Referenz A', points: [[0, 0, 0], [2, 0, 0]], knownMeters: 2, createdAt },
    { id: '123e4567-e89b-42d3-a456-426614174002', label: 'Referenz B', points: [[0, 0, 0], [1, 0, 0]], knownMeters: 1.02, createdAt }
  ] };
  const html = measurementReport(calibrated, { language: 'de', createdAt });
  assert.match(html, /Mit Referenz kalibriert/);
  assert.match(html, /2,020/);
  assert.match(html, /\+0,020 m/);
  assert.match(html, /\+1,000 %/);
  assert.match(html, /-0,010 m/);
  assert.match(html, /-0,980 %/);
  assert.match(html, /keine Genauigkeitsgarantie/);
});

test('report embeds supplied safe note photos, positions and missing-photo status', () => {
  const path = 'kantura-notes/123e4567-e89b-42d3-a456-426614174000.jpg';
  const photo = 'data:image/jpeg;base64,/9j/2Q==';
  const notes = [{ id: '123e4567-e89b-42d3-a456-426614174000', title: 'Tor & Tür', description: 'Linker Pfosten\n<mark>prüfen</mark>', kind: 'gate', point: [1000, 2000, -3000], photo: path }];
  const html = measurementReport({ ...project, notes }, { createdAt, photoData: { [path]: photo } });
  assert.ok(html.includes(`src="${photo}"`));
  assert.match(html, /alt="Tor &amp; Tür"/);
  assert.match(html, /&lt;mark&gt;prüfen&lt;\/mark&gt;/);
  assert.match(html, /X 1,000 · Y 2,000 · Z -3,000/);
  assert.match(measurementReport({ ...project, notes }, { createdAt }), /Foto nicht in diesen Bericht eingebettet/);
});

test('report rejects active image sources, oversized images and invalid dates', () => {
  for (const source of ['https://example.com/image.jpg', 'data:image/svg+xml;base64,PHN2Zz4=', 'data:image/jpeg;base64,abc', 'data:image/png;base64,AAAA" onerror="alert(1)']) {
    assert.throws(() => measurementReport(project, { createdAt, photoData: { image: source } }), { code: 'invalidProject' });
  }
  assert.throws(() => measurementReport(project, { createdAt, photoData: { image: `data:image/png;base64,${'AAAA'.repeat(1747627)}` } }), { code: 'tooLarge' });
  assert.throws(() => measurementReport(project, { createdAt: 'invalid' }), { code: 'invalidProject' });
});

const transportInput = () => ({ object: { width: 0.6, depth: 0.66, height: 2.03 }, route: { width: 1, ceiling: 2.6, landingWidth: 2, landingDepth: 2, rise: 0.17, run: 0.28, turnDegrees: 90 }, margin: 0.03, allowTilt: true });
const transportProject = (changes = {}) => ({ ...project, transport: { input: transportInput(), model: 'Bosch KGN39VLEA', assessedAt: createdAt, ...changes } });

test('transport report recomputes the verdict instead of trusting stored results and preserves metric input units', () => {
  const input = transportInput(); input.route.width = 0.5;
  const html = measurementReport(transportProject({ input, verdict: 'possible', reasons: ['upright_envelope_fits'] }), { language: 'de', createdAt });
  assert.match(html, /<p class="transport-verdict blocked">Durchgang zu klein<\/p>/);
  assert.match(html, /Die kleinste Gerätekante einschließlich Abstand/);
  assert.match(html, /Beim Berichtsexport aus den gespeicherten Eingaben neu berechnet/);
  assert.match(html, /keine Bestätigung eines kollisionsfreien oder sicheren Transportwegs/);
  assert.match(html, /0,600 m/);
  assert.match(html, /0,660 m/);
  assert.match(html, /2,030 m/);
  assert.match(html, /0,030 m/);
  assert.match(html, /90,000 °/);
  assert.match(html, /-0,160 m/);
  assert.match(html, /Gespeicherte Eingaben \(UTC\)/);
  assert.match(html, /href="https:\/\/www\.bosch-home\.com\/de\/de\/product\/KGN39VLEA"/);
  assert.match(html, /diese können von Katalogmaßen abweichen/);
});

test('transport verdicts, reasons and explicit assumptions are available in all five report languages', () => {
  const expected = {
    de: ['Transportabschätzung', 'Im geprüften Hüllraum möglich', 'Stufen und Geländern'],
    fr: ['Estimation du transport', 'Possible dans l’enveloppe vérifiée', 'marches individuelles'],
    es: ['Estimación del transporte', 'Posible dentro del volumen comprobado', 'escalones individuales'],
    it: ['Stima del trasporto', 'Possibile nell’ingombro verificato', 'singoli gradini'],
    'zh-Hans': ['搬运空间估算', '在已检查的包络空间内可行', '单个台阶或扶手']
  };
  for (const [language, content] of Object.entries(expected)) {
    const html = measurementReport(transportProject(), { language, createdAt });
    for (const text of content) assert.ok(html.includes(text), `${language}: ${text}`);
    assert.doesNotMatch(html, /rectangular_object|no_carriers_or_equipment|upright_envelope_fits|centred_turn_on_rectangular_landing/);
  }
  const input = transportInput(); input.route.landingWidth = 0.7; input.route.landingDepth = 0.7;
  const uncertain = measurementReport(transportProject({ input }), { language: 'de', createdAt });
  assert.match(uncertain, /<p class="transport-verdict uncertain">Weitere Prüfung nötig<\/p>/);
  assert.match(uncertain, /Eine versetzte Bewegung muss am tatsächlichen Weg geprüft werden/);
});

test('transport report escapes arbitrary model names and never treats imported source URLs or partial model matches as catalogue evidence', () => {
  const evil = '</dd><img src=x onerror=alert(1)> KGN39VLEA';
  const html = measurementReport(transportProject({ model: evil, sourceUrl: 'javascript:alert(1)' }), { createdAt });
  assert.ok(html.includes('&lt;/dd&gt;&lt;img src=x onerror=alert(1)&gt;'));
  assert.doesNotMatch(html, /<img src=x|href="javascript:|www\.bosch-home\.com/);
  assert.match(html, /Manuell eingegebene Maße; keine eindeutige Katalogzuordnung/);
  const partial = measurementReport(transportProject({ model: 'KGN39' }), { createdAt });
  assert.doesNotMatch(partial, /www\.bosch-home\.com/);
  const exact = measurementReport(transportProject({ model: 'KGN39VLEA' }), { createdAt });
  assert.match(exact, /www\.bosch-home\.com/);
});

test('transport report rejects invalid or incomplete saved inputs rather than printing a stale assessment', () => {
  assert.throws(() => measurementReport(transportProject({ assessedAt: 'not-a-date' }), { createdAt }), { code: 'invalidProject' });
  assert.throws(() => measurementReport(transportProject({ input: {} }), { createdAt }), { code: 'invalidTransport' });
  assert.throws(() => measurementReport(transportProject({ model: 12 }), { createdAt }), { code: 'invalidProject' });
  const input = transportInput(); input.route.width = 0;
  assert.throws(() => measurementReport(transportProject({ input }), { createdAt }), { code: 'invalidTransport' });
});
