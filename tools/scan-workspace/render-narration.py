"""Render public tutorial text with local, language-specific speech synthesis.

Requires: Python 3.9+ and piper-tts==1.8.0 (includes NumPy and eSpeak NG).
Example, from this directory:
  python render-narration.py --languages en fr es it zh-Hans \
    --output-dir ../../../narration --model-dir ../../../piper-voices \
    --download-models

English uses the from-scratch LJ Speech Piper voice. Other languages use eSpeak
formant voices, without neural models with unresolved training provenance.
First-time English model download is explicit; synthesis itself is offline.
Do not commit model weights or the preparation environment. See docs/video-voices.md.
"""
from __future__ import annotations

import argparse
import ctypes as C
import hashlib
import importlib.metadata
import importlib.util
import json
from pathlib import Path
import re
import urllib.request
import wave

import numpy as np

ROOT = Path(__file__).resolve().parent
REVISION = 'c10ece1aade47bb51c153c893d14e5bf8e5b7117'
VOICE = 'en_US-ljspeech-medium'
VOICE_PATH = 'en/en_US/ljspeech/medium'
ESPEAK = {
    'de': 'de', 'fr': 'fr', 'es': 'es', 'it': 'it', 'zh-Hans': 'cmn',
    'pt': 'pt', 'ar': 'ar', 'hi': 'hi', 'bn': 'bn', 'ru': 'ru',
    'ja': 'ja', 'ko': 'ko', 'id': 'id', 'tr': 'tr',
}
SCENE_IDS = ['start', 'capture', 'organize', 'inspect', 'measure', 'photos', 'share', 'transport']


def read_pronunciations(path, languages):
    """Japanese and Arabic need explicit readings; never substitute English."""
    if not path.is_file():
        if {'ja', 'ar'}.intersection(languages):
            raise ValueError('Japanese/Arabic require --readings with kana/vocalized text: ' + str(path))
        return {}, None
    data = path.read_bytes()
    document = json.loads(data.decode('utf-8'))
    if document.get('version') != 1 or not isinstance(document.get('languages'), dict):
        raise ValueError('Invalid pronunciation file schema')
    readings = document['languages']
    for language in set(languages).intersection({'ja', 'ar'}):
        scenes = readings.get(language)
        if not isinstance(scenes, dict) or set(scenes) != set(SCENE_IDS):
            raise ValueError('Missing or unexpected pronunciation scene IDs: ' + language)
        for scene_id, value in scenes.items():
            if not isinstance(value, str) or not value.strip() or len(value) > 2000:
                raise ValueError('Invalid pronunciation text: ' + language + '/' + scene_id)
            if re.search(r'[A-Za-z]', value):
                raise ValueError('Spell product names in the reading script: ' + language + '/' + scene_id)
            if language == 'ja' and (re.search(r'[\u3400-\u9fff\uf900-\ufaff]', value) or not re.search(r'[\u3040-\u30ff]', value)):
                raise ValueError('Japanese eSpeak readings must use kana, not kanji: ' + scene_id)
            if language == 'ar' and not re.search(r'[\u064b-\u0652]', value):
                raise ValueError('Arabic eSpeak readings must be vocalized: ' + scene_id)
    return readings, hashlib.sha256(data).hexdigest()


def read_url(url):
    with urllib.request.urlopen(url, timeout=120) as response:
        return response.read()


def english_model(directory, allow_download):
    directory = directory / VOICE
    directory.mkdir(parents=True, exist_ok=True)
    provenance = directory / 'provenance.json'
    if provenance.exists():
        record = json.loads(provenance.read_text(encoding='utf-8'))
        if record.get('revision') == REVISION and record.get('voice') == VOICE:
            if all((directory / f['name']).is_file() and hashlib.sha256((directory / f['name']).read_bytes()).hexdigest() == f['sha256'] for f in record['files']):
                return directory / (VOICE + '.onnx'), record
    if not allow_download:
        raise RuntimeError('English voice is not cached and verified. Run once with --download-models and an explicit --model-dir.')
    base = f'https://huggingface.co/rhasspy/piper-voices/resolve/{REVISION}/'
    manifest = json.loads(read_url(base + 'voices.json'))[VOICE]['files']
    files = []
    for name in [VOICE + '.onnx', VOICE + '.onnx.json', 'MODEL_CARD']:
        remote = VOICE_PATH + '/' + name
        data = read_url(base + remote)
        expected = manifest.get(remote, {})
        if expected.get('size_bytes') and len(data) != expected['size_bytes']:
            raise RuntimeError('Voice download length mismatch: ' + name)
        if expected.get('md5_digest') and hashlib.md5(data).hexdigest() != expected['md5_digest']:
            raise RuntimeError('Voice download checksum mismatch: ' + name)
        (directory / name).write_bytes(data)
        files.append({'name': name, 'url': base + remote, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
    record = {'voice': VOICE, 'revision': REVISION, 'datasetLicense': 'Public domain; trained from scratch', 'files': files}
    provenance.write_text(json.dumps(record, indent=2), encoding='utf-8')
    return directory / (VOICE + '.onnx'), record


def inspect_wav(path):
    with wave.open(str(path), 'rb') as audio:
        rate, channels, width, frames = audio.getframerate(), audio.getnchannels(), audio.getsampwidth(), audio.getnframes()
        if channels != 1 or width != 2 or rate <= 0:
            raise RuntimeError('Unexpected PCM format: ' + str(path))
        samples = np.frombuffer(audio.readframes(frames), dtype='<i2').astype(np.float64)
    duration = frames / rate
    rms = float(np.sqrt(np.mean(samples * samples))) if len(samples) else 0
    if not 1 < duration < 45 or rms < 30:
        raise RuntimeError('Missing/implausible speech signal: ' + str(path))
    return {'duration': duration, 'sampleRate': rate, 'channels': channels, 'rms': rms, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


class FormantVoice:
    """Use the public eSpeak C API in Piper's local extension; no audio playback."""
    def __init__(self, language, rate):
        package = Path(importlib.util.find_spec('piper').origin).parent
        extension = importlib.util.find_spec('piper.espeakbridge')
        if not extension or not extension.origin:
            raise RuntimeError('Piper eSpeak extension not found on this platform')
        self.library = lib = C.CDLL(extension.origin)
        self.callback_type = C.CFUNCTYPE(C.c_int, C.POINTER(C.c_short), C.c_int, C.c_void_p)
        lib.espeak_Initialize.argtypes = [C.c_int, C.c_int, C.c_char_p, C.c_int]
        lib.espeak_Initialize.restype = C.c_int
        lib.espeak_SetSynthCallback.argtypes = [self.callback_type]
        lib.espeak_SetSynthCallback.restype = None
        lib.espeak_SetVoiceByName.argtypes = [C.c_char_p]
        lib.espeak_SetVoiceByName.restype = C.c_int
        lib.espeak_SetParameter.argtypes = [C.c_int, C.c_int, C.c_int]
        lib.espeak_Synth.argtypes = [C.c_char_p, C.c_size_t, C.c_uint, C.c_int, C.c_uint, C.c_uint, C.POINTER(C.c_uint), C.c_void_p]
        lib.espeak_Synth.restype = C.c_int
        lib.espeak_Info.argtypes = [C.POINTER(C.c_char_p)]
        lib.espeak_Info.restype = C.c_char_p
        lib.espeak_Terminate.argtypes = []
        lib.espeak_Terminate.restype = C.c_int

        class CurrentVoice(C.Structure):
            _fields_ = [('name', C.c_char_p), ('languages', C.c_char_p), ('identifier', C.c_char_p)]

        lib.espeak_GetCurrentVoice.argtypes = []
        lib.espeak_GetCurrentVoice.restype = C.POINTER(CurrentVoice)
        self.sample_rate = lib.espeak_Initialize(2, 0, str(package).encode('utf-8'), 0x8000)
        if self.sample_rate <= 0:
            raise RuntimeError('eSpeak NG initialization failed')
        selected = ESPEAK[language]
        if lib.espeak_SetVoiceByName(selected.encode()) != 0:
            raise RuntimeError('Requested voice is unavailable; no language substitution: ' + selected)
        voice = lib.espeak_GetCurrentVoice().contents
        identifier = voice.identifier.decode()
        if identifier.replace('\\', '/').split('/')[-1] != selected:
            raise RuntimeError('Unexpected voice selected: ' + identifier)
        self.metadata = {'engine': 'eSpeak NG formant', 'engineVersion': lib.espeak_Info(None).decode(),
                         'voice': {'name': voice.name.decode(), 'identifier': identifier, 'language': selected},
                         'rate': rate, 'extensionSha256': hashlib.sha256(Path(extension.origin).read_bytes()).hexdigest()}
        lib.espeak_SetParameter(1, rate, 0)
        self.chunks = []

        @self.callback_type
        def collect(samples, count, events):
            if samples and count > 0:
                self.chunks.append(C.string_at(samples, count * 2))
            return 0

        self.callback = collect
        lib.espeak_SetSynthCallback(self.callback)

    def synthesize(self, text, path):
        self.chunks.clear()
        encoded = text.encode('utf-8')
        if self.library.espeak_Synth(encoded, len(encoded) + 1, 0, 1, 0, 1 | 0x1000, None, None) != 0:
            raise RuntimeError('eSpeak NG synthesis failed')
        with wave.open(str(path), 'wb') as audio:
            audio.setnchannels(1)
            audio.setsampwidth(2)
            audio.setframerate(self.sample_rate)
            audio.writeframes(b''.join(self.chunks))

    def close(self):
        self.library.espeak_Terminate()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--languages', nargs='+', choices=['en', *ESPEAK], default=['en', 'fr', 'es', 'it', 'zh-Hans'])
    parser.add_argument('--scripts', type=Path, default=ROOT / 'public/videos/scripts.json')
    parser.add_argument('--readings', type=Path, default=ROOT / 'public/videos/pronunciation.json',
                        help='Japanese kana and vocalized Arabic readings; captions stay unchanged')
    parser.add_argument('--output-dir', required=True, type=Path)
    parser.add_argument('--model-dir', type=Path)
    parser.add_argument('--download-models', action='store_true')
    parser.add_argument('--rate', type=int, default=170, help='eSpeak speech-rate parameter; default 170')
    args = parser.parse_args()
    if not 80 <= args.rate <= 300:
        parser.error('--rate must be between 80 and 300')
    if 'en' in args.languages and args.model_dir is None:
        parser.error('English requires --model-dir outside the distributed project')
    scripts = json.loads(args.scripts.read_text(encoding='utf-8'))
    readings, readings_hash = read_pronunciations(args.readings, args.languages)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    summary = {}
    for language in args.languages:
        scenes = scripts['languages'][language]['scenes']
        if [scene['id'] for scene in scenes] != SCENE_IDS:
            raise ValueError('Unexpected scene IDs: ' + language)
        if any(not isinstance(scene.get('narration'), str) or not scene['narration'].strip() or len(scene['narration']) > 2000 for scene in scenes):
            raise ValueError('Invalid narration text')
        target = args.output_dir / language
        target.mkdir(parents=True, exist_ok=True)
        formant = None
        if language == 'en':
            from piper import PiperVoice, SynthesisConfig
            model, provenance = english_model(args.model_dir, args.download_models)
            voice = PiperVoice.load(str(model))
            config = SynthesisConfig(length_scale=1.0)
            result = {'engine': 'piper-tts', 'engineVersion': importlib.metadata.version('piper-tts'), 'voice': VOICE, 'model': provenance}
        else:
            formant = FormantVoice(language, args.rate)
            result = dict(formant.metadata)
        result.update({'language': language, 'scenes': [], 'scriptsSha256': hashlib.sha256(args.scripts.read_bytes()).hexdigest()})
        if language in {'ja', 'ar'}:
            result['readingsSha256'] = readings_hash
        try:
            for scene in scenes:
                path = target / (scene['id'] + '.wav')
                spoken_text = readings[language][scene['id']] if language in {'ja', 'ar'} else scene['narration']
                if formant:
                    formant.synthesize(spoken_text, path)
                else:
                    with wave.open(str(path), 'wb') as audio:
                        voice.synthesize_wav(spoken_text, audio, syn_config=config)
                record = {'id': scene['id'], 'path': str(path.resolve()), 'text': scene['narration'],
                          'spokenText': spoken_text, **inspect_wav(path)}
                result['scenes'].append(record)
                print(f'{language}/{scene["id"]}.wav: {record["duration"]:.2f}s', flush=True)
        finally:
            if formant:
                formant.close()
        result['totalSeconds'] = sum(scene['duration'] for scene in result['scenes'])
        (target / 'manifest.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
        summary[language] = result['totalSeconds']
    print('Generated:', summary, flush=True)


if __name__ == '__main__':
    main()
