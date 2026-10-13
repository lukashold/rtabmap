import { strToU8 } from 'fflate';
import { MeasureError, resultFor } from './measure.js';
import { ShapeUtils, Vector2 } from 'three';
import { storedSurfaces } from './areas.js';

const kinds=['wall','door','window','opening','floor'];
const finite=v=>Number.isFinite(v)&&Math.abs(v)<=100000;
const vector=(v,n)=>Array.isArray(v)&&v.length===n&&v.every(finite);
export function validateRoomPlan(data) {
  if(data?.format!=='kantura-room-plan'||data.version!==1||data.units!=='m'||data.coordinateSystem?.upAxis!=='y'||data.coordinateSystem?.handedness!=='right'||data.coordinateSystem?.matrixOrder!=='column-major'||typeof data.name!=='string'||data.name.length>200||!Array.isArray(data.surfaces)||!data.surfaces.length||data.surfaces.length>150)throw new MeasureError('roomplanUnsupported');
  const ids=new Set();
  if(data.building!==undefined&&(!data.building||['name','floor','room'].some(key=>typeof data.building[key]!=='string'||data.building[key].length>200)))throw new MeasureError('roomplanUnsupported');
  for(const s of data.surfaces) {
    if(typeof s.id!=='string'||s.id.length>200||ids.has(s.id)||!kinds.includes(s.kind)||!vector(s.dimensions,3)||s.dimensions.some(v=>v<0)||!vector(s.transform,16)||!['high','medium','low','unknown'].includes(s.confidence))throw new MeasureError('roomplanUnsupported');
    ids.add(s.id);
    const m=s.transform;
    if(Math.abs(m[3])+Math.abs(m[7])+Math.abs(m[11])+Math.abs(m[15]-1)>1e-4)throw new MeasureError('roomplanUnsupported');
    // Dimensions are meters: the transform must be rigid, not another scale.
    for(let a=0;a<3;a++)for(let b=0;b<3;b++)if(Math.abs(m[a*4]*m[b*4]+m[a*4+1]*m[b*4+1]+m[a*4+2]*m[b*4+2]-(a===b?1:0))>.02)throw new MeasureError('roomplanUnsupported');
    if(s.polygonCorners!==undefined&&(!Array.isArray(s.polygonCorners)||s.polygonCorners.length<3||s.polygonCorners.length>100||!s.polygonCorners.every(v=>vector(v,3))))throw new MeasureError('roomplanUnsupported');
  }
  return data;
}
export function transformPoint(p,m) {return [m[0]*p[0]+m[4]*p[1]+m[8]*p[2]+m[12],m[1]*p[0]+m[5]*p[1]+m[9]*p[2]+m[13],m[2]*p[0]+m[6]*p[1]+m[10]*p[2]+m[14]];}
const openingKinds=['door','window','opening'];
/** Apply the user's corrections from the iPhone app (surface id → kind or
 * "deleted"). An opening marked "wall" closes its wall, like on the phone. */
export function applyCorrections(data) {
  const corrections=data.corrections;
  if(corrections===undefined)return data;
  if(!corrections||typeof corrections!=='object'||Array.isArray(corrections)||Object.keys(corrections).length>150)throw new MeasureError('roomplanUnsupported');
  const ids=new Set(data.surfaces.map(s=>s.id));
  for(const [id,kind] of Object.entries(corrections))if(!ids.has(id)||![...kinds,'deleted'].includes(kind)||kind==='floor')throw new MeasureError('roomplanUnsupported');
  const surfaces=data.surfaces.flatMap(s=>{
    const kind=corrections[s.id];
    if(kind===undefined||s.kind==='floor')return [s];
    if(kind==='deleted'||kind==='wall'&&openingKinds.includes(s.kind))return [];
    return [{...s,kind}];
  });
  if(!surfaces.length)throw new MeasureError('roomplanUnsupported');
  return {...data,surfaces};
}
export function roomPlanBundle(data,labels={}) {
  validateRoomPlan(data);
  data=applyCorrections(data);
  let obj='mtllib roomplan.mtl\n',index=1;
  const measurements=[],notes=[],vertices=[];
  const add=(surface,kind,label,points)=>{try{resultFor({kind,points},1);measurements.push({id:`${surface.id}-${kind}-${measurements.length}`,kind,label,points,source:'roomplan',confidence:surface.confidence});}catch{/* Incomplete/non-planar capture has no claimed area. */}};
  data.surfaces.forEach((s,i)=>{
    const [w,h]=s.dimensions,m=s.transform;
    const label=`${labels[s.kind]||s.kind} ${i+1}`;
    const rectangle=[[-w/2,-h/2,0],[w/2,-h/2,0],[w/2,h/2,0],[-w/2,h/2,0]];
    // A floor without its actual contour is deliberately not filled or measured.
    const local=s.polygonCorners||(s.kind!=='floor'&&w>0&&h>0?rectangle:[]);
    const points=local.map(p=>transformPoint(p,m));
    let shape;
    if(points.length>=3)try{shape=resultFor({kind:s.kind==='floor'?'floor':'surface',points},1);}catch{/* Never create phantom geometry from an invalid contour. */}
    if(shape){
      vertices.push(...points);
      obj+=`o surface_${i}\nusemtl ${s.kind}\n`+points.map(p=>'v '+p.join(' ')).join('\n')+'\n';
      const triangles=ShapeUtils.triangulateShape(shape.flat.map(p=>new Vector2(...p)),[]);
      obj+=triangles.map(face=>'f '+face.map(j=>index+j).join(' ')).join('\n')+'\n';index+=points.length;
      add(s,s.kind==='floor'?'floor':'surface',label,points);
    }
    if(s.kind!=='floor'&&w>0&&h>0){
      add(s,'distance',`${label} · ${labels.width||'Width'}`,rectangle.slice(0,2).map(p=>transformPoint(p,m)));
      add(s,'distance',`${label} · ${labels.height||'Height'}`,[rectangle[1],rectangle[2]].map(p=>transformPoint(p,m)));
    }
    notes.push({id:`roomplan-${i}`,title:label,description:`RoomPlan · ${s.confidence}`,kind:['door','window','wall'].includes(s.kind)?s.kind:'other',point:transformPoint([0,0,0],m)});
  });
  if(index===1)throw new MeasureError('roomplanUnsupported');
  // Viewer centers every model. Normalize generated geometry and annotations
  // together once, so imported dimensions also line up with later picked points.
  const bounds=axis=>[Math.min(...vertices.map(p=>p[axis])),Math.max(...vertices.map(p=>p[axis]))];
  const x=bounds(0),y=bounds(1),z=bounds(2),offset=[(x[0]+x[1])/2,y[0],(z[0]+z[1])/2],normalize=p=>p.map((v,i)=>v-offset[i]);
  obj=obj.replace(/^v (.+)$/gm,(_,line)=>'v '+normalize(line.split(' ').map(Number)).join(' '));
  measurements.forEach(m=>m.points=m.points.map(normalize));notes.forEach(note=>note.point=normalize(note.point));
  const mtl='newmtl wall\nKd 0.84 0.82 0.9\nnewmtl door\nKd 0.44 0.87 0.72\nnewmtl window\nKd 0.48 0.7 0.94\nnewmtl opening\nKd 0.78 0.7 0.94\nnewmtl floor\nKd 0.68 0.56 0.44\n';
  // Preserve the original detected surfaces (translated with the model) so floor,
  // gross/net wall areas and opening assignments can be recomputed and corrected.
  const roomSurfaces=storedSurfaces(data.surfaces,offset,(s,i)=>`${labels[s.kind]||s.kind} ${i+1}`);
  const project={version:1,name:data.name,scale:1,upAxis:'y',calibrated:false,demo:!!data.demo,measurements,notes,checks:[],roomSurfaces,openingAssignments:{}};
  return {model:'roomplan.obj',assets:{'roomplan.obj':strToU8(obj),'roomplan.mtl':strToU8(mtl)},name:data.name,project,roomPlan:true,demo:!!data.demo,location:data.building};
}
