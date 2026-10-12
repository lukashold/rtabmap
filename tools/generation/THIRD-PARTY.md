# Generation engine provenance

The TripoSR repository states that its MIT release includes source and pretrained
models. This component does not download any model from Polycam or other scanning
apps. It is a separate optional CPU tool, not an iOS-bundled neural engine.

| Component | Immutable source | License / treatment |
| --- | --- | --- |
| TripoSR code | [VAST-AI-Research/TripoSR `107cefd…`](https://github.com/VAST-AI-Research/TripoSR/tree/107cefdc244c39106fa830359024f6a2f1c78871) | MIT; original source and notices retained under `/opt/triposr`; two documented local import/config patches |
| TripoSR checkpoint | [stabilityai/TripoSR `5d95c21…`](https://huggingface.co/stabilityai/TripoSR/tree/5d95c2191bfbe7b97e1f1d1d7271dc28eaadd9ee) | MIT per model card and official source README; exact SHA-256 and size in `pins.json` |
| DINO ViT configuration | [facebook/dino-vitb16 `f205d5d…`](https://huggingface.co/facebook/dino-vitb16/tree/f205d5d8e640a89a2b8ef0369670dfc37cc07fc2) | Apache-2.0 per model metadata; only architecture JSON downloaded, no separate DINO weight archive |
| torchmcubes | [tatsy/torchmcubes `879926d…`](https://github.com/tatsy/torchmcubes/tree/879926d0ef58e6ce0ac2630fdecb5e53af7ed3ff) | **MPL-2.0**, not MIT; unmodified complete corresponding source and license retained under `/opt/torchmcubes-src` in every image |
| PyTorch / Transformers / supporting packages | Exact direct versions in `requirements.txt` and installer; resolved environment saved as `installed-packages.txt` in the image | Separate upstream package licenses remain in installed distributions; do not describe the whole dependency stack as MIT |

Copies of TripoSR's MIT license, torchmcubes' MPL-2.0 license and Apache-2.0 are
in `licenses/`. Apache-derived transformer code also retains its original file
headers inside the vendored TripoSR tree. If redistributing binaries, preserve
these files and the included torchmcubes source rather than copying only its
compiled extension. This is a provenance record, not trademark or legal clearance.

The checkpoint SHA-256 comes from Hugging Face's Git LFS metadata for the pinned
revision: `429e2c6b22a0923967459de24d67f05962b235f79cde6b032aa7ed2ffcd970ee`,
1,677,246,742 bytes. The build streams the download and verifies both size and
digest. The smaller TripoSR YAML and DINO JSON are independently SHA-256 pinned.

Local changes applied by `patch_vendor.py`:

1. Move `rembg`'s import inside its unused upstream helper, avoiding an extra
   segmentation dependency/model. The CLI accepts a supplied foreground and never
   calls this helper.
2. Load the DINO architecture JSON from the verified local file rather than an
   unpinned network Hub request. Neural architecture parameters and TripoSR
   checkpoint weights are unchanged.

The adapter directly constructs `TSR` and uses `weights_only=True`; it does not
execute upstream `run.py`, Gradio, browser scripts, or arbitrary uploaded pickle.
The offline execution contract and generated provenance are part of Kantura's
adapter, not a performance or dimensional-accuracy claim from the upstream model.
