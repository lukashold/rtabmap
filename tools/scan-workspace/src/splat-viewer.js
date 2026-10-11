import { PerspectiveCamera, Vector3, WebGLRenderer } from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { Viewer, SceneFormat, RenderMode, SceneRevealMode } from '@mkkellogg/gaussian-splats-3d';
import { splatSubjectBounds } from './splat-focus.js';

// External renderer/camera/controls keep this subview isolated from measurement
// coordinates, keyboard shortcuts, global document elements and OAuth headers.
export class SplatViewer {
  constructor(container, onError = () => {}) {
    this.container = container; this.onError = onError;
    this.renderer = new WebGLRenderer({ antialias: false });
    this.renderer.setPixelRatio(Math.min(globalThis.devicePixelRatio || 1, 1.5));
    this.renderer.setClearColor(0x251a40, 1);
    this.renderer.domElement.tabIndex = 0;
    container.append(this.renderer.domElement);
    this.camera = new PerspectiveCamera(50, 1, .01, 1000);
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    try { this.engine = new Viewer({ rootElement: container, renderer: this.renderer, camera: this.camera, selfDrivenMode: false, useBuiltInControls: false, sharedMemoryForWorkers: false, gpuAcceleratedSort: false, integerBasedSort: false, sphericalHarmonicsDegree: 0, renderMode: RenderMode.OnChange, sceneRevealMode: SceneRevealMode.Instant }); }
    catch (error) { this.controls.dispose(); this.renderer.dispose(); this.renderer.forceContextLoss(); this.renderer.domElement.remove(); throw error; }
    this.observer = new ResizeObserver(() => this.resize()); this.observer.observe(container); this.resize();
  }
  resize() {
    if (this.closed) return;
    const { width, height } = this.container.getBoundingClientRect(); if (!width || !height) return;
    this.renderer.setSize(width, height); this.camera.aspect = width / height; this.camera.updateProjectionMatrix(); this.engine.forceRenderNextFrame();
  }
  async load(data) {
    this.data = data;
    this.subjectBounds = undefined;
    const url = URL.createObjectURL(new Blob([data.bytes], { type: 'application/octet-stream' }));
    try {
      await this.engine.addSplatScene(url, { format: SceneFormat.Splat, showLoadingUI: false, progressiveLoad: false, splatAlphaRemovalThreshold: 1 });
      if (this.closed) throw Object.assign(new Error('cancelled'), { code: 'cancelled' });
      this.fit(); this.renderFrame(); this.frame = requestAnimationFrame(() => this.animate());
    } finally { URL.revokeObjectURL(url); }
  }
  fit() {
    if (!this.data || this.closed) return;
    this.fitBounds(this.data.bounds);
  }
  focusSubject() {
    if (!this.data || this.closed) return;
    this.subjectBounds ??= splatSubjectBounds(this.data);
    if (this.subjectBounds) this.fitBounds(this.subjectBounds);
  }
  fitBounds({ min, max }) {
    const center = new Vector3(...min).add(new Vector3(...max)).multiplyScalar(.5);
    const radius = Math.max(new Vector3(...max).sub(new Vector3(...min)).length() / 2, .01), fov = this.camera.fov * Math.PI / 180;
    const distance = radius / Math.sin(Math.min(fov, 2 * Math.atan(Math.tan(fov / 2) * this.camera.aspect)) / 2) * 1.1;
    this.camera.position.copy(center).add(new Vector3(.7,.45,1).normalize().multiplyScalar(distance));
    // Framing can ignore outliers, but the far plane still accommodates the
    // full scene, including Gaussian scales. No data is culled or rewritten.
    const fullCenter = new Vector3(...this.data.bounds.min).add(new Vector3(...this.data.bounds.max)).multiplyScalar(.5);
    const fullRadius = new Vector3(...this.data.bounds.max).sub(new Vector3(...this.data.bounds.min)).length() / 2;
    this.camera.near = radius / 10000; this.camera.far = Math.max(distance + radius * 100, this.camera.position.distanceTo(fullCenter) + fullRadius * 1.1); this.camera.updateProjectionMatrix();
    this.controls.target.copy(center); this.controls.update(); this.engine.forceRenderNextFrame();
  }
  renderFrame() { this.controls.update(); this.engine.update(); if (this.engine.shouldRender()) this.engine.render(); }
  animate() {
    if (this.closed) return;
    try { this.renderFrame(); }
    catch (error) { this.onError(error); return; }
    this.frame = requestAnimationFrame(() => this.animate());
  }
  async dispose() {
    if (this.closed) return; this.closed = true;
    cancelAnimationFrame(this.frame); this.observer.disconnect(); this.controls.dispose();
    try { await this.engine.dispose(); } catch { /* Aborted loads still release the external renderer below. */ }
    this.renderer.dispose(); this.renderer.forceContextLoss(); this.renderer.domElement.remove(); this.data = undefined;
  }
}
