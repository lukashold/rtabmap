import { test } from 'node:test';
import assert from 'node:assert/strict';
import { distance, polygon, calibration, validateProject, floorplanSVG } from '../src/measure.js';
const close=(a,b)=>assert.ok(Math.abs(a-b)<1e-8,`${a} != ${b}`);
const rectangle=[[0,0,0],[4,0,0],[4,0,3],[0,0,3]];
test('distance, horizontal and height use physical scale',()=>{
  assert.deepEqual(distance([0,0,0],[3,12,4]),{length:13,horizontal:5,vertical:12});
  close(distance([0,0,0],[3000,0,4000],.001).length,5);
});
test('room outline produces area and perimeter in either winding',()=>{
  for(const points of [rectangle,[...rectangle].reverse()]) { close(polygon(points).area,12);close(polygon(points).perimeter,14); }
  close(polygon(rectangle,2).area,48);close(polygon(rectangle,2).perimeter,28);
});
test('concave L room is not its bounding rectangle',()=>{
  close(polygon([[0,0,0],[4,0,0],[4,0,1],[1,0,1],[1,0,3],[0,0,3]]).area,6);
});
test('surface area supports a vertical gate',()=>{
  close(polygon([[0,0,0],[4,0,0],[4,3,0],[0,3,0]],1,'surface').area,12);
});
test('non-planar, crossing, duplicate and degenerate areas are rejected',()=>{
  const cases=[[[0,0,0],[4,0,0],[4,1,3],[0,0,3]],[[0,0,0],[4,0,3],[4,0,0],[0,0,3]],[[0,0,0],[4,0,0],[0,0,0]],[[0,0,0],[1,0,0],[2,0,0]]];
  for(const p of cases) assert.throws(()=>polygon(p));
});
test('a closing duplicate is rejected instead of double-counted',()=>assert.throws(()=>polygon([...rectangle,rectangle[0]])));
test('area tolerances follow meter scale for millimeter models',()=>{
  close(polygon(rectangle.map(p=>p.map(v=>v*1000)),.001).area,12);
  assert.throws(()=>polygon([[0,0,0],[1000,0,0],[1000,100,1000],[0,0,1000]],.001));
});
test('calibration uses a reference, never rescales twice',()=>{ close(calibration([0,0,0],[2,0,0],3),1.5);assert.throws(()=>calibration([0,0,0],[0,0,0],3)); });
test('invalid numeric data is rejected',()=>{
  for(const scale of [0,-1,Infinity,NaN]) assert.throws(()=>distance([0,0,0],[1,0,0],scale));
  assert.throws(()=>distance([NaN,0,0],[1,0,0]));
});
test('project load validates all geometry and versions',()=>{
  const p={version:1,name:'Room',upAxis:'z',scale:1,measurements:[{kind:'floor',label:'Room',points:rectangle}]};
  assert.equal(validateProject(p),p);assert.throws(()=>validateProject({...p,version:2}));
});
test('SVG floorplan preserves dimensions and escapes labels',()=>{
  const svg=floorplanSVG([{kind:'floor',label:'<script>',points:rectangle}],1,'A&B');
  assert.match(svg,/12.000 m²/);assert.match(svg,/4.000 m/);assert.match(svg,/&lt;script&gt;/);assert.match(svg,/A&amp;B/);
});
