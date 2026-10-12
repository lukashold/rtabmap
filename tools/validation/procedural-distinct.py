"""Second authored synthetic fixture: same cube/orbit, distinct static textures.

Keep procedural-capture.py and its difficult periodic fixture unchanged. This
fixture separates capture texture ambiguity from other reconstruction failures;
success here never replaces or improves the old baseline's reported result.
"""
import argparse
import io
import json
import math
from pathlib import Path
import zipfile

import numpy as np
from PIL import Image, ImageDraw


def face_textures():
    textures = []
    for face in range(6):
        rng = np.random.default_rng(41081 + face * 3571)
        base = rng.integers(45, 210, (19 + face, 23 + face, 3), dtype=np.uint8)
        image = Image.fromarray(base).resize((512, 512), Image.Resampling.BICUBIC)
        draw = ImageDraw.Draw(image)
        # Independent layouts, sizes, orientations and intensities per face.
        # No common checkerboard, square-border lattice or repeated text grid.
        for index in range(170):
            x, y = rng.integers(0, 512, 2)
            width, height = rng.integers(6, 65, 2)
            color = tuple(int(v) for v in rng.integers(8, 248, 3))
            if index % 3 == 0:
                draw.ellipse((x, y, x + width, y + height), fill=color)
            elif index % 3 == 1:
                draw.polygon([(x, y), (x + width, y + height // 3), (x + width // 3, y + height)], fill=color)
            else:
                draw.line((x, y, x + width, y - height), fill=color, width=int(rng.integers(2, 9)))
        textures.append(np.asarray(image))
    return textures


def lattice(ix, iz, seed):
    # Coordinate hashing makes the field static in world space, without a
    # repeated tile texture. All operations are deliberately unsigned/bounded.
    a = np.asarray(ix, dtype=np.int64).astype(np.uint64)
    b = np.asarray(iz, dtype=np.int64).astype(np.uint64)
    value = ((a * np.uint64(73856093)) ^ (b * np.uint64(19349663)) ^ np.uint64(seed)) & np.uint64(0xffffffff)
    value ^= value >> np.uint64(13)
    value = (value * np.uint64(1274126177)) & np.uint64(0xffffffff)
    value ^= value >> np.uint64(16)
    return (value & np.uint64(65535)).astype(float) / 65535


def ground_rgb(x, z):
    channels = []
    for channel in range(3):
        result = np.zeros_like(x, dtype=float)
        for frequency, weight in [(0.9, 0.50), (3.7, 0.32), (9.1, 0.18)]:
            px, pz = x * frequency, z * frequency
            ix, iz = np.floor(px), np.floor(pz)
            ax, az = px - ix, pz - iz
            ax, az = ax * ax * (3 - 2 * ax), az * az * (3 - 2 * az)
            seed = 19247 + channel * 8123 + int(frequency * 100)
            low = lattice(ix, iz, seed) * (1 - ax) + lattice(ix + 1, iz, seed) * ax
            high = lattice(ix, iz + 1, seed) * (1 - ax) + lattice(ix + 1, iz + 1, seed) * ax
            result += weight * (low * (1 - az) + high * az)
        channels.append(np.clip((result - 0.5) * 390 + 128, 8, 248))
    return np.stack(channels, axis=-1).astype(np.uint8)


def render_view(index, count, size, textures):
    yy, xx = np.mgrid[0:size, 0:size]
    focal = 0.5 * size / math.tan(math.radians(55) / 2)
    camera_rays = np.stack(((xx + .5 - size / 2) / focal, -(yy + .5 - size / 2) / focal, np.ones_like(xx)), axis=-1)
    angle = index * 2 * math.pi / count
    eye = np.array([3.8 * math.cos(angle), 1.3 + .2 * math.sin(angle * 2), 3.8 * math.sin(angle)])
    forward = -eye / np.linalg.norm(eye)
    right = np.cross(forward, [0., 1., 0.]); right /= np.linalg.norm(right)
    up = np.cross(right, forward)
    rays = camera_rays[..., 0, None] * right + camera_rays[..., 1, None] * up + camera_rays[..., 2, None] * forward
    safe = np.where(np.abs(rays) < 1e-12, 1e-12, rays)
    ta, tb = (-1 - eye) / safe, (1 - eye) / safe
    entering, exiting = np.minimum(ta, tb), np.maximum(ta, tb)
    near, far = entering.max(axis=-1), exiting.min(axis=-1)
    cube = (far >= near) & (near > 0)
    points = eye + rays * near[..., None]
    axis = np.argmax(entering, axis=-1)
    sign = np.take_along_axis(points, axis[..., None], axis=-1)[..., 0] > 0
    face_ids = axis * 2 + sign
    result = np.full((size, size, 3), (168, 188, 210), dtype=np.uint8)
    ground_t = (-1.08 - eye[1]) / safe[..., 1]
    ground = (ground_t > 0) & (~cube | (ground_t < near))
    ground_points = eye + rays * ground_t[..., None]
    result[ground] = ground_rgb(ground_points[..., 0][ground], ground_points[..., 2][ground])
    for face in range(6):
        mask = cube & ~ground & (face_ids == face)
        first, second = [i for i in range(3) if i != face // 2]
        u = np.clip(((points[..., first] + 1) * 255.5).astype(int), 0, 511)
        v = np.clip(((1 - points[..., second]) * 255.5).astype(int), 0, 511)
        result[mask] = textures[face][v[mask], u[mask]]
    reference = {'sourceFile': f'Images/view-{index:03d}.jpg', 'preparedFile': f'frame_{index+1:05d}.jpg', 'position': eye.tolist(), 'rotation': np.column_stack((right, -up, forward)).tolist()}
    return result, reference, focal


def write_member(archive, name, payload):
    member = zipfile.ZipInfo(name, date_time=(2026, 10, 12, 0, 0, 0))
    member.compress_type = zipfile.ZIP_DEFLATED
    archive.writestr(member, payload)


def generate(output, truth_path=None, size=384, count=32):
    if not 128 <= size <= 1024 or not 16 <= count <= 80 or count % 2:
        raise ValueError('Use 128–1024 pixels and an even count between 16 and 80')
    output = Path(output)
    if truth_path is not None and output.resolve() == Path(truth_path).resolve():
        raise ValueError('Ground truth must be outside the photo ZIP')
    output.parent.mkdir(parents=True, exist_ok=True)
    textures, cameras, records = face_textures(), [], []
    with zipfile.ZipFile(output, 'w') as archive:
        for index in range(count):
            pixels, camera, focal = render_view(index, count, size, textures)
            buffer = io.BytesIO()
            Image.fromarray(pixels).save(buffer, format='JPEG', quality=95)
            payload = buffer.getvalue()
            write_member(archive, camera['sourceFile'], payload)
            records.append({'file': camera['sourceFile'], 'bytes': len(payload)})
            cameras.append(camera)
        manifest = {'format': 'kantura-photo-dataset', 'version': 1, 'id': 'kantura-synthetic-distinct-cube-v1', 'name': 'Synthetic cube with distinct textures — independent fixture', 'createdAt': '2026-10-12T00:00:00Z', 'source': 'kantura-synthetic-validation-distinct', 'captureMode': 'object', 'scaleStatus': 'unverified', 'images': records}
        write_member(archive, 'manifest.json', json.dumps(manifest, ensure_ascii=False).encode('utf-8'))
    truth = {'format': 'kantura-synthetic-truth', 'version': 1, 'fixture': 'distinct-cube-v1', 'cameraConvention': 'camera-to-world: right, down, forward', 'fieldAccuracyValidated': False, 'cameras': cameras, 'imageSize': [size, size], 'focalPixels': focal, 'cubeBounds': [[-1, -1, -1], [1, 1, 1]], 'groundHeight': -1.08, 'opposingPairs': [{'first': cameras[i]['preparedFile'], 'second': cameras[i + count // 2]['preparedFile']} for i in range(count // 2)]}
    if truth_path is not None:
        truth_path = Path(truth_path)
        truth_path.parent.mkdir(parents=True, exist_ok=True)
        truth_path.write_text(json.dumps(truth, indent=2), encoding='utf-8')
    return truth


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--truth', type=Path)
    parser.add_argument('--size', type=int, default=384)
    parser.add_argument('--count', type=int, default=32)
    arguments = parser.parse_args()
    generate(arguments.output, arguments.truth, arguments.size, arguments.count)
    print(f'Created {arguments.count} distinct-texture views; ground truth is outside the ZIP.')
