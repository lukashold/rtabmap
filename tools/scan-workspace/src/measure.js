import { assessTransport } from './transport.js';
export class MeasureError extends Error { constructor(code) { super(code); this.code = code; } }
const sub = (a, b) => a.map((v, i) => v - b[i]);
const dot = (a, b) => a.reduce((s, v, i) => s + v * b[i], 0);
const cross = (a, b) => [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]];
const norm = a => Math.hypot(...a);
const unit = a => a.map(v => v / norm(a));
export function validatePoints(points, minimum = 2) {
  if (!Array.isArray(points) || points.length < minimum || points.length > 1000 || points.some(p => !Array.isArray(p) || p.length !== 3 || p.some(v => !Number.isFinite(v) || Math.abs(v) > 1e9))) throw new MeasureError('invalidPoints');
}
export function validateScale(scale) {
  if (!Number.isFinite(scale) || scale <= 0 || scale > 1e6) throw new MeasureError('invalidScale');
}
export function distance(a, b, scale = 1) {
  validatePoints([a, b]); validateScale(scale);
  const d = sub(b, a);
  return { length: norm(d) * scale, horizontal: Math.hypot(d[0], d[2]) * scale, vertical: Math.abs(d[1]) * scale };
}
function cross2(a, b, c) { return (b[0]-a[0])*(c[1]-a[1]) - (b[1]-a[1])*(c[0]-a[0]); }
function onSegment(a, b, p, epsilon) {
  return Math.abs(cross2(a,b,p)) < epsilon && p[0] >= Math.min(a[0],b[0])-epsilon && p[0] <= Math.max(a[0],b[0])+epsilon && p[1] >= Math.min(a[1],b[1])-epsilon && p[1] <= Math.max(a[1],b[1])+epsilon;
}
export function polygon(points, scale = 1, kind = 'floor') {
  validatePoints(points, 3); validateScale(scale);
  if (!['floor', 'surface'].includes(kind)) throw new MeasureError('invalidPoints');
  const origin = points[0], local = points.map(p => sub(p, origin));
  const extent = Math.max(...local.map(norm), 1e-9);
  const epsilon = Math.max(extent * extent * 1e-10, 1e-14);
  let normal = [0, 1, 0], u = [1, 0, 0], v = [0, 0, 1];
  if (kind === 'surface') {
    // Choose the largest non-collinear pair; concave polygons are supported.
    let largest = [0, 0, 0];
    for (let i=1;i<local.length;i++) for(let j=i+1;j<local.length;j++) {
      const n = cross(local[i], local[j]); if(norm(n)>norm(largest)) largest=n;
    }
    if (norm(largest) < epsilon) throw new MeasureError('degenerate');
    normal = unit(largest); u = unit(local.find(p => norm(p) > extent * 1e-8)); v = cross(normal, u);
  }
  // Never silently label a slanted/non-planar outline as a measured floor/surface.
  if (local.some(p => Math.abs(dot(p,normal)) * scale > 0.03)) throw new MeasureError('notPlanar');
  const flat = local.map(p => [dot(p,u), dot(p,v)]);
  const n = flat.length;
  for(let i=0;i<n;i++) for(let j=i+1;j<n;j++) {
    if(Math.hypot(flat[i][0]-flat[j][0],flat[i][1]-flat[j][1]) < extent * 1e-8) throw new MeasureError('duplicatePoint');
    if(j===i+1 || (i===0&&j===n-1)) continue;
    const a=flat[i], b=flat[(i+1)%n], c=flat[j], d=flat[(j+1)%n];
    const p=cross2(a,b,c), q=cross2(a,b,d), r=cross2(c,d,a), s=cross2(c,d,b);
    if((p*q<0&&r*s<0) || onSegment(a,b,c,epsilon) || onSegment(a,b,d,epsilon) || onSegment(c,d,a,epsilon) || onSegment(c,d,b,epsilon)) throw new MeasureError('selfIntersection');
  }
  let area=0, perimeter=0;
  for(let i=0;i<n;i++) {
    const a=flat[i],b=flat[(i+1)%n]; area+=a[0]*b[1]-b[0]*a[1]; perimeter+=Math.hypot(b[0]-a[0],b[1]-a[1]);
  }
  if(Math.abs(area)<epsilon) throw new MeasureError('degenerate');
  return { area: Math.abs(area) * 0.5 * scale * scale, perimeter: perimeter * scale, flat, normal };
}
export function calibration(a,b,knownMeters) {
  if(!Number.isFinite(knownMeters)||knownMeters<=0) throw new MeasureError('invalidScale');
  const measured=distance(a,b).length;
  if(measured<1e-8) throw new MeasureError('degenerate');
  const factor=knownMeters/measured; validateScale(factor); return factor;
}
export function resultFor(measure,scale) {
  return measure.kind==='distance' ? distance(...measure.points,scale) : polygon(measure.points,scale,measure.kind);
}
export function validateProject(p) {
  if(p?.version!==1 || typeof p.name!=='string' || p.name.length>200 || !['y','z'].includes(p.upAxis) || !Array.isArray(p.measurements) || p.measurements.length>500) throw new MeasureError('invalidProject');
  if(p.source!==undefined&&!['photogrammetry','generated'].includes(p.source))throw new MeasureError('invalidProject');
  if(p.source==='generated'&&(p.measurements.length||p.checks?.length||p.calibrated===true||p.transport!==undefined))throw new MeasureError('invalidProject');
  validateScale(p.scale);
  for(const m of p.measurements) {
    if(typeof m.label!=='string'||m.label.length>200||!['distance','floor','surface'].includes(m.kind)) throw new MeasureError('invalidProject');
    if(m.kind==='distance' && m.points.length!==2) throw new MeasureError('invalidProject');
    resultFor(m,p.scale);
  }
  const ids=new Set();
  if(p.transport!==undefined){if(typeof p.transport.model!=='string'||p.transport.model.length>200||typeof p.transport.assessedAt!=='string'||!Number.isFinite(Date.parse(p.transport.assessedAt)))throw new MeasureError('invalidProject');assessTransport(p.transport.input);}
  for(const [key,limit] of [['notes',200],['checks',100]]) {
    if(p[key]===undefined)continue;
    if(!Array.isArray(p[key])||p[key].length>limit)throw new MeasureError('invalidProject');
    for(const item of p[key]) {
      if(typeof item.id!=='string'||item.id.length>200||ids.has(item.id))throw new MeasureError('invalidProject');ids.add(item.id);
      if(key==='notes') {
        if(typeof item.title!=='string'||!item.title.trim()||item.title.length>200||typeof item.description!=='string'||item.description.length>4000||!['door','window','gate','wall','other'].includes(item.kind)||item.photo!==undefined&&!/^kantura-notes\/[a-zA-Z0-9-]{1,80}\.(jpg|png|webp)$/.test(item.photo))throw new MeasureError('invalidProject');
        validatePoints([item.point],1);
      }else{
        if(typeof item.label!=='string'||item.label.length>200||item.points?.length!==2||typeof item.createdAt!=='string'||!Number.isFinite(Date.parse(item.createdAt)))throw new MeasureError('invalidProject');
        validateScale(item.knownMeters);distance(...item.points,p.scale);
      }
    }
  }
  return p;
}
const escapeXML = v => String(v).replace(/[<>&"']/g,c=>({'<':'&lt;','>':'&gt;','&':'&amp;','"':'&quot;',"'":'&apos;'}[c]));
export function floorplanSVG(measurements, scale, name='Floor plan') {
  const floors=measurements.filter(m=>m.kind==='floor');
  if(!floors.length) throw new MeasureError('noFloor');
  floors.forEach(m=>polygon(m.points,scale,'floor'));
  const points=floors.flatMap(m=>m.points.map(p=>[p[0]*scale,-p[2]*scale]));
  const min=[Math.min(...points.map(p=>p[0])),Math.min(...points.map(p=>p[1]))];
  const width=Math.max(...points.map(p=>p[0]))-min[0],height=Math.max(...points.map(p=>p[1]))-min[1];
  const ratio=700/Math.max(width,height,0.01), xy=p=>[(p[0]*scale-min[0])*ratio+70,(-p[2]*scale-min[1])*ratio+90];
  let body='';
  for(const m of floors) {
    const pts=m.points.map(xy), area=polygon(m.points,scale).area;
    body+=`<polygon points="${pts.map(p=>p.join(',')).join(' ')}" fill="#ede9fe" fill-opacity="0.45" stroke="#6d28d9" stroke-width="2"/>`;
    pts.forEach((a,i)=>{const b=pts[(i+1)%pts.length],length=distance(m.points[i],m.points[(i+1)%pts.length],scale).length;body+=`<text x="${(a[0]+b[0])/2}" y="${(a[1]+b[1])/2-8}" text-anchor="middle">${length.toFixed(3)} m</text>`;});
    const center=pts.reduce((a,b)=>[a[0]+b[0]/pts.length,a[1]+b[1]/pts.length],[0,0]);
    body+=`<text x="${center[0]}" y="${center[1]}" text-anchor="middle">${escapeXML(m.label)} · ${area.toFixed(3)} m²</text>`;
  }
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width*ratio+140} ${height*ratio+160}"><rect width="100%" height="100%" fill="white"/><g font-family="sans-serif" font-size="14" fill="#1e1b4b"><text x="30" y="35">${escapeXML(name)}</text>${body}<text x="30" y="${height*ratio+140}">KANTURA · floor contours · m · verify against a reference</text></g></svg>`;
}
