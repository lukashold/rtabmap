"""Bounded archive and output contract; no reconstruction is simulated here."""
import hashlib
import json
import math
import re
import stat
import struct
import unicodedata
import zipfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath


@dataclass(frozen=True)
class Limits:
    upload: int = 200 * 1024**2
    expanded: int = 1024**3
    artifact: int = 200 * 1024**2
    output_expanded: int = 500 * 1024**2
    image: int = 50 * 1024**2
    min_images: int = 8
    max_images: int = 250
    queue: int = 4


LIMITS = Limits()
EXTENSIONS = {'.jpg', '.jpeg', '.png', '.heic', '.heif'}
VIDEO_TYPES = {'video/mp4', 'video/quicktime'}
VIDEO_LIMITS = {'durationSeconds': 180, 'maxWidth': 4096, 'maxHeight': 4096,
                'maxPixels': 16_777_216, 'maxFrameRate': 240, 'candidateFrames': 360}
OPTIONAL_ARTIFACTS = {'photos.zip': 'application/zip', 'cameras.json': 'application/json'}
ARTIFACTS = {
    'mesh': {'mesh.zip': 'application/zip', 'model.ply': 'application/octet-stream', 'reconstruction.json': 'application/json'},
    'splat': {'splat.ply': 'application/octet-stream', 'cameras.json': 'application/json', 'reconstruction.json': 'application/json'},
}


class ContractError(Exception):
    def __init__(self, code, message=None):
        super().__init__(message or code)
        self.code = code


def safe_path(name):
    if not isinstance(name, str) or not name or len(name) > 240:
        raise ContractError('invalid_archive')
    if any(ord(c) < 32 for c in name) or '\\' in name or ':' in name or name.startswith('/'):
        raise ContractError('invalid_archive')
    path = PurePosixPath(name)
    if any(p in ('', '.', '..') for p in name.rstrip('/').split('/')) or path.is_absolute():
        raise ContractError('invalid_archive')
    return path


def zip_entries(archive, expanded_limit, file_limit, entry_limit):
    entries = archive.infolist()
    if len(entries) > entry_limit:
        raise ContractError('too_large')
    seen, total, files = set(), 0, []
    for info in entries:
        safe_path(info.orig_filename)
        key = unicodedata.normalize('NFC', info.filename.rstrip('/')).casefold()
        if key in seen:
            raise ContractError('invalid_archive')
        seen.add(key)
        kind = stat.S_IFMT(info.external_attr >> 16)
        if kind not in (0, stat.S_IFREG, stat.S_IFDIR) or info.flag_bits & 1:
            raise ContractError('invalid_archive')
        if info.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
            raise ContractError('invalid_archive')
        total += info.file_size
        if info.file_size > file_limit or total > expanded_limit or info.file_size > max(1, info.compress_size) * 200:
            raise ContractError('too_large')
        if not info.is_dir():
            files.append(info)
    return files


def inspect_input(path, limits=LIMITS):
    if Path(path).stat().st_size > limits.upload:
        raise ContractError('too_large')
    try:
        with zipfile.ZipFile(path) as archive:
            files = zip_entries(archive, limits.expanded, limits.image, limits.max_images * 3 + 1)
            images = [i for i in files if PurePosixPath(i.filename).suffix.lower() in EXTENSIONS]
            extras = [i for i in files if i not in images]
            if any(i.filename != 'manifest.json' for i in extras):
                raise ContractError('unsupported_image')
            if len(images) < limits.min_images:
                raise ContractError('too_few_images')
            if len(images) > limits.max_images:
                raise ContractError('too_large')
            if any(i.file_size == 0 for i in images):
                raise ContractError('unsupported_image')
            source = {'source': 'photo-zip', 'scaleStatus': 'unverified'}
            if extras:
                if extras[0].file_size > 1024**2:
                    raise ContractError('invalid_manifest')
                manifest = json.loads(archive.read('manifest.json'))
                if not isinstance(manifest, dict) or manifest.get('format') != 'kantura-photo-dataset' or manifest.get('version') != 1:
                    raise ContractError('invalid_manifest')
                records = manifest.get('images')
                if not isinstance(records, list) or len(records) != len(images):
                    raise ContractError('invalid_manifest')
                actual = {i.filename: i.file_size for i in images}
                declared = {}
                for item in records:
                    if not isinstance(item, dict) or not isinstance(item.get('file'), str) or type(item.get('bytes')) is not int:
                        raise ContractError('invalid_manifest')
                    safe_path(item['file'])
                    if item['file'] in declared:
                        raise ContractError('invalid_manifest')
                    declared[item['file']] = item['bytes']
                if actual != declared:
                    raise ContractError('invalid_manifest')
                source = {'format': manifest['format'], 'version': 1}
                for key in ('id', 'name', 'createdAt', 'source', 'captureMode', 'scaleStatus'):
                    if key in manifest:
                        if not isinstance(manifest[key], str) or len(manifest[key]) > 200 or any(ord(c) < 32 for c in manifest[key]):
                            raise ContractError('invalid_manifest')
                        source[key] = manifest[key]
            # Decompress with a bounded buffer and check CRCs before queuing. Never extract paths.
            for info in files:
                count = 0
                with archive.open(info) as stream:
                    while True:
                        block = stream.read(1024 * 1024)
                        if not block:
                            break
                        count += len(block)
                        if count > info.file_size or count > limits.image:
                            raise ContractError('too_large')
                if count != info.file_size:
                    raise ContractError('invalid_archive')
            return {'imageCount': len(images), 'source': source, 'images': [i.filename for i in images]}
    except ContractError:
        raise
    except (ValueError, OSError, RuntimeError, zipfile.BadZipFile, EOFError, KeyError) as error:
        raise ContractError('invalid_archive') from error


def sha256(path):
    digest = hashlib.sha256()
    with open(path, 'rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def inspect_video_input(path, limits=LIMITS):
    """Cheap ISO-BMFF preflight; decoding and limits are checked in the worker."""
    path = Path(path)
    if not 16 <= path.stat().st_size <= limits.upload:
        raise ContractError('too_large')
    with path.open('rb') as stream:
        header = stream.read(16)
    if header[4:8] != b'ftyp' or not 16 <= int.from_bytes(header[:4], 'big') <= 4096:
        raise ContractError('unsupported_video')
    return {'imageCount': None, 'source': {'source': 'video', 'scaleStatus': 'unverified'}}


def inspect_ply(path, splat=False):
    """Validate scalar vertices and mesh face records, never geometry quality."""
    scalar = {'char': 'b', 'int8': 'b', 'uchar': 'B', 'uint8': 'B', 'short': 'h', 'int16': 'h', 'ushort': 'H', 'uint16': 'H', 'int': 'i', 'int32': 'i', 'uint': 'I', 'uint32': 'I', 'float': 'f', 'float32': 'f', 'double': 'd', 'float64': 'd'}
    with open(path, 'rb') as stream:
        header = bytearray()
        while True:
            line = stream.readline(4096)
            if not line or len(header) + len(line) > 65536:
                raise ContractError('invalid_artifacts')
            header.extend(line)
            if line.rstrip(b'\r\n') == b'end_header':
                break
        lines = header.decode('ascii').splitlines()
        if lines[0] != 'ply':
            raise ContractError('invalid_artifacts')
        elements, encoding = [], None
        for line in lines:
            if line.startswith('format '):
                parts = line.split()
                if len(parts) != 3 or parts[2] != '1.0' or encoding is not None:
                    raise ContractError('invalid_artifacts')
                encoding = parts[1]
            elif line.startswith('element '):
                parts = line.split()
                if len(parts) != 3 or not parts[2].isdigit() or parts[1] not in {'vertex', 'face'} or any(e[0] == parts[1] for e in elements):
                    raise ContractError('invalid_artifacts')
                elements.append((parts[1], int(parts[2]), []))
            elif line.startswith('property '):
                parts = line.split()[1:]
                if not elements or (len(parts) != 2 and len(parts) != 4):
                    raise ContractError('invalid_artifacts')
                if len(parts) == 2 and parts[0] not in scalar:
                    raise ContractError('invalid_artifacts')
                if len(parts) == 4 and (parts[0] != 'list' or parts[1] not in scalar or parts[2] not in scalar or scalar[parts[1]] in 'fd'):
                    raise ContractError('invalid_artifacts')
                elements[-1][2].append(parts)
        if encoding not in {'ascii', 'binary_little_endian', 'binary_big_endian'} or not elements or elements[0][0] != 'vertex':
            raise ContractError('invalid_artifacts')
        vertices, properties = elements[0][1:]
        faces = next((e[1] for e in elements if e[0] == 'face'), 0)
        required = {'x', 'y', 'z'} | ({'f_dc_0', 'f_dc_1', 'f_dc_2', 'opacity', 'scale_0', 'scale_1', 'scale_2', 'rot_0', 'rot_1', 'rot_2', 'rot_3'} if splat else set())
        names = [p[-1] for p in properties]
        if not vertices or vertices > 10_000_000 or faces > 20_000_000 or len(set(names)) != len(names) or not required.issubset(names) or any(len(p) != 2 for p in properties) or (not splat and not faces):
            raise ContractError('invalid_artifacts')
        endian = '<' if encoding == 'binary_little_endian' else '>'
        def number(type_name):
            fmt = endian + scalar[type_name]
            size = struct.calcsize(fmt)
            data = stream.read(size)
            if len(data) != size:
                raise ContractError('invalid_artifacts')
            return struct.unpack(fmt, data)[0]
        # Fixed-width vertex preflight rejects fabricated large element counts.
        if encoding != 'ascii' and Path(path).stat().st_size - len(header) < vertices * sum(struct.calcsize(endian + scalar[p[0]]) for p in properties):
            raise ContractError('invalid_artifacts')
        for element, count, props in elements:
            if element == 'face' and not any(len(p) == 4 and p[-1] in {'vertex_indices', 'vertex_index'} for p in props):
                raise ContractError('invalid_artifacts')
            if element == 'vertex' and encoding != 'ascii':
                record = struct.Struct(endian + ''.join(scalar[p[0]] for p in props))
                remaining = count
                while remaining:
                    batch = min(remaining, 2048)
                    data = stream.read(record.size * batch)
                    if len(data) != record.size * batch or any(not math.isfinite(v) for row in record.iter_unpack(data) for v in row):
                        raise ContractError('invalid_artifacts')
                    remaining -= batch
                continue
            for _ in range(count):
                row = None
                if encoding == 'ascii':
                    line = stream.readline(65536)
                    if not line.endswith(b'\n') or len(line) >= 65536:
                        raise ContractError('invalid_artifacts')
                    row = iter(line.decode('ascii').split())
                try:
                    def read_value(type_name):
                        value = number(type_name) if row is None else (float(next(row)) if scalar[type_name] in 'fd' else int(next(row)))
                        if not math.isfinite(value):
                            raise ContractError('invalid_artifacts')
                        return value
                    for prop in props:
                        if len(prop) == 2:
                            read_value(prop[0])
                        else:
                            length = read_value(prop[1])
                            if not 0 <= length <= 1024:
                                raise ContractError('invalid_artifacts')
                            values = [read_value(prop[2]) for _ in range(length)]
                            if prop[-1] in {'vertex_indices', 'vertex_index'} and (length < 3 or scalar[prop[2]] in 'fd' or any(v < 0 or v >= vertices for v in values)):
                                raise ContractError('invalid_artifacts')
                    if row is not None and next(row, None) is not None:
                        raise ContractError('invalid_artifacts')
                except (ValueError, StopIteration, UnicodeError, struct.error) as error:
                    raise ContractError('invalid_artifacts') from error
        if stream.read(1):
            raise ContractError('invalid_artifacts')
        return {'vertices': vertices, 'faces': faces}


def validate_artifacts(directory, mode, limits=LIMITS):
    directory = Path(directory).resolve()
    expected = dict(ARTIFACTS[mode])
    for name, media in OPTIONAL_ARTIFACTS.items():
        if (directory / name).exists():
            expected[name] = media
    result = []
    for name, media in expected.items():
        path = directory / name
        if path.is_symlink() or not path.is_file() or path.resolve().parent != directory:
            raise ContractError('missing_artifacts')
        size = path.stat().st_size
        if not size or size > limits.artifact:
            raise ContractError('too_large')
        result.append({'name': name, 'mediaType': media, 'bytes': size, 'sha256': sha256(path)})
    try:
        if (directory / 'reconstruction.json').stat().st_size > 4 * 1024**2:
            raise ContractError('invalid_artifacts')
        manifest = json.loads((directory / 'reconstruction.json').read_text('utf-8'))
        if manifest.get('format') != 'kantura-reconstruction' or manifest.get('version') != 1 or manifest.get('mode') != mode or manifest.get('scaleStatus') != 'unverified':
            raise ContractError('invalid_artifacts')
        declared = manifest.get('files', {})
        for item in result:
            if item['name'] != 'reconstruction.json' and declared.get(item['name']) != item['sha256']:
                raise ContractError('invalid_artifacts')
        if 'photos.zip' in expected:
            inspect_input(directory / 'photos.zip', limits)
        if mode == 'mesh':
            inspect_ply(directory / 'model.ply')
            with zipfile.ZipFile(directory / 'mesh.zip') as archive:
                entries = zip_entries(archive, limits.output_expanded, limits.artifact, 1000)
                if not any(i.filename.endswith('.obj') for i in entries) or any(PurePosixPath(i.filename).suffix.lower() not in {'.obj', '.mtl', '.png', '.jpg', '.jpeg'} for i in entries):
                    raise ContractError('invalid_artifacts')
                if archive.testzip() is not None:
                    raise ContractError('invalid_artifacts')
        else:
            inspect_ply(directory / 'splat.ply', splat=True)
        if 'cameras.json' in expected:
            if (directory / 'cameras.json').stat().st_size > 4 * 1024**2:
                raise ContractError('invalid_artifacts')
            cameras = json.loads((directory / 'cameras.json').read_text('utf-8'))
            if not isinstance(cameras, list) or not cameras:
                raise ContractError('invalid_artifacts')
            if len(cameras) > limits.max_images:
                raise ContractError('invalid_artifacts')
            for camera in cameras:
                if not isinstance(camera, dict) or any(type(camera.get(key)) not in (float, int) or not math.isfinite(camera[key]) or camera[key] <= 0 for key in ('width', 'height', 'fx', 'fy')):
                    raise ContractError('invalid_artifacts')
                position, rotation = camera.get('position'), camera.get('rotation')
                if not isinstance(position, list) or len(position) != 3 or not isinstance(rotation, list) or len(rotation) != 3 or any(not isinstance(row, list) or len(row) != 3 for row in rotation):
                    raise ContractError('invalid_artifacts')
                if any(type(v) not in (float, int) or not math.isfinite(v) for v in position + [v for row in rotation for v in row]):
                    raise ContractError('invalid_artifacts')
        return result
    except ContractError:
        raise
    except (ValueError, UnicodeError, OSError, zipfile.BadZipFile, AttributeError) as error:
        raise ContractError('invalid_artifacts') from error
