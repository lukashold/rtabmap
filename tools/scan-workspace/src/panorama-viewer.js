import { Scene, PerspectiveCamera, WebGLRenderer, SphereGeometry, MeshBasicMaterial, Mesh, Texture, SRGBColorSpace } from 'three';
import { normalizePanoramaView, panoramaDirection } from './panorama-data.js';

// Fixed optical centre: gestures change viewing direction/FOV, never position.
export class PanoramaViewer {
  constructor(container, { label, onError = () => {}, onViewChange = () => {} } = {}) {
    this.container = container; this.onError = onError; this.onViewChange = onViewChange;
    this.view = normalizePanoramaView(); this.pointers = new Map(); this.listeners = [];
    this.renderer = new WebGLRenderer({ antialias: true });
    this.renderer.setPixelRatio(Math.min(globalThis.devicePixelRatio || 1, 2));
    this.renderer.setClearColor(0x10252d);
    this.scene = new Scene(); this.camera = new PerspectiveCamera(75, 1, .1, 20);
    this.geometry = new SphereGeometry(10, 64, 32);
    this.geometry.scale(-1, 1, 1); this.geometry.rotateY(-Math.PI / 2);
    this.material = new MeshBasicMaterial({ color: 0xffffff });
    this.mesh = new Mesh(this.geometry, this.material); this.scene.add(this.mesh); this.mesh.visible = false;
    this.canvas = this.renderer.domElement;
    this.canvas.tabIndex = 0; this.canvas.setAttribute('role', 'img'); this.canvas.setAttribute('aria-label', label || '360°');
    this.canvas.style.cssText = 'display:block;width:100%;height:100%;touch-action:none;outline-offset:-4px;';
    container.append(this.canvas);
    const listen = (name, fn, options) => { this.canvas.addEventListener(name, fn, options); this.listeners.push(() => this.canvas.removeEventListener(name, fn, options)); };
    const distance = () => { const values = [...this.pointers.values()]; return values.length === 2 ? Math.hypot(values[0].x - values[1].x, values[0].y - values[1].y) : 0; };
    listen('pointerdown', event => {
      if (event.pointerType === 'mouse' && event.button !== 0) return;
      this.canvas.focus({ preventScroll: true }); this.canvas.setPointerCapture(event.pointerId);
      this.pointers.set(event.pointerId, { x: event.clientX, y: event.clientY }); this.pinchDistance = distance();
    });
    listen('pointermove', event => {
      const previous = this.pointers.get(event.pointerId); if (!previous) return;
      this.pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
      if (this.pointers.size === 1) this.setView({ yaw: this.view.yaw - (event.clientX - previous.x) * .16, pitch: this.view.pitch + (event.clientY - previous.y) * .16 });
      else if (this.pointers.size === 2) { const next = distance(); if (this.pinchDistance > 0 && next > 0) this.setView({ fov: this.view.fov * this.pinchDistance / next }); this.pinchDistance = next; }
    });
    const release = event => { this.pointers.delete(event.pointerId); this.pinchDistance = distance(); };
    listen('pointerup', release); listen('pointercancel', release); listen('lostpointercapture', release);
    listen('wheel', event => { event.preventDefault(); this.setView({ fov: this.view.fov + Math.sign(event.deltaY) * 3 }); }, { passive: false });
    listen('keydown', event => {
      const actions = { ArrowLeft: () => this.setView({ yaw: this.view.yaw - 5 }), ArrowRight: () => this.setView({ yaw: this.view.yaw + 5 }), ArrowUp: () => this.setView({ pitch: this.view.pitch + 5 }), ArrowDown: () => this.setView({ pitch: this.view.pitch - 5 }), '+': () => this.zoom(-5), '=': () => this.zoom(-5), '-': () => this.zoom(5), Home: () => this.reset() };
      if (actions[event.key]) { event.preventDefault(); event.stopPropagation(); actions[event.key](); }
    });
    listen('webglcontextlost', event => { event.preventDefault(); if (!this.closed) this.onError(Object.assign(new Error('webgl'), { code: 'webgl' })); });
    this.observer = new ResizeObserver(() => this.resize()); this.observer.observe(container); this.resize();
  }
  setView(change) { if (this.closed) return; this.view = normalizePanoramaView({ ...this.view, ...change }); this.render(); this.onViewChange(this.view); }
  zoom(delta) { this.setView({ fov: this.view.fov + delta }); }
  reset() { this.setView({ yaw: 0, pitch: 0, fov: 75 }); }
  load(decoded) {
    if (this.closed) { decoded.dispose(); return; }
    const texture = new Texture(decoded.image); texture.colorSpace = SRGBColorSpace; texture.needsUpdate = true;
    this.material.map?.dispose(); this.decoded?.dispose(); this.decoded = decoded;
    this.material.map = texture; this.material.needsUpdate = true; this.mesh.visible = true; this.reset();
  }
  resize() {
    if (this.closed) return;
    const { width, height } = this.container.getBoundingClientRect(); if (width < 1 || height < 1) return;
    this.renderer.setSize(width, height, false); this.camera.aspect = width / height; this.camera.updateProjectionMatrix(); this.render();
  }
  render() {
    if (this.closed) return;
    try { this.camera.position.set(0, 0, 0); this.camera.fov = this.view.fov; this.camera.updateProjectionMatrix(); this.camera.lookAt(...panoramaDirection(this.view)); this.renderer.render(this.scene, this.camera); }
    catch (error) { this.onError(Object.assign(error, { code: 'webgl' })); }
  }
  dispose() {
    if (this.closed) return; this.closed = true;
    this.observer.disconnect(); this.listeners.forEach(remove => remove()); this.pointers.clear();
    this.material.map?.dispose(); this.material.dispose(); this.geometry.dispose(); this.decoded?.dispose();
    this.renderer.dispose(); this.renderer.forceContextLoss(); this.canvas.remove(); this.decoded = undefined;
  }
}
