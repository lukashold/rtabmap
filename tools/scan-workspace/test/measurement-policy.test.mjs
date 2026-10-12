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
