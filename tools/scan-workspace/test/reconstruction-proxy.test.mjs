import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer, request } from 'node:http';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createAppServer } from '../server.mjs';
import { createReconstructionProxy } from '../reconstruction-proxy.mjs';

const token = 'reconstruction-test-token-32-characters-long';
const authorization = `Bearer ${token}`;
const id = '134c6a1d-dc64-4384-a0ce-31294a3fe618';
const listen = server => new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const close = server => new Promise(resolve => { server.close(resolve); server.closeAllConnections(); });
async function withProxy(handler, action, limits, readBody = true) {
  const folder = await mkdtemp(join(tmpdir(), 'kantura-proxy-'));
  const site = join(folder, 'site'); await mkdir(site); await writeFile(join(site, 'index.html'), 'Kantura');
  const calls = [];
  const worker = createServer(async (req, res) => {
    const bytes = []; if (readBody) for await (const chunk of req) bytes.push(chunk);
    const call = { path: req.url, method: req.method, headers: req.headers, body: Buffer.concat(bytes) };
    calls.push(call); await handler(call, res); if (!readBody) req.resume();
  });
  await listen(worker);
  const origin = `http://127.0.0.1:${worker.address().port}`;
  const server = createAppServer(site, { token, dataDir: join(folder, 'private'), reconstructionURL: origin, reconstructionLimits: limits });
  await server.storageReady; await listen(server);
  try { await action({ url: `http://127.0.0.1:${server.address().port}`, origin, calls }); }
  finally { await close(server); await close(worker); await rm(folder, { recursive: true, force: true }); }
}
const json = (res, status, value) => { res.writeHead(status, { 'Content-Type': 'application/json' }); res.end(JSON.stringify(value)); };

test('reconstruction transport authenticates before forwarding and keeps the worker origin private', async () => {
  await withProxy((call, res) => json(res, 200, { modes: [] }), async ({ url, calls, origin }) => {
    const config = await (await fetch(`${url}/config.json`)).text();
    assert.equal(JSON.parse(config).reconstructionEnabled, true);
    assert.ok(!config.includes(token) && !config.includes(origin));
    assert.equal((await fetch(`${url}/api/reconstruction/capabilities`)).status, 401);
    assert.equal(calls.length, 0);
    const response = await fetch(`${url}/api/reconstruction/capabilities`, { headers: { authorization } });
    assert.deepEqual(await response.json(), { modes: [] });
    assert.equal(calls[0].headers.authorization, authorization);
    assert.equal(calls[0].path, '/api/reconstruction/capabilities');
  });
});

test('photo ZIP bytes, canonical mode/name and job status pass through without arbitrary commands', async () => {
  const bytes = Buffer.from('PK-test-transport-envelope');
  await withProxy((call, res) => json(res, 202, { job: { id, status: 'queued' } }), async ({ url, calls }) => {
    const response = await fetch(`${url}/api/reconstruction/jobs?name=Test%20room&mode=splat`, { method: 'POST', headers: { authorization, 'Content-Type': 'application/zip' }, body: bytes });
    assert.equal(response.status, 202); assert.equal((await response.json()).job.status, 'queued');
    assert.deepEqual(calls[0].body, bytes);
    assert.equal(Number(calls[0].headers['content-length']), bytes.length);
    assert.equal(calls[0].path, '/api/reconstruction/jobs?mode=splat&name=Test+room');
    for (const path of [`/jobs/${id}`, `/jobs/${id}/cancel`]) {
      const result = await fetch(`${url}/api/reconstruction${path}`, { method: path.endsWith('/cancel') ? 'POST' : 'GET', headers: { authorization } });
      assert.equal(result.status, 202); await result.arrayBuffer();
    }
  });
});

test('invalid proxy routes, upload types, modes, queries and large declared bodies never reach the worker', async () => {
  await withProxy((call, res) => json(res, 200, {}), async ({ url, calls }) => {
    const uploads = [
      ['?mode=unknown&name=Room', 'application/zip', 'x', 400],
      ['?mode=mesh&name=Room&command=whoami', 'application/zip', 'x', 400],
      ['?mode=mesh&mode=splat&name=Room', 'application/zip', 'x', 400],
      ['?mode=mesh&name=../Room', 'application/zip', 'x', 400],
      ['?mode=mesh&name=Room', 'text/plain', 'x', 415],
      ['?mode=mesh&name=Room', 'application/zip', '123456789', 413]
    ];
    for (const [query, type, body, status] of uploads) {
      const response = await fetch(`${url}/api/reconstruction/jobs${query}`, { method: 'POST', headers: { authorization, 'Content-Type': type }, body });
      assert.equal(response.status, status); await response.arrayBuffer();
    }
    for (const path of [`jobs/not-a-uuid`, `jobs/${id}/artifacts/worker.log`, `jobs/${id}/artifacts/input.zip`, 'capabilities?token=secret']) {
      const response = await fetch(`${url}/api/reconstruction/${path}`, { headers: { authorization } });
      assert.ok([400, 404].includes(response.status)); await response.arrayBuffer();
    }
    assert.equal(calls.length, 0);
  }, { maxBytes: 8 });
});

test('an early unavailable worker can refuse an upload without destroying the browser response', async () => {
  await withProxy((call, res) => json(res, 503, { error: 'worker_unavailable' }), async ({ url }) => {
    const response = await fetch(`${url}/api/reconstruction/jobs?mode=mesh&name=Room`, { method: 'POST', headers: { authorization, 'Content-Type': 'application/zip' }, body: Buffer.alloc(1024 * 1024, 0x5a) });
    assert.equal(response.status, 503);
    assert.equal((await response.json()).error, 'worker_unavailable');
    assert.equal(await (await fetch(`${url}/health`)).text(), 'ok');
  }, undefined, false);
});

test('chunked uploads without a length are rejected before contacting the reconstruction worker', async () => {
  await withProxy((call, res) => json(res, 200, {}), async ({ url, calls }) => {
    const status = await new Promise((resolve, reject) => {
      const req = request(`${url}/api/reconstruction/jobs?mode=mesh&name=Room`, { method: 'POST', headers: { authorization, 'Content-Type': 'application/zip', 'Transfer-Encoding': 'chunked' } }, res => { res.resume(); res.once('end', () => resolve(res.statusCode)); });
      req.on('error', reject); req.write('partial bytes'); req.end();
    });
    assert.equal(status, 411); assert.equal(calls.length, 0);
  });
});

test('worker redirects never send a token or request to their destination', async () => {
  let destinationRequests = 0;
  const destination = createServer((req, res) => { destinationRequests++; res.end('unexpected'); });
  await listen(destination);
  try {
    await withProxy((call, res) => { res.writeHead(302, { Location: `http://127.0.0.1:${destination.address().port}/token-target` }); res.end(); }, async ({ url }) => {
      const response = await fetch(`${url}/api/reconstruction/jobs`, { headers: { authorization } });
      assert.equal(response.status, 502); assert.equal((await response.json()).error, 'reconstruction_unavailable');
      assert.equal(destinationRequests, 0);
    });
  } finally { await close(destination); }
});

test('artifact attachments preserve bytes and size but discard worker cookies and HTML content type', async () => {
  const bytes = Buffer.from('a real transport payload');
  await withProxy((call, res) => { res.writeHead(200, { 'Content-Type': 'text/html', 'Set-Cookie': 'secret=value', 'Content-Length': bytes.length }); res.end(bytes); }, async ({ url }) => {
    const response = await fetch(`${url}/api/reconstruction/jobs/${id}/artifacts/splat.ply`, { headers: { authorization } });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('set-cookie'), null);
    assert.equal(response.headers.get('content-type'), 'application/octet-stream');
    assert.match(response.headers.get('content-disposition'), /splat\.ply/);
    assert.deepEqual(Buffer.from(await response.arrayBuffer()), bytes);
  });
});

test('oversized worker output and timeouts fail explicitly rather than becoming completed jobs', async () => {
  await withProxy((call, res) => { res.writeHead(200, { 'Content-Length': 99 }); res.end('large'); }, async ({ url }) => {
    const response = await fetch(`${url}/api/reconstruction/jobs/${id}/artifacts/mesh.zip`, { headers: { authorization } });
    assert.equal(response.status, 502); assert.equal((await response.json()).error, 'reconstruction_result_too_large');
  }, { maxBytes: 8 });
  await withProxy(() => {}, async ({ url }) => {
    const response = await fetch(`${url}/api/reconstruction/capabilities`, { headers: { authorization } });
    assert.equal(response.status, 502); assert.equal((await response.json()).error, 'reconstruction_unavailable');
  }, { timeoutMs: 30 });
});

test('worker configuration rejects credentials, paths and non-HTTP transports', () => {
  for (const origin of ['file:///etc/passwd', 'http://secret@example.com/', 'http://localhost/worker', 'http://localhost/?token=x', 'http://localhost/#fragment']) assert.throws(() => createReconstructionProxy(origin, token));
  assert.throws(() => createReconstructionProxy('http://localhost/', 'short'));
});

test('video MIME/profile and selected-photo download pass only through fixed authenticated routes',async()=>{
  await withProxy((call,res)=>json(res,202,{job:{id,status:'queued'}}),async({url,calls})=>{
    const response=await fetch(`${url}/api/reconstruction/jobs?mode=mesh&name=Video&profile=uav`,{method:'POST',headers:{authorization,'Content-Type':'video/mp4'},body:Buffer.from('original-video')});
    assert.equal(response.status,202); await response.arrayBuffer();
    assert.equal(calls[0].headers['content-type'],'video/mp4');assert.match(calls[0].path,/profile=uav$/);
    const photos=await fetch(`${url}/api/reconstruction/jobs/${id}/artifacts/photos.zip`,{headers:{authorization}});
    assert.equal(photos.status,202); assert.equal(photos.headers.get('content-type'),'application/zip'); await photos.arrayBuffer();
    const refused=await fetch(`${url}/api/reconstruction/jobs?mode=mesh&name=Video&profile=../../secret`,{method:'POST',headers:{authorization,'Content-Type':'video/mp4'},body:'x'});
    assert.equal(refused.status,400); await refused.arrayBuffer();assert.equal(calls.length,2);
  });
});
