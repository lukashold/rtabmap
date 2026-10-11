export const MAX_SPLATS = 1000000;
export const MAX_SPLAT_BYTES = 200 * 1024 * 1024;
const fail = code => Object.assign(new Error(code), { code });
const fields = ['x', 'y', 'z', 'scale_0', 'scale_1', 'scale_2', 'rot_0', 'rot_1', 'rot_2', 'rot_3', 'opacity', 'f_dc_0', 'f_dc_1', 'f_dc_2'];
const types = { char: [1, 'getInt8'], uchar: [1, 'getUint8'], int8: [1, 'getInt8'], uint8: [1, 'getUint8'], short: [2, 'getInt16'], ushort: [2, 'getUint16'], int16: [2, 'getInt16'], uint16: [2, 'getUint16'], int: [4, 'getInt32'], uint: [4, 'getUint32'], int32: [4, 'getInt32'], uint32: [4, 'getUint32'], float: [4, 'getFloat32'], float32: [4, 'getFloat32'], double: [8, 'getFloat64'], float64: [8, 'getFloat64'] };

export function splatPlyHeader(bytes) {
  const text = new TextDecoder().decode(bytes.subarray(0, 65536));
  if (!text.startsWith('ply\n') && !text.startsWith('ply\r\n')) return null;
  const end = /(?:^|\n)end_header\r?\n/.exec(text);
  if (!end) throw fail('splatInvalid');
  const header = text.slice(0, end.index + end[0].length), properties = [];
  let format, count, element, stride = 0, beforeVertex = false, sawVertex = false;
  for (const line of header.split(/\r?\n/)) {
    const words = line.trim().split(/\s+/);
    if (words[0] === 'format') format = words[1];
    if (words[0] === 'element') {
      element = words[1];
      if (element === 'vertex') { if (sawVertex) throw fail('splatInvalid'); sawVertex = true; count = Number(words[2]); }
      else if (!sawVertex && Number(words[2]) > 0) beforeVertex = true;
    }
    if (words[0] === 'property' && element === 'vertex') {
      properties.push({ name: words.at(-1), type: words[1], offset: stride });
      stride += types[words[1]]?.[0] ?? 0;
    }
  }
  const names = new Set(properties.map(property => property.name));
  if (![...names].some(name => /^(scale_\d+|rot_\d+|f_dc_\d+|packed_(position|rotation)|features_dc|scaling|rotation_re)$/.test(name))) return null;
  if (beforeVertex || !fields.every(name => names.has(name)) || names.size !== properties.length || properties.some(property => !types[property.type]) || !['ascii', 'binary_little_endian'].includes(format) || !Number.isSafeInteger(count) || count < 1) throw fail('splatInvalid');
  if (count > MAX_SPLATS) throw fail('splatLimit');
  return { format, count, properties, stride, offset: new TextEncoder().encode(header).length };
}

function writeSplat(view, bytes, index, position, scale, color, rotation) {
  const offset = index * 32, length = Math.hypot(...rotation);
  if (![...position, ...scale, ...color, ...rotation].every(Number.isFinite) || position.some(value => Math.abs(value) > 1e8) || scale.some(value => value <= 0 || value > 1e6) || !length) throw fail('splatInvalid');
  for (let i = 0; i < 3; i++) { view.setFloat32(offset + i * 4, position[i], true); view.setFloat32(offset + 12 + i * 4, scale[i], true); }
  for (let i = 0; i < 4; i++) { bytes[offset + 24 + i] = Math.max(0, Math.min(255, Math.round(color[i]))); bytes[offset + 28 + i] = Math.max(0, Math.min(255, Math.round(rotation[i] / length * 128 + 128))); }
}

// Canonical .splat preserves anisotropic scales, quaternion and opacity. The
// initial viewer uses the DC/base colour only; higher SH coefficients are not
// rendered. Downloads retain the original file including all its coefficients.
export function decodeSplat(bytes, name) {
  if (!(bytes instanceof Uint8Array) || bytes.byteLength > MAX_SPLAT_BYTES) throw fail('splatLimit');
  let data;
  if (/\.splat$/i.test(name)) {
    if (!bytes.length || bytes.length % 32) throw fail('splatInvalid');
    if (bytes.length / 32 > MAX_SPLATS) throw fail('splatLimit');
    data = bytes;
  } else if (/\.ply$/i.test(name)) {
    const header = splatPlyHeader(bytes); if (!header) throw fail('splatInvalid');
    data = new Uint8Array(header.count * 32); const target = new DataView(data.buffer), source = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    let lines;
    if (header.format === 'ascii') {
      lines = new TextDecoder().decode(bytes.subarray(header.offset)).trim().split(/\r?\n/);
      if (lines.length < header.count) throw fail('splatInvalid');
    } else if (header.offset + header.stride * header.count > bytes.byteLength) throw fail('splatInvalid');
    for (let index = 0; index < header.count; index++) {
      const row = Object.create(null), tokens = lines?.[index].trim().split(/\s+/);
      if (tokens && tokens.length !== header.properties.length) throw fail('splatInvalid');
      header.properties.forEach((property, i) => { row[property.name] = tokens ? Number(tokens[i]) : source[types[property.type][1]](header.offset + index * header.stride + property.offset, true); });
      if (!fields.every(name => Number.isFinite(row[name]))) throw fail('splatInvalid');
      const values = suffix => [0,1,2].map(i => row[`${suffix}_${i}`]);
      writeSplat(target, data, index, [row.x,row.y,row.z], values('scale').map(Math.exp), [...values('f_dc').map(value => (0.5 + 0.28209479177387814 * value) * 255), 255 / (1 + Math.exp(-row.opacity))], [0,1,2,3].map(i => row[`rot_${i}`]));
    }
  } else throw fail('splatInvalid');
  const view = new DataView(data.buffer, data.byteOffset, data.byteLength), min = [Infinity,Infinity,Infinity], max = [-Infinity,-Infinity,-Infinity];
  for (let index = 0; index < data.length; index += 32) {
    let quaternionLength = 0;
    const radius = 3 * Math.max(view.getFloat32(index + 12, true), view.getFloat32(index + 16, true), view.getFloat32(index + 20, true));
    for (let i = 0; i < 3; i++) {
      const position = view.getFloat32(index + i * 4, true), sigma = view.getFloat32(index + 12 + i * 4, true);
      if (!Number.isFinite(position) || Math.abs(position) > 1e8 || !Number.isFinite(sigma) || sigma <= 0 || sigma > 1e6) throw fail('splatInvalid');
      // Rotation may align the largest Gaussian axis with any world axis.
      min[i] = Math.min(min[i], position - radius); max[i] = Math.max(max[i], position + radius);
    }
    for (let i = 0; i < 4; i++) quaternionLength += (data[index + 28 + i] - 128) ** 2;
    if (!quaternionLength) throw fail('splatInvalid');
  }
  return { bytes: data, count: data.length / 32, bounds: { min, max }, original: bytes, name };
}

export async function detectSplatFile(file) {
  if (/\.splat$/i.test(file.name)) return true;
  if (!/\.ply$/i.test(file.name)) return false;
  return !!splatPlyHeader(new Uint8Array(await file.slice(0, 65536).arrayBuffer()));
}

export function syntheticSplatDemo() {
  const points = [];
  for (let x = -15; x <= 15; x++) for (let z = -12; z <= 12; z++) points.push([[x * .1, 0, z * .1], [.06,.02,.06], [133,109,83,235], [1,0,0,0]]);
  for (let x = -15; x <= 15; x++) for (let y = 1; y <= 22; y++) points.push([[x * .1, y * .1, -1.2], [.06,.06,.018], [183,208,196,230], [1,0,0,0]]);
  for (let a = 0; a < 60; a++) for (let y = 0; y <= 14; y++) { const angle = a / 60 * Math.PI * 2; points.push([[Math.cos(angle) * .36, y * .055 + .2, Math.sin(angle) * .36], [.07,.04,.02], [145+Math.round(50*Math.cos(angle)),84,164,210], [Math.cos(angle/2),0,Math.sin(angle/2),0]]); }
  const bytes = new Uint8Array(points.length * 32), view = new DataView(bytes.buffer);
  points.forEach((point, index) => writeSplat(view, bytes, index, ...point));
  return bytes;
}
