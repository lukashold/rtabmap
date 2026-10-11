import { Readable, Transform } from 'node:stream';
import { pipeline } from 'node:stream/promises';

export const RECONSTRUCTION_MAX_BYTES = 200 * 1024 * 1024;
const uuid = '[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}';
const artifactNames = ['mesh.zip', 'model.ply', 'splat.ply', 'cameras.json', 'reconstruction.json'];
const route = new RegExp(`^/api/reconstruction/jobs/(${uuid})(?:/(cancel)|/artifacts/(${artifactNames.map(name => name.replace('.', '\\.')).join('|')}))?$`);
const fail = (status, code) => Object.assign(new Error(code), { status, code });

// Only the operator configures this origin. User input never selects a host,
// redirects never receive a token, and private worker paths are not forwarded.
export function createReconstructionProxy(origin, token, options = {}) {
  if (!origin) return null;
  let base;
  try { base = new URL(origin); } catch { throw new Error('Invalid RECONSTRUCTION_URL'); }
  if (!['http:', 'https:'].includes(base.protocol) || base.username || base.password || base.search || base.hash || base.pathname !== '/') throw new Error('RECONSTRUCTION_URL must be an HTTP(S) origin without credentials or a path');
  if (typeof token !== 'string' || token.length < 32) throw new Error('Reconstruction requires a strong SERVER_TOKEN');
  const maxBytes = options.maxBytes ?? RECONSTRUCTION_MAX_BYTES;
  const timeoutMs = options.timeoutMs ?? 120000;
  if (!Number.isSafeInteger(maxBytes) || maxBytes < 1 || maxBytes > RECONSTRUCTION_MAX_BYTES || !Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 120000) throw new Error('Invalid reconstruction proxy limits');

  return async function proxy(req, res, path, requestURL) {
    const match = route.exec(path);
    const isJobs = path === '/api/reconstruction/jobs';
    const isCapabilities = path === '/api/reconstruction/capabilities';
    if (!isJobs && !isCapabilities && !match) throw fail(404, 'not_found');
    const upload = isJobs && req.method === 'POST';
    const cancel = Boolean(match?.[2]) && req.method === 'POST';
    if (!upload && !cancel && req.method !== 'GET') throw fail(405, 'method_not_allowed');
    if (match?.[2] && !cancel) throw fail(405, 'method_not_allowed');

    const upstream = new URL(path, base);
    const headers = { authorization: `Bearer ${token}`, accept: 'application/json' };
    if (upload) {
      const keys = [...requestURL.searchParams.keys()];
      if (keys.some(key => !['mode', 'name'].includes(key)) || new Set(keys).size !== keys.length) throw fail(400, 'invalid_request');
      const mode = requestURL.searchParams.get('mode');
      const name = requestURL.searchParams.get('name')?.trim();
      if (!['mesh', 'splat'].includes(mode) || !name || name.length > 120 || /[\x00-\x1f\x7f/\\]/.test(name)) throw fail(400, 'invalid_request');
      if (!['application/zip', 'application/octet-stream'].includes((req.headers['content-type'] || '').split(';')[0].toLowerCase())) throw fail(415, 'invalid_archive');
      if (req.headers['content-length'] === undefined) throw fail(411, 'length_required');
      if (!/^\d+$/.test(req.headers['content-length']) || Number(req.headers['content-length']) > maxBytes) throw fail(413, 'too_large');
      upstream.searchParams.set('mode', mode);
      upstream.searchParams.set('name', name);
      headers['content-type'] = 'application/zip';
      headers['content-length'] = req.headers['content-length'];
    } else if ([...requestURL.searchParams].length) throw fail(400, 'invalid_request');
    if (cancel && (req.headers['transfer-encoding'] || Number(req.headers['content-length'] || 0) !== 0)) throw fail(400, 'invalid_request');

    const controller = new AbortController();
    let uploadError;
    const abort = () => controller.abort();
    const onClose = () => { if (!res.writableEnded) abort(); };
    const timer = setTimeout(abort, timeoutMs);
    timer.unref();
    req.once('aborted', abort);
    res.once('close', onClose);
    async function* body() {
      let size = 0;
      // An early worker refusal must not destroy the browser socket when fetch
      // cancels this iterator. Drain unused input in finally instead.
      for await (const bytes of req.iterator({ destroyOnReturn: false })) {
        size += bytes.length;
        if (size > maxBytes) { uploadError = fail(413, 'too_large'); throw uploadError; }
        yield bytes;
      }
    }
    try {
      const response = await fetch(upstream, {
        method: req.method, headers, redirect: 'manual', signal: controller.signal,
        ...(upload ? { body: body(), duplex: 'half' } : {})
      });
      if (response.status >= 300 && response.status < 400) { await response.body?.cancel(); throw fail(502, 'reconstruction_unavailable'); }
      const artifact = match?.[3];
      const responseLimit = artifact && response.ok ? maxBytes : 1024 * 1024;
      const length = response.headers.get('content-length');
      if (length !== null && (!/^\d+$/.test(length) || Number(length) > responseLimit)) { await response.body?.cancel(); throw fail(502, 'reconstruction_result_too_large'); }
      const contentType = artifact && response.ok ? artifact.endsWith('.zip') ? 'application/zip' : artifact.endsWith('.json') ? 'application/json; charset=utf-8' : 'application/octet-stream' : 'application/json; charset=utf-8';
      res.setHeader('Content-Type', contentType);
      if (length !== null) res.setHeader('Content-Length', length);
      if (artifact && response.ok) res.setHeader('Content-Disposition', `attachment; filename="${artifact}"`);
      res.writeHead(response.status);
      if (!response.body) { res.end(); return; }
      let received = 0;
      const limit = new Transform({ transform(bytes, encoding, callback) {
        received += bytes.length;
        callback(received > responseLimit ? fail(502, 'reconstruction_result_too_large') : null, bytes);
      } });
      await pipeline(Readable.fromWeb(response.body), limit, res);
    } catch (error) {
      if (uploadError) throw uploadError;
      if (error.status) throw error;
      throw fail(502, 'reconstruction_unavailable');
    } finally {
      clearTimeout(timer);
      req.off('aborted', abort);
      res.off('close', onClose);
      if (upload && !req.complete && !req.destroyed) req.resume();
    }
  };
}
