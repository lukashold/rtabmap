"""Selection tests plus actual FFmpeg encode/decode tests when tools exist.

Synthetic video is generated here; no fixture binaries or camera poses are
shipped or treated as reconstruction-quality evidence.
"""
import json
import contextlib
import io
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from contract import ContractError, inspect_input, inspect_video_input
from media import probe_video, select_frames, prepare_video, export_selected_photos

VIDEO_HEADER = b'\x00\x00\x00\x18ftypisom\x00\x00\x02\x00isommp42'


class VideoContracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.folder = Path(self.temp.name)
        self.video = self.folder / 'input.video'
        self.video.write_bytes(VIDEO_HEADER)

    def tearDown(self):
        self.temp.cleanup()

    def probe(self, **changes):
        stream = {'codec_name': 'h264', 'width': 640, 'height': 360,
                  'duration': '12', 'avg_frame_rate': '30/1', **changes}
        result = SimpleNamespace(returncode=0, stdout=json.dumps({'streams': [stream]}).encode())
        with mock.patch('media.shutil.which', return_value='/test/ffprobe'), mock.patch('media.subprocess.run', return_value=result) as run:
            value = probe_video(self.video)
        arguments = run.call_args.args[0]
        self.assertEqual(arguments[arguments.index('-protocol_whitelist')+1], 'file')
        self.assertEqual(arguments[arguments.index('-enable_drefs')+1], '0')
        self.assertEqual(arguments[arguments.index('-use_absolute_path')+1], '0')
        self.assertEqual(arguments[arguments.index('-f')+1], 'mov')
        self.assertEqual(run.call_args.kwargs['timeout'], 20)
        return value

    def test_video_preflight_requires_bounded_local_isobmff_header(self):
        self.assertEqual(inspect_video_input(self.video)['source']['source'], 'video')
        for data in [b'https://example.com/private', b'#EXTM3U\n', b'\x7f\xff\xff\xffftyp' + b'x'*16]:
            self.video.write_bytes(data)
            with self.assertRaises(ContractError):
                inspect_video_input(self.video)

    def test_probe_rotation_and_limits(self):
        self.assertEqual(self.probe(side_data_list=[{'rotation': -90}])['rotationDegrees'], -90)
        for overrides, code in [({'duration': '181'}, 'video_duration'), ({'duration': '3'}, 'video_duration'),
                                ({'width': 5000}, 'video_dimensions'), ({'avg_frame_rate': '1000/1'}, 'unsupported_video'),
                                ({'avg_frame_rate': '0/0'}, 'unsupported_video'), ({'duration': 'nan'}, 'unsupported_video'),
                                ({'codec_name': 'gif'}, 'unsupported_video'),
                                ({'tags': {'rotate': '45'}}, 'unsupported_video')]:
            with self.subTest(overrides=overrides), self.assertRaises(ContractError) as error:
                self.probe(**overrides)
            self.assertEqual(error.exception.code, code)

    def test_ffmpeg44_section_name_is_supported_and_probe_errors_stay_private_bounded(self):
        def legacy_probe(command, **options):
            entries = command[command.index('-show_entries')+1]
            # The real 4.4 ffprobe section table has no stream_side_data alias.
            if 'stream_side_data=' in entries:
                return SimpleNamespace(returncode=1, stdout=b'', stderr=b'No match for section stream_side_data')
            return SimpleNamespace(returncode=0, stdout=json.dumps({'streams':[
                {'codec_name':'h264','width':640,'height':360,'duration':'12','avg_frame_rate':'30/1',
                 'side_data_list':[{'rotation':90}]}]}).encode(), stderr=b'')
        with mock.patch('media.shutil.which',return_value='/test/ffprobe'), mock.patch('media.subprocess.run',side_effect=legacy_probe):
            self.assertEqual(probe_video(self.video)['rotationDegrees'],90)
        diagnostic = io.StringIO()
        with mock.patch('media.shutil.which',return_value='/test/ffprobe'), mock.patch('media.subprocess.run',return_value=SimpleNamespace(returncode=1,stdout=b'x'*10000,stderr=b'bad\nprobe'*2000)),contextlib.redirect_stderr(diagnostic):
            with self.assertRaises(ContractError) as error:probe_video(self.video)
        self.assertEqual(error.exception.code,'unsupported_video')
        record=json.loads(diagnostic.getvalue())
        self.assertEqual(record['exitCode'],1)
        self.assertLessEqual(len(record['stderr']),2048)
        self.assertLessEqual(len(record['stdout']),2048)
        self.assertEqual(record['arguments'][-1],'<input.video>')

    def test_selection_uses_quality_timeline_bins_and_limits_not_camera_poses(self):
        candidates = []
        for index in range(360):
            candidates.append({'candidate': index+1, '_fingerprint': bytes([index % 250])*1024,
                               'quality': {'laplacianVariance128': 100+index%3,
                                           'darkFraction': 0, 'brightFraction': 0,
                                           'dHash64': f'{index*0x9e3779b97f4a7c15 % 2**64:016x}'}})
        candidates[1]['quality']['laplacianVariance128'] = 0
        candidates[2]['quality']['brightFraction'] = 1
        selected, rejected = select_frames(candidates, 20)
        self.assertLessEqual(len(selected), 20)
        self.assertGreater(selected[-1]['candidate'], 340)
        self.assertLess(selected[0]['candidate'], 20)
        self.assertEqual([x['candidate'] for x in selected], sorted(x['candidate'] for x in selected))
        self.assertTrue({'low-detail-or-blur', 'extreme-exposure', 'sharper-in-time-bin'} <= {x['reason'] for x in rejected})

    def test_duplicate_frames_cannot_pad_minimum_usable_photo_count(self):
        quality = {'laplacianVariance128': 100, 'darkFraction': 0, 'brightFraction': 0, 'dHash64': 'a'*16}
        candidates = [{'candidate': i+1, 'quality': dict(quality), '_fingerprint': b'x'*1024} for i in range(20)]
        selected, rejected = select_frames(candidates)
        self.assertEqual(len(selected), 1)
        self.assertEqual({x['reason'] for x in rejected}, {'near-duplicate'})


@unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'Actual FFmpeg/ffprobe unavailable; Docker/CI runs these tests')
class RealVideoDecoding(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.folder = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def run_ffmpeg(self, *args):
        subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', *map(str, args)], check=True,
                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, timeout=60)

    def test_real_rotated_video_frames_are_upright_bounded_and_exported_as_compatible_photos(self):
        original = self.folder / 'original.mp4'
        video = self.folder / 'rotated.mov'
        self.run_ffmpeg('-f', 'lavfi', '-i', 'testsrc2=size=320x192:rate=10:duration=8',
                        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', original)
        # FFmpeg 6 added an explicit input display-matrix option and deprecated
        # translating output "rotate" tags. Test an actual matrix on new builds;
        # retain the supported metadata interface on the pinned FFmpeg 4.4.
        help_text = subprocess.run(['ffmpeg', '-hide_banner', '-h', 'full'],
                                   capture_output=True, text=True, check=True, timeout=10).stdout
        if '-display_rotation' in help_text:
            self.run_ffmpeg('-display_rotation:v:0', '90', '-i', original, '-c', 'copy', video)
        else:
            self.run_ffmpeg('-i', original, '-c', 'copy', '-metadata:s:v:0', 'rotate=90', video)
        before = video.read_bytes()
        info, records = prepare_video(video, self.folder / 'images', max_size=256)
        self.assertEqual(abs(info['video']['rotationDegrees']), 90, info['video'])
        self.assertGreaterEqual(len(records), 8)
        self.assertLessEqual(len(records), 16)
        for record in records:
            self.assertEqual(record['height'], 256)
            self.assertLess(record['width'], record['height'])
            self.assertEqual(record['timestampKind'], 'fps-filter-timeline-estimate')
            self.assertNotIn('pose', record)
            with Image.open(self.folder / record['file']) as image:
                self.assertEqual(image.size, (record['width'], record['height']))
        output = self.folder / 'photos.zip'
        export_selected_photos(output, self.folder / 'images', records)
        self.assertEqual(inspect_input(output)['imageCount'], len(records))
        self.assertEqual(video.read_bytes(), before)
        with zipfile.ZipFile(output) as archive:
            manifest = json.loads(archive.read('manifest.json'))
            self.assertEqual(manifest['captureMode'], 'video')
            self.assertEqual(manifest['scaleStatus'], 'unverified')

    def test_static_video_fails_instead_of_claiming_enough_distinct_views(self):
        video = self.folder / 'static.mp4'
        self.run_ffmpeg('-f', 'lavfi', '-i', 'color=c=gray:size=128x96:rate=2:duration=8',
                        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', video)
        with self.assertRaises(ContractError) as error:
            prepare_video(video, self.folder / 'images', max_size=256)
        self.assertEqual(error.exception.code, 'too_few_usable_frames')


if __name__ == '__main__':
    unittest.main()
