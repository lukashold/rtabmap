import test from 'node:test';
import assert from 'node:assert/strict';
import {coordinateAnchors} from '../src/coordinate-anchors.js';

test('manual picked anchors scale once in their existing Y-up frame and preserve labels',()=>{
 const p={name:'Upper floor',scale:2,upAxis:'z',notes:[{id:'a',title:'A',point:[1,2,3]},{id:'b',title:'B',point:[0,1,0]},{id:'c',title:'C',point:[0,0,1]},{id:'duplicate',point:[1,2,3]},{id:'roomplan-wall',point:[7,8,9]}]};
 const r=coordinateAnchors(p,{roomId:'floor-1',floor:'OG',modelToViewer:[1,0,0,0,0,1,0,0,0,0,1,0,-3,1,2,1]});
 assert.deepEqual(r.points,[[2,4,6],[0,2,0],[0,0,2]]);assert.deepEqual(r.labels,['A','B','C']);
 assert.deepEqual(r.sourceFrame.modelToFrame,[2,0,0,0,0,2,0,0,0,0,2,0,-6,2,4,1]);
 assert.equal(r.sourceFrame.roomId,'floor-1');assert.equal(r.metricAccuracyValidated,false);
 r.points[0][0]=100;assert.equal(p.notes[0].point[0],1);
});
test('nonmetric or suspect projects cannot supply metric registration anchors',()=>{
 for(const project of [{source:'generated',calibrated:true},{source:'photogrammetry',calibrated:false},{captureWarnings:['camera_pose_ambiguity']},{captureWarnings:['insufficient_parallax']}])
  assert.throws(()=>coordinateAnchors({...project,scale:1,notes:[]}),{code:'coordinateSourceUnavailable'});
 assert.deepEqual(coordinateAnchors({source:'photogrammetry',calibrated:true,scale:1,notes:[]}).points,[]);
 assert.throws(()=>coordinateAnchors({scale:0,notes:[]}));
 assert.throws(()=>coordinateAnchors({scale:1,notes:[{point:[0,NaN,0]}]}));
});
