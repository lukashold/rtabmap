import { test } from 'node:test';
import assert from 'node:assert/strict';
import { zipSync, strToU8 } from 'fflate';
import { safePath, unpack, resolveAsset, csvReport, readFiles, packageProject } from '../src/files.js';
import { resultFor } from '../src/measure.js';
test('archive paths cannot escape or target network resources',()=>{
  for(const p of ['../secret','C:\\secret','/etc/passwd','x/../../file','a\0b']) assert.throws(()=>safePath(p));
  assert.equal(safePath('./scan/room.obj'),'scan/room.obj');
});
test('unsafe zip entries are rejected',async()=>assert.rejects(unpack(zipSync({'../room.obj':strToU8('x')}))));
test('asset lookup supports OBJ folders and rejects network fetches and ambiguity',()=>{
  const assets={'room/model.obj':new Uint8Array(),'room/textures/wall.jpg':new Uint8Array()};
  assert.equal(resolveAsset('textures/wall.jpg',assets,'room/'),'room/textures/wall.jpg');
  assert.throws(()=>resolveAsset('https://example.com/image.jpg',assets));
  assert.throws(()=>resolveAsset('wall.jpg',{'a/wall.jpg':1,'b/wall.jpg':2}));
});
test('project zip roundtrip preserves source data, scale and measurements',async()=>{
  const project={version:1,name:'Tor',upAxis:'z',scale:.001,measurements:[{kind:'distance',label:'Breite',points:[[0,0,0],[3000,0,0]]}]};
  const assets={'gate.obj':strToU8('v 0 0 0\nv 3000 0 0\nv 0 1000 0\nf 1 2 3')};
  const blob=await packageProject({assets},project), loaded=await readFiles([new File([blob],'Tor.zip')]);
  assert.deepEqual(loaded.project,project);assert.deepEqual(loaded.assets,assets);
});
test('multiple models are not silently merged with mismatched coordinate systems',async()=>{
  await assert.rejects(readFiles([new File(['v 0 0 0'],'a.obj'),new File(['v 1 1 1'],'b.obj')]));
});
test('CSV neutralizes spreadsheet formulas and uses explicit metric units',()=>{
  const csv=csvReport([{kind:'distance',label:'=HYPERLINK("x")',points:[[0,0,0],[3,0,0]]}],1,resultFor);
  assert.match(csv,/length_m/);assert.match(csv,/'=HYPERLINK/);assert.match(csv,/,"3",/);
});
