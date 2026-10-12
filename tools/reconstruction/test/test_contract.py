"""Archive/output contract tests. These do not run COLMAP, OpenMVS or OpenSplat."""
import io
import json
import stat
import struct
import sys
import tempfile
import unittest
import zipfile
from dataclasses import replace
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from contract import LIMITS, ContractError, inspect_input, inspect_ply, safe_path, sha256, validate_artifacts
from fake_worker import artifacts


def photo_zip(manifest=False, extra=None, count=8):
    stream = io.BytesIO()
    images = [{'file': f'Images/{i}.jpg', 'bytes': 11} for i in range(count)]
    with zipfile.ZipFile(stream, 'w') as archive:
        for item in images:
            archive.writestr(item['file'], b'not decoded')
        if manifest:
            value = {'format': 'kantura-photo-dataset', 'version': 1, 'source': 'apple-object-capture', 'captureMode': 'object', 'scaleStatus': 'unverified', 'images': images}
            if isinstance(manifest, dict):
                value.update(manifest)
            archive.writestr('manifest.json', json.dumps(value))
        if extra:
            archive.writestr(extra[0], extra[1])
    return stream.getvalue()


class Contracts(unittest.TestCase):
    def test_optional_mesh_camera_and_video_photo_artifacts_require_valid_content_and_hashes(self):
        artifacts(self.root, 'mesh')
        camera = {'id': 0, 'img_name': 'frame_00001.jpg', 'width': 128, 'height': 128, 'fx': 100, 'fy': 100,
                  'position': [0, 0, 0], 'rotation': [[1, 0, 0], [0, 1, 0], [0, 0, 1]]}
        (self.root / 'cameras.json').write_text(json.dumps([camera]), 'utf-8')
        (self.root / 'photos.zip').write_bytes(photo_zip(manifest=True))
        manifest_path = self.root / 'reconstruction.json'
        manifest = json.loads(manifest_path.read_text('utf-8'))
        for name in ['cameras.json', 'photos.zip']:
            manifest['files'][name] = sha256(self.root / name)
        manifest_path.write_text(json.dumps(manifest), 'utf-8')
        self.assertEqual(len(validate_artifacts(self.root, 'mesh')), 5)
        (self.root / 'cameras.json').write_text('[]', 'utf-8')
        manifest['files']['cameras.json'] = sha256(self.root / 'cameras.json')
        manifest_path.write_text(json.dumps(manifest), 'utf-8')
        self.error('invalid_artifacts', validate_artifacts, self.root, 'mesh')

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def inspect(self, data, limits=LIMITS):
        path = self.root / 'input.zip'
        path.write_bytes(data)
        return inspect_input(path, limits)

    def error(self, code, function, *args):
        with self.assertRaises(ContractError) as context:
            function(*args)
        self.assertEqual(code, context.exception.code)

    def test_plain_photo_archive(self):
        self.assertEqual(self.inspect(photo_zip())['imageCount'], 8)

    def test_native_manifest_retained(self):
        value = self.inspect(photo_zip(manifest=True))
        self.assertEqual(value['source']['source'], 'apple-object-capture')
        self.assertEqual(value['source']['scaleStatus'], 'unverified')

    def test_manifest_cannot_claim_different_files(self):
        self.error('invalid_manifest', self.inspect, photo_zip(manifest={'images': []}))

    def test_manifest_not_object(self):
        self.error('invalid_manifest', self.inspect, photo_zip(extra=('manifest.json', '[]')))

    def test_safe_paths(self):
        for name in ['../a.jpg', '/a.jpg', 'C:/a.jpg', 'a\\b.jpg', 'a/./b.jpg', 'a//b.jpg', 'a\x00.jpg', './a.jpg']:
            with self.subTest(name=name):
                self.error('invalid_archive', safe_path, name)

    def test_archive_traversal(self):
        self.error('invalid_archive', self.inspect, photo_zip(extra=('../evil.jpg', 'x')))

    def test_case_collision(self):
        self.error('invalid_archive', self.inspect, photo_zip(extra=('images/0.JPG', 'x')))

    def test_symlink_rejected(self):
        link = zipfile.ZipInfo('link.jpg')
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        self.error('invalid_archive', self.inspect, photo_zip(extra=(link, '../private')))

    def test_non_image_sidecar_rejected(self):
        self.error('unsupported_image', self.inspect, photo_zip(extra=('SYNTHETIC.txt', 'fixture')))

    def test_image_count_minimum_and_maximum(self):
        self.error('too_few_images', self.inspect, photo_zip(count=7))
        self.error('too_large', self.inspect, photo_zip(count=9), replace(LIMITS, max_images=8))

    def test_limits(self):
        data = photo_zip()
        for limits in [replace(LIMITS, upload=100), replace(LIMITS, expanded=10), replace(LIMITS, image=5)]:
            self.error('too_large', self.inspect, data, limits)

    def test_compression_bomb_ratio(self):
        stream = io.BytesIO(photo_zip())
        with zipfile.ZipFile(stream, 'a', compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('huge.jpg', b'0' * 100000)
        self.error('too_large', self.inspect, stream.getvalue())

    def test_crc_damage(self):
        data = photo_zip().replace(b'not decoded', b'not decodex', 1)
        self.error('invalid_archive', self.inspect, data)

    def test_valid_mesh_and_splat_contract_test_doubles(self):
        for mode in ['mesh', 'splat']:
            directory = self.root / mode
            artifacts(directory, mode)
            self.assertEqual(len(validate_artifacts(directory, mode)), 3)

    def test_mesh_archive_retains_photogrammetry_provenance_and_exact_warnings(self):
        warnings = ['camera_pose_ambiguity', 'insufficient_parallax']
        artifacts(self.root, 'mesh', warnings)
        validate_artifacts(self.root, 'mesh')
        with zipfile.ZipFile(self.root / 'mesh.zip') as archive:
            project = json.loads(archive.read('rtab-measure.json'))
        self.assertEqual(project['source'], 'photogrammetry')
        self.assertEqual(project['scale'], 1)
        self.assertIs(project['calibrated'], False)
        self.assertEqual(project['captureWarnings'], warnings)
        self.assertEqual(project['measurements'], [])

    def test_mesh_archive_rejects_missing_unsafe_or_misleading_project_metadata(self):
        artifacts(self.root, 'mesh', ['camera_pose_ambiguity'])
        with zipfile.ZipFile(self.root / 'mesh.zip') as archive:
            original = {name: archive.read(name) for name in archive.namelist()}
        project = json.loads(original['rtab-measure.json'])
        cases = [None, 'not json', [], {**project, 'version': True},
                 {**project, 'source': 'lidar'}, {**project, 'calibrated': True},
                 {**project, 'scale': 2}, {**project, 'scale': True},
                 {**project, 'measurements': [{'id': 'fabricated'}]},
                 {**project, 'captureWarnings': []},
                 {**project, 'captureWarnings': ['invented_accuracy_pass']},
                 {**project, 'captureWarnings': ['camera_pose_ambiguity']*2},
                 {**project, 'unexpected': '<svg/onload=alert(1)>'}]
        for value in cases:
            with self.subTest(value=value):
                with zipfile.ZipFile(self.root / 'mesh.zip', 'w') as archive:
                    archive.writestr('model.obj', original['model.obj'])
                    if value is not None:
                        archive.writestr('rtab-measure.json', json.dumps(value))
                manifest_path = self.root / 'reconstruction.json'
                manifest = json.loads(manifest_path.read_text('utf-8'))
                manifest['files']['mesh.zip'] = sha256(self.root / 'mesh.zip')
                manifest_path.write_text(json.dumps(manifest), 'utf-8')
                self.error('invalid_artifacts', validate_artifacts, self.root, 'mesh')
        for name, data in [('nested/rtab-measure.json', json.dumps(project)),
                           ('rtab-measure.json', ' '*8193), ('anything.svg', '<svg/>')]:
            with self.subTest(name=name), zipfile.ZipFile(self.root / 'mesh.zip', 'w') as archive:
                archive.writestr('model.obj', original['model.obj'])
                archive.writestr(name, data)
            manifest['files']['mesh.zip'] = sha256(self.root / 'mesh.zip')
            manifest_path.write_text(json.dumps(manifest), 'utf-8')
            self.error('invalid_artifacts', validate_artifacts, self.root, 'mesh')

    def test_absent_artifacts_fail(self):
        self.error('missing_artifacts', validate_artifacts, self.root, 'mesh')

    def test_changed_artifact_hash(self):
        artifacts(self.root)
        with (self.root / 'model.ply').open('ab') as stream:
            stream.write(b'changed')
        self.error('invalid_artifacts', validate_artifacts, self.root, 'mesh')

    def test_truncated_mesh_cannot_complete(self):
        artifacts(self.root)
        path = self.root / 'model.ply'
        path.write_bytes(path.read_bytes().split(b'end_header\n')[0] + b'end_header\n')
        self.error('invalid_artifacts', inspect_ply, path)

    def test_mesh_face_indices_checked(self):
        artifacts(self.root)
        path = self.root / 'model.ply'
        path.write_bytes(path.read_bytes().replace(b'3 0 1 2', b'3 0 1 9'))
        self.error('invalid_artifacts', inspect_ply, path)

    def test_nonfinite_coordinates_rejected(self):
        artifacts(self.root)
        path = self.root / 'model.ply'
        path.write_bytes(path.read_bytes().replace(b'0 0 0', b'nan 0 0'))
        self.error('invalid_artifacts', inspect_ply, path)

    def test_binary_ply_payload_and_crlf(self):
        path = self.root / 'binary.ply'
        header = b'ply\r\nformat binary_little_endian 1.0\r\nelement vertex 3\r\nproperty float x\r\nproperty float y\r\nproperty float z\r\nelement face 1\r\nproperty list uchar int vertex_indices\r\nend_header\r\n'
        payload = struct.pack('<9fB3i', 0, 0, 0, 1, 0, 0, 0, 1, 0, 3, 0, 1, 2)
        path.write_bytes(header + payload)
        self.assertEqual(inspect_ply(path)['vertices'], 3)
        path.write_bytes(header + payload[:-1])
        self.error('invalid_artifacts', inspect_ply, path)

    def test_cameras_must_be_finite_valid_matrices(self):
        artifacts(self.root, 'splat')
        camera = self.root / 'cameras.json'
        camera.write_text('[{"width":1,"height":1,"fx":1,"fy":1,"position":[0,0,0],"rotation":[]}]', 'utf-8')
        manifest = self.root / 'reconstruction.json'
        value = json.loads(manifest.read_text('utf-8'))
        value['files']['cameras.json'] = sha256(camera)
        manifest.write_text(json.dumps(value), 'utf-8')
        self.error('invalid_artifacts', validate_artifacts, self.root, 'splat')


if __name__ == '__main__':
    unittest.main()
