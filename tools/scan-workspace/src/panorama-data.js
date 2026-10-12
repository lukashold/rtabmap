// Local equirectangular still images only. Header limits precede browser decode.
export const MAX_PANORAMA_BYTES = 32 * 1024 * 1024;
export const MAX_PANORAMA_WIDTH = 8192;
export const MAX_PANORAMA_VIEWS = 8;
export const PANORAMA_HEADER_BYTES = 1024 * 1024;
const fail = code => Object.assign(new Error(code), { code });

export function panoramaDimensions(width, height) {
  if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width < 256 || height < 128 || width > MAX_PANORAMA_WIDTH || height > MAX_PANORAMA_WIDTH / 2) throw fail('dimensions');
  if (width !== height * 2) throw fail('aspect');
  return { width, height };
}

export function panoramaHeader(bytes) {
  if (!(bytes instanceof Uint8Array)) throw fail('format');
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const png = [137,80,78,71,13,10,26,10];
  if (bytes.length >= 33 && png.every((v, i) => bytes[i] === v)) {
    if (view.getUint32(8) !== 13 || String.fromCharCode(...bytes.subarray(12,16)) !== 'IHDR') throw fail('format');
    return { ...panoramaDimensions(view.getUint32(16), view.getUint32(20)), mime: 'image/png', format: 'PNG' };
  }
  if (bytes.length < 4 || bytes[0] !== 255 || bytes[1] !== 216) throw fail('format');
  const sof = new Set([192,193,194,195,197,198,199,201,202,203,205,206,207]);
  let offset = 2;
  while (offset < bytes.length) {
    if (bytes[offset++] !== 255) throw fail('format');
    while (offset < bytes.length && bytes[offset] === 255) offset++;
    if (offset >= bytes.length) throw fail('format');
    const marker = bytes[offset++];
    if (marker === 218 || marker === 217 || marker === 0) throw fail('format');
    if (marker === 1 || marker >= 208 && marker <= 215) continue;
    if (offset + 2 > bytes.length) throw fail('format');
    const length = view.getUint16(offset);
    if (length < 2 || offset + length > bytes.length) throw fail('format');
    if (sof.has(marker)) {
      if (length < 8) throw fail('format');
      return { ...panoramaDimensions(view.getUint16(offset + 5), view.getUint16(offset + 3)), mime: 'image/jpeg', format: 'JPEG' };
    }
    offset += length;
  }
  throw fail('format');
}

export async function inspectPanoramaFile(file) {
  if (!file || typeof file.slice !== 'function' || !Number.isSafeInteger(file.size) || !file.size || file.size > MAX_PANORAMA_BYTES) throw fail('size');
  if (!/\.(?:jpe?g|png)$/i.test(file.name || '')) throw fail('format');
  return panoramaHeader(new Uint8Array(await file.slice(0, PANORAMA_HEADER_BYTES).arrayBuffer()));
}

export function normalizePanoramaView({ yaw = 0, pitch = 0, fov = 75 } = {}) {
  if (![yaw, pitch, fov].every(Number.isFinite)) throw fail('view');
  return { yaw: ((yaw + 180) % 360 + 360) % 360 - 180, pitch: Math.max(-85, Math.min(85, pitch)), fov: Math.max(35, Math.min(100, fov)) };
}

export function panoramaDirection(view) {
  const { yaw, pitch } = normalizePanoramaView(view), a = yaw * Math.PI / 180, b = pitch * Math.PI / 180;
  return [Math.sin(a) * Math.cos(b), Math.sin(b), -Math.cos(a) * Math.cos(b)];
}

export async function decodePanoramaFile(file, { signal } = {}) {
  const metadata = await inspectPanoramaFile(file);
  if (signal?.aborted) throw fail('cancelled');
  const image = new Image();
  image.decoding = 'async';
  const url = URL.createObjectURL(file);
  const abort = () => { image.src = ''; };
  signal?.addEventListener('abort', abort, { once: true });
  try {
    image.src = url;
    await image.decode();
    if (signal?.aborted) throw fail('cancelled');
    panoramaDimensions(image.naturalWidth, image.naturalHeight);
    if (image.naturalWidth !== metadata.width || image.naturalHeight !== metadata.height) throw fail('aspect');
    return { image, metadata, dispose() { image.src = ''; } };
  } catch (error) {
    image.src = '';
    throw signal?.aborted ? fail('cancelled') : (error.code ? error : fail('decode'));
  } finally {
    signal?.removeEventListener('abort', abort);
    URL.revokeObjectURL(url);
  }
}

// Generated here from geometric bands and a grid. No captured/private imagery.
export async function syntheticPanoramaFile(label = 'Synthetic panorama') {
  const canvas = document.createElement('canvas');
  canvas.width = 2048; canvas.height = 1024;
  const context = canvas.getContext('2d');
  if (!context) throw fail('decode');
  const sky = context.createLinearGradient(0, 0, 0, 1024);
  sky.addColorStop(0, '#163247'); sky.addColorStop(.5, '#90c1cb'); sky.addColorStop(.501, '#506553'); sky.addColorStop(1, '#152e24');
  context.fillStyle = sky; context.fillRect(0, 0, 2048, 1024);
  context.strokeStyle = '#ffffff44'; context.lineWidth = 2;
  for (let x = 0; x <= 2048; x += 128) { context.beginPath(); context.moveTo(x, 0); context.lineTo(x, 1024); context.stroke(); }
  for (let y = 128; y < 1024; y += 128) { context.beginPath(); context.moveTo(0, y); context.lineTo(2048, y); context.stroke(); }
  context.font = 'bold 44px sans-serif'; context.textAlign = 'center'; context.textBaseline = 'middle';
  for (let i = 0; i < 4; i++) {
    const x = 256 + i * 512;
    context.fillStyle = ['#e6a452', '#9dcdb3', '#e5daca', '#bbacde'][i];
    context.fillRect(x - 140, 390, 280, 250);
    context.fillStyle = '#182a31'; context.fillText(String(i + 1), x, 500);
  }
  context.fillStyle = '#152936'; context.fillRect(644, 250, 760, 84);
  context.fillStyle = '#ffffff'; context.font = '32px sans-serif'; context.fillText(label, 1024, 292, 720);
  const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/png'));
  canvas.width = canvas.height = 1;
  if (!blob) throw fail('decode');
  return new File([blob], 'kantura-synthetic-panorama.png', { type: 'image/png' });
}
