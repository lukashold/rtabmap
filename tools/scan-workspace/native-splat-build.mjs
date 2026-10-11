import { build } from 'esbuild';
import { mkdir, copyFile, writeFile, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';

const source = dirname(fileURLToPath(import.meta.url));
const destination = resolve(source, '../../app/ios/RTABMapApp/SplatViewerAssets');
await mkdir(destination, { recursive: true });
await build({ absWorkingDir: source, entryPoints: ['src/native-splat-page.js'], bundle: true, format: 'iife', outfile: resolve(destination, 'viewer.js'), minify: true, target: ['safari17'], legalComments: 'inline', sourcemap: false });
await copyFile(resolve(source, 'public/native-splat.html'), resolve(destination, 'index.html'));
const notices = [
  ['RTAB-Map / Kantura', '../../LICENSE'],
  ['Three.js (MIT) — https://github.com/mrdoob/three.js', 'node_modules/three/LICENSE'],
  ['GaussianSplats3D 0.4.7 (MIT) — https://github.com/mkkellogg/GaussianSplats3D', 'node_modules/@mkkellogg/gaussian-splats-3d/LICENSE'],
];
const provenance = 'Generated offline preview from tools/scan-workspace/src/native-splat-page.js, native-splat-data.js, splat-data.js, splat-focus.js and splat-viewer.js. Renderer dependencies are bundled locally; no CDN, SharedArrayBuffer or network scene requests. Source and package versions: tools/scan-workspace/package.json / pnpm-lock.yaml. This viewer uses base (DC) colour and does not render higher-order spherical harmonics.\n\n';
await writeFile(resolve(destination, 'THIRD-PARTY-LICENSES.txt'), provenance + (await Promise.all(notices.map(async ([name, path]) => `${name}\n${'='.repeat(name.length)}\n${await readFile(resolve(source, path), 'utf8')}`))).join('\n\n'));
console.log(`Built offline WKWebView assets: ${destination}`);
