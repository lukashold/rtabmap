import test from 'node:test';
import assert from 'node:assert/strict';
import { MAX_PANORAMA_BYTES, panoramaDimensions, panoramaHeader, inspectPanoramaFile, normalizePanoramaView, panoramaDirection } from '../src/panorama-data.js';
import { panoramaStrings } from '../src/panorama-i18n.js';

function png(width = 2048, height = 1024) {
  const bytes = new Uint8Array(33), view = new DataView(bytes.buffer);
  bytes.set([137,80,78,71,13,10,26,10]); view.setUint32(8, 13); bytes.set([73,72,68,82], 12); view.setUint32(16, width); view.setUint32(20, height);
  return bytes; // Header fixture only: browser decode must validate actual images.
}
function jpeg(width = 2048, height = 1024, marker = 192) {
  const bytes = new Uint8Array([255,216,255,224,0,4,0,0,255,marker,0,17,8,0,0,0,0,3,1,17,0,2,17,0,3,17,0]);
  const view = new DataView(bytes.buffer); view.setUint16(13, height); view.setUint16(15, width); return bytes;
}
const code = expected => error => error.code === expected;

test('panorama dimensions require exact 2:1 and bound decoded memory', () => {
  assert.deepEqual(panoramaDimensions(8192,4096), {width:8192,height:4096});
  assert.deepEqual(panoramaDimensions(256,128), {width:256,height:128});
  assert.throws(() => panoramaDimensions(2048,1000), code('aspect'));
  for (const dims of [[16384,8192],[200,100],[Infinity,100],[256,NaN],[512.5,256]]) assert.throws(() => panoramaDimensions(...dims), code('dimensions'));
});
test('PNG header reads true dimensions with a typed-array byte offset', () => {
  const buffer = new Uint8Array(43); buffer.set(png(),10);
  assert.deepEqual(panoramaHeader(buffer.subarray(10)), {width:2048,height:1024,mime:'image/png',format:'PNG'});
});
test('JPEG baseline and progressive frames skip bounded application metadata', () => {
  for (const marker of [192,194]) assert.deepEqual(panoramaHeader(jpeg(4096,2048,marker)), {width:4096,height:2048,mime:'image/jpeg',format:'JPEG'});
});
test('SVG, corrupt JPEG segments and truncated headers fail before decoder', () => {
  for (const bytes of [new TextEncoder().encode('<svg width="2048" height="1024"/>'),jpeg().subarray(0,15),new Uint8Array([255,216,255,224,0,0]),new Uint8Array([255,216,255,218]),png().subarray(0,20)]) assert.throws(() => panoramaHeader(bytes), code('format'));
});
test('header rejects dimensions that could expand to an excessive texture', () => {
  assert.throws(() => panoramaHeader(png(0xffffffff,0x7fffffff)), code('dimensions'));
  assert.throws(() => panoramaHeader(jpeg(65534,32767)), code('dimensions'));
});
test('file inspection enforces bytes/extensions instead of trusting MIME', async () => {
  assert.equal((await inspectPanoramaFile(new File([png()], 'room.PNG', {type:'text/plain'}))).format, 'PNG');
  await assert.rejects(inspectPanoramaFile(new File([png()], 'room.svg')), code('format'));
  await assert.rejects(inspectPanoramaFile(new File([], 'room.png')), code('size'));
  await assert.rejects(inspectPanoramaFile({name:'large.png',size:MAX_PANORAMA_BYTES + 1,slice(){throw new Error('Must not read oversized file');}}), code('size'));
});
test('view controls wrap yaw and bound poles/FOV', () => {
  assert.deepEqual(normalizePanoramaView({yaw:725,pitch:90,fov:120}), {yaw:5,pitch:85,fov:100});
  assert.deepEqual(normalizePanoramaView({yaw:-725,pitch:-90,fov:10}), {yaw:-5,pitch:-85,fov:35});
  assert.throws(() => normalizePanoramaView({yaw:NaN}), code('view'));
});
test('view directions have unit length, default forwards, positive yaw right', () => {
  assert.deepEqual(panoramaDirection({}), [0,0,-1]);
  const right = panoramaDirection({yaw:90}); assert.ok(Math.abs(right[0] - 1) < 1e-12);
  for (const yaw of [-180,-90,0,90,180]) for (const pitch of [-85,0,85]) assert.ok(Math.abs(Math.hypot(...panoramaDirection({yaw,pitch})) - 1) < 1e-12);
});
test('all fifteen panorama dictionaries have complete translated UI/error strings', () => {
  const languages = ['de','en','fr','es','it','zh-Hans','pt','ar','hi','bn','ru','ja','ko','id','tr'];
  assert.deepEqual(Object.keys(panoramaStrings).sort(), languages.sort());
  const keys = Object.keys(panoramaStrings.en);
  for (const [language, values] of Object.entries(panoramaStrings)) {
    assert.deepEqual(Object.keys(values), keys);
    assert.ok(Object.values(values).every(value => typeof value === 'string' && value.trim()));
    if (language !== 'en') assert.notEqual(values.help, panoramaStrings.en.help);
  }
});
