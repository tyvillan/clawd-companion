#!/usr/bin/env python3
"""Generates AppIcon.icns from the same mascot grid the app renders.

Kept as a script (rather than a checked-in binary nobody can regenerate) so
the icon stays derivable from MascotSprite.swift's grid -- if the sprite's
shape or body color ever changes, rerun this and the two stay in sync.

Usage:  python3 tools/make_icon.py
Writes: Resources/AppIcon.icns
"""

import os
import shutil
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFilter

# Mirrors MascotSprite.base / bodyColor / eyeColor in
# Sources/ClawdCompanion/MascotSprite.swift.
GRID = [
    "..BBBBBBBBB..",
    "..BKBBBBBKB..",
    "BBBBBBBBBBBBB",
    "..BBBBBBBBB..",
    "..BBBBBBBBB..",
    "...B.B.B.B...",
    "...B.B.B.B...",
]
BODY = (224, 107, 69, 255)   # Color(red: 0.88, green: 0.42, blue: 0.27)
EYE = (0, 0, 0, 255)

# macOS Big Sur+ icon geometry: the rounded square occupies the middle
# ~80% of the canvas, leaving the margin the system expects for its own
# shadow/spacing. Radius is the standard ~22.5% of the square's side.
CANVAS = 1024
MARGIN = 100
SQUARE = CANVAS - MARGIN * 2
RADIUS = 185

# Cream backdrop so the orange mascot reads strongly at small sizes -- a
# dark backdrop muddied the body color once scaled down to 16pt.
BG_TOP = (250, 247, 242, 255)
BG_BOTTOM = (234, 226, 214, 255)

ICNS_SIZES = [16, 32, 64, 128, 256, 512, 1024]
# (filename, pixel size) pairs iconutil expects in an .iconset.
ICONSET = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def vertical_gradient(size, top, bottom):
    grad = Image.new("RGBA", (1, size))
    for y in range(size):
        t = y / max(1, size - 1)
        grad.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(4)))
    return grad.resize((size, size), Image.BILINEAR)


def render_master():
    icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    plate = vertical_gradient(SQUARE, BG_TOP, BG_BOTTOM)
    plate.putalpha(rounded_mask(SQUARE, RADIUS))
    icon.alpha_composite(plate, (MARGIN, MARGIN))

    cols, rows = len(GRID[0]), len(GRID)
    # Mascot spans ~62% of the plate's width; the grid is much wider than it
    # is tall, so width (not height) is the constraining dimension.
    pixel = int(SQUARE * 0.62) // cols
    art_w, art_h = cols * pixel, rows * pixel
    origin_x = (CANVAS - art_w) // 2
    # Nudged up from true center: the sprite is bottom-heavy (legs), so
    # optical center sits slightly above geometric center.
    origin_y = (CANVAS - art_h) // 2 - int(SQUARE * 0.02)

    # Soft contact shadow under the feet, drawn before the sprite itself.
    # Heavily blurred and sat below the leg tips -- an unblurred ellipse read
    # as a hard grey disc slicing across the legs rather than as a shadow.
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse(
        [
            origin_x + pixel * 2,
            origin_y + art_h + pixel * 0.1,
            origin_x + art_w - pixel * 2,
            origin_y + art_h + pixel * 1.3,
        ],
        fill=(120, 70, 45, 70),
    )
    icon.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(pixel * 0.55)))

    sprite = Image.new("RGBA", (cols, rows), (0, 0, 0, 0))
    for y, row in enumerate(GRID):
        for x, ch in enumerate(row):
            if ch == "B":
                sprite.putpixel((x, y), BODY)
            elif ch == "K":
                sprite.putpixel((x, y), EYE)
    # NEAREST keeps the blocky pixel-art edges crisp instead of blurring
    # them into a smudge -- the whole point of the sprite's look.
    icon.alpha_composite(sprite.resize((art_w, art_h), Image.NEAREST), (origin_x, origin_y))
    return icon


def main():
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(repo, "Resources")
    os.makedirs(out_dir, exist_ok=True)
    master = render_master()

    workdir = tempfile.mkdtemp()
    try:
        iconset = os.path.join(workdir, "AppIcon.iconset")
        os.makedirs(iconset)
        # Render each size from the 1024 master with LANCZOS (smooth
        # downscale of an already-crisp source) rather than re-rasterizing
        # the grid per size, which produced uneven pixel widths at 16/32.
        for name, size in ICONSET:
            master.resize((size, size), Image.LANCZOS).save(os.path.join(iconset, name))
        icns = os.path.join(out_dir, "AppIcon.icns")
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", icns], check=True)
        print("wrote", icns)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    main()
