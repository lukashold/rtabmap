export const MAX_SUBJECT_SAMPLES = 8192;

// Camera framing only: read the canonical 32-byte records without modifying
// positions, Gaussian sizes, the original file, or the full scene bounds.
// Evenly spaced samples make the memory/sort cost independent of scene size.
export function splatSubjectBounds(data) {
  const bytes = data?.bytes, count = data?.count;
  if (!(bytes instanceof Uint8Array) || !Number.isSafeInteger(count) || count < 1 || bytes.byteLength !== count * 32) return null;
  const size = Math.min(count, MAX_SUBJECT_SAMPLES);
  const axes = Array.from({ length: 3 }, () => new Float64Array(size));
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let valid = 0;
  for (let sample = 0; sample < size; sample++) {
    const index = size === 1 ? 0 : Math.floor(sample * (count - 1) / (size - 1)), offset = index * 32;
    const x = view.getFloat32(offset, true), y = view.getFloat32(offset + 4, true), z = view.getFloat32(offset + 8, true);
    if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(z)) continue;
    axes[0][valid] = x; axes[1][valid] = y; axes[2][valid++] = z;
  }
  if (!valid) return null;
  const quantile = (axis, fraction) => {
    const position = (valid - 1) * fraction, lower = Math.floor(position), upper = Math.ceil(position);
    return axis[lower] + (axis[upper] - axis[lower]) * (position - lower);
  };
  const sorted = axes.map(axis => axis.subarray(0, valid).sort());
  return { min: sorted.map(axis => quantile(axis, .05)), max: sorted.map(axis => quantile(axis, .95)), sampleCount: valid };
}
