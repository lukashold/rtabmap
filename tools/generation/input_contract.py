"""Bounded image input and generated-output provenance, independent of Torch."""
import hashlib
import io
import math
from pathlib import Path
import warnings

from PIL import Image, ImageOps

MAX_IMAGE_BYTES = 25 * 1024 * 1024
MAX_IMAGE_PIXELS = 16 * 1024 * 1024
MAX_IMAGE_SIDE = 8192
MODEL_IMAGE_SIDE = 512
MAX_OUTPUT_BYTES = 200 * 1024 * 1024


class InputError(ValueError):
    pass


def read_input(path, foreground_isolated=False):
    """Return original bytes + prepared RGB image, never modifying the original.

    Alpha images are cropped to their nontransparent subject and placed inside
    an 85% square. Opaque inputs require an explicit foreground-isolated flag.
    This is transparent compositing, NOT automatic segmentation or reconstruction.
    """
    path = Path(path)
    if not path.is_absolute() or path.is_symlink() or not path.is_file():
        raise InputError("Input must be an absolute path to a regular, non-symlink image file")
    if path.suffix.lower() not in (".png", ".jpg", ".jpeg"):
        raise InputError("Use a PNG or JPEG foreground-object image")
    size = path.stat().st_size
    if not 0 < size <= MAX_IMAGE_BYTES:
        raise InputError("Input exceeds the 25 MiB limit or is empty")
    with path.open("rb") as stream:
        original = stream.read(MAX_IMAGE_BYTES + 1)
    if len(original) != size or len(original) > MAX_IMAGE_BYTES:
        raise InputError("Input changed while being read or exceeds its size limit")
    with warnings.catch_warnings():
        warnings.simplefilter("error", Image.DecompressionBombWarning)
        try:
            with Image.open(io.BytesIO(original)) as source:
                width, height = source.size
                if source.format not in ("PNG", "JPEG") or getattr(source, "n_frames", 1) != 1:
                    raise InputError("Only one still PNG/JPEG image is accepted")
                if min(width, height) < 64 or max(width, height) > MAX_IMAGE_SIDE or width * height > MAX_IMAGE_PIXELS:
                    raise InputError("Image must be 64–8192 pixels per side and at most 16 megapixels")
                source.load()
                oriented = ImageOps.exif_transpose(source)
                rgba = oriented.convert("RGBA")
        except (OSError, Image.DecompressionBombError, Image.DecompressionBombWarning) as error:
            raise InputError("Image decode rejected: " + str(error)) from error
    alpha = rgba.getchannel("A")
    low, high = alpha.getextrema()
    if high == 0:
        raise InputError("The image is fully transparent")
    transparent = low < 255
    if not transparent and not foreground_isolated:
        raise InputError("Provide a transparent PNG, or explicitly use --foreground-isolated for a centered object on a plain background")
    if transparent:
        bounds = alpha.getbbox()
        assert bounds is not None
        foreground = rgba.crop(bounds)
        kind = "alpha-bounds-centered-on-grey"
    else:
        bounds = (0, 0, rgba.width, rgba.height)
        foreground = rgba
        kind = "user-confirmed-foreground-centered-on-grey"
    foreground.thumbnail((round(MODEL_IMAGE_SIDE * 0.85), round(MODEL_IMAGE_SIDE * 0.85)), Image.Resampling.LANCZOS)
    # Thumbnail only reduces. Upscale small foregrounds to keep the documented
    # 85% occupancy and avoid tiny images being treated as tiny objects.
    scale = MODEL_IMAGE_SIDE * 0.85 / max(foreground.size)
    target = (max(1, round(foreground.width * scale)), max(1, round(foreground.height * scale)))
    foreground = foreground.resize(target, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (MODEL_IMAGE_SIDE, MODEL_IMAGE_SIDE), (128, 128, 128, 255))
    canvas.alpha_composite(foreground, ((MODEL_IMAGE_SIDE - foreground.width) // 2, (MODEL_IMAGE_SIDE - foreground.height) // 2))
    metadata = {
        "originalName": path.name,
        "bytes": len(original),
        "sha256": hashlib.sha256(original).hexdigest(),
        "width": width,
        "height": height,
        "alphaForeground": transparent,
        "foregroundConfirmedByUser": bool(foreground_isolated),
        "preprocessing": {"kind": kind, "modelImageSize": MODEL_IMAGE_SIDE, "occupancy": 0.85,
                          "orientedCropBounds": list(bounds), "backgroundRGB": [128, 128, 128]},
    }
    extension = ".png" if original.startswith(b"\x89PNG\r\n\x1a\n") else ".jpg"
    return original, canvas.convert("RGB"), metadata, extension


def generation_manifest(*, input_metadata, original_file, outputs, pins, resolution, threads, duration_seconds, vertices, faces):
    if resolution not in (96, 128) or not 1 <= threads <= 32:
        raise ValueError("Unsupported inference bounds")
    if not math.isfinite(duration_seconds) or duration_seconds < 0 or vertices <= 0 or faces <= 0:
        raise ValueError("Invalid result statistics")
    expected = {"generated-model.glb", "generated-model.obj", "generated-model.ply", "model.zip"}
    if set(outputs) != expected:
        raise ValueError("All three generated formats and browser archive must be present")
    for name, info in outputs.items():
        if not 0 < info["bytes"] <= MAX_OUTPUT_BYTES or len(info["sha256"]) != 64:
            raise ValueError("Invalid output integrity metadata: " + name)
    return {
        "format": "kantura-generation", "version": 1, "source": "generated", "mode": "single-image-to-3d",
        "metricMeasurementsAllowed": False, "scaleStatus": "unverified", "units": "arbitrary", "upAxis": "y",
        "geometryStatus": "inferred-including-unseen-surfaces", "status": "complete",
        "engine": {"name": "TripoSR", "sourceCommit": pins["triposr"]["commit"],
                   "weightsRevision": pins["triposr"]["weightsRevision"],
                   "weightsSHA256": next(item["sha256"] for item in pins["downloads"] if item["name"] == "model.ckpt"),
                   "device": "cpu", "marchingCubesResolution": resolution, "threads": threads},
        "input": dict(input_metadata, file=original_file), "outputs": outputs,
        "statistics": {"vertices": int(vertices), "faces": int(faces), "durationSeconds": round(duration_seconds, 3)},
        "limitations": ["Generated geometry is not a scan of the physical object.",
                        "Unseen surfaces and dimensions are inferred and may be wrong.",
                        "Do not use this output for metric measurements, fitting parts or construction.",
                        "Vertex colors are inferred; no photographically verified surface texture is claimed."],
    }
