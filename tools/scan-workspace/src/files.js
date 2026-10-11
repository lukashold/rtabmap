import { unzip, zip, strFromU8, strToU8 } from 'fflate';
import { validateProject, MeasureError } from './measure.js';
export const MAX_INPUT=200*1024*1024, MAX_UNPACKED=500*1024*1024;
const allowed=/\.(obj|mtl|ply|glb|bin|png|jpe?g|webp|bmp)$/i;
export function safePath(name) {
  if(typeof name!=='string'||name.length>500||/[\x00-\x1f]/.test(name)) throw new MeasureError('badArchive');
  const path=name.replace(/\\/g,'/');
  if(path.startsWith('/')||path.includes(':')||path.split('/').some(p=>p==='..')) throw new MeasureError('badArchive');
  return path.split('/').filter(p=>p&&p!=='.').join('/');
}
export async function unpack(bytes) {
  if(bytes.byteLength>MAX_INPUT) throw new MeasureError('tooLarge');
  let size=0,count=0,failure=null;
  const files=await new Promise((resolve,reject)=>unzip(bytes,{filter:entry=>{
    try {
      safePath(entry.name);size+=entry.originalSize;count++;
      if(size>MAX_UNPACKED||count>2000) throw new MeasureError('tooLarge');
      return true;
    } catch(e) { failure=e;return false; }
  }},(error,result)=>error?reject(new MeasureError('badArchive')):resolve(result)));
  if(failure) throw failure;
  const out=Object.create(null);size=0;
  for(const [name,data] of Object.entries(files)) {
    size+=data.byteLength;if(size>MAX_UNPACKED) throw new MeasureError('tooLarge');
    const path=safePath(name);if(!path||name.endsWith('/'))continue;
    if(Object.hasOwn(out,path)) throw new MeasureError('badArchive');
    out[path]=data;
  }
  return out;
}
export async function readFiles(input) {
  const files=Array.from(input);
  if(!files.length) throw new MeasureError('unsupported');
  if(files.reduce((s,f)=>s+f.size,0)>MAX_INPUT) throw new MeasureError('tooLarge');
  let entries=Object.create(null);
  if(files.length===1&&/\.zip$/i.test(files[0].name)) entries=await unpack(new Uint8Array(await files[0].arrayBuffer()));
  else for(const file of files){const path=safePath(file.webkitRelativePath||file.name);if(Object.hasOwn(entries,path))throw new MeasureError('badArchive');entries[path]=new Uint8Array(await file.arrayBuffer());}
  let project;
  if(entries['rtab-measure.json']) {
    try {project=validateProject(JSON.parse(strFromU8(entries['rtab-measure.json'])));} catch { throw new MeasureError('invalidProject'); }
  }
  const assets=Object.fromEntries(Object.entries(entries).filter(([p])=>allowed.test(p)&&!p.startsWith('__MACOSX/')));
  const models=Object.keys(assets).filter(p=>/\.(obj|ply|glb)$/i.test(p));
  if(models.length!==1) throw new MeasureError(models.length?'multipleModels':'unsupported');
  return {assets,model:models[0],project,name:project?.name||files[0].name.replace(/\.[^.]+$/,'')};
}
export async function packageProject(bundle,project) {
  validateProject(project);
  const entries={...bundle.assets,'rtab-measure.json':strToU8(JSON.stringify(project,null,2))};
  return new Promise((resolve,reject)=>zip(entries,{level:1},(err,data)=>err?reject(err):resolve(new Blob([data],{type:'application/zip'}))));
}
export function csvReport(measurements,scale,resultFor) {
  const cell=v=>`"${String(v).replace(/^[=+\-@\t\r]/,"'$&").replaceAll('"','""')}"`;
  const rows=[['name','type','length_m','horizontal_m','vertical_m','area_m2','perimeter_m','meters_per_model_unit']];
  for(const m of measurements){const r=resultFor(m,scale);rows.push([m.label,m.kind,r.length??'',r.horizontal??'',r.vertical??'',r.area??'',r.perimeter??'',scale]);}
  return '\uFEFF'+rows.map(row=>row.map(cell).join(',')).join('\r\n');
}
export function download(blob,name) {
  const url=URL.createObjectURL(blob), a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),60000);
}
export function resolveAsset(request,assets,base='') {
  if(/^(https?:|file:|ftp:|\/\/)/i.test(request)) throw new MeasureError('missingAsset');
  let decoded;
  try {decoded=decodeURIComponent(request);} catch {throw new MeasureError('missingAsset');}
  const path=safePath(decoded), relative=safePath(base+path);
  if(Object.hasOwn(assets,relative))return relative;
  if(Object.hasOwn(assets,path))return path;
  const basename=path.split('/').at(-1), matches=Object.keys(assets).filter(p=>p.split('/').at(-1)===basename);
  if(matches.length===1)return matches[0];
  throw new MeasureError('missingAsset');
}
