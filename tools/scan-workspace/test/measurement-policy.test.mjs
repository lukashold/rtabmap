import test from 'node:test';
import assert from 'node:assert/strict';
import { zipSync, strToU8 } from 'fflate';
import { measurementPolicy } from '../src/measurement-policy.js';
import { validateProject } from '../src/measure.js';
import { readFiles,packageProject } from '../src/files.js';
test('AI geometry remains viewable and annotatable but reference scaling never permits measurements',()=>{
  assert.equal(measurementPolicy('generated',false).canMeasure,false);
  assert.equal(measurementPolicy('generated',true).canMeasure,false);
  assert.equal(measurementPolicy('generated',true).canCalibrate,false);
  assert.equal(measurementPolicy('generated',true).metricDisplay,false);
  assert.equal(measurementPolicy('generated',true).canNote,true);
  assert.equal(measurementPolicy('photogrammetry',false).canMeasure,false);
  assert.equal(measurementPolicy('photogrammetry',true).canMeasure,true);
  assert.equal(measurementPolicy('photogrammetry',true,['camera_pose_ambiguity']).canMeasure,false);
  assert.equal(measurementPolicy('photogrammetry',false,['insufficient_parallax']).canCalibrate,false);
  assert.equal(measurementPolicy('photogrammetry',true,['repeated_camera_views']).canMeasure,true);
});
test('generated provenance survives project archive save/reload and rejects a forged metric result',async()=>{
  const project={version:1,name:'Generated object',source:'generated',scale:1,upAxis:'y',calibrated:false,measurements:[],notes:[],checks:[]};
  const input=zipSync({'model.obj':strToU8('v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3'),'rtab-measure.json':strToU8(JSON.stringify(project))});
  const bundle=await readFiles([new File([input],'generated.zip')]);
  assert.equal(bundle.project.source,'generated');
  const saved=await packageProject(bundle,bundle.project),restored=await readFiles([new File([saved],'saved.zip')]);
  assert.equal(restored.project.source,'generated');
  for(const forged of [{calibrated:true},{measurements:[{kind:'distance',label:'Invented',points:[[0,0,0],[1,0,0]]}]},{checks:[{}]}])assert.throws(()=>validateProject({...project,...forged}),{code:'invalidProject'});
});

test('reconstruction warnings persist through archive roundtrip and reject unknown or duplicated diagnoses',async()=>{
  const project={version:1,name:'Review scan',source:'photogrammetry',scale:1,upAxis:'y',calibrated:false,measurements:[],notes:[],checks:[],captureWarnings:['camera_pose_ambiguity']};
  const bundle={model:'model.obj',assets:{'model.obj':strToU8('v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3')}};
  const file=await packageProject(bundle,project),loaded=await readFiles([new File([file],'review.zip')]);
  assert.deepEqual(loaded.project.captureWarnings,project.captureWarnings);
  assert.equal(measurementPolicy(loaded.project.source,true,loaded.project.captureWarnings).canMeasure,false);
  for(const warnings of ['camera_pose_ambiguity',['script'],['camera_pose_ambiguity','camera_pose_ambiguity']])assert.throws(()=>validateProject({...project,captureWarnings:warnings}),{code:'invalidProject'});
  assert.throws(()=>validateProject({...project,calibrated:'yes'}),{code:'invalidProject'});
});
