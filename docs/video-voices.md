# Tutorial voices and regeneration

The fifteen tutorial languages use synthetic speech and original animated demonstrations.
They are not recordings of real iPhone scans. Narration and complete captions
come from [scripts.json](../tools/scan-workspace/public/videos/scripts.json).
No private scans, personal voice recordings or voice-cloning samples are used.

## Voice choices

| Language | Voice |
| --- | --- |
| German | Microsoft `de-DE-KatjaNeural`, an earlier service-generated synthetic track |
| English | Piper `en_US-ljspeech-medium`, a neural model trained from scratch |
| French | eSpeak NG `fr` (`roa/fr`) |
| Spanish | eSpeak NG `es` (`roa/es`) |
| Italian | eSpeak NG `it` (`roa/it`) |
| Simplified Chinese / Mandarin | eSpeak NG `cmn` (`sit/cmn`) |
| Portuguese / Portugal | eSpeak NG `pt` (`roa/pt`) |
| Arabic | eSpeak NG `ar` (`sem/ar`), fully vocalized reading |
| Hindi | eSpeak NG `hi` (`inc/hi`) |
| Bengali | eSpeak NG `bn` (`inc/bn`) |
| Russian | eSpeak NG `ru` (`zle/ru`) |
| Japanese | eSpeak NG `ja` (`jpx/ja`), kana reading |
| Korean | eSpeak NG `ko` (`ko`) |
| Indonesian | eSpeak NG `id` (`poz/id`) |
| Turkish | eSpeak NG `tr` (`trk/tr`) |

All eSpeak tracks use formant synthesis and sound mechanical. Each uses its own
language definition; the helper verifies the actual selected voice identifier
and rejects a substitute voice. File/signal checks verify
non-silent, mono 16-bit audio and plausible durations. Native-speaker review of
pronunciation and phrasing remains useful.

## Sources and licenses

[Piper 1.8.0](https://pypi.org/project/piper-tts/1.8.0/) and
[eSpeak NG](https://github.com/espeak-ng/espeak-ng/blob/master/COPYING) use
GPL-3.0-or-later for their engines. The embedded eSpeak runtime reports
**1.52.0.1**; its [language list](https://github.com/espeak-ng/espeak-ng/blob/master/docs/languages.md)
includes the selected language definitions. These are
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

To generate only the nine additional languages, without neural model downloads:

```sh
python tools/scan-workspace/render-narration.py --languages pt ar hi bn ru ja ko id tr --output-dir ../narration-15
python tools/scan-workspace/render-videos.py --languages pt ar hi bn ru ja ko id tr --audio-dir ../narration-15
```

Japanese eSpeak supports Hiragana and Katakana rather than general Kanji text;
Arabic requires fully vocalized input. The helper therefore requires explicit
readings for these two languages, using
[`pronunciation.json`](../tools/scan-workspace/public/videos/pronunciation.json)
by default. `--readings another-file.json` selects an alternative. Its schema is
`{"version":1,"languages":{"ja":{"start":"…","capture":"…"},"ar":{"start":"…","capture":"…"}}}`;
each selected language must provide all eight scene IDs. Japanese readings use
kana and Arabic readings include vowel marks. Product names are written
phonetically in the corresponding script. These are pronunciation aids for the
same narration, not replacement translations or English fallback speech.
Keep readings synchronized when editing the original script; native-speaker
review of the complete result is still pending.

Original captions and narration remain in `scripts.json`. Each generated scene
records the original `text` and the synthesized `spokenText`, and Japanese and
Arabic manifests include the reading-file SHA-256. The helper rejects missing
readings, unconverted Japanese Kanji and Latin-letter product names in these
two reading scripts. It does not certify linguistic or pronunciation quality.

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
plus `manifest.json` with voice, source text, spoken text, hashes and actual durations.
The renderer derives scene timing from each WAV and adds reading pauses.
Regenerated neural audio may differ slightly in timing; do not truncate it to
a fixed one-minute target. Review synchronization and caption layout in the
resulting MP4s.
