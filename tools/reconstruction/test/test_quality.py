import json
from contextlib import closing
import math
import sqlite3
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from contract import ContractError
from quality import image_quality, near_duplicate, camera_hint, assign_camera_groups, sfm_report


class QualityDiagnostics(unittest.TestCase):
    def test_texture_blur_and_duplicate_scores_are_observable_not_accuracy_claims(self):
        from PIL import Image, ImageFilter
        image = Image.new('L', (128, 128))
        image.putdata([255 if ((x//8+y//8) % 2) else 0 for y in range(128) for x in range(128)])
        sharp, first = image_quality(image)
        blurred, second = image_quality(image.filter(ImageFilter.GaussianBlur(5)))
        self.assertGreater(sharp['laplacianVariance128'], blurred['laplacianVariance128'] * 10)
        self.assertTrue(near_duplicate(first, first, sharp, sharp))
        self.assertFalse(near_duplicate(first, second, sharp, blurred))
        self.assertEqual(len(sharp['dHash64']), 16)

    def test_camera_hint_needs_plausible_exif_not_only_dimensions(self):
        from PIL import Image
        image = Image.new('RGB', (64, 64))
        self.assertNotIn('signature', camera_hint(image))
        image.getexif().update({271: 'Example', 272: 'Camera', 42036: 'Fixed lens', 37386: 12, 41989: 24, 42033: 'private-serial'})
        hint = camera_hint(image)
        self.assertIn('signature', hint)
        self.assertNotIn('private-serial', json.dumps(hint))
        image.getexif()[37386] = 24
        self.assertNotEqual(camera_hint(image)['signature'], hint['signature'])

    def database(self, root):
        database = root / 'database.db'
        with closing(sqlite3.connect(database)) as connection, connection:
            connection.executescript('CREATE TABLE cameras(camera_id INTEGER PRIMARY KEY,model INTEGER,width INTEGER,height INTEGER); CREATE TABLE images(image_id INTEGER PRIMARY KEY,camera_id INTEGER,name TEXT);')
            for i in range(1, 4):
                connection.execute('INSERT INTO cameras VALUES(?,?,?,?)', (i, 2, 640, 480))
                connection.execute('INSERT INTO images VALUES(?,?,?)', (i, i, f'frame_{i:05}.jpg'))
        return database

    def test_auto_camera_sharing_requires_matching_exif_and_preserves_unknown_camera(self):
        with tempfile.TemporaryDirectory() as directory:
            database = self.database(Path(directory))
            records = [{'file': f'images/frame_{i:05}.jpg', 'width': 640, 'height': 480,
                        'cameraHint': {'signature': 'same-fixed-lens'} if i < 3 else {}} for i in range(1, 4)]
            result = assign_camera_groups(database, records, 'auto')
            with closing(sqlite3.connect(database)) as connection, connection:
                ids = [row[0] for row in connection.execute('SELECT camera_id FROM images ORDER BY image_id')]
            self.assertEqual(ids, [1, 1, 3])
            self.assertEqual([group['images'] for group in result['groups']], [2, 1])

    def test_unknown_metadata_never_shares_unless_operator_explicitly_requests_single(self):
        with tempfile.TemporaryDirectory() as directory:
            database = self.database(Path(directory))
            records = [{'file': f'images/frame_{i:05}.jpg', 'width': 640, 'height': 480} for i in range(1, 4)]
            result = assign_camera_groups(database, records)
            self.assertEqual(len(result['groups']), 3)
            self.assertEqual(len(assign_camera_groups(database, records, 'single')['groups']), 1)
            records[0]['width'] = 100
            with self.assertRaises(ContractError):
                assign_camera_groups(database, records, 'single')

    def model(self, root):
        (root / 'cameras.bin').write_bytes(struct.pack('<QiiQQdddd', 1, 1, 2, 640, 480, 600, 320, 240, 0))
        q = math.sqrt(.5)
        (root / 'images.bin').write_bytes(struct.pack('<Qidddddddi', 1, 7, q, 0, 0, q, 1, 2, 3, 1) + b'frame_00001.jpg\0' + struct.pack('<Qddq', 1, 320, 240, 1))
        points = struct.pack('<Q', 2)
        for i, error in enumerate([.2, .6]):
            points += struct.pack('<QdddBBBdQiiii', i+1, 0, 0, 1, 120, 120, 120, error, 2, 7, 0, 8, 1)
        (root / 'points3D.bin').write_bytes(points)

    def test_sfm_binary_reports_errors_and_true_camera_to_world_convention(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.model(root)
            report, cameras = sfm_report(root, 2)
            self.assertEqual(report['registeredFraction'], .5)
            self.assertAlmostEqual(report['reprojectionErrorPixels']['mean'], .4)
            self.assertEqual(report['reprojectionErrorPixels']['p95'], .6)
            self.assertEqual(report['meanTrackLength'], 2)
            for actual, expected in zip(cameras[0]['position'], [-2, 1, -3]):
                self.assertAlmostEqual(actual, expected)
            self.assertAlmostEqual(cameras[0]['rotation'][0][1], 1)
            self.assertAlmostEqual(cameras[0]['rotation'][1][0], -1)
            self.assertFalse(report['metricAccuracyValidated'])

    def test_truncated_sfm_model_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.model(root)
            (root / 'points3D.bin').write_bytes(struct.pack('<Q', 20))
            with self.assertRaises(ContractError):
                sfm_report(root, 1)


if __name__ == '__main__':
    unittest.main()
