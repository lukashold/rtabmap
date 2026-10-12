"""TEST DOUBLE ONLY: writes a tiny triangle, never evidence of reconstruction."""
import argparse
import json
import sys
import time
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from contract import sha256


def artifacts(directory, mode='mesh'):
    if mode in {'panorama','generated'}:
        from capture_fixtures import artifacts as capture_artifacts
        return capture_artifacts(directory, mode)
    directory.mkdir(parents=True, exist_ok=True)
    if mode == 'mesh':
        (directory / 'model.ply').write_text('ply\nformat ascii 1.0\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\nelement face 1\nproperty list uchar int vertex_indices\nend_header\n0 0 0\n1 0 0\n0 1 0\n3 0 1 2\n', 'ascii')
        with zipfile.ZipFile(directory / 'mesh.zip', 'w') as archive:
            archive.writestr('model.obj', '# TEST DOUBLE ONLY\nv 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n')
    else:
        props = ['x', 'y', 'z', 'f_dc_0', 'f_dc_1', 'f_dc_2', 'opacity', 'scale_0', 'scale_1', 'scale_2', 'rot_0', 'rot_1', 'rot_2', 'rot_3']
        (directory / 'splat.ply').write_text('ply\nformat ascii 1.0\nelement vertex 1\n' + ''.join('property float ' + p + '\n' for p in props) + 'end_header\n' + ' '.join('0' for _ in props) + '\n', 'ascii')
        (directory / 'cameras.json').write_text(json.dumps([{'id': 0, 'img_name': 'TEST', 'width': 10, 'height': 10, 'fx': 1, 'fy': 1, 'position': [0, 0, 0], 'rotation': [[1, 0, 0], [0, 1, 0], [0, 0, 1]]}]), 'utf-8')
    manifest = {'format': 'kantura-reconstruction', 'version': 1, 'mode': mode, 'scaleStatus': 'unverified', 'testDouble': True, 'files': {p.name: sha256(p) for p in directory.iterdir() if p.name != 'reconstruction.json'}}
    (directory / 'reconstruction.json').write_text(json.dumps(manifest), 'utf-8')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--behavior', choices=['valid', 'missing', 'failure', 'sleep', 'oversize'], default='valid')
    parser.add_argument('--job-dir', type=Path, required=True)
    parser.add_argument('--mode', required=True)
    parser.add_argument('--device')
    parser.add_argument('--input-type', default='photos')
    parser.add_argument('--profile', default='auto')
    parser.add_argument('--foreground-isolated', action='store_true')
    args = parser.parse_args()
    scratch = args.job_dir / 'work' / 'generated'
    scratch.mkdir(parents=True)
    (scratch / 'intermediate.bin').write_bytes(b'test-only intermediate')
    print('TEST DOUBLE worker started', flush=True)
    print('input-type=' + args.input_type + ' profile=' + args.profile, flush=True)
    if args.behavior == 'failure':
        return 7
    if args.behavior == 'sleep':
        (args.job_dir / 'progress.json').write_text('{"stage":"matching"}', 'utf-8')
        time.sleep(60)
    if args.behavior == 'oversize':
        (scratch / 'large.bin').write_bytes(b'x' * 32768)
        time.sleep(60)
    if args.behavior == 'valid':
        artifacts(args.job_dir / 'artifacts', args.mode)
    return 0


if __name__ == '__main__':
    sys.exit(main())
