"""Command-handoff regression tests with explicit engine test doubles.

These validate orchestration, not real reconstruction or visual accuracy.
"""
import contextlib
import io
import hashlib
import json
import struct
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import worker

MESH = ('ply\nformat ascii 1.0\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\n'
        'element face 1\nproperty list uchar int vertex_indices\nend_header\n0 0 0\n1 0 0\n0 1 0\n3 0 1 2\n')
CAMERA = {'id': 0, 'img_name': 'frame_00001.jpg', 'width': 256, 'height': 256,
          'fx': 300, 'fy': 300, 'position': [0, 0, 0],
          'rotation': [[1, 0, 0], [0, 1, 0], [0, 0, 1]]}


class WorkerHandoff(unittest.TestCase):
    def test_actual_engine_diagnostic_format_is_bounded_and_preserves_final_loss(self):
        metrics = {'lossSamples': [], 'validationPSNR': None, 'validationLoss': None}
        for step in range(1200):
            worker.record_training_line(metrics, f'Step {step}: 0.125 [50%]')
        worker.record_training_line(metrics, 'frame_00001.jpg validation loss: 0.234')
        worker.record_training_line(metrics, 'frame_00001.jpg validation PSNR: 21.75')
        for line in ['Step 1201: NaN', 'Step 1201: 1e999', 'Step 1201: +e', 'validation PSNR: inf', 'validation loss: nan']:
            worker.record_training_line(metrics, line)
        self.assertEqual(len(metrics['lossSamples']), 1000)
        self.assertEqual(metrics['lastLoss'], {'step': 1199, 'loss': .125})
        self.assertEqual(metrics['validationPSNR'], 21.75)
        self.assertEqual(metrics['validationLoss'], .234)

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
                elif command[0] == 'RefineMesh':
                    self.assertTrue(argument('-i').is_file())
                    self.assertEqual(argument('--mesh-file').read_text('ascii'), MESH)
                    argument('-o').with_suffix('.ply').write_text(MESH, 'ascii')
                elif command[0] == 'TextureMesh':
                    self.assertTrue(argument('-i').is_file())
                    self.assertEqual(argument('-i').name, 'scene_dense.mvs')
                    self.assertEqual(argument('--mesh-file').read_text('ascii'), MESH)
                    self.assertEqual(argument('--mesh-file').name, 'scene_refined.ply')
                    argument('-o').with_suffix('.obj').write_text('# TEST DOUBLE\nmtllib model.mtl\nv 0 0 0\nv 1 0 0\nv 0 1 0\nusemtl material_0\nf 1 2 3\n', 'ascii')
                    argument('-o').with_suffix('.mtl').write_text('newmtl material_0\nKd 1 1 1\nTr 1.000000\nillum 1\n', 'ascii')
                return SimpleNamespace(returncode=0)

            with mock.patch.object(worker, 'prepare_images', side_effect=fake_prepare), mock.patch.object(worker, 'sfm_report', return_value=({'testDouble': True}, [CAMERA])), mock.patch.object(worker.shutil, 'which', return_value='/test/engine'), mock.patch.object(worker.subprocess, 'run', side_effect=fake_run), contextlib.redirect_stdout(io.StringIO()):
                worker.reconstruct(job, 'mesh')
            self.assertEqual([command[0] for command in calls][-4:], ['DensifyPointCloud', 'ReconstructMesh', 'RefineMesh', 'TextureMesh'])
            self.assertTrue((job / 'artifacts' / 'mesh.zip').is_file())
            self.assertEqual((job / 'artifacts' / 'model.ply').read_text('ascii'), MESH)
            self.assertFalse((job / 'work' / 'scene_mesh.mvs').exists())
            manifest = json.loads((job / 'artifacts' / 'reconstruction.json').read_text('utf-8'))
            patch = manifest['enginePatches']['openmvs'][0]
            patch_bytes = Path(worker.__file__).with_name('patches').joinpath(patch['file']).read_bytes()
            self.assertEqual(patch['sha256'], hashlib.sha256(patch_bytes).hexdigest())
            self.assertEqual(patch['baseRevision'], manifest['engines']['openmvs']['revision'])
            self.assertEqual((job / 'input.zip').read_bytes(), b'test-only input; decoder mocked below')
            with zipfile.ZipFile(job / 'artifacts' / 'mesh.zip') as archive:
                self.assertEqual(archive.read('model.mtl'), b'newmtl material_0\nKd 1 1 1\nd 1.000000\nillum 1\n')
                self.assertEqual(archive.read('model.obj'), (job / 'work' / 'textured' / 'model.obj').read_bytes())
                self.assertEqual(archive.read('model.obj').decode('ascii').splitlines()[-5:], ['v 0 0 0', 'v 1 0 0', 'v 0 1 0', 'usemtl material_0', 'f 1 2 3'])
            normalization = manifest['materialNormalization']
            self.assertEqual(normalization['files'], [{'file': 'model.mtl', 'materials': 1}])
            self.assertFalse(normalization['geometryChanged'])
            self.assertEqual(json.loads((job / 'artifacts' / 'cameras.json').read_text('utf-8')), [CAMERA])
            self.assertIn('right/down/forward', manifest['cameraConvention'])

    def test_opacity_normalization_only_changes_known_generated_rgb_atlas_lines(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            material = folder / 'model.mtl'
            material.write_bytes(b'newmtl a\nTr 1.000000\nnewmtl b\nTr 0.500000\n# Tr 1.000000\nKd 1 0 1\n')
            model = folder / 'model.obj'
            model.write_bytes(b'# Tr 1.000000\nv 0 0 0\n')
            record = worker.normalize_openmvs_materials([material, model], folder)
            self.assertEqual(material.read_bytes(), b'newmtl a\nd 1.000000\nnewmtl b\nTr 0.500000\n# Tr 1.000000\nKd 1 0 1\n')
            self.assertEqual(model.read_bytes(), b'# Tr 1.000000\nv 0 0 0\n')
            self.assertEqual(record['files'], [{'file': 'model.mtl', 'materials': 1}])
            self.assertEqual(worker.normalize_openmvs_materials([material, model], folder)['files'], [])

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
