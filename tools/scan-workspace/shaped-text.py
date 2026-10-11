"""Single-line HarfBuzz/FreeType text for Pillow builds without libraqm.

Use ``ShapedFont(path, size)`` and ``Draw(image)`` in the tutorial renderer.
Normal Pillow fonts and non-text drawing calls pass through unchanged. Complex
text is split into logical script/direction runs before shaping; the Unicode
bidi algorithm orders runs, never the Arabic letters or Indic combining marks
that HarfBuzz must receive in logical order. The default anchor is Pillow's
``la`` (left, ascender), not the top of the visible glyphs.

Dependencies: Pillow, uharfbuzz, freetype-py, python-bidi. Fonts must cover their
input: a missing shaped glyph raises an error rather than producing tofu.
``fallback_paths`` can supply symbol fonts. A sibling segoeui.ttf is used by
default on Windows (Nirmala lacks the delta and arrow in the tutorial).
The Python bidi implementation does not support Unicode isolate controls;
those are rejected explicitly. Tutorial strings do not use these controls.

API references:
https://harfbuzz.github.io/text-runs.html
https://uharfbuzz.readthedocs.io/reference.html
https://python-bidi.readthedocs.io/en/stable/bidi.html
https://freetype-py.readthedocs.io/en/stable/glyph_slot.html
"""

from dataclasses import dataclass
from functools import lru_cache
import math
from pathlib import Path
import unicodedata

import freetype
import uharfbuzz as hb
from bidi import algorithm as bidi
from PIL import Image, ImageChops, ImageDraw


@dataclass(frozen=True)
class _Run:
    text: str
    direction: str
    script: str
    visual_index: int


def _script(character):
    """Distinguish the tutorial scripts; marks/common characters inherit a run."""
    if unicodedata.category(character)[0] != 'L':
        return None
    name = unicodedata.name(character, '')
    for prefix, tag in [('DEVANAGARI', 'Deva'), ('BENGALI', 'Beng'),
                        ('ARABIC', 'Arab'), ('LATIN', 'Latn'),
                        ('GREEK', 'Grek'), ('CYRILLIC', 'Cyrl'),
                        ('HEBREW', 'Hebr')]:
        if name.startswith(prefix):
            return tag
    # HarfBuzz still guesses properties for other scripts. Their Unicode name
    # prefix separates them from Latin and the explicitly supported scripts.
    return name.split(' ')[0] or 'Zyyy'


def _visual_runs(text, direction=None):
    if direction not in (None, 'ltr', 'rtl'):
        raise ValueError('Only horizontal ltr/rtl text is supported')
    if any(c in text for c in '\u2066\u2067\u2068\u2069'):
        raise ValueError('Unicode bidi isolate controls are not supported by python-bidi.algorithm')
    if not text:
        return ()
    storage = bidi.get_empty_storage()
    base = bidi.get_base_level(text) if direction is None else int(direction == 'rtl')
    storage['base_level'] = base
    storage['base_dir'] = ('L', 'R')[base]
    bidi.get_embedding_levels(text, storage)
    for index, char in enumerate(storage['chars']):
        char['source_index'] = index
    bidi.explicit_embed_and_overrides(storage)
    bidi.resolve_weak_types(storage)
    bidi.resolve_neutral_types(storage, False)
    bidi.resolve_implicit_levels(storage, False)
    bidi.reorder_resolved_levels(storage, False)
    # Do not apply character mirroring here: HarfBuzz handles mirrored glyphs
    # from each run's direction. Applying it twice would undo parentheses.
    levels = {char['source_index']: char['level'] for char in storage['chars']}
    visual = {char['source_index']: i for i, char in enumerate(storage['chars'])}
    chars = []
    previous_level = base
    for index, char in enumerate(text):
        if index in levels:
            previous_level = levels[index]
        elif char not in '\u200c\u200d':
            continue
        # Bidi removes boundary-neutral controls. Keep ZWNJ/ZWJ in the logical
        # shaping input, where they can change Indic conjuncts/Arabic joining.
        chars.append([index, char, previous_level, _script(char)])
    previous_script = None
    for char in chars:
        if char[3] is None:
            char[3] = previous_script
        else:
            previous_script = char[3]
    following_script = 'Zyyy'
    for char in reversed(chars):
        if char[3] is None:
            char[3] = following_script
        else:
            following_script = char[3]
    logical_runs = []
    for char in chars:
        if not logical_runs or char[2:] != logical_runs[-1][-1][2:]:
            logical_runs.append([])
        logical_runs[-1].append(char)
    runs = []
    for run in logical_runs:
        indices = [visual[c[0]] for c in run if c[0] in visual]
        if indices:
            runs.append(_Run(''.join(c[1] for c in run),
                             'rtl' if run[0][2] % 2 else 'ltr',
                             run[0][3], min(indices)))
    return tuple(sorted(runs, key=lambda run: run.visual_index))


def _features(features):
    if not features:
        return ()
    if isinstance(features, dict):
        return tuple(sorted(features.items()))
    result = {}
    for feature in features:
        if '=' in feature:
            key, value = feature.split('=', 1)
            result[key] = int(value)
        else:
            result[feature.lstrip('+-')] = 0 if feature.startswith('-') else 1
    return tuple(sorted(result.items()))


class ShapedFont:
    def __init__(self, path, size, index=0, fallback_paths=None):
        if not math.isfinite(size) or size <= 0:
            raise ValueError('Font size must be positive and finite')
        self.path, self.size, self.index = str(path), float(size), index
        self._bytes = Path(path).read_bytes()
        self._hb_face = hb.Face(self._bytes, index)
        self._hb_font = hb.Font(self._hb_face)
        hb.ot_font_set_funcs(self._hb_font)
        scaled = round(self.size * 64)
        self._hb_font.scale = (scaled, scaled)
        self._ft = freetype.Face(self.path, index=index)
        self._ft.set_char_size(scaled)
        self.ascent = math.ceil(self._ft.size.ascender / 64)
        self.descent = math.ceil(-self._ft.size.descender / 64)
        if fallback_paths is None:
            sibling = Path(path).with_name('segoeui.ttf')
            fallback_paths = [sibling] if sibling.is_file() and sibling.resolve() != Path(path).resolve() else []
        self._fonts = (self,) + tuple(ShapedFont(p, size, fallback_paths=()) for p in fallback_paths)
        # Per-font caches are bounded; frame-by-frame labels reuse both the
        # rendered glyph bitmaps and the complete positioned line mask.
        self._glyph = lru_cache(maxsize=2048)(self._render_glyph)
        self._layout = lru_cache(maxsize=1024)(self._shape_line)
        self._mask = lru_cache(maxsize=256)(self._line_mask)

    def getmetrics(self):
        return self.ascent, self.descent

    def with_size(self, size):
        """Create a resized font while retaining the collection index/fallbacks."""
        if size == self.size:
            return self
        return ShapedFont(self.path, size, index=self.index,
                          fallback_paths=[font.path for font in self._fonts[1:]])

    resize = with_size

    def _covers(self, character):
        return (unicodedata.category(character) == 'Cf' or
                character in '\ufe0e\ufe0f' or
                bool(self._hb_font.get_nominal_glyph(ord(character))))

    def _font_runs(self, run):
        # Prefer one font for the entire run, so shaping connections survive.
        for index, font in enumerate(self._fonts):
            if all(font._covers(c) for c in run.text):
                return [(index, run.text)]
        parts = []
        for char in run.text:
            index = next((i for i, f in enumerate(self._fonts) if f._covers(char)), None)
            if index is None:
                raise ValueError('No font covers ' + repr(char) + ' in ' + self.path)
            # Do not silently split an Indic/Arabic letter or combining mark
            # away from its neighbours. Missing symbols may switch fonts.
            if index and unicodedata.category(char)[0] in 'LM' and run.script in ('Deva', 'Beng', 'Arab', 'Hebr'):
                raise ValueError('Choose a font covering the entire complex-script run: ' + repr(run.text))
            if parts and parts[-1][0] == index:
                parts[-1] = (index, parts[-1][1] + char)
            else:
                parts.append((index, char))
        return list(reversed(parts)) if run.direction == 'rtl' else parts

    def _shape_line(self, text, direction, features, language):
        if '\n' in text or '\r' in text:
            raise ValueError('Shape one line at a time')
        glyphs, pen = [], 0.0
        for run in _visual_runs(text, direction):
            for font_index, part in self._font_runs(run):
                font = self._fonts[font_index]
                buffer = hb.Buffer()
                buffer.add_str(part)
                buffer.guess_segment_properties()
                buffer.direction = run.direction
                if len(run.script) == 4:
                    buffer.script = run.script
                buffer.language = language or {'Deva': 'hi', 'Beng': 'bn', 'Arab': 'ar'}.get(run.script, 'und')
                hb.shape(font._hb_font, buffer, dict(features))
                for info, position in zip(buffer.glyph_infos, buffer.glyph_positions):
                    if info.codepoint == 0:
                        raise ValueError('Font lacks a shaped glyph: ' + font.path + ' for ' + repr(part))
                    glyphs.append((font_index, info.codepoint, pen + position.x_offset / 64,
                                   -position.y_offset / 64))
                    pen += position.x_advance / 64
        return tuple(glyphs), pen

    def glyph_ids(self, text, direction=None, features=None, language=None):
        """Expose shaped glyph IDs for coverage checks without rasterizing."""
        return tuple(item[1] for item in self._layout(text, direction, _features(features), language)[0])

    def getlength(self, text, direction=None, features=None, language=None):
        return self._layout(text, direction, _features(features), language)[1]

    def _render_glyph(self, glyph_id):
        self._ft.load_glyph(glyph_id, freetype.FT_LOAD_DEFAULT | freetype.FT_LOAD_NO_BITMAP)
        slot = self._ft.glyph
        slot.render(freetype.FT_RENDER_MODE_NORMAL)
        bitmap = slot.bitmap
        if not bitmap.width or not bitmap.rows:
            return None, slot.bitmap_left, slot.bitmap_top
        if bitmap.pixel_mode != freetype.FT_PIXEL_MODE_GRAY:
            raise ValueError('Only grayscale outline font rendering is supported')
        stride = abs(bitmap.pitch)
        # FreeType's slot is overwritten on the next load: make an owned copy.
        pixels = bytes(bitmap.buffer)
        rows = [pixels[i * stride:i * stride + bitmap.width] for i in range(bitmap.rows)]
        if bitmap.pitch < 0:
            rows.reverse()
        mask = Image.frombytes('L', (bitmap.width, bitmap.rows), b''.join(rows))
        return mask, slot.bitmap_left, slot.bitmap_top

    def _line_mask(self, text, direction, features, language):
        glyphs, advance = self._layout(text, direction, features, language)
        tiles = []
        for font_index, glyph_id, x, y in glyphs:
            mask, left, top = self._fonts[font_index]._glyph(glyph_id)
            if mask is not None:
                tiles.append((mask, round(x + left), round(self.ascent + y - top)))
        if not tiles:
            return None, (0, 0, 0, 0), advance
        left = min(x for mask, x, y in tiles)
        top = min(y for mask, x, y in tiles)
        right = max(x + mask.width for mask, x, y in tiles)
        bottom = max(y + mask.height for mask, x, y in tiles)
        result = Image.new('L', (right - left, bottom - top))
        for mask, x, y in tiles:
            box = (x - left, y - top, x - left + mask.width, y - top + mask.height)
            result.paste(ImageChops.lighter(result.crop(box), mask), box)
        return result, (left, top, right, bottom), advance

    def getbbox(self, text, direction=None, features=None, language=None, anchor=None):
        _, bbox, advance = self._mask(text, direction, _features(features), language)
        dx, dy = self._anchor(anchor, bbox, advance)
        return tuple(value + (dx if i % 2 == 0 else dy) for i, value in enumerate(bbox))

    def _anchor(self, anchor, bbox, advance):
        anchor = anchor or 'la'
        if len(anchor) != 2 or anchor[0] not in 'lmr' or anchor[1] not in 'atmsbd':
            raise ValueError('Unsupported horizontal text anchor: ' + anchor)
        dx = {'l': 0, 'm': -advance / 2, 'r': -advance}[anchor[0]]
        dy = {'a': 0, 't': -bbox[1], 'm': -(self.ascent + self.descent) / 2,
              's': -self.ascent, 'b': -bbox[3], 'd': -(self.ascent + self.descent)}[anchor[1]]
        return dx, dy


class Draw:
    """ImageDraw proxy; does not monkey-patch Pillow's global Draw factory."""
    def __init__(self, image, mode=None):
        self._image = image
        self._draw = ImageDraw.Draw(image, mode)

    def __getattr__(self, name):
        return getattr(self._draw, name)

    def textlength(self, text, font=None, direction=None, features=None, language=None, **kwargs):
        if not isinstance(font, ShapedFont):
            return self._draw.textlength(text, font=font, direction=direction,
                                         features=features, language=language, **kwargs)
        return font.getlength(text, direction, features, language)

    def textbbox(self, xy, text, font=None, anchor=None, direction=None,
                 features=None, language=None, **kwargs):
        if not isinstance(font, ShapedFont):
            return self._draw.textbbox(xy, text, font=font, anchor=anchor, direction=direction,
                                       features=features, language=language, **kwargs)
        self._check_options(kwargs)
        bbox = font.getbbox(text, direction, features, language, anchor)
        return tuple(value + xy[i % 2] for i, value in enumerate(bbox))

    @staticmethod
    def _check_options(options):
        unsupported = {key: value for key, value in options.items()
                       if value and key not in ('align', 'spacing')}
        if unsupported:
            raise ValueError('Unsupported shaped-text options: ' + ', '.join(unsupported))

    def text(self, xy, text, fill=None, font=None, anchor=None, direction=None,
             features=None, language=None, **kwargs):
        if not isinstance(font, ShapedFont):
            return self._draw.text(xy, text, fill=fill, font=font, anchor=anchor,
                                   direction=direction, features=features, language=language, **kwargs)
        self._check_options(kwargs)
        if '\n' in text:
            raise ValueError('Draw wrapped tutorial lines separately; shaped text is single-line')
        mask, bbox, advance = font._mask(text, direction, _features(features), language)
        if mask is None:
            return
        dx, dy = font._anchor(anchor, bbox, advance)
        origin = (round(xy[0] + dx + bbox[0]), round(xy[1] + dy + bbox[1]))
        self._image.paste(fill if fill is not None else 'white', origin +
                          (origin[0] + mask.width, origin[1] + mask.height), mask)
