import test from 'node:test';
import assert from 'node:assert/strict';
import { decodeSplat, splatPlyHeader, detectSplatFile, syntheticSplatDemo, MAX_SPLATS } from '../src/splat-data.js';
import { parseModel } from '../src/viewer.js';
import { captureDictionaries } from '../src/capture-i18n.js';
import { supportedLanguages } from '../locales/index.js';

const names = ['x','y','z','scale_0','scale_1','scale_2','rot_0','rot_1','rot_2','rot_3','opacity','f_dc_0','f_dc_1','f_dc_2'];
const values = [1,2,3,Math.log(.1),Math.log(.2),Math.log(.3),1,0,0,0,0,0,.2,-.2];
const ply = (format = 'ascii', row = values, count = 1) => {
  const header = `ply\nformat ${format} 1.0\nelement vertex ${count}\n${names.map(name => `property float ${name}\n`).join('')}end_header\n`;
  return format === 'ascii' ? new TextEncoder().encode(header + row.join(' ') + '\n') : new Uint8Array(Buffer.concat([Buffer.from(header), Buffer.from(new Float32Array(row).buffer)]));
};

test('Gaussian PLY is identified by its vertex fields while an ordinary PLY stays an ordinary model', async () => {
  const ordinary = new TextEncoder().encode('ply\nformat ascii 1.0\nelement vertex 1\nproperty float x\nproperty float y\nproperty float z\nproperty float opacity\nend_header\n0 0 0 1\n');
  assert.equal(splatPlyHeader(ordinary), null);
  assert.equal(await detectSplatFile(new File([ordinary], 'scan.ply')), false);
  assert.equal(await detectSplatFile(new File([ply()], 'scan.ply')), true);
  await assert.rejects(parseModel({ model: 'gaussian.ply', assets: { 'gaussian.ply': ply() } }), { code: 'splatSeparate' });
});

test('ASCII and binary Gaussian PLY preserve position, anisotropic scale, opacity, quaternion and DC colour', () => {
  for (const format of ['ascii','binary_little_endian']) {
    const original = ply(format), result = decodeSplat(original, 'test.ply'), view = new DataView(result.bytes.buffer);
    assert.equal(result.count, 1); assert.equal(result.original, original);
    assert.deepEqual([0,4,8].map(offset => view.getFloat32(offset, true)), [1,2,3]);
    for (const [i, expected] of [.1,.2,.3].entries()) assert.ok(Math.abs(view.getFloat32(12 + i * 4, true) - expected) < 1e-6);
    assert.equal(result.bytes[24], 128); assert.ok(result.bytes[25] > 128); assert.ok(result.bytes[26] < 128); assert.equal(result.bytes[27], 128);
    assert.deepEqual([...result.bytes.slice(28,32)], [255,128,128,128]);
  }
});

test('synthetic splat fixture contains non-isotropic Gaussians and roundtrips without coordinate rescaling', () => {
  const bytes = syntheticSplatDemo(), result = decodeSplat(bytes, 'demo.splat');
  assert.ok(result.count > 2000); assert.equal(result.bytes, bytes);
  assert.ok(result.bounds.min.every(Number.isFinite)); assert.ok(result.bounds.max.every(Number.isFinite));
  const view = new DataView(bytes.buffer); assert.notEqual(view.getFloat32(12,true), view.getFloat32(16,true));
});

test('invalid fields, nonfinite Gaussian parameters, truncation and declared size limits fail before rendering', () => {
  for (const index of [0,3,6,10,11]) { const row = [...values]; row[index] = NaN; assert.throws(() => decodeSplat(ply('ascii', row), 'bad.ply'), { code: 'splatInvalid' }); }
  const negative = syntheticSplatDemo().slice(0,32); new DataView(negative.buffer).setFloat32(12,-1,true);
  assert.throws(() => decodeSplat(negative, 'bad.splat'), { code: 'splatInvalid' });
  assert.throws(() => decodeSplat(ply('binary_little_endian').slice(0,-2), 'bad.ply'), { code: 'splatInvalid' });
  assert.throws(() => decodeSplat(new Uint8Array(33), 'bad.splat'), { code: 'splatInvalid' });
  assert.throws(() => splatPlyHeader(ply('ascii', values, MAX_SPLATS + 1)), { code: 'splatLimit' });
  const missing = new TextEncoder().encode(new TextDecoder().decode(ply()).replace('property float rot_3\n',''));
  assert.throws(() => decodeSplat(missing, 'bad.ply'), { code: 'splatInvalid' });
});

test('all fifteen languages explain separate splat viewing and real photo-job states', () => {
  assert.deepEqual(Object.keys(captureDictionaries).sort(), [...supportedLanguages].sort());
  const keys = Object.keys(captureDictionaries.en).sort(); assert.equal(keys.length, 22);
  for (const dictionary of Object.values(captureDictionaries)) { assert.deepEqual(Object.keys(dictionary).sort(), keys); for (const value of Object.values(dictionary)) assert.ok(typeof value === 'string' && value.trim()); }
});
