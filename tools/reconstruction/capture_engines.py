"""Adapters for existing local capture CLIs; one service/process supervisor."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

from contract import ARTIFACTS, ContractError, sha256, validate_artifacts


def engine_paths(mode):
    name = 'generation' if mode == 'generated' else 'panorama'
    bundled = Path(__file__).with_name('capture-engines')
    root = Path(os.environ.get('CAPTURE_ENGINE_DIR', str(bundled if bundled.is_dir() else Path(__file__).resolve().parent.parent)))
    code = root/name
    default_python = Path('/opt/kantura-' + name + '-env/bin/python')
    python = Path(os.environ.get(name.upper()+'_PYTHON', str(default_python if default_python.is_file() else Path(sys.executable))))
    return code, python


def available(mode):
    code, python = engine_paths(mode)
    script = code/('generate.py' if mode == 'generated' else 'stitch.py')
    if not script.is_file() or not python.is_file():
        return False
    # A venv's bin/python may symlink to the service's base executable, but
    # invoking that path selects different site-packages via pyvenv.cfg. Compare
    # invocation paths, not resolved binary identity; keep the isolated runtime's
    # successful-build import marker mandatory below.
    if os.path.normcase(os.path.abspath(python)) == os.path.normcase(os.path.abspath(sys.executable)):
        modules = ['cv2','numpy','PIL','pillow_heif'] if mode == 'panorama' else ['torch','torchmcubes','tsr']
        try:
            if not all(importlib.util.find_spec(module) for module in modules):
                return False
        except (ImportError, ValueError):
            return False
    elif not (python.parent.parent/'runtime.json').is_file() and not (code/'runtime.json').is_file():
        return False  # Created only after the isolated environment imports pass.
    if mode == 'generated':
        models = Path(os.environ.get('KANTURA_MODEL_DIR', '/opt/kantura-models'))
        try:
            pins = json.loads((code/'pins.json').read_text('utf-8'))
            for item in pins['downloads']:
                path = models/item['name']
                if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size or ('bytes' in item and path.stat().st_size != item['bytes']):
                    return False
        except (OSError, ValueError, KeyError):
            return False
        # The CLI additionally verifies all hashes before loading any weights.
    return True


def run_capture(job_dir, mode, threads=2, foreground_isolated=False):
    job_dir = Path(job_dir).resolve()
    if mode not in {'panorama','generated'} or not available(mode):
        raise ContractError('worker_unavailable')
    work, output = job_dir/'work', job_dir/'artifacts'
    if work.exists() or output.exists():
        raise ContractError('reconstruction_failed')
    work.mkdir()
    stage = work/'result'
    code, python = engine_paths(mode)
    if mode == 'panorama':
        source = job_dir/'input.zip'
        command = [str(python), str(code/'stitch.py'), str(source), str(stage), '--width', '2048', '--timeout', '600', '--worker']
    else:
        source = job_dir/('input.png' if (job_dir/'input.png').is_file() else 'input.jpg')
        command = [str(python), str(code/'generate.py'), '--input', str(source), '--output', str(stage), '--threads', str(min(threads,32))]
        if foreground_isolated:
            command.append('--foreground-isolated')
    if not source.is_file():
        raise ContractError('invalid_archive')
    environment = dict(os.environ)
    # Python Torch wheels must load their own ABI, not OpenSplat's LibTorch 2.2.
    environment.pop('LD_LIBRARY_PATH', None)
    if mode == 'generated':
        environment.update(PYTHONPATH='/opt/triposr', HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1',
                           HF_HUB_DISABLE_TELEMETRY='1', TOKENIZERS_PARALLELISM='false')
    (job_dir/'progress.json').write_text(json.dumps({'stage': 'stitching' if mode == 'panorama' else 'generating'}), 'utf-8')
    result = subprocess.run(command, cwd=work, stdin=subprocess.DEVNULL, check=False, env=environment)
    if result.returncode:
        raise ContractError('panorama_failed' if mode == 'panorama' else 'generation_failed')
    (job_dir/'progress.json').write_text('{"stage":"validating"}', 'utf-8')
    validate_artifacts(stage, mode)
    if mode == 'panorama' and sha256(stage/'originals.zip') != sha256(source):
        raise ContractError('invalid_artifacts')
    output.mkdir()
    for name in ARTIFACTS[mode]:
        shutil.copyfile(stage/name, output/name)
    validate_artifacts(output, mode)
