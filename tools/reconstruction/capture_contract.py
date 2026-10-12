"""Strict input/output validation for non-metric panorama and generated jobs."""
import hashlib
import json
import math
import struct
import warnings
import zipfile
from dataclasses import replace
from pathlib import Path

from contract import ARTIFACTS, LIMITS, ContractError, inspect_input, inspect_ply, sha256, zip_entries

IMAGE_TYPES = {'image/jpeg', 'image/png'}
GENERATED_BYTES = 20 * 1024**2
PANORAMA_LIMITS = replace(LIMITS, min_images=2, max_images=40, image=32*1024**2, expanded=512*1024**2)


def inspect_generated_input(path, content_type, foreground_isolated=False):
    from PIL import Image
    path = Path(path)
    if not 0 < path.stat().st_size <= GENERATED_BYTES:
        raise ContractError('too_large')
    try:
        with warnings.catch_warnings(), Image.open(path) as image:
            warnings.simplefilter('error', Image.DecompressionBombWarning)
            if image.format != {'image/png': 'PNG', 'image/jpeg': 'JPEG'}.get(content_type) or getattr(image, 'n_frames', 1) != 1:
                raise ContractError('unsupported_image')
            width, height = image.size
            if min(width, height) < 64 or max(width, height) > 8192 or width*height > 16*1024**2:
                raise ContractError('unsupported_image')
            image.load()
            low, high = image.convert('RGBA').getchannel('A').getextrema()
            if high == 0:
                raise ContractError('unsupported_image')
            if low == 255 and not foreground_isolated:
                raise ContractError('foreground_required')
        return {'imageCount': 1, 'source': {'source': 'generated', 'scaleStatus': 'unverified',
                                           'metricMeasurementsAllowed': False}}
    except ContractError:
        raise
    except Exception as error:
        raise ContractError('unsupported_image') from error


def read_json(path):
    if path.stat().st_size > 4 * 1024**2:
        raise ContractError('invalid_artifacts')
    return json.loads(path.read_text('utf-8'))


def generated_provenance(value):
    return isinstance(value, dict) and value.get('source') == 'generated' and value.get('metricMeasurementsAllowed') is False


def inspect_generated_glb(path):
    """Validate the actual embedded triangle buffers, not only a magic header."""
    with path.open('rb') as stream:
        header = stream.read(12)
        if len(header) != 12 or struct.unpack('<4sII', header) != (b'glTF', 2, path.stat().st_size):
            raise ContractError('invalid_artifacts')
        length, kind = struct.unpack('<II', stream.read(8))
        if kind != 0x4e4f534a or length > 4*1024**2 or length % 4:
            raise ContractError('invalid_artifacts')
        document = json.loads(stream.read(length))
        length, kind = struct.unpack('<II', stream.read(8))
        if kind != 0x004e4942 or length > LIMITS.artifact or length % 4:
            raise ContractError('invalid_artifacts')
        binary = stream.read(length)
        if len(binary) != length or stream.read(1):
            raise ContractError('invalid_artifacts')
    if document.get('asset', {}).get('version') != '2.0' or document.get('images') or document.get('extensionsRequired'):
        raise ContractError('invalid_artifacts')
    buffers = document.get('buffers', [])
    if len(buffers) != 1 or 'uri' in buffers[0] or not length-3 <= buffers[0].get('byteLength', -1) <= length:
        raise ContractError('invalid_artifacts')
    meshes, scenes = document.get('meshes', []), document.get('scenes', [])
    if len(meshes) != 1 or not any(generated_provenance(item.get('extras')) for item in meshes+scenes):
        raise ContractError('invalid_artifacts')
    primitives = meshes[0].get('primitives', [])
    if len(primitives) != 1 or primitives[0].get('mode', 4) != 4:
        raise ContractError('invalid_artifacts')
    accessors, views = document.get('accessors', []), document.get('bufferViews', [])

    def values(index, expected, allowed):
        if type(index) is not int or not 0 <= index < len(accessors):
            raise ContractError('invalid_artifacts')
        accessor = accessors[index]
        component = accessor.get('componentType')
        if accessor.get('type') != expected or component not in allowed or accessor.get('sparse'):
            raise ContractError('invalid_artifacts')
        count = accessor.get('count')
        if type(count) is not int or not 1 <= count <= 12_000_000:
            raise ContractError('invalid_artifacts')
        view_index = accessor.get('bufferView')
        if type(view_index) is not int or not 0 <= view_index < len(views):
            raise ContractError('invalid_artifacts')
        view = views[view_index]
        parser = struct.Struct('<' + {5121:'B',5123:'H',5125:'I',5126:'f'}[component] * (3 if expected == 'VEC3' else 1))
        stride = view.get('byteStride', parser.size)
        offset = accessor.get('byteOffset', 0)
        base = view.get('byteOffset', 0)
        if view.get('buffer') != 0 or any(type(v) is not int or v < 0 for v in [stride, offset, base, view.get('byteLength')]) or stride < parser.size or stride > 252:
            raise ContractError('invalid_artifacts')
        end = offset+(count-1)*stride+parser.size
        if end > view['byteLength'] or base+view['byteLength'] > len(binary):
            raise ContractError('invalid_artifacts')
        return count, (parser.unpack_from(binary, base+offset+i*stride) for i in range(count))

    primitive = primitives[0]
    vertices, coordinates = values(primitive.get('attributes', {}).get('POSITION'), 'VEC3', {5126})
    if vertices < 3 or vertices > 2_000_000:
        raise ContractError('invalid_artifacts')
    lower, upper = [math.inf]*3, [-math.inf]*3
    for row in coordinates:
        if any(not math.isfinite(x) for x in row):
            raise ContractError('invalid_artifacts')
        lower = [min(a,b) for a,b in zip(lower,row)]
        upper = [max(a,b) for a,b in zip(upper,row)]
    if max(b-a for a,b in zip(lower,upper)) <= 1e-8:
        raise ContractError('invalid_artifacts')
    indices, triangles = values(primitive.get('indices'), 'SCALAR', {5121,5123,5125})
    if indices % 3 or any(row[0] >= vertices for row in triangles):
        raise ContractError('invalid_artifacts')
    return {'vertices': vertices, 'faces': indices//3}


def inspect_generated_obj(path, expected):
    vertices, faces, maximum_index = 0, 0, 0
    with path.open('r', encoding='utf-8') as stream:
        for line in stream:
            if len(line) > 65536:
                raise ContractError('invalid_artifacts')
            values = line.split()
            if not values or values[0].startswith('#'):
                continue
            if values[0] == 'v':
                if len(values) < 4 or any(not math.isfinite(float(x)) for x in values[1:]):
                    raise ContractError('invalid_artifacts')
                vertices += 1
            elif values[0] == 'f':
                if len(values) != 4:
                    raise ContractError('invalid_artifacts')
                indices = [int(x.split('/')[0]) for x in values[1:]]
                if min(indices) < 1:
                    raise ContractError('invalid_artifacts')
                maximum_index = max(maximum_index,*indices)
                faces += 1
            elif values[0] in {'mtllib','usemtl'}:
                raise ContractError('invalid_artifacts')  # This exporter uses vertex colors only.
    if {'vertices':vertices,'faces':faces} != expected or maximum_index > vertices:
        raise ContractError('invalid_artifacts')


def validate_capture_artifacts(directory, mode, limits=LIMITS):
    from PIL import Image, ImageChops
    directory = Path(directory).resolve()
    result = []
    try:
        for name, media in ARTIFACTS[mode].items():
            path = directory/name
            if path.is_symlink() or not path.is_file() or path.resolve().parent != directory:
                raise ContractError('missing_artifacts')
            size = path.stat().st_size
            if not 0 < size <= limits.artifact:
                raise ContractError('too_large')
            result.append({'name': name, 'mediaType': media, 'bytes': size, 'sha256': sha256(path)})
        name = 'result.json' if mode == 'panorama' else 'generation.json'
        manifest = read_json(directory/name)
        if manifest.get('version') != 1 or manifest.get('status') != 'complete' or manifest.get('scaleStatus') != 'unverified':
            raise ContractError('invalid_artifacts')
        if mode == 'panorama':
            if manifest.get('format') != 'kantura-panorama' or manifest.get('hasDepth') is not False or manifest.get('canMeasure') is not False or manifest.get('projection') != 'equirectangular':
                raise ContractError('invalid_artifacts')
            declared = {item['name']: item for item in manifest['artifacts']}
            for item in result:
                if item['name'] != name and any(declared[item['name']].get(k) != item[k] for k in ['bytes','sha256']):
                    raise ContractError('invalid_artifacts')
            width, height = manifest['width'], manifest['height']
            fraction = manifest['coverageFraction']
            if type(width) is not int or type(height) is not int or not 512 <= width <= 4096 or width != 2*height or not isinstance(fraction, (int,float)) or not math.isfinite(fraction) or not 0 < fraction <= 1:
                raise ContractError('invalid_artifacts')
            with Image.open(directory/'panorama.png') as image, Image.open(directory/'coverage.png') as mask:
                if image.format != 'PNG' or mask.format != 'PNG' or image.mode != 'RGBA' or mask.mode != 'L' or image.size != (width,height) or mask.size != image.size:
                    raise ContractError('invalid_artifacts')
                if any(mask.histogram()[1:255]) or ImageChops.difference(image.getchannel('A'), mask).getbbox():
                    raise ContractError('invalid_artifacts')
                weights = [math.sin((y+.5)*math.pi/height) for y in range(height)]
                observed = sum(mask.crop((0,y,width,y+1)).histogram()[255]*weights[y] for y in range(height))/(width*sum(weights))
                if abs(observed-fraction) > 1e-6:
                    raise ContractError('invalid_artifacts')
            inspect_input(directory/'originals.zip', PANORAMA_LIMITS)
        else:
            if manifest.get('format') != 'kantura-generation' or not generated_provenance(manifest) or manifest.get('units') != 'arbitrary':
                raise ContractError('invalid_artifacts')
            for item in result:
                if item['name'] != name and any(manifest['outputs'][item['name']].get(k) != item[k] for k in ['bytes','sha256']):
                    raise ContractError('invalid_artifacts')
            ply = inspect_ply(directory/'generated-model.ply')
            glb = inspect_generated_glb(directory/'generated-model.glb')
            if ply != glb or any(manifest['statistics'][key] != value for key,value in ply.items()):
                raise ContractError('invalid_artifacts')
            inspect_generated_obj(directory/'generated-model.obj', ply)
            with zipfile.ZipFile(directory/'model.zip') as archive:
                entries = zip_entries(archive, limits.output_expanded, limits.artifact, 2)
                if {e.filename for e in entries} != {'model.glb','rtab-measure.json'}:
                    raise ContractError('invalid_artifacts')
                if archive.getinfo('rtab-measure.json').file_size > 1024**2:
                    raise ContractError('invalid_artifacts')
                project = json.loads(archive.read('rtab-measure.json'))
                if not generated_provenance(project) or project.get('calibrated') is not False or project.get('measurements') != []:
                    raise ContractError('invalid_artifacts')
                with archive.open('model.glb') as stream:
                    digest = hashlib.sha256()
                    for chunk in iter(lambda: stream.read(1024**2), b''):
                        digest.update(chunk)
                if digest.hexdigest() != sha256(directory/'generated-model.glb') or archive.testzip() is not None:
                    raise ContractError('invalid_artifacts')
        return result
    except ContractError:
        raise
    except Exception as error:
        raise ContractError('invalid_artifacts') from error
