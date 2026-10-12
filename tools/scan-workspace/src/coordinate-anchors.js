import { measurementPolicy } from './measurement-policy.js';

// Picks and saved notes already use the centered Y-up viewer frame. Scale them
// once; applying the imported file's up-axis again would rotate them twice.
export function coordinateAnchors(project, {roomId='',floor='',modelToViewer}={}) {
  if(!project || !measurementPolicy(project.source,project.calibrated,project.captureWarnings||[]).canMeasure) {
    throw Object.assign(new Error('coordinateSourceUnavailable'),{code:'coordinateSourceUnavailable'});
  }
  const scale=project.scale;
  if(!Number.isFinite(scale)||scale<=0||scale>1e9) throw new Error('Invalid coordinate scale');
  const points=[],labels=[],seen=new Set();
  for(const note of project.notes||[]) {
    if(note.id?.startsWith('roomplan-'))continue;
    const p=note.point;
    if(!Array.isArray(p)||p.length!==3||!p.every(v=>Number.isFinite(v)&&Math.abs(v*scale)<=1e9))throw new Error('Invalid coordinate point');
    const point=p.map(v=>v*scale),key=JSON.stringify(point);
    if(seen.has(key))continue;
    if(points.length>=100)throw new Error('Too many coordinate anchors');
    seen.add(key);points.push(point);labels.push(String(note.title||'').slice(0,200));
  }
  let modelToFrame;
  if(modelToViewer!==undefined) {
    if(!Array.isArray(modelToViewer)||modelToViewer.length!==16||!modelToViewer.every(Number.isFinite)||modelToViewer[3]!==0||modelToViewer[7]!==0||modelToViewer[11]!==0||modelToViewer[15]!==1)throw new Error('Invalid model frame');
    modelToFrame=modelToViewer.map((value,index)=>index%4<3?value*scale:value);
  }
  return {points,labels,sourceFrame:{roomId:String(roomId),name:String(project.name||''),floor:String(floor),kind:'viewer-centered-y-up',units:'m',modelToFrame},metricAccuracyValidated:false};
}
