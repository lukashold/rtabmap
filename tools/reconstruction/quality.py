"""Observable input/SfM diagnostics. None of these establish metric accuracy."""
import hashlib
from contextlib import closing
import json
import math
import sqlite3
import statistics
import struct
from pathlib import Path

from contract import ContractError


def image_quality(image):
    from PIL import Image
    gray = image.convert('L').resize((128, 128), Image.Resampling.BILINEAR)
    pixels = list(gray.getdata())
    lap = [pixels[i - 1] + pixels[i + 1] + pixels[i - 128] + pixels[i + 128] - 4 * pixels[i]
           for y in range(1, 127) for x in range(1, 127) for i in [y * 128 + x]]
    average = sum(lap) / len(lap)
    variance = sum((x - average)**2 for x in lap) / len(lap)
    thumb = image.convert('L').resize((9, 8), Image.Resampling.BILINEAR)
    values = list(thumb.getdata())
    bits = ''.join('1' if values[y*9+x] > values[y*9+x+1] else '0' for y in range(8) for x in range(8))
    fingerprint = bytes(image.convert('L').resize((32, 32), Image.Resampling.BILINEAR).getdata())
    return {'laplacianVariance128': round(variance, 4), 'meanLuma': round(sum(pixels)/len(pixels), 4),
            'darkFraction': round(sum(x < 8 for x in pixels)/len(pixels), 5),
            'brightFraction': round(sum(x > 247 for x in pixels)/len(pixels), 5),
            'dHash64': f'{int(bits, 2):016x}'}, fingerprint


def near_duplicate(first, second, first_quality, second_quality):
    # A perceptual hash alone confuses plain but unrelated frames. Require
    # both near-identical luminance and a small difference-hash distance.
    distance = bin(int(first_quality['dHash64'], 16) ^ int(second_quality['dHash64'], 16)).count('1')
    if distance > 2:
        return False
    difference = sum(abs(a-b) for a, b in zip(first, second)) / 1024
    return distance <= 2 and difference <= 2.0


def camera_hint(image):
    exif = dict(image.getexif())
    try:
        exif.update(image.getexif().get_ifd(34665))
    except (KeyError, ValueError, TypeError):
        pass
    def number(tag):
        try:
            value = float(exif.get(tag, 0))
            return round(value, 6) if math.isfinite(value) and 0 < value < 10000 else None
        except (TypeError, ValueError, ZeroDivisionError):
            return None
    def label(tag):
        value = exif.get(tag)
        if isinstance(value, str):
            return ''.join(c for c in value if ord(c) >= 32).strip()[:100] or None
        return None
    hint = {'make': label(271), 'model': label(272), 'lens': label(42036),
            'focalMillimeters': number(37386), 'focal35mm': number(41989),
            'digitalZoomRatio': number(41988) or 1.0,
            'gpsMetadataPresent': 34853 in exif}
    # Hash optional serials into the grouping key, never expose serial numbers.
    signature = [hint[k] for k in ['make', 'model', 'lens', 'focalMillimeters', 'focal35mm', 'digitalZoomRatio']]
    if all(signature[:4]):
        signature.extend([label(42033), label(42037)])
        hint['signature'] = hashlib.sha256(json.dumps(signature, separators=(',', ':')).encode()).hexdigest()
    return hint


def assign_camera_groups(database, records, policy='auto'):
    """COLMAP 3.11 database relation: images.camera_id references intrinsics.

    Features are already extracted with a camera per image. Group only after
    verifying dimensions/model, before matching and bundle adjustment.
    """
    if policy not in {'auto', 'single', 'per-image'}:
        raise ContractError('invalid_camera_policy')
    if not records:
        return {'policy': policy, 'groups': [], 'basis': 'no-records'}
    if policy == 'single' and len({(r['width'], r['height']) for r in records}) != 1:
        raise ContractError('invalid_camera_policy')
    groups = {}
    for record in records:
        signature = record.get('cameraHint', {}).get('signature')
        key = ('operator-single',) if policy == 'single' else (
            ('exif', signature, record['width'], record['height']) if policy == 'auto' and signature
            else ('independent', record['file']))
        groups.setdefault(key, []).append(record)
    summary = []
    with closing(sqlite3.connect(database)) as connection, connection:
        for key, group in groups.items():
            entries = []
            for record in group:
                name = Path(record['file']).name
                row = connection.execute('SELECT i.image_id,i.camera_id,c.model,c.width,c.height FROM images i JOIN cameras c ON i.camera_id=c.camera_id WHERE i.name=?', (name,)).fetchone()
                if not row or tuple(row[3:]) != (record['width'], record['height']):
                    raise ContractError('invalid_camera_database')
                entries.append(row)
            if len({tuple(row[2:]) for row in entries}) != 1:
                raise ContractError('invalid_camera_database')
            camera_id = entries[0][1]
            for row in entries[1:]:
                connection.execute('UPDATE images SET camera_id=? WHERE image_id=?', (camera_id, row[0]))
            summary.append({'cameraId': camera_id, 'basis': key[0], 'images': len(group)})
    return {'policy': policy, 'groups': summary,
            'assumption': 'Shared intrinsics require a fixed lens/focal setting; EXIF is evidence, not calibration.'}


def _read(stream, fmt):
    parser = struct.Struct('<' + fmt)
    data = stream.read(parser.size)
    if len(data) != parser.size:
        raise ContractError('invalid_sfm_model')
    return parser.unpack(data)


def _q_rotation(q):
    length = math.sqrt(sum(x*x for x in q))
    if not math.isfinite(length) or length < .5 or length > 1.5:
        raise ContractError('invalid_sfm_model')
    w, x, y, z = [v/length for v in q]
    return [[1-2*y*y-2*z*z, 2*x*y-2*z*w, 2*x*z+2*y*w],
            [2*x*y+2*z*w, 1-2*x*x-2*z*z, 2*y*z-2*x*w],
            [2*x*z-2*y*w, 2*y*z+2*x*w, 1-2*x*x-2*y*y]]


def sfm_report(model, input_count):
    """Read pinned COLMAP binary layout, not unstable text log summaries."""
    model = Path(model)
    cameras = {}
    with (model / 'cameras.bin').open('rb') as stream:
        count, = _read(stream, 'Q')
        if not 1 <= count <= 250:
            raise ContractError('invalid_sfm_model')
        for _ in range(count):
            identifier, kind, width, height = _read(stream, 'iiQQ')
            parameter_count = {0: 3, 1: 4, 2: 4}.get(kind)
            if parameter_count is None:
                raise ContractError('invalid_sfm_model')
            params = _read(stream, 'd'*parameter_count)
            if not width or not height or not all(math.isfinite(v) for v in params):
                raise ContractError('invalid_sfm_model')
            cameras[identifier] = {'modelId': kind, 'width': width, 'height': height, 'parameters': list(params)}
    exported, observed = [], 0
    with (model / 'images.bin').open('rb') as stream:
        count, = _read(stream, 'Q')
        if not 1 <= count <= 250:
            raise ContractError('invalid_sfm_model')
        for _ in range(count):
            row = _read(stream, 'i'+'d'*7+'i')
            image_id, q, translation, camera_id = row[0], row[1:5], row[5:8], row[8]
            name = bytearray()
            while True:
                character = stream.read(1)
                if character == b'\0':
                    break
                if not character or len(name) >= 240:
                    raise ContractError('invalid_sfm_model')
                name.extend(character)
            name = name.decode('utf-8')
            if Path(name).name != name or any(ord(c) < 32 for c in name):
                raise ContractError('invalid_sfm_model')
            point_count, = _read(stream, 'Q')
            if point_count > 1_000_000:
                raise ContractError('invalid_sfm_model')
            for _ in range(point_count):
                _, _, point_id = _read(stream, 'ddq')
                observed += point_id >= 0
            intrinsic = cameras.get(camera_id)
            if intrinsic is None or not all(math.isfinite(v) for v in translation):
                raise ContractError('invalid_sfm_model')
            rotation = _q_rotation(q)
            camera_to_world = [list(row) for row in zip(*rotation)]
            position = [-sum(camera_to_world[i][j]*translation[j] for j in range(3)) for i in range(3)]
            params = intrinsic['parameters']
            exported.append({'id': image_id, 'img_name': name, 'width': intrinsic['width'], 'height': intrinsic['height'],
                             'fx': params[0], 'fy': params[1] if intrinsic['modelId'] == 1 else params[0],
                             'position': position, 'rotation': camera_to_world})
    errors, tracks = [], []
    with (model / 'points3D.bin').open('rb') as stream:
        count, = _read(stream, 'Q')
        if count > 10_000_000:
            raise ContractError('invalid_sfm_model')
        # Store a bounded deterministic diagnostic sample on very large models.
        stride = max(1, math.ceil(count / 100000))
        for index in range(count):
            row = _read(stream, 'QdddBBBd')
            error = row[-1]
            track_length, = _read(stream, 'Q')
            if not math.isfinite(error) or error < 0 or track_length > 250:
                raise ContractError('invalid_sfm_model')
            if len(stream.read(track_length*8)) != track_length*8:
                raise ContractError('invalid_sfm_model')
            if index % stride == 0:
                errors.append(error)
                tracks.append(track_length)
    errors.sort()
    report = {'registeredImages': len(exported), 'inputImages': input_count,
              'registeredFraction': len(exported)/input_count, 'sparsePoints': count,
              'observations': observed, 'reprojectionErrorPixels': {
                  'mean': statistics.mean(errors) if errors else None,
                  'median': statistics.median(errors) if errors else None,
                  'p95': errors[math.ceil(len(errors)*.95)-1] if errors else None,
                  'sampleCount': len(errors), 'samplingStride': stride},
              'meanTrackLength': statistics.mean(tracks) if tracks else None,
              'cameraModels': [{'cameraId': key, **value} for key, value in cameras.items()],
              'cameraConvention': 'COLMAP camera-to-world; right/down/forward; arbitrary similarity frame',
              'metricAccuracyValidated': False}
    return report, sorted(exported, key=lambda item: item['img_name'])
