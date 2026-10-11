"""Single-worker private reconstruction API. Run behind an HTTPS reverse proxy."""
import argparse
import hmac
import importlib.util
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, unquote, urlsplit

from contract import ARTIFACTS, EXTENSIONS, LIMITS, ContractError, inspect_input, sha256, validate_artifacts

PREFIX = '/api/reconstruction'
UUID = r'[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'
STAGES = {'preparing', 'features', 'matching', 'mapping', 'undistorting', 'dense', 'meshing', 'texturing', 'training', 'validating'}
FINAL = {'complete', 'failed', 'cancelled'}


def now():
    return datetime.now(timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')


def atomic_json(path, value):
    path = Path(path)
    temporary = path.with_suffix('.tmp')
    with temporary.open('w', encoding='utf-8') as stream:
        json.dump(value, stream, ensure_ascii=False, allow_nan=False)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def terminate_tree(process):
    if process.poll() is not None:
        return
    if os.name == 'nt':
        subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
    else:
        try:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=10)


class Service:
    def __init__(self, directory, token, limits=LIMITS, worker_command=None, device='cpu', timeout=7200, max_work_bytes=8 * 1024**3, minimum_free_bytes=2 * 1024**3, verify_programs=True, autostart=True):
        if not token or len(token) < 32 or len(token) > 1024:
            raise ValueError('RECONSTRUCTION_TOKEN must contain 32–1024 characters')
        if device not in {'cpu', 'cuda', 'mps'}:
            raise ValueError('Invalid worker device')
        self.root = Path(directory).resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        self.token, self.limits, self.device = token, limits, device
        self.timeout, self.max_work_bytes, self.minimum_free_bytes = timeout, max_work_bytes, minimum_free_bytes
        self.worker_command = worker_command or [sys.executable, str(Path(__file__).with_name('worker.py'))]
        self.verify_programs = verify_programs
        self.lock = threading.RLock()
        self.upload_lock = threading.Lock()
        self.wake, self.stopping = threading.Event(), threading.Event()
        self.jobs, self.process, self.current = {}, None, None
        self.lockfile = (self.root / '.service.lock').open('a+b')
        if os.name == 'nt':
            import msvcrt
            self.lockfile.seek(0)
            if self.lockfile.read(1) == b'':
                self.lockfile.write(b'0')
                self.lockfile.flush()
            self.lockfile.seek(0)
            msvcrt.locking(self.lockfile.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(self.lockfile, fcntl.LOCK_EX | fcntl.LOCK_NB)
        for folder in sorted(self.root.iterdir()):
            if not re.fullmatch(UUID, folder.name) or folder.is_symlink() or not folder.is_dir():
                continue
            state = folder / 'state.json'
            if not state.exists():
                continue  # unfinished upload; never publish it
            try:
                job = json.loads(state.read_text('utf-8'))
                if job.get('id') != folder.name or job.get('mode') not in ARTIFACTS:
                    continue
                if job.get('status') not in FINAL | {'queued', 'running'}:
                    continue
                self.jobs[job['id']] = job
                if job['status'] == 'running':
                    self.change(job, status='failed', stage='failed', error={'code': 'interrupted', 'message': 'Worker interrupted by service restart.'}, artifacts=[])
                elif job['status'] in FINAL and isinstance(job.get('error'), dict) and job['error'].get('code') == 'interrupted':
                    # A worker orphaned by a crash may still own these files.
                    # Only a process whose exit we observed is safe to clean.
                    pass
                elif job['status'] in FINAL:
                    self.cleanup_work(job)
            except (ValueError, OSError):
                continue
        self.thread = threading.Thread(target=self.loop, name='reconstruction-worker', daemon=True)
        if autostart:
            self.thread.start()
            self.wake.set()

    def cleanup_work(self, job):
        """Remove only generated scratch after a terminal job's worker has exited."""
        identifier = job.get('id')
        if job.get('status') not in FINAL or not isinstance(identifier, str) or not re.fullmatch(UUID, identifier):
            return False
        with self.lock:
            if self.current == identifier and self.process is not None and self.process.poll() is None:
                return False
            folder = self.root / identifier
            work = folder / 'work'
            try:
                # Reparse points, symlinked job folders and redirected work roots
                # must never turn a scratch cleanup into deletion elsewhere.
                if folder.is_symlink() or folder.resolve(strict=True) != folder or folder.parent != self.root:
                    return False
                if not work.exists():
                    return not work.is_symlink()
                if work.is_symlink() or work.resolve(strict=True) != work or work.parent != folder or not work.is_dir():
                    return False
                # shutil.rmtree removes nested links without traversing them;
                # on Linux its fd-based implementation also resists link swaps.
                shutil.rmtree(work)
                return True
            except FileNotFoundError:
                return not work.exists()  # Concurrent terminal cleanup is safe.
            except OSError:
                # Retain files and retry on restart; never invalidate outputs.
                print('Scratch cleanup deferred for job ' + identifier, file=sys.stderr, flush=True)
                return False

    def capabilities(self):
        decoder = importlib.util.find_spec('PIL') is not None and importlib.util.find_spec('pillow_heif') is not None
        common = decoder and shutil.which('colmap') is not None
        mesh = common and all(shutil.which(name) for name in ['InterfaceCOLMAP', 'DensifyPointCloud', 'ReconstructMesh', 'TextureMesh'])
        splat = common and shutil.which('opensplat') is not None
        return {'version': 1, 'modes': [
            {'id': 'mesh', 'available': bool(mesh or not self.verify_programs), 'engine': 'COLMAP + OpenMVS', 'accelerator': 'cpu'},
            {'id': 'splat', 'available': bool(splat or not self.verify_programs), 'engine': 'COLMAP + OpenSplat', 'accelerator': self.device}],
            'input': {'contentType': 'application/zip', 'extensions': sorted(EXTENSIONS), 'minImages': self.limits.min_images, 'maxImages': self.limits.max_images},
            'limits': {'uploadBytes': self.limits.upload, 'artifactBytes': self.limits.artifact, 'expandedBytes': self.limits.expanded, 'maxQueuedJobs': self.limits.queue},
            'scaleStatus': 'unverified', 'hardwareValidated': False}

    def change(self, job, **changes):
        job.update(changes)
        job['updatedAt'] = now()
        atomic_json(self.root / job['id'] / 'state.json', job)

    def public(self, job):
        return json.loads(json.dumps(job))

    def list(self):
        with self.lock:
            return [self.public(job) for job in sorted(self.jobs.values(), key=lambda j: j['createdAt'], reverse=True)]

    def get(self, identifier):
        with self.lock:
            if identifier not in self.jobs:
                raise ContractError('not_found')
            return self.public(self.jobs[identifier])

    def admission(self, mode, name):
        if mode not in ARTIFACTS:
            raise ContractError('invalid_mode')
        if not name or len(name) > 120 or any(ord(c) < 32 or c in '/\\' for c in name):
            raise ContractError('invalid_name')
        if not next(m for m in self.capabilities()['modes'] if m['id'] == mode)['available']:
            raise ContractError('worker_unavailable')
        with self.lock:
            if sum(j['status'] not in FINAL for j in self.jobs.values()) >= self.limits.queue or len(self.jobs) >= 200:
                raise ContractError('busy')
        if shutil.disk_usage(self.root).free < self.minimum_free_bytes + self.limits.upload:
            raise ContractError('storage_full')

    def create(self, mode, name, body, length):
        if length <= 0 or length > self.limits.upload:
            raise ContractError('too_large')
        if not self.upload_lock.acquire(blocking=False):
            raise ContractError('busy')
        folder = None
        try:
            self.admission(mode, name)
            identifier = str(uuid.uuid4())
            folder = self.root / identifier
            folder.mkdir(mode=0o700)
            remaining, started = length, time.monotonic()
            with (folder / 'input.zip').open('wb') as stream:
                while remaining:
                    if time.monotonic() - started > 120:
                        raise ContractError('upload_timeout')
                    block = body.read(min(remaining, 1024 * 1024))
                    if not block:
                        raise ContractError('invalid_archive')
                    stream.write(block)
                    remaining -= len(block)
            info = inspect_input(folder / 'input.zip', self.limits)
            stamp = now()
            job = {'id': identifier, 'name': name, 'mode': mode, 'status': 'queued', 'stage': 'queued', 'createdAt': stamp, 'updatedAt': stamp, 'scaleStatus': 'unverified', 'imageCount': info['imageCount'], 'source': info['source'], 'artifacts': [], 'error': None}
            with self.lock:
                atomic_json(folder / 'state.json', job)
                self.jobs[identifier] = job
                answer = self.public(job)
            self.wake.set()
            return answer
        except Exception:
            if folder and folder.resolve().parent == self.root and re.fullmatch(UUID, folder.name) and not (folder / 'state.json').exists():
                shutil.rmtree(folder)
            raise
        finally:
            self.upload_lock.release()

    def cancel(self, identifier):
        with self.lock:
            job = self.jobs.get(identifier)
            if not job:
                raise ContractError('not_found')
            if job['status'] not in FINAL:
                self.change(job, status='cancelled', stage='cancelled', artifacts=[], error=None)
                process = self.process if self.current == identifier else None
            else:
                process = None
        if process:
            terminate_tree(process)
        else:
            self.cleanup_work(job)  # Queued cancellation has no running worker.
        return self.get(identifier)

    def loop(self):
        while not self.stopping.is_set():
            with self.lock:
                job = next((j for j in sorted(self.jobs.values(), key=lambda j: j['createdAt']) if j['status'] == 'queued'), None)
                if job:
                    self.change(job, status='running', stage='preparing')
                    self.current = job['id']
            if not job:
                self.wake.wait(1)
                self.wake.clear()
                continue
            self.execute(job)

    def execute(self, job):
        folder = self.root / job['id']
        started = time.monotonic()
        try:
            with (folder / 'worker.log').open('wb') as log:
                command = self.worker_command + ['--job-dir', str(folder), '--mode', job['mode'], '--device', self.device]
                options = {'start_new_session': True} if os.name != 'nt' else {'creationflags': subprocess.CREATE_NEW_PROCESS_GROUP}
                with self.lock:
                    if job['status'] == 'cancelled':
                        return
                    self.process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT, **options)
                    process = self.process
                while process.poll() is None:
                    if self.stopping.is_set():
                        terminate_tree(process)
                        raise ContractError('interrupted')
                    if time.monotonic() - started > self.timeout:
                        terminate_tree(process)
                        raise ContractError('worker_timeout')
                    total = sum(p.stat().st_size for p in folder.rglob('*') if p.is_file() and not p.is_symlink())
                    if total > self.max_work_bytes or (folder / 'worker.log').stat().st_size > 8 * 1024**2:
                        terminate_tree(process)
                        raise ContractError('worker_limit')
                    try:
                        progress = folder / 'progress.json'
                        if progress.stat().st_size > 8192:
                            raise ContractError('worker_limit')
                        stage = json.loads(progress.read_text('utf-8')).get('stage')
                        with self.lock:
                            if stage in STAGES and job['status'] == 'running' and stage != job['stage']:
                                self.change(job, stage=stage)
                    except (ValueError, OSError):
                        pass
                    time.sleep(0.25)
                with self.lock:
                    if job['status'] == 'cancelled':
                        return
                if process.returncode != 0:
                    code = 'reconstruction_failed'
                    try:
                        error_file = folder / 'error.json'
                        if error_file.stat().st_size > 8192:
                            raise ContractError('worker_limit')
                        error = json.loads(error_file.read_text('utf-8'))
                        if error.get('code') in {'unsupported_image', 'insufficient_registration', 'worker_unavailable', 'invalid_artifacts', 'too_large', 'reconstruction_failed'}:
                            code = error['code']
                    except (ValueError, OSError):
                        pass
                    raise ContractError(code)
                artifacts = validate_artifacts(folder / 'artifacts', job['mode'], self.limits)
                for item in artifacts:
                    item['url'] = f"{PREFIX}/jobs/{job['id']}/artifacts/{item['name']}"
                with self.lock:
                    if job['status'] == 'running':
                        self.change(job, status='complete', stage='complete', artifacts=artifacts, error=None)
        except Exception as error:
            code = error.code if isinstance(error, ContractError) else 'worker_failed'
            with self.lock:
                if job['status'] != 'cancelled':
                    self.change(job, status='failed', stage='failed', artifacts=[], error={'code': code, 'message': code.replace('_', ' ')})
        finally:
            if self.process:
                terminate_tree(self.process)
            # Preserve original uploads, status, logs and all artifact files.
            # Cleanup is after process termination, including cancel/close.
            self.cleanup_work(job)
            with self.lock:
                self.process, self.current = None, None

    def close(self):
        self.stopping.set()
        self.wake.set()
        if self.thread.is_alive():
            self.thread.join(timeout=20)
        self.lockfile.close()


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    server_version = 'KanturaReconstruction/1'

    def setup(self):
        super().setup()
        self.connection.settimeout(30)

    def log_message(self, *_):
        pass  # Do not put tokens, private project names or input paths in access logs.

    def json(self, status, body):
        data = json.dumps(body, ensure_ascii=False, allow_nan=False).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Connection', 'close')
        self.end_headers()
        self.response_started = True
        self.close_connection = True
        self.wfile.write(data)

    def auth(self):
        value = self.headers.get('Authorization', '')
        expected = 'Bearer ' + self.server.service.token
        return hmac.compare_digest(value.encode('utf-8'), expected.encode('utf-8'))

    def dispatch(self):
        service = self.server.service
        parsed = urlsplit(self.path)
        path = unquote(parsed.path)
        if self.command == 'GET' and path == '/health':
            return self.json(200, {'status': 'ok', 'version': 1})
        if not self.auth():
            return self.json(401, {'error': 'unauthorized'})
        if self.command == 'GET' and path == PREFIX + '/capabilities':
            return self.json(200, service.capabilities())
        if path == PREFIX + '/jobs':
            if self.command == 'GET':
                return self.json(200, {'jobs': service.list()})
            if self.command == 'POST':
                if self.headers.get('Transfer-Encoding'):
                    return self.json(411, {'error': 'length_required'})
                length = self.headers.get('Content-Length')
                if not length or not length.isdigit() or len(self.headers.get_all('Content-Length', [])) != 1:
                    return self.json(411, {'error': 'length_required'})
                if self.headers.get('Content-Type', '').split(';')[0].strip().lower() != 'application/zip':
                    return self.json(415, {'error': 'unsupported_media_type'})
                query = parse_qs(parsed.query)
                job = service.create(query.get('mode', [''])[0], query.get('name', ['Photo capture'])[0], self.rfile, int(length))
                return self.json(202, {'job': job})
        match = re.fullmatch(PREFIX + '/jobs/(' + UUID + ')(?:/(cancel|artifacts/([^/]+)))?', path)
        if match:
            identifier, action, filename = match.groups()
            if self.command == 'POST' and action == 'cancel':
                return self.json(200, {'job': service.cancel(identifier)})
            job = service.get(identifier)
            if self.command == 'GET' and not action:
                return self.json(200, {'job': job})
            if self.command == 'GET' and filename:
                if filename not in ARTIFACTS[job['mode']]:
                    raise ContractError('not_found')
                if job['status'] != 'complete':
                    raise ContractError('not_complete')
                item = next((a for a in job['artifacts'] if a['name'] == filename), None)
                file = service.root / identifier / 'artifacts' / filename
                if not item or file.parent.is_symlink() or file.is_symlink() or not file.is_file() or file.stat().st_size != item['bytes'] or sha256(file) != item['sha256']:
                    raise ContractError('not_found')
                self.send_response(200)
                self.send_header('Content-Type', item['mediaType'])
                self.send_header('Content-Length', str(item['bytes']))
                self.send_header('Content-Disposition', 'attachment; filename="' + filename + '"')
                self.send_header('Cache-Control', 'no-store')
                self.send_header('X-Content-Type-Options', 'nosniff')
                self.send_header('Connection', 'close')
                self.end_headers()
                self.response_started = True
                self.close_connection = True
                with file.open('rb') as stream:
                    shutil.copyfileobj(stream, self.wfile, 1024 * 1024)
                return
        raise ContractError('not_found')

    def handle_api(self):
        self.response_started = False
        try:
            self.dispatch()
        except ContractError as error:
            if self.response_started:
                self.close_connection = True
                return
            code = {'not_found': 404, 'not_complete': 409, 'busy': 409, 'too_large': 413, 'worker_unavailable': 503, 'storage_full': 503, 'upload_timeout': 408}.get(error.code, 400)
            self.json(code, {'error': error.code})
        except (BrokenPipeError, ConnectionResetError, TimeoutError):
            self.close_connection = True
        except Exception:
            if self.response_started:
                self.close_connection = True
            else:
                self.json(500, {'error': 'internal_error'})

    do_GET = handle_api
    do_POST = handle_api


class BoundedHTTPServer(ThreadingHTTPServer):
    """A private proxy-facing API still needs a finite connection budget."""
    def __init__(self, *args, **kwargs):
        self.connections = threading.BoundedSemaphore(16)
        super().__init__(*args, **kwargs)

    def process_request(self, request, client_address):
        if not self.connections.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self.connections.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.connections.release()


def make_server(service, host='127.0.0.1', port=4180):
    server = BoundedHTTPServer((host, port), Handler)
    server.daemon_threads = True
    server.service = service
    return server


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', default=os.environ.get('HOST', '127.0.0.1'))
    parser.add_argument('--port', type=int, default=int(os.environ.get('PORT', '4180')))
    args = parser.parse_args()
    service = Service(os.environ.get('DATA_DIR', './reconstruction-data'), os.environ.get('RECONSTRUCTION_TOKEN', ''), device=os.environ.get('WORKER_DEVICE', 'cpu'), timeout=int(os.environ.get('JOB_TIMEOUT_SECONDS', '7200')))
    server = make_server(service, args.host, args.port)
    def stop(_signal, _frame):
        threading.Thread(target=server.shutdown, daemon=True).start()
    signal.signal(signal.SIGTERM, stop)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        service.close()


if __name__ == '__main__':
    main()
