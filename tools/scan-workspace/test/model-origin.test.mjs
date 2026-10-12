import test from 'node:test';
import assert from 'node:assert/strict';
import { modelOrigin } from '../src/model-origin.js';
import { readFiles } from '../src/files.js';
const bytes=value=>new TextEncoder().encode(value);
test('standalone generated OBJ/PLY keep their measurement restriction without an archive',async()=>{
  const obj=bytes('# Kantura: AI-generated geometry, NOT a measured scan.\n# metricMeasurementsAllowed=false; units=arbitrary\nv 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3');
  assert.equal(modelOrigin('part.obj',obj),'generated');
  assert.equal((await readFiles([new File([obj],'part.obj')])).source,'generated');
  assert.equal(modelOrigin('part.ply',bytes('ply\ncomment Kantura AI-generated, not a measured scan\ncomment metricMeasurementsAllowed=false\n')),'generated');
  assert.equal(modelOrigin('normal.obj',bytes('v 0 0 0')),undefined);
});
test('embedded GLB origin is detected from scene/mesh extras and malformed chunks never produce a verified origin',()=>{
  const json=bytes(JSON.stringify({scenes:[{extras:{source:'generated',metricMeasurementsAllowed:false}}]}));
  const length=Math.ceil(json.length/4)*4,blob=new Uint8Array(20+length);blob.fill(32,20);const view=new DataView(blob.buffer);
  view.setUint32(0,0x46546c67,true);view.setUint32(4,2,true);view.setUint32(8,blob.length,true);view.setUint32(12,length,true);view.setUint32(16,0x4e4f534a,true);blob.set(json,20);
  assert.equal(modelOrigin('part.glb',blob),'generated');
  view.setUint32(12,0xffffffff,true);assert.equal(modelOrigin('part.glb',blob),undefined);
});
