"""Encode our own synthetic JPEG sequence using the installed worker FFmpeg.

Only used in CI. Original images and geometry truth stay separate; encoded video
contains neither camera poses nor calibration that could leak into reconstruction.
"""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('--archive',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
args = parser.parse_args()
args.output.parent.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='kantura-video-') as folder:
    root = Path(folder)
    with zipfile.ZipFile(args.archive) as archive:
        images = [name for name in archive.namelist() if name.lower().endswith('.jpg')]
        if not 8 <= len(images) <= 80: raise ValueError('Invalid synthetic sequence')
        for index,name in enumerate(images):
            (root/f'frame_{index:03}.jpg').write_bytes(archive.read(name))
    subprocess.run(['docker','run','--rm','--user',f'{os.getuid()}:{os.getgid()}',
        '--entrypoint','ffmpeg','--mount',f'type=bind,source={root},target=/validation',
        'kantura-reconstruction:ci','-hide_banner','-loglevel','error','-framerate','2',
        '-i','/validation/frame_%03d.jpg','-c:v','libx264','-crf','15','-pix_fmt','yuv420p',
        '-an','/validation/capture.mp4'],check=True,timeout=120)
    args.output.write_bytes((root/'capture.mp4').read_bytes())
print(f'Encoded {len(images)} own synthetic views: {args.output}')
