"""HTTP/persistence/process tests use the explicitly labelled FakeWorker."""
import http.client
import io
import json
import sys
import tempfile
import threading
import time
import unittest
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from contract import LIMITS, ContractError
from service import PREFIX, Service, atomic_json, make_server
from test_contract import photo_zip
from test_media import VIDEO_HEADER

TOKEN = 'private-test-token-' + 'x' * 32


class ServiceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.service = None
        self.server = None

    def tearDown(self):
        if self.server:
            self.server.shutdown()
            self.server.server_close()
        if self.service:
            self.service.close()
        self.temp.cleanup()

    def start(self, behavior='valid', **options):
        self.service = Service(self.root, TOKEN, worker_command=[sys.executable, str(Path(__file__).with_name('fake_worker.py')), '--behavior', behavior], minimum_free_bytes=options.pop('minimum_free_bytes', 0), verify_programs=False, **options)
        return self.service

    def upload(self, mode='mesh', data=None):
        data = data or photo_zip(manifest=True)
        return self.service.create(mode, 'Private project', io.BytesIO(data), len(data))

    def final(self, identifier, timeout=8):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            job = self.service.get(identifier)
            if job['status'] in {'complete', 'failed', 'cancelled'}:
                return job
            time.sleep(.03)
        self.fail('Worker did not finish in time')

    def http(self):
        self.server = make_server(self.service, port=0)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def request(self, method, path, body=None, token=TOKEN, headers=None):
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=5)
        fields = {} if token is None else {'Authorization': 'Bearer ' + token}
        fields.update(headers or {})
        connection.request(method, path, body, fields)
        response = connection.getresponse()
        data = response.read()
        result = (response.status, data, dict(response.getheaders()))
        connection.close()
        return result

    def test_token_minimum(self):
        with self.assertRaises(ValueError):
            Service(self.root, 'weak')

    def test_health_public_api_private(self):
        self.start(autostart=False)
        self.http()
        self.assertEqual(self.request('GET', '/health', token=None)[0], 200)
        for endpoint in ['/capabilities', '/jobs']:
            self.assertEqual(self.request('GET', PREFIX + endpoint, token=None)[0], 401)
            self.assertEqual(self.request('GET', PREFIX + endpoint, token='wrong')[0], 401)

    def test_capabilities_honest_about_program_presence(self):
        self.start(autostart=False)
        self.service.verify_programs = True
        with mock.patch('service.shutil.which', return_value=None):
            caps = self.service.capabilities()
            self.assertFalse(any(m['available'] for m in caps['modes']))
            with self.assertRaises(ContractError) as error:
                self.upload()
            self.assertEqual(error.exception.code, 'worker_unavailable')
        self.assertFalse(caps['hardwareValidated'])

    def test_http_create_list_status(self):
        self.start(autostart=False)
        self.http()
        status, body, _ = self.request('POST', PREFIX + '/jobs?mode=mesh&name=Room', photo_zip(), headers={'Content-Type': 'application/zip'})
        self.assertEqual(status, 202)
        job = json.loads(body)['job']
        self.assertEqual(job['status'], 'queued')
        self.assertEqual(json.loads(self.request('GET', PREFIX + '/jobs')[1])['jobs'][0]['id'], job['id'])
        self.assertEqual(json.loads(self.request('GET', PREFIX + '/jobs/' + job['id'])[1])['job']['scaleStatus'], 'unverified')
        self.assertEqual(self.request('GET', PREFIX + '/jobs/' + job['id'] + '/artifacts/mesh.zip')[0], 409)

    def test_http_upload_type_mode_size(self):
        self.start(autostart=False, limits=replace(LIMITS, upload=2048))
        self.http()
        self.assertEqual(self.request('POST', PREFIX + '/jobs?mode=mesh', b'zip')[0], 415)
        self.assertEqual(self.request('POST', PREFIX + '/jobs?mode=shell', photo_zip(), headers={'Content-Type': 'application/zip'})[0], 400)
        self.assertEqual(self.request('POST', PREFIX + '/jobs?mode=mesh', b'x' * 2049, headers={'Content-Type': 'application/zip'})[0], 413)

    def test_video_and_uav_profile_admission_keep_original_and_report_deferred_image_count(self):
        self.start(autostart=False)
        self.http()
        caps = json.loads(self.request('GET', PREFIX + '/capabilities')[1])
        self.assertTrue(caps['video']['available'])
        self.assertEqual(caps['video']['durationSeconds'], 180)
        self.assertEqual(caps['profiles'], ['auto', 'uav'])
        for media_type in ['video/mp4', 'video/quicktime']:
            status, body, _ = self.request('POST', PREFIX + '/jobs?mode=mesh&profile=uav', VIDEO_HEADER,
                                           headers={'Content-Type': media_type})
            self.assertEqual(status, 202)
            job = json.loads(body)['job']
            self.assertEqual(job['inputType'], 'video')
            self.assertEqual(job['captureProfile'], 'uav')
            self.assertIsNone(job['imageCount'])
            self.assertEqual((self.root / job['id'] / 'input.video').read_bytes(), VIDEO_HEADER)
        self.assertEqual(self.request('POST', PREFIX + '/jobs?mode=mesh&profile=unknown', VIDEO_HEADER,
                                     headers={'Content-Type': 'video/mp4'})[0], 400)
        self.assertEqual(self.request('POST', PREFIX + '/jobs?mode=mesh', b'#EXTM3U\nhttps://private.example',
                                     headers={'Content-Type': 'video/mp4'})[0], 400)
        self.assertEqual(self.request('POST', PREFIX + '/jobs?mode=mesh', VIDEO_HEADER,
                                     headers={'Content-Type': 'video/webm'})[0], 415)

    def test_video_worker_arguments_are_explicit_and_original_is_preserved_after_cleanup(self):
        self.start()
        admitted = self.service.create('mesh', 'Video', io.BytesIO(VIDEO_HEADER), len(VIDEO_HEADER), 'video/mp4', 'uav')
        job = self.final(admitted['id'])
        self.assertEqual(job['status'], 'complete')  # Explicit FakeWorker, not reconstruction evidence.
        self.assertEqual((self.root / job['id'] / 'input.video').read_bytes(), VIDEO_HEADER)
        self.assertFalse((self.root / job['id'] / 'work').exists())
        diagnostic = (self.root / job['id'] / 'worker.log').read_text('utf-8')
        self.assertIn('input-type=video profile=uav', diagnostic)

    def test_video_capability_does_not_claim_missing_decoder(self):
        self.start(autostart=False)
        self.service.verify_programs = True
        with mock.patch('service.shutil.which', side_effect=lambda name: None if name == 'ffmpeg' else '/test/bin'):
            self.assertFalse(self.service.capabilities()['video']['available'])
            with self.assertRaises(ContractError) as error:
                self.service.create('mesh', 'Video', io.BytesIO(VIDEO_HEADER), len(VIDEO_HEADER), 'video/mp4')
            self.assertEqual(error.exception.code, 'worker_unavailable')

    def test_abort_upload_cleans_only_incomplete_private_folder(self):
        self.start(autostart=False)
        sentinel = self.root / 'keep.txt'
        sentinel.write_text('keep')
        with self.assertRaises(ContractError):
            self.service.create('mesh', 'Room', io.BytesIO(b'short'), 100)
        self.assertEqual(sentinel.read_text(), 'keep')
        self.assertEqual([p for p in self.root.iterdir() if p.is_dir()], [])

    def test_queue_limit_and_cancelled_slot(self):
        self.start(autostart=False, limits=replace(LIMITS, queue=1))
        first = self.upload()
        with self.assertRaises(ContractError) as error:
            self.upload()
        self.assertEqual(error.exception.code, 'busy')
        self.assertEqual(self.service.cancel(first['id'])['status'], 'cancelled')
        self.assertEqual(self.upload()['status'], 'queued')

    def test_zero_exit_without_artifacts_is_failed(self):
        self.start('missing')
        job = self.final(self.upload()['id'])
        self.assertEqual(job['status'], 'failed')
        self.assertEqual(job['error']['code'], 'missing_artifacts')
        self.assertEqual(job['artifacts'], [])

    def test_nonzero_worker_is_failed(self):
        self.start('failure')
        self.assertEqual(self.final(self.upload()['id'])['error']['code'], 'reconstruction_failed')

    def test_mesh_contract_complete_and_only_allowlisted_artifacts(self):
        self.start()
        job = self.final(self.upload()['id'])
        self.assertEqual(job['status'], 'complete')
        self.assertEqual(len(job['artifacts']), 3)
        self.http()
        for artifact in job['artifacts']:
            status, data, headers = self.request('GET', artifact['url'])
            self.assertEqual(status, 200)
            self.assertEqual(len(data), artifact['bytes'])
            self.assertEqual(headers['Cache-Control'], 'no-store')
        for filename in ['worker.log', 'input.zip', 'state.json', '..%2fstate.json']:
            self.assertEqual(self.request('GET', PREFIX + '/jobs/' + job['id'] + '/artifacts/' + filename)[0], 404)
        self.assertEqual(self.service.cancel(job['id'])['status'], 'complete')

    def test_same_size_artifact_corruption_is_not_served(self):
        self.start()
        job = self.final(self.upload()['id'])
        file = self.root / job['id'] / 'artifacts' / 'model.ply'
        data = file.read_bytes()
        file.write_bytes(b'X' + data[1:])
        self.http()
        self.assertEqual(self.request('GET', PREFIX + '/jobs/' + job['id'] + '/artifacts/model.ply')[0], 404)

    def test_splat_contract_complete_test_double_only(self):
        self.start()
        job = self.final(self.upload(mode='splat')['id'])
        self.assertEqual(job['status'], 'complete')
        self.assertEqual({a['name'] for a in job['artifacts']}, {'splat.ply', 'cameras.json', 'reconstruction.json'})

    def test_cancel_running_process(self):
        self.start('sleep')
        identifier = self.upload()['id']
        deadline = time.monotonic() + 5
        while not (self.root / identifier / 'progress.json').exists() and time.monotonic() < deadline:
            time.sleep(.03)
        self.http()
        status, body, _ = self.request('POST', PREFIX + '/jobs/' + identifier + '/cancel')
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)['job']['status'], 'cancelled')
        self.assertEqual(self.service.get(identifier)['artifacts'], [])

    def test_timeout_terminates_worker(self):
        self.start('sleep', timeout=.4)
        self.assertEqual(self.final(self.upload()['id'])['error']['code'], 'worker_timeout')

    def test_work_budget_terminates_worker(self):
        self.start('oversize', max_work_bytes=10000)
        self.assertEqual(self.final(self.upload()['id'])['error']['code'], 'worker_limit')

    def test_running_disk_reserve_terminates_worker_and_keeps_original_and_log(self):
        low_space = threading.Event()
        def telemetry(path):
            self.assertEqual(Path(path), self.root)
            return SimpleNamespace(free=512 if low_space.is_set() else 4 * 1024**3)
        with mock.patch('service.shutil.disk_usage', side_effect=telemetry):
            self.start('sleep', minimum_free_bytes=1024)
            original = photo_zip(manifest=True)
            identifier = self.upload(data=original)['id']
            self.scratch_ready(identifier)
            folder = self.root / identifier
            process = self.service.process
            self.assertIsNone(process.poll())
            self.assertTrue((folder / 'work' / 'generated' / 'intermediate.bin').is_file())
            low_space.set()
            job = self.final(identifier)
            self.settled(identifier)
            self.assertEqual(job['status'], 'failed')
            self.assertEqual(job['error']['code'], 'storage_full')
            self.assertEqual(job['artifacts'], [])
            self.assertIsNotNone(process.poll())
            self.assertFalse((folder / 'work').exists())
            self.assertEqual((folder / 'input.zip').read_bytes(), original)
            self.assertIn(b'TEST DOUBLE worker started', (folder / 'worker.log').read_bytes())
            self.assertTrue((folder / 'state.json').is_file())

    def test_queued_jobs_resume_and_running_jobs_fail_after_restart(self):
        self.start(autostart=False)
        queued = self.upload()
        running = self.upload()
        self.service.change(self.service.jobs[running['id']], status='running')
        self.service.close()
        self.service = None
        self.start()
        self.assertEqual(self.final(queued['id'])['status'], 'complete')
        self.assertEqual(self.service.get(running['id'])['error']['code'], 'interrupted')


    def settled(self, identifier, timeout=8):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.service.current != identifier:
                return
            time.sleep(.02)
        self.fail('Worker did not release its job')

    def scratch_ready(self, identifier):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if (self.root / identifier / 'progress.json').exists():
                return
            time.sleep(.02)
        self.fail('Sleeping worker did not start')

    def test_generated_scratch_removed_after_success_original_and_artifacts_preserved(self):
        self.start()
        original = photo_zip(manifest=True)
        job = self.final(self.upload(data=original)['id'])
        self.settled(job['id'])
        folder = self.root / job['id']
        self.assertEqual(job['status'], 'complete')
        self.assertFalse((folder / 'work').exists())
        self.assertEqual((folder / 'input.zip').read_bytes(), original)
        self.assertTrue((folder / 'worker.log').is_file())
        self.assertTrue((folder / 'state.json').is_file())
        for artifact in job['artifacts']:
            self.assertEqual((folder / 'artifacts' / artifact['name']).stat().st_size, artifact['bytes'])

    def test_generated_scratch_removed_after_worker_failure(self):
        self.start('failure')
        identifier = self.upload()['id']
        self.assertEqual(self.final(identifier)['status'], 'failed')
        self.settled(identifier)
        folder = self.root / identifier
        self.assertFalse((folder / 'work').exists())
        self.assertTrue((folder / 'input.zip').is_file())
        self.assertTrue((folder / 'worker.log').is_file())

    def test_cancel_waits_for_process_before_cleaning_only_generated_scratch(self):
        self.start('sleep')
        identifier = self.upload()['id']
        self.scratch_ready(identifier)
        folder = self.root / identifier
        self.assertTrue((folder / 'work' / 'generated' / 'intermediate.bin').exists())
        self.assertFalse(self.service.cleanup_work({**self.service.get(identifier), 'status':'failed'}))
        self.assertTrue((folder / 'work').exists())
        process = self.service.process
        self.service.cancel(identifier)
        self.settled(identifier)
        self.assertIsNotNone(process.poll())
        self.assertFalse((folder / 'work').exists())
        self.assertTrue((folder / 'input.zip').is_file())
        self.assertTrue((folder / 'worker.log').is_file())

    def test_service_close_terminates_worker_then_cleans_scratch(self):
        self.start('sleep')
        identifier = self.upload()['id']
        self.scratch_ready(identifier)
        process = self.service.process
        self.service.close()
        self.assertIsNotNone(process.poll())
        folder = self.root / identifier
        self.assertFalse((folder / 'work').exists())
        self.assertTrue((folder / 'input.zip').is_file())
        self.assertEqual(self.service.get(identifier)['status'], 'failed')

    def test_restart_cleans_old_final_scratch_but_preserves_queued_and_unknown_running_work(self):
        self.start(autostart=False)
        finished, queued, running = self.upload(), self.upload(), self.upload()
        self.service.change(self.service.jobs[finished['id']], status='complete')
        self.service.change(self.service.jobs[running['id']], status='running')
        for job in (finished, queued, running):
            folder = self.root / job['id']
            (folder / 'work').mkdir()
            (folder / 'work' / 'intermediate.bin').write_bytes(b'old-generated-data')
            (folder / 'artifacts').mkdir()
            (folder / 'artifacts' / 'keep.bin').write_bytes(b'keep artifact')
        self.service.close()
        self.start(autostart=False)
        self.assertFalse((self.root / finished['id'] / 'work').exists())
        self.assertTrue((self.root / queued['id'] / 'work').is_dir())
        self.assertTrue((self.root / running['id'] / 'work').is_dir())
        for job in (finished, queued, running):
            self.assertTrue((self.root / job['id'] / 'input.zip').is_file())
            self.assertEqual((self.root / job['id'] / 'artifacts' / 'keep.bin').read_bytes(), b'keep artifact')
        # A subsequent restart still cannot prove an orphaned worker has exited.
        self.service.close()
        self.start(autostart=False)
        self.assertTrue((self.root / running['id'] / 'work').is_dir())

    def test_cleanup_refuses_traversal_and_symlink_targets_outside_exact_job(self):
        self.start(autostart=False)
        job = self.upload()
        self.service.change(self.service.jobs[job['id']], status='cancelled')
        with tempfile.TemporaryDirectory() as outside:
            external = Path(outside)
            (external / 'keep.bin').write_bytes(b'outside')
            self.assertFalse(self.service.cleanup_work({'id':'../'+external.name, 'status':'failed'}))
            link = self.root / job['id'] / 'work'
            try:
                link.symlink_to(external, target_is_directory=True)
            except OSError:
                self.skipTest('Creating symlinks is unavailable on this host')
            try:
                self.assertFalse(self.service.cleanup_work(self.service.jobs[job['id']]))
                self.assertEqual((external / 'keep.bin').read_bytes(), b'outside')
                self.assertTrue(link.is_symlink())
            finally:
                link.unlink()
            link.mkdir()
            nested = link / 'nested'
            nested.symlink_to(external, target_is_directory=True)
            self.assertTrue(self.service.cleanup_work(self.service.jobs[job['id']]))
            self.assertEqual((external / 'keep.bin').read_bytes(), b'outside')
            self.assertFalse(link.exists())


if __name__ == '__main__':
    unittest.main()
