import json
import os
import sys
import tempfile
import subprocess
import venv
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock
from PIL import Image

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from contract import ContractError, validate_artifacts, sha256
from capture_contract import inspect_generated_input
import capture_engines
from capture_fixtures import artifacts, input_image


class CaptureContracts(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
    def tearDown(self):
        self.temp.cleanup()

    def test_opaque_generation_requires_explicit_foreground_assertion_and_real_image(self):
        path=self.root/'input.png';path.write_bytes(input_image(False))
        with self.assertRaises(ContractError) as error: inspect_generated_input(path,'image/png')
        self.assertEqual(error.exception.code,'foreground_required')
        self.assertFalse(inspect_generated_input(path,'image/png',True)['source']['metricMeasurementsAllowed'])
        path.write_bytes(input_image())
        self.assertEqual(inspect_generated_input(path,'image/png')['imageCount'],1)
        with self.assertRaises(ContractError): inspect_generated_input(path,'image/jpeg')
        Image.new('RGBA',(64,64),(0,0,0,0)).save(path)
        with self.assertRaises(ContractError): inspect_generated_input(path,'image/png')
        path.write_bytes(b'not an image')
        with self.assertRaises(ContractError): inspect_generated_input(path,'image/png',True)

    def test_panorama_validates_alpha_mask_and_spherical_coverage_even_with_updated_hash(self):
        artifacts(self.root,'panorama');self.assertEqual(len(validate_artifacts(self.root,'panorama')),4)
        path=self.root/'coverage.png';Image.new('L',(512,256),255).save(path)
        manifest=json.loads((self.root/'result.json').read_text('utf-8'))
        item=next(x for x in manifest['artifacts'] if x['name']=='coverage.png')
        item.update(bytes=path.stat().st_size,sha256=sha256(path))
        (self.root/'result.json').write_text(json.dumps(manifest),'utf-8')
        with self.assertRaises(ContractError):validate_artifacts(self.root,'panorama')

    def test_generated_actual_glb_triangle_buffers_and_provenance_are_validated(self):
        artifacts(self.root,'generated');self.assertEqual(len(validate_artifacts(self.root,'generated')),5)
        path=self.root/'generation.json';value=json.loads(path.read_text('utf-8'));value['metricMeasurementsAllowed']=True;path.write_text(json.dumps(value),'utf-8')
        with self.assertRaises(ContractError):validate_artifacts(self.root,'generated')
        other=self.root/'nan';artifacts(other,'generated',nonfinite=True)
        with self.assertRaises(ContractError):validate_artifacts(other,'generated')

    def test_capture_cli_handoff_uses_existing_supervisor_paths_and_isolated_torch_environment(self):
        job=self.root/'job';job.mkdir();original=input_image(False);(job/'input.png').write_bytes(original)
        def run(command,**options):
            self.assertEqual(command[command.index('--input')+1],str(job/'input.png'))
            self.assertIn('--foreground-isolated',command)
            self.assertEqual(command[command.index('--threads')+1],'32')
            self.assertNotIn('LD_LIBRARY_PATH',options['env'])
            self.assertEqual(options['env']['HF_HUB_OFFLINE'],'1')
            artifacts(Path(command[command.index('--output')+1]),'generated')
            return SimpleNamespace(returncode=0)
        with mock.patch.object(capture_engines,'available',return_value=True),mock.patch.object(capture_engines.subprocess,'run',side_effect=run),mock.patch.dict(os.environ,{'LD_LIBRARY_PATH':'/wrong/torch'}):
            capture_engines.run_capture(job,'generated',64,True)
        self.assertEqual((job/'input.png').read_bytes(),original)
        self.assertEqual(len(validate_artifacts(job/'artifacts','generated')),5)

    def test_isolated_runtime_is_not_confused_with_the_same_resolved_base_binary(self):
        # Explicit filesystem test double for Linux's venv symlink identity.
        # Covers both real marker locations used by the Docker installers.
        for mode in ['panorama', 'generated']:
            with self.subTest(mode=mode):
                code = self.root / mode
                code.mkdir()
                (code / ('stitch.py' if mode == 'panorama' else 'generate.py')).write_text('# test engine', 'utf-8')
                environment = self.root / (mode + '-env')
                python = environment / 'bin' / 'python'
                python.parent.mkdir(parents=True)
                python.write_bytes(b'test interpreter path, never executed')
                marker = (environment if mode == 'panorama' else code) / 'runtime.json'
                marker.write_text('{"validated":"test-only imports marker"}', 'utf-8')
                models = self.root / (mode + '-models')
                models.mkdir()
                (models / 'model.bin').write_bytes(b'test-only-weight')
                (code / 'pins.json').write_text(json.dumps({'downloads': [{'name': 'model.bin', 'bytes': 16}]}), 'utf-8')
                with mock.patch.object(capture_engines, 'engine_paths', return_value=(code, python)), \
                     mock.patch.object(Path, 'resolve', return_value=Path(sys.executable)), \
                     mock.patch.object(capture_engines.importlib.util, 'find_spec', return_value=None) as base_import, \
                     mock.patch.dict(os.environ, {'KANTURA_MODEL_DIR': str(models)}):
                    self.assertTrue(capture_engines.available(mode))
                    base_import.assert_not_called()
                    marker.unlink()
                    self.assertFalse(capture_engines.available(mode))
                    marker.write_text('{}', 'utf-8')
                    if mode == 'generated':
                        (models / 'model.bin').write_bytes(b'wrong-size')
                        self.assertFalse(capture_engines.available(mode))

    def test_current_interpreter_still_requires_its_actual_imports(self):
        code = self.root / 'panorama'
        code.mkdir()
        (code / 'stitch.py').write_text('# test engine', 'utf-8')
        # A marker cannot override missing imports when using this interpreter.
        (code / 'runtime.json').write_text('{}', 'utf-8')
        with mock.patch.object(capture_engines, 'engine_paths', return_value=(code, Path(sys.executable))), \
             mock.patch.object(capture_engines.importlib.util, 'find_spec', return_value=None) as imports:
            self.assertFalse(capture_engines.available('panorama'))
            imports.assert_called_once_with('cv2')

    @unittest.skipUnless(os.name == 'posix', 'Real Linux venv symlink regression runs in Docker/CI')
    def test_real_symlinked_venv_keeps_its_runtime_identity(self):
        environment = self.root / 'real-env'
        venv.EnvBuilder(with_pip=False, symlinks=True).create(environment)
        python = environment / 'bin' / 'python'
        self.assertEqual(python.resolve(), Path(sys.executable).resolve())
        result = subprocess.run([str(python), '-c',
            'import sys,json,pathlib; pathlib.Path(sys.prefix,"runtime.json").write_text(json.dumps({"prefix":sys.prefix})); print(sys.prefix)'],
            capture_output=True, text=True, check=True, timeout=20)
        self.assertEqual(Path(result.stdout.strip()), environment)
        code = self.root / 'panorama'
        code.mkdir()
        (code / 'stitch.py').write_text('# test engine', 'utf-8')
        with mock.patch.object(capture_engines, 'engine_paths', return_value=(code, python)), \
             mock.patch.object(capture_engines.importlib.util, 'find_spec', return_value=None):
            self.assertTrue(capture_engines.available('panorama'))

    def test_missing_generation_models_never_advertise_availability(self):
        with mock.patch.dict(os.environ,{'KANTURA_MODEL_DIR':str(self.root/'absent')}):
            self.assertFalse(capture_engines.available('generated'))


if __name__=='__main__':unittest.main()
