import test from 'node:test';
import assert from 'node:assert/strict';
import {registerLandmarks} from '../src/registration.js';
import {Matrix4,Vector3} from 'three';
import {georeferencePoint} from '../src/georeference.js';

test('geodetic control points can define a rigid candidate without changing scale or asserting survey accuracy',()=>{
 const origin={latitude:45,longitude:8,height:200,verticalDatum:'ellipsoidal',uncertainty:{horizontalMeters:2,verticalMeters:4}};
 const controls=[origin,{...origin,longitude:8.0001},{...origin,latitude:45.0001},{...origin,height:203}].map(p=>georeferencePoint(p,origin));
 const target=controls.map(c=>c.position);
 // Independent known 90-degree source-frame transform, not another fitted matrix.
 const source=target.map(([x,y,z])=>[z+3,y-4,-x+5]);
 const result=registerLandmarks(source,target,{maxResidual:1e-6});
 assert.equal(result.accepted,true);assert.equal(result.scale,1);
 const expected=[0,0,1,0,0,1,0,0,-1,0,0,0,5,4,-3,1];
 result.matrix.forEach((v,i)=>assert.ok(Math.abs(v-expected[i])<1e-8));
 source.forEach((p,i)=>new Vector3(...p).applyMatrix4(new Matrix4().fromArray(result.matrix)).toArray().forEach((v,j)=>assert.ok(Math.abs(v-target[i][j])<1e-8)));
 assert.ok(controls.every(c=>c.metricAccuracyValidated===false&&c.qualityStatus==='unverified'));
 assert.deepEqual(controls[0].origin.uncertainty,origin.uncertainty);
 const unknown=registerLandmarks(source,target);assert.equal(unknown.accepted,null);
});
