import io
import json
import math
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import cv2 as cv
import numpy as np
from PIL import Image

from stitch import StitchError, compose_sphere, estimate_cameras, process, read_dataset, safe_member, sha256
from synthetic import make_fixture, write_fixture


class PanoramaTests(unittest.TestCase):
    def test_archive_paths_and_links_are_rejected(self):
        for name in ['../a.jpg', '/a.jpg', 'C:/a.jpg', 'Images\\a.jpg', 'Images/./a.jpg', 'Images/../a.jpg']:
            with self.subTest(name=name), self.assertRaises(StitchError):
                safe_member(zipfile.ZipInfo(name))
        info = zipfile.ZipInfo('linked.jpg')
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        with self.assertRaises(StitchError):
            safe_member(info)

    def test_bad_archive_members_and_duplicate_paths_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'bad.zip'
            image = io.BytesIO()
            Image.new('RGB', (256, 128)).save(image, format='PNG')
            for entries in [[('file.svg', b'<svg/>')], [('A.png', image.getvalue()), ('a.png', image.getvalue())], [('manifest.json', b'[]')]]:
                with zipfile.ZipFile(path, 'w') as archive:
                    for name, data in entries:
                        archive.writestr(name, data)
                with self.assertRaises((StitchError, ValueError)):
                    read_dataset(path)

    def test_real_heic_decode_and_exif_orientation(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'formats.zip'
            image = Image.new('RGB', (256, 128), '#cc8044')
            heic, jpeg = io.BytesIO(), io.BytesIO()
            image.save(heic, format='HEIF')
            orientation = image.getexif()
            orientation[274] = 6
            image.save(jpeg, format='JPEG', exif=orientation)
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr('photo.heic', heic.getvalue())
                archive.writestr('rotated.jpg', jpeg.getvalue())
            images, originals, _ = read_dataset(path)
            self.assertEqual(images[0].shape[:2], (128, 256))
            self.assertEqual(images[1].shape[:2], (256, 128))
            self.assertEqual(originals[1]['originalWidth'], 256)
            self.assertEqual(originals[1]['workingWidth'], 128)

    def test_archive_byte_limits_precede_image_decoder(self):
        with tempfile.TemporaryDirectory() as folder:
            path = write_fixture(Path(folder) / 'photos.zip')
            with patch('stitch.MAX_ZIP', 8), self.assertRaisesRegex(StitchError, '200 MiB'):
                read_dataset(path)
            with patch('stitch.MAX_EXPANDED', 8), self.assertRaisesRegex(StitchError, 'expanded-size'):
                read_dataset(path)

    def test_pixel_dimensions_rejected_before_full_decode(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'small.zip'
            image = io.BytesIO()
            Image.new('RGB', (64, 64)).save(image, format='PNG')
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr('tiny.png', image.getvalue())
            with self.assertRaisesRegex(StitchError, 'dimensions'):
                read_dataset(path)

    def test_known_rotations_preserve_full_sphere_coordinates_and_unknown_poles(self):
        truth, images, cameras = make_fixture()
        panorama, mask, fraction = compose_sphere(images, cameras, 1024)
        self.assertEqual(panorama.shape, (512, 1024, 4))
        self.assertTrue(np.all(mask[:20] == 0))
        self.assertTrue(np.all(mask[-20:] == 0))
        self.assertTrue(np.all(mask[230:280] == 255))
        self.assertTrue(np.array_equal(panorama[:, :, 3], mask))
        self.assertGreater(fraction, 0.45)
        self.assertLess(fraction, 0.75)
        # A fixed angular canvas retains known texture coordinates, even at seam.
        for start, stop in [(0, 10), (450, 580), (1010, 1024)]:
            error = np.abs(panorama[200:310, start:stop, :3].astype(float) - truth[200:310, start:stop].astype(float))
            self.assertLess(float(error.mean()), 24)

    def test_partial_capture_is_not_stretched_to_fill_unobserved_longitudes(self):
        _, images, cameras = make_fixture((-25, 0, 25))
        panorama, mask, fraction = compose_sphere(images, cameras, 1024)
        self.assertLess(fraction, 0.4)
        self.assertEqual(int(mask[:, :150].max()), 0)
        self.assertEqual(int(mask[:, -150:].max()), 0)
        self.assertTrue(np.all(panorama[mask == 0] == 0))

    def test_real_feature_matching_recovers_relative_rotations(self):
        _, images, truth = make_fixture()
        cameras, matches = estimate_cameras(images)
        self.assertEqual(len(cameras), 8)
        self.assertGreaterEqual(len(matches), 7)
        for i in range(8):
            known = truth[0].R.T @ truth[i].R
            actual = cameras[0].R.T @ cameras[i].R
            delta = actual @ known.T
            angle = math.degrees(math.acos(float(np.clip((np.trace(delta) - 1) / 2, -1, 1))))
            self.assertLess(angle, 3, 'rotation error for photo %d' % i)

    def test_featureless_photos_fail_instead_of_generating_a_panorama(self):
        images = [np.zeros((360, 480, 3), np.uint8) for _ in range(3)]
        with self.assertRaisesRegex(StitchError, 'visual detail'):
            estimate_cameras(images)

    def test_disconnected_photos_are_not_silently_discarded(self):
        _, images, _ = make_fixture((0, 45, 180))
        with self.assertRaisesRegex(StitchError, 'connected panorama'):
            estimate_cameras(images)

    def test_real_end_to_end_stitch_preserves_originals_and_checksums(self):
        with tempfile.TemporaryDirectory() as folder:
            source = write_fixture(Path(folder) / 'photos.zip')
            output = Path(folder) / 'result'
            result = process(source, output, width=1024)
            self.assertEqual(result['status'], 'complete')
            self.assertFalse(result['hasDepth'])
            self.assertFalse(result['canMeasure'])
            self.assertEqual(result['scaleStatus'], 'unverified')
            self.assertEqual(result['sourceManifest']['source'], 'kantura-synthetic-panorama-validation')
            self.assertEqual(sha256(source), sha256(output / 'originals.zip'))
            self.assertEqual(len(result['images']), 8)
            for artifact in result['artifacts']:
                self.assertEqual(artifact['sha256'], sha256(output / artifact['name']))
            with Image.open(output / 'panorama.png') as panorama:
                self.assertEqual(panorama.size, (1024, 512))
                self.assertEqual(panorama.mode, 'RGBA')
            with self.assertRaisesRegex(StitchError, 'must not exist'):
                process(source, output)

    def test_canvas_bounds_and_failure_never_publish_complete_output(self):
        for width in (128, 513, 8192, True):
            with self.assertRaises(StitchError):
                compose_sphere([], [], width)
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder) / 'broken.zip'
            source.write_bytes(b'not a zip')
            output = Path(folder) / 'result'
            with self.assertRaises(zipfile.BadZipFile):
                process(source, output)
            self.assertFalse(output.exists())
            self.assertEqual(sorted(p.name for p in Path(folder).iterdir()), ['broken.zip'])


if __name__ == '__main__':
    unittest.main()
