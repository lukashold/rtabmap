"""Bounded private worker logs for the synthetic CI container only."""
import os
import re
import uuid
from pathlib import Path

MAX_BYTES = 64 * 1024


def tail(path, token):
    with path.open('rb') as stream:
        stream.seek(0, 2)
        stream.seek(max(0, stream.tell() - MAX_BYTES))
        text = stream.read(MAX_BYTES).decode('utf-8', 'replace')
    if token:
        text = text.replace(token, '[REDACTED]')
    # Do not let engine logs inject terminal control sequences.
    return ''.join(c for c in text if c in '\n\t' or ord(c) >= 32 and ord(c) != 127)


def main():
    marker = str(uuid.uuid4())
    # GitHub treats double-colon output as workflow commands unless suspended.
    print('::stop-commands::' + marker, flush=True)
    try:
        token = os.environ.get('RECONSTRUCTION_TOKEN', '')
        jobs = [path for path in Path('/data').iterdir()
                if re.fullmatch(r'[0-9a-f-]{36}', path.name) and path.is_dir() and not path.is_symlink()]
        for folder in sorted(jobs, key=lambda path: path.stat().st_mtime)[-4:]:
            for name in ('state.json', 'error.json', 'progress.json', 'worker.log'):
                path = folder / name
                if path.is_file() and not path.is_symlink():
                    print(f'--- synthetic job {folder.name}/{name} (last {MAX_BYTES} bytes) ---')
                    print(tail(path, token), flush=True)
    finally:
        print('::' + marker + '::', flush=True)


if __name__ == '__main__':
    main()
