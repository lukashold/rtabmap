"""Bounded local MP4/MOV decoding and explainable frame selection."""
import json
import math
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

from contract import LIMITS, VIDEO_LIMITS, ContractError, inspect_video_input
from quality import image_quality, near_duplicate


def probe_video(path):
    inspect_video_input(path)
    if not shutil.which('ffprobe'):
        raise ContractError('worker_unavailable')
    # Force a local MOV/MP4 demuxer. No playlists, URL protocols, audio decode,
    # external data-reference paths, or user-controlled command fragments.
    command = ['ffprobe', '-v', 'error', '-protocol_whitelist', 'file',
               '-f', 'mov', '-enable_drefs', '0', '-use_absolute_path', '0',
               '-probesize', '10000000', '-analyzeduration', '10000000',
               # Full stream metadata includes its display matrix in both 4.4
               # and newer releases. The shared side_data selector also enables
               # packet/frame sections in 4.4; never use it for this preflight.
               '-select_streams', 'v:0', '-show_streams', '-show_format',
               '-of', 'json', str(path)]
    result = None

    def diagnostic(reason):
        def bounded(field, maximum):
            data = getattr(result, field, b'') or b''
            if isinstance(data, bytes):
                data = data.decode('utf-8', 'replace')
            return data[:maximum]
        # Only private worker.log receives these bounded, JSON-escaped details.
        # No environment, bearer token, original filename or public API payload.
        print(json.dumps({'program': 'ffprobe', 'reason': reason,
                          'arguments': command[1:-1]+['<input.video>'],
                          'exitCode': getattr(result, 'returncode', None),
                          'stdout': bounded('stdout', 2048),
                          'stderr': bounded('stderr', 2048)}, ensure_ascii=True), file=sys.stderr, flush=True)
    try:
        result = subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True, timeout=20, check=False)
        if result.returncode or len(result.stdout) > 65536:
            raise ContractError('unsupported_video')
        document = json.loads(result.stdout)
        streams = document.get('streams', [])
        if len(streams) != 1:
            raise ContractError('unsupported_video')
        video = streams[0]
        width, height = int(video['width']), int(video['height'])
        duration = float(video.get('duration', document.get('format', {}).get('duration')))
        numerator, denominator = video['avg_frame_rate'].split('/')
        rate = float(numerator)/float(denominator)
        rotation = float(video.get('tags', {}).get('rotate', 0))
        for item in video.get('side_data_list', []):
            if 'rotation' in item:
                rotation = float(item['rotation'])
        if video.get('codec_name') not in {'h264', 'hevc', 'mpeg4'}:
            raise ContractError('unsupported_video')
        if not all(math.isfinite(v) for v in [duration, rate, rotation]):
            raise ContractError('unsupported_video')
        if not 4 <= duration <= VIDEO_LIMITS['durationSeconds']:
            raise ContractError('video_duration')
        if not 0 < rate <= VIDEO_LIMITS['maxFrameRate']:
            raise ContractError('unsupported_video')
        if not 32 <= width <= VIDEO_LIMITS['maxWidth'] or not 32 <= height <= VIDEO_LIMITS['maxHeight'] or width*height > VIDEO_LIMITS['maxPixels']:
            raise ContractError('video_dimensions')
        if abs(rotation/90-round(rotation/90)) > .001:
            raise ContractError('unsupported_video')
        return {'codec': video['codec_name'], 'encodedWidth': width, 'encodedHeight': height,
                'durationSeconds': duration, 'averageFrameRate': rate,
                'rotationDegrees': rotation, 'autorotation': 'ffmpeg-default-enabled'}
    except ContractError as error:
        diagnostic(error.code)
        raise
    except (ValueError, KeyError, TypeError, ZeroDivisionError, OSError, subprocess.TimeoutExpired) as error:
        diagnostic(type(error).__name__)
        raise ContractError('unsupported_video') from error


def select_frames(candidates, maximum=250):
    """Prefer sharp candidates in uniform timeline bins, reject near repeats."""
    buckets = {}
    rejected = []
    for index, item in enumerate(candidates):
        quality = item['quality']
        if quality['laplacianVariance128'] < 20:
            rejected.append({'candidate': item['candidate'], 'reason': 'low-detail-or-blur'})
            continue
        if quality['darkFraction'] > .95 or quality['brightFraction'] > .95:
            rejected.append({'candidate': item['candidate'], 'reason': 'extreme-exposure'})
            continue
        bucket = index * min(maximum, len(candidates)) // max(1, len(candidates))
        previous = buckets.get(bucket)
        if previous is None or quality['laplacianVariance128'] > previous['quality']['laplacianVariance128']:
            if previous:
                rejected.append({'candidate': previous['candidate'], 'reason': 'sharper-in-time-bin'})
            buckets[bucket] = item
        else:
            rejected.append({'candidate': item['candidate'], 'reason': 'sharper-in-time-bin'})
    selected = []
    for item in sorted(buckets.values(), key=lambda value: value['candidate']):
        duplicate = next((previous for previous in selected if near_duplicate(item['_fingerprint'], previous['_fingerprint'], item['quality'], previous['quality'])), None)
        if duplicate:
            rejected.append({'candidate': item['candidate'], 'reason': 'near-duplicate', 'duplicateOf': duplicate['candidate']})
        else:
            selected.append(item)
    return selected, rejected


def prepare_video(path, image_dir, max_size=1600, run=None):
    from PIL import Image
    metadata = probe_video(path)
    if not shutil.which('ffmpeg'):
        raise ContractError('worker_unavailable')
    raw = image_dir.parent / 'video-candidates'
    raw.mkdir()
    image_dir.mkdir()
    # Sampling spans the complete clip. At most 360 candidates and 250 selected
    # images; ffmpeg's default autorotation precedes the scale filter.
    sampling = min(2.0, VIDEO_LIMITS['candidateFrames']/metadata['durationSeconds'])
    arguments = ['-nostdin', '-v', 'error', '-protocol_whitelist', 'file',
                 '-f', 'mov', '-enable_drefs', '0', '-use_absolute_path', '0',
                 '-threads', '2', '-i', path, '-map', '0:v:0', '-an', '-sn', '-dn',
                 '-t', str(VIDEO_LIMITS['durationSeconds']),
                 '-vf', f"fps={sampling:.8f},scale=w='min({max_size},iw)':h='min({max_size},ih)':force_original_aspect_ratio=decrease",
                 '-frames:v', str(VIDEO_LIMITS['candidateFrames']), '-q:v', '2', '-threads', '2',
                 raw / 'candidate_%06d.jpg']
    if run is None:
        result = subprocess.run(['ffmpeg']+[str(v) for v in arguments], stdin=subprocess.DEVNULL, check=False, timeout=600)
        if result.returncode:
            raise ContractError('unsupported_video')
    else:
        run('extracting', 'ffmpeg', *arguments)
    candidates = []
    for index, filename in enumerate(sorted(raw.glob('candidate_*.jpg'))):
        if index >= VIDEO_LIMITS['candidateFrames'] or filename.stat().st_size > LIMITS.image:
            raise ContractError('too_large')
        with Image.open(filename) as image:
            if image.width > max_size or image.height > max_size:
                raise ContractError('video_dimensions')
            quality, fingerprint = image_quality(image)
            candidates.append({'candidate': index+1, 'path': filename,
                               'quality': quality, '_fingerprint': fingerprint,
                               'width': image.width, 'height': image.height})
    selected, rejected = select_frames(candidates, LIMITS.max_images)
    if len(selected) < LIMITS.min_images:
        raise ContractError('too_few_usable_frames')
    records = []
    for index, item in enumerate(selected):
        name = f'frame_{index+1:05}.jpg'
        shutil.copyfile(item['path'], image_dir / name)
        records.append({'sourceFile': 'input.video', 'file': 'images/'+name,
                        'sourceFormat': 'VIDEO', 'encodedFormat': 'JPEG',
                        'width': item['width'], 'height': item['height'],
                        'sourceCandidate': item['candidate'],
                        'sampleTimestampSeconds': round((item['candidate']-1)/sampling, 6),
                        'timestampKind': 'fps-filter-timeline-estimate',
                        'quality': item['quality'], 'metadataPreserved': 'original-video-only'})
    selection = {'candidateCount': len(candidates), 'selectedCount': len(records),
                 'samplingFramesPerSecond': sampling, 'rejected': rejected,
                 'policy': 'uniform timeline bins; prefer higher Laplacian variance; reject near duplicates',
                 'thresholds': {'laplacianVariance128Min': 20, 'extremeExposureFraction': .95,
                                'dHashHammingMax': 2, 'meanLumaDifference32Max': 2},
                 'limits': VIDEO_LIMITS, 'metricAccuracyValidated': False}
    return {'imageCount': len(records), 'source': {'source': 'video', 'scaleStatus': 'unverified'},
            'video': metadata, 'selection': selection}, records


def export_selected_photos(output, image_dir, records):
    manifest = {'format': 'kantura-photo-dataset', 'version': 1, 'source': 'kantura-video-frames',
                'scaleStatus': 'unverified', 'captureMode': 'video', 'images': []}
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for record in records:
            path = image_dir / Path(record['file']).name
            manifest['images'].append({'file': record['file'], 'bytes': path.stat().st_size,
                                       'sampleTimestampSeconds': record['sampleTimestampSeconds'],
                                       'timestampKind': record['timestampKind']})
            archive.write(path, record['file'])
        archive.writestr('manifest.json', json.dumps(manifest, ensure_ascii=False, allow_nan=False))
    if Path(output).stat().st_size > LIMITS.artifact:
        raise ContractError('too_large')
