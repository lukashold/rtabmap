"""Command-handoff regression tests with explicit engine test doubles.

These validate orchestration, not real reconstruction or visual accuracy.
"""
import contextlib
import io
import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import worker

MESH = ('ply\nformat ascii 1.0\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\n'
        'element face 1\nproperty list uchar int vertex_indices\nend_header\n0 0 0\n1 0 0\n0 1 0\n3 0 1 2\n')


class WorkerHandoff(unittest.TestCase):
    def test_interface_scene_texturing_uses_existing_cameras_and_explicit_mesh(self):
        with tempfile.TemporaryDirectory() as directory:
            job = Path(directory)
            (job / 'input.zip').write_bytes(b'test-only input; decoder mocked below')
            calls = []

            def fake_prepare(archive, image_dir, max_size):
                image_dir.mkdir(parents=True)
                return {'imageCount': 8, 'source': {'testDouble': True}}, []

            def fake_run(command, **options):
                calls.append(command)
                def argument(flag):
                    return Path(command[command.index(flag) + 1])
                if command[:2] == ['colmap', 'mapper']:
                    model = argument('--output_path') / '0'
                    model.mkdir()
                    for name, count in [('cameras.bin', 8), ('images.bin', 8), ('points3D.bin', 20)]:
                        (model / name).write_bytes(struct.pack('<Q', count))
                elif command[:2] == ['colmap', 'image_undistorter']:
                    argument('--output_path').mkdir()
                elif command[0] == 'InterfaceCOLMAP':
                    argument('-o').write_bytes(b'test-only cameras interface')
                elif command[0] == 'DensifyPointCloud':
                    argument('-o').write_bytes(b'test-only cameras interface')
                    argument('-o').with_suffix('.ply').write_text('test-only dense cloud', 'ascii')
                elif command[0] == 'ReconstructMesh':
                    argument('-o').with_suffix('.ply').write_text(MESH, 'ascii')
                    # Matches the pinned OpenMVS default: no scene_mesh.mvs.
                    self.assertFalse(argument('-o').exists())
                elif command[0] == 'TextureMesh':
                    self.assertTrue(argument('-i').is_file())
                    self.assertEqual(argument('-i').name, 'scene_dense.mvs')
                    self.assertEqual(argument('--mesh-file').read_text('ascii'), MESH)
                    argument('-o').with_suffix('.obj').write_text('# TEST DOUBLE\nv 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n', 'ascii')
                return SimpleNamespace(returncode=0)

            with mock.patch.object(worker, 'prepare_images', side_effect=fake_prepare), mock.patch.object(worker.shutil, 'which', return_value='/test/engine'), mock.patch.object(worker.subprocess, 'run', side_effect=fake_run), contextlib.redirect_stdout(io.StringIO()):
                worker.reconstruct(job, 'mesh')
            self.assertEqual([command[0] for command in calls][-3:], ['DensifyPointCloud', 'ReconstructMesh', 'TextureMesh'])
            self.assertTrue((job / 'artifacts' / 'mesh.zip').is_file())
            self.assertEqual((job / 'artifacts' / 'model.ply').read_text('ascii'), MESH)
            self.assertFalse((job / 'work' / 'scene_mesh.mvs').exists())

    def test_unexpected_worker_errors_keep_details_in_private_log_only(self):
        with tempfile.TemporaryDirectory() as directory:
            stderr = io.StringIO()
            with mock.patch.object(sys, 'argv', ['worker.py', '--job-dir', directory, '--mode', 'mesh']), mock.patch.object(worker, 'reconstruct', side_effect=RuntimeError('private diagnostic detail')), contextlib.redirect_stderr(stderr):
                self.assertEqual(worker.main(), 1)
            error = json.loads((Path(directory) / 'error.json').read_text('utf-8'))
            self.assertEqual(error, {'code': 'reconstruction_failed'})
            self.assertIn('private diagnostic detail', stderr.getvalue())


if __name__ == '__main__':
    unittest.main()
