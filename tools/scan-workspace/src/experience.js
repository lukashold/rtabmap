import { distance, MeasureError, validateScale, validateProject } from './measure.js';

export const photoPath=/^kantura-notes\/[a-zA-Z0-9-]{1,80}\.(jpg|png|webp)$/;
export const validateExperience=validateProject;
export function referenceCheck(check,scale) {
  validateScale(check.knownMeters);
  const measured=distance(...check.points,scale).length,difference=measured-check.knownMeters;
  return {measured,known:check.knownMeters,difference,percent:difference/check.knownMeters*100};
}
export async function preparePhoto(file) {
  if(!['image/jpeg','image/png','image/webp'].includes(file.type))throw new MeasureError('noteInvalidPhoto');
  if(file.size>12*1024*1024)throw new MeasureError('noteTooLarge');
  let bitmap;
  try{
    bitmap=await createImageBitmap(file);
    if(bitmap.width*bitmap.height>50000000)throw new MeasureError('noteTooLarge');
    const factor=Math.min(1,1600/Math.max(bitmap.width,bitmap.height)),canvas=document.createElement('canvas');
    canvas.width=Math.max(1,Math.round(bitmap.width*factor));canvas.height=Math.max(1,Math.round(bitmap.height*factor));
    const context=canvas.getContext('2d');context.fillStyle='white';context.fillRect(0,0,canvas.width,canvas.height);context.drawImage(bitmap,0,0,canvas.width,canvas.height);
    const blob=await new Promise(resolve=>canvas.toBlob(resolve,'image/jpeg',.85));if(!blob)throw new MeasureError('noteInvalidPhoto');
    return new Uint8Array(await blob.arrayBuffer());
  }catch(error){throw error?.code?error:new MeasureError('noteInvalidPhoto');}finally{bitmap?.close();}
}
export function photoData(assets,notes) {
  const result={};
  for(const note of notes||[])if(note.photo&&assets[note.photo]){
    const bytes=assets[note.photo];if(bytes.length>5*1024*1024)throw new MeasureError('noteTooLarge');
    let binary='';for(let i=0;i<bytes.length;i+=8192)binary+=String.fromCharCode(...bytes.subarray(i,i+8192));
    const type=note.photo.endsWith('.png')?'png':note.photo.endsWith('.webp')?'webp':'jpeg';result[note.photo]=`data:image/${type};base64,${btoa(binary)}`;
  }
  return result;
}
