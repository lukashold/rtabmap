import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { OBJLoader } from 'three/addons/loaders/OBJLoader.js';
import { MTLLoader } from 'three/addons/loaders/MTLLoader.js';
import { PLYLoader } from 'three/addons/loaders/PLYLoader.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { strFromU8, strToU8 } from 'fflate';
import { resolveAsset } from './files.js';
import { MeasureError, resultFor } from './measure.js';

function disposeTree(object) {
  const textures=new Set(),materials=new Set();
  object.traverse(child=>{child.geometry?.dispose();for(const m of Array.isArray(child.material)?child.material:[child.material])if(m){materials.add(m);for(const value of [...Object.values(m),m.userData.originalMap])if(value?.isTexture)textures.add(value);}});
  textures.forEach(t=>t.dispose());materials.forEach(m=>m.dispose());
}
export async function parseModel(bundle) {
  const manager=new THREE.LoadingManager(), urls=[],base=bundle.model.includes('/')?bundle.model.slice(0,bundle.model.lastIndexOf('/')+1):'';
  let assetFailure,pendingLoads=0,completed;
  const start=manager.itemStart.bind(manager),end=manager.itemEnd.bind(manager);
  manager.itemStart=url=>{pendingLoads++;start(url);};
  manager.itemEnd=url=>{pendingLoads--;end(url);if(!pendingLoads)completed?.();};
  manager.onError=url=>{assetFailure=new MeasureError('missingAsset');};
  manager.setURLModifier(request=>{
    if(request.startsWith('blob:')||/^data:(image\/(png|jpeg|webp)|application\/octet-stream);base64,/i.test(request))return request;
    const path=resolveAsset(request,bundle.assets,base);
    const blob=new Blob([bundle.assets[path]],{type:/\.png$/i.test(path)?'image/png':/\.webp$/i.test(path)?'image/webp':'image/jpeg'});
    const url=URL.createObjectURL(blob);urls.push(url);return url;
  });
  const bytes=bundle.assets[bundle.model];let root;
  try {
    if(/\.obj$/i.test(bundle.model)) {
      const text=strFromU8(bytes), loader=new OBJLoader(manager), mtls=[...text.matchAll(/^mtllib\s+(.+)$/gm)].map(m=>m[1].trim());
      if(mtls.length>1)throw new MeasureError('unsupported');
      if(mtls.length){const path=resolveAsset(mtls[0],bundle.assets,base);const material=new MTLLoader(manager).parse(strFromU8(bundle.assets[path]),path.includes('/')?path.slice(0,path.lastIndexOf('/')+1):'');loader.setMaterials(material);}
      root=loader.parse(text);
    } else if(/\.ply$/i.test(bundle.model)) {
      const geometry=new PLYLoader().parse(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength));
      if(geometry.index){geometry.computeVertexNormals();root=new THREE.Mesh(geometry,new THREE.MeshStandardMaterial({vertexColors:geometry.hasAttribute('color'),color:geometry.hasAttribute('color')?0xffffff:0xd8d5e8,roughness:.9,side:THREE.DoubleSide}));}
      else root=new THREE.Points(geometry,new THREE.PointsMaterial({vertexColors:geometry.hasAttribute('color'),color:geometry.hasAttribute('color')?0xffffff:0x796eb8,size:.008}));
    } else {
      const gltf=await new GLTFLoader(manager).parseAsync(bytes.buffer.slice(bytes.byteOffset,bytes.byteOffset+bytes.byteLength),'');root=gltf.scene;
    }
    // Wait for texture loads before revoking object URLs or reporting readiness.
    if(pendingLoads)await new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(new MeasureError('missingAsset')),15000);completed=()=>{clearTimeout(timer);resolve();};});
    if(assetFailure)throw assetFailure;
    let positions=0;
    root.traverse(child=>{
      const attribute=child.geometry?.getAttribute('position');
      if(attribute){positions+=attribute.count;for(let i=0;i<attribute.array.length;i++)if(!Number.isFinite(attribute.array[i])||Math.abs(attribute.array[i])>1e9)throw new MeasureError('invalidPoints');}
      if(child.isMesh)for(const material of Array.isArray(child.material)?child.material:[child.material]){material.side=THREE.DoubleSide;material.userData.originalMap=material.map;material.userData.originalColor=material.color?.clone();}
    });
    if(!positions||positions>10000000)throw new MeasureError(positions?'tooLarge':'unsupported');
    return root;
  }catch(error){if(root)disposeTree(root);throw error;}finally{urls.forEach(url=>URL.revokeObjectURL(url));}
}

export class Viewer {
  constructor(container,onPick) {
    this.container=container;this.onPick=onPick;this.mode='orbit';this.top=false;this.roof=false;this.textured=true;this.labels=[];
    this.renderer=new THREE.WebGLRenderer({antialias:true,alpha:false});
    this.renderer.setPixelRatio(Math.min(devicePixelRatio,2));this.renderer.setClearColor(0xf0f1f5);this.renderer.localClippingEnabled=true;
    this.renderer.domElement.tabIndex=0;this.renderer.domElement.setAttribute('aria-label','3D model');container.append(this.renderer.domElement);
    this.scene=new THREE.Scene();this.scene.add(new THREE.HemisphereLight(0xffffff,0xa0a8bf,2.5));
    const light=new THREE.DirectionalLight(0xffffff,2.5);light.position.set(3,8,5);this.scene.add(light);
    this.perspective=new THREE.PerspectiveCamera(42,1,.01,10000);this.orthographic=new THREE.OrthographicCamera(-5,5,5,-5,.01,10000);this.camera=this.perspective;
    this.annotation=new THREE.Group();this.scene.add(this.annotation);this.ray=new THREE.Raycaster();this.clip=new THREE.Plane(new THREE.Vector3(0,-1,0),100);
    this.setControls();this.observer=new ResizeObserver(()=>this.resize());this.observer.observe(container);
    this.renderer.domElement.addEventListener('pointerdown',e=>this.down=[e.clientX,e.clientY]);
    this.renderer.domElement.addEventListener('pointerup',e=>{
      if(e.button!==0||this.mode==='orbit'||!this.root||!this.down||Math.hypot(e.clientX-this.down[0],e.clientY-this.down[1])>5)return;
      const rect=this.renderer.domElement.getBoundingClientRect();
      this.ray.setFromCamera(new THREE.Vector2((e.clientX-rect.left)/rect.width*2-1,-(e.clientY-rect.top)/rect.height*2+1),this.camera);
      this.ray.params.Points.threshold=this.span*.005;
      const hit=this.ray.intersectObject(this.root,true).find(h=>!this.roof||h.point.y<=this.clip.constant+1e-7);
      if(hit){let point=hit.point;if(hit.object.isPoints&&Number.isInteger(hit.index))point=new THREE.Vector3().fromBufferAttribute(hit.object.geometry.attributes.position,hit.index).applyMatrix4(hit.object.matrixWorld);this.onPick(point.toArray());}
    });
  }
  setControls(){this.controls?.dispose();this.controls=new OrbitControls(this.camera,this.renderer.domElement);this.controls.enableRotate=!this.top;this.controls.addEventListener('change',()=>this.render());}
  resize(){const {width,height}=this.container.getBoundingClientRect();if(!width||!height)return;this.renderer.setSize(width,height);this.perspective.aspect=width/height;this.perspective.updateProjectionMatrix();const extent=(this.span||5)*.65;this.orthographic.left=-extent*width/height;this.orthographic.right=extent*width/height;this.orthographic.top=extent;this.orthographic.bottom=-extent;this.orthographic.updateProjectionMatrix();this.render();}
  setModel(root,upAxis='z'){
    if(this.root){this.scene.remove(this.root);disposeTree(this.root);}
    this.root=new THREE.Group();this.root.add(root);this.root.rotation.x=upAxis==='z'?-Math.PI/2:0;this.root.updateMatrixWorld(true);
    let box=new THREE.Box3().setFromObject(this.root);if(box.isEmpty())throw new MeasureError('unsupported');
    const center=box.getCenter(new THREE.Vector3());this.root.position.set(-center.x,-box.min.y,-center.z);this.root.updateMatrixWorld(true);
    box=new THREE.Box3().setFromObject(this.root);this.span=Math.max(...box.getSize(new THREE.Vector3()).toArray(),.01);this.height=box.max.y;this.center=box.getCenter(new THREE.Vector3());
    this.scene.add(this.root);this.setRoof(this.roof);this.setTexture(this.textured);this.fit();
  }
  fit(){if(!this.root)return;this.perspective.near=this.span/10000;this.perspective.far=this.span*100;this.perspective.updateProjectionMatrix();this.orthographic.near=this.span/10000;this.orthographic.far=this.span*100;
    const aspect=this.container.clientWidth/Math.max(1,this.container.clientHeight),fov=THREE.MathUtils.degToRad(42),limitingFov=Math.min(fov,2*Math.atan(Math.tan(fov/2)*aspect));
    const radius=new THREE.Box3().setFromObject(this.root).getBoundingSphere(new THREE.Sphere()).radius;
    const offset=this.top?new THREE.Vector3(0,this.span*2,0):new THREE.Vector3(.85,.8,1.1).normalize().multiplyScalar(radius/Math.sin(limitingFov/2)*1.08);
    this.camera.position.copy(this.center).add(offset);
    this.camera.up.set(0,this.top?0:1,this.top?-1:0);this.controls.target.copy(this.center);this.camera.zoom=1;this.controls.update();this.resize();}
  setTop(enabled){this.top=enabled;this.camera=enabled?this.orthographic:this.perspective;this.setControls();this.fit();}
  setRoof(enabled){this.roof=enabled;this.clip.constant=(this.height||1)*.55;this.renderer.clippingPlanes=enabled?[this.clip]:[];this.render();}
  setTexture(enabled){this.textured=enabled;this.root?.traverse(child=>{if(child.isMesh)for(const m of Array.isArray(child.material)?child.material:[child.material]){if('originalMap'in m.userData)m.map=enabled?m.userData.originalMap:null;if(m.color)m.color.copy(enabled&&m.userData.originalColor?m.userData.originalColor:new THREE.Color(0xb9c1d5));m.needsUpdate=true;}});this.render();}
  setMode(mode){this.mode=mode;this.renderer.domElement.style.cursor=mode==='orbit'?'grab':'crosshair';}
  drawMeasurements(measurements,pending,scale,format){
    disposeTree(this.annotation);this.annotation.clear();this.labels.forEach(l=>l.element.remove());this.labels=[];
    const radius=(this.span||5)*.0018;
    const add=(points,closed,color,text)=>{
      for(const p of points){const sphere=new THREE.Mesh(new THREE.SphereGeometry(radius*2,12,8),new THREE.MeshBasicMaterial({color,depthTest:false}));sphere.position.fromArray(p);sphere.renderOrder=10;this.annotation.add(sphere);}
      const vertices=points.map(p=>new THREE.Vector3(...p));if(closed&&vertices.length>2)vertices.push(vertices[0]);
      if(vertices.length>1){const line=new THREE.Line(new THREE.BufferGeometry().setFromPoints(vertices),new THREE.LineBasicMaterial({color,depthTest:false}));line.renderOrder=10;this.annotation.add(line);}
      if(text&&vertices.length){const position=new THREE.Vector3();points.forEach(p=>position.add(new THREE.Vector3(...p)));position.divideScalar(points.length);const label=document.createElement('div');label.className='model-label';label.textContent=text;this.container.append(label);this.labels.push({position,element:label});}
    };
    for(const m of measurements){const r=resultFor(m,scale);add(m.points,m.kind!=='distance',0x6d28d9,`${m.label} · ${format(r.area??r.length)} ${m.kind==='distance'?'m':'m²'}`);}
    add(pending,false,0x00a99b);this.render();
  }
  render(){if(!this.camera)return;this.renderer.render(this.scene,this.camera);const width=this.container.clientWidth,height=this.container.clientHeight;for(const label of this.labels){const p=label.position.clone().project(this.camera);label.element.hidden=Math.abs(p.z)>1||Math.abs(p.x)>1||Math.abs(p.y)>1;label.element.style.left=`${(p.x+1)*width/2}px`;label.element.style.top=`${(1-p.y)*height/2}px`;}}
  destroy(){this.observer.disconnect();this.controls.dispose();if(this.root)disposeTree(this.root);disposeTree(this.annotation);this.renderer.dispose();}
}

export function demoBundle(){
  let obj='mtllib room.mtl\n', index=1;
  const box=(name,x,y,z,w,d,h,material)=>{
    obj+=`o ${name}\nusemtl ${material}\n`;
    const points=[[x,y,z],[x+w,y,z],[x+w,y+d,z],[x,y+d,z],[x,y,z+h],[x+w,y,z+h],[x+w,y+d,z+h],[x,y+d,z+h]];
    obj+=points.map(p=>'v '+p.join(' ')).join('\n')+'\n';
    for(const face of [[0,3,2,1],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7],[4,5,6,7]])obj+='f '+face.map(v=>v+index).join(' ')+'\n';index+=8;
  };
  box('floor',0,0,-.08,4.8,3.6,.08,'wood');box('back_wall',0,3.6,0,4.8,.12,2.7,'wall');box('side_wall',-.12,0,0,.12,3.6,2.7,'wall');
  box('sofa_base',.28,1.3,.15,.85,1.8,.4,'fabric');box('sofa_back',.2,1.25,.5,.16,1.9,.4,'fabric');box('sofa_arm_a',.25,1.2,.5,.9,.13,.2,'fabric');box('sofa_arm_b',.25,3.1,.5,.9,.13,.2,'fabric');
  box('table_top',1.6,1.7,.48,1.05,.65,.06,'table');for(const [x,y]of[[1.66,1.76],[2.5,1.76],[1.66,2.24],[2.5,2.24]])box('leg',x,y,0,.06,.06,.48,'table');
  box('cabinet',3.5,3.15,0,1,.4,.85,'table');box('door',.015,.25,0,.015,.85,2.1,'door');
  const mtl='newmtl wood\nKd 0.68 0.53 0.39\nnewmtl wall\nKd 0.91 0.89 0.85\nnewmtl fabric\nKd 0.32 0.42 0.39\nnewmtl table\nKd 0.37 0.27 0.19\nnewmtl door\nKd 0.53 0.39 0.27\n';
  return {assets:{'room.obj':strToU8(obj),'room.mtl':strToU8(mtl)},model:'room.obj',name:'Demo 4.80 × 3.60 m',demo:true};
}
