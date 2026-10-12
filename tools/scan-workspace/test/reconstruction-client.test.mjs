import test from 'node:test';
import assert from 'node:assert/strict';
import { unzipSync } from 'fflate';
import { photoArchive, reconstructionInput, ReconstructionClient, validateJob, RECONSTRUCTION_LIMIT } from '../src/reconstruction.js';

const id = '134c6a1d-dc64-4384-a0ce-31294a3fe618', payload = new TextEncoder().encode('verified artifact bytes');
const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', payload)), byte => byte.toString(16).padStart(2,'0')).join('');
const makeJob = (status = 'complete') => ({ id, name: 'A room', mode: 'mesh', status, scaleStatus: 'unverified', artifacts: status === 'complete' ? ['mesh.zip','model.ply','reconstruction.json'].map(name => ({ name, bytes: payload.length, sha256: hash, url: 'https://untrusted.example/steal' })) : [] });
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

test('photo selection becomes a bounded ZIP with unique safe paths and preserves original image bytes', async () => {
  const files = Array.from({ length: 8 }, (_, i) => new File([new Uint8Array([i,3,4])], '../same.jpg'));
  const zip = await photoArchive(files), entries = unzipSync(new Uint8Array(await zip.arrayBuffer()));
  assert.equal(Object.keys(entries).length, 8);
  assert.ok(Object.keys(entries).every(name => /^Images\/photo-\d{4}\.jpg$/.test(name)));
  for (let i = 0; i < 8; i++) assert.deepEqual([...entries[`Images/photo-000${i+1}.jpg`]], [i,3,4]);
  const nativeZip = new File([zip], 'native-dataset.zip'); assert.equal(await photoArchive([nativeZip]), nativeZip);
  await assert.rejects(photoArchive(files.slice(0,7)), { code: 'photoInputHelp' });
  await assert.rejects(photoArchive([...files,new File(['not an image'],'script.html')]), { code: 'photoInputHelp' });
  await assert.rejects(photoArchive([{ name: 'large.zip', size: RECONSTRUCTION_LIMIT + 1 }]), { code: 'tooLarge' });
});

test('panorama selections use the same two-to-forty limit as the real stitcher', async () => {
  const files=Array.from({length:41},(_,i)=>new File([new Uint8Array([i])],`${i}.jpg`));
  const input=await reconstructionInput(files.slice(0,2),'panorama');
  assert.equal(input.inputType,'photos');
  assert.equal(Object.keys(unzipSync(new Uint8Array(await input.blob.arrayBuffer()))).length,2);
  await reconstructionInput(files.slice(0,40),'panorama');
  await assert.rejects(reconstructionInput(files.slice(0,1),'panorama'),{code:'panoramaPhotosHelp'});
  await assert.rejects(reconstructionInput(files,'panorama'),{code:'panoramaPhotosHelp'});
  await assert.rejects(reconstructionInput(files.slice(0,2),'mesh'),{code:'photoInputHelp'});
});

test('job submission is explicit authenticated raw ZIP with the selected mode and sanitized name', async () => {
  const calls = [], client = new ReconstructionClient('private-memory-token', async (url, options) => { calls.push({ url, options }); return json({ job: makeJob('queued') }, 202); });
  const input = new Blob(['zip']); const job = await client.submit(input, 'mesh', 'Living / room');
  assert.equal(job.status, 'queued');
  assert.match(calls[0].url, /^\.\/api\/reconstruction\/jobs\?mode=mesh&name=Living\+_\+room$/);
  assert.equal(calls[0].options.body, input); assert.equal(calls[0].options.headers.Authorization, 'Bearer private-memory-token');
  assert.equal(calls[0].options.headers['Content-Type'], 'application/zip'); assert.equal(calls[0].options.redirect, 'error');
  await assert.rejects(client.submit(input,'made-up-mode','x'), { code: 'reconstructionInvalid' });
  await assert.rejects(client.submit(input,'constructor','x'), { code: 'reconstructionInvalid' });
  assert.equal(calls.length, 1);
});

test('capabilities require real boolean availability and failed authentication never becomes a successful job', async () => {
  const data = { version: 1, modes: [{ id:'mesh',available:false,engine:'COLMAP + OpenMVS' },{ id:'splat',available:false,engine:'COLMAP + OpenSplat' }] };
  const client = new ReconstructionClient('key', async () => json(data));
  assert.ok((await client.capabilities()).modes.every(mode => mode.available === false));
  data.modes[0].available = 'yes'; await assert.rejects(client.capabilities(), { code: 'reconstructionInvalid' });
  const denied = new ReconstructionClient('wrong', async () => json({ error: 'unauthorized' },401));
  await assert.rejects(denied.submit(new Blob(['zip']),'mesh','room'), { code: 'networkError', status:401 });
});

test('a complete job requires all allowed nonempty verified artifacts and failed jobs cannot advertise output', () => {
  assert.equal(validateJob(makeJob()).status, 'complete');
  assert.throws(() => validateJob({ ...makeJob(), mode:'__proto__' }), { code:'reconstructionInvalid' });
  assert.throws(() => validateJob({ ...makeJob(), artifacts:[null] }), { code:'reconstructionInvalid' });
  const incomplete = makeJob(); incomplete.artifacts.pop(); assert.throws(() => validateJob(incomplete), { code:'reconstructionInvalid' });
  const fake = makeJob(); fake.status = 'failed'; assert.throws(() => validateJob(fake), { code:'reconstructionInvalid' });
  const unsafe = makeJob(); unsafe.artifacts[0].name = '../../server.key'; assert.throws(() => validateJob(unsafe), { code:'reconstructionInvalid' });
});

test('artifact downloads ignore supplied URLs, enforce bytes and SHA-256, and never leak the token', async () => {
  const calls = [], client = new ReconstructionClient('private-token', async (url, options) => { calls.push({url,options}); return new Response(payload); });
  assert.deepEqual(new Uint8Array(await (await client.artifact(makeJob(),'mesh.zip')).arrayBuffer()), payload);
  assert.equal(calls[0].url, `./api/reconstruction/jobs/${id}/artifacts/mesh.zip`);
  assert.equal(calls[0].options.headers.Authorization, 'Bearer private-token');
  await assert.rejects(client.artifact(makeJob(),'https://attacker.example'), { code:'reconstructionInvalid' });
  assert.equal(calls.length,1);
  const broken = makeJob(); broken.artifacts[0].sha256 = '0'.repeat(64);
  await assert.rejects(client.artifact(broken,'mesh.zip'), { code:'reconstructionInvalid' });
  const truncated = new ReconstructionClient('key', async () => new Response(payload.slice(0,-1)));
  await assert.rejects(truncated.artifact(makeJob(),'mesh.zip'), { code:'reconstructionInvalid' });
});

test('cancel and listing reject malformed identifiers and result envelopes before UI presentation', async () => {
  const calls = [], client = new ReconstructionClient('key', async (url, options) => { calls.push({url,options}); return json({ job:makeJob('cancelled') }); });
  await assert.rejects(client.cancel('../private'), { code:'reconstructionInvalid' }); assert.equal(calls.length,0);
  assert.equal((await client.cancel(id)).status,'cancelled'); assert.equal(calls[0].options.method,'POST');
  await assert.rejects(client.list(), { code:'reconstructionInvalid' });
});

test('a single original video passes unchanged with explicit type/profile; mixed files are refused', async () => {
  const video = new File(['ftyp-is-probed-on-server'], 'capture.MOV');
  const input = await reconstructionInput([video]);
  assert.equal(input.blob,video); assert.equal(input.inputType,'video');
  await assert.rejects(reconstructionInput([video,new File(['x'],'photo.jpg')]),{code:'photoInputHelp'});
  const calls=[], client=new ReconstructionClient('key',async(url,options)=>{calls.push({url,options});return json({job:makeJob('queued')});});
  await client.submit(video,'splat','Drone',{inputType:'video',profile:'uav'});
  assert.match(calls[0].url,/profile=uav$/);
  assert.equal(calls[0].options.headers['Content-Type'],'video/quicktime');
  assert.equal(calls[0].options.body,video);
  await assert.rejects(client.submit(video,'mesh','x',{inputType:'url'}),{code:'reconstructionInvalid'});
  await assert.rejects(client.submit(video,'mesh','x',{profile:'shell-command'}),{code:'reconstructionInvalid'});
});

test('optional selected frames/cameras retain size and checksum validation without accepting private logs',()=>{
  const job=makeJob();job.artifacts.push({name:'photos.zip',bytes:payload.length,sha256:hash},{name:'cameras.json',bytes:payload.length,sha256:hash});
  assert.equal(validateJob(job),job);
  const duplicate=structuredClone(job);duplicate.artifacts[4].name='photos.zip';
  assert.throws(()=>validateJob(duplicate),{code:'reconstructionInvalid'});
  job.artifacts[4].name='worker.log'; assert.throws(()=>validateJob(job),{code:'reconstructionInvalid'});
});

test('panorama and generated jobs require their distinct complete artifact sets',async()=>{
  const modes={panorama:['panorama.png','coverage.png','originals.zip','result.json'],generated:['generated-model.glb','generated-model.obj','generated-model.ply','model.zip','generation.json']};
  for(const [mode,names] of Object.entries(modes)){
    const job={...makeJob(),mode,artifacts:names.map(name=>({name,bytes:payload.length,sha256:hash}))};
    assert.equal(validateJob(job),job);
    assert.throws(()=>validateJob({...job,artifacts:job.artifacts.slice(1)}),{code:'reconstructionInvalid'});
  }
  const image=new File(['input'],'foreground.png'),calls=[];
  assert.equal((await reconstructionInput([image],'generated')).inputType,'image');
  await assert.rejects(reconstructionInput([image,image],'generated'),{code:'imageInputHelp'});
  const client=new ReconstructionClient('key',async(url,options)=>{calls.push({url,options});return json({job:{...makeJob('queued'),mode:'generated'}});});
  await client.submit(image,'generated','Concept',{inputType:'image',foregroundIsolated:true});
  assert.match(calls[0].url,/foregroundIsolated=1$/);assert.equal(calls[0].options.headers['Content-Type'],'image/png');
  await assert.rejects(client.submit(image,'generated','x',{inputType:'image',profile:'uav'}),{code:'reconstructionInvalid'});
});
