import test from 'node:test';
import assert from 'node:assert/strict';
import { decodeNativeSplatMessage, NATIVE_SPLAT_LIMIT } from '../src/native-splat-data.js';
import { decodeSplat, syntheticSplatDemo } from '../src/splat-data.js';
const bytes = syntheticSplatDemo();
const message = { base64: Buffer.from(bytes).toString('base64'), name: 'scene.splat', language: 'ja' };

test('native bridge decodes original bytes through the shared Gaussian validator without changing coordinates', () => {
  const result = decodeNativeSplatMessage(message);
  assert.equal(result.name, message.name); assert.deepEqual(result.original, bytes); assert.equal(result.count, bytes.length / 32);
});

test('native bridge rejects oversized base64 before decoding and malformed or executable-looking inputs', () => {
  assert.throws(() => decodeNativeSplatMessage({ ...message, base64: 'A'.repeat(Math.ceil(NATIVE_SPLAT_LIMIT / 3) * 4 + 4) }), { code: 'splatLimit' });
  for (const base64 of ['', '====', 'AAAA=AAA', '<script>', 'AQI', 'data:application/octet-stream;base64,' + message.base64]) assert.throws(() => decodeNativeSplatMessage({ ...message, base64 }), { code: 'splatInvalid' });
  for (const name of ['../../scene.splat', 'C:\\scene.splat', 'scene.splat\n', 'file.obj', 'a'.repeat(256) + '.splat']) assert.throws(() => decodeNativeSplatMessage({ ...message, name }), { code: 'splatInvalid' });
  for (const input of [null, undefined, 3, {}, { ...message, base64: {} }]) assert.throws(() => decodeNativeSplatMessage(input), { code: 'splatInvalid' });
});

test('native bridge rejects a malformed Gaussian even when base64 and extension are valid', () => {
  const invalid = bytes.slice(0,32); new DataView(invalid.buffer).setFloat32(12, NaN, true);
  assert.throws(() => decodeNativeSplatMessage({ ...message, base64: Buffer.from(invalid).toString('base64') }), { code: 'splatInvalid' });
});


// Exercise the actual bridge module with a controllable renderer. WebGL remains
// a separate browser/device acceptance check; these tests cover async ownership.
import { readFile } from 'node:fs/promises';
import { runInNewContext } from 'node:vm';
const pageSource = (await readFile(new URL('../src/native-splat-page.js', import.meta.url), 'utf8')).replace(/^import .*;\r?\n/gm, '');
function bridgeHarness() {
  const elements = new Map(), messages = [], instances = [];
  const element = id => {
    if (!elements.has(id)) elements.set(id, { textContent:'', disabled:false, setAttribute(){}, replaceChildren(){}, set innerHTML(value) { throw new Error('User data must never be HTML'); } });
    return elements.get(id);
  };
  class FakeViewer {
    constructor() { this.renderer = {domElement:{setAttribute(){}}}; instances.push(this); }
    load(data) { this.data=data; return new Promise(resolve => { this.finish=resolve; }); }
    async dispose() { this.closed=true; }
    fit() { this.fitted=true; }
    focusSubject() { this.focused=true; }
  }
  const window = { addEventListener(){} };
  runInNewContext(pageSource, { window, document:{getElementById:element,documentElement:{}}, navigator:{language:'en'}, webkit:{messageHandlers:{kanturaSplat:{postMessage:message=>messages.push(message)}}}, SplatViewer:FakeViewer, decodeNativeSplatMessage, decodeSplat, syntheticSplatDemo, resolveLanguage:value=>value==='ar'?'ar':'en', dictionaries:{en:{working:'Loading',fit:'Fit'},ar:{}}, uxDictionaries:{en:{splatTitle:'Splats',splatInvalid:'Invalid',splatHelp:'No measurements',splatDemo:'Demo',viewerUnavailable:'Renderer unavailable'},ar:{splatTitle:'Arabic splats',splatHelp:'Arabic help',splatDemo:'Arabic demo',mobileNavigateHint:'Arabic navigation'}} });
  return { configure:window.configureKanturaSplat, load:window.loadKanturaSplat, elements, messages, instances };
}

test('native invalid replacement leaves the current scene intact and filename markup stays text', async () => {
  const bridge=bridgeHarness(), name='<svg onload=alert(1)>.splat', loading=bridge.load({...message,name});
  await Promise.resolve(); bridge.instances[0].finish(); assert.equal(await loading,true);
  assert.equal(bridge.elements.get('status').textContent,name);
  assert.equal(await bridge.load({...message,base64:'broken'}),false);
  assert.equal(bridge.instances[0].closed,undefined);
  assert.equal(bridge.messages.at(-1).type,'error');
});

test('native rapid replacement disposes the old scene and an old async completion cannot overwrite the new status', async () => {
  const bridge=bridgeHarness(), first=bridge.load({...message,name:'first.splat'});
  await Promise.resolve(); const second=bridge.load({...message,name:'second.splat'});
  await new Promise(setImmediate); bridge.instances[1].finish(); assert.equal(await second,true);
  bridge.instances[0].finish(); assert.equal(await first,false);
  assert.equal(bridge.instances[0].closed,true); assert.equal(bridge.elements.get('status').textContent,'second.splat');
  assert.deepEqual(bridge.messages.filter(item=>item.type==='status'&&item.state==='ready').map(item=>item.name),['second.splat']);
});


test('native language configuration is synchronous and localizes help and demo before importing a scene', () => {
  const bridge=bridgeHarness();
  assert.equal(bridge.configure({language:'ar'}),true);
  assert.equal(bridge.elements.get('title').textContent,'Arabic splats');
  assert.equal(bridge.elements.get('help').textContent,'Arabic help');
  assert.equal(bridge.elements.get('demo').textContent,'Arabic demo');
  assert.equal(bridge.instances.length,0);
  assert.equal(bridge.configure({language:'en'}),true);
  assert.equal(bridge.elements.get('demo').textContent,'Demo');
});

test('native focus and full-extent buttons address the loaded viewer separately', async () => {
  const bridge=bridgeHarness();
  assert.equal(bridge.elements.get('focus').disabled,true);
  const loading=bridge.load(message);
  await Promise.resolve(); bridge.instances[0].finish(); await loading;
  assert.equal(bridge.elements.get('focus').disabled,false);
  bridge.elements.get('focus').onclick();
  assert.equal(bridge.instances[0].focused,true); assert.equal(bridge.instances[0].fitted,undefined);
  bridge.elements.get('fit').onclick(); assert.equal(bridge.instances[0].fitted,true);
});
