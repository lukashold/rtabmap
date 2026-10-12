"""Local rotation-only photo stitching. No depth, invented pixels, or metric scale.

OpenCV detail camera estimation and its spherical warper are used directly.
The image is placed in angular coordinates on a complete sphere, not stretched.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
import math
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import sys
import tempfile
import warnings
import zipfile

import cv2 as cv
import numpy as np
from PIL import Image, ImageOps
import pillow_heif

pillow_heif.register_heif_opener()
MAX_ZIP = 200 * 1024 * 1024
MAX_EXPANDED = 512 * 1024 * 1024
MAX_IMAGE = 32 * 1024 * 1024
MAX_PIXELS = 48_000_000
MAX_IMAGES = 40
IMAGE_SIDE = 1200
Image.MAX_IMAGE_PIXELS = MAX_PIXELS


class StitchError(ValueError):
    pass


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def safe_member(info):
    # ZipInfo normalizes Windows separators; inspect the original name as well.
    name = info.orig_filename
    parts = PurePosixPath(name).parts
    if not name or '\\' in name or ':' in name or name.startswith('/') or any(p in ('..', '.') for p in name.split('/')) or any(ord(c) < 32 for c in name):
        raise StitchError('Unsafe ZIP path')
    mode = info.external_attr >> 16
    if stat.S_ISLNK(mode) or (stat.S_IFMT(mode) and not (stat.S_ISREG(mode) or stat.S_ISDIR(mode))):
        raise StitchError('ZIP links and special files are not supported')
    if info.flag_bits & 1:
        raise StitchError('Encrypted ZIP files are not supported')
    if not parts:
        raise StitchError('Empty ZIP path')
    if name != info.filename:
        raise StitchError('Normalized ZIP path is not accepted')
    return name


def read_dataset(path):
    """Read bounded image members without extracting paths; retain original archive."""
    if not 0 < Path(path).stat().st_size <= MAX_ZIP:
        raise StitchError('Photo ZIP must be at most 200 MiB')
    images, originals, declared = [], [], None
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        if len(entries) > 128 or sum(i.file_size for i in entries) > MAX_EXPANDED:
            raise StitchError('ZIP exceeds entry or expanded-size limit')
        seen = set()
        for info in entries:
            name = safe_member(info)
            if name.casefold() in seen:
                raise StitchError('Duplicate ZIP paths')
            seen.add(name.casefold())
            if info.is_dir():
                continue
            if name == 'manifest.json':
                if info.file_size > 1024 * 1024:
                    raise StitchError('Dataset manifest too large')
                declared = json.loads(archive.read(info).decode('utf-8'))
                if not isinstance(declared, dict):
                    raise StitchError('Dataset manifest must be an object')
                continue
            extension = PurePosixPath(name).suffix.lower()
            if extension not in ('.jpg', '.jpeg', '.png', '.heic', '.heif'):
                raise StitchError('ZIP may contain only photos and manifest.json')
            if len(images) >= MAX_IMAGES or not 0 < info.file_size <= MAX_IMAGE:
                raise StitchError('Use 2–40 photos, each at most 32 MiB')
            # Stream limit also checks actual bytes, not only central-directory sizes.
            with archive.open(info) as stream:
                data = stream.read(MAX_IMAGE + 1)
            if len(data) != info.file_size or len(data) > MAX_IMAGE:
                raise StitchError('Image byte count is invalid')
            try:
                with warnings.catch_warnings():
                    warnings.simplefilter('error', Image.DecompressionBombWarning)
                    with Image.open(io.BytesIO(data)) as source:
                        if source.format not in ('JPEG', 'PNG', 'HEIF') or getattr(source, 'n_frames', 1) != 1:
                            raise StitchError('Only single-frame JPEG, PNG and HEIC/HEIF photos are supported')
                        width, height = source.size
                        if min(width, height) < 128 or width * height > MAX_PIXELS:
                            raise StitchError('Photo dimensions outside limits')
                        oriented = ImageOps.exif_transpose(source).convert('RGB')
                        oriented.thumbnail((IMAGE_SIDE, IMAGE_SIDE), Image.Resampling.LANCZOS)
                        pixels = np.asarray(oriented).copy()[:, :, ::-1].copy()
            except StitchError:
                raise
            except Exception as error:
                raise StitchError('Cannot decode photo: ' + name) from error
            images.append(pixels)
            originals.append({'file': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(), 'originalWidth': width, 'originalHeight': height, 'workingWidth': pixels.shape[1], 'workingHeight': pixels.shape[0]})
    if len(images) < 2:
        raise StitchError('At least two overlapping photos are required')
    return images, originals, declared


def estimate_cameras(images):
    """Infer all cameras from real matches; reject disconnected image sets."""
    cv.setNumThreads(2)
    cv.setRNGSeed(7321)
    finder = cv.SIFT_create(nfeatures=5000)
    features = [cv.detail.computeImageFeatures2(finder, image) for image in images]
    if any(len(feature.getKeypoints()) < 20 for feature in features):
        raise StitchError('Not enough visual detail; use sharper overlapping photos')
    matcher = cv.detail_BestOf2NearestMatcher(False, 0.65)
    matches = matcher.apply2(features)
    matcher.collectGarbage()
    graph = [set() for _ in images]
    pairs = []
    for match in matches:
        a, b = match.src_img_idx, match.dst_img_idx
        if a >= 0 and b >= 0 and match.confidence >= 0.8 and match.num_inliers >= 12:
            graph[a].add(b)
            if a < b:
                pairs.append({'a': a, 'b': b, 'inliers': int(match.num_inliers), 'matchConfidence': float(match.confidence)})
    reached, pending = {0}, [0]
    while pending:
        for neighbor in graph[pending.pop()]:
            if neighbor not in reached:
                reached.add(neighbor)
                pending.append(neighbor)
    if len(reached) != len(images):
        raise StitchError('Photos do not form one connected panorama; none were silently discarded')
    ok, cameras = cv.detail_HomographyBasedEstimator().apply(features, matches, None)
    if not ok:
        raise StitchError('Rotation/focal estimation failed')
    for camera in cameras:
        camera.R = camera.R.astype(np.float32)
    adjuster = cv.detail_BundleAdjusterRay()
    adjuster.setConfThresh(0.8)
    ok, cameras = adjuster.apply(features, matches, cameras)
    if not ok:
        raise StitchError('Camera adjustment failed; no replacement panorama generated')
    rotations = cv.detail.waveCorrect([camera.R.astype(np.float32) for camera in cameras], cv.detail.WAVE_CORRECT_HORIZ)
    for image, camera, rotation in zip(images, cameras, rotations):
        camera.R = rotation
        if not np.isfinite(camera.K()).all() or not np.isfinite(rotation).all() or not 0.1 * max(image.shape[:2]) < camera.focal < 10 * max(image.shape[:2]):
            raise StitchError('Estimated camera parameters are implausible')
        if not np.allclose(rotation.T @ rotation, np.eye(3), atol=0.005) or not 0.995 < np.linalg.det(rotation) < 1.005:
            raise StitchError('Estimated camera rotation is invalid')
    return cameras, pairs


def compose_sphere(images, cameras, width=2048):
    """OpenCV spherical angular coordinates: u∈[-πs,πs], v∈[0,πs]."""
    if isinstance(width, bool) or not isinstance(width, int) or width < 512 or width > 4096 or width % 2:
        raise StitchError('Output width must be even and between 512 and 4096')
    height = width // 2
    accumulator = np.zeros((height, width, 3), np.float32)
    weights = np.zeros((height, width), np.float32)
    warper = cv.PyRotationWarper('spherical', width / (2 * math.pi))
    for image, camera in zip(images, cameras):
        intrinsic = camera.K().astype(np.float32)
        rotation = camera.R.astype(np.float32)
        roi = warper.warpRoi((image.shape[1], image.shape[0]), intrinsic, rotation)
        if roi[2] > width + 2 or roi[3] > height + 2 or roi[2] < 1 or roi[3] < 1:
            raise StitchError('Spherical warp exceeds bounded canvas')
        source_mask = np.zeros(image.shape[:2], np.uint8)
        source_mask[2:-2, 2:-2] = 255
        source_weight = cv.distanceTransform(source_mask, cv.DIST_L2, 3)
        source_weight /= max(float(source_weight.max()), 1)
        corner, warped = warper.warp(image, intrinsic, rotation, cv.INTER_LINEAR, cv.BORDER_CONSTANT)
        weight_corner, warped_weight = warper.warp(source_weight, intrinsic, rotation, cv.INTER_LINEAR, cv.BORDER_CONSTANT)
        if corner != weight_corner or warped.shape[:2] != warped_weight.shape:
            raise StitchError('Warped image/mask coordinates disagree')
        x0, y0 = corner[0] + width // 2, corner[1]
        top, bottom = max(0, y0), min(height, y0 + warped.shape[0])
        if bottom <= top:
            continue
        # Wrap longitude across the seam; trim the redundant last angular sample.
        columns = min(warped.shape[1], width)
        for start in range(0, columns):
            target_x = (x0 + start) % width
            weight = warped_weight[top - y0:bottom - y0, start]
            accumulator[top:bottom, target_x] += warped[top - y0:bottom - y0, start].astype(np.float32) * weight[:, None]
            weights[top:bottom, target_x] += weight
    coverage = weights > 1e-5
    if not np.any(coverage):
        raise StitchError('No observed spherical pixels')
    panorama = np.zeros((height, width, 4), np.uint8)
    panorama[coverage, :3] = np.clip(accumulator[coverage] / weights[coverage, None], 0, 255).astype(np.uint8)
    panorama[coverage, 3] = 255
    # Fraction of spherical surface, not unweighted equirectangular pixel count.
    latitude_weights = np.sin((np.arange(height) + 0.5) * math.pi / height)
    fraction = float((coverage * latitude_weights[:, None]).sum() / (width * latitude_weights.sum()))
    return panorama, coverage.astype(np.uint8) * 255, fraction


def process(source, destination, width=2048):
    source, destination = Path(source).resolve(), Path(destination).resolve()
    if destination.exists():
        raise StitchError('Output directory must not exist; existing results are never replaced')
    if isinstance(width, bool) or not isinstance(width, int) or width < 512 or width > 4096 or width % 2:
        raise StitchError('Output width must be even and between 512 and 4096')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.kantura-panorama-', dir=destination.parent) as temporary:
        stage = Path(temporary) / 'result'
        stage.mkdir()
        # Work from an immutable copied input; output preserves these exact bytes.
        if not 0 < source.stat().st_size <= MAX_ZIP:
            raise StitchError('Photo ZIP must be at most 200 MiB')
        shutil.copyfile(source, stage / 'originals.zip')
        images, originals, declared = read_dataset(stage / 'originals.zip')
        cameras, pairs = estimate_cameras(images)
        panorama, mask, fraction = compose_sphere(images, cameras, width)
        if not cv.imwrite(str(stage / 'panorama.png'), panorama) or not cv.imwrite(str(stage / 'coverage.png'), mask):
            raise StitchError('Cannot write panorama output')
        manifest = {'format': 'kantura-panorama', 'version': 1, 'status': 'complete', 'createdAt': datetime.now(timezone.utc).isoformat(), 'projection': 'equirectangular', 'width': width, 'height': width // 2, 'scaleStatus': 'unverified', 'hasDepth': False, 'canMeasure': False, 'coverageFraction': fraction, 'coverageMeaning': 'observed spherical solid-angle fraction; not registration accuracy', 'unknownPixels': 'transparent alpha=0 and coverage mask=0; never generated', 'engine': {'opencv': cv.__version__, 'model': 'rotation-only homography + ray bundle adjustment + spherical warper', 'blend': 'edge-distance feather; no seam optimization or exposure correction'}, 'images': originals, 'matchedPairs': pairs, 'cameras': [{'K': camera.K().tolist(), 'R': camera.R.tolist()} for camera in cameras], 'sourceManifest': declared, 'limitations': ['No metric depth or measurements', 'Requires rotation about one camera centre; translation/parallax may cause ghosts', 'No automatic horizon or stitch-quality guarantee', 'Incomplete angular coverage remains unknown'], 'artifacts': []}
        for name in ('panorama.png', 'coverage.png', 'originals.zip'):
            path = stage / name
            manifest['artifacts'].append({'name': name, 'bytes': path.stat().st_size, 'sha256': sha256(path)})
        (stage / 'result.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
        # Atomic publication: failed jobs never leave a directory called complete.
        os.replace(stage, destination)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('photos_zip', type=Path)
    parser.add_argument('output_directory', type=Path)
    parser.add_argument('--width', type=int, default=2048)
    parser.add_argument('--timeout', type=int, default=600, help='Whole process timeout, 10–1800 seconds')
    parser.add_argument('--worker', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if not 10 <= args.timeout <= 1800:
        parser.error('timeout must be 10–1800 seconds')
    if not args.worker:
        try:
            destination = args.output_directory.resolve()
            if destination.exists():
                raise StitchError('Output directory must not exist; existing results are never replaced')
            destination.parent.mkdir(parents=True, exist_ok=True)
            # Parent owns the staging tree, so killing native code on timeout also
            # removes private input copies and half-written artifacts afterwards.
            with tempfile.TemporaryDirectory(prefix='.kantura-panorama-run-', dir=destination.parent) as temporary:
                stage = Path(temporary) / 'result'
                result = subprocess.run([sys.executable, str(Path(__file__).resolve()), str(args.photos_zip.resolve()), str(stage), '--width', str(args.width), '--timeout', str(args.timeout), '--worker'], timeout=args.timeout, capture_output=True, text=True)
                if result.returncode:
                    print(json.dumps({'status': 'failed', 'error': (result.stdout or result.stderr or 'Panorama worker failed').strip()[-2000:]}))
                    return 1
                manifest = json.loads((stage / 'result.json').read_text(encoding='utf-8'))
                if manifest.get('status') != 'complete':
                    raise StitchError('Worker did not publish verified output')
                os.replace(stage, destination)
                print(json.dumps({'status': 'complete', 'output': str(destination), 'coverageFraction': manifest['coverageFraction'], 'hasDepth': False}))
                return 0
        except subprocess.TimeoutExpired:
            print(json.dumps({'status': 'failed', 'error': 'Panorama processing timed out; staging data removed'}))
            return 1
        except Exception as error:
            print(json.dumps({'status': 'failed', 'error': str(error)}))
            return 1
    try:
        result = process(args.photos_zip, args.output_directory, args.width)
        print(json.dumps({'status': 'complete', 'output': str(args.output_directory), 'coverageFraction': result['coverageFraction'], 'hasDepth': False}))
        return 0
    except Exception as error:
        print(json.dumps({'status': 'failed', 'error': str(error)}))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
