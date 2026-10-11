import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, readFile, readdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { zipSync, strToU8 } from 'fflate';
import { createAppServer, MAX_PROJECT_BYTES } from '../server.mjs';

const token = 'a-random-test-token-of-at-least-32-characters';
const authorization = `Bearer ${token}`;
const archive = zipSync({ 'rtab-measure.json': strToU8('{"version":1}'), 'room.obj': strToU8('v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3') });
async function withServer(options, fn) {
  const temporary = await mkdtemp(join(tmpdir(), 'kantura-server-'));
  const root = join(temporary, 'site');
  await mkdir(root);
  await writeFile(join(root, 'index.html'), '<h1>KANTURA</h1>');
  const dataDir = join(temporary, 'private-projects');
  const server = createAppServer(root, { dataDir, token, ...options });
  await server.storageReady;
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const url = `http://127.0.0.1:${server.address().port}`;
  try { await fn({ url, root, dataDir }); }
  finally { await new Promise(resolve => server.close(resolve)); await rm(temporary, { recursive: true, force: true }); }
}
const upload = (url, name = 'Wohnzimmer', body = archive) => fetch(`${url}/api/projects?name=${encodeURIComponent(name)}`, { method: 'POST', headers: { authorization, 'Content-Type': 'application/zip' }, body });

test('static mode explicitly disables the library and keeps the public viewer usable', async () => {
  await withServer({ token: '' }, async ({ url }) => {
    assert.equal(await (await fetch(url)).text(), '<h1>KANTURA</h1>');
    const configuration = await (await fetch(`${url}/config.json`)).json();
    assert.equal(configuration.serverEnabled, false);
    assert.equal((await fetch(`${url}/api/projects`)).status, 503);
    assert.equal(configuration.serverToken, undefined);
  });
});

test('list, upload and download require Bearer authorization; config never exposes the secret', async () => {
  await withServer({}, async ({ url, dataDir }) => {
    const configuration = await (await fetch(`${url}/config.json`)).text();
    assert.equal(JSON.parse(configuration).serverEnabled, true);
    assert.ok(!configuration.includes(token));
    assert.ok(!configuration.includes(dataDir));
    for (const method of ['GET', 'POST']) {
      const response = await fetch(`${url}/api/projects?name=room&token=${encodeURIComponent(token)}`, { method, ...(method === 'POST' ? { body: archive } : {}) });
      assert.equal(response.status, 401);
      assert.equal((await response.json()).error, 'unauthorized');
    }
    assert.equal((await fetch(`${url}/api/projects`, { headers: { authorization: 'Bearer wrong' } })).status, 401);
    assert.equal((await fetch(`${url}/api/projects`, { headers: { authorization: `Basic ${token}` } })).status, 401);
    assert.deepEqual(await (await fetch(`${url}/api/projects`, { headers: { authorization } })).json(), { projects: [] });
  });
});

test('immutable snapshots round-trip exactly, list metadata only, and survive a new server instance', async () => {
  await withServer({}, async ({ url, root, dataDir }) => {
    const created = await upload(url, 'Küche / Tor');
    assert.equal(created.status, 400);
    const response = await upload(url, 'Küche & Tor');
    assert.equal(response.status, 201);
    const { project } = await response.json();
    assert.match(project.id, /^[0-9a-f-]{36}$/);
    assert.equal(project.name, 'Küche & Tor');
    assert.equal(project.size, archive.length);
    assert.ok(Number.isFinite(Date.parse(project.createdAt)));
    const second = await (await upload(url, 'Küche & Tor')).json();
    assert.notEqual(project.id, second.project.id);
    const list = await (await fetch(`${url}/api/projects`, { headers: { authorization } })).json();
    assert.equal(list.projects.length, 2);
    assert.deepEqual(list.projects.find(p => p.id === project.id), project);
    assert.equal((await fetch(`${url}/api/projects/${project.id}`)).status, 401);
    const downloaded = await fetch(`${url}/api/projects/${project.id}`, { headers: { authorization } });
    assert.equal(downloaded.headers.get('content-type'), 'application/zip');
    assert.equal(downloaded.headers.get('cache-control'), 'no-store');
    assert.ok(!downloaded.headers.has('access-control-allow-origin'));
    assert.deepEqual(new Uint8Array(await downloaded.arrayBuffer()), archive);
    assert.deepEqual(new Uint8Array(await readFile(join(dataDir, project.id, 'scan.zip'))), archive);
    const next = createAppServer(root, { dataDir, token });
    await new Promise(resolve => next.listen(0, '127.0.0.1', resolve));
    try { assert.equal((await (await fetch(`http://127.0.0.1:${next.address().port}/api/projects`, { headers: { authorization } })).json()).projects.length, 2); }
    finally { await new Promise(resolve => next.close(resolve)); }
  });
});

test('bad names, content types and truncated archives leave no partial snapshots', async () => {
  await withServer({}, async ({ url, dataDir }) => {
    for (const name of ['', '../room', 'room\\secret', 'room\nheader', 'x'.repeat(121)]) assert.equal((await upload(url, name)).status, 400);
    assert.equal((await fetch(`${url}/api/projects?name=room`, { method: 'POST', headers: { authorization, 'Content-Type': 'text/plain' }, body: archive })).status, 415);
    for (const body of [new Uint8Array(), strToU8('not a zip'), archive.subarray(0, archive.length - 2)]) assert.equal((await upload(url, 'room', body)).status, 400);
    assert.deepEqual(await readdir(dataDir), []);
  });
});

test('both declared and chunked uploads enforce the size limit and clean their staging files', async () => {
  assert.equal(MAX_PROJECT_BYTES, 200 * 1024 * 1024);
  await withServer({ maxBytes: 1024 }, async ({ url, dataDir }) => {
    assert.equal((await upload(url, 'large', new Uint8Array(1025))).status, 413);
    async function* chunks() { yield new Uint8Array(700); yield new Uint8Array(700); }
    const streamed = await fetch(`${url}/api/projects?name=large`, { method: 'POST', headers: { authorization, 'Content-Type': 'application/zip' }, body: chunks(), duplex: 'half' });
    assert.equal(streamed.status, 413);
    assert.equal((await streamed.json()).error, 'too_large');
    assert.deepEqual(await readdir(dataDir), []);
    assert.equal((await upload(url)).status, 201);
  });
});

test('traversal, unknown IDs and unsupported methods cannot reach project files', async () => {
  await withServer({}, async ({ url }) => {
    for (const path of ['/api/projects/%2e%2e%2findex.html', '/api/projects/%2e%2e%5cindex.html', '/api/projects/not-a-uuid', '/api/projects/00000000-0000-4000-8000-000000000000', '/%2e%2e%2fserver.mjs', '/%2e%2e%5cserver.mjs']) {
      assert.equal((await fetch(url + path, { headers: { authorization } })).status, 404, path);
    }
    assert.equal((await fetch(`${url}/api/projects`, { method: 'DELETE', headers: { authorization } })).status, 405);
    const { project } = await (await upload(url)).json();
    assert.equal((await fetch(`${url}/api/projects/${project.id}`, { method: 'POST', headers: { authorization } })).status, 405);
    assert.equal((await fetch(`${url}/api/projects/${project.id}/scan.zip`, { headers: { authorization } })).status, 404);
  });
});

test('an enabled library refuses weak shared tokens', () => {
  assert.throws(() => createAppServer('.', { dataDir: './data', token: 'short' }), /at least 32/);
});

test('private archive storage cannot be placed inside the public viewer directory', async () => {
  const root = await mkdtemp(join(tmpdir(), 'kantura-private-'));
  try {
    const server = createAppServer(root, { dataDir: join(root, 'public-data'), token });
    await assert.rejects(server.storageReady, /outside the public/);
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('static SVG and bitmap assets have usable image content types with nosniff enabled', async () => {
  await withServer({}, async ({ url, root }) => {
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"><path d="M0 0L1 1"/></svg>';
    await writeFile(join(root, 'kantura.svg'), svg);
    await writeFile(join(root, 'preview.png'), new Uint8Array([137, 80, 78, 71]));
    const image = await fetch(`${url}/kantura.svg`);
    assert.equal(image.headers.get('content-type'), 'image/svg+xml');
    assert.equal(image.headers.get('x-content-type-options'), 'nosniff');
    assert.equal(await image.text(), svg);
    assert.equal((await fetch(`${url}/preview.png`)).headers.get('content-type'), 'image/png');
  });
});
