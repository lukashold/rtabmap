import { decodeSplat } from './splat-data.js';
export const NATIVE_SPLAT_LIMIT = 32 * 1024 * 1024;
const fail = code => Object.assign(new Error(code), { code });

// WKWebView receives JSON data, never executable filename/base64 fragments.
// Bound the encoded string before allocating its decoded binary copy.
export function decodeNativeSplatMessage(message) {
  if (!message || typeof message !== 'object' || typeof message.base64 !== 'string' || typeof message.name !== 'string' || message.name.length > 255 || !/\.(splat|ply)$/i.test(message.name) || /[\x00-\x1f\x7f/\\]/.test(message.name)) throw fail('splatInvalid');
  const base64 = message.base64;
  if (base64.length > Math.ceil(NATIVE_SPLAT_LIMIT / 3) * 4) throw fail('splatLimit');
  const padding = base64.endsWith('==') ? 2 : base64.endsWith('=') ? 1 : 0;
  if (!base64.length || base64.length % 4 || /[^A-Za-z0-9+/=]/.test(base64) || base64.slice(0, base64.length - padding).includes('=')) throw fail('splatInvalid');
  if (base64.length / 4 * 3 - padding > NATIVE_SPLAT_LIMIT) throw fail('splatLimit');
  let binary;
  try { binary = atob(base64); } catch { throw fail('splatInvalid'); }
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return decodeSplat(bytes, message.name);
}
