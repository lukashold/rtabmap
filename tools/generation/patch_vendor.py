"""Two explicit, fail-closed changes to the pinned TripoSR source.

The neural architecture and weights are unchanged. Original licenses stay in
the image alongside the complete source. No background-removal model is used.
"""
from pathlib import Path
import sys


def replace_once(path, before, after):
    source = path.read_text()
    if source.count(before) != 1:
        raise RuntimeError("Unexpected upstream source; review patch: " + str(path))
    path.write_text(source.replace(before, after))


def patch(root):
    root = Path(root)
    replace_once(root / "tsr/utils.py", "import rembg\n", "")
    replace_once(root / "tsr/utils.py", "        image = rembg.remove(image, session=rembg_session, **rembg_kwargs)",
                 "        # Kantura: this optional upstream helper is not used by the CLI.\n"
                 "        import rembg\n"
                 "        image = rembg.remove(image, session=rembg_session, **rembg_kwargs)")
    tokenizer = root / "tsr/models/tokenizers/image.py"
    replace_once(tokenizer, "from dataclasses import dataclass", "from dataclasses import dataclass\nimport os")
    replace_once(tokenizer,
                 'ViTModel.config_class.from_pretrained(\n'
                 '                hf_hub_download(\n'
                 '                    repo_id=self.cfg.pretrained_model_name_or_path,\n'
                 '                    filename="config.json",\n'
                 '                )\n'
                 '            )',
                 '# Kantura: immutable local architecture config, no runtime Hub access.\n'
                 '            ViTModel.config_class.from_json_file(os.environ["KANTURA_DINO_CONFIG"])')


if __name__ == "__main__":
    patch(sys.argv[1])
