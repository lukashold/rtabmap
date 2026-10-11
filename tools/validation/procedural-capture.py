"""Original synthetic multi-view photographs for reconstruction smoke checks.

Ray-cast a textured cube and ground plane. These images are not iPhone scans,
do not validate field accuracy, and contain no third-party photographs/assets.
"""
from pathlib import Path
import argparse, json, math, zipfile
import numpy as np
from PIL import Image, ImageDraw, ImageFont

parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--size', type=int, default=384)
parser.add_argument('--count', type=int, default=32)
args = parser.parse_args()
assert 128 <= args.size <= 1024 and 16 <= args.count <= 80
args.output.parent.mkdir(parents=True, exist_ok=True)
rng = np.random.default_rng(231017)
textures = []
for face in range(6):
    pixels = rng.integers(30, 225, (32, 32, 3), dtype=np.uint8)
    image = Image.fromarray(pixels).resize((512, 512), Image.Resampling.NEAREST)
    draw = ImageDraw.Draw(image)
    for y in range(0, 512, 64):
        for x in range(0, 512, 64):
            draw.rectangle((x+2, y+2, x+60, y+60), outline=(245,245,245), width=2)
            draw.text((x+10, y+22), f'{face}:{x//64},{y//64}', fill=(10,10,10), font=ImageFont.load_default())
    textures.append(np.asarray(image))

size = args.size
yy, xx = np.mgrid[0:size, 0:size]
focal = .5 * size / math.tan(math.radians(55) / 2)
camera_rays = np.stack(((xx+.5-size/2)/focal, -(yy+.5-size/2)/focal, np.ones_like(xx)), axis=-1)
metadata = []
with zipfile.ZipFile(args.output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for index in range(args.count):
        angle = index * 2 * math.pi / args.count
        eye = np.array([3.8 * math.cos(angle), 1.3 + .2 * math.sin(angle * 2), 3.8 * math.sin(angle)])
        target = np.array([0., 0., 0.])
        forward = target-eye; forward /= np.linalg.norm(forward)
        right = np.cross(forward, [0.,1.,0.]); right /= np.linalg.norm(right)
        up = np.cross(right, forward)
        rays = camera_rays[...,0,None]*right + camera_rays[...,1,None]*up + camera_rays[...,2,None]*forward
        safe = np.where(np.abs(rays)<1e-12, 1e-12, rays)
        ta, tb = (-1-eye)/safe, (1-eye)/safe
        entering = np.minimum(ta, tb); exiting = np.maximum(ta, tb)
        near, far = entering.max(axis=-1), exiting.min(axis=-1)
        cube = (far >= near) & (near > 0)
        points = eye + rays * near[...,None]
        axis = np.argmax(entering, axis=-1)
        sign = np.take_along_axis(points, axis[...,None], axis=-1)[...,0] > 0
        face_ids = axis*2+sign
        result = np.full((size,size,3), (168,188,210), dtype=np.uint8)
        # A non-repeating, static background floor gives registration context.
        ground_t = (-1.08-eye[1])/safe[...,1]
        ground = (ground_t > 0) & (~cube | (ground_t < near))
        ground_points = eye + rays * ground_t[...,None]
        tile_x = np.floor(ground_points[...,0]*2).astype(np.int64)
        tile_z = np.floor(ground_points[...,2]*2).astype(np.int64)
        grid = (tile_x+tile_z)%2
        result[ground] = np.stack((110+grid*28,115+grid*28,105+grid*28), axis=-1)[ground]
        for face in range(6):
            mask = cube & ~ground & (face_ids == face)
            ax = face//2
            first, second = [i for i in range(3) if i != ax]
            u = np.clip(((points[...,first]+1)*255.5).astype(int),0,511)
            v = np.clip(((1-points[...,second])*255.5).astype(int),0,511)
            result[mask] = textures[face][v[mask],u[mask]]
        import io
        buffer = io.BytesIO(); Image.fromarray(result).save(buffer,format='JPEG',quality=95)
        name = f'Images/view-{index:03d}.jpg'
        payload = buffer.getvalue(); archive.writestr(name,payload)
        metadata.append({'file':name,'bytes':len(payload)})
    manifest = {'format':'kantura-photo-dataset','version':1,'id':'kantura-synthetic-cube-v1',
                'name':'Synthetic textured cube — interaction test', 'createdAt':'2026-10-11T00:00:00Z',
                'source':'kantura-synthetic-validation','captureMode':'object',
                'scaleStatus':'unverified','images':metadata}
    archive.writestr('manifest.json',json.dumps(manifest,ensure_ascii=False))
print(f'Created {args.count} original synthetic views: {args.output}')
