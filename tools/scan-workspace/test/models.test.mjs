import test from 'node:test';
import assert from 'node:assert/strict';
import { Box3, Vector3 } from 'three';
import { strToU8 } from 'fflate';
import { parseModel, demoBundle } from '../src/viewer.js';
test('OBJ and MTL load together without changing source metric scale',async()=>{
  const root=await parseModel(demoBundle()),size=new Box3().setFromObject(root).getSize(new Vector3());
  assert.ok(Math.abs(size.x-4.92)<1e-6);assert.ok(Math.abs(size.y-3.72)<1e-6);
  assert.ok(root.children.some(mesh=>mesh.material.color));
});
test('PLY face geometry retains meter dimensions',async()=>{
  const ply='ply\nformat ascii 1.0\nelement vertex 4\nproperty float x\nproperty float y\nproperty float z\nelement face 2\nproperty list uchar int vertex_indices\nend_header\n0 0 0\n4 0 0\n4 3 0\n0 3 0\n3 0 1 2\n3 0 2 3\n';
  const model=await parseModel({model:'test.ply',assets:{'test.ply':strToU8(ply)}});
  assert.equal(model.geometry.index.count,6);assert.deepEqual(new Box3().setFromObject(model).getSize(new Vector3()).toArray(),[4,3,0]);
});
test('GLB geometry loads with its declared transforms and units',async()=>{
  const data={asset:{version:'2.0'},scene:0,scenes:[{nodes:[0]}],nodes:[{mesh:0}],meshes:[{primitives:[{attributes:{POSITION:0}}]}],buffers:[{byteLength:36}],bufferViews:[{buffer:0,byteOffset:0,byteLength:36}],accessors:[{bufferView:0,componentType:5126,count:3,type:'VEC3',min:[0,0,0],max:[4,3,0]}]};
  const json=JSON.stringify(data),jsonBytes=Buffer.from(json.padEnd(Math.ceil(json.length/4)*4,' '));
  const bin=Buffer.from(new Float32Array([0,0,0,4,0,0,0,3,0]).buffer),file=Buffer.alloc(12+8+jsonBytes.length+8+bin.length);
  file.writeUInt32LE(0x46546c67,0);file.writeUInt32LE(2,4);file.writeUInt32LE(file.length,8);file.writeUInt32LE(jsonBytes.length,12);file.writeUInt32LE(0x4e4f534a,16);jsonBytes.copy(file,20);
  const offset=20+jsonBytes.length;file.writeUInt32LE(bin.length,offset);file.writeUInt32LE(0x004e4942,offset+4);bin.copy(file,offset+8);
  const root=await parseModel({model:'test.glb',assets:{'test.glb':new Uint8Array(file)}});
  assert.deepEqual(new Box3().setFromObject(root).getSize(new Vector3()).toArray(),[4,3,0]);
});
