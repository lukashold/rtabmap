import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


fixture = load('distinct', ROOT / 'procedural-distinct.py')
quality = load('evaluation', ROOT / 'reconstruction-quality.py')


class DistinctFixtureTests(unittest.TestCase):
    def test_world_ground_has_no_old_half_or_unit_tile_repetition(self):
        z, x = np.mgrid[-4:4:64j, -4:4:64j]
        first = fixture.ground_rgb(x, z).astype(float)
        for shift in (.5, 1., 2., 4.):
            shifted = fixture.ground_rgb(x + shift, z).astype(float)
            self.assertGreater(float(np.abs(first - shifted).mean()), 20)
        np.testing.assert_array_equal(first, fixture.ground_rgb(x, z))

    def test_face_feature_layouts_are_distinct_and_deterministic(self):
        faces = fixture.face_textures()
        self.assertEqual(len({hashlib.sha256(face.tobytes()).hexdigest() for face in faces}), 6)
        for first, second in [(0, 1), (2, 3), (4, 5)]:
            a = np.asarray(Image.fromarray(faces[first]).convert('L').resize((64, 64))).astype(float)
            b = np.asarray(Image.fromarray(faces[second]).convert('L').resize((64, 64))).astype(float)
            self.assertGreater(float(np.abs(a - b).mean()), 20)
        np.testing.assert_array_equal(faces[0], fixture.face_textures()[0])

    def test_real_jpegs_distinguish_opposite_views_and_truth_stays_outside_zip(self):
        with tempfile.TemporaryDirectory() as folder:
            archive = Path(folder) / 'images.zip'
            truth_path = Path(folder) / 'truth.json'
            truth = fixture.generate(archive, truth_path, size=128, count=16)
            first_bytes = archive.read_bytes()
            fixture.generate(archive, truth_path, size=128, count=16)
            self.assertEqual(first_bytes, archive.read_bytes())
            with zipfile.ZipFile(archive) as data:
                self.assertEqual(len(data.namelist()), 17)
                manifest = json.loads(data.read('manifest.json'))
                self.assertNotIn('cameras', manifest)
                self.assertNotIn('rotation', json.dumps(manifest))
                images = [np.asarray(Image.open(io.BytesIO(data.read(record['file']))).convert('L').resize((64, 64))).astype(float) for record in manifest['images']]
                differences = [float(np.abs(images[i] - images[i + 8]).mean()) for i in range(8)]
                self.assertGreater(min(differences), 10)
            self.assertEqual(json.loads(truth_path.read_text()), truth)
            self.assertEqual(len(truth['opposingPairs']), 8)
            np.testing.assert_allclose(truth['cameras'][0]['position'], [3.8, 1.3, 0])
            self.assertEqual(truth['cubeBounds'], [[-1, -1, -1], [1, 1, 1]])

    def test_collapse_diagnostic_is_scale_invariant_and_uses_exact_known_pairs(self):
        cameras = []
        truth = {'cameras': [], 'opposingPairs': []}
        for i in range(16):
            angle = i * 2 * np.pi / 16
            name = f'frame_{i+1:05d}.jpg'
            position = [3.8 * np.cos(angle), 1.3, 3.8 * np.sin(angle)]
            truth['cameras'].append({'preparedFile': name, 'position': position})
            cameras.append({'img_name': name, 'position': position.copy()})
            if i < 8:
                truth['opposingPairs'].append({'first': name, 'second': f'frame_{i+9:05d}.jpg'})
        self.assertEqual(quality.camera_coincidence(truth, cameras)['coincidentPairCount'], 0)
        for i in range(8):
            cameras[i + 8]['position'] = cameras[i]['position'].copy()
        result = quality.camera_coincidence(truth, cameras)
        self.assertEqual(result['coincidentPairCount'], 8)
        self.assertEqual(result['opposingPairsChecked'], 8)
        scaled = [{**camera, 'position': (np.asarray(camera['position']) * 31 + [8, -4, 2]).tolist()} for camera in cameras]
        self.assertEqual(quality.camera_coincidence(truth, scaled)['coincidentPairs'], [dict(pair, estimatedPositionDistance=0.) for pair in result['coincidentPairs']])
        one_separate = [{**camera, 'position': [0., 0., 0.]} for camera in cameras]
        one_separate[-1]['position'] = [10., 0., 0.]
        self.assertEqual(quality.camera_coincidence(truth, one_separate)['coincidentPairCount'], 7)


if __name__ == '__main__':
    unittest.main()
