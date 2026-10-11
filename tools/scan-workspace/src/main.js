import { Viewer, parseModel, demoBundle } from './viewer.js';
import { guide, dictionaries, resolveLanguage } from './i18n.js';
import { resultFor, calibration, validateProject, floorplanSVG } from './measure.js';
import { readFiles, packageProject, csvReport, download } from './files.js';
import { CloudDrive, prepareAuth, signIn, disconnect, resetAuth } from './cloud.js';
import { ServerDrive } from './server-drive.js';

const $=id=>document.getElementById(id);
const storage={get(key){try{return localStorage.getItem(key);}catch{return null;}},set(key,value){try{localStorage.setItem(key,value);}catch{}}};
let language=resolveLanguage(storage.get('rtab-language')||navigator.language),bundle,measurements=[],pending=[],scale=1,upAxis='z',mode='orbit',dirty=false,calibrated=false,busy=false,guideStep=0;
let provider='microsoft',config={},authReady=false,drive,cloudBusy=false,toastTimer,authAttempt=0;
const t=key=>dictionaries[language][key]||key;
const format=value=>new Intl.NumberFormat(language,{maximumFractionDigits:3}).format(value);
const icons={folder:'M3 7h7l2 2h9v11H3z M3 7V4h7l2 3',ruler:'M3 16L16 3l5 5L8 21z M8 11l3 3 M12 7l3 3 M5 14l3 3',floor:'M3 4h18v16H3z M3 9h6V4 M15 20v-5h6',surface:'M3 8l13-5 5 13-13 5z',target:'M12 3v4 M12 17v4 M3 12h4 M17 12h4 M17 12a5 5 0 1 1-10 0 5 5 0 0 1 10 0',cloud:'M6 18a5 5 0 0 1-1-10 7 7 0 0 1 13-1 5 5 0 0 1 0 11 M12 20V10 M8 14l4-4 4 4',cube:'M12 2l9 5v10l-9 5-9-5V7z M3 7l9 5 9-5 M12 12v10',image:'M3 3h18v18H3z M3 17l6-6 4 4 3-3 5 5 M15 7h1',layers:'M3 7l9-5 9 5-9 5z M3 12l9 5 9-5 M3 17l9 5 9-5',fit:'M8 3H3v5 M16 3h5v5 M3 16v5h5 M21 16v5h-5',book:'M12 5Q6 1 2 4v16q5-3 10 0 5-3 10 0V4q-5-3-10 1v15',save:'M4 3h13l4 4v14H3V3z M7 3v6h10V3 M7 21v-8h10v8',download:'M12 3v12 M7 10l5 5 5-5 M4 16v5h16v-5'};
function icon(name){return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${icons[name]||icons.cube}"/></svg>`;}
document.querySelectorAll('[data-icon]').forEach(el=>el.innerHTML=icon(el.dataset.icon));
let viewer;
try{viewer=new Viewer($('stage'),pick);}catch(e){showError(e);}
function toast(text,error=false){clearTimeout(toastTimer);$('status').textContent=text;$('status').classList.toggle('error',error);$('status').classList.add('visible');toastTimer=setTimeout(()=>$('status').classList.remove('visible'),6500);}
function showError(error){toast(`${t('error')}: ${t(error?.code||'unsupported')}${error?.status?` (${error.status})`:''}`,true);}
function project(){return structuredClone({version:1,name:$('project-name').value.trim()||'Scan',scale,upAxis,calibrated,demo:!!bundle?.demo,measurements});}
function refresh(){
  $('save').disabled=!bundle||busy;$('csv').disabled=!measurements.length;$('svg').disabled=!measurements.some(m=>m.kind==='floor');
  $('empty-overlay').hidden=!!bundle;$('model-name').hidden=!bundle;$('model-name').textContent=bundle?.model||'';$('demo-badge').hidden=!bundle?.demo;
  $('results-empty').hidden=!!measurements.length;$('measure-count').textContent=measurements.length;
  $('instruction').textContent=t(mode==='reference'?'pickReference':mode==='distance'?'pickTwo':['floor','surface'].includes(mode)?'pickArea':'navigateHint');
  $('point-count').textContent=pending.length?`${pending.length} ●`:'';
  $('selection-actions').hidden=mode==='orbit';$('finish').hidden=!['floor','surface'].includes(mode);$('finish').disabled=pending.length<3;$('undo').disabled=!pending.length;
  $('scale-status').textContent=`${t(calibrated?'calibrated':'unverified')} · 1 = ${format(scale)} m`;
  document.querySelectorAll('[data-mode]').forEach(el=>{el.classList.toggle('active',el.dataset.mode===mode);el.setAttribute('aria-pressed',String(el.dataset.mode===mode));el.disabled=!bundle||busy;});
  $('calibrate').disabled=!bundle||busy;
  $('axis').disabled=!bundle||busy;$('units').disabled=!bundle||busy;
  const list=$('measure-list');list.replaceChildren();
  measurements.forEach((m,index)=>{
    const r=resultFor(m,scale),li=document.createElement('li');li.className='measure-item';
    const heading=document.createElement('div');heading.className='measure-name';
    const name=document.createElement('button');name.className='measure-rename';name.textContent=m.label;name.title=t('namePrompt');
    name.onclick=()=>{const value=prompt(t('namePrompt'),m.label);if(value?.trim()){m.label=value.trim().slice(0,200);dirty=true;refresh();}};
    const remove=document.createElement('button');remove.className='icon-button';remove.textContent='×';remove.setAttribute('aria-label',`${t('remove')}: ${m.label}`);remove.onclick=()=>{measurements.splice(index,1);dirty=true;refresh();};heading.append(name,remove);
    const value=document.createElement('div');value.className='measure-value';value.textContent=`${format(r.area??r.length)} ${m.kind==='distance'?'m':'m²'}`;
    const detail=document.createElement('p');detail.className='measure-detail';detail.textContent=m.kind==='distance'?`${t('horizontal')} ${format(r.horizontal)} m · ${t('vertical')} ${format(r.vertical)} m`:`${t('perimeter')} ${format(r.perimeter)} m`;
    li.append(heading,value,detail);list.append(li);
  });
  viewer?.drawMeasurements(measurements,pending,scale,format);refreshCloudButtons();
}
function translate(){
  document.documentElement.lang=language;$('language').value=language;
  document.querySelectorAll('[data-i18n]').forEach(el=>el.textContent=t(el.dataset.i18n));
  document.querySelectorAll('[data-close]').forEach(el=>el.setAttribute('aria-label',t('close')));
  $('step-scan').textContent=guide[language].start;$('step-review').textContent=guide[language].assemble;
  $('texture').title=t('texture');viewer?.renderer.domElement.setAttribute('aria-label',t('model'));
  refresh();renderGuide();
}
function setMode(next){if(busy)return;if(!bundle)return toast(t('noModel'));mode=next;pending=[];viewer.setMode(next);refresh();}
function pick(point){
  if(busy||mode==='orbit')return;
  if(pending.length>=1000)return showError({code:'tooLarge'});
  pending.push(point);
  if(pending.length===2&&mode==='reference'){$('reference-length').value='';$('reference-dialog').showModal();$('reference-length').focus();}
  else if(pending.length===2&&mode==='distance')finish();
  refresh();
}
function finish(){try{
  if(measurements.length>=500)throw {code:'tooLarge'};
  const measurement={kind:mode,label:`${t(mode)} ${measurements.length+1}`,points:pending.map(p=>[...p])};
  const result=resultFor(measurement,scale);if(result.length===0)throw {code:'degenerate'};
  measurements.push(measurement);pending=[];dirty=true;refresh();
}catch(e){showError(e);}}
function allowReplace(){return !dirty||confirm(t('replace'));}
async function load(next){
  if(!viewer)throw {code:'unsupported'};busy=true;refresh();toast(t('loading'));
  try{
    const model=await parseModel(next),p=next.project;
    bundle=next;bundle.demo=!!(next.demo||p?.demo);scale=p?.scale||1;upAxis=p?.upAxis||(/\.glb$/i.test(next.model)?'y':'z');
    measurements=p?.measurements||[];calibrated=!!p?.calibrated;pending=[];mode='orbit';dirty=false;
    $('project-name').value=p?.name||next.name;$('axis').value=upAxis;$('units').value=[1,.01,.001].includes(scale)?String(scale):'1';
    viewer.setModel(model,upAxis);viewer.setMode(mode);toast(t('ready'));
  }finally{busy=false;refresh();}
}
async function openFiles(files){if(!files.length||busy||!allowReplace())return;try{await load(await readFiles(files));}catch(e){showError(e);}}
['open','open-hero'].forEach(id=>$(id).onclick=()=>$('file').click());
$('file').onchange=async()=>{await openFiles($('file').files);$('file').value='';};
$('demo').onclick=async()=>{if(!allowReplace())return;try{await load(demoBundle());}catch(e){showError(e);}};
window.addEventListener('dragover',e=>e.preventDefault());window.addEventListener('drop',e=>{e.preventDefault();openFiles(e.dataTransfer.files);});
document.querySelectorAll('[data-mode]').forEach(el=>el.onclick=()=>setMode(el.dataset.mode));
$('finish').onclick=finish;$('undo').onclick=()=>{pending.pop();refresh();};$('cancel').onclick=()=>setMode('orbit');
$('calibrate').onclick=()=>setMode('reference');
$('reference-form').onsubmit=e=>{e.preventDefault();try{
  const next=calibration(...pending,Number($('reference-length').value));validateProject({...project(),scale:next});scale=next;calibrated=true;dirty=true;$('reference-dialog').close();setMode('orbit');
}catch(error){showError(error);}};
$('reference-dialog').addEventListener('close',()=>{if(mode==='reference'){pending=[];refresh();}});
$('project-name').oninput=()=>{if(bundle)dirty=true;};
$('units').onchange=()=>{const previous=scale;try{const next=Number($('units').value);validateProject({...project(),scale:next});scale=next;calibrated=false;dirty=true;refresh();}catch(e){$('units').value=String(previous);showError(e);}};
$('axis').onchange=async()=>{if(!bundle||busy)return;if(measurements.length&&!confirm(t('replace'))){$('axis').value=upAxis;return;}busy=true;refresh();try{const root=await parseModel(bundle);upAxis=$('axis').value;measurements=[];pending=[];viewer.setModel(root,upAxis);dirty=true;}catch(e){$('axis').value=upAxis;showError(e);}finally{busy=false;refresh();}};
$('orbit').onclick=()=>{viewer?.setTop(false);if(bundle)setMode('orbit');$('orbit').classList.add('active');$('top').classList.remove('active');};
$('top').onclick=()=>{viewer?.setTop(true);$('top').classList.add('active');$('orbit').classList.remove('active');};
$('fit').onclick=()=>viewer?.fit();
$('texture').onclick=()=>{viewer?.setTexture(!viewer.textured);$('texture').classList.toggle('active',!!viewer?.textured);};
$('roof').onclick=()=>{viewer?.setRoof(!viewer.roof);$('roof').classList.toggle('active',!!viewer?.roof);};
$('save').onclick=async()=>{if(!bundle||busy)return;busy=true;refresh();try{const snapshot=project();download(await packageProject(bundle,snapshot),`${snapshot.name}.rtabmeasure.zip`);if(JSON.stringify(snapshot)===JSON.stringify(project()))dirty=false;toast(t('saved'));}catch(e){showError(e);}finally{busy=false;refresh();}};
$('csv').onclick=()=>download(new Blob([csvReport(measurements,scale,resultFor)],{type:'text/csv;charset=utf-8'}),`${project().name}.csv`);
$('svg').onclick=()=>{try{download(new Blob([floorplanSVG(measurements,scale,project().name)],{type:'image/svg+xml'}),`${project().name}.svg`);}catch(e){showError(e);}};
window.addEventListener('beforeunload',e=>{if(dirty){e.preventDefault();e.returnValue='';}});
window.addEventListener('keydown',e=>{if(document.querySelector('dialog[open]')||/^(INPUT|SELECT|TEXTAREA)$/.test(e.target.tagName))return;const choice={'1':'distance','2':'floor','3':'surface','Escape':'orbit'}[e.key];if(choice){e.preventDefault();setMode(choice);}if(e.key==='Backspace'&&pending.length){e.preventDefault();pending.pop();refresh();}});
$('language').onchange=()=>{language=$('language').value;storage.set('rtab-language',language);translate();};
function renderGuide(){const g=guide[language],step=g.steps[guideStep];$('guide-subtitle').textContent=g.title;$('guide-title').textContent=step.title;$('guide-body').textContent=step.body;$('guide-illustration').innerHTML=icon(['target','cube','image','ruler','floor','target','cloud'][guideStep]);$('guide-counter').textContent=`${guideStep+1} / ${g.steps.length}`;$('guide-back').disabled=guideStep===0;$('guide-next').textContent=guideStep===g.steps.length-1?t('done'):t('next');$('guide-progress').replaceChildren(...g.steps.map((_,i)=>{const dot=document.createElement('span');dot.classList.toggle('active',i<=guideStep);return dot;}));}
function openGuide(step=0){guideStep=step;renderGuide();$('guide-dialog').showModal();}
$('tutorial').onclick=()=>openGuide();document.querySelectorAll('[data-guide-step]').forEach(el=>el.onclick=()=>openGuide(Number(el.dataset.guideStep)));
$('guide-back').onclick=()=>{guideStep--;renderGuide();};$('guide-next').onclick=()=>{if(guideStep===guide[language].steps.length-1)$('guide-dialog').close();else{guideStep++;renderGuide();}};
document.querySelectorAll('[data-close]').forEach(el=>el.onclick=()=>$(el.dataset.close).close());

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
  items.forEach(item=>{const li=document.createElement('li'),button=document.createElement('button');button.textContent=item.name;button.onclick=()=>cloudTask(async()=>{if(!allowReplace())return;await connect();const data=await drive.download(item.id);await load(await readFiles([new File([data],/\.zip$/i.test(item.name)?item.name:`${item.name}.zip`,{type:'application/zip'})]));$('cloud-dialog').close();});li.append(button);$('cloud-files').append(li);});
}
$('connect').onclick=()=>cloudTask(async()=>{await connect();await listCloud();});
$('refresh').onclick=()=>cloudTask(async()=>{await connect();await listCloud();});
$('disconnect').onclick=()=>cloudTask(async()=>{if(provider==='server')$('server-token').value='';else await disconnect(provider);drive=undefined;$('cloud-files').replaceChildren();$('cloud-status').textContent='';});
$('upload').onclick=()=>cloudTask(async()=>{await connect();const snapshot=project(),data=await packageProject(bundle,snapshot);$('upload-progress').hidden=false;$('upload-progress').value=0;try{await drive.upload(data,snapshot.name,p=>{$('upload-progress').value=p;$('cloud-status').textContent=`${t('progress')} ${Math.round(p*100)}%`;});if(JSON.stringify(snapshot)===JSON.stringify(project()))dirty=false;await listCloud();$('cloud-status').textContent=t('saved');}finally{$('upload-progress').hidden=true;}});
translate();
