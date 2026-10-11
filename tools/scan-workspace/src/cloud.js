const GRAPH='https://graph.microsoft.com/v1.0';
const DRIVE='https://www.googleapis.com/drive/v3';
export const SCOPES={google:'https://www.googleapis.com/auth/drive.file',microsoft:'Files.ReadWrite.AppFolder'};
const suffix='.rtabmeasure.zip';
export class CloudError extends Error { constructor(status=0){super('networkError');this.code='networkError';this.status=status;} }
async function checked(response, extra=[]) { if(!response.ok&&!extra.includes(response.status))throw new CloudError(response.status);return response; }
function safeUrl(url,host) { const parsed=new URL(url);if(parsed.protocol!=='https:'||parsed.username||parsed.password||(host&&parsed.hostname!==host))throw new CloudError();return url; }
export class CloudDrive {
  constructor(provider,token,fetcher=(...args)=>fetch(...args)){this.provider=provider;this.token=token;this.fetch=fetcher;}
  async api(url,options={}) {
    safeUrl(url,this.provider==='google'?'www.googleapis.com':'graph.microsoft.com');
    return checked(await this.fetch(url,{...options,headers:{...options.headers,Authorization:`Bearer ${this.token}`}}));
  }
  async folder(){if(!this.folderId)this.folderId=(await(await this.api(`${GRAPH}/me/drive/special/approot`)).json()).id;return this.folderId;}
  async list() {
    let url=this.provider==='google'
      ? `${DRIVE}/files?${new URLSearchParams({q:"trashed = false and appProperties has { key='rtabMeasure' and value='1' }",fields:'files(id,name,size),nextPageToken',pageSize:'100',orderBy:'modifiedTime desc'})}`
      : `${GRAPH}/me/drive/items/${encodeURIComponent(await this.folder())}/children?$select=id,name,size,file&$top=100`;
    const items=[];
    for(let page=0;url&&page<10;page++) {
      const data=await(await this.api(url)).json();
      items.push(...(this.provider==='google'?data.files:data.value).filter(f=>f.name?.endsWith(suffix)).map(f=>({id:f.id,name:f.name,size:Number(f.size)})));
      if(this.provider==='google') {const next=data.nextPageToken; const parsed=new URL(url);if(next)parsed.searchParams.set('pageToken',next);url=next?parsed.href:null;}
      else url=data['@odata.nextLink'];
    }
    return items;
  }
  async download(id,maxBytes=200*1024*1024) {
    let response;
    if(this.provider==='google') response=await this.api(`${DRIVE}/files/${encodeURIComponent(id)}?alt=media`);
    else {
      const item=await(await this.api(`${GRAPH}/me/drive/items/${encodeURIComponent(id)}?$select=id,size,@microsoft.graph.downloadUrl`)).json();
      if(Number(item.size)>maxBytes)throw Object.assign(new Error('tooLarge'),{code:'tooLarge'});
      // The preauthenticated URL must never receive our Graph bearer token.
      response=await checked(await this.fetch(safeUrl(item['@microsoft.graph.downloadUrl'])));
    }
    if(Number(response.headers.get('Content-Length'))>maxBytes)throw Object.assign(new Error('tooLarge'),{code:'tooLarge'});
    const reader=response.body.getReader(),chunks=[];let total=0;
    while(true){const {done,value}=await reader.read();if(done)break;total+=value.byteLength;if(total>maxBytes){await reader.cancel();throw Object.assign(new Error('tooLarge'),{code:'tooLarge'});}chunks.push(value);}
    return new Blob(chunks,{type:'application/zip'});
  }
  async upload(blob,name,onProgress=()=>{}) {
    if(!blob.size||blob.size>200*1024*1024)throw Object.assign(new Error('tooLarge'),{code:'tooLarge'});
    const filename=name.replace(/[<>:"/\\|?*\x00-\x1f]/g,'_').slice(0,100)+`-${new Date().toISOString().replaceAll(':','-')}${suffix}`;
    let url;
    if(this.provider==='google') {
      const response=await this.api('https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable',{method:'POST',headers:{'Content-Type':'application/json','X-Upload-Content-Type':'application/zip','X-Upload-Content-Length':String(blob.size)},body:JSON.stringify({name:filename,appProperties:{rtabMeasure:'1'}})});
      url=safeUrl(response.headers.get('Location'),'www.googleapis.com');
    } else {
      const response=await this.api(`${GRAPH}/me/drive/items/${encodeURIComponent(await this.folder())}:/${encodeURIComponent(filename)}:/createUploadSession`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({item:{'@microsoft.graph.conflictBehavior':'rename',name:filename}})});
      url=safeUrl((await response.json()).uploadUrl);
    }
    // 5 MiB is a multiple of both Google's 256 KiB and Microsoft's 320 KiB.
    const chunkSize=5*1024*1024;
    for(let offset=0;offset<blob.size;) {
      const end=Math.min(offset+chunkSize,blob.size);
      const headers={'Content-Type':'application/octet-stream','Content-Range':`bytes ${offset}-${end-1}/${blob.size}`};
      if(this.provider==='google') headers.Authorization=`Bearer ${this.token}`;
      const response=await checked(await this.fetch(url,{method:'PUT',headers,body:blob.slice(offset,end)}),[308]);
      if(this.provider==='google'&&response.status===308){
        const range=response.headers.get('Range'),received=range&&/^bytes=0-(\d+)$/.exec(range);
        if(!received||Number(received[1])+1!==end)throw new CloudError(308);
      }
      if(this.provider==='microsoft'&&response.status===202){
        const data=await response.json();
        if(!data.nextExpectedRanges?.some(r=>r.startsWith(`${end}-`)))throw new CloudError(202);
      }
      if(end===blob.size && ![200,201].includes(response.status))throw new CloudError(response.status);
      offset=end;onProgress(offset/blob.size);
    }
    return filename;
  }
}

let googleClient,googleToken,googleExpiry=0,msalApp,msalAccount;
export async function resetAuth(){await disconnect('google');await disconnect('microsoft');googleClient=undefined;msalApp=undefined;}
export async function prepareAuth(config) {
  if(config.microsoftClientId&&!msalApp){
    const {PublicClientApplication}=await import('@azure/msal-browser');
    msalApp=new PublicClientApplication({auth:{clientId:config.microsoftClientId,authority:'https://login.microsoftonline.com/common',redirectUri:new URL('./auth.html',location.href).href},cache:{cacheLocation:'memoryStorage'}});
    await msalApp.initialize();
  }
  if(config.googleClientId&&!googleClient){
    if(!window.google?.accounts?.oauth2)await new Promise((resolve,reject)=>{const script=document.createElement('script');script.src='https://accounts.google.com/gsi/client';script.onload=resolve;script.onerror=reject;document.head.append(script);});
    googleClient={clientId:config.googleClientId};
  }
}
export async function signIn(provider) {
  if(provider==='google'){
    if(googleToken&&Date.now()<googleExpiry)return googleToken;
    if(!googleClient)throw new CloudError();
    return new Promise((resolve,reject)=>{
      const client=window.google.accounts.oauth2.initTokenClient({client_id:googleClient.clientId,scope:SCOPES.google,
        callback:response=>{if(response.error||!response.access_token){reject(new CloudError());return;}googleToken=response.access_token;googleExpiry=Date.now()+(Number(response.expires_in)-60)*1000;resolve(googleToken);},
        error_callback:()=>reject(new CloudError())});
      client.requestAccessToken({prompt:googleToken?'':'select_account'});
    });
  }
  if(!msalApp)throw new CloudError();
  const request={scopes:[SCOPES.microsoft]};
  if(msalAccount)try{return (await msalApp.acquireTokenSilent({...request,account:msalAccount})).accessToken;}catch{}
  const result=await msalApp.acquireTokenPopup(request);msalAccount=result.account;return result.accessToken;
}
export async function disconnect(provider) {
  if(provider==='google'){googleToken=undefined;googleExpiry=0;}
  else {await msalApp?.clearCache();msalAccount=undefined;}
}
