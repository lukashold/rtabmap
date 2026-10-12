import json
import os
import sys
import tempfile
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

    def test_missing_generation_models_never_advertise_availability(self):
        with mock.patch.dict(os.environ,{'KANTURA_MODEL_DIR':str(self.root/'absent')}):
            self.assertFalse(capture_engines.available('generated'))


if __name__=='__main__':unittest.main()
