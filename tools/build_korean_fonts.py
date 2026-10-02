#!/usr/bin/env python3
"""Rebuild assets/ko_ui.ttf and assets/ko_title.ttf from official Noto Sans KR.

The game draws Latin text with DejaVu and attaches these Hangul subsets as
runtime fallbacks (see i18n.gd). Each subset keeps the 2,350 KS X 1001 Hangul
syllables, compatibility jamo and a few CJK punctuation marks, which covers
ordinary Korean text. If a translation needs a rarer syllable, tests/test_i18n.gd
fails on the missing glyph; add it to EXTRA and rerun this script.

Requires: pip install fonttools
Usage:    python3 tools/build_korean_fonts.py path/to/NotoSansKR[wght].ttf
Source:   https://github.com/google/fonts/tree/main/ofl/notosanskr (OFL 1.1)
"""
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ASSETS = Path(__file__).resolve().parent.parent / "assets"
# Variable-font weights matching the DejaVu Sans / DejaVu Sans Bold primaries.
OUTPUTS = {"ko_ui.ttf": 400, "ko_title.ttf": 700}
EXTRA = ""


def codepoints() -> list[int]:
    syllables = [c for c in range(0xAC00, 0xD7A4) if len(chr(c).encode("euc-kr", errors="ignore")) == 2]
    jamo = list(range(0x3131, 0x318F))
    punctuation = [0x3000, 0x3001, 0x3002, 0x300C, 0x300D, 0x300E, 0x300F, 0x00B7, 0x2026, 0x2022, 0x00D7]
    return sorted(set(syllables + jamo + punctuation + [ord(c) for c in EXTRA]))


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    source = Path(sys.argv[1])
    for name, weight in OUTPUTS.items():
        font = instancer.instantiateVariableFont(TTFont(source), {"wght": weight})
        options = subset.Options()
        options.layout_features = ["*"]
        options.name_IDs = ["*"]
        options.notdef_outline = True
        options.hinting = False
        subsetter = subset.Subsetter(options)
        subsetter.populate(unicodes=codepoints())
        subsetter.subset(font)
        # Reproducible output: keep the source timestamp instead of "now".
        font.recalcTimestamp = False
        font["head"].modified = font["head"].created
        font.save(ASSETS / name)
        print(f"{name}: weight {weight}, {(ASSETS / name).stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
