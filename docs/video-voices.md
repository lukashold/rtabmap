# Tutorial voices and regeneration

The six tutorials use synthetic speech and original animated demonstrations.
They are not recordings of real iPhone scans. Narration and complete captions
come from [scripts.json](../tools/scan-workspace/public/videos/scripts.json).
No private scans, personal voice recordings or voice-cloning samples are used.

## Published voice choices

| Language | Voice | Final video duration |
| --- | --- | ---: |
| German | Microsoft `de-DE-KatjaNeural`, an earlier service-generated synthetic track | 86.8 s |
| English | Piper `en_US-ljspeech-medium`, neural synthesis from a model trained from scratch | 66.9 s |
| French | eSpeak NG `fr` (`roa/fr`), formant synthesis | 62.2 s |
| Spanish | eSpeak NG `es` (`roa/es`), formant synthesis | 72.2 s |
| Italian | eSpeak NG `it` (`roa/it`), formant synthesis | 71.5 s |
| Simplified Chinese / Mandarin | eSpeak NG `cmn` (`sit/cmn`), formant synthesis | 69.0 s |

The formant voices sound mechanical. Each uses its own language definition;
Chinese is not spoken by an English fallback voice. File/signal checks verify
non-silent, mono 16-bit audio and plausible durations. Native-speaker review of
pronunciation and phrasing remains useful.

## Sources and licenses

[Piper 1.8.0](https://pypi.org/project/piper-tts/1.8.0/) and
[eSpeak NG](https://github.com/espeak-ng/espeak-ng/blob/master/COPYING) use
GPL-3.0-or-later for their engines. The embedded eSpeak runtime reports
**1.52.0.1**; its [language list](https://github.com/espeak-ng/espeak-ng/blob/master/docs/languages.md)
includes the selected French, Spanish, Italian and Mandarin voices. These are
build-time tools, not engines bundled in the browser, Docker image or native app.

The English [Piper model card](https://huggingface.co/rhasspy/piper-voices/blob/c10ece1aade47bb51c153c893d14e5bf8e5b7117/en/en_US/ljspeech/medium/MODEL_CARD)
identifies a from-scratch model using the public-domain
[LJ Speech dataset](https://keithito.com/LJ-Speech-Dataset/) by Keith Ito, based on
LibriVox recordings. Model downloads are pinned to repository revision
`c10ece1aade47bb51c153c893d14e5bf8e5b7117`, verified against its available checksums,
and recorded with SHA-256 provenance. Model weights are not redistributed.

German was generated using [edge-tts](https://github.com/rany2/edge-tts), which
contacts Microsoft's Edge TTS service. This track is separate from the offline
generator; the tool's license does not grant rights to Microsoft's service.
Keep this provenance notice with tutorial distributions. Do not describe the
synthesis engines, voice resources or service as covered by KANTURA's BSD license.

## Generate the offline tracks

Use an isolated Python 3.9+ environment. From the repository root:

```sh
python -m pip install -r tools/scan-workspace/requirements-video.txt
python tools/scan-workspace/render-narration.py --languages en fr es it zh-Hans --output-dir ../narration --model-dir ../piper-voices --download-models
python tools/scan-workspace/render-videos.py --languages en fr es it zh-Hans --audio-dir ../narration
```

The [narration helper](../tools/scan-workspace/render-narration.py) uses the
[official Piper API](https://github.com/OHF-Voice/piper1-gpl/blob/main/docs/API_PYTHON.md)
for English and the bundled eSpeak C API for other languages. It has no
machine-specific paths. Windows was tested; other platforms need a runtime
check. Keep environments and weights outside the repository.

First-time English model downloads require Internet. Omit `--download-models`
on subsequent runs to reuse the verified cached model; speech synthesis itself
does not call a TTS service. To create a fully local German alternative, with a
different, mechanical voice:

```sh
python tools/scan-workspace/render-narration.py --languages de --output-dir ../narration
python tools/scan-workspace/render-videos.py --languages de --audio-dir ../narration
```

Each language directory contains `start.wav`, `capture.wav`, `organize.wav`,
`inspect.wav`, `measure.wav`, `photos.wav`, `share.wav` and `transport.wav`,
plus `manifest.json` with voice, source text, hashes and actual durations.
The renderer derives scene timing from each WAV and adds reading pauses.
Regenerated neural audio may differ slightly in timing; do not truncate it to
a fixed one-minute target. Review synchronization and caption layout in the
resulting MP4s.
