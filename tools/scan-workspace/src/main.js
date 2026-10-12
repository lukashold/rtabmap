import { Viewer, parseModel, demoBundle } from './viewer.js';
import { guide, dictionaries, resolveLanguage } from './i18n.js';
import { resultFor, calibration, validateProject, floorplanSVG } from './measure.js';
import { readFiles, packageBuilding, csvReport, download } from './files.js';
import { CloudDrive, prepareAuth, signIn, disconnect, resetAuth } from './cloud.js';
import { ServerDrive } from './server-drive.js';
import { experienceDictionaries } from './experience-i18n.js';
import { preparePhoto, photoData, referenceCheck } from './experience.js';
import { floorplanDXF, measurementReport } from './report.js';
import { assessTransport } from './transport.js';
import { applianceCatalog } from './appliance-catalog.js';
import { designDictionaries } from './design-i18n.js';
import videos from '../public/videos/scripts.json' with { type: 'json' };
import { supportedLanguages, directionFor } from '../locales/index.js';
import { uxDictionaries } from './ux-i18n.js';
import { createTaskRunner } from './ui-tasks.js';
import { decodeSplat, detectSplatFile, splatPlyHeader, syntheticSplatDemo, MAX_SPLAT_BYTES } from './splat-data.js';
import { ReconstructionPanel } from './reconstruction-ui.js';
import { qualityDictionaries } from './quality-i18n.js';
import { panoramaText } from './panorama-i18n.js';

const $=id=>document.getElementById(id);
$('language').replaceChildren();for(const code of supportedLanguages){const option=document.createElement('option');option.value=code;option.textContent=guide[code].name;$('language').append(option);}
const storage={get(key){try{return localStorage.getItem(key);}catch{return null;}},set(key,value){try{localStorage.setItem(key,value);}catch{}}};
let language=resolveLanguage(storage.get('rtab-language')||navigator.language),bundle,measurements=[],notes=[],checks=[],pending=[],scale=1,upAxis='z',mode='orbit',dirty=false,calibrated=false,busy=false,guideStep=0,guideRoute='lidar',entryChoice,focusLoadedWorkspace=false;
let building={name:'',rooms:[],activeRoom:null},addingRoom=false,selectedMeasurement=null,editingNote,notePoint,removePhoto=false,photoPreviewURL,transportResult,transportRecord;
const photoURLs=new Map();
let snapFeedback,splatViewer,splatData,splatAttempt=0,splatLoading=false,photoPanel;
let provider='microsoft',config={},authReady=false,drive,cloudBusy=false,toastTimer,authAttempt=0;
const t=key=>key==='panoramaTitle'?panoramaText(language).title:qualityDictionaries[language]?.[key]||uxDictionaries[language]?.[key]||designDictionaries[language]?.[key]||experienceDictionaries[language]?.[key]||dictionaries[language][key]||key;
const format=value=>new Intl.NumberFormat(language,{maximumFractionDigits:3}).format(value);
const icons={folder:'M3 7h7l2 2h9v11H3z M3 7V4h7l2 3',ruler:'M3 16L16 3l5 5L8 21z M8 11l3 3 M12 7l3 3 M5 14l3 3',floor:'M3 4h18v16H3z M3 9h6V4 M15 20v-5h6',surface:'M3 8l13-5 5 13-13 5z',target:'M12 3v4 M12 17v4 M3 12h4 M17 12h4 M17 12a5 5 0 1 1-10 0 5 5 0 0 1 10 0',cloud:'M6 18a5 5 0 0 1-1-10 7 7 0 0 1 13-1 5 5 0 0 1 0 11 M12 20V10 M8 14l4-4 4 4',cube:'M12 2l9 5v10l-9 5-9-5V7z M3 7l9 5 9-5 M12 12v10',image:'M3 3h18v18H3z M3 17l6-6 4 4 3-3 5 5 M15 7h1',layers:'M3 7l9-5 9 5-9 5z M3 12l9 5 9-5 M3 17l9 5 9-5',fit:'M8 3H3v5 M16 3h5v5 M3 16v5h5 M21 16v5h-5',book:'M12 5Q6 1 2 4v16q5-3 10 0 5-3 10 0V4q-5-3-10 1v15',save:'M4 3h13l4 4v14H3V3z M7 3v6h10V3 M7 21v-8h10v8',download:'M12 3v12 M7 10l5 5 5-5 M4 16v5h16v-5'};
function icon(name){return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${icons[name]||icons.cube}"/></svg>`;}
document.querySelectorAll('[data-icon]').forEach(el=>el.innerHTML=icon(el.dataset.icon));
let viewer;
try{viewer=new Viewer($('stage'),pick);}catch(e){showError(e);}
function toast(text,error=false,persistent=false){clearTimeout(toastTimer);$('status').textContent=text;$('status').classList.toggle('error',error);$('status').classList.add('visible');if(!persistent)toastTimer=setTimeout(()=>$('status').classList.remove('visible'),6500);}
function showError(error){const detail=error?.code&&t(error.code)!==error.code?t(error.code):'',text=`${t('error')}${detail?`: ${detail}`:''}${error?.status?` (${error.status})`:''}`,feedback=document.querySelector('dialog[open] .dialog-feedback');if(feedback){feedback.textContent=text;feedback.hidden=false;feedback.scrollIntoView({block:'nearest'});}else toast(text,true);}
const tasks=createTaskRunner(active=>{busy=active;refresh();if(active){const feedback=document.querySelector('dialog[open] .dialog-feedback');if(feedback)feedback.hidden=true;toast(t('working'),false,true);}else{if($('status').textContent===t('working'))$('status').classList.remove('visible');if(focusLoadedWorkspace){focusLoadedWorkspace=false;window.scrollTo(0,0);viewer?.renderer.domElement.focus({preventScroll:true});}}});
async function runTask(action){try{return await tasks.run(action);}catch(error){showError(error);return false;}}
function project(){return structuredClone({version:1,source:bundle?.source==='photogrammetry'?'photogrammetry':undefined,name:$('project-name').value.trim()||'Scan',scale,upAxis,calibrated,demo:!!bundle?.demo,measurements,notes,checks,transport:transportRecord});}
function stashRoom(){const room=building.rooms.find(r=>r.id===building.activeRoom);if(room&&bundle){room.project=project();room.bundle=bundle;room.floor=$('floor-name').value.trim()||'0';}building.name=$('building-name').value.trim()||project().name;}
function workspaceSnapshot(){stashRoom();return {name:building.name,activeRoom:building.activeRoom,rooms:building.rooms.map(r=>({...r,project:structuredClone(r.project)}))};}
function stateSignature(){stashRoom();return JSON.stringify({name:building.name,activeRoom:building.activeRoom,rooms:building.rooms.map(r=>({id:r.id,floor:r.floor,project:r.project}))});}
function refreshRooms(){const select=$('room-select');select.replaceChildren();building.rooms.forEach(r=>{const option=document.createElement('option');option.value=r.id;option.textContent=`${r.floor} · ${r.id===building.activeRoom?project().name:r.project.name}`;select.append(option);});select.value=building.activeRoom||'';select.disabled=busy||!bundle;$('add-room').disabled=busy;}
function refresh(){
  const home=!bundle||document.body.classList.contains('show-home');$('home-screen').hidden=!home;document.querySelector('.workspace').hidden=home;document.querySelector('.workflow').hidden=home;$('return-workspace').hidden=!bundle;
  document.querySelector('.workspace').inert=busy;document.querySelector('.workspace').setAttribute('aria-busy',String(busy));$('home-screen').setAttribute('aria-busy',String(busy));
  for(const id of ['open','open-hero','home-open','home-demo','demo','entry-open','entry-demo'])$(id).disabled=busy||!viewer;
  for(const id of ['home-nav','return-workspace'])$(id).disabled=busy;
  document.querySelectorAll('[data-entry]').forEach(button=>button.disabled=busy);
  $('viewer-error').hidden=!!viewer;
  $('save').disabled=!bundle||busy;$('csv').disabled=!measurements.length;$('svg').disabled=!measurements.some(m=>m.kind==='floor');
  $('dxf').disabled=$('svg').disabled;$('report').disabled=!bundle||busy;$('verify').disabled=!measurements.some(m=>m.kind==='distance')||busy;
  $('empty-overlay').hidden=!!bundle;$('model-name').hidden=!bundle;$('model-name').textContent=bundle?.model||'';$('demo-badge').hidden=!bundle?.demo;
  $('results-empty').hidden=!!measurements.length;$('measure-count').textContent=measurements.length;
  $('instruction').textContent=t(mode==='note'?'notePick':mode==='reference'?'pickReference':mode==='distance'?'pickTwo':['floor','surface'].includes(mode)?'pickArea':mobileLayout.matches?'mobileNavigateHint':'navigateHint');
  $('point-count').textContent=pending.length?`${pending.length} ●`:'';
  $('selection-actions').hidden=mode==='orbit';$('finish').hidden=!['floor','surface'].includes(mode);$('finish').disabled=pending.length<3;$('undo').disabled=!pending.length;
  $('scale-status').textContent=bundle?.source==='photogrammetry'&&!calibrated?t('photoScaleWarning'):`${t(calibrated?'calibrated':'unverified')} · 1 = ${format(scale)} m`;
  $('scale-status').classList.toggle('verified',calibrated);
  for(const [id,pressed]of [['orbit',!viewer?.top],['top',!!viewer?.top],['texture',!!viewer?.textured],['roof',!!viewer?.roof]]){$(id).classList.toggle('active',pressed);$(id).setAttribute('aria-pressed',String(pressed));$(id).disabled=!bundle||busy;}
  document.querySelectorAll('[data-mode]').forEach(el=>{el.classList.toggle('active',el.dataset.mode===mode);el.setAttribute('aria-pressed',String(el.dataset.mode===mode));el.disabled=!bundle||busy||(bundle.source==='photogrammetry'&&!calibrated);});
  $('calibrate').disabled=!bundle||busy;refreshSnapping();
  $('axis').disabled=!bundle||busy;$('units').disabled=!bundle||busy;
  const list=$('measure-list');list.replaceChildren();
  measurements.forEach((m,index)=>{
    const r=resultFor(m,scale),li=document.createElement('li');li.className='measure-item';
    const heading=document.createElement('div');heading.className='measure-name';
    const name=document.createElement('button');name.className='measure-rename';name.textContent=m.label;name.title=t('namePrompt');
    name.onclick=()=>{const value=prompt(t('namePrompt'),m.label);if(value?.trim()){m.label=value.trim().slice(0,200);dirty=true;refresh();}};
    const remove=document.createElement('button');remove.className='icon-button';remove.textContent='×';remove.setAttribute('aria-label',`${t('remove')}: ${m.label}`);remove.onclick=()=>{if(!confirm(`${t('remove')}: ${m.label}?`))return;measurements.splice(index,1);dirty=true;refresh();};heading.append(name,remove);
    const locate=document.createElement('button');locate.className='locate-button';locate.textContent='⌖';locate.setAttribute('aria-label',`${t('model')}: ${m.label}`);locate.onclick=()=>{selectedMeasurement=m.id;viewer.focusPoints(m.points);refresh();};heading.insertBefore(locate,remove);
    const value=document.createElement('div');value.className='measure-value';value.textContent=`${format(r.area??r.length)} ${m.kind==='distance'?'m':'m²'}`;
    const detail=document.createElement('p');detail.className='measure-detail';detail.textContent=m.kind==='distance'?`${t('horizontal')} ${format(r.horizontal)} m · ${t('vertical')} ${format(r.vertical)} m`:`${t('perimeter')} ${format(r.perimeter)} m`;
    li.append(heading,value,detail);list.append(li);
  });
  viewer?.drawMeasurements(measurements.filter(m=>m.source!=='roomplan'||m.id===selectedMeasurement),pending,scale,format,notes.filter(n=>!n.id.startsWith('roomplan-')||n.id===editingNote),openNote);renderNotes();renderChecks();refreshRooms();refreshRouteSources();refreshCloudButtons();
}
function translate(){
  document.documentElement.lang=language;document.documentElement.dir=directionFor(language);$('language').value=language;
  document.querySelector('.snap-explanation summary').setAttribute('aria-label',t('snapInfo'));
  $('language').setAttribute('aria-label',t('languageLabel'));document.querySelector('.language-pills').setAttribute('aria-label',t('languageLabel'));
  document.querySelector('.brand').setAttribute('aria-label',`Kantura · ${t('home')}`);
  document.querySelectorAll('[data-i18n]').forEach(el=>el.textContent=t(el.dataset.i18n));
  document.querySelectorAll('button').forEach(el=>{const label=el.querySelector('[data-i18n]');if(label)el.setAttribute('aria-label',t(label.dataset.i18n));});
  document.querySelectorAll('[data-close]').forEach(el=>el.setAttribute('aria-label',t('close')));
  $('guide-room-title').textContent=guide[language].roomPlan.modeTitle;$('guide-room-detail').textContent=guide[language].roomPlan.modeDetail;$('guide-lidar-detail').textContent=guide[language].workflow.stages[0].detail;
  $('step-scan').textContent=guide[language].start;$('step-review').textContent=guide[language].assemble;
  $('texture').title=t('texture');$('stage').setAttribute('aria-label',t('model'));viewer?.renderer.domElement.setAttribute('aria-label',t('model'));document.querySelector('.workflow').setAttribute('aria-label',t('workspace'));
  document.querySelectorAll('.tool-group,.mobile-measurement-dock').forEach(group=>group.setAttribute('aria-label',t('measurements')));
  document.querySelectorAll('[data-route-source]').forEach(select=>{const field=$(select.dataset.routeSource);select.setAttribute('aria-label',`${t('measurementSource')} · ${field.closest('label').querySelector('[data-i18n]').textContent}`);});
  for(const id of ['transport-scenario','transport-step','transport-canvas'])$(id).setAttribute('aria-label',t('simulate'));
  $('splat-navigation').textContent=t(mobileLayout.matches?'mobileNavigateHint':'navigateHint');if(splatViewer)splatViewer.renderer.domElement.setAttribute('aria-label',t('splatTitle'));photoPanel?.refresh();
  $('splat-focus').title=t('splatFocusHelp').replace('{all}',t('fit'));$('splat-focus-help').textContent=$('splat-focus').title;
  refresh();renderGuide();
}
function setMode(next){if(busy)return;if(!bundle)return toast(t('noModel'));if(bundle.source==='photogrammetry'&&!calibrated&&!['reference','orbit'].includes(next))return toast(t('photoScaleWarning'));mode=next;pending=[];viewer.setMode(next);refresh();if(mobileLayout.matches)document.querySelector('.model-panel').scrollIntoView({block:'nearest'});}
function pick(point){
  if(busy||mode==='orbit')return;
  if(mode==='note'){notePoint=point;openNote();return;}
  if(pending.length>=1000)return showError({code:'tooLarge'});
  pending.push(point);
  if(pending.length===2&&mode==='reference'){$('reference-length').value='';$('reference-dialog').showModal();$('reference-length').focus();}
  else if(pending.length===2&&mode==='distance')finish();
  refresh();
}
function finish(){try{
  if(measurements.length>=500)throw {code:'tooLarge'};
  const measurement={id:crypto.randomUUID(),kind:mode,label:`${t(mode)} ${measurements.length+1}`,points:pending.map(p=>[...p])};
  const result=resultFor(measurement,scale);if(result.length===0)throw {code:'degenerate'};
  measurements.push(measurement);pending=[];dirty=true;refresh();
}catch(e){showError(e);}}
function allowReplace(){return !dirty||confirm(t('replace'));}
async function load(next,{keepBuilding=false,roomId}={}){
  if(!viewer)throw {code:'unsupported'};
    const model=await parseModel(next),p=next.project;
    bundle={...next};delete bundle.building;document.body.classList.remove('show-home');document.querySelector('.workspace').hidden=false;document.querySelector('.workflow').hidden=false;$('home-screen').hidden=true;bundle.source=p?.source==='photogrammetry'||next.source==='photogrammetry'?'photogrammetry':undefined;bundle.demo=!!(next.demo||p?.demo);scale=p?.scale||1;upAxis=p?.upAxis||(/\.glb$/i.test(next.model)?'y':'z');
    measurements=p?.measurements||[];measurements.forEach(m=>m.id??=crypto.randomUUID());notes=p?.notes||[];checks=p?.checks||[];calibrated=!!p?.calibrated;pending=[];mode='orbit';selectedMeasurement=null;editingNote=undefined;
    transportRecord=p?.transport;$('transport-form').reset();$('model-search').value='';$('catalog-source').replaceChildren();$('catalog-results').replaceChildren();invalidateTransport();
    photoURLs.forEach(URL.revokeObjectURL);photoURLs.clear();
    $('project-name').value=p?.name||next.name;$('axis').value=upAxis;$('units').value=[1,.01,.001].includes(scale)?String(scale):'1';
    viewer.setModel(model,upAxis);viewer.setMode(mode);toast(t('ready'));
    if(next.building){building=next.building;building.activeRoom=next.building.activeRoom;}
    else if(!keepBuilding){const id=crypto.randomUUID();building={name:next.location?.name||p?.name||next.name,activeRoom:id,rooms:[{id,floor:next.location?.floor||'0',bundle:next,project:project()}]};}
    else if(roomId)building.activeRoom=roomId;
    else{const id=crypto.randomUUID();building.rooms.push({id,floor:next.location?.floor||$('floor-name').value||'0',bundle:next,project:project()});building.activeRoom=id;}
    $('building-name').value=building.name;$('floor-name').value=building.rooms.find(r=>r.id===building.activeRoom)?.floor||'0';
    $('building-settings').open=entryChoice==='house'||building.rooms.length>1;
    if(!keepBuilding)dirty=false;
    focusLoadedWorkspace=true;
}
async function openFiles(input){const files=Array.from(input);if(!files.length||busy)return;const append=addingRoom;addingRoom=false;await runTask(async()=>{
  if(files.length===1&&await detectSplatFile(files[0])){await openSplatFile(files[0]);return;}
  const next=await readFiles(files,{roomLabels:{wall:t('wall'),door:t('door'),window:t('window'),opening:t('opening'),floor:t('kindFloor'),width:t('width'),height:t('height')}});
  if(/\.ply$/i.test(next.model)&&splatPlyHeader(next.assets[next.model])){if(next.project||next.building)throw {code:'splatSeparate'};await openSplatBytes(next.assets[next.model],next.model);return;}
  if(!append&&!allowReplace())return;if(append)stashRoom();if(append&&next.building)throw {code:'invalidProject'};await load(next,{keepBuilding:append&&!!building.rooms.length});dirty=append;
});entryChoice=undefined;}

['open','open-hero','home-open'].forEach(id=>$(id).onclick=()=>{addingRoom=false;entryChoice=undefined;$('file').click();});
$('home-demo').onclick=()=>{entryChoice=undefined;$('demo').click();};
document.querySelectorAll('[data-entry]').forEach(button=>button.onclick=()=>{entryChoice=button.dataset.entry;$('entry-title').textContent=t({room:'roomCard',house:'houseCard',object:'objectCard'}[entryChoice]);$('entry-description').textContent=entryChoice==='house'?`${t('houseBody')} ${t('buildingHelp')} ${t('roomplanHelp')}`:entryChoice==='room'?t('roomplanHelp'):`${t('objectBody')} ${t('openHint')} ${t('fileHint')}`;$('entry-dialog').returnValue='';$('entry-dialog').showModal();});
$('entry-open').onclick=()=>{addingRoom=false;$('entry-dialog').close('open');$('file').click();};
$('entry-dialog').addEventListener('close',()=>{if($('entry-dialog').returnValue!=='open')entryChoice=undefined;});
$('entry-demo').onclick=()=>{$('entry-dialog').close();entryChoice=undefined;$('demo').click();};
function showOverview(){if(busy)return;document.body.classList.add('show-home');refresh();$('home-screen').scrollIntoView({block:'start'});$('home-open').focus({preventScroll:true});}
$('home-nav').onclick=showOverview;
document.querySelector('.brand').onclick=event=>{event.preventDefault();showOverview();};
$('return-workspace').onclick=()=>{document.body.classList.remove('show-home');refresh();viewer?.resize();viewer?.renderer.domElement.focus();};
$('file').addEventListener('cancel',()=>{addingRoom=false;entryChoice=undefined;});
$('file').onchange=async()=>{await openFiles($('file').files);$('file').value='';};
$('demo').onclick=async()=>{if(busy||!allowReplace())return;entryChoice=undefined;await runTask(async()=>{await load(demoBundle());dirty=false;});};
$('add-room').onclick=()=>{addingRoom=true;$('file').click();};
$('room-select').onchange=async()=>{if(busy)return;stashRoom();const room=building.rooms.find(r=>r.id===$('room-select').value);if(!room)return;await runTask(()=>load({...room.bundle,project:room.project},{keepBuilding:true,roomId:room.id}));};
$('building-name').oninput=()=>{if(bundle){building.name=$('building-name').value;dirty=true;}};
$('floor-name').oninput=()=>{if(bundle){stashRoom();dirty=true;refreshRooms();}};
window.addEventListener('dragover',e=>e.preventDefault());window.addEventListener('drop',e=>{e.preventDefault();if(document.querySelector('dialog[open]'))return;addingRoom=false;entryChoice=undefined;openFiles(e.dataTransfer.files);});
const mobileLayout=window.matchMedia('(max-width:560px)');
function placeSelectionActions(){const actions=$('selection-actions'),snapping=$('snap-controls');if(mobileLayout.matches)document.querySelector('.mobile-measurement-dock').append(snapping,actions);else{document.querySelector('.tools-panel .tool-group').insertAdjacentElement('afterend',snapping);snapping.insertAdjacentElement('afterend',actions);}}
mobileLayout.addEventListener('change',()=>{placeSelectionActions();refresh();});placeSelectionActions();
document.querySelectorAll('[data-mode]').forEach(el=>el.onclick=()=>setMode(el.dataset.mode));
function refreshSnapping(){
  $('snap-toggle').checked=!!viewer?.snapEnabled;$('snap-toggle').disabled=!bundle||busy;$('snap-status').hidden=!viewer?.snapEnabled;
  const state=viewer?.snapIndex?.status;
  let text=t(state==='limit'?'snapLimit':state==='unsupported'?'snapUnavailable':'snapReady');
  if(snapFeedback?.kind==='free')text=t('snapFree');
  else if(snapFeedback?.kind)text=`${snapFeedback.picked?t('snapApplied')+': ':''}${t(snapFeedback.kind==='vertex'?'snapVertex':'snapEdge')}`;
  if($('snap-status').textContent!==text)$('snap-status').textContent=text;
}
if(viewer)viewer.onSnapChange=feedback=>{snapFeedback=feedback;refreshSnapping();};
$('snap-toggle').onchange=()=>{viewer?.setSnapping($('snap-toggle').checked);refreshSnapping();};
$('finish').onclick=finish;$('undo').onclick=()=>{pending.pop();refresh();};$('cancel').onclick=()=>setMode('orbit');
$('calibrate').onclick=()=>setMode('reference');
$('reference-form').onsubmit=e=>{e.preventDefault();try{
  const next=calibration(...pending,Number($('reference-length').value));validateProject({...project(),scale:next});scale=next;calibrated=true;dirty=true;$('reference-dialog').close();setMode('orbit');
}catch(error){showError(error);}};
$('reference-dialog').addEventListener('close',()=>{if(mode==='reference'){pending=[];refresh();}});
$('project-name').oninput=()=>{if(bundle){dirty=true;refreshRooms();}};
$('units').onchange=()=>{const previous=scale;try{const next=Number($('units').value);validateProject({...project(),scale:next});scale=next;calibrated=false;dirty=true;refresh();}catch(e){$('units').value=String(previous);showError(e);}};
$('axis').onchange=async()=>{if(!bundle||busy)return;if((measurements.length||notes.length||checks.length)&&!confirm(t('replace'))){$('axis').value=upAxis;return;}await runTask(async()=>{try{const root=await parseModel(bundle);upAxis=$('axis').value;measurements=[];pending=[];notes.forEach(n=>{if(n.photo)delete bundle.assets[n.photo];});notes=[];checks=[];calibrated=false;photoURLs.forEach(URL.revokeObjectURL);photoURLs.clear();viewer.setModel(root,upAxis);dirty=true;}catch(error){$('axis').value=upAxis;throw error;}});};
$('orbit').onclick=()=>{viewer?.setTop(false);if(bundle)setMode('orbit');$('orbit').classList.add('active');$('top').classList.remove('active');};
$('top').onclick=()=>{viewer?.setTop(true);refresh();};
$('fit').onclick=()=>viewer?.fit();
$('texture').onclick=()=>{viewer?.setTexture(!viewer.textured);refresh();};
$('roof').onclick=()=>{viewer?.setRoof(!viewer.roof);refresh();};
$('save').onclick=async()=>{if(!bundle||busy)return;await runTask(async()=>{const snapshot=workspaceSnapshot(),signature=stateSignature();download(await packageBuilding(snapshot),`${snapshot.name}.kantura-building.zip`);if(signature===stateSignature())dirty=false;toast(`${t('archiveDownloadStarted')}: ${snapshot.name}.kantura-building.zip`);});};
$('csv').onclick=()=>download(new Blob([csvReport(measurements,scale,resultFor)],{type:'text/csv;charset=utf-8'}),`${project().name}.csv`);
$('svg').onclick=()=>{try{download(new Blob([floorplanSVG(measurements,scale,project().name)],{type:'image/svg+xml'}),`${project().name}.svg`);}catch(e){showError(e);}};
$('dxf').onclick=()=>{try{download(new Blob([floorplanDXF(measurements,scale,project().name)],{type:'application/dxf'}),`${project().name}.dxf`);}catch(e){showError(e);}};
$('report').onclick=()=>{try{const html=measurementReport(project(),{language,photoData:photoData(bundle.assets,notes)});download(new Blob([html],{type:'text/html;charset=utf-8'}),`${project().name}-report.html`);}catch(e){showError(e);}};
window.addEventListener('beforeunload',e=>{if(dirty){e.preventDefault();e.returnValue='';}});
window.addEventListener('keydown',e=>{if(busy||!bundle||$('home-screen').hidden===false||document.querySelector('dialog[open]')||e.ctrlKey||e.altKey||e.metaKey||e.target.isContentEditable||/^(INPUT|SELECT|TEXTAREA)$/.test(e.target.tagName))return;const choice={'1':'distance','2':'floor','3':'surface','4':'note','Escape':'orbit'}[e.key];if(choice){e.preventDefault();setMode(choice);}if(e.key==='Backspace'&&pending.length){e.preventDefault();pending.pop();refresh();}});
$('language').onchange=()=>{language=$('language').value;storage.set('rtab-language',language);translate();};
function guideSteps(){const g=guide[language];if(guideRoute==='lidar')return g.steps;return [
  {title:g.roomPlan.prepare,body:`${g.roomPlan.intro} ${g.roomPlan.noTexture}`},
  {title:g.roomPlan.start,body:g.roomPlan.scanHelp},
  {title:g.roomPlan.review,body:`${g.roomPlan.verify} ${g.roomPlan.separateOrigins}`},
  {title:t('workspace'),body:`${t('roomplanHelp')} ${t('pickTwo')} ${t('verificationHelp')}`},
  g.steps[4],g.steps[5],
  {title:g.roomPlan.export,body:`${g.roomPlan.savedLocally} ${t('roomplanHelp')} ${t('reportDownloadHelp')}`}
];}
function renderGuide(){const g=guide[language],steps=guideSteps(),step=steps[guideStep];$('guide-subtitle').textContent=guideRoute==='room'?g.roomPlan.modeTitle:t('lidarRoute');$('guide-title').textContent=step.title;$('guide-body').textContent=step.body;$('guide-illustration').innerHTML=icon(['target','cube','image','ruler','floor','target','cloud'][guideStep]);$('guide-counter').textContent=`${guideStep+1} / ${steps.length}`;$('guide-back').disabled=guideStep===0;$('guide-next').textContent=guideStep===steps.length-1?t('done'):t('next');$('guide-progress').replaceChildren(...steps.map((_,i)=>{const dot=document.createElement('span');dot.classList.toggle('active',i<=guideStep);return dot;}));}
function openGuide(step=0){guideStep=step;renderGuide();$('guide-dialog').showModal();}
function chooseGuide(step=0){guideStep=step;$('capture-choice').showModal();}
$('tutorial').onclick=()=>chooseGuide();document.querySelectorAll('[data-guide-step]').forEach(el=>el.onclick=()=>chooseGuide(Number(el.dataset.guideStep)));
for(const route of ['room','lidar'])$('guide-'+route).onclick=()=>{guideRoute=route;$('capture-choice').close();openGuide(guideStep);};
$('guide-back').onclick=()=>{guideStep--;renderGuide();};$('guide-next').onclick=()=>{if(guideStep===guideSteps().length-1)$('guide-dialog').close();else{guideStep++;renderGuide();}};
document.querySelectorAll('[data-close]').forEach(el=>el.onclick=()=>$(el.dataset.close).close());
for(const dialog of document.querySelectorAll('dialog')){const heading=dialog.querySelector('h2');heading.id||=dialog.id+'-title';dialog.setAttribute('aria-labelledby',heading.id);const feedback=document.createElement('p');feedback.className='dialog-feedback';feedback.setAttribute('role','alert');feedback.hidden=true;dialog.append(feedback);dialog.addEventListener('close',()=>{feedback.hidden=true;feedback.textContent='';});}
function openVideo(){
  const script=videos.languages[language]||videos.languages.en,video=$('explainer-video');video.pause();
  $('video-title').textContent=script.title;$('video-description').textContent=script.description;$('video-error').hidden=true;
  video.replaceChildren();const source=document.createElement('source');source.src=`./videos/kantura-${language}.mp4`;source.type='video/mp4';source.onerror=()=>$('video-error').hidden=false;video.append(source);
  const track=document.createElement('track');track.kind='captions';track.src=`./videos/kantura-${language}.vtt`;track.srclang=language;track.label=$('language').selectedOptions[0].textContent;track.default=true;video.append(track);
  video.load();$('video-download').href=source.src;$('caption-download').href=track.src;$('video-transcript').replaceChildren();
  script.scenes.forEach(scene=>{const li=document.createElement('li'),title=document.createElement('strong'),body=document.createElement('p');title.textContent=scene.title;body.textContent=scene.narration;li.append(title,body);$('video-transcript').append(li);});
  $('video-dialog').showModal();
}
['learn-nav','home-video','hero-video'].forEach(id=>$(id).onclick=openVideo);
$('explainer-video').addEventListener('error',()=>$('video-error').hidden=false);
$('video-dialog').addEventListener('close',()=>$('explainer-video').pause());

function noteURL(note){if(!note.photo||!bundle?.assets[note.photo])return undefined;if(!photoURLs.has(note.photo))photoURLs.set(note.photo,URL.createObjectURL(new Blob([bundle.assets[note.photo]],{type:note.photo.endsWith('.png')?'image/png':note.photo.endsWith('.webp')?'image/webp':'image/jpeg'})));return photoURLs.get(note.photo);}
function openNote(note){if(!bundle||busy)return;editingNote=note?.id;notePoint=note?.point||notePoint;removePhoto=false;$('note-title').value=note?.title||'';$('note-kind').value=note?.kind||'other';$('note-description').value=note?.description||'';$('note-photo').value='';const url=note&&noteURL(note);$('note-preview').hidden=!url;if(url)$('note-preview').src=url;$('note-dialog').showModal();$('note-title').focus();}
function renderNotes(){
  $('note-count').textContent=notes.length;$('notes-empty').hidden=!!notes.length;$('note-list').replaceChildren();
  notes.forEach(note=>{const li=document.createElement('li'),button=document.createElement('button'),remove=document.createElement('button');button.textContent=`${t('kind'+note.kind[0].toUpperCase()+note.kind.slice(1))} · ${note.title}${note.photo?' · 📷':''}`;button.onclick=()=>{viewer.focusPoints([note.point]);openNote(note);};remove.textContent='×';remove.className='icon-button';remove.setAttribute('aria-label',`${t('noteRemove')}: ${note.title}`);remove.onclick=()=>{if(!confirm(`${t('noteRemove')}: ${note.title}?`))return;notes=notes.filter(n=>n.id!==note.id);if(note.photo&&!notes.some(n=>n.photo===note.photo)){delete bundle.assets[note.photo];URL.revokeObjectURL(photoURLs.get(note.photo));photoURLs.delete(note.photo);}dirty=true;refresh();};li.append(button,remove);$('note-list').append(li);});
}
$('note-photo').onchange=()=>{if(photoPreviewURL)URL.revokeObjectURL(photoPreviewURL);const file=$('note-photo').files[0];if(file){photoPreviewURL=URL.createObjectURL(file);$('note-preview').src=photoPreviewURL;$('note-preview').hidden=false;removePhoto=false;}};
$('note-photo-remove').onclick=()=>{removePhoto=true;$('note-photo').value='';$('note-preview').hidden=true;};
$('note-dialog').addEventListener('close',()=>{if(photoPreviewURL)URL.revokeObjectURL(photoPreviewURL);photoPreviewURL=undefined;if(mode==='note')setMode('orbit');});
$('note-form').onsubmit=async event=>{event.preventDefault();if(busy||!notePoint)return;$('note-submit').disabled=true;await runTask(async()=>{
  const old=notes.find(n=>n.id===editingNote),id=old?.id||crypto.randomUUID();if(!old&&notes.length>=200)throw {code:'tooLarge'};
  const note={id,title:$('note-title').value.trim(),description:$('note-description').value.trim(),kind:$('note-kind').value,point:[...notePoint]},file=$('note-photo').files[0];
  if(old?.photo&&!removePhoto)note.photo=old.photo;
  let bytes;if(file){bytes=await preparePhoto(file);note.photo=`kantura-notes/${crypto.randomUUID()}.jpg`;}
  const next=old?notes.map(n=>n.id===old.id?note:n):[...notes,note];validateProject({...project(),notes:next});
  if(old?.photo&&old.photo!==note.photo&&!next.some(n=>n.photo===old.photo)){delete bundle.assets[old.photo];URL.revokeObjectURL(photoURLs.get(old.photo));photoURLs.delete(old.photo);}if(bytes)bundle.assets[note.photo]=bytes;
  notes=next;dirty=true;$('note-dialog').close();
});$('note-submit').disabled=false;if(!$('note-dialog').open){mode='orbit';pending=[];viewer.setMode(mode);refresh();}};
function renderChecks(){
  $('checks-empty').hidden=!!checks.length;$('check-list').replaceChildren();
  checks.forEach(check=>{const result=referenceCheck(check,scale),li=document.createElement('li'),text=document.createElement('p'),remove=document.createElement('button');text.textContent=`${check.label}: ${format(result.measured)} / ${format(result.known)} m · ${t('verificationDeviation')} ${format(result.difference)} m (${format(result.percent)} %)`;remove.className='icon-button';remove.textContent='×';remove.setAttribute('aria-label',`${t('verificationRemove')}: ${check.label}`);remove.onclick=()=>{if(!confirm(`${t('verificationRemove')}: ${check.label}?`))return;checks=checks.filter(c=>c.id!==check.id);dirty=true;refresh();};li.append(text,remove);$('check-list').append(li);});
}
$('verify').onclick=()=>{$('check-measurement').replaceChildren();measurements.filter(m=>m.kind==='distance').forEach(m=>{const option=document.createElement('option');option.value=m.id;option.textContent=`${m.label} · ${format(resultFor(m,scale).length)} m`;$('check-measurement').append(option);});$('check-known').value='';$('check-dialog').showModal();};
$('check-form').onsubmit=event=>{event.preventDefault();try{const m=measurements.find(m=>m.id===$('check-measurement').value);if(!m||checks.length>=100)throw {code:'verificationInvalid'};const check={id:crypto.randomUUID(),label:m.label,points:structuredClone(m.points),knownMeters:Number($('check-known').value),createdAt:new Date().toISOString()};validateProject({...project(),checks:[...checks,check]});checks.push(check);dirty=true;$('check-dialog').close();refresh();}catch(error){showError(error);}};

function catalogSearch(){
  const query=$('model-search').value.toLowerCase().replace(/\s/g,'');$('catalog-results').replaceChildren();if(query.length<2)return;
  const matches=applianceCatalog.filter(item=>(item.brand+' '+item.model).toLowerCase().replace(/\s/g,'').includes(query)).slice(0,8);if(!matches.length){const li=document.createElement('li');li.textContent=t('catalogEmpty');$('catalog-results').append(li);}
  matches.forEach(item=>{const li=document.createElement('li'),button=document.createElement('button');button.textContent=`${item.brand} ${item.model} · ${item.width} × ${item.depth} × ${item.height} m`;button.onclick=()=>{invalidateTransport();for(const key of ['width','depth','height'])$('object-'+key).value=item[key];$('catalog-source').replaceChildren();const link=document.createElement('a');link.href=item.sourceUrl;link.target='_blank';link.rel='noopener noreferrer';link.textContent=`${t('catalogSource')}: ${item.brand} · ${item.verifiedAt}`;$('catalog-source').append(link,document.createElement('br'),document.createTextNode(item.note||''));$('catalog-results').replaceChildren();$('model-search').value=`${item.brand} ${item.model}`;};li.append(button);$('catalog-results').append(li);});
}
$('transport').onclick=()=>{if(busy)return;$('transport-sample').hidden=!!transportRecord;if(transportRecord){const input=transportRecord.input;for(const key of ['width','depth','height'])$('object-'+key).value=input.object[key];const mapping={width:'route-width',ceiling:'route-ceiling',landingWidth:'landing-width',landingDepth:'landing-depth',rise:'stair-rise',run:'stair-run',turnDegrees:'turn-angle'};for(const [key,id]of Object.entries(mapping))$(id).value=input.route[key];$('transport-margin').value=input.margin;$('allow-tilt').checked=input.allowTilt;$('model-search').value=transportRecord.model;}$('transport-dialog').showModal();};$('model-search').oninput=()=>{$('catalog-source').replaceChildren();invalidateTransport();catalogSearch();};
function refreshRouteSources(){for(const select of document.querySelectorAll('[data-route-source]')){select.replaceChildren();const manual=document.createElement('option');manual.value='';manual.textContent=t('manualDimensions');select.append(manual);measurements.filter(m=>m.kind==='distance').forEach(m=>{const result=resultFor(m,scale);for(const metric of ['length','horizontal','vertical']){const option=document.createElement('option');option.value=`${m.id}|${metric}`;option.textContent=`${m.label} · ${metric==='length'?t('distance'):t(metric)} ${format(result[metric])} m`;select.append(option);}});}}
function invalidateTransport(){transportResult=undefined;for(const id of ['transport-result','transport-canvas','transport-step','transport-scenario'])$(id).hidden=true;}
$('transport-form').addEventListener('input',invalidateTransport);
for(const id of ['route-width','route-ceiling','landing-width','landing-depth','stair-rise','stair-run']){const select=document.createElement('select'),label=document.createElement('label'),caption=document.createElement('span');select.dataset.routeSource=id;label.className='field source-field';caption.dataset.i18n='measurementSource';label.append(caption,select);select.onchange=()=>{const [identifier,metric]=select.value.split('|'),m=measurements.find(m=>m.id===identifier);if(m)$(id).value=resultFor(m,scale)[metric];invalidateTransport();};$(id).addEventListener('input',()=>select.value='');$(id).closest('label').insertAdjacentElement('afterend',label);}
$('transport-form').onsubmit=event=>{event.preventDefault();try{
  const number=id=>Number($(id).value),input={object:{width:number('object-width'),depth:number('object-depth'),height:number('object-height')},route:{width:number('route-width'),ceiling:number('route-ceiling'),landingWidth:number('landing-width'),landingDepth:number('landing-depth'),rise:number('stair-rise'),run:number('stair-run'),turnDegrees:number('turn-angle')},margin:number('transport-margin'),allowTilt:$('allow-tilt').checked};
  transportResult=assessTransport(input);transportResult.input=input;transportRecord={input,model:$('model-search').value.trim().slice(0,200)||t('manualDimensions'),assessedAt:new Date().toISOString()};if(bundle)dirty=true;$('transport-result').hidden=false;$('transport-result').className=`verdict ${transportResult.verdict}`;$('transport-result').textContent=`${t(transportResult.verdict)}\n${transportResult.reasons.map(t).join(' · ')}\n${t('remainingClearance')}: ${Object.entries(transportResult.limitingClearances).map(([key,value])=>`${t({corridorWidth:'routeWidth',ceiling:'routeCeiling',landingWidth:'landingWidth',landingDepth:'landingDepth'}[key]||key)}: ${format(value)} m`).join(' · ')}\n${t('transportAssumptions')}`;
  $('transport-scenario').replaceChildren();transportResult.scenarios.forEach(s=>{const option=document.createElement('option');option.value=s.id;option.textContent=`${s.startingYaw}° · ${t('allowTilt')} ${format(s.tilt)}° · ${t(s.fits?'possible':'uncertain')}`;$('transport-scenario').append(option);});$('transport-scenario').value=transportResult.chosenScenario;$('transport-scenario').hidden=false;
  $('transport-canvas').hidden=false;$('transport-step').hidden=false;$('transport-step').max=Math.max(0,transportResult.samples.length-1);$('transport-step').value='0';drawTransport();
}catch(error){showError(error);}};
$('transport-step').oninput=drawTransport;
$('transport-scenario').onchange=()=>{const scenario=transportResult.scenarios.find(s=>s.id===$('transport-scenario').value);$('transport-step').max=Math.max(0,scenario.samples.length-1);$('transport-step').value='0';drawTransport();};
function drawTransport(){
  if(!transportResult)return;const scenario=transportResult.scenarios.find(s=>s.id===$('transport-scenario').value)||transportResult.scenarios[0],sample=scenario.samples[Number($('transport-step').value)]||scenario.samples[0];if(!sample)return;
  const canvas=$('transport-canvas'),ctx=canvas.getContext('2d'),{object,route,margin}=transportResult.input;ctx.clearRect(0,0,canvas.width,canvas.height);ctx.fillStyle='#f5f2fa';ctx.fillRect(0,0,600,340);
  const ratio=220/Math.max(route.landingWidth,route.landingDepth,object.width,object.depth,1),x=160,y=170;
  ctx.strokeStyle='#6d6281';ctx.lineWidth=2;ctx.strokeRect(x-route.landingWidth*ratio/2,y-route.landingDepth*ratio/2,route.landingWidth*ratio,route.landingDepth*ratio);
  const width=scenario.sideways?object.depth:object.width,depth=scenario.sideways?object.width:object.depth,tilt=(sample.tilt||0)*Math.PI/180,footprintDepth=depth*Math.abs(Math.cos(tilt))+object.height*Math.abs(Math.sin(tilt));
  ctx.save();ctx.translate(x,y);ctx.rotate((sample.yaw||0)*Math.PI/180);ctx.fillStyle='#70edc599';ctx.strokeStyle='#218d70';ctx.fillRect(-width*ratio/2,-footprintDepth*ratio/2,width*ratio,footprintDepth*ratio);ctx.strokeRect(-width*ratio/2,-footprintDepth*ratio/2,width*ratio,footprintDepth*ratio);ctx.restore();
  ctx.strokeStyle='#a05a29';ctx.setLineDash([5,4]);ctx.strokeRect(x-(sample.width+2*margin)*ratio/2,y-(sample.depth+2*margin)*ratio/2,(sample.width+2*margin)*ratio,(sample.depth+2*margin)*ratio);ctx.setLineDash([]);
  ctx.fillStyle='#251a40';ctx.font='14px Segoe UI';ctx.fillText(`${format(sample.yaw||0)}° · ${format(sample.width)} × ${format(sample.depth)} m`,35,315);
  const hRatio=220/Math.max(route.ceiling,sample.height||object.height,1);ctx.strokeStyle='#6d6281';ctx.beginPath();ctx.moveTo(350,280-route.ceiling*hRatio);ctx.lineTo(565,280-route.ceiling*hRatio);ctx.stroke();ctx.fillStyle='#7050ce88';ctx.fillRect(400,280-(sample.height||object.height)*hRatio,80,(sample.height||object.height)*hRatio);ctx.fillStyle='#251a40';ctx.fillText(`${t('height')}: ${format(sample.height||object.height)} m`,350,315);ctx.fillText(`${t('allowTilt')}: ${format(sample.tilt||0)}°`,350,30);
}

function refreshCloudButtons(){const server=provider==='server',configured=server?config.serverEnabled:!!config[provider==='google'?'googleClientId':'microsoftClientId'];$('connect').disabled=(!server&&!authReady)||!configured||cloudBusy;$('disconnect').disabled=!drive||cloudBusy;$('refresh').disabled=!drive||cloudBusy;$('upload').disabled=!drive||!bundle||cloudBusy||busy;$('save-config').disabled=cloudBusy;$('server-config').hidden=!server;$('cloud-config').hidden=server;$('provider-help').textContent=t(server?'serverHelp':'cloudScope');document.querySelectorAll('[data-provider]').forEach(el=>{el.disabled=cloudBusy;el.classList.toggle('active',el.dataset.provider===provider);});}
async function initializeAuth(){const attempt=++authAttempt,selected=provider;authReady=false;refreshCloudButtons();try{if(selected!=='server')await prepareAuth(selected==='google'?{googleClientId:config.googleClientId}:{microsoftClientId:config.microsoftClientId});if(attempt===authAttempt)authReady=true;}catch(e){if(attempt===authAttempt)$('cloud-status').textContent=t('networkError');}refreshCloudButtons();}
$('cloud').onclick=async()=>{if(!Object.keys(config).length){try{config=await(await fetch('./config.json')).json();}catch{}try{config={...config,...JSON.parse(storage.get('rtab-cloud-config')||'{}')};}catch{}}
  $('google-id').value=config.googleClientId||'';$('microsoft-id').value=config.microsoftClientId||'';$('cloud-config').open=!config.googleClientId&&!config.microsoftClientId;$('cloud-dialog').showModal();await initializeAuth();};
$('save-config').onclick=async()=>{const ids={googleClientId:$('google-id').value.trim(),microsoftClientId:$('microsoft-id').value.trim()};config={...config,...ids};storage.set('rtab-cloud-config',JSON.stringify(ids));await resetAuth();drive=undefined;$('cloud-files').replaceChildren();await initializeAuth();toast(t('saved'));};
document.querySelectorAll('[data-provider]').forEach(el=>el.onclick=()=>{provider=el.dataset.provider;drive=undefined;$('cloud-files').replaceChildren();$('cloud-status').textContent='';initializeAuth();});
async function cloudTask(action){if(cloudBusy)return;cloudBusy=true;refreshCloudButtons();try{await action();}catch(e){$('cloud-status').textContent=`${t(e.code||'networkError')}${e.status?` (${e.status})`:''}`;}finally{cloudBusy=false;refreshCloudButtons();}}
async function connect(){drive=provider==='server'?new ServerDrive($('server-token').value):new CloudDrive(provider,await signIn(provider));}
async function listCloud(){
  const items=await drive.list();$('cloud-files').replaceChildren();$('cloud-status').textContent=items.length?'':t('cloudEmpty');
  items.forEach(item=>{const li=document.createElement('li'),button=document.createElement('button');button.textContent=item.name;button.onclick=()=>cloudTask(async()=>{if(busy||!allowReplace())return;await runTask(async()=>{await connect();const data=await drive.download(item.id);await load(await readFiles([new File([data],/\.zip$/i.test(item.name)?item.name:`${item.name}.zip`,{type:'application/zip'})]));$('cloud-dialog').close();});});li.append(button);$('cloud-files').append(li);});
}
$('connect').onclick=()=>cloudTask(async()=>{await connect();await listCloud();});
$('refresh').onclick=()=>cloudTask(async()=>{await connect();await listCloud();});
$('disconnect').onclick=()=>cloudTask(async()=>{if(provider==='server'){$('server-token').value='';photoPanel.disconnect();}else await disconnect(provider);drive=undefined;$('cloud-files').replaceChildren();$('cloud-status').textContent='';});
$('upload').onclick=()=>cloudTask(async()=>{await connect();const snapshot=workspaceSnapshot(),signature=stateSignature(),data=await packageBuilding(snapshot);$('upload-progress').hidden=false;$('upload-progress').value=0;try{await drive.upload(data,snapshot.name,p=>{$('upload-progress').value=p;$('cloud-status').textContent=`${t('progress')} ${Math.round(p*100)}%`;});if(signature===stateSignature())dirty=false;await listCloud();$('cloud-status').textContent=t('saved');}finally{$('upload-progress').hidden=true;}});
async function openSplatBytes(bytes,name){
  const attempt=++splatAttempt;if(!$('splat-dialog').open)$('splat-dialog').showModal();splatLoading=true;splatButtons();$('splat-status').textContent=t('working');
  let instance,validData=false;
  const current=()=>attempt===splatAttempt&&$('splat-dialog').open;
  try{
    const data=decodeSplat(bytes,name);validData=true;
    const old=splatViewer;splatViewer=undefined;splatData=undefined;await old?.dispose();if(!current())return;
    $('splat-stage').replaceChildren();
    const {SplatViewer}=await import('./splat-viewer.js');if(!current())return;
    instance=new SplatViewer($('splat-stage'),()=>{if(current())$('splat-status').textContent=t('viewerUnavailable');});splatViewer=instance;instance.renderer.domElement.setAttribute('aria-label',t('splatTitle'));
    await instance.load(data);if(!current())return;splatData=data;$('splat-status').textContent=name;instance.renderer.domElement.focus({preventScroll:true});
  }catch(error){
    if(current()){$('splat-status').textContent=t(error.code==='splatLimit'?'splatLimit':validData?'viewerUnavailable':'splatInvalid');if(instance===splatViewer&&instance){splatViewer=undefined;splatData=undefined;await instance.dispose();}}
  }finally{if(attempt===splatAttempt){splatLoading=false;splatButtons();}}
}
function splatButtons(){for(const id of ['splat-open','splat-demo'])$(id).disabled=splatLoading;for(const id of ['splat-fit','splat-focus','splat-download'])$(id).disabled=splatLoading||!splatData;}
async function openSplatFile(file){if(file.size>MAX_SPLAT_BYTES)throw {code:'splatLimit'};await openSplatBytes(new Uint8Array(await file.arrayBuffer()),file.name);}
function showSplatPanel(){$('splat-dialog').showModal();splatButtons();}
for(const id of ['home-splats','workspace-splats'])$(id).onclick=showSplatPanel;
$('splat-open').onclick=()=>$('splat-file').click();$('splat-file').onchange=async()=>{const file=$('splat-file').files[0];if(file)try{await openSplatFile(file);}catch(error){showError(error);}$('splat-file').value='';};
$('splat-demo').onclick=()=>openSplatBytes(syntheticSplatDemo(),'kantura-synthetic-demo.splat');$('splat-fit').onclick=()=>splatViewer?.fit();$('splat-download').onclick=()=>{if(splatData)download(new Blob([splatData.original],{type:'application/octet-stream'}),splatData.name);};
$('splat-focus').onclick=()=>splatViewer?.focusSubject();
$('splat-dialog').addEventListener('close',async()=>{++splatAttempt;splatLoading=false;const old=splatViewer;splatViewer=undefined;splatData=undefined;await old?.dispose();splatButtons();});
photoPanel=new ReconstructionPanel({t,getToken:()=>$('server-token').value,setToken:token=>{$('server-token').value=token;},openArtifact:async(file,job)=>{
  if(job.mode==='splat'){await openSplatFile(file);return;}
  await runTask(async()=>{if(!allowReplace())return;const next=await readFiles([file]);if(next.building||next.project)throw {code:'invalidProject'};next.source='photogrammetry';next.name=job.name;await load(next);toast(t('photoScaleWarning'));});
}});
for(const id of ['home-photo-jobs','workspace-photo-jobs'])$(id).onclick=()=>photoPanel.open();
translate();

let panoramaPanel;
async function openPanoramaPanel(){
  if(busy)return;
  if(panoramaPanel){panoramaPanel.element.focus();return;}
  try{const {openPanorama}=await import('./panorama.js');panoramaPanel=openPanorama({language,onClose:()=>{panoramaPanel=undefined;},onError:showError});await panoramaPanel.ready;}
  catch(error){panoramaPanel?.dispose();panoramaPanel=undefined;showError(error);}
}
$('home-panorama').onclick=openPanoramaPanel;
$('workspace-panorama').onclick=openPanoramaPanel;
