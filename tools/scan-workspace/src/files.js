import { unzip, zip, strFromU8, strToU8 } from 'fflate';
import { validateProject, MeasureError } from './measure.js';
import { roomPlanBundle } from './roomplan.js';
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
export async function readFiles(input,{roomLabels={}}={}) {
  const files=Array.from(input);
  if(!files.length) throw new MeasureError('unsupported');
  if(files.reduce((s,f)=>s+f.size,0)>MAX_INPUT) throw new MeasureError('tooLarge');
  if(files.length===1&&/\.json$/i.test(files[0].name)) {
    if(files[0].size>5*1024*1024)throw new MeasureError('tooLarge');
    try{return roomPlanBundle(JSON.parse(await files[0].text()),roomLabels);}catch(error){throw new MeasureError(error?.code||'roomplanUnsupported');}
  }
  let entries=Object.create(null);
  if(files.length===1&&/\.zip$/i.test(files[0].name)) entries=await unpack(new Uint8Array(await files[0].arrayBuffer()));
  else for(const file of files){const path=safePath(file.webkitRelativePath||file.name);if(Object.hasOwn(entries,path))throw new MeasureError('badArchive');entries[path]=new Uint8Array(await file.arrayBuffer());}
  let project;
  if(entries['rtab-measure.json']) {
    try {project=validateProject(JSON.parse(strFromU8(entries['rtab-measure.json'])));} catch { throw new MeasureError('invalidProject'); }
  }
  if(entries['kantura-building.json']) {
    let manifest;
    try{manifest=JSON.parse(strFromU8(entries['kantura-building.json']));}catch{throw new MeasureError('invalidProject');}
    if(manifest?.format!=='kantura-building'||manifest.version!==1||typeof manifest.name!=='string'||manifest.name.length>200||!Array.isArray(manifest.rooms)||!manifest.rooms.length||manifest.rooms.length>100)throw new MeasureError('invalidProject');
    const ids=new Set();
    const rooms=manifest.rooms.map((room,i)=>{
      if(typeof room.id!=='string'||room.id.length>200||ids.has(room.id)||typeof room.floor!=='string'||room.floor.length>200||room.prefix!==`rooms/${i}/`)throw new MeasureError('invalidProject');ids.add(room.id);
      const local=Object.fromEntries(Object.entries(entries).filter(([p])=>p.startsWith(room.prefix)).map(([p,data])=>[p.slice(room.prefix.length),data]));
      let p;try{p=validateProject(JSON.parse(strFromU8(local['rtab-measure.json'])));}catch{throw new MeasureError('invalidProject');}
      const assets=Object.fromEntries(Object.entries(local).filter(([path])=>allowed.test(path))),models=Object.keys(assets).filter(path=>/\.(obj|ply|glb)$/i.test(path));
      if(models.length!==1||p.notes?.some(n=>n.photo&&!assets[n.photo]))throw new MeasureError('invalidProject');
      return {id:room.id,floor:room.floor,bundle:{assets,model:models[0],name:p.name,project:p},project:p};
    });
    const active=rooms.find(room=>room.id===manifest.activeRoom)||rooms[0];
    return {...active.bundle,building:{name:manifest.name,activeRoom:active.id,rooms}};
  }
  const assets=Object.fromEntries(Object.entries(entries).filter(([p])=>allowed.test(p)&&!p.startsWith('__MACOSX/')));
  if(project?.notes?.some(n=>n.photo&&!assets[n.photo]))throw new MeasureError('missingAsset');
  const models=Object.keys(assets).filter(p=>/\.(obj|ply|glb)$/i.test(p));
  if(models.length!==1) throw new MeasureError(models.length?'multipleModels':'unsupported');
  return {assets,model:models[0],project,name:project?.name||files[0].name.replace(/\.[^.]+$/,'')};
}
export async function packageProject(bundle,project) {
  validateProject(project);
  if(project.notes?.some(n=>n.photo&&!bundle.assets[n.photo]))throw new MeasureError('missingAsset');
  const entries={...bundle.assets,'rtab-measure.json':strToU8(JSON.stringify(project,null,2))};
  if(Object.keys(entries).length>2000||Object.values(entries).reduce((s,b)=>s+b.byteLength,0)>MAX_UNPACKED)throw new MeasureError('tooLarge');
  return new Promise((resolve,reject)=>zip(entries,{level:1},(err,data)=>err?reject(err):data.length>MAX_INPUT?reject(new MeasureError('tooLarge')):resolve(new Blob([data],{type:'application/zip'}))));
}
export async function packageBuilding(building) {
  if(!building?.rooms?.length||building.rooms.length>100||typeof building.name!=='string'||building.name.length>200)throw new MeasureError('invalidProject');
  const entries={},rooms=[],ids=new Set();
  building.rooms.forEach((room,i)=>{
    if(typeof room.id!=='string'||room.id.length>200||ids.has(room.id)||typeof room.floor!=='string'||room.floor.length>200)throw new MeasureError('invalidProject');ids.add(room.id);
    validateProject(room.project);
    if(room.project.notes?.some(n=>n.photo&&!room.bundle.assets[n.photo]))throw new MeasureError('missingAsset');
    const prefix=`rooms/${i}/`;rooms.push({id:room.id,floor:room.floor,prefix});
    for(const [path,bytes] of Object.entries(room.bundle.assets))entries[prefix+safePath(path)]=bytes;
    entries[prefix+'rtab-measure.json']=strToU8(JSON.stringify(room.project));
  });
  if(Object.values(entries).reduce((s,b)=>s+b.byteLength,0)>MAX_UNPACKED)throw new MeasureError('tooLarge');
  entries['kantura-building.json']=strToU8(JSON.stringify({format:'kantura-building',version:1,name:building.name,activeRoom:building.activeRoom,rooms}));
  if(Object.keys(entries).length>2000)throw new MeasureError('tooLarge');
  return new Promise((resolve,reject)=>zip(entries,{level:1},(error,data)=>error?reject(error):data.length>MAX_INPUT?reject(new MeasureError('tooLarge')):resolve(new Blob([data],{type:'application/zip'}))));
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
