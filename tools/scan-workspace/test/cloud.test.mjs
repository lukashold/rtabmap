import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CloudDrive, SCOPES, prepareAuth, signIn, resetAuth } from '../src/cloud.js';
import { ServerDrive } from '../src/server-drive.js';
const json=(data,status=200,headers={})=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json',...headers}});
test('browser fetch is not invoked with a drive object as its receiver',async()=>{
  const original=globalThis.fetch;
  globalThis.fetch=async function(url){assert.ok(this===undefined||this===globalThis);return json(url.startsWith('./')?{projects:[]}:{files:[]});};
  try{assert.deepEqual(await new ServerDrive('token').list(),[]);assert.deepEqual(await new CloudDrive('google','token').list(),[]);}finally{globalThis.fetch=original;}
});
test('Google popup closure rejects the pending login and a later login can succeed',async()=>{
  const original=globalThis.window;let response='close';
  globalThis.window={google:{accounts:{oauth2:{initTokenClient:options=>({requestAccessToken(){if(response==='close')options.error_callback({type:'popup_closed'});else options.callback({access_token:'fresh-token',expires_in:3600});}})}}}};
  try{
    await resetAuth();await prepareAuth({googleClientId:'public-client-id'});
    await assert.rejects(signIn('google'),e=>e.code==='networkError');
    response='success';assert.equal(await signIn('google'),'fresh-token');
  }finally{await resetAuth();if(original===undefined)delete globalThis.window;else globalThis.window=original;}
});
test('OneDrive uses app-folder scope and no bearer token on upload session URLs',async()=>{
  assert.equal(SCOPES.microsoft,'Files.ReadWrite.AppFolder');const calls=[];
  const drive=new CloudDrive('microsoft','TOKEN',async(url,options={})=>{calls.push([url,options]);if(url.includes('special/approot'))return json({id:'folder'});if(url.includes('createUploadSession'))return json({uploadUrl:'https://upload.example.test/session'});return json({id:'saved'},201);});
  await drive.upload(new Blob(['data']),'Tor');
  assert.equal(calls[0][1].headers.Authorization,'Bearer TOKEN');assert.equal(calls.at(-1)[1].headers.Authorization,undefined);
  assert.match(calls.at(-1)[1].headers['Content-Range'],/bytes 0-3\/4/);
  assert.match(calls[1][1].body,/rename/);
});
test('Google chunks a file and preserves returned session URL',async()=>{
  const ranges=[];const drive=new CloudDrive('google','TOKEN',async(url,options)=>{
    if(options.method==='POST')return new Response(null,{headers:{Location:'https://www.googleapis.com/upload/session'}});
    assert.equal(url,'https://www.googleapis.com/upload/session');ranges.push(options.headers['Content-Range']);
    return ranges.length===1?new Response(null,{status:308,headers:{Range:'bytes=0-5242879'}}):json({id:'saved'});
  });
  await drive.upload(new Blob([new Uint8Array(5242881)]),'Room');
  assert.deepEqual(ranges,['bytes 0-5242879/5242881','bytes 5242880-5242880/5242881']);
});
test('untrusted pagination links cannot receive provider tokens',async()=>{
  const drive=new CloudDrive('microsoft','TOKEN',async url=>url.includes('approot')?json({id:'folder'}):json({value:[],'@odata.nextLink':'https://attacker.example/next'}));
  await assert.rejects(drive.list());
});
test('cloud authentication failure is never reported as successful saving',async()=>{
  const drive=new CloudDrive('google','TOKEN',async()=>new Response(null,{status:401}));await assert.rejects(drive.upload(new Blob(['x']),'Room'));
});
test('Google listing is limited to projects created by this app',async()=>{
  const drive=new CloudDrive('google','TOKEN',async url=>{assert.match(decodeURIComponent(url),/rtabMeasure/);return json({files:[{id:'1',name:'Room.rtabmeasure.zip',size:'4'}]});});
  assert.deepEqual(await drive.list(),[{id:'1',name:'Room.rtabmeasure.zip',size:4}]);
});
test('OneDrive downloads use preauthenticated URLs without Graph tokens',async()=>{
  const calls=[];const drive=new CloudDrive('microsoft','TOKEN',async(url,options)=>{calls.push([url,options]);return url.startsWith('https://graph.microsoft.com')?json({size:2,'@microsoft.graph.downloadUrl':'https://download.example.test/item'}):new Response('ok');});
  assert.equal(await(await drive.download('a')).text(),'ok');assert.equal(calls[1][1],undefined);
});
