import { createServer } from 'node:http';
import { createReadStream } from 'node:fs';
import { access, constants, lstat, mkdir, open, readFile, readdir, realpath, rename, rm, writeFile } from 'node:fs/promises';
import { createHash, randomUUID, timingSafeEqual } from 'node:crypto';
import { pipeline } from 'node:stream/promises';
import { resolve, extname, sep, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const MAX_PROJECT_BYTES = 200 * 1024 * 1024;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const digest = value => createHash('sha256').update(value).digest();
const validName = value => typeof value === 'string' && value.trim().length > 0 && value.length <= 120 && !/[\x00-\x1f\x7f/\\]/.test(value);
const json = (res, status, body) => { res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' }); res.end(JSON.stringify(body)); };
const fail = (status, code) => Object.assign(new Error(code), { status, code });

// Archives are stored without extracting them. Verify the ZIP envelope; the viewer
// validates the project manifest, assets, paths and decompressed size when opened.
function isZip(first, tail, size) {
  if (size < 26 || first.length < 4 || first.readUInt32LE(0) !== 0x04034b50) return false;
  for (let offset = tail.length - 22; offset >= 0; offset--) {
    if (tail.readUInt32LE(offset) === 0x06054b50 && offset + 22 + tail.readUInt16LE(offset + 20) === tail.length) return true;
  }
  return false;
}

export function createAppServer(root = fileURLToPath(new URL('./dist', import.meta.url)), options = {}) {
  const base = resolve(root);
  const dataDir = options.dataDir ?? process.env.DATA_DIR ?? '';
  const token = options.token ?? process.env.SERVER_TOKEN ?? '';
  const maxBytes = options.maxBytes ?? MAX_PROJECT_BYTES;
  const enabled = Boolean(dataDir && token);
  if (enabled && token.length < 32) throw new Error('SERVER_TOKEN must contain at least 32 characters. Generate a random token.');
  if (!Number.isSafeInteger(maxBytes) || maxBytes <= 0 || maxBytes > MAX_PROJECT_BYTES) throw new Error('Invalid project size limit');
  const tokenDigest = digest(token);
  let storageBase;
  let uploadActive = false;
  const storageReady = enabled ? (async () => {
    await mkdir(resolve(dataDir), { recursive: true, mode: 0o700 });
    storageBase = await realpath(resolve(dataDir));
    const publicBase = await realpath(base).catch(() => base);
    if (storageBase === publicBase || storageBase.startsWith(publicBase + sep)) throw new Error('DATA_DIR must be outside the public viewer directory.');
    await access(storageBase, constants.R_OK | constants.W_OK);
  })() : Promise.resolve();
  storageReady.catch(() => {});

  async function readProject(id) {
    if (!uuidPattern.test(id)) throw fail(404, 'not_found');
    const directory = join(storageBase, id);
    try {
      if (!(await lstat(directory)).isDirectory()) throw fail(404, 'not_found');
      const [metadataStat, archiveStat] = await Promise.all([lstat(join(directory, 'project.json')), lstat(join(directory, 'scan.zip'))]);
      if (!metadataStat.isFile() || metadataStat.size > 2048 || !archiveStat.isFile()) throw fail(404, 'not_found');
      const item = JSON.parse(await readFile(join(directory, 'project.json'), 'utf8'));
      if (!item || typeof item !== 'object' || item.id !== id || !validName(item.name) || !Number.isFinite(Date.parse(item.createdAt)) || item.size !== archiveStat.size || item.size > maxBytes) throw fail(404, 'not_found');
      return { id, name: item.name, createdAt: item.createdAt, size: item.size };
    } catch (error) {
      if (error.code === 'ENOENT' || error instanceof SyntaxError) throw fail(404, 'not_found');
      throw error;
    }
  }

  async function receiveProject(req, res, url) {
    const name = url.searchParams.get('name')?.trim();
    if (!validName(name)) throw fail(400, 'invalid_name');
    if (!['application/zip', 'application/octet-stream'].includes((req.headers['content-type'] || '').split(';')[0].toLowerCase())) throw fail(415, 'invalid_archive');
    const declared = req.headers['content-length'];
    if (declared && (!/^\d+$/.test(declared) || Number(declared) > maxBytes)) throw fail(413, 'too_large');
    if (uploadActive) throw fail(409, 'busy');
    uploadActive = true;
    const id = randomUUID();
    const temporary = join(storageBase, `.upload-${id}`);
    let handle, savedProject;
    try {
      await mkdir(temporary, { mode: 0o700 });
      handle = await open(join(temporary, 'scan.zip'), 'wx', 0o600);
      let size = 0;
      let first = Buffer.alloc(0);
      let tail = Buffer.alloc(0);
      for await (const chunk of req.iterator({ destroyOnReturn: false })) {
        size += chunk.length;
        if (size > maxBytes) throw fail(413, 'too_large');
        if (first.length < 4) first = Buffer.concat([first, chunk.subarray(0, 4 - first.length)]);
        tail = Buffer.concat([tail, chunk]).subarray(-65557);
        await handle.writeFile(chunk);
      }
      if (!isZip(first, tail, size)) throw fail(400, 'invalid_archive');
      await handle.sync();
      await handle.close(); handle = undefined;
      const project = { id, name, createdAt: new Date().toISOString(), size };
      await writeFile(join(temporary, 'project.json'), JSON.stringify(project), { flag: 'wx', mode: 0o600 });
      await rename(temporary, join(storageBase, id));
      savedProject = project;
    } finally {
      if (handle) await handle.close().catch(() => {});
      await rm(temporary, { recursive: true, force: true }).catch(() => {});
      uploadActive = false;
    }
    // A completed response must mean the next sequential upload can begin.
    // Await cleanup and release the guard before notifying the client.
    json(res, 201, { project: savedProject });
  }

  const server = createServer(async (req, res) => {
    res.setHeader('X-Content-Type-Options', 'nosniff');
    // Google Identity Services needs the origin referrer on localhost HTTP.
    res.setHeader('Referrer-Policy', 'no-referrer-when-downgrade');
    res.setHeader('Cache-Control', 'no-store');
    // Popup OAuth needs opener communication. No global COOP isolation.
    let path;
    let url;
    try { url = new URL(req.url, 'http://localhost'); path = decodeURIComponent(url.pathname); }
    catch { res.writeHead(404).end(); return; }
    if (path === '/api' || path.startsWith('/api/')) {
      try {
        if (!enabled) throw fail(503, 'disabled');
        const authorization = req.headers.authorization || '';
        if (!authorization.startsWith('Bearer ') || !timingSafeEqual(digest(authorization.slice(7)), tokenDigest)) throw fail(401, 'unauthorized');
        await storageReady;
        if (path === '/api/projects') {
          if (req.method === 'POST') { await receiveProject(req, res, url); return; }
          if (req.method !== 'GET') throw fail(405, 'method_not_allowed');
          const projects = [];
          for (const entry of await readdir(storageBase, { withFileTypes: true })) {
            if (entry.isDirectory() && uuidPattern.test(entry.name)) {
              try { projects.push(await readProject(entry.name)); }
              catch (error) { if (error.status !== 404) throw error; }
            }
          }
          projects.sort((a, b) => b.createdAt.localeCompare(a.createdAt) || a.id.localeCompare(b.id));
          json(res, 200, { projects }); return;
        }
        const match = /^\/api\/projects\/([^/]+)$/.exec(path);
        if (!match || !uuidPattern.test(match[1])) throw fail(404, 'not_found');
        if (req.method !== 'GET') throw fail(405, 'method_not_allowed');
        const project = await readProject(match[1]);
        res.writeHead(200, { 'Content-Type': 'application/zip', 'Content-Length': project.size, 'Content-Disposition': `attachment; filename="${project.id}.rtabmeasure.zip"` });
        await pipeline(createReadStream(join(storageBase, project.id, 'scan.zip')), res);
      } catch (error) {
        if (res.headersSent) { res.destroy(); return; }
        if (req.method === 'POST') { res.setHeader('Connection', 'close'); req.resume(); }
        if (error.status === 401) res.setHeader('WWW-Authenticate', 'Bearer realm="KANTURA project library"');
        json(res, error.status || 500, { error: error.status ? error.code : 'storage_error' });
      }
      return;
    }
    if (!['GET', 'HEAD'].includes(req.method)) { res.writeHead(405).end(); return; }
    try {
      if (path === '/health') { res.setHeader('Content-Type', 'text/plain'); res.end(req.method === 'HEAD' ? undefined : 'ok'); return; }
      if (path === '/config.json') {
        res.setHeader('Content-Type', 'application/json');
        res.end(req.method === 'HEAD' ? undefined : JSON.stringify({ googleClientId: process.env.GOOGLE_CLIENT_ID || '', microsoftClientId: process.env.MICROSOFT_CLIENT_ID || '', serverEnabled: enabled })); return;
      }
      const file = resolve(base, '.' + (path === '/' ? '/index.html' : path));
      if (!file.startsWith(base + sep)) { res.writeHead(404).end(); return; }
      const [canonicalBase, canonicalFile] = await Promise.all([realpath(base), realpath(file)]);
      if (!canonicalFile.startsWith(canonicalBase + sep) || !(await lstat(canonicalFile)).isFile()) { res.writeHead(404).end(); return; }
      const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8', '.json': 'application/json', '.map': 'application/json', '.txt': 'text/plain', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.ico': 'image/x-icon' };
      res.setHeader('Content-Type', types[extname(file)] || 'application/octet-stream');
      res.end(req.method === 'HEAD' ? undefined : await readFile(canonicalFile));
    } catch { res.writeHead(404).end(); }
  });
  server.requestTimeout = 120000;
  server.headersTimeout = 15000;
  server.storageReady = storageReady;
  return server;
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const port = Number(process.env.PORT || 4173);
  const host = process.env.HOST || '127.0.0.1';
  const server = createAppServer();
  await server.storageReady;
  server.listen(port, host, () => console.log(`Local: http://${host}:${port}`));
}
