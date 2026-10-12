import { zip } from 'fflate';

export const RECONSTRUCTION_LIMIT = 200 * 1024 * 1024;
const idPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const required = { mesh: ['mesh.zip', 'model.ply', 'reconstruction.json'], splat: ['splat.ply', 'cameras.json', 'reconstruction.json'] };
const allowed = { mesh: [...required.mesh, 'cameras.json', 'photos.zip'], splat: [...required.splat, 'photos.zip'] };
const fail = (code, status) => Object.assign(new Error(code), { code, status });
export function validateJob(job) {
  if (!job || !idPattern.test(job.id) || !Object.hasOwn(required, job.mode) || typeof job.name !== 'string' || job.name.length > 200 || !['queued','running','complete','failed','cancelled'].includes(job.status) || !Array.isArray(job.artifacts) || job.artifacts.length > 5) throw fail('reconstructionInvalid');
  const names = new Set();
  for (const artifact of job.artifacts) {
    if (!artifact || !allowed[job.mode].includes(artifact.name) || names.has(artifact.name) || !Number.isSafeInteger(artifact.bytes) || artifact.bytes < 1 || artifact.bytes > RECONSTRUCTION_LIMIT || !/^[0-9a-f]{64}$/.test(artifact.sha256)) throw fail('reconstructionInvalid');
    names.add(artifact.name);
  }
  if (job.status === 'complete' ? required[job.mode].some(name => !names.has(name)) : job.artifacts.length !== 0) throw fail('reconstructionInvalid');
  return job;
}

export class ReconstructionClient {
  constructor(token, fetcher = (...args) => fetch(...args)) { this.token = token; this.fetch = fetcher; }
  async request(path, options = {}) {
    const response = await this.fetch(`./api/reconstruction/${path}`, { ...options, redirect: 'error', headers: { ...options.headers, Authorization: `Bearer ${this.token}` } });
    if (!response.ok) {
      let code; try { code = (await response.json()).error; } catch { /* HTTP status remains useful. */ }
      throw fail(code === 'worker_unavailable' ? 'workerUnavailable' : code === 'too_large' ? 'tooLarge' : code === 'too_few_images' ? 'photoInputHelp' : 'networkError', response.status);
    }
    return response;
  }
  async capabilities() {
    const data = await (await this.request('capabilities')).json();
    if (data?.version !== 1 || !Array.isArray(data.modes) || data.modes.length !== 2 || new Set(data.modes.map(mode => mode?.id)).size !== 2 || data.modes.some(mode => !mode || !Object.hasOwn(required, mode.id) || typeof mode.available !== 'boolean' || typeof mode.engine !== 'string' || mode.engine.length > 200)) throw fail('reconstructionInvalid');
    return data;
  }
  async list() { const data = await (await this.request('jobs')).json(); if (!Array.isArray(data.jobs) || data.jobs.length > 1000) throw fail('reconstructionInvalid'); return data.jobs.map(validateJob); }
  async submit(blob, mode, name, { inputType = 'photos', profile = 'auto' } = {}) {
    if (!Object.hasOwn(required, mode)) throw fail('reconstructionInvalid');
    if (!['photos','video'].includes(inputType) || !['auto','uav'].includes(profile)) throw fail('reconstructionInvalid');
    if (!blob.size || blob.size > RECONSTRUCTION_LIMIT) throw fail('tooLarge');
    const cleanName = name.trim().replace(/[\x00-\x1f\x7f/\\]/g, '_').slice(0, 120) || 'Scan';
    const query = new URLSearchParams({ mode, name: cleanName });
    if (profile !== 'auto') query.set('profile', profile);
    const contentType = inputType === 'video' ? (/\.mov$/i.test(blob.name || '') ? 'video/quicktime' : 'video/mp4') : 'application/zip';
    return validateJob((await (await this.request(`jobs?${query}`, { method: 'POST', headers: { 'Content-Type': contentType }, body: blob })).json()).job);
  }
  async cancel(id) { if (!idPattern.test(id)) throw fail('reconstructionInvalid'); return validateJob((await (await this.request(`jobs/${id}/cancel`, { method: 'POST' })).json()).job); }
  async artifact(job, name) {
    validateJob(job); if (job.status !== 'complete') throw fail('reconstructionInvalid');
    const item = job.artifacts.find(artifact => artifact.name === name); if (!item) throw fail('reconstructionInvalid');
    // Ignore server-provided URLs: the Bearer token never leaves this origin.
    const response = await this.request(`jobs/${job.id}/artifacts/${encodeURIComponent(name)}`);
    if (Number(response.headers.get('Content-Length')) > RECONSTRUCTION_LIMIT) throw fail('tooLarge');
    const reader = response.body.getReader(), chunks = []; let total = 0;
    while (true) { const { done, value } = await reader.read(); if (done) break; total += value.length; if (total > item.bytes || total > RECONSTRUCTION_LIMIT) { await reader.cancel(); throw fail('reconstructionInvalid'); } chunks.push(value); }
    if (total !== item.bytes) throw fail('reconstructionInvalid');
    const blob = new Blob(chunks), hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', await blob.arrayBuffer())), byte => byte.toString(16).padStart(2, '0')).join('');
    if (hash !== item.sha256) throw fail('reconstructionInvalid');
    return blob;
  }
}

export async function reconstructionInput(input) {
  const files = Array.from(input);
  if (files.length === 1 && /\.(mp4|mov)$/i.test(files[0].name)) {
    const file = files[0];
    if (!file.size || file.size > RECONSTRUCTION_LIMIT) throw fail('tooLarge');
    return { blob: file, inputType: 'video' };
  }
  return { blob: await photoArchive(files), inputType: 'photos' };
}

export async function photoArchive(input) {
  const files = Array.from(input);
  if (!files.length) throw fail('photoInputHelp');
  if (files.reduce((sum, file) => sum + file.size, 0) > RECONSTRUCTION_LIMIT) throw fail('tooLarge');
  if (files.length === 1 && /\.zip$/i.test(files[0].name)) return files[0];
  if (files.length < 8 || files.length > 250 || files.some(file => !/\.(jpe?g|png|heic|heif)$/i.test(file.name))) throw fail('photoInputHelp');
  const entries = {};
  for (const [index, file] of files.entries()) entries[`Images/photo-${String(index + 1).padStart(4, '0')}${file.name.slice(file.name.lastIndexOf('.')).toLowerCase()}`] = new Uint8Array(await file.arrayBuffer());
  return new Promise((resolve, reject) => zip(entries, { level: 0 }, (error, data) => error ? reject(error) : data.length > RECONSTRUCTION_LIMIT ? reject(fail('tooLarge')) : resolve(new Blob([data], { type: 'application/zip' }))));
}
