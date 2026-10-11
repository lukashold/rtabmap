"""Real COLMAP/OpenMVS/OpenSplat worker. Missing programs or bad data fail closed."""
import argparse
import json
import math
import os
import shutil
import struct
import subprocess
import sys
import traceback
import warnings
import zipfile
from datetime import datetime, timezone
from pathlib import Path

from contract import ARTIFACTS, LIMITS, ContractError, inspect_input, sha256, validate_artifacts


def atomic_json(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, allow_nan=False), 'utf-8')
    os.replace(temporary, path)


def prepare_images(archive_path, image_dir, max_size=1600):
    try:
        from PIL import Image, ImageOps
        from pillow_heif import register_heif_opener
    except ImportError as error:
        raise ContractError('worker_unavailable') from error
    register_heif_opener()
    Image.MAX_IMAGE_PIXELS = 60_000_000
    info = inspect_input(archive_path)
    records = []
    image_dir.mkdir(parents=True)
    with warnings.catch_warnings(), zipfile.ZipFile(archive_path) as archive:
        warnings.simplefilter('error', Image.DecompressionBombWarning)
        for index, name in enumerate(info['images']):
            try:
                with archive.open(name) as stream, Image.open(stream) as original:
                    if original.format not in {'JPEG', 'PNG', 'HEIF'} or original.width < 32 or original.height < 32:
                        raise ContractError('unsupported_image')
                    original.load()
                    image = ImageOps.exif_transpose(original).convert('RGB')
                    image.thumbnail((max_size, max_size), Image.Resampling.LANCZOS)
                    filename = f'frame_{index + 1:05}.jpg'
                    # Originals and Apple metadata remain in input.zip. Converted
                    # intrinsics/poses are estimated, never invented from EXIF.
                    image.save(image_dir / filename, 'JPEG', quality=95)
                    records.append({'sourceFile': name, 'file': 'images/' + filename, 'sourceFormat': original.format, 'encodedFormat': 'JPEG', 'width': image.width, 'height': image.height, 'metadataPreserved': 'original-archive-only'})
            except ContractError:
                raise
            except Exception as error:
                raise ContractError('unsupported_image') from error
    return info, records


def count_binary(path):
    try:
        with path.open('rb') as stream:
            return struct.unpack('<Q', stream.read(8))[0]
    except (OSError, struct.error):
        return 0


def normalize_openmvs_materials(files, folder):
    """Correct the pinned RGB-atlas exporter's inverse opacity convention.

    Called only on newly generated TextureMesh outputs, never user imports.
    OpenMVS's RGB atlas has no transparency channel. Its hard-coded Tr 1
    otherwise makes every face invisible in standards-conforming MTL readers.
    """
    changed = []
    for path in files:
        if path.suffix.lower() != '.mtl':
            continue
        before = path.read_text('utf-8')
        lines = before.splitlines()
        count = sum(line.strip() == 'Tr 1.000000' for line in lines)
        if not count:
            continue
        after = '\n'.join('d 1.000000' if line.strip() == 'Tr 1.000000' else line for line in lines) + '\n'
        path.write_bytes(after.encode('utf-8'))
        changed.append({'file': path.relative_to(folder).as_posix(), 'materials': count})
    return {'producer': 'OpenMVS v2.3.0 RGB atlas exporter',
            'rule': 'Tr 1.000000 -> d 1.000000 (opaque RGB atlas)',
            'files': changed, 'geometryChanged': False}


def reconstruct(job_dir, mode, device='cpu', iterations=1000, threads=2, image_max_side=1600):
    job_dir = Path(job_dir).resolve()
    if not (job_dir / 'input.zip').is_file() or mode not in ARTIFACTS:
        raise ContractError('invalid_archive')
    if (job_dir / 'work').exists() or (job_dir / 'artifacts').exists():
        raise ContractError('reconstruction_failed')  # Never reuse stale outputs.
    work = job_dir / 'work'
    work.mkdir()
    output = job_dir / 'artifacts'
    output.mkdir()

    def phase(stage):
        atomic_json(job_dir / 'progress.json', {'stage': stage})

    commands = []

    def run(stage, executable, *args, cwd=work):
        if not shutil.which(executable):
            raise ContractError('worker_unavailable')
        phase(stage)
        command = [executable] + [str(a) for a in args]
        print(json.dumps({'stage': stage, 'program': executable}), flush=True)
        # Shell-free arguments, all paths generated inside the private job folder.
        result = subprocess.run(command, cwd=cwd, stdin=subprocess.DEVNULL, check=False,
                                env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'OMP_NUM_THREADS': str(threads)})
        commands.append({'stage': stage, 'program': executable, 'exitCode': result.returncode})
        print(json.dumps({'stage': stage, 'program': executable, 'exitCode': result.returncode}), flush=True)
        if result.returncode:
            raise ContractError('reconstruction_failed')

    phase('preparing')
    info, image_records = prepare_images(job_dir / 'input.zip', work / 'images', image_max_side)
    database = work / 'database.db'
    sparse = work / 'sparse'
    sparse.mkdir()
    run('features', 'colmap', 'feature_extractor', '--database_path', database, '--image_path', work / 'images', '--ImageReader.camera_model', 'SIMPLE_RADIAL', '--SiftExtraction.use_gpu', '0', '--SiftExtraction.num_threads', threads, '--SiftExtraction.max_image_size', image_max_side)
    run('matching', 'colmap', 'exhaustive_matcher', '--database_path', database, '--SiftMatching.use_gpu', '0', '--SiftMatching.num_threads', threads)
    run('mapping', 'colmap', 'mapper', '--database_path', database, '--image_path', work / 'images', '--output_path', sparse, '--Mapper.num_threads', threads)
    models = [p for p in sparse.iterdir() if p.is_dir() and (p / 'cameras.bin').is_file()]
    if not models:
        raise ContractError('insufficient_registration')
    best = max(models, key=lambda p: count_binary(p / 'images.bin'))
    registered = count_binary(best / 'images.bin')
    points = count_binary(best / 'points3D.bin')
    if registered < max(6, math.ceil(info['imageCount'] * .6)) or points < 10:
        raise ContractError('insufficient_registration')
    dense = work / 'undistorted'
    run('undistorting', 'colmap', 'image_undistorter', '--image_path', work / 'images', '--input_path', best, '--output_path', dense, '--output_type', 'COLMAP', '--max_image_size', image_max_side)
    material_normalization = None
    if mode == 'mesh':
        scene = work / 'scene.mvs'
        dense_scene = work / 'scene_dense.mvs'
        mesh_scene = work / 'scene_mesh.mvs'
        textured = work / 'textured'
        textured.mkdir()
        run('dense', 'InterfaceCOLMAP', '-i', dense, '-o', scene, '--image-folder', dense / 'images')
        run('dense', 'DensifyPointCloud', '-i', scene, '-o', dense_scene, '--resolution-level', '1', '--max-resolution', image_max_side, '--min-resolution', min(320, image_max_side), '--max-threads', threads)
        run('meshing', 'ReconstructMesh', '-i', dense_scene, '-o', mesh_scene, '--max-threads', threads)
        model = work / 'scene_mesh.ply'
        if not model.is_file():
            raise ContractError('invalid_artifacts')
        shutil.copyfile(model, output / 'model.ply')
        # OpenMVS 2.3 ReconstructMesh does not save scene_mesh.mvs when the
        # input is interface format and archive-type retains its -1 default.
        # Keep that camera scene and provide its reconstructed mesh explicitly.
        run('texturing', 'TextureMesh', '-i', dense_scene, '--mesh-file', model, '-o', textured / 'model.mvs', '--export-type', 'obj', '--resolution-level', '1', '--min-resolution', '320', '--max-threads', threads)
        files = [p for p in textured.rglob('*') if p.is_file() and p.suffix.lower() in {'.obj', '.mtl', '.png', '.jpg', '.jpeg'}]
        if not any(p.suffix == '.obj' for p in files) or sum(p.stat().st_size for p in files) > LIMITS.output_expanded:
            raise ContractError('invalid_artifacts')
        material_normalization = normalize_openmvs_materials(files, textured)
        with zipfile.ZipFile(output / 'mesh.zip', 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            for path in files:
                archive.write(path, path.relative_to(textured).as_posix())
    else:
        # OpenSplat's COLMAP reader expects sparse/0 below the images root.
        normalized = dense / 'sparse' / '0'
        normalized.mkdir()
        for name in ('cameras.bin', 'images.bin', 'points3D.bin'):
            shutil.copyfile(dense / 'sparse' / name, normalized / name)
        arguments = [dense, '-n', iterations, '-o', output / 'splat.ply', '--output-cameras', output / 'cameras.json']
        if device == 'cpu':
            arguments.append('--cpu')
        elif device == 'cuda':
            if not shutil.which('nvidia-smi') or subprocess.run(['nvidia-smi', '-L'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
                raise ContractError('worker_unavailable')
        elif device == 'mps' and sys.platform != 'darwin':
            raise ContractError('worker_unavailable')
        run('training', 'opensplat', *arguments)
    phase('validating')
    pins = json.loads(Path(__file__).with_name('pins.json').read_text('utf-8'))
    manifest = {'format': 'kantura-reconstruction', 'version': 1, 'mode': mode,
                'createdAt': datetime.now(timezone.utc).isoformat(), 'scaleStatus': 'unverified',
                'coordinateSystem': 'COLMAP arbitrary similarity frame; not registered to RoomPlan',
                'source': info['source'], 'images': image_records, 'imageCount': info['imageCount'],
                'registeredImages': registered, 'sparsePoints': points, 'discardedSparseModels': len(models) - 1,
                'commands': commands, 'engines': pins['sources'],
                'enginePatches': json.loads(Path(__file__).with_name('patches').joinpath('manifest.json').read_text('utf-8')),
                'materialNormalization': material_normalization,
                'deviceRequested': device if mode == 'splat' else 'cpu',
                'splatIterations': iterations if mode == 'splat' else None, 'imageMaxSide': image_max_side,
                'files': {name: sha256(output / name) for name in ARTIFACTS[mode] if name != 'reconstruction.json'}}
    atomic_json(output / 'reconstruction.json', manifest)
    validate_artifacts(output, mode)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--job-dir', required=True, type=Path)
    parser.add_argument('--mode', required=True, choices=sorted(ARTIFACTS))
    parser.add_argument('--device', choices=['cpu', 'cuda', 'mps'], default='cpu')
    parser.add_argument('--iterations', type=int, default=int(os.environ.get('SPLAT_ITERATIONS', '1000')))
    parser.add_argument('--threads', type=int, default=int(os.environ.get('WORKER_THREADS', '2')))
    parser.add_argument('--image-max-side', type=int, default=int(os.environ.get('IMAGE_MAX_SIDE', '1600')))
    args = parser.parse_args()
    if not 1 <= args.iterations <= 30000 or not 1 <= args.threads <= 64 or not 256 <= args.image_max_side <= 4096:
        parser.error('iterations must be 1–30000, threads 1–64 and image max side 256–4096')
    try:
        reconstruct(args.job_dir, args.mode, args.device, args.iterations, args.threads, args.image_max_side)
    except Exception as error:
        if not isinstance(error, ContractError):
            traceback.print_exc()  # Private worker.log, never the public API.
        code = error.code if isinstance(error, ContractError) else 'reconstruction_failed'
        atomic_json(args.job_dir / 'error.json', {'code': code})
        print('Reconstruction failed: ' + code, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
