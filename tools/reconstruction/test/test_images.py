"""Real image-codec checks; still not a reconstruction/real-iPhone test."""
import importlib.util
import io
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from contract import ContractError, sha256
from worker import prepare_images

CODECS = importlib.util.find_spec('PIL') is not None and importlib.util.find_spec('pillow_heif') is not None


@unittest.skipUnless(CODECS, 'Install requirements.txt for actual JPEG/PNG/HEIC decoder tests')
class ImageDecoding(unittest.TestCase):
    def setUp(self):
        from PIL import Image
        from pillow_heif import register_heif_opener
        register_heif_opener()
        self.Image = Image
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def archive(self, entries):
        path = self.root / 'input.zip'
        with zipfile.ZipFile(path, 'w') as archive:
            for i in range(8):
                suffix, data = entries[i % len(entries)]
                archive.writestr(f'Images/{i}.{suffix}', data)
        return path

    def encoded(self, format, size=(80, 40), orientation=None):
        image = self.Image.new('RGB', size, (54, 123, 191))
        stream = io.BytesIO()
        options = {}
        if orientation:
            exif = self.Image.Exif()
            exif[274] = orientation
            options['exif'] = exif
        image.save(stream, format, **options)
        return stream.getvalue()

    def test_real_jpeg_png_heic_decoding_keeps_original_archive(self):
        path = self.archive([('jpg', self.encoded('JPEG')), ('png', self.encoded('PNG')), ('heic', self.encoded('HEIF'))])
        original = sha256(path)
        info, images = prepare_images(path, self.root / 'images')
        self.assertEqual(info['imageCount'], 8)
        self.assertEqual({i['sourceFormat'] for i in images}, {'JPEG', 'PNG', 'HEIF'})
        self.assertEqual(sha256(path), original)
        self.assertTrue(all(i['metadataPreserved'] == 'original-archive-only' for i in images))
        self.assertTrue(all(i['file'].startswith('images/frame_') for i in images))
        self.assertTrue(all('pose' not in i for i in images))

    def test_exif_orientation_before_resize(self):
        path = self.archive([('jpg', self.encoded('JPEG', orientation=6))])
        _, images = prepare_images(path, self.root / 'images')
        self.assertEqual((images[0]['width'], images[0]['height']), (40, 80))

    def test_maximum_image_side(self):
        path = self.archive([('png', self.encoded('PNG', size=(400, 200)))])
        _, images = prepare_images(path, self.root / 'images', max_size=256)
        self.assertEqual((images[0]['width'], images[0]['height']), (256, 128))

    def test_mislabelled_files_fail_decoding(self):
        path = self.archive([('jpg', b'this is not a photograph')])
        with self.assertRaises(ContractError) as error:
            prepare_images(path, self.root / 'images')
        self.assertEqual(error.exception.code, 'unsupported_image')


if __name__ == '__main__':
    unittest.main()
