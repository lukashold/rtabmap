import { CloudError } from './cloud.js';
export class ServerDrive {
  constructor(token,fetcher=(...args)=>fetch(...args)){this.token=token;this.fetch=fetcher;}
  async api(path,options={}){
    const response=await this.fetch(`./api/projects${path}`,{...options,headers:{...options.headers,Authorization:`Bearer ${this.token}`}});
    if(!response.ok)throw new CloudError(response.status);
    return response;
  }
  async list(){return (await(await this.api('')).json()).projects;}
  async download(id){const response=await this.api(`/${encodeURIComponent(id)}`);return response.blob();}
  async upload(blob,name,onProgress=()=>{}){if(blob.size>200*1024*1024)throw {code:'tooLarge'};name=name.replace(/[\x00-\x1f\x7f/\\]/g,'_').trim().slice(0,120)||'Scan';onProgress(0);await this.api(`?${new URLSearchParams({name})}`,{method:'POST',headers:{'Content-Type':'application/zip'},body:blob});onProgress(1);}
}
