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
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from contract import LIMITS, ContractError
from service import PREFIX, Service, atomic_json, make_server
from test_contract import photo_zip

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
        self.service = Service(self.root, TOKEN, worker_command=[sys.executable, str(Path(__file__).with_name('fake_worker.py')), '--behavior', behavior], minimum_free_bytes=0, verify_programs=False, **options)
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


if __name__ == '__main__':
    unittest.main()
