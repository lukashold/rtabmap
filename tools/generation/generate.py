"""Offline CPU single-image-to-3D generation using actual pinned TripoSR weights."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time
import zipfile

from input_contract import InputError, MAX_OUTPUT_BYTES, generation_manifest, read_input


def progress(stage, **fields):
    print(json.dumps({"stage": stage, **fields}), flush=True)


def verified_model_paths(model_dir, pins):
    # Model directory is part of the build image, not an accepted user payload.
    # Verify again at startup so a changed/mounted model cannot inherit false
    # provenance from the build's pins. Checkpoint deserialization
    # below also restricts itself to tensor weights rather than arbitrary pickle.
    for entry in pins["downloads"]:
        path = model_dir / entry["name"]
        if path.is_symlink() or not path.is_file() or ("bytes" in entry and path.stat().st_size != entry["bytes"]):
            raise InputError("Pinned model file is missing or changed: " + entry["name"])
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        if digest.hexdigest() != entry["sha256"]:
            raise InputError("Pinned model integrity check failed: " + entry["name"])


def validate_mesh(mesh):
    import numpy as np
    vertices, faces = np.asarray(mesh.vertices), np.asarray(mesh.faces)
    if vertices.ndim != 2 or vertices.shape[1] != 3 or not 3 <= len(vertices) <= 2_000_000:
        raise RuntimeError("TripoSR produced an empty or oversized vertex array")
    if faces.ndim != 2 or faces.shape[1] != 3 or not 1 <= len(faces) <= 4_000_000:
        raise RuntimeError("TripoSR produced an empty or oversized triangle array")
    if not np.isfinite(vertices).all() or faces.min() < 0 or faces.max() >= len(vertices):
        raise RuntimeError("TripoSR produced invalid coordinates or triangle indices")
    if not np.isfinite(mesh.bounds).all() or np.linalg.norm(mesh.extents) <= 1e-8:
        raise RuntimeError("TripoSR produced degenerate geometry")
    colors = np.asarray(mesh.visual.vertex_colors)
    if colors.shape != (len(vertices), 4):
        raise RuntimeError("TripoSR output is missing vertex colors")


def export_models(mesh, output):
    import trimesh
    validate_mesh(mesh)
    provenance = {"source": "generated", "metricMeasurementsAllowed": False, "scaleStatus": "unverified",
                  "generator": "Kantura / TripoSR", "units": "arbitrary"}
    mesh.metadata.update(provenance)
    scene = trimesh.Scene(mesh)
    scene.metadata.update(provenance)
    glb = scene.export(file_type="glb")
    obj = ("# Kantura: AI-generated geometry, NOT a measured scan.\n"
           "# metricMeasurementsAllowed=false; scaleStatus=unverified; units=arbitrary\n" +
           trimesh.exchange.obj.export_obj(mesh, include_color=True, include_texture=False)).encode("utf-8")
    ply = trimesh.exchange.ply.export_ply(mesh, encoding="binary_little_endian", vertex_normal=True)
    if not ply.startswith(b"ply\n"):
        raise RuntimeError("Unexpected PLY exporter format")
    ply = ply.replace(b"ply\n", b"ply\ncomment Kantura AI-generated, not a measured scan\n"
                      b"comment metricMeasurementsAllowed=false scaleStatus=unverified units=arbitrary\n", 1)
    outputs = {}
    for name, data in {"generated-model.glb": glb, "generated-model.obj": obj, "generated-model.ply": ply}.items():
        if not isinstance(data, bytes) or not 0 < len(data) <= MAX_OUTPUT_BYTES:
            raise RuntimeError("Generated output exceeds the 200 MiB per-format limit")
        target = output / name
        temporary = output / (name + ".partial")
        with temporary.open("xb") as stream:
            stream.write(data)
        temporary.replace(target)
        outputs[name] = {"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
    # Kantura's browser opens exactly one model in a project archive. The other
    # export formats and private originals intentionally stay outside this ZIP.
    project = {"version": 1, "name": "AI-generated model", "scale": 1, "upAxis": "y", "calibrated": False,
               "source": "generated", "metricMeasurementsAllowed": False,
               "measurements": [], "notes": [], "checks": []}
    archive = output / "model.zip"
    temporary = output / "model.zip.partial"
    with zipfile.ZipFile(temporary, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as target:
        target.writestr("model.glb", glb)
        target.writestr("rtab-measure.json", json.dumps(project, indent=2) + "\n")
    if temporary.stat().st_size > MAX_OUTPUT_BYTES:
        raise RuntimeError("Browser archive exceeds 200 MiB")
    temporary.replace(archive)
    digest = hashlib.sha256()
    with archive.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    outputs["model.zip"] = {"bytes": archive.stat().st_size, "sha256": digest.hexdigest()}
    return outputs


def generate(args):
    started = time.monotonic()
    original, prepared, input_metadata, extension = read_input(args.input, args.foreground_isolated)
    output = args.output
    if not output.is_absolute() or output.is_symlink():
        raise InputError("Output must be an absolute, non-symlink directory")
    output.mkdir(parents=False, exist_ok=True)
    if not output.is_dir() or any(output.iterdir()):
        raise InputError("Output directory must be empty; existing files are never overwritten")
    # Exclusive creation also handles two processes racing for an empty output.
    lock = output / ".generation-lock"
    with lock.open("x") as stream:
        stream.write(str(os.getpid()))
    try:
        original_dir = output / "Original"
        original_dir.mkdir()
        original_file = "Original/input" + extension
        (output / original_file).write_bytes(original)
        # This derived input has no EXIF/location metadata. The separate original
        # intentionally retains its exact bytes and must be shared consciously.
        prepared.save(output / "prepared-input.png")
        progress("input-ready", bytes=len(original), source="generated", metricMeasurementsAllowed=False)
        pins = json.loads(Path(__file__).with_name("pins.json").read_text())
        model_dir = Path(os.environ.get("KANTURA_MODEL_DIR", "/opt/kantura-models"))
        if not model_dir.is_absolute():
            raise InputError("KANTURA_MODEL_DIR must be absolute")
        verified_model_paths(model_dir, pins)
        os.environ["KANTURA_DINO_CONFIG"] = str(model_dir / "dino-config.json")
        os.environ["HF_HUB_OFFLINE"] = "1"
        os.environ["TRANSFORMERS_OFFLINE"] = "1"
        import torch
        from omegaconf import OmegaConf
        from tsr.system import TSR
        torch.set_num_threads(args.threads)
        torch.set_num_interop_threads(1)
        torch.manual_seed(0)
        progress("loading-model", engine="TripoSR", device="cpu")
        config = OmegaConf.load(model_dir / "config.yaml")
        OmegaConf.resolve(config)
        model = TSR(config)
        weights = torch.load(model_dir / "model.ckpt", map_location="cpu", weights_only=True)
        model.load_state_dict(weights, strict=True)
        del weights
        model.eval().to("cpu")
        model.renderer.set_chunk_size(8192)
        progress("inference", imageSize=512)
        with torch.inference_mode():
            scene_codes = model([prepared], device="cpu")
            progress("extracting-mesh", resolution=args.resolution)
            meshes = model.extract_mesh(scene_codes, has_vertex_color=True, resolution=args.resolution)
        if len(meshes) != 1:
            raise RuntimeError("Expected exactly one generated mesh")
        mesh = meshes[0]
        # Upstream get_spherical_cameras uses Z as up. Export all formats in
        # right-handed Y-up so the browser archive has a consistent upAxis.
        mesh.apply_transform([[1, 0, 0, 0], [0, 0, 1, 0], [0, -1, 0, 0], [0, 0, 0, 1]])
        progress("exporting")
        outputs = export_models(mesh, output)
        manifest = generation_manifest(input_metadata=input_metadata, original_file=original_file, outputs=outputs,
            pins=pins, resolution=args.resolution, threads=args.threads, duration_seconds=time.monotonic() - started,
            vertices=len(mesh.vertices), faces=len(mesh.faces))
        # Written last: consumers must require a complete manifest before using
        # any partially exported output as a successful generation result.
        temporary = output / "generation.json.partial"
        temporary.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        temporary.replace(output / "generation.json")
        progress("complete", **manifest["statistics"])
    except Exception as error:
        # Preserve input for recovery; never replace failure with invented mesh.
        (output / "generation-error.json").write_text(json.dumps({"status": "failed", "source": "generated",
            "metricMeasurementsAllowed": False, "message": str(error)[:2000]}, indent=2) + "\n", encoding="utf-8")
        raise
    finally:
        lock.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True, help="Absolute path to a still foreground PNG/JPEG")
    parser.add_argument("--output", type=Path, required=True, help="Absolute path to an empty writable directory")
    parser.add_argument("--foreground-isolated", action="store_true", help="Confirm an opaque image already shows one centered object on a plain background")
    parser.add_argument("--resolution", type=int, choices=(96, 128), default=96)
    parser.add_argument("--threads", type=int, choices=range(1, 33), default=2)
    args = parser.parse_args()
    try:
        generate(args)
    except Exception as error:
        print(json.dumps({"stage": "failed", "error": str(error)[:2000]}), file=sys.stderr, flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
