import { ReconstructionClient, reconstructionInput } from './reconstruction.js';
import { download } from './files.js';

export class ReconstructionPanel {
  constructor({ t, openArtifact, getToken, setToken }) {
    this.t = t; this.openArtifact = openArtifact; this.getToken = getToken; this.setToken = setToken;
    this.$ = id => document.getElementById(id); this.jobs = []; this.busy = false; this.generation = 0;
    this.$('reconstruction-connect').onclick = () => this.run(async () => {
      const generation = this.generation, client = new ReconstructionClient(this.$('reconstruction-token').value.trim());
      const capabilities = await client.capabilities(), jobs = await client.list();
      if (generation !== this.generation) return;
      this.client = client; this.capabilities = capabilities; this.jobs = jobs; this.setToken(client.token);
    });
    this.$('reconstruction-token').oninput = () => { ++this.generation; clearTimeout(this.timer); this.client = undefined; this.capabilities = undefined; this.jobs = []; this.refresh(); };
    this.$('reconstruction-refresh').onclick = () => this.run(async () => { const client = this.client, generation = this.generation, capabilities = await client.capabilities(); if (generation !== this.generation) return; this.capabilities = capabilities; await this.list(); });
    this.$('reconstruction-mode').onchange = () => this.refresh();
    this.$('photo-form').onsubmit = event => { event.preventDefault(); this.run(async () => {
      if (!this.modeAvailable()) throw { code: 'workerUnavailable' };
      const client = this.client, generation = this.generation, { blob, inputType } = await reconstructionInput(this.$('photo-input').files);
      if (generation !== this.generation) return;
      if (inputType === 'video' && !this.capabilities?.video?.available) throw { code: 'workerUnavailable' };
      await client.submit(blob, this.$('reconstruction-mode').value, this.$('reconstruction-name').value, { inputType, profile:this.$('reconstruction-profile').value });
      this.$('photo-input').value = ''; await this.list();
    }); };
    this.$('reconstruction-dialog').addEventListener('close', () => clearTimeout(this.timer));
  }
  disconnect() { ++this.generation; clearTimeout(this.timer); this.client = undefined; this.capabilities = undefined; this.jobs = []; this.$('reconstruction-token').value = ''; this.refresh(); }
  async open() {
    this.$('reconstruction-token').value = this.getToken() || '';
    if (this.client?.token !== this.$('reconstruction-token').value.trim()) { this.client = undefined; this.capabilities = undefined; this.jobs = []; }
    this.$('reconstruction-feedback').textContent = ''; this.$('reconstruction-dialog').showModal();
    this.enabled = false; this.refresh();
    try { this.enabled = (await (await fetch('./config.json')).json()).reconstructionEnabled === true; }
    catch { /* Static hosting supports local splats but no photo worker. */ }
    this.refresh(); if (this.enabled && this.client) await this.run(() => this.list());
  }
  modeAvailable() { return !!this.capabilities?.modes.find(mode => mode.id === this.$('reconstruction-mode').value)?.available; }
  async run(action) {
    if (this.busy) return;
    this.busy = true; clearTimeout(this.timer); this.$('reconstruction-feedback').textContent = this.t('working'); this.refresh();
    try { await action(); this.$('reconstruction-feedback').textContent = ''; }
    catch (error) { this.$('reconstruction-feedback').textContent = `${this.t(error.code || 'networkError')}${error.status ? ` (${error.status})` : ''}`; }
    finally { this.busy = false; this.refresh(); this.schedule(); }
  }
  async list() { const generation = this.generation, client = this.client, jobs = await client.list(); if (generation === this.generation && client === this.client) this.jobs = jobs; }
  schedule() {
    clearTimeout(this.timer);
    if (this.$('reconstruction-dialog').open && this.client && this.jobs.some(job => ['queued','running'].includes(job.status))) this.timer = setTimeout(() => this.run(() => this.list()), 5000);
  }
  refresh() {
    const t = this.t, dialog = this.$('reconstruction-dialog'); dialog.setAttribute('aria-busy', String(this.busy));
    this.$('reconstruction-disabled').hidden = !!this.enabled;
    this.$('reconstruction-progress').hidden = !this.busy;
    this.$('reconstruction-connect').disabled = !this.enabled || this.busy || this.$('reconstruction-token').value.trim().length < 32;
    this.$('reconstruction-refresh').disabled = !this.client || this.busy;
    this.$('reconstruction-submit').disabled = !this.client || !this.modeAvailable() || this.busy;
    for (const id of ['reconstruction-token','reconstruction-name','reconstruction-mode','reconstruction-profile','photo-input']) this.$(id).disabled = this.busy;
    const capabilities = this.$('reconstruction-capabilities'); capabilities.replaceChildren();
    for (const mode of this.capabilities?.modes || []) {
      const item = document.createElement('p'); item.className = 'privacy';
      item.textContent = `${t(mode.id === 'mesh' ? 'photoMesh' : 'photoSplat')} · ${mode.engine} · ${t(mode.available ? 'workerAvailable' : 'workerUnavailable')}`;
      capabilities.append(item);
    }
    if (this.capabilities?.video) {
      const item = document.createElement('p'); item.className = 'privacy';
      item.textContent = `${t('videoInput')} · ${t(this.capabilities.video.available ? 'workerAvailable' : 'workerUnavailable')}`;
      capabilities.append(item);
    }
    const list = this.$('reconstruction-jobs'); list.replaceChildren();
    for (const job of this.jobs) {
      const item = document.createElement('li'), heading = document.createElement('strong'), state = document.createElement('p');
      heading.textContent = job.name; state.textContent = `${t('job' + job.status[0].toUpperCase() + job.status.slice(1))} · ${t(job.mode === 'mesh' ? 'photoMesh' : 'photoSplat')}`;
      item.append(heading, state);
      if (job.status === 'failed' && job.error) { const error = document.createElement('p'); error.className = 'privacy'; error.textContent = String(typeof job.error === 'object' ? job.error.message || job.error.code || '' : job.error).slice(0, 500); item.append(error); }
      if (['queued','running'].includes(job.status)) {
        const cancel = document.createElement('button'); cancel.textContent = t('cancel'); cancel.disabled = this.busy; cancel.onclick = () => this.run(async () => { await this.client.cancel(job.id); await this.list(); }); item.append(cancel);
      }
      if (job.status === 'complete') {
        const actions = document.createElement('div'); actions.className = 'job-artifacts';
        for (const artifact of job.artifacts) {
          const button = document.createElement('button'); button.textContent = `${t('download')}: ${artifact.name}`; button.disabled = this.busy;
          button.onclick = () => this.run(async () => download(await this.client.artifact(job, artifact.name), artifact.name)); actions.append(button);
        }
        const open = document.createElement('button'), name = job.mode === 'splat' ? 'splat.ply' : 'mesh.zip'; open.className = 'primary'; open.textContent = t('open'); open.disabled = this.busy;
        open.onclick = () => this.run(async () => { const blob = await this.client.artifact(job, name); dialog.close(); await this.openArtifact(new File([blob], name), job); });
        actions.append(open); item.append(actions);
      }
      list.append(item);
    }
  }
}
