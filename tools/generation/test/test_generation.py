import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from input_contract import InputError, MAX_IMAGE_BYTES, MAX_OUTPUT_BYTES, generation_manifest, read_input
from download_models import fetch_verified
from generate import export_models, generate, validate_mesh


class InputContractTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()

    def tearDown(self):
        self.temporary.cleanup()

    def image(self, name="object.png", mode="RGBA"):
        image = Image.new(mode, (120, 100), (0, 0, 0, 0) if mode == "RGBA" else (250, 250, 250))
        draw = ImageDraw.Draw(image)
        draw.rectangle((40, 10, 80, 90), fill=(230, 20, 30, 255) if mode == "RGBA" else (230, 20, 30))
        path = self.root / name
        image.save(path)
        return path

    def test_transparent_foreground_is_centered_without_changing_original(self):
        path = self.image()
        before = path.read_bytes()
        original, prepared, info, ext = read_input(path)
        self.assertEqual(original, before)
        self.assertEqual(path.read_bytes(), before)
        self.assertEqual(info["sha256"], hashlib.sha256(before).hexdigest())
        self.assertEqual(info["preprocessing"]["orientedCropBounds"], [40, 10, 81, 91])
        self.assertEqual(prepared.size, (512, 512))
        self.assertEqual(prepared.mode, "RGB")
        self.assertEqual(prepared.getpixel((0, 0)), (128, 128, 128))
        self.assertEqual(prepared.getpixel((256, 256)), (230, 20, 30))
        self.assertTrue(info["alphaForeground"])
        self.assertEqual(ext, ".png")

    def test_opaque_photo_requires_explicit_foreground_confirmation(self):
        path = self.image("object.jpg", mode="RGB")
        with self.assertRaisesRegex(InputError, "foreground-isolated"):
            read_input(path)
        original, prepared, info, ext = read_input(path, foreground_isolated=True)
        self.assertEqual(original, path.read_bytes())
        self.assertFalse(info["alphaForeground"])
        self.assertTrue(info["foregroundConfirmedByUser"])
        self.assertEqual(ext, ".jpg")

    def test_transparent_empty_corrupt_and_relative_inputs_are_rejected(self):
        path = self.root / "empty.png"
        Image.new("RGBA", (100, 100), (0, 0, 0, 0)).save(path)
        with self.assertRaisesRegex(InputError, "fully transparent"):
            read_input(path)
        path.write_bytes(b"not an image")
        with self.assertRaises(InputError):
            read_input(path)
        with self.assertRaises(InputError):
            read_input(Path("relative.png"))
        unsupported = self.root / "page.svg"
        unsupported.write_text("<svg/>")
        with self.assertRaises(InputError):
            read_input(unsupported)

    def test_size_and_resolution_limits_before_model_import(self):
        path = self.root / "large.jpg"
        with path.open("wb") as file:
            file.truncate(MAX_IMAGE_BYTES + 1)
        with self.assertRaisesRegex(InputError, "25 MiB"):
            read_input(path, True)
        Image.new("RGB", (8193, 64)).save(path)
        with self.assertRaisesRegex(InputError, "64–8192"):
            read_input(path, True)
        Image.new("RGB", (30, 64)).save(path)
        with self.assertRaises(InputError):
            read_input(path, True)

    def test_existing_output_and_bad_input_do_not_overwrite_files_or_load_model(self):
        path = self.image()
        output = self.root / "result"
        output.mkdir()
        keep = output / "keep.txt"
        keep.write_text("private existing work")
        args = argparse.Namespace(input=path, output=output, foreground_isolated=False, resolution=96, threads=2)
        with self.assertRaisesRegex(InputError, "empty"):
            generate(args)
        self.assertEqual(keep.read_text(), "private existing work")
        self.assertFalse((output / "generation.json").exists())
        self.assertFalse((output / "Original").exists())

    def test_missing_engine_keeps_original_and_marks_failure(self):
        path = self.image()
        before = path.read_bytes()
        output = self.root / "result"
        args = argparse.Namespace(input=path, output=output, foreground_isolated=False, resolution=96, threads=2)
        with patch.dict("os.environ", {"KANTURA_MODEL_DIR": str(self.root / "no-model")}), self.assertRaises(InputError):
            generate(args)
        self.assertEqual((output / "Original/input.png").read_bytes(), before)
        self.assertFalse((output / "generation.json").exists())
        self.assertFalse((output / ".generation-lock").exists())
        error = json.loads((output / "generation-error.json").read_text())
        self.assertEqual(error["status"], "failed")
        self.assertFalse(error["metricMeasurementsAllowed"])


class IntegrityTests(unittest.TestCase):
    def test_downloader_checks_hash_and_size_before_promoting_file(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "model.ckpt"
            payload = b"verified fixture, not a neural checkpoint"
            entry = {"name": "model.ckpt", "url": "https://example.invalid/model", "bytes": len(payload),
                     "sha256": hashlib.sha256(payload).hexdigest()}
            with patch("urllib.request.urlopen", return_value=io.BytesIO(payload)):
                fetch_verified(entry, path)
            self.assertEqual(path.read_bytes(), payload)
            path.unlink()
            for bad in (payload + b"extra", b"different model"):
                with patch("urllib.request.urlopen", return_value=io.BytesIO(bad)), self.assertRaises(ValueError):
                    fetch_verified(entry, path)
                self.assertFalse(path.exists())
                self.assertFalse(path.with_suffix(".ckpt.download").exists())

    def test_manifest_cannot_omit_generated_scale_and_measurement_limits(self):
        pins = json.loads(Path(__file__).resolve().parents[1].joinpath("pins.json").read_text())
        outputs = {name: {"bytes": 1, "sha256": "0" * 64} for name in
                   ("generated-model.glb", "generated-model.obj", "generated-model.ply", "model.zip")}
        options = dict(input_metadata={"sha256": "a" * 64}, original_file="Original/input.png", outputs=outputs,
                       pins=pins, resolution=96, threads=2, duration_seconds=4.2, vertices=12, faces=20)
        manifest = generation_manifest(**options)
        self.assertEqual(manifest["source"], "generated")
        self.assertEqual(manifest["units"], "arbitrary")
        self.assertEqual(manifest["scaleStatus"], "unverified")
        self.assertFalse(manifest["metricMeasurementsAllowed"])
        with self.assertRaises(ValueError):
            generation_manifest(**dict(options, resolution=4096))
        with self.assertRaises(ValueError):
            generation_manifest(**dict(options, duration_seconds=float("nan")))
        with self.assertRaises(ValueError):
            generation_manifest(**dict(options, outputs={}))


@unittest.skipUnless(importlib.util.find_spec("trimesh"), "trimesh is installed in the Docker inference image")
class MeshExportTests(unittest.TestCase):
    def test_real_format_export_preserves_vertex_colors_and_generated_provenance(self):
        import numpy as np
        import trimesh
        # This is an export-format fixture, not a substitute for the model run.
        mesh = trimesh.creation.icosphere(subdivisions=1)
        mesh.visual.vertex_colors = np.tile([17, 80, 190, 255], (len(mesh.vertices), 1))
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            entries = export_models(mesh, output)
            self.assertEqual(set(entries), {"generated-model.glb", "generated-model.obj", "generated-model.ply", "model.zip"})
            for name, info in entries.items():
                payload = (output / name).read_bytes()
                self.assertEqual(info["bytes"], len(payload))
                self.assertEqual(info["sha256"], hashlib.sha256(payload).hexdigest())
            scene = trimesh.load(output / "generated-model.glb", force="scene")
            self.assertEqual(scene.metadata["source"], "generated")
            self.assertFalse(scene.metadata["metricMeasurementsAllowed"])
            restored = list(scene.geometry.values())[0]
            self.assertTrue(np.all(restored.visual.vertex_colors == [17, 80, 190, 255]))
            self.assertIn(b"metricMeasurementsAllowed=false", (output / "generated-model.ply").read_bytes()[:300])
            with zipfile.ZipFile(output / "model.zip") as archive:
                self.assertEqual(set(archive.namelist()), {"model.glb", "rtab-measure.json"})
                project = json.loads(archive.read("rtab-measure.json"))
                self.assertEqual(project["source"], "generated")
                self.assertFalse(project["calibrated"])
                self.assertFalse(project["metricMeasurementsAllowed"])
                self.assertEqual(project["measurements"], [])
                self.assertEqual(archive.read("model.glb"), (output / "generated-model.glb").read_bytes())

    def test_empty_and_nonfinite_model_output_fails_instead_of_making_a_placeholder(self):
        import numpy as np
        import trimesh
        with self.assertRaises(RuntimeError):
            validate_mesh(trimesh.Trimesh())
        bad = trimesh.Trimesh(vertices=[[0, 0, 0], [1, 0, 0], [float("nan"), 1, 0]], faces=[[0, 1, 2]], process=False)
        with self.assertRaises(RuntimeError):
            validate_mesh(bad)


if __name__ == "__main__":
    unittest.main()
