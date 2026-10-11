import test from 'node:test';
import assert from 'node:assert/strict';
import { File } from 'node:buffer';
import { strFromU8, strToU8, zipSync } from 'fflate';
import { Box3, Triangle, Vector3 } from 'three';
import { roomPlanBundle, validateRoomPlan } from '../src/roomplan.js';
import { parseModel } from '../src/viewer.js';
import { readFiles, packageBuilding, packageProject } from '../src/files.js';
import { validateProject, resultFor } from '../src/measure.js';
import { referenceCheck } from '../src/experience.js';
import { experienceDictionaries } from '../src/experience-i18n.js';
const matrix=[1,0,0,0,0,1,0,0,0,0,1,0,10,1.5,20,1];
const floorMatrix=[1,0,0,0,0,0,1,0,0,-1,0,0,10,0,20,1];
const data=()=>({format:'kantura-room-plan',version:1,units:'m',name:'Kitchen',coordinateSystem:{upAxis:'y',handedness:'right',matrixOrder:'column-major'},building:{name:'House',floor:'EG',room:'Kitchen'},surfaces:[{id:'wall',kind:'wall',dimensions:[4,3,0],transform:[...matrix],confidence:'high'},{id:'floor',kind:'floor',dimensions:[3,3,0],transform:[...floorMatrix],confidence:'medium',polygonCorners:[[3,0,0],[3,1,0],[1,1,0],[1,3,0],[0,3,0],[0,0,0]]}]});
test('RoomPlan dimensions use column-major rigid world transforms and meter units',()=>{
  const bundle=roomPlanBundle(data());validateProject(bundle.project);
  assert.equal(bundle.project.upAxis,'y');assert.equal(bundle.location.floor,'EG');
  const measures=bundle.project.measurements;
  assert.equal(resultFor(measures.find(m=>m.kind==='floor'),1).area,5);
  assert.deepEqual(measures.filter(m=>m.kind==='distance').map(m=>resultFor(m,1).length),[4,3]);
});
test('concave RoomPlan mesh is ear-clipped and does not create a phantom floor',async()=>{
  const bundle=roomPlanBundle(data()),root=await parseModel(bundle);let area=0;
  root.traverse(mesh=>{if(mesh.name!=='surface_1')return;const p=mesh.geometry.attributes.position;for(let i=0;i<p.count;i+=3)area+=new Triangle(new Vector3().fromBufferAttribute(p,i),new Vector3().fromBufferAttribute(p,i+1),new Vector3().fromBufferAttribute(p,i+2)).getArea();});
  assert.equal(area,5);
  const bounds=new Box3().setFromObject(root);assert.ok(Math.abs(bounds.getCenter(new Vector3()).x)<1e-8);assert.equal(bounds.min.y,0);
  for(const measure of bundle.project.measurements)for(const point of measure.points)assert.ok(bounds.containsPoint(new Vector3(...point)));
});
test('a floor without polygon is never reported as its bounding rectangle',()=>{
  const d=data();delete d.surfaces[1].polygonCorners;assert.ok(!roomPlanBundle(d).project.measurements.some(m=>m.kind==='floor'));
});
test('RoomPlan rejects unexpected units, scale/shear, duplicate surfaces and invalid numbers',()=>{
  for(const mutate of [d=>d.units='cm',d=>d.surfaces[0].transform[0]=2,d=>d.surfaces[0].transform[3]=1,d=>d.surfaces[0].dimensions[0]=NaN,d=>d.surfaces.push(d.surfaces[0])]){const d=data();mutate(d);assert.throws(()=>validateRoomPlan(d));}
});
test('multiple floors, independent rooms, notes/photos and reference checks roundtrip together',async()=>{
  const bundle=roomPlanBundle(data()),p=bundle.project;
  p.notes.push({id:'photo-note',title:'Gate',description:'Hinge',kind:'gate',point:[0,0,0],photo:'kantura-notes/photo.jpg'});bundle.assets['kantura-notes/photo.jpg']=new Uint8Array([1,2,3]);
  p.checks=[{id:'check',label:'Width',points:[[0,0,0],[4,0,0]],knownMeters:4.1,createdAt:'2026-10-11T12:00:00Z'}];
  const second=roomPlanBundle({...data(),name:'Bedroom'});
  const building={name:'House',activeRoom:'upstairs',rooms:[{id:'ground',floor:'EG',bundle,project:p},{id:'upstairs',floor:'1. OG',bundle:second,project:second.project}]};
  const blob=await packageBuilding(building),restored=await readFiles([new File([blob],'House.kantura-building.zip')]);
  assert.equal(restored.project.name,'Bedroom');assert.equal(restored.building.rooms.length,2);assert.equal(restored.building.rooms[0].floor,'EG');
  assert.deepEqual(restored.building.rooms[0].project,p);assert.deepEqual(restored.building.rooms[0].bundle.assets['kantura-notes/photo.jpg'],bundle.assets['kantura-notes/photo.jpg']);
});
test('invalid room manifests and missing referenced photos cannot be saved or reopened',async()=>{
  const bundle=roomPlanBundle(data()),p={...bundle.project,notes:[{id:'n',title:'x',description:'',kind:'other',point:[0,0,0],photo:'kantura-notes/missing.jpg'}]};
  await assert.rejects(packageProject(bundle,p));await assert.rejects(packageBuilding({name:'House',rooms:[{id:'x',floor:'EG',bundle,project:p}]}));
  const zip=zipSync({'kantura-building.json':strToU8(JSON.stringify({format:'kantura-building',version:1,name:'House',rooms:[{id:'x',floor:'EG',prefix:'../'}]}))});
  await assert.rejects(readFiles([new File([zip],'bad.zip')]));
});
test('archive export never exceeds its own supported entry count',async()=>{
  const bundle=roomPlanBundle(data());for(let i=0;i<2000;i++)bundle.assets[`image${i}.png`]=new Uint8Array([1]);
  await assert.rejects(packageBuilding({name:'House',rooms:[{id:'x',floor:'EG',bundle,project:bundle.project}]}),e=>e.code==='tooLarge');
});
test('reference deviations change with calibration and never imply certification',()=>{
  const check={knownMeters:2,points:[[0,0,0],[2.1,0,0]]};assert.ok(Math.abs(referenceCheck(check,1).percent-5)<1e-8);assert.ok(Math.abs(referenceCheck(check,2/2.1).difference)<1e-8);assert.throws(()=>referenceCheck({...check,knownMeters:0},1));
});
test('note/check project validation rejects active paths, duplicate ids and unsafe numbers',()=>{
  const p=roomPlanBundle(data()).project;const note={id:'n',title:'x',description:'',kind:'other',point:[0,0,0]};
  for(const change of [{photo:'https://evil/x.jpg'},{point:[Infinity,0,0]},{description:'x'.repeat(4001)},{title:''}])assert.throws(()=>validateProject({...p,notes:[{...note,...change}]}));
  assert.throws(()=>validateProject({...p,notes:[note,note]}));
});
test('experience features have complete translations for all supported UI languages',()=>{
  for(const dictionary of Object.values(experienceDictionaries)){assert.deepEqual(Object.keys(dictionary),Object.keys(experienceDictionaries.de));assert.ok(Object.values(dictionary).every(v=>typeof v==='string'&&v.length>0));}
});
