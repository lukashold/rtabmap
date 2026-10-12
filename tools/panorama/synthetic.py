"""Deterministic authored texture and perspective photos for real engine tests."""
import argparse
import json
import math
from pathlib import Path
import zipfile
import cv2 as cv
import numpy as np


def rotation(yaw):
    angle = math.radians(yaw)
    return np.array([[math.cos(angle), 0, math.sin(angle)], [0, 1, 0], [-math.sin(angle), 0, math.cos(angle)]], np.float32)


def make_fixture(yaws=(0, 45, 90, 135, 180, 225, 270, 315)):
    rng = np.random.default_rng(19231)
    panorama = rng.integers(25, 230, (512, 1024, 3), dtype=np.uint8)
    panorama = cv.GaussianBlur(panorama, (3, 3), 0.6)
    for _ in range(900):
        centre = tuple(int(v) for v in rng.integers([0, 0], [1024, 512]))
        color = tuple(int(v) for v in rng.integers(10, 245, 3))
        cv.circle(panorama, centre, int(rng.integers(2, 14)), color, -1)
    images, cameras = [], []
    width, height = 480, 360
    focal = width / (2 * math.tan(math.radians(95) / 2))
    xx, yy = np.meshgrid(np.arange(width), np.arange(height))
    rays = np.stack([(xx - width / 2) / focal, (yy - height / 2) / focal, np.ones_like(xx)], axis=-1)
    for yaw in yaws:
        matrix = rotation(yaw)
        directions = rays @ matrix.T
        theta = np.arctan2(directions[:, :, 0], directions[:, :, 2])
        phi = np.arccos(-directions[:, :, 1] / np.linalg.norm(directions, axis=2))
        map_x = ((theta + math.pi) * panorama.shape[1] / (2 * math.pi)).astype(np.float32)
        map_y = (phi * panorama.shape[0] / math.pi).astype(np.float32)
        images.append(cv.remap(panorama, map_x, map_y, cv.INTER_LINEAR, borderMode=cv.BORDER_WRAP))
        camera = cv.detail_CameraParams()
        camera.focal = focal
        camera.ppx = width / 2
        camera.ppy = height / 2
        camera.aspect = 1
        camera.R = matrix
        cameras.append(camera)
    return panorama, images, cameras


def write_fixture(path, yaws=(0, 45, 90, 135, 180, 225, 270, 315)):
    _, images, _ = make_fixture(yaws)
    with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        manifest = {'format': 'kantura-photo-dataset', 'version': 1, 'source': 'kantura-synthetic-panorama-validation', 'captureMode': 'panorama', 'scaleStatus': 'unverified', 'images': []}
        for index, image in enumerate(images):
            ok, encoded = cv.imencode('.jpg', image, [cv.IMWRITE_JPEG_QUALITY, 97])
            if not ok:
                raise RuntimeError('Fixture image encode failed')
            name = 'Images/photo-%02d.jpg' % index
            archive.writestr(name, encoded.tobytes())
            manifest['images'].append({'file': name, 'bytes': len(encoded)})
        archive.writestr('manifest.json', json.dumps(manifest))
    return Path(path)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output_zip', type=Path)
    args = parser.parse_args()
    write_fixture(args.output_zip)
