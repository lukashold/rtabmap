// Our standalone exports retain their non-metric origin even without model.zip.
// Unlabelled third-party geometry remains unverified; absence is not a proof.
export function modelOrigin(name, bytes) {
  if (!bytes?.byteLength) return undefined;
  if (/\.(obj|ply)$/i.test(name)) {
    const header=new TextDecoder().decode(bytes.subarray(0,4096));
    if (/Kantura(?:[: ]+)AI-generated/i.test(header)&&/metricMeasurementsAllowed=false/.test(header)) return 'generated';
  } else if (/\.glb$/i.test(name)&&bytes.byteLength>=20) {
    const view=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength);
    const length=view.getUint32(12,true);
    if (view.getUint32(0,true)!==0x46546c67||view.getUint32(4,true)!==2||view.getUint32(16,true)!==0x4e4f534a||length>4*1024*1024||length+20>bytes.byteLength) return undefined;
    try {
      const json=JSON.parse(new TextDecoder().decode(bytes.subarray(20,20+length)));
      const items=[json.asset,...(Array.isArray(json.meshes)?json.meshes:[]),...(Array.isArray(json.scenes)?json.scenes:[])];
      if(items.some(item=>item?.extras?.source==='generated'&&item.extras.metricMeasurementsAllowed===false)) return 'generated';
    } catch { /* The model loader handles malformed geometry separately. */ }
  }
}
