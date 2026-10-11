import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createAppServer } from '../server.mjs';
import { guide } from '../src/i18n.js';
import { extraLocales, supportedLanguages } from '../locales/index.js';

// Transport fixtures only: byte ranges must work without decoding or checking in
// a media binary. Distinct bytes make off-by-one and suffix errors observable.
const video = Buffer.from(Array.from({ length: 256 }, (_, index) => index));
const captions = 'WEBVTT\n\n00:00.000 --> 00:02.000\nKüche · 测量 · Room\n';
async function withMediaServer(run) {
  const root = await mkdtemp(join(tmpdir(), 'kantura-video-test-'));
  const server = createAppServer(root, { dataDir: '', token: '' });
  try {
    await Promise.all([
      writeFile(join(root, 'demo.mp4'), video),
      writeFile(join(root, 'empty.mp4'), Buffer.alloc(0)),
      writeFile(join(root, 'demo.vtt'), captions)
    ]);
    await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
    await run(`http://127.0.0.1:${server.address().port}`);
  } finally {
    if (server.listening) await new Promise(resolve => server.close(resolve));
    await rm(root, { recursive: true, force: true });
  }
}
const bodyBytes = async response => Buffer.from(await response.arrayBuffer());

test('MP4 delivery preserves the full bytes and declares video type, length and range support', async () => {
  await withMediaServer(async url => {
    const response = await fetch(`${url}/demo.mp4`);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('content-type'), 'video/mp4');
    assert.equal(response.headers.get('content-length'), String(video.length));
    assert.equal(response.headers.get('accept-ranges'), 'bytes');
    assert.equal(response.headers.get('content-range'), null);
    assert.equal(response.headers.get('x-content-type-options'), 'nosniff');
    assert.deepEqual(await bodyBytes(response), video);
  });
});

test('MP4 byte ranges include both endpoints and support open-ended, suffix and clamped requests', async () => {
  await withMediaServer(async url => {
    const ranges = [
      ['bytes=0-0', 0, 0],
      ['bytes=8-31', 8, 31],
      ['bytes=250-', 250, 255],
      ['bytes=-16', 240, 255],
      ['bytes=250-999', 250, 255],
      ['bytes=-999', 0, 255]
    ];
    for (const [range, start, end] of ranges) {
      const response = await fetch(`${url}/demo.mp4`, { headers: { Range: range } });
      assert.equal(response.status, 206, range);
      assert.equal(response.headers.get('content-type'), 'video/mp4', range);
      assert.equal(response.headers.get('accept-ranges'), 'bytes', range);
      assert.equal(response.headers.get('content-range'), `bytes ${start}-${end}/${video.length}`, range);
      assert.equal(response.headers.get('content-length'), String(end - start + 1), range);
      assert.deepEqual(await bodyBytes(response), video.subarray(start, end + 1), range);
    }
  });
});

test('MP4 HEAD returns the same metadata without sending a response body', async () => {
  await withMediaServer(async url => {
    const response = await fetch(`${url}/demo.mp4`, { method: 'HEAD' });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('content-type'), 'video/mp4');
    assert.equal(response.headers.get('content-length'), String(video.length));
    assert.equal(response.headers.get('accept-ranges'), 'bytes');
    assert.equal(response.headers.get('content-range'), null);
    assert.equal((await bodyBytes(response)).length, 0);
    const empty = await fetch(`${url}/empty.mp4`);
    assert.equal(empty.status, 200);
    assert.equal(empty.headers.get('content-length'), '0');
    assert.equal((await bodyBytes(empty)).length, 0);
  });
});

test('unsatisfiable or unsupported MP4 ranges return 416 with the complete resource length', async () => {
  await withMediaServer(async url => {
    for (const range of ['bytes=256-', 'bytes=50-49', 'bytes=-0', 'bytes=-', 'bytes=abc-def', 'bytes=0-1,4-5', 'items=0-1', 'bytes=9007199254740992-']) {
      const response = await fetch(`${url}/demo.mp4`, { headers: { Range: range } });
      assert.equal(response.status, 416, range);
      assert.equal(response.headers.get('content-range'), `bytes */${video.length}`, range);
      assert.equal((await bodyBytes(response)).length, 0, range);
    }
    const empty = await fetch(`${url}/empty.mp4`, { headers: { Range: 'bytes=0-0' } });
    assert.equal(empty.status, 416);
    assert.equal(empty.headers.get('content-range'), 'bytes */0');
    assert.equal((await bodyBytes(empty)).length, 0);
  });
});

test('WebVTT captions retain UTF-8 text and the browser subtitle MIME type', async () => {
  await withMediaServer(async url => {
    const response = await fetch(`${url}/demo.vtt`);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('content-type'), 'text/vtt; charset=utf-8');
    assert.equal(await response.text(), captions);
    const head = await fetch(`${url}/demo.vtt`, { method: 'HEAD' });
    assert.equal(head.status, 200);
    assert.equal(head.headers.get('content-type'), 'text/vtt; charset=utf-8');
    assert.equal(await head.text(), '');
  });
});

test('video scripts cover all fifteen guide languages with the complete narrated workflow', async () => {
  const scripts = JSON.parse(await readFile(new URL('../public/videos/scripts.json', import.meta.url), 'utf8'));
  assert.equal(scripts.version, 1);
  assert.deepEqual(Object.keys(scripts.languages).sort(), Object.keys(guide).sort());
  assert.deepEqual(Object.keys(scripts.languages).sort(), [...supportedLanguages].sort());
  assert.equal(Object.keys(scripts.languages).length, 15);
  const sceneIds = ['start', 'capture', 'organize', 'inspect', 'measure', 'photos', 'share', 'transport'];
  const requiredText = (value, label) => {
    assert.equal(typeof value, 'string', label);
    assert.ok(value.trim().length > 0, label);
    assert.doesNotMatch(value, /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/, label);
  };
  for (const [language, script] of Object.entries(scripts.languages)) {
    if (extraLocales[language]) assert.deepEqual(script, extraLocales[language].video, `${language}: video script matches its locale pack`);
    for (const key of ['title', 'description']) requiredText(script[key], `${language}/${key}`);
    assert.deepEqual(script.scenes.map(scene => scene.id), sceneIds, `${language}: chapter order`);
    for (const scene of script.scenes) {
      for (const key of ['title', 'caption', 'narration']) requiredText(scene[key], `${language}/${scene.id}/${key}`);
      // Cue separators or injected timestamps would split a generated VTT/SRT cue.
      assert.doesNotMatch(scene.caption, /-->|\r|\n\s*\n/, `${language}/${scene.id}: subtitle cue`);
    }
    for (const key of ['videoTitle', 'videoDetail', 'videoUnavailable', 'videoUnavailableDetail']) {
      requiredText(guide[language].roomPlan[key], `${language}/native/${key}`);
    }
  }
});
